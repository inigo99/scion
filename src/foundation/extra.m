/* extra.m — scion Foundation: NSScanner, NSMutableCharacterSet, NSUUID, NSFileHandle, NSBundle. MRC. */
#import "internal.h"
long lseek(int, long, int); int fsync(int);
int getentropy(void *, size_t);
char ***_NSGetArgv(void);

NSString *const NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReason";
NSString *const NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestion";
NSString *const NSUnderlyingErrorKey = @"NSUnderlyingError";

/* ================================================================ NSMutableCharacterSet: union of parts, optionally inverted */
@implementation NSMutableCharacterSet { NSMutableArray *_parts; BOOL _minv; }
- (instancetype)init { _parts = [[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [_parts release]; [super dealloc]; }
- (BOOL)characterIsMember:(unichar)c {
    for (NSCharacterSet *p in _parts) if ([p characterIsMember:c]) return !_minv;
    return _minv;
}
- (void)formUnionWithCharacterSet:(NSCharacterSet *)o {
    if (_minv) { NSMutableCharacterSet *me = [self copy]; [_parts removeAllObjects]; [_parts addObject:me]; [me release]; _minv = NO; }
    [_parts addObject:[[o copy] autorelease]];
}
- (void)addCharactersInString:(NSString *)s { [self formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:s]]; }
- (void)addCharactersInRange:(NSRange)r {
    unichar *u = malloc((r.length + 1) * sizeof(unichar));
    for (NSUInteger i = 0; i < r.length; i++) u[i] = (unichar)(r.location + i);
    [self addCharactersInString:mw_str_take(u, r.length)];
}
- (void)invert { _minv = !_minv; }
/* removing and intersecting: rebuilt from the membership of the 16-bit range (ponytail: 64K tests per call) */
- (void)_keep:(BOOL (^)(unichar c))keep {
    unichar *u = malloc(65536 * sizeof(unichar)); NSUInteger n = 0;
    for (NSUInteger i = 0; i < 65536; i++) if (keep((unichar)i)) u[n++] = (unichar)i;
    NSCharacterSet *fresh = [NSCharacterSet characterSetWithCharactersInString:mw_str_take(u, n)];
    [_parts removeAllObjects]; [_parts addObject:fresh]; _minv = NO;
}
- (void)removeCharactersInRange:(NSRange)r { NSCharacterSet *old = [[self copy] autorelease]; [self _keep:^BOOL(unichar c) { return [old characterIsMember:c] && !NSLocationInRange(c, r); }]; }
- (void)removeCharactersInString:(NSString *)str { NSCharacterSet *old = [[self copy] autorelease], *rm = [NSCharacterSet characterSetWithCharactersInString:str]; [self _keep:^BOOL(unichar c) { return [old characterIsMember:c] && ![rm characterIsMember:c]; }]; }
- (void)formIntersectionWithCharacterSet:(NSCharacterSet *)o { NSCharacterSet *old = [[self copy] autorelease]; [self _keep:^BOOL(unichar c) { return [old characterIsMember:c] && [o characterIsMember:c]; }]; }
- (NSCharacterSet *)invertedSet { NSMutableCharacterSet *s = [[self copy] autorelease]; [s invert]; return s; }
- (id)copyWithZone:(NSZone *)z { NSMutableCharacterSet *s = [[NSMutableCharacterSet alloc] init]; [s->_parts addObjectsFromArray:_parts]; s->_minv = _minv; return s; }
- (id)mutableCopyWithZone:(NSZone *)z { return [self copyWithZone:z]; }
@end
@implementation NSCharacterSet (MutableCopy)
- (id)mutableCopyWithZone:(NSZone *)z { NSMutableCharacterSet *s = [[NSMutableCharacterSet alloc] init]; [s formUnionWithCharacterSet:self]; return s; }
- (id)mutableCopy { return [self mutableCopyWithZone:0]; }
@end

/* ================================================================ NSScanner */
@implementation NSScanner { NSString *_s; unichar *_u; NSUInteger _n, _pos; NSCharacterSet *_skip; BOOL _case; }
+ (instancetype)scannerWithString:(NSString *)s { return [[[self alloc] initWithString:s] autorelease]; }
- (instancetype)initWithString:(NSString *)s {
    _s = [s copy]; _u = mw_chars(_s, &_n);
    _skip = [[NSCharacterSet whitespaceAndNewlineCharacterSet] retain];
    return self;
}
- (void)dealloc { [_s release]; free(_u); [_skip release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSScanner *c = [[NSScanner alloc] initWithString:_s]; c->_pos = _pos; [c setCharactersToBeSkipped:_skip]; c->_case = _case; return c; }
- (NSString *)string { return _s; }
- (NSUInteger)scanLocation { return _pos; }
- (void)setScanLocation:(NSUInteger)p { if (p > _n) mw_raise("NSRangeException", "-[NSScanner setScanLocation:] index beyond bounds"); _pos = p; }
- (NSCharacterSet *)charactersToBeSkipped { return _skip; }
- (void)setCharactersToBeSkipped:(NSCharacterSet *)c { [_skip release]; _skip = [c copy]; }
- (BOOL)caseSensitive { return _case; }
- (void)setCaseSensitive:(BOOL)c { _case = c; }
static NSUInteger skipped(NSScanner *s) { NSUInteger p = s->_pos; if (s->_skip) while (p < s->_n && [s->_skip characterIsMember:s->_u[p]]) p++; return p; }
- (BOOL)isAtEnd { return skipped(self) >= _n; }
static BOOL eqc(unichar a, unichar b, BOOL cs) { return a == b || (!cs && a < 128 && b < 128 && tolower(a) == tolower(b)); }
static BOOL match_at(NSScanner *s, NSUInteger p, const unichar *w, NSUInteger m) {
    if (p + m > s->_n) return NO;
    for (NSUInteger i = 0; i < m; i++) if (!eqc(s->_u[p + i], w[i], s->_case)) return NO;
    return YES;
}
static NSString *sub(NSScanner *s, NSUInteger a, NSUInteger b) { return [NSString stringWithCharacters:s->_u + a length:b - a]; }
- (BOOL)scanString:(NSString *)w intoString:(NSString **)out {
    NSUInteger p = skipped(self), m; unichar *wu = mw_chars(w, &m);
    BOOL ok = m && match_at(self, p, wu, m);
    free(wu);
    if (!ok) return NO;
    if (out) *out = sub(self, p, p + m);
    _pos = p + m; return YES;
}
- (BOOL)scanUpToString:(NSString *)w intoString:(NSString **)out {
    NSUInteger p = skipped(self), q = p, m; unichar *wu = mw_chars(w, &m);
    while (q < _n && !(m && match_at(self, q, wu, m))) q++;
    free(wu);
    if (q == p) return NO;
    if (out) *out = sub(self, p, q);
    _pos = q; return YES;
}
- (BOOL)scanCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)out {
    NSUInteger p = skipped(self), q = p;
    while (q < _n && [set characterIsMember:_u[q]]) q++;
    if (q == p) return NO;
    if (out) *out = sub(self, p, q);
    _pos = q; return YES;
}
- (BOOL)scanUpToCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)out {
    NSUInteger p = skipped(self), q = p;
    while (q < _n && ![set characterIsMember:_u[q]]) q++;
    if (q == p) return NO;
    if (out) *out = sub(self, p, q);
    _pos = q; return YES;
}
static BOOL scan_signed(NSScanner *s, long long *v) {
    NSUInteger p = skipped(s); BOOL neg = NO;
    if (p < s->_n && (s->_u[p] == '-' || s->_u[p] == '+')) neg = s->_u[p++] == '-';
    NSUInteger d = p; unsigned long long x = 0; BOOL over = NO;
    while (p < s->_n && s->_u[p] >= '0' && s->_u[p] <= '9') { unsigned long long nx = x * 10 + (s->_u[p] - '0'); if (nx < x) over = YES; x = nx; p++; }
    if (p == d) return NO;
    if (over || x > 0x7FFFFFFFFFFFFFFFull) x = neg ? 0x8000000000000000ull : 0x7FFFFFFFFFFFFFFFull, neg = NO;
    if (v) *v = neg ? -(long long)x : (long long)x;
    s->_pos = p; return YES;
}
- (BOOL)scanLongLong:(long long *)v { return scan_signed(self, v); }
- (BOOL)scanInteger:(NSInteger *)v { long long x; if (!scan_signed(self, &x)) return NO; if (v) *v = (NSInteger)x; return YES; }
- (BOOL)scanInt:(int *)v {
    long long x; if (!scan_signed(self, &x)) return NO;
    if (v) *v = x > 2147483647LL ? 2147483647 : x < -2147483648LL ? (int)-2147483648LL : (int)x;
    return YES;
}
- (BOOL)scanUnsignedLongLong:(unsigned long long *)v { long long x; if (!scan_signed(self, &x)) return NO; if (v) *v = (unsigned long long)x; return YES; }
- (BOOL)scanHexLongLong:(unsigned long long *)v {
    NSUInteger p = skipped(self);
    if (p + 1 < _n && _u[p] == '0' && (_u[p + 1] == 'x' || _u[p + 1] == 'X')) p += 2;
    NSUInteger d = p; unsigned long long x = 0;
    for (; p < _n; p++) {
        unichar c = _u[p]; int k = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (k < 0) break;
        x = x << 4 | (unsigned)k;
    }
    if (p == d) return NO;
    if (v) *v = x;
    _pos = p; return YES;
}
- (BOOL)scanHexInt:(unsigned *)v { unsigned long long x; if (![self scanHexLongLong:&x]) return NO; if (v) *v = x > 0xFFFFFFFFull ? 0xFFFFFFFFu : (unsigned)x; return YES; }
- (BOOL)scanDouble:(double *)v {
    NSUInteger p = skipped(self), q = p;
    while (q < _n && q - p < 255 && _u[q] < 128 && strchr("+-.0123456789eE", (int)_u[q])) q++;
    char b[256]; for (NSUInteger i = p; i < q; i++) b[i - p] = (char)_u[i]; b[q - p] = 0;
    char *end; double d = strtod(b, &end);
    if (end == b) return NO;
    if (v) *v = d;
    _pos = p + (NSUInteger)(end - b); return YES;
}
- (BOOL)scanFloat:(float *)v { double d; if (![self scanDouble:&d]) return NO; if (v) *v = (float)d; return YES; }
@end

/* ================================================================ NSUUID */
@implementation NSUUID { unsigned char _b[16]; }
+ (instancetype)UUID { return [[[self alloc] init] autorelease]; }
- (instancetype)init { getentropy(_b, 16); _b[6] = (_b[6] & 0x0F) | 0x40; _b[8] = (_b[8] & 0x3F) | 0x80; return self; }
- (instancetype)initWithUUIDBytes:(const unsigned char *)b { memcpy(_b, b, 16); return self; }
- (instancetype)initWithUUIDString:(NSString *)s {
    const char *c = [s UTF8String]; int k = 0;
    for (; *c && k < 32; c++) {
        if (*c == '-') continue;
        int v = *c >= '0' && *c <= '9' ? *c - '0' : (*c | 32) >= 'a' && (*c | 32) <= 'f' ? (*c | 32) - 'a' + 10 : -1;
        if (v < 0) { [self release]; return nil; }
        _b[k / 2] = (unsigned char)(k & 1 ? _b[k / 2] | v : v << 4); k++;
    }
    if (k != 32 || *c || [s length] != 36) { [self release]; return nil; }
    return self;
}
- (void)getUUIDBytes:(unsigned char *)b { memcpy(b, _b, 16); }
- (NSString *)UUIDString {
    return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            _b[0], _b[1], _b[2], _b[3], _b[4], _b[5], _b[6], _b[7], _b[8], _b[9], _b[10], _b[11], _b[12], _b[13], _b[14], _b[15]];
}
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSUUID class]] && !memcmp(_b, ((NSUUID *)o)->_b, 16)); }
- (NSUInteger)hash { NSUInteger h; memcpy(&h, _b, sizeof h); return h; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)description { return [NSString stringWithFormat:@"<__NSConcreteUUID %p> %@", self, [self UUIDString]]; }
@end

/* ================================================================ NSFileHandle (blocking; a readability handler is
 * called from a thread that reads ahead; ponytail: no notifications) */
@implementation NSFileHandle { int _fd; BOOL _close, _eof, _watching; NSMutableData *_pending; id _rh; }
static NSFileHandle *std_handle(int fd) { static NSFileHandle *h[3]; if (!h[fd]) h[fd] = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:NO]; return h[fd]; }
+ (NSFileHandle *)fileHandleWithStandardInput { return std_handle(0); }
+ (NSFileHandle *)fileHandleWithStandardOutput { return std_handle(1); }
+ (NSFileHandle *)fileHandleWithStandardError { return std_handle(2); }
+ (instancetype)fileHandleForReadingAtPath:(NSString *)p { int fd = open([p fileSystemRepresentation], 0); return fd < 0 ? nil : [[[self alloc] initWithFileDescriptor:fd closeOnDealloc:YES] autorelease]; }
+ (instancetype)fileHandleForWritingAtPath:(NSString *)p { int fd = open([p fileSystemRepresentation], 1); return fd < 0 ? nil : [[[self alloc] initWithFileDescriptor:fd closeOnDealloc:YES] autorelease]; }
- (instancetype)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)c { _fd = fd; _close = c; return self; }
- (instancetype)initWithFileDescriptor:(int)fd { return [self initWithFileDescriptor:fd closeOnDealloc:NO]; }
- (void)dealloc { if (_close && _fd >= 0) close(_fd); [_pending release]; [_rh release]; [super dealloc]; }
- (int)fileDescriptor { return _fd; }
/* the handler runs on a thread of its own each time data (or the end) arrives; -availableData hands that data out */
- (void)setReadabilityHandler:(void (^)(NSFileHandle *))h {
    BOOL start = NO;
    @synchronized(self) {
        id old = _rh; _rh = [h copy]; [old release];
        if (h && !_watching && _fd >= 0) start = _watching = YES;
    }
    if (start) [NSThread detachNewThreadSelector:@selector(_watch) toTarget:self withObject:nil];
}
- (void (^)(NSFileHandle *))readabilityHandler { @synchronized(self) { return [[_rh retain] autorelease]; } }
- (void)setWriteabilityHandler:(void (^)(NSFileHandle *))h {}   /* ponytail: writes do not wait here */
- (void (^)(NSFileHandle *))writeabilityHandler { return nil; }
- (void)_watch {
    char *buf = malloc(65536);
    for (BOOL more = YES; more;) {
        long r = read(_fd, buf, 65536);
        void (^h)(NSFileHandle *);
        @synchronized(self) {
            if (r > 0) { if (!_pending) _pending = [[NSMutableData alloc] init]; [_pending appendBytes:buf length:(NSUInteger)r]; }
            else _eof = YES;
            h = [_rh copy];
            more = r > 0 && h;
            if (!more) _watching = NO;
        }
        if (h) { void *pool = objc_autoreleasePoolPush(); h(self); objc_autoreleasePoolPop(pool); [h release]; }
    }
    free(buf);
}
- (void)writeData:(NSData *)d {
    const char *b = [d bytes]; NSUInteger n = [d length];
    while (n) { long w = write(_fd, b, n); if (w <= 0) mw_raise("NSFileHandleOperationException", "writeData: failed"); b += w; n -= (NSUInteger)w; }
}
- (NSData *)readDataOfLength:(NSUInteger)n {
    NSMutableData *d = [NSMutableData dataWithLength:n]; NSUInteger got = 0;
    while (got < n) { long r = read(_fd, (char *)[d mutableBytes] + got, n - got); if (r <= 0) break; got += (NSUInteger)r; }
    [d setLength:got]; return d;
}
- (NSData *)readDataToEndOfFile { NSMutableData *d = [NSMutableData data]; NSData *c; while ([(c = [self readDataOfLength:65536]) length]) [d appendData:c]; return d; }
- (NSData *)availableData {
    @synchronized(self) {
        if ([_pending length] || _eof) { NSData *d = _pending ? [_pending autorelease] : [NSData data]; _pending = nil; return d; }
    }
    NSMutableData *d = [NSMutableData dataWithLength:65536]; long r = read(_fd, [d mutableBytes], 65536); [d setLength:r > 0 ? (NSUInteger)r : 0]; return d; }
- (unsigned long long)seekToEndOfFile { return (unsigned long long)lseek(_fd, 0, 2); }
- (void)seekToFileOffset:(unsigned long long)o { lseek(_fd, (long)o, 0); }
- (unsigned long long)offsetInFile { return (unsigned long long)lseek(_fd, 0, 1); }
- (void)synchronizeFile { fsync(_fd); }
- (void)closeFile { if (_fd >= 0) close(_fd); _fd = -1; }
@end


/* ================================================================ small API gaps found with class-dump */
char *realpath(const char *, char *);
@implementation NSObject (KeyPath)
- (id)valueForKeyPath:(NSString *)p {
    id v = self;
    for (NSString *k in [p componentsSeparatedByString:@"."]) {
        if ([v isKindOfClass:[NSArray class]]) {
            if ([k isEqualToString:@"@count"]) { v = [NSNumber numberWithUnsignedInteger:[v count]]; continue; }
            NSMutableArray *r = [NSMutableArray array];
            for (id o in v) { id x = [o valueForKey:k]; [r addObject:x ? x : [NSNull null]]; }
            v = r;
        } else v = [v valueForKey:k];
    }
    return v;
}
@end
@implementation NSError (Reason)
- (NSString *)localizedFailureReason { return [[self userInfo] objectForKey:NSLocalizedFailureReasonErrorKey]; }
- (NSString *)localizedRecoverySuggestion { return [[self userInfo] objectForKey:NSLocalizedRecoverySuggestionErrorKey]; }
@end
int access(const char *, int);
@implementation NSFileManager (Access)
- (BOOL)isWritableFileAtPath:(NSString *)p { return access([p fileSystemRepresentation], 2) == 0; }
- (BOOL)isExecutableFileAtPath:(NSString *)p { return access([p fileSystemRepresentation], 1) == 0; }
@end
@implementation NSString (Paths2)
- (NSString *)stringByResolvingSymlinksInPath {
    char b[1024]; NSString *e = [self stringByExpandingTildeInPath];
    return realpath([e fileSystemRepresentation], b) ? [NSString stringWithUTF8String:b] : [e stringByStandardizingPath];
}
- (NSString *)decomposedStringWithCanonicalMapping { return [[self copy] autorelease]; }   /* ponytail: no Unicode normalization tables yet */
- (NSString *)precomposedStringWithCanonicalMapping { return [[self copy] autorelease]; }
@end
@implementation NSData (Mapped)
+ (instancetype)dataWithContentsOfMappedFile:(NSString *)p { return [self dataWithContentsOfFile:p]; }
@end

NSData *_scion_url_data(NSURL *, NSError **); NSString *_scion_url_string(NSURL *, NSStringEncoding, NSError **);
@implementation NSData (URL)
+ (instancetype)dataWithContentsOfURL:(NSURL *)u { return [u isFileURL] ? [self dataWithContentsOfFile:[u path]] : _scion_url_data(u, NULL); }
@end
@implementation NSString (URL)
+ (instancetype)stringWithContentsOfURL:(NSURL *)u encoding:(NSStringEncoding)e error:(NSError **)err { return [u isFileURL] ? [self stringWithContentsOfFile:[u path] encoding:e error:err] : _scion_url_string(u, e, err); }
@end

/* ================================================================ NSGeometry */
double floor(double); double ceil(double); double fmin(double, double); double fmax(double, double); double strtod(const char *, char **);
const NSPoint NSZeroPoint = {0, 0}; const NSSize NSZeroSize = {0, 0}; const NSRect NSZeroRect = {{0, 0}, {0, 0}};
const NSEdgeInsets NSEdgeInsetsZero = {0, 0, 0, 0};
BOOL NSEqualPoints(NSPoint a, NSPoint b) { return a.x == b.x && a.y == b.y; }
BOOL NSEqualSizes(NSSize a, NSSize b) { return a.width == b.width && a.height == b.height; }
BOOL NSEqualRects(NSRect a, NSRect b) { return NSEqualPoints(a.origin, b.origin) && NSEqualSizes(a.size, b.size); }
BOOL NSEdgeInsetsEqual(NSEdgeInsets a, NSEdgeInsets b) { return a.top == b.top && a.left == b.left && a.bottom == b.bottom && a.right == b.right; }
BOOL NSIsEmptyRect(NSRect r) { return !(r.size.width > 0 && r.size.height > 0); }
BOOL NSPointInRect(NSPoint p, NSRect r) { return p.x >= NSMinX(r) && p.y >= NSMinY(r) && p.x < NSMaxX(r) && p.y < NSMaxY(r); }
BOOL NSMouseInRect(NSPoint p, NSRect r, BOOL flipped) {
    return p.x >= NSMinX(r) && p.x < NSMaxX(r) && (flipped ? p.y >= NSMinY(r) && p.y < NSMaxY(r) : p.y > NSMinY(r) && p.y <= NSMaxY(r));
}
BOOL NSContainsRect(NSRect a, NSRect b) {
    return !NSIsEmptyRect(b) && NSMinX(a) <= NSMinX(b) && NSMinY(a) <= NSMinY(b) && NSMaxX(a) >= NSMaxX(b) && NSMaxY(a) >= NSMaxY(b);
}
NSRect NSIntersectionRect(NSRect a, NSRect b) {
    CGFloat x0 = fmax(NSMinX(a), NSMinX(b)), y0 = fmax(NSMinY(a), NSMinY(b)), x1 = fmin(NSMaxX(a), NSMaxX(b)), y1 = fmin(NSMaxY(a), NSMaxY(b));
    return x1 > x0 && y1 > y0 ? NSMakeRect(x0, y0, x1 - x0, y1 - y0) : NSZeroRect;
}
BOOL NSIntersectsRect(NSRect a, NSRect b) { return !NSIsEmptyRect(NSIntersectionRect(a, b)); }
NSRect NSUnionRect(NSRect a, NSRect b) {
    if (NSIsEmptyRect(a)) return b;
    if (NSIsEmptyRect(b)) return a;
    CGFloat x0 = fmin(NSMinX(a), NSMinX(b)), y0 = fmin(NSMinY(a), NSMinY(b));
    return NSMakeRect(x0, y0, fmax(NSMaxX(a), NSMaxX(b)) - x0, fmax(NSMaxY(a), NSMaxY(b)) - y0);
}
NSRect NSInsetRect(NSRect r, CGFloat dx, CGFloat dy) { return NSMakeRect(r.origin.x + dx, r.origin.y + dy, r.size.width - 2 * dx, r.size.height - 2 * dy); }
NSRect NSOffsetRect(NSRect r, CGFloat dx, CGFloat dy) { r.origin.x += dx; r.origin.y += dy; return r; }
NSRect NSIntegralRect(NSRect r) {
    if (NSIsEmptyRect(r)) return NSZeroRect;
    CGFloat x0 = floor(NSMinX(r)), y0 = floor(NSMinY(r));
    return NSMakeRect(x0, y0, ceil(NSMaxX(r)) - x0, ceil(NSMaxY(r)) - y0);
}
void NSDivideRect(NSRect r, NSRect *slice, NSRect *rem, CGFloat amount, NSRectEdge edge) {
    NSRect s = r, m = r;
    if (edge == NSMinXEdge || edge == NSMaxXEdge) {
        amount = fmin(amount, r.size.width); s.size.width = amount; m.size.width -= amount;
        if (edge == NSMinXEdge) m.origin.x += amount; else s.origin.x = NSMaxX(r) - amount;
    } else {
        amount = fmin(amount, r.size.height); s.size.height = amount; m.size.height -= amount;
        if (edge == NSMinYEdge) m.origin.y += amount; else s.origin.y = NSMaxY(r) - amount;
    }
    if (slice) *slice = s;
    if (rem) *rem = m;
}
NSString *NSStringFromPoint(NSPoint p) { return [NSString stringWithFormat:@"{%g, %g}", p.x, p.y]; }
NSString *NSStringFromSize(NSSize s) { return [NSString stringWithFormat:@"{%g, %g}", s.width, s.height]; }
NSString *NSStringFromRect(NSRect r) { return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", r.origin.x, r.origin.y, r.size.width, r.size.height]; }
static int geo_nums(NSString *s, double *v, int n) {
    const char *p = [s UTF8String]; int k = 0;
    while (p && *p && k < n) { char *e; double d = strtod(p, &e); if (e != p) { v[k++] = d; p = e; } else p++; }
    return k;
}
NSPoint NSPointFromString(NSString *s) { double v[2] = {0}; geo_nums(s, v, 2); return NSMakePoint(v[0], v[1]); }
NSSize NSSizeFromString(NSString *s) { double v[2] = {0}; geo_nums(s, v, 2); return NSMakeSize(v[0], v[1]); }
NSRect NSRectFromString(NSString *s) { double v[4] = {0}; geo_nums(s, v, 4); return NSMakeRect(v[0], v[1], v[2], v[3]); }

/* ================================================================ NSAttributedString (one attribute set for the whole string) */
@implementation NSAttributedString { @protected NSMutableString *_s; NSMutableDictionary *_a; }
- (instancetype)init { return [self initWithString:@"" attributes:nil]; }
- (instancetype)initWithString:(NSString *)s { return [self initWithString:s attributes:nil]; }
- (instancetype)initWithString:(NSString *)s attributes:(NSDictionary *)a {
    if ((self = [super init])) { _s = [[NSMutableString alloc] initWithString:s ? s : @""]; _a = [[NSMutableDictionary alloc] initWithDictionary:a ? a : @{}]; }
    return self;
}
- (instancetype)initWithAttributedString:(NSAttributedString *)s { return [self initWithString:s.string attributes:[s attributesAtIndex:0 effectiveRange:0]]; }
- (void)dealloc { [_s release]; [_a release]; [super dealloc]; }
- (NSString *)string { return [[_s copy] autorelease]; }
- (NSUInteger)length { return [_s length]; }
- (NSDictionary *)attributesAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { if (r) *r = NSMakeRange(0, [_s length]); return [[_a copy] autorelease]; }
- (id)attribute:(NSString *)n atIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { if (r) *r = NSMakeRange(0, [_s length]); return [_a objectForKey:n]; }
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)r { return [[[NSAttributedString alloc] initWithString:[_s substringWithRange:r] attributes:_a] autorelease]; }
- (void)enumerateAttributesInRange:(NSRange)r options:(NSUInteger)o usingBlock:(void (^)(NSDictionary *, NSRange, BOOL *))b { BOOL stop = NO; b(_a, r, &stop); }
- (id)copyWithZone:(NSZone *)z { return [[NSAttributedString alloc] initWithString:_s attributes:_a]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableAttributedString alloc] initWithString:_s attributes:_a]; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSAttributedString class]] && [_s isEqualToString:[o string]]; }
- (NSString *)description { return [_s description]; }
@end
@implementation NSMutableAttributedString
- (void)appendAttributedString:(NSAttributedString *)s { [_s appendString:s.string]; if (![_a count]) [_a addEntriesFromDictionary:[s attributesAtIndex:0 effectiveRange:0]]; }
- (void)addAttribute:(NSString *)n value:(id)v range:(NSRange)r { [_a setObject:v forKey:n]; }
- (void)addAttributes:(NSDictionary *)a range:(NSRange)r { [_a addEntriesFromDictionary:a]; }
- (void)setAttributes:(NSDictionary *)a range:(NSRange)r { [_a removeAllObjects]; if (a) [_a addEntriesFromDictionary:a]; }
- (void)removeAttribute:(NSString *)n range:(NSRange)r { [_a removeObjectForKey:n]; }
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s { [_s replaceCharactersInRange:r withString:s]; }
/* one set of attributes for the whole string (ponytail): an empty string takes the inserted text's */
- (void)replaceCharactersInRange:(NSRange)r withAttributedString:(NSAttributedString *)s {
    if (![_s length] || ![_a count]) { [_a removeAllObjects]; if ([s length]) [_a addEntriesFromDictionary:[s attributesAtIndex:0 effectiveRange:0]]; }
    [_s replaceCharactersInRange:r withString:s.string];
}
- (void)insertAttributedString:(NSAttributedString *)s atIndex:(NSUInteger)i { [self replaceCharactersInRange:NSMakeRange(i, 0) withAttributedString:s]; }
- (void)deleteCharactersInRange:(NSRange)r { [_s deleteCharactersInRange:r]; }
- (void)setAttributedString:(NSAttributedString *)s { [self replaceCharactersInRange:NSMakeRange(0, [_s length]) withAttributedString:s]; }
- (void)beginEditing { } - (void)endEditing { }
- (NSMutableString *)mutableString { return _s; }
@end

/* ================================================================ NSTask, on posix_spawn: a thread per task waits for it to
 * end, then sets its status and calls the termination handler (and posts NSTaskDidTerminateNotification) there */
int posix_spawn(int *, const char *, void *const *, void *const *, char *const[], char *const[]);
int posix_spawn_file_actions_init(void **); int posix_spawn_file_actions_destroy(void **);
int posix_spawn_file_actions_adddup2(void **, int, int); int posix_spawn_file_actions_addchdir_np(void **, const char *);
int posix_spawnattr_init(void **); int posix_spawnattr_destroy(void **); int posix_spawnattr_setflags(void **, short);
int waitpid(int, int *, int); int kill(int, int); int usleep(unsigned);
NSNotificationName const NSTaskDidTerminateNotification = @"NSTaskDidTerminateNotification";
@implementation NSTask {
    int _pid, _status; NSTaskTerminationReason _reason; BOOL _launched; volatile BOOL _running;
}
@synthesize executableURL, launchPath, arguments, environment, currentDirectoryURL, currentDirectoryPath, standardInput, standardOutput,
    standardError, terminationHandler;
- (void)dealloc {
    [executableURL release]; [launchPath release]; [arguments release]; [environment release]; [currentDirectoryURL release];
    [currentDirectoryPath release]; [standardInput release]; [standardOutput release]; [standardError release]; [terminationHandler release];
    [super dealloc];
}
- (int)processIdentifier { return _pid; }
- (int)terminationStatus {
    if (!_launched || _running) mw_raise("NSInvalidArgumentException", "task not launched or still running");
    return _status;
}
- (NSTaskTerminationReason)terminationReason { return _reason; }
- (BOOL)isRunning { return __atomic_load_n(&_running, __ATOMIC_ACQUIRE); }
static int task_fd(id io, BOOL input) {   /* the descriptor a standardInput/Output/Error stands for, -1: this process's */
    if ([io isKindOfClass:[NSPipe class]]) return [(input ? [io fileHandleForReading] : [io fileHandleForWriting]) fileDescriptor];
    if ([io isKindOfClass:[NSFileHandle class]]) return [io fileDescriptor];
    return -1;
}
- (BOOL)launchAndReturnError:(NSError **)error {
    if (_launched) mw_raise("NSInvalidArgumentException", "task already launched");
    NSString *path = executableURL ? [executableURL path] : launchPath;
    if (!path) mw_raise("NSInvalidArgumentException", "must provide launch path");
    NSUInteger n = [arguments count];
    char **argv = calloc(n + 2, sizeof *argv);
    argv[0] = (char *)[path fileSystemRepresentation];
    for (NSUInteger i = 0; i < n; i++) argv[i + 1] = (char *)[[[arguments objectAtIndex:i] description] UTF8String];
    char **envp = 0;
    if (environment) {
        envp = calloc([environment count] + 1, sizeof *envp);
        NSUInteger k = 0;
        for (NSString *key in environment) envp[k++] = (char *)[[NSString stringWithFormat:@"%@=%@", key, [environment objectForKey:key]] UTF8String];
    }
    void *fa, *at;
    posix_spawn_file_actions_init(&fa);
    id io[3] = {standardInput, standardOutput, standardError};
    for (int i = 0; i < 3; i++) { int fd = task_fd(io[i], i == 0); if (fd >= 0) posix_spawn_file_actions_adddup2(&fa, fd, i); }
    NSString *cwd = currentDirectoryURL ? [currentDirectoryURL path] : currentDirectoryPath;
    if (cwd) posix_spawn_file_actions_addchdir_np(&fa, [cwd fileSystemRepresentation]);
    posix_spawnattr_init(&at);
    posix_spawnattr_setflags(&at, 0x4000 /* POSIX_SPAWN_CLOEXEC_DEFAULT, as Foundation */);
    int r = posix_spawn(&_pid, argv[0], &fa, &at, argv, envp);
    posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&at);
    free(argv); free(envp);
    if (r) {
        if (error) *error = r == 2 ? [NSError errorWithDomain:NSCocoaErrorDomain code:4 /* NSFileNoSuchFileError */ userInfo:@{NSFilePathErrorKey: path}]
                                   : mw_posix_error(r, path);
        return NO;
    }
    /* the child's ends of pipes close here, so reading the other end sees the end when the child is done */
    if ([standardInput isKindOfClass:[NSPipe class]]) [[standardInput fileHandleForReading] closeFile];
    if ([standardOutput isKindOfClass:[NSPipe class]]) [[standardOutput fileHandleForWriting] closeFile];
    if ([standardError isKindOfClass:[NSPipe class]]) [[standardError fileHandleForWriting] closeFile];
    _launched = YES; _running = YES;
    [NSThread detachNewThreadSelector:@selector(_reap) toTarget:self withObject:nil];   /* (the thread keeps the task) */
    return YES;
}
- (void)_reap {
    int st = 0;
    while (waitpid(_pid, &st, 0) < 0 && errno == 4 /* EINTR */) {}
    if (st & 0x7f) { _reason = NSTaskTerminationReasonUncaughtSignal; _status = st & 0x7f; }
    else { _reason = NSTaskTerminationReasonExit; _status = (st >> 8) & 0xff; }
    __atomic_store_n(&_running, NO, __ATOMIC_RELEASE);
    void *pool = objc_autoreleasePoolPush();
    void (^h)(NSTask *) = [[terminationHandler retain] autorelease];
    if (h) h(self);
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTaskDidTerminateNotification object:self];
    objc_autoreleasePoolPop(pool);
}
- (void)launch {
    NSError *e = nil;
    if (![self launchAndReturnError:&e]) mw_raise("NSInvalidArgumentException", "launch path not accessible");
}
/* the main thread's run loop keeps running meanwhile, as in Foundation */
- (void)waitUntilExit {
    while ([self isRunning]) {
        if ([NSThread isMainThread]) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        else usleep(1000);
    }
}
- (void)terminate { if ([self isRunning]) kill(_pid, 15); }
- (void)interrupt { if ([self isRunning]) kill(_pid, 2); }
- (BOOL)suspend { return [self isRunning] && kill(_pid, 17) == 0; }
- (BOOL)resume { return [self isRunning] && kill(_pid, 19) == 0; }
@end
