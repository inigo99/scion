/* NSString.m — scion Foundation: strings (UTF-16 storage), constant strings, character sets. MRC. */
#import "internal.h"

/* ---------------- UTF-8 <-> UTF-16 ---------------- */
unichar *mw_utf8_to_utf16(const char *s, size_t n, NSUInteger *outn) {
    unichar *u = malloc((n + 1) * sizeof(unichar)); NSUInteger k = 0;
    for (size_t i = 0; i < n;) {
        unsigned c = (unsigned char)s[i]; uint32_t cp; int len;
        if (c < 0x80) { cp = c; len = 1; }
        else if ((c >> 5) == 6 && i + 1 < n) { cp = (c & 31) << 6 | (s[i + 1] & 63); len = 2; }
        else if ((c >> 4) == 14 && i + 2 < n) { cp = (c & 15) << 12 | (s[i + 1] & 63) << 6 | (s[i + 2] & 63); len = 3; }
        else if ((c >> 3) == 30 && i + 3 < n) { cp = (c & 7) << 18 | (s[i + 1] & 63) << 12 | (s[i + 2] & 63) << 6 | (s[i + 3] & 63); len = 4; }
        else { cp = 0xFFFD; len = 1; }
        i += len;
        if (cp >= 0x10000) { cp -= 0x10000; u[k++] = (unichar)(0xD800 | cp >> 10); u[k++] = (unichar)(0xDC00 | (cp & 0x3FF)); }
        else u[k++] = (unichar)cp;
    }
    *outn = k; return u;
}
char *mw_utf16_to_utf8(const unichar *u, NSUInteger n, size_t *outn) {
    char *s = malloc(n * 3 + 1); size_t k = 0;
    for (NSUInteger i = 0; i < n; i++) {
        uint32_t c = u[i];
        if (c >= 0xD800 && c < 0xDC00 && i + 1 < n && u[i + 1] >= 0xDC00 && u[i + 1] < 0xE000) { c = 0x10000 + ((c - 0xD800) << 10) + (u[i + 1] - 0xDC00); i++; }
        if (c < 0x80) s[k++] = (char)c;
        else if (c < 0x800) { s[k++] = (char)(0xC0 | c >> 6); s[k++] = (char)(0x80 | (c & 63)); }
        else if (c < 0x10000) { s[k++] = (char)(0xE0 | c >> 12); s[k++] = (char)(0x80 | (c >> 6 & 63)); s[k++] = (char)(0x80 | (c & 63)); }
        else { s[k++] = (char)(0xF0 | c >> 18); s[k++] = (char)(0x80 | (c >> 12 & 63)); s[k++] = (char)(0x80 | (c >> 6 & 63)); s[k++] = (char)(0x80 | (c & 63)); }
    }
    s[k] = 0; if (outn) *outn = k; return s;
}
/* malloc'd copy of a string's UTF-16 contents */
unichar *mw_chars(NSString *s, NSUInteger *n) {
    *n = [s length];
    unichar *u = malloc((*n + 1) * sizeof(unichar));
    [s getCharacters:u range:NSMakeRange(0, *n)];
    return u;
}
NSString *mw_str_take(unichar *u, NSUInteger n) { return [[[__NSStringImpl alloc] _initTakingUTF16:u length:n] autorelease]; }
NSString *mw_str_utf8(const char *s) { return [NSString stringWithUTF8String:s]; }
static int fold(int c) { return c < 128 ? tolower(c) : c; }

/* ================================================================ NSString (abstract: primitives only) */
@implementation NSString
+ (id)allocWithZone:(NSZone *)z { return self == [NSString class] ? (id)class_createInstance([__NSStringImpl class], 0) : (id)class_createInstance(self, 0); }
+ (id)alloc { return [self allocWithZone:0]; }
+ (instancetype)string { return [[[self alloc] _initTakingUTF16:malloc(2) length:0] autorelease]; }
+ (instancetype)stringWithString:(NSString *)s { return [[[self alloc] initWithString:s] autorelease]; }
+ (instancetype)stringWithUTF8String:(const char *)s { return s ? [[[self alloc] initWithUTF8String:s] autorelease] : nil; }
+ (instancetype)stringWithCString:(const char *)s encoding:(NSStringEncoding)e { return s ? [[[self alloc] initWithBytes:s length:strlen(s) encoding:e] autorelease] : nil; }
+ (instancetype)stringWithCharacters:(const unichar *)c length:(NSUInteger)n { return [[[self alloc] initWithCharacters:c length:n] autorelease]; }
+ (instancetype)stringWithFormat:(NSString *)f, ... { va_list ap; va_start(ap, f); id r = [[[self alloc] initWithFormat:f arguments:ap] autorelease]; va_end(ap); return r; }
+ (instancetype)stringWithContentsOfFile:(NSString *)p encoding:(NSStringEncoding)e error:(NSError **)err {
    NSData *d = [NSData dataWithContentsOfFile:p];
    if (!d) { if (err) *err = mw_posix_error(errno, p); return nil; }
    return [[[self alloc] initWithData:d encoding:e] autorelease];
}
+ (instancetype)stringWithContentsOfFile:(NSString *)p usedEncoding:(NSStringEncoding *)e error:(NSError **)err { if (e) *e = NSUTF8StringEncoding; return [self stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:err]; }
- (instancetype)_initTakingUTF16:(unichar *)u length:(NSUInteger)n { [self doesNotRecognizeSelector:_cmd]; return nil; }
- (instancetype)init { return [self _initTakingUTF16:malloc(2) length:0]; }
- (instancetype)initWithUTF8String:(const char *)s { NSUInteger n; unichar *u = mw_utf8_to_utf16(s, strlen(s), &n); return [self _initTakingUTF16:u length:n]; }
- (instancetype)initWithString:(NSString *)s { NSUInteger n; unichar *u = mw_chars(s, &n); return [self _initTakingUTF16:u length:n]; }
- (instancetype)initWithCharacters:(const unichar *)c length:(NSUInteger)n { unichar *u = malloc((n + 1) * 2); memcpy(u, c, n * 2); return [self _initTakingUTF16:u length:n]; }
- (instancetype)initWithCharactersNoCopy:(unichar *)c length:(NSUInteger)n freeWhenDone:(BOOL)f { id r = [self initWithCharacters:c length:n]; if (f) free(c); return r; }
- (instancetype)initWithBytes:(const void *)b length:(NSUInteger)n encoding:(NSStringEncoding)e {
    const unsigned char *p = b; NSUInteger k = 0; unichar *u;
    if (e == NSUTF16StringEncoding || e == NSUTF16LittleEndianStringEncoding || e == 0x90000100 /* UTF16BE */) {
        int be = e == 0x90000100;
        if (n >= 2 && p[0] == 0xFF && p[1] == 0xFE) { p += 2; n -= 2; be = 0; }
        else if (n >= 2 && p[0] == 0xFE && p[1] == 0xFF) { p += 2; n -= 2; be = 1; }
        u = malloc(n + 2); k = n / 2;
        for (NSUInteger i = 0; i < k; i++) u[i] = be ? (unichar)(p[2 * i] << 8 | p[2 * i + 1]) : (unichar)(p[2 * i] | p[2 * i + 1] << 8);
    } else if (e == NSISOLatin1StringEncoding || e == 12 /* WindowsCP1252 */ || e == 30 /* MacRoman approx */) {
        u = malloc((n + 1) * 2); for (k = 0; k < n; k++) u[k] = p[k];
    } else {
        if (e == NSASCIIStringEncoding) for (NSUInteger i = 0; i < n; i++) if (p[i] >= 128) { [self release]; return nil; }
        if (n >= 3 && p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF) { p += 3; n -= 3; }
        u = mw_utf8_to_utf16((const char *)p, n, &k);
    }
    return [self _initTakingUTF16:u length:k];
}
- (instancetype)initWithData:(NSData *)d encoding:(NSStringEncoding)e { return [self initWithBytes:[d bytes] length:[d length] encoding:e]; }
- (instancetype)initWithFormat:(NSString *)f, ... { va_list ap; va_start(ap, f); id r = [self initWithFormat:f arguments:ap]; va_end(ap); return r; }
- (instancetype)initWithFormat:(NSString *)f arguments:(va_list)ap {
    char *s = 0; vasprintf(&s, [f UTF8String], ap);
    id r = [self initWithUTF8String:s ? s : ""]; free(s); return r;
}
- (instancetype)initWithFormat:(NSString *)f locale:(id)l, ... { va_list ap; va_start(ap, l); id r = [self initWithFormat:f arguments:ap]; va_end(ap); return r; }
+ (instancetype)localizedStringWithFormat:(NSString *)f, ... { va_list ap; va_start(ap, f); id r = [[[self alloc] initWithFormat:f arguments:ap] autorelease]; va_end(ap); return r; }

- (NSUInteger)length { [self doesNotRecognizeSelector:_cmd]; return 0; }
- (unichar)characterAtIndex:(NSUInteger)i { unichar c; [self getCharacters:&c range:NSMakeRange(i, 1)]; return c; }
- (void)getCharacters:(unichar *)buf range:(NSRange)r { for (NSUInteger i = 0; i < r.length; i++) buf[i] = [self characterAtIndex:r.location + i]; }
- (void)getCharacters:(unichar *)buf { [self getCharacters:buf range:NSMakeRange(0, [self length])]; }
- (const char *)UTF8String {
    NSUInteger n; unichar *u = mw_chars(self, &n);
    char *s = mw_utf16_to_utf8(u, n, 0); free(u);
    return [[NSData dataWithBytesNoCopy:s length:strlen(s) + 1 freeWhenDone:YES] bytes]; /* lives as long as the pool */
}
- (const char *)cStringUsingEncoding:(NSStringEncoding)e { return [self UTF8String]; }
- (const char *)cString { return [self UTF8String]; }
- (const char *)fileSystemRepresentation { return [self UTF8String]; }
- (BOOL)getFileSystemRepresentation:(char *)buf maxLength:(NSUInteger)n { return [self getCString:buf maxLength:n encoding:NSUTF8StringEncoding]; }
- (BOOL)getCString:(char *)buf maxLength:(NSUInteger)n encoding:(NSStringEncoding)e {
    const char *s = [self UTF8String]; size_t l = strlen(s);
    if (l + 1 > n) return NO;
    memcpy(buf, s, l + 1); return YES;
}
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)e { return e == NSUTF16StringEncoding ? [self length] * 2 : strlen([self UTF8String]); }
- (NSUInteger)maximumLengthOfBytesUsingEncoding:(NSStringEncoding)e { return [self length] * 3; }
- (NSData *)dataUsingEncoding:(NSStringEncoding)e {
    if (e == NSUTF16StringEncoding || e == NSUTF16LittleEndianStringEncoding) {
        NSUInteger n; unichar *u = mw_chars(self, &n);
        NSMutableData *d = [NSMutableData data];
        if (e == NSUTF16StringEncoding) { unichar bom = 0xFEFF; [d appendBytes:&bom length:2]; }
        [d appendBytes:u length:n * 2]; free(u); return d;
    }
    if (e == NSISOLatin1StringEncoding || e == NSASCIIStringEncoding) {
        NSUInteger n; unichar *u = mw_chars(self, &n); char *b = malloc(n + 1);
        for (NSUInteger i = 0; i < n; i++) { if (u[i] > (e == NSASCIIStringEncoding ? 127 : 255)) { free(u); free(b); return nil; } b[i] = (char)u[i]; }
        free(u); return [NSData dataWithBytesNoCopy:b length:n freeWhenDone:YES];
    }
    const char *s = [self UTF8String];
    return [NSData dataWithBytes:s length:strlen(s)];
}
- (NSData *)dataUsingEncoding:(NSStringEncoding)e allowLossyConversion:(BOOL)l { return [self dataUsingEncoding:e]; }

/* identity */
- (NSUInteger)hash {
    NSUInteger n; unichar *u = mw_chars(self, &n); uint64_t h = 1469598103934665603ull;
    for (NSUInteger i = 0; i < n; i++) h = (h ^ u[i]) * 1099511628211ull;
    free(u); return (NSUInteger)h;
}
- (BOOL)isEqualToString:(NSString *)o {
    if (o == self) return YES;
    if (!o) return NO;
    NSUInteger a = [self length]; if ([o length] != a) return NO;
    NSUInteger n1, n2; unichar *u = mw_chars(self, &n1), *v = mw_chars(o, &n2);
    BOOL eq = !memcmp(u, v, a * 2); free(u); free(v); return eq;
}
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSString class]] && [self isEqualToString:o]); }
- (id)copyWithZone:(NSZone *)z { return [[NSString alloc] initWithString:self]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableString alloc] initWithString:self]; }
- (NSString *)description { return self; }
- (NSString *)debugDescription { return self; }

/* comparison */
- (NSComparisonResult)compare:(NSString *)s options:(NSStringCompareOptions)o range:(NSRange)r {
    NSUInteger n1, n2; unichar *a = mw_chars(self, &n1), *b = mw_chars(s, &n2);
    a += r.location; n1 = r.length;
    NSComparisonResult res = NSOrderedSame; NSUInteger i = 0, j = 0;
    while (i < n1 && j < n2) {
        if ((o & NSNumericSearch) && a[i] < 128 && b[j] < 128 && isdigit(a[i]) && isdigit(b[j])) {
            NSUInteger si = i, sj = j;
            while (si < n1 && a[si] == '0') si++;
            while (sj < n2 && b[sj] == '0') sj++;
            NSUInteger ei = si, ej = sj;
            while (ei < n1 && a[ei] < 128 && isdigit(a[ei])) ei++;
            while (ej < n2 && b[ej] < 128 && isdigit(b[ej])) ej++;
            if (ei - si != ej - sj) { res = ei - si < ej - sj ? NSOrderedAscending : NSOrderedDescending; break; }
            for (; si < ei; si++, sj++) if (a[si] != b[sj]) { res = a[si] < b[sj] ? NSOrderedAscending : NSOrderedDescending; break; }
            if (res != NSOrderedSame) break;
            i = ei; j = ej; continue;
        }
        int x = a[i], y = b[j];
        if (o & NSCaseInsensitiveSearch) x = fold(x), y = fold(y);
        if (x != y) { res = x < y ? NSOrderedAscending : NSOrderedDescending; break; }
        i++; j++;
    }
    if (res == NSOrderedSame && (i < n1 || j < n2)) res = i < n1 ? NSOrderedDescending : NSOrderedAscending;
    free(a - r.location); free(b);
    return res;
}
- (NSComparisonResult)compare:(NSString *)s options:(NSStringCompareOptions)o { return [self compare:s options:o range:NSMakeRange(0, [self length])]; }
- (NSComparisonResult)compare:(NSString *)s { return [self compare:s options:0]; }
- (NSComparisonResult)caseInsensitiveCompare:(NSString *)s { return [self compare:s options:NSCaseInsensitiveSearch]; }
- (NSComparisonResult)localizedCompare:(NSString *)s { return [self compare:s]; }
- (NSComparisonResult)localizedCaseInsensitiveCompare:(NSString *)s { return [self compare:s options:NSCaseInsensitiveSearch]; }
- (NSComparisonResult)localizedStandardCompare:(NSString *)s { return [self compare:s options:NSCaseInsensitiveSearch | NSNumericSearch]; }

/* searching */
- (NSRange)rangeOfString:(NSString *)s options:(NSStringCompareOptions)o range:(NSRange)r {
    if (o & NSRegularExpressionSearch) { extern NSRange mw_regex_range(NSString *, NSString *, NSUInteger, NSRange); return mw_regex_range(self, s, o, r); }
    NSUInteger n1, n2; unichar *a = mw_chars(self, &n1), *b = mw_chars(s, &n2);
    NSRange res = {NSNotFound, 0};
    if (n2 && n2 <= r.length) {
        NSUInteger last = r.location + r.length - n2;
        for (NSUInteger k = 0; k <= r.length - n2; k++) {
            NSUInteger i = (o & NSBackwardsSearch) ? last - k : r.location + k;
            BOOL m = YES;
            for (NSUInteger j = 0; j < n2 && m; j++) m = (o & NSCaseInsensitiveSearch) ? fold(a[i + j]) == fold(b[j]) : a[i + j] == b[j];
            if (m) { res = NSMakeRange(i, n2); break; }
            if (o & NSAnchoredSearch) break;
        }
    }
    free(a); free(b); return res;
}
- (NSRange)rangeOfString:(NSString *)s options:(NSStringCompareOptions)o { return [self rangeOfString:s options:o range:NSMakeRange(0, [self length])]; }
- (NSRange)rangeOfString:(NSString *)s { return [self rangeOfString:s options:0]; }
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set options:(NSStringCompareOptions)o range:(NSRange)r {
    NSUInteger n; unichar *a = mw_chars(self, &n); NSRange res = {NSNotFound, 0};
    for (NSUInteger k = 0; k < r.length; k++) { NSUInteger i = (o & NSBackwardsSearch) ? r.location + r.length - 1 - k : r.location + k; if ([set characterIsMember:a[i]]) { res = NSMakeRange(i, 1); break; } }
    free(a); return res;
}
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set { return [self rangeOfCharacterFromSet:set options:0 range:NSMakeRange(0, [self length])]; }
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set options:(NSStringCompareOptions)o { return [self rangeOfCharacterFromSet:set options:o range:NSMakeRange(0, [self length])]; }
- (BOOL)hasPrefix:(NSString *)s { return [s length] && [self rangeOfString:s options:NSAnchoredSearch].location == 0; }
- (BOOL)hasSuffix:(NSString *)s { return [s length] && [self rangeOfString:s options:NSAnchoredSearch | NSBackwardsSearch].location != NSNotFound; }
- (BOOL)containsString:(NSString *)s { return [self rangeOfString:s].location != NSNotFound; }
- (BOOL)localizedCaseInsensitiveContainsString:(NSString *)s { return [self rangeOfString:s options:NSCaseInsensitiveSearch].location != NSNotFound; }

/* derived strings */
- (NSString *)substringWithRange:(NSRange)r {
    if (NSMaxRange(r) > [self length]) mw_raise("NSRangeException", "substringWithRange: range out of bounds");
    unichar *u = malloc((r.length + 1) * 2); [self getCharacters:u range:r]; return mw_str_take(u, r.length);
}
- (NSString *)substringFromIndex:(NSUInteger)i { return [self substringWithRange:NSMakeRange(i, [self length] - i)]; }
- (NSString *)substringToIndex:(NSUInteger)i { return [self substringWithRange:NSMakeRange(0, i)]; }
- (NSString *)stringByAppendingString:(NSString *)s {
    NSUInteger a = [self length], b = [s length]; unichar *u = malloc((a + b + 1) * 2);
    [self getCharacters:u range:NSMakeRange(0, a)]; [s getCharacters:u + a range:NSMakeRange(0, b)];
    return mw_str_take(u, a + b);
}
- (NSString *)stringByAppendingFormat:(NSString *)f, ... { va_list ap; va_start(ap, f); NSString *t = [[[NSString alloc] initWithFormat:f arguments:ap] autorelease]; va_end(ap); return [self stringByAppendingString:t]; }
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)a withString:(NSString *)b options:(NSStringCompareOptions)o range:(NSRange)r {
    NSMutableString *m = [[self mutableCopy] autorelease];
    [m replaceOccurrencesOfString:a withString:b options:o range:r];
    return [NSString stringWithString:m];
}
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)a withString:(NSString *)b { return [self stringByReplacingOccurrencesOfString:a withString:b options:0 range:NSMakeRange(0, [self length])]; }
- (NSString *)stringByReplacingCharactersInRange:(NSRange)r withString:(NSString *)s { NSMutableString *m = [[self mutableCopy] autorelease]; [m replaceCharactersInRange:r withString:s]; return [NSString stringWithString:m]; }
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set {
    NSUInteger n; unichar *u = mw_chars(self, &n), b = 0, e = 0; (void)b; (void)e;
    NSUInteger s = 0, t = n;
    while (s < t && [set characterIsMember:u[s]]) s++;
    while (t > s && [set characterIsMember:u[t - 1]]) t--;
    free(u); return [self substringWithRange:NSMakeRange(s, t - s)];
}
- (NSString *)stringByPaddingToLength:(NSUInteger)len withString:(NSString *)pad startingAtIndex:(NSUInteger)i {
    NSMutableString *m = [NSMutableString string]; NSUInteger n = [self length];
    if (len <= n) return [self substringToIndex:len];
    [m appendString:self];
    while ([m length] < len) { [m appendString:[pad substringWithRange:NSMakeRange(i % [pad length], 1)]]; i++; }
    return m;
}
- (NSArray *)componentsSeparatedByString:(NSString *)sep {
    NSMutableArray *a = [NSMutableArray array]; NSUInteger n = [self length], pos = 0;
    for (;;) {
        NSRange r = [self rangeOfString:sep options:0 range:NSMakeRange(pos, n - pos)];
        if (r.location == NSNotFound) { [a addObject:[self substringFromIndex:pos]]; break; }
        [a addObject:[self substringWithRange:NSMakeRange(pos, r.location - pos)]];
        pos = NSMaxRange(r);
    }
    return a;
}
- (NSArray *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)set {
    NSMutableArray *a = [NSMutableArray array]; NSUInteger n; unichar *u = mw_chars(self, &n), st = 0; NSUInteger s = 0; (void)st;
    for (NSUInteger i = 0; i <= n; i++) if (i == n || [set characterIsMember:u[i]]) { [a addObject:mw_str_take(memcpy(malloc((i - s + 1) * 2), u + s, (i - s) * 2), i - s)]; s = i + 1; }
    free(u); return a;
}
- (NSString *)_mapCase:(int)mode {
    NSUInteger n; unichar *u = mw_chars(self, &n); BOOL word = YES;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = u[i];
        if (mode == 0) u[i] = (c >= 'A' && c <= 'Z') || (c >= 0xC0 && c <= 0xDE && c != 0xD7) ? c + 32 : c;
        else if (mode == 1) u[i] = (c >= 'a' && c <= 'z') || (c >= 0xE0 && c <= 0xFE && c != 0xF7) ? c - 32 : c;
        else { u[i] = word ? ((c >= 'a' && c <= 'z') ? c - 32 : c) : ((c >= 'A' && c <= 'Z') ? c + 32 : c); word = c == ' ' || c == '\t' || c == '\n'; }
    }
    return mw_str_take(u, n);
}
- (NSString *)lowercaseString { return [self _mapCase:0]; }
- (NSString *)uppercaseString { return [self _mapCase:1]; }
- (NSString *)capitalizedString { return [self _mapCase:2]; }
- (int)intValue { return (int)strtol([self UTF8String], 0, 10); }
- (NSInteger)integerValue { return strtol([self UTF8String], 0, 10); }
- (long long)longLongValue { return strtoll([self UTF8String], 0, 10); }
- (double)doubleValue { return strtod([self UTF8String], 0); }
- (float)floatValue { return (float)strtod([self UTF8String], 0); }
- (BOOL)boolValue {
    const char *s = [self UTF8String]; while (isspace((unsigned char)*s)) s++;
    if (*s == '+' || *s == '-') s++;
    while (*s == '0') s++;
    return *s == 'Y' || *s == 'y' || *s == 'T' || *s == 't' || (*s >= '1' && *s <= '9');
}
- (void)enumerateLinesUsingBlock:(void (^)(NSString *, BOOL *))b {
    NSArray *lines = [[self stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"];
    BOOL stop = NO; NSUInteger n = [lines count];
    if (n && ![[lines lastObject] length]) n--;
    for (NSUInteger i = 0; i < n && !stop; i++) b([lines objectAtIndex:i], &stop);
}
- (NSUInteger)_firstNonWS { return 0; }

/* paths */
- (NSArray *)pathComponents {
    NSMutableArray *a = [NSMutableArray array];
    if ([self hasPrefix:@"/"]) [a addObject:@"/"];
    for (NSString *c in [self componentsSeparatedByString:@"/"]) if ([c length]) [a addObject:c];
    if ([self length] > 1 && [self hasSuffix:@"/"]) [a addObject:@"/"];
    return a;
}
- (BOOL)isAbsolutePath { return [self hasPrefix:@"/"] || [self hasPrefix:@"~"]; }
- (NSString *)_trimSlash { NSString *s = self; while ([s length] > 1 && [s hasSuffix:@"/"]) s = [s substringToIndex:[s length] - 1]; return s; }
- (NSString *)lastPathComponent {
    NSString *s = [self _trimSlash];
    NSRange r = [s rangeOfString:@"/" options:NSBackwardsSearch];
    return r.location == NSNotFound || [s length] == 1 ? s : [s substringFromIndex:r.location + 1];
}
- (NSString *)stringByDeletingLastPathComponent {
    NSString *s = [self _trimSlash];
    NSRange r = [s rangeOfString:@"/" options:NSBackwardsSearch];
    if (r.location == NSNotFound) return @"";
    if (r.location == 0) return @"/";
    return [s substringToIndex:r.location];
}
+ (NSString *)pathWithComponents:(NSArray *)c { NSString *p = @""; for (NSString *x in c) p = [p stringByAppendingPathComponent:x]; return p; }
- (NSString *)stringByAppendingPathComponent:(NSString *)c {
    if (![self length]) return c;
    if (![c length]) return self;
    return [([self hasSuffix:@"/"] ? self : [self stringByAppendingString:@"/"]) stringByAppendingString:([c hasPrefix:@"/"] ? [c substringFromIndex:1] : c)];
}
- (NSString *)pathExtension {
    NSString *l = [self lastPathComponent]; NSRange r = [l rangeOfString:@"." options:NSBackwardsSearch];
    return r.location == NSNotFound || r.location == 0 ? @"" : [l substringFromIndex:r.location + 1];
}
- (NSString *)stringByDeletingPathExtension {
    NSString *e = [self pathExtension];
    return [e length] ? [[self _trimSlash] substringToIndex:[[self _trimSlash] length] - [e length] - 1] : self;
}
- (NSString *)stringByAppendingPathExtension:(NSString *)e { return [[self _trimSlash] stringByAppendingFormat:@".%@", e]; }
- (NSString *)stringByExpandingTildeInPath {
    if (![self hasPrefix:@"~"]) return self;
    return [NSHomeDirectory() stringByAppendingString:[self substringFromIndex:1]];
}
- (NSString *)stringByStandardizingPath { return [[self stringByExpandingTildeInPath] _trimSlash]; }
- (NSString *)stringByResolvingSymlinksInPath { return [self stringByStandardizingPath]; }
- (BOOL)writeToFile:(NSString *)p atomically:(BOOL)a encoding:(NSStringEncoding)e error:(NSError **)err {
    BOOL ok = [[self dataUsingEncoding:e] writeToFile:p atomically:a];
    if (!ok && err) *err = mw_posix_error(errno, p);
    return ok;
}
- (BOOL)writeToFile:(NSString *)p atomically:(BOOL)a { return [self writeToFile:p atomically:a encoding:NSUTF8StringEncoding error:0]; }
@end

/* ================================================================ concrete immutable */
@implementation __NSStringImpl
- (instancetype)_initTakingUTF16:(unichar *)u length:(NSUInteger)n { _u = u; _n = n; return self; }
- (void)dealloc { free(_u); free(_utf8); [super dealloc]; }
- (NSUInteger)length { return _n; }
- (unichar)characterAtIndex:(NSUInteger)i { if (i >= _n) mw_raise("NSRangeException", "characterAtIndex: index out of bounds"); return _u[i]; }
- (void)getCharacters:(unichar *)b range:(NSRange)r { memcpy(b, _u + r.location, r.length * 2); }
- (const char *)UTF8String { if (!_utf8) _utf8 = mw_utf16_to_utf8(_u, _n, 0); return _utf8; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end

/* ================================================================ mutable */
@implementation NSMutableString { unichar *_u; NSUInteger _n, _cap; char *_utf8; }
+ (instancetype)stringWithCapacity:(NSUInteger)n { return [[[self alloc] initWithCapacity:n] autorelease]; }
- (instancetype)initWithCapacity:(NSUInteger)n { return [self _initTakingUTF16:malloc((n + 1) * 2) length:0]; }
- (instancetype)_initTakingUTF16:(unichar *)u length:(NSUInteger)n { _u = u; _n = n; _cap = n; return self; }
- (void)dealloc { free(_u); free(_utf8); [super dealloc]; }
- (NSUInteger)length { return _n; }
- (unichar)characterAtIndex:(NSUInteger)i { if (i >= _n) mw_raise("NSRangeException", "characterAtIndex: index out of bounds"); return _u[i]; }
- (void)getCharacters:(unichar *)b range:(NSRange)r { memcpy(b, _u + r.location, r.length * 2); }
- (const char *)UTF8String { free(_utf8); _utf8 = mw_utf16_to_utf8(_u, _n, 0); return _utf8; }
- (id)copyWithZone:(NSZone *)z { return [[NSString alloc] initWithCharacters:_u length:_n]; }
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s {
    if (NSMaxRange(r) > _n) mw_raise("NSRangeException", "replaceCharactersInRange: range out of bounds");
    NSUInteger m = [s length], nn = _n - r.length + m;
    unichar *tmp = malloc((m + 1) * 2); [s getCharacters:tmp range:NSMakeRange(0, m)];
    if (nn > _cap) { _cap = nn * 2 + 16; _u = realloc(_u, (_cap + 1) * 2); }
    memmove(_u + r.location + m, _u + NSMaxRange(r), (_n - NSMaxRange(r)) * 2);
    memcpy(_u + r.location, tmp, m * 2); free(tmp);
    _n = nn;
}
- (void)appendString:(NSString *)s { [self replaceCharactersInRange:NSMakeRange(_n, 0) withString:s]; }
- (void)appendFormat:(NSString *)f, ... { va_list ap; va_start(ap, f); NSString *t = [[NSString alloc] initWithFormat:f arguments:ap]; va_end(ap); [self appendString:t]; [t release]; }
- (void)insertString:(NSString *)s atIndex:(NSUInteger)i { [self replaceCharactersInRange:NSMakeRange(i, 0) withString:s]; }
- (void)deleteCharactersInRange:(NSRange)r { [self replaceCharactersInRange:r withString:@""]; }
- (void)setString:(NSString *)s { [self replaceCharactersInRange:NSMakeRange(0, _n) withString:s]; }
- (NSUInteger)replaceOccurrencesOfString:(NSString *)a withString:(NSString *)b options:(NSStringCompareOptions)o range:(NSRange)r {
    if (o & NSRegularExpressionSearch) { extern NSUInteger mw_regex_replace(NSMutableString *, NSString *, NSString *, NSUInteger, NSRange); return mw_regex_replace(self, a, b, o, r); }
    NSUInteger count = 0, pos = r.location, end = NSMaxRange(r), la = [a length], lb = [b length];
    if (!la) return 0;
    while (pos + la <= end) {
        NSRange f = [self rangeOfString:a options:o & ~NSBackwardsSearch range:NSMakeRange(pos, end - pos)];
        if (f.location == NSNotFound) break;
        [self replaceCharactersInRange:f withString:b];
        pos = f.location + lb; end = end - la + lb; count++;
    }
    return count;
}
@end

/* ================================================================ constant strings (clang's CFString literals) */
uintptr_t __CFConstantStringClassReference[12];
@implementation __NSCFConstantString
+ (void)load { memcpy(__CFConstantStringClassReference, (void *)self, 40); mw_foundation_load(); }
- (NSUInteger)length { return (NSUInteger)_len; }
- (unichar)characterAtIndex:(NSUInteger)i { return (_info & 0x10) ? ((const unichar *)_str)[i] : ((const unsigned char *)_str)[i]; }
- (void)getCharacters:(unichar *)b range:(NSRange)r { for (NSUInteger i = 0; i < r.length; i++) b[i] = [self characterAtIndex:r.location + i]; }
- (const char *)UTF8String {
    if (!(_info & 0x10)) return (const char *)_str;
    return mw_utf16_to_utf8((const unichar *)_str, (NSUInteger)_len, 0); /* ponytail: UTF-16 literals leak one buffer per call */
}
- (id)retain { return self; }
- (oneway void)release { }
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return (NSUInteger)-1; }
- (id)copyWithZone:(NSZone *)z { return self; }
@end

/* ================================================================ NSCharacterSet */
@implementation NSCharacterSet { int _kind; unichar *_set; NSUInteger _n; BOOL _inv; }
static NSCharacterSet *mkset(int kind) { NSCharacterSet *s = [[NSCharacterSet alloc] init]; s->_kind = kind; return [s autorelease]; }
+ (NSCharacterSet *)whitespaceCharacterSet { return mkset(1); }
+ (NSCharacterSet *)whitespaceAndNewlineCharacterSet { return mkset(2); }
+ (NSCharacterSet *)newlineCharacterSet { return mkset(3); }
+ (NSCharacterSet *)decimalDigitCharacterSet { return mkset(4); }
+ (NSCharacterSet *)letterCharacterSet { return mkset(5); }
+ (NSCharacterSet *)alphanumericCharacterSet { return mkset(6); }
+ (NSCharacterSet *)punctuationCharacterSet { return mkset(7); }
+ (NSCharacterSet *)uppercaseLetterCharacterSet { return mkset(8); }
+ (NSCharacterSet *)lowercaseLetterCharacterSet { return mkset(9); }
+ (NSCharacterSet *)characterSetWithCharactersInString:(NSString *)s { NSCharacterSet *c = mkset(0); c->_set = mw_chars(s, &c->_n); return c; }
- (void)dealloc { free(_set); [super dealloc]; }
- (BOOL)characterIsMember:(unichar)c {
    BOOL r;
    switch (_kind) {
    case 1: r = c == ' ' || c == '\t' || c == 0xA0; break;
    case 2: r = c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0xB || c == 0xC || c == 0xA0 || c == 0x85 || c == 0x2028 || c == 0x2029; break;
    case 3: r = c == '\n' || c == '\r' || c == 0x85 || c == 0x2028 || c == 0x2029; break;
    case 4: r = c >= '0' && c <= '9'; break;
    case 5: r = (c < 128 && isalpha(c)) || (c >= 0xC0 && c != 0xD7 && c != 0xF7); break;
    case 6: r = (c < 128 && isalnum(c)) || (c >= 0xC0 && c != 0xD7 && c != 0xF7); break;
    case 7: r = c < 128 && ispunct(c); break;
    case 8: r = c >= 'A' && c <= 'Z'; break;
    case 9: r = c >= 'a' && c <= 'z'; break;
    default: r = NO; for (NSUInteger i = 0; i < _n; i++) if (_set[i] == c) { r = YES; break; }
    }
    return r != _inv;
}
- (NSCharacterSet *)invertedSet {
    NSCharacterSet *s = [[NSCharacterSet alloc] init];
    s->_kind = _kind; s->_inv = !_inv;
    if (_set) { s->_set = malloc(_n * 2 + 2); memcpy(s->_set, _set, _n * 2); s->_n = _n; }
    return [s autorelease];
}
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end
