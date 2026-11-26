/* hostcalls.h — the only boundary between the Mach-O world (guest libSystem)
 * and the host (Windows today, Linux later).
 * Rule: every hostcall is  int64_t fn(up to 6 integer/pointer args).
 * No floats, no varargs, no structs by value -> one generic thunk serves x86_64
 * (ms_abi call) and arm64 (svc #n under the JIT).
 * Errors are returned as -errno (Darwin errno values). */
#pragma once
#include <stdint.h>

#define HOSTCALLS(X)                                                        \
    X(write)      /* fd, buf, n                       */                    \
    X(read)       /* fd, buf, n                       */                    \
    X(pread)      /* fd, buf, n, off                  */                    \
    X(open)       /* dirfd, path, flags, mode -> fd   */                    \
    X(close)      /* fd                               */                    \
    X(lseek)      /* fd, off, whence                  */                    \
    X(stat)       /* dirfd, path, struct dstat*, flags (path==0: fstat dirfd) */ \
    X(dup)        /* fd, newfd(-1 = any)              */                    \
    X(getcwd)     /* buf, size                        */                    \
    X(mkdir)      /* path, mode                       */                    \
    X(unlink)     /* path, isdir                      */                    \
    X(readdir)    /* fd, struct ddirent*  -> 1 entry, 0 end */              \
    X(isatty)     /* fd                               */                    \
    X(mmap)       /* addr, len, prot, flags, fd, off  */                    \
    X(munmap)     /* addr, len                        */                    \
    X(mprotect)   /* addr, len, prot                  */                    \
    X(exit)       /* code                             */                    \
    X(getpid)     /*                                  */                    \
    X(thread)     /* start, arg, stacksize -> 0       */                    \
    X(self)       /* -> struct gthread* of the caller */                    \
    X(sleep)      /* ns                               */                    \
    X(lock)       /* srwlock*, op (0 lock,1 unlock,2 trylock, 3 shared lock, 4 shared unlock, 5 shared trylock) */            \
    X(cond)       /* cv*, srwlock*, op(0 wait,1 signal,2 broadcast), timeout_ns (-1 inf) */ \
    X(clock)      /* kind 0 realtime, 1 monotonic -> ns */                  \
    X(random)     /* buf, n                           */                    \
    X(ncpu)       /*                                  */                    \
    X(kqueue)     /*                                  */                    \
    X(kevent)     /* kq, changes, nch, events, nev, timeout_ns (-1 inf) */  \
    X(log)        /* msg (debug trace to stderr)      */                    \
    X(join)       /* struct gthread*                  */                    \
    X(chdir)      /* path                             */                    \
    X(ftruncate)  /* fd, len                          */                    \
    X(rename)     /* from, to                         */                    \
    X(realpath)   /* path, out[1024]                  */                    \
    X(pipe)       /* int fds[2]                       */                    \
    X(math)       /* op, a, b, c (IEEE-754 bit patterns) -> bits */     \
    X(sigaction)  /* sig, const dsigaction*, dsigaction* old            */ \
    X(sigaltstack)/* const dstack*, dstack* old                         */ \
    X(tkill)      /* struct gthread*, sig  (asynchronous, other threads) */ \
    X(sigreturn)  /* ucontext* (x86_64 trampoline only)                 */ \
    X(safecopy)   /* dst, src, n, need_writable_dst -> 0 / -errno (never faults) */ \
    X(thread_ctl) /* port, op (0 suspend, 1 resume, 2 get_state, 3 set_state), flavor, state* */ \
    X(dl)         /* op (0 dlopen path|0, 1 dlsym handle name, 2 dladdr addr Dl_info*, 3 last error buf n) */ \
    X(link)       /* symbolic, from, to                                  */ \
    X(futex)      /* addr(u32*), op (0 wait if *addr==val, 1 wake one, 2 wake all), val, timeout_ns (-1 inf) -> 0 / -ETIMEDOUT */ \
    X(icache)     /* addr, len: guest code changed (sys_icache_invalidate / __clear_cache) */ \
    X(alias)      /* dst (0 = anywhere), len, src, fixed, int *cur_prot -> dst / -errno: vm_remap(copy=FALSE), arm64 only */ \
    X(metal)      /* op, a, b, c, d, e -> see metal/mtlbridge.h (forwarded to scion-metal.dll) */ \
    X(ui)         /* op, a, b, c, d, e -> see uibridge.h (windows, events, menus, controllers, sound) */ \
    X(xattr)      /* op (0 get, 1 set, 2 remove, 3 list), fd (path == 0) , path, name, buf, size -> bytes / -errno */ \
    X(net)        /* op, a, b, c, d, e -> sockets, name resolution, poll: see NET_* (net.cpp) */

enum {
#define HC_ENUM(n) HC_##n,
    HOSTCALLS(HC_ENUM)
#undef HC_ENUM
    HC_COUNT
};

/* Per-thread block. arm64: TPIDRRO_EL0 points here (Darwin TSD layout: slot k at +8k).
 * x86_64: reachable through HC_self. */
struct gthread {
    uint64_t tsd[512];
    int err;            /* errno */
    int in_handler;     /* x86_64: signal frames not yet sigreturn'ed (async signals wait while > 0) */
    uint64_t tid;
    uint64_t handle;    /* host thread handle (pthread_join) */
    uint64_t stack_top, stack_size;
    uint64_t alt_sp, alt_size; int32_t alt_flags, pad2; /* sigaltstack */
    uint64_t host;      /* host-private (arm64: ArmEnv*) */
    uint32_t port, pad3; /* mach thread port */
};
enum { D_THREAD_SUSPEND, D_THREAD_RESUME, D_THREAD_GET_STATE, D_THREAD_SET_STATE };
enum { D_x86_THREAD_STATE64 = 4, D_ARM_THREAD_STATE64 = 6, D_ARM_NEON_STATE64 = 17 };
/* ARM_THREAD_STATE64 payload (272 bytes, count 68) */
struct darm_state { uint64_t x[29], fp, lr, sp, pc; uint32_t cpsr, pad; };
struct darm_neon { uint64_t v[64]; uint32_t fpsr, fpcr; uint64_t pad; };   /* arm_neon_state64_t: 528 bytes */

/* Darwin signal ABI */
struct dsigaction { uint64_t handler; uint32_t mask; int32_t flags; };
struct dstack { uint64_t sp, size; int32_t flags, pad; };
struct dsiginfo { int32_t signo, err, code, pid, uid, status; uint64_t addr, value, band, pad[7]; };          /* 104 */
struct ducontext { int32_t onstack; uint32_t sigmask; struct dstack stack; uint64_t link, mcsize, mcontext; }; /* 56 */
struct dmcontext_x86 { uint16_t trapno, cpu; uint32_t err; uint64_t faultvaddr;
                       uint64_t rax, rbx, rcx, rdx, rdi, rsi, rbp, rsp, r8, r9, r10, r11, r12, r13, r14, r15, rip, rflags, cs, fs, gs;
                       uint8_t fs_state[524]; };
struct dmcontext_arm { uint64_t faddr; uint32_t esr, exception;
                       uint64_t x[29], fp, lr, sp, pc; uint32_t cpsr, pad;
                       uint64_t v[64]; uint32_t fpsr, fpcr; uint64_t pad2; };
enum { D_SIGILL = 4, D_SIGTRAP = 5, D_SIGABRT = 6, D_SIGFPE = 8, D_SIGBUS = 10, D_SIGSEGV = 11, D_SIGURG = 16,
       D_SA_ONSTACK = 1, D_SA_RESETHAND = 4, D_SA_SIGINFO = 0x40, D_SS_ONSTACK = 1, D_SS_DISABLE = 4 };
static inline int dsig_default_ignored(int s) { return s == 16 || s == 19 || s == 20 || s == 28 || s == 29; }

/* HC_math operations (double unless noted) */
enum { M_SIN, M_COS, M_TAN, M_ASIN, M_ACOS, M_ATAN, M_ATAN2, M_SINH, M_COSH, M_TANH, M_ASINH, M_ACOSH, M_ATANH,
       M_EXP, M_EXPM1, M_LOG, M_LOG10, M_LOG1P, M_LOG2, M_POW, M_CBRT, M_HYPOT, M_FMOD, M_FMA, M_EXP2,
       M_ERF, M_ERFC, M_TGAMMA, M_LGAMMA, M_J0, M_J1, M_JN, M_Y0, M_Y1, M_YN };

/* Darwin struct stat64 (144 bytes), also struct stat on arm64. */
struct dstat {
    int32_t dev; uint16_t mode, nlink; uint64_t ino; uint32_t uid, gid; int32_t rdev, pad0;
    int64_t atime, atime_ns, mtime, mtime_ns, ctime, ctime_ns, btime, btime_ns;
    int64_t size, blocks; int32_t blksize; uint32_t flags, gen; int32_t lspare; int64_t qspare[2];
};

/* Darwin struct dirent (64-bit inode variant). */
struct ddirent {
    uint64_t ino, seekoff; uint16_t reclen, namlen; uint8_t type; char name[1024]; uint8_t pad[3];
};

/* Darwin struct kevent (64-bit). */
struct dkevent { uint64_t ident; int16_t filter; uint16_t flags; uint32_t fflags; int64_t data; uint64_t udata; };

/* HC_net operations. Everything crossing is Darwin's: socket domains, types, options, flags, sockaddrs, errnos. */
enum {
    NET_SOCKET,     /* domain, type, protocol -> fd */
    NET_SOCKETPAIR, /* domain, type, protocol, int fds[2] */
    NET_CONNECT,    /* fd, sockaddr, len */
    NET_BIND,       /* fd, sockaddr, len */
    NET_LISTEN,     /* fd, backlog */
    NET_ACCEPT,     /* fd, sockaddr out (or 0), uint32_t *len -> fd */
    NET_SEND,       /* fd, struct dnetio * -> bytes */
    NET_RECV,       /* fd, struct dnetio * (addrlen updated) -> bytes */
    NET_SHUTDOWN,   /* fd, how */
    NET_GETSOCKOPT, /* fd, level, name, value, uint32_t *len */
    NET_SETSOCKOPT, /* fd, level, name, value, len */
    NET_SOCKNAME,   /* fd, sockaddr out, uint32_t *len, peer (getpeername) */
    NET_RESOLVE,    /* node, service, struct dnethints *, struct dnetai *out, max -> count / -(1000 + EAI_x) */
    NET_NAMEINFO,   /* struct dnetni * -> 0 / EAI_x */
    NET_POLL,       /* struct dpollfd *, n, timeout_ns (-1 inf) -> ready */
    NET_FLAGS,      /* fd, set (-1: get), Darwin O_ flags (only O_NONBLOCK changes) -> flags */
    NET_NREAD,      /* fd -> bytes ready to read (FIONREAD) */
    /* HTTP(S) for URLSession, on the host's HTTP stack (http.cpp: WinHTTP, libcurl), which follows redirects, speaks
     * TLS with the host's certificates, uses the host's proxy settings and decompresses bodies. Errors are
     * NSURLErrorDomain codes (< 0). */
    NET_HTTP_NEW = 100, /* struct dhttpreq * -> handle */
    NET_HTTP_SEND,  /* handle, struct dhttpreq * -> 0 once the final response's headers are in (status, headers, url) */
    NET_HTTP_READ,  /* handle, buf, n -> bytes of the (decoded) body, 0 at its end */
    NET_HTTP_CANCEL,/* handle: a SEND or READ blocked on it in another thread returns NSURLErrorCancelled */
    NET_HTTP_CLOSE, /* handle */
};
struct dnetio { uint64_t buf, len; int32_t flags; uint32_t addrlen; uint64_t addr; };   /* send(to), recv(from) */
struct dnethints { int32_t flags, family, socktype, protocol; uint64_t canon, canonlen; };
struct dnetai { int32_t family, socktype, protocol; uint32_t addrlen; uint8_t addr[28]; uint8_t pad[4]; };
struct dnetni { uint64_t addr; uint32_t addrlen; int32_t flags; uint64_t host, hostlen, serv, servlen; };
struct dpollfd { int32_t fd; int16_t events, revents; };
struct dhttpreq {
    uint64_t method, url, headers;  /* C strings; headers: "Name: value\r\n" lines */
    uint64_t body, body_len;
    int64_t timeout_ms;             /* no progress for that long: NSURLErrorTimedOut */
    int32_t status, pad;            /* out (SEND): the status, the headers ("Name: value\r\n" lines, cut at the */
    uint64_t resp_headers, resp_headers_cap, final_url, final_url_cap;   /* capacity), the URL after redirects */
};

/* Darwin ABI values used by both sides. */
enum {
    D_EPERM = 1, D_ENOENT = 2, D_EINTR = 4, D_EIO = 5, D_EBADF = 9, D_ENOMEM = 12, D_EACCES = 13, D_EFAULT = 14,
    D_EEXIST = 17, D_ENOTDIR = 20, D_EISDIR = 21, D_EINVAL = 22, D_EMFILE = 24, D_ENOTTY = 25,
    D_ESPIPE = 29, D_EAGAIN = 35, D_ENOTSOCK = 38, D_EAFNOSUPPORT = 47, D_ETIMEDOUT = 60,
    D_ELOOP = 62, D_ENAMETOOLONG = 63, D_ENOTEMPTY = 66, D_ENOSYS = 78,
    D_O_WRONLY = 1, D_O_RDWR = 2, D_O_NONBLOCK = 4, D_O_APPEND = 8, D_O_NOFOLLOW = 0x100,
    D_O_CREAT = 0x200, D_O_TRUNC = 0x400, D_O_EXCL = 0x800, D_O_DIRECTORY = 0x100000, D_O_CLOEXEC = 0x1000000,
    D_PROT_READ = 1, D_PROT_WRITE = 2, D_PROT_EXEC = 4,
    D_MAP_SHARED = 1, D_MAP_PRIVATE = 2, D_MAP_FIXED = 0x10, D_MAP_ANON = 0x1000,
    D_AT_FDCWD = -2, D_AT_SYMLINK_NOFOLLOW = 0x20,
    D_S_IFIFO = 0010000, D_S_IFCHR = 0020000, D_S_IFDIR = 0040000, D_S_IFREG = 0100000, D_S_IFLNK = 0120000,
    D_DT_DIR = 4, D_DT_REG = 8, D_DT_LNK = 10,
    D_EVFILT_READ = -1, D_EVFILT_WRITE = -2, D_EVFILT_USER = -10,
    D_EV_ADD = 1, D_EV_DELETE = 2, D_EV_ENABLE = 4, D_EV_DISABLE = 8, D_EV_ONESHOT = 0x10, D_EV_CLEAR = 0x20,
    D_EV_RECEIPT = 0x40, D_EV_DISPATCH = 0x80, D_EV_ERROR = 0x4000, D_EV_EOF = 0x8000, D_NOTE_TRIGGER = 0x1000000,
    D_EPIPE = 32, D_EINPROGRESS = 36, D_EALREADY = 37, D_ENOPROTOOPT = 42, D_EOPNOTSUPP = 45, D_ECONNRESET = 54,
    D_ENOTCONN = 57, D_ECONNREFUSED = 61, D_S_IFSOCK = 0140000,
};
