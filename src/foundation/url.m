/* url.m — NSURLComponents, NSURLQueryItem and NSURL (RFC 3986 parsing through NSURLComponents), for Foundation and
 * Swift's Foundation overlay. Written from Apple's public documentation. */
#include "internal.h"

/* ======================================================================= URL components and query items */
/* percent-encoding by code point: allowed BMP characters stay, everything else becomes %XX of its UTF-8 bytes */
__attribute__((visibility("hidden"))) NSString *pct_encode(NSString *s, NSCharacterSet *allowed) {
    NSUInteger n; unichar *u = mw_chars(s, &n); NSMutableString *out = [NSMutableString stringWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) {
        uint32_t c = u[i];
        if (c >= 0xd800 && c < 0xdc00 && i + 1 < n && u[i + 1] >= 0xdc00 && u[i + 1] < 0xe000) { c = 0x10000 + ((c - 0xd800) << 10) + (u[i + 1] - 0xdc00); i++; }
        if (c < 0x10000 && [allowed characterIsMember:(unichar)c]) { unichar ch = (unichar)c; [out appendString:[NSString stringWithCharacters:&ch length:1]]; continue; }
        unsigned char b[4]; int k = 0;
        if (c < 0x80) b[k++] = (unsigned char)c;
        else if (c < 0x800) { b[k++] = (unsigned char)(0xc0 | c >> 6); b[k++] = (unsigned char)(0x80 | (c & 63)); }
        else if (c < 0x10000) { b[k++] = (unsigned char)(0xe0 | c >> 12); b[k++] = (unsigned char)(0x80 | (c >> 6 & 63)); b[k++] = (unsigned char)(0x80 | (c & 63)); }
        else { b[k++] = (unsigned char)(0xf0 | c >> 18); b[k++] = (unsigned char)(0x80 | (c >> 12 & 63)); b[k++] = (unsigned char)(0x80 | (c >> 6 & 63)); b[k++] = (unsigned char)(0x80 | (c & 63)); }
        for (int j = 0; j < k; j++) [out appendFormat:@"%%%02X", b[j]];
    }
    free(u);
    return out;
}
static int hexv(unichar c) { return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1; }
/* nil when an escape is malformed or the bytes are not UTF-8 */
__attribute__((visibility("hidden"))) NSString *pct_decode(NSString *s) {
    NSUInteger n; unichar *u = mw_chars(s, &n); NSMutableData *d = [NSMutableData dataWithCapacity:n]; BOOL ok = YES;
    for (NSUInteger i = 0; i < n && ok; i++) {
        if (u[i] == '%') {
            int h = i + 2 < n ? hexv(u[i + 1]) : -1, l = i + 2 < n ? hexv(u[i + 2]) : -1;
            if (h < 0 || l < 0) { ok = NO; break; }
            unsigned char b = (unsigned char)(h << 4 | l); [d appendBytes:&b length:1]; i += 2;
        } else {
            NSString *ch = [NSString stringWithCharacters:&u[i] length:1]; NSData *e = [ch dataUsingEncoding:NSUTF8StringEncoding];
            if (u[i] >= 0xd800 && u[i] < 0xdc00 && i + 1 < n) { e = [[NSString stringWithCharacters:&u[i] length:2] dataUsingEncoding:NSUTF8StringEncoding]; i++; }
            [d appendData:e];
        }
    }
    free(u);
    if (!ok) return nil;
    const unsigned char *b = [d bytes]; NSUInteger m = [d length];
    for (NSUInteger i = 0; i < m;) { /* strict UTF-8 check */
        unsigned char c = b[i]; int k = c < 0x80 ? 0 : (c & 0xe0) == 0xc0 ? 1 : (c & 0xf0) == 0xe0 ? 2 : (c & 0xf8) == 0xf0 ? 3 : -1;
        if (k < 0 || i + (NSUInteger)k >= m + (k ? 0 : 1)) return nil;
        for (int j = 1; j <= k; j++) if ((b[i + j] & 0xc0) != 0x80) return nil;
        i += (NSUInteger)k + 1;
    }
    return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
}
@implementation NSURLQueryItem { NSString *_name, *_value; }
- (instancetype)initWithName:(NSString *)n value:(NSString *)v { _name = [n copy]; _value = [v copy]; return self; }
+ (instancetype)queryItemWithName:(NSString *)n value:(NSString *)v { return [[[self alloc] initWithName:n value:v] autorelease]; }
- (void)dealloc { [_name release]; [_value release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)name { return _name; } - (NSString *)value { return _value; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSURLQueryItem class]] && [_name isEqualToString:[o name]] && (_value == [o value] || [_value isEqualToString:[o value]]); }
- (NSUInteger)hash { return [_name hash]; }
- (NSString *)description { return _value ? [NSString stringWithFormat:@"%@=%@", _name, _value] : _name; }
@end
@implementation NSURLComponents { NSString *_scheme, *_user, *_password, *_host, *_path, *_query, *_fragment; NSNumber *_port; }
- (instancetype)init { _path = @""; return self; }
- (void)dealloc { [_scheme release]; [_user release]; [_password release]; [_host release]; [_path release]; [_query release]; [_fragment release]; [_port release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSURLComponents *c = [[NSURLComponents alloc] init]; [c setString_:[self string]]; return c; }
- (BOOL)setString_:(NSString *)s {
    if (!s) return NO;
    NSString *rest = s; NSRange r;
    r = [rest rangeOfString:@"#"]; if (r.location != NSNotFound) { _fragment = [[rest substringFromIndex:NSMaxRange(r)] copy]; rest = [rest substringToIndex:r.location]; }
    r = [rest rangeOfString:@"?"]; if (r.location != NSNotFound) { _query = [[rest substringFromIndex:NSMaxRange(r)] copy]; rest = [rest substringToIndex:r.location]; }
    r = [rest rangeOfString:@":"];
    if (r.location != NSNotFound && r.location > 0 && [[rest substringToIndex:r.location] rangeOfString:@"/"].location == NSNotFound) {
        _scheme = [[rest substringToIndex:r.location] copy]; rest = [rest substringFromIndex:NSMaxRange(r)];
    }
    if ([rest hasPrefix:@"//"]) {
        rest = [rest substringFromIndex:2]; NSRange sl = [rest rangeOfString:@"/"];
        NSString *auth = sl.location == NSNotFound ? rest : [rest substringToIndex:sl.location];
        rest = sl.location == NSNotFound ? @"" : [rest substringFromIndex:sl.location];
        NSRange at = [auth rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) {
            NSString *ui = [auth substringToIndex:at.location]; auth = [auth substringFromIndex:NSMaxRange(at)];
            NSRange c = [ui rangeOfString:@":"];
            if (c.location != NSNotFound) { _user = [[ui substringToIndex:c.location] copy]; _password = [[ui substringFromIndex:NSMaxRange(c)] copy]; }
            else _user = [ui copy];
        }
        NSRange pc = [auth rangeOfString:@":" options:NSBackwardsSearch];
        if (pc.location != NSNotFound && ![auth hasSuffix:@"]"]) { _port = [[NSNumber alloc] initWithInteger:[[auth substringFromIndex:NSMaxRange(pc)] integerValue]]; auth = [auth substringToIndex:pc.location]; }
        _host = [auth copy];
    }
    [_path release]; _path = [rest copy];
    return YES;
}
- (instancetype)initWithString:(NSString *)s { _path = @""; if (![self setString_:s]) { [self release]; return nil; } return self; }
+ (instancetype)componentsWithString:(NSString *)s { return [[[self alloc] initWithString:s] autorelease]; }
- (instancetype)initWithURL:(NSURL *)u resolvingAgainstBaseURL:(BOOL)r { return [self initWithString:[(r ? [u absoluteURL] : u) absoluteString]]; }
+ (instancetype)componentsWithURL:(NSURL *)u resolvingAgainstBaseURL:(BOOL)r { return [[[self alloc] initWithURL:u resolvingAgainstBaseURL:r] autorelease]; }
- (NSString *)string {
    NSMutableString *s = [NSMutableString string];
    if (_scheme) [s appendFormat:@"%@:", _scheme];
    if (_host || _user || _port) {
        [s appendString:@"//"];
        if (_user) { [s appendString:_user]; if (_password) [s appendFormat:@":%@", _password]; [s appendString:@"@"]; }
        if (_host) [s appendString:_host];
        if (_port) [s appendFormat:@":%@", _port];
    }
    if (_path) [s appendString:_path];
    if (_query) [s appendFormat:@"?%@", _query];
    if (_fragment) [s appendFormat:@"#%@", _fragment];
    return s;
}
- (NSURL *)URL { return [NSURL URLWithString:[self string]]; }
- (NSURL *)URLRelativeToURL:(NSURL *)b { return [NSURL URLWithString:[self string] relativeToURL:b]; }
/* stored percent-encoded; the plain accessors decode and encode */
#define RAW(get, set, iv) - (NSString *)get { return iv; } - (void)set:(NSString *)v { [iv release]; iv = [v copy]; }
#define DEC(get, set, raw, rawset, allowed) - (NSString *)get { NSString *r = [self raw]; return r ? (pct_decode(r) ?: r) : nil; } \
    - (void)set:(NSString *)v { [self rawset:v ? pct_encode(v, allowed) : nil]; }
RAW(scheme, setScheme, _scheme)
RAW(percentEncodedUser, setPercentEncodedUser_, _user) RAW(percentEncodedPassword, setPercentEncodedPassword_, _password)
RAW(percentEncodedHost, setPercentEncodedHost_, _host) RAW(percentEncodedQuery, setPercentEncodedQuery_, _query)
RAW(percentEncodedFragment, setPercentEncodedFragment_, _fragment)
- (void)setPercentEncodedUser:(NSString *)v { [self setPercentEncodedUser_:v]; } - (void)setPercentEncodedPassword:(NSString *)v { [self setPercentEncodedPassword_:v]; }
- (void)setPercentEncodedHost:(NSString *)v { [self setPercentEncodedHost_:v]; } - (void)setPercentEncodedQuery:(NSString *)v { [self setPercentEncodedQuery_:v]; }
- (void)setPercentEncodedFragment:(NSString *)v { [self setPercentEncodedFragment_:v]; }
- (NSString *)percentEncodedPath { return _path ? _path : @""; } - (void)setPercentEncodedPath_:(NSString *)p { [_path release]; _path = [(p ? p : @"") copy]; }
- (void)setPercentEncodedPath:(NSString *)p { [self setPercentEncodedPath_:p]; }
- (NSString *)encodedHost { return _host; } - (void)setEncodedHost:(NSString *)v { [self setPercentEncodedHost_:v]; }
DEC(user, setUser, percentEncodedUser, setPercentEncodedUser_, [NSCharacterSet URLUserAllowedCharacterSet])
DEC(password, setPassword, percentEncodedPassword, setPercentEncodedPassword_, [NSCharacterSet URLPasswordAllowedCharacterSet])
DEC(host, setHost, percentEncodedHost, setPercentEncodedHost_, [NSCharacterSet URLHostAllowedCharacterSet])
DEC(path, setPath, percentEncodedPath, setPercentEncodedPath_, [NSCharacterSet URLPathAllowedCharacterSet])
DEC(query, setQuery, percentEncodedQuery, setPercentEncodedQuery_, [NSCharacterSet URLQueryAllowedCharacterSet])
DEC(fragment, setFragment, percentEncodedFragment, setPercentEncodedFragment_, [NSCharacterSet URLFragmentAllowedCharacterSet])
- (NSNumber *)port { return _port; } - (void)setPort:(NSNumber *)p { [_port release]; _port = [p copy]; }
static NSArray *query_items(NSString *q, BOOL decode) {
    if (!q) return nil;
    NSMutableArray *a = [NSMutableArray array];
    if (![q length]) return a;
    for (NSString *part in [q componentsSeparatedByString:@"&"]) {
        NSRange eq = [part rangeOfString:@"="];
        NSString *n = eq.location == NSNotFound ? part : [part substringToIndex:eq.location], *v = eq.location == NSNotFound ? nil : [part substringFromIndex:NSMaxRange(eq)];
        if (decode) { n = pct_decode(n) ?: n; v = v ? (pct_decode(v) ?: v) : nil; }
        [a addObject:[NSURLQueryItem queryItemWithName:n value:v]];
    }
    return a;
}
static NSString *join_items(NSArray *items, BOOL encode) {
    if (!items) return nil;
    NSMutableCharacterSet *ok = [[[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy] autorelease]; [ok removeCharactersInString:@"&="];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSURLQueryItem *q in items) {
        NSString *n = encode ? pct_encode([q name], ok) : [q name], *v = [q value] ? (encode ? pct_encode([q value], ok) : [q value]) : nil;
        [parts addObject:v ? [NSString stringWithFormat:@"%@=%@", n, v] : n];
    }
    return [parts componentsJoinedByString:@"&"];
}
- (NSArray *)queryItems { return query_items(_query, YES); }
- (void)setQueryItems:(NSArray *)items { [self setPercentEncodedQuery_:join_items(items, YES)]; }
- (NSArray *)percentEncodedQueryItems { return query_items(_query, NO); }
- (void)setPercentEncodedQueryItems:(NSArray *)items { [self setPercentEncodedQuery_:join_items(items, NO)]; }
static NSRange find_in(NSString *s, NSString *part) { return part ? [s rangeOfString:part] : NSMakeRange(NSNotFound, 0); }
- (NSRange)rangeOfScheme { return find_in([self string], _scheme); } - (NSRange)rangeOfUser { return find_in([self string], _user); }
- (NSRange)rangeOfPassword { return find_in([self string], _password); } - (NSRange)rangeOfHost { return find_in([self string], _host); }
- (NSRange)rangeOfPort { return find_in([self string], [_port stringValue]); } - (NSRange)rangeOfPath { return [_path length] ? find_in([self string], _path) : NSMakeRange(NSNotFound, 0); }
- (NSRange)rangeOfQuery { return find_in([self string], _query); } - (NSRange)rangeOfFragment { return find_in([self string], _fragment); }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSURLComponents class]] && [[self string] isEqualToString:[o string]]; }
- (NSUInteger)hash { return [[self string] hash]; }
- (NSString *)description { return [NSString stringWithFormat:@"<NSURLComponents %p> {%@}", self, [self string]]; }
@end

/* ======================================================================= NSURL (RFC 3986 parsing through NSURLComponents) */
static NSString *remove_dots(NSString *p) {
    if ([p rangeOfString:@"."].location == NSNotFound) return p;
    NSArray *segs = [p componentsSeparatedByString:@"/"]; NSMutableArray *out = [NSMutableArray array]; NSUInteger n = [segs count];
    for (NSUInteger i = 0; i < n; i++) {
        NSString *s = segs[i]; BOOL last = i + 1 == n;
        if ([s isEqualToString:@"."]) { if (last) [out addObject:@""]; continue; }
        if ([s isEqualToString:@".."]) {
            if ([out count] > 1 || ([out count] == 1 && [out[0] length])) [out removeLastObject];
            if (last) [out addObject:@""];
            continue;
        }
        [out addObject:s];
    }
    return [out componentsJoinedByString:@"/"];
}
static BOOL has_scheme(NSString *s) {
    NSUInteger n = [s length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == ':') return i > 0;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (i && ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.')))) return NO;
    }
    return NO;
}
static NSString *resolve(NSString *base, NSString *rel) {
    if (has_scheme(rel)) return rel;
    NSURLComponents *B = [NSURLComponents componentsWithString:base], *R = [NSURLComponents componentsWithString:rel];
    if ([rel hasPrefix:@"//"]) return [NSString stringWithFormat:@"%@:%@", [B scheme], rel];
    NSString *rp = [R percentEncodedPath];
    if (![rp length]) { if ([R percentEncodedQuery]) [B setPercentEncodedQuery:[R percentEncodedQuery]]; }
    else {
        if (![rp hasPrefix:@"/"]) {
            NSString *bp = [B percentEncodedPath]; NSRange sl = [bp rangeOfString:@"/" options:NSBackwardsSearch];
            rp = sl.location == NSNotFound ? ([B percentEncodedHost] ? [@"/" stringByAppendingString:rp] : rp) : [[bp substringToIndex:sl.location + 1] stringByAppendingString:rp];
        }
        [B setPercentEncodedPath:remove_dots(rp)]; [B setPercentEncodedQuery:[R percentEncodedQuery]];
    }
    [B setPercentEncodedFragment:[R percentEncodedFragment]];
    return [B string];
}
@implementation NSURL { NSString *_s; NSURL *_base; NSURLComponents *_c; }
- (instancetype)initWithString:(NSString *)s relativeToURL:(NSURL *)b {
    if (!s) { [self release]; return nil; }
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@" \"<>\\^`{|}\t\n\r"];
    if ([s rangeOfCharacterFromSet:bad].location != NSNotFound) { [self release]; return nil; } /* not a valid URL string */
    _s = [s copy]; _base = has_scheme(s) ? nil : [[b absoluteURL] retain];
    _c = [[NSURLComponents alloc] initWithString:[self absoluteString]];
    if (!_c) { [self release]; return nil; }
    return self;
}
- (instancetype)initWithString:(NSString *)s { return [self initWithString:s relativeToURL:nil]; }
+ (instancetype)URLWithString:(NSString *)s { return [[[self alloc] initWithString:s] autorelease]; }
+ (instancetype)URLWithString:(NSString *)s relativeToURL:(NSURL *)b { return [[[self alloc] initWithString:s relativeToURL:b] autorelease]; }
- (instancetype)initWithScheme:(NSString *)sc host:(NSString *)h path:(NSString *)p {
    return [self initWithString:[NSString stringWithFormat:@"%@://%@%@", sc, h ? h : @"", pct_encode(p, [NSCharacterSet URLPathAllowedCharacterSet])]];
}
- (instancetype)initFileURLWithPath:(NSString *)p isDirectory:(BOOL)dir relativeToURL:(NSURL *)b {
    if (![p length]) p = @".";
    if (![p isAbsolutePath]) p = [(b ? [b path] : [[NSFileManager defaultManager] currentDirectoryPath]) stringByAppendingPathComponent:p];
    if ([p hasSuffix:@"/."]) p = [p substringToIndex:[p length] - 1];
    NSString *e = pct_encode(p, [NSCharacterSet URLPathAllowedCharacterSet]);
    if (dir && ![e hasSuffix:@"/"]) e = [e stringByAppendingString:@"/"];
    return [self initWithString:[@"file://" stringByAppendingString:e]];
}
- (instancetype)initFileURLWithPath:(NSString *)p relativeToURL:(NSURL *)b {
    BOOL dir = [p hasSuffix:@"/"];
    if (!dir) { NSString *full = [p isAbsolutePath] || !b ? p : [[b path] stringByAppendingPathComponent:p]; [[NSFileManager defaultManager] fileExistsAtPath:[full length] ? full : @"." isDirectory:&dir]; }
    return [self initFileURLWithPath:p isDirectory:dir relativeToURL:b];
}
- (instancetype)initFileURLWithPath:(NSString *)p { return [self initFileURLWithPath:p relativeToURL:nil]; }
- (instancetype)initFileURLWithPath:(NSString *)p isDirectory:(BOOL)d { return [self initFileURLWithPath:p isDirectory:d relativeToURL:nil]; }
- (instancetype)initFileURLWithFileSystemRepresentation:(const char *)p isDirectory:(BOOL)d relativeToURL:(NSURL *)b {
    return [self initFileURLWithPath:[NSString stringWithUTF8String:p] isDirectory:d relativeToURL:b];
}
+ (NSURL *)fileURLWithPath:(NSString *)p { return [[[self alloc] initFileURLWithPath:p] autorelease]; }
+ (NSURL *)fileURLWithPath:(NSString *)p isDirectory:(BOOL)d { return [[[self alloc] initFileURLWithPath:p isDirectory:d] autorelease]; }
+ (NSURL *)fileURLWithPath:(NSString *)p isDirectory:(BOOL)d relativeToURL:(NSURL *)b { return [[[self alloc] initFileURLWithPath:p isDirectory:d relativeToURL:b] autorelease]; }
+ (NSURL *)fileURLWithPath:(NSString *)p relativeToURL:(NSURL *)b { return [[[self alloc] initFileURLWithPath:p relativeToURL:b] autorelease]; }
+ (NSURL *)fileURLWithFileSystemRepresentation:(const char *)p isDirectory:(BOOL)d relativeToURL:(NSURL *)b { return [[[self alloc] initFileURLWithFileSystemRepresentation:p isDirectory:d relativeToURL:b] autorelease]; }
+ (NSURL *)fileURLWithPathComponents:(NSArray *)c { return [c count] ? [self fileURLWithPath:[NSString pathWithComponents:c]] : nil; }
- (instancetype)initWithDataRepresentation:(NSData *)d relativeToURL:(NSURL *)b {
    NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
    return [self initWithString:s ? s : @"" relativeToURL:b];
}
- (instancetype)initAbsoluteURLWithDataRepresentation:(NSData *)d relativeToURL:(NSURL *)b {
    NSURL *u = [[[NSURL alloc] initWithDataRepresentation:d relativeToURL:b] autorelease];
    return [self initWithString:[u absoluteString]];
}
+ (NSURL *)URLWithDataRepresentation:(NSData *)d relativeToURL:(NSURL *)b { return [[[self alloc] initWithDataRepresentation:d relativeToURL:b] autorelease]; }
+ (NSURL *)absoluteURLWithDataRepresentation:(NSData *)d relativeToURL:(NSURL *)b { return [[[self alloc] initAbsoluteURLWithDataRepresentation:d relativeToURL:b] autorelease]; }
- (void)dealloc { [_s release]; [_base release]; [_c release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSData *)dataRepresentation { return [_s dataUsingEncoding:NSUTF8StringEncoding]; }
- (NSString *)relativeString { return _s; }
- (NSString *)absoluteString { return _base ? resolve([_base absoluteString], _s) : _s; }
- (NSURL *)baseURL { return _base; }
- (NSURL *)absoluteURL { return _base ? [NSURL URLWithString:[self absoluteString]] : self; }
- (NSString *)description { return _base ? [NSString stringWithFormat:@"%@ -- %@", _s, _base] : _s; }
- (NSString *)scheme { return [_c scheme]; }
- (NSString *)user { return [_c user]; }
- (NSString *)password { return [_c password]; }
- (NSString *)host { return [_c host]; }
- (NSNumber *)port { return [_c port]; }
- (NSString *)query { return [_c percentEncodedQuery]; }
- (NSString *)fragment { return [_c percentEncodedFragment]; }
- (NSString *)parameterString { return nil; }
- (NSString *)resourceSpecifier { NSString *a = [self absoluteString]; NSRange r = [a rangeOfString:@":"]; return r.location == NSNotFound ? a : [a substringFromIndex:NSMaxRange(r)]; }
static NSString *clean_path(NSString *enc) {
    NSString *p = pct_decode(enc) ?: enc;
    if ([p length] > 1 && [p hasSuffix:@"/"]) p = [p substringToIndex:[p length] - 1];
    return p;
}
- (NSString *)path { return clean_path([_c percentEncodedPath]); }
- (NSString *)relativePath { return _base ? clean_path([[NSURLComponents componentsWithString:_s] percentEncodedPath]) : [self path]; }
- (BOOL)hasDirectoryPath { return [[_c percentEncodedPath] hasSuffix:@"/"]; }
- (BOOL)isFileURL { return [[self scheme] caseInsensitiveCompare:@"file"] == NSOrderedSame; }
- (NSString *)lastPathComponent { return [[self path] lastPathComponent]; }
- (NSString *)pathExtension { return [[self path] pathExtension]; }
- (NSArray *)pathComponents { NSString *p = [self path]; return [p length] ? [p pathComponents] : nil; }
- (const char *)fileSystemRepresentation { return [[self path] fileSystemRepresentation]; }
- (BOOL)getFileSystemRepresentation:(char *)b maxLength:(NSUInteger)m { return [[self path] getFileSystemRepresentation:b maxLength:m]; }
static NSURL *with_path(NSURL *u, NSString *encPath) {
    NSURLComponents *c = [NSURLComponents componentsWithString:[u absoluteString]]; [c setPercentEncodedPath:encPath]; return [c URL];
}
- (NSURL *)URLByAppendingPathComponent:(NSString *)comp isDirectory:(BOOL)dir {
    NSString *p = [_c percentEncodedPath], *e = pct_encode(comp, [NSCharacterSet URLPathAllowedCharacterSet]);
    if (![p hasSuffix:@"/"] && ([p length] || [_c percentEncodedHost])) p = [p stringByAppendingString:@"/"];
    if ([e hasPrefix:@"/"] && [p hasSuffix:@"/"]) e = [e substringFromIndex:1];
    p = [p stringByAppendingString:e];
    if (dir && ![p hasSuffix:@"/"]) p = [p stringByAppendingString:@"/"];
    return with_path(self, p);
}
- (NSURL *)URLByAppendingPathComponent:(NSString *)comp {
    BOOL dir = NO;
    if ([self isFileURL]) [[NSFileManager defaultManager] fileExistsAtPath:[[self path] stringByAppendingPathComponent:comp] isDirectory:&dir];
    return [self URLByAppendingPathComponent:comp isDirectory:dir];
}
- (NSURL *)URLByAppendingPathExtension:(NSString *)ext {
    NSString *p = [_c percentEncodedPath]; BOOL dir = [p length] > 1 && [p hasSuffix:@"/"];
    if (dir) p = [p substringToIndex:[p length] - 1];
    if (![p length] || [p hasSuffix:@"/"]) return self;
    p = [NSString stringWithFormat:@"%@.%@%@", p, pct_encode(ext, [NSCharacterSet URLPathAllowedCharacterSet]), dir ? @"/" : @""];
    return with_path(self, p);
}
- (NSURL *)URLByDeletingPathExtension {
    NSString *p = [_c percentEncodedPath]; BOOL dir = [p length] > 1 && [p hasSuffix:@"/"];
    if (dir) p = [p substringToIndex:[p length] - 1];
    NSRange dot = [p rangeOfString:@"." options:NSBackwardsSearch], sl = [p rangeOfString:@"/" options:NSBackwardsSearch];
    if (dot.location == NSNotFound || (sl.location != NSNotFound && dot.location < sl.location + 2)) return self;
    p = [p substringToIndex:dot.location];
    return with_path(self, dir ? [p stringByAppendingString:@"/"] : p);
}
- (NSURL *)URLByDeletingLastPathComponent {
    NSString *p = [_c percentEncodedPath];
    if ([p length] > 1 && [p hasSuffix:@"/"]) p = [p substringToIndex:[p length] - 1];
    NSRange sl = [p rangeOfString:@"/" options:NSBackwardsSearch];
    p = sl.location == NSNotFound ? @"./" : [p substringToIndex:sl.location + 1];
    return with_path(self, p);
}
- (NSURL *)standardizedURL { return with_path(self, remove_dots([_c percentEncodedPath])); }
- (NSURL *)URLByStandardizingPath { return [self isFileURL] ? [NSURL fileURLWithPath:[[self path] stringByStandardizingPath] isDirectory:[self hasDirectoryPath]] : self; }
- (NSURL *)URLByResolvingSymlinksInPath { return [self isFileURL] ? [NSURL fileURLWithPath:[[self path] stringByResolvingSymlinksInPath] isDirectory:[self hasDirectoryPath]] : self; }
- (NSURL *)filePathURL { return [self isFileURL] ? self : nil; }
- (NSURL *)fileReferenceURL { return [self filePathURL]; }
- (BOOL)isFileReferenceURL { return NO; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSURL class]] && [_s isEqualToString:[o relativeString]] && (_base == [o baseURL] || [_base isEqual:[o baseURL]])); }
- (NSUInteger)hash { return [_s hash]; }
/* resource values: from the file system, nothing cached */
static NSError *no_file(NSURL *u) {
    return [NSError errorWithDomain:NSCocoaErrorDomain code:260 userInfo:@{NSURLErrorKey: u, NSFilePathErrorKey: [u path] ?: @""}];
}
- (BOOL)getResourceValue:(id *)v forKey:(NSURLResourceKey)k error:(NSError **)err {
    *v = nil;
    if (![self isFileURL]) return YES;
    NSString *p = [self path]; BOOL dir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&dir]) { if (err) *err = no_file(self); return NO; }
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:p error:0];
    if ([k isEqualToString:NSURLIsDirectoryKey]) *v = [NSNumber numberWithBool:dir];
    else if ([k isEqualToString:NSURLIsRegularFileKey]) *v = [NSNumber numberWithBool:!dir];
    else if ([k isEqualToString:NSURLIsSymbolicLinkKey] || [k isEqualToString:NSURLIsPackageKey] || [k isEqualToString:NSURLIsAliasFileKey]
             || [k isEqualToString:NSURLIsVolumeKey] || [k isEqualToString:NSURLIsUbiquitousItemKey] || [k isEqualToString:NSURLIsExcludedFromBackupKey])
        *v = [NSNumber numberWithBool:NO];
    else if ([k isEqualToString:NSURLIsHiddenKey]) *v = [NSNumber numberWithBool:[[p lastPathComponent] hasPrefix:@"."]];
    else if ([k isEqualToString:NSURLIsReadableKey] || [k isEqualToString:NSURLIsWritableKey]) *v = [NSNumber numberWithBool:YES];
    else if ([k isEqualToString:NSURLIsExecutableKey]) *v = [NSNumber numberWithBool:dir];
    else if ([k isEqualToString:NSURLFileSizeKey] || [k isEqualToString:NSURLTotalFileSizeKey] || [k isEqualToString:NSURLFileAllocatedSizeKey]
             || [k isEqualToString:NSURLTotalFileAllocatedSizeKey]) *v = dir ? nil : a[NSFileSize];
    else if ([k isEqualToString:NSURLContentModificationDateKey] || [k isEqualToString:NSURLCreationDateKey] || [k isEqualToString:NSURLAttributeModificationDateKey]
             || [k isEqualToString:NSURLContentAccessDateKey]) *v = a[NSFileModificationDate];
    else if ([k isEqualToString:NSURLNameKey] || [k isEqualToString:NSURLLocalizedNameKey]) *v = [p lastPathComponent];
    else if ([k isEqualToString:NSURLPathKey] || [k isEqualToString:NSURLCanonicalPathKey]) *v = p;
    else if ([k isEqualToString:NSURLParentDirectoryURLKey]) *v = [self URLByDeletingLastPathComponent];
    else if ([k isEqualToString:NSURLFileResourceTypeKey]) *v = dir ? NSURLFileResourceTypeDirectory : NSURLFileResourceTypeRegular;
    else if ([k isEqualToString:NSURLTypeIdentifierKey]) *v = dir ? @"public.folder" : @"public.data";
    else if ([k isEqualToString:NSURLLinkCountKey]) *v = [NSNumber numberWithInt:1];
    return YES;
}
- (NSDictionary *)resourceValuesForKeys:(NSArray *)keys error:(NSError **)err {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in keys) { id v; if (![self getResourceValue:&v forKey:k error:err]) return nil; if (v) d[k] = v; }
    return d;
}
- (BOOL)getPromisedItemResourceValue:(id *)v forKey:(NSURLResourceKey)k error:(NSError **)e { return [self getResourceValue:v forKey:k error:e]; }
- (NSDictionary *)promisedItemResourceValuesForKeys:(NSArray *)keys error:(NSError **)e { return [self resourceValuesForKeys:keys error:e]; }
- (BOOL)setResourceValue:(id)v forKey:(NSURLResourceKey)k error:(NSError **)e { return YES; } /* ponytail: attributes are not written */
- (BOOL)setResourceValues:(NSDictionary *)d error:(NSError **)e { return YES; }
- (void)removeCachedResourceValueForKey:(NSURLResourceKey)k {} - (void)removeAllCachedResourceValues {}
- (void)setTemporaryResourceValue:(id)v forKey:(NSURLResourceKey)k {}
- (BOOL)checkResourceIsReachableAndReturnError:(NSError **)e {
    if ([self isFileURL] && [[NSFileManager defaultManager] fileExistsAtPath:[self path]]) return YES;
    if (e) *e = no_file(self); return NO;
}
- (BOOL)checkPromisedItemIsReachableAndReturnError:(NSError **)e { return [self checkResourceIsReachableAndReturnError:e]; }
- (BOOL)startAccessingSecurityScopedResource { return YES; } - (void)stopAccessingSecurityScopedResource {}
/* bookmarks: the bookmark is the URL's own string (no aliases or volume lookups) */
- (NSData *)bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)o includingResourceValuesForKeys:(NSArray *)k relativeToURL:(NSURL *)r error:(NSError **)e { return [[self absoluteString] dataUsingEncoding:NSUTF8StringEncoding]; }
- (instancetype)initByResolvingBookmarkData:(NSData *)d options:(NSURLBookmarkResolutionOptions)o relativeToURL:(NSURL *)r bookmarkDataIsStale:(BOOL *)stale error:(NSError **)e {
    if (stale) *stale = NO;
    self = [self initAbsoluteURLWithDataRepresentation:d relativeToURL:nil];
    if (!self && e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:259 userInfo:nil];
    return self;
}
+ (instancetype)URLByResolvingBookmarkData:(NSData *)d options:(NSURLBookmarkResolutionOptions)o relativeToURL:(NSURL *)r bookmarkDataIsStale:(BOOL *)s error:(NSError **)e {
    return [[[self alloc] initByResolvingBookmarkData:d options:o relativeToURL:r bookmarkDataIsStale:s error:e] autorelease];
}
+ (NSDictionary *)resourceValuesForKeys:(NSArray *)keys fromBookmarkData:(NSData *)d { return [[NSURL absoluteURLWithDataRepresentation:d relativeToURL:nil] resourceValuesForKeys:keys error:0]; }
+ (BOOL)writeBookmarkData:(NSData *)d toURL:(NSURL *)u options:(NSURLBookmarkFileCreationOptions)o error:(NSError **)e { return [d writeToURL:u options:0 error:e]; }
+ (NSData *)bookmarkDataWithContentsOfURL:(NSURL *)u error:(NSError **)e { return [NSData dataWithContentsOfURL:u options:0 error:e]; }
+ (instancetype)URLByResolvingAliasFileAtURL:(NSURL *)u options:(NSURLBookmarkResolutionOptions)o error:(NSError **)e { return u; }
@end
