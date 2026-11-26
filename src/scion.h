/* scion.h — declarations shared by the host translation units (Windows: host.cpp, Linux: host_linux.cpp). */
#pragma once
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define HCABI   /* host calls: the guest calls them with the Microsoft x64 convention, Windows' own */
#else
#include <stdint.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>
typedef uint32_t DWORD;
#define _stricmp strcasecmp
#define HCABI __attribute__((ms_abi))
#endif
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <string>
#include <vector>
#include <map>
#include "hostcalls.h"

#define SYSV __attribute__((sysv_abi))
extern bool g_trace;
#define TRACE(...) do { if (g_trace) fprintf(stderr, "[scion] " __VA_ARGS__); } while (0)
void die(const char *m);
bool mw_subcommand(int argc, wchar_t **argv, int *rc); /* install.cpp */
std::string mw_bundle_executable(const std::string &app);

typedef int64_t A;
typedef A (HCABI *hostfn)(A, A, A, A, A, A);
extern hostfn g_hc[HC_COUNT];
HCABI A hc_exit(A code, A, A, A, A, A);
HCABI A hc_clock(A kind, A, A, A, A, A);
std::string win_to_darwin(const std::string &w);
std::wstring darwin_to_win(const char *p, int dirfd);
void *low_alloc(size_t n, DWORD type, DWORD prot); /* guest memory below 2^39 (Windows) */
void *image_alloc(uint64_t at, uint64_t len);    /* an image's RWX mapping, at its address if free */
/* the whole file, read-only and never unmapped (images live as long as the process); nullptr on failure */
const uint8_t *host_map_file(const std::string &path, size_t *size);
/* the file's [off, off+len) copy-on-write and RWX at dst (inside an image_alloc mapping), page-aligned; false: copy it */
bool host_map_segment(void *dst, uint64_t len, const std::string &path, uint64_t off);
/* the mapping around a: [lo, hi) with D_PROT_* bits; false if nothing is mapped there */
bool host_mem_query(uint64_t a, uint64_t *lo, uint64_t *hi, int *prot);
int host_pid();
HCABI A hc_ui(A op, A a, A b, A c, A d, A e); /* ui.cpp */
/* net.cpp: sockets and kqueue for both hosts */
HCABI A hc_net(A op, A a, A b, A c, A d, A e);
/* http.cpp: HTTP(S) for URLSession (NET_HTTP_*) */
A http_op(A op, A a, A b, A c);
HCABI A hc_kqueue(A, A, A, A, A, A);
HCABI A hc_kevent(A kq, A changes, A nchanges, A events, A nevents, A timeout_ns);
void net_fd_closed(int fd);   /* every close: a kqueue, or registrations of the descriptor, go */
A net_sock_io(int fd, uintptr_t s, void *buf, size_t n, bool write);   /* Windows: read/write on a socket descriptor */
extern DWORD g_tls_self;
extern bool g_guest_arm;

/* ---- Mach-O images (dyld.cpp) ---- */
struct seg64 { uint32_t cmd, cmdsize; char segname[16]; uint64_t vmaddr, vmsize, fileoff, filesize; uint32_t maxprot, initprot, nsects, flags; };
struct sect64 { char sectname[16], segname[16]; uint64_t addr, size; uint32_t offset, align, reloff, nreloc, flags, r1, r2, r3; };
struct dyldinfo { uint32_t cmd, cmdsize, rebase_off, rebase_size, bind_off, bind_size, weak_off, weak_size, lazy_off, lazy_size, export_off, export_size; };
struct linkedit { uint32_t cmd, cmdsize, off, size; };
#define CPU_X86_64 0x01000007u
#define CPU_ARM64 0x0100000cu
struct Image {
    std::string path;
    const uint8_t *file = nullptr; size_t file_size = 0;   /* host_map_file */
    uint8_t *mh = nullptr;      /* header inside file */
    uint8_t *base = nullptr;    /* mapped address of the lowest segment */
    int64_t slide = 0;
    uint64_t size = 0;
    bool arm = false;
    std::vector<seg64 *> segs;
    dyldinfo *di = nullptr;
    linkedit *chained = nullptr, *exports = nullptr;
    uint64_t entry = 0; bool unixthread = false;
    std::map<std::string, uint64_t> syms; /* exported symbol -> runtime address */
    std::map<std::string, std::pair<int, std::string>> reexported; /* trie re-exports: name -> (ordinal, import name) */
    std::string install_name;
    std::string dpath;          /* Darwin-side path reported by _dyld_get_image_name / dladdr */
    std::vector<std::string> dep_names, rpaths;
    std::vector<bool> dep_weak, dep_reexport;
    std::vector<Image *> deps;  /* index = library ordinal - 1 */
    bool inited = false;
    uint64_t vm(uint64_t a) const { return a + slide; }
    uint64_t mh_rt() const { /* runtime address of the mach header (start of __TEXT) */
        for (seg64 *s : segs) if (!strncmp(s->segname, "__TEXT", 16)) return vm(s->vmaddr);
        return 0;
    }
};
Image *map_image(const std::string &path, uint32_t want);
Image *load_all(const std::string &main_path);   /* main + dependencies, linked */
void init_all(Image *main, uint64_t *args4);      /* objc registration + initializers, dependencies first */
void init_image(Image *im);                       /* same, for an image added by dlopen */
std::string locate_dl(const std::string &name);   /* install name / @rpath / bare name -> file, "" if absent */
Image *load_dl(const std::string &file);          /* load + dependencies (not linked yet), nullptr on failure */
uint64_t dl_sym(Image *im, const std::string &name);
extern Image *g_main;
Image *find_image(const char *install_suffix);
void link_image(Image &im);
void setup_tlv(Image &im);
uint64_t call_guest(uint64_t fn, const uint64_t *args, int n); /* host.cpp */
extern std::string g_lib_dir;
int patch_gs_tsd(Image &im, DWORD tls_idx);
extern Image *g_libsys;
extern std::vector<Image *> g_images;
bool guest_pc(uint64_t pc);

/* ---- signals (host.cpp) ---- */
extern struct dsigaction g_sig[64];
struct gthread *cur_gthread();
extern uint64_t g_missing_stub;
extern std::vector<std::string> g_missing;

/* ---- arm64 guests (arm64.cpp) ---- */
extern uint32_t *g_arm_thunks;
void arm64_init(const std::string &main_path);
void arm64_exit(void); /* process exit */
uint64_t run_arm64(uint64_t pc, const uint64_t *args, int nargs, uint64_t sp, struct gthread *t);
void arm64_thread_end(void); /* frees the thread's JITs (end of a guest thread) */
void arm64_signal(struct gthread *t, int sig); /* async: deliver at the next block boundary */
void arm64_invalidate(uint64_t addr, uint64_t len);   /* guest code at [addr, addr+len) changed */
void arm64_alias_set(uint64_t dst, uint64_t len, uint64_t src); /* drop aliases overlapping dst; then dst -> src if src */
void arm64_mem_changed(void);                         /* mprotect/munmap: forget the validated regions */
uint64_t arm64_translate(uint64_t a);                  /* guest address -> backing address (vm_remap aliases) */
size_t arm64_alias_count();
int arm64_thread_ctl(struct gthread *t, int op, int flavor, void *state);   /* mach thread_suspend/resume/get/set_state */
bool arm64_thread_peek(struct gthread *t, struct darm_state *st, bool *hostcall, uint64_t *callbacks, uint64_t *code_reads);
