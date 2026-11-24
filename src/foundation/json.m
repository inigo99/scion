/* json.m — scion Foundation: NSJSONSerialization (RFC 8259, UTF-8). MRC.
 * Output follows Apple's: "/" escaped as "\/" unless WithoutEscapingSlashes, pretty print with 2 spaces and " : ". */
#import "internal.h"

@interface NSNumber (MWType) - (char)_mwType; @end
enum { RD_MUTABLE_CONTAINERS = 1, RD_MUTABLE_LEAVES = 2, RD_FRAGMENTS = 4, RD_JSON5 = 8 };
enum { WR_PRETTY = 1, WR_SORTED = 2, WR_FRAGMENTS = 4, WR_NO_SLASH_ESCAPE = 8 };

typedef struct { const unsigned char *s; size_t n, i; NSUInteger opt; const char *err; int depth; } JR;
static void ws(JR *r) {
    for (;;) {
        while (r->i < r->n && (r->s[r->i] == ' ' || r->s[r->i] == '\t' || r->s[r->i] == '\n' || r->s[r->i] == '\r' || ((r->opt & RD_JSON5) && (r->s[r->i] == '\f' || r->s[r->i] == '\v')))) r->i++;
        if (!(r->opt & RD_JSON5) || r->i + 1 >= r->n || r->s[r->i] != '/') return;
        if (r->s[r->i + 1] == '/') { while (r->i < r->n && r->s[r->i] != '\n') r->i++; }   /* JSON5 comments */
        else if (r->s[r->i + 1] == '*') { r->i += 2; while (r->i + 1 < r->n && !(r->s[r->i] == '*' && r->s[r->i + 1] == '/')) r->i++; r->i += 2; }
        else return;
    }
}
static id jvalue(JR *r);
static int hex4(JR *r, uint32_t *v) {
    if (r->i + 4 > r->n) return 0;
    *v = 0;
    for (int k = 0; k < 4; k++) {
        unsigned char c = r->s[r->i++]; int h = c >= '0' && c <= '9' ? c - '0' : (c | 32) >= 'a' && (c | 32) <= 'f' ? (c | 32) - 'a' + 10 : -1;
        if (h < 0) return 0;
        *v = *v * 16 + (uint32_t)h;
    }
    return 1;
}
static NSString *jstring(JR *r) {
    unsigned char q = r->s[r->i++]; /* opening quote: " (or ' in JSON5) */
    size_t cap = 64, n = 0; unichar *u = malloc(cap * sizeof(unichar));
#define PUT(c) do { if (n + 2 >= cap) u = realloc(u, (cap *= 2) * sizeof(unichar)); u[n++] = (unichar)(c); } while (0)
    while (r->i < r->n) {
        unsigned char c = r->s[r->i];
        if (c == q) { r->i++; NSString *s = mw_str_take(u, n); return (r->opt & RD_MUTABLE_LEAVES) ? [[s mutableCopy] autorelease] : s; }
        if (c < 0x20) { r->err = "Unescaped control character"; break; }
        if (c == '\\') {
            r->i++;
            if (r->i >= r->n) break;
            unsigned char e = r->s[r->i++];
            uint32_t v;
            switch (e) {
            case '"': PUT('"'); break; case '\\': PUT('\\'); break; case '/': PUT('/'); break;
            case '\'': if (!(r->opt & RD_JSON5)) { r->err = "Invalid escape sequence"; goto fail; } PUT('\''); break;
            case '\n': if (!(r->opt & RD_JSON5)) { r->err = "Invalid escape sequence"; goto fail; } break;   /* line continuation */
            case '0': if (!(r->opt & RD_JSON5)) { r->err = "Invalid escape sequence"; goto fail; } PUT(0); break;
            case 'v': if (!(r->opt & RD_JSON5)) { r->err = "Invalid escape sequence"; goto fail; } PUT('\v'); break;
            case 'x': {
                if (!(r->opt & RD_JSON5) || r->i + 2 > r->n) { r->err = "Invalid escape sequence"; goto fail; }
                char h[3] = {(char)r->s[r->i], (char)r->s[r->i + 1], 0}; r->i += 2; PUT(strtoll(h, 0, 16)); break;
            }
            case 'b': PUT('\b'); break; case 'f': PUT('\f'); break; case 'n': PUT('\n'); break; case 'r': PUT('\r'); break; case 't': PUT('\t'); break;
            case 'u':
                if (!hex4(r, &v)) { r->err = "Invalid escape sequence"; goto fail; }
                PUT(v); break;   /* surrogate pairs arrive as two \u escapes and stay two UTF-16 units */
            default: r->err = "Invalid escape sequence"; goto fail;
            }
            continue;
        }
        /* UTF-8 sequence */
        uint32_t cp; int len;
        if (c < 0x80) { cp = c; len = 1; }
        else if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; len = 2; }
        else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; len = 3; }
        else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; len = 4; }
        else { r->err = "Invalid UTF-8"; break; }
        if (r->i + (size_t)len > r->n) { r->err = "Invalid UTF-8"; break; }
        for (int k = 1; k < len; k++) { unsigned char d = r->s[r->i + k]; if ((d & 0xC0) != 0x80) { r->err = "Invalid UTF-8"; goto fail; } cp = cp << 6 | (d & 0x3F); }
        r->i += (size_t)len;
        if (cp >= 0x10000) { cp -= 0x10000; PUT(0xD800 + (cp >> 10)); PUT(0xDC00 + (cp & 0x3FF)); } else PUT(cp);
    }
#undef PUT
    if (!r->err) r->err = "Unterminated string";
fail:
    free(u);
    return nil;
}
static id jnumber5(JR *r) {   /* JSON5: + . hex Infinity NaN */
    int neg = 0;
    if (r->s[r->i] == '+' || r->s[r->i] == '-') neg = r->s[r->i++] == '-';
    if (r->i + 8 <= r->n && !memcmp(r->s + r->i, "Infinity", 8)) { r->i += 8; return [NSNumber numberWithDouble:neg ? -__builtin_inf() : __builtin_inf()]; }
    if (r->i + 3 <= r->n && !memcmp(r->s + r->i, "NaN", 3)) { r->i += 3; return [NSNumber numberWithDouble:__builtin_nan("")]; }
    char buf[80]; size_t l = 0;
    if (neg) buf[l++] = '-';
    while (r->i < r->n && l < 78 && (isalnum(r->s[r->i]) || r->s[r->i] == '.' || ((r->s[r->i] == '+' || r->s[r->i] == '-') && (r->s[r->i - 1] | 32) == 'e'))) buf[l++] = (char)r->s[r->i++];
    buf[l] = 0;
    char *end; 
    if (strchr(buf, 'x') || strchr(buf, 'X')) { long long v = strtoll(buf, &end, 16); return *end ? (r->err = "Invalid number", nil) : [NSNumber numberWithLongLong:v]; }
    if (!strchr(buf, '.') && !strchr(buf, 'e') && !strchr(buf, 'E')) { long long v = strtoll(buf, &end, 10); if (!*end) return [NSNumber numberWithLongLong:v]; }
    double d = strtod(buf, &end);
    if (*end || l == (size_t)neg) { r->err = "Invalid number"; return nil; }
    return [NSNumber numberWithDouble:d];
}
static id jnumber(JR *r) {
    if (r->opt & RD_JSON5) return jnumber5(r);
    size_t st = r->i; int isfloat = 0;
    if (r->s[r->i] == '-') r->i++;
    if (r->i >= r->n || r->s[r->i] < '0' || r->s[r->i] > '9') { r->err = "Invalid number"; return nil; }
    if (r->s[r->i] == '0' && r->i + 1 < r->n && r->s[r->i + 1] >= '0' && r->s[r->i + 1] <= '9') { r->err = "Leading zeros are not allowed"; return nil; }
    while (r->i < r->n && r->s[r->i] >= '0' && r->s[r->i] <= '9') r->i++;
    if (r->i < r->n && r->s[r->i] == '.') {
        isfloat = 1; r->i++;
        if (r->i >= r->n || r->s[r->i] < '0' || r->s[r->i] > '9') { r->err = "Invalid number"; return nil; }
        while (r->i < r->n && r->s[r->i] >= '0' && r->s[r->i] <= '9') r->i++;
    }
    if (r->i < r->n && (r->s[r->i] == 'e' || r->s[r->i] == 'E')) {
        isfloat = 1; r->i++;
        if (r->i < r->n && (r->s[r->i] == '+' || r->s[r->i] == '-')) r->i++;
        if (r->i >= r->n || r->s[r->i] < '0' || r->s[r->i] > '9') { r->err = "Invalid number"; return nil; }
        while (r->i < r->n && r->s[r->i] >= '0' && r->s[r->i] <= '9') r->i++;
    }
    char buf[64]; size_t l = r->i - st; if (l > 63) { isfloat = 1; l = 63; }
    memcpy(buf, r->s + st, l); buf[l] = 0;
    if (!isfloat) {
        errno = 0; long long v = strtoll(buf, 0, 10);
        if (!errno) return [NSNumber numberWithLongLong:v];
        if (buf[0] != '-') { errno = 0; unsigned long long uv = strtoull(buf, 0, 10); if (!errno) return [NSNumber numberWithUnsignedLongLong:uv]; }
    }
    return [NSNumber numberWithDouble:strtod(buf, 0)];
}
static int lit(JR *r, const char *w) { size_t l = strlen(w); if (r->i + l <= r->n && !memcmp(r->s + r->i, w, l)) { r->i += l; return 1; } return 0; }
static id jvalue(JR *r) {
    ws(r);
    if (r->i >= r->n) { r->err = "Unexpected end of file"; return nil; }
    if (++r->depth > 512) { r->err = "Too many nested arrays or dictionaries"; return nil; }
    unsigned char c = r->s[r->i];
    id res = nil;
    if (c == '{') {
        r->i++;
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        ws(r);
        if (r->i < r->n && r->s[r->i] == '}') r->i++;
        else for (;;) {
            ws(r);
            if ((r->opt & RD_JSON5) && r->i < r->n && r->s[r->i] == '}') { r->i++; break; }   /* trailing comma */
            NSString *k;
            if ((r->opt & RD_JSON5) && r->i < r->n && r->s[r->i] != '"' && r->s[r->i] != '\'') {   /* identifier key */
                size_t b = r->i; while (r->i < r->n && (isalnum(r->s[r->i]) || r->s[r->i] == '_' || r->s[r->i] == '$' || r->s[r->i] >= 0x80)) r->i++;
                if (r->i == b) { r->err = "No string key for value in object"; return nil; }
                k = [[[NSString alloc] initWithBytes:r->s + b length:r->i - b encoding:NSUTF8StringEncoding] autorelease];
            } else {
                if (r->i >= r->n || r->s[r->i] != '"' ) { if (!((r->opt & RD_JSON5) && r->i < r->n && r->s[r->i] == '\'')) { r->err = "No string key for value in object"; return nil; } }
                k = jstring(r); if (!k) return nil;
            }
            ws(r);
            if (r->i >= r->n || r->s[r->i] != ':') { r->err = "No value for key in object"; return nil; }
            r->i++;
            id v = jvalue(r); if (!v) return nil;
            [d setObject:v forKey:k];
            ws(r);
            if (r->i < r->n && r->s[r->i] == ',') { r->i++; continue; }
            if (r->i < r->n && r->s[r->i] == '}') { r->i++; break; }
            r->err = "Badly formed object"; return nil;
        }
        res = (r->opt & RD_MUTABLE_CONTAINERS) ? d : [NSDictionary dictionaryWithDictionary:d];
    } else if (c == '[') {
        r->i++;
        NSMutableArray *a = [NSMutableArray array];
        ws(r);
        if (r->i < r->n && r->s[r->i] == ']') r->i++;
        else for (;;) {
            ws(r);
            if ((r->opt & RD_JSON5) && r->i < r->n && r->s[r->i] == ']') { r->i++; break; }   /* trailing comma */
            id v = jvalue(r); if (!v) return nil;
            [a addObject:v];
            ws(r);
            if (r->i < r->n && r->s[r->i] == ',') { r->i++; continue; }
            if (r->i < r->n && r->s[r->i] == ']') { r->i++; break; }
            r->err = "Badly formed array"; return nil;
        }
        res = (r->opt & RD_MUTABLE_CONTAINERS) ? a : [NSArray arrayWithArray:a];
    } else if (c == '"' || (c == '\'' && (r->opt & RD_JSON5))) res = jstring(r);
    else if (c == '-' || (c >= '0' && c <= '9') || ((r->opt & RD_JSON5) && (c == '+' || c == '.' || c == 'I' || c == 'N'))) res = jnumber(r);
    else if (lit(r, "true")) res = [NSNumber numberWithBool:YES];
    else if (lit(r, "false")) res = [NSNumber numberWithBool:NO];
    else if (lit(r, "null")) res = [NSNull null];
    else r->err = "Invalid value";
    r->depth--;
    return res;
}
static NSError *jerror(const char *msg, size_t at) {
    NSString *d = [NSString stringWithFormat:@"%s around line 1, column %lu.", msg, (unsigned long)at];
    return [NSError errorWithDomain:NSCocoaErrorDomain code:3840 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
            d, @"NSDebugDescription", @"The data couldn’t be read because it isn’t in the correct format.", NSLocalizedDescriptionKey, nil]];
}

/* ------------------------------------------------------------------ writer */
typedef struct { char *b; size_t n, cap; NSUInteger opt; const char *err; } JW;
static void wput(JW *w, const char *s, size_t l) { if (w->n + l + 1 > w->cap) { w->cap = (w->n + l + 1) * 2; w->b = realloc(w->b, w->cap); } memcpy(w->b + w->n, s, l); w->n += l; }
static void wputs(JW *w, const char *s) { wput(w, s, strlen(s)); }
static void indent(JW *w, int d) { if (w->opt & WR_PRETTY) { wputs(w, "\n"); for (int i = 0; i < d; i++) wputs(w, "  "); } }
static void wstring(JW *w, NSString *s) {
    const char *u = [s UTF8String];
    wputs(w, "\"");
    for (const unsigned char *p = (const unsigned char *)u; *p; p++) {
        char e[8];
        switch (*p) {
        case '"': wputs(w, "\\\""); break;
        case '\\': wputs(w, "\\\\"); break;
        case '/': wputs(w, (w->opt & WR_NO_SLASH_ESCAPE) ? "/" : "\\/"); break;
        case '\n': wputs(w, "\\n"); break; case '\r': wputs(w, "\\r"); break; case '\t': wputs(w, "\\t"); break;
        case '\b': wputs(w, "\\b"); break; case '\f': wputs(w, "\\f"); break;
        default:
            if (*p < 0x20) { snprintf(e, sizeof e, "\\u%04x", *p); wputs(w, e); }
            else wput(w, (const char *)p, 1);
        }
    }
    wputs(w, "\"");
}
static int wvalue(JW *w, id o, int d) {
    if ([o isKindOfClass:[NSString class]]) { wstring(w, o); return 1; }
    if ([o isKindOfClass:[NSNumber class]]) {
        char t = [o _mwType], b[40];
        if (t == 'B') { wputs(w, [o boolValue] ? "true" : "false"); return 1; }
        if (t == 'd' || t == 'f') {
            double v = [o doubleValue];
            if (v != v || v - v != 0) { w->err = "Invalid number value (NaN or infinity) in JSON write"; return 0; }
            if (v == (double)(long long)v && v > -1e15 && v < 1e15) snprintf(b, sizeof b, "%lld", (long long)v);
            else { snprintf(b, sizeof b, "%.15g", v); if (strtod(b, 0) != v) snprintf(b, sizeof b, "%.17g", v); }
            wputs(w, b); return 1;
        }
        if (t == 'u') snprintf(b, sizeof b, "%llu", [o unsignedLongLongValue]); else snprintf(b, sizeof b, "%lld", [o longLongValue]);
        wputs(w, b); return 1;
    }
    if (o == (id)[NSNull null]) { wputs(w, "null"); return 1; }
    if ([o isKindOfClass:[NSArray class]]) {
        wputs(w, "[");
        NSUInteger n = [o count], i = 0;
        for (id x in o) { indent(w, d + 1); if (!wvalue(w, x, d + 1)) return 0; if (++i < n) wputs(w, ","); }
        if (n) indent(w, d);
        wputs(w, "]"); return 1;
    }
    if ([o isKindOfClass:[NSDictionary class]]) {
        wputs(w, "{");
        NSArray *keys = [o allKeys];
        for (id k in keys) if (![k isKindOfClass:[NSString class]]) { w->err = "Invalid (non-string) key in JSON dictionary"; return 0; }
        if (w->opt & WR_SORTED) keys = [keys sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger n = [keys count], i = 0;
        for (id k in keys) {
            indent(w, d + 1); wstring(w, k); wputs(w, (w->opt & WR_PRETTY) ? " : " : ":");
            if (!wvalue(w, [o objectForKey:k], d + 1)) return 0;
            if (++i < n) wputs(w, ",");
        }
        if (n) indent(w, d);
        wputs(w, "}"); return 1;
    }
    w->err = "Invalid type in JSON write";
    return 0;
}
static BOOL valid(id o, int top) {
    if ([o isKindOfClass:[NSArray class]]) { for (id x in o) if (!valid(x, 0)) return NO; return YES; }
    if ([o isKindOfClass:[NSDictionary class]]) { for (id k in o) if (![k isKindOfClass:[NSString class]] || !valid([o objectForKey:k], 0)) return NO; return YES; }
    if (top) return NO;
    if ([o isKindOfClass:[NSNumber class]]) { char t = [o _mwType]; if (t == 'd' || t == 'f') { double v = [o doubleValue]; return v == v && v - v == 0; } return YES; }
    return [o isKindOfClass:[NSString class]] || o == (id)[NSNull null];
}

@implementation NSJSONSerialization
+ (BOOL)isValidJSONObject:(id)o { return o && valid(o, 1); }
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)e {
    if (!data) mw_raise("NSInvalidArgumentException", "data parameter is nil");
    JR r = {[data bytes], [data length], 0, opt, 0, 0};
    if (r.n >= 3 && r.s[0] == 0xEF && r.s[1] == 0xBB && r.s[2] == 0xBF) r.i = 3;
    ws(&r);
    if (r.i >= r.n) { if (e) *e = jerror("Unable to parse empty data.", 0); return nil; }
    if (!(opt & RD_FRAGMENTS) && r.s[r.i] != '{' && r.s[r.i] != '[') { if (e) *e = jerror("JSON text did not start with array or object and option to allow fragments not set.", r.i); return nil; }
    id v = jvalue(&r);
    if (v) { ws(&r); if (r.i < r.n) { r.err = "Garbage at end"; v = nil; } }
    if (!v && e) *e = jerror(r.err ? r.err : "Invalid value", r.i);
    return v;
}
+ (NSData *)dataWithJSONObject:(id)o options:(NSJSONWritingOptions)opt error:(NSError **)e {
    if (!(opt & WR_FRAGMENTS) && ![o isKindOfClass:[NSArray class]] && ![o isKindOfClass:[NSDictionary class]])
        mw_raise("NSInvalidArgumentException", "*** +[NSJSONSerialization dataWithJSONObject:options:error:]: Invalid top-level type in JSON write");
    JW w = {0, 0, 0, opt, 0};
    if (!wvalue(&w, o, 0)) {
        free(w.b);
        if (!strncmp(w.err, "Invalid type", 12) || !strncmp(w.err, "Invalid number", 14) || !strncmp(w.err, "Invalid (non", 12)) {
            char m[160]; snprintf(m, sizeof m, "*** +[NSJSONSerialization dataWithJSONObject:options:error:]: %s", w.err);
            mw_raise("NSInvalidArgumentException", m);
        }
        if (e) *e = jerror(w.err, 0);
        return nil;
    }
    return [NSData dataWithBytesNoCopy:w.b length:w.n freeWhenDone:YES];
}
@end
