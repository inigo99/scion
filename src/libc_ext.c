/* libc_ext.c — parts of scion's libSystem compiled against the Darwin SDK headers (sdk/darwin), where the exact
 * Apple struct layouts matter: _DefaultRuneLocale, xlocale (_l) functions, wide characters, statvfs, pthread_once.
 * Locales: "C" (bytes) and UTF-8. ponytail: uselocale() is process-wide, not per thread. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <locale.h>
#include <xlocale.h>
#include <runetype.h>
#include <nl_types.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <dirent.h>

/* ---------------- ctype table read directly by Apple's inline isalpha()/isdigit()… ---------------- */
static uint32_t ctype_of(int c) {
    uint32_t m = 0;
    if (c < 0x20 || c == 0x7f) m |= _CTYPE_C;
    if (c == ' ' || (c >= '\t' && c <= '\r')) m |= _CTYPE_S;
    if (c == ' ' || c == '\t') m |= _CTYPE_B;
    if (c >= 'A' && c <= 'Z') m |= _CTYPE_U | _CTYPE_A;
    if (c >= 'a' && c <= 'z') m |= _CTYPE_L | _CTYPE_A;
    if (c >= '0' && c <= '9') m |= _CTYPE_D | _CTYPE_X | (uint32_t)(c - '0');
    if ((c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) m |= _CTYPE_X | (uint32_t)((c | 32) - 'a' + 10);
    if (c > 0x20 && c < 0x7f) { m |= _CTYPE_G | _CTYPE_R; if (!(m & (_CTYPE_A | _CTYPE_D))) m |= _CTYPE_P; }
    if (c == ' ') m |= _CTYPE_R;
    if (c >= 0x20 && c < 0x7f) m |= _CTYPE_SW1;
    return m;
}
_RuneLocale _DefaultRuneLocale = {"RuneMagi", "NONE"};
_RuneLocale *_CurrentRuneLocale = &_DefaultRuneLocale;
__attribute__((constructor)) static void init_runes(void) {
    for (int c = 0; c < 256; c++) {
        _DefaultRuneLocale.__runetype[c] = c < 128 ? ctype_of(c) : 0;
        _DefaultRuneLocale.__maplower[c] = c >= 'A' && c <= 'Z' ? c + 32 : c;
        _DefaultRuneLocale.__mapupper[c] = c >= 'a' && c <= 'z' ? c - 32 : c;
    }
    _DefaultRuneLocale.__invalid_rune = 0xFFFD;
}

/* ---------------- locales ---------------- */
struct _xlocale { int utf8; char name[16]; struct lconv lc; };
static struct _xlocale c_loc = {0, "C", {".", "", "", "", "", "", "", "", "", "", 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127}};
static struct _xlocale u_loc = {1, "UTF-8", {".", "", "", "", "", "", "", "", "", "", 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127}};
static struct _xlocale *g_loc = &c_loc;
static struct _xlocale *L(locale_t l) { return l == LC_GLOBAL_LOCALE ? g_loc : l ? (struct _xlocale *)l : &c_loc; }
static struct _xlocale *by_name(const char *n) {
    if (!n) return 0;
    if (!*n) { n = getenv("LC_ALL"); if (!n || !*n) n = getenv("LC_CTYPE"); if (!n || !*n) n = getenv("LANG"); if (!n) n = "C"; }
    if (!strcmp(n, "C") || !strcmp(n, "POSIX")) return &c_loc;
    return strstr(n, "UTF-8") || strstr(n, "utf8") || strstr(n, "UTF8") ? &u_loc : &c_loc;
}
char *setlocale(int cat, const char *n) {
    if (!n) return g_loc->name;
    struct _xlocale *l = by_name(n);
    if (cat == LC_ALL || cat == LC_CTYPE) g_loc = l;
    return l->name;
}
locale_t newlocale(int mask, const char *n, locale_t base) { struct _xlocale *l = by_name(n); return l ? (locale_t)l : 0; }
locale_t duplocale(locale_t l) { return (locale_t)L(l); }
int freelocale(locale_t l) { return 0; }
locale_t uselocale(locale_t l) { struct _xlocale *old = g_loc; if (l) g_loc = L(l); return (locale_t)old; }
const char *querylocale(int mask, locale_t l) { return L(l)->name; }
struct lconv *localeconv(void) { return &g_loc->lc; }
struct lconv *localeconv_l(locale_t l) { return &L(l)->lc; }
int ___mb_cur_max(void) { return g_loc->utf8 ? 4 : 1; }
int ___mb_cur_max_l(locale_t l) { return L(l)->utf8 ? 4 : 1; }
extern int __maskrune(int, unsigned long);
int __maskrune_l(int c, unsigned long f, locale_t l) { return __maskrune(c, f); }
int ___tolower_l(int c, locale_t l) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }
int ___toupper_l(int c, locale_t l) { return c >= 'a' && c <= 'z' ? c - 32 : c; }
int ___istype_l(int c, unsigned long f, locale_t l) { return __maskrune(c, f) != 0; }

/* ---------------- multibyte <-> wide ---------------- */
static size_t dec(wchar_t *wc, const char *s, size_t n, int utf8) {
    if (!s) return 0;
    if (!n) return (size_t)-2;
    unsigned char c = (unsigned char)*s;
    if (!utf8 || c < 0x80) { if (wc) *wc = c; return c ? 1 : 0; }
    int len = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 0;
    if (!len) { errno = EILSEQ; return (size_t)-1; }
    if (n < (size_t)len) return (size_t)-2;
    uint32_t v = c & (0x7F >> len);
    for (int i = 1; i < len; i++) { unsigned char k = (unsigned char)s[i]; if ((k & 0xC0) != 0x80) { errno = EILSEQ; return (size_t)-1; } v = v << 6 | (k & 63); }
    if (wc) *wc = (wchar_t)v;
    return v ? (size_t)len : 0;
}
static size_t enc(char *s, wchar_t w, int utf8) {
    uint32_t v = (uint32_t)w;
    if (!utf8) { if (v > 255) { errno = EILSEQ; return (size_t)-1; } *s = (char)v; return 1; }
    if (v < 0x80) { *s = (char)v; return 1; }
    if (v < 0x800) { s[0] = (char)(0xC0 | v >> 6); s[1] = (char)(0x80 | (v & 63)); return 2; }
    if (v < 0x10000) { s[0] = (char)(0xE0 | v >> 12); s[1] = (char)(0x80 | (v >> 6 & 63)); s[2] = (char)(0x80 | (v & 63)); return 3; }
    s[0] = (char)(0xF0 | v >> 18); s[1] = (char)(0x80 | (v >> 12 & 63)); s[2] = (char)(0x80 | (v >> 6 & 63)); s[3] = (char)(0x80 | (v & 63)); return 4;
}
size_t mbrtowc_l(wchar_t *wc, const char *s, size_t n, mbstate_t *ps, locale_t l) { return dec(wc, s, n, L(l)->utf8); }
size_t mbrtowc(wchar_t *wc, const char *s, size_t n, mbstate_t *ps) { return dec(wc, s, n, g_loc->utf8); }
int mbtowc_l(wchar_t *wc, const char *s, size_t n, locale_t l) { size_t r = dec(wc, s, n, L(l)->utf8); return r >= (size_t)-2 ? -1 : (int)r; }
int mbtowc(wchar_t *wc, const char *s, size_t n) { return mbtowc_l(wc, s, n, LC_GLOBAL_LOCALE); }
size_t mbrlen_l(const char *s, size_t n, mbstate_t *ps, locale_t l) { return dec(0, s, n, L(l)->utf8); }
size_t mbrlen(const char *s, size_t n, mbstate_t *ps) { return dec(0, s, n, g_loc->utf8); }
int mblen(const char *s, size_t n) { size_t r = dec(0, s, n, g_loc->utf8); return r >= (size_t)-2 ? -1 : (int)r; }
size_t wcrtomb_l(char *s, wchar_t w, mbstate_t *ps, locale_t l) { char b[8]; return enc(s ? s : b, s ? w : 0, L(l)->utf8); }
size_t wcrtomb(char *s, wchar_t w, mbstate_t *ps) { return wcrtomb_l(s, w, ps, LC_GLOBAL_LOCALE); }
int wctomb(char *s, wchar_t w) { if (!s) return 0; size_t r = enc(s, w, g_loc->utf8); return r == (size_t)-1 ? -1 : (int)r; }
wint_t btowc_l(int c, locale_t l) { return c == EOF || (L(l)->utf8 && c >= 0x80) ? WEOF : (wint_t)(unsigned char)c; }
wint_t btowc(int c) { return btowc_l(c, LC_GLOBAL_LOCALE); }
int wctob_l(wint_t c, locale_t l) { return c < (L(l)->utf8 ? 0x80u : 0x100u) ? (int)c : EOF; }
int wctob(wint_t c) { return wctob_l(c, LC_GLOBAL_LOCALE); }
int mbsinit(const mbstate_t *ps) { return 1; }
size_t mbsnrtowcs_l(wchar_t *dst, const char **src, size_t nms, size_t len, mbstate_t *ps, locale_t loc) {
    int u = L(loc)->utf8; const char *s = *src; size_t k = 0;
    while (nms && (!dst || k < len)) {
        wchar_t w; size_t r = dec(&w, s, nms, u);
        if (r == (size_t)-1) { *src = s; return r; }
        if (r == (size_t)-2) break;
        if (dst) dst[k] = w;
        if (r == 0) { if (dst) *src = 0; return k; }
        s += r; nms -= r; k++;
    }
    if (dst) *src = s;
    return k;
}
size_t mbsnrtowcs(wchar_t *d, const char **s, size_t n, size_t len, mbstate_t *ps) { return mbsnrtowcs_l(d, s, n, len, ps, LC_GLOBAL_LOCALE); }
size_t mbsrtowcs_l(wchar_t *d, const char **s, size_t len, mbstate_t *ps, locale_t l) { return mbsnrtowcs_l(d, s, (size_t)-1, len, ps, l); }
size_t mbsrtowcs(wchar_t *d, const char **s, size_t len, mbstate_t *ps) { return mbsrtowcs_l(d, s, len, ps, LC_GLOBAL_LOCALE); }
size_t mbstowcs(wchar_t *d, const char *s, size_t n) { return mbsrtowcs(d, &s, n, 0); }
size_t wcsnrtombs_l(char *dst, const wchar_t **src, size_t nwc, size_t len, mbstate_t *ps, locale_t loc) {
    int u = L(loc)->utf8; const wchar_t *s = *src; size_t k = 0; char b[8];
    for (; nwc; nwc--, s++) {
        size_t r = enc(b, *s, u);
        if (r == (size_t)-1) { if (dst) *src = s; return r; }
        if (dst && k + r > len) break;
        if (dst) memcpy(dst + k, b, r);
        if (!*s) { if (dst) *src = 0; return k; }
        k += r;
    }
    if (dst) *src = s;
    return k;
}
size_t wcsnrtombs(char *d, const wchar_t **s, size_t n, size_t len, mbstate_t *ps) { return wcsnrtombs_l(d, s, n, len, ps, LC_GLOBAL_LOCALE); }
size_t wcsrtombs_l(char *d, const wchar_t **s, size_t len, mbstate_t *ps, locale_t l) { return wcsnrtombs_l(d, s, (size_t)-1, len, ps, l); }
size_t wcsrtombs(char *d, const wchar_t **s, size_t len, mbstate_t *ps) { return wcsrtombs_l(d, s, len, ps, LC_GLOBAL_LOCALE); }
size_t wcstombs(char *d, const wchar_t *s, size_t n) { return wcsrtombs(d, &s, n, 0); }

/* ---------------- wide strings ---------------- */
size_t wcslen(const wchar_t *s) { const wchar_t *p = s; while (*p) p++; return (size_t)(p - s); }
wchar_t *wmemchr(const wchar_t *s, wchar_t c, size_t n) { for (; n; n--, s++) if (*s == c) return (wchar_t *)s; return 0; }
int wmemcmp(const wchar_t *a, const wchar_t *b, size_t n) { for (; n; n--, a++, b++) if (*a != *b) return *a < *b ? -1 : 1; return 0; }
wchar_t *wmemcpy(wchar_t *d, const wchar_t *s, size_t n) { return memcpy(d, s, n * sizeof(wchar_t)); }
wchar_t *wmemmove(wchar_t *d, const wchar_t *s, size_t n) { return memmove(d, s, n * sizeof(wchar_t)); }
wchar_t *wmemset(wchar_t *d, wchar_t c, size_t n) { for (size_t i = 0; i < n; i++) d[i] = c; return d; }
int wcscmp(const wchar_t *a, const wchar_t *b) { while (*a && *a == *b) a++, b++; return *a < *b ? -1 : *a > *b; }
int wcscoll_l(const wchar_t *a, const wchar_t *b, locale_t l) { return wcscmp(a, b); }
int wcscoll(const wchar_t *a, const wchar_t *b) { return wcscmp(a, b); }
size_t wcsxfrm_l(wchar_t *d, const wchar_t *s, size_t n, locale_t l) { size_t k = wcslen(s); if (n) { size_t c = k < n ? k : n - 1; wmemcpy(d, s, c); d[c] = 0; } return k; }
size_t wcsxfrm(wchar_t *d, const wchar_t *s, size_t n) { return wcsxfrm_l(d, s, n, 0); }
int strcoll_l(const char *a, const char *b, locale_t l) { return strcmp(a, b); }
size_t strxfrm_l(char *d, const char *s, size_t n, locale_t l) { size_t k = strlen(s); if (n) { size_t c = k < n ? k : n - 1; memcpy(d, s, c); d[c] = 0; } return k; }
/* wide -> narrow copy for the numeric parsers (digits, signs, exponents are ASCII) */
static char *narrow(const wchar_t *s, char *buf, size_t cap) { size_t i = 0; while (i + 1 < cap && s[i] && s[i] < 128) { buf[i] = (char)s[i]; i++; } buf[i] = 0; return buf; }
#define WSTR(T, name, call) T name { char b[512], *e; narrow(s, b, sizeof b); T r = call; if (end) *end = (wchar_t *)s + (e - b); return r; }
typedef long double ldouble; typedef long long llong; typedef unsigned long ulong; typedef unsigned long long ullong;
WSTR(double, wcstod(const wchar_t *s, wchar_t **end), strtod(b, &e))
WSTR(float, wcstof(const wchar_t *s, wchar_t **end), strtof(b, &e))
WSTR(ldouble, wcstold(const wchar_t *s, wchar_t **end), strtold(b, &e))
WSTR(long, wcstol(const wchar_t *s, wchar_t **end, int base), strtol(b, &e, base))
WSTR(llong, wcstoll(const wchar_t *s, wchar_t **end, int base), strtoll(b, &e, base))
WSTR(ulong, wcstoul(const wchar_t *s, wchar_t **end, int base), strtoul(b, &e, base))
WSTR(ullong, wcstoull(const wchar_t *s, wchar_t **end, int base), strtoull(b, &e, base))
double strtod_l(const char *s, char **e, locale_t l) { return strtod(s, e); }
float strtof_l(const char *s, char **e, locale_t l) { return strtof(s, e); }
long double strtold_l(const char *s, char **e, locale_t l) { return strtold(s, e); }
long long strtoll_l(const char *s, char **e, int b, locale_t l) { return strtoll(s, e, b); }
unsigned long long strtoull_l(const char *s, char **e, int b, locale_t l) { return strtoull(s, e, b); }
int snprintf_l(char *b, size_t n, locale_t l, const char *f, ...) { va_list ap; va_start(ap, f); int r = vsnprintf(b, n, f, ap); va_end(ap); return r; }
int asprintf_l(char **b, locale_t l, const char *f, ...) { va_list ap; va_start(ap, f); int r = vasprintf(b, f, ap); va_end(ap); return r; }
int sscanf_l(const char *s, locale_t l, const char *f, ...) { va_list ap; va_start(ap, f); int r = vsscanf(s, f, ap); va_end(ap); return r; }
int vswprintf(wchar_t *ws, size_t n, const wchar_t *wf, va_list ap) {
    char f[1024], out[4096]; size_t k = 0;
    for (const wchar_t *p = wf; *p && k + 4 < sizeof f; p++) k += enc(f + k, *p, 1);
    f[k] = 0;
    int r = vsnprintf(out, sizeof out, f, ap);
    if (r < 0) return -1;
    const char *s = out; size_t m = mbsnrtowcs_l(ws, &s, (size_t)r, n, 0, (locale_t)&u_loc);
    if (m >= n) { if (n) ws[n - 1] = 0; return -1; }
    ws[m] = 0; return (int)m;
}
int swprintf(wchar_t *ws, size_t n, const wchar_t *f, ...) { va_list ap; va_start(ap, f); int r = vswprintf(ws, n, f, ap); va_end(ap); return r; }
wint_t fputwc(wchar_t w, FILE *fp) { char b[8]; size_t r = enc(b, w, g_loc->utf8); if (r == (size_t)-1 || fwrite(b, 1, r, fp) != r) return WEOF; return (wint_t)w; }
wint_t putwc(wchar_t w, FILE *fp) { return fputwc(w, fp); }
wint_t fgetwc(FILE *fp) {
    char b[4]; int c = fgetc(fp); if (c == EOF) return WEOF;
    b[0] = (char)c; size_t n = 1; wchar_t w;
    for (;;) {
        size_t r = dec(&w, b, n, g_loc->utf8);
        if (r != (size_t)-2) return r == (size_t)-1 ? WEOF : (wint_t)w;
        if (n == 4 || (c = fgetc(fp)) == EOF) return WEOF;
        b[n++] = (char)c;
    }
}
wint_t getwc(FILE *fp) { return fgetwc(fp); }
wint_t ungetwc(wint_t w, FILE *fp) { return w < 0x80 && ungetc((int)w, fp) != EOF ? w : WEOF; }

/* ---------------- message catalogs: none (callers fall back to their default strings) ---------------- */
nl_catd catopen(const char *n, int f) { return (nl_catd)-1; }
char *catgets(nl_catd c, int set, int msg, const char *def) { return (char *)def; }
int catclose(nl_catd c) { return 0; }

/* ---------------- pthread_once ---------------- */
int pthread_once(pthread_once_t *o, void (*fn)(void)) {
    volatile int *st = (volatile int *)o->__opaque;
    int z = 0;
    if (__atomic_load_n(st, __ATOMIC_ACQUIRE) == 2) return 0;
    if (__atomic_compare_exchange_n(st, &z, 1, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) { fn(); __atomic_store_n(st, 2, __ATOMIC_RELEASE); return 0; }
    while (__atomic_load_n(st, __ATOMIC_ACQUIRE) != 2) sched_yield();
    return 0;
}

/* ---------------- file system odds and ends ---------------- */
extern int scion_link(int symbolic, const char *from, const char *to); /* libsystem.c */
int link(const char *a, const char *b) { return scion_link(0, a, b); }
int symlink(const char *a, const char *b) { return scion_link(1, a, b); }
int truncate(const char *p, off_t n) { int fd = open(p, O_WRONLY); if (fd < 0) return -1; int r = ftruncate(fd, n); close(fd); return r; }
int fchmodat(int fd, const char *p, mode_t m, int flag) { return 0; } /* ponytail: Windows ACLs are not mapped to modes */
int utimensat(int fd, const char *p, const struct timespec t[2], int flag) { return 0; } /* ponytail: timestamps are not set */
int futimens(int fd, const struct timespec t[2]) { return 0; }
int utimes(const char *p, const struct timeval t[2]) { return 0; }
int statvfs(const char *p, struct statvfs *s) {
    memset(s, 0, sizeof *s);
    s->f_bsize = s->f_frsize = 4096; s->f_blocks = 1ull << 28; s->f_bfree = s->f_bavail = 1ull << 27; /* ponytail: fixed 1 TiB / 512 GiB free */
    s->f_files = s->f_ffree = s->f_favail = 1u << 30; s->f_namemax = 255;
    return 0;
}
int fstatvfs(int fd, struct statvfs *s) { return statvfs("/", s); }
/* readdir lives in libsystem.c (one entry buffer per DIR, as on macOS) */

/* ---------------- strftime (C locale) ---------------- */
#include <time.h>
static const char *wday[] = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
static const char *mon[] = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"};
size_t strftime(char *restrict s, size_t n, const char *restrict f, const struct tm *restrict t) {
    size_t k = 0; char b[64];
    for (; *f; f++) {
        const char *add = b; b[0] = 0;
        if (*f != '%') { b[0] = *f; b[1] = 0; }
        else switch (*++f) {
        case 'a': snprintf(b, sizeof b, "%.3s", wday[t->tm_wday % 7]); break;
        case 'A': add = wday[t->tm_wday % 7]; break;
        case 'b': case 'h': snprintf(b, sizeof b, "%.3s", mon[t->tm_mon % 12]); break;
        case 'B': add = mon[t->tm_mon % 12]; break;
        case 'c': snprintf(b, sizeof b, "%.3s %.3s %2d %02d:%02d:%02d %d", wday[t->tm_wday % 7], mon[t->tm_mon % 12], t->tm_mday, t->tm_hour, t->tm_min, t->tm_sec, t->tm_year + 1900); break;
        case 'C': snprintf(b, sizeof b, "%02d", (t->tm_year + 1900) / 100); break;
        case 'd': snprintf(b, sizeof b, "%02d", t->tm_mday); break;
        case 'D': snprintf(b, sizeof b, "%02d/%02d/%02d", t->tm_mon + 1, t->tm_mday, t->tm_year % 100); break;
        case 'e': snprintf(b, sizeof b, "%2d", t->tm_mday); break;
        case 'F': snprintf(b, sizeof b, "%d-%02d-%02d", t->tm_year + 1900, t->tm_mon + 1, t->tm_mday); break;
        case 'H': snprintf(b, sizeof b, "%02d", t->tm_hour); break;
        case 'I': snprintf(b, sizeof b, "%02d", t->tm_hour % 12 ? t->tm_hour % 12 : 12); break;
        case 'j': snprintf(b, sizeof b, "%03d", t->tm_yday + 1); break;
        case 'k': snprintf(b, sizeof b, "%2d", t->tm_hour); break;
        case 'l': snprintf(b, sizeof b, "%2d", t->tm_hour % 12 ? t->tm_hour % 12 : 12); break;
        case 'm': snprintf(b, sizeof b, "%02d", t->tm_mon + 1); break;
        case 'M': snprintf(b, sizeof b, "%02d", t->tm_min); break;
        case 'n': add = "\n"; break;
        case 'p': add = t->tm_hour < 12 ? "AM" : "PM"; break;
        case 'r': snprintf(b, sizeof b, "%02d:%02d:%02d %s", t->tm_hour % 12 ? t->tm_hour % 12 : 12, t->tm_min, t->tm_sec, t->tm_hour < 12 ? "AM" : "PM"); break;
        case 'R': snprintf(b, sizeof b, "%02d:%02d", t->tm_hour, t->tm_min); break;
        case 's': snprintf(b, sizeof b, "%lld", (long long)timegm((struct tm *)t)); break;
        case 'S': snprintf(b, sizeof b, "%02d", t->tm_sec); break;
        case 't': add = "\t"; break;
        case 'T': case 'X': snprintf(b, sizeof b, "%02d:%02d:%02d", t->tm_hour, t->tm_min, t->tm_sec); break;
        case 'u': snprintf(b, sizeof b, "%d", t->tm_wday ? t->tm_wday : 7); break;
        case 'w': snprintf(b, sizeof b, "%d", t->tm_wday); break;
        case 'x': snprintf(b, sizeof b, "%02d/%02d/%02d", t->tm_mon + 1, t->tm_mday, t->tm_year % 100); break;
        case 'y': snprintf(b, sizeof b, "%02d", t->tm_year % 100); break;
        case 'Y': snprintf(b, sizeof b, "%d", t->tm_year + 1900); break;
        case 'z': snprintf(b, sizeof b, "%c%02ld%02ld", t->tm_gmtoff < 0 ? '-' : '+', labs(t->tm_gmtoff) / 3600, labs(t->tm_gmtoff) / 60 % 60); break;
        case 'Z': add = t->tm_zone ? t->tm_zone : "UTC"; break;
        case '%': add = "%"; break;
        case 0: f--; break;
        default: snprintf(b, sizeof b, "%%%c", *f);
        }
        size_t m = strlen(add);
        if (k + m >= n) return 0;
        memcpy(s + k, add, m); k += m;
    }
    s[k] = 0; return k;
}
size_t strftime_l(char *restrict s, size_t n, const char *restrict f, const struct tm *restrict t, locale_t l) { return strftime(s, n, f, t); }

/* ---------------- mach-o/arch.h ---------------- */
#include <mach-o/arch.h>
#include <mach-o/fat.h>
static const NXArchInfo arch_table[] = {
    {"x86_64", CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_ALL, NX_LittleEndian, "Intel x86-64"},
    {"x86_64h", CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_H, NX_LittleEndian, "Intel x86-64h Haswell"},
    {"arm64", CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, NX_LittleEndian, "ARM64"},
    {"arm64e", CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64E, NX_LittleEndian, "arm64e"},
    {"arm64_32", CPU_TYPE_ARM64_32, CPU_SUBTYPE_ARM64_32_V8, NX_LittleEndian, "arm64_32"},
    {"i386", CPU_TYPE_I386, CPU_SUBTYPE_I386_ALL, NX_LittleEndian, "Intel 80x86"},
    {"armv7", CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, NX_LittleEndian, "arm v7"},
    {"armv7s", CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7S, NX_LittleEndian, "arm v7s"},
    {"armv7k", CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7K, NX_LittleEndian, "arm v7k"},
    {"armv6", CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V6, NX_LittleEndian, "arm v6"},
    {"arm", CPU_TYPE_ARM, CPU_SUBTYPE_ARM_ALL, NX_LittleEndian, "ARM"},
    {"ppc", CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_ALL, NX_BigEndian, "PowerPC"},
    {"ppc64", CPU_TYPE_POWERPC64, CPU_SUBTYPE_POWERPC_ALL, NX_BigEndian, "PowerPC 64-bit"},
    {0, 0, 0, NX_UnknownByteOrder, 0},
};
const NXArchInfo *NXGetAllArchInfos(void) { return arch_table; }
const NXArchInfo *NXGetLocalArchInfo(void) { return &arch_table[
#if defined(__arm64__)
    2
#else
    0
#endif
]; }
const NXArchInfo *NXGetArchInfoFromName(const char *n) {
    for (const NXArchInfo *a = arch_table; a->name; a++) if (!strcmp(a->name, n)) return a;
    return 0;
}
const NXArchInfo *NXGetArchInfoFromCpuType(cpu_type_t t, cpu_subtype_t s) {
    const NXArchInfo *any = 0;
    for (const NXArchInfo *a = arch_table; a->name; a++) {
        if (a->cputype != t) continue;
        if ((a->cpusubtype & ~CPU_SUBTYPE_MASK) == (s & ~CPU_SUBTYPE_MASK)) return a;
        if (!any) any = a;
    }
    return s == CPU_SUBTYPE_MULTIPLE ? any : any; /* unknown subtype: report the family */
}
struct fat_arch *NXFindBestFatArch(cpu_type_t t, cpu_subtype_t s, struct fat_arch *f, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) if (f[i].cputype == t && (f[i].cpusubtype & ~CPU_SUBTYPE_MASK) == (s & ~CPU_SUBTYPE_MASK)) return &f[i];
    for (uint32_t i = 0; i < n; i++) if (f[i].cputype == t) return &f[i];
    return 0;
}

/* ---------------- CommonCrypto: SHA-1 (FIPS 180-4) ---------------- */
#include <CommonCrypto/CommonDigest.h>
static uint32_t rol(uint32_t x, int n) { return x << n | x >> (32 - n); }
static void sha1_block(CC_SHA1_CTX *c, const unsigned char *p) {
    uint32_t w[80], a = c->h0, b = c->h1, d = c->h3, e = c->h4, cc = c->h2;
    for (int i = 0; i < 16; i++) w[i] = (uint32_t)p[4 * i] << 24 | (uint32_t)p[4 * i + 1] << 16 | (uint32_t)p[4 * i + 2] << 8 | p[4 * i + 3];
    for (int i = 16; i < 80; i++) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20) f = (b & cc) | (~b & d), k = 0x5A827999;
        else if (i < 40) f = b ^ cc ^ d, k = 0x6ED9EBA1;
        else if (i < 60) f = (b & cc) | (b & d) | (cc & d), k = 0x8F1BBCDC;
        else f = b ^ cc ^ d, k = 0xCA62C1D6;
        uint32_t t = rol(a, 5) + f + e + k + w[i];
        e = d; d = cc; cc = rol(b, 30); b = a; a = t;
    }
    c->h0 += a; c->h1 += b; c->h2 += cc; c->h3 += d; c->h4 += e;
}
int CC_SHA1_Init(CC_SHA1_CTX *c) {
    memset(c, 0, sizeof *c);
    c->h0 = 0x67452301; c->h1 = 0xEFCDAB89; c->h2 = 0x98BADCFE; c->h3 = 0x10325476; c->h4 = 0xC3D2E1F0;
    return 1;
}
int CC_SHA1_Update(CC_SHA1_CTX *c, const void *data, CC_LONG len) {
    const unsigned char *p = data; unsigned char *buf = (unsigned char *)c->data;
    uint64_t total = ((uint64_t)c->Nh << 32 | c->Nl);
    size_t have = (size_t)(total / 8 % 64);
    total += (uint64_t)len * 8; c->Nl = (CC_LONG)total; c->Nh = (CC_LONG)(total >> 32);
    while (len) {
        size_t k = 64 - have < len ? 64 - have : len;
        memcpy(buf + have, p, k); have += k; p += k; len -= (CC_LONG)k;
        if (have == 64) { sha1_block(c, buf); have = 0; }
    }
    return 1;
}
int CC_SHA1_Final(unsigned char *md, CC_SHA1_CTX *c) {
    uint64_t bits = (uint64_t)c->Nh << 32 | c->Nl;
    unsigned char pad[72] = {0x80}; size_t have = (size_t)(bits / 8 % 64), n = have < 56 ? 56 - have : 120 - have;
    for (int i = 0; i < 8; i++) pad[n + i] = (unsigned char)(bits >> (56 - 8 * i));
    CC_LONG nl = c->Nl, nh = c->Nh;
    CC_SHA1_Update(c, pad, (CC_LONG)(n + 8));
    (void)nl; (void)nh;
    uint32_t h[5] = {c->h0, c->h1, c->h2, c->h3, c->h4};
    for (int i = 0; i < 20; i++) md[i] = (unsigned char)(h[i / 4] >> (24 - 8 * (i % 4)));
    return 1;
}
unsigned char *CC_SHA1(const void *data, CC_LONG len, unsigned char *md) {
    CC_SHA1_CTX c; CC_SHA1_Init(&c); CC_SHA1_Update(&c, data, len); CC_SHA1_Final(md, &c); return md;
}

/* ---------------- getopt / getopt_long (BSD semantics: stops at the first non-option, like macOS) ---------------- */
#include <getopt.h>
char *optarg; int optind = 1, opterr = 1, optopt, optreset;
static int optpos; /* position inside a bundle of short options (-abc) */
static int getopt_impl(int argc, char *const argv[], const char *opts, const struct option *lo, int *idx, int only_long) {
    if (optreset) { optreset = 0; optind = 1; optpos = 0; }
    if (optind == 0) optind = 1, optpos = 0;
    optarg = 0;
    const char *o = opts; int colon;
    if (*o == '+' || *o == '-') o++;
    colon = *o == ':';
    if (!optpos) {
        if (optind >= argc || !argv[optind] || argv[optind][0] != '-' || !argv[optind][1]) return -1;
        if (!strcmp(argv[optind], "--")) { optind++; return -1; }
        if (lo && (argv[optind][1] == '-' || only_long)) {
            const char *name = argv[optind] + (argv[optind][1] == '-' ? 2 : 1), *eq = strchr(name, '=');
            size_t len = eq ? (size_t)(eq - name) : strlen(name);
            int found = -1, matches = 0;
            for (int i = 0; lo[i].name; i++) {
                if (strncmp(lo[i].name, name, len)) continue;
                if (strlen(lo[i].name) == len) { found = i; matches = 1; break; }
                if (found < 0) found = i;
                matches++;
            }
            if (found >= 0 && matches == 1) {
                const struct option *op = &lo[found];
                optind++;
                if (op->has_arg == required_argument || op->has_arg == optional_argument) {
                    if (eq) optarg = (char *)eq + 1;
                    else if (op->has_arg == required_argument) {
                        if (optind >= argc) { if (opterr && !colon) fprintf(stderr, "%s: option `--%s' requires an argument\n", argv[0], op->name); return colon ? ':' : '?'; }
                        optarg = argv[optind++];
                    }
                } else if (eq) { if (opterr) fprintf(stderr, "%s: option `--%.*s' doesn't allow an argument\n", argv[0], (int)len, name); return '?'; }
                if (idx) *idx = found;
                if (op->flag) { *op->flag = op->val; return 0; }
                return op->val;
            }
            if (argv[optind][1] == '-') {
                if (opterr) fprintf(stderr, "%s: %s option `%s'\n", argv[0], matches > 1 ? "ambiguous" : "unrecognized", argv[optind]);
                optind++; optopt = 0; return '?';
            }
        }
        optpos = 1;
    }
    char c = argv[optind][optpos++];
    const char *p = c && c != ':' ? strchr(o, c) : 0;
    if (!argv[optind][optpos]) { optind++; optpos = 0; }
    if (!p) { optopt = c; if (opterr && !colon) fprintf(stderr, "%s: illegal option -- %c\n", argv[0], c); return '?'; }
    if (p[1] == ':') {
        if (optpos) { optarg = argv[optind] + optpos; optind++; optpos = 0; }
        else if (p[2] != ':') {
            if (optind >= argc) { optopt = c; if (opterr && !colon) fprintf(stderr, "%s: option requires an argument -- %c\n", argv[0], c); return colon ? ':' : '?'; }
            optarg = argv[optind++];
        }
    }
    return c;
}
int getopt(int argc, char *const argv[], const char *opts) { return getopt_impl(argc, argv, opts, 0, 0, 0); }
int getopt_long(int argc, char *const argv[], const char *opts, const struct option *lo, int *idx) { return getopt_impl(argc, argv, opts, lo, idx, 0); }
int getopt_long_only(int argc, char *const argv[], const char *opts, const struct option *lo, int *idx) { return getopt_impl(argc, argv, opts, lo, idx, 1); }

/* ---------------- CommonCrypto ciphers: not implemented yet (callers get kCCUnimplemented) ---------------- */
#include <CommonCrypto/CommonCryptor.h>
CCCryptorStatus CCCryptorCreate(CCOperation op, CCAlgorithm alg, CCOptions o, const void *key, size_t kl, const void *iv, CCCryptorRef *out) { if (out) *out = 0; return kCCUnimplemented; }
CCCryptorStatus CCCryptorUpdate(CCCryptorRef c, const void *in, size_t inl, void *out, size_t outl, size_t *moved) { if (moved) *moved = 0; return kCCUnimplemented; }
CCCryptorStatus CCCryptorFinal(CCCryptorRef c, void *out, size_t outl, size_t *moved) { if (moved) *moved = 0; return kCCUnimplemented; }
CCCryptorStatus CCCryptorReset(CCCryptorRef c, const void *iv) { return kCCUnimplemented; }
CCCryptorStatus CCCryptorRelease(CCCryptorRef c) { return kCCSuccess; }
CCCryptorStatus CCCrypt(CCOperation op, CCAlgorithm alg, CCOptions o, const void *key, size_t kl, const void *iv, const void *in, size_t inl, void *out, size_t outl, size_t *moved) { if (moved) *moved = 0; return kCCUnimplemented; }

/* clonefile: a plain copy (no copy-on-write on Windows) of a file, or of a directory tree, with the extended attributes */
#include <sys/xattr.h>
static void copy_xattrs(const char *src, const char *dst) {
    char names[4096]; ssize_t n = listxattr(src, names, sizeof names, 0);
    for (ssize_t i = 0; i < n; i += (ssize_t)strlen(names + i) + 1) {
        char val[4096]; ssize_t v = getxattr(src, names + i, val, sizeof val, 0, 0);
        if (v >= 0) setxattr(dst, names + i, val, (size_t)v, 0, 0);
    }
}
int clonefile(const char *src, const char *dst, uint32_t flags) {
    struct stat st;
    if (lstat(src, &st)) return -1;
    if (!lstat(dst, &st) || errno != ENOENT) { errno = EEXIST; return -1; }
    lstat(src, &st);
    if (S_ISDIR(st.st_mode)) {
        if (mkdir(dst, st.st_mode & 0777)) return -1;
        DIR *d = opendir(src);
        if (!d) return -1;
        struct dirent *e; int r = 0;
        while (!r && (e = readdir(d))) {
            if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
            char a[1024], b[1024];
            snprintf(a, sizeof a, "%s/%s", src, e->d_name); snprintf(b, sizeof b, "%s/%s", dst, e->d_name);
            r = clonefile(a, b, flags);
        }
        closedir(d);
        if (!r) copy_xattrs(src, dst);
        return r;
    }
    int in = open(src, O_RDONLY), out;
    if (in < 0) return -1;
    if ((out = open(dst, O_WRONLY | O_CREAT | O_EXCL, st.st_mode & 0777)) < 0) { close(in); return -1; }
    char buf[65536]; ssize_t r;
    while ((r = read(in, buf, sizeof buf)) > 0) if (write(out, buf, (size_t)r) != r) { r = -1; break; }
    close(in); close(out);
    if (r >= 0) copy_xattrs(src, dst);
    return r < 0 ? -1 : 0;
}
int clonefileat(int sfd, const char *src, int dfd, const char *dst, uint32_t flags) { return clonefile(src, dst, flags); } /* ponytail: AT_FDCWD only */