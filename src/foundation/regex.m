/* regex.m — scion Foundation: NSRegularExpression / NSTextCheckingResult on a small backtracking engine (MRC).
 * ICU syntax subset: . [] [^] ranges \d\w\s\D\W\S \p{L,Lu,Ll,N,Nd,P,S,Z} \b\B \A\z\Z ^ $ | () (?:) (?<name>) (?=) (?!)
 * (?<=) (?<!) (?>) (?imsx-imsx) (?i:...) * + ? {n,m} lazy (?) and possessive (+) quantifiers, \1 \k<name>, \Q..\E,
 * \x{..} \uhhhh \t\n\r\f\e\0. Matching works on UTF-16 indices and decodes surrogate pairs as one code point.
 * ponytail: \p{} classes are approximations (ASCII/Latin-1 exact, others by coarse ranges); lookbehind looks at most
 * 255 units back; no class set operations ([a-z&&[^aeiou]]). */
#import "internal.h"

enum { O_CHAR, O_ANY, O_CLASS, O_SPLIT, O_JMP, O_SAVE, O_BOL, O_EOL, O_SBEG, O_SEND, O_SENDNL, O_WORDB, O_NWORDB,
       O_BACKREF, O_LOOK, O_ATOMIC, O_MARK, O_CHECK, O_MATCH };
enum { F_I = 1, F_M = 2, F_S = 4, F_X = 8, F_UNIX = 16 };          /* per-instruction flags */
typedef struct { uint8_t op, fl; int a, b; } Ins;                  /* jumps (a, b) are relative to the instruction */
enum { P_DIGIT = 1, P_WORD, P_SPACE, P_L, P_LU, P_LL, P_N, P_P, P_S, P_Z, P_ANY };
typedef struct { uint32_t lo, hi; } Rng;
typedef struct { Rng *r; int nr; int props[16][2]; int np; int neg; } CSet;

typedef struct {
    Ins *code; int n, cap;
    CSet *sets; int nsets;
    int ngroups, nregs;
    char **names; int *name_idx; int nnames;
    /* parser state */
    const unichar *p; NSUInteger pl, pi; int flags; const char *err;
} Prog;

static uint32_t fold(uint32_t c) {
    if (c >= 'A' && c <= 'Z') return c + 32;
    if ((c >= 0xC0 && c <= 0xDE && c != 0xD7) || (c >= 0x391 && c <= 0x3A9) || (c >= 0x410 && c <= 0x42F)) return c + 32;
    if (c >= 0x400 && c <= 0x40F) return c + 80;
    return c;
}
static int is_line_term(uint32_t c, int unix_only) { return c == '\n' || (!unix_only && (c == '\r' || c == 0x85 || c == 0x2028 || c == 0x2029 || c == 0x0B || c == 0x0C)); }
static int prop(int p, uint32_t c) {
    switch (p) {
    case P_DIGIT: case P_N: return (c >= '0' && c <= '9') || (c >= 0x660 && c <= 0x669) || (c >= 0xFF10 && c <= 0xFF19) || (p == P_N && (c == 0xB2 || c == 0xB3 || c == 0xB9 || (c >= 0xBC && c <= 0xBE)));
    case P_SPACE: case P_Z: return c == ' ' || (p == P_SPACE && c >= '\t' && c <= '\r') || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000 || (p == P_SPACE && c == 0x85);
    case P_LU: return (c >= 'A' && c <= 'Z') || (c >= 0xC0 && c <= 0xDE && c != 0xD7) || (c >= 0x391 && c <= 0x3A9) || (c >= 0x400 && c <= 0x42F);
    case P_LL: return (c >= 'a' && c <= 'z') || (c >= 0xDF && c <= 0xFF && c != 0xF7) || (c >= 0x3B1 && c <= 0x3C9) || (c >= 0x430 && c <= 0x45F);
    case P_L: return prop(P_LU, c) || prop(P_LL, c) || c == 0xAA || c == 0xBA || (c >= 0x100 && c <= 0x24F) || (c >= 0x370 && c <= 0x52F && !prop(P_N, c))
                   || (c >= 0x5D0 && c <= 0x5EA) || (c >= 0x620 && c <= 0x64A) || (c >= 0x900 && c <= 0x0DFF) || (c >= 0x1E00 && c <= 0x1FFF)
                   || (c >= 0x3040 && c <= 0x30FF) || (c >= 0x3400 && c <= 0x9FFF) || (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0xF900 && c <= 0xFAFF) || c >= 0x20000;
    case P_WORD: return prop(P_L, c) || prop(P_DIGIT, c) || c == '_' || c == 0x200C || c == 0x200D;
    case P_P: return (c < 128 && strchr("!\"#%&'()*,-./:;?@[\\]_{}", (int)c) && c) || c == 0xA1 || c == 0xA7 || c == 0xAB || c == 0xB6 || c == 0xB7 || c == 0xBB || c == 0xBF || (c >= 0x2010 && c <= 0x2027) || (c >= 0x3001 && c <= 0x3003);
    case P_S: return (c < 128 && strchr("$+<=>^`|~", (int)c) && c) || c == 0xA2 || c == 0xA3 || c == 0xA4 || c == 0xA5 || c == 0xA6 || c == 0xA8 || c == 0xA9 || c == 0xAC || c == 0xAE || c == 0xAF || c == 0xB0 || c == 0xB1 || c == 0xB4 || c == 0xD7 || c == 0xF7 || (c >= 0x20A0 && c <= 0x20CF) || (c >= 0x2190 && c <= 0x21FF) || (c >= 0x2200 && c <= 0x22FF) || (c >= 0x1F300 && c <= 0x1FAFF);
    case P_ANY: return 1;
    }
    return 0;
}
static int set_has(const CSet *s, uint32_t c, int icase) {
    int m = 0;
    for (int k = 0; k < 2 && !m; k++) {
        uint32_t x = k == 0 ? c : (fold(c) != c ? fold(c) : (c >= 'a' && c <= 'z') ? c - 32 : (prop(P_LL, c) && c >= 0xE0 && c <= 0xFE) ? c - 32 : (c >= 0x3B1 && c <= 0x3C9) || (c >= 0x430 && c <= 0x44F) ? c - 32 : (c >= 0x450 && c <= 0x45F) ? c - 80 : c);
        if (k == 1 && (!icase || x == c)) break;
        for (int i = 0; i < s->nr && !m; i++) m = x >= s->r[i].lo && x <= s->r[i].hi;
        for (int i = 0; i < s->np && !m; i++) m = prop(s->props[i][0], x) != s->props[i][1];
    }
    return s->neg ? !m : m;
}

/* ------------------------------------------------------------------ compiler */
static int emit(Prog *g, int op, int fl, int a, int b) {
    if (g->n == g->cap) { g->cap = g->cap * 2 + 64; g->code = realloc(g->code, g->cap * sizeof(Ins)); }
    g->code[g->n] = (Ins){(uint8_t)op, (uint8_t)fl, a, b};
    return g->n++;
}
static int more(Prog *g) { return g->pi < g->pl; }
static uint32_t peek(Prog *g) { return more(g) ? g->p[g->pi] : 0; }
static uint32_t next_cp(Prog *g) {
    uint32_t c = g->p[g->pi++];
    if (c >= 0xD800 && c < 0xDC00 && more(g) && g->p[g->pi] >= 0xDC00 && g->p[g->pi] < 0xE000) c = 0x10000 + ((c - 0xD800) << 10) + (g->p[g->pi++] - 0xDC00);
    return c;
}
static void skip_x(Prog *g) {
    if (!(g->flags & F_X)) return;
    for (;;) {
        while (more(g) && (peek(g) == ' ' || (peek(g) >= '\t' && peek(g) <= '\r'))) g->pi++;
        if (more(g) && peek(g) == '#') { while (more(g) && peek(g) != '\n') g->pi++; continue; }
        break;
    }
}
static int hexval(uint32_t c) { return c >= '0' && c <= '9' ? (int)(c - '0') : (c | 32) >= 'a' && (c | 32) <= 'f' ? (int)((c | 32) - 'a' + 10) : -1; }
static uint32_t parse_hex(Prog *g, int maxd) {
    uint32_t v = 0; int d = 0;
    if (maxd == 0) { /* \x{...} */
        while (more(g) && peek(g) != '}') { int h = hexval(next_cp(g)); if (h < 0) { g->err = "bad hex"; return 0; } v = v * 16 + (uint32_t)h; }
        if (!more(g)) { g->err = "unterminated \\x{"; return 0; }
        g->pi++; return v;
    }
    while (d < maxd && more(g) && hexval(peek(g)) >= 0) { v = v * 16 + (uint32_t)hexval(next_cp(g)); d++; }
    if (!d) g->err = "bad hex escape";
    return v;
}
/* \p{Name}: returns a property id, or 0 */
static int parse_prop(Prog *g) {
    char name[32]; int k = 0;
    if (peek(g) == '{') { g->pi++; while (more(g) && peek(g) != '}' && k < 31) name[k++] = (char)next_cp(g); g->pi++; }
    else if (more(g)) name[k++] = (char)next_cp(g);
    name[k] = 0;
    const char *n = name; if (!strncmp(n, "Is", 2)) n += 2;
    if (!strcmp(n, "L") || !strcasecmp(n, "Letter") || !strcasecmp(n, "Alphabetic") || !strcasecmp(n, "Alpha")) return P_L;
    if (!strcmp(n, "Lu") || !strcasecmp(n, "Uppercase") || !strcasecmp(n, "Upper")) return P_LU;
    if (!strcmp(n, "Ll") || !strcasecmp(n, "Lowercase") || !strcasecmp(n, "Lower")) return P_LL;
    if (!strcmp(n, "N") || !strcmp(n, "Nd") || !strcasecmp(n, "Digit")) return P_N;
    if (!strcmp(n, "P") || !strcasecmp(n, "Punct") || !strcasecmp(n, "Punctuation")) return P_P;
    if (!strcmp(n, "S") || !strcmp(n, "Sm") || !strcmp(n, "Sc")) return P_S;
    if (!strcmp(n, "Z") || !strcmp(n, "Zs") || !strcasecmp(n, "White_Space") || !strcasecmp(n, "Space")) return P_SPACE;
    if (!strcasecmp(n, "Any") || !strcasecmp(n, "Assigned")) return P_ANY;
    g->err = "unknown \\p{} property";
    return 0;
}
/* escape inside or outside a class. Returns 1 and sets *cp for a literal, 2 and sets pp and pneg for a property class. */
static int parse_escape(Prog *g, uint32_t *cp, int *pp, int *pneg) {
    if (!more(g)) { g->err = "trailing backslash"; return 0; }
    uint32_t c = next_cp(g);
    *pneg = 0;
    switch (c) {
    case 'd': *pp = P_DIGIT; return 2;  case 'D': *pp = P_DIGIT; *pneg = 1; return 2;
    case 'w': *pp = P_WORD; return 2;   case 'W': *pp = P_WORD; *pneg = 1; return 2;
    case 's': *pp = P_SPACE; return 2;  case 'S': *pp = P_SPACE; *pneg = 1; return 2;
    case 'h': *pp = P_Z; return 2;      case 'H': *pp = P_Z; *pneg = 1; return 2;
    case 'p': *pp = parse_prop(g); return g->err ? 0 : 2;
    case 'P': *pp = parse_prop(g); *pneg = 1; return g->err ? 0 : 2;
    case 'n': *cp = '\n'; return 1;  case 't': *cp = '\t'; return 1;  case 'r': *cp = '\r'; return 1;
    case 'f': *cp = '\f'; return 1;  case 'e': *cp = 0x1B; return 1;  case 'a': *cp = 7; return 1;
    case '0': { uint32_t v = 0; int d = 0; while (d < 3 && peek(g) >= '0' && peek(g) <= '7') { v = v * 8 + (next_cp(g) - '0'); d++; } *cp = v; return 1; }
    case 'x': if (peek(g) == '{') { g->pi++; *cp = parse_hex(g, 0); } else *cp = parse_hex(g, 2); return g->err ? 0 : 1;
    case 'u': *cp = parse_hex(g, 4); return g->err ? 0 : 1;
    case 'U': *cp = parse_hex(g, 8); return g->err ? 0 : 1;
    case 'c': *cp = next_cp(g) & 0x1F; return 1;
    }
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) { g->err = "unknown escape"; return 0; }
    *cp = c; return 1;
}
static int new_set(Prog *g) {
    g->sets = realloc(g->sets, (g->nsets + 1) * sizeof(CSet));
    memset(&g->sets[g->nsets], 0, sizeof(CSet));
    return g->nsets++;
}
static void set_range(CSet *s, uint32_t lo, uint32_t hi) { s->r = realloc(s->r, (s->nr + 1) * sizeof(Rng)); s->r[s->nr++] = (Rng){lo, hi}; }
static void set_prop(CSet *s, int p, int neg) { if (s->np < 16) { s->props[s->np][0] = p; s->props[s->np][1] = neg; s->np++; } }
static void parse_class(Prog *g) {
    int si = new_set(g);
    if (peek(g) == '^') { g->sets[si].neg = 1; g->pi++; }
    int first = 1;
    while (more(g) && (peek(g) != ']' || first)) {
        first = 0;
        uint32_t lo; int pp, pneg;
        if (peek(g) == '[' && g->pi + 1 < g->pl && g->p[g->pi + 1] == ':') { /* [:alpha:] */
            NSUInteger e = g->pi + 2; while (e < g->pl && g->p[e] != ':') e++;
            char nm[16] = {0}; int neg = g->p[g->pi + 2] == '^'; int k = 0;
            for (NSUInteger i = g->pi + 2 + neg; i < e && k < 15; i++) nm[k++] = (char)g->p[i];
            g->pi = e + 2;
            int p = !strcmp(nm, "alpha") ? P_L : !strcmp(nm, "digit") ? P_DIGIT : !strcmp(nm, "alnum") ? P_WORD : !strcmp(nm, "space") ? P_SPACE
                  : !strcmp(nm, "upper") ? P_LU : !strcmp(nm, "lower") ? P_LL : !strcmp(nm, "punct") ? P_P : 0;
            if (!strcmp(nm, "xdigit")) { set_range(&g->sets[si], '0', '9'); set_range(&g->sets[si], 'a', 'f'); set_range(&g->sets[si], 'A', 'F'); continue; }
            if (!p) { g->err = "unknown POSIX class"; return; }
            set_prop(&g->sets[si], p, neg); continue;
        }
        if (peek(g) == '\\') {
            g->pi++;
            int r = parse_escape(g, &lo, &pp, &pneg);
            if (!r) return;
            if (r == 2) { set_prop(&g->sets[si], pp, pneg); continue; }
        } else lo = next_cp(g);
        uint32_t hi = lo;
        if (peek(g) == '-' && g->pi + 1 < g->pl && g->p[g->pi + 1] != ']') {
            g->pi++;
            if (peek(g) == '\\') { g->pi++; int r = parse_escape(g, &hi, &pp, &pneg); if (r != 1) { if (!g->err) g->err = "bad range"; return; } }
            else hi = next_cp(g);
            if (hi < lo) { g->err = "bad range order"; return; }
        }
        set_range(&g->sets[si], lo, hi);
    }
    if (!more(g)) { g->err = "missing ]"; return; }
    g->pi++;
    emit(g, O_CLASS, g->flags, si, 0);
}

static void parse_alt(Prog *g);
static int group_by_name(Prog *g, const char *n) { for (int i = 0; i < g->nnames; i++) if (!strcmp(g->names[i], n)) return g->name_idx[i]; return -1; }
static int parse_flags(Prog *g, int *fl) { /* after "(?": reads imsxw-imsx, returns terminator */
    int on = 1;
    while (more(g)) {
        uint32_t c = peek(g);
        if (c == '-') on = 0;
        else if (c == 'i' || c == 'm' || c == 's' || c == 'x' || c == 'w') {
            int b = c == 'i' ? F_I : c == 'm' ? F_M : c == 's' ? F_S : c == 'x' ? F_X : 0;
            *fl = on ? (*fl | b) : (*fl & ~b);
        } else return (int)c;
        g->pi++;
    }
    return 0;
}
/* parses one atom; returns 0 if there is none here (end of alternative) */
static int parse_atom(Prog *g) {
    skip_x(g);
    if (!more(g)) return 0;
    uint32_t c = peek(g);
    if (c == '|' || c == ')') return 0;
    g->pi++;
    switch (c) {
    case '.': emit(g, O_ANY, g->flags, 0, 0); return 1;
    case '^': emit(g, O_BOL, g->flags, 0, 0); return 1;
    case '$': emit(g, O_EOL, g->flags, 0, 0); return 1;
    case '[': parse_class(g); return 1;
    case '*': case '+': case '?': g->err = "quantifier without operand"; return 0;
    case '{': if (more(g) && peek(g) >= '0' && peek(g) <= '9') { g->err = "quantifier without operand"; return 0; } emit(g, O_CHAR, g->flags, '{', 0); return 1;
    case '\\': {
        if (!more(g)) { g->err = "trailing backslash"; return 0; }
        uint32_t e = peek(g);
        switch (e) {
        case 'b': g->pi++; emit(g, O_WORDB, g->flags, 0, 0); return 1;
        case 'B': g->pi++; emit(g, O_NWORDB, g->flags, 0, 0); return 1;
        case 'A': g->pi++; emit(g, O_SBEG, g->flags, 0, 0); return 1;
        case 'z': g->pi++; emit(g, O_SEND, g->flags, 0, 0); return 1;
        case 'Z': g->pi++; emit(g, O_SENDNL, g->flags, 0, 0); return 1;
        case 'G': g->pi++; emit(g, O_SBEG, g->flags, 0, 0); return 1; /* ponytail: \G as start of search */
        case 'Q': {
            g->pi++;
            int n0 = g->n, cnt = 0;
            while (more(g) && !(peek(g) == '\\' && g->pi + 1 < g->pl && g->p[g->pi + 1] == 'E')) { emit(g, O_CHAR, g->flags, (int)next_cp(g), 0); cnt++; }
            if (more(g)) g->pi += 2;
            if (!cnt) return parse_atom(g);
            (void)n0; return 1; /* ponytail: a quantifier after \Q..\E applies to the whole literal */
        }
        case 'k': {
            g->pi++;
            if (peek(g) != '<') { g->err = "bad \\k"; return 0; }
            g->pi++; char nm[64]; int k = 0;
            while (more(g) && peek(g) != '>' && k < 63) nm[k++] = (char)next_cp(g);
            nm[k] = 0; g->pi++;
            int gi = group_by_name(g, nm);
            if (gi < 0) { g->err = "unknown group name"; return 0; }
            emit(g, O_BACKREF, g->flags, gi, 0); return 1;
        }
        }
        if (e >= '1' && e <= '9') {
            int v = 0;
            while (more(g) && peek(g) >= '0' && peek(g) <= '9' && v * 10 + (int)(peek(g) - '0') <= (g->ngroups > 9 ? g->ngroups : 9)) v = v * 10 + (int)(next_cp(g) - '0');
            emit(g, O_BACKREF, g->flags, v, 0); return 1;
        }
        uint32_t cp; int pp, pneg;
        int r = parse_escape(g, &cp, &pp, &pneg);
        if (!r) return 0;
        if (r == 2) { int si = new_set(g); set_prop(&g->sets[si], pp, pneg); emit(g, O_CLASS, g->flags, si, 0); }
        else emit(g, O_CHAR, g->flags, (int)cp, 0);
        return 1;
    }
    case '(': {
        int saved = g->flags;
        if (peek(g) == '?') {
            g->pi++;
            uint32_t k = peek(g);
            if (k == ':') { g->pi++; parse_alt(g); }
            else if (k == '=' || k == '!' || (k == '<' && g->pi + 1 < g->pl && (g->p[g->pi + 1] == '=' || g->p[g->pi + 1] == '!'))) {
                int behind = k == '<'; if (behind) g->pi++;
                int neg = peek(g) == '!'; g->pi++;
                int at = emit(g, O_LOOK, (neg ? 1 : 0) | (behind ? 2 : 0), 0, 0);
                parse_alt(g);
                emit(g, O_MATCH, 0, 0, 0);
                g->code[at].a = g->n - at;   /* skip over the sub-program */
            } else if (k == '>') {
                g->pi++;
                int at = emit(g, O_ATOMIC, 0, 0, 0);
                parse_alt(g);
                emit(g, O_MATCH, 0, 0, 0);
                g->code[at].a = g->n - at;
            } else if (k == '<' || k == 'P' || k == '\'') { /* named group */
                if (k == 'P') g->pi++;
                uint32_t close = peek(g) == '\'' ? '\'' : '>'; g->pi++;
                char nm[64]; int n = 0;
                while (more(g) && peek(g) != close && n < 63) nm[n++] = (char)next_cp(g);
                nm[n] = 0; g->pi++;
                int gi = ++g->ngroups;
                g->names = realloc(g->names, (g->nnames + 1) * sizeof(char *)); g->name_idx = realloc(g->name_idx, (g->nnames + 1) * sizeof(int));
                g->names[g->nnames] = strdup(nm); g->name_idx[g->nnames++] = gi;
                emit(g, O_SAVE, 0, 2 * gi, 0); parse_alt(g); emit(g, O_SAVE, 0, 2 * gi + 1, 0);
            } else if (k == '#') { /* comment */
                while (more(g) && peek(g) != ')') g->pi++;
                g->pi++; return parse_atom(g);
            } else {
                int fl = g->flags, t = parse_flags(g, &fl);
                if (t == ')') { g->pi++; g->flags = fl; return parse_atom(g); }   /* (?i) applies to the rest of the group */
                if (t != ':') { g->err = "bad group syntax"; return 0; }
                g->pi++; g->flags = fl; parse_alt(g);
            }
        } else {
            int gi = ++g->ngroups;
            emit(g, O_SAVE, 0, 2 * gi, 0); parse_alt(g); emit(g, O_SAVE, 0, 2 * gi + 1, 0);
        }
        g->flags = saved;
        if (g->err) return 0;
        if (peek(g) != ')') { g->err = "missing )"; return 0; }
        g->pi++;
        return 1;
    }
    }
    if (c == ')') { g->err = "unbalanced )"; return 0; }
    g->pi--;
    emit(g, O_CHAR, g->flags, (int)next_cp(g), 0);
    return 1;
}
/* applies a quantifier to the code emitted since `start` */
static void quantify(Prog *g, int start, int mn, int mx, int mode /* 0 greedy, 1 lazy, 2 possessive */) {
    int len = g->n - start;
    if ((long)len * (mx < 0 ? mn + 1 : mx) > 200000) { g->err = "repetition too large"; return; }
    Ins *atom = malloc(len * sizeof(Ins)); memcpy(atom, g->code + start, len * sizeof(Ins));
    g->n = start;
    int at_atomic = -1;
    if (mode == 2) at_atomic = emit(g, O_ATOMIC, 0, 0, 0);
    for (int i = 0; i < mn; i++) for (int k = 0; k < len; k++) emit(g, atom[k].op, atom[k].fl, atom[k].a, atom[k].b);
    if (mx < 0) {
        int reg = g->nregs++;
        int loop = emit(g, O_SPLIT, 0, 0, 0);
        emit(g, O_MARK, 0, reg, 0);
        for (int k = 0; k < len; k++) emit(g, atom[k].op, atom[k].fl, atom[k].a, atom[k].b);
        int chk = emit(g, O_CHECK, 0, reg, 0);
        int j = emit(g, O_JMP, 0, 0, 0);
        g->code[j].a = loop - j;
        int out = g->n - loop;
        g->code[chk].b = g->n - chk;
        g->code[loop].a = mode == 1 ? out : 1; g->code[loop].b = mode == 1 ? 1 : out;
    } else {
        int *splits = malloc(sizeof(int) * (mx - mn + 1)); int ns = 0;
        for (int i = mn; i < mx; i++) {
            splits[ns++] = emit(g, O_SPLIT, 0, 0, 0);
            for (int k = 0; k < len; k++) emit(g, atom[k].op, atom[k].fl, atom[k].a, atom[k].b);
        }
        for (int i = 0; i < ns; i++) { int s = splits[i], out = g->n - s; g->code[s].a = mode == 1 ? out : 1; g->code[s].b = mode == 1 ? 1 : out; }
        free(splits);
    }
    if (at_atomic >= 0) { emit(g, O_MATCH, 0, 0, 0); g->code[at_atomic].a = g->n - at_atomic; }
    free(atom);
}
static void parse_seq(Prog *g) {
    for (;;) {
        int start = g->n;
        if (!parse_atom(g) || g->err) return;
        for (;;) {
            skip_x(g);
            if (!more(g)) break;
            uint32_t c = peek(g); int mn, mx;
            if (c == '*') { mn = 0; mx = -1; g->pi++; }
            else if (c == '+') { mn = 1; mx = -1; g->pi++; }
            else if (c == '?') { mn = 0; mx = 1; g->pi++; }
            else if (c == '{' && g->pi + 1 < g->pl && g->p[g->pi + 1] >= '0' && g->p[g->pi + 1] <= '9') {
                NSUInteger save = g->pi; g->pi++;
                mn = 0; while (peek(g) >= '0' && peek(g) <= '9') mn = mn * 10 + (int)(next_cp(g) - '0');
                mx = mn;
                if (peek(g) == ',') { g->pi++; if (peek(g) == '}') mx = -1; else { mx = 0; while (peek(g) >= '0' && peek(g) <= '9') mx = mx * 10 + (int)(next_cp(g) - '0'); } }
                if (peek(g) != '}') { g->pi = save; break; }
                g->pi++;
                if (mx >= 0 && mx < mn) { g->err = "bad {m,n}"; return; }
            } else break;
            int mode = 0;
            if (peek(g) == '?') { mode = 1; g->pi++; } else if (peek(g) == '+') { mode = 2; g->pi++; }
            quantify(g, start, mn, mx, mode);
            if (g->err) return;
        }
    }
}
static void parse_alt(Prog *g) {
    int start = g->n;
    parse_seq(g);
    if (g->err || peek(g) != '|') return;
    /* rebuild as: SPLIT(+1, next) alt1 JMP end ; SPLIT ... ; altN */
    int *jmps = NULL; int nj = 0;
    while (!g->err && peek(g) == '|') {
        g->pi++;
        int len = g->n - start;
        Ins *alt = malloc(len * sizeof(Ins) + 1); memcpy(alt, g->code + start, len * sizeof(Ins));
        g->n = start;
        int s = emit(g, O_SPLIT, 0, 1, 0);
        for (int k = 0; k < len; k++) emit(g, alt[k].op, alt[k].fl, alt[k].a, alt[k].b);
        free(alt);
        jmps = realloc(jmps, (nj + 1) * sizeof(int)); jmps[nj++] = emit(g, O_JMP, 0, 0, 0);
        g->code[s].b = g->n - s;
        start = g->n;
        parse_seq(g);
    }
    for (int i = 0; i < nj; i++) g->code[jmps[i]].a = g->n - jmps[i];
    free(jmps);
}

static void prog_free(Prog *g) {
    free(g->code); for (int i = 0; i < g->nsets; i++) free(g->sets[i].r); free(g->sets);
    for (int i = 0; i < g->nnames; i++) free(g->names[i]); free(g->names); free(g->name_idx); free(g);
}
static Prog *compile(const unichar *p, NSUInteger n, NSUInteger opts, const char **err) {
    Prog *g = calloc(1, sizeof *g);
    g->p = p; g->pl = n;
    g->flags = (opts & 1 ? F_I : 0) | (opts & 2 ? F_X : 0) | (opts & 8 ? F_S : 0) | (opts & 16 ? F_M : 0) | (opts & 32 ? F_UNIX : 0);
    if (opts & 4) { for (NSUInteger i = 0; i < n; i++) emit(g, O_CHAR, g->flags, p[i], 0); }   /* IgnoreMetacharacters */
    else {
        parse_alt(g);
        if (!g->err && more(g)) g->err = peek(g) == ')' ? "unbalanced )" : "syntax error";
    }
    emit(g, O_MATCH, 0, 0, 0);
    if (g->err) { *err = g->err; prog_free(g); return NULL; }
    return g;
}

/* ------------------------------------------------------------------ matcher (backtracking with an undo log) */
typedef struct { const unichar *s; NSUInteger n; long *slots; int nslots; Prog *g; long steps; } M;
typedef struct { int kind; int pc; long sp; int slot; long old; } BT; /* kind 0 branch, 1 restore, 2 barrier */
typedef struct { BT *v; long n, cap; } Stack;
static void push(Stack *st, BT b) { if (st->n == st->cap) { st->cap = st->cap * 2 + 256; st->v = realloc(st->v, st->cap * sizeof(BT)); } st->v[st->n++] = b; }
static uint32_t cp_at(M *m, long i, int *w) {
    uint32_t c = m->s[i]; *w = 1;
    if (c >= 0xD800 && c < 0xDC00 && (NSUInteger)i + 1 < m->n && m->s[i + 1] >= 0xDC00 && m->s[i + 1] < 0xE000) { *w = 2; return 0x10000 + ((c - 0xD800) << 10) + (m->s[i + 1] - 0xDC00); }
    return c;
}
static uint32_t cp_before(M *m, long i) {
    uint32_t c = m->s[i - 1];
    if (c >= 0xDC00 && c < 0xE000 && i >= 2 && m->s[i - 2] >= 0xD800 && m->s[i - 2] < 0xDC00) return 0x10000 + ((m->s[i - 2] - 0xD800) << 10) + (c - 0xDC00);
    return c;
}
static int isword_at(M *m, long i) { int w; return i >= 0 && (NSUInteger)i < m->n && prop(P_WORD, cp_at(m, i, &w)); }
static void set_slot(M *m, Stack *st, int slot, long v) { push(st, (BT){1, 0, 0, slot, m->slots[slot]}); m->slots[slot] = v; }
static long run(M *m, int pc, long sp, long must_end);
static long run(M *m, int pc, long sp, long must_end) {
    Stack st = {0};
    Ins *code = m->g->code;
    long result = -1;
    for (;;) {
        Ins *in = &code[pc];
        int ok = 1, w;
        switch (in->op) {
        case O_MATCH:
            if (must_end >= 0 && sp != must_end) { ok = 0; break; }
            result = sp; goto done;
        case O_CHAR:
            if ((NSUInteger)sp >= m->n) { ok = 0; break; }
            { uint32_t c = cp_at(m, sp, &w); ok = c == (uint32_t)in->a || ((in->fl & F_I) && fold(c) == fold((uint32_t)in->a)); }
            if (ok) { sp += w; pc++; }
            break;
        case O_ANY:
            if ((NSUInteger)sp >= m->n) { ok = 0; break; }
            { uint32_t c = cp_at(m, sp, &w); ok = (in->fl & F_S) || !is_line_term(c, in->fl & F_UNIX); }
            if (ok) { sp += w; pc++; }
            break;
        case O_CLASS:
            if ((NSUInteger)sp >= m->n) { ok = 0; break; }
            { uint32_t c = cp_at(m, sp, &w); ok = set_has(&m->g->sets[in->a], c, in->fl & F_I); }
            if (ok) { sp += w; pc++; }
            break;
        case O_SPLIT: push(&st, (BT){0, pc + in->b, sp, 0, 0}); pc += in->a; break;
        case O_JMP: pc += in->a; break;
        case O_SAVE: set_slot(m, &st, in->a, sp); pc++; break;
        case O_MARK: set_slot(m, &st, 2 * (m->g->ngroups + 1) + in->a, sp); pc++; break;
        case O_CHECK: pc += m->slots[2 * (m->g->ngroups + 1) + in->a] != sp ? 1 : in->b; break;   /* empty iteration: leave the loop (Perl/ICU) */
        case O_BOL:
            ok = sp == 0 || ((in->fl & F_M) && is_line_term(m->s[sp - 1], in->fl & F_UNIX) && !(m->s[sp - 1] == '\r' && (NSUInteger)sp < m->n && m->s[sp] == '\n'));
            pc++; break;
        case O_EOL: {
            NSUInteger n = m->n;
            if ((NSUInteger)sp == n) ok = 1;
            else if (in->fl & F_M) ok = is_line_term(m->s[sp], in->fl & F_UNIX) && !(sp > 0 && m->s[sp - 1] == '\r' && m->s[sp] == '\n');
            else ok = ((NSUInteger)sp + 1 == n && is_line_term(m->s[sp], in->fl & F_UNIX)) || ((NSUInteger)sp + 2 == n && m->s[sp] == '\r' && m->s[sp + 1] == '\n');
            pc++; break;
        }
        case O_SBEG: ok = sp == 0; pc++; break;
        case O_SEND: ok = (NSUInteger)sp == m->n; pc++; break;
        case O_SENDNL: ok = (NSUInteger)sp == m->n || ((NSUInteger)sp + 1 == m->n && is_line_term(m->s[sp], 0)) || ((NSUInteger)sp + 2 == m->n && m->s[sp] == '\r' && m->s[sp + 1] == '\n'); pc++; break;
        case O_WORDB: case O_NWORDB: {
            int a = sp > 0 && prop(P_WORD, cp_before(m, sp)), b = isword_at(m, sp);
            ok = (a != b) == (in->op == O_WORDB); pc++; break;
        }
        case O_BACKREF: {
            long s0 = in->a < m->g->ngroups + 1 ? m->slots[2 * in->a] : -1, s1 = in->a < m->g->ngroups + 1 ? m->slots[2 * in->a + 1] : -1;
            if (s0 < 0 || s1 < 0) { ok = 0; break; }
            long len = s1 - s0;
            if ((NSUInteger)(sp + len) > m->n) { ok = 0; break; }
            for (long i = 0; i < len && ok; i++) ok = m->s[s0 + i] == m->s[sp + i] || ((in->fl & F_I) && fold(m->s[s0 + i]) == fold(m->s[sp + i]));
            if (ok) { sp += len; pc++; }
            break;
        }
        case O_LOOK: case O_ATOMIC: {
            int neg = in->op == O_LOOK && (in->fl & 1), behind = in->op == O_LOOK && (in->fl & 2);
            long *snap = malloc(m->nslots * sizeof(long)); memcpy(snap, m->slots, m->nslots * sizeof(long));
            long r = -1;
            if (behind) { for (long s = sp; s >= 0 && s >= sp - 255 && r < 0; s--) r = run(m, pc + 1, s, sp); }
            else r = run(m, pc + 1, sp, -1);
            if (neg || r < 0) memcpy(m->slots, snap, m->nslots * sizeof(long));
            else for (int i = 0; i < m->nslots; i++) if (m->slots[i] != snap[i]) push(&st, (BT){1, 0, 0, i, snap[i]});
            free(snap);
            ok = neg ? r < 0 : r >= 0;
            if (ok && in->op == O_ATOMIC) sp = r;
            pc += in->a;
            break;
        }
        }
        if (++m->steps > 50000000) { result = -2; goto done; } /* pathological pattern: give up like ICU's time limit */
        if (ok) continue;
        /* backtrack */
        for (;;) {
            if (!st.n) goto done;
            BT b = st.v[--st.n];
            if (b.kind == 1) { m->slots[b.slot] = b.old; continue; }
            pc = b.pc; sp = b.sp; break;
        }
    }
done:
    if (result < 0) while (st.n) { BT b = st.v[--st.n]; if (b.kind == 1) m->slots[b.slot] = b.old; }
    free(st.v);
    return result;
}

/* ------------------------------------------------------------------ Objective-C classes */
@interface NSRegularExpression (MWPrivate) - (NSInteger)_groupIndexForName:(NSString *)n; @end
@interface NSTextCheckingResult (MWPrivate) - (instancetype)_initWithRanges:(NSRange *)r count:(NSUInteger)n regex:(NSRegularExpression *)re; @end
static void append_ch(NSMutableString *s, unichar c) { [s appendString:[NSString stringWithCharacters:&c length:1]]; }
@implementation NSTextCheckingResult { NSRange *_r; NSUInteger _n; NSRegularExpression *_re; }
- (instancetype)_initWithRanges:(NSRange *)r count:(NSUInteger)n regex:(NSRegularExpression *)re {
    _r = malloc(n * sizeof(NSRange)); memcpy(_r, r, n * sizeof(NSRange)); _n = n; _re = [re retain]; return self;
}
- (void)dealloc { free(_r); [_re release]; [super dealloc]; }
- (uint64_t)resultType { return 1ull << 10; } /* NSTextCheckingTypeRegularExpression */
- (NSRange)range { return _r[0]; }
- (NSUInteger)numberOfRanges { return _n; }
- (NSRange)rangeAtIndex:(NSUInteger)i { if (i >= _n) mw_raise("NSRangeException", "-[NSTextCheckingResult rangeAtIndex:]: index out of bounds"); return _r[i]; }
- (NSRange)rangeWithName:(NSString *)name { NSInteger i = [_re _groupIndexForName:name]; return i >= 0 && (NSUInteger)i < _n ? _r[i] : NSMakeRange(NSNotFound, 0); }
- (NSRegularExpression *)regularExpression { return _re; }
- (NSTextCheckingResult *)resultByAdjustingRangesWithOffset:(NSInteger)off {
    NSRange *r = malloc(_n * sizeof(NSRange));
    for (NSUInteger i = 0; i < _n; i++) r[i] = _r[i].location == NSNotFound ? _r[i] : NSMakeRange(_r[i].location + off, _r[i].length);
    NSTextCheckingResult *t = [[[NSTextCheckingResult alloc] _initWithRanges:r count:_n regex:_re] autorelease]; free(r); return t;
}
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)description { return [NSString stringWithFormat:@"<NSRegularExpressionCheckingResult: %p>{%lu, %lu}", self, (unsigned long)_r[0].location, (unsigned long)_r[0].length]; }
@end

NSString *const NSRegularExpressionErrorDomain = @"NSCocoaErrorDomain";
@implementation NSRegularExpression { NSString *_pattern; NSUInteger _opts; Prog *_g; }
+ (NSRegularExpression *)regularExpressionWithPattern:(NSString *)p options:(NSUInteger)o error:(NSError **)e { return [[[self alloc] initWithPattern:p options:o error:e] autorelease]; }
- (instancetype)initWithPattern:(NSString *)p options:(NSUInteger)o error:(NSError **)e {
    if (!p) { [self release]; mw_raise("NSInvalidArgumentException", "-[NSRegularExpression initWithPattern:options:error:]: nil argument"); }
    NSUInteger n; unichar *u = mw_chars(p, &n);
    const char *err = 0;
    _g = compile(u, n, o, &err);
    free(u);
    if (!_g) {
        if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:2048 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                     p, @"NSInvalidValue", [NSString stringWithFormat:@"The value “%@” is invalid (%s).", p, err], NSLocalizedDescriptionKey, nil]];
        [self release]; return nil;
    }
    _pattern = [p copy]; _opts = o;
    return self;
}
- (void)dealloc { if (_g) prog_free(_g); [_pattern release]; [super dealloc]; }
- (NSString *)pattern { return _pattern; }
- (NSUInteger)options { return _opts; }
- (NSUInteger)numberOfCaptureGroups { return (NSUInteger)_g->ngroups; }
- (NSInteger)_groupIndexForName:(NSString *)name { return group_by_name(_g, [name UTF8String]); }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSRegularExpression class]] && [_pattern isEqual:[o pattern]] && _opts == [o options]); }
- (NSUInteger)hash { return [_pattern hash] ^ _opts; }
- (NSString *)description { return [NSString stringWithFormat:@"<NSRegularExpression: %p> %@ 0x%lx", self, _pattern, (unsigned long)_opts]; }

/* NSMatchingOptions: ReportProgress 1, ReportCompletion 2, Anchored 4, WithTransparentBounds 8, WithoutAnchoringBounds 16 */
- (void)enumerateMatchesInString:(NSString *)str options:(NSUInteger)opt range:(NSRange)rg usingBlock:(void (^)(NSTextCheckingResult *, NSUInteger, BOOL *))block {
    if (!str) mw_raise("NSInvalidArgumentException", "-[NSRegularExpression enumerateMatchesInString:options:range:usingBlock:]: nil argument");
    if (NSMaxRange(rg) > [str length]) mw_raise("NSRangeException", "-[NSRegularExpression enumerateMatchesInString:options:range:usingBlock:]: Range out of bounds");
    unichar *u = malloc((rg.length + 1) * sizeof(unichar)); [str getCharacters:u range:rg];
    M m = {u, rg.length, NULL, 2 * (_g->ngroups + 1) + _g->nregs, _g, 0};
    m.slots = malloc(m.nslots * sizeof(long));
    NSRange *rs = malloc((_g->ngroups + 1) * sizeof(NSRange));
    BOOL stop = NO;
    long pos = 0; int prev_empty_at = -1;
    int anchored_start = _g->code[0].op == O_SBEG || (_g->code[0].op == O_BOL && !(_g->code[0].fl & F_M));
    while (!stop && (NSUInteger)pos <= m.n) {
        long end = -1, start = pos;
        for (; (NSUInteger)start <= m.n; start++) {
            if (start == prev_empty_at) continue;
            for (int i = 0; i < m.nslots; i++) m.slots[i] = -1;
            end = run(&m, 0, start, -1);
            if (end == -2) { end = -1; break; }
            if (end >= 0 || (opt & 4) || anchored_start) break;
            if ((NSUInteger)start < m.n && u[start] >= 0xD800 && u[start] < 0xDC00) start++;   /* never split a surrogate pair */
        }
        if (end < 0) break;
        rs[0] = NSMakeRange(rg.location + (NSUInteger)start, (NSUInteger)(end - start));
        for (int gi = 1; gi <= _g->ngroups; gi++) {
            long a = m.slots[2 * gi], b = m.slots[2 * gi + 1];
            rs[gi] = a >= 0 && b >= a ? NSMakeRange(rg.location + (NSUInteger)a, (NSUInteger)(b - a)) : NSMakeRange(NSNotFound, 0);
        }
        NSTextCheckingResult *r = [[NSTextCheckingResult alloc] _initWithRanges:rs count:_g->ngroups + 1 regex:self];
        block(r, 0, &stop);
        [r release];
        if (end == start) { prev_empty_at = (int)end; pos = end; } else { pos = end; prev_empty_at = -1; }
        if (opt & 4) { if (end == start) break; }
        if (anchored_start) break;
    }
    if (opt & 2 && !stop) block(nil, 2 /* NSMatchingCompleted */, &stop);
    free(rs); free(m.slots); free(u);
}
- (NSArray *)matchesInString:(NSString *)s options:(NSUInteger)o range:(NSRange)r {
    NSMutableArray *a = [NSMutableArray array];
    [self enumerateMatchesInString:s options:o & ~3ul range:r usingBlock:^(NSTextCheckingResult *t, NSUInteger f, BOOL *stop) { if (t) [a addObject:t]; }];
    return a;
}
- (NSUInteger)numberOfMatchesInString:(NSString *)s options:(NSUInteger)o range:(NSRange)r { return [[self matchesInString:s options:o range:r] count]; }
- (NSTextCheckingResult *)firstMatchInString:(NSString *)s options:(NSUInteger)o range:(NSRange)r {
    __block NSTextCheckingResult *res = nil;
    [self enumerateMatchesInString:s options:o & ~3ul range:r usingBlock:^(NSTextCheckingResult *t, NSUInteger f, BOOL *stop) { res = [[t retain] autorelease]; *stop = YES; }];
    return res;
}
- (NSRange)rangeOfFirstMatchInString:(NSString *)s options:(NSUInteger)o range:(NSRange)r {
    NSTextCheckingResult *t = [self firstMatchInString:s options:o range:r];
    return t ? [t range] : NSMakeRange(NSNotFound, 0);
}
- (NSString *)replacementStringForResult:(NSTextCheckingResult *)res inString:(NSString *)s offset:(NSInteger)off template:(NSString *)tmpl {
    NSMutableString *out = [NSMutableString string];
    NSUInteger n; unichar *t = mw_chars(tmpl, &n);
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = t[i];
        if (c == '\\' && i + 1 < n) { append_ch(out, t[++i]); continue; }
        if (c == '$' && i + 1 < n && t[i + 1] >= '0' && t[i + 1] <= '9') {
            NSUInteger g = t[++i] - '0';
            while (i + 1 < n && t[i + 1] >= '0' && t[i + 1] <= '9' && g * 10 + (t[i + 1] - '0') <= [res numberOfRanges] - 1) g = g * 10 + (t[++i] - '0');
            if (g < [res numberOfRanges]) { NSRange r = [res rangeAtIndex:g]; if (r.location != NSNotFound) [out appendString:[s substringWithRange:NSMakeRange(r.location + off, r.length)]]; }
            continue;
        }
        if (c == '$' && i + 1 < n && t[i + 1] == '{') {
            NSUInteger e = i + 2; while (e < n && t[e] != '}') e++;
            NSString *name = [NSString stringWithCharacters:t + i + 2 length:e - i - 2];
            NSRange r = [res rangeWithName:name];
            if (r.location != NSNotFound) [out appendString:[s substringWithRange:NSMakeRange(r.location + off, r.length)]];
            i = e; continue;
        }
        append_ch(out, c);
    }
    free(t);
    return out;
}
- (NSUInteger)replaceMatchesInString:(NSMutableString *)s options:(NSUInteger)o range:(NSRange)r withTemplate:(NSString *)tmpl {
    NSArray *ms = [self matchesInString:s options:o range:r];
    NSString *orig = [[s copy] autorelease];
    NSInteger delta = 0;
    for (NSTextCheckingResult *t in ms) {
        NSString *rep = [self replacementStringForResult:t inString:orig offset:0 template:tmpl];
        NSRange mr = [t range];
        [s replaceCharactersInRange:NSMakeRange(mr.location + delta, mr.length) withString:rep];
        delta += (NSInteger)[rep length] - (NSInteger)mr.length;
    }
    return [ms count];
}
- (NSString *)stringByReplacingMatchesInString:(NSString *)s options:(NSUInteger)o range:(NSRange)r withTemplate:(NSString *)tmpl {
    NSMutableString *m = [[s mutableCopy] autorelease];
    [self replaceMatchesInString:m options:o range:r withTemplate:tmpl];
    return [NSString stringWithString:m];
}
+ (NSString *)escapedPatternForString:(NSString *)s {
    NSMutableString *o = [NSMutableString string]; NSUInteger n; unichar *u = mw_chars(s, &n);
    for (NSUInteger i = 0; i < n; i++) { if (u[i] < 128 && strchr("\\^$.|?*+()[]{}-/", u[i])) [o appendString:@"\\"]; append_ch(o, u[i]); }
    free(u); return o;
}
+ (NSString *)escapedTemplateForString:(NSString *)s {
    NSMutableString *o = [NSMutableString string]; NSUInteger n; unichar *u = mw_chars(s, &n);
    for (NSUInteger i = 0; i < n; i++) { if (u[i] == '\\' || u[i] == '$') [o appendString:@"\\"]; append_ch(o, u[i]); }
    free(u); return o;
}
@end

/* NSString / NSMutableString with NSRegularExpressionSearch (1024) */
NSRange mw_regex_range(NSString *self, NSString *pat, NSUInteger o, NSRange r) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:(o & NSCaseInsensitiveSearch ? 1 : 0) error:nil];
    if (!re) return NSMakeRange(NSNotFound, 0);
    if (o & NSBackwardsSearch) {
        NSArray *a = [re matchesInString:self options:(o & NSAnchoredSearch ? 0 : 0) range:r];
        if (o & NSAnchoredSearch) { NSTextCheckingResult *l = [a lastObject]; return l && NSMaxRange([l range]) == NSMaxRange(r) ? [l range] : NSMakeRange(NSNotFound, 0); }
        return [a count] ? [[a lastObject] range] : NSMakeRange(NSNotFound, 0);
    }
    return [re rangeOfFirstMatchInString:self options:(o & NSAnchoredSearch ? 4 : 0) range:r];
}
NSUInteger mw_regex_replace(NSMutableString *s, NSString *pat, NSString *tmpl, NSUInteger o, NSRange r) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:(o & NSCaseInsensitiveSearch ? 1 : 0) error:nil];
    return re ? [re replaceMatchesInString:s options:(o & NSAnchoredSearch ? 4 : 0) range:r withTemplate:tmpl] : 0;
}
