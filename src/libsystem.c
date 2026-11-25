/* libsystem.c — scion's libSystem.B.dylib (Mach-O, Darwin ABI, x86_64 + arm64).
 * Runs inside the Mach-O world; everything that touches the OS goes through hostcalls.
 * Functions are added on demand by real binaries' imports (Wine-style), see docs/compatibility.md. */
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include "hostcalls.h"

#ifdef __x86_64__
#define HCABI __attribute__((ms_abi))
#else
#define HCABI
#endif
typedef int64_t (HCABI *hcfn)(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);
hcfn scion_hc[HC_COUNT]; /* filled by the loader */

#define H(...) H_(__VA_ARGS__, 0, 0, 0, 0, 0, 0)
#define H_(n, a, b, c, d, e, f, ...) \
    scion_hc[HC_##n]((int64_t)(a), (int64_t)(b), (int64_t)(c), (int64_t)(d), (int64_t)(e), (int64_t)(f))

typedef int64_t ssize_t;
typedef int64_t off_t;
struct timespec { int64_t tv_sec, tv_nsec; };

int snprintf(char *, size_t, const char *, ...); int strncmp(const char *, const char *, size_t); void abort(void);
void *malloc(size_t); void free(void *);
static struct gthread *self(void) { return (struct gthread *)H(self); }
int *__error(void) { return &self()->err; }
static int64_t ret(int64_t r) { if (r < 0) { self()->err = (int)-r; return -1; } return r; }
static int fail(int e) { self()->err = e; return -1; }

/* ---------- string / memory (clang may emit calls to these) ---------- */
void *memcpy(void *d, const void *s, size_t n) { char *a = d; const char *b = s; while (n--) *a++ = *b++; return d; }
void *memmove(void *d, const void *s, size_t n) {
    char *a = d; const char *b = s;
    if (a < b) while (n--) *a++ = *b++; else while (n--) a[n] = b[n];
    return d;
}
void *memset(void *d, int c, size_t n) { char *a = d; while (n--) *a++ = (char)c; return d; }
int memcmp(const void *x, const void *y, size_t n) {
    const unsigned char *a = x, *b = y;
    for (; n; n--, a++, b++) if (*a != *b) return *a - *b;
    return 0;
}
size_t strlen(const char *s) { const char *p = s; while (*p) p++; return (size_t)(p - s); }
int strcmp(const char *a, const char *b) { while (*a && *a == *b) a++, b++; return (unsigned char)*a - (unsigned char)*b; }

/* ---------- files ---------- */
ssize_t write(int fd, const void *b, size_t n) { return ret(H(write, fd, b, n)); }
ssize_t read(int fd, void *b, size_t n) { return ret(H(read, fd, b, n)); }
ssize_t pread(int fd, void *b, size_t n, off_t o) { return ret(H(pread, fd, b, n, o)); }
int openat(int dirfd, const char *p, int fl, ...) {
    va_list ap; va_start(ap, fl); int mode = (fl & D_O_CREAT) ? va_arg(ap, int) : 0; va_end(ap);
    return (int)ret(H(open, dirfd, p, fl, mode));
}
int open(const char *p, int fl, ...) {
    va_list ap; va_start(ap, fl); int mode = (fl & D_O_CREAT) ? va_arg(ap, int) : 0; va_end(ap);
    return (int)ret(H(open, D_AT_FDCWD, p, fl, mode));
}
int close(int fd) { return (int)ret(H(close, fd)); }
int close_nocancel(int fd) __asm__("_close$NOCANCEL");
int close_nocancel(int fd) { return close(fd); }
off_t lseek(int fd, off_t o, int w) { return ret(H(lseek, fd, o, w)); }
int dup(int fd) { return (int)ret(H(dup, fd, -1)); }
int dup2(int a, int b) { return (int)ret(H(dup, a, b)); }
int fstatat(int dfd, const char *p, struct dstat *st, int fl) { return (int)ret(H(stat, dfd, p, st, fl)); }
int stat(const char *p, struct dstat *st) { return fstatat(D_AT_FDCWD, p, st, 0); }
int faccessat(int dirfd, const char *p, int mode, int flags) {
    struct dstat st;
    if (fstatat(dirfd, p, &st, flags & D_AT_SYMLINK_NOFOLLOW)) return -1;
    if (((mode & 2) && !(st.mode & 0222)) || ((mode & 1) && !(st.mode & 0111))) { *__error() = D_EACCES; return -1; }
    return 0;
}
int64_t _scion_metal(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e) { return H(metal, op, a, b, c, d, e); } /* Metal.framework -> host */
int64_t _scion_ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e) { return H(ui, op, a, b, c, d, e); } /* AppKit, GameController, AudioToolbox -> host */
int fsync(int fd) { return 0; }   /* ponytail: writes go straight to the OS; no explicit flush */
int access(const char *p, int mode) { return faccessat(D_AT_FDCWD, p, mode, 0); }
int lstat(const char *p, struct dstat *st) { return fstatat(D_AT_FDCWD, p, st, D_AT_SYMLINK_NOFOLLOW); }
int fstat(int fd, struct dstat *st) { return (int)ret(H(stat, fd, 0, st, 0)); }
/* x86_64 SDK names for the 64-bit-inode variants (same struct) */
int stat64(const char *p, struct dstat *st) { return stat(p, st); }
int lstat64(const char *p, struct dstat *st) { return lstat(p, st); }
int fstat64(int fd, struct dstat *st) { return fstat(fd, st); }
int fstatat64(int d, const char *p, struct dstat *st, int f) { return fstatat(d, p, st, f); }
int stat_i(const char *p, struct dstat *st) __asm__("_stat$INODE64");
int stat_i(const char *p, struct dstat *st) { return stat(p, st); }
int lstat_i(const char *p, struct dstat *st) __asm__("_lstat$INODE64");
int lstat_i(const char *p, struct dstat *st) { return lstat(p, st); }
int fstat_i(int fd, struct dstat *st) __asm__("_fstat$INODE64");
int fstat_i(int fd, struct dstat *st) { return fstat(fd, st); }
int fstatat_i(int d, const char *p, struct dstat *st, int f) __asm__("_fstatat$INODE64");
int fstatat_i(int d, const char *p, struct dstat *st, int f) { return fstatat(d, p, st, f); }
char *getcwd(char *b, size_t n) { return ret(H(getcwd, b, n)) < 0 ? 0 : b; }
int mkdir(const char *p, int mode) { return (int)ret(H(mkdir, p, mode)); }
int rename(const char *a, const char *b);
/* *at() on top of the path calls: a relative path under a directory descriptor is joined to that directory's path */
static const char *at_path(int dfd, const char *p, char *buf) {
    if (dfd == D_AT_FDCWD || !p || p[0] == '/') return p;
    char dir[1024];
    if (ret(H(realpath, 0, dir, dfd)) < 0) return 0;
    snprintf(buf, 2100, "%s/%s", dir, p);
    return buf;
}
int mkdirat(int dfd, const char *p, int mode) { char b[2100]; const char *q = at_path(dfd, p, b); return q ? mkdir(q, mode) : -1; }
int renameat(int fa, const char *a, int fb, const char *b) {
    char x[2100], y[2100]; const char *p = at_path(fa, a, x), *q = at_path(fb, b, y);
    return p && q ? rename(p, q) : -1;
}
/* ponytail: pwrite moves the file position and restores it (not atomic against other threads on the same descriptor) */
ssize_t pwrite(int fd, const void *b, size_t n, off_t o) {
    off_t cur = lseek(fd, 0, 1);
    if (cur < 0 || lseek(fd, o, 0) < 0) return -1;
    ssize_t w = write(fd, b, n);
    lseek(fd, cur, 0);
    return w;
}
int rmdir(const char *p) { return (int)ret(H(unlink, p, 1, D_AT_FDCWD)); }
int unlink(const char *p) { return (int)ret(H(unlink, p, 0, D_AT_FDCWD)); }
int chmod(const char *p, int m) { return 0; }
ssize_t readlink(const char *p, char *b, size_t n) { return fail(D_EINVAL); } /* ponytail: no symlinks on the host side yet */

/* DIR* is opaque to callers: we hand out fd+1 */
typedef struct DIR DIR;
DIR *fdopendir(int fd) { return (DIR *)(intptr_t)(fd + 1); }
DIR *fdopendir_ino64(int fd) __asm__("_fdopendir$INODE64");
DIR *fdopendir_ino64(int fd) { return fdopendir(fd); }
int readdir_r(DIR *d, struct ddirent *e, struct ddirent **res) {
    int64_t r = H(readdir, (intptr_t)d - 1, e);
    if (r < 0) return (int)-r;
    *res = r ? e : 0;
    return 0;
}
int readdir_r_ino64(DIR *d, struct ddirent *e, struct ddirent **res) __asm__("_readdir_r$INODE64");
int readdir_r_ino64(DIR *d, struct ddirent *e, struct ddirent **res) { return readdir_r(d, e, res); }
static struct ddirent *dir_bufs[4096]; /* readdir's per-DIR entry (callers may hold a pointer across other readdirs) */
int closedir(DIR *d) {
    int fd = (int)((intptr_t)d - 1);
    if (fd >= 0 && fd < 4096 && dir_bufs[fd]) { free(dir_bufs[fd]); dir_bufs[fd] = 0; }
    return close(fd);
}
struct ddirent *readdir(DIR *d) {
    int fd = (int)((intptr_t)d - 1); struct ddirent *e, *r;
    if (fd < 0 || fd >= 4096) { self()->err = D_EBADF; return 0; }
    if (!dir_bufs[fd]) dir_bufs[fd] = malloc(sizeof(struct ddirent));
    e = dir_bufs[fd];
    return readdir_r(d, e, &r) ? 0 : r;
}
struct ddirent *readdir_i64(DIR *d) __asm__("_readdir$INODE64");
struct ddirent *readdir_i64(DIR *d) { return readdir(d); }
int dirfd(DIR *d) { return (int)((intptr_t)d - 1); }
DIR *opendir(const char *p) { int fd = open(p, D_O_DIRECTORY); return fd < 0 ? 0 : fdopendir(fd); }
DIR *opendir_i(const char *p) __asm__("_opendir$INODE64");
DIR *opendir_i(const char *p) { return opendir(p); }

enum { F_DUPFD = 0, F_GETFD = 1, F_SETFD = 2, F_GETFL = 3, F_SETFL = 4, F_DUPFD_CLOEXEC = 0x43 };
int fcntl(int fd, int cmd, ...) {
    switch (cmd) {
    case F_DUPFD: case F_DUPFD_CLOEXEC: return dup(fd);
    case F_GETFD: case F_SETFD: return 0;
    case F_SETFL: { va_list ap; va_start(ap, cmd); int fl = va_arg(ap, int); va_end(ap); return ret(H(net, NET_FLAGS, fd, fl)) < 0 ? -1 : 0; }
    case 7: case 8: case 9:                   /* F_GETLK / F_SETLK / F_SETLKW: no advisory locks (ponytail) */
    case 44: case 45: case 48: case 73: case 74: return 0;   /* F_RDADVISE, F_RDAHEAD, F_NOCACHE, F_SETNOSIGPIPE, F_GETNOSIGPIPE: hints */
    case 51: case 85: return fsync(fd);       /* F_FULLFSYNC, F_BARRIERFSYNC */
    case F_GETFL: return (int)ret(H(net, NET_FLAGS, fd, -1));
    case 50: { /* F_GETPATH */ va_list ap; va_start(ap, cmd); char *buf = va_arg(ap, char *); va_end(ap); return (int)ret(H(realpath, 0, buf, fd)); }
    }
    return fail(D_EINVAL);
}
#define TIOCGETA 0x40487413ul
int ioctl(int fd, unsigned long req, ...) {
    va_list ap; va_start(ap, req); void *p = va_arg(ap, void *); va_end(ap);
    if (req == TIOCGETA) { if (!H(isatty, fd)) return fail(D_ENOTTY); memset(p, 0, 72); return 0; }
    if (req == 0x8004667eul) { int64_t r = ret(H(net, NET_FLAGS, fd, *(int *)p ? D_O_NONBLOCK : 0)); return r < 0 ? -1 : 0; }   /* FIONBIO */
    if (req == 0x4004667ful) { int64_t r = ret(H(net, NET_NREAD, fd)); if (r < 0) return -1; *(int *)p = (int)r; return 0; }  /* FIONREAD */
    return fail(D_ENOTTY);
}

/* ---------- memory ---------- */
void *mmap(void *a, size_t n, int prot, int fl, int fd, off_t off) {
    int64_t r = H(mmap, a, n, prot, fl, fd, off);
    return r < 0 && r > -4096 ? (ret(r), (void *)-1) : (void *)r;
}
int munmap(void *a, size_t n) { return (int)ret(H(munmap, a, n)); }
int mprotect(void *a, size_t n, int p) { return (int)ret(H(mprotect, a, n, p)); }
int madvise(void *a, size_t n, int adv) { return 0; }
int mlock(const void *a, size_t n) { return 0; }

/* ---------- process / time ---------- */
void _exit(int c) { H(exit, c); for (;;) ; }
/* atexit and __cxa_atexit share one list, run in reverse order by exit() */
static struct { void (*fn)(void *); void *arg; } cxa_fns[256]; static int ncxa;
int __cxa_atexit(void (*f)(void *), void *arg, void *dso) { if (ncxa >= 256) return -1; cxa_fns[ncxa].fn = f; cxa_fns[ncxa].arg = arg; ncxa++; return 0; }
void __cxa_finalize(void *dso) { }
int __cxa_thread_atexit_impl(void (*f)(void *), void *o, void *dso) { return 0; } /* ponytail: thread_local destructors are not run */
static void call_noarg(void *f) { ((void (*)(void))f)(); }
void exit(int c) { while (ncxa) { ncxa--; cxa_fns[ncxa].fn(cxa_fns[ncxa].arg); } _exit(c); }
int getpid(void) { return (int)H(getpid); }
int issetugid(void) { return 0; }
void arc4random_buf(void *b, size_t n) { H(random, b, n); }
/* uuid (RFC 4122 version 4) */
void uuid_generate_random(unsigned char u[16]) { arc4random_buf(u, 16); u[6] = (u[6] & 0x0f) | 0x40; u[8] = (u[8] & 0x3f) | 0x80; }
void uuid_generate(unsigned char u[16]) { uuid_generate_random(u); }
void uuid_clear(unsigned char u[16]) { for (int i = 0; i < 16; i++) u[i] = 0; }
int uuid_is_null(const unsigned char u[16]) { for (int i = 0; i < 16; i++) if (u[i]) return 0; return 1; }
int uuid_compare(const unsigned char a[16], const unsigned char b[16]) { for (int i = 0; i < 16; i++) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1; return 0; }
void uuid_copy(unsigned char d[16], const unsigned char s[16]) { for (int i = 0; i < 16; i++) d[i] = s[i]; }
static void uuid_fmt(const unsigned char u[16], char *out, const char *hex) {
    for (int i = 0, o = 0; i < 16; i++) { if (i == 4 || i == 6 || i == 8 || i == 10) out[o++] = '-'; out[o++] = hex[u[i] >> 4]; out[o++] = hex[u[i] & 15]; out[o] = 0; }
}
void uuid_unparse_upper(const unsigned char u[16], char *out) { uuid_fmt(u, out, "0123456789ABCDEF"); }
void uuid_unparse_lower(const unsigned char u[16], char *out) { uuid_fmt(u, out, "0123456789abcdef"); }
void uuid_unparse(const unsigned char u[16], char *out) { uuid_unparse_upper(u, out); }
int uuid_parse(const char *s, unsigned char u[16]) {
    for (int i = 0, k = 0; i < 36; i++) {
        if (i == 8 || i == 13 || i == 18 || i == 23) { if (s[i] != '-') return -1; continue; }
        char c = s[i]; int v = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (v < 0) return -1;
        if (k & 1) u[k >> 1] |= (unsigned char)v; else u[k >> 1] = (unsigned char)(v << 4);
        k++;
    }
    return s[36] ? -1 : 0;
}
uint64_t mach_absolute_time(void) { return (uint64_t)H(clock, 1); }
int mach_timebase_info(uint32_t *tb) { tb[0] = tb[1] = 1; return 0; }
/* Darwin clock ids: 0 REALTIME, 12 PROCESS_CPUTIME_ID, 16 THREAD_CPUTIME_ID, the rest monotonic */
static int clock_kind(int clk) { return clk == 0 ? 0 : clk == 16 ? 2 : clk == 12 ? 3 : 1; }
int clock_gettime(int clk, struct timespec *ts) {
    int64_t ns = H(clock, clock_kind(clk));
    ts->tv_sec = ns / 1000000000; ts->tv_nsec = ns % 1000000000;
    return 0;
}
int usleep(uint32_t us) { H(sleep, (int64_t)us * 1000); return 0; }
unsigned sleep(unsigned s) { H(sleep, (int64_t)s * 1000000000); return 0; }
uint64_t clock_gettime_nsec_np(int clk) { return (uint64_t)H(clock, clock_kind(clk)); }
int getpagesize(void);
int flock(int fd, int op) { return 0; } /* ponytail: one process per data directory, nothing to lock against */
struct rlimit { uint64_t cur, max; };
int getrlimit(int r, struct rlimit *l) { l->cur = 256; l->max = 0x7fffffffffffffffull; return 0; }
int setrlimit(int r, const struct rlimit *l) { return 0; }
int getrusage(int who, void *ru) { memset(ru, 0, 144); return 0; }

enum { CTL_KERN = 1, CTL_HW = 6, KERN_OSRELEASE = 2, HW_NCPU = 3, HW_PAGESIZE = 7 };
#ifdef __x86_64__
#define PAGE 4096
#else
#define PAGE 16384
#endif
static int sysout(void *old, size_t *oldlen, const void *v, size_t n) {
    if (old) { if (*oldlen < n) return fail(D_ENOMEM); memcpy(old, v, n); }
    *oldlen = n;
    return 0;
}
int getpagesize(void) { return PAGE; }
int sysctl(int *mib, unsigned n, void *old, size_t *oldlen, void *nw, size_t nwlen) {
    int v;
    if (n == 2 && mib[0] == CTL_HW && mib[1] == HW_NCPU) return v = (int)H(ncpu), sysout(old, oldlen, &v, 4);
    if (n == 2 && mib[0] == CTL_HW && mib[1] == HW_PAGESIZE) return v = PAGE, sysout(old, oldlen, &v, 4);
    if (n == 2 && mib[0] == CTL_KERN && mib[1] == KERN_OSRELEASE) return sysout(old, oldlen, "23.6.0", 7);
    return fail(D_ENOENT);
}
int sysctlbyname(const char *name, void *old, size_t *oldlen, void *nw, size_t nwlen) {
    int v;
    if (!strcmp(name, "kern.osrelease")) return sysout(old, oldlen, "23.6.0", 7);
    if (!strcmp(name, "hw.ncpu") || !strcmp(name, "hw.logicalcpu")) return v = (int)H(ncpu), sysout(old, oldlen, &v, 4);
    if (!strcmp(name, "hw.pagesize")) return v = PAGE, sysout(old, oldlen, &v, 4);
    return fail(D_ENOENT);
}

/* ---------- signals: dispositions live in the host, which delivers faults and cross-thread signals ---------- */
int sigaction(int sig, const struct dsigaction *act, struct dsigaction *old) { return (int)ret(H(sigaction, sig, act, old)); }
int sigaltstack(const struct dstack *ss, struct dstack *old) { return (int)ret(H(sigaltstack, ss, old)); }
int pthread_sigmask(int how, const uint32_t *set, uint32_t *old) { if (old) *old = 0; return 0; } /* ponytail: no masks */
int sigprocmask(int how, const uint32_t *set, uint32_t *old) { return pthread_sigmask(how, set, old); }
int setitimer(int w, const void *v, void *o) { if (o) memset(o, 0, 32); return 0; }
/* synchronous signal to ourselves: run the handler right here with a minimal context */
static int raise_self(int sig) {
    struct dsigaction a;
    if (sig == 0) return 0;
    if (H(sigaction, sig, 0, &a) < 0) return fail(D_EINVAL);
    if (a.handler == 1) return 0;
    if (a.handler == 0) {
        if (dsig_default_ignored(sig)) return 0;
        H(log, sig == D_SIGABRT ? "Abort trap: 6" : "fatal signal without a handler");
        H(exit, 128 + sig);
    }
    struct dsiginfo si; struct ducontext uc; uint64_t mc[128];
    memset(&si, 0, sizeof si); memset(&uc, 0, sizeof uc); memset(mc, 0, sizeof mc);
    si.signo = sig; si.pid = getpid();
    uc.mcsize = sizeof mc; uc.mcontext = (uint64_t)mc;
    ((void (*)(int, void *, void *))a.handler)(sig, &si, &uc);
    return 0;
}
int kill(int pid, int sig) { return pid == 0 || pid == getpid() ? raise_self(sig) : fail(D_EPERM); }
int raise(int sig) { return raise_self(sig); }

/* ---------- pthreads ---------- */
typedef struct gthread *pthread_t;
pthread_t pthread_self(void) { return self(); }
int pthread_equal(pthread_t a, pthread_t b) { return a == b; }
int pthread_attr_init(uint64_t *a) { memset(a, 0, 64); a[1] = 512 * 1024; return 0; }
int pthread_attr_getstacksize(const uint64_t *a, size_t *s) { *s = a[1]; return 0; }
int pthread_attr_setstacksize(uint64_t *a, size_t s) { a[1] = s; return 0; }
int pthread_attr_setdetachstate(uint64_t *a, int d) { return 0; }
int pthread_attr_destroy(uint64_t *a) { return 0; }
/* every thread starts here, so pthread_exit can jump back out of it (TSD slot 120: Apple-reserved, unused here) */
struct tstart { void *(*fn)(void *); void *arg, *ret; uint64_t jb[64]; };
int setjmp(uint64_t *jb) __attribute__((returns_twice)); void longjmp(uint64_t *jb, int v) __attribute__((noreturn));
static int next_key = 256; /* keys below 256 are Apple-reserved TSD slots */
static void (*key_dtor[512])(void *);
static void run_key_dtors(void) { /* as POSIX: up to 4 rounds while destructors set values again */
    uint64_t *tsd = self()->tsd;
    for (int round = 0, again = 1; again && round < 4; round++) {
        again = 0;
        for (int k = 0; k < next_key && k < 512; k++) if (key_dtor[k] && tsd[k]) { void *v = (void *)tsd[k]; tsd[k] = 0; key_dtor[k](v); again = 1; }
    }
}
static void *thread_trampoline(void *p) {
    struct tstart *t = p;
    void *r;
    self()->tsd[120] = (uint64_t)t;
    if (!setjmp(t->jb)) r = t->fn(t->arg); else r = t->ret;
    run_key_dtors();
    self()->tsd[120] = 0;
    free(t);
    return r;
}
void pthread_exit(void *v) {
    struct tstart *t = (struct tstart *)self()->tsd[120];
    if (!t) for (;;) H(sleep, 1000000000); /* the main thread: ponytail: the process should end with the last thread */
    t->ret = v;
    longjmp(t->jb, 1);
}
int pthread_create(pthread_t *t, const uint64_t *a, void *(*start)(void *), void *arg) {
    struct tstart *ts = malloc(sizeof *ts);
    if (!ts) return 12;
    ts->fn = start; ts->arg = arg; ts->ret = 0;
    int64_t r = H(thread, thread_trampoline, ts, a ? a[1] : 512 * 1024);
    if (r < 0) { free(ts); return (int)-r; }
    if (t) *t = (pthread_t)r;
    return 0;
}
int pthread_kill(pthread_t t, int sig) { return t == self() ? raise_self(sig) : (int)-H(tkill, t, sig); }
int pthread_join(pthread_t t, void **res) { if (res) *res = 0; return (int)-H(join, t); }
int pthread_detach(pthread_t t) { return 0; }
int pthread_setname_np(const char *n) { return 0; }
int pthread_threadid_np(pthread_t t, uint64_t *id) { *id = (t ? t : self())->tid; return 0; }
void *pthread_get_stackaddr_np(pthread_t t) { return (void *)t->stack_top; }
size_t pthread_get_stacksize_np(pthread_t t) { return t->stack_size; }
int pthread_key_delete(unsigned long k) { if (k < 512) key_dtor[k] = 0; return 0; }
int pthread_mutexattr_init(uint64_t *a) { memset(a, 0, 16); return 0; }
int pthread_mutexattr_settype(uint64_t *a, int t) { a[1] = (uint64_t)t; return 0; }
int pthread_mutexattr_gettype(const uint64_t *a, int *t) { *t = (int)a[1]; return 0; }
int pthread_mutexattr_destroy(uint64_t *a) { return 0; }
int pthread_cond_timedwait(uint64_t *c, uint64_t *m, const struct timespec *abs) {
    int64_t rel = abs->tv_sec * 1000000000 + abs->tv_nsec - H(clock, 0);
    return (int)-H(cond, c + 1, m + 1, 0, rel < 0 ? 0 : rel);
}
int sched_yield(void) { H(sleep, 0); return 0; }
/* the host lock/condvar live at offset 8, after Darwin's signature word */
/* Darwin pthread_mutex_t is 64 bytes: [0] signature, [1] host SRWLOCK, [2] owner, [3] recursion depth (recursive only) */
#define MTX_SIG_RECURSIVE_INIT 0x32AAABA2ull /* PTHREAD_RECURSIVE_MUTEX_INITIALIZER */
#define MTX_SIG_RECURSIVE 0x4d55545852ull    /* ours: initialized as PTHREAD_MUTEX_RECURSIVE */
int pthread_mutex_init(uint64_t *m, const uint64_t *a) { memset(m, 0, 64); if (a && a[1] == 2) m[0] = MTX_SIG_RECURSIVE; return 0; }
static int mtx_recursive(uint64_t *m) { return m[0] == MTX_SIG_RECURSIVE || m[0] == MTX_SIG_RECURSIVE_INIT; }
int pthread_mutex_lock(uint64_t *m) {
    if (mtx_recursive(m)) {
        uint64_t me = (uint64_t)self();
        if (__atomic_load_n(&m[2], __ATOMIC_RELAXED) == me) { m[3]++; return 0; }
        H(lock, m + 1, 0); __atomic_store_n(&m[2], me, __ATOMIC_RELAXED); m[3] = 1; return 0;
    }
    H(lock, m + 1, 0); return 0;
}
int pthread_mutex_unlock(uint64_t *m) {
    if (mtx_recursive(m)) { if (--m[3]) return 0; __atomic_store_n(&m[2], 0, __ATOMIC_RELAXED); }
    H(lock, m + 1, 1); return 0;
}
int pthread_mutex_trylock(uint64_t *m) {
    if (mtx_recursive(m)) {
        uint64_t me = (uint64_t)self();
        if (__atomic_load_n(&m[2], __ATOMIC_RELAXED) == me) { m[3]++; return 0; }
        if (!H(lock, m + 1, 2)) return 16;
        __atomic_store_n(&m[2], me, __ATOMIC_RELAXED); m[3] = 1; return 0;
    }
    return H(lock, m + 1, 2) ? 0 : 16 /* EBUSY */;
}
/* pthread_rwlock_t (200 bytes): [1] host SRWLOCK, [2] exclusive owner (0 = held shared or free) */
int pthread_rwlock_init(uint64_t *l, const void *a) { memset(l, 0, 200); return 0; }
int pthread_rwlock_destroy(uint64_t *l) { return 0; }
int pthread_rwlock_rdlock(uint64_t *l) { H(lock, l + 1, 3); return 0; }
int pthread_rwlock_tryrdlock(uint64_t *l) { return H(lock, l + 1, 5) ? 0 : 16; }
int pthread_rwlock_wrlock(uint64_t *l) { H(lock, l + 1, 0); l[2] = (uint64_t)self(); return 0; }
int pthread_rwlock_trywrlock(uint64_t *l) { if (!H(lock, l + 1, 2)) return 16; l[2] = (uint64_t)self(); return 0; }
int pthread_rwlock_unlock(uint64_t *l) {
    if (l[2] == (uint64_t)self()) { l[2] = 0; H(lock, l + 1, 1); } else H(lock, l + 1, 4);
    return 0;
}
int pthread_rwlock_rdlock_u(uint64_t *l) __asm__("_pthread_rwlock_rdlock$UNIX2003");
int pthread_rwlock_rdlock_u(uint64_t *l) { return pthread_rwlock_rdlock(l); }
int pthread_rwlock_wrlock_u(uint64_t *l) __asm__("_pthread_rwlock_wrlock$UNIX2003");
int pthread_rwlock_wrlock_u(uint64_t *l) { return pthread_rwlock_wrlock(l); }
int pthread_rwlock_unlock_u(uint64_t *l) __asm__("_pthread_rwlock_unlock$UNIX2003");
int pthread_rwlock_unlock_u(uint64_t *l) { return pthread_rwlock_unlock(l); }
void __assert_rtn(const char *fn, const char *file, int line, const char *expr) {
    char b[512]; snprintf(b, sizeof b, "Assertion failed: (%s), function %s, file %s, line %d.\n", expr, fn, file, line);
    write(2, b, strlen(b)); abort();
}
int pthread_mutex_destroy(uint64_t *m) { return 0; }
int pthread_cond_init(uint64_t *c, const void *a) { memset(c, 0, 48); return 0; }
int pthread_cond_wait(uint64_t *c, uint64_t *m) { H(cond, c + 1, m + 1, 0, -1); return 0; }
int pthread_cond_timedwait_relative_np(uint64_t *c, uint64_t *m, const struct timespec *ts) {
    return (int)-H(cond, c + 1, m + 1, 0, ts->tv_sec * 1000000000 + ts->tv_nsec);
}
int pthread_cond_signal(uint64_t *c) { H(cond, c + 1, 0, 1, 0); return 0; }
int pthread_cond_broadcast(uint64_t *c) { H(cond, c + 1, 0, 2, 0); return 0; }
int pthread_cond_destroy(uint64_t *c) { return 0; }
int pthread_key_create(unsigned long *k, void (*dtor)(void *)) {
    *k = (unsigned long)__atomic_fetch_add(&next_key, 1, __ATOMIC_RELAXED);
    if (*k >= 512) return 35;
    key_dtor[*k] = dtor;
    return 0;
}
/* a reserved (Apple) key below 256 with a destructor: Swift's runtime uses 100..109 */
int pthread_key_init_np(int k, void (*dtor)(void *)) { if (k < 0 || k >= 256) return 22; key_dtor[k] = dtor; return 0; }
int pthread_setspecific(unsigned long k, const void *v) { self()->tsd[k] = (uint64_t)v; return 0; }
void *pthread_getspecific(unsigned long k) { return (void *)self()->tsd[k]; }

/* ---------- kqueue ---------- */
int kqueue(void) { return (int)ret(H(kqueue)); }
int kevent(int kq, const struct dkevent *ch, int nch, struct dkevent *ev, int nev, const struct timespec *ts) {
    return (int)ret(H(kevent, kq, ch, nch, ev, nev, ts ? ts->tv_sec * 1000000000 + ts->tv_nsec : -1));
}

/* ---------- not supported yet: exec ---------- */
int execve(const char *p, char *const a[], char *const e[]) { return fail(D_ENOSYS); }
int sendfile(int fd, int s, off_t o, off_t *len, void *h, int f) { return fail(D_ENOSYS); }

/* ---------- Mach ---------- */
enum { KERN_SUCCESS, KERN_INVALID_ADDRESS, KERN_PROTECTION_FAILURE, KERN_NO_SPACE, KERN_INVALID_ARGUMENT, KERN_FAILURE };
uint32_t mach_task_self_ = 0x203;
#if defined(__arm64__)
uintptr_t vm_page_size = 16384, vm_page_mask = 16383; int vm_page_shift = 14; /* what arm64 macOS reports */
#else
uintptr_t vm_page_size = 4096, vm_page_mask = 4095; int vm_page_shift = 12;
#endif
uint32_t mach_thread_self(void) { return self()->port; }
int pthread_main_np(void) { return self()->port == 0x1000; } /* the first thread registered: the main one */
uint32_t mach_host_self(void) { return 0x303; }
uint32_t pthread_mach_thread_np(struct gthread *t) { return t->port; }
int mach_port_deallocate(uint32_t task, uint32_t port) { return KERN_SUCCESS; }
int mach_vm_allocate(uint32_t task, uint64_t *addr, uint64_t size, int flags) {
    void *p = mmap((flags & 1) ? 0 : (void *)*addr, size, 3, D_MAP_ANON | D_MAP_PRIVATE | ((flags & 1) ? 0 : D_MAP_FIXED), -1, 0);
    if (p == (void *)-1) return KERN_NO_SPACE;
    *addr = (uint64_t)p; return KERN_SUCCESS;
}
int vm_allocate(uint32_t task, uint64_t *addr, uint64_t size, int flags) { return mach_vm_allocate(task, addr, size, flags); }
int mach_vm_deallocate(uint32_t task, uint64_t addr, uint64_t size) { return munmap((void *)addr, size) ? KERN_INVALID_ADDRESS : KERN_SUCCESS; }
int vm_deallocate(uint32_t task, uint64_t addr, uint64_t size) { return mach_vm_deallocate(task, addr, size); }
int mach_vm_protect(uint32_t task, uint64_t addr, uint64_t size, int setmax, int prot) {
    if (setmax) return KERN_SUCCESS; /* ponytail: maximum protections are not tracked */
    return mprotect((void *)addr, size, prot & 7) ? KERN_PROTECTION_FAILURE : KERN_SUCCESS;
}
int vm_protect(uint32_t task, uint64_t addr, uint64_t size, int setmax, int prot) { return mach_vm_protect(task, addr, size, setmax, prot); }
int mach_vm_read_overwrite(uint32_t task, uint64_t addr, uint64_t size, uint64_t data, uint64_t *out) {
    if (H(safecopy, data, addr, size, 0)) return KERN_INVALID_ADDRESS;
    *out = size; return KERN_SUCCESS;
}
int vm_read_overwrite(uint32_t task, uint64_t addr, uint64_t size, uint64_t data, uint64_t *out) { return mach_vm_read_overwrite(task, addr, size, data, out); }
int mach_vm_write(uint32_t task, uint64_t addr, uint64_t data, uint32_t cnt) {
    int64_t r = H(safecopy, addr, data, cnt, 1);
    return r == 0 ? KERN_SUCCESS : r == -D_EACCES ? KERN_PROTECTION_FAILURE : KERN_INVALID_ADDRESS;
}
int vm_write(uint32_t task, uint64_t addr, uint64_t data, uint32_t cnt) { return mach_vm_write(task, addr, data, cnt); }
int mach_vm_remap(uint32_t tt, uint64_t *taddr, uint64_t size, uint64_t mask, int flags, uint32_t st, uint64_t saddr,
                  int copy, int *cur, int *max, int inh) {
    if (!copy) { /* shared alias: arm64 guests only (see hc_alias) */
        int64_t r = H(alias, (flags & 1) ? 0 : *taddr, size, saddr, !(flags & 1), cur);
        if (r < 0) { H(log, "vm_remap without copy: arm64 programs only"); return KERN_FAILURE; }
        *taddr = (uint64_t)r; if (max) *max = 7;
        return KERN_SUCCESS;
    }
    int r = mach_vm_allocate(tt, taddr, size, flags);
    if (r) return r;
    if (H(safecopy, *taddr, saddr, size, 0)) { mach_vm_deallocate(tt, *taddr, size); return KERN_INVALID_ADDRESS; }
    if (cur) *cur = 3; if (max) *max = 7;
    return KERN_SUCCESS;
}
int vm_remap(uint32_t tt, uint64_t *taddr, uint64_t size, uint64_t mask, int flags, uint32_t st, uint64_t saddr,
             int copy, int *cur, int *max, int inh) { return mach_vm_remap(tt, taddr, size, mask, flags, st, saddr, copy, cur, max, inh); }
int mach_vm_region() { return KERN_INVALID_ADDRESS; }
int task_info(uint32_t task, int flavor, int *info, uint32_t *count) { memset(info, 0, (size_t)*count * 4); return KERN_SUCCESS; }
int thread_info(uint32_t th, int flavor, int *info, uint32_t *count) { memset(info, 0, (size_t)*count * 4); return KERN_SUCCESS; }
int thread_policy_set(uint32_t th, int flavor, void *p, uint32_t n) { return KERN_SUCCESS; }
int thread_policy_get(uint32_t th, int flavor, void *p, uint32_t *n, int *def) { if (def) *def = 1; return KERN_SUCCESS; }
static int thctl(uint32_t th, int op, int flavor, void *st) { int64_t r = H(thread_ctl, th, op, flavor, st); return r == 0 ? KERN_SUCCESS : r == -4 ? KERN_INVALID_ARGUMENT : KERN_FAILURE; }
int thread_suspend(uint32_t th) { return thctl(th, D_THREAD_SUSPEND, 0, 0); }
int thread_resume(uint32_t th) { return thctl(th, D_THREAD_RESUME, 0, 0); }
int thread_get_state(uint32_t th, int flavor, uint32_t *st, uint32_t *count) {
    uint32_t need = flavor == D_ARM_THREAD_STATE64 ? 68 : flavor == D_ARM_NEON_STATE64 ? 132 : flavor == D_x86_THREAD_STATE64 ? 42 : 0;
    if (!need || *count < need) return KERN_INVALID_ARGUMENT;
    *count = need; return thctl(th, D_THREAD_GET_STATE, flavor, st);
}
int thread_set_state(uint32_t th, int flavor, uint32_t *st, uint32_t count) { return thctl(th, D_THREAD_SET_STATE, flavor, st); }
int proc_regionfilename() { return 0; }
int notify_is_valid_token(int t) { return 0; }
void *xpc_date_create_from_current(void) { return 0; }

/* ---------- CoreFoundation / Security stubs (Go's crypto/x509 only) ---------- */
#define STUB(name) void *name() { return 0; }
STUB(CFArrayAppendValue) STUB(CFArrayCreateMutable) STUB(CFArrayGetCount) STUB(CFArrayGetValueAtIndex)
STUB(CFDataCreate) STUB(CFDataGetBytePtr) STUB(CFDataGetLength) STUB(CFDateCreate) STUB(CFErrorCopyDescription)
STUB(CFErrorGetCode) STUB(CFRelease) STUB(CFStringCreateExternalRepresentation) STUB(CFStringCreateWithBytes)
STUB(SecCertificateCopyData) STUB(SecCertificateCreateWithData) STUB(SecPolicyCreateSSL)
STUB(SecTrustCopyCertificateChain) STUB(SecTrustCreateWithCertificates) STUB(SecTrustEvaluateWithError)
STUB(SecTrustSetVerifyDate)

/* dyld calls this through LC_LOAD_DYLINKER-less binaries' lazy stubs; we bind eagerly */
void dyld_stub_binder(void) __asm__("dyld_stub_binder");
void dyld_stub_binder(void) { H(log, "dyld_stub_binder called: unresolved lazy bind"); H(exit, 127); }

/* ---------- stack protector ---------- */
uint64_t __stack_chk_guard = 0x2f8a0c1d5e6b7a39ull;
void __stack_chk_fail(void) { H(log, "stack smashing detectado"); H(exit, 134); for (;;) ; }

/* ---------- malloc: power-of-two classes 16 B .. 64 KB with free lists; bigger blocks come straight from mmap.
 * ponytail: global lock and no coalescing; swap for mimalloc-style per-thread heaps when allocation-heavy apps arrive */
#define NCLS 13 /* 16 << 12 = 64 KB */
static void *freelist[NCLS];
static uint64_t malloc_lock;
static char *arena, *arena_end;
struct mhdr { uint64_t size, cls; };
void *malloc(size_t n) {
    size_t need = n + sizeof(struct mhdr);
    if (need > (16u << (NCLS - 1))) {
        struct mhdr *h = mmap(0, need, 3, D_MAP_ANON | D_MAP_PRIVATE, -1, 0);
        if (h == (void *)-1) return 0;
        h->size = n; h->cls = NCLS;
        return h + 1;
    }
    int c = 0; while ((16u << c) < need) c++;
    H(lock, &malloc_lock, 0);
    struct mhdr *h = freelist[c];
    if (h) freelist[c] = *(void **)h;
    else {
        size_t sz = 16u << c;
        if (arena + sz > arena_end) {
            arena = mmap(0, 4 << 20, 3, D_MAP_ANON | D_MAP_PRIVATE, -1, 0);
            if (arena == (void *)-1) { arena = arena_end = 0; H(lock, &malloc_lock, 1); return 0; }
            arena_end = arena + (4 << 20);
        }
        h = (struct mhdr *)arena; arena += sz;
    }
    H(lock, &malloc_lock, 1);
    h->size = n; h->cls = (uint64_t)c;
    return h + 1;
}
void free(void *p) {
    if (!p) return;
    struct mhdr *h = (struct mhdr *)p - 1;
    if (h->cls == NCLS) { munmap(h, h->size + sizeof *h); return; }
    H(lock, &malloc_lock, 0);
    *(void **)h = freelist[h->cls]; freelist[h->cls] = h;
    H(lock, &malloc_lock, 1);
}
void *calloc(size_t a, size_t b) { void *p = malloc(a * b); if (p) memset(p, 0, a * b); return p; }
void *realloc(void *p, size_t n) {
    if (!p) return malloc(n);
    struct mhdr *h = (struct mhdr *)p - 1;
    if (n <= h->size) return p;
    void *q = malloc(n);
    if (q) { memcpy(q, p, h->size); free(p); }
    return q;
}
size_t malloc_size(const void *p) { return p ? ((struct mhdr *)p - 1)->size : 0; }

/* ---------- process info (set by the loader) ---------- */
int NXArgc; char **NXArgv; char **environ; char scion_exe_path[1024];
uint64_t scion_tsd_off; /* x86_64: %gs offset of the TlsSlots entry that holds struct gthread* */
int *_NSGetArgc(void) { return &NXArgc; }
char ***_NSGetArgv(void) { return &NXArgv; }
char ***_NSGetEnviron(void) { return &environ; }
int _NSGetExecutablePath(char *b, uint32_t *n) {
    uint32_t l = (uint32_t)strlen(scion_exe_path) + 1;
    if (*n < l) { *n = l; return -1; }
    memcpy(b, scion_exe_path, l); return 0;
}
int strncmp(const char *a, const char *b, size_t n) {
    for (; n; n--, a++, b++) { if (*a != *b) return (unsigned char)*a - (unsigned char)*b; if (!*a) return 0; }
    return 0;
}
char *getenv(const char *k) {
    size_t n = strlen(k);
    for (char **e = environ; e && *e; e++) if (!strncmp(*e, k, n) && (*e)[n] == '=') return *e + n + 1;
    return 0;
}
char *strchr(const char *s, int c); char *strcpy(char *d, const char *s);
/* the environment array is copied on the first change; replaced strings leak (ponytail: as many libcs, no locking) */
static int env_put(char *kv, size_t n) {
    static char **own; size_t c = 0;
    for (char **e = environ; e && *e; e++, c++) if (!strncmp(*e, kv, n) && (*e)[n] == '=') { *e = kv; return 0; }
    {
        char **ne = malloc((c + 2) * sizeof *ne);
        if (!ne) return fail(D_ENOMEM);
        if (c) memcpy(ne, environ, c * sizeof *ne);
        ne[c] = kv; ne[c + 1] = 0;
        if (own) free(own);
        environ = own = ne;
    }
    return 0;
}
int setenv(const char *k, const char *v, int over) {
    size_t n = strlen(k);
    if (!n || strchr(k, '=')) return fail(D_EINVAL);
    if (getenv(k) && !over) return 0;
    char *kv = malloc(n + strlen(v) + 2);
    if (!kv) return fail(D_ENOMEM);
    memcpy(kv, k, n); kv[n] = '='; strcpy(kv + n + 1, v);
    return env_put(kv, n);
}
int putenv(char *kv) { char *eq = strchr(kv, '='); return eq ? env_put(kv, (size_t)(eq - kv)) : fail(D_EINVAL); }
int unsetenv(const char *k) {
    size_t n = strlen(k);
    if (!n || strchr(k, '=')) return fail(D_EINVAL);
    char **w = environ;
    for (char **e = environ; e && *e; e++) if (strncmp(*e, k, n) || (*e)[n] != '=') *w++ = *e;
    if (w) *w = 0;
    return 0;
}
int atexit(void (*f)(void)) { return __cxa_atexit(call_noarg, (void *)f, 0); }
void abort(void) { H(log, "abort()", __builtin_frame_address(0)); H(exit, 134); for (;;) ; }

/* ---------- more string / memory ---------- */
void *memchr(const void *p, int c, size_t n) { const unsigned char *a = p; for (; n; n--, a++) if (*a == (unsigned char)c) return (void *)a; return 0; }
char *strchr(const char *s, int c) { for (;; s++) { if (*s == (char)c) return (char *)s; if (!*s) return 0; } }
void __bzero(void *p, size_t n) { memset(p, 0, n); }
void bzero(void *p, size_t n) { memset(p, 0, n); }
void memset_pattern16(void *d, const void *pat, size_t n) { char *a = d; const char *b = pat; for (size_t i = 0; i < n; i++) a[i] = b[i & 15]; }
int strerror_r(int e, char *b, size_t n) {
    const char *m = e == D_ENOENT ? "No such file or directory" : e == D_EACCES ? "Permission denied" : e == D_EEXIST ? "File exists"
                  : e == D_ENOTDIR ? "Not a directory" : e == D_EISDIR ? "Is a directory" : e == D_ENOSYS ? "Function not implemented" : "Error";
    size_t l = strlen(m); if (l >= n) l = n - 1; memcpy(b, m, l); b[l] = 0; return 0;
}

/* ---------- more files ---------- */
ssize_t writev(int fd, const uint64_t *iov, int n) {
    ssize_t t = 0;
    for (int i = 0; i < n; i++) { ssize_t w = write(fd, (void *)iov[2 * i], iov[2 * i + 1]); if (w < 0) return t ? t : -1; t += w; if ((uint64_t)w < iov[2 * i + 1]) break; }
    return t;
}
int isatty(int fd) { return H(isatty, fd) ? 1 : (fail(D_ENOTTY), 0); }
int chdir(const char *p) { return (int)ret(H(chdir, p)); }
int chroot(const char *p) { return fail(D_EPERM); }
int fchmod(int fd, int m) { return 0; }
int ftruncate(int fd, off_t n) { return (int)ret(H(ftruncate, fd, n)); }
int rename(const char *a, const char *b) { return (int)ret(H(rename, a, b)); }
int unlinkat(int dfd, const char *p, int fl) { return (int)ret(H(unlink, p, (fl & 0x80) != 0, dfd)); }
char *realpath(const char *p, char *out) {
    static char buf[1024]; char *o = out ? out : malloc(1024);
    if (!o) o = buf;
    return ret(H(realpath, p, o)) < 0 ? 0 : o;
}
char *realpath_x(const char *p, char *out) __asm__("_realpath$DARWIN_EXTSN");
char *realpath_x(const char *p, char *out) { return realpath(p, out); }
int pipe(int fds[2]) { return (int)ret(H(pipe, fds)); }
#define ENOTSUP_FN(name) int name() { return fail(45); }
ENOTSUP_FN(fcopyfile) ENOTSUP_FN(fclonefileat)
/* extended attributes (host: per-file store); position and options are ignored */
ssize_t getxattr(const char *p, const char *n, void *b, size_t sz, uint32_t pos, int o) { return ret(H(xattr, 0, -1, p, n, b, sz)); }
ssize_t fgetxattr(int fd, const char *n, void *b, size_t sz, uint32_t pos, int o) { return ret(H(xattr, 0, fd, 0, n, b, sz)); }
int setxattr(const char *p, const char *n, const void *b, size_t sz, uint32_t pos, int o) { return (int)ret(H(xattr, 1, -1, p, n, b, sz)); }
int fsetxattr(int fd, const char *n, const void *b, size_t sz, uint32_t pos, int o) { return (int)ret(H(xattr, 1, fd, 0, n, b, sz)); }
int removexattr(const char *p, const char *n, int o) { return (int)ret(H(xattr, 2, -1, p, n, 0, 0)); }
int fremovexattr(int fd, const char *n, int o) { return (int)ret(H(xattr, 2, fd, 0, n, 0, 0)); }
ssize_t listxattr(const char *p, char *b, size_t sz, int o) { return ret(H(xattr, 3, -1, p, 0, b, sz)); }
ssize_t flistxattr(int fd, char *b, size_t sz, int o) { return ret(H(xattr, 3, fd, 0, 0, b, sz)); }
/* renamex_np: RENAME_SWAP (2) through a temporary name, RENAME_EXCL (4) refuses an existing destination */
int access(const char *p, int m);
int renamex_np(const char *a, const char *b, unsigned fl) {
    if (fl & 4) { if (access(b, 0) == 0) return fail(17 /* EEXIST */); return rename(a, b); }
    if (fl & 2) {
        char tmp[1100]; snprintf(tmp, sizeof tmp, "%s.mwswap", a);
        if (rename(a, tmp) || rename(b, a) || rename(tmp, b)) return -1;
        return 0;
    }
    return rename(a, b);
}
int renameatx_np(int fa, const char *a, int fb, const char *b, unsigned fl) {
    char x[2100], y[2100]; const char *p = at_path(fa, a, x), *q = at_path(fb, b, y);
    return p && q ? renamex_np(p, q, fl) : -1;
}
int proc_pid_rusage(int pid, int flavor, void *buf) { return fail(D_ENOSYS); } /* ponytail: no per-process CPU accounting */
void *copyfile_state_alloc(void) { return 0; }
int copyfile_state_free(void *s) { return 0; }
int copyfile_state_get(void *s, uint32_t f, void *d) { return -1; }

/* ---------- identity / time ---------- */
uint32_t getuid(void) { return 501; }
uint32_t geteuid(void) { return 501; }
uint32_t getgid(void) { return 20; }
int setuid(uint32_t u) { return fail(D_EPERM); }
int setgid(uint32_t g) { return fail(D_EPERM); }
int setgroups(int n, const uint32_t *g) { return fail(D_EPERM); }
int setsid(void) { return fail(D_EPERM); }
int setpgid(int a, int b) { return fail(D_EPERM); }
int getpwuid_r(uint32_t u, void *pw, char *b, size_t n, void **res) { *res = 0; return 0; }
long sysconf(int name) {
    if (name == 58 || name == 57) return H(ncpu); /* _SC_NPROCESSORS_ONLN / _CONF */
    if (name == 29) return PAGE;                  /* _SC_PAGESIZE */
    if (name == 3) return 100;                    /* _SC_CLK_TCK */
    return fail(D_EINVAL);
}
size_t confstr(int n, char *b, size_t l) { return 0; }
struct timeval { int64_t tv_sec; int32_t tv_usec; };
int gettimeofday(struct timeval *tv, void *tz) { int64_t ns = H(clock, 0); tv->tv_sec = ns / 1000000000; tv->tv_usec = (int32_t)(ns % 1000000000 / 1000); return 0; }
int nanosleep(const struct timespec *ts, struct timespec *rem) { H(sleep, ts->tv_sec * 1000000000 + ts->tv_nsec); if (rem) rem->tv_sec = rem->tv_nsec = 0; return 0; }
struct tm { int sec, min, hour, mday, mon, year, wday, yday, isdst; long gmtoff; const char *zone; };
struct tm *gmtime_r(const int64_t *t, struct tm *tm) {
    int64_t s = *t, days = s / 86400, rem = s % 86400;
    if (rem < 0) rem += 86400, days--;
    tm->hour = (int)(rem / 3600); tm->min = (int)(rem % 3600 / 60); tm->sec = (int)(rem % 60);
    tm->wday = (int)((4 + days) % 7); if (tm->wday < 0) tm->wday += 7;
    int64_t z = days + 719468, era = (z >= 0 ? z : z - 146096) / 146097, doe = z - era * 146097;
    int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365, y = yoe + era * 400, doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int64_t mp = (5 * doy + 2) / 153, d = doy - (153 * mp + 2) / 5 + 1, m = mp < 10 ? mp + 3 : mp - 9;
    tm->year = (int)(y + (m <= 2) - 1900); tm->mon = (int)m - 1; tm->mday = (int)d;
    tm->yday = (int)(doy >= 306 ? doy - 306 : doy + 59 + ((y % 4 == 0 && y % 100) || y % 400 == 0)); /* doy counts from March 1 */
    tm->isdst = 0; tm->gmtoff = 0; tm->zone = "UTC";
    return tm;
}
/* time zone: TZ in POSIX form ("CST-8", "<+0530>-5:30"); the standard part only, ponytail: no DST rules, no zoneinfo
 * names, and without TZ local time is UTC */
char *tzname[2] = {"UTC", "UTC"}; long timezone; int daylight;
static char tz_name[16] = "UTC";
void tzset(void) {
    const char *z = getenv("TZ"); long off = 0; size_t n = 0;
    if (z && *z == ':') z = 0;
    if (z && *z) {
        if (*z == '<') { z++; while (z[n] && z[n] != '>' && n < 15) n++; memcpy(tz_name, z, n); z += n + (z[n] == '>'); }
        else { while (((z[n] | 32) >= 'a' && (z[n] | 32) <= 'z') && n < 15) n++; memcpy(tz_name, z, n); z += n; }
        tz_name[n] = 0;
        int sign = *z == '-' ? -1 : 1; if (*z == '-' || *z == '+') z++;
        long h = 0, m = 0, sec = 0;
        while (*z >= '0' && *z <= '9') h = h * 10 + *z++ - '0';
        if (*z == ':') { z++; while (*z >= '0' && *z <= '9') m = m * 10 + *z++ - '0'; }
        if (*z == ':') { z++; while (*z >= '0' && *z <= '9') sec = sec * 10 + *z++ - '0'; }
        off = sign * (h * 3600 + m * 60 + sec); /* seconds west of UTC */
    } else strcpy(tz_name, "UTC");
    timezone = off; daylight = 0; tzname[0] = tzname[1] = tz_name;
}
struct tm *localtime_r(const int64_t *t, struct tm *tm) {
    tzset();
    int64_t l = *t - timezone;
    gmtime_r(&l, tm); tm->gmtoff = -timezone; tm->zone = tz_name;
    return tm;
}
int64_t timegm(struct tm *tm) { /* days_from_civil (H. Hinnant) */
    int64_t y = tm->year + 1900 + tm->mon / 12, m = tm->mon % 12; if (m < 0) m += 12, y--;
    y -= m < 2; int64_t era = (y >= 0 ? y : y - 399) / 400, yoe = y - era * 400;
    int64_t doy = (153 * (m + (m > 1 ? -2 : 10)) + 2) / 5 + tm->mday - 1, doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    int64_t days = era * 146097 + doe - 719468;
    return days * 86400 + tm->hour * 3600 + tm->min * 60 + tm->sec;
}
struct tm *gmtime(const int64_t *t) { static struct tm tm; return gmtime_r(t, &tm); }
struct tm *localtime(const int64_t *t) { static struct tm tm; return localtime_r(t, &tm); }
int64_t mktime(struct tm *tm) { tzset(); int64_t t = timegm(tm) + timezone; localtime_r(&t, tm); return t; }
int getentropy(void *b, size_t n) { H(random, b, n); return 0; }
int CCRandomGenerateBytes(void *b, size_t n) { H(random, b, n); return 0; }

/* ---------- signals (bookkeeping only) ---------- */
int sigemptyset(uint32_t *s) { *s = 0; return 0; }
int sigaddset(uint32_t *s, int n) { *s |= 1u << (n - 1); return 0; }
void *signal(int sig, void *h) { return 0; }
int pause(void) { for (;;) H(sleep, 1000000000); }

/* ---------- processes: not yet ---------- */
#define NOSPAWN(name) int name() { return fail(D_ENOSYS); }
NOSPAWN(fork) NOSPAWN(execvp) NOSPAWN(waitpid) NOSPAWN(posix_spawnp) NOSPAWN(posix_spawn)
void *sem_open(const char *name, int flags, ...) { fail(D_ENOSYS); return (void *)-1; } /* SEM_FAILED: no named semaphores */
int posix_spawn_file_actions_init(void *a) { return 0; }
int posix_spawn_file_actions_destroy(void *a) { return 0; }
int posix_spawn_file_actions_adddup2(void *a, int f, int t) { return 0; }
int posix_spawnattr_init(void *a) { return 0; }
int posix_spawnattr_destroy(void *a) { return 0; }
int posix_spawnattr_setflags(void *a, short f) { return 0; }
int posix_spawnattr_setpgroup(void *a, int g) { return 0; }
int posix_spawnattr_setsigdefault(void *a, const void *s) { return 0; }

/* ---------- dyld introspection ---------- */
/* ---------- dyld: image table (filled by the loader), dlopen/dlsym/dladdr, unwind sections ---------- */
struct mw_image { const void *mh; intptr_t slide; const char *path; };
struct mw_image scion_images[512];
uint32_t scion_image_count;
uint32_t _dyld_image_count(void) { return __atomic_load_n(&scion_image_count, __ATOMIC_ACQUIRE); }
const void *_dyld_get_image_header(uint32_t i) { return i < _dyld_image_count() ? scion_images[i].mh : 0; }
const char *_dyld_get_image_name(uint32_t i) { return i < _dyld_image_count() ? scion_images[i].path : 0; }
intptr_t _dyld_get_image_vmaddr_slide(uint32_t i) { return i < _dyld_image_count() ? scion_images[i].slide : 0; }
typedef void (*dyld_cb)(const void *mh, intptr_t slide);
static dyld_cb add_cbs[32]; static int n_add_cbs;
void _dyld_register_func_for_add_image(dyld_cb f) {
    if (n_add_cbs < 32) add_cbs[n_add_cbs++] = f;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) f(scion_images[i].mh, scion_images[i].slide);
}
void _dyld_register_func_for_remove_image(dyld_cb f) { } /* images are never unloaded */
static char dl_err[256];
void *dlopen(const char *p, int mode) {
    uint32_t before = _dyld_image_count();
    void *h = (void *)H(dl, 0, p, mode);
    if (!h) { H(dl, 3, dl_err, sizeof dl_err); return 0; }
    for (uint32_t i = before; i < _dyld_image_count(); i++) for (int k = 0; k < n_add_cbs; k++) add_cbs[k](scion_images[i].mh, scion_images[i].slide);
    dl_err[0] = 0; return h;
}
void *dlsym(void *h, const char *name) {
    void *r = (void *)H(dl, 1, h, name);
    if (!r) snprintf(dl_err, sizeof dl_err, "dlsym(%p, %s): symbol not found", h, name);
    return r;
}
char *dlerror(void) { if (!dl_err[0]) return 0; static char out[256]; memcpy(out, dl_err, sizeof out); dl_err[0] = 0; return out; }
int dlclose(void *h) { return 0; }
typedef struct { const char *dli_fname; void *dli_fbase; const char *dli_sname; void *dli_saddr; } Dl_info;
int dladdr(const void *a, Dl_info *i) { return (int)H(dl, 2, a, i); }
int dlopen_preflight(const char *p) { return 1; }

/* sections of a loaded image (shared with libunwind and the ObjC runtime) */
struct mh64 { uint32_t magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved; };
struct seg64 { uint32_t cmd, cmdsize; char segname[16]; uint64_t vmaddr, vmsize, fileoff, filesize; uint32_t maxprot, initprot, nsects, flags; };
struct sect64 { char sectname[16], segname[16]; uint64_t addr, size; uint32_t offset, align, reloff, nreloc, flags, r1, r2, r3; };
static int img_contains(const struct mw_image *im, uintptr_t a) {
    const struct mh64 *h = im->mh; const uint8_t *lc = (const uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++, lc += ((const uint32_t *)lc)[1]) {
        const struct seg64 *s = (const struct seg64 *)lc;
        if (s->cmd == 0x19 && s->initprot && a >= s->vmaddr + im->slide && a < s->vmaddr + s->vmsize + im->slide) return 1;
    }
    return 0;
}
static const struct sect64 *img_section(const struct mw_image *im, const char *seg, const char *sect) {
    const struct mh64 *h = im->mh; const uint8_t *lc = (const uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++, lc += ((const uint32_t *)lc)[1]) {
        const struct seg64 *s = (const struct seg64 *)lc;
        if (s->cmd != 0x19 || strncmp(s->segname, seg, 16)) continue;
        const struct sect64 *sc = (const struct sect64 *)(s + 1);
        for (uint32_t k = 0; k < s->nsects; k++) if (!strncmp(sc[k].sectname, sect, 16)) return &sc[k];
    }
    return 0;
}
static const struct mw_image *image_for(uintptr_t a) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) if (img_contains(&scion_images[i], a)) return &scion_images[i];
    return 0;
}
struct dyld_unwind_sections { const void *mh; const void *dwarf_section; uintptr_t dwarf_section_length; const void *compact_unwind_section; uintptr_t compact_unwind_section_length; };
int _dyld_find_unwind_sections(void *addr, struct dyld_unwind_sections *info) {
    const struct mw_image *im = image_for((uintptr_t)addr);
    if (!im) return 0;
    const struct sect64 *eh = img_section(im, "__TEXT", "__eh_frame"), *ui = img_section(im, "__TEXT", "__unwind_info");
    info->mh = im->mh;
    info->dwarf_section = eh ? (void *)(eh->addr + im->slide) : 0; info->dwarf_section_length = eh ? eh->size : 0;
    info->compact_unwind_section = ui ? (void *)(ui->addr + im->slide) : 0; info->compact_unwind_section_length = ui ? ui->size : 0;
    return 1;
}
const void *_dyld_get_image_header_containing_address(const void *a) { const struct mw_image *im = image_for((uintptr_t)a); return im ? im->mh : 0; }
uint8_t *getsectiondata(const void *mh, const char *seg, const char *sect, unsigned long *size) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) if (scion_images[i].mh == mh) {
        const struct sect64 *s = img_section(&scion_images[i], seg, sect);
        if (!s) return 0;
        *size = s->size; return (uint8_t *)(s->addr + scion_images[i].slide);
    }
    return 0;
}

/* unwinding: LLVM libunwind is linked into libSystem (out/rt/<arch>/unwind) */

/* ---------- os_unfair_lock (4 bytes: spinlock + yield) ---------- */
void os_unfair_lock_lock(uint32_t *l) { while (__atomic_exchange_n(l, 1, __ATOMIC_ACQUIRE)) H(sleep, 0); }
int os_unfair_lock_trylock(uint32_t *l) { return !__atomic_exchange_n(l, 1, __ATOMIC_ACQUIRE); }
void os_unfair_lock_unlock(uint32_t *l) { __atomic_store_n(l, 0, __ATOMIC_RELEASE); }

/* ---------- libdispatch: semaphores only ---------- */
struct dsema { void *isa; uint64_t lock, cv; int64_t value; };
void *_scion_dispatch_isa(int kind);
void *dispatch_semaphore_create(long v) { struct dsema *s = calloc(1, sizeof *s); if (s) { s->isa = _scion_dispatch_isa(2 /* semaphore */); s->value = v; } return s; }
long dispatch_semaphore_signal(struct dsema *s) {
    H(lock, &s->lock, 0); s->value++; H(lock, &s->lock, 1); H(cond, &s->cv, 0, 1, 0); return 0;
}
long dispatch_semaphore_wait(struct dsema *s, uint64_t timeout) {
    H(lock, &s->lock, 0);
    while (s->value <= 0) {
        int64_t t = timeout == ~0ull ? -1 : (int64_t)(timeout - (uint64_t)H(clock, 1));
        if (t != -1 && t <= 0) { H(lock, &s->lock, 1); return -1; }
        H(cond, &s->cv, &s->lock, 0, t);
    }
    s->value--; H(lock, &s->lock, 1); return 0;
}

/* Mach semaphores: the port name indexes a table of dispatch semaphores. ponytail: 1024 live semaphores */
static struct dsema *msema[1024];
int semaphore_create(unsigned task, unsigned *s, int policy, int value) {
    (void)task; (void)policy;
    for (unsigned i = 1; i < 1024; i++) if (!msema[i]) {
        struct dsema *d = dispatch_semaphore_create(value);
        if (!d) break;
        if (__atomic_compare_exchange_n(&msema[i], &(struct dsema *){0}, d, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) { *s = i; return 0; }
        free(d);
    }
    return 6; /* KERN_RESOURCE_SHORTAGE */
}
int semaphore_destroy(unsigned task, unsigned s) { (void)task; if (s >= 1024 || !msema[s]) return 4; free(__atomic_exchange_n(&msema[s], 0, __ATOMIC_ACQ_REL)); return 0; }
int semaphore_signal(unsigned s) { if (s >= 1024 || !msema[s]) return 4; dispatch_semaphore_signal(msema[s]); return 0; }
int semaphore_wait(unsigned s) { if (s >= 1024 || !msema[s]) return 4; dispatch_semaphore_wait(msema[s], ~0ull); return 0; }

/* ---------- libm through the host (doubles travel as bit patterns) ---------- */
static uint64_t d2b(double d) { uint64_t b; memcpy(&b, &d, 8); return b; }
static double b2d(uint64_t b) { double d; memcpy(&d, &b, 8); return d; }
#define M1(name, op) double name(double x) { return b2d((uint64_t)H(math, op, d2b(x))); }
#define M2(name, op) double name(double x, double y) { return b2d((uint64_t)H(math, op, d2b(x), d2b(y))); }
M1(sin, M_SIN) M1(cos, M_COS) M1(tan, M_TAN) M1(asin, M_ASIN) M1(acos, M_ACOS) M1(atan, M_ATAN) M2(atan2, M_ATAN2)
M1(sinh, M_SINH) M1(cosh, M_COSH) M1(tanh, M_TANH) M1(asinh, M_ASINH) M1(acosh, M_ACOSH) M1(atanh, M_ATANH)
M1(exp, M_EXP) M1(expm1, M_EXPM1) M1(log, M_LOG) M1(log10, M_LOG10) M1(log1p, M_LOG1P) M1(log2, M_LOG2) M1(exp2, M_EXP2)
M2(pow, M_POW) M1(cbrt, M_CBRT) M2(hypot, M_HYPOT) M2(fmod, M_FMOD)
M1(erf, M_ERF) M1(erfc, M_ERFC) M1(tgamma, M_TGAMMA) M1(lgamma, M_LGAMMA)
M1(j0, M_J0) M1(j1, M_J1) M1(y0, M_Y0) M1(y1, M_Y1)
double jn(int n, double x) { return b2d((uint64_t)H(math, M_JN, d2b(x), d2b((double)n))); }
double yn(int n, double x) { return b2d((uint64_t)H(math, M_YN, d2b(x), d2b((double)n))); }
int signgam;
double lgamma_r(double x, int *sign) { double t = tgamma(x); *sign = t < 0 ? -1 : 1; return lgamma(x); }
float lgammaf_r(float x, int *sign) { return (float)lgamma_r(x, sign); }
long double lgammal_r(long double x, int *sign) { return lgamma_r((double)x, sign); }
double fma(double x, double y, double z) { return b2d((uint64_t)H(math, M_FMA, d2b(x), d2b(y), d2b(z))); }
float powf(float x, float y) { return (float)pow(x, y); }
float exp2f(float x) { return (float)exp2(x); }
/* ldexp/frexp by bit manipulation (subnormals via scaling) */
double scalbn(double x, int n) {
    while (n > 1023) { x *= 0x1p1023; n -= 1023; }
    while (n < -1022) { x *= 0x1p-1022; n += 1022; }
    union { double d; uint64_t u; } k = {.u = (uint64_t)(n + 1023) << 52};
    return x * k.d;
}
double ldexp(double x, int n) { return scalbn(x, n); }
float scalbnf(float x, int n) { return (float)scalbn(x, n); }
float ldexpf(float x, int n) { return (float)scalbn(x, n); }
double frexp(double x, int *e) {
    union { double d; uint64_t u; } v = {x};
    int ee = (int)(v.u >> 52 & 0x7ff);
    if (!ee) { if (x == 0) { *e = 0; return x; } x = frexp(x * 0x1p64, e); *e -= 64; return x; }
    if (ee == 0x7ff) { *e = 0; return x; }
    *e = ee - 1022;
    v.u = (v.u & 0x800fffffffffffffull) | 0x3fe0000000000000ull;
    return v.d;
}
float frexpf(float x, int *e) { return (float)frexp(x, e); }
double rint(double); double copysign(double, double);
double nan(const char *tag) { return __builtin_nan(""); }
float nanf(const char *tag) { return __builtin_nanf(""); }
long double nanl(const char *tag) { return __builtin_nanl(""); }
double nextafter(double x, double y) { /* one ulp from x toward y */
    if (x != x || y != y) return x + y;
    if (x == y) return y;
    union { double d; uint64_t u; } v = {x};
    if (x == 0) v.u = 1, v.d = copysign(v.d, y);
    else if ((x < y) == (x > 0)) v.u++;
    else v.u--;
    return v.d;
}
float nextafterf(float x, float y) { /* one float ulp */
    if (x != x || y != y) return x + y;
    if (x == y) return y;
    union { float f; uint32_t u; } v = {x};
    if (x == 0) { v.u = 1; if (y < 0) v.u |= 0x80000000u; }
    else if ((x < y) == (x > 0)) v.u++;
    else v.u--;
    return v.f;
}
double remquo(double x, double y, int *q) { double n = rint(x / y); long long k = (long long)n; *q = (int)(k < 0 ? -(-k & 0x7fffffff) : k & 0x7fffffff); return x - n * y; }
float remquof(float x, float y, int *q) { return (float)remquo(x, y, q); }
float fdimf(float a, float b) { return a > b ? a - b : 0; }
double logb(double x) { if (x == 0) return -1.0 / 0.0; if (x != x || x - x != 0) return x * x; int e; frexp(x, &e); return e - 1; }
float cbrtf(float x) { return (float)cbrt(x); }
float sinf(float x) { return (float)sin(x); }
float cosf(float x) { return (float)cos(x); }
/* rounding, min/max, sqrt: plain code (x86_64 has no rounding instruction in the baseline ISA) */
double fabs(double x) { union { double d; uint64_t u; } v = {x}; v.u &= ~(1ull << 63); return v.d; }
double copysign(double x, double y) { union { double d; uint64_t u; } a = {x}, b = {y}; a.u = (a.u & ~(1ull << 63)) | (b.u & (1ull << 63)); return a.d; }
double trunc(double x) { return fabs(x) < 0x1p52 ? copysign((double)(int64_t)x, x) : x; }
double floor(double x) { double t = trunc(x); return t > x ? t - 1 : t; }
double ceil(double x) { double t = trunc(x); return t < x ? t + 1 : t; }
double round(double x) { double t = trunc(x); return fabs(x - t) >= 0.5 ? t + copysign(1, x) : t; }
double rint(double x) { /* round half to even, the default rounding mode */
    if (!(fabs(x) < 0x1p52)) return x;
    double k = copysign(0x1p52, x);
    return copysign((x + k) - k, x);
}
double nearbyint(double x) { return rint(x); }
long lround(double x) { return (long)round(x); }
long long llround(double x) { return (long long)round(x); }
long lrint(double x) { return (long)rint(x); }
long long llrint(double x) { return (long long)rint(x); }
double fmin(double a, double b) { return a != a ? b : b != b ? a : a < b ? a : b; }
double fmax(double a, double b) { return a != a ? b : b != b ? a : a > b ? a : b; }
double fdim(double a, double b) { return a > b ? a - b : 0; }
double sqrt(double x) { return __builtin_sqrt(x); }
double modf(double x, double *ip) { double t = trunc(x); if (ip) *ip = t; return fabs(x) < 0x1p52 ? copysign(x - t, x) : copysign(0, x); }
double remainder(double x, double y) { return x - rint(x / y) * y; }
float fabsf(float x) { return (float)fabs(x); }
float copysignf(float x, float y) { return (float)copysign(x, y); }
float truncf(float x) { return (float)trunc(x); }
float floorf(float x) { return (float)floor(x); }
float ceilf(float x) { return (float)ceil(x); }
float roundf(float x) { return (float)round(x); }
float rintf(float x) { return (float)rint(x); }
float nearbyintf(float x) { return (float)rint(x); }
long lroundf(float x) { return (long)round(x); }
long lrintf(float x) { return (long)rint(x); }
float fminf(float a, float b) { return (float)fmin(a, b); }
float fmaxf(float a, float b) { return (float)fmax(a, b); }
float sqrtf(float x) { return __builtin_sqrtf(x); }
float modff(float x, float *ip) { double i; float r = (float)modf(x, &i); if (ip) *ip = (float)i; return r; }
float fmodf(float x, float y) { return (float)fmod(x, y); }
float fmaf(float x, float y, float z) { return (float)fma(x, y, z); }
#define F1(name) float name##f(float x) { return (float)name(x); }
F1(tan) F1(asin) F1(acos) F1(atan) F1(sinh) F1(cosh) F1(tanh) F1(asinh) F1(acosh) F1(atanh) F1(exp) F1(expm1) F1(log) F1(log10) F1(log1p) F1(log2)
F1(erf) F1(erfc) F1(tgamma) F1(lgamma) F1(logb)
float atan2f(float y, float x) { return (float)atan2(y, x); }
float hypotf(float x, float y) { return (float)hypot(x, y); }
struct sincosf_ret { float s, c; };
struct sincosf_ret __sincosf_stret(float x) { struct sincosf_ret r = {(float)sin(x), (float)cos(x)}; return r; }
double __exp10(double x) { volatile double ten = 10; return pow(ten, x); } /* volatile: clang would turn pow(10, x) back into __exp10 */
float __exp10f(float x) { volatile double ten = 10; return (float)pow(ten, x); }
struct sincos_ret { double s, c; };
struct sincos_ret __sincos_stret(double x) { struct sincos_ret r = {sin(x), cos(x)}; return r; }

/* ---------- CoreFoundation / CoreServices: stubs (file watching, run loops unsupported) ---------- */
STUB(CFArrayInsertValueAtIndex) STUB(CFArrayRemoveValueAtIndex) STUB(CFRunLoopGetCurrent) STUB(CFRunLoopIsWaiting)
STUB(CFRunLoopStop) STUB(CFStringCompare) STUB(CFURLCopyAbsoluteURL) STUB(CFURLCopyFileSystemPath)
STUB(CFURLCopyLastPathComponent) STUB(CFURLCreateCopyAppendingPathComponent) STUB(CFURLCreateCopyDeletingLastPathComponent)
STUB(CFURLCreateFilePathURL) STUB(CFURLCreateFileReferenceURL) STUB(CFURLCreateFromFileSystemRepresentation) STUB(CFURLResourceIsReachable)
STUB(FSEventStreamCreate) STUB(FSEventStreamGetDeviceBeingWatched) STUB(FSEventStreamInvalidate) STUB(FSEventStreamRelease)
STUB(FSEventStreamScheduleWithRunLoop) STUB(FSEventStreamStart) STUB(FSEventStreamStop) STUB(FSEventsGetCurrentEventId)
STUB(FSEventsPurgeEventsForDeviceUpToEventId)
const void *kCFRunLoopDefaultMode = "kCFRunLoopDefaultMode";
uint64_t kCFTypeArrayCallBacks[5];

/* ---------- thread-local variables (Mach-O __thread_vars) ----------
 * The loader points every descriptor's thunk at scion_tlv_get_addr and gives each image a key in 480..511.
 * Contract: returns the variable address in rax/x0 and preserves every other register. */
struct tlv_tmpl { uint64_t start, size; } scion_tlv_tmpl[32];
void *scion_tlv_slow(uint64_t *desc) {
    struct tlv_tmpl *t = &scion_tlv_tmpl[desc[1] - 480];
    char *b = malloc(t->size ? t->size : 1);
    memcpy(b, (void *)t->start, t->size);
    self()->tsd[desc[1]] = (uint64_t)b;
    return b + desc[2];
}
void _tlv_atexit(void (*f)(void *), void *o) {} /* ponytail: TLV destructors are not run */
void _tlv_bootstrap(void) { H(log, "_tlv_bootstrap not bound"); H(exit, 127); }
#ifdef __x86_64__
__asm__(".globl _scion_tlv_get_addr\n_scion_tlv_get_addr:\n"
        " pushq %rcx\n movq _scion_tsd_off(%rip), %rcx\n movq %gs:(%rcx), %rcx\n"
        " movq 8(%rdi), %rax\n movq (%rcx,%rax,8), %rax\n popq %rcx\n"
        " testq %rax, %rax\n jz 1f\n addq 16(%rdi), %rax\n ret\n"
        "1:\n pushq %rbp\n movq %rsp, %rbp\n andq $-16, %rsp\n subq $320, %rsp\n"
        " movq %rcx, 0(%rsp)\n movq %rdx, 8(%rsp)\n movq %rsi, 16(%rsp)\n movq %rdi, 24(%rsp)\n"
        " movq %r8, 32(%rsp)\n movq %r9, 40(%rsp)\n movq %r10, 48(%rsp)\n movq %r11, 56(%rsp)\n"
        " movdqu %xmm0, 64(%rsp)\n movdqu %xmm1, 80(%rsp)\n movdqu %xmm2, 96(%rsp)\n movdqu %xmm3, 112(%rsp)\n"
        " movdqu %xmm4, 128(%rsp)\n movdqu %xmm5, 144(%rsp)\n movdqu %xmm6, 160(%rsp)\n movdqu %xmm7, 176(%rsp)\n"
        " movdqu %xmm8, 192(%rsp)\n movdqu %xmm9, 208(%rsp)\n movdqu %xmm10, 224(%rsp)\n movdqu %xmm11, 240(%rsp)\n"
        " movdqu %xmm12, 256(%rsp)\n movdqu %xmm13, 272(%rsp)\n movdqu %xmm14, 288(%rsp)\n movdqu %xmm15, 304(%rsp)\n"
        " call _scion_tlv_slow\n"
        " movq 0(%rsp), %rcx\n movq 8(%rsp), %rdx\n movq 16(%rsp), %rsi\n movq 24(%rsp), %rdi\n"
        " movq 32(%rsp), %r8\n movq 40(%rsp), %r9\n movq 48(%rsp), %r10\n movq 56(%rsp), %r11\n"
        " movdqu 64(%rsp), %xmm0\n movdqu 80(%rsp), %xmm1\n movdqu 96(%rsp), %xmm2\n movdqu 112(%rsp), %xmm3\n"
        " movdqu 128(%rsp), %xmm4\n movdqu 144(%rsp), %xmm5\n movdqu 160(%rsp), %xmm6\n movdqu 176(%rsp), %xmm7\n"
        " movdqu 192(%rsp), %xmm8\n movdqu 208(%rsp), %xmm9\n movdqu 224(%rsp), %xmm10\n movdqu 240(%rsp), %xmm11\n"
        " movdqu 256(%rsp), %xmm12\n movdqu 272(%rsp), %xmm13\n movdqu 288(%rsp), %xmm14\n movdqu 304(%rsp), %xmm15\n"
        " movq %rbp, %rsp\n popq %rbp\n ret\n");
/* stack probe: our stacks are fully committed, nothing to touch */
__asm__(".globl ____chkstk_darwin\n____chkstk_darwin:\n ret\n");
#else
__asm__(".globl _scion_tlv_get_addr\n.p2align 2\n_scion_tlv_get_addr:\n"
        " mrs x16, tpidrro_el0\n ldr x17, [x0, #8]\n ldr x16, [x16, x17, lsl #3]\n cbz x16, 1f\n"
        " ldr x17, [x0, #16]\n add x0, x16, x17\n ret\n"
        "1:\n stp x29, x30, [sp, #-16]!\n mov x29, sp\n sub sp, sp, #656\n"
        " stp x1, x2, [sp, #0]\n stp x3, x4, [sp, #16]\n stp x5, x6, [sp, #32]\n stp x7, x8, [sp, #48]\n"
        " stp x9, x10, [sp, #64]\n stp x11, x12, [sp, #80]\n stp x13, x14, [sp, #96]\n stp x15, x18, [sp, #112]\n"
        " stp q0, q1, [sp, #128]\n stp q2, q3, [sp, #160]\n stp q4, q5, [sp, #192]\n stp q6, q7, [sp, #224]\n"
        " stp q16, q17, [sp, #256]\n stp q18, q19, [sp, #288]\n stp q20, q21, [sp, #320]\n stp q22, q23, [sp, #352]\n"
        " stp q24, q25, [sp, #384]\n stp q26, q27, [sp, #416]\n stp q28, q29, [sp, #448]\n stp q30, q31, [sp, #480]\n"
        " bl _scion_tlv_slow\n"
        " ldp x1, x2, [sp, #0]\n ldp x3, x4, [sp, #16]\n ldp x5, x6, [sp, #32]\n ldp x7, x8, [sp, #48]\n"
        " ldp x9, x10, [sp, #64]\n ldp x11, x12, [sp, #80]\n ldp x13, x14, [sp, #96]\n ldp x15, x18, [sp, #112]\n"
        " ldp q0, q1, [sp, #128]\n ldp q2, q3, [sp, #160]\n ldp q4, q5, [sp, #192]\n ldp q6, q7, [sp, #224]\n"
        " ldp q16, q17, [sp, #256]\n ldp q18, q19, [sp, #288]\n ldp q20, q21, [sp, #320]\n ldp q22, q23, [sp, #352]\n"
        " ldp q24, q25, [sp, #384]\n ldp q26, q27, [sp, #416]\n ldp q28, q29, [sp, #448]\n ldp q30, q31, [sp, #480]\n"
        " mov sp, x29\n ldp x29, x30, [sp], #16\n ret\n");
__asm__(".globl ___chkstk_darwin\n.p2align 2\n___chkstk_darwin:\n ret\n"); /* arm64 spelling has one underscore less */
#endif

/* ---------- setjmp / longjmp (callee-saved state only; signal masks are not tracked) ---------- */
#ifdef __x86_64__
__asm__(".globl _setjmp, __setjmp, _sigsetjmp\n_setjmp:\n__setjmp:\n_sigsetjmp:\n"
        " movq %rbx, 0(%rdi)\n movq %rbp, 8(%rdi)\n movq %r12, 16(%rdi)\n movq %r13, 24(%rdi)\n movq %r14, 32(%rdi)\n movq %r15, 40(%rdi)\n"
        " leaq 8(%rsp), %rax\n movq %rax, 48(%rdi)\n movq (%rsp), %rax\n movq %rax, 56(%rdi)\n stmxcsr 64(%rdi)\n fnstcw 68(%rdi)\n xorl %eax, %eax\n ret\n"
        ".globl _longjmp, __longjmp, _siglongjmp\n_longjmp:\n__longjmp:\n_siglongjmp:\n"
        " movl %esi, %eax\n testl %eax, %eax\n jnz 1f\n incl %eax\n1:\n"
        " movq 0(%rdi), %rbx\n movq 8(%rdi), %rbp\n movq 16(%rdi), %r12\n movq 24(%rdi), %r13\n movq 32(%rdi), %r14\n movq 40(%rdi), %r15\n"
        " ldmxcsr 64(%rdi)\n fldcw 68(%rdi)\n movq 48(%rdi), %rsp\n jmpq *56(%rdi)\n");
#else
__asm__(".globl _setjmp, __setjmp, _sigsetjmp\n.p2align 2\n_setjmp:\n__setjmp:\n_sigsetjmp:\n"
        " stp x19, x20, [x0, #0]\n stp x21, x22, [x0, #16]\n stp x23, x24, [x0, #32]\n stp x25, x26, [x0, #48]\n stp x27, x28, [x0, #64]\n"
        " stp x29, x30, [x0, #80]\n mov x16, sp\n str x16, [x0, #96]\n stp d8, d9, [x0, #104]\n stp d10, d11, [x0, #120]\n stp d12, d13, [x0, #136]\n stp d14, d15, [x0, #152]\n"
        " mov w0, #0\n ret\n"
        ".globl _longjmp, __longjmp, _siglongjmp\n.p2align 2\n_longjmp:\n__longjmp:\n_siglongjmp:\n"
        " ldp x19, x20, [x0, #0]\n ldp x21, x22, [x0, #16]\n ldp x23, x24, [x0, #32]\n ldp x25, x26, [x0, #48]\n ldp x27, x28, [x0, #64]\n"
        " ldp x29, x30, [x0, #80]\n ldr x16, [x0, #96]\n mov sp, x16\n ldp d8, d9, [x0, #104]\n ldp d10, d11, [x0, #120]\n ldp d12, d13, [x0, #136]\n ldp d14, d15, [x0, #152]\n"
        " cmp w1, #0\n csinc w0, w1, wzr, ne\n ret\n");
#endif

/* ---------- compiler-rt builtins the runtimes need (128-bit division) ---------- */
typedef unsigned __int128 u128; typedef __int128 i128;
static u128 udivmod128(u128 n, u128 d, u128 *rem) {
    if (!d) __builtin_trap();
    u128 q = 0, r = 0;
    if (!(n >> 64) && !(d >> 64)) { uint64_t a = (uint64_t)n, b = (uint64_t)d; if (rem) *rem = a % b; return a / b; }
    for (int i = 127; i >= 0; i--) { r = r << 1 | (n >> i & 1); if (r >= d) { r -= d; q |= (u128)1 << i; } }
    if (rem) *rem = r;
    return q;
}
u128 __udivti3(u128 a, u128 b) { return udivmod128(a, b, 0); }
u128 __umodti3(u128 a, u128 b) { u128 r; udivmod128(a, b, &r); return r; }
i128 __divti3(i128 a, i128 b) { u128 q = udivmod128(a < 0 ? -(u128)a : (u128)a, b < 0 ? -(u128)b : (u128)b, 0); return (a < 0) != (b < 0) ? -(i128)q : (i128)q; }
i128 __modti3(i128 a, i128 b) { u128 r; udivmod128(a < 0 ? -(u128)a : (u128)a, b < 0 ? -(u128)b : (u128)b, &r); return a < 0 ? -(i128)r : (i128)r; }
u128 __udivmodti4(u128 a, u128 b, u128 *rem) { return udivmod128(a, b, rem); }

/* ---------- ulock (libc++ atomic wait, os_unfair_lock) on WaitOnAddress ---------- */
int __ulock_wait(uint32_t op, void *addr, uint64_t val, uint32_t timeout_us) {
    int64_t r = H(futex, addr, 0, (uint32_t)val, timeout_us ? (int64_t)timeout_us * 1000 : -1);
    return r < 0 ? fail((int)-r) : 0;
}
int __ulock_wait2(uint32_t op, void *addr, uint64_t val, uint64_t timeout_ns, uint64_t val2) {
    int64_t r = H(futex, addr, 0, (uint32_t)val, timeout_ns ? (int64_t)timeout_ns : -1);
    return r < 0 ? fail((int)-r) : 0;
}
int __ulock_wake(uint32_t op, void *addr, uint64_t wake_value) { H(futex, addr, op & 0x100 ? 2 : 1, 0, 0); return 0; }
int scion_link(int symbolic, const char *from, const char *to) { return (int)ret(H(link, symbolic, from, to)); }

/* ---------- instruction cache: guest code that was written or patched (JITs, dlopen'd code) ---------- */
void sys_icache_invalidate(void *a, size_t n) { H(icache, a, n); }
void sys_dcache_flush(void *a, size_t n) { (void)a; (void)n; }
void __clear_cache(void *b, void *e) { H(icache, b, (char *)e - (char *)b); }
/* MAP_JIT pages are RWX here, so the W^X toggle has nothing to do */
void pthread_jit_write_protect_np(int enabled) { (void)enabled; }
int pthread_jit_write_protect_supported_np(void) { return 1; }
int fchdir(int fd) { char p[1024]; return fcntl(fd, 50, p) ? -1 : chdir(p); }

/* alarm(): a watchdog thread raises SIGALRM when the deadline passes (tests use it to stop a hang) */
static volatile int64_t alarm_at; /* clock(1) ns, 0 = none */
static void *alarm_thread(void *p) {
    for (;;) {
        int64_t at = alarm_at, now = H(clock, 1);
        if (at && now >= at) { alarm_at = 0; raise_self(14 /* SIGALRM */); }
        H(sleep, 50000000);
    }
    return 0;
}
unsigned alarm(unsigned s) {
    static int started;
    int64_t now = H(clock, 1), old = alarm_at;
    alarm_at = s ? now + (int64_t)s * 1000000000 : 0;
    if (s && !started) { started = 1; pthread_t t; pthread_create(&t, 0, alarm_thread, 0); }
    return old && old > now ? (unsigned)((old - now + 999999999) / 1000000000) : 0;
}
/* QoS: every thread is default class */
int pthread_set_qos_class_self_np(unsigned qos, int rel) { return 0; }
int pthread_attr_set_qos_class_np(uint64_t *a, unsigned qos, int rel) { return 0; }
/* task_threads: no Mach thread enumeration (callers use it for diagnostics) */
int task_threads(unsigned task, unsigned **threads, unsigned *n) { if (threads) *threads = 0; if (n) *n = 0; return 5 /* KERN_FAILURE */; }
int pthread_get_qos_class_np(pthread_t t, unsigned *qos, int *rel) { if (qos) *qos = 0x15; if (rel) *rel = 0; return 0; }

/* ---- mach_wait_until, sysctl extras */
/* mach time is in ns here (mach_timebase_info 1/1) */
int mach_wait_until(uint64_t deadline) {
    uint64_t now = mach_absolute_time();
    if (deadline > now) { struct timespec ts = {(int64_t)((deadline - now) / 1000000000ull), (int64_t)((deadline - now) % 1000000000ull)}; nanosleep(&ts, 0); }
    return 0;
}
/* thread names are not kept (pthread_setname_np does nothing): an empty name */
int pthread_getname_np(void *t, char *name, size_t len) { if (len) name[0] = 0; return 0; }
/* per-thread instruction and cycle counters (private libSystem call): not available */
int thread_selfcounts(int type, void *buf, size_t n) { memset(buf, 0, n); return -1; }
/* ponytail: no stack walk; crash reports come from the host (mw_backtrace) */
int backtrace(void **buf, int n) { return 0; }
void backtrace_symbols_fd(void *const *buf, int n, int fd) { }
char **backtrace_symbols(void *const *buf, int n) { return calloc(1, sizeof(char *)); }
/* POSIX dirname: in place, "." for no slash, "/" for the root */
char *dirname(char *p) {
    static char dot[] = ".", slash[] = "/";
    if (!p || !*p) return dot;
    size_t n = strlen(p);
    while (n > 1 && p[n - 1] == '/') n--;
    while (n && p[n - 1] != '/') n--;
    if (!n) return dot;
    while (n > 1 && p[n - 1] == '/') n--;
    p[n] = 0;
    return n == 1 && p[0] == '/' ? slash : p;
}

/* `@available` / `if #available` (compiler-rt): scion is macOS 14.6 (as NSProcessInfo and kern.osrelease say) */
static int mw_os_at_least(uint32_t major, uint32_t minor, uint32_t sub) {
    uint32_t v[3] = {14, 6, 0}, w[3] = {major, minor, sub};
    for (int i = 0; i < 3; i++) if (v[i] != w[i]) return v[i] > w[i];
    return 1;
}
int32_t __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t sub) { return platform == 1 /* macOS */ && mw_os_at_least(major, minor, sub); }
int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t sub) { return mw_os_at_least((uint32_t)major, (uint32_t)minor, (uint32_t)sub); }

/* ---- for the Swift runtime */
float remainderf(float x, float y) { return x - rintf(x / y) * y; }
void memset_pattern8(void *d, const void *pat, size_t n) { char *a = d; const char *b = pat; for (size_t i = 0; i < n; i++) a[i] = b[i & 7]; }
void memset_pattern4(void *d, const void *pat, size_t n) { char *a = d; const char *b = pat; for (size_t i = 0; i < n; i++) a[i] = b[i & 3]; }
struct os_system_version_s { unsigned major, minor, patch; };
int os_system_version_get_current_version(struct os_system_version_s *v) { v->major = 14; v->minor = 6; v->patch = 0; return 0; }
/* one malloc zone (ponytail: every pointer is said to come from it) */
static struct { void *reserved[2]; const char *zone_name; } mw_zone = {{0, 0}, "DefaultMallocZone"};
void *malloc_default_zone(void) { return &mw_zone; }
void *malloc_zone_from_ptr(const void *p) { return p ? &mw_zone : 0; }
/* dyld: built against a recent SDK; no shared cache, so no ObjC constants in it */
typedef struct { uint32_t platform, version; } dyld_build_version_t;
int dyld_program_sdk_at_least(dyld_build_version_t v) { return 1; }
int _dyld_is_objc_constant(int kind, const void *addr) { return 0; }
const char *dyld_image_path_containing_address(const void *a) { const struct mw_image *im = image_for((uintptr_t)a); return im ? im->path : 0; }
int32_t __isPlatformOrVariantPlatformVersionAtLeast(uint32_t p1, uint32_t maj1, uint32_t min1, uint32_t sub1, uint32_t p2, uint32_t maj2, uint32_t min2, uint32_t sub2) {
    return __isPlatformVersionAtLeast(p1, maj1, min1, sub1) || __isPlatformVersionAtLeast(p2, maj2, min2, sub2);
}

/* long double math (x86_64: 80-bit; Swift's Float80). ponytail: computed in double precision */
double cos(double); double sin(double); double exp(double); double exp2(double); double log(double); double log2(double);
double log10(double); double fmod(double, double);
#define LD1(f) long double f##l(long double x) { return (long double)f((double)x); }
#define LD2(f) long double f##l(long double x, long double y) { return (long double)f((double)x, (double)y); }
LD1(ceil) LD1(floor) LD1(round) LD1(trunc) LD1(rint) LD1(nearbyint) LD1(cos) LD1(sin) LD1(exp) LD1(exp2) LD1(log) LD1(log2) LD1(log10)
LD2(fmod) LD2(remainder)
double tan(double); double asin(double); double acos(double); double atan(double); double sinh(double); double cosh(double);
double tanh(double); double asinh(double); double acosh(double); double atanh(double); double expm1(double); double log1p(double);
double cbrt(double); double erf(double); double erfc(double); double tgamma(double); double lgamma(double); double logb(double);
LD1(tan) LD1(asin) LD1(acos) LD1(atan) LD1(sinh) LD1(cosh) LD1(tanh) LD1(asinh) LD1(acosh) LD1(atanh) LD1(expm1) LD1(log1p)
LD1(cbrt) LD1(erf) LD1(erfc) LD1(tgamma) LD1(lgamma) LD1(logb)
double atan2(double, double); double hypot(double, double); double pow(double, double); double copysign(double, double);
double fdim(double, double); double fmax(double, double); double fmin(double, double);
LD2(atan2) LD2(hypot) LD2(pow) LD2(copysign) LD2(fdim) LD2(fmax) LD2(fmin)
long double nextafterl(long double x, long double y) { return nextafter((double)x, (double)y); } /* ponytail: a double ulp */
long double remquol(long double x, long double y, int *q) { return remquo((double)x, (double)y, q); }
long double fmal(long double x, long double y, long double z) { return (long double)fma((double)x, (double)y, (double)z); }
/* float -> IEEE half (compiler-rt __truncsfhf2): round to nearest even */
uint16_t __truncsfhf2(float f) {
    union { float f; uint32_t u; } v = {f};
    uint32_t sign = (v.u >> 16) & 0x8000, e = (v.u >> 23) & 0xff, m = v.u & 0x7fffff;
    if (e == 0xff) return (uint16_t)(sign | 0x7c00 | (m ? 0x200 | (m >> 13) : 0));
    int ex = (int)e - 127 + 15;
    if (ex >= 31) return (uint16_t)(sign | 0x7c00);
    if (ex <= 0) {
        if (ex < -10) return (uint16_t)sign;
        m |= 0x800000;
        uint32_t shift = (uint32_t)(14 - ex), h = m >> shift, rem = m & ((1u << shift) - 1), half = 1u << (shift - 1);
        if (rem > half || (rem == half && (h & 1))) h++;
        return (uint16_t)(sign | h);
    }
    uint32_t h = ((uint32_t)ex << 10) | (m >> 13), rem = m & 0x1fff;
    if (rem > 0x1000 || (rem == 0x1000 && (h & 1))) h++;
    return (uint16_t)(sign | h);
}
int clock_getres(int clk, struct timespec *ts) { if (ts) { ts->tv_sec = 0; ts->tv_nsec = 1; } return 0; }
int memset_s(void *s, size_t smax, int c, size_t n) { if (!s) return 22; memset(s, c, n < smax ? n : smax); return n > smax ? 84 : 0; }
/* without Foundation, the main run loop is the main dispatch queue (Swift's async main runs there) */
void dispatch_main(void);
void CFRunLoopRun(void) { dispatch_main(); }

/* ---------- sockets and name resolution (the host translates Darwin's values: net.cpp) ---------- */
typedef uint32_t socklen_t;
int socket(int d, int t, int p) { return (int)ret(H(net, NET_SOCKET, d, t, p)); }
int socketpair(int d, int t, int p, int sv[2]) { return (int)ret(H(net, NET_SOCKETPAIR, d, t, p, sv)); }
int connect(int s, const void *a, socklen_t n) { return (int)ret(H(net, NET_CONNECT, s, a, n)); }
int bind(int s, const void *a, socklen_t n) { return (int)ret(H(net, NET_BIND, s, a, n)); }
int listen(int s, int backlog) { return (int)ret(H(net, NET_LISTEN, s, backlog)); }
int accept(int s, void *a, socklen_t *n) { return (int)ret(H(net, NET_ACCEPT, s, a, n)); }
int shutdown(int s, int how) { return (int)ret(H(net, NET_SHUTDOWN, s, how)); }
int getsockopt(int s, int l, int o, void *v, socklen_t *n) { return (int)ret(H(net, NET_GETSOCKOPT, s, l, o, v, n)); }
int setsockopt(int s, int l, int o, const void *v, socklen_t n) { return (int)ret(H(net, NET_SETSOCKOPT, s, l, o, v, n)); }
int getsockname(int s, void *a, socklen_t *n) { return (int)ret(H(net, NET_SOCKNAME, s, a, n, 0)); }
int getpeername(int s, void *a, socklen_t *n) { return (int)ret(H(net, NET_SOCKNAME, s, a, n, 1)); }
ssize_t sendto(int s, const void *b, size_t n, int f, const void *a, socklen_t al) {
    struct dnetio io = {(uint64_t)b, n, f, al, (uint64_t)a};
    return ret(H(net, NET_SEND, s, &io));
}
ssize_t recvfrom(int s, void *b, size_t n, int f, void *a, socklen_t *al) {
    struct dnetio io = {(uint64_t)b, n, f, a && al ? *al : 0, a && al ? (uint64_t)a : 0};
    ssize_t r = ret(H(net, NET_RECV, s, &io));
    if (r >= 0 && a && al) *al = io.addrlen;
    return r;
}
ssize_t send(int s, const void *b, size_t n, int f) { return sendto(s, b, n, f, 0, 0); }
ssize_t recv(int s, void *b, size_t n, int f) { return recvfrom(s, b, n, f, 0, 0); }
struct iovec { void *base; size_t len; };
struct msghdr { void *name; socklen_t namelen; struct iovec *iov; int iovlen; void *control; socklen_t controllen; int flags; };
/* gathered into one buffer (ponytail: no control messages, so no descriptor passing) */
ssize_t sendmsg(int s, const struct msghdr *m, int f) {
    size_t n = 0; for (int i = 0; i < m->iovlen; i++) n += m->iov[i].len;
    char *b = malloc(n ? n : 1), *p = b; if (!b) return fail(D_ENOMEM);
    for (int i = 0; i < m->iovlen; i++) { memcpy(p, m->iov[i].base, m->iov[i].len); p += m->iov[i].len; }
    ssize_t r = sendto(s, b, n, f, m->name, m->name ? m->namelen : 0);
    free(b); return r;
}
ssize_t recvmsg(int s, struct msghdr *m, int f) {
    size_t n = 0; for (int i = 0; i < m->iovlen; i++) n += m->iov[i].len;
    char *b = malloc(n ? n : 1); if (!b) return fail(D_ENOMEM);
    socklen_t al = m->name ? m->namelen : 0;
    ssize_t r = recvfrom(s, b, n, f, m->name, m->name ? &al : 0);
    if (r >= 0) {
        size_t left = (size_t)r; char *p = b;
        for (int i = 0; i < m->iovlen && left; i++) { size_t k = m->iov[i].len < left ? m->iov[i].len : left; memcpy(m->iov[i].base, p, k); p += k; left -= k; }
        if (m->name) m->namelen = al;
        m->controllen = 0; m->flags = 0;
    }
    free(b); return r;
}
/* the $NOCANCEL and $UNIX2003 names some binaries import */
int accept_nc(int s, void *a, socklen_t *n) __asm__("_accept$NOCANCEL");
int accept_nc(int s, void *a, socklen_t *n) { return accept(s, a, n); }
int connect_nc(int s, const void *a, socklen_t n) __asm__("_connect$NOCANCEL");
int connect_nc(int s, const void *a, socklen_t n) { return connect(s, a, n); }
ssize_t sendto_nc(int s, const void *b, size_t n, int f, const void *a, socklen_t al) __asm__("_sendto$NOCANCEL");
ssize_t sendto_nc(int s, const void *b, size_t n, int f, const void *a, socklen_t al) { return sendto(s, b, n, f, a, al); }
ssize_t recvfrom_nc(int s, void *b, size_t n, int f, void *a, socklen_t *al) __asm__("_recvfrom$NOCANCEL");
ssize_t recvfrom_nc(int s, void *b, size_t n, int f, void *a, socklen_t *al) { return recvfrom(s, b, n, f, a, al); }
ssize_t sendmsg_nc(int s, const struct msghdr *m, int f) __asm__("_sendmsg$NOCANCEL");
ssize_t sendmsg_nc(int s, const struct msghdr *m, int f) { return sendmsg(s, m, f); }
ssize_t recvmsg_nc(int s, struct msghdr *m, int f) __asm__("_recvmsg$NOCANCEL");
ssize_t recvmsg_nc(int s, struct msghdr *m, int f) { return recvmsg(s, m, f); }

int poll(struct dpollfd *fds, unsigned n, int timeout) {
    return (int)ret(H(net, NET_POLL, fds, n, timeout < 0 ? -1 : (int64_t)timeout * 1000000));
}
int poll_nc(struct dpollfd *fds, unsigned n, int timeout) __asm__("_poll$NOCANCEL");
int poll_nc(struct dpollfd *fds, unsigned n, int timeout) { return poll(fds, n, timeout); }
/* select on poll: fd_set is 1024 bits */
typedef struct { int32_t bits[32]; } fd_set_;
static int fdisset(const fd_set_ *s, int fd) { return s && (s->bits[fd / 32] >> (fd % 32)) & 1; }
int select(int nfds, fd_set_ *r, fd_set_ *w, fd_set_ *x, struct timeval *tv) {
    if (nfds < 0 || nfds > 1024) return fail(D_EINVAL);
    struct dpollfd p[1024]; int n = 0;
    for (int fd = 0; fd < nfds; fd++) {
        short ev = (fdisset(r, fd) ? 1 : 0) | (fdisset(w, fd) ? 4 : 0) | (fdisset(x, fd) ? 2 : 0);
        if (ev) { p[n].fd = fd; p[n].events = ev; p[n].revents = 0; n++; }
    }
    int64_t t = tv ? tv->tv_sec * 1000000000 + (int64_t)tv->tv_usec * 1000 : -1;
    int64_t got = ret(H(net, NET_POLL, p, n, t));
    if (got < 0) return -1;
    if (r) memset(r, 0, (size_t)(nfds + 7) / 8);
    if (w) memset(w, 0, (size_t)(nfds + 7) / 8);
    if (x) memset(x, 0, (size_t)(nfds + 7) / 8);
    int c = 0;
    for (int i = 0; i < n; i++) {
        int fd = p[i].fd, rv = p[i].revents;
        if (rv & 0x20) return fail(D_EBADF);
        if (r && (p[i].events & 1) && (rv & (1 | 0x10 | 8))) { r->bits[fd / 32] |= 1 << (fd % 32); c++; }
        if (w && (p[i].events & 4) && (rv & (4 | 0x10 | 8))) { w->bits[fd / 32] |= 1 << (fd % 32); c++; }
        if (x && (p[i].events & 2) && (rv & 2)) { x->bits[fd / 32] |= 1 << (fd % 32); c++; }
    }
    return c;
}
int select_1050(int n, fd_set_ *r, fd_set_ *w, fd_set_ *x, struct timeval *tv) __asm__("_select$1050");
int select_1050(int n, fd_set_ *r, fd_set_ *w, fd_set_ *x, struct timeval *tv) { return select(n, r, w, x, tv); }
int select_x(int n, fd_set_ *r, fd_set_ *w, fd_set_ *x, struct timeval *tv) __asm__("_select$DARWIN_EXTSN");
int select_x(int n, fd_set_ *r, fd_set_ *w, fd_set_ *x, struct timeval *tv) { return select(n, r, w, x, tv); }
int select_xnc(int n, fd_set_ *r, fd_set_ *w, fd_set_ *x, struct timeval *tv) __asm__("_select$DARWIN_EXTSN$NOCANCEL");
int select_xnc(int n, fd_set_ *r, fd_set_ *w, fd_set_ *x, struct timeval *tv) { return select(n, r, w, x, tv); }
int pselect(int n, fd_set_ *r, fd_set_ *w, fd_set_ *x, const struct timespec *ts, const void *mask) {
    struct timeval tv; if (ts) { tv.tv_sec = ts->tv_sec; tv.tv_usec = (int32_t)(ts->tv_nsec / 1000); }
    return select(n, r, w, x, ts ? &tv : 0);
}

/* getaddrinfo: the host resolves; the list is built here, one allocation per entry (freeaddrinfo frees each) */
struct addrinfo { int flags, family, socktype, protocol; socklen_t addrlen; char *canonname; void *addr; struct addrinfo *next; };
void freeaddrinfo(struct addrinfo *a);
int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    if (!node && !service) return 8;   /* EAI_NONAME */
    struct dnetai found[64]; char canon[256] = {0};
    struct dnethints h = {0x600 /* AI_DEFAULT */, 0, 0, 0, (uint64_t)canon, sizeof canon};
    if (hints) { h.flags = hints->flags; h.family = hints->family; h.socktype = hints->socktype; h.protocol = hints->protocol; }
    int64_t n = H(net, NET_RESOLVE, node, service, &h, found, 64);
    if (n < 0) return n <= -1000 ? (int)(-n - 1000) : 11;   /* EAI_x, or EAI_SYSTEM */
    struct addrinfo *head = 0, **tail = &head;
    for (int64_t i = 0; i < n; i++) {
        struct addrinfo *a = malloc(sizeof *a + 28);
        if (!a) { freeaddrinfo(head); return 6; }   /* EAI_MEMORY */
        memset(a, 0, sizeof *a);
        a->flags = h.flags; a->family = found[i].family; a->socktype = found[i].socktype; a->protocol = found[i].protocol;
        a->addrlen = found[i].addrlen; a->addr = a + 1; memcpy(a->addr, found[i].addr, 28);
        if (i == 0 && (h.flags & 2) && canon[0]) { a->canonname = malloc(strlen(canon) + 1); if (a->canonname) strcpy(a->canonname, canon); }
        *tail = a; tail = &a->next;
    }
    *res = head;
    return 0;
}
void freeaddrinfo(struct addrinfo *a) { while (a) { struct addrinfo *n = a->next; free(a->canonname); free(a); a = n; } }
const char *gai_strerror(int e) {
    switch (e) {
    case 2: return "Temporary failure in name resolution";
    case 3: return "Invalid value for ai_flags";
    case 4: return "Non-recoverable failure in name resolution";
    case 5: return "ai_family not supported";
    case 6: return "Memory allocation failure";
    case 8: return "nodename nor servname provided, or not known";
    case 9: return "servname not supported for ai_socktype";
    case 10: return "ai_socktype not supported";
    case 11: return "System error";
    }
    return "Unknown error";
}
int getnameinfo(const void *sa, socklen_t salen, char *host, socklen_t hostlen, char *serv, socklen_t servlen, int flags) {
    struct dnetni a = {(uint64_t)sa, salen, flags, (uint64_t)host, host ? hostlen : 0, (uint64_t)serv, serv ? servlen : 0};
    return (int)H(net, NET_NAMEINFO, &a);
}

/* textual addresses */
static int hexval(int c) { return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1; }
static int pton4(const char *s, unsigned char *out) {
    for (int i = 0; i < 4; i++) {
        int v = 0, d = 0;
        while (*s >= '0' && *s <= '9') { v = v * 10 + (*s++ - '0'); if (++d > 3 || v > 255) return 0; }
        if (!d || (i < 3 && *s++ != '.')) return 0;
        out[i] = (unsigned char)v;
    }
    return *s == 0;
}
static int pton6(const char *s, unsigned char *out) {
    unsigned char b[16] = {0}; int n = 0, gap = -1;
    if (s[0] == ':' && s[1] == ':') { gap = 0; s += 2; }
    while (*s && n < 16) {
        const char *start = s; int v = 0, d = 0, h;
        while ((h = hexval(*s)) >= 0) { v = v * 16 + h; s++; if (++d > 4) return 0; }
        if (*s == '.') { if (n > 12 || !pton4(start, b + n)) return 0; n += 4; s = start + strlen(start); break; }
        if (!d) return 0;
        b[n++] = (unsigned char)(v >> 8); b[n++] = (unsigned char)v;
        if (*s == ':') { s++; if (*s == ':') { if (gap >= 0) return 0; gap = n; s++; } else if (!*s) return 0; }
        else if (*s) return 0;
    }
    if (*s || (gap < 0 && n != 16)) return 0;
    memset(out, 0, 16);
    if (gap < 0) memcpy(out, b, 16);
    else { memcpy(out, b, (size_t)gap); memcpy(out + 16 - (n - gap), b + gap, (size_t)(n - gap)); }
    return 1;
}
int inet_pton(int af, const char *s, void *dst) {
    if (af == 2) return pton4(s, dst);
    if (af == 30) return pton6(s, dst);
    return fail(D_EAFNOSUPPORT);
}
const char *inet_ntop(int af, const void *src, char *dst, socklen_t size) {
    char t[64]; const unsigned char *a = src;
    if (af == 2) snprintf(t, sizeof t, "%u.%u.%u.%u", a[0], a[1], a[2], a[3]);
    else if (af == 30) {
        int best = -1, bestlen = 0;   /* the longest run of zero groups becomes "::" */
        for (int i = 0; i < 8; i++) {
            int j = i; while (j < 8 && !a[2 * j] && !a[2 * j + 1]) j++;
            if (j - i > bestlen && j - i > 1) { best = i; bestlen = j - i; }
            if (j > i) i = j;
        }
        char *p = t;
        if (best == 0 && bestlen == 5 && a[10] == 0xff && a[11] == 0xff) { snprintf(t, sizeof t, "::ffff:%u.%u.%u.%u", a[12], a[13], a[14], a[15]); goto out; }
        for (int i = 0; i < 8; i++) {
            if (i == best) { *p++ = ':'; if (i == 0) *p++ = ':'; i += bestlen - 1; continue; }
            p += snprintf(p, 8, "%x", a[2 * i] << 8 | a[2 * i + 1]);
            if (i < 7) *p++ = ':';
        }
        *p = 0;
    } else { fail(D_EAFNOSUPPORT); return 0; }
out:
    if (strlen(t) + 1 > size) { fail(28); return 0; }   /* ENOSPC */
    strcpy(dst, t);
    return dst;
}
uint32_t inet_addr(const char *s) { uint32_t a; return pton4(s, (unsigned char *)&a) ? a : 0xffffffffu; }
int inet_aton(const char *s, uint32_t *a) { return pton4(s, (unsigned char *)a); }
char *inet_ntoa(uint32_t a) { static char b[16]; inet_ntop(2, &a, b, sizeof b); return b; }
const unsigned char in6addr_any[16] = {0};
const unsigned char in6addr_loopback[16] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1};
/* FD_SET and friends check the descriptor first */
int __darwin_check_fd_set_overflow(int fd, const void *set, int unlimited) { return fd >= 0 && (unlimited || fd < 1024); }
