/* scion host for Windows x64.
 *  - dyld-lite: loads the main Mach-O + scion's libSystem.B.dylib, rebases, binds
 *    (classic opcodes and chained fixups), exports trie, initializers, entry (LC_MAIN/LC_UNIXTHREAD)
 *  - CPU: x86_64 guests run natively (SysV<->MS bridged by the guest libSystem),
 *         arm64 guests run under dynarmic; hostcalls arrive as SVC
 *  - hostcalls: Win32 implementation of the narrow interface in hostcalls.h
 */
#include "scion.h"
#include "backtrace.h"
#include "metal/mtlbridge.h"
#include <bcrypt.h>
#include <timeapi.h>
#include <malloc.h>
#include <math.h>
#include <mutex>
#include <memory>
#include <atomic>
#include <algorithm>
#include <map>
#include <unordered_map>
#include <stddef.h>

bool g_trace = false;
void die(const char *m) { fprintf(stderr, "scion: %s\n", m); ExitProcess(70); }

/* ======================================================================= host state */
DWORD g_tls_self; static DWORD g_tls_go;
static std::string g_root; /* directory backing "/" for paths that are not /<drive>/... */
static std::mutex g_fdmu;

enum FdKind { FD_FREE, FD_FILE, FD_DIR, FD_KQ, FD_SOCK };
struct Fd {
    FdKind kind = FD_FREE; HANDLE h = INVALID_HANDLE_VALUE; std::wstring path; bool append = false;
    int dev = 0; /* reads from /dev/zero (1) or /dev/random, /dev/urandom (2): writes go to NUL */
    HANDLE find = INVALID_HANDLE_VALUE; bool find_done = false; WIN32_FIND_DATAW fd{};
    uintptr_t sock = ~(uintptr_t)0; std::shared_ptr<void> sock_owner;   /* FD_SOCK: closed with the last descriptor (net.cpp) */
};
static std::vector<Fd> g_fds;

static int64_t err_from_win(DWORD e = GetLastError()) {
    switch (e) {
    case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: case ERROR_INVALID_NAME: case ERROR_BAD_NETPATH: case ERROR_INVALID_DRIVE: return -D_ENOENT;
    case ERROR_ACCESS_DENIED: case ERROR_SHARING_VIOLATION: return -D_EACCES;
    case ERROR_ALREADY_EXISTS: case ERROR_FILE_EXISTS: return -D_EEXIST;
    case ERROR_DIR_NOT_EMPTY: return -D_ENOTEMPTY;
    case ERROR_NOACCESS: return -D_EFAULT;   /* the buffer is not writable (a protected page), as the kernel says */
    case ERROR_DIRECTORY: return -D_ENOTDIR;
    case ERROR_NOT_ENOUGH_MEMORY: case ERROR_OUTOFMEMORY: return -D_ENOMEM;
    case ERROR_INVALID_HANDLE: return -D_EBADF;
    case ERROR_BROKEN_PIPE: return 0;
    case ERROR_DELETE_PENDING: return -D_ENOENT;
    case ERROR_LOCK_VIOLATION: case ERROR_PRIVILEGE_NOT_HELD: return ERROR_PRIVILEGE_NOT_HELD == e ? -1 /* EPERM */ : -D_EACCES;
    case ERROR_INVALID_PARAMETER: case ERROR_NEGATIVE_SEEK: return -22;  /* EINVAL */
    case ERROR_DISK_FULL: case ERROR_HANDLE_DISK_FULL: return -28;      /* ENOSPC */
    case ERROR_NOT_SAME_DEVICE: return -18;                              /* EXDEV */
    case ERROR_FILENAME_EXCED_RANGE: return -63;                         /* ENAMETOOLONG */
    case ERROR_CANT_RESOLVE_FILENAME: return -62;                        /* ELOOP */
    case ERROR_NOT_SUPPORTED: return -45;                                /* ENOTSUP */
    }
    return -D_EIO;
}

static std::wstring widen(const std::string &s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
    std::wstring w(n ? n - 1 : 0, L'\0');
    if (n) MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &w[0], n);
    return w;
}
static std::string narrow(const std::wstring &w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string s(n ? n - 1 : 0, '\0');
    if (n) WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, &s[0], n, nullptr, nullptr);
    return s;
}

/* "C:\Users\x" -> "/c/Users/x" */
std::string win_to_darwin(const std::string &w) {
    std::string s = w;
    for (char &c : s) if (c == '\\') c = '/';
    if (s.size() >= 2 && isalpha((unsigned char)s[0]) && s[1] == ':') s = std::string("/") + (char)tolower(s[0]) + s.substr(2);
    if (s.size() > 2 && s.back() == '/') s.pop_back();
    return s;
}

/* Darwin path -> Windows path. "/c/x" -> "C:\x", "/dev/null" -> "NUL", other absolute -> g_root\... */
std::wstring darwin_to_win(const char *p, int dirfd) {
    std::string s = p;
    if (s == "/dev/null") return L"NUL";
    if (!s.empty() && s[0] == '/') {
        if (s.size() >= 2 && isalpha((unsigned char)s[1]) && (s.size() == 2 || s[2] == '/'))
            s = std::string(1, (char)toupper(s[1])) + ":" + (s.size() == 2 ? "/" : s.substr(2));
        else if (s.rfind("/tmp", 0) == 0) { char t[MAX_PATH]; GetTempPathA(MAX_PATH, t); s = std::string(t) + s.substr(std::min<size_t>(s.size(), 5)); }
        else s = g_root + s;
    } else if (dirfd >= 0) {
        std::lock_guard<std::mutex> l(g_fdmu);
        if (dirfd < (int)g_fds.size() && g_fds[dirfd].kind == FD_DIR) return g_fds[dirfd].path + L"\\" + widen(s);
    }
    for (char &c : s) if (c == '/') c = '\\';
    return widen(s);
}

/* Anonymous memory goes below 2^39, from 4 GB up, as on macOS arm64 (Wine hands out 47-bit addresses): guest code
 * (Switch emulators, JS engines) checks that its pointers fit in 39 bits. First free gap at or above a moving cursor. */
bool host_mem_query(uint64_t a, uint64_t *lo, uint64_t *hi, int *prot) {
    MEMORY_BASIC_INFORMATION mi;
    if (!VirtualQuery((void *)a, &mi, sizeof mi) || mi.State != MEM_COMMIT) return false;
    *lo = (uint64_t)mi.BaseAddress; *hi = *lo + mi.RegionSize;
    DWORD p = mi.Protect;
    *prot = (p & (PAGE_NOACCESS | PAGE_GUARD)) ? 0
          : (p & (PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) ? 7 : (p & (PAGE_EXECUTE_READ | PAGE_EXECUTE)) ? 5
          : (p & (PAGE_READWRITE | PAGE_WRITECOPY)) ? 3 : (p & PAGE_READONLY) ? 1 : 0;
    return true;
}
int host_pid() { return (int)GetCurrentProcessId(); }
void *image_alloc(uint64_t at, uint64_t len) {
    /* an image with no address of its own (dylibs linked at 0) goes where low_alloc puts it, not where Windows would
     * (a random address): the same place every run, so the arm64 code cache on disk finds its code again */
    void *p = at ? VirtualAlloc((void *)at, len, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE) : nullptr;
    return p ? p : low_alloc(len, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
}
/* read into memory rather than mapped: a mapped file cannot be replaced while the app runs (self-updaters) */
const uint8_t *host_map_file(const std::string &path, size_t *size) {
    HANDLE f = CreateFileW(widen(path).c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE) return nullptr;
    LARGE_INTEGER n{}; uint8_t *p = nullptr; DWORD got = 0;
    if (GetFileSizeEx(f, &n) && n.QuadPart > 0 && n.QuadPart < (1ll << 32) && (p = (uint8_t *)malloc((size_t)n.QuadPart))
        && !(ReadFile(f, p, (DWORD)n.QuadPart, &got, nullptr) && got == (DWORD)n.QuadPart)) { free(p); p = nullptr; }
    CloseHandle(f);
    if (p) *size = (size_t)n.QuadPart;
    return p;
}
/* ponytail: Windows maps views only at 64 KB-aligned free addresses, not over the image's allocation: copied */
bool host_map_segment(void *, uint64_t, const std::string &, uint64_t) { return false; }
void *low_alloc(size_t n, DWORD type, DWORD prot) {
    static std::atomic<uint64_t> cursor{1ull << 32};
    /* the reservation is whole 64 KB units, but only the pages asked for are committed: munmap decommits exactly
     * those, so a committed tail would stay charged to the process forever (Windows counts commit, not use) */
    size_t want = (n + 0xFFF) & ~(size_t)0xFFF;
    n = (n + 0xFFFF) & ~(size_t)0xFFFF;
    auto get = [&](void *at) -> void * {
        void *p = VirtualAlloc(at, n, MEM_RESERVE, (type & MEM_COMMIT) ? PAGE_NOACCESS : prot);
        if (p && (type & MEM_COMMIT) && !VirtualAlloc(p, want, MEM_COMMIT, prot)) { VirtualFree(p, 0, MEM_RELEASE); return nullptr; }
        return p;
    };
    for (int pass = 0; pass < 2; pass++) {
        MEMORY_BASIC_INFORMATION mi;
        for (uint64_t a = pass ? 1ull << 32 : cursor.load(); a + n <= (1ull << 39) && VirtualQuery((void *)a, &mi, sizeof mi);) {
            uint64_t end = (uint64_t)mi.BaseAddress + mi.RegionSize, s = (a + 0xFFFF) & ~0xFFFFull;
            if (mi.State == MEM_FREE && s + n <= end) {
                if (void *p = get((void *)s)) { cursor = s + n; return p; }
            }
            a = end > a ? end : a + 0x10000;
        }
    }
    return get(nullptr);
}

static int fd_alloc(Fd &&f, int want = -1) {
    std::lock_guard<std::mutex> l(g_fdmu);
    if (want >= 0) {
        if ((int)g_fds.size() <= want) g_fds.resize(want + 1);
        g_fds[want] = std::move(f);
        return want;
    }
    for (size_t i = 0; i < g_fds.size(); i++) if (g_fds[i].kind == FD_FREE) { g_fds[i] = std::move(f); return (int)i; }
    g_fds.push_back(std::move(f));
    return (int)g_fds.size() - 1;
}
static Fd *fd_get(int64_t fd) {
    std::lock_guard<std::mutex> l(g_fdmu);
    return fd >= 0 && fd < (int64_t)g_fds.size() && g_fds[fd].kind != FD_FREE ? &g_fds[fd] : nullptr;
}
/* for net.cpp */
uintptr_t host_fd_socket(int fd) {
    std::lock_guard<std::mutex> l(g_fdmu);
    return fd >= 0 && fd < (int)g_fds.size() && g_fds[fd].kind == FD_SOCK ? g_fds[fd].sock : ~(uintptr_t)0;
}
int host_fd_add_socket(uintptr_t s, std::shared_ptr<void> owner) { Fd f; f.kind = FD_SOCK; f.sock = s; f.sock_owner = std::move(owner); return fd_alloc(std::move(f)); }
int host_fd_add_kqueue() { Fd f; f.kind = FD_KQ; return fd_alloc(std::move(f)); }

static int64_t filetime_ns(FILETIME ft) { return (int64_t)((((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime) - 116444736000000000ull) * 100; }
static uint64_t path_ino(const std::wstring &p) { uint64_t h = 1469598103934665603ull; for (wchar_t c : p) h = (h ^ towlower(c)) * 1099511628211ull; return h; }

static void fill_stat(struct dstat *st, DWORD attrs, FILETIME c, FILETIME a, FILETIME m, uint64_t size, uint64_t ino) {
    memset(st, 0, sizeof *st);
    bool dir = attrs & FILE_ATTRIBUTE_DIRECTORY;
    st->mode = dir ? D_S_IFDIR | 0755 : D_S_IFREG | ((attrs & FILE_ATTRIBUTE_READONLY) ? 0444 : 0644);
    st->nlink = 1; st->ino = ino; st->dev = 1; st->uid = 501; st->gid = 20;
    auto ts = [](FILETIME f, int64_t &s, int64_t &ns) { int64_t t = filetime_ns(f); s = t / 1000000000; ns = t % 1000000000; };
    ts(a, st->atime, st->atime_ns); ts(m, st->mtime, st->mtime_ns); ts(m, st->ctime, st->ctime_ns); ts(c, st->btime, st->btime_ns);
    st->size = dir ? 0 : (int64_t)size; st->blksize = 4096; st->blocks = (st->size + 511) / 512;
}

/* ======================================================================= hostcalls (Win32) */
/* A guest pointer as host code must use it: inside a vm_remap alias (kept inaccessible to the host, see arm64.cpp)
 * it becomes the source page. ponytail: the range is assumed to lie within one alias, as in hc_mprotect */
static inline A G(A x) { return g_guest_arm ? (A)arm64_translate((uint64_t)x) : x; }
static A hc_write(A fd, A buf, A n, A, A, A) {
    buf = G(buf);
    TRACE("write fd=%lld n=%lld\n", (long long)fd, (long long)n);
    Fd *f = fd_get(fd); if (!f || (f->kind != FD_FILE && f->kind != FD_SOCK)) return -D_EBADF;
    if (f->kind == FD_SOCK) return net_sock_io((int)fd, f->sock, (void *)buf, (size_t)n, true);
    if (f->append) { LARGE_INTEGER z{}; SetFilePointerEx(f->h, z, nullptr, FILE_END); }
    DWORD w = 0;
    if (!WriteFile(f->h, (void *)buf, (DWORD)n, &w, nullptr)) return err_from_win();
    return w;
}
static A hc_read(A fd, A buf, A n, A, A, A) {
    buf = G(buf);
    Fd *f = fd_get(fd); if (!f) return -D_EBADF;
    if (f->kind == FD_DIR) return -D_EISDIR;
    if (f->kind == FD_SOCK) return net_sock_io((int)fd, f->sock, (void *)buf, (size_t)n, false);
    if (f->dev == 1) { memset((void *)buf, 0, n); return n; }
    if (f->dev == 2) { BCryptGenRandom(nullptr, (PUCHAR)buf, (ULONG)n, BCRYPT_USE_SYSTEM_PREFERRED_RNG); return n; }
    DWORD r = 0;
    if (!ReadFile(f->h, (void *)buf, (DWORD)n, &r, nullptr)) return err_from_win();
    return r;
}
static A hc_pread(A fd, A buf, A n, A off, A, A) {
    buf = G(buf);
    Fd *f = fd_get(fd); if (!f || f->kind != FD_FILE) return -D_EBADF;
    LARGE_INTEGER cur{}, z{}; SetFilePointerEx(f->h, z, &cur, FILE_CURRENT);
    OVERLAPPED ov{}; ov.Offset = (DWORD)off; ov.OffsetHigh = (DWORD)(off >> 32);
    DWORD r = 0; BOOL ok = ReadFile(f->h, (void *)buf, (DWORD)n, &r, &ov);
    SetFilePointerEx(f->h, cur, nullptr, FILE_BEGIN);
    if (!ok) { DWORD e = GetLastError(); return e == ERROR_HANDLE_EOF ? 0 : err_from_win(e); }
    return r;
}
static A hc_open(A dirfd, A path, A flags, A mode, A, A) {
    const char *dp = (const char *)path;
    int dev = !strcmp(dp, "/dev/zero") ? 1 : !strcmp(dp, "/dev/random") || !strcmp(dp, "/dev/urandom") ? 2 : 0;
    if (dev) {
        HANDLE h = CreateFileW(L"NUL", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
        if (h == INVALID_HANDLE_VALUE) return err_from_win();
        Fd f; f.kind = FD_FILE; f.h = h; f.path = L"NUL"; f.dev = dev;
        return fd_alloc(std::move(f));
    }
    std::wstring wp = darwin_to_win((const char *)path, (int)dirfd);
    DWORD attrs = GetFileAttributesW(wp.c_str());
    bool exists = attrs != INVALID_FILE_ATTRIBUTES, isdir = exists && (attrs & FILE_ATTRIBUTE_DIRECTORY);
    if ((flags & D_O_DIRECTORY) && exists && !isdir) return -D_ENOTDIR;
    if (isdir) {
        if (flags & (D_O_WRONLY | D_O_RDWR)) return -D_EISDIR;
        HANDLE h = CreateFileW(wp.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                               OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
        if (h == INVALID_HANDLE_VALUE) return err_from_win();
        /* absolute: a directory fd keeps naming the same directory after chdir (fchdir, the *at calls) */
        wchar_t full[MAX_PATH * 4]; DWORD fl = GetFullPathNameW(wp.c_str(), MAX_PATH * 4, full, nullptr);
        Fd f; f.kind = FD_DIR; f.h = h; f.path = fl && fl < MAX_PATH * 4 ? std::wstring(full, fl) : wp;
        while (f.path.size() > 3 && f.path.back() == L'\\') f.path.pop_back();
        return fd_alloc(std::move(f));
    }
    DWORD acc = (flags & D_O_RDWR) ? GENERIC_READ | GENERIC_WRITE : (flags & D_O_WRONLY) ? GENERIC_WRITE : GENERIC_READ;
    DWORD disp = OPEN_EXISTING;
    if (flags & D_O_CREAT) disp = (flags & D_O_EXCL) ? CREATE_NEW : (flags & D_O_TRUNC) ? CREATE_ALWAYS : OPEN_ALWAYS;
    else if (flags & D_O_TRUNC) disp = TRUNCATE_EXISTING;
    HANDLE h = CreateFileW(wp.c_str(), acc, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, disp,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return err_from_win();
    Fd f; f.kind = FD_FILE; f.h = h; f.path = wp; f.append = flags & D_O_APPEND;
    TRACE("open %s -> ok\n", (const char *)path);
    return fd_alloc(std::move(f));
}
static A hc_close(A fd, A, A, A, A, A) {
    std::shared_ptr<void> sock;   /* closed (the last reference) outside the table's lock */
    {
        std::lock_guard<std::mutex> l(g_fdmu);
        if (fd < 0 || fd >= (A)g_fds.size() || g_fds[fd].kind == FD_FREE) return -D_EBADF;
        Fd &f = g_fds[fd];
        if (f.find != INVALID_HANDLE_VALUE) FindClose(f.find);
        if (f.h != INVALID_HANDLE_VALUE && fd > 2) CloseHandle(f.h);
        sock = std::move(f.sock_owner);
        f = Fd();
    }
    net_fd_closed((int)fd);
    return 0;
}
static A hc_lseek(A fd, A off, A whence, A, A, A) {
    Fd *f = fd_get(fd); if (!f) return -D_EBADF;
    if (GetFileType(f->h) != FILE_TYPE_DISK) return -D_ESPIPE;
    LARGE_INTEGER d; d.QuadPart = off; LARGE_INTEGER out;
    if (!SetFilePointerEx(f->h, d, &out, whence == 0 ? FILE_BEGIN : whence == 1 ? FILE_CURRENT : FILE_END)) return err_from_win();
    return out.QuadPart;
}
static A hc_stat(A dirfd, A path, A stp, A flags, A, A) {
    struct dstat *st = (struct dstat *)stp;
    if (!path) { /* fstat */
        Fd *f = fd_get(dirfd); if (!f) return -D_EBADF;
        if (f->kind == FD_SOCK || f->kind == FD_KQ) {
            memset(st, 0, sizeof *st); st->mode = (f->kind == FD_SOCK ? D_S_IFSOCK : 0) | 0666; st->nlink = 1; st->blksize = 4096;
            return 0;
        }
        DWORD t = GetFileType(f->h);
        if (f->kind == FD_FILE && t != FILE_TYPE_DISK) {
            memset(st, 0, sizeof *st); st->mode = (t == FILE_TYPE_CHAR ? D_S_IFCHR : D_S_IFIFO) | 0620; st->nlink = 1; st->blksize = 4096;
            return 0;
        }
        BY_HANDLE_FILE_INFORMATION bi;
        if (!GetFileInformationByHandle(f->h, &bi)) return err_from_win();
        fill_stat(st, bi.dwFileAttributes, bi.ftCreationTime, bi.ftLastAccessTime, bi.ftLastWriteTime,
                  (uint64_t)bi.nFileSizeHigh << 32 | bi.nFileSizeLow, path_ino(f->path));
        return 0;
    }
    std::wstring wp = darwin_to_win((const char *)path, (int)dirfd);
    TRACE("stat %s\n", (const char *)path);
    WIN32_FILE_ATTRIBUTE_DATA ad;
    if (!GetFileAttributesExW(wp.c_str(), GetFileExInfoStandard, &ad)) return err_from_win();
    fill_stat(st, ad.dwFileAttributes, ad.ftCreationTime, ad.ftLastAccessTime, ad.ftLastWriteTime,
              (uint64_t)ad.nFileSizeHigh << 32 | ad.nFileSizeLow, path_ino(wp));
    return 0;
}
static A hc_dup(A fd, A want, A, A, A, A) {
    Fd *f = fd_get(fd); if (!f) return -D_EBADF;
    Fd n = *f; n.find = INVALID_HANDLE_VALUE;
    if (f->kind == FD_KQ) return -D_EBADF;   /* ponytail: kqueue state is per descriptor (net.cpp) */
    if (f->kind != FD_SOCK && !DuplicateHandle(GetCurrentProcess(), f->h, GetCurrentProcess(), &n.h, 0, FALSE, DUPLICATE_SAME_ACCESS)) return err_from_win();
    if (want >= 0) hc_close(want, 0, 0, 0, 0, 0);
    return fd_alloc(std::move(n), (int)want);
}
static A hc_getcwd(A buf, A size, A, A, A, A) {
    wchar_t w[32768]; GetCurrentDirectoryW(32768, w);
    std::string s = win_to_darwin(narrow(w));
    if ((A)s.size() + 1 > size) return -34; /* ERANGE */
    memcpy((void *)buf, s.c_str(), s.size() + 1);
    return (A)s.size();
}
static A hc_mkdir(A path, A, A, A, A, A) { return CreateDirectoryW(darwin_to_win((const char *)path, -1).c_str(), nullptr) ? 0 : err_from_win(); }
static A hc_unlink(A path, A isdir, A dirfd, A, A, A) {
    std::wstring w = darwin_to_win((const char *)path, (int)dirfd);
    /* POSIX semantics (Windows 10 1709+, NTFS): the name disappears now even if the file is still open,
     * so removing its directory right after works as on macOS. Fallback: classic delete-pending. */
    HANDLE h = CreateFileW(w.c_str(), DELETE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                           FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (h == INVALID_HANDLE_VALUE) return err_from_win();
    BY_HANDLE_FILE_INFORMATION bi;
    /* a symbolic link to a directory is a directory to Windows but a link (unlink) to Darwin */
    bool dir = GetFileInformationByHandle(h, &bi) && (bi.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !(bi.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT);
    if (dir != !!isdir) { CloseHandle(h); return isdir ? -D_ENOTDIR : -1 /* EPERM: unlink() on a directory */; }
    DWORD dx = 0x1 | 0x2 | 0x10; /* DELETE | POSIX_SEMANTICS | IGNORE_READONLY_ATTRIBUTE */
    bool ok = SetFileInformationByHandle(h, (FILE_INFO_BY_HANDLE_CLASS)21 /* FileDispositionInfoEx */, &dx, sizeof dx);
    if (ok || GetLastError() == ERROR_DIR_NOT_EMPTY) { A r = ok ? 0 : err_from_win(); CloseHandle(h); return r; }
    CloseHandle(h);
    if (!isdir) { /* no POSIX semantics (FAT, old Windows, Wine): move the name out of the way first, then delete */
        static std::atomic<unsigned> seq;
        wchar_t tmp[MAX_PATH + 1]; DWORD n = GetTempPathW(MAX_PATH, tmp);
        std::wstring t = std::wstring(tmp, n) + L"mw-del-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(seq++);
        if (MoveFileExW(w.c_str(), t.c_str(), 0)) { DeleteFileW(t.c_str()); return 0; }
    }
    return (isdir ? RemoveDirectoryW(w.c_str()) : DeleteFileW(w.c_str())) ? 0 : err_from_win();
}
static A hc_readdir(A fd, A ent, A, A, A, A) {
    Fd *f = fd_get(fd); if (!f || f->kind != FD_DIR) return -D_EBADF;
    struct ddirent *d = (struct ddirent *)ent;
    for (;;) {
        if (f->find_done) return 0;
        if (f->find == INVALID_HANDLE_VALUE) {
            f->find = FindFirstFileW((f->path + L"\\*").c_str(), &f->fd);
            if (f->find == INVALID_HANDLE_VALUE) { f->find_done = true; return 0; }
        } else if (!FindNextFileW(f->find, &f->fd)) { f->find_done = true; return 0; }
        if (!wcscmp(f->fd.cFileName, L".") || !wcscmp(f->fd.cFileName, L"..")) continue;
        std::string name = narrow(f->fd.cFileName);
        memset(d, 0, sizeof *d);
        d->ino = path_ino(f->path + L"\\" + f->fd.cFileName);
        d->type = (f->fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? D_DT_DIR : D_DT_REG;
        d->namlen = (uint16_t)std::min<size_t>(name.size(), 1023);
        memcpy(d->name, name.c_str(), d->namlen);
        d->reclen = sizeof *d;
        return 1;
    }
}
static A hc_isatty(A fd, A, A, A, A, A) { Fd *f = fd_get(fd); DWORD m; return f && GetFileType(f->h) == FILE_TYPE_CHAR && GetConsoleMode(f->h, &m); }

/* walk [a, a+n) region by region (VirtualQuery) so one call may span several allocations */
template <class F> static bool each_region(uint64_t a, uint64_t n, F fn) {
    uint64_t end = a + n;
    while (a < end) {
        MEMORY_BASIC_INFORMATION mi;
        if (!VirtualQuery((void *)a, &mi, sizeof mi)) return false;
        uint64_t rend = std::min<uint64_t>(end, (uint64_t)mi.BaseAddress + mi.RegionSize);
        if (!fn(a, rend - a, mi)) return false;
        a = rend;
    }
    return true;
}
static DWORD winprot(A prot) {
    if (!(prot & 7)) return PAGE_NOACCESS;
    if (prot & D_PROT_EXEC) return (prot & D_PROT_WRITE) ? PAGE_EXECUTE_READWRITE : PAGE_EXECUTE_READ;
    return (prot & D_PROT_WRITE) ? PAGE_READWRITE : PAGE_READONLY;
}
static A hc_mmap(A addr, A len, A prot, A flags, A fd, A off) {
    DWORD wp = winprot(prot);
    bool commit = (prot & 7) != 0;
    uint64_t n = (len + 0xFFF) & ~0xFFFull;
    void *p = nullptr;
    if ((flags & D_MAP_FIXED) && addr) {
        if (g_guest_arm) arm64_alias_set((uint64_t)addr, n, 0);
        bool ok = each_region(addr, n, [&](uint64_t a, uint64_t l, MEMORY_BASIC_INFORMATION &mi) {
            if (mi.State == MEM_FREE) return VirtualAlloc((void *)a, l, MEM_RESERVE | (commit ? MEM_COMMIT : 0), commit ? wp : PAGE_NOACCESS) != nullptr;
            if (!commit) return VirtualFree((void *)a, l, MEM_DECOMMIT) != 0;
            if (!VirtualAlloc((void *)a, l, MEM_COMMIT, wp)) return false;
            memset((void *)a, 0, l); /* MAP_FIXED replaces contents */
            return true;
        });
        if (!ok) return -D_ENOMEM;
        p = (void *)addr;
    } else {
        DWORD type = MEM_RESERVE | (commit ? MEM_COMMIT : 0), pr = commit ? wp : PAGE_NOACCESS;
        if (addr) p = VirtualAlloc((void *)addr, n, type, pr);
        if (!p) p = low_alloc(n, type, pr);
        if (!p) return -D_ENOMEM;
    }
    if (fd >= 0 && !(flags & D_MAP_ANON)) { /* ponytail: private copy of the file, no shared mappings */
        Fd *f = fd_get(fd); if (!f) return -D_EBADF;
        DWORD prev; VirtualProtect(p, n, PAGE_READWRITE, &prev);
        hc_pread(fd, (A)p, len, off, 0, 0);
        VirtualProtect(p, n, wp, &prev);
    }
    return (A)p;
}
static A hc_munmap(A addr, A len, A, A, A, A) {
    if (g_guest_arm) arm64_alias_set((uint64_t)addr, ((uint64_t)len + 0xFFF) & ~0xFFFull, 0);
    uint64_t n = ((uint64_t)len + 0xFFF) & ~0xFFFull;
    each_region(addr, n, [](uint64_t a, uint64_t l, MEMORY_BASIC_INFORMATION &mi) {
        if (g_guest_arm && mi.State == MEM_COMMIT && (mi.Protect & 0xF0 /* PAGE_EXECUTE* */)) arm64_invalidate(a, l);
        if (mi.State == MEM_COMMIT) VirtualFree((void *)a, l, MEM_DECOMMIT);
        return true;
    });
    /* a whole reservation unmapped (malloc's big blocks, every frame's bitmap): give the addresses back, or the
     * 2^39 space low_alloc hands out runs dry after a few hundred GB of churn. A part stays reserved. */
    MEMORY_BASIC_INFORMATION mi;
    if (VirtualQuery((void *)addr, &mi, sizeof mi) && (uint64_t)mi.AllocationBase == (uint64_t)addr) {
        uint64_t a = addr;
        while (VirtualQuery((void *)a, &mi, sizeof mi) && (uint64_t)mi.AllocationBase == (uint64_t)addr && mi.State != MEM_FREE)
            a = (uint64_t)mi.BaseAddress + mi.RegionSize;
        if (a <= addr + ((n + 0xFFFF) & ~0xFFFFull) && a - addr >= n) VirtualFree((void *)addr, 0, MEM_RELEASE);
    }
    if (g_guest_arm) arm64_mem_changed();
    return 0;
}
static A hc_mprotect(A addr, A len, A prot, A, A, A) {
    DWORD wp = winprot(prot);
    /* an alias (mach_vm_remap without copy) is only a translation: protect the pages it shows.
     * ponytail: so both mappings change, and the range is assumed to lie in one alias */
    if (g_guest_arm) addr = (A)arm64_translate((uint64_t)addr);
    bool ok = each_region(addr, (len + 0xFFF) & ~0xFFFull, [&](uint64_t a, uint64_t l, MEMORY_BASIC_INFORMATION &mi) {
        if (mi.State == MEM_RESERVE) return VirtualAlloc((void *)a, l, MEM_COMMIT, wp) != nullptr;
        DWORD old; bool r = VirtualProtect((void *)a, l, wp, &old) != 0;
        if (g_guest_arm && r && ((old | wp) & 0xF0)) arm64_invalidate(a, l);   /* executable code may have changed */
        return r;
    });
    if (g_guest_arm) arm64_mem_changed();
    return ok ? 0 : -D_ENOMEM;
}
static void prof_report();
A hc_exit(A code, A, A, A, A, A) {
    TRACE("exit(%lld)\n", (long long)code);
    prof_report();
    if (g_guest_arm) arm64_exit();
    if (g_trace && !g_missing.empty()) for (auto &m : g_missing) fprintf(stderr, "[scion] unimplemented import: %s\n", m.c_str());
    fflush(stdout); fflush(stderr);
    /* guest atexit handlers already ran (libSystem's exit); skip DLL teardown: Vulkan drivers can deadlock in it
     * when their worker threads are killed mid-lock */
    TerminateProcess(GetCurrentProcess(), (UINT)code);
    return 0;
}
static A hc_getpid(A, A, A, A, A, A) { return GetCurrentProcessId(); }
static A hc_self(A, A, A, A, A, A) { return (A)TlsGetValue(g_tls_self); }
static A hc_sleep(A ns, A, A, A, A, A) { if (ns < 1000000) SwitchToThread(); else Sleep((DWORD)(ns / 1000000)); return 0; }
static A hc_lock(A l, A op, A, A, A, A) {
    l = G(l);
    switch (op) {
    case 0: AcquireSRWLockExclusive((PSRWLOCK)l); return 0;
    case 1: ReleaseSRWLockExclusive((PSRWLOCK)l); return 0;
    case 2: return TryAcquireSRWLockExclusive((PSRWLOCK)l);
    case 3: AcquireSRWLockShared((PSRWLOCK)l); return 0;
    case 4: ReleaseSRWLockShared((PSRWLOCK)l); return 0;
    default: return TryAcquireSRWLockShared((PSRWLOCK)l);
    }
}
static A hc_cond(A cv, A l, A op, A timeout, A, A) {
    cv = G(cv); l = G(l);
    if (op == 1) { WakeConditionVariable((PCONDITION_VARIABLE)cv); return 0; }
    if (op == 2) { WakeAllConditionVariable((PCONDITION_VARIABLE)cv); return 0; }
    DWORD ms = timeout < 0 ? INFINITE : (DWORD)((timeout + 999999) / 1000000);
    if (!SleepConditionVariableSRW((PCONDITION_VARIABLE)cv, (PSRWLOCK)l, ms, 0))
        return GetLastError() == ERROR_TIMEOUT ? -D_ETIMEDOUT : -D_EINVAL;
    return 0;
}
A hc_clock(A kind, A, A, A, A, A) {
    if (kind == 0) { FILETIME ft; GetSystemTimePreciseAsFileTime(&ft); return filetime_ns(ft); }
    if (kind == 2 || kind == 3) {   /* CPU time of the calling thread / of the process (user + kernel) */
        FILETIME c, x, k, u;
        if (kind == 2 ? !GetThreadTimes(GetCurrentThread(), &c, &x, &k, &u) : !GetProcessTimes(GetCurrentProcess(), &c, &x, &k, &u)) return 0;
        auto t = [](FILETIME f) { return ((A)f.dwHighDateTime << 32 | f.dwLowDateTime) * 100; };
        return t(k) + t(u);
    }
    static LARGE_INTEGER freq = [] { LARGE_INTEGER f; QueryPerformanceFrequency(&f); return f; }();
    LARGE_INTEGER c; QueryPerformanceCounter(&c);
    return (A)((__int128)c.QuadPart * 1000000000 / freq.QuadPart);
}
static A hc_random(A buf, A n, A, A, A, A) { BCryptGenRandom(nullptr, (PUCHAR)G(buf), (ULONG)n, BCRYPT_USE_SYSTEM_PREFERRED_RNG); return 0; }
static A hc_ncpu(A, A, A, A, A, A) { return GetActiveProcessorCount(ALL_PROCESSOR_GROUPS); }
static void guest_backtrace(uint64_t pc, uint64_t fp, uint64_t lr);
/* msg, optional frame pointer: with it, a backtrace of the guest stack follows (abort) */
static A hc_log(A msg, A fp, A, A, A, A) { fprintf(stderr, "[scion] %s\n", (const char *)msg); if (fp) guest_backtrace(0, (uint64_t)fp, 0); return 0; }
/* ---------- signals ---------- */
struct dsigaction g_sig[64];
static std::mutex g_sigmu;
struct gthread *cur_gthread() { return (struct gthread *)TlsGetValue(g_tls_self); }
static A hc_sigaction(A sig, A act, A old, A, A, A) {
    if (sig <= 0 || sig >= 64) return -D_EINVAL;
    std::lock_guard<std::mutex> l(g_sigmu);
    if (old) *(struct dsigaction *)old = g_sig[sig];
    if (act) g_sig[sig] = *(const struct dsigaction *)act;
    return 0;
}
static A hc_sigaltstack(A ss, A old, A, A, A, A) {
    struct gthread *t = cur_gthread();
    if (old) { struct dstack *o = (struct dstack *)old; o->sp = t->alt_sp; o->size = t->alt_size; o->flags = t->alt_size ? t->alt_flags : D_SS_DISABLE; }
    if (ss) { const struct dstack *n = (const struct dstack *)ss; t->alt_sp = n->sp; t->alt_size = n->size; t->alt_flags = n->flags; }
    return 0;
}
static const char *signame(int s) {
    switch (s) { case D_SIGSEGV: return "Segmentation fault: 11"; case D_SIGBUS: return "Bus error: 10"; case D_SIGILL: return "Illegal instruction: 4";
                 case D_SIGFPE: return "Floating point exception: 8"; case D_SIGTRAP: return "Trace/BPT trap: 5"; case D_SIGABRT: return "Abort trap: 6"; }
    return "fatal signal";
}
/* where a guest address lives: image + offset (+ nearest exported symbol) */
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
/* frame-pointer walk of the guest stack (both arches keep frame records: [fp] = caller fp, [fp+8] = return address) */
static void guest_backtrace(uint64_t pc, uint64_t fp, uint64_t lr) {
    if (pc) print_guest_addr("pc", pc);
    if (lr) print_guest_addr("lr", lr);
    for (int n = 0; n < 24 && fp && !(fp & 7); n++) {
        MEMORY_BASIC_INFORMATION m;
        if (!VirtualQuery((void *)fp, &m, sizeof m) || m.State != MEM_COMMIT) break;
        uint64_t next = ((uint64_t *)fp)[0], ret = ((uint64_t *)fp)[1];
        if (!ret) break;
        print_guest_addr("  ", ret);
        if (next <= fp) break;
        fp = next;
    }
}
static void fatal_signal(int sig, uint64_t pc, uint64_t addr, uint64_t fp = 0, uint64_t lr = 0) {
    fprintf(stderr, "scion: %s (pc=%llx dir=%llx)\n", signame(sig), (unsigned long long)pc, (unsigned long long)addr);
    if (fp) guest_backtrace(pc, fp, lr);
    hc_exit(128 + sig, 0, 0, 0, 0, 0);
}

/* x86_64 guests: Windows exceptions -> Darwin signals. The handler does not run inside the
 * exception dispatcher: the faulting context is redirected to sigtramp_x86 on the guest (or alt) stack,
 * which calls the handler and then HC_sigreturn, which restores the (possibly edited) context. */
struct alignas(64) SigFrameX86 {
    uint64_t handler, sig, info, uc;
    struct dsiginfo si; uint64_t pad0;
    struct ducontext uc_; uint64_t pad1;
    struct dmcontext_x86 mc;
    alignas(16) CONTEXT ctx;
};
extern "C" void sigtramp_x86();
asm(".globl sigtramp_x86\nsigtramp_x86:\n"
    " mov (%rsp), %rax\n mov 8(%rsp), %rdi\n mov 16(%rsp), %rsi\n mov 24(%rsp), %rdx\n mov %rsp, %rbx\n"
    " call *%rax\n"                       /* SysV: rbx survives the handler */
    " mov 24(%rbx), %rcx\n mov %rbx, %rsp\n and $-16, %rsp\n sub $32, %rsp\n"
    " call hc_sigreturn_entry\n ud2\n");
static bool redirect_x86(CONTEXT *c, int sig, int code, uint64_t addr, struct gthread *t) {
    struct dsigaction a; { std::lock_guard<std::mutex> l(g_sigmu); a = g_sig[sig]; if (a.flags & D_SA_RESETHAND) g_sig[sig].handler = 0; }
    if (a.handler == 1 && sig != D_SIGSEGV && sig != D_SIGBUS && sig != D_SIGILL && sig != D_SIGFPE) return false;
    if (a.handler <= 1) { if (dsig_default_ignored(sig)) return false; fatal_signal(sig, c->Rip, addr, c->Rbp, c->Rip < 0x10000 ? *(uint64_t *)c->Rsp : 0); }
    bool on_alt = t && t->alt_size && !(t->alt_flags & D_SS_DISABLE) && c->Rsp >= t->alt_sp && c->Rsp < t->alt_sp + t->alt_size;
    uint64_t sp = (a.flags & D_SA_ONSTACK) && t && t->alt_size && !(t->alt_flags & D_SS_DISABLE) && !on_alt ? t->alt_sp + t->alt_size : c->Rsp - 128;
    SigFrameX86 *f = (SigFrameX86 *)((sp - sizeof(SigFrameX86)) & ~63ull);
    memset((void *)f, 0, offsetof(SigFrameX86, ctx));
    f->ctx = *c;
    f->handler = a.handler; f->sig = sig; f->info = (uint64_t)&f->si; f->uc = (uint64_t)&f->uc_;
    f->si.signo = sig; f->si.code = code; f->si.addr = addr; f->si.pid = (int32_t)GetCurrentProcessId();
    f->uc_.onstack = on_alt; f->uc_.mcsize = sizeof f->mc; f->uc_.mcontext = (uint64_t)&f->mc;
    if (t) { f->uc_.stack.sp = t->alt_sp; f->uc_.stack.size = t->alt_size; f->uc_.stack.flags = t->alt_flags; }
    struct dmcontext_x86 &m = f->mc;
    m.trapno = sig == D_SIGSEGV ? 14 : sig == D_SIGFPE ? 0 : sig == D_SIGILL ? 6 : 3; m.faultvaddr = addr; m.err = code == 2 ? 6 : 4;
    m.rax = c->Rax; m.rbx = c->Rbx; m.rcx = c->Rcx; m.rdx = c->Rdx; m.rdi = c->Rdi; m.rsi = c->Rsi; m.rbp = c->Rbp; m.rsp = c->Rsp;
    m.r8 = c->R8; m.r9 = c->R9; m.r10 = c->R10; m.r11 = c->R11; m.r12 = c->R12; m.r13 = c->R13; m.r14 = c->R14; m.r15 = c->R15;
    m.rip = c->Rip; m.rflags = c->EFlags; m.cs = 0x2b;
    c->Rsp = (uint64_t)f; c->Rip = (uint64_t)sigtramp_x86;
    if (t) t->in_handler++;
    return true;
}
/* Our own context restore (instead of RtlRestoreContext, whose checks differ between Windows versions and
 * Wine): fxrstor + GPRs, then iretq from an iret frame kept in CONTEXT's unused P1Home..P5Home, so RIP, RSP and
 * RFLAGS change atomically and the interrupted code's red zone is never touched. */
[[noreturn]] static void restore_ctx(CONTEXT *c) {
    if (!c->SegCs) { uint16_t cs, ss; asm("mov %%cs, %0\n mov %%ss, %1" : "=r"(cs), "=r"(ss)); c->SegCs = cs; c->SegSs = ss; }
    c->P1Home = c->Rip; c->P2Home = c->SegCs; c->P3Home = c->EFlags; c->P4Home = c->Rsp; c->P5Home = c->SegSs;
    asm volatile(
        "fxrstor %c[flt](%%rcx)\n"
        "mov %c[rax](%%rcx), %%rax\n mov %c[rdx](%%rcx), %%rdx\n mov %c[rbx](%%rcx), %%rbx\n mov %c[rbp](%%rcx), %%rbp\n"
        "mov %c[rsi](%%rcx), %%rsi\n mov %c[rdi](%%rcx), %%rdi\n mov %c[r8](%%rcx), %%r8\n mov %c[r9](%%rcx), %%r9\n"
        "mov %c[r10](%%rcx), %%r10\n mov %c[r11](%%rcx), %%r11\n mov %c[r12](%%rcx), %%r12\n mov %c[r13](%%rcx), %%r13\n"
        "mov %c[r14](%%rcx), %%r14\n mov %c[r15](%%rcx), %%r15\n"
        "lea %c[iret](%%rcx), %%rsp\n mov %c[rcx](%%rcx), %%rcx\n iretq\n"
        :: "c"(c), [flt] "i"(offsetof(CONTEXT, FltSave)), [iret] "i"(offsetof(CONTEXT, P1Home)),
           [rax] "i"(offsetof(CONTEXT, Rax)), [rcx] "i"(offsetof(CONTEXT, Rcx)), [rdx] "i"(offsetof(CONTEXT, Rdx)),
           [rbx] "i"(offsetof(CONTEXT, Rbx)), [rbp] "i"(offsetof(CONTEXT, Rbp)), [rsi] "i"(offsetof(CONTEXT, Rsi)),
           [rdi] "i"(offsetof(CONTEXT, Rdi)), [r8] "i"(offsetof(CONTEXT, R8)), [r9] "i"(offsetof(CONTEXT, R9)),
           [r10] "i"(offsetof(CONTEXT, R10)), [r11] "i"(offsetof(CONTEXT, R11)), [r12] "i"(offsetof(CONTEXT, R12)),
           [r13] "i"(offsetof(CONTEXT, R13)), [r14] "i"(offsetof(CONTEXT, R14)), [r15] "i"(offsetof(CONTEXT, R15))
        : "memory");
    __builtin_unreachable();
}
extern "C" void hc_sigreturn_entry(struct ducontext *uc) {
    SigFrameX86 *f = (SigFrameX86 *)((uint8_t *)uc - offsetof(SigFrameX86, uc_));
    if (struct gthread *t = cur_gthread(); t && t->in_handler > 0) t->in_handler--;
    struct dmcontext_x86 &m = f->mc; CONTEXT &c = f->ctx;
    c.Rax = m.rax; c.Rbx = m.rbx; c.Rcx = m.rcx; c.Rdx = m.rdx; c.Rdi = m.rdi; c.Rsi = m.rsi; c.Rbp = m.rbp; c.Rsp = m.rsp;
    c.R8 = m.r8; c.R9 = m.r9; c.R10 = m.r10; c.R11 = m.r11; c.R12 = m.r12; c.R13 = m.r13; c.R14 = m.r14; c.R15 = m.r15;
    c.Rip = m.rip; c.EFlags = (c.EFlags & ~0xCD5u) | (m.rflags & 0xCD5u);
    restore_ctx(&c);
}
static A hc_sigreturn(A uc, A, A, A, A, A) { hc_sigreturn_entry((struct ducontext *)uc); return 0; }
static LONG CALLBACK guest_veh(PEXCEPTION_POINTERS ep) {
    if (g_guest_arm) return EXCEPTION_CONTINUE_SEARCH;
    CONTEXT *c = ep->ContextRecord; EXCEPTION_RECORD *r = ep->ExceptionRecord;
    /* a guest call through a NULL (or tiny) function pointer faults outside guest code: its return address tells */
    bool null_call = c->Rip < 0x10000 && r->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && guest_pc(*(uint64_t *)c->Rsp);
    if (!guest_pc(c->Rip) && !null_call) return EXCEPTION_CONTINUE_SEARCH;
    int sig, code = 0; uint64_t addr = (uint64_t)r->ExceptionAddress;
    switch (r->ExceptionCode) {
    case EXCEPTION_ACCESS_VIOLATION: case EXCEPTION_IN_PAGE_ERROR:
        sig = D_SIGSEGV; addr = r->ExceptionInformation[1];
        { MEMORY_BASIC_INFORMATION mi; code = VirtualQuery((void *)addr, &mi, sizeof mi) && mi.State == MEM_COMMIT ? 2 : 1; } break;
    case EXCEPTION_STACK_OVERFLOW: sig = D_SIGSEGV; code = 2; break;
    case EXCEPTION_ILLEGAL_INSTRUCTION: case EXCEPTION_PRIV_INSTRUCTION: sig = D_SIGILL; code = 1; break;
    case EXCEPTION_INT_DIVIDE_BY_ZERO: case EXCEPTION_INT_OVERFLOW: sig = D_SIGFPE; code = 7; break;
    case EXCEPTION_BREAKPOINT: case EXCEPTION_SINGLE_STEP: sig = D_SIGTRAP; break;
    case EXCEPTION_DATATYPE_MISALIGNMENT: sig = D_SIGBUS; code = 1; break;
    default: return EXCEPTION_CONTINUE_SEARCH;
    }
    TRACE("signal %d at rip=%llx addr=%llx\n", sig, (unsigned long long)c->Rip, (unsigned long long)addr);
    return redirect_x86(c, sig, code, addr, cur_gthread()) ? EXCEPTION_CONTINUE_EXECUTION : EXCEPTION_CONTINUE_SEARCH;
}
/* signal another guest thread (Go: SIGURG preemption). x86_64: only if it is running guest code right now. */
/* Signals can only be injected while the target executes guest code; otherwise they wait in a queue
 * that a pump thread retries every millisecond (Go never re-sends a preemption signal still pending). */
static std::mutex g_pendmu;
static std::vector<std::pair<struct gthread *, int>> g_pend;
static HANDLE g_pump_ev;
static bool try_inject_x86(struct gthread *t, int sig) {
    /* POSIX blocks a signal while its handler runs: never nest an async frame inside an unfinished one.
     * ponytail: a handler that siglongjmps out leaves in_handler set (async signals then stay queued);
     * track the full signal mask if a real program needs that. */
    if (t->in_handler > 0) return false;
    HANDLE h = (HANDLE)t->handle;
    if (SuspendThread(h) == (DWORD)-1) return true; /* thread gone: drop */
    CONTEXT c; c.ContextFlags = CONTEXT_ALL;
    bool done = false;
    if (t->in_handler == 0 && GetThreadContext(h, &c) && guest_pc(c.Rip)) {
        if (redirect_x86(&c, sig, 0, 0, t)) {
            if (!SetThreadContext(h, &c)) { t->in_handler--; TRACE("SetThreadContext failed (%lu)\n", GetLastError()); ResumeThread(h); return false; }
            TRACE("signal %d injected into thread %llu rip=%llx\n", sig, (unsigned long long)t->tid, (unsigned long long)c.Rip);
        }
        done = true;
    }
    ResumeThread(h);
    return done;
}
static DWORD WINAPI signal_pump(void *) {
    for (;;) {
        WaitForSingleObject(g_pump_ev, 1);
        std::lock_guard<std::mutex> l(g_pendmu);
        for (size_t i = 0; i < g_pend.size();)
            if (try_inject_x86(g_pend[i].first, g_pend[i].second)) g_pend.erase(g_pend.begin() + i); else i++;
    }
}
static A hc_tkill(A tp, A sig, A, A, A, A) {
    struct gthread *t = (struct gthread *)tp;
    if (!t || !t->handle) return -3; /* ESRCH */
    if (g_guest_arm) { arm64_signal(t, (int)sig); return 0; }
    std::lock_guard<std::mutex> l(g_pendmu);
    if (try_inject_x86(t, (int)sig)) return 0;
    if (!g_pump_ev) { g_pump_ev = CreateEventW(nullptr, FALSE, FALSE, nullptr); CloseHandle(CreateThread(nullptr, 0, signal_pump, nullptr, 0, nullptr)); }
    g_pend.push_back({t, (int)sig});
    SetEvent(g_pump_ev);
    return 0;
}

static A hc_thread(A start, A arg, A stacksize, A, A, A);
static A hc_join(A, A, A, A, A, A); static A hc_chdir(A, A, A, A, A, A); static A hc_ftruncate(A, A, A, A, A, A);
static A hc_rename(A, A, A, A, A, A); static A hc_realpath(A, A, A, A, A, A); static A hc_pipe(A, A, A, A, A, A);
static A hc_math(A, A, A, A, A, A);
static A hc_safecopy(A, A, A, A, A, A); static A hc_thread_ctl(A, A, A, A, A, A);

static A hc_link(A sym, A from, A to, A, A, A) {
    std::wstring f = darwin_to_win((const char *)from, -1), t = darwin_to_win((const char *)to, -1);
    if (!sym) return CreateHardLinkW(t.c_str(), f.c_str(), nullptr) ? 0 : err_from_win();
    std::wstring probe = f; /* a relative target is relative to the link's directory */
    if (f.size() < 2 || (f[1] != L':' && f[0] != L'\\')) { size_t k = t.find_last_of(L'\\'); if (k != std::wstring::npos) probe = t.substr(0, k + 1) + f; }
    DWORD at = GetFileAttributesW(probe.c_str());
    DWORD fl = 0x2 /* ALLOW_UNPRIVILEGED_CREATE (developer mode) */ | (at != INVALID_FILE_ATTRIBUTES && (at & FILE_ATTRIBUTE_DIRECTORY) ? 0x1 : 0);
    return CreateSymbolicLinkW(t.c_str(), f.c_str(), fl) ? 0 : err_from_win();
}
static A hc_futex(A addr, A op, A val, A timeout, A, A) {
    if (op == 1) { WakeByAddressSingle((void *)addr); return 0; }
    if (op == 2) { WakeByAddressAll((void *)addr); return 0; }
    uint32_t v = (uint32_t)val;
    DWORD ms = timeout < 0 ? INFINITE : (DWORD)((timeout + 999999) / 1000000);
    if (!WaitOnAddress((volatile void *)addr, &v, 4, ms)) return GetLastError() == ERROR_TIMEOUT ? -60 /* ETIMEDOUT */ : 0;
    return 0;
}
static A hc_dl(A, A, A, A, A, A);
static A hc_icache(A a, A n, A, A, A, A) { if (g_guest_arm) arm64_invalidate((uint64_t)a, (uint64_t)n); else FlushInstructionCache(GetCurrentProcess(), (void *)a, (SIZE_T)n); return 0; }
static int darwin_prot(DWORD p) {
    if (p & (PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) return 7;
    if (p & (PAGE_EXECUTE_READ)) return 5;
    if (p & PAGE_EXECUTE) return 4;
    if (p & (PAGE_READWRITE | PAGE_WRITECOPY)) return 3;
    return p & PAGE_READONLY ? 1 : 0;
}
static A hc_alias(A dst, A len, A src, A fixed, A cur, A) {
    if (!g_guest_arm) return -45; /* ENOTSUP: x86_64 guests run natively, there is no software path to redirect them */
    uint64_t n = ((uint64_t)len + 0xFFF) & ~0xFFFull, s = arm64_translate((uint64_t)src);
    MEMORY_BASIC_INFORMATION mi;
    if (!n || !VirtualQuery((void *)s, &mi, sizeof mi) || mi.State == MEM_FREE) return -22; /* EINVAL */
    uint64_t d = (uint64_t)dst;
    if (!fixed) { d = (uint64_t)low_alloc(n, MEM_RESERVE, PAGE_NOACCESS); if (!d) return -12; }
    else if (!each_region(d, n, [](uint64_t a, uint64_t l, MEMORY_BASIC_INFORMATION &m) {
        if (m.State == MEM_FREE) return VirtualAlloc((void *)a, l, MEM_RESERVE, PAGE_NOACCESS) != nullptr;
        return m.State != MEM_COMMIT || VirtualFree((void *)a, l, MEM_DECOMMIT) != 0;
    })) return -12; /* ENOMEM */
    arm64_invalidate(d, n);
    arm64_alias_set(d, n, s);
    if (cur) *(int *)cur = darwin_prot(mi.Protect);
    TRACE("vm_remap alias %llx -> %llx (%llu bytes)\n", (unsigned long long)d, (unsigned long long)s, (unsigned long long)n);
    return (A)d;
}
/* Extended attributes: kept per file (volume serial + file index, which survive renames) in
 * %LOCALAPPDATA%\\scion\\xattr\\<file>\\<hex name>, so they work on any file system (NTFS streams don't under Wine).
 * ponytail: entries of deleted files stay behind; a reused file index would see them. */
static A hc_xattr(A op, A fd, A path, A name, A buf, A size) {
    HANDLE h = INVALID_HANDLE_VALUE; bool own = false;
    std::wstring p;
    if (path) p = darwin_to_win((const char *)path, -1);
    else { Fd *f = fd_get(fd); if (!f) return -D_EBADF; if (f->kind == FD_DIR || f->h == INVALID_HANDLE_VALUE) p = f->path; else h = f->h; }
    if (h == INVALID_HANDLE_VALUE) {
        h = CreateFileW(p.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
        if (h == INVALID_HANDLE_VALUE) return err_from_win();
        own = true;
    }
    BY_HANDLE_FILE_INFORMATION bi{};
    BOOL ok = GetFileInformationByHandle(h, &bi);
    if (own) CloseHandle(h);
    if (!ok) return err_from_win();
    const char *base = getenv("LOCALAPPDATA");
    std::wstring dir = widen(base ? base : "C:\\Temp") + L"\\scion";
    CreateDirectoryW(dir.c_str(), nullptr); dir += L"\\xattr"; CreateDirectoryW(dir.c_str(), nullptr);
    wchar_t key[64]; swprintf(key, 64, L"\\%08lx-%08lx%08lx", bi.dwVolumeSerialNumber, bi.nFileIndexHigh, bi.nFileIndexLow);
    dir += key;
    if (op == 3) { /* list: names separated by NUL */
        WIN32_FIND_DATAW fdw; HANDLE fh = FindFirstFileW((dir + L"\\*").c_str(), &fdw);
        std::string out;
        if (fh != INVALID_HANDLE_VALUE) {
            do {
                std::string hex = narrow(fdw.cFileName), n;
                if (hex == "." || hex == "..") continue;
                for (size_t i = 0; i + 1 < hex.size(); i += 2) n += (char)strtol(hex.substr(i, 2).c_str(), nullptr, 16);
                out += n; out += '\0';
            } while (FindNextFileW(fh, &fdw));
            FindClose(fh);
        }
        if (buf) { if (out.size() > (size_t)size) return -34 /* ERANGE */; memcpy((void *)buf, out.data(), out.size()); }
        return (A)out.size();
    }
    std::wstring file = dir + L"\\";
    for (const char *c = (const char *)name; *c; c++) { wchar_t x[3]; swprintf(x, 3, L"%02x", (unsigned char)*c); file += x; }
    if (op == 1) {
        CreateDirectoryW(dir.c_str(), nullptr);
        HANDLE w = CreateFileW(file.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
        if (w == INVALID_HANDLE_VALUE) return err_from_win();
        DWORD n = 0; BOOL wr = WriteFile(w, (const void *)buf, (DWORD)size, &n, nullptr);
        CloseHandle(w);
        return wr ? 0 : -D_EIO;
    }
    if (op == 2) return DeleteFileW(file.c_str()) ? 0 : -93 /* ENOATTR */;
    HANDLE r = CreateFileW(file.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (r == INVALID_HANDLE_VALUE) return -93; /* ENOATTR */
    LARGE_INTEGER sz{}; GetFileSizeEx(r, &sz);
    A res = (A)sz.QuadPart;
    if (buf) {
        if (sz.QuadPart > (LONGLONG)size) res = -34 /* ERANGE */;
        else { DWORD n = 0; ReadFile(r, (void *)buf, (DWORD)sz.QuadPart, &n, nullptr); res = n; }
    }
    CloseHandle(r);
    return res;
}
/* Metal: the host half lives in scion-metal.dll (Indium + Iridium + LLVM), loaded on first use */
static A hc_metal(A op, A a, A b, A c, A d, A e) {
    typedef int64_t (*fn_t)(int, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
    static fn_t fn; static std::once_flag once;
    std::call_once(once, [] {
        wchar_t p[MAX_PATH]; DWORD n = GetModuleFileNameW(nullptr, p, MAX_PATH);
        std::wstring dir(p, n); dir = dir.substr(0, dir.find_last_of(L"\\/") + 1);
        HMODULE m = LoadLibraryW((dir + L"scion-metal.dll").c_str());
        if (m) fn = (fn_t)GetProcAddress(m, "mw_metal");
        if (!fn) fprintf(stderr, "scion: could not load scion-metal.dll (Metal is not available)\n");
    });
    if (!fn) return 0;
    /* data the guest hands over (buffer bytes, shader source, region copies) may lie in a vm_remap alias; the other
     * arguments are handles and sizes, far below the 4 GB where aliases live */
    MwRegionCopy rc;
    if (op == MW_TEXTURE_REPLACE || op == MW_TEXTURE_GETBYTES) { rc = *(MwRegionCopy *)G(b); rc.bytes = G(rc.bytes); b = (A)&rc; }
    else b = G(b);
    return fn((int)op, (uint64_t)G(a), (uint64_t)b, (uint64_t)G(c), (uint64_t)G(d), (uint64_t)G(e));
}
hostfn g_hc[HC_COUNT] = {
#define HC_IMPL(n) hc_##n,
    HOSTCALLS(HC_IMPL)
#undef HC_IMPL
};

static std::mutex g_thrmu;
static std::vector<struct gthread *> g_threads; /* mach thread port = 0x1000 + index */
static struct gthread *alloc_gthread() {
    struct gthread *t = (struct gthread *)VirtualAlloc(nullptr, sizeof(struct gthread), MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    t->tsd[0] = (uint64_t)t; /* Darwin: slot 0 = pthread self */
    std::lock_guard<std::mutex> l(g_thrmu);
    t->port = 0x1000 + (uint32_t)g_threads.size();
    g_threads.push_back(t);
    return t;
}
static struct gthread *thread_by_port(A port) {
    std::lock_guard<std::mutex> l(g_thrmu);
    return port >= 0x1000 && port - 0x1000 < (A)g_threads.size() ? g_threads[port - 0x1000] : nullptr;
}
/* SCION_PROF=1: every millisecond, where each guest thread that is using the CPU is on the host: JIT-generated code,
 * scion.exe itself (the JIT compiler and host calls) or a Windows/driver DLL. Threads whose cycle count did not move
 * since the last look are waiting and are not sampled. Reported every 60 s and at exit; resolve exe+offsets with the
 * linker map of the same build (out/scion.map). */
static HANDLE g_prof_thread; static std::atomic<bool> g_prof_on;
static uint64_t g_prof[4], g_prof_idle, g_prof_exe_lo, g_prof_exe_hi;
static std::map<uint64_t, uint64_t> g_prof_hot, g_prof_dll;
static std::mutex g_prof_mu;
static void prof_report();
static DWORD WINAPI prof_loop(void *) {
    std::map<HANDLE, ULONG64> last;
    for (ULONGLONG next = GetTickCount64() + 60000; g_prof_on;) {
        Sleep(1);
        std::vector<HANDLE> hs{g_prof_thread};
        { std::lock_guard<std::mutex> l(g_thrmu); for (auto *t : g_threads) if (t->handle && (HANDLE)t->handle != g_prof_thread) hs.push_back((HANDLE)t->handle); }
        {
            std::lock_guard<std::mutex> l(g_prof_mu);
            for (HANDLE h : hs) {
                ULONG64 cy = 0;
                if (QueryThreadCycleTime(h, &cy) && cy && cy == last[h]) { g_prof_idle++; continue; }   /* Wine reports 0: sample all */
                last[h] = cy;
                if (SuspendThread(h) == (DWORD)-1) continue;
                CONTEXT c; c.ContextFlags = CONTEXT_CONTROL;
                bool got = GetThreadContext(h, &c);
                ResumeThread(h);   /* before touching the maps: the thread may have held the heap lock */
                if (!got) continue;
                MEMORY_BASIC_INFORMATION mi; int k = 3;
                if (c.Rip >= g_prof_exe_lo && c.Rip < g_prof_exe_hi) { k = 1; g_prof_hot[(c.Rip - g_prof_exe_lo) & ~0xFFull]++; }
                else if (VirtualQuery((void *)c.Rip, &mi, sizeof mi)) {
                    if (mi.Type == MEM_PRIVATE) k = 0;
                    else if (mi.Type == MEM_IMAGE) { k = 2; g_prof_dll[(uint64_t)mi.AllocationBase]++; }
                }
                g_prof[k]++;
            }
        }
        if (GetTickCount64() >= next) { next += 60000; prof_report(); }
    }
    return 0;
}
static void prof_start() {
    DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &g_prof_thread, 0, FALSE, DUPLICATE_SAME_ACCESS);
    uint8_t *b = (uint8_t *)GetModuleHandleW(nullptr);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(b + ((IMAGE_DOS_HEADER *)b)->e_lfanew);
    g_prof_exe_lo = (uint64_t)b; g_prof_exe_hi = (uint64_t)b + nt->OptionalHeader.SizeOfImage;
    g_prof_on = true; CloseHandle(CreateThread(nullptr, 0, prof_loop, nullptr, 0, nullptr));
}
static void prof_report() {
    if (!g_prof_on) return;
    std::lock_guard<std::mutex> l(g_prof_mu);
    uint64_t t = g_prof[0] + g_prof[1] + g_prof[2] + g_prof[3]; if (!t) return;
    fprintf(stderr, "[prof] %llu busy samples (%.1f%% of looks; the rest were waiting): JIT %.1f%%  scion.exe %.1f%%  DLLs %.1f%%  other %.1f%%\n",
            (unsigned long long)t, 100.0 * t / (t + g_prof_idle), 100.0 * g_prof[0] / t, 100.0 * g_prof[1] / t, 100.0 * g_prof[2] / t, 100.0 * g_prof[3] / t);
    std::vector<std::pair<uint64_t, uint64_t>> v(g_prof_hot.begin(), g_prof_hot.end());
    std::sort(v.begin(), v.end(), [](auto &x, auto &y) { return x.second > y.second; });
    for (size_t i = 0; i < v.size() && i < 15; i++) fprintf(stderr, "[prof]   exe+%llx  %.1f%%\n", (unsigned long long)v[i].first, 100.0 * v[i].second / t);
    std::vector<std::pair<uint64_t, uint64_t>> d(g_prof_dll.begin(), g_prof_dll.end());
    std::sort(d.begin(), d.end(), [](auto &x, auto &y) { return x.second > y.second; });
    for (size_t i = 0; i < d.size() && i < 8; i++) {
        wchar_t n[MAX_PATH] = L"?"; GetModuleFileNameW((HMODULE)d[i].first, n, MAX_PATH);
        const wchar_t *base = wcsrchr(n, L'\\'); fprintf(stderr, "[prof]   %ls  %.1f%%\n", base ? base + 1 : n, 100.0 * d[i].second / t);
    }
    fflush(stderr);
    memset(g_prof, 0, sizeof g_prof); g_prof_idle = 0; g_prof_hot.clear(); g_prof_dll.clear();
}
/* copy without faulting (mach_vm_read_overwrite / mach_vm_write semantics) */
static A hc_safecopy(A dst, A src, A n, A need_w, A, A) {
    if (g_guest_arm) { dst = (A)arm64_translate((uint64_t)dst); src = (A)arm64_translate((uint64_t)src); }
    if (need_w) {
        bool ok = each_region(dst, n, [](uint64_t, uint64_t, MEMORY_BASIC_INFORMATION &mi) {
            return mi.State == MEM_COMMIT && (mi.Protect & (PAGE_READWRITE | PAGE_EXECUTE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_WRITECOPY)) && !(mi.Protect & PAGE_GUARD);
        });
        if (!ok) return -D_EACCES;
    }
    if (!each_region(src, n, [](uint64_t, uint64_t, MEMORY_BASIC_INFORMATION &mi) {
            return mi.State == MEM_COMMIT && !(mi.Protect & (PAGE_NOACCESS | PAGE_GUARD));
        })) return -14; /* EFAULT: Wine's ReadProcessMemory on our own process does not always refuse PAGE_NOACCESS */
    SIZE_T got = 0;
    return ReadProcessMemory(GetCurrentProcess(), (void *)src, (void *)dst, (SIZE_T)n, &got) && got == (SIZE_T)n ? 0 : -14; /* EFAULT */
}
int arm64_thread_ctl(struct gthread *t, int op, int flavor, void *state);
static A hc_thread_ctl(A port, A op, A flavor, A state, A, A) {
    struct gthread *t = thread_by_port(port);
    if (!t || !t->handle) return -1; /* KERN_INVALID_ADDRESS-ish: caller maps */
    if (g_guest_arm) return arm64_thread_ctl(t, (int)op, (int)flavor, (void *)state);
    HANDLE h = (HANDLE)t->handle;
    switch (op) {
    case D_THREAD_SUSPEND: return SuspendThread(h) == (DWORD)-1 ? -1 : 0;
    case D_THREAD_RESUME: return ResumeThread(h) == (DWORD)-1 ? -1 : 0;
    }
    if (flavor != D_x86_THREAD_STATE64) return -4;
    CONTEXT c; c.ContextFlags = CONTEXT_FULL;
    if (!GetThreadContext(h, &c)) return -1;
    uint64_t *r = (uint64_t *)state;
    uint64_t *map[] = {&c.Rax, &c.Rbx, &c.Rcx, &c.Rdx, &c.Rdi, &c.Rsi, &c.Rbp, &c.Rsp, &c.R8, &c.R9, &c.R10, &c.R11, &c.R12, &c.R13, &c.R14, &c.R15, &c.Rip};
    if (op == D_THREAD_GET_STATE) { for (int i = 0; i < 17; i++) r[i] = *map[i]; r[17] = c.EFlags; r[18] = 0x2b; r[19] = r[20] = 0; return 0; }
    for (int i = 0; i < 17; i++) *map[i] = r[i];
    c.EFlags = (DWORD)r[17];
    return SetThreadContext(h, &c) ? 0 : -1;
}
/* bind a gthread to the calling host thread; x86_64 guests run on the host stack */
static struct gthread *enter_gthread(struct gthread *t) {
    t->tid = GetCurrentThreadId();
    ULONG_PTR lo, hi; GetCurrentThreadStackLimits(&lo, &hi);
    if (!t->stack_top) t->stack_top = hi, t->stack_size = hi - lo;
    TlsSetValue(g_tls_self, t);
    return t;
}

/* ======================================================================= threads */
struct ThreadStart { A start, arg, stacksize; bool arm; struct gthread *t; };
static DWORD WINAPI thread_entry(void *p) {
    ThreadStart ts = *(ThreadStart *)p; delete (ThreadStart *)p;
    struct gthread *t = ts.t;
    if (ts.arm) {
        uint8_t *stk = (uint8_t *)low_alloc(ts.stacksize, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
        t->stack_top = (uint64_t)(stk + ts.stacksize); t->stack_size = ts.stacksize;
        enter_gthread(t);
        uint64_t a[1] = {(uint64_t)ts.arg};
        run_arm64((uint64_t)ts.start, a, 1, (uint64_t)(stk + ts.stacksize), t);
        arm64_thread_end();
        VirtualFree(stk, 0, MEM_RELEASE);   /* games and servers start and end threads all the time */
        t->stack_top = 0;
    } else {
        enter_gthread(t);
        ((SYSV void *(*)(void *))ts.start)((void *)ts.arg);
    }
    return 0;
}
bool g_guest_arm;
static A hc_thread(A start, A arg, A stacksize, A, A, A) {
    if (stacksize < 64 * 1024) stacksize = 64 * 1024;
    struct gthread *t = alloc_gthread();
    ThreadStart *ts = new ThreadStart{start, arg, stacksize, g_guest_arm, t};
    /* x86_64 guests run on this stack: commit it fully (Go code does not probe guard pages) */
    HANDLE h = CreateThread(nullptr, g_guest_arm ? 256 * 1024 : (SIZE_T)stacksize, thread_entry, ts, CREATE_SUSPENDED, nullptr);
    if (!h) { delete ts; return -D_EAGAIN; }
    t->handle = (uint64_t)h; /* ponytail: handle never closed (threads are few) */
    ResumeThread(h);
    return (A)t;
}
static A hc_join(A t, A, A, A, A, A) { WaitForSingleObject((HANDLE)((struct gthread *)t)->handle, INFINITE); return 0; }
static A hc_chdir(A path, A, A, A, A, A) { return SetCurrentDirectoryW(darwin_to_win((const char *)path, -1).c_str()) ? 0 : err_from_win(); }
static A hc_ftruncate(A fd, A len, A, A, A, A) {
    Fd *f = fd_get(fd); if (!f || f->kind != FD_FILE) return -D_EBADF;
    LARGE_INTEGER cur{}, z{}, l; l.QuadPart = len;
    SetFilePointerEx(f->h, z, &cur, FILE_CURRENT);
    BOOL ok = SetFilePointerEx(f->h, l, nullptr, FILE_BEGIN) && SetEndOfFile(f->h);
    SetFilePointerEx(f->h, cur, nullptr, FILE_BEGIN);
    return ok ? 0 : err_from_win();
}
static A hc_rename(A a, A b, A, A, A, A) {
    return MoveFileExW(darwin_to_win((const char *)a, -1).c_str(), darwin_to_win((const char *)b, -1).c_str(), MOVEFILE_REPLACE_EXISTING) ? 0 : err_from_win();
}
static A hc_realpath(A path, A out, A fd, A, A, A) {   /* path == 0: the path of open descriptor fd (F_GETPATH) */
    std::wstring w;
    if (!path) { if (fd < 0 || fd >= (A)g_fds.size() || g_fds[fd].path.empty()) return -D_EBADF; w = g_fds[fd].path; }
    else w = darwin_to_win((const char *)path, -1);
    if (GetFileAttributesW(w.c_str()) == INVALID_FILE_ATTRIBUTES) return err_from_win();
    wchar_t full[32768]; GetFullPathNameW(w.c_str(), 32768, full, nullptr);
    std::string d = win_to_darwin(narrow(full));
    if (d.size() >= 1024) return -D_ENAMETOOLONG;
    memcpy((void *)out, d.c_str(), d.size() + 1);
    return 0;
}
static A hc_pipe(A fds, A, A, A, A, A) {
    HANDLE r, w; if (!CreatePipe(&r, &w, nullptr, 0)) return err_from_win();
    Fd fr; fr.kind = FD_FILE; fr.h = r; Fd fw; fw.kind = FD_FILE; fw.h = w;
    ((int *)fds)[0] = fd_alloc(std::move(fr)); ((int *)fds)[1] = fd_alloc(std::move(fw));
    return 0;
}
extern "C" double _j0(double), _j1(double), _jn(int, double), _y0(double), _y1(double), _yn(int, double); /* UCRT Bessel functions */
static A hc_math(A op, A a, A b, A c, A, A) {
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
    case M_EXP2: r = exp2(x); break;
    case M_ERF: r = erf(x); break; case M_ERFC: r = erfc(x); break; case M_TGAMMA: r = tgamma(x); break;
    case M_LGAMMA: r = lgamma(x); break;
    /* Bessel functions: the CRT's (_j0 ...) */
    case M_J0: r = _j0(x); break; case M_J1: r = _j1(x); break; case M_JN: r = _jn((int)y, x); break;
    case M_Y0: r = _y0(x); break; case M_Y1: r = _y1(x); break; case M_YN: r = _yn((int)y, x); break;
    }
    A out; memcpy(&out, &r, 8); return out;
}

/* ======================================================================= startup */
struct Startup { Image *main; int argc; std::vector<std::string> argv, envp, apple; };

/* call guest code from the host on the current thread (initializers, objc registration) */
uint64_t call_guest(uint64_t fn, const uint64_t *a, int n) {
    if (g_guest_arm) { struct gthread *t = cur_gthread(); return run_arm64(fn, a, n, t->stack_top - 64 * 1024, t); }
    uint64_t r[6] = {0};
    for (int i = 0; i < n && i < 6; i++) r[i] = a[i];
    return ((SYSV uint64_t (*)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t))fn)(r[0], r[1], r[2], r[3], r[4], r[5]);
}

extern "C" void __attribute__((noreturn)) jump_unixthread(uint64_t sp, uint64_t pc); /* ms_abi: rcx=sp, rdx=pc */
asm(".globl jump_unixthread\njump_unixthread:\n mov %rcx, %rsp\n xor %eax, %eax\n xor %ebx, %ebx\n xor %ebp, %ebp\n jmp *%rdx\n");

static DWORD WINAPI guest_main(void *p) {
    Startup &s = *(Startup *)p;
    struct gthread *t = enter_gthread(alloc_gthread());
    DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), (HANDLE *)&t->handle, 0, FALSE, DUPLICATE_SAME_ACCESS);
    /* kernel layout, contiguous: argc, argv..., 0, envp..., 0, apple..., 0 (Go walks argv past argc to find envp) */
    std::vector<uint64_t> frame{(uint64_t)s.argc};
    for (auto *v : {&s.argv, &s.envp, &s.apple}) { for (auto &str : *v) frame.push_back((uint64_t)&str[0]); frame.push_back(0); }
    char **argv = (char **)&frame[1], **envp = argv + s.argv.size() + 1, **apple = envp + s.envp.size() + 1;
    auto setvar = [](const char *sym, uint64_t v) { auto it = g_libsys->syms.find(sym); if (it != g_libsys->syms.end()) *(uint64_t *)it->second = v; };
    setvar("_NXArgv", (uint64_t)argv); setvar("_environ", (uint64_t)envp);
    *(int *)g_libsys->syms["_NXArgc"] = s.argc;
    strncpy((char *)g_libsys->syms["_scion_exe_path"], s.argv[0].c_str(), 1023);
    Image &im = *s.main;
    uint64_t args4[4] = {(uint64_t)s.argc, (uint64_t)argv, (uint64_t)envp, (uint64_t)apple};
    if (im.arm) {
        uint8_t *stk = (uint8_t *)low_alloc(8 << 20, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
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
    int rc = ((SYSV int (*)(int, char **, char **, char **))im.entry)(s.argc, argv, envp, apple);
    hc_exit(rc, 0, 0, 0, 0, 0);
    return 0;
}

/* ---------- dyld services for the guest: image table, dlopen/dlsym/dladdr ---------- */
static void publish_image(Image *im) {
    struct MwImage { uint64_t mh; int64_t slide; const char *path; };
    MwImage *t = (MwImage *)g_libsys->syms["_scion_images"];
    uint32_t *n = (uint32_t *)g_libsys->syms["_scion_image_count"];
    if (!t || !n || *n >= 512) return;
    bool sys = !im->install_name.empty() && !im->path.rfind(g_lib_dir, 0);
    im->dpath = sys ? im->install_name : win_to_darwin(im->path);
    t[*n] = {im->mh_rt(), im->slide, im->dpath.c_str()};
    __atomic_store_n(n, *n + 1, __ATOMIC_RELEASE);
}
static void prepare_image(Image *im) {
    link_image(*im);
    setup_tlv(*im);
    int patched = patch_gs_tsd(*im, g_tls_go);
    if (patched) TRACE("%s: gs:TSD patches -> TlsSlots[%lu]: %d\n", im->path.c_str(), g_tls_go, patched);
    publish_image(im);
}
static std::recursive_mutex g_dlmu;
static std::string g_dlerr;
struct DlInfo { const char *fname; uint64_t fbase; const char *sname; uint64_t saddr; };
static A hc_dl(A op, A a, A b, A, A, A) {
    std::lock_guard<std::recursive_mutex> l(g_dlmu);
    if (op == 0) { /* dlopen */
        if (!a) return (A)g_main;
        std::string name = (const char *)a;
        for (Image *i : g_images) if (i->dpath == name || i->install_name == name) return (A)i;
        std::wstring w = darwin_to_win(name.c_str(), -1);
        DWORD at = GetFileAttributesW(w.c_str());
        std::string f = at != INVALID_FILE_ATTRIBUTES && !(at & FILE_ATTRIBUTE_DIRECTORY) && name[0] != '@' ? narrow(w) : locate_dl(name);
        if (f.empty()) { g_dlerr = "dlopen(" + name + ", 1): image not found"; return 0; }
        for (Image *i : g_images) if (!_stricmp(i->path.c_str(), f.c_str())) return (A)i;
        size_t before = g_images.size();
        Image *im = load_dl(f);
        if (!im) { g_dlerr = "dlopen(" + name + "): not a compatible Mach-O"; return 0; }
        for (size_t k = before; k < g_images.size(); k++) prepare_image(g_images[k]);
        TRACE("dlopen %s -> %s\n", name.c_str(), f.c_str());
        init_image(im);
        return (A)im;
    }
    if (op == 1) { /* dlsym: RTLD_NEXT -1, RTLD_DEFAULT -2, RTLD_SELF -3, RTLD_MAIN_ONLY -5 */
        std::string n = std::string("_") + (const char *)b;
        if (a == -5) return (A)dl_sym(g_main, n);
        if (a < 0 && a >= -5) {   /* libSystem last: its CoreFoundation stubs (CFRunLoopRun...) must not hide Foundation's */
            Image *sys = nullptr;
            for (Image *i : g_images) {
                if (i->path.find("libSystem") != std::string::npos) { sys = i; continue; }
                if (uint64_t v = dl_sym(i, n)) return (A)v;
            }
            return sys ? (A)dl_sym(sys, n) : 0;
        }
        return (A)dl_sym((Image *)a, n);
    }
    if (op == 2) { /* dladdr */
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

static std::string exe_dir() {
    wchar_t w[MAX_PATH]; GetModuleFileNameW(nullptr, w, MAX_PATH);
    std::string s = narrow(w); return s.substr(0, s.find_last_of("\\/"));
}

/* Under Wine, a Linux path argument ("/home/x/tool") becomes its DOS path ("Z:\home\x\tool"), so it is not taken for a
   path inside Scion's own root. Elsewhere (and for paths that do not exist on Linux) the argument is unchanged. */
static std::string from_unix(const std::string &a) {
    typedef WCHAR *(CDECL *dosname_fn)(const char *);
    static dosname_fn dosname = (dosname_fn)GetProcAddress(GetModuleHandleA("kernel32.dll"), "wine_get_dos_file_name");
    if (!dosname || a.empty() || a[0] != '/' || (a.size() > 1 && a[1] == '/')) return a;
    WCHAR *w = dosname(a.c_str()); if (!w) return a;
    std::string r = narrow(w); HeapFree(GetProcessHeap(), 0, w);
    return GetFileAttributesW(widen(r).c_str()) == INVALID_FILE_ATTRIBUTES ? a : r;
}

/* Windows-style path arguments become Darwin paths ("C:\a" -> "/c/a", "--x=C:\a" -> "--x=/c/a") */
static std::string conv_arg(const std::string &a0) {
    std::string a = from_unix(a0);
    auto isdrv = [&](size_t i) { return i + 2 < a.size() + 1 && isalpha((unsigned char)a[i]) && a[i + 1] == ':' && i + 2 < a.size() && (a[i + 2] == '\\' || a[i + 2] == '/'); };
    if (isdrv(0)) return win_to_darwin(a);
    if (a.find('\\') != std::string::npos && GetFileAttributesA(a.c_str()) != INVALID_FILE_ATTRIBUTES) {   /* a relative Windows path */
        std::string r = a; for (char &c : r) if (c == '\\') c = '/';
        return r;
    }
    size_t eq = a.find('=');
    if (eq != std::string::npos && isdrv(eq + 1)) return a.substr(0, eq + 1) + win_to_darwin(a.substr(eq + 1));
    return a;
}

int wmain(int wargc, wchar_t **wargv) {
    if (wargc < 2) {
        fprintf(stderr, "usage: scion <macOS program | App.app> [args...]\n       scion install <App.app>      (Start menu entry, icon, \"Open with\")\n"
                        "       scion uninstall <App.app | bundle id>\n"
                        "   SCION_TRACE=1 traces the program; SCION_ARCH=arm64 runs the arm64 slice of a universal binary\n");
        return 2;
    }
    { int rc; if (mw_subcommand(wargc, wargv, &rc)) return rc; }
    g_trace = getenv("SCION_TRACE") != nullptr;
    if (getenv("SCION_PROF")) prof_start();
    /* sharp windows on scaled screens: sizes are real pixels, AppKit converts to points with the screen's scale */
    typedef BOOL(WINAPI * dpictx_t)(HANDLE);
    if (auto f = (dpictx_t)GetProcAddress(GetModuleHandleW(L"user32.dll"), "SetProcessDpiAwarenessContext")) f((HANDLE)-4 /* PER_MONITOR_AWARE_V2 */);
    g_tls_self = TlsAlloc(); g_tls_go = TlsAlloc();
    AddVectoredExceptionHandler(1, guest_veh);
    SetUnhandledExceptionFilter([](PEXCEPTION_POINTERS ep) -> LONG {
        fprintf(stderr, "[scion] exception %#lx in the host, address %#llx\n", ep->ExceptionRecord->ExceptionCode,
            (unsigned long long)(ep->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION ? ep->ExceptionRecord->ExceptionInformation[1] : 0));
        mw_backtrace(*ep->ContextRecord);
        return EXCEPTION_CONTINUE_SEARCH;
    });
    if (g_tls_go >= 64 || g_tls_self >= 64) die("no free direct TlsSlots");
    /* "/" for the guest: %LOCALAPPDATA%\scion\root (writable even when scion lives in Program Files) */
    if (const char *la = getenv("LOCALAPPDATA")) { g_root = std::string(la) + "\\scion"; CreateDirectoryA(g_root.c_str(), nullptr); g_root += "\\root"; }
    else g_root = exe_dir() + "\\root";
    CreateDirectoryA(g_root.c_str(), nullptr);
    g_fds.resize(3);
    DWORD stdh[3] = {STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE};
    for (int i = 0; i < 3; i++) { g_fds[i].kind = FD_FILE; g_fds[i].h = GetStdHandle(stdh[i]); }
    /* macOS tools write UTF-8 and ANSI colors */
    SetConsoleOutputCP(CP_UTF8);
    /* Sleep() and timed waits round up to the system timer tick (15.6 ms by default), so a program pacing its threads
     * with 1-2 ms waits waited up to 15x longer. Ask for 1 ms ticks, also while the window is hidden (Windows 11
     * otherwise lets a hidden process fall back to the coarse tick). */
    timeBeginPeriod(1);
    { PROCESS_POWER_THROTTLING_STATE pt = {PROCESS_POWER_THROTTLING_CURRENT_VERSION, 4 /* IGNORE_TIMER_RESOLUTION */, 0};
      SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, &pt, sizeof pt); }
    for (int i = 1; i < 3; i++) { DWORD m; if (GetConsoleMode(g_fds[i].h, &m)) SetConsoleMode(g_fds[i].h, m | 0x4 /* VIRTUAL_TERMINAL_PROCESSING */); }

    std::string mainpath = from_unix(narrow(wargv[1]));
    { std::string exe = mw_bundle_executable(mainpath); if (!exe.empty()) mainpath = exe; } /* App.app: its Contents/MacOS executable */
    g_lib_dir = exe_dir() + "\\lib";
    Image *main = load_all(mainpath);
    if (!main) die("not a valid 64-bit Mach-O executable");
    g_guest_arm = main->arm;

    /* hostcall table inside the guest libSystem */
    uint64_t *table = (uint64_t *)g_libsys->syms["_scion_hc"];
    if (!table) die("libSystem lacks _scion_hc");
    if (main->arm) {
        arm64_init(mainpath);
        for (int i = 0; i < HC_COUNT; i++) table[i] = (uint64_t)(g_arm_thunks + 2 * i);
        g_missing_stub = (uint64_t)(g_arm_thunks + 2 * HC_exit); /* exit(x0) */
    } else {
        for (int i = 0; i < HC_COUNT; i++) table[i] = (uint64_t)g_hc[i];
        g_missing_stub = g_libsys->syms["_dyld_stub_binder"];
    }
    *(uint64_t *)g_libsys->syms["_scion_tsd_off"] = 0x1480 + 8 * g_tls_self;
    for (size_t k = 0; k < g_images.size(); k++) prepare_image(g_images[k]);
    if (!g_missing.empty()) for (auto &m : g_missing) TRACE("unimplemented import: %s\n", m.c_str());
    if (!main->entry) die("no entry point");

    Startup s; s.main = main; s.argc = wargc - 1;
    s.argv.push_back(win_to_darwin(mainpath));
    for (int i = 2; i < wargc; i++) s.argv.push_back(conv_arg(narrow(wargv[i])));
    wchar_t *env = GetEnvironmentStringsW();
    for (wchar_t *e = env; *e; e += wcslen(e) + 1) {
        std::string kv = narrow(e);
        if (kv[0] == '=') continue;
        std::string k = kv.substr(0, kv.find('='));
        if (k == "USERPROFILE") s.envp.push_back("HOME=" + win_to_darwin(kv.substr(k.size() + 1)));
        if (k == "TEMP") s.envp.push_back("TMPDIR=" + win_to_darwin(kv.substr(k.size() + 1)));
        s.envp.push_back(kv);
    }
    FreeEnvironmentStringsW(env);
    s.apple.push_back("executable_path=" + s.argv[0]);
    HANDLE h = CreateThread(nullptr, 8 << 20, guest_main, &s, 0, nullptr); /* 8 MB committed main stack */
    /* SCION_THREAD_DUMP=<s>: every <s> seconds, where each guest thread is (pc, lr and its frame chain, by image and
     * nearest exported symbol), with its slow memory accesses and JIT compilation per second: for programs that hang
     * or crawl. x86_64 guests: the main thread, once. */
    if (const char *t = getenv("SCION_THREAD_DUMP")) {
        static HANDLE main_thread; static DWORD every; main_thread = h; every = (DWORD)atoi(t); if (!every) every = 30;
        CreateThread(nullptr, 0, [](LPVOID) -> DWORD {
            if (!g_guest_arm) {
                Sleep(every * 1000);
                SuspendThread(main_thread);
                CONTEXT c = {}; c.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
                if (GetThreadContext(main_thread, &c)) { fprintf(stderr, "scion: main thread after %lu s\n", (unsigned long)every); guest_backtrace(c.Rip, c.Rbp, 0); }
                ResumeThread(main_thread);
                return 0;
            }
            std::vector<uint64_t> before, before_code;
            for (int round = 1;; round++) {
                Sleep(every * 1000);
                std::vector<struct gthread *> ts;
                { std::lock_guard<std::mutex> l(g_thrmu); ts = g_threads; }
                fprintf(stderr, "scion: thread dump %d (%lu s), %zu vm_remap aliases\n", round, (unsigned long)(every * round), arm64_alias_count());
                before.resize(ts.size()); before_code.resize(ts.size());
                for (size_t i = 0; i < ts.size(); i++) {
                    struct darm_state st; bool hc = false; uint64_t cb = 0, code = 0;
                    if (!ts[i] || !arm64_thread_peek(ts[i], &st, &hc, &cb, &code)) continue;
                    fprintf(stderr, " thread %zu%s: %llu slow accesses/s, %llu instructions compiled/s, x0 %llx x1 %llx x2 %llx\n", i,
                            hc ? " (waiting in the host)" : "", (unsigned long long)((cb >= before[i] ? cb - before[i] : cb) / every),
                            (unsigned long long)((code >= before_code[i] ? code - before_code[i] : code) / every),
                            (unsigned long long)st.x[0], (unsigned long long)st.x[1], (unsigned long long)st.x[2]);
                    before[i] = cb; before_code[i] = code;
                    guest_backtrace(st.pc, st.fp, st.lr);
                }
                fflush(stderr);
            }
            return 0;
        }, nullptr, 0, nullptr);
    }
    /* SCION_SAMPLE=<ms>[,<s>]: sampling profile of arm64 guests. Every <ms> each thread's pc is noted (its return
     * address, marked "host", while it is inside a host call); every <s> seconds (60) the 30 most frequent are printed.
     * Samples land where the JIT can stop (block boundaries), so they point at functions, not single instructions. */
    if (const char *t = getenv("SCION_SAMPLE")) {
        static DWORD ms, period; ms = (DWORD)atoi(t); if (!ms) ms = 5;
        const char *c = strchr(t, ','); period = 1000 * (c ? (DWORD)atoi(c + 1) : 60); if (!period) period = 60000;
        CreateThread(nullptr, 0, [](LPVOID) -> DWORD {
            std::unordered_map<uint64_t, unsigned> hist; unsigned total = 0, host = 0;
            for (ULONGLONG next = GetTickCount64() + period;;) {
                Sleep(ms);
                std::vector<struct gthread *> ts;
                { std::lock_guard<std::mutex> l(g_thrmu); ts = g_threads; }
                for (struct gthread *g : ts) {
                    struct darm_state st; bool hc = false; uint64_t cb, code;
                    if (!g || !arm64_thread_peek(g, &st, &hc, &cb, &code)) continue;
                    if (hc) { host++; hist[st.lr | 1ull << 63]++; } else hist[st.pc]++;
                    total++;
                }
                if (GetTickCount64() < next) continue;
                next += period;
                std::vector<std::pair<unsigned, uint64_t>> top;
                for (auto &kv : hist) top.push_back({kv.second, kv.first});
                std::sort(top.rbegin(), top.rend());
                fprintf(stderr, "scion: profile, %u samples, %.1f%% waiting in the host\n", total, total ? 100.0 * host / total : 0.0);
                for (size_t i = 0; i < top.size() && i < 30; i++) {
                    char tag[32]; snprintf(tag, sizeof tag, "%5.1f%%%s", 100.0 * top[i].first / total, top[i].second >> 63 ? " host" : "");
                    print_guest_addr(tag, top[i].second & ~(1ull << 63));
                }
                fflush(stderr);
                hist.clear(); total = host = 0;
            }
            return 0;
        }, nullptr, 0, nullptr);
    }
    WaitForSingleObject(h, INFINITE);
    return 0;
}
