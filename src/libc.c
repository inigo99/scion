/* libc.c — C library pieces of scion's libSystem: stdio (printf family, FILE), stdlib, string, ctype.
 * Formatting supports %@ through a hook installed by Foundation (object -> description). */
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

void *malloc(size_t); void free(void *); void *realloc(void *, size_t); void *calloc(size_t, size_t);
void *memcpy(void *, const void *, size_t); void *memmove(void *, const void *, size_t); void *memset(void *, int, size_t);
int memcmp(const void *, const void *, size_t); size_t strlen(const char *); int strcmp(const char *, const char *);
int strncmp(const char *, const char *, size_t); char *strchr(const char *, int);
int64_t write(int, const void *, size_t); int64_t read(int, void *, size_t); int open(const char *, int, ...); int close(int);
int64_t lseek(int, int64_t, int); int *__error(void); void exit(int); int64_t clock_gettime_ns_realtime(void);

/* ===================================================================== ctype */
int isdigit(int c) { return c >= '0' && c <= '9'; }
int isalpha(int c) { return (c | 32) >= 'a' && (c | 32) <= 'z'; }
int isalnum(int c) { return isdigit(c) || isalpha(c); }
int isspace(int c) { return c == ' ' || (c >= 9 && c <= 13); }
int isupper(int c) { return c >= 'A' && c <= 'Z'; }
int islower(int c) { return c >= 'a' && c <= 'z'; }
int isxdigit(int c) { return isdigit(c) || ((c | 32) >= 'a' && (c | 32) <= 'f'); }
int isprint(int c) { return c >= 32 && c < 127; }
int ispunct(int c) { return isprint(c) && !isalnum(c) && c != ' '; }
int iscntrl(int c) { return (c >= 0 && c < 32) || c == 127; }
int isgraph(int c) { return c > 32 && c < 127; }
int toupper(int c) { return islower(c) ? c - 32 : c; }
int tolower(int c) { return isupper(c) ? c + 32 : c; }
/* Darwin <ctype.h> inlines go through these when the "fast" tables are not used */
int __tolower(int c) { return tolower(c); }
int __toupper(int c) { return toupper(c); }
unsigned long ___runetype(int c) { return 0; }
int __maskrune(int c, unsigned long f) {
    unsigned long m = 0;
    if (isalpha(c)) m |= 0x100; if (isdigit(c)) m |= 0x400; if (isspace(c)) m |= 0x4000; if (isupper(c)) m |= 0x8000;
    if (islower(c)) m |= 0x1000; if (isxdigit(c)) m |= 0x10000; if (ispunct(c)) m |= 0x2000; if (isprint(c)) m |= 0x40000;
    if (iscntrl(c)) m |= 0x200; if (isgraph(c)) m |= 0x800;
    return (int)(m & f);
}

/* ===================================================================== string */
char *strcpy(char *d, const char *s) { char *r = d; while ((*d++ = *s++)) continue; return r; }
char *strncpy(char *d, const char *s, size_t n) { size_t i = 0; for (; i < n && s[i]; i++) d[i] = s[i]; for (; i < n; i++) d[i] = 0; return d; }
char *strcat(char *d, const char *s) { strcpy(d + strlen(d), s); return d; }
char *strncat(char *d, const char *s, size_t n) { char *e = d + strlen(d); size_t i = 0; for (; i < n && s[i]; i++) e[i] = s[i]; e[i] = 0; return d; }
size_t strlcpy(char *d, const char *s, size_t n) { size_t l = strlen(s); if (n) { size_t c = l < n - 1 ? l : n - 1; memcpy(d, s, c); d[c] = 0; } return l; }
size_t strlcat(char *d, const char *s, size_t n) { size_t dl = strlen(d); if (dl >= n) return n + strlen(s); return dl + strlcpy(d + dl, s, n - dl); }
char *strdup(const char *s) { size_t l = strlen(s) + 1; char *r = malloc(l); if (r) memcpy(r, s, l); return r; }
char *strndup(const char *s, size_t n) { size_t l = 0; while (l < n && s[l]) l++; char *r = malloc(l + 1); if (r) { memcpy(r, s, l); r[l] = 0; } return r; }
size_t strnlen(const char *s, size_t n) { size_t l = 0; while (l < n && s[l]) l++; return l; }
char *strrchr(const char *s, int c) { const char *r = 0; for (;; s++) { if (*s == (char)c) r = s; if (!*s) return (char *)r; } }
char *strstr(const char *h, const char *n) { size_t l = strlen(n); if (!l) return (char *)h; for (; *h; h++) if (!strncmp(h, n, l)) return (char *)h; return 0; }
int strcasecmp(const char *a, const char *b) { while (*a && tolower((unsigned char)*a) == tolower((unsigned char)*b)) a++, b++; return tolower((unsigned char)*a) - tolower((unsigned char)*b); }
int strncasecmp(const char *a, const char *b, size_t n) {
    for (; n; n--, a++, b++) { int d = tolower((unsigned char)*a) - tolower((unsigned char)*b); if (d || !*a) return d; }
    return 0;
}
char *strcasestr(const char *h, const char *n) { size_t l = strlen(n); for (; *h; h++) if (!strncasecmp(h, n, l)) return (char *)h; return l ? 0 : (char *)h; }
size_t strspn(const char *s, const char *a) { size_t n = 0; while (s[n] && strchr(a, s[n])) n++; return n; }
size_t strcspn(const char *s, const char *a) { size_t n = 0; while (s[n] && !strchr(a, s[n])) n++; return n; }
char *strpbrk(const char *s, const char *a) { s += strcspn(s, a); return *s ? (char *)s : 0; }
char *strtok_r(char *s, const char *d, char **save) {
    if (!s) s = *save;
    s += strspn(s, d);
    if (!*s) { *save = s; return 0; }
    char *e = s + strcspn(s, d);
    if (*e) *e++ = 0;
    *save = e; return s;
}
static char *tok_save;
char *strtok(char *s, const char *d) { return strtok_r(s, d, &tok_save); }
char *strsep(char **sp, const char *d) { char *s = *sp; if (!s) return 0; char *e = s + strcspn(s, d); if (*e) { *e = 0; *sp = e + 1; } else *sp = 0; return s; }
void *memrchr(const void *p, int c, size_t n) { const unsigned char *a = p; while (n--) if (a[n] == (unsigned char)c) return (void *)(a + n); return 0; }
void *memmem(const void *h, size_t hl, const void *n, size_t nl) {
    if (!nl) return (void *)h;
    for (size_t i = 0; i + nl <= hl; i++) if (!memcmp((const char *)h + i, n, nl)) return (char *)h + i;
    return 0;
}
int bcmp(const void *a, const void *b, size_t n) { return memcmp(a, b, n); }
void bcopy(const void *s, void *d, size_t n) { memmove(d, s, n); }
char *strerror(int e) { static char b[64]; extern int strerror_r(int, char *, size_t); strerror_r(e, b, sizeof b); return b; }

/* ===================================================================== stdlib */
int abs(int x) { return x < 0 ? -x : x; }
long labs(long x) { return x < 0 ? -x : x; }
long long llabs(long long x) { return x < 0 ? -x : x; }
unsigned long long strtoull(const char *s, char **end, int base) {
    while (isspace((unsigned char)*s)) s++;
    if (*s == '+') s++;
    if ((base == 0 || base == 16) && s[0] == '0' && (s[1] | 32) == 'x' && isxdigit((unsigned char)s[2])) { s += 2; base = 16; }
    else if (base == 0 && s[0] == '0') base = 8;
    else if (base == 0) base = 10;
    unsigned long long v = 0; const char *st = s;
    for (;; s++) {
        int d = isdigit((unsigned char)*s) ? *s - '0' : isalpha((unsigned char)*s) ? (*s | 32) - 'a' + 10 : 99;
        if (d >= base) break;
        v = v * base + d;
    }
    if (end) *end = (char *)(s == st ? st : s);
    return v;
}
long long strtoll(const char *s, char **end, int base) {
    while (isspace((unsigned char)*s)) s++;
    int neg = *s == '-'; if (*s == '-' || *s == '+') s++;
    unsigned long long v = strtoull(s, end, base);
    return neg ? -(long long)v : (long long)v;
}
unsigned long strtoul(const char *s, char **e, int b) { return strtoull(s, e, b); }
long strtol(const char *s, char **e, int b) { return strtoll(s, e, b); }
int atoi(const char *s) { return (int)strtol(s, 0, 10); }
long atol(const char *s) { return strtol(s, 0, 10); }
long long atoll(const char *s) { return strtoll(s, 0, 10); }
double strtod(const char *s, char **end) {
    const char *p = s; while (isspace((unsigned char)*p)) p++;
    int neg = *p == '-'; if (*p == '-' || *p == '+') p++;
    double v = 0, scale = 1; int any = 0;
    if (!strncasecmp(p, "inf", 3)) { if (end) *end = (char *)p + 3; return neg ? -__builtin_inf() : __builtin_inf(); }
    if (!strncasecmp(p, "nan", 3)) { if (end) *end = (char *)p + 3; return __builtin_nan(""); }
    while (isdigit((unsigned char)*p)) v = v * 10 + (*p++ - '0'), any = 1;
    if (*p == '.') { p++; while (isdigit((unsigned char)*p)) { scale /= 10; v += (*p++ - '0') * scale; any = 1; } }
    if (any && (*p | 32) == 'e') {
        const char *q = p + 1; int en = 0, eneg = *q == '-';
        if (*q == '-' || *q == '+') q++;
        if (isdigit((unsigned char)*q)) { while (isdigit((unsigned char)*q)) en = en * 10 + (*q++ - '0'); p = q; double f = 1; while (en--) f *= 10; v = eneg ? v / f : v * f; }
    }
    if (end) *end = (char *)(any ? p : s);
    return neg ? -v : v;
}
float strtof(const char *s, char **e) { return (float)strtod(s, e); }
long double strtold(const char *s, char **e) { return strtod(s, e); }
double atof(const char *s) { return strtod(s, 0); }
static void swapb(char *a, char *b, size_t n) {
    if (a == b) return;
    if (!(((uintptr_t)a | (uintptr_t)b | n) & 7)) { for (uint64_t *x = (uint64_t *)a, *y = (uint64_t *)b; n; n -= 8, x++, y++) { uint64_t t = *x; *x = *y; *y = t; } return; }
    if (!(((uintptr_t)a | (uintptr_t)b | n) & 3)) { for (uint32_t *x = (uint32_t *)a, *y = (uint32_t *)b; n; n -= 4, x++, y++) { uint32_t t = *x; *x = *y; *y = t; } return; }
    while (n--) { char t = *a; *a++ = *b; *b++ = t; }
}
/* introsort: median-of-3 quicksort, insertion sort for small runs, heapsort if recursion gets too deep. */
typedef int (*cmp3_t)(void *, const void *, const void *);
static void heap_sift(char *b, size_t i, size_t n, size_t sz, void *th, cmp3_t c) {
    for (size_t k; (k = 2 * i + 1) < n; i = k) {
        if (k + 1 < n && c(th, b + k * sz, b + (k + 1) * sz) < 0) k++;
        if (c(th, b + i * sz, b + k * sz) >= 0) return;
        swapb(b + i * sz, b + k * sz, sz);
    }
}
static void isort(char *b, size_t n, size_t sz, void *th, cmp3_t c, int depth) {
    while (n > 12) {
        if (!depth--) { /* heapsort */
            for (size_t i = n / 2; i--;) heap_sift(b, i, n, sz, th, c);
            for (size_t i = n; --i;) { swapb(b, b + i * sz, sz); heap_sift(b, 0, i, sz, th, c); }
            return;
        }
        char *lo = b, *mid = b + n / 2 * sz, *hi = b + (n - 1) * sz;
        if (c(th, mid, lo) < 0) swapb(mid, lo, sz);
        if (c(th, hi, mid) < 0) { swapb(hi, mid, sz); if (c(th, mid, lo) < 0) swapb(mid, lo, sz); }
        swapb(b, mid, sz); /* pivot at b[0] */
        size_t i = 1, j = n - 1;
        for (;;) {
            while (i <= j && c(th, b + i * sz, b) < 0) i++;
            while (j >= i && c(th, b + j * sz, b) > 0) j--;
            if (i >= j) break;
            swapb(b + i * sz, b + j * sz, sz); i++; j--;
        }
        swapb(b, b + j * sz, sz);
        size_t ln = j, rn = n - j - 1;
        if (ln < rn) { isort(b, ln, sz, th, c, depth); b += (j + 1) * sz; n = rn; }
        else { isort(b + (j + 1) * sz, rn, sz, th, c, depth); n = ln; }
    }
    for (size_t i = 1; i < n; i++)
        for (size_t k = i; k && c(th, b + (k - 1) * sz, b + k * sz) > 0; k--) swapb(b + (k - 1) * sz, b + k * sz, sz);
}
static int cmp2(void *f, const void *a, const void *b) { return ((int (*)(const void *, const void *))f)(a, b); }
void qsort_r(void *base, size_t n, size_t sz, void *th, int (*cmp)(void *, const void *, const void *)) {
    int d = 0; for (size_t m = n; m; m >>= 1) d += 2;
    isort(base, n, sz, th, cmp, d);
}
void qsort(void *base, size_t n, size_t sz, int (*cmp)(const void *, const void *)) { qsort_r(base, n, sz, (void *)cmp, cmp2); }
static int cmpb(void *f, const void *a, const void *b) { return ((int (^)(const void *, const void *))f)(a, b); }
void qsort_b(void *base, size_t n, size_t sz, int (^cmp)(const void *, const void *)) { qsort_r(base, n, sz, (void *)cmp, cmpb); }
void *bsearch(const void *k, const void *base, size_t n, size_t sz, int (*cmp)(const void *, const void *)) {
    size_t lo = 0, hi = n;
    while (lo < hi) { size_t m = (lo + hi) / 2; int c = cmp(k, (const char *)base + m * sz); if (!c) return (char *)base + m * sz; if (c < 0) hi = m; else lo = m + 1; }
    return 0;
}
static uint64_t rng = 0x853c49e6748fea9bull;
int rand(void) { rng = rng * 6364136223846793005ull + 1442695040888963407ull; return (int)(rng >> 33) & 0x7fffffff; }
void srand(unsigned s) { rng = s; }
long random(void) { return rand(); }
void srandom(unsigned s) { srand(s); }
uint32_t arc4random(void) { uint32_t v; extern void arc4random_buf(void *, size_t); arc4random_buf(&v, 4); return v; }
uint32_t arc4random_uniform(uint32_t n) { return n ? arc4random() % n : 0; }
int64_t time(int64_t *t) { struct { int64_t s, ns; } ts; extern int clock_gettime(int, void *); clock_gettime(0, &ts); if (t) *t = ts.s; return ts.s; }
int posix_memalign(void **p, size_t al, size_t n) { /* ponytail: over-allocate, never freed through free() correctly when al > 16 */
    if (al <= 16) { *p = malloc(n); return *p ? 0 : 12; }
    char *r = malloc(n + al); if (!r) return 12;
    *p = (void *)(((uintptr_t)r + al - 1) & ~(uintptr_t)(al - 1)); return 0;
}
void *aligned_alloc(size_t al, size_t n) { void *p; return posix_memalign(&p, al, n) ? 0 : p; }
void *valloc(size_t n) { return aligned_alloc(4096, n); }
void *reallocf(void *p, size_t n) { void *r = realloc(p, n); if (!r) free(p); return r; }
size_t malloc_good_size(size_t n) { return (n + 15) & ~(size_t)15; }

/* ===================================================================== formatting */
/* Foundation installs this to format %@ (returns a UTF-8 description that stays valid until the next call) */
const char *(*_scion_describe_object)(void *obj);

struct fout { char *buf; size_t cap, len; int fd; };
static void put(struct fout *o, const char *s, size_t n) {
    if (o->fd >= 0) { write(o->fd, s, n); o->len += n; return; }
    for (size_t i = 0; i < n; i++, o->len++) if (o->len + 1 < o->cap) o->buf[o->len] = s[i];
}
static void pad(struct fout *o, char c, int n) { while (n-- > 0) put(o, &c, 1); }
static int fmt_double(char *b, double v, int prec, char conv, int alt) { /* %f %e %g with correct rounding for common magnitudes */
    char *p = b;
    if (v != v) { memcpy(b, "nan", 4); return 3; }
    if (v < 0 || (v == 0 && 1 / v < 0)) { *p++ = '-'; v = -v; }
    if (v == __builtin_inf()) { memcpy(p, "inf", 4); return (int)(p - b) + 3; }
    if (prec < 0) prec = 6;
    int exp10 = 0;
    if (conv == 'g' || conv == 'G') {
        if (prec == 0) prec = 1;
        double t = v; int e = 0;
        if (t != 0) { while (t >= 10) t /= 10, e++; while (t < 1) t *= 10, e--; }
        if (e < -4 || e >= prec) { conv = conv == 'g' ? 'e' : 'E'; prec--; }
        else { conv = 'f'; prec = prec - 1 - e; }
        if (!alt) { /* %g strips trailing zeros */
            int n = fmt_double(p, v, prec, conv, 1);
            char *q = p + n, *dot = 0, *ex = 0;
            for (char *r = p; r < q; r++) { if (*r == '.') dot = r; if (*r == 'e' || *r == 'E') ex = r; }
            if (dot) {
                char *end = ex ? ex : q, *z = end;
                while (z > dot + 1 && z[-1] == '0') z--;
                if (z == dot + 1) z = dot;
                memmove(z, end, (size_t)(q - end) + 1); q = z + (q - end);
            }
            return (int)(q - b);
        }
    }
    if (conv == 'e' || conv == 'E') {
        if (v != 0) { while (v >= 10) v /= 10, exp10++; while (v < 1) v *= 10, exp10--; }
    }
    double r = 0.5; for (int i = 0; i < prec; i++) r /= 10;
    v += r;
    if ((conv == 'e' || conv == 'E') && v >= 10) { v /= 10; exp10++; }
    if (v >= 1e19) { /* beyond integer formatting: fall back to exponent form */
        int e = 0; while (v >= 10) v /= 10, e++;
        int n = fmt_double(p, v, prec, 'e', alt); p += n; return (int)(p - b);
    }
    uint64_t ip = (uint64_t)v; double fr = v - (double)ip;
    char tmp[24]; int k = 0; do tmp[k++] = (char)('0' + ip % 10); while (ip /= 10);
    while (k) *p++ = tmp[--k];
    if (prec || alt) *p++ = '.';
    for (int i = 0; i < prec; i++) { fr *= 10; int d = (int)fr; if (d > 9) d = 9; *p++ = (char)('0' + d); fr -= d; }
    if (conv == 'e' || conv == 'E') {
        *p++ = conv; *p++ = exp10 < 0 ? '-' : '+'; if (exp10 < 0) exp10 = -exp10;
        if (exp10 >= 100) *p++ = (char)('0' + exp10 / 100);
        *p++ = (char)('0' + exp10 / 10 % 10); *p++ = (char)('0' + exp10 % 10);
    }
    *p = 0;
    return (int)(p - b);
}
static int utf8_of(uint32_t c, char *o) {
    if (c < 0x80) { o[0] = (char)c; return 1; }
    if (c < 0x800) { o[0] = (char)(0xC0 | c >> 6); o[1] = (char)(0x80 | (c & 63)); return 2; }
    if (c < 0x10000) { o[0] = (char)(0xE0 | c >> 12); o[1] = (char)(0x80 | (c >> 6 & 63)); o[2] = (char)(0x80 | (c & 63)); return 3; }
    o[0] = (char)(0xF0 | c >> 18); o[1] = (char)(0x80 | (c >> 12 & 63)); o[2] = (char)(0x80 | (c >> 6 & 63)); o[3] = (char)(0x80 | (c & 63)); return 4;
}
/* positional arguments ("%2$@ of %1$@"): the types are scanned first, then every argument is read in order */
enum { K_NONE, K_INT, K_LL, K_DBL, K_LDBL, K_PTR };
union farg { long long i; double d; long double ld; void *p; };
static int fpos(const char **fp) { const char *f = *fp; int n = 0; while (isdigit((unsigned char)*f)) n = n * 10 + (*f++ - '0'); if (*f != '$' || !n) return 0; *fp = f + 1; return n; }
static int fpositional(const char *f, union farg *args, int max, va_list ap) {
    unsigned char kind[64] = {0}; int top = 0;
    for (; *f; f++) {
        if (*f != '%') continue;
        f++; if (*f == '%') continue;
        int i = fpos(&f); if (!i) return 0;
        while (strchr("-0+ #'", *f) && *f) f++;
        while (isdigit((unsigned char)*f) || *f == '*' || *f == '.') f++;
        int lng = 0; for (;; f++) { if (*f == 'l') lng++; else if (*f == 'z' || *f == 't' || *f == 'j' || *f == 'q' || *f == 'L') lng = 2; else if (*f != 'h') break; }
        if (!*f || i > max) return 0;
        int k = strchr("diuxXoc", *f) ? (lng ? K_LL : K_INT) : strchr("OUD", *f) ? K_LL : strchr("fFeEgGaA", *f) ? (lng == 2 ? K_LDBL : K_DBL) : strchr("psS@nC", *f) ? K_PTR : K_INT;
        kind[i - 1] = (unsigned char)k; if (i > top) top = i;
    }
    for (int i = 0; i < top; i++)
        switch (kind[i]) { case K_LL: args[i].i = va_arg(ap, long long); break; case K_DBL: args[i].d = va_arg(ap, double); break; case K_LDBL: args[i].ld = va_arg(ap, long double); break; case K_PTR: args[i].p = va_arg(ap, void *); break; default: args[i].i = va_arg(ap, int); }
    return top;
}
static void vformat(struct fout *o, const char *f, va_list ap) {
    union farg args[64]; int positional = strchr(f, '$') && fpositional(f, args, 64, ap), cur = 0;
#undef va_arg
#define va_arg(ap, T) (positional ? *(T *)&args[cur] : __builtin_va_arg(ap, T))   /* little-endian: an int is the low half of its slot */
    for (; *f; f++) {
        if (*f != '%') { const char *s = f; while (f[1] && f[1] != '%') f++; put(o, s, (size_t)(f - s + 1)); continue; }
        f++;
        if (positional && *f != '%') cur = fpos(&f) - 1;
        int left = 0, zero = 0, plus = 0, space = 0, alt = 0, width = -1, prec = -1, lng = 0, hh = 0, h = 0;
        for (;; f++) { if (*f == '-') left = 1; else if (*f == '0') zero = 1; else if (*f == '+') plus = 1; else if (*f == ' ') space = 1; else if (*f == '#') alt = 1; else if (*f == '\'') ; else break; }
        if (*f == '*') { width = va_arg(ap, int); if (width < 0) left = 1, width = -width; f++; } else if (isdigit((unsigned char)*f)) { width = 0; while (isdigit((unsigned char)*f)) width = width * 10 + (*f++ - '0'); }
        if (*f == '.') { f++; prec = 0; if (*f == '*') { prec = va_arg(ap, int); f++; } else while (isdigit((unsigned char)*f)) prec = prec * 10 + (*f++ - '0'); }
        for (;; f++) { if (*f == 'l') lng++; else if (*f == 'h') { if (h) hh = 1; h = 1; } else if (*f == 'z' || *f == 't' || *f == 'j' || *f == 'q') lng = 2; else if (*f == 'L') lng = 2; else break; }
        char buf[352], *s = buf; int n = 0, neg = 0;
        const char *pre = "";
        switch (*f) {
        case 'd': case 'i': {
            long long v = lng ? va_arg(ap, long long) : va_arg(ap, int);
            if (hh) v = (signed char)v; else if (h) v = (short)v;
            unsigned long long u = v < 0 ? 0ull - (unsigned long long)v : (unsigned long long)v; neg = v < 0;
            char t[24]; int k = 0; do t[k++] = (char)('0' + u % 10); while (u /= 10);
            while (k < prec) t[k++] = '0';
            if (prec == 0 && v == 0) k = 0;
            while (k) buf[n++] = t[--k];
            pre = neg ? "-" : plus ? "+" : space ? " " : "";
            break;
        }
        case 'u': case 'x': case 'X': case 'o': case 'p': case 'O': case 'U': case 'D': {
            unsigned long long u; int base = (*f == 'x' || *f == 'X' || *f == 'p') ? 16 : (*f == 'o' || *f == 'O') ? 8 : 10;
            if (*f == 'p') { u = (uintptr_t)va_arg(ap, void *); alt = 1; }
            else if (*f == 'D') { long long v = va_arg(ap, long); neg = v < 0; u = neg ? 0ull - (unsigned long long)v : (unsigned long long)v; }
            else u = (lng || *f == 'O' || *f == 'U') ? va_arg(ap, unsigned long long) : va_arg(ap, unsigned int);
            if (hh) u = (unsigned char)u; else if (h) u = (unsigned short)u;
            const char *dig = *f == 'X' ? "0123456789ABCDEF" : "0123456789abcdef";
            char t[24]; int k = 0; do t[k++] = dig[u % base]; while (u /= base);
            while (k < prec) t[k++] = '0';
            while (k) buf[n++] = t[--k];
            if (alt && base == 16) pre = *f == 'X' ? "0X" : "0x";
            if (alt && base == 8 && buf[0] != '0') pre = "0";
            if (neg) pre = "-";
            break;
        }
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A': {
            double v = lng == 2 ? (double)va_arg(ap, long double) : va_arg(ap, double);
            char c = *f == 'F' ? 'f' : *f == 'a' ? 'e' : *f == 'A' ? 'E' : *f;
            n = fmt_double(buf, v, prec, c, alt);
            if (buf[0] == '-') { s = buf + 1; n--; pre = "-"; } else pre = plus ? "+" : space ? " " : "";
            prec = -1;
            break;
        }
        case 'c': case 'C': { uint32_t c = (uint32_t)va_arg(ap, int); n = *f == 'C' || lng ? utf8_of(c, buf) : (buf[0] = (char)c, 1); break; }
        case 's': case 'S': {
            if (*f == 'S' || lng) { /* wide string: UTF-32 on Darwin for %ls, UTF-16 for %S in NSString formats */
                const uint16_t *w = va_arg(ap, const uint16_t *);
                if (!w) { s = "(null)"; n = 6; break; }
                char *t = buf; for (int i = 0; w[i] && t - buf < 340 && (prec < 0 || t - buf < prec); i++) t += utf8_of(w[i], t);
                n = (int)(t - buf); break;
            }
            s = va_arg(ap, char *);
            if (!s) s = "(null)";
            n = 0; while (s[n] && (prec < 0 || n < prec)) n++;
            break;
        }
        case '@': {
            void *obj = va_arg(ap, void *);
            s = obj ? (_scion_describe_object ? (char *)_scion_describe_object(obj) : "<object>") : "(null)";
            n = (int)strlen(s);
            break;
        }
        case 'n': { int *p = va_arg(ap, int *); if (p) *p = (int)o->len; continue; }
        case '%': buf[0] = '%'; n = 1; break;
        case 0: return;
        default: buf[0] = '%'; buf[1] = *f; n = 2; break;
        }
        int total = n + (int)strlen(pre);
        if (!left && !zero) pad(o, ' ', width - total);
        put(o, pre, strlen(pre));
        if (!left && zero) pad(o, '0', width - total);
        put(o, s, (size_t)n);
        if (left) pad(o, ' ', width - total);
    }
#undef va_arg
#define va_arg(ap, T) __builtin_va_arg(ap, T)
}
int vsnprintf(char *b, size_t cap, const char *f, va_list ap) {
    struct fout o = {b, cap, 0, -1};
    vformat(&o, f, ap);
    if (cap) b[o.len < cap ? o.len : cap - 1] = 0;
    return (int)o.len;
}
int snprintf(char *b, size_t cap, const char *f, ...) { va_list ap; va_start(ap, f); int r = vsnprintf(b, cap, f, ap); va_end(ap); return r; }
int vsprintf(char *b, const char *f, va_list ap) { return vsnprintf(b, (size_t)-1 >> 1, f, ap); }
int sprintf(char *b, const char *f, ...) { va_list ap; va_start(ap, f); int r = vsprintf(b, f, ap); va_end(ap); return r; }
int vasprintf(char **out, const char *f, va_list ap) {
    va_list c; va_copy(c, ap);
    int n = vsnprintf(0, 0, f, c); va_end(c);
    *out = malloc((size_t)n + 1);
    if (!*out) return -1;
    return vsnprintf(*out, (size_t)n + 1, f, ap);
}
int asprintf(char **out, const char *f, ...) { va_list ap; va_start(ap, f); int r = vasprintf(out, f, ap); va_end(ap); return r; }

/* ===================================================================== FILE (Darwin __sFILE-compatible prefix, unbuffered) */
typedef struct FILE {
    unsigned char *p; int r, w; short flags, file;  /* Darwin layout: getc/putc_unlocked macros see r == w == 0 */
    char pad[140];
    int fd, eof, err, ungot;
    /* funopen(): callbacks instead of a descriptor */
    void *cookie; int (*rd)(void *, char *, int); int (*wr)(void *, const char *, int); int64_t (*sk)(void *, int64_t, int); int (*cl)(void *);
} FILE;
static int64_t f_write(FILE *fp, const void *p, size_t n) { return fp->wr ? fp->wr(fp->cookie, p, (int)n) : fp->rd ? -1 : write(fp->fd, p, n); }
static int64_t f_read(FILE *fp, void *p, size_t n) { return fp->rd ? fp->rd(fp->cookie, p, (int)n) : fp->wr ? -1 : read(fp->fd, p, n); }
static FILE f_in = {.fd = 0, .file = 0, .ungot = -1}, f_out = {.fd = 1, .file = 1, .ungot = -1}, f_err = {.fd = 2, .file = 2, .ungot = -1};
FILE *__stdinp = &f_in, *__stdoutp = &f_out, *__stderrp = &f_err;
int vfprintf(FILE *fp, const char *f, va_list ap) {
    char tmp[1024]; va_list c; va_copy(c, ap);
    int n = vsnprintf(tmp, sizeof tmp, f, c); va_end(c);
    if (n < (int)sizeof tmp) { f_write(fp, tmp, (size_t)n); return n; }
    if (fp->wr) { char *b = malloc((size_t)n + 1); vsnprintf(b, (size_t)n + 1, f, ap); f_write(fp, b, (size_t)n); free(b); return n; }
    struct fout o = {0, 0, 0, fp->fd}; vformat(&o, f, ap); return (int)o.len;
}
int fprintf(FILE *fp, const char *f, ...) { va_list ap; va_start(ap, f); int r = vfprintf(fp, f, ap); va_end(ap); return r; }
int vprintf(const char *f, va_list ap) { return vfprintf(__stdoutp, f, ap); }
int printf(const char *f, ...) { va_list ap; va_start(ap, f); int r = vfprintf(__stdoutp, f, ap); va_end(ap); return r; }
int vdprintf(int fd, const char *f, va_list ap) { FILE t = {.fd = fd}; return vfprintf(&t, f, ap); }
int dprintf(int fd, const char *f, ...) { FILE t = {.fd = fd}; va_list ap; va_start(ap, f); int r = vfprintf(&t, f, ap); va_end(ap); return r; }
size_t fwrite(const void *p, size_t sz, size_t n, FILE *fp) {
    if (!sz || !n) return 0;
    int64_t w = f_write(fp, p, sz * n);
    if (w < 0) { fp->err = 1; return 0; }
    return (size_t)w / sz;
}
int fputs(const char *s, FILE *fp) { return fwrite(s, 1, strlen(s), fp) == strlen(s) ? 0 : -1; }
int puts(const char *s) { fputs(s, __stdoutp); return fputs("\n", __stdoutp); }
int fputc(int c, FILE *fp) { unsigned char b = (unsigned char)c; return fwrite(&b, 1, 1, fp) ? c : -1; }
int putc(int c, FILE *fp) { return fputc(c, fp); }
int putchar(int c) { return fputc(c, __stdoutp); }
int __swbuf(int c, FILE *fp) { return fputc(c, fp); }
size_t fread(void *p, size_t sz, size_t n, FILE *fp) {
    if (!sz || !n) return 0;
    size_t want = sz * n, got = 0;
    if (fp->ungot >= 0 && want) { ((unsigned char *)p)[got++] = (unsigned char)fp->ungot; fp->ungot = -1; }
    while (got < want) {
        int64_t r = f_read(fp, (char *)p + got, want - got);
        if (r <= 0) { if (r == 0) fp->eof = 1; else fp->err = 1; break; }
        got += (size_t)r;
    }
    return got / sz;
}
int fgetc(FILE *fp) { unsigned char c; return fread(&c, 1, 1, fp) ? c : -1; }
int getc(FILE *fp) { return fgetc(fp); }
int getchar(void) { return fgetc(__stdinp); }
int __srget(FILE *fp) { return fgetc(fp); }
int ungetc(int c, FILE *fp) { if (c < 0) return -1; fp->ungot = c; fp->eof = 0; return c; }
char *fgets(char *s, int n, FILE *fp) {
    int i = 0;
    while (i < n - 1) { int c = fgetc(fp); if (c < 0) break; s[i++] = (char)c; if (c == '\n') break; }
    if (!i) return 0;
    s[i] = 0; return s;
}
int64_t getline(char **lp, size_t *cap, FILE *fp) {
    size_t n = 0;
    for (;;) {
        int c = fgetc(fp);
        if (c < 0) break;
        if (n + 2 > *cap || !*lp) { *cap = *cap ? *cap * 2 : 128; *lp = realloc(*lp, *cap); }
        (*lp)[n++] = (char)c;
        if (c == '\n') break;
    }
    if (!n) return -1;
    (*lp)[n] = 0; return (int64_t)n;
}
FILE *fdopen(int fd, const char *mode) { FILE *f = calloc(1, sizeof *f); if (f) { f->fd = fd; f->file = (short)fd; f->ungot = -1; } return f; }
FILE *fopen(const char *path, const char *mode) {
    int fl = 0;
    switch (mode[0]) { case 'r': fl = strchr(mode, '+') ? 2 : 0; break;
                       case 'w': fl = (strchr(mode, '+') ? 2 : 1) | 0x200 | 0x400; break;
                       case 'a': fl = (strchr(mode, '+') ? 2 : 1) | 0x200 | 8; break;
                       default: *__error() = 22; return 0; }
    int fd = open(path, fl, 0644);
    return fd < 0 ? 0 : fdopen(fd, mode);
}
FILE *funopen(const void *cookie, int (*rd)(void *, char *, int), int (*wr)(void *, const char *, int),
               int64_t (*sk)(void *, int64_t, int), int (*cl)(void *)) {
    FILE *f = calloc(1, sizeof *f);
    if (!f) return 0;
    f->fd = -1; f->file = -1; f->ungot = -1; f->cookie = (void *)cookie; f->rd = rd; f->wr = wr; f->sk = sk; f->cl = cl;
    return f;
}
int fclose(FILE *fp) { int r = fp->rd || fp->wr ? (fp->cl ? fp->cl(fp->cookie) : 0) : close(fp->fd); if (fp != &f_in && fp != &f_out && fp != &f_err) free(fp); return r; }
int fflush(FILE *fp) { return 0; }
int dup2(int, int);
FILE *freopen(const char *path, const char *mode, FILE *fp) {
    if (!path) return fp;   /* mode change only: nothing to do */
    FILE *n = fopen(path, mode);
    if (!n) return 0;
    if (fp->fd >= 0 && !fp->rd && !fp->wr) { dup2(n->fd, fp->fd); close(n->fd); free(n); }   /* stderr stays fd 2 */
    else { int fd = n->fd; free(n); fp->rd = 0; fp->wr = 0; fp->fd = fd; fp->file = (short)fd; }
    fp->eof = fp->err = 0; fp->ungot = -1;
    return fp;
}
/* ===================================================================== system, popen: /bin/sh -c (proc.cpp maps it on Windows) */
int posix_spawn(int *, const char *, void *const *, void *const *, char *const[], char *const[]);
int posix_spawn_file_actions_init(void **); int posix_spawn_file_actions_destroy(void **);
int posix_spawn_file_actions_adddup2(void **, int, int); int posix_spawn_file_actions_addclose(void **, int);
int waitpid(int, int *, int); int pipe(int[2]);
static int sh(const char *cmd, void **fa, int *pid) {
    char *argv[] = {"sh", "-c", (char *)cmd, 0};
    return posix_spawn(pid, "/bin/sh", fa, 0, argv, 0);
}
int system(const char *cmd) {
    int pid, st = 0;
    if (!cmd) return 1;   /* a shell is there */
    if (sh(cmd, 0, &pid)) return 127 << 8;
    while (waitpid(pid, &st, 0) < 0 && *__error() == 4 /* EINTR */) {}
    return st;
}
/* the FILE of each popen, with its child */
static struct { FILE *f; int pid; } g_popen[64];
FILE *popen(const char *cmd, const char *mode) {
    int fds[2], pid, w = mode[0] == 'w';
    if ((mode[0] != 'r' && !w) || pipe(fds)) { *__error() = 22; return 0; }
    void *fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, fds[w ? 0 : 1], w ? 0 : 1);
    posix_spawn_file_actions_addclose(&fa, fds[w ? 1 : 0]);
    int e = sh(cmd, &fa, &pid);
    posix_spawn_file_actions_destroy(&fa);
    close(fds[w ? 0 : 1]);
    if (e) { close(fds[w ? 1 : 0]); *__error() = e; return 0; }
    FILE *f = fdopen(fds[w ? 1 : 0], mode);
    for (int i = 0; i < 64; i++) if (!g_popen[i].f) { g_popen[i].f = f; g_popen[i].pid = pid; break; }   /* ponytail: 64 at a time */
    return f;
}
int pclose(FILE *f) {
    int pid = -1, st = 0;
    for (int i = 0; i < 64; i++) if (g_popen[i].f == f) { pid = g_popen[i].pid; g_popen[i].f = 0; break; }
    fclose(f);
    if (pid < 0) { *__error() = 10 /* ECHILD */; return -1; }
    while (waitpid(pid, &st, 0) < 0) if (*__error() != 4) return -1;
    return st;
}
int fseek(FILE *fp, long off, int wh) {
    fp->eof = 0; fp->ungot = -1;
    if (fp->rd || fp->wr) return fp->sk && fp->sk(fp->cookie, off, wh) >= 0 ? 0 : -1;
    return lseek(fp->fd, off, wh) < 0 ? -1 : 0;
}
int fseeko(FILE *fp, int64_t off, int wh) { return fseek(fp, (long)off, wh); }
long ftell(FILE *fp) { return fp->rd || fp->wr ? (fp->sk ? (long)fp->sk(fp->cookie, 0, 1) : -1) : (long)lseek(fp->fd, 0, 1); }
int64_t ftello(FILE *fp) { return ftell(fp); }
void rewind(FILE *fp) { fseek(fp, 0, 0); fp->err = 0; }
int feof(FILE *fp) { return fp->eof; }
int ferror(FILE *fp) { return fp->err; }
void clearerr(FILE *fp) { fp->eof = fp->err = 0; }
int fileno(FILE *fp) { return fp->fd; }
int setvbuf(FILE *fp, char *b, int m, size_t n) { return 0; }
void setbuf(FILE *fp, char *b) {}
void setlinebuf(FILE *fp) {}
void perror(const char *s) { extern char *strerror(int); if (s && *s) { fputs(s, __stderrp); fputs(": ", __stderrp); } fputs(strerror(*__error()), __stderrp); fputs("\n", __stderrp); }
int remove(const char *p) { extern int unlink(const char *); extern int rmdir(const char *); return unlink(p) == 0 ? 0 : rmdir(p); }
void flockfile(FILE *f) {}
/* temporary files and directories: the trailing X's become random letters */
extern void arc4random_buf(void *, size_t); extern int mkdir(const char *, int);
static int tmpname(char *t, int suffix) {
    size_t n = strlen(t) - (size_t)suffix, k = 0;
    while (k < n && t[n - 1 - k] == 'X') k++;
    if (k < 1) { *__error() = 22; return -1; }
    unsigned char r[64]; arc4random_buf(r, k > 64 ? 64 : k);
    for (size_t i = 0; i < k; i++) t[n - k + i] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[r[i % 64] % 62];
    return 0;
}
int mkstemps(char *t, int suffix) {
    char *copy = strdup(t);
    for (int tries = 0; tries < 100; tries++) {
        strcpy(t, copy);
        if (tmpname(t, suffix) < 0) break;
        int fd = open(t, 2 | 0x200 | 0x800, 0600); /* O_RDWR | O_CREAT | O_EXCL */
        if (fd >= 0 || *__error() != 17 /* EEXIST */) { free(copy); return fd; }
    }
    free(copy); return -1;
}
int mkstemp(char *t) { return mkstemps(t, 0); }
char *mkdtemp(char *t) {
    char *copy = strdup(t);
    for (int tries = 0; tries < 100; tries++) {
        strcpy(t, copy);
        if (tmpname(t, 0) < 0) break;
        if (mkdir(t, 0700) == 0) { free(copy); return t; }
        if (*__error() != 17) break;
    }
    free(copy); return 0;
}
char *mktemp(char *t) { return tmpname(t, 0) < 0 ? 0 : t; }
void funlockfile(FILE *f) {}

/* minimal sscanf: %d %i %u %x %ld %lld %lu %f %lf %s %c %n and literals */
int vsscanf(const char *s, const char *f, va_list ap) {
    int count = 0; const char *start = s;
    for (; *f; f++) {
        if (isspace((unsigned char)*f)) { while (isspace((unsigned char)*s)) s++; continue; }
        if (*f != '%') { if (*s != *f) return count; s++; continue; }
        f++;
        int skip = *f == '*'; if (skip) f++;
        int width = 0; while (isdigit((unsigned char)*f)) width = width * 10 + (*f++ - '0');
        int lng = 0; while (*f == 'l' || *f == 'h' || *f == 'z' || *f == 'q') { if (*f == 'l' || *f == 'z' || *f == 'q') lng++; f++; }
        if (*f != 'c' && *f != 'n') while (isspace((unsigned char)*s)) s++;
        char *end;
        switch (*f) {
        case 'd': case 'i': case 'u': case 'x': case 'X': {
            long long v = (*f == 'u' || *f == 'x' || *f == 'X') ? (long long)strtoull(s, &end, *f == 'u' ? 10 : 16) : strtoll(s, &end, *f == 'i' ? 0 : 10);
            if (end == s) return count ? count : -1;
            s = end;
            if (!skip) { if (lng) *va_arg(ap, long long *) = v; else *va_arg(ap, int *) = (int)v; count++; }
            break;
        }
        case 'f': case 'g': case 'e': {
            double v = strtod(s, &end); if (end == s) return count ? count : -1; s = end;
            if (!skip) { if (lng) *va_arg(ap, double *) = v; else *va_arg(ap, float *) = (float)v; count++; }
            break;
        }
        case 's': {
            char *o = skip ? 0 : va_arg(ap, char *); int k = 0;
            while (*s && !isspace((unsigned char)*s) && (!width || k < width)) { if (o) o[k] = *s; k++; s++; }
            if (o) o[k] = 0;
            if (!k) return count ? count : -1;
            if (!skip) count++;
            break;
        }
        case 'c': { if (!*s) return count ? count : -1; if (!skip) { *va_arg(ap, char *) = *s; count++; } s++; break; }
        case 'n': if (!skip) *va_arg(ap, int *) = (int)(s - start); break;
        case '%': if (*s != '%') return count; s++; break;
        }
    }
    return count;
}
/* ponytail: fscanf reads one line and scans it (enough for line-oriented formats) */
int vfscanf(FILE *fp, const char *f, va_list ap) { char line[4096]; if (!fgets(line, sizeof line, fp)) return -1; return vsscanf(line, f, ap); }
int fscanf(FILE *fp, const char *f, ...) { va_list ap; va_start(ap, f); int r = vfscanf(fp, f, ap); va_end(ap); return r; }
int sscanf(const char *s, const char *f, ...) { va_list ap; va_start(ap, f); int r = vsscanf(s, f, ap); va_end(ap); return r; }

/* ---------- _FORTIFY_SOURCE checks (Apple's *_chk entry points) ---------- */
extern void abort(void);
static void chk_fail(void) { fputs("detected buffer overflow\n", __stderrp); abort(); }
#define CHK(n, need) do { if ((need) > (n)) chk_fail(); } while (0)
char *stpcpy(char *d, const char *s) { size_t l = strlen(s); memcpy(d, s, l + 1); return d + l; }
char *stpncpy(char *d, const char *s, size_t n) { size_t l = strnlen(s, n); memcpy(d, s, l); memset(d + l, 0, n - l); return d + l; }
void *memccpy(void *d, const void *s, int c, size_t n) {
    unsigned char *a = d; const unsigned char *b = s;
    for (size_t i = 0; i < n; i++) { a[i] = b[i]; if (b[i] == (unsigned char)c) return a + i + 1; }
    return 0;
}
void *__memcpy_chk(void *d, const void *s, size_t n, size_t dn) { CHK(dn, n); return memcpy(d, s, n); }
void *__memmove_chk(void *d, const void *s, size_t n, size_t dn) { CHK(dn, n); return memmove(d, s, n); }
void *__memset_chk(void *d, int c, size_t n, size_t dn) { CHK(dn, n); return memset(d, c, n); }
void *__memccpy_chk(void *d, const void *s, int c, size_t n, size_t dn) { CHK(dn, n); return memccpy(d, s, c, n); }
char *__strcpy_chk(char *d, const char *s, size_t dn) { CHK(dn, strlen(s) + 1); return strcpy(d, s); }
char *__stpcpy_chk(char *d, const char *s, size_t dn) { CHK(dn, strlen(s) + 1); return stpcpy(d, s); }
char *__strncpy_chk(char *d, const char *s, size_t n, size_t dn) { CHK(dn, n); return strncpy(d, s, n); }
char *__stpncpy_chk(char *d, const char *s, size_t n, size_t dn) { CHK(dn, n); return stpncpy(d, s, n); }
char *__strcat_chk(char *d, const char *s, size_t dn) { CHK(dn, strlen(d) + strlen(s) + 1); return strcat(d, s); }
char *__strncat_chk(char *d, const char *s, size_t n, size_t dn) { size_t l = strnlen(s, n); CHK(dn, strlen(d) + l + 1); return strncat(d, s, n); }
size_t __strlcpy_chk(char *d, const char *s, size_t n, size_t dn) { CHK(dn, n); return strlcpy(d, s, n); }
size_t __strlcat_chk(char *d, const char *s, size_t n, size_t dn) { CHK(dn, n); return strlcat(d, s, n); }
int __vsnprintf_chk(char *b, size_t n, int fl, size_t bn, const char *f, va_list ap) { CHK(bn, n); return vsnprintf(b, n, f, ap); }
int __snprintf_chk(char *b, size_t n, int fl, size_t bn, const char *f, ...) { va_list ap; va_start(ap, f); int r = __vsnprintf_chk(b, n, fl, bn, f, ap); va_end(ap); return r; }
int __vsprintf_chk(char *b, int fl, size_t bn, const char *f, va_list ap) {
    int r = vsnprintf(b, bn, f, ap);
    if (r >= 0 && (size_t)r >= bn) chk_fail();
    return r;
}
int __sprintf_chk(char *b, int fl, size_t bn, const char *f, ...) { va_list ap; va_start(ap, f); int r = __vsprintf_chk(b, fl, bn, f, ap); va_end(ap); return r; }

/* ===================================================================== CommonCrypto: SHA-256 (FIPS 180-4) */
typedef struct { uint32_t count[2], hash[8]; unsigned char buf[64]; } sha256_ctx; /* CC_SHA256_CTX: count = bytes (lo, hi) */
static const uint32_t K256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
static void sha256_block(sha256_ctx *c, const unsigned char *p) {
    uint32_t w[64], a, b, d, e, f, g, h, cc, t1, t2;
    for (int i = 0; i < 16; i++) w[i] = (uint32_t)p[4 * i] << 24 | (uint32_t)p[4 * i + 1] << 16 | (uint32_t)p[4 * i + 2] << 8 | p[4 * i + 3];
    for (int i = 16; i < 64; i++) w[i] = (ROR(w[i - 2], 17) ^ ROR(w[i - 2], 19) ^ (w[i - 2] >> 10)) + w[i - 7] + (ROR(w[i - 15], 7) ^ ROR(w[i - 15], 18) ^ (w[i - 15] >> 3)) + w[i - 16];
    a = c->hash[0]; b = c->hash[1]; cc = c->hash[2]; d = c->hash[3]; e = c->hash[4]; f = c->hash[5]; g = c->hash[6]; h = c->hash[7];
    for (int i = 0; i < 64; i++) {
        t1 = h + (ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25)) + ((e & f) ^ (~e & g)) + K256[i] + w[i];
        t2 = (ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22)) + ((a & b) ^ (a & cc) ^ (b & cc));
        h = g; g = f; f = e; e = d + t1; d = cc; cc = b; b = a; a = t1 + t2;
    }
    c->hash[0] += a; c->hash[1] += b; c->hash[2] += cc; c->hash[3] += d; c->hash[4] += e; c->hash[5] += f; c->hash[6] += g; c->hash[7] += h;
}
int CC_SHA256_Init(sha256_ctx *c) {
    static const uint32_t iv[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    memset(c, 0, sizeof *c); memcpy(c->hash, iv, sizeof iv); return 1;
}
int CC_SHA256_Update(sha256_ctx *c, const void *data, uint32_t len) {
    const unsigned char *p = data;
    uint64_t n = (uint64_t)c->count[1] << 32 | c->count[0];
    size_t have = (size_t)(n % 64);
    n += len; c->count[0] = (uint32_t)n; c->count[1] = (uint32_t)(n >> 32);
    while (len) {
        size_t k = 64 - have < len ? 64 - have : len;
        memcpy(c->buf + have, p, k); have += k; p += k; len -= (uint32_t)k;
        if (have == 64) { sha256_block(c, c->buf); have = 0; }
    }
    return 1;
}
int CC_SHA256_Final(unsigned char *md, sha256_ctx *c) {
    uint64_t bits = ((uint64_t)c->count[1] << 32 | c->count[0]) * 8;
    unsigned char pad[72] = {0x80};
    size_t have = (size_t)(bits / 8 % 64), padlen = have < 56 ? 56 - have : 120 - have;
    CC_SHA256_Update(c, pad, (uint32_t)padlen);
    unsigned char len[8]; for (int i = 0; i < 8; i++) len[i] = (unsigned char)(bits >> (56 - 8 * i));
    CC_SHA256_Update(c, len, 8);
    for (int i = 0; i < 8; i++) { md[4 * i] = (unsigned char)(c->hash[i] >> 24); md[4 * i + 1] = (unsigned char)(c->hash[i] >> 16); md[4 * i + 2] = (unsigned char)(c->hash[i] >> 8); md[4 * i + 3] = (unsigned char)c->hash[i]; }
    return 1;
}
unsigned char *CC_SHA256(const void *data, uint32_t len, unsigned char *md) { sha256_ctx c; CC_SHA256_Init(&c); CC_SHA256_Update(&c, data, len); CC_SHA256_Final(md, &c); return md; }
