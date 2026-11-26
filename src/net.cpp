/* net.cpp — sockets, name resolution, poll and kqueue for the guest, on both hosts (Winsock on Windows, the kernel's
 * sockets on Linux). The guest passes Darwin's values (domains, options, flags, sockaddrs with their length byte) and
 * gets Darwin's errnos back; this file translates.
 *
 * kqueue: EVFILT_USER (Go's netpoll wakeup) and EVFILT_READ / EVFILT_WRITE on sockets (on Linux, on anything epoll
 * takes). Linux maps it onto epoll (EV_CLEAR is EPOLLET). Windows has no readiness notification to wait on together
 * with an event, so a kqueue there is a list of registrations polled with WSAPoll, plus a pair of loopback UDP sockets
 * that wake the waiter; EV_CLEAR (edge-triggered) is emulated: a reported registration stays quiet until the guest gets
 * EAGAIN on that socket again, which is what code using edge triggering waits for. */
#include "scion.h"
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET Sock;
#define BAD_SOCK INVALID_SOCKET
#define sock_errno() WSAGetLastError()
#else
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/ioctl.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netdb.h>
#include <poll.h>
#include <fcntl.h>
#include <errno.h>
typedef int Sock;
#define BAD_SOCK (-1)
#define sock_errno() errno
#endif
#include <mutex>
#include <memory>
#include <map>
#include <unordered_map>
#include <algorithm>
#include <chrono>
#include <thread>

static inline A G(A x) { return g_guest_arm ? (A)arm64_translate((uint64_t)x) : x; }
template<typename T> static T *GP(A x) { return x ? (T *)G(x) : nullptr; }

/* ======================================================================= Darwin <-> host values */
/* a socket error as a Darwin errno: Winsock's WSAE* codes are 10000 + the BSD errno, which Darwin kept */
static int derrno(int e) {
#ifdef _WIN32
    if (e == WSAEMSGSIZE) return 40;
    if (e == WSA_NOT_ENOUGH_MEMORY) return D_ENOMEM;
    if (e == WSA_INVALID_HANDLE || e == WSAENOTSOCK) return D_ENOTSOCK;
    return e > 10000 && e < 10072 ? e - 10000 : D_EIO;
#else
    if (e == EAGAIN) return D_EAGAIN;
    if (e == EINPROGRESS) return D_EINPROGRESS;
    if (e == EALREADY) return D_EALREADY;
    if (e >= 88 && e <= 111) return e - 50;          /* ENOTSOCK .. ECONNREFUSED */
    if (e == 112 || e == 113) return e - 48;         /* EHOSTDOWN, EHOSTUNREACH */
    if (e == ENAMETOOLONG) return D_ENAMETOOLONG;
    if (e == ENOSYS) return D_ENOSYS;
    return e > 0 && e <= 34 ? e : D_EIO;
#endif
}
static A neg() { return -derrno(sock_errno()); }

static int dom_in(int d) { return d == 0 ? AF_UNSPEC : d == 1 ? AF_UNIX : d == 2 ? AF_INET : d == 30 ? AF_INET6 : -1; }
static int dom_out(int f) { return f == AF_INET ? 2 : f == AF_INET6 ? 30 : f == AF_UNIX ? 1 : 0; }

/* a Darwin sockaddr -> the host's */
static A sa_in(const uint8_t *d, uint32_t len, sockaddr_storage &h, socklen_t &hl) {
    memset(&h, 0, sizeof h);
    if (!d || len < 2) return -D_EINVAL;
    switch (d[1]) {
    case 2: {
        if (len < 8) return -D_EINVAL;
        sockaddr_in *s = (sockaddr_in *)&h; s->sin_family = AF_INET;
        memcpy(&s->sin_port, d + 2, 2); memcpy(&s->sin_addr, d + 4, 4); hl = sizeof *s;
        return 0;
    }
    case 30: {
        if (len < 24) return -D_EINVAL;
        sockaddr_in6 *s = (sockaddr_in6 *)&h; s->sin6_family = AF_INET6;
        memcpy(&s->sin6_port, d + 2, 2); memcpy(&s->sin6_flowinfo, d + 4, 4); memcpy(&s->sin6_addr, d + 8, 16);
        if (len >= 28) memcpy(&s->sin6_scope_id, d + 24, 4);
        hl = sizeof *s;
        return 0;
    }
#ifndef _WIN32
    case 1: {
        sockaddr_un *s = (sockaddr_un *)&h; s->sun_family = AF_UNIX;
        size_t n = strnlen((const char *)d + 2, len - 2);
        if (n >= sizeof s->sun_path) return -D_ENAMETOOLONG;
        memcpy(s->sun_path, d + 2, n); hl = (socklen_t)(offsetof(sockaddr_un, sun_path) + n + 1);
        return 0;
    }
#endif
    }
    return -47;   /* EAFNOSUPPORT (ponytail: AF_UNIX on Windows) */
}
/* the host's sockaddr -> Darwin's, at most *len bytes of it; *len becomes its full length */
static void sa_out(const sockaddr *h, socklen_t hl, uint8_t *d, uint32_t *len) {
    uint8_t t[128] = {0}; uint32_t n = 0;
    if (h->sa_family == AF_INET) {
        const sockaddr_in *s = (const sockaddr_in *)h; n = 16; t[0] = 16; t[1] = 2;
        memcpy(t + 2, &s->sin_port, 2); memcpy(t + 4, &s->sin_addr, 4);
    } else if (h->sa_family == AF_INET6) {
        const sockaddr_in6 *s = (const sockaddr_in6 *)h; n = 28; t[0] = 28; t[1] = 30;
        memcpy(t + 2, &s->sin6_port, 2); memcpy(t + 4, &s->sin6_flowinfo, 4); memcpy(t + 8, &s->sin6_addr, 16);
        memcpy(t + 24, &s->sin6_scope_id, 4);
#ifndef _WIN32
    } else if (h->sa_family == AF_UNIX) {
        const sockaddr_un *s = (const sockaddr_un *)h;
        size_t p = hl > offsetof(sockaddr_un, sun_path) ? strnlen(s->sun_path, hl - offsetof(sockaddr_un, sun_path)) : 0;
        n = (uint32_t)std::min<size_t>(2 + p + 1, 106); t[0] = (uint8_t)n; t[1] = 1; memcpy(t + 2, s->sun_path, std::min<size_t>(p, 103));
#endif
    } else { n = 2; t[1] = 0; }
    if (d && len) memcpy(d, t, std::min(*len, n));
    if (len) *len = n;
}

static int msg_flags(int f) {
    int h = 0;
    if (f & 1) h |= MSG_OOB;
    if (f & 2) h |= MSG_PEEK;
    if (f & 4) h |= MSG_DONTROUTE;
    if (f & 0x40) h |= MSG_WAITALL;
#ifndef _WIN32
    if (f & 0x80) h |= MSG_DONTWAIT;
    h |= MSG_NOSIGNAL;   /* the guest gets EPIPE, never the host's SIGPIPE */
#endif
    return h;
}

/* ======================================================================= the host's sockets (Windows: descriptors) */
#ifdef _WIN32
/* host.cpp's descriptor table */
uintptr_t host_fd_socket(int fd);                                  /* INVALID_SOCKET if fd is not a socket */
int host_fd_add_socket(uintptr_t s, std::shared_ptr<void> owner);   /* a descriptor for s; owner closes it with the last */
int host_fd_add_kqueue();
/* Windows cannot ask a socket whether it is non-blocking or what it is doing: kept here, per socket */
struct SockInfo { bool stream = true, nonblock = false; int state = 0; };   /* state: 0 new, 1 connecting, 2 connected, 3 listening, 4 failed */
static std::mutex g_sockmu;
static std::unordered_map<Sock, SockInfo> g_socks;
static void net_init() { static std::once_flag once; std::call_once(once, [] { WSADATA w; WSAStartup(MAKEWORD(2, 2), &w); }); }
static SockInfo info_of(Sock s) { std::lock_guard<std::mutex> l(g_sockmu); auto it = g_socks.find(s); return it == g_socks.end() ? SockInfo{} : it->second; }
static void set_state(Sock s, int st) { std::lock_guard<std::mutex> l(g_sockmu); auto it = g_socks.find(s); if (it != g_socks.end()) it->second.state = st; }
static void rearm(int fd, int filter);
static A new_fd(Sock s, bool stream, int state, bool nonblock = false) {
    { std::lock_guard<std::mutex> l(g_sockmu); g_socks[s] = SockInfo{stream, nonblock, state}; }
    auto owner = std::shared_ptr<void>(new Sock(s), [](void *p) {
        Sock s = *(Sock *)p; delete (Sock *)p;
        { std::lock_guard<std::mutex> l(g_sockmu); g_socks.erase(s); }
        closesocket(s);
    });
    return host_fd_add_socket(s, std::move(owner));
}
static Sock sock_of(A fd) { return (Sock)host_fd_socket((int)fd); }
static void set_nonblock(Sock s, bool on) {
    u_long v = on; ioctlsocket(s, FIONBIO, &v);
    std::lock_guard<std::mutex> l(g_sockmu); auto it = g_socks.find(s); if (it != g_socks.end()) it->second.nonblock = on;
}
/* an operation that would block: EAGAIN for the guest, and edge-triggered kqueue registrations on fd come back */
static A would_block(A fd, int filter) { rearm((int)fd, filter); return -D_EAGAIN; }
#else
static void net_init() {}
static A new_fd(Sock s, bool, int, bool = false) { return s; }
static Sock sock_of(A fd) { return (Sock)fd; }
#endif

/* ======================================================================= socket options */
enum { OPT_INT, OPT_TIMEVAL, OPT_LINGER, OPT_IGNORE, OPT_ERROR, OPT_NREAD, OPT_NONE };
struct Opt { int level, name, kind; };
static Opt opt_in(int level, int name) {
    switch (level) {
    case 0xffff:   /* SOL_SOCKET */
        switch (name) {
        case 2: return {SOL_SOCKET, SO_ACCEPTCONN, OPT_INT};
        case 4: return {SOL_SOCKET, SO_REUSEADDR, OPT_INT};
        case 8: return {SOL_SOCKET, SO_KEEPALIVE, OPT_INT};
        case 0x10: return {SOL_SOCKET, SO_DONTROUTE, OPT_INT};
        case 0x20: return {SOL_SOCKET, SO_BROADCAST, OPT_INT};
        case 0x80: case 0x1080: return {SOL_SOCKET, SO_LINGER, OPT_LINGER};
        case 0x100: return {SOL_SOCKET, SO_OOBINLINE, OPT_INT};
#ifdef _WIN32
        case 0x200: return {0, 0, OPT_IGNORE};   /* SO_REUSEPORT: SO_REUSEADDR already lets ports be shared */
        case 0x1003: case 0x1004: return {0, 0, OPT_IGNORE};   /* low-water marks */
#else
        case 0x200: return {SOL_SOCKET, SO_REUSEPORT, OPT_INT};
        case 0x1003: return {SOL_SOCKET, SO_SNDLOWAT, OPT_INT};
        case 0x1004: return {SOL_SOCKET, SO_RCVLOWAT, OPT_INT};
#endif
        case 0x1001: return {SOL_SOCKET, SO_SNDBUF, OPT_INT};
        case 0x1002: return {SOL_SOCKET, SO_RCVBUF, OPT_INT};
        case 0x1005: return {SOL_SOCKET, SO_SNDTIMEO, OPT_TIMEVAL};
        case 0x1006: return {SOL_SOCKET, SO_RCVTIMEO, OPT_TIMEVAL};
        case 0x1007: return {SOL_SOCKET, SO_ERROR, OPT_ERROR};
        case 0x1008: return {SOL_SOCKET, SO_TYPE, OPT_INT};
        case 0x1020: return {0, 0, OPT_NREAD};   /* SO_NREAD */
        case 0x1022: case 0x1023: case 0x1024: case 0x1025: case 0x1021: return {0, 0, OPT_IGNORE};   /* NOSIGPIPE, ... */
        }
        break;
    case 6:   /* IPPROTO_TCP */
        switch (name) {
        case 1: return {IPPROTO_TCP, TCP_NODELAY, OPT_INT};
#ifndef _WIN32
        case 2: return {IPPROTO_TCP, TCP_MAXSEG, OPT_INT};
        case 0x10: return {IPPROTO_TCP, TCP_KEEPIDLE, OPT_INT};
#else
        case 0x10: return {IPPROTO_TCP, 3 /* TCP_KEEPALIVE (idle seconds) */, OPT_INT};
#endif
#ifdef _WIN32
        case 0x101: return {IPPROTO_TCP, 17 /* TCP_KEEPINTVL */, OPT_INT};
        case 0x102: return {IPPROTO_TCP, 16 /* TCP_KEEPCNT */, OPT_INT};
#else
        case 0x101: return {IPPROTO_TCP, TCP_KEEPINTVL, OPT_INT};
        case 0x102: return {IPPROTO_TCP, TCP_KEEPCNT, OPT_INT};
#endif
        case 4: case 8: case 0x20: case 0x80: case 0x105: case 0x106: return {0, 0, OPT_IGNORE};   /* NOPUSH, NOOPT, timeouts, fast open */
        }
        break;
    case 0:   /* IPPROTO_IP */
        switch (name) {
        case 3: return {IPPROTO_IP, IP_TOS, OPT_INT};
        case 4: return {IPPROTO_IP, IP_TTL, OPT_INT};
        case 9: return {IPPROTO_IP, IP_MULTICAST_IF, OPT_NONE};
        case 10: return {IPPROTO_IP, IP_MULTICAST_TTL, OPT_INT};
        case 11: return {IPPROTO_IP, IP_MULTICAST_LOOP, OPT_INT};
        case 12: return {IPPROTO_IP, IP_ADD_MEMBERSHIP, OPT_NONE};   /* struct ip_mreq: the same everywhere */
        case 13: return {IPPROTO_IP, IP_DROP_MEMBERSHIP, OPT_NONE};
        case 25: case 26: case 7: return {0, 0, OPT_IGNORE};   /* IP_BOUND_IF, IP_PKTINFO, IP_RECVDSTADDR */
        }
        break;
    case 41:   /* IPPROTO_IPV6 */
        switch (name) {
        case 4: return {IPPROTO_IPV6, IPV6_UNICAST_HOPS, OPT_INT};
        case 9: return {IPPROTO_IPV6, IPV6_MULTICAST_IF, OPT_INT};
        case 10: return {IPPROTO_IPV6, IPV6_MULTICAST_HOPS, OPT_INT};
        case 11: return {IPPROTO_IPV6, IPV6_MULTICAST_LOOP, OPT_INT};
        case 12: return {IPPROTO_IPV6, IPV6_JOIN_GROUP, OPT_NONE};   /* struct ipv6_mreq: the same everywhere */
        case 13: return {IPPROTO_IPV6, IPV6_LEAVE_GROUP, OPT_NONE};
        case 27: return {IPPROTO_IPV6, IPV6_V6ONLY, OPT_INT};
        case 36: case 61: case 125: return {0, 0, OPT_IGNORE};   /* IPV6_TCLASS, IPV6_RECVPKTINFO, IPV6_BOUND_IF */
        }
        break;
    }
    return {0, 0, -1};
}
static int read_int(const uint8_t *v, uint32_t len) {
    if (!v) return 0;
    if (len >= 4) { int x; memcpy(&x, v, 4); return x; }
    return len ? v[0] : 0;
}
static A sockopt(A fd, A level, A name, A val, A lenp_or_len, bool set) {
    Opt o = opt_in((int)level, (int)name);
    if (o.kind < 0) return -D_ENOPROTOOPT;
    Sock s = sock_of(fd);
    uint8_t *v = GP<uint8_t>(val);
    if (set) {
        uint32_t len = (uint32_t)lenp_or_len;
        switch (o.kind) {
        case OPT_IGNORE: return 0;
        case OPT_NREAD: case OPT_ERROR: return -D_ENOPROTOOPT;
        case OPT_INT: { int x = read_int(v, len); return setsockopt(s, o.level, o.name, (const char *)&x, sizeof x) ? neg() : 0; }
        case OPT_TIMEVAL: {
            if (len < 12) return -D_EINVAL;
            int64_t sec; int32_t usec; memcpy(&sec, v, 8); memcpy(&usec, v + 8, 4);
#ifdef _WIN32
            DWORD ms = (DWORD)(sec * 1000 + usec / 1000); if (!ms && usec) ms = 1;
            return setsockopt(s, o.level, o.name, (const char *)&ms, sizeof ms) ? neg() : 0;
#else
            struct timeval tv = {(time_t)sec, (suseconds_t)usec};
            return setsockopt(s, o.level, o.name, &tv, sizeof tv) ? neg() : 0;
#endif
        }
        case OPT_LINGER: {
            if (len < 8) return -D_EINVAL;
            int on, secs; memcpy(&on, v, 4); memcpy(&secs, v + 4, 4);
            linger l; l.l_onoff = (decltype(l.l_onoff))!!on; l.l_linger = (decltype(l.l_linger))secs;
            return setsockopt(s, o.level, o.name, (const char *)&l, sizeof l) ? neg() : 0;
        }
        default: return setsockopt(s, o.level, o.name, (const char *)v, (socklen_t)len) ? neg() : 0;
        }
    }
    uint32_t *lenp = GP<uint32_t>(lenp_or_len);
    if (!lenp || !v) return -D_EFAULT;
    auto put_int = [&](int x) { uint32_t n = std::min<uint32_t>(*lenp, 4); memcpy(v, &x, n); *lenp = n; return (A)0; };
    switch (o.kind) {
    case OPT_IGNORE: return put_int(0);
    case OPT_NREAD: {
#ifdef _WIN32
        u_long n = 0; ioctlsocket(s, FIONREAD, &n);
#else
        int n = 0; ioctl(s, FIONREAD, &n);
#endif
        return put_int((int)n);
    }
    case OPT_INT: case OPT_ERROR: {
        int x = 0; socklen_t n = sizeof x;
        if (getsockopt(s, o.level, o.name, (char *)&x, &n)) return neg();
        if (o.kind == OPT_ERROR) {
            x = x ? derrno(x) : 0;
#ifdef _WIN32
            if (x) set_state(s, 4);
#endif
        }
        if (o.name == SO_TYPE && o.level == SOL_SOCKET) x = x == SOCK_DGRAM ? 2 : x == SOCK_RAW ? 3 : x == SOCK_SEQPACKET ? 5 : 1;
        return put_int(x);
    }
    case OPT_TIMEVAL: {
        int64_t sec = 0; int32_t usec = 0;
#ifdef _WIN32
        DWORD ms = 0; int n = sizeof ms;
        if (getsockopt(s, o.level, o.name, (char *)&ms, &n)) return neg();
        sec = ms / 1000; usec = (int32_t)(ms % 1000) * 1000;
#else
        struct timeval tv{}; socklen_t n = sizeof tv;
        if (getsockopt(s, o.level, o.name, &tv, &n)) return neg();
        sec = tv.tv_sec; usec = (int32_t)tv.tv_usec;
#endif
        uint8_t t[16] = {0}; memcpy(t, &sec, 8); memcpy(t + 8, &usec, 4);
        uint32_t n2 = std::min<uint32_t>(*lenp, 16); memcpy(v, t, n2); *lenp = n2;
        return 0;
    }
    case OPT_LINGER: {
        linger l{}; socklen_t n = sizeof l;
        if (getsockopt(s, o.level, o.name, (char *)&l, &n)) return neg();
        int t[2] = {l.l_onoff ? 1 : 0, (int)l.l_linger};
        uint32_t n2 = std::min<uint32_t>(*lenp, 8); memcpy(v, t, n2); *lenp = n2;
        return 0;
    }
    default: {
        socklen_t n = (socklen_t)*lenp;
        if (getsockopt(s, o.level, o.name, (char *)v, &n)) return neg();
        *lenp = (uint32_t)n;
        return 0;
    }
    }
}

/* ======================================================================= name resolution */
static int eai_out(int e) {
    switch (e) {
    case EAI_AGAIN: return 2;
    case EAI_BADFLAGS: return 3;
    case EAI_FAIL: return 4;
    case EAI_FAMILY: return 5;
    case EAI_MEMORY: return 6;
#if defined(EAI_NODATA) && EAI_NODATA != EAI_NONAME
    case EAI_NODATA: return 8;
#endif
    case EAI_NONAME: return 8;
    case EAI_SERVICE: return 9;
    case EAI_SOCKTYPE: return 10;
#ifdef EAI_SYSTEM
    case EAI_SYSTEM: return 11;
#endif
    }
    return 4;
}
static A resolve(A node, A service, A hintsp, A outp, A max) {
    net_init();
    const dnethints *dh = GP<dnethints>(hintsp);
    addrinfo h{}, *res = nullptr;
    if (dh) {
        int f = dh->flags;
        h.ai_flags = (f & 1 ? AI_PASSIVE : 0) | (f & 2 ? AI_CANONNAME : 0) | (f & 4 ? AI_NUMERICHOST : 0)
                   | (f & 0x1000 ? AI_NUMERICSERV : 0) | (f & 0x400 ? AI_ADDRCONFIG : 0) | (f & 0x800 ? AI_V4MAPPED : 0)
                   | (f & 0x100 ? AI_ALL : 0);
        h.ai_family = dom_in(dh->family); if (h.ai_family < 0) return -(1000 + 5);
        h.ai_socktype = dh->socktype; h.ai_protocol = dh->protocol;
    }
    int r = getaddrinfo(GP<const char>(node), GP<const char>(service), dh ? &h : nullptr, &res);
    if (r) return -(1000 + eai_out(r));
    dnetai *out = GP<dnetai>(outp);
    A n = 0;
    for (addrinfo *a = res; a && n < max; a = a->ai_next) {
        if (a->ai_family != AF_INET && a->ai_family != AF_INET6) continue;
        dnetai &o = out[n++];
        memset(&o, 0, sizeof o);
        o.family = dom_out(a->ai_family); o.socktype = a->ai_socktype; o.protocol = a->ai_protocol;
        o.addrlen = sizeof o.addr;
        sa_out(a->ai_addr, (socklen_t)a->ai_addrlen, o.addr, &o.addrlen);
    }
    if (dh && dh->canon && dh->canonlen && res && res->ai_canonname) {
        char *c = GP<char>(dh->canon);
        size_t len = std::min<size_t>(strlen(res->ai_canonname), dh->canonlen - 1);
        memcpy(c, res->ai_canonname, len); c[len] = 0;
    }
    freeaddrinfo(res);
    return n ? n : -(1000 + 8);
}
static A nameinfo(A argp) {
    net_init();
    const dnetni *a = GP<dnetni>(argp);
    sockaddr_storage h; socklen_t hl;
    if (sa_in(GP<uint8_t>(a->addr), a->addrlen, h, hl)) return 5;   /* EAI_FAMILY */
    int f = a->flags;
    int hf = (f & 1 ? NI_NOFQDN : 0) | (f & 2 ? NI_NUMERICHOST : 0) | (f & 4 ? NI_NAMEREQD : 0) | (f & 8 ? NI_NUMERICSERV : 0)
           | (f & 0x10 ? NI_DGRAM : 0);
    int r = getnameinfo((sockaddr *)&h, hl, GP<char>(a->host), (socklen_t)a->hostlen, GP<char>(a->serv), (socklen_t)a->servlen, hf);
    return r ? eai_out(r) : 0;
}

/* ======================================================================= poll */
/* Darwin and Linux poll bits agree except the band/normal write bits; Winsock has its own */
static A do_poll(A fdsp, A n, A timeout) {
    dpollfd *p = GP<dpollfd>(fdsp);
#ifdef _WIN32
    /* sockets through WSAPoll; anything else counts as ready (ponytail: pipes and consoles are not polled) */
    std::vector<WSAPOLLFD> w; std::vector<int> idx;
    A ready = 0;
    for (A i = 0; i < n; i++) {
        p[i].revents = 0;
        if (p[i].fd < 0) continue;
        Sock s = sock_of(p[i].fd);
        if (s == BAD_SOCK) { if ((p[i].revents = p[i].events & 5)) ready++; continue; }
        WSAPOLLFD x{}; x.fd = s;
        if (p[i].events & (1 | 0x40)) x.events |= POLLRDNORM;
        if (p[i].events & 4) x.events |= POLLWRNORM;
        w.push_back(x); idx.push_back((int)i);
    }
    if (w.empty()) {
        if (!ready && timeout != 0) std::this_thread::sleep_for(std::chrono::nanoseconds(timeout < 0 ? 1000000000ll : timeout));
        return ready;
    }
    int ms = ready ? 0 : timeout < 0 ? -1 : (int)((timeout + 999999) / 1000000);
    int r = WSAPoll(w.data(), (ULONG)w.size(), ms);
    if (r < 0) return neg();
    for (size_t k = 0; k < w.size(); k++) {
        dpollfd &q = p[idx[k]]; short rv = w[k].revents;
        if (rv & (POLLRDNORM | POLLRDBAND)) q.revents |= q.events & (1 | 0x40);
        if (rv & POLLWRNORM) { q.revents |= q.events & 4; if (info_of(w[k].fd).state == 1) set_state(w[k].fd, 2); }
        if (rv & POLLERR) q.revents |= 8;
        if (rv & POLLHUP) q.revents |= 0x10;
        if (rv & POLLNVAL) q.revents |= 0x20;
        if (q.revents) ready++;
    }
    return ready;
#else
    std::vector<pollfd> h((size_t)n);
    for (A i = 0; i < n; i++) {
        short e = p[i].events;
        h[i].fd = p[i].fd;
        h[i].events = (short)((e & (POLLIN | POLLPRI | POLLOUT | POLLRDNORM | POLLRDBAND)) | (e & 0x100 ? POLLWRBAND : 0));
    }
    int r = poll(h.data(), (nfds_t)n, timeout < 0 ? -1 : (int)((timeout + 999999) / 1000000));
    if (r < 0) return neg();
    for (A i = 0; i < n; i++) {
        short e = h[i].revents;
        p[i].revents = (short)((e & (POLLIN | POLLPRI | POLLOUT | POLLERR | POLLHUP | POLLNVAL | POLLRDNORM | POLLRDBAND))
                             | (e & POLLWRNORM ? 4 : 0) | (e & POLLWRBAND ? 0x100 : 0));
    }
    return r;
#endif
}

/* ======================================================================= kqueue */
struct Reg { uint64_t udata = 0; uint16_t flags = 0; bool enabled = true, armed = true, eof = false; };
struct Kq {
    std::mutex mu;
    std::map<std::pair<int, int>, Reg> regs;   /* (fd, filter) */
    uint64_t user_ident = 0, user_udata = 0; uint16_t user_flags = 0; bool user_on = false, user_fired = false;
#ifdef _WIN32
    Sock wake_rx = BAD_SOCK, wake_tx = BAD_SOCK; int waiting = 0;
    void wake() { if (waiting) { char b = 0; send(wake_tx, &b, 1, 0); } }
#else
    int ep = -1, evfd = -1;
#endif
};
static std::mutex g_kqmu;
static std::unordered_map<int, std::shared_ptr<Kq>> g_kqs;   /* by descriptor */
static std::shared_ptr<Kq> kq_of(A fd) { std::lock_guard<std::mutex> l(g_kqmu); auto it = g_kqs.find((int)fd); return it == g_kqs.end() ? nullptr : it->second; }

#ifdef _WIN32
/* an edge-triggered registration that was reported comes back once the guest has emptied (or filled) the socket */
static void rearm(int fd, int filter) {
    std::vector<std::shared_ptr<Kq>> kqs;
    { std::lock_guard<std::mutex> l(g_kqmu); for (auto &k : g_kqs) kqs.push_back(k.second); }
    for (auto &k : kqs) {
        std::lock_guard<std::mutex> l(k->mu);
        auto it = k->regs.find({fd, filter});
        if (it != k->regs.end() && !it->second.armed) { it->second.armed = true; k->wake(); }
    }
}
#endif

HCABI A hc_kqueue(A, A, A, A, A, A) {
    net_init();
    auto k = std::make_shared<Kq>();
#ifdef _WIN32
    /* the wakeup: a datagram from wake_tx to wake_rx, both on the loopback interface */
    k->wake_rx = socket(AF_INET, SOCK_DGRAM, 0); k->wake_tx = socket(AF_INET, SOCK_DGRAM, 0);
    sockaddr_in a{}; a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK); int al = sizeof a;
    if (k->wake_rx == BAD_SOCK || k->wake_tx == BAD_SOCK || bind(k->wake_rx, (sockaddr *)&a, sizeof a)
        || getsockname(k->wake_rx, (sockaddr *)&a, &al) || connect(k->wake_tx, (sockaddr *)&a, sizeof a)) {
        A e = neg(); closesocket(k->wake_rx); closesocket(k->wake_tx); return e;
    }
    u_long one = 1; ioctlsocket(k->wake_rx, FIONBIO, &one);
    int fd = host_fd_add_kqueue();
#else
    k->ep = epoll_create1(EPOLL_CLOEXEC);
    k->evfd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (k->ep < 0 || k->evfd < 0) { A e = neg(); close(k->ep); close(k->evfd); return e; }
    epoll_event e{}; e.events = EPOLLIN; e.data.fd = k->evfd;
    epoll_ctl(k->ep, EPOLL_CTL_ADD, k->evfd, &e);
    int fd = k->ep;
#endif
    std::lock_guard<std::mutex> l(g_kqmu); g_kqs[fd] = k;
    return fd;
}

/* a descriptor was closed (host.cpp / host_linux.cpp hc_close): its kqueue, or its registrations, go */
void net_fd_closed(int fd) {
    std::shared_ptr<Kq> gone;
    std::vector<std::shared_ptr<Kq>> kqs;
    {
        std::lock_guard<std::mutex> l(g_kqmu);
        auto it = g_kqs.find(fd);
        if (it != g_kqs.end()) { gone = it->second; g_kqs.erase(it); }
        for (auto &k : g_kqs) kqs.push_back(k.second);
    }
    if (gone) {
#ifdef _WIN32
        closesocket(gone->wake_rx); closesocket(gone->wake_tx);
#else
        close(gone->evfd);   /* (ep is fd itself: hc_close closes it) */
#endif
    }
    for (auto &k : kqs) {
        std::lock_guard<std::mutex> l(k->mu);
        k->regs.erase({fd, D_EVFILT_READ}); k->regs.erase({fd, D_EVFILT_WRITE});
    }
}

#ifndef _WIN32
/* the epoll registration of fd from the kqueue's registrations of it */
static int epoll_sync(Kq &k, int fd) {
    uint32_t ev = 0; bool any = false, et = false;
    for (int f : {D_EVFILT_READ, D_EVFILT_WRITE}) {
        auto it = k.regs.find({fd, f});
        if (it == k.regs.end()) continue;
        any = true;
        if (it->second.flags & (D_EV_CLEAR | D_EV_DISPATCH)) et = true;
        if (it->second.enabled) ev |= f == D_EVFILT_READ ? EPOLLIN | EPOLLRDHUP : EPOLLOUT;
    }
    epoll_event e{}; e.events = ev | (et ? EPOLLET : 0); e.data.fd = fd;
    if (!any) { epoll_ctl(k.ep, EPOLL_CTL_DEL, fd, &e); return 0; }
    if (epoll_ctl(k.ep, EPOLL_CTL_MOD, fd, &e) == 0) return 0;
    return errno == ENOENT && epoll_ctl(k.ep, EPOLL_CTL_ADD, fd, &e) == 0 ? 0 : -derrno(errno);
}
#endif

static int nread(Sock s) {
#ifdef _WIN32
    u_long n = 0; ioctlsocket(s, FIONREAD, &n); return (int)n;
#else
    int n = 0; ioctl(s, FIONREAD, &n); return n;
#endif
}

HCABI A hc_kevent(A kqfd, A chp, A nch, A evp, A nev, A timeout) {
    auto k = kq_of(kqfd); if (!k) return -D_EBADF;
    const dkevent *ch = GP<const dkevent>(chp);
    dkevent *ev = GP<dkevent>(evp);
    A out = 0;
    auto emit = [&](const dkevent &e) { if (out < nev) ev[out++] = e; };
    /* the changes */
    {
        std::lock_guard<std::mutex> l(k->mu);
        bool wake = false;
        for (A i = 0; i < nch; i++) {
            const dkevent &c = ch[i];
            int err = 0;
            if (c.filter == D_EVFILT_USER) {
                if (c.flags & D_EV_ADD) { k->user_on = true; k->user_ident = c.ident; k->user_udata = c.udata; k->user_flags = c.flags; }
                if (c.flags & D_EV_DELETE) k->user_on = false;
                if (c.fflags & D_NOTE_TRIGGER) {
                    k->user_fired = true;
#ifdef _WIN32
                    wake = true;
#else
                    uint64_t one = 1; if (write(k->evfd, &one, 8)) {}
#endif
                }
            } else if (c.filter == D_EVFILT_READ || c.filter == D_EVFILT_WRITE) {
                int fd = (int)c.ident;
                auto key = std::make_pair(fd, (int)c.filter);
                auto it = k->regs.find(key);
#ifdef _WIN32
                if (sock_of(fd) == BAD_SOCK) err = (c.flags & D_EV_DELETE) ? D_ENOENT : D_EINVAL;   /* sockets only */
                else
#endif
                if (c.flags & D_EV_ADD) {
                    Reg &r = k->regs[key];
                    r.udata = c.udata; r.flags = c.flags; r.enabled = !(c.flags & D_EV_DISABLE); r.armed = true; wake = true;
                } else if (it == k->regs.end()) err = D_ENOENT;
                else if (c.flags & D_EV_DELETE) k->regs.erase(it);
                else {
                    if (c.flags & D_EV_ENABLE) { it->second.enabled = true; it->second.armed = true; wake = true; }
                    if (c.flags & D_EV_DISABLE) it->second.enabled = false;
                }
#ifndef _WIN32
                if (!err && (err = -epoll_sync(*k, fd))) k->regs.erase(key);
#endif
            } else err = D_EINVAL;   /* ponytail: EVFILT_TIMER, EVFILT_PROC, EVFILT_SIGNAL, EVFILT_VNODE */
            if (err || (c.flags & D_EV_RECEIPT)) {
                if (!nev) return -err;
                dkevent r = c; r.flags |= D_EV_ERROR; r.data = err; emit(r);
            }
        }
#ifdef _WIN32
        if (wake) k->wake();
#else
        (void)wake;
#endif
    }
    if (out || nev <= 0) return out;

    /* the wait */
    using clk = std::chrono::steady_clock;
    const auto deadline = clk::now() + std::chrono::nanoseconds(timeout < 0 ? 0 : timeout);
    for (;;) {
        int ms = timeout < 0 ? -1 : (int)std::max<int64_t>(0, (std::chrono::duration_cast<std::chrono::nanoseconds>(deadline - clk::now()).count() + 999999) / 1000000);
#ifdef _WIN32
        std::vector<WSAPOLLFD> w;
        std::vector<int> fds;   /* w[i + 1] polls fds[i] */
        {
            std::lock_guard<std::mutex> l(k->mu);
            if (k->user_on && k->user_fired) ms = 0;
            WSAPOLLFD x{}; x.fd = k->wake_rx; x.events = POLLRDNORM; w.push_back(x);
            for (auto &r : k->regs) {
                if (!r.second.enabled) continue;
                Sock s = sock_of(r.first.first);
                if (s == BAD_SOCK) continue;
                SockInfo si = info_of(s);
                bool rd = r.first.second == D_EVFILT_READ;
                /* an edge-triggered read registration on a connected socket with nothing left to read: whatever comes
                 * next (data, the end of the stream) is a new edge, even if the guest never got EAGAIN */
                if (!r.second.armed && rd && si.state == 2 && !r.second.eof && nread(s) == 0) r.second.armed = true;
                if (!r.second.armed) continue;
                /* a stream socket that is not connecting, connected or listening has nothing to say yet */
                if (si.stream && (rd ? si.state < 2 : si.state == 0 || si.state == 3)) continue;
                if (!fds.empty() && fds.back() == r.first.first) { w.back().events |= rd ? POLLRDNORM : POLLWRNORM; continue; }
                x.fd = s; x.events = rd ? POLLRDNORM : POLLWRNORM; w.push_back(x); fds.push_back(r.first.first);
            }
            k->waiting++;
        }
        int r = WSAPoll(w.data(), (ULONG)w.size(), ms);
        std::lock_guard<std::mutex> l(k->mu);
        k->waiting--;
        if (r < 0) {   /* a socket in the set was closed meanwhile: its registrations are gone, poll again */
            if (WSAGetLastError() != WSAENOTSOCK) return neg();
            continue;
        }
        if (w[0].revents) { char b[64]; while (recv(k->wake_rx, b, sizeof b, 0) > 0) {} }
        for (size_t i = 1; i < w.size() && out < nev; i++) {
            short rv = w[i].revents;
            if (!rv) continue;
            int fd = fds[i - 1];
            Sock s = sock_of(fd);
            if (rv & POLLWRNORM) { SockInfo si = info_of(s); if (si.state == 1) set_state(s, 2); }
            if ((rv & (POLLERR | POLLHUP)) && info_of(s).state == 1) set_state(s, 4);
            for (int f : {D_EVFILT_READ, D_EVFILT_WRITE}) {
                auto it = k->regs.find({fd, f});
                if (it == k->regs.end() || !it->second.enabled || !it->second.armed || out >= nev) continue;
                bool hit = f == D_EVFILT_READ ? (rv & (POLLRDNORM | POLLHUP | POLLERR)) : (rv & (POLLWRNORM | POLLHUP | POLLERR));
                if (!hit) continue;
                dkevent e{}; e.ident = (uint64_t)fd; e.filter = (int16_t)f; e.udata = it->second.udata;
                e.flags = (rv & (POLLHUP | POLLERR)) ? D_EV_EOF : 0;
                /* Winsock reports a peer's shutdown as readable only: the end of the stream is a read that returns 0 */
                char peek;
                if (f == D_EVFILT_READ && !e.flags && info_of(s).stream && nread(s) == 0 && recv(s, &peek, 1, MSG_PEEK) == 0) e.flags = D_EV_EOF;
                if (e.flags & D_EV_EOF) it->second.eof = true;
                if (rv & POLLERR) { int x = 0; int n = sizeof x; getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&x, &n); e.fflags = x ? derrno(x) : 0; }
                e.data = f == D_EVFILT_READ ? nread(s) : 65536;
                emit(e);
                if (it->second.flags & D_EV_ONESHOT) k->regs.erase(it);
                else if (it->second.flags & D_EV_DISPATCH) it->second.enabled = false;
                else if (it->second.flags & D_EV_CLEAR) it->second.armed = false;
            }
        }
#else
        epoll_event e[64];
        int r = epoll_wait(k->ep, e, (int)std::min<A>(64, std::max<A>(1, nev / 2)), ms);
        if (r < 0) return -derrno(errno);
        std::lock_guard<std::mutex> l(k->mu);
        for (int i = 0; i < r; i++) {
            int fd = e[i].data.fd; uint32_t rv = e[i].events;
            if (fd == k->evfd) { uint64_t v; if (read(k->evfd, &v, 8)) {} continue; }
            bool sync = false;
            for (int f : {D_EVFILT_READ, D_EVFILT_WRITE}) {
                auto it = k->regs.find({fd, f});
                if (it == k->regs.end() || !it->second.enabled || out >= nev) continue;
                bool hit = f == D_EVFILT_READ ? (rv & (EPOLLIN | EPOLLRDHUP | EPOLLHUP | EPOLLERR)) : (rv & (EPOLLOUT | EPOLLHUP | EPOLLERR));
                if (!hit) continue;
                dkevent d{}; d.ident = (uint64_t)fd; d.filter = (int16_t)f; d.udata = it->second.udata;
                d.flags = (rv & (EPOLLHUP | EPOLLERR)) || (f == D_EVFILT_READ && (rv & EPOLLRDHUP)) ? D_EV_EOF : 0;
                if (rv & EPOLLERR) { int x = 0; socklen_t n = sizeof x; getsockopt(fd, SOL_SOCKET, SO_ERROR, &x, &n); d.fflags = x ? derrno(x) : 0; }
                d.data = f == D_EVFILT_READ ? nread(fd) : 65536;
                emit(d);
                if (it->second.flags & D_EV_ONESHOT) { k->regs.erase(it); sync = true; }
                else if (it->second.flags & D_EV_DISPATCH) { it->second.enabled = false; sync = true; }
            }
            if (sync) epoll_sync(*k, fd);
        }
#endif
        if (k->user_on && k->user_fired && out < nev) {
            dkevent d{}; d.ident = k->user_ident; d.filter = D_EVFILT_USER; d.udata = k->user_udata;
            emit(d);
            if (k->user_flags & (D_EV_CLEAR | D_EV_ONESHOT | D_EV_DISPATCH)) k->user_fired = false;
            if (k->user_flags & D_EV_ONESHOT) k->user_on = false;
        }
        if (out || (timeout >= 0 && clk::now() >= deadline)) return out;
    }
}

/* ======================================================================= the guest's descriptors as sockets */
#ifdef _WIN32
/* read / write on a socket descriptor (host.cpp) */
A net_sock_io(int fd, uintptr_t s, void *buf, size_t n, bool wr) {
    int r = wr ? send((Sock)s, (const char *)buf, (int)std::min<size_t>(n, INT_MAX), 0) : recv((Sock)s, (char *)buf, (int)std::min<size_t>(n, INT_MAX), 0);
    if (r >= 0) return r;
    int e = WSAGetLastError();
    if (e == WSAEWOULDBLOCK) return would_block(fd, wr ? D_EVFILT_WRITE : D_EVFILT_READ);
    if (e == WSAESHUTDOWN && wr) return -D_EPIPE;
    if (e == WSAEMSGSIZE && !wr) return (A)n;
    return -derrno(e);
}
#endif

/* a connected pair (Windows: over the loopback interface; AF_UNIX there would need paths) */
static A socketpair_(A domain, A type, A proto, int *fds) {
#ifdef _WIN32
    (void)proto;
    if (domain != 1 && domain != 2) return -47;
    bool stream = type != 2;
    Sock l = socket(AF_INET, stream ? SOCK_STREAM : SOCK_DGRAM, 0), a = BAD_SOCK, b = BAD_SOCK;
    sockaddr_in sa{}; sa.sin_family = AF_INET; sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK); int sl = sizeof sa;
    if (l == BAD_SOCK || bind(l, (sockaddr *)&sa, sizeof sa) || getsockname(l, (sockaddr *)&sa, &sl)) goto fail;
    b = socket(AF_INET, stream ? SOCK_STREAM : SOCK_DGRAM, 0);
    if (stream) {
        if (listen(l, 1) || b == BAD_SOCK || connect(b, (sockaddr *)&sa, sizeof sa)) goto fail;
        a = accept(l, nullptr, nullptr); closesocket(l); l = BAD_SOCK;
        if (a == BAD_SOCK) goto fail;
    } else {
        sockaddr_in sb{}; sb.sin_family = AF_INET; sb.sin_addr.s_addr = htonl(INADDR_LOOPBACK); int bl = sizeof sb;
        if (b == BAD_SOCK || bind(b, (sockaddr *)&sb, sizeof sb) || getsockname(b, (sockaddr *)&sb, &bl)
            || connect(b, (sockaddr *)&sa, sizeof sa) || connect(l, (sockaddr *)&sb, sizeof sb)) goto fail;
        a = l; l = BAD_SOCK;
    }
    if (stream) { BOOL one = TRUE; setsockopt(a, IPPROTO_TCP, TCP_NODELAY, (char *)&one, sizeof one); setsockopt(b, IPPROTO_TCP, TCP_NODELAY, (char *)&one, sizeof one); }
    fds[0] = (int)new_fd(a, stream, 2); fds[1] = (int)new_fd(b, stream, 2);
    return 0;
fail:
    A e = neg();
    if (l != BAD_SOCK) closesocket(l);
    if (a != BAD_SOCK) closesocket(a);
    if (b != BAD_SOCK) closesocket(b);
    return e;
#else
    int d = dom_in((int)domain);
    return d < 0 ? -47 : socketpair(d, (int)type, (int)proto, fds) ? neg() : 0;
#endif
}

HCABI A hc_net(A op, A a, A b, A c, A d, A e) {
    if (op >= NET_HTTP_NEW) return http_op(op, a, b, c);
    net_init();
    switch (op) {
    case NET_SOCKET: {
        int dom = dom_in((int)a);
        if (dom < 0 || dom == AF_UNSPEC) return -47;   /* EAFNOSUPPORT: AF_ROUTE, AF_SYSTEM, ... */
#ifdef _WIN32
        if (dom == AF_UNIX) return -47;
#endif
        Sock s = socket(dom, (int)b, (int)c);
        if (s == BAD_SOCK) return neg();
#ifdef _WIN32
        if (dom == AF_INET6) { DWORD off = 0; setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, (char *)&off, sizeof off); }   /* dual stack, as on Darwin */
#endif
        return new_fd(s, b != 2, 0);
    }
    case NET_SOCKETPAIR: return socketpair_(a, b, c, GP<int>(d));
    case NET_CONNECT: case NET_BIND: {
        Sock s = sock_of(a); if (s == BAD_SOCK) return -D_ENOTSOCK;
        sockaddr_storage h; socklen_t hl = 0;
        if (A r = sa_in(GP<uint8_t>(b), (uint32_t)c, h, hl)) return r;
        if (op == NET_BIND) return bind(s, (sockaddr *)&h, hl) ? neg() : 0;
        int r = connect(s, (sockaddr *)&h, hl);
#ifdef _WIN32
        if (!r) { set_state(s, 2); return 0; }
        int err = WSAGetLastError();
        if (err == WSAEWOULDBLOCK || err == WSAEINPROGRESS) { set_state(s, 1); rearm((int)a, D_EVFILT_WRITE); return -D_EINPROGRESS; }
        if (err == WSAEALREADY || err == WSAEINVAL) return info_of(s).state == 1 ? -D_EALREADY : -derrno(err);
        if (err == WSAEISCONN) set_state(s, 2);
        return -derrno(err);
#else
        return r ? neg() : 0;
#endif
    }
    case NET_LISTEN: {
        Sock s = sock_of(a); if (s == BAD_SOCK) return -D_ENOTSOCK;
        if (listen(s, (int)b < 0 ? SOMAXCONN : (int)b)) return neg();
#ifdef _WIN32
        set_state(s, 3); rearm((int)a, D_EVFILT_READ);
#endif
        return 0;
    }
    case NET_ACCEPT: {
        Sock s = sock_of(a); if (s == BAD_SOCK) return -D_ENOTSOCK;
        sockaddr_storage h; socklen_t hl = sizeof h;
#ifdef _WIN32
        Sock n = accept(s, (sockaddr *)&h, &hl);
        if (n == BAD_SOCK) return WSAGetLastError() == WSAEWOULDBLOCK ? would_block(a, D_EVFILT_READ) : neg();
        bool nb = info_of(s).nonblock;   /* accepted sockets keep the listener's blocking mode, as on Darwin */
        A fd = new_fd(n, true, 2, nb);
#else
        int fl = fcntl(s, F_GETFL);
        Sock n = accept4(s, (sockaddr *)&h, &hl, SOCK_CLOEXEC | (fl >= 0 && (fl & O_NONBLOCK) ? SOCK_NONBLOCK : 0));
        if (n < 0) return neg();
        A fd = n;
#endif
        if (b) sa_out((sockaddr *)&h, hl, GP<uint8_t>(b), GP<uint32_t>(c));
        else if (c) *GP<uint32_t>(c) = 0;
        return fd;
    }
    case NET_SEND: case NET_RECV: {
        Sock s = sock_of(a); if (s == BAD_SOCK) return -D_ENOTSOCK;
        dnetio *io = GP<dnetio>(b);
        char *buf = GP<char>(io->buf);
        int len = (int)std::min<uint64_t>(io->len, INT_MAX), fl = msg_flags(io->flags);
        sockaddr_storage to; socklen_t tol = 0;
        if (op == NET_SEND && io->addr && io->addrlen) { if (A x = sa_in(GP<uint8_t>(io->addr), io->addrlen, to, tol)) return x; }
#ifdef _WIN32
        bool dontwait = (io->flags & 0x80) && !info_of(s).nonblock;   /* MSG_DONTWAIT: non-blocking for this call */
        if (dontwait) { u_long on = 1; ioctlsocket(s, FIONBIO, &on); }
#endif
        int r;
        if (op == NET_SEND) {
            r = tol ? sendto(s, buf, len, fl, (sockaddr *)&to, tol) : send(s, buf, len, fl);
        } else {
            sockaddr_storage h; socklen_t hl = sizeof h;
            memset(&h, 0, sizeof h);
            r = recvfrom(s, buf, len, fl, (sockaddr *)&h, &hl);
            if (r >= 0 && io->addr) { if (hl > 0 && h.ss_family) sa_out((sockaddr *)&h, hl, GP<uint8_t>(io->addr), &io->addrlen); else io->addrlen = 0; }
        }
        int err = r < 0 ? sock_errno() : 0;
#ifdef _WIN32
        if (dontwait) { u_long off = 0; ioctlsocket(s, FIONBIO, &off); }
        if (r < 0 && err == WSAEMSGSIZE && op == NET_RECV) return len;   /* a truncated datagram, as POSIX returns it */
        if (r < 0 && err == WSAESHUTDOWN && op == NET_SEND) return -D_EPIPE;
        if (r < 0 && err == WSAEWOULDBLOCK) return would_block(a, op == NET_SEND ? D_EVFILT_WRITE : D_EVFILT_READ);
        if (r >= 0 && info_of(s).state == 1) set_state(s, 2);
#endif
        io->flags = 0;
        return r < 0 ? -derrno(err) : r;
    }
    case NET_SHUTDOWN: {
        Sock s = sock_of(a); if (s == BAD_SOCK) return -D_ENOTSOCK;
        return shutdown(s, (int)b) ? neg() : 0;   /* SHUT_RD/WR/RDWR are 0, 1, 2 everywhere */
    }
    case NET_GETSOCKOPT: case NET_SETSOCKOPT:
        if (sock_of(a) == BAD_SOCK) return -D_ENOTSOCK;
        return sockopt(a, b, c, d, e, op == NET_SETSOCKOPT);
    case NET_SOCKNAME: {
        Sock s = sock_of(a); if (s == BAD_SOCK) return -D_ENOTSOCK;
        sockaddr_storage h; socklen_t hl = sizeof h;
        if (d ? getpeername(s, (sockaddr *)&h, &hl) : getsockname(s, (sockaddr *)&h, &hl)) {
#ifdef _WIN32
            if (d && WSAGetLastError() == WSAENOTCONN && info_of(s).state == 1) rearm((int)a, D_EVFILT_WRITE);   /* still connecting */
#endif
            return neg();
        }
#ifdef _WIN32
        if (d) set_state(s, 2);
#endif
        sa_out((sockaddr *)&h, hl, GP<uint8_t>(b), GP<uint32_t>(c));
        return 0;
    }
    case NET_RESOLVE: return resolve(a, b, c, d, e);
    case NET_NAMEINFO: return nameinfo(a);
    case NET_POLL: return do_poll(a, b, c);
    case NET_FLAGS: {
        Sock s = sock_of(a);
#ifdef _WIN32
        if (s == BAD_SOCK) return D_O_RDWR;   /* other descriptors: no flags to change (ponytail: O_NONBLOCK on pipes) */
        if (b >= 0) set_nonblock(s, b & D_O_NONBLOCK);
        return D_O_RDWR | (info_of(s).nonblock ? D_O_NONBLOCK : 0);
#else
        int fl = fcntl(s, F_GETFL);
        if (fl < 0) return neg();
        if (b >= 0) { fl = (fl & ~O_NONBLOCK) | (b & D_O_NONBLOCK ? O_NONBLOCK : 0); if (fcntl(s, F_SETFL, fl)) return neg(); }
        return (fl & O_ACCMODE) | (fl & O_NONBLOCK ? D_O_NONBLOCK : 0) | (fl & O_APPEND ? D_O_APPEND : 0);
#endif
    }
    case NET_NREAD: {
        Sock s = sock_of(a);
        if (s == BAD_SOCK) return -D_ENOTSOCK;
        return nread(s);
    }
    }
    return -D_ENOSYS;
}
