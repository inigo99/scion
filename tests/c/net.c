/* Sockets on the loopback interface: TCP (blocking and non-blocking, with kqueue, poll and select), UDP,
 * socketpair, IPv6, options, getaddrinfo / getnameinfo and the inet_* conversions. Prints NET OK. */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s (errno %d)\n", __LINE__, #c, errno); return 1; } } while (0)

/* the next event for (ident, filter); events for others are kept for later calls, as edge-triggered ones come once */
static struct kevent pending[16];
static int npending;
static int wait_kq(int kq, int ident, int filter, int ms, struct kevent *out) {
    for (int i = 0; i < npending; i++)
        if ((int)pending[i].ident == ident && pending[i].filter == filter) { *out = pending[i]; pending[i] = pending[--npending]; return 1; }
    struct timespec ts = {ms / 1000, (ms % 1000) * 1000000};
    for (;;) {
        int n = kevent(kq, NULL, 0, out, 1, &ts);
        if (n <= 0) return n;
        if ((int)out->ident == ident && out->filter == filter) return 1;
        if (npending < 16) pending[npending++] = *out;
    }
}

int main(void) {
    /* text <-> address */
    struct in_addr a4; struct in6_addr a6; char buf[64];
    CHECK(inet_pton(AF_INET, "192.168.1.20", &a4) == 1 && ntohl(a4.s_addr) == 0xC0A80114);
    CHECK(inet_pton(AF_INET, "256.1.1.1", &a4) == 0);
    CHECK(inet_pton(AF_INET6, "fe80::1:2", &a6) == 1 && a6.s6_addr[0] == 0xfe && a6.s6_addr[13] == 1 && a6.s6_addr[15] == 2);
    CHECK(!strcmp(inet_ntop(AF_INET6, &a6, buf, sizeof buf), "fe80::1:2"));
    CHECK(inet_pton(AF_INET6, "::ffff:10.0.0.1", &a6) == 1 && !strcmp(inet_ntop(AF_INET6, &a6, buf, sizeof buf), "::ffff:10.0.0.1"));
    printf("inet_pton/ntop ok\n");

    /* names */
    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV; hints.ai_socktype = SOCK_STREAM;
    CHECK(getaddrinfo("127.0.0.1", "8080", &hints, &res) == 0 && res && res->ai_family == AF_INET);
    struct sockaddr_in *sin = (struct sockaddr_in *)res->ai_addr;
    CHECK(ntohs(sin->sin_port) == 8080 && sin->sin_len == sizeof *sin && res->ai_addrlen == sizeof *sin);
    char host[64], serv[16];
    CHECK(getnameinfo(res->ai_addr, res->ai_addrlen, host, sizeof host, serv, sizeof serv, NI_NUMERICHOST | NI_NUMERICSERV) == 0);
    CHECK(!strcmp(host, "127.0.0.1") && !strcmp(serv, "8080"));
    freeaddrinfo(res);
    memset(&hints, 0, sizeof hints); hints.ai_socktype = SOCK_STREAM;
    CHECK(getaddrinfo("localhost", NULL, &hints, &res) == 0 && res);
    freeaddrinfo(res);
    CHECK(getaddrinfo("no-such-host.invalid", NULL, &hints, &res) != 0);
    printf("getaddrinfo ok\n");

    /* TCP: a listener, a non-blocking client, kqueue */
    int ls = socket(AF_INET, SOCK_STREAM, 0); CHECK(ls >= 0);
    int one = 1; CHECK(setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one) == 0);
    struct sockaddr_in sa = {0}; sa.sin_len = sizeof sa; sa.sin_family = AF_INET; sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(ls, (struct sockaddr *)&sa, sizeof sa) == 0 && listen(ls, 8) == 0);
    socklen_t sl = sizeof sa; CHECK(getsockname(ls, (struct sockaddr *)&sa, &sl) == 0 && sa.sin_port != 0);
    CHECK(fcntl(ls, F_SETFL, fcntl(ls, F_GETFL) | O_NONBLOCK) == 0 && (fcntl(ls, F_GETFL) & O_NONBLOCK));
    CHECK(accept(ls, NULL, NULL) < 0 && errno == EAGAIN);

    int c = socket(AF_INET, SOCK_STREAM, 0); CHECK(c >= 0);
    CHECK(fcntl(c, F_SETFL, O_NONBLOCK) == 0);
    CHECK(setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one) == 0);
    int kq = kqueue(); CHECK(kq >= 0);
    struct kevent ch[3], ev;
    EV_SET(&ch[0], ls, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, (void *)1);
    EV_SET(&ch[1], c, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, (void *)2);
    EV_SET(&ch[2], c, EVFILT_WRITE, EV_ADD | EV_CLEAR, 0, 0, (void *)3);
    CHECK(kevent(kq, ch, 3, NULL, 0, NULL) == 0);
    int r = connect(c, (struct sockaddr *)&sa, sizeof sa);
    CHECK(r == 0 || errno == EINPROGRESS);
    CHECK(wait_kq(kq, ls, EVFILT_READ, 5000, &ev) == 1 && ev.udata == (void *)1);
    struct sockaddr_in peer; socklen_t pl = sizeof peer;
    int s = accept(ls, (struct sockaddr *)&peer, &pl); CHECK(s >= 0 && pl == sizeof peer && peer.sin_family == AF_INET);
    CHECK(wait_kq(kq, c, EVFILT_WRITE, 5000, &ev) == 1);
    int err = -1; socklen_t el = sizeof err;
    CHECK(getsockopt(c, SOL_SOCKET, SO_ERROR, &err, &el) == 0 && err == 0);
    pl = sizeof peer; CHECK(getpeername(c, (struct sockaddr *)&peer, &pl) == 0 && peer.sin_port == sa.sin_port);
    printf("connect, accept, kqueue ok\n");

    /* data, edge-triggered reads: reported once, again after EAGAIN */
    CHECK(write(c, "ping", 4) == 4);
    char b[64]; CHECK(recv(s, b, sizeof b, 0) == 4 && !memcmp(b, "ping", 4));
    CHECK(send(s, "pong", 4, 0) == 4);
    CHECK(wait_kq(kq, c, EVFILT_READ, 5000, &ev) == 1 && ev.data >= 1);
    CHECK(read(c, b, sizeof b) == 4 && !memcmp(b, "pong", 4));
    CHECK(read(c, b, sizeof b) < 0 && errno == EAGAIN);
    CHECK(send(s, "more", 4, 0) == 4);
    CHECK(wait_kq(kq, c, EVFILT_READ, 5000, &ev) == 1);
    CHECK(recv(c, b, sizeof b, MSG_PEEK) == 4 && recv(c, b, sizeof b, 0) == 4 && !memcmp(b, "more", 4));
    printf("send, recv, EV_CLEAR ok\n");

    /* poll and select */
    CHECK(send(s, "x", 1, 0) == 1);
    struct pollfd pf = {c, POLLIN, 0};
    CHECK(poll(&pf, 1, 5000) == 1 && (pf.revents & POLLIN));
    fd_set rs; FD_ZERO(&rs); FD_SET(c, &rs);
    struct timeval tv = {5, 0};
    CHECK(select(c + 1, &rs, NULL, NULL, &tv) == 1 && FD_ISSET(c, &rs));
    CHECK(recv(c, b, 1, 0) == 1);
    pf.revents = 0; CHECK(poll(&pf, 1, 0) == 0);
    printf("poll, select ok\n");

    /* options */
    struct timeval to = {1, 500000}, got; socklen_t gl = sizeof got;
    CHECK(setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &to, sizeof to) == 0);
    CHECK(getsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &got, &gl) == 0 && got.tv_sec == 1 && got.tv_usec / 1000 == 500);
    int type = 0; gl = sizeof type; CHECK(getsockopt(s, SOL_SOCKET, SO_TYPE, &type, &gl) == 0 && type == SOCK_STREAM);
    CHECK(setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one) == 0);
    printf("options ok\n");

    /* end of stream */
    CHECK(shutdown(s, SHUT_WR) == 0);
    CHECK(wait_kq(kq, c, EVFILT_READ, 5000, &ev) == 1 && (ev.flags & EV_EOF));
    CHECK(read(c, b, sizeof b) == 0);
    close(s); close(c); close(ls);
    printf("shutdown, EOF ok\n");

    /* UDP */
    int u1 = socket(AF_INET, SOCK_DGRAM, 0), u2 = socket(AF_INET, SOCK_DGRAM, 0); CHECK(u1 >= 0 && u2 >= 0);
    struct sockaddr_in ua = {0}; ua.sin_len = sizeof ua; ua.sin_family = AF_INET; ua.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(u1, (struct sockaddr *)&ua, sizeof ua) == 0);
    sl = sizeof ua; CHECK(getsockname(u1, (struct sockaddr *)&ua, &sl) == 0);
    CHECK(sendto(u2, "datagram", 8, 0, (struct sockaddr *)&ua, sizeof ua) == 8);
    struct sockaddr_in from; socklen_t fl = sizeof from;
    CHECK(recvfrom(u1, b, sizeof b, 0, (struct sockaddr *)&from, &fl) == 8 && !memcmp(b, "datagram", 8));
    CHECK(fl == sizeof from && from.sin_addr.s_addr == htonl(INADDR_LOOPBACK) && from.sin_port != 0);
    close(u1); close(u2);
    printf("udp ok\n");

    /* socketpair */
    int sv[2]; CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0);
    CHECK(write(sv[0], "hi", 2) == 2 && read(sv[1], b, 2) == 2 && !memcmp(b, "hi", 2));
    CHECK(write(sv[1], "yo", 2) == 2 && read(sv[0], b, 2) == 2 && !memcmp(b, "yo", 2));
    close(sv[0]); close(sv[1]);
    printf("socketpair ok\n");

    /* IPv6, if the host has it */
    int l6 = socket(AF_INET6, SOCK_STREAM, 0);
    struct sockaddr_in6 s6 = {0}; s6.sin6_len = sizeof s6; s6.sin6_family = AF_INET6; s6.sin6_addr = in6addr_loopback;
    if (l6 >= 0 && bind(l6, (struct sockaddr *)&s6, sizeof s6) == 0) {
        sl = sizeof s6; CHECK(listen(l6, 1) == 0 && getsockname(l6, (struct sockaddr *)&s6, &sl) == 0 && s6.sin6_family == AF_INET6);
        int c6 = socket(AF_INET6, SOCK_STREAM, 0); CHECK(c6 >= 0 && connect(c6, (struct sockaddr *)&s6, sizeof s6) == 0);
        int a6s = accept(l6, NULL, NULL); CHECK(a6s >= 0 && send(c6, "6", 1, 0) == 1 && recv(a6s, b, 1, 0) == 1 && b[0] == '6');
        close(c6); close(a6s);
        printf("ipv6 ok\n");
    } else printf("ipv6 unavailable\n");
    if (l6 >= 0) close(l6);

    /* errors */
    int bad = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in closed = sa; closed.sin_port = 0;
    CHECK(connect(bad, (struct sockaddr *)&closed, sizeof closed) < 0);
    close(bad);
    close(kq);
    printf("NET OK\n");
    return 0;
}
