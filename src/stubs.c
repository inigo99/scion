/* stubs.c — parts of libSystem (and of the C frameworks scion does not provide) that apps import but rarely need to work:
 * OSAtomic, fts, statfs, Mach messaging, asl, compiler-rt odds and ends; and Tcl, xar, bzip2, zlib's uncompress, Disk
 * Arbitration, Authorization, Service Management, Security transforms and the Carbon File Manager, which answer "not
 * available" so the app takes its error path. Compiled against the Darwin SDK headers for the struct layouts. */
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/time.h>

/* ---------------- OSAtomic (deprecated on macOS, still imported by older code) ---------------- */
int32_t OSAtomicAdd32(int32_t v, volatile int32_t *p) { return __atomic_add_fetch(p, v, __ATOMIC_SEQ_CST); }
int32_t OSAtomicAdd32Barrier(int32_t v, volatile int32_t *p) { return __atomic_add_fetch(p, v, __ATOMIC_SEQ_CST); }
int64_t OSAtomicAdd64(int64_t v, volatile int64_t *p) { return __atomic_add_fetch(p, v, __ATOMIC_SEQ_CST); }
int64_t OSAtomicAdd64Barrier(int64_t v, volatile int64_t *p) { return __atomic_add_fetch(p, v, __ATOMIC_SEQ_CST); }
int32_t OSAtomicIncrement32(volatile int32_t *p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
int32_t OSAtomicIncrement32Barrier(volatile int32_t *p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
int32_t OSAtomicDecrement32(volatile int32_t *p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }
int32_t OSAtomicDecrement32Barrier(volatile int32_t *p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }
int64_t OSAtomicIncrement64(volatile int64_t *p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
int64_t OSAtomicIncrement64Barrier(volatile int64_t *p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
int64_t OSAtomicDecrement64(volatile int64_t *p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }
int64_t OSAtomicDecrement64Barrier(volatile int64_t *p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }
_Bool OSAtomicCompareAndSwap32(int32_t o, int32_t n, volatile int32_t *p) { return __atomic_compare_exchange_n(p, &o, n, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }
_Bool OSAtomicCompareAndSwap32Barrier(int32_t o, int32_t n, volatile int32_t *p) { return OSAtomicCompareAndSwap32(o, n, p); }
_Bool OSAtomicCompareAndSwap64(int64_t o, int64_t n, volatile int64_t *p) { return __atomic_compare_exchange_n(p, &o, n, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }
_Bool OSAtomicCompareAndSwap64Barrier(int64_t o, int64_t n, volatile int64_t *p) { return OSAtomicCompareAndSwap64(o, n, p); }
_Bool OSAtomicCompareAndSwapPtr(void *o, void *n, void *volatile *p) { return __atomic_compare_exchange_n(p, &o, n, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }
_Bool OSAtomicCompareAndSwapPtrBarrier(void *o, void *n, void *volatile *p) { return OSAtomicCompareAndSwapPtr(o, n, p); }
_Bool OSAtomicCompareAndSwapLong(long o, long n, volatile long *p) { return __atomic_compare_exchange_n(p, &o, n, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }
_Bool OSAtomicCompareAndSwapLongBarrier(long o, long n, volatile long *p) { return OSAtomicCompareAndSwapLong(o, n, p); }
int32_t OSAtomicOr32(uint32_t v, volatile uint32_t *p) { return (int32_t)__atomic_or_fetch(p, v, __ATOMIC_SEQ_CST); }
int32_t OSAtomicAnd32(uint32_t v, volatile uint32_t *p) { return (int32_t)__atomic_and_fetch(p, v, __ATOMIC_SEQ_CST); }
void OSMemoryBarrier(void) { __atomic_thread_fence(__ATOMIC_SEQ_CST); }
/* the lock-free LIFO queue: a spin lock is enough (ponytail: not lock-free) */
typedef struct { void *head; long gen; } mw_queue;
static volatile int q_lock;
void OSAtomicEnqueue(mw_queue *q, void *e, size_t off) {
    while (__atomic_exchange_n(&q_lock, 1, __ATOMIC_ACQUIRE)) {}
    *(void **)((char *)e + off) = q->head; q->head = e;
    __atomic_store_n(&q_lock, 0, __ATOMIC_RELEASE);
}
void *OSAtomicDequeue(mw_queue *q, size_t off) {
    while (__atomic_exchange_n(&q_lock, 1, __ATOMIC_ACQUIRE)) {}
    void *e = q->head; if (e) q->head = *(void **)((char *)e + off);
    __atomic_store_n(&q_lock, 0, __ATOMIC_RELEASE);
    return e;
}

/* ---------------- file system ---------------- */
int statfs(const char *p, struct statfs *s) {   /* the SDK names it statfs$INODE64 on x86_64 */
    memset(s, 0, sizeof *s);
    s->f_bsize = 4096; s->f_iosize = 1 << 20; s->f_blocks = 1ull << 28; s->f_bfree = s->f_bavail = 1ull << 27; /* as statvfs */
    s->f_files = s->f_ffree = 1u << 30; s->f_flags = MNT_LOCAL;
    strcpy(s->f_fstypename, "apfs"); strcpy(s->f_mntonname, "/"); strcpy(s->f_mntfromname, "/dev/disk1s1");
    return 0;
}
int fstatfs(int fd, struct statfs *s) { return statfs("/", s); }
/* ponytail: fts walks nothing; add a real walker when an app depends on it */
void *fts_open_i(char *const *paths, int opts, int (*cmp)(const void **, const void **)) __asm__("_fts_open$INODE64");
void *fts_open_i(char *const *paths, int opts, int (*cmp)(const void **, const void **)) { errno = ENOSYS; return 0; }
void *fts_read_i(void *f) __asm__("_fts_read$INODE64");
void *fts_read_i(void *f) { return 0; }
int fts_close_i(void *f) __asm__("_fts_close$INODE64");
int fts_close_i(void *f) { return 0; }
#if defined(__arm64__)
void *fts_open(char *const *paths, int opts, int (*cmp)(const void **, const void **)) { errno = ENOSYS; return 0; }
void *fts_read(void *f) { return 0; }
int fts_close(void *f) { return 0; }
#endif
int fchown(int fd, uid_t u, gid_t g) { return 0; }   /* Windows ownership is not mapped */
int lchown(const char *p, uid_t u, gid_t g) { return 0; }
int lchmod(const char *p, mode_t m) { return chmod(p, m); }
int futimes(int fd, const struct timeval t[2]) { return 0; }
char *devname_r(dev_t d, mode_t t, char *buf, int n) { return 0; }
int fileport_makefd(unsigned port) { errno = ENOSYS; return -1; }

/* ---------------- C library odds and ends ---------------- */
extern char **NXArgv;
static const char *progname;
const char *getprogname(void) {
    if (progname) return progname;
    const char *p = NXArgv && NXArgv[0] ? NXArgv[0] : "scion", *s = p;
    for (; *p; p++) if (*p == '/' || *p == '\\') s = p + 1;
    return s;
}
void setprogname(const char *n) { progname = n; }
int strcoll(const char *a, const char *b) { return strcmp(a, b); }
static void vwarn_(const char *f, va_list ap, int err) {
    fprintf(stderr, "%s: ", getprogname());
    if (f) vfprintf(stderr, f, ap);
    if (err >= 0) fprintf(stderr, "%s%s", f ? ": " : "", strerror(err));
    fputc('\n', stderr);
}
void warn(const char *f, ...) { int e = errno; va_list ap; va_start(ap, f); vwarn_(f, ap, e); va_end(ap); }
void warnx(const char *f, ...) { va_list ap; va_start(ap, f); vwarn_(f, ap, -1); va_end(ap); }
void vwarn(const char *f, va_list ap) { vwarn_(f, ap, errno); }
void vwarnx(const char *f, va_list ap) { vwarn_(f, ap, -1); }
/* hsearch-style tables of BSD's <hash.h>: not provided */
void *hash_create(int n) { return 0; }
void *hash_search(void *t, const char *k, void *d, void *r) { return 0; }
/* long double helpers (x86_64: 80-bit; arm64: same as double) */
long double ldexpl(long double x, int e) {
    while (e > 1000) { x *= 0x1p1000L; e -= 1000; }
    while (e < -1000) { x *= 0x1p-1000L; e += 1000; }
    return x * (long double)__builtin_ldexp(1.0, e);
}
#if defined(__x86_64__)
long double __floatuntixf(unsigned __int128 v) { return (long double)(uint64_t)(v >> 64) * 0x1p64L + (long double)(uint64_t)v; }
float __extendhfsf2(_Float16 h) {   /* half to float, from the bits */
    uint16_t b; memcpy(&b, &h, 2);
    uint32_t s = (uint32_t)(b & 0x8000) << 16, e = (b >> 10) & 0x1f, m = b & 0x3ff, r;
    if (e == 0x1f) r = s | 0x7f800000 | (m << 13);
    else if (e) r = s | ((e + 112) << 23) | (m << 13);
    else if (!m) r = s;
    else { e = 113; while (!(m & 0x400)) { m <<= 1; e--; } r = s | (e << 23) | ((m & 0x3ff) << 13); }
    float f; memcpy(&f, &r, 4); return f;
}
#endif

/* ---------------- Mach messaging and asl: no Mach ports here ---------------- */
typedef struct { unsigned char mig_vers, if_vers, reserved1, mig_encoding, int_rep, char_rep, float_rep, reserved2; } NDR_record_t;
NDR_record_t NDR_record = {0, 0, 0, 0, 1, 0, 0, 0};
const char *mach_error_string(int e) { return e ? "(os/kern) failure" : "(os/kern) successful"; }
int mach_msg(void *m, int opt, unsigned ss, unsigned rs, unsigned rn, unsigned to, unsigned notify) { return 0x10000003; } /* MACH_SEND_INVALID_DEST */
int mach_msg_send(void *m) { return 0x10000003; }
void mach_msg_destroy(void *m) {}
int mach_port_allocate(unsigned task, unsigned right, unsigned *name) { if (name) *name = 0; return 5; } /* KERN_FAILURE */
int mach_port_insert_right(unsigned task, unsigned name, unsigned poly, unsigned type) { return 5; }
unsigned mig_get_reply_port(void) { return 0; }
void mig_put_reply_port(unsigned p) {}
void mig_dealloc_reply_port(unsigned p) {}
int mig_strncpy(char *d, const char *s, int n) { if (n <= 0) return 0; int i = 0; for (; i < n - 1 && s[i]; i++) d[i] = s[i]; d[i] = 0; return i; }
void *asl_open(const char *ident, const char *facility, uint32_t opts) { return (void *)1; }
void *asl_new(uint32_t type) { return (void *)1; }
int asl_set(void *m, const char *k, const char *v) { return 0; }
int asl_send(void *c, void *m) { return 0; }
void asl_free(void *m) {}
void asl_close(void *c) {}
int asl_log(void *c, void *m, int level, const char *f, ...) { va_list ap; va_start(ap, f); vfprintf(stderr, f, ap); va_end(ap); fputc('\n', stderr); return 0; }

/* ---------------- zlib, bzip2, xar: archives the app may open; reported as unreadable ---------------- */
int uncompress(unsigned char *d, unsigned long *dn, const unsigned char *s, unsigned long sn) { return -3; } /* Z_DATA_ERROR */
void *BZ2_bzReadOpen(int *err, void *f, int verbosity, int small, void *unused, int nunused) { if (err) *err = -6; return 0; } /* BZ_IO_ERROR */
int BZ2_bzRead(int *err, void *b, void *buf, int n) { if (err) *err = -6; return 0; }
void BZ2_bzReadClose(int *err, void *b) { if (err) *err = 0; }
void *xar_open(const char *file, int32_t flags) { return 0; }
int xar_close(void *x) { return 0; }
void *xar_iter_new(void) { return 0; }
void *xar_file_first(void *x, void *i) { return 0; }
void *xar_file_next(void *i) { return 0; }
char *xar_get_path(void *f) { return 0; }
int32_t xar_extract_tofile(void *x, void *f, const char *p) { return -1; }
int32_t xar_prop_get(void *f, const char *k, const char **v) { if (v) *v = 0; return -1; }
void *xar_subdoc_first(void *x) { return 0; }
void *xar_subdoc_next(void *s) { return 0; }
const char *xar_subdoc_name(void *s) { return 0; }
int32_t xar_subdoc_prop_get(void *s, const char *k, const char **v) { if (v) *v = 0; return -1; }

/* ---------------- Tcl: no interpreter (scripts that need one report an error) ---------------- */
void *Tcl_CreateInterp(void) { return 0; }
void Tcl_DeleteInterp(void *i) {}
int Tcl_Init(void *i) { return 1; } /* TCL_ERROR */
int Tcl_Eval(void *i, const char *s) { return 1; }
int Tcl_EvalFile(void *i, const char *f) { return 1; }
int Tcl_EvalObjEx(void *i, void *o, int f) { return 1; }
const char *Tcl_GetStringResult(void *i) { return "Tcl is not available in scion"; }
void *Tcl_CreateObjCommand(void *i, const char *n, void *p, void *d, void *del) { return 0; }
int Tcl_GetCommandInfo(void *i, const char *n, void *info) { return 0; }
char *Tcl_Alloc(unsigned n) { return malloc(n); }
char *Tcl_Realloc(char *p, unsigned n) { return realloc(p, n); }
void Tcl_Free(char *p) { free(p); }
void TclFreeObj(void *o) {}
void Tcl_AddErrorInfo(void *i, const char *m) {}
void *Tcl_NewStringObj(const char *s, int n) { return 0; }
void *Tcl_NewIntObj(int v) { return 0; }
void *Tcl_NewWideIntObj(long long v) { return 0; }
void *Tcl_NewDoubleObj(double v) { return 0; }
void *Tcl_NewBooleanObj(int v) { return 0; }
void *Tcl_NewByteArrayObj(const unsigned char *b, int n) { return 0; }
void *Tcl_ObjPrintf(const char *f, ...) { return 0; }
void Tcl_AppendToObj(void *o, const char *s, int n) {}
void Tcl_AppendPrintfToObj(void *o, const char *f, ...) {}
void Tcl_SetObjResult(void *i, void *o) {}
void Tcl_WrongNumArgs(void *i, int n, void *const *objv, const char *m) {}
char *Tcl_GetString(void *o) { return ""; }
char *Tcl_GetStringFromObj(void *o, int *n) { if (n) *n = 0; return ""; }
unsigned char *Tcl_GetByteArrayFromObj(void *o, int *n) { if (n) *n = 0; return 0; }
int Tcl_GetIntFromObj(void *i, void *o, int *v) { return 1; }
int Tcl_GetLongFromObj(void *i, void *o, long *v) { return 1; }
int Tcl_GetDoubleFromObj(void *i, void *o, double *v) { return 1; }
int Tcl_DictObjGet(void *i, void *d, void *k, void **v) { if (v) *v = 0; return 1; }
void *Tcl_GetReturnOptions(void *i, int r) { return 0; }
void Tcl_GetTime(void *t) { struct timeval tv; gettimeofday(&tv, 0); ((long *)t)[0] = tv.tv_sec; ((long *)t)[1] = tv.tv_usec; }
void Tcl_LimitSetTime(void *i, void *t) {}
void Tcl_LimitTypeSet(void *i, int t) {}
void Tcl_SetErrno(int e) { errno = e; }

/* ---------------- Disk Arbitration, Authorization, Service Management, Security, Carbon File Manager ---------------- */
void *DASessionCreate(const void *alloc) { return 0; }
void DASessionScheduleWithRunLoop(void *s, void *rl, const void *mode) {}
void DASessionUnscheduleFromRunLoop(void *s, void *rl, const void *mode) {}
void DARegisterDiskAppearedCallback(void *s, const void *m, void *cb, void *ctx) {}
void DARegisterDiskDisappearedCallback(void *s, const void *m, void *cb, void *ctx) {}
void DAUnregisterCallback(void *s, void *cb, void *ctx) {}
const void *DADiskCopyDescription(void *d) { return 0; }
const char *DADiskGetBSDName(void *d) { return 0; }
enum { errAuthorizationDenied = -60005, errSecUnimplemented = -4, fnfErr = -43 };
int AuthorizationCreate(const void *r, const void *e, uint32_t f, void **a) { if (a) *a = 0; return errAuthorizationDenied; }
int AuthorizationFree(void *a, uint32_t f) { return 0; }
int AuthorizationCopyRights(void *a, const void *r, const void *e, uint32_t f, void **out) { if (out) *out = 0; return errAuthorizationDenied; }
int AuthorizationMakeExternalForm(void *a, void *ext) { return errAuthorizationDenied; }
int AuthorizationExecuteWithPrivileges(void *a, const char *tool, uint32_t o, char *const *args, void **pipe) { return errAuthorizationDenied; }
_Bool SMJobBless(const void *domain, const void *label, void *auth, void **err) { if (err) *err = 0; return 0; }
_Bool SMJobRemove(const void *domain, const void *label, void *auth, _Bool wait, void **err) { if (err) *err = 0; return 0; }
const void *SMJobCopyDictionary(const void *domain, const void *label) { return 0; }
int SecStaticCodeCreateWithPath(const void *url, uint32_t f, void **code) { if (code) *code = 0; return errSecUnimplemented; }
int SecStaticCodeCheckValidityWithErrors(void *code, uint32_t f, void *req, void **err) { if (err) *err = 0; return errSecUnimplemented; }
int SecCodeCopySigningInformation(void *code, uint32_t f, const void **info) { if (info) *info = 0; return errSecUnimplemented; }
int SecCodeCopyDesignatedRequirement(void *code, uint32_t f, void **req) { if (req) *req = 0; return errSecUnimplemented; }
int SecRequirementCopyString(void *req, uint32_t f, const void **s) { if (s) *s = 0; return errSecUnimplemented; }
int SecItemImport(const void *data, const void *ext, void *fmt, void *type, uint32_t f, const void *params, void *kc, const void **out) { if (out) *out = 0; return errSecUnimplemented; }
void *SecDigestTransformCreate(const void *type, long len, void **err) { if (err) *err = 0; return 0; }
void *SecVerifyTransformCreate(void *key, const void *sig, void **err) { if (err) *err = 0; return 0; }
void *SecTransformCreateReadTransformWithReadStream(void *stream) { return 0; }
void *SecTransformCreateGroupTransform(void) { return 0; }
void *SecTransformConnectTransforms(void *a, const void *an, void *b, const void *bn, void *g, void **err) { if (err) *err = 0; return 0; }
const void *SecTransformExecute(void *t, void **err) { if (err) *err = 0; return 0; }
int FSPathMakeRefWithOptions(const unsigned char *path, uint32_t o, void *ref, _Bool *isdir) { return fnfErr; }
int FSGetCatalogInfo(const void *ref, uint32_t which, void *info, void *name, void *spec, void *parent) { return fnfErr; }
int FSCopyObjectSync(const void *src, const void *dst, const void *name, void *target, uint32_t o) { return fnfErr; }
void FSEventStreamSetDispatchQueue(void *s, void *q) {}

/* ---------------- @available checks (compiler-rt's __isPlatformVersionAtLeast): scion is macOS 14.6 ---------------- */
_Bool _availability_version_check(uint32_t count, const void *versions) {
    const struct { uint32_t platform, version; } *v = versions;   /* version = major << 16 | minor << 8 | patch */
    for (uint32_t i = 0; i < count; i++)
        if (v[i].platform == 1 /* macOS */) return v[i].version <= 0x000E0600;
    return 1;   /* other platforms (iOS apps): answer as the newest */
}

/* ---------------- os_log: the unified log is not kept (ponytail: decode the format buffer if logs are needed) ---------------- */
/* log objects are Objective-C objects (Swift's OSLog is the class OS_os_log): libobjc sets their isa when it loads */
struct mw_os_log { void *isa; void *pad[3]; };
struct mw_os_log _os_log_default, _os_log_disabled, g_os_log_dummy;
void _scion_os_log_set_class(void *c) { _os_log_default.isa = _os_log_disabled.isa = g_os_log_dummy.isa = c; }
void *os_log_create(const char *subsystem, const char *category) { return &g_os_log_dummy; }
_Bool os_log_type_enabled(void *log, uint8_t type) { return 0; }
void _os_log_impl(void *dso, void *log, uint8_t type, const char *fmt, uint8_t *buf, uint32_t size) {}
void _os_log_error_impl(void *dso, void *log, uint8_t type, const char *fmt, uint8_t *buf, uint32_t size) {}
void _os_log_debug_impl(void *dso, void *log, uint8_t type, const char *fmt, uint8_t *buf, uint32_t size) {}
void _os_log_fault_impl(void *dso, void *log, uint8_t type, const char *fmt, uint8_t *buf, uint32_t size) {}
char *xar_get_safe_path(void *f) { return 0; }

/* ---------------- Carbon events and global hot keys: accepted, never fired
   ponytail: map RegisterEventHotKey to the host's RegisterHotKey when an app's shortcut matters ---------------- */
static char g_event_target[16];
void *GetEventDispatcherTarget(void) { return g_event_target; }
void *GetApplicationEventTarget(void) { return g_event_target; }
int InstallEventHandler(void *target, void *handler, unsigned long n, const void *types, void *user, void **out) { if (out) *out = g_event_target; return 0; }
int RemoveEventHandler(void *h) { return 0; }
int AddEventTypesToHandler(void *h, unsigned long n, const void *types) { return 0; }
int RemoveEventTypesFromHandler(void *h, unsigned long n, const void *types) { return 0; }

/* ServiceManagement: no launchd jobs, login items cannot be set */
const void *SMCopyAllJobDictionaries(const void *domain) { return 0; }
unsigned char SMJobSubmit(const void *domain, const void *job, const void *auth, void **error) { if (error) *error = 0; return 0; }
unsigned char SMLoginItemSetEnabled(const void *identifier, unsigned char enabled) { return 0; }
int RegisterEventHotKey(uint32_t key, uint32_t mods, uint64_t id, void *target, uint32_t opts, void **out) { static char ref[16]; if (out) *out = ref; return 0; }
int UnregisterEventHotKey(void *ref) { return 0; }
uint32_t GetEventClass(void *e) { return 0; }
uint32_t GetEventKind(void *e) { return 0; }
int GetEventParameter(void *e, uint32_t name, uint32_t type, uint32_t *outType, unsigned long size, unsigned long *outSize, void *out) { return -9870; /* eventParameterNotFoundErr */ }
int CopySymbolicHotKeys(const void **out) { if (out) *out = 0; return -50; }
/* keyboard layouts (Text Input Sources): none, so key names come from the app's own fallback */
void *TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void) { return 0; }
void *TISCopyCurrentKeyboardLayoutInputSource(void) { return 0; }
void *TISCopyCurrentKeyboardInputSource(void) { return 0; }
void *TISGetInputSourceProperty(void *src, const void *key) { return 0; }
const void *kTISPropertyUnicodeKeyLayoutData = "TISPropertyUnicodeKeyLayoutData";
const void *kTISPropertyInputSourceID = "TISPropertyInputSourceID";
const void *kTISPropertyLocalizedName = "TISPropertyLocalizedName";
int UCKeyTranslate(const void *layout, uint16_t code, uint16_t action, uint32_t mods, uint32_t kbd, uint32_t opts, uint32_t *dead, unsigned long max, unsigned long *len, uint16_t *out) { if (len) *len = 0; return -50; }
uint8_t LMGetKbdType(void) { return 0; }

/* ---------------- Launch Services: no login items, no default handlers ---------------- */
const void *kLSSharedFileListSessionLoginItems = "com.apple.LSSharedFileList.SessionLoginItems";
const void *kLSSharedFileListGlobalLoginItems = "com.apple.LSSharedFileList.GlobalLoginItems";
const void *kLSSharedFileListItemLast = "kLSSharedFileListItemLast";
const void *kLSSharedFileListItemBeforeFirst = "kLSSharedFileListItemBeforeFirst";
void *LSSharedFileListCreate(const void *alloc, const void *type, const void *opts) { return 0; }
const void *LSSharedFileListCopySnapshot(void *list, uint32_t *seed) { if (seed) *seed = 0; return 0; }
void *LSSharedFileListInsertItemURL(void *list, void *after, const void *name, void *icon, const void *url, const void *props, const void *clear) { return 0; }
const void *LSSharedFileListItemCopyResolvedURL(void *item, uint32_t flags, void **err) { if (err) *err = 0; return 0; }
int LSSharedFileListItemRemove(void *list, void *item) { return -50; }
const void *LSCopyDefaultRoleHandlerForContentType(const void *type, uint32_t role) { return 0; }
const void *LSCopyDefaultHandlerForURLScheme(const void *scheme) { return 0; }
