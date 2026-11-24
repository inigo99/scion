/* plist.m — property lists (XML, binary bplist00 and OpenStep/.strings), and what is built on them: NSBundle with its
 * Info.plist and localized strings, NSUserDefaults saved in ~/Library/Preferences, and the contentsOfFile/writeToFile
 * methods of NSDictionary and NSArray. Written from Apple's public format descriptions (CFBinaryPList.c's header comment,
 * the PropertyList-1.0 DTD). Files read here are untrusted: every offset and count is checked. */
#include "internal.h"
unsigned long strtoul(const char *, char **, int); int atexit(void (*)(void));
static int isxdigit(int c) { return (c >= '0' && c <= '9') || ((c | 32) >= 'a' && (c | 32) <= 'f'); }

static NSError *plist_error(NSInteger code, NSString *why) {
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:@{NSDebugDescriptionErrorKey: why}];
}
static BOOL is_plist_object(id o) {
    return [o isKindOfClass:[NSString class]] || [o isKindOfClass:[NSNumber class]] || [o isKindOfClass:[NSData class]]
        || [o isKindOfClass:[NSDate class]] || [o isKindOfClass:[NSArray class]] || [o isKindOfClass:[NSDictionary class]];
}

/* ======================================================================= XML */
typedef struct { const char *p, *end; BOOL leaves; } xin;
static void xml_skip(xin *x) { /* white space, comments, <?...?>, <!DOCTYPE ...> */
    for (;;) {
        while (x->p < x->end && (*x->p == ' ' || *x->p == '\t' || *x->p == '\n' || *x->p == '\r')) x->p++;
        if (x->end - x->p >= 4 && !memcmp(x->p, "<!--", 4)) { const char *e = x->p + 4; while (e + 3 <= x->end && memcmp(e, "-->", 3)) e++; x->p = e + 3 > x->end ? x->end : e + 3; continue; }
        if (x->end - x->p >= 2 && x->p[0] == '<' && (x->p[1] == '?' || x->p[1] == '!')) { while (x->p < x->end && *x->p != '>') x->p++; if (x->p < x->end) x->p++; continue; }
        return;
    }
}
static BOOL xml_lit(xin *x, const char *s) { size_t n = strlen(s); if ((size_t)(x->end - x->p) < n || memcmp(x->p, s, n)) return NO; x->p += n; return YES; }
/* text up to the next '<' with entities decoded */
static NSString *xml_text(xin *x) {
    NSMutableData *d = [NSMutableData data];
    while (x->p < x->end && *x->p != '<') {
        if (*x->p != '&') { [d appendBytes:x->p length:1]; x->p++; continue; }
        const char *semi = x->p; while (semi < x->end && *semi != ';' && semi - x->p < 12) semi++;
        if (semi >= x->end || *semi != ';') return nil;
        size_t n = (size_t)(semi - x->p - 1); const char *e = x->p + 1; char out[4]; int k = 0;
        if (n == 3 && !memcmp(e, "amp", 3)) out[k++] = '&'; else if (n == 2 && !memcmp(e, "lt", 2)) out[k++] = '<';
        else if (n == 2 && !memcmp(e, "gt", 2)) out[k++] = '>'; else if (n == 4 && !memcmp(e, "quot", 4)) out[k++] = '"';
        else if (n == 4 && !memcmp(e, "apos", 4)) out[k++] = '\'';
        else if (n > 1 && e[0] == '#') {
            unsigned long c = e[1] == 'x' ? strtoul(e + 2, 0, 16) : strtoul(e + 1, 0, 10);
            if (c < 0x80) out[k++] = (char)c;
            else if (c < 0x800) { out[k++] = (char)(0xc0 | c >> 6); out[k++] = (char)(0x80 | (c & 63)); }
            else if (c < 0x10000) { out[k++] = (char)(0xe0 | c >> 12); out[k++] = (char)(0x80 | (c >> 6 & 63)); out[k++] = (char)(0x80 | (c & 63)); }
            else { out[k++] = (char)(0xf0 | c >> 18); out[k++] = (char)(0x80 | (c >> 12 & 63)); out[k++] = (char)(0x80 | (c >> 6 & 63)); out[k++] = (char)(0x80 | (c & 63)); }
        } else return nil;
        [d appendBytes:out length:(NSUInteger)k]; x->p = semi + 1;
    }
    if (x->end - x->p >= 9 && !memcmp(x->p, "<![CDATA[", 9)) { /* CDATA sections: literal text */
        const char *e = x->p + 9; while (e + 3 <= x->end && memcmp(e, "]]>", 3)) e++;
        if (e + 3 > x->end) return nil;
        [d appendBytes:x->p + 9 length:(NSUInteger)(e - x->p - 9)]; x->p = e + 3;
        NSString *rest = xml_text(x); if (!rest) return nil;
        NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
        return s ? [s stringByAppendingString:rest] : nil;
    }
    return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
}
static id xml_value(xin *x, int depth);
/* <tag>text</tag> or <tag/>: the text */
static NSString *xml_simple(xin *x, const char *tag) {
    char open[32], close[32], empty[32];
    snprintf(open, sizeof open, "<%s>", tag); snprintf(close, sizeof close, "</%s>", tag); snprintf(empty, sizeof empty, "<%s/>", tag);
    if (xml_lit(x, empty)) return @"";
    if (!xml_lit(x, open)) return nil;
    NSString *t = xml_text(x);
    return t && xml_lit(x, close) ? t : nil;
}
static id xml_value(xin *x, int depth) {
    if (depth > 512) return nil;
    xml_skip(x);
    if (x->p >= x->end || *x->p != '<') return nil;
    if (xml_lit(x, "<true/>")) return [NSNumber numberWithBool:YES];
    if (xml_lit(x, "<false/>")) return [NSNumber numberWithBool:NO];
    if (xml_lit(x, "<dict/>")) return [NSMutableDictionary dictionary];
    if (xml_lit(x, "<array/>")) return [NSMutableArray array];
    if (xml_lit(x, "<dict>")) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (;;) {
            xml_skip(x);
            if (xml_lit(x, "</dict>")) return d;
            NSString *k = xml_simple(x, "key"); if (!k) return nil;
            id v = xml_value(x, depth + 1); if (!v) return nil;
            [d setObject:v forKey:k];
        }
    }
    if (xml_lit(x, "<array>")) {
        NSMutableArray *a = [NSMutableArray array];
        for (;;) {
            xml_skip(x);
            if (xml_lit(x, "</array>")) return a;
            id v = xml_value(x, depth + 1); if (!v) return nil;
            [a addObject:v];
        }
    }
    NSString *t;
    if ((t = xml_simple(x, "string"))) return x->leaves ? [[t mutableCopy] autorelease] : t;
    if ((t = xml_simple(x, "integer"))) {
        const char *c = [[t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] UTF8String];
        if (*c == '-') return [NSNumber numberWithLongLong:strtoll(c, 0, 0)];
        unsigned long long u = strtoull(c, 0, 0);
        return u > 0x7fffffffffffffffull ? [NSNumber numberWithUnsignedLongLong:u] : [NSNumber numberWithLongLong:(long long)u];
    }
    if ((t = xml_simple(x, "real"))) {
        NSString *v = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        double r = [v caseInsensitiveCompare:@"nan"] == NSOrderedSame ? 0.0 / 0.0 : [v caseInsensitiveCompare:@"+infinity"] == NSOrderedSame || [v caseInsensitiveCompare:@"infinity"] == NSOrderedSame ? 1.0 / 0.0
                 : [v caseInsensitiveCompare:@"-infinity"] == NSOrderedSame ? -1.0 / 0.0 : strtod([v UTF8String], 0);
        return [NSNumber numberWithDouble:r];
    }
    if ((t = xml_simple(x, "date"))) return [[[[NSISO8601DateFormatter alloc] init] autorelease] dateFromString:[t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    if ((t = xml_simple(x, "data"))) {
        NSData *d = [[[NSData alloc] initWithBase64EncodedString:t options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
        return d && x->leaves ? [[d mutableCopy] autorelease] : d;
    }
    return nil;
}
static id xml_read(NSData *data, BOOL leaves) {
    xin x = {[data bytes], (const char *)[data bytes] + [data length], leaves};
    if (x.end - x.p >= 3 && (unsigned char)x.p[0] == 0xef && (unsigned char)x.p[1] == 0xbb && (unsigned char)x.p[2] == 0xbf) x.p += 3; /* BOM */
    xml_skip(&x);
    BOOL wrapped = NO;
    if (xml_lit(&x, "<plist")) { while (x.p < x.end && *x.p != '>') x.p++; if (x.p >= x.end) return nil; x.p++; wrapped = YES; }
    id v = xml_value(&x, 0);
    if (!v) return nil;
    xml_skip(&x);
    if (wrapped && !xml_lit(&x, "</plist>")) return nil;
    return v;
}
static void xml_escape(NSMutableString *out, NSString *s) {
    NSUInteger n = [s length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '&') [out appendString:@"&amp;"]; else if (c == '<') [out appendString:@"&lt;"]; else if (c == '>') [out appendString:@"&gt;"];
        else [out appendString:[NSString stringWithCharacters:&c length:1]];
    }
}
static BOOL xml_write(NSMutableString *out, id o, int indent) {
    NSMutableString *tabs = [NSMutableString string]; for (int i = 0; i < indent; i++) [tabs appendString:@"\t"];
    if ([o isKindOfClass:[NSString class]]) { [out appendFormat:@"%@<string>", tabs]; xml_escape(out, o); [out appendString:@"</string>\n"]; }
    else if ([o isKindOfClass:[NSNumber class]]) {
        if (mw_number_is_bool(o)) [out appendFormat:@"%@<%@/>\n", tabs, [o boolValue] ? @"true" : @"false"];
        else if (mw_number_is_real(o)) [out appendFormat:@"%@<real>%.17g</real>\n", tabs, [o doubleValue]];
        else if (!strcmp([o objCType], "Q")) [out appendFormat:@"%@<integer>%llu</integer>\n", tabs, [o unsignedLongLongValue]];
        else [out appendFormat:@"%@<integer>%lld</integer>\n", tabs, [o longLongValue]];
    }
    else if ([o isKindOfClass:[NSData class]]) [out appendFormat:@"%@<data>\n%@%@\n%@</data>\n", tabs, tabs, [o base64EncodedStringWithOptions:0], tabs];
    else if ([o isKindOfClass:[NSDate class]]) [out appendFormat:@"%@<date>%@</date>\n", tabs, [[[[NSISO8601DateFormatter alloc] init] autorelease] stringFromDate:o]];
    else if ([o isKindOfClass:[NSArray class]]) {
        if (![o count]) { [out appendFormat:@"%@<array/>\n", tabs]; return YES; }
        [out appendFormat:@"%@<array>\n", tabs];
        for (id e in o) if (!xml_write(out, e, indent + 1)) return NO;
        [out appendFormat:@"%@</array>\n", tabs];
    } else if ([o isKindOfClass:[NSDictionary class]]) {
        if (![o count]) { [out appendFormat:@"%@<dict/>\n", tabs]; return YES; }
        [out appendFormat:@"%@<dict>\n", tabs];
        for (id k in [[o allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            if (![k isKindOfClass:[NSString class]]) return NO;
            [out appendFormat:@"%@\t<key>", tabs]; xml_escape(out, k); [out appendString:@"</key>\n"];
            if (!xml_write(out, [o objectForKey:k], indent + 1)) return NO;
        }
        [out appendFormat:@"%@</dict>\n", tabs];
    } else return NO;
    return YES;
}

/* ======================================================================= binary (bplist00) */
typedef struct { const uint8_t *b; NSUInteger n; uint64_t *offs; uint64_t count; unsigned refsz; BOOL leaves; uint8_t *busy; } bin;
static uint64_t be(const uint8_t *p, unsigned n) { uint64_t v = 0; for (unsigned i = 0; i < n; i++) v = v << 8 | p[i]; return v; }
static id bin_obj(bin *r, uint64_t idx, int depth);
/* the count after a marker: low nibble, or an int object when it is 0xF */
static BOOL bin_count(bin *r, NSUInteger *pos, unsigned nib, uint64_t *out) {
    if (nib != 0xf) { *out = nib; return YES; }
    if (*pos >= r->n) return NO;
    uint8_t m = r->b[*pos]; if ((m >> 4) != 1) return NO;
    unsigned sz = 1u << (m & 0xf); if (sz > 8 || *pos + 1 + sz > r->n) return NO;
    *out = be(r->b + *pos + 1, sz); *pos += 1 + sz; return YES;
}
static id bin_obj(bin *r, uint64_t idx, int depth) {
    if (idx >= r->count || depth > 512 || r->busy[idx]) return nil; /* cycles are corrupt */
    NSUInteger pos = (NSUInteger)r->offs[idx];
    if (pos >= r->n) return nil;
    uint8_t m = r->b[pos++]; unsigned hi = m >> 4, lo = m & 0xf; uint64_t cnt;
    switch (hi) {
    case 0x0: return m == 0x08 ? [NSNumber numberWithBool:NO] : m == 0x09 ? [NSNumber numberWithBool:YES] : nil;
    case 0x1: {
        unsigned sz = 1u << lo; if (sz > 16 || pos + sz > r->n) return nil;
        if (sz == 16) return [NSNumber numberWithLongLong:(long long)be(r->b + pos + 8, 8)];
        uint64_t v = be(r->b + pos, sz);
        return sz == 8 ? [NSNumber numberWithLongLong:(long long)v] : [NSNumber numberWithLongLong:(long long)v]; /* 1-4 byte ints are unsigned */
    }
    case 0x2: {
        if (lo == 2 && pos + 4 <= r->n) { uint32_t v = (uint32_t)be(r->b + pos, 4); float f; memcpy(&f, &v, 4); return [NSNumber numberWithDouble:f]; }
        if (lo == 3 && pos + 8 <= r->n) { uint64_t v = be(r->b + pos, 8); double d; memcpy(&d, &v, 8); return [NSNumber numberWithDouble:d]; }
        return nil;
    }
    case 0x3: {
        if (m != 0x33 || pos + 8 > r->n) return nil;
        uint64_t v = be(r->b + pos, 8); double d; memcpy(&d, &v, 8); return [NSDate dateWithTimeIntervalSinceReferenceDate:d];
    }
    case 0x4: case 0x5: case 0x6: {
        if (!bin_count(r, &pos, lo, &cnt)) return nil;
        uint64_t bytes = hi == 0x6 ? cnt * 2 : cnt;
        if (cnt > r->n || pos + bytes > r->n) return nil;
        if (hi == 0x4) { NSData *d = [NSData dataWithBytes:r->b + pos length:(NSUInteger)bytes]; return r->leaves ? [[d mutableCopy] autorelease] : d; }
        NSString *s;
        if (hi == 0x5) s = [[[NSString alloc] initWithBytes:r->b + pos length:(NSUInteger)bytes encoding:NSISOLatin1StringEncoding] autorelease];
        else {
            unichar *u = malloc((size_t)(cnt ? cnt : 1) * sizeof(unichar));
            for (uint64_t i = 0; i < cnt; i++) u[i] = (unichar)be(r->b + pos + i * 2, 2);
            s = mw_str_take(u, (NSUInteger)cnt);
        }
        return r->leaves ? [[s mutableCopy] autorelease] : s;
    }
    case 0x8: { /* UID (keyed archives): exposed like Apple's CFKeyedArchiverUID as a dictionary */
        unsigned sz = lo + 1; if (pos + sz > r->n) return nil;
        return @{@"CF$UID": [NSNumber numberWithLongLong:(long long)be(r->b + pos, sz)]};
    }
    case 0xa: case 0xc: case 0xd: {
        if (!bin_count(r, &pos, lo, &cnt)) return nil;
        uint64_t refs = hi == 0xd ? cnt * 2 : cnt;
        if (cnt > r->count || pos + refs * r->refsz > r->n) return nil;
        r->busy[idx] = 1;
        id result = nil;
        if (hi == 0xd) {
            NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)cnt];
            for (uint64_t i = 0; i < cnt; i++) {
                id k = bin_obj(r, be(r->b + pos + i * r->refsz, r->refsz), depth + 1), v = bin_obj(r, be(r->b + pos + (cnt + i) * r->refsz, r->refsz), depth + 1);
                if (!k || !v) { d = nil; break; }
                [d setObject:v forKey:k];
            }
            result = d;
        } else {
            NSMutableArray *a = [NSMutableArray arrayWithCapacity:(NSUInteger)cnt];
            for (uint64_t i = 0; i < cnt; i++) { id v = bin_obj(r, be(r->b + pos + i * r->refsz, r->refsz), depth + 1); if (!v) { a = nil; break; } [a addObject:v]; }
            result = hi == 0xc && a ? (id)[NSMutableSet setWithArray:a] : a;
        }
        r->busy[idx] = 0;
        return result;
    }
    }
    return nil;
}
static id bin_read(NSData *data, BOOL leaves) {
    const uint8_t *b = [data bytes]; NSUInteger n = [data length];
    if (n < 8 + 32 || memcmp(b, "bplist0", 7)) return nil;
    const uint8_t *t = b + n - 32;
    unsigned offsz = t[6], refsz = t[7]; uint64_t count = be(t + 8, 8), top = be(t + 16, 8), table = be(t + 24, 8);
    if (offsz < 1 || offsz > 8 || refsz < 1 || refsz > 8 || count == 0 || count > n || top >= count || table < 8 || table + count * offsz > n - 32) return nil;
    uint64_t *offs = malloc((size_t)count * sizeof *offs);
    for (uint64_t i = 0; i < count; i++) { offs[i] = be(b + table + i * offsz, offsz); if (offs[i] < 8 || offs[i] >= table) { free(offs); return nil; } }
    bin r = {b, n, offs, count, refsz, leaves, calloc((size_t)count, 1)};
    id v = bin_obj(&r, top, 0);
    free(offs); free(r.busy);
    return v;
}
/* writer: objects flattened depth-first (no sharing); kids[i] lists the object indices a container refers to */
static NSUInteger bin_flatten(id o, NSMutableArray *objs, NSMutableArray *kids) {
    NSUInteger i = [objs count]; [objs addObject:o]; [kids addObject:[NSNull null]];
    if ([o isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [o allKeys]; NSMutableArray *r = [NSMutableArray array];
        for (id k in keys) [r addObject:[NSNumber numberWithUnsignedInteger:bin_flatten(k, objs, kids)]];
        for (id k in keys) [r addObject:[NSNumber numberWithUnsignedInteger:bin_flatten([o objectForKey:k], objs, kids)]];
        kids[i] = r;
    } else if ([o isKindOfClass:[NSArray class]]) {
        NSMutableArray *r = [NSMutableArray array];
        for (id e in o) [r addObject:[NSNumber numberWithUnsignedInteger:bin_flatten(e, objs, kids)]];
        kids[i] = r;
    }
    return i;
}
static void bin_marker(NSMutableData *d, uint8_t hi, NSUInteger cnt) {
    uint8_t m = (uint8_t)(hi << 4 | (cnt < 15 ? cnt : 15)); [d appendBytes:&m length:1];
    if (cnt >= 15) {
        uint8_t im[9]; unsigned sz = cnt < 256 ? 1 : cnt < 65536 ? 2 : cnt <= 0xffffffffu ? 4 : 8; im[0] = (uint8_t)(0x10 | (sz == 1 ? 0 : sz == 2 ? 1 : sz == 4 ? 2 : 3));
        for (unsigned i = 0; i < sz; i++) im[1 + i] = (uint8_t)((uint64_t)cnt >> (8 * (sz - 1 - i)));
        [d appendBytes:im length:1 + sz];
    }
}
static void put_be(NSMutableData *d, uint64_t v, unsigned sz) { uint8_t b[8]; for (unsigned i = 0; i < sz; i++) b[i] = (uint8_t)(v >> (8 * (sz - 1 - i))); [d appendBytes:b length:sz]; }
static NSData *bin_write(id root) {
    NSMutableArray *objs = [NSMutableArray array], *kids = [NSMutableArray array];
    bin_flatten(root, objs, kids);
    NSUInteger count = [objs count]; unsigned refsz = count < 256 ? 1 : count < 65536 ? 2 : 4;
    NSMutableData *d = [NSMutableData dataWithBytes:"bplist00" length:8];
    uint64_t *offs = malloc(count * sizeof *offs);
    for (NSUInteger i = 0; i < count; i++) {
        id o = objs[i]; offs[i] = [d length];
        if ([o isKindOfClass:[NSNumber class]]) {
            uint8_t m;
            if (mw_number_is_bool(o)) { m = [o boolValue] ? 0x09 : 0x08; [d appendBytes:&m length:1]; }
            else if (mw_number_is_real(o)) { double v = [o doubleValue]; uint64_t u; memcpy(&u, &v, 8); m = 0x23; [d appendBytes:&m length:1]; put_be(d, u, 8); }
            else {
                long long v = [o longLongValue]; unsigned sz = v < 0 ? 8 : v < 256 ? 1 : v < 65536 ? 2 : v <= 0xffffffffll ? 4 : 8;
                m = (uint8_t)(0x10 | (sz == 1 ? 0 : sz == 2 ? 1 : sz == 4 ? 2 : 3)); [d appendBytes:&m length:1]; put_be(d, (uint64_t)v, sz);
            }
        } else if ([o isKindOfClass:[NSDate class]]) {
            double v = [o timeIntervalSinceReferenceDate]; uint64_t u; memcpy(&u, &v, 8); uint8_t m = 0x33; [d appendBytes:&m length:1]; put_be(d, u, 8);
        } else if ([o isKindOfClass:[NSData class]]) { bin_marker(d, 0x4, [o length]); [d appendData:o]; }
        else if ([o isKindOfClass:[NSString class]]) {
            NSData *a = [o dataUsingEncoding:NSASCIIStringEncoding];
            if (a) { bin_marker(d, 0x5, [a length]); [d appendData:a]; }
            else { NSUInteger n = [o length]; bin_marker(d, 0x6, n); for (NSUInteger j = 0; j < n; j++) put_be(d, [o characterAtIndex:j], 2); }
        } else if ([o isKindOfClass:[NSDictionary class]] || [o isKindOfClass:[NSArray class]]) {
            NSArray *r = kids[i]; BOOL dict = [o isKindOfClass:[NSDictionary class]];
            bin_marker(d, dict ? 0xd : 0xa, dict ? [r count] / 2 : [r count]);
            for (NSNumber *k in r) put_be(d, [k unsignedLongLongValue], refsz);
        } else { free(offs); return nil; }
    }
    uint64_t table = [d length]; unsigned offsz = table < 256 ? 1 : table < 65536 ? 2 : table <= 0xffffffffu ? 4 : 8;
    for (NSUInteger i = 0; i < count; i++) put_be(d, offs[i], offsz);
    uint8_t trailer[8] = {0}; trailer[6] = (uint8_t)offsz; trailer[7] = (uint8_t)refsz;
    [d appendBytes:trailer length:8]; put_be(d, count, 8); put_be(d, 0, 8); put_be(d, table, 8);
    free(offs);
    return d;
}

/* ======================================================================= OpenStep (old ASCII) and .strings */
typedef struct { const unichar *u; NSUInteger i, n; BOOL leaves; } oin;
static void os_skip(oin *x) {
    for (;;) {
        while (x->i < x->n && (x->u[x->i] == ' ' || x->u[x->i] == '\t' || x->u[x->i] == '\n' || x->u[x->i] == '\r' || x->u[x->i] == 0xfeff)) x->i++;
        if (x->i + 1 < x->n && x->u[x->i] == '/' && x->u[x->i + 1] == '/') { while (x->i < x->n && x->u[x->i] != '\n') x->i++; continue; }
        if (x->i + 1 < x->n && x->u[x->i] == '/' && x->u[x->i + 1] == '*') {
            x->i += 2; while (x->i + 1 < x->n && !(x->u[x->i] == '*' && x->u[x->i + 1] == '/')) x->i++; x->i = x->i + 2 > x->n ? x->n : x->i + 2; continue;
        }
        return;
    }
}
static BOOL os_bare(unichar c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '$' || c == '/' || c == ':' || c == '.' || c == '-'; }
static NSString *os_string(oin *x) {
    if (x->i >= x->n) return nil;
    unichar q = x->u[x->i];
    if (q == '"' || q == '\'') {
        x->i++; NSMutableString *s = [NSMutableString string];
        while (x->i < x->n && x->u[x->i] != q) {
            unichar c = x->u[x->i++];
            if (c == '\\' && x->i < x->n) {
                c = x->u[x->i++];
                switch (c) {
                case 'n': c = '\n'; break; case 't': c = '\t'; break; case 'r': c = '\r'; break; case 'a': c = 7; break; case 'b': c = 8; break;
                case 'f': c = 12; break; case 'v': c = 11; break;
                case 'U': case 'u': { unsigned v = 0; for (int k = 0; k < 4 && x->i < x->n && isxdigit(x->u[x->i] < 128 ? x->u[x->i] : 0); k++) v = v * 16 + (unsigned)(isdigit(x->u[x->i]) ? x->u[x->i] - '0' : (x->u[x->i] | 32) - 'a' + 10), x->i++; c = (unichar)v; break; }
                default: if (c >= '0' && c <= '7') { unsigned v = c - '0'; for (int k = 0; k < 2 && x->i < x->n && x->u[x->i] >= '0' && x->u[x->i] <= '7'; k++) v = v * 8 + (x->u[x->i++] - '0'); c = (unichar)v; }
                }
            }
            [s appendString:[NSString stringWithCharacters:&c length:1]];
        }
        if (x->i >= x->n) return nil;
        x->i++;
        return s;
    }
    NSUInteger a = x->i; while (x->i < x->n && os_bare(x->u[x->i])) x->i++;
    return x->i > a ? [NSString stringWithCharacters:x->u + a length:x->i - a] : nil;
}
static id os_value(oin *x, int depth);
static NSMutableDictionary *os_dict_body(oin *x, unichar end, int depth) { /* key = value; ... up to end (or the end of the text when 0) */
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (;;) {
        os_skip(x);
        if (end ? (x->i < x->n && x->u[x->i] == end) : x->i >= x->n) { if (end) x->i++; return d; }
        NSString *k = os_string(x); if (!k) return nil;
        os_skip(x);
        id v;
        if (x->i < x->n && x->u[x->i] == '=') { x->i++; v = os_value(x, depth + 1); if (!v) return nil; os_skip(x); }
        else v = k; /* "key"; in .strings means key = key */
        if (x->i >= x->n || x->u[x->i] != ';') { if (!end && x->i >= x->n) { [d setObject:v forKey:k]; return d; } return nil; }
        x->i++;
        [d setObject:v forKey:k];
    }
}
static id os_value(oin *x, int depth) {
    if (depth > 512) return nil;
    os_skip(x);
    if (x->i >= x->n) return nil;
    unichar c = x->u[x->i];
    if (c == '{') { x->i++; return os_dict_body(x, '}', depth); }
    if (c == '(') {
        x->i++; NSMutableArray *a = [NSMutableArray array];
        for (;;) {
            os_skip(x);
            if (x->i < x->n && x->u[x->i] == ')') { x->i++; return a; }
            id v = os_value(x, depth + 1); if (!v) return nil;
            [a addObject:v]; os_skip(x);
            if (x->i < x->n && x->u[x->i] == ',') x->i++;
            else if (!(x->i < x->n && x->u[x->i] == ')')) return nil;
        }
    }
    if (c == '<') {
        x->i++; NSMutableData *d = [NSMutableData data]; int hi = -1;
        while (x->i < x->n && x->u[x->i] != '>') {
            unichar h = x->u[x->i++]; int v = h >= '0' && h <= '9' ? h - '0' : (h | 32) >= 'a' && (h | 32) <= 'f' ? (h | 32) - 'a' + 10 : -1;
            if (v < 0) { if (h == ' ' || h == '\n' || h == '\t' || h == '\r') continue; return nil; }
            if (hi < 0) hi = v; else { uint8_t b = (uint8_t)(hi << 4 | v); [d appendBytes:&b length:1]; hi = -1; }
        }
        if (x->i >= x->n || hi >= 0) return nil;
        x->i++; return d;
    }
    NSString *s = os_string(x);
    return s && x->leaves ? [[s mutableCopy] autorelease] : s;
}
static NSString *text_of(NSData *data) {
    const uint8_t *b = [data bytes]; NSUInteger n = [data length];
    if (n >= 2 && ((b[0] == 0xff && b[1] == 0xfe) || (b[0] == 0xfe && b[1] == 0xff)))
        return [[[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding] autorelease];
    NSString *s = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    return s ? s : [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
}
static id os_read(NSData *data, BOOL leaves) {
    NSString *s = text_of(data); if (!s) return nil;
    NSUInteger n; unichar *u = mw_chars(s, &n);
    oin x = {u, 0, n, leaves};
    os_skip(&x);
    id v;
    NSUInteger save = x.i;
    /* a .strings file is a dictionary without its braces: try "key = value;" first when the text does not start with a container */
    if (x.i < x.n && x.u[x.i] != '{' && x.u[x.i] != '(' && x.u[x.i] != '<') { v = os_dict_body(&x, 0, 0); if (!v) { x.i = save; v = os_value(&x, 0); } }
    else v = os_value(&x, 0);
    if (v) { os_skip(&x); if (x.i != x.n) v = nil; }
    free(u);
    return v;
}
static void os_write(NSMutableString *out, id o) {
    if ([o isKindOfClass:[NSString class]]) {
        BOOL bare = [o length] > 0; for (NSUInteger i = 0; i < [o length] && bare; i++) bare = os_bare([o characterAtIndex:i]);
        if (bare) { [out appendString:o]; return; }
        [out appendString:@"\""];
        for (NSUInteger i = 0; i < [o length]; i++) { unichar c = [o characterAtIndex:i]; if (c == '"' || c == '\\') [out appendString:@"\\"]; if (c == '\n') [out appendString:@"\\n"]; else [out appendString:[NSString stringWithCharacters:&c length:1]]; }
        [out appendString:@"\""];
    } else if ([o isKindOfClass:[NSData class]]) {
        [out appendString:@"<"]; const uint8_t *b = [o bytes]; for (NSUInteger i = 0; i < [o length]; i++) [out appendFormat:@"%02x", b[i]]; [out appendString:@">"];
    } else if ([o isKindOfClass:[NSArray class]]) {
        [out appendString:@"("]; BOOL first = YES; for (id e in o) { if (!first) [out appendString:@", "]; first = NO; os_write(out, e); } [out appendString:@")"];
    } else if ([o isKindOfClass:[NSDictionary class]]) {
        [out appendString:@"{"]; for (id k in [[o allKeys] sortedArrayUsingSelector:@selector(compare:)]) { os_write(out, k); [out appendString:@" = "]; os_write(out, [o objectForKey:k]); [out appendString:@"; "]; } [out appendString:@"}"];
    } else os_write(out, [o description]);
}

/* ======================================================================= NSPropertyListSerialization */
@implementation NSPropertyListSerialization
+ (BOOL)propertyList:(id)p isValidForFormat:(NSPropertyListFormat)f {
    if (!is_plist_object(p)) return NO;
    if ([p isKindOfClass:[NSArray class]]) { for (id e in p) if (![self propertyList:e isValidForFormat:f]) return NO; }
    else if ([p isKindOfClass:[NSDictionary class]]) for (id k in p) if (![k isKindOfClass:[NSString class]] || ![self propertyList:[p objectForKey:k] isValidForFormat:f]) return NO;
    return YES;
}
+ (NSData *)dataWithPropertyList:(id)p format:(NSPropertyListFormat)f options:(NSPropertyListWriteOptions)o error:(NSError **)e {
    if (![self propertyList:p isValidForFormat:f]) { if (e) *e = plist_error(3851, @"Property list invalid for format"); return nil; }
    if (f == NSPropertyListBinaryFormat_v1_0) { NSData *d = bin_write(p); if (!d && e) *e = plist_error(3851, @"Property list invalid for format"); return d; }
    NSMutableString *s = [NSMutableString string];
    if (f == NSPropertyListOpenStepFormat) os_write(s, p);
    else {
        [s appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n"];
        xml_write(s, p, 0);
        [s appendString:@"</plist>\n"];
    }
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}
+ (id)propertyListWithData:(NSData *)d options:(NSPropertyListReadOptions)o format:(NSPropertyListFormat *)f error:(NSError **)e {
    BOOL leaves = o == NSPropertyListMutableContainersAndLeaves; id v = nil; NSPropertyListFormat fmt = 0;
    if ([d length] >= 6 && !memcmp([d bytes], "bplist", 6)) { v = bin_read(d, leaves); fmt = NSPropertyListBinaryFormat_v1_0; }
    else {
        /* UTF-16 text (Xcode writes .strings that way): parse its UTF-8 form */
        const unsigned char *u = [d bytes];
        if ([d length] >= 2 && ((u[0] == 0xff && u[1] == 0xfe) || (u[0] == 0xfe && u[1] == 0xff))) {
            NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF16StringEncoding] autorelease];
            NSData *u8 = [s dataUsingEncoding:NSUTF8StringEncoding];
            if (u8) return [self propertyListWithData:u8 options:o format:f error:e];
        }
        /* XML when the first non-blank character is '<' followed by '?', '!' or a plist tag; OpenStep otherwise */
        const char *b = [d bytes], *end = b + [d length]; if (end - b >= 3 && (unsigned char)b[0] == 0xef) b += 3;
        while (b < end && (*b == ' ' || *b == '\n' || *b == '\r' || *b == '\t')) b++;
        if (b + 1 < end && b[0] == '<' && (b[1] == '?' || b[1] == '!' || b[1] == 'p' || b[1] == 'd' || b[1] == 'a' || b[1] == 's')) {
            v = xml_read(d, leaves); fmt = NSPropertyListXMLFormat_v1_0;
        }
        if (!v) { v = os_read(d, leaves); fmt = NSPropertyListOpenStepFormat; }
    }
    if (!v) { if (e) *e = plist_error(3840, @"The data couldn't be read because it isn't in the correct format."); return nil; }
    if (f) *f = fmt;
    return v;
}
+ (id)propertyListFromData:(NSData *)d mutabilityOption:(NSPropertyListMutabilityOptions)o format:(NSPropertyListFormat *)f errorDescription:(NSString **)err {
    NSError *e = nil; id v = [self propertyListWithData:d options:o format:f error:&e];
    if (!v && err) *err = [e localizedDescription];
    return v;
}
+ (NSData *)dataFromPropertyList:(id)p format:(NSPropertyListFormat)f errorDescription:(NSString **)err {
    NSError *e = nil; NSData *d = [self dataWithPropertyList:p format:f options:0 error:&e];
    if (!d && err) *err = [e localizedDescription];
    return d;
}
+ (id)propertyListWithStream:(id)s options:(NSPropertyListReadOptions)o format:(NSPropertyListFormat *)f error:(NSError **)e {
    if (e) *e = plist_error(3840, @"Streams are not supported"); return nil; /* ponytail: no stream reading */
}
@end

/* ======================================================================= collections from and to files */
static id plist_file(NSString *p, Class want) {
    NSData *d = p ? [NSData dataWithContentsOfFile:p] : nil;
    id v = d ? [NSPropertyListSerialization propertyListWithData:d options:0 format:0 error:0] : nil;
    return [v isKindOfClass:want] ? v : nil;
}
static BOOL write_plist(id o, NSString *path, BOOL atomic, NSError **e) {
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:o format:NSPropertyListXMLFormat_v1_0 options:0 error:e];
    return d && [d writeToFile:path options:atomic ? NSDataWritingAtomic : 0 error:e];
}
@implementation NSDictionary (MWPropertyList)
+ (instancetype)dictionaryWithContentsOfFile:(NSString *)p { NSDictionary *d = plist_file(p, [NSDictionary class]); return d ? [self dictionaryWithDictionary:d] : nil; }
+ (instancetype)dictionaryWithContentsOfURL:(NSURL *)u { return [u isFileURL] ? [self dictionaryWithContentsOfFile:[u path]] : nil; }
+ (instancetype)dictionaryWithContentsOfURL:(NSURL *)u error:(NSError **)e {
    id d = [self dictionaryWithContentsOfURL:u]; if (!d && e) *e = plist_error(3840, @"The file couldn't be read."); return d;
}
- (instancetype)initWithContentsOfFile:(NSString *)p { NSDictionary *d = plist_file(p, [NSDictionary class]); if (!d) { [self release]; return nil; } return [self initWithDictionary:d]; }
- (instancetype)initWithContentsOfURL:(NSURL *)u { return [self initWithContentsOfFile:[u isFileURL] ? [u path] : nil]; }
- (instancetype)initWithContentsOfURL:(NSURL *)u error:(NSError **)e { self = [self initWithContentsOfURL:u]; if (!self && e) *e = plist_error(3840, @"The file couldn't be read."); return self; }
- (BOOL)writeToFile:(NSString *)p atomically:(BOOL)a { return write_plist(self, p, a, 0); }
- (BOOL)writeToURL:(NSURL *)u atomically:(BOOL)a { return [u isFileURL] && write_plist(self, [u path], a, 0); }
- (BOOL)writeToURL:(NSURL *)u error:(NSError **)e { return [u isFileURL] && write_plist(self, [u path], YES, e); }
@end
@implementation NSArray (MWPropertyList)
+ (instancetype)arrayWithContentsOfFile:(NSString *)p { NSArray *a = plist_file(p, [NSArray class]); return a ? [self arrayWithArray:a] : nil; }
+ (instancetype)arrayWithContentsOfURL:(NSURL *)u { return [u isFileURL] ? [self arrayWithContentsOfFile:[u path]] : nil; }
+ (instancetype)arrayWithContentsOfURL:(NSURL *)u error:(NSError **)e { id a = [self arrayWithContentsOfURL:u]; if (!a && e) *e = plist_error(3840, @"The file couldn't be read."); return a; }
- (instancetype)initWithContentsOfFile:(NSString *)p { NSArray *a = plist_file(p, [NSArray class]); if (!a) { [self release]; return nil; } return [self initWithArray:a]; }
- (instancetype)initWithContentsOfURL:(NSURL *)u { return [self initWithContentsOfFile:[u isFileURL] ? [u path] : nil]; }
- (instancetype)initWithContentsOfURL:(NSURL *)u error:(NSError **)e { self = [self initWithContentsOfURL:u]; if (!self && e) *e = plist_error(3840, @"The file couldn't be read."); return self; }
- (BOOL)writeToFile:(NSString *)p atomically:(BOOL)a { return write_plist(self, p, a, 0); }
- (BOOL)writeToURL:(NSURL *)u atomically:(BOOL)a { return [u isFileURL] && write_plist(self, [u path], a, 0); }
- (BOOL)writeToURL:(NSURL *)u error:(NSError **)e { return [u isFileURL] && write_plist(self, [u path], YES, e); }
@end

/* ======================================================================= NSBundle */
char ***_NSGetArgv(void);
const char *dyld_image_path_containing_address(const void *addr);
const char *class_getImageName(Class c);
void *dlopen(const char *, int);
static NSMutableDictionary *bundles_by_path; /* every bundle made, so a path gives back the same object */
@implementation NSBundle { NSString *_path; NSDictionary *_info; NSMutableDictionary *_tables; BOOL _loaded; }
static NSString *bundle_root_of_executable(NSString *exe) {
    /* .../X.app/Contents/MacOS/X -> .../X.app; .../Y.framework/Versions/A/Y -> .../Y.framework/Versions/A */
    NSString *dir = [exe stringByDeletingLastPathComponent];
    if ([[dir lastPathComponent] isEqualToString:@"MacOS"] && [[[dir stringByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"Contents"])
        return [[dir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    return dir;
}
+ (NSBundle *)mainBundle {
    static NSBundle *m;
    @synchronized(self) {
        if (!m) {
            char **av = *_NSGetArgv(); NSString *exe = av && av[0] ? [NSString stringWithUTF8String:av[0]] : @"";
            m = [[NSBundle bundleWithPath:bundle_root_of_executable(exe)] retain];
            if (!m) m = [[NSBundle bundleWithPath:@"."] retain];
        }
    }
    return m;
}
+ (instancetype)bundleWithPath:(NSString *)p { return [[[self alloc] initWithPath:p] autorelease]; }
+ (instancetype)bundleWithURL:(NSURL *)u { return [self bundleWithPath:[u path]]; }
- (instancetype)initWithURL:(NSURL *)u { return [self initWithPath:[u path]]; }
- (instancetype)initWithPath:(NSString *)p {
    BOOL dir = NO;
    if (!p || ![[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&dir] || !dir) { [self release]; return nil; }
    p = [p stringByStandardizingPath];
    @synchronized([NSBundle class]) {
        if (!bundles_by_path) bundles_by_path = [[NSMutableDictionary alloc] init];
        NSBundle *old = bundles_by_path[p];
        if (old) { [self release]; return [old retain]; }
        _path = [p copy];
        bundles_by_path[p] = self;
    }
    return self;
}
- (void)dealloc { [_path release]; [_info release]; [_tables release]; [super dealloc]; }
+ (NSBundle *)bundleWithIdentifier:(NSString *)ident {
    if ([[[self mainBundle] bundleIdentifier] isEqualToString:ident]) return [self mainBundle];
    @synchronized(self) { for (NSBundle *b in [bundles_by_path allValues]) if ([[b bundleIdentifier] isEqualToString:ident]) return b; }
    return nil;
}
+ (NSBundle *)bundleForClass:(Class)c {
    const char *img = c ? class_getImageName(c) : 0;
    NSString *exe = img ? [NSString stringWithUTF8String:img] : nil;
    NSBundle *b = exe ? [self bundleWithPath:bundle_root_of_executable(exe)] : nil;
    return b && [b infoDictionary][@"CFBundleIdentifier"] ? b : [self mainBundle];
}
+ (NSArray *)allBundles { return @[[self mainBundle]]; }
+ (NSArray *)allFrameworks { return @[]; }
- (NSString *)bundlePath { return _path; }
- (NSURL *)bundleURL { return [NSURL fileURLWithPath:_path isDirectory:YES]; }
- (NSString *)_contents { NSString *c = [_path stringByAppendingPathComponent:@"Contents"]; return [[NSFileManager defaultManager] fileExistsAtPath:c] ? c : _path; }
- (NSString *)resourcePath {
    NSString *c = [[self _contents] stringByAppendingPathComponent:@"Resources"];
    return [[NSFileManager defaultManager] fileExistsAtPath:c] ? c : _path;
}
- (NSURL *)resourceURL { return [NSURL fileURLWithPath:[self resourcePath] isDirectory:YES]; }
- (NSDictionary *)infoDictionary {
    @synchronized(self) {
        if (!_info) {
            NSDictionary *d = nil;
            for (NSString *p in @[[[self _contents] stringByAppendingPathComponent:@"Info.plist"], [[self resourcePath] stringByAppendingPathComponent:@"Info.plist"]])
                if ((d = [NSDictionary dictionaryWithContentsOfFile:p])) break;
            _info = [(d ? d : @{}) retain];
        }
        return _info;
    }
}
- (NSDictionary *)localizedInfoDictionary {   /* read once: apps ask for it often (objectForInfoDictionaryKey:) */
    NSDictionary *c = objc_getAssociatedObject(self, "mw_locinfo");
    if (c) return c;
    NSString *p = [self pathForResource:@"InfoPlist" ofType:@"strings"];
    NSDictionary *loc = p ? plist_file(p, [NSDictionary class]) : nil;
    NSDictionary *d = [self infoDictionary];
    if (loc) { NSMutableDictionary *m = [[d mutableCopy] autorelease]; [m addEntriesFromDictionary:loc]; d = m; }
    objc_setAssociatedObject(self, "mw_locinfo", d, OBJC_ASSOCIATION_RETAIN);
    return d;
}
- (NSString *)bundleIdentifier { return [self infoDictionary][@"CFBundleIdentifier"]; }
- (id)objectForInfoDictionaryKey:(NSString *)k { id v = [self localizedInfoDictionary][k]; return v ? v : [self infoDictionary][k]; }
- (NSString *)executablePath {
    NSString *name = [self infoDictionary][@"CFBundleExecutable"]; if (!name) name = [[_path lastPathComponent] stringByDeletingPathExtension];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *c in @[[[self _contents] stringByAppendingPathComponent:[@"MacOS" stringByAppendingPathComponent:name]], [_path stringByAppendingPathComponent:name]])
        if ([fm fileExistsAtPath:c]) return c;
    return nil;
}
- (NSURL *)executableURL { NSString *p = [self executablePath]; return p ? [NSURL fileURLWithPath:p] : nil; }
- (NSString *)privateFrameworksPath { return [[self _contents] stringByAppendingPathComponent:@"Frameworks"]; }
- (NSString *)sharedFrameworksPath { return [[self _contents] stringByAppendingPathComponent:@"SharedFrameworks"]; }
- (NSString *)builtInPlugInsPath { return [[self _contents] stringByAppendingPathComponent:@"PlugIns"]; }
- (NSString *)sharedSupportPath { return [[self _contents] stringByAppendingPathComponent:@"SharedSupport"]; }
- (NSURL *)privateFrameworksURL { return [NSURL fileURLWithPath:[self privateFrameworksPath] isDirectory:YES]; }
- (NSURL *)sharedFrameworksURL { return [NSURL fileURLWithPath:[self sharedFrameworksPath] isDirectory:YES]; }
- (NSURL *)builtInPlugInsURL { return [NSURL fileURLWithPath:[self builtInPlugInsPath] isDirectory:YES]; }
- (NSURL *)sharedSupportURL { return [NSURL fileURLWithPath:[self sharedSupportPath] isDirectory:YES]; }
- (NSURL *)appStoreReceiptURL { return [NSURL fileURLWithPath:[[self _contents] stringByAppendingPathComponent:@"_MASReceipt/receipt"]]; }
/* localizations: the *.lproj folders; the preferred one follows the user's language, then English, then Base */
- (NSArray *)localizations {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self resourcePath] error:0])
        if ([[f pathExtension] isEqualToString:@"lproj"]) [a addObject:[f stringByDeletingPathExtension]];
    return a;
}
+ (NSArray *)preferredLocalizationsFromArray:(NSArray *)have forPreferences:(NSArray *)prefs {
    if (!prefs) prefs = [NSLocale preferredLanguages];
    for (NSString *p in prefs) {
        NSString *lang = [[p componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_"]] firstObject];
        for (NSString *h in have) if ([h caseInsensitiveCompare:p] == NSOrderedSame) return @[h];
        for (NSString *h in have) if ([h caseInsensitiveCompare:lang] == NSOrderedSame || [[h lowercaseString] hasPrefix:[[lang lowercaseString] stringByAppendingString:@"-"]]) return @[h];
    }
    for (NSString *h in @[@"en", @"English", @"Base"]) if ([have containsObject:h]) return @[h];
    return [have count] ? @[have[0]] : @[];
}
+ (NSArray *)preferredLocalizationsFromArray:(NSArray *)have { return [self preferredLocalizationsFromArray:have forPreferences:nil]; }
- (NSArray *)preferredLocalizations { return [NSBundle preferredLocalizationsFromArray:[self localizations]]; }
- (NSString *)developmentLocalization { NSString *d = [self infoDictionary][@"CFBundleDevelopmentRegion"]; return d ? d : @"en"; }
- (NSArray *)_lprojs { /* search order for localized resources */
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *l in [self preferredLocalizations]) [a addObject:[l stringByAppendingPathExtension:@"lproj"]];
    for (NSString *l in @[@"Base", [self developmentLocalization], @"en", @"English"]) { NSString *f = [l stringByAppendingPathExtension:@"lproj"]; if (![a containsObject:f]) [a addObject:f]; }
    return a;
}
- (NSString *)pathForResource:(NSString *)n ofType:(NSString *)t inDirectory:(NSString *)sub forLocalization:(NSString *)loc {
    NSString *file = [t length] ? ([n length] ? [n stringByAppendingPathExtension:[t hasPrefix:@"."] ? [t substringFromIndex:1] : t] : nil) : n;
    if (!file) { /* first file of that type */
        NSArray *all = [self pathsForResourcesOfType:t inDirectory:sub]; return [all count] ? all[0] : nil;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [self resourcePath]; if ([sub length]) base = [base stringByAppendingPathComponent:sub];
    NSString *direct = [base stringByAppendingPathComponent:file];
    if (!loc && [fm fileExistsAtPath:direct]) return direct;
    for (NSString *l in loc ? @[[loc stringByAppendingPathExtension:@"lproj"]] : [self _lprojs]) {
        NSString *c = [[base stringByAppendingPathComponent:l] stringByAppendingPathComponent:file];
        if ([fm fileExistsAtPath:c]) return c;
    }
    return nil;
}
- (NSString *)pathForResource:(NSString *)n ofType:(NSString *)t inDirectory:(NSString *)sub { return [self pathForResource:n ofType:t inDirectory:sub forLocalization:nil]; }
- (NSString *)pathForResource:(NSString *)n ofType:(NSString *)t { return [self pathForResource:n ofType:t inDirectory:nil forLocalization:nil]; }
+ (NSString *)pathForResource:(NSString *)n ofType:(NSString *)t inDirectory:(NSString *)d { return [[NSBundle bundleWithPath:d] pathForResource:n ofType:t]; }
- (NSArray *)pathsForResourcesOfType:(NSString *)t inDirectory:(NSString *)sub {
    NSMutableArray *out = [NSMutableArray array]; NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [self resourcePath]; if ([sub length]) base = [base stringByAppendingPathComponent:sub];
    NSMutableArray *dirs = [NSMutableArray arrayWithObject:base];
    for (NSString *l in [self _lprojs]) [dirs addObject:[base stringByAppendingPathComponent:l]];
    for (NSString *d in dirs) for (NSString *f in [fm contentsOfDirectoryAtPath:d error:0])
        if (![t length] || [[f pathExtension] isEqualToString:t]) [out addObject:[d stringByAppendingPathComponent:f]];
    return out;
}
- (NSURL *)URLForResource:(NSString *)n withExtension:(NSString *)e subdirectory:(NSString *)s localization:(NSString *)l {
    NSString *p = [self pathForResource:n ofType:e inDirectory:s forLocalization:l]; return p ? [NSURL fileURLWithPath:p] : nil;
}
- (NSURL *)URLForResource:(NSString *)n withExtension:(NSString *)e subdirectory:(NSString *)s { return [self URLForResource:n withExtension:e subdirectory:s localization:nil]; }
- (NSURL *)URLForResource:(NSString *)n withExtension:(NSString *)e { return [self URLForResource:n withExtension:e subdirectory:nil localization:nil]; }
- (NSArray *)URLsForResourcesWithExtension:(NSString *)e subdirectory:(NSString *)s {
    NSMutableArray *a = [NSMutableArray array]; for (NSString *p in [self pathsForResourcesOfType:e inDirectory:s]) [a addObject:[NSURL fileURLWithPath:p]]; return a;
}
- (NSURL *)URLForAuxiliaryExecutable:(NSString *)n { NSString *p = [[[self _contents] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:n]; return [NSURL fileURLWithPath:p]; }
- (NSString *)pathForAuxiliaryExecutable:(NSString *)n { return [[self URLForAuxiliaryExecutable:n] path]; }
/* strings tables: Localizable.strings (or .stringsdict, ignored) in the preferred .lproj, cached per table */
- (NSString *)localizedStringForKey:(NSString *)k value:(NSString *)v table:(NSString *)t {
    if (!k) return [v length] ? v : @"";
    if (![t length]) t = @"Localizable";
    NSDictionary *tab;
    @synchronized(self) {
        if (!_tables) _tables = [[NSMutableDictionary alloc] init];
        tab = _tables[t];
        if (!tab) {
            NSString *p = [self pathForResource:t ofType:@"strings"];
            tab = (p ? plist_file(p, [NSDictionary class]) : nil) ?: @{};
            _tables[t] = tab;
        }
    }
    NSString *s = tab[k];
    return [s isKindOfClass:[NSString class]] ? s : [v length] ? v : k;
}
- (NSAttributedString *)localizedAttributedStringForKey:(NSString *)k value:(NSString *)v table:(NSString *)t { return (id)[self localizedStringForKey:k value:v table:t]; }
- (BOOL)load {
    if (_loaded || self == [NSBundle mainBundle]) return _loaded = YES;
    NSString *exe = [self executablePath];
    _loaded = exe && dlopen([exe fileSystemRepresentation], 2) != 0;
    return _loaded;
}
- (BOOL)loadAndReturnError:(NSError **)e { BOOL ok = [self load]; if (!ok && e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:3587 userInfo:nil]; return ok; }
- (BOOL)preflightAndReturnError:(NSError **)e { return [self executablePath] != nil; }
- (BOOL)isLoaded { return _loaded || self == [NSBundle mainBundle]; }
- (BOOL)unload { return NO; }
- (Class)classNamed:(NSString *)n { [self load]; return NSClassFromString(n); }
- (Class)principalClass { [self load]; NSString *n = [self infoDictionary][@"NSPrincipalClass"]; return n ? NSClassFromString(n) : Nil; }
- (NSArray *)executableArchitectures { return @[@0x01000007, @0x0100000c]; }
- (NSString *)description { return [NSString stringWithFormat:@"NSBundle <%@> (%@)", _path, [self isLoaded] ? @"loaded" : @"not yet loaded"]; }
@end

/* ======================================================================= NSUserDefaults (saved as a binary plist in ~/Library/Preferences) */
NSString *const NSGlobalDomain = @"NSGlobalDomain", *const NSArgumentDomain = @"NSArgumentDomain", *const NSRegistrationDomain = @"NSRegistrationDomain";
NSNotificationName const NSUserDefaultsDidChangeNotification = @"NSUserDefaultsDidChangeNotification";
static NSMutableArray *all_defaults; /* every NSUserDefaults with a file, flushed at exit */
@implementation NSUserDefaults { NSMutableDictionary *_d, *_reg, *_args; NSString *_file; NSLock *_l; BOOL _dirty; }
static NSString *prefs_file(NSString *domain) {
    return [[[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"] stringByAppendingPathComponent:domain] stringByAppendingPathExtension:@"plist"];
}
static void flush_all(void) { @synchronized([NSUserDefaults class]) { for (NSUserDefaults *u in all_defaults) [u synchronize]; } }
- (instancetype)initWithSuiteName:(NSString *)suite {
    NSString *domain = suite;
    if (!domain) { domain = [[NSBundle mainBundle] bundleIdentifier]; if (!domain) domain = [[NSProcessInfo processInfo] processName]; }
    _l = [[NSLock alloc] init]; _reg = [[NSMutableDictionary alloc] init]; _args = [[NSMutableDictionary alloc] init];
    _file = [prefs_file(domain) copy];
    NSDictionary *saved = plist_file(_file, [NSDictionary class]);
    _d = saved ? [saved mutableCopy] : [[NSMutableDictionary alloc] init];
    /* -Key value on the command line overrides (the argument domain) */
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    for (NSUInteger i = 1; i + 1 < [args count]; i++) {
        NSString *a = args[i];
        if ([a length] > 1 && [a hasPrefix:@"-"] && ![a hasPrefix:@"--"]) {
            NSData *vd = [args[i + 1] dataUsingEncoding:NSUTF8StringEncoding];
            id v = os_read(vd, NO); _args[[a substringFromIndex:1]] = v ? v : args[i + 1]; i++;
        }
    }
    @synchronized([NSUserDefaults class]) {
        if (!all_defaults) { all_defaults = [[NSMutableArray alloc] init]; atexit(flush_all); }
        [all_defaults addObject:self];
    }
    return self;
}
- (instancetype)init { return [self initWithSuiteName:nil]; }
- (instancetype)initWithUser:(NSString *)u { return [self initWithSuiteName:nil]; }
- (void)dealloc { [_d release]; [_reg release]; [_args release]; [_file release]; [_l release]; [super dealloc]; }
+ (NSUserDefaults *)standardUserDefaults {
    static NSUserDefaults *u;
    @synchronized(self) { if (!u) u = [[NSUserDefaults alloc] init]; }
    return u;
}
+ (void)resetStandardUserDefaults { [[self standardUserDefaults] synchronize]; }
- (id)objectForKey:(NSString *)k {
    if (!k) return nil;
    [_l lock]; id o = _args[k]; if (!o) o = _d[k]; if (!o) o = _reg[k]; o = [[o retain] autorelease]; [_l unlock];
    return o;
}
- (void)setObject:(id)o forKey:(NSString *)k {
    if (!k) return;
    if (o && ![NSPropertyListSerialization propertyList:o isValidForFormat:NSPropertyListBinaryFormat_v1_0])
        mw_raise("NSInvalidArgumentException", "Attempt to insert non-property list object for key");
    [self willChangeValueForKey:k]; if (mw_defaults_change_hook) mw_defaults_change_hook(k, NO);
    [_l lock]; id copy = [o copy]; [_d setObject:copy forKeyedSubscript:k]; [copy release]; _dirty = YES; [_l unlock];
    [self didChangeValueForKey:k]; if (mw_defaults_change_hook) mw_defaults_change_hook(k, YES);
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}
- (void)removeObjectForKey:(NSString *)k { [self setObject:nil forKey:k]; }
void (*mw_defaults_change_hook)(NSString *key, BOOL did);
- (id)valueForKey:(NSString *)k { return [self objectForKey:k]; }
- (void)setValue:(id)v forKey:(NSString *)k { [self setObject:v forKey:k]; }
- (NSString *)stringForKey:(NSString *)k { id o = [self objectForKey:k]; return [o isKindOfClass:[NSString class]] ? o : [o isKindOfClass:[NSNumber class]] ? [o stringValue] : nil; }
- (NSArray *)arrayForKey:(NSString *)k { id o = [self objectForKey:k]; return [o isKindOfClass:[NSArray class]] ? o : nil; }
- (NSDictionary *)dictionaryForKey:(NSString *)k { id o = [self objectForKey:k]; return [o isKindOfClass:[NSDictionary class]] ? o : nil; }
- (NSData *)dataForKey:(NSString *)k { id o = [self objectForKey:k]; return [o isKindOfClass:[NSData class]] ? o : nil; }
- (NSArray *)stringArrayForKey:(NSString *)k { NSArray *a = [self arrayForKey:k]; for (id e in a) if (![e isKindOfClass:[NSString class]]) return nil; return a; }
static double num_of(id o) { return [o isKindOfClass:[NSNumber class]] || [o isKindOfClass:[NSString class]] ? [o doubleValue] : 0; }
- (NSInteger)integerForKey:(NSString *)k { id o = [self objectForKey:k]; return [o isKindOfClass:[NSNumber class]] || [o isKindOfClass:[NSString class]] ? [o integerValue] : 0; }
- (float)floatForKey:(NSString *)k { return (float)num_of([self objectForKey:k]); }
- (double)doubleForKey:(NSString *)k { return num_of([self objectForKey:k]); }
- (BOOL)boolForKey:(NSString *)k {
    id o = [self objectForKey:k];
    if ([o isKindOfClass:[NSString class]]) return [o caseInsensitiveCompare:@"YES"] == NSOrderedSame || [o caseInsensitiveCompare:@"true"] == NSOrderedSame || [o integerValue] != 0;
    return [o isKindOfClass:[NSNumber class]] ? [o boolValue] : NO;
}
- (NSURL *)URLForKey:(NSString *)k {
    id o = [self objectForKey:k];
    if ([o isKindOfClass:[NSString class]]) return [NSURL fileURLWithPath:[o stringByExpandingTildeInPath]];
    if ([o isKindOfClass:[NSData class]]) { NSString *s = [[[NSString alloc] initWithData:o encoding:NSUTF8StringEncoding] autorelease]; return s ? [NSURL URLWithString:s] : nil; }
    return nil;
}
- (void)setInteger:(NSInteger)v forKey:(NSString *)k { [self setObject:[NSNumber numberWithInteger:v] forKey:k]; }
- (void)setFloat:(float)v forKey:(NSString *)k { [self setObject:[NSNumber numberWithDouble:v] forKey:k]; }
- (void)setDouble:(double)v forKey:(NSString *)k { [self setObject:[NSNumber numberWithDouble:v] forKey:k]; }
- (void)setBool:(BOOL)v forKey:(NSString *)k { [self setObject:[NSNumber numberWithBool:v] forKey:k]; }
- (void)setURL:(NSURL *)u forKey:(NSString *)k { [self setObject:u ? [[u absoluteString] dataUsingEncoding:NSUTF8StringEncoding] : nil forKey:k]; }
- (void)registerDefaults:(NSDictionary *)d { [_l lock]; [_reg addEntriesFromDictionary:d]; [_l unlock]; }
- (NSDictionary *)dictionaryRepresentation {
    [_l lock]; NSMutableDictionary *r = [_reg mutableCopy]; [r addEntriesFromDictionary:_d]; [r addEntriesFromDictionary:_args]; [_l unlock];
    return [r autorelease];
}
- (NSArray *)volatileDomainNames { return @[NSArgumentDomain, NSRegistrationDomain]; }
- (NSDictionary *)volatileDomainForName:(NSString *)n { return [n isEqualToString:NSArgumentDomain] ? _args : [n isEqualToString:NSRegistrationDomain] ? _reg : @{}; }
- (NSDictionary *)persistentDomainForName:(NSString *)n {
    NSString *me = [[_file lastPathComponent] stringByDeletingPathExtension];
    if ([n isEqualToString:me]) { [_l lock]; NSDictionary *c = [[_d copy] autorelease]; [_l unlock]; return c; }
    return plist_file(prefs_file(n), [NSDictionary class]);
}
- (void)setPersistentDomain:(NSDictionary *)d forName:(NSString *)n {
    NSString *me = [[_file lastPathComponent] stringByDeletingPathExtension];
    if ([n isEqualToString:me]) { [_l lock]; [_d setDictionary:d]; _dirty = YES; [_l unlock]; [self synchronize]; return; }
    [[NSFileManager defaultManager] createDirectoryAtPath:[prefs_file(n) stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:0];
    [[NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListBinaryFormat_v1_0 options:0 error:0] writeToFile:prefs_file(n) atomically:YES];
}
- (void)removePersistentDomainForName:(NSString *)n { [self setPersistentDomain:@{} forName:n]; }
- (void)addSuiteNamed:(NSString *)s {} - (void)removeSuiteNamed:(NSString *)s {}
- (BOOL)objectIsForcedForKey:(NSString *)k { return NO; }
- (BOOL)synchronize {
    [_l lock];
    if (!_dirty) { [_l unlock]; return YES; }
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:_d format:NSPropertyListBinaryFormat_v1_0 options:0 error:0];
    _dirty = NO;
    [_l unlock];
    [[NSFileManager defaultManager] createDirectoryAtPath:[_file stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:0];
    return d && [d writeToFile:_file atomically:YES];
}
@end
