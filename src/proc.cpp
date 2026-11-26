/* proc.cpp — child processes for the guest (HC_proc): posix_spawn, waitpid and kill, on both hosts.
 *
 * A Mach-O program runs in a new scion process (this executable, with the program and its arguments); anything else
 * runs natively: on Linux any executable, on Windows an .exe, where a Darwin path under /bin, /usr/bin... that does
 * not exist names a program on the PATH ("/usr/bin/git" -> git.exe) and a shell without sh.exe falls back to cmd.exe.
 * Signal numbers, wait statuses and errnos crossing here are Darwin's. */
#include "scion.h"
#include <algorithm>
#include <mutex>
#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#endif

static inline A G(A x) { return g_guest_arm ? (A)arm64_translate((uint64_t)x) : x; }
template<typename T> static T *GP(A x) { return x ? (T *)G(x) : nullptr; }
static std::vector<std::string> strings(A v) {   /* a guest char *[] */
    std::vector<std::string> out;
    for (uint64_t *p = GP<uint64_t>(v); p && *p; p++) out.push_back(GP<char>((A)*p));
    return out;
}
static bool is_macho(const unsigned char *m) {
    uint32_t v; memcpy(&v, m, 4);
    return v == 0xfeedfacf || v == 0xbebafeca || v == 0xbfbafeca;   /* 64-bit Mach-O, universal (32- and 64-bit offsets) */
}

#ifdef _WIN32
/* ======================================================================= Windows */
HANDLE host_fd_handle(int fd);   /* host.cpp */
static std::mutex g_pmu;   /* the children; also makes CreateProcess calls one at a time, so each child inherits only
                            * its own descriptors */
static std::map<DWORD, HANDLE> g_children;

static std::wstring wide(const std::string &s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, 0);
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), &w[0], n);
    return w;
}
/* one argument as CommandLineToArgvW and the C runtime read it back */
static void quote(std::wstring &out, const std::wstring &a) {
    if (!out.empty()) out += L' ';
    if (!a.empty() && a.find_first_of(L" \t\n\v\"") == std::wstring::npos) { out += a; return; }
    out += L'"';
    for (size_t i = 0;; i++) {
        size_t bs = 0;
        while (i < a.size() && a[i] == L'\\') { i++; bs++; }
        if (i == a.size()) { out.append(bs * 2, L'\\'); break; }
        if (a[i] == L'"') out.append(bs * 2 + 1, L'\\');
        else out.append(bs, L'\\');
        out += a[i];
    }
    out += L'"';
}
static A werr(DWORD e = GetLastError()) {
    switch (e) {
    case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: case ERROR_INVALID_NAME: return -D_ENOENT;
    case ERROR_ACCESS_DENIED: return -D_EACCES;
    case ERROR_BAD_EXE_FORMAT: case ERROR_EXE_MACHINE_TYPE_MISMATCH: return -8;   /* ENOEXEC */
    case ERROR_NOT_ENOUGH_MEMORY: case ERROR_OUTOFMEMORY: return -D_ENOMEM;
    }
    return -D_EINVAL;
}
static bool exists(const std::wstring &p) { DWORD a = GetFileAttributesW(p.c_str()); return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY); }
static std::wstring on_path(const std::string &name) {
    wchar_t out[MAX_PATH * 2];
    DWORD n = SearchPathW(nullptr, wide(name).c_str(), L".exe", MAX_PATH * 2, out, nullptr);
    return n && n < MAX_PATH * 2 ? std::wstring(out, n) : std::wstring();
}

static A proc_spawn(dspawn *s) {
    std::string path = GP<char>(s->path) ? GP<char>(s->path) : "";
    std::vector<std::string> args = strings(s->argv), env = strings(s->envp);
    if (path.empty()) return -D_ENOENT;
    std::wstring app, cmd, cwd;
    bool macho = false;
    size_t slash = path.find_last_of('/');
    std::string base = path.substr(slash == std::string::npos ? 0 : slash + 1);
    bool unix_bin = false;
    for (const char *d : {"/bin/", "/usr/bin/", "/usr/local/bin/", "/sbin/", "/usr/sbin/", "/opt/homebrew/bin/"})
        if (path.rfind(d, 0) == 0 && slash == strlen(d) - 1) unix_bin = true;
    std::wstring wp = slash == std::string::npos && s->search ? std::wstring() : darwin_to_win(path.c_str(), D_AT_FDCWD);
    if (!wp.empty() && exists(wp)) {
        HANDLE f = CreateFileW(wp.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, 0, nullptr);
        if (f == INVALID_HANDLE_VALUE) return werr();
        unsigned char m[4] = {}; DWORD got = 0;
        ReadFile(f, m, 4, &got, nullptr);
        CloseHandle(f);
        macho = got == 4 && is_macho(m);
        app = wp;
    } else if (s->search || unix_bin) {
        app = on_path(base);
        if (app.empty()) {
            /* no sh.exe: "sh -c <command>" runs the command with cmd.exe (ponytail: cmd's syntax, not sh's) */
            if ((base == "sh" || base == "bash") && args.size() == 3 && args[1] == "-c")
                cmd = L"cmd.exe /d /s /c \"" + wide(args[2]) + L"\"";
            else return -D_ENOENT;
        }
    } else return -D_ENOENT;
    if (cmd.empty()) {
        if (macho) {
            /* this scion runs it; the arguments are passed as they are (SCION_RAW_ARGS), the program by its Windows
             * path and by the Darwin path it is known by */
            wchar_t self[MAX_PATH * 2]; GetModuleFileNameW(nullptr, self, MAX_PATH * 2);
            quote(cmd, self); quote(cmd, app); quote(cmd, wide(path));
            for (size_t i = 1; i < args.size(); i++) quote(cmd, wide(args[i]));
            env.push_back("SCION_RAW_ARGS=1");
            app = self;
        } else for (size_t i = 0; i < args.size(); i++) quote(cmd, wide(i == 0 && args[0].empty() ? base : args[i]));
        if (cmd.empty()) quote(cmd, app);
    } else app.clear();

    /* the descriptors after the file actions: only 0-2 reach the child */
    std::map<int, HANDLE> fds;
    std::vector<int> opened;
    auto handle = [&](int fd) { auto it = fds.find(fd); return it != fds.end() ? it->second : host_fd_handle(fd); };
    A rc = 0;
    for (int i = 0; i < s->nactions && !rc; i++) {
        dspawn_action &a = GP<dspawn_action>(s->actions)[i];
        switch (a.op) {
        case D_SPAWN_CLOSE: fds[a.fd] = INVALID_HANDLE_VALUE; break;
        case D_SPAWN_DUP2: {
            HANDLE h = handle(a.fd);
            if (h == INVALID_HANDLE_VALUE) rc = -D_EBADF; else fds[a.newfd] = h;
            break;
        }
        case D_SPAWN_OPEN: {
            A fd = g_hc[HC_open](D_AT_FDCWD, (A)a.path, a.oflag, a.mode, 0, 0);
            if (fd < 0) rc = fd; else { opened.push_back((int)fd); fds[a.fd] = host_fd_handle((int)fd); }
            break;
        }
        case D_SPAWN_CHDIR: cwd = darwin_to_win(GP<char>((A)a.path), D_AT_FDCWD); break;
        }
    }
    /* what Windows programs (scion among them) cannot start without, when the guest's environment lacks it */
    for (const char *k : {"SystemRoot", "SystemDrive", "windir", "ComSpec", "PATHEXT", "TEMP", "TMP", "USERPROFILE", "APPDATA", "LOCALAPPDATA"}) {
        bool have = false;
        for (auto &kv : env) if (!_strnicmp(kv.c_str(), k, strlen(k)) && kv[strlen(k)] == '=') have = true;
        if (const char *v = getenv(k)) if (!have) env.push_back(std::string(k) + "=" + v);
    }
    std::wstring block;
    for (auto &kv : env) { block += wide(kv); block += L'\0'; }
    block += L'\0';
    DWORD pid = 0;
    if (!rc) {
        std::lock_guard<std::mutex> l(g_pmu);
        STARTUPINFOW si{}; si.cb = sizeof si; si.dwFlags = STARTF_USESTDHANDLES;
        HANDLE *std_[3] = {&si.hStdInput, &si.hStdOutput, &si.hStdError};
        for (int i = 0; i < 3; i++) {
            HANDLE h = handle(i);
            *std_[i] = nullptr;
            if (h != INVALID_HANDLE_VALUE && h) DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), std_[i], 0, TRUE, DUPLICATE_SAME_ACCESS);
        }
        PROCESS_INFORMATION pi{};
        DWORD flags = CREATE_UNICODE_ENVIRONMENT | (GetConsoleWindow() ? 0 : CREATE_NO_WINDOW);
        if (CreateProcessW(app.empty() ? nullptr : app.c_str(), &cmd[0], nullptr, nullptr, TRUE, flags, &block[0],
                           cwd.empty() ? nullptr : cwd.c_str(), &si, &pi)) {
            CloseHandle(pi.hThread);
            pid = pi.dwProcessId;
            g_children[pid] = pi.hProcess;
        } else rc = werr();
        for (int i = 0; i < 3; i++) if (*std_[i]) CloseHandle(*std_[i]);
    }
    for (int fd : opened) g_hc[HC_close](fd, 0, 0, 0, 0, 0);
    TRACE("posix_spawn %s -> %ld\n", path.c_str(), rc ? (long)rc : (long)pid);
    return rc ? rc : (A)pid;
}

enum : DWORD { KILLED = 0xC5C10000 };   /* exit code of a process kill() ended: KILLED | signal */
static A proc_wait(A pid, A status, A options) {
    std::vector<DWORD> pids; std::vector<HANDLE> hs;
    {
        std::lock_guard<std::mutex> l(g_pmu);
        for (auto &c : g_children) if (pid <= 0 || (DWORD)pid == c.first) { pids.push_back(c.first); hs.push_back(c.second); }
    }
    if (hs.empty()) return -D_ECHILD;
    if (hs.size() > MAXIMUM_WAIT_OBJECTS) { hs.resize(MAXIMUM_WAIT_OBJECTS); pids.resize(MAXIMUM_WAIT_OBJECTS); }   /* ponytail: 64 children waited for together */
    DWORD r = WaitForMultipleObjects((DWORD)hs.size(), hs.data(), FALSE, (options & D_WNOHANG) ? 0 : INFINITE);
    if (r == WAIT_TIMEOUT) return 0;
    if (r >= WAIT_OBJECT_0 + hs.size()) return werr();
    DWORD code = 0, which = pids[r - WAIT_OBJECT_0];
    GetExitCodeProcess(hs[r - WAIT_OBJECT_0], &code);
    {
        std::lock_guard<std::mutex> l(g_pmu);
        auto it = g_children.find(which);
        if (it == g_children.end()) return -D_ECHILD;   /* another thread reaped it */
        CloseHandle(it->second);
        g_children.erase(it);
    }
    if (int *st = GP<int>(status)) *st = (code & 0xFFFFFF00) == KILLED ? (int)(code & 0x7f) : (int)((code & 0xff) << 8);
    return which;
}

static A proc_kill(A pid, A sig) {
    HANDLE h = nullptr; bool own = false;
    {
        std::lock_guard<std::mutex> l(g_pmu);
        auto it = g_children.find((DWORD)pid);
        if (it != g_children.end()) { h = it->second; own = true; }
    }
    if (!h) h = OpenProcess(PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
    if (!h) return GetLastError() == ERROR_ACCESS_DENIED ? -D_EPERM : -D_ESRCH;
    DWORD code = 0;
    A rc = 0;
    if (!GetExitCodeProcess(h, &code) || code != STILL_ACTIVE) rc = own ? 0 : -D_ESRCH;   /* (a zombie for kill(0)) */
    else if (sig == 0 || sig == 16 || sig == 19 || sig == 20 || sig == 28 || sig == 29) rc = 0;   /* URG CONT CHLD WINCH INFO: ignored by default */
    else if (sig == 17 || sig == 18) rc = -45;   /* ponytail: no stopping (STOP, TSTP) */
    else if (!TerminateProcess(h, KILLED | (DWORD)(sig & 0x7f))) rc = werr();   /* ponytail: no handlers run in the child */
    if (!own) CloseHandle(h);
    return rc;
}

#else
/* ======================================================================= Linux */
A host_open_flags(A fl);   /* host_linux.cpp */
static const int g_sigs[32] = {0, SIGHUP, SIGINT, SIGQUIT, SIGILL, SIGTRAP, SIGABRT, 0 /* EMT */, SIGFPE, SIGKILL, SIGBUS,
    SIGSEGV, SIGSYS, SIGPIPE, SIGALRM, SIGTERM, SIGURG, SIGSTOP, SIGTSTP, SIGCONT, SIGCHLD, SIGTTIN, SIGTTOU, SIGIO,
    SIGXCPU, SIGXFSZ, SIGVTALRM, SIGPROF, SIGWINCH, 0 /* INFO */, SIGUSR1, SIGUSR2};   /* by Darwin number */
static int to_darwin(int s) { for (int i = 1; i < 32; i++) if (g_sigs[i] == s) return i; return s; }

static A proc_spawn(dspawn *s) {
    std::string path = GP<char>(s->path) ? GP<char>(s->path) : "";
    std::vector<std::string> args = strings(s->argv), env = strings(s->envp);
    if (path.empty()) return -ENOENT;
    if (s->search && path.find('/') == std::string::npos) {
        std::string found;
        const char *p = getenv("PATH");
        std::string dirs = p ? p : "/usr/bin:/bin";
        for (size_t i = 0; found.empty() && i <= dirs.size();) {
            size_t j = dirs.find(':', i); if (j == std::string::npos) j = dirs.size();
            std::string f = (j > i ? dirs.substr(i, j - i) : ".") + "/" + path;
            if (access(f.c_str(), X_OK) == 0) found = f;
            i = j + 1;
        }
        if (found.empty()) return -ENOENT;
        path = found;
    }
    int f = open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (f < 0) return -errno;
    unsigned char m[4] = {};
    bool macho = read(f, m, 4) == 4 && is_macho(m);
    close(f);
    std::string exe = path;
    if (macho) {   /* this scion runs it */
        char self[4096]; ssize_t n = readlink("/proc/self/exe", self, sizeof self - 1);
        if (n <= 0) return -ENOENT;
        exe.assign(self, n);
        args.insert(args.begin(), exe);
        if (args.size() > 1) args[1] = path; else args.push_back(path);
    }
    std::vector<char *> av, ev;
    for (auto &a : args) av.push_back(&a[0]);
    av.push_back(nullptr);
    for (auto &e : env) ev.push_back(&e[0]);
    ev.push_back(nullptr);

    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    int top = 2;
    for (int i = 0; i < s->nactions; i++) {
        dspawn_action &a = GP<dspawn_action>(s->actions)[i];
        switch (a.op) {
        case D_SPAWN_CLOSE: posix_spawn_file_actions_addclose(&fa, a.fd); break;
        case D_SPAWN_DUP2: posix_spawn_file_actions_adddup2(&fa, a.fd, a.newfd); top = std::max(top, a.newfd); break;
        case D_SPAWN_OPEN: posix_spawn_file_actions_addopen(&fa, a.fd, GP<char>((A)a.path), (int)host_open_flags(a.oflag), a.mode); top = std::max(top, a.fd); break;
        case D_SPAWN_CHDIR: posix_spawn_file_actions_addchdir_np(&fa, GP<char>((A)a.path)); break;
        case D_SPAWN_INHERIT: top = std::max(top, a.fd); break;
        }
    }
    /* POSIX_SPAWN_CLOEXEC_DEFAULT: what the actions do not name stays here (ponytail: anything up to the highest
     * descriptor they name is inherited) */
    if (s->close_others) posix_spawn_file_actions_addclosefrom_np(&fa, top + 1);
    /* the child starts with no blocked signals and default handling of those scion ignores (SIGPIPE) */
    posix_spawnattr_t at; posix_spawnattr_init(&at);
    sigset_t none, def; sigemptyset(&none); sigemptyset(&def); sigaddset(&def, SIGPIPE);
    posix_spawnattr_setsigmask(&at, &none); posix_spawnattr_setsigdefault(&at, &def);
    posix_spawnattr_setflags(&at, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
    pid_t pid = 0;
    int r = posix_spawn(&pid, exe.c_str(), &fa, &at, av.data(), ev.data());
    posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&at);
    TRACE("posix_spawn %s -> %d\n", path.c_str(), r ? -r : pid);
    return r ? -r : pid;   /* (the errnos it gives match Darwin's) */
}

static A proc_wait(A pid, A status, A options) {
    int st = 0; pid_t r;
    while ((r = waitpid((pid_t)pid, &st, (options & D_WNOHANG) ? WNOHANG : 0)) < 0 && errno == EINTR) {}
    if (r < 0) return -errno;
    if (r > 0) if (int *out = GP<int>(status))
        *out = WIFEXITED(st) ? WEXITSTATUS(st) << 8 : WIFSIGNALED(st) ? to_darwin(WTERMSIG(st)) | (WCOREDUMP(st) ? 0x80 : 0)
             : WIFSTOPPED(st) ? 0x7f | to_darwin(WSTOPSIG(st)) << 8 : st;
    return r;
}

static A proc_kill(A pid, A sig) {
    if (sig < 0 || sig >= 32 || (sig && !g_sigs[sig])) return -D_EINVAL;
    return ::kill((pid_t)pid, g_sigs[sig]) ? -errno : 0;
}
#endif

HCABI A hc_proc(A op, A a, A b, A c, A, A) {
    switch (op) {
    case PROC_SPAWN: { dspawn *s = GP<dspawn>(a); return s ? proc_spawn(s) : -D_EINVAL; }
    case PROC_WAIT: return proc_wait(a, b, c);
    case PROC_KILL: return proc_kill(a, b);
    }
    return -D_EINVAL;
}
