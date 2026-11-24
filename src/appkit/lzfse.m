/* lzfse.m — an LZFSE decoder (Apple's compressor, used inside compiled asset catalogs), written from the format:
 * blocks "bvx2" (FSE-coded literals and L/M/D triples, compressed header), "bvx-" (raw) and "bvx$" (end).
 * ponytail: "bvx1" and LZVN ("bvxn") blocks are not decoded; catalogs from Xcode use bvx2. */
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

size_t mw_lzfse_decode(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size);

enum { L_SYMS = 20, M_SYMS = 20, D_SYMS = 64, LIT_SYMS = 256, L_STATES = 64, M_STATES = 64, D_STATES = 256, LIT_STATES = 1024 };

static const uint8_t l_bits[L_SYMS] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,5,8};
static const int32_t l_base[L_SYMS] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,20,28,60};
static const uint8_t m_bits[M_SYMS] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,5,8,11};
static const int32_t m_base[M_SYMS] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,24,56,312};
static const uint8_t d_bits[D_SYMS] = {0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,6,6,6,6,7,7,7,7,8,8,8,8,9,9,9,9,
                                      10,10,10,10,11,11,11,11,12,12,12,12,13,13,13,13,14,14,14,14,15,15,15,15};
static const int32_t d_base[D_SYMS] = {0,1,2,3,4,6,8,10,12,16,20,24,28,36,44,52,60,76,92,108,124,156,188,220,252,316,380,444,
    508,636,764,892,1020,1276,1532,1788,2044,2556,3068,3580,4092,5116,6140,7164,8188,10236,12284,14332,16380,20476,24572,
    28668,32764,40956,49148,57340,65532,81916,98300,114684,131068,163836,196604,229372};

typedef struct { uint8_t k, sym; int16_t delta; } LitEntry;
typedef struct { uint8_t total, vbits; int16_t delta; int32_t vbase; } ValEntry;
typedef struct { uint64_t accum; int nbits; } BitIn;

static uint64_t ld64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }
static uint64_t lsb(uint64_t x, int n) { return n >= 64 ? x : n <= 0 ? 0 : x & ((1ull << n) - 1); }

/* the payloads are read backwards, from their end */
static int in_init(BitIn *in, int nbits, const uint8_t **p, const uint8_t *start) {
    if (nbits) { if (*p - 8 < start) return -1; *p -= 8; in->accum = ld64(*p); in->nbits = nbits + 64; }
    else { if (*p - 7 < start) return -1; *p -= 7; in->accum = ld64(*p) & 0xffffffffffffffull; in->nbits = 56; }
    if (in->nbits < 56 || in->nbits >= 64 || (in->accum >> in->nbits)) return -1;
    return 0;
}
/* may read bytes before the payload (the header): they fill bits that are never pulled; start is the block's start */
static int in_flush(BitIn *in, const uint8_t **p, const uint8_t *start) {
    int n = (63 - in->nbits) & -8;
    const uint8_t *q = *p - (n >> 3);
    if (q < start) return -1;
    *p = q;
    in->accum = (in->accum << n) | lsb(ld64(q), n);
    in->nbits += n;
    return 0;
}
static uint64_t in_pull(BitIn *in, int n) {
    in->nbits -= n;
    uint64_t r = in->accum >> in->nbits;
    in->accum = lsb(in->accum, in->nbits);
    return r;
}

static int init_lit(int nstates, int nsyms, const uint16_t *freq, LitEntry *t) {
    int nclz = __builtin_clz((unsigned)nstates), sum = 0, pos = 0;
    for (int i = 0; i < nsyms; i++) {
        int f = freq[i];
        if (!f) continue;
        if ((sum += f) > nstates) return -1;
        int k = __builtin_clz((unsigned)f) - nclz, j0 = ((2 * nstates) >> k) - f;
        for (int j = 0; j < f; j++, pos++) {
            t[pos].sym = (uint8_t)i;
            if (j < j0) { t[pos].k = (uint8_t)k; t[pos].delta = (int16_t)(((f + j) << k) - nstates); }
            else { t[pos].k = (uint8_t)(k - 1); t[pos].delta = (int16_t)((j - j0) << (k - 1)); }
        }
    }
    return 0;
}
static int init_val(int nstates, int nsyms, const uint16_t *freq, const uint8_t *vbits, const int32_t *vbase, ValEntry *t) {
    int nclz = __builtin_clz((unsigned)nstates), sum = 0, pos = 0;
    for (int i = 0; i < nsyms; i++) {
        int f = freq[i];
        if (!f) continue;
        if ((sum += f) > nstates) return -1;
        int k = __builtin_clz((unsigned)f) - nclz, j0 = ((2 * nstates) >> k) - f;
        for (int j = 0; j < f; j++, pos++) {
            t[pos].vbits = vbits[i]; t[pos].vbase = vbase[i];
            if (j < j0) { t[pos].total = (uint8_t)(k + vbits[i]); t[pos].delta = (int16_t)(((f + j) << k) - nstates); }
            else { t[pos].total = (uint8_t)(k - 1 + vbits[i]); t[pos].delta = (int16_t)((j - j0) << (k - 1)); }
        }
    }
    return 0;
}
static int32_t val_decode(int *state, const ValEntry *t, BitIn *in) {
    ValEntry e = t[*state];
    uint64_t sv = in_pull(in, e.total);
    *state = e.delta + (int)(sv >> e.vbits);
    return e.vbase + (int32_t)lsb(sv, e.vbits);
}
static uint32_t field(uint64_t v, int off, int n) { return (uint32_t)((v >> off) & ((1ull << n) - 1)); }
static int freq_value(uint32_t bits, int *nbits) {
    static const int8_t nb[32] = {2,3,2,5,2,3,2,8,2,3,2,5,2,3,2,14,2,3,2,5,2,3,2,8,2,3,2,5,2,3,2,14};
    static const int8_t val[32] = {0,2,1,4,0,3,1,-1,0,2,1,5,0,3,1,-1,0,2,1,6,0,3,1,-1,0,2,1,7,0,3,1,-1};
    uint32_t b = bits & 31;
    *nbits = nb[b];
    if (nb[b] == 8) return 8 + (int)((bits >> 4) & 0xf);
    if (nb[b] == 14) return 24 + (int)((bits >> 4) & 0x3ff);
    return val[b];
}

/* one bvx2 block: src points after the magic; returns the bytes it used, or 0 */
static size_t block_v2(const uint8_t *src, const uint8_t *end, uint8_t *dst, uint8_t *dst_start, uint8_t *dst_end, uint8_t **out) {
    if (end - src < 28) return 0;
    uint32_t n_raw; uint64_t v0, v1, v2;
    memcpy(&n_raw, src, 4); memcpy(&v0, src + 4, 8); memcpy(&v1, src + 12, 8); memcpy(&v2, src + 20, 8);
    uint32_t n_lit = field(v0, 0, 20), n_lit_bytes = field(v0, 20, 20), n_matches = field(v0, 40, 20);
    int lit_bits = (int)field(v0, 60, 3) - 7;
    int lit_state[4] = {(int)field(v1, 0, 10), (int)field(v1, 10, 10), (int)field(v1, 20, 10), (int)field(v1, 30, 10)};
    uint32_t n_lmd_bytes = field(v1, 40, 20);
    int lmd_bits = (int)field(v1, 60, 3) - 7;
    uint32_t hsize = field(v2, 0, 32);
    int ls = (int)field(v2, 32, 10), ms = (int)field(v2, 42, 10), ds = (int)field(v2, 52, 10);
    const uint8_t *h = src - 4;   /* the header counts from the magic */
    if (hsize < 32 || h + hsize > end || n_lit > 0x100000 || (size_t)(dst_end - dst) < n_raw) return 0;
    /* frequency tables: L, M, D, literals, variable-length coded */
    uint16_t freq[L_SYMS + M_SYMS + D_SYMS + LIT_SYMS];
    const uint8_t *fp = h + 32, *fe = h + hsize;
    uint32_t acc = 0; int accn = 0;
    for (int i = 0; i < L_SYMS + M_SYMS + D_SYMS + LIT_SYMS; i++) {
        while (fp < fe && accn + 8 <= 32) { acc |= (uint32_t)*fp++ << accn; accn += 8; }
        int nb; int f = freq_value(acc, &nb);
        if (nb > accn) return 0;
        acc >>= nb; accn -= nb;
        freq[i] = (uint16_t)f;
    }
    static LitEntry lit_t[LIT_STATES]; static ValEntry l_t[L_STATES], m_t[M_STATES], d_t[D_STATES];
    if (init_val(L_STATES, L_SYMS, freq, l_bits, l_base, l_t) || init_val(M_STATES, M_SYMS, freq + L_SYMS, m_bits, m_base, m_t) ||
        init_val(D_STATES, D_SYMS, freq + L_SYMS + M_SYMS, d_bits, d_base, d_t) ||
        init_lit(LIT_STATES, LIT_SYMS, freq + L_SYMS + M_SYMS + D_SYMS, lit_t)) return 0;
    /* literals */
    const uint8_t *lp = fe, *lend = fe + n_lit_bytes;
    if (lend + n_lmd_bytes > end) return 0;
    uint8_t *lits = malloc(n_lit + 64);
    if (!lits) return 0;
    BitIn in; const uint8_t *p = lend;
    if (in_init(&in, lit_bits, &p, lp)) { free(lits); return 0; }
    for (uint32_t i = 0; i < n_lit; i += 4) {
        if (in_flush(&in, &p, h)) { free(lits); return 0; }
        for (int s = 0; s < 4; s++) {
            LitEntry e = lit_t[lit_state[s]];
            lit_state[s] = e.delta + (int)in_pull(&in, e.k);
            lits[i + s] = e.sym;
        }
    }
    /* L, M, D: copy L literals, then M bytes from D back */
    const uint8_t *mp = lend, *mend = lend + n_lmd_bytes;
    p = mend;
    if (in_init(&in, lmd_bits, &p, mp)) { free(lits); return 0; }
    const uint8_t *lit = lits;
    int32_t D = 0;
    uint8_t *d = dst, *dlim = dst + n_raw;
    for (uint32_t i = 0; i < n_matches; i++) {
        if (in_flush(&in, &p, h)) { free(lits); return 0; }
        int32_t L = val_decode(&ls, l_t, &in), M = val_decode(&ms, m_t, &in), nd = val_decode(&ds, d_t, &in);
        if (nd) D = nd;
        if (L < 0 || M < 0 || d + L + M > dlim || lit + L > lits + n_lit || (M && (D <= 0 || d + L - D < dst_start))) { free(lits); return 0; }
        memcpy(d, lit, (size_t)L); d += L; lit += L;
        for (int32_t k = 0; k < M; k++, d++) *d = d[-D];
    }
    free(lits);
    *out = d;
    return (size_t)(mend - h);
}

size_t mw_lzfse_decode(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size) {
    const uint8_t *p = src, *end = src + src_size;
    uint8_t *d = dst, *dend = dst + dst_size;
    while (end - p >= 4) {
        uint32_t magic; memcpy(&magic, p, 4);
        if (magic == 0x24787662) return (size_t)(d - dst);                     /* bvx$ */
        if (magic == 0x2d787662) {                                              /* bvx- */
            uint32_t n; if (end - p < 8) return 0;
            memcpy(&n, p + 4, 4);
            if ((size_t)(end - p - 8) < n || (size_t)(dend - d) < n) return 0;
            memcpy(d, p + 8, n); d += n; p += 8 + n;
        } else if (magic == 0x32787662) {                                       /* bvx2 */
            uint8_t *nd = d;
            size_t used = block_v2(p + 4, end, d, dst, dend, &nd);
            if (!used) return 0;
            d = nd; p += used;
        } else return 0;
    }
    return (size_t)(d - dst);
}
