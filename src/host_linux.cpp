/* host_linux.cpp — scion host for Linux x86_64, without Wine (#10). The Windows host is host.cpp; both implement the
 * host-call table of hostcalls.h, and dyld.cpp (Mach-O loading) is shared.
 * Work in progress: x86_64 and arm64 (dynarmic, arm64.cpp) command-line programs. Not yet: windows, input and audio
 * (ui), Metal, `scion install`.
 * Linux is closer to Darwin than Windows is: paths are the same, guest file descriptors are host file descriptors,
 * file mappings are real, and x86_64 guests keep %gs for their thread-specific data as on macOS (the gs base is the
 * thread's struct gthread, whose first member is the TSD array). */
#include "scion.h"
#include "metal/mtlbridge.h"
#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/random.h>
#include <sys/xattr.h>
#include <sys/uio.h>
#include <sys/eventfd.h>
#include <linux/futex.h>
#include <asm/prctl.h>
#include <signal.h>
#include <ucontext.h>
#include <pthread.h>
#include <fcntl.h>
#include <poll.h>
#include <sched.h>
#include <time.h>
#include <math.h>
#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <algorithm>
#include <unordered_map>

bool g_trace = false;
bool g_guest_arm = false;
DWORD g_tls_self;
void die(const char *m) { fprintf(stderr, "scion: %s\n", m); fflush(stderr); _exit(70); }
#define HC static HCABI A
/* a guest pointer as host code must use it: inside a vm_remap alias (arm64 guests) it becomes the source page */
static inline A G(A x) { return g_guest_arm ? (A)arm64_translate((uint64_t)x) : x; }
int host_pid() { return getpid(); }

/* ======================================================================= Linux -> Darwin values */
static A derr(int e = errno) {
    switch (e) {
    case EAGAIN: return -D_EAGAIN;
    case EDEADLK: return -11;
    case ENAMETOOLONG: return -D_ENAMETOOLONG;
    case ENOLCK: return -77;
    case ENOSYS: return -D_ENOSYS;
    case ENOTEMPTY: return -D_ENOTEMPTY;
    case ELOOP: return -D_ELOOP;
    case ETIMEDOUT: return -D_ETIMEDOUT;
    case EOPNOTSUPP: return -45;      /* ENOTSUP */
    case ENODATA: return -93;         /* ENOATTR */
    case EOVERFLOW: return -84;
    case ENOTSOCK: return -D_ENOTSOCK;
    }
    return e > 0 && e <= 34 ? -e : -D_EIO;   /* 1..34 are the same on both, except the two above */
}
static A chk(long r) { return r < 0 ? derr() : r; }
static int dfd(A dirfd) { return dirfd == D_AT_FDCWD ? AT_FDCWD : (int)dirfd; }

/* ======================================================================= files */
static A guest_open_flags(A fl) {
    int f = (int)(fl & 3);
    if (fl & D_O_NONBLOCK) f |= O_NONBLOCK;
    if (fl & D_O_APPEND) f |= O_APPEND;
    if (fl & D_O_NOFOLLOW) f |= O_NOFOLLOW;
    if (fl & D_O_CREAT) f |= O_CREAT;
    if (fl & D_O_TRUNC) f |= O_TRUNC;
    if (fl & D_O_EXCL) f |= O_EXCL;
    if (fl & D_O_DIRECTORY) f |= O_DIRECTORY;
    if (fl & D_O_CLOEXEC) f |= O_CLOEXEC;
    return f;
}
HC hc_write(A fd, A buf, A n, A, A, A) { return chk(write((int)fd, (const void *)G(buf), (size_t)n)); }
HC hc_read(A fd, A buf, A n, A, A, A) { return chk(read((int)fd, (void *)G(buf), (size_t)n)); }
HC hc_pread(A fd, A buf, A n, A off, A, A) { return chk(pread((int)fd, (void *)G(buf), (size_t)n, off)); }
HC hc_open(A dirfd, A path, A flags, A mode, A, A) {
    TRACE("open %s\n", (const char *)path);
    return chk(openat(dfd(dirfd), (const char *)path, (int)guest_open_flags(flags), (mode_t)mode));
}
/* readdir state of directory descriptors */
struct DirBuf { std::vector<char> buf; size_t pos = 0, len = 0; };
static std::mutex g_dirmu;
static std::unordered_map<int, DirBuf> g_dirs;
static std::unordered_map<int, uint64_t> g_kq;   /* kqueue (an eventfd) -> EVFILT_USER ident */
HC hc_close(A fd, A, A, A, A, A) {
    { std::lock_guard<std::mutex> l(g_dirmu); g_dirs.erase((int)fd); g_kq.erase((int)fd); }
    return fd <= 2 ? 0 : chk(close((int)fd));   /* the guest closing stdio must not close ours */
}
HC hc_lseek(A fd, A off, A whence, A, A, A) { return chk(lseek((int)fd, off, (int)whence)); }
static void fill_stat(struct dstat *d, const struct stat &s) {
    memset(d, 0, sizeof *d);
    d->dev = (int32_t)s.st_dev; d->mode = (uint16_t)s.st_mode; d->nlink = (uint16_t)s.st_nlink; d->ino = s.st_ino;
    d->uid = s.st_uid; d->gid = s.st_gid; d->rdev = (int32_t)s.st_rdev;
    d->atime = s.st_atim.tv_sec; d->atime_ns = s.st_atim.tv_nsec; d->mtime = s.st_mtim.tv_sec; d->mtime_ns = s.st_mtim.tv_nsec;
    d->ctime = s.st_ctim.tv_sec; d->ctime_ns = s.st_ctim.tv_nsec; d->btime = d->ctime; d->btime_ns = d->ctime_ns;  /* ponytail: statx for btime */
    d->size = s.st_size; d->blocks = s.st_blocks; d->blksize = (int32_t)s.st_blksize;
}
HC hc_stat(A dirfd, A path, A stp, A flags, A, A) {
    struct stat s;
    int r = path ? fstatat(dfd(dirfd), (const char *)path, &s, (flags & D_AT_SYMLINK_NOFOLLOW) ? AT_SYMLINK_NOFOLLOW : 0)
                 : fstat((int)dirfd, &s);
    if (r < 0) return derr();
    fill_stat((struct dstat *)stp, s);
    return 0;
}
HC hc_dup(A fd, A want, A, A, A, A) { return chk(want < 0 ? dup((int)fd) : dup2((int)fd, (int)want)); }
HC hc_getcwd(A buf, A size, A, A, A, A) { if (!getcwd((char *)buf, (size_t)size)) return derr(); return (A)strlen((char *)buf); }
HC hc_mkdir(A path, A mode, A, A, A, A) { return chk(mkdir((const char *)path, mode ? (mode_t)mode : 0777)); }
HC hc_unlink(A path, A isdir, A dirfd, A, A, A) {
    if (unlinkat(dfd(dirfd), (const char *)path, isdir ? AT_REMOVEDIR : 0) == 0) return 0;
    return !isdir && errno == EISDIR ? -D_EPERM : derr();   /* Darwin: unlink() on a directory is EPERM */
}
HC hc_readdir(A fd, A ent, A, A, A, A) {
    std::lock_guard<std::mutex> l(g_dirmu);
    DirBuf &d = g_dirs[(int)fd];
    for (;;) {
        if (d.pos >= d.len) {
            d.buf.resize(32768);
            long n = syscall(SYS_getdents64, (int)fd, d.buf.data(), d.buf.size());
            if (n < 0) return derr();
            if (n == 0) return 0;
            d.pos = 0; d.len = (size_t)n;
        }
        struct de { uint64_t ino; int64_t off; uint16_t reclen; uint8_t type; char name[1]; } *e = (de *)(d.buf.data() + d.pos);
        d.pos += e->reclen;
        if (!strcmp(e->name, ".") || !strcmp(e->name, "..")) continue;   /* as the Windows host */
        struct ddirent *o = (struct ddirent *)ent;
        memset(o, 0, sizeof *o);
        o->ino = e->ino; o->seekoff = (uint64_t)e->off; o->type = e->type;   /* DT_* values are the same */
        o->namlen = (uint16_t)std::min<size_t>(strlen(e->name), 1023);
        memcpy(o->name, e->name, o->namlen);
        o->reclen = sizeof *o;
        return 1;
    }
}
HC hc_isatty(A fd, A, A, A, A, A) { return isatty((int)fd); }
HC hc_chdir(A path, A, A, A, A, A) { return chk(chdir((const char *)path)); }
HC hc_ftruncate(A fd, A len, A, A, A, A) { return chk(ftruncate((int)fd, len)); }
HC hc_rename(A a, A b, A, A, A, A) { return chk(rename((const char *)a, (const char *)b)); }
HC hc_realpath(A path, A out, A fd, A, A, A) {   /* path == 0: the path of descriptor fd (F_GETPATH) */
    char buf[PATH_MAX];
    if (!path) {
        char link[64]; snprintf(link, sizeof link, "/proc/self/fd/%d", (int)fd);
        ssize_t n = readlink(link, buf, sizeof buf - 1); if (n < 0) return derr(); buf[n] = 0;
    } else if (!realpath((const char *)path, buf)) return derr();
    if (strlen(buf) >= 1024) return -D_ENAMETOOLONG;
    strcpy((char *)out, buf);
    return 0;
}
HC hc_pipe(A fds, A, A, A, A, A) { return chk(pipe((int *)fds)); }
HC hc_link(A sym, A from, A to, A, A, A) { return chk(sym ? symlink((const char *)from, (const char *)to) : link((const char *)from, (const char *)to)); }
/* extended attributes: Linux's user.* namespace */
HC hc_xattr(A op, A fd, A path, A name, A buf, A size) {
    const char *p = (const char *)path;
    std::string n = name ? "user." + std::string((const char *)name) : "";
    long r;
    switch (op) {
    case 0: r = p ? getxattr(p, n.c_str(), (void *)buf, (size_t)size) : fgetxattr((int)fd, n.c_str(), (void *)buf, (size_t)size); break;
    case 1: r = p ? setxattr(p, n.c_str(), (const void *)buf, (size_t)size, 0) : fsetxattr((int)fd, n.c_str(), (const void *)buf, (size_t)size, 0); break;
    case 2: r = p ? removexattr(p, n.c_str()) : fremovexattr((int)fd, n.c_str()); break;
    default: {
        std::vector<char> all(65536);
        r = p ? listxattr(p, all.data(), all.size()) : flistxattr((int)fd, all.data(), all.size());
        if (r < 0) break;
        std::string out;
        for (const char *c = all.data(); c < all.data() + r; c += strlen(c) + 1)
            if (!strncmp(c, "user.", 5)) { out += c + 5; out += '\0'; }
        if (buf) { if (out.size() > (size_t)size) return -34; /* ERANGE */ memcpy((void *)buf, out.data(), out.size()); }
        return (A)out.size();
    }
    }
    return r < 0 ? derr() : r;
}

/* ======================================================================= memory */
/* Guest memory without a fixed address goes below 2^39, from 4 GB up, as on macOS arm64: guest code (JS engines,
 * emulators) checks that its pointers fit in 39 bits. ponytail: a moving cursor and MAP_FIXED_NOREPLACE probes */
static void *low_map(size_t n, int prot, int flags, int fd, off_t off) {
    static std::atomic<uint64_t> cursor{1ull << 32};
    n = (n + 0xFFFF) & ~(size_t)0xFFFF;
    for (int pass = 0; pass < 2; pass++)
        for (uint64_t a = pass ? 1ull << 32 : cursor.load(); a + n <= (1ull << 39); a += std::max<size_t>(n, 1 << 20)) {
            void *p = mmap((void *)a, n, prot, flags | MAP_FIXED_NOREPLACE, fd, off);
            if (p != MAP_FAILED) { cursor = a + n; return p; }
            if (errno != EEXIST) break;
        }
    void *p = mmap(nullptr, n, prot, flags, fd, off);
    return p == MAP_FAILED ? nullptr : p;
}
void *image_alloc(uint64_t at, uint64_t len) {
    void *p = at ? mmap((void *)at, len, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0) : MAP_FAILED;
    return p != MAP_FAILED ? p : low_map(len, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
}
const uint8_t *host_map_file(const std::string &path, size_t *size) {
    int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC); if (fd < 0) return nullptr;
    struct stat st; void *p = fstat(fd, &st) || !st.st_size ? MAP_FAILED : mmap(nullptr, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (p == MAP_FAILED) return nullptr;
    *size = (size_t)st.st_size; return (const uint8_t *)p;
}
bool host_map_segment(void *dst, uint64_t len, const std::string &path, uint64_t off) {
    if (((uint64_t)dst | len | off) & 0xFFF) return false;
    int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC); if (fd < 0) return false;
    void *p = mmap(dst, len, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_FIXED, fd, (off_t)off);   /* noexec mounts refuse */
    close(fd);
    return p == dst;
}
void *low_alloc(size_t n, DWORD, DWORD) { return low_map(n, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); }
/* host_mem_query: a copy of /proc/self/maps, parsed again when an answer would come from a region that guest code
 * unmapped or reprotected since (or the address is not in the copy). Reading it again on every change made threads
 * that start and end all the time queue up behind each other on the mutex. */
struct MapRegion { uint64_t lo, hi; int prot; };
static std::mutex g_maps_mu;
static std::vector<MapRegion> g_maps;
static std::vector<std::pair<uint64_t, uint64_t>> g_maps_dirty;   /* [lo, hi) changed since the copy */
static bool g_maps_loaded;
static void maps_changed(uint64_t a, uint64_t n) {
    { std::lock_guard<std::mutex> l(g_maps_mu); g_maps_dirty.push_back({a, a + n}); }
    if (g_guest_arm) arm64_mem_changed();
}
static void maps_load() {
    g_maps.clear(); g_maps_dirty.clear(); g_maps_loaded = true;
    FILE *f = fopen("/proc/self/maps", "r"); if (!f) return;
    char line[512];
    while (fgets(line, sizeof line, f)) {
        unsigned long long lo, hi; char p[5] = "";
        if (sscanf(line, "%llx-%llx %4s", &lo, &hi, p) != 3) continue;
        g_maps.push_back({lo, hi, (p[0] == 'r' ? D_PROT_READ : 0) | (p[1] == 'w' ? D_PROT_WRITE : 0) | (p[2] == 'x' ? D_PROT_EXEC : 0)});
    }
    fclose(f);
}
bool host_mem_query(uint64_t a, uint64_t *lo, uint64_t *hi, int *prot) {
    std::lock_guard<std::mutex> l(g_maps_mu);
    if (!g_maps_loaded || g_maps_dirty.size() > 64) maps_load();
    for (int pass = 0; pass < 2; pass++) {
        if (pass) maps_load();
        auto it = std::upper_bound(g_maps.begin(), g_maps.end(), a, [](uint64_t x, const MapRegion &r) { return x < r.lo; });
        if (it == g_maps.begin() || a >= (--it)->hi) continue;
        bool stale = false;
        for (auto &d : g_maps_dirty) if (d.first < it->hi && it->lo < d.second) { stale = true; break; }
        if (stale) continue;
        *lo = it->lo; *hi = it->hi; *prot = it->prot; return true;
    }
    return false;
}
HC hc_mmap(A addr, A len, A prot, A flags, A fd, A off) {
    int f = (flags & D_MAP_SHARED ? MAP_SHARED : MAP_PRIVATE) | (flags & D_MAP_ANON ? MAP_ANONYMOUS : 0);
    int pr = (int)(prot & 7), hfd = flags & D_MAP_ANON ? -1 : (int)fd;
    if (!pr) f |= MAP_NORESERVE;
    void *p;
    if (flags & D_MAP_FIXED) {
        if (g_guest_arm) { arm64_alias_set((uint64_t)addr, ((uint64_t)len + 0xFFF) & ~0xFFFull, 0); arm64_invalidate((uint64_t)addr, (uint64_t)len); }
        p = mmap((void *)addr, (size_t)len, pr, f | MAP_FIXED, hfd, off);
    }
    else {
        p = addr ? mmap((void *)addr, (size_t)len, pr, f | MAP_FIXED_NOREPLACE, hfd, off) : MAP_FAILED;
        if (p == MAP_FAILED) p = low_map((size_t)len, pr, f, hfd, off);
        if (!p) p = MAP_FAILED;
    }
    if (p == MAP_FAILED) return derr();
    if (flags & D_MAP_FIXED) maps_changed((uint64_t)p, (uint64_t)len);   /* it may replace mappings; one in a hole changes no answer */
    return (A)p;
}
HC hc_munmap(A addr, A len, A, A, A, A) {
    if (g_guest_arm) { arm64_alias_set((uint64_t)addr, ((uint64_t)len + 0xFFF) & ~0xFFFull, 0); arm64_invalidate((uint64_t)addr, (uint64_t)len); }
    A r = chk(munmap((void *)addr, (size_t)len));
    maps_changed((uint64_t)addr, (uint64_t)len);
    return r;
}
HC hc_mprotect(A addr, A len, A prot, A, A, A) {
    /* an alias (vm_remap without copy) is only a translation: protect the pages it shows.
     * ponytail: so both mappings change, and the range is assumed to lie in one alias */
    addr = G(addr);
    uint64_t a = addr & ~0xFFFull, n = ((uint64_t)addr + len - a + 0xFFF) & ~0xFFFull;
    if (g_guest_arm) arm64_invalidate(a, n);   /* executable code may have changed */
    A r = chk(mprotect((void *)a, n, (int)(prot & 7)));
    maps_changed(a, n);
    return r;
}
/* copy without faulting (mach_vm_read_overwrite / mach_vm_write): the kernel reports a bad address as EFAULT */
HC hc_safecopy(A dst, A src, A n, A need_w, A, A) {
    dst = G(dst); src = G(src);
    struct iovec d = {(void *)dst, (size_t)n}, s = {(void *)src, (size_t)n};
    ssize_t r = need_w ? process_vm_writev(getpid(), &s, 1, &d, 1, 0) : process_vm_readv(getpid(), &d, 1, &s, 1, 0);
    return r == (ssize_t)n ? 0 : -D_EFAULT;
}
static bool readable(uint64_t a, size_t n) { uint64_t tmp[4]; return n <= sizeof tmp && hc_safecopy((A)tmp, (A)a, (A)n, 0, 0, 0) == 0; }
HC hc_icache(A a, A n, A, A, A, A) { if (g_guest_arm) arm64_invalidate((uint64_t)a, (uint64_t)n); return 0; }   /* x86 is coherent */
/* vm_remap(copy=FALSE), arm64 guests: dst stays inaccessible and the JIT redirects its accesses to src (arm64.cpp) */
HC hc_alias(A dst, A len, A src, A fixed, A cur, A) {
    if (!g_guest_arm) return -45;   /* ENOTSUP: x86_64 guests run natively, there is no software path to redirect them */
    uint64_t n = ((uint64_t)len + 0xFFF) & ~0xFFFull, s = arm64_translate((uint64_t)src), lo, hi; int prot;
    if (!n || !host_mem_query(s, &lo, &hi, &prot)) return -D_EINVAL;
    void *d = fixed ? mmap((void *)dst, n, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED, -1, 0)
                    : low_map(n, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (!d || d == MAP_FAILED) return -D_ENOMEM;
    maps_changed((uint64_t)d, n);
    arm64_invalidate((uint64_t)d, n);
    arm64_alias_set((uint64_t)d, n, s);
    if (cur) *(int *)cur = prot;
    TRACE("vm_remap alias %llx -> %llx (%llu bytes)\n", (unsigned long long)d, (unsigned long long)s, (unsigned long long)n);
    return (A)d;
}

/* ======================================================================= process, time */
HC hc_getpid(A, A, A, A, A, A) { return getpid(); }
HCABI A hc_exit(A code, A, A, A, A, A) {
    TRACE("exit(%lld)\n", (long long)code);
    if (g_guest_arm) arm64_exit();
    if (g_trace) for (auto &m : g_missing) fprintf(stderr, "[scion] unimplemented import: %s\n", m.c_str());
    fflush(stdout); fflush(stderr);
    _exit((int)code);
}
HC hc_sleep(A ns, A, A, A, A, A) {
    if (ns < 1000000) { sched_yield(); return 0; }
    struct timespec t = {ns / 1000000000, ns % 1000000000};
    while (nanosleep(&t, &t) && errno == EINTR) {}
    return 0;
}
HCABI A hc_clock(A kind, A, A, A, A, A) {
    static const clockid_t ids[] = {CLOCK_REALTIME, CLOCK_MONOTONIC, CLOCK_THREAD_CPUTIME_ID, CLOCK_PROCESS_CPUTIME_ID};
    struct timespec t; clock_gettime(ids[kind >= 0 && kind < 4 ? kind : 1], &t);
    return (A)t.tv_sec * 1000000000 + t.tv_nsec;
}
HC hc_random(A buf, A n, A, A, A, A) {
    buf = G(buf);
    for (A got = 0; got < n;) { ssize_t r = getrandom((char *)buf + got, (size_t)(n - got), 0); if (r > 0) got += r; else if (errno != EINTR) return derr(); }
    return 0;
}
HC hc_ncpu(A, A, A, A, A, A) { return sysconf(_SC_NPROCESSORS_ONLN); }
HC hc_math(A op, A a, A b, A c, A, A) {
    double x, y, z, r = 0; memcpy(&x, &a, 8); memcpy(&y, &b, 8); memcpy(&z, &c, 8);
    switch (op) {
    case M_SIN: r = sin(x); break; case M_COS: r = cos(x); break; case M_TAN: r = tan(x); break;
    case M_ASIN: r = asin(x); break; case M_ACOS: r = acos(x); break; case M_ATAN: r = atan(x); break;
    case M_ATAN2: r = atan2(x, y); break; case M_SINH: r = sinh(x); break; case M_COSH: r = cosh(x); break;
    case M_TANH: r = tanh(x); break; case M_ASINH: r = asinh(x); break; case M_ACOSH: r = acosh(x); break;
    case M_ATANH: r = atanh(x); break; case M_EXP: r = exp(x); break; case M_EXPM1: r = expm1(x); break;
    case M_LOG: r = log(x); break; case M_LOG10: r = log10(x); break; case M_LOG1P: r = log1p(x); break;
    case M_LOG2: r = log2(x); break; case M_POW: r = pow(x, y); break; case M_CBRT: r = cbrt(x); break;
    case M_HYPOT: r = hypot(x, y); break; case M_FMOD: r = fmod(x, y); break; case M_FMA: r = fma(x, y, z); break;
    case M_EXP2: r = exp2(x); break; case M_ERF: r = erf(x); break; case M_ERFC: r = erfc(x); break;
    case M_TGAMMA: r = tgamma(x); break; case M_LGAMMA: r = lgamma(x); break;
    case M_J0: r = j0(x); break; case M_J1: r = j1(x); break; case M_JN: r = jn((int)y, x); break;
    case M_Y0: r = y0(x); break; case M_Y1: r = y1(x); break; case M_YN: r = yn((int)y, x); break;
    }
    A out; memcpy(&out, &r, 8); return out;
}

/* ======================================================================= locks, futexes, kqueue */
static long futex(void *a, int op, uint32_t v, A timeout_ns = -1) {
    struct timespec t = {timeout_ns / 1000000000, timeout_ns % 1000000000};
    return syscall(SYS_futex, a, op | FUTEX_PRIVATE_FLAG, v, timeout_ns < 0 ? nullptr : &t, nullptr, 0);
}
/* The guest's lock is one zeroed 8-byte word (an SRWLOCK on Windows): here a reader-writer lock in its low 32 bits.
 * ponytail: unfair (readers can starve a writer), every release with waiters wakes them all */
enum : uint32_t { RW_WRITER = 1u << 31, RW_WAITERS = 1u << 30 };
static void rw_wait(std::atomic<uint32_t> *w, uint32_t s) {
    if (!(s & RW_WAITERS) && !w->compare_exchange_strong(s, s | RW_WAITERS)) return;
    futex(w, FUTEX_WAIT, s | RW_WAITERS);
}
static void rw_wake(std::atomic<uint32_t> *w) { futex(w, FUTEX_WAKE, INT_MAX); }
static void lock_ex(std::atomic<uint32_t> *w) {
    for (;;) {
        uint32_t s = w->load();
        if (!(s & ~RW_WAITERS)) { if (w->compare_exchange_weak(s, s | RW_WRITER)) return; continue; }
        rw_wait(w, s);
    }
}
static void unlock_ex(std::atomic<uint32_t> *w) { if (w->exchange(0) & RW_WAITERS) rw_wake(w); }
HC hc_lock(A l, A op, A, A, A, A) {
    l = G(l);
    auto *w = (std::atomic<uint32_t> *)l;
    switch (op) {
    case 0: lock_ex(w); return 0;
    case 1: unlock_ex(w); return 0;
    case 2: { uint32_t s = w->load(); return !(s & ~RW_WAITERS) && w->compare_exchange_strong(s, s | RW_WRITER); }
    case 3:
        for (;;) {
            uint32_t s = w->load();
            if (!(s & RW_WRITER)) { if (w->compare_exchange_weak(s, s + 1)) return 0; continue; }
            rw_wait(w, s);
        }
    case 4: {
        uint32_t s = w->fetch_sub(1) - 1, x = RW_WAITERS;
        if (s == RW_WAITERS && w->compare_exchange_strong(x, 0)) rw_wake(w);
        return 0;
    }
    default: { uint32_t s = w->load(); return !(s & RW_WRITER) && w->compare_exchange_strong(s, s + 1); }
    }
}
/* condition variable: a sequence number in the guest's 8-byte word; waits hold the lock exclusively */
HC hc_cond(A cv, A l, A op, A timeout, A, A) {
    cv = G(cv); l = G(l);
    auto *seq = (std::atomic<uint32_t> *)cv;
    if (op) { seq->fetch_add(1); futex(seq, FUTEX_WAKE, op == 1 ? 1 : INT_MAX); return 0; }
    uint32_t s = seq->load();
    unlock_ex((std::atomic<uint32_t> *)l);
    long r = futex(seq, FUTEX_WAIT, s, timeout);
    int e = errno;
    lock_ex((std::atomic<uint32_t> *)l);
    return r < 0 && e == ETIMEDOUT ? -D_ETIMEDOUT : 0;
}
HC hc_futex(A addr, A op, A val, A timeout, A, A) {
    addr = G(addr);
    if (op) { futex((void *)addr, FUTEX_WAKE, op == 1 ? 1 : INT_MAX); return 0; }
    return futex((void *)addr, FUTEX_WAIT, (uint32_t)val, timeout) < 0 && errno == ETIMEDOUT ? -D_ETIMEDOUT : 0;
}
/* kqueue: only EVFILT_USER (Go's netpoll wakeup), on an eventfd; registering fds fails, callers then block on I/O */
HC hc_kqueue(A, A, A, A, A, A) {
    int fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK); if (fd < 0) return derr();
    std::lock_guard<std::mutex> l(g_dirmu); g_kq[fd] = 0;
    return fd;
}
HC hc_kevent(A kq, A chp, A nch, A evp, A nev, A timeout) {
    uint64_t *ident;
    { std::lock_guard<std::mutex> l(g_dirmu); auto it = g_kq.find((int)kq); if (it == g_kq.end()) return -D_EBADF; ident = &it->second; }
    struct dkevent *ch = (struct dkevent *)chp, *ev = (struct dkevent *)evp;
    for (A i = 0; i < nch; i++) {
        if (ch[i].filter != D_EVFILT_USER) return -D_EINVAL;
        if (ch[i].flags & D_EV_ADD) *ident = ch[i].ident;
        if (ch[i].fflags & D_NOTE_TRIGGER) { uint64_t one = 1; if (write((int)kq, &one, 8)) {} }
    }
    if (nev <= 0) return 0;
    struct pollfd p = {(int)kq, POLLIN, 0};
    if (poll(&p, 1, timeout < 0 ? -1 : (int)((timeout + 999999) / 1000000)) <= 0) return 0;
    uint64_t v; if (read((int)kq, &v, 8)) {}
    memset(ev, 0, sizeof *ev); ev->ident = *ident; ev->filter = D_EVFILT_USER;
    return 1;
}

/* ======================================================================= threads */
/* host-private per-thread state, in gthread.handle (gthread.host is the arm64 JIT's) */
struct HostThread { pthread_t pt; std::atomic<uint64_t> pending{0}; std::atomic<int> suspend{0}; ucontext_t *uc = nullptr; std::atomic<int> parked{0}; };
static thread_local struct gthread *tl_self;
struct gthread *cur_gthread() { return tl_self; }
static HostThread *ht(struct gthread *t) { return (HostThread *)t->handle; }
static std::mutex g_thrmu;
static std::vector<struct gthread *> g_threads;   /* mach thread port = 0x1000 + index */
static struct gthread *alloc_gthread() {
    struct gthread *t = (struct gthread *)mmap(nullptr, sizeof(struct gthread), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    t->tsd[0] = (uint64_t)t;   /* Darwin: slot 0 = pthread self */
    t->handle = (uint64_t)new HostThread;
    std::lock_guard<std::mutex> l(g_thrmu);
    t->port = 0x1000 + (uint32_t)g_threads.size();
    g_threads.push_back(t);
    return t;
}
static struct gthread *thread_by_port(A port) {
    std::lock_guard<std::mutex> l(g_thrmu);
    return port >= 0x1000 && port - 0x1000 < (A)g_threads.size() ? g_threads[port - 0x1000] : nullptr;
}
/* bind a gthread to the calling host thread: %gs points at it (TSD slot k at %gs:8k, as on macOS) */
static struct gthread *enter_gthread(struct gthread *t) {
    tl_self = t;
    t->tid = (uint64_t)syscall(SYS_gettid);
    ht(t)->pt = pthread_self();
    pthread_attr_t a; void *lo; size_t sz;
    if (!pthread_getattr_np(pthread_self(), &a)) { pthread_attr_getstack(&a, &lo, &sz); pthread_attr_destroy(&a); t->stack_top = (uint64_t)lo + sz; t->stack_size = sz; }
    if (syscall(SYS_arch_prctl, ARCH_SET_GS, (unsigned long)t)) die("arch_prctl(ARCH_SET_GS) failed");
    stack_t ss = {mmap(nullptr, 65536, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0), 0, 65536};
    sigaltstack(&ss, nullptr);   /* host handlers run here, so a guest stack overflow is still reported */
    return t;
}
HC hc_self(A, A, A, A, A, A) { return (A)tl_self; }
struct ThreadStart { A start, arg, stacksize; struct gthread *t; };
static void *thread_entry(void *p) {
    ThreadStart ts = *(ThreadStart *)p; delete (ThreadStart *)p;
    struct gthread *t = enter_gthread(ts.t);
    if (!g_guest_arm) { ((SYSV void *(*)(void *))ts.start)((void *)ts.arg); return nullptr; }
    /* arm64 guests run on a stack of their own; the host thread's small stack is the JIT's */
    uint8_t *stk = (uint8_t *)low_alloc((size_t)ts.stacksize, 0, 0);
    t->stack_top = (uint64_t)(stk + ts.stacksize); t->stack_size = (uint64_t)ts.stacksize;
    uint64_t a[1] = {(uint64_t)ts.arg};
    run_arm64((uint64_t)ts.start, a, 1, t->stack_top, t);
    arm64_thread_end();
    munmap(stk, (size_t)ts.stacksize);   /* games and servers start and end threads all the time */
    maps_changed((uint64_t)stk, (uint64_t)ts.stacksize);
    t->stack_top = 0;
    return nullptr;
}
HC hc_thread(A start, A arg, A stacksize, A, A, A) {
    if (stacksize < 256 * 1024) stacksize = 256 * 1024;
    struct gthread *t = alloc_gthread();
    pthread_attr_t a; pthread_attr_init(&a); pthread_attr_setstacksize(&a, g_guest_arm ? 1 << 20 : (size_t)stacksize);
    pthread_t pt;
    int r = pthread_create(&pt, &a, thread_entry, new ThreadStart{start, arg, stacksize, t});
    pthread_attr_destroy(&a);
    if (r) return -D_EAGAIN;
    ht(t)->pt = pt;
    return (A)t;
}
HC hc_join(A t, A, A, A, A, A) { pthread_join(ht((struct gthread *)t)->pt, nullptr); return 0; }

/* ======================================================================= signals (x86_64 guests) */
struct dsigaction g_sig[64];
static std::mutex g_sigmu;
static const int SIG_GUEST = SIGRTMIN + 1, SIG_SUSPEND = SIGRTMIN + 2;   /* async guest signals, thread_suspend */
HC hc_sigaction(A sig, A act, A old, A, A, A) {
    if (sig <= 0 || sig >= 64) return -D_EINVAL;
    std::lock_guard<std::mutex> l(g_sigmu);
    if (old) *(struct dsigaction *)old = g_sig[sig];
    if (act) g_sig[sig] = *(const struct dsigaction *)act;
    return 0;
}
HC hc_sigaltstack(A ss, A old, A, A, A, A) {
    struct gthread *t = tl_self;
    if (old) { struct dstack *o = (struct dstack *)old; o->sp = t->alt_sp; o->size = t->alt_size; o->flags = t->alt_size ? t->alt_flags : D_SS_DISABLE; }
    if (ss) { const struct dstack *n = (const struct dstack *)ss; t->alt_sp = n->sp; t->alt_size = n->size; t->alt_flags = n->flags; }
    return 0;
}
static void print_guest_addr(const char *tag, uint64_t x) {
    for (Image *i : g_images) {
        if (x < (uint64_t)i->base || x >= (uint64_t)i->base + i->size) continue;
        const char *sn = ""; uint64_t sa = 0;
        for (auto &kv : i->syms) if (kv.second <= x && kv.second > sa) { sa = kv.second; sn = kv.first.c_str(); }
        fprintf(stderr, "  %s %llx %s+0x%llx %s+0x%llx\n", tag, (unsigned long long)x, i->dpath.c_str(), (unsigned long long)(x - (uint64_t)i->base), sn, (unsigned long long)(x - sa));
        return;
    }
    fprintf(stderr, "  %s %llx ?\n", tag, (unsigned long long)x);
}
static void guest_backtrace(uint64_t pc, uint64_t fp) {
    if (pc) print_guest_addr("pc", pc);
    for (int n = 0; n < 24 && fp && !(fp & 7) && readable(fp, 16); n++) {
        uint64_t next = ((uint64_t *)fp)[0], ret = ((uint64_t *)fp)[1];
        if (!ret) break;
        print_guest_addr("  ", ret);
        if (next <= fp) break;
        fp = next;
    }
}
HC hc_log(A msg, A fp, A, A, A, A) { fprintf(stderr, "[scion] %s\n", (const char *)msg); if (fp) guest_backtrace(0, (uint64_t)fp); return 0; }
static const char *signame(int s) {
    switch (s) { case D_SIGSEGV: return "Segmentation fault: 11"; case D_SIGBUS: return "Bus error: 10"; case D_SIGILL: return "Illegal instruction: 4";
                 case D_SIGFPE: return "Floating point exception: 8"; case D_SIGTRAP: return "Trace/BPT trap: 5"; case D_SIGABRT: return "Abort trap: 6"; }
    return "fatal signal";
}
/* The host handler never runs guest code: it rewrites the interrupted context so that, when the kernel returns to
 * it, sigtramp_x86 runs on the guest (or guest alternate) stack, calls the guest handler and then HC_sigreturn,
 * which restores the (possibly edited) context itself. */
struct alignas(64) SigFrameX86 {
    uint64_t handler, sig, info, uc;
    struct dsiginfo si; uint64_t pad0;
    struct ducontext uc_; uint64_t pad1;
    struct dmcontext_x86 mc;
    alignas(16) uint8_t fx[512];   /* the interrupted FPU/SSE state (fxsave layout) */
    uint64_t iret[5];              /* rip, cs, rflags, rsp, ss */
};
extern "C" void sigtramp_x86();
asm(".globl sigtramp_x86\nsigtramp_x86:\n"
    " mov (%rsp), %rax\n mov 8(%rsp), %rdi\n mov 16(%rsp), %rsi\n mov 24(%rsp), %rdx\n mov %rsp, %rbx\n"
    " call *%rax\n"                        /* SysV: rbx survives the handler */
    " mov 24(%rbx), %rdi\n mov %rbx, %rsp\n and $-16, %rsp\n"
    " call hc_sigreturn_entry\n ud2\n");
static bool redirect_x86(ucontext_t *uc, int sig, int code, uint64_t addr, struct gthread *t) {
    greg_t *g = uc->uc_mcontext.gregs;
    struct dsigaction a; { std::lock_guard<std::mutex> l(g_sigmu); a = g_sig[sig]; if (a.flags & D_SA_RESETHAND) g_sig[sig].handler = 0; }
    if (a.handler == 1 && sig != D_SIGSEGV && sig != D_SIGBUS && sig != D_SIGILL && sig != D_SIGFPE) return false;   /* SIG_IGN */
    if (a.handler <= 1) {   /* SIG_DFL */
        if (dsig_default_ignored(sig)) return false;
        fprintf(stderr, "scion: %s (pc=%llx addr=%llx)\n", signame(sig), (unsigned long long)g[REG_RIP], (unsigned long long)addr);
        guest_backtrace((uint64_t)g[REG_RIP], (uint64_t)g[REG_RBP]);
        hc_exit(128 + sig, 0, 0, 0, 0, 0);
    }
    uint64_t rsp = (uint64_t)g[REG_RSP];
    bool alt_ok = t && t->alt_size && !(t->alt_flags & D_SS_DISABLE), on_alt = alt_ok && rsp >= t->alt_sp && rsp < t->alt_sp + t->alt_size;
    uint64_t sp = (a.flags & D_SA_ONSTACK) && alt_ok && !on_alt ? t->alt_sp + t->alt_size : rsp - 128;
    SigFrameX86 *f = (SigFrameX86 *)((sp - sizeof(SigFrameX86)) & ~63ull);
    memset((void *)f, 0, sizeof *f);
    if (uc->uc_mcontext.fpregs) memcpy(f->fx, uc->uc_mcontext.fpregs, 512);
    f->handler = a.handler; f->sig = sig; f->info = (uint64_t)&f->si; f->uc = (uint64_t)&f->uc_;
    f->si.signo = sig; f->si.code = code; f->si.addr = addr; f->si.pid = getpid();
    f->uc_.onstack = on_alt; f->uc_.mcsize = sizeof f->mc; f->uc_.mcontext = (uint64_t)&f->mc;
    if (t) { f->uc_.stack.sp = t->alt_sp; f->uc_.stack.size = t->alt_size; f->uc_.stack.flags = t->alt_flags; }
    struct dmcontext_x86 &m = f->mc;
    m.trapno = sig == D_SIGSEGV ? 14 : sig == D_SIGFPE ? 0 : sig == D_SIGILL ? 6 : 3; m.faultvaddr = addr; m.err = code == 2 ? 6 : 4;
    m.rax = g[REG_RAX]; m.rbx = g[REG_RBX]; m.rcx = g[REG_RCX]; m.rdx = g[REG_RDX]; m.rdi = g[REG_RDI]; m.rsi = g[REG_RSI];
    m.rbp = g[REG_RBP]; m.rsp = g[REG_RSP]; m.r8 = g[REG_R8]; m.r9 = g[REG_R9]; m.r10 = g[REG_R10]; m.r11 = g[REG_R11];
    m.r12 = g[REG_R12]; m.r13 = g[REG_R13]; m.r14 = g[REG_R14]; m.r15 = g[REG_R15]; m.rip = g[REG_RIP]; m.rflags = g[REG_EFL]; m.cs = 0x2b;
    g[REG_RSP] = (greg_t)f; g[REG_RIP] = (greg_t)sigtramp_x86;
    if (t) t->in_handler++;
    return true;
}
/* restore a context without the kernel: fxrstor + registers, then iretq, so rip, rsp and rflags change at once and
 * the interrupted code's red zone is never touched */
extern "C" [[noreturn]] void hc_sigreturn_entry(struct ducontext *uc) {
    SigFrameX86 *f = (SigFrameX86 *)((uint8_t *)uc - offsetof(SigFrameX86, uc_));
    if (struct gthread *t = tl_self; t && t->in_handler > 0) t->in_handler--;
    struct dmcontext_x86 &m = f->mc;
    uint16_t cs, ss; asm("mov %%cs, %0\n mov %%ss, %1" : "=r"(cs), "=r"(ss));
    uint64_t rfl; asm volatile("pushfq\n pop %0" : "=r"(rfl));
    f->iret[0] = m.rip; f->iret[1] = cs; f->iret[2] = (rfl & ~0xCD5ull) | (m.rflags & 0xCD5ull); f->iret[3] = m.rsp; f->iret[4] = ss;
    uint64_t r[16] = {m.rax, m.rbx, m.rcx, m.rdx, m.rsi, m.rdi, m.rbp, m.r8, m.r9, m.r10, m.r11, m.r12, m.r13, m.r14, m.r15,
                      (uint64_t)f->iret};
    asm volatile(
        "fxrstor (%1)\n mov 120(%0), %%rsp\n"
        "mov 8(%0), %%rbx\n mov 16(%0), %%rcx\n mov 24(%0), %%rdx\n mov 32(%0), %%rsi\n mov 40(%0), %%rdi\n mov 48(%0), %%rbp\n"
        "mov 56(%0), %%r8\n mov 64(%0), %%r9\n mov 72(%0), %%r10\n mov 80(%0), %%r11\n mov 88(%0), %%r12\n mov 96(%0), %%r13\n"
        "mov 104(%0), %%r14\n mov 112(%0), %%r15\n mov (%0), %%rax\n iretq\n"
        :: "a"(r), "c"(f->fx) : "memory");
    __builtin_unreachable();
}
HC hc_sigreturn(A uc, A, A, A, A, A) { hc_sigreturn_entry((struct ducontext *)uc); }
static void host_crash(int sig, siginfo_t *si, ucontext_t *uc) {
    fprintf(stderr, "[scion] signal %d in the host, address %p, pc %llx\n", sig, si->si_addr, (unsigned long long)uc->uc_mcontext.gregs[REG_RIP]);
    signal(sig, SIG_DFL);   /* returning re-faults with the default action: a core dump for a debugger */
}
static void on_fault(int sig, siginfo_t *si, void *ucv) {
    ucontext_t *uc = (ucontext_t *)ucv; greg_t *g = uc->uc_mcontext.gregs;
    uint64_t rip = (uint64_t)g[REG_RIP];
    /* a guest call through a NULL (or tiny) function pointer faults outside guest code: its return address tells */
    bool null_call = rip < 0x10000 && sig == SIGSEGV && readable((uint64_t)g[REG_RSP], 8) && guest_pc(*(uint64_t *)g[REG_RSP]);
    if (!guest_pc(rip) && !null_call) { host_crash(sig, si, uc); return; }
    int ds, code = 0; uint64_t addr = (uint64_t)si->si_addr;
    switch (sig) {
    case SIGSEGV: ds = D_SIGSEGV; code = si->si_code == SEGV_ACCERR ? 2 : 1; break;
    case SIGBUS: ds = D_SIGBUS; code = 1; break;
    case SIGILL: ds = D_SIGILL; code = 1; break;
    case SIGFPE: ds = D_SIGFPE; code = si->si_code == FPE_INTDIV ? 7 : si->si_code; break;
    default: ds = D_SIGTRAP; break;
    }
    TRACE("signal %d at rip=%llx addr=%llx\n", ds, (unsigned long long)rip, (unsigned long long)addr);
    if (!redirect_x86(uc, ds, code, addr, tl_self)) { if (sig != SIGTRAP) host_crash(sig, si, uc); }
}
/* Asynchronous signals to another guest thread (Go's SIGURG preemption): pending bits in its HostThread and a host
 * signal; it is delivered only while the thread runs guest code and is not in a handler already, otherwise it waits
 * and a pump thread pokes the thread again every millisecond while any is pending (and sleeps otherwise). */
static std::atomic<bool> g_pump_on;
static std::mutex g_pump_mu; static std::condition_variable g_pump_cv; static uint64_t g_pump_seq;
static void on_guest_signal(int, siginfo_t *, void *ucv) {
    struct gthread *t = tl_self; if (!t) return;
    ucontext_t *uc = (ucontext_t *)ucv;
    if (t->in_handler > 0 || !guest_pc((uint64_t)uc->uc_mcontext.gregs[REG_RIP])) return;
    uint64_t p = ht(t)->pending.load();
    for (int s = 1; s < 64; s++) if (p & (1ull << s)) {
        ht(t)->pending.fetch_and(~(1ull << s));
        redirect_x86(uc, s, 0, 0, t);
        return;
    }
}
static void *signal_pump(void *) {
    for (uint64_t seen = 0;;) {
        { std::unique_lock<std::mutex> l(g_pump_mu); g_pump_cv.wait(l, [&] { return g_pump_seq != seen; }); seen = g_pump_seq; }
        for (bool any = true; any;) {
            struct timespec ms = {0, 1000000}; nanosleep(&ms, nullptr);
            std::lock_guard<std::mutex> l(g_thrmu);
            any = false;
            for (struct gthread *t : g_threads) if (ht(t)->pending.load() && t->tid) { pthread_kill(ht(t)->pt, SIG_GUEST); any = true; }
        }
    }
}
HC hc_tkill(A tp, A sig, A, A, A, A) {
    struct gthread *t = (struct gthread *)tp;
    if (!t || !t->handle || sig <= 0 || sig >= 64) return -3;   /* ESRCH */
    if (g_guest_arm) { arm64_signal(t, (int)sig); return 0; }
    ht(t)->pending.fetch_or(1ull << sig);
    if (!g_pump_on.exchange(true)) { pthread_t p; pthread_create(&p, nullptr, signal_pump, nullptr); pthread_detach(p); }
    pthread_kill(ht(t)->pt, SIG_GUEST);
    { std::lock_guard<std::mutex> l(g_pump_mu); g_pump_seq++; } g_pump_cv.notify_one();
    return 0;
}
/* thread_suspend / thread_get_state: the target parks in a host signal handler, its context at hand */
static void on_suspend(int, siginfo_t *, void *ucv) {
    struct gthread *t = tl_self; if (!t) return;
    HostThread *h = ht(t);
    h->uc = (ucontext_t *)ucv; h->parked = 1; futex(&h->parked, FUTEX_WAKE, INT_MAX);
    while (h->suspend.load() > 0) futex(&h->suspend, FUTEX_WAIT, (uint32_t)h->suspend.load());
    h->uc = nullptr; h->parked = 0;
}
HC hc_thread_ctl(A port, A op, A flavor, A state, A, A) {
    struct gthread *t = thread_by_port(port);
    if (!t || !t->handle || t == tl_self) return -1;
    if (g_guest_arm) return arm64_thread_ctl(t, (int)op, (int)flavor, (void *)state);
    HostThread *h = ht(t);
    switch (op) {
    case D_THREAD_SUSPEND:
        if (h->suspend.fetch_add(1) == 0) {
            pthread_kill(h->pt, SIG_SUSPEND);
            while (!h->parked.load()) futex(&h->parked, FUTEX_WAIT, 0, 1000000);
        }
        return 0;
    case D_THREAD_RESUME:
        if (h->suspend.load() > 0 && h->suspend.fetch_sub(1) == 1) futex(&h->suspend, FUTEX_WAKE, INT_MAX);
        return 0;
    }
    if (flavor != D_x86_THREAD_STATE64) return -4;
    if (!h->parked.load() || !h->uc) return -1;
    greg_t *g = h->uc->uc_mcontext.gregs; uint64_t *r = (uint64_t *)state;
    static const int map[] = {REG_RAX, REG_RBX, REG_RCX, REG_RDX, REG_RDI, REG_RSI, REG_RBP, REG_RSP, REG_R8, REG_R9,
                              REG_R10, REG_R11, REG_R12, REG_R13, REG_R14, REG_R15, REG_RIP};
    if (op == D_THREAD_GET_STATE) { for (int i = 0; i < 17; i++) r[i] = (uint64_t)g[map[i]]; r[17] = (uint64_t)g[REG_EFL]; r[18] = 0x2b; r[19] = r[20] = 0; return 0; }
    for (int i = 0; i < 17; i++) g[map[i]] = (greg_t)r[i];
    g[REG_EFL] = (greg_t)r[17];
    return 0;
}

/* ======================================================================= not yet on Linux */
/* Metal: the host half lives in scion-metal.so (Indium on Vulkan + AIR -> SPIR-V), loaded on first use */
bool ui_native_window(uint64_t sdl_window, uint32_t w, uint32_t h, const char *title, MwNativeWindow *out);   /* ui_linux.cpp */
static std::string exe_dir();
HC hc_metal(A op, A a, A b, A c, A d, A e) {
    typedef int64_t (*fn_t)(int, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
    static fn_t fn; static std::once_flag once;
    std::call_once(once, [] {
        void *m = dlopen((exe_dir() + "/scion-metal.so").c_str(), RTLD_NOW | RTLD_LOCAL);
        if (m) fn = (fn_t)dlsym(m, "mw_metal");
        if (!fn) fprintf(stderr, "scion: could not load scion-metal.so (Metal is not available): %s\n", dlerror());
    });
    if (!fn) return 0;
    MwNativeWindow nw;
    if (op == MW_NEW_LAYER) {   /* the AppKit window's SDL window (UI_WINDOW_HWND), or a window of the layer's own */
        if (!ui_native_window((uint64_t)e, (uint32_t)a, (uint32_t)b, (const char *)c, &nw)) return 0;
        e = (A)&nw;
    }
    /* data the guest hands over may lie in a vm_remap alias (arm64); the other arguments are handles and sizes */
    MwRegionCopy rc;
    if (op == MW_TEXTURE_REPLACE || op == MW_TEXTURE_GETBYTES) { rc = *(MwRegionCopy *)G(b); rc.bytes = G(rc.bytes); b = (A)&rc; }
    else b = G(b);
    return fn((int)op, (uint64_t)G(a), (uint64_t)b, (uint64_t)G(c), (uint64_t)G(d), op == MW_NEW_LAYER ? (uint64_t)e : (uint64_t)G(e));
}

/* ======================================================================= dyld services for the guest */
static void publish_image(Image *im) {
    struct MwImage { uint64_t mh; int64_t slide; const char *path; };
    MwImage *t = (MwImage *)g_libsys->syms["_scion_images"];
    uint32_t *n = (uint32_t *)g_libsys->syms["_scion_image_count"];
    if (!t || !n || *n >= 512) return;
    bool sys = !im->install_name.empty() && !im->path.rfind(g_lib_dir, 0);
    im->dpath = sys ? im->install_name : im->path;
    t[*n] = {im->mh_rt(), im->slide, im->dpath.c_str()};
    __atomic_store_n(n, *n + 1, __ATOMIC_RELEASE);
}
static void prepare_image(Image *im) { link_image(*im); setup_tlv(*im); publish_image(im); }
static std::recursive_mutex g_dlmu;
static std::string g_dlerr;
struct DlInfo { const char *fname; uint64_t fbase; const char *sname; uint64_t saddr; };
HC hc_dl(A op, A a, A b, A, A, A) {
    std::lock_guard<std::recursive_mutex> l(g_dlmu);
    if (op == 0) {   /* dlopen */
        if (!a) return (A)g_main;
        std::string name = (const char *)a;
        for (Image *i : g_images) if (i->dpath == name || i->install_name == name) return (A)i;
        struct stat st;
        std::string f = name[0] != '@' && !stat(name.c_str(), &st) && S_ISREG(st.st_mode) ? name : locate_dl(name);
        if (f.empty()) { g_dlerr = "dlopen(" + name + ", 1): image not found"; return 0; }
        for (Image *i : g_images) if (i->path == f) return (A)i;
        size_t before = g_images.size();
        Image *im = load_dl(f);
        if (!im) { g_dlerr = "dlopen(" + name + "): not a compatible Mach-O"; return 0; }
        for (size_t k = before; k < g_images.size(); k++) prepare_image(g_images[k]);
        TRACE("dlopen %s -> %s\n", name.c_str(), f.c_str());
        init_image(im);
        return (A)im;
    }
    if (op == 1) {   /* dlsym: RTLD_NEXT -1, RTLD_DEFAULT -2, RTLD_SELF -3, RTLD_MAIN_ONLY -5 */
        std::string n = std::string("_") + (const char *)b;
        if (a == -5) return (A)dl_sym(g_main, n);
        if (a < 0 && a >= -5) {   /* libSystem last: its CoreFoundation stubs must not hide Foundation's */
            Image *sys = nullptr;
            for (Image *i : g_images) {
                if (i->path.find("libSystem") != std::string::npos) { sys = i; continue; }
                if (uint64_t v = dl_sym(i, n)) return (A)v;
            }
            return sys ? (A)dl_sym(sys, n) : 0;
        }
        return (A)dl_sym((Image *)a, n);
    }
    if (op == 2) {   /* dladdr */
        uint64_t x = (uint64_t)a; DlInfo *d = (DlInfo *)b;
        for (Image *i : g_images) {
            if (x < (uint64_t)i->base || x >= (uint64_t)i->base + i->size) continue;
            d->fname = i->dpath.c_str(); d->fbase = i->mh_rt(); d->sname = nullptr; d->saddr = 0;
            for (auto &kv : i->syms) if (kv.second <= x && kv.second > d->saddr) { d->saddr = kv.second; d->sname = kv.first.c_str() + 1; }
            return 1;
        }
        return 0;
    }
    if (op == 3) { size_t n = std::min<size_t>(g_dlerr.size(), (size_t)b - 1); memcpy((void *)a, g_dlerr.data(), n); ((char *)a)[n] = 0; return 0; }
    return 0;
}

hostfn g_hc[HC_COUNT] = {
#define HC_IMPL(n) hc_##n,
    HOSTCALLS(HC_IMPL)
#undef HC_IMPL
};

/* ======================================================================= startup */
uint64_t call_guest(uint64_t fn, const uint64_t *a, int n) {
    if (g_guest_arm) { struct gthread *t = tl_self; return run_arm64(fn, a, n, t->stack_top - 64 * 1024, t); }
    uint64_t r[6] = {0};
    for (int i = 0; i < n && i < 6; i++) r[i] = a[i];
    return ((SYSV uint64_t (*)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t))fn)(r[0], r[1], r[2], r[3], r[4], r[5]);
}
extern "C" void __attribute__((noreturn)) jump_unixthread(uint64_t sp, uint64_t pc);
asm(".globl jump_unixthread\njump_unixthread:\n mov %rdi, %rsp\n xor %eax, %eax\n xor %ebx, %ebx\n xor %ebp, %ebp\n jmp *%rsi\n");

struct Startup { Image *main; std::vector<std::string> argv, envp, apple; };
static void *guest_main(void *p) {
    Startup &s = *(Startup *)p;
    struct gthread *t = enter_gthread(alloc_gthread());
    /* kernel layout, contiguous: argc, argv..., 0, envp..., 0, apple..., 0 (Go walks argv past argc to find envp) */
    std::vector<uint64_t> frame{(uint64_t)s.argv.size()};
    for (auto *v : {&s.argv, &s.envp, &s.apple}) { for (auto &str : *v) frame.push_back((uint64_t)&str[0]); frame.push_back(0); }
    char **argv = (char **)&frame[1], **envp = argv + s.argv.size() + 1, **apple = envp + s.envp.size() + 1;
    auto setvar = [](const char *sym, uint64_t v) { auto it = g_libsys->syms.find(sym); if (it != g_libsys->syms.end()) *(uint64_t *)it->second = v; };
    setvar("_NXArgv", (uint64_t)argv); setvar("_environ", (uint64_t)envp);
    *(int *)g_libsys->syms["_NXArgc"] = (int)s.argv.size();
    strncpy((char *)g_libsys->syms["_scion_exe_path"], s.argv[0].c_str(), 1023);
    Image &im = *s.main;
    uint64_t args4[4] = {(uint64_t)s.argv.size(), (uint64_t)argv, (uint64_t)envp, (uint64_t)apple};
    if (im.arm) {
        uint8_t *stk = (uint8_t *)low_alloc(8 << 20, 0, 0);
        t->stack_top = (uint64_t)(stk + (8 << 20)); t->stack_size = 8 << 20;
        if (im.unixthread) die("LC_UNIXTHREAD is not supported for arm64 yet");
        init_all(&im, args4);
        hc_exit((A)run_arm64(im.entry, args4, 4, t->stack_top, t), 0, 0, 0, 0, 0);
    }
    init_all(&im, args4);
    if (im.unixthread) {
        uint64_t *sp = (uint64_t *)alloca(frame.size() * 8 + 64);
        sp = (uint64_t *)(((uint64_t)sp + 15) & ~15ull);
        memcpy(sp, frame.data(), frame.size() * 8);
        jump_unixthread((uint64_t)sp, im.entry);
    }
    int rc = ((SYSV int (*)(int, char **, char **, char **))im.entry)((int)s.argv.size(), argv, envp, apple);
    hc_exit(rc, 0, 0, 0, 0, 0);
    return nullptr;
}
static std::string exe_dir() {
    char b[PATH_MAX]; ssize_t n = readlink("/proc/self/exe", b, sizeof b - 1);
    std::string s(b, n > 0 ? (size_t)n : 0); return s.substr(0, s.find_last_of('/'));
}
bool mw_subcommand_linux(int argc, char **argv, int *rc);   /* install_linux.cpp */

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: scion <macOS program | App.app> [args...]\n"
                        "       scion install <App.app>      menu entry, icon and file types (freedesktop.org)\n"
                        "       scion uninstall <App.app | bundle id>\n"
                        "   SCION_TRACE=1 traces the program; SCION_ARCH=arm64 runs the arm64 slice of a universal binary.\n"
                        "   Linux host (#10): command-line programs for now.\n");
        return 2;
    }
    if (int rc; mw_subcommand_linux(argc, argv, &rc)) return rc;
    g_trace = getenv("SCION_TRACE") != nullptr;
    struct sigaction sa = {}; sa.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_NODEFER;
    sa.sa_sigaction = on_fault;
    for (int s : {SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP}) sigaction(s, &sa, nullptr);
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESTART;
    sa.sa_sigaction = on_guest_signal; sigaction(SIG_GUEST, &sa, nullptr);
    sa.sa_sigaction = on_suspend; sigaction(SIG_SUSPEND, &sa, nullptr);
    signal(SIGPIPE, SIG_IGN);   /* a closed pipe is EPIPE for the guest, as macOS programs expect from their own handlers */

    std::string mainpath = argv[1];
    { std::string exe = mw_bundle_executable(mainpath); if (!exe.empty()) mainpath = exe; }
    g_lib_dir = exe_dir() + "/lib";
    Image *main = load_all(mainpath);
    if (!main) die("not a valid 64-bit Mach-O executable");
    g_guest_arm = main->arm;
    uint64_t *table = (uint64_t *)g_libsys->syms["_scion_hc"];
    if (!table) die("libSystem lacks _scion_hc");
    if (main->arm) {   /* host calls arrive as SVC #n through these thunks (arm64.cpp) */
        arm64_init();
        for (int i = 0; i < HC_COUNT; i++) table[i] = (uint64_t)(g_arm_thunks + 2 * i);
        g_missing_stub = (uint64_t)(g_arm_thunks + 2 * HC_exit);   /* exit(x0) */
    } else {
        for (int i = 0; i < HC_COUNT; i++) table[i] = (uint64_t)g_hc[i];
        g_missing_stub = g_libsys->syms["_dyld_stub_binder"];
    }
    *(uint64_t *)g_libsys->syms["_scion_tsd_off"] = 0;   /* %gs:0 = TSD slot 0 = the struct gthread itself */
    for (size_t k = 0; k < g_images.size(); k++) prepare_image(g_images[k]);
    if (!g_missing.empty()) for (auto &m : g_missing) TRACE("unimplemented import: %s\n", m.c_str());
    if (!main->entry) die("no entry point");

    Startup s; s.main = main;
    s.argv.push_back(mainpath);
    for (int i = 2; i < argc; i++) s.argv.push_back(argv[i]);
    for (char **e = environ; *e; e++) s.envp.push_back(*e);
    s.apple.push_back("executable_path=" + s.argv[0]);
    pthread_attr_t a; pthread_attr_init(&a); pthread_attr_setstacksize(&a, 8 << 20);   /* the main thread's 8 MB, as macOS */
    pthread_t t; if (pthread_create(&t, &a, guest_main, &s)) die("could not start the main thread");
    pthread_join(t, nullptr);
    return 0;
}
