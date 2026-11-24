/* system.m — scion Foundation: NSObject(Foundation), NSLog, NSError, NSDate, NSProcessInfo, NSFileManager,
 * NSThread, locks, NSAutoreleasePool, NSUserDefaults, helpers and the CoreFoundation basics. MRC. */
#import "internal.h"
#include "../hostcalls.h"

typedef struct DIR DIR;
int stat(const char *, struct dstat *); int mkdir(const char *, int); int rmdir(const char *); int unlink(const char *);
int rename(const char *, const char *); char *getcwd(char *, size_t); int chdir(const char *);
DIR *opendir(const char *); int readdir_r(DIR *, struct ddirent *, struct ddirent **); int closedir(DIR *);
char *strerror(int); int clock_gettime(int, struct timespec *);
struct tm { int sec, min, hour, mday, mon, year, wday, yday, isdst; long gmtoff; const char *zone; };
struct tm *localtime_r(const int64_t *, struct tm *);
char ***_NSGetArgv(void); int *_NSGetArgc(void); char ***_NSGetEnviron(void);
int sysctlbyname(const char *, void *, size_t *, void *, size_t); long sysconf(int); int usleep(unsigned);
int pthread_key_create(unsigned long *, void (*)(void *)); void *pthread_getspecific(unsigned long); int pthread_setspecific(unsigned long, const void *);
int pthread_threadid_np(void *, uint64_t *); int pthread_detach(void *);
void *_Block_copy(const void *); void _Block_release(const void *);
int _scion_dispatch_drain_main(void);
extern const char *(*_scion_describe_object)(void *);

@interface NSObject (MWIndent) - (NSString *)descriptionWithIndent:(int)i; @end

/* ================================================================ helpers */
void mw_raise(const char *name, const char *reason) {
    [NSException raise:[NSString stringWithUTF8String:name] format:@"%s", reason];
    __builtin_unreachable();
}
NSString *mw_darwin_errstr(int e) { return [NSString stringWithUTF8String:strerror(e)]; }
NSError *mw_posix_error(int code, NSString *path) {
    NSMutableDictionary *u = [NSMutableDictionary dictionaryWithObject:mw_darwin_errstr(code) forKey:NSLocalizedDescriptionKey];
    if (path) [u setObject:path forKey:NSFilePathErrorKey];
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:u];
}
static const char *describe(void *o) { return [[(id)o description] UTF8String]; }
static unsigned long thread_key;
static id main_thread;

/* ================================================================ NSObject(Foundation) */
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
@implementation NSObject (Foundation)
- (NSString *)description { return [NSString stringWithFormat:@"<%s: %p>", class_getName(object_getClass(self)), self]; }
+ (NSString *)description { return [NSString stringWithUTF8String:class_getName(self)]; }
- (NSString *)debugDescription { return [self description]; }
- (void)doesNotRecognizeSelector:(SEL)s {
    [NSException raise:NSInvalidArgumentException format:@"-[%s %s]: unrecognized selector sent to instance %p", class_getName(object_getClass(self)), sel_getName(s), self];
}
+ (void)doesNotRecognizeSelector:(SEL)s {
    [NSException raise:NSInvalidArgumentException format:@"+[%s %s]: unrecognized selector sent to class %p", class_getName(self), sel_getName(s), self];
}
/* key-value coding: accessor methods first (key, getKey, isKey, _key / setKey:, _setKey:), then instance variables
 * (_key, _isKey, key, isKey); numbers box and unbox scalar types. ponytail: structs other than the geometry ones are not boxed */
#if __x86_64__
void objc_msgSend_stret(void);
#endif
static NSString *cap(NSString *k) { return [[[k substringToIndex:1] uppercaseString] stringByAppendingString:[k substringFromIndex:1]]; }
static id box(const char *t, void *p) {
    switch (*t) {
    case '@': case '#': return *(id *)p;
    case 'c': return [NSNumber numberWithChar:*(char *)p]; case 'B': return [NSNumber numberWithBool:*(_Bool *)p];
    case 'C': return [NSNumber numberWithUnsignedChar:*(unsigned char *)p];
    case 's': return [NSNumber numberWithShort:*(short *)p]; case 'S': return [NSNumber numberWithUnsignedShort:*(unsigned short *)p];
    case 'i': return [NSNumber numberWithInt:*(int *)p]; case 'I': return [NSNumber numberWithUnsignedInt:*(unsigned *)p];
    case 'l': case 'q': return [NSNumber numberWithLongLong:*(long long *)p]; case 'L': case 'Q': return [NSNumber numberWithUnsignedLongLong:*(unsigned long long *)p];
    case 'f': return [NSNumber numberWithFloat:*(float *)p]; case 'd': return [NSNumber numberWithDouble:*(double *)p];
    case '{':
        if (!strncmp(t, "{CGRect", 7) || !strncmp(t, "{_NSRect", 8)) return [NSValue valueWithRect:*(NSRect *)p];
        if (!strncmp(t, "{CGPoint", 8) || !strncmp(t, "{_NSPoint", 9)) return [NSValue valueWithPoint:*(NSPoint *)p];
        if (!strncmp(t, "{CGSize", 7) || !strncmp(t, "{_NSSize", 8)) return [NSValue valueWithSize:*(NSSize *)p];
        if (!strncmp(t, "{_NSRange", 9)) return [NSValue valueWithRange:*(NSRange *)p];
    }
    return nil;
}
static BOOL unbox(const char *t, id v, void *p) { /* nil numbers become 0 */
    switch (*t) {
    case 'c': *(char *)p = (char)[v charValue]; return YES; case 'B': *(_Bool *)p = [v boolValue]; return YES;
    case 'C': *(unsigned char *)p = (unsigned char)[v unsignedCharValue]; return YES;
    case 's': *(short *)p = [v shortValue]; return YES; case 'S': *(unsigned short *)p = [v unsignedShortValue]; return YES;
    case 'i': *(int *)p = [v intValue]; return YES; case 'I': *(unsigned *)p = [v unsignedIntValue]; return YES;
    case 'l': case 'q': *(long long *)p = [v longLongValue]; return YES; case 'L': case 'Q': *(unsigned long long *)p = [v unsignedLongLongValue]; return YES;
    case 'f': *(float *)p = [v floatValue]; return YES; case 'd': *(double *)p = [v doubleValue]; return YES;
    case '{':
        if (!strncmp(t, "{CGRect", 7) || !strncmp(t, "{_NSRect", 8)) { *(NSRect *)p = [v rectValue]; return YES; }
        if (!strncmp(t, "{CGPoint", 8) || !strncmp(t, "{_NSPoint", 9)) { *(NSPoint *)p = [v pointValue]; return YES; }
        if (!strncmp(t, "{CGSize", 7) || !strncmp(t, "{_NSSize", 8)) { *(NSSize *)p = [v sizeValue]; return YES; }
        if (!strncmp(t, "{_NSRange", 9)) { *(NSRange *)p = [v rangeValue]; return YES; }
    }
    return NO;
}
static Ivar find_ivar(Class c, NSString *k) {
    for (NSString *n in @[[@"_" stringByAppendingString:k], [@"_is" stringByAppendingString:cap(k)], k, [@"is" stringByAppendingString:cap(k)]]) {
        Ivar iv = class_getInstanceVariable(c, [n UTF8String]); if (iv) return iv;
    }
    return NULL;
}
+ (BOOL)accessInstanceVariablesDirectly { return YES; }
- (id)valueForKey:(NSString *)k {
    if (![k length]) return [self valueForUndefinedKey:k];
    for (NSString *n in @[k, [@"get" stringByAppendingString:cap(k)], [@"is" stringByAppendingString:cap(k)], [@"_" stringByAppendingString:k]]) {
        SEL s = sel_registerName([n UTF8String]);
        Method m = class_getInstanceMethod(object_getClass(self), s);
        if (!m) continue;
        char t[64]; method_getReturnType(m, t, sizeof t);
        const char *rt = t; while (*rt == 'r' || *rt == 'n' || *rt == 'N' || *rt == 'o' || *rt == 'O' || *rt == 'R' || *rt == 'V') rt++;
        switch (*rt) {
        case '@': case '#': return ((id (*)(id, SEL))objc_msgSend)(self, s);
        case 'c': case 'B': case 'C': { char v = ((char (*)(id, SEL))objc_msgSend)(self, s); return box(rt, &v); }
        case 's': case 'S': { short v = ((short (*)(id, SEL))objc_msgSend)(self, s); return box(rt, &v); }
        case 'i': case 'I': { int v = ((int (*)(id, SEL))objc_msgSend)(self, s); return box(rt, &v); }
        case 'l': case 'q': case 'L': case 'Q': { long long v = ((long long (*)(id, SEL))objc_msgSend)(self, s); return box(rt, &v); }
        case 'f': { float v = ((float (*)(id, SEL))objc_msgSend)(self, s); return box(rt, &v); }
        case 'd': { double v = ((double (*)(id, SEL))objc_msgSend)(self, s); return box(rt, &v); }
        case '{': {
            if (!strncmp(rt, "{CGRect", 7) || !strncmp(rt, "{_NSRect", 8)) {
#if __x86_64__
                NSRect r = ((NSRect (*)(id, SEL))(void *)objc_msgSend_stret)(self, s);
#else
                NSRect r = ((NSRect (*)(id, SEL))objc_msgSend)(self, s);
#endif
                return box(rt, &r);
            }
            if (!strncmp(rt, "{CGPoint", 8) || !strncmp(rt, "{_NSPoint", 9) || !strncmp(rt, "{CGSize", 7) || !strncmp(rt, "{_NSSize", 8) || !strncmp(rt, "{_NSRange", 9)) {
                NSPoint pt = ((NSPoint (*)(id, SEL))objc_msgSend)(self, s); return box(rt, &pt); /* two words: returned in registers */
            }
            return nil;
        }
        default: return nil;
        }
    }
    if ([[self class] accessInstanceVariablesDirectly]) {
        Ivar iv = find_ivar(object_getClass(self), k);
        if (iv) return box(ivar_getTypeEncoding(iv), (char *)self + ivar_getOffset(iv));
    }
    return [self valueForUndefinedKey:k];
}
- (id)valueForUndefinedKey:(NSString *)k {
    [NSException raise:@"NSUnknownKeyException" format:@"[<%s %p> valueForUndefinedKey:]: this class is not key value coding-compliant for the key %@.", class_getName(object_getClass(self)), self, k];
    return nil;
}
- (void)setValue:(id)v forKey:(NSString *)k {
    if (![k length]) { [self setValue:v forUndefinedKey:k]; return; }
    for (NSString *n in @[[NSString stringWithFormat:@"set%@:", cap(k)], [NSString stringWithFormat:@"_set%@:", cap(k)]]) {
        SEL s = sel_registerName([n UTF8String]);
        Method m = class_getInstanceMethod(object_getClass(self), s);
        if (!m) continue;
        char t[64]; method_getArgumentType(m, 2, t, sizeof t);
        const char *at = t; while (*at == 'r' || *at == 'n' || *at == 'N' || *at == 'o' || *at == 'O' || *at == 'R' || *at == 'V') at++;
        if (*at == '@' || *at == '#') { ((void (*)(id, SEL, id))objc_msgSend)(self, s, v); return; }
        if (!v && *at != '{') { [self setNilValueForKey:k]; return; }
        switch (*at) {
        case 'c': case 'B': case 'C': ((void (*)(id, SEL, char))objc_msgSend)(self, s, *at == 'B' ? (char)[v boolValue] : (char)[v charValue]); return;
        case 's': case 'S': ((void (*)(id, SEL, short))objc_msgSend)(self, s, [v shortValue]); return;
        case 'i': case 'I': ((void (*)(id, SEL, int))objc_msgSend)(self, s, [v intValue]); return;
        case 'l': case 'q': case 'L': case 'Q': ((void (*)(id, SEL, long long))objc_msgSend)(self, s, [v longLongValue]); return;
        case 'f': ((void (*)(id, SEL, float))objc_msgSend)(self, s, [v floatValue]); return;
        case 'd': ((void (*)(id, SEL, double))objc_msgSend)(self, s, [v doubleValue]); return;
        case '{':
            if (!strncmp(at, "{CGRect", 7) || !strncmp(at, "{_NSRect", 8)) { ((void (*)(id, SEL, NSRect))objc_msgSend)(self, s, [v rectValue]); return; }
            if (!strncmp(at, "{CGPoint", 8) || !strncmp(at, "{_NSPoint", 9)) { ((void (*)(id, SEL, NSPoint))objc_msgSend)(self, s, [v pointValue]); return; }
            if (!strncmp(at, "{CGSize", 7) || !strncmp(at, "{_NSSize", 8)) { ((void (*)(id, SEL, NSSize))objc_msgSend)(self, s, [v sizeValue]); return; }
            if (!strncmp(at, "{_NSRange", 9)) { ((void (*)(id, SEL, NSRange))objc_msgSend)(self, s, [v rangeValue]); return; }
        }
        break;
    }
    if ([[self class] accessInstanceVariablesDirectly]) {
        Ivar iv = find_ivar(object_getClass(self), k);
        if (iv) {
            const char *t = ivar_getTypeEncoding(iv); char *p = (char *)self + ivar_getOffset(iv);
            if (*t == '@') { [self willChangeValueForKey:k]; id old = *(id *)p; *(id *)p = [v retain]; [old release]; [self didChangeValueForKey:k]; return; }
            if (!v) { [self setNilValueForKey:k]; return; }
            [self willChangeValueForKey:k];
            BOOL ok = unbox(t, v, p);
            [self didChangeValueForKey:k];
            if (ok) return;
        }
    }
    [self setValue:v forUndefinedKey:k];
}
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {
    [NSException raise:@"NSUnknownKeyException" format:@"[<%s %p> setValue:forUndefinedKey:]: this class is not key value coding-compliant for the key %@.", class_getName(object_getClass(self)), self, k];
}
- (void)setNilValueForKey:(NSString *)k { [NSException raise:NSInvalidArgumentException format:@"[<%s %p> setNilValueForKey]: could not set nil as the value for the key %@.", class_getName(object_getClass(self)), self, k]; }
- (NSDictionary *)dictionaryWithValuesForKeys:(NSArray *)keys { NSMutableDictionary *d = [NSMutableDictionary dictionary]; for (NSString *k in keys) { id v = [self valueForKey:k]; d[k] = v ? v : [NSNull null]; } return d; }
- (void)setValuesForKeysWithDictionary:(NSDictionary *)d { for (NSString *k in d) { id v = d[k]; [self setValue:v == [NSNull null] ? nil : v forKey:k]; } }
@end

/* ================================================================ NSLog */
void NSLogv(NSString *f, va_list ap) {
    NSString *m = [[NSString alloc] initWithFormat:f arguments:ap];
    struct timespec ts; clock_gettime(0, &ts);
    struct tm tm; localtime_r(&ts.tv_sec, &tm);
    uint64_t tid = 0; pthread_threadid_np(0, &tid);
    char **av = *_NSGetArgv(); const char *pn = av && av[0] ? av[0] : "app", *sl = strrchr(pn, '/');
    char *line = 0;
    asprintf(&line, "%04d-%02d-%02d %02d:%02d:%02d.%03d %s[%d:%llx] %s\n", tm.year + 1900, tm.mon + 1, tm.mday, tm.hour, tm.min, tm.sec,
             (int)(ts.tv_nsec / 1000000), sl ? sl + 1 : pn, getpid(), (unsigned long long)tid, [m UTF8String]);
    write(2, line, strlen(line)); free(line); [m release];
}
void NSLog(NSString *f, ...) { va_list ap; va_start(ap, f); NSLogv(f, ap); va_end(ap); }

NSString *NSStringFromClass(Class c) { return c ? [NSString stringWithUTF8String:class_getName(c)] : nil; }
Class NSClassFromString(NSString *s) { return s ? objc_getClass([s UTF8String]) : Nil; }
NSString *NSStringFromSelector(SEL s) { return s ? [NSString stringWithUTF8String:sel_getName(s)] : nil; }
SEL NSSelectorFromString(NSString *s) { return s ? sel_registerName([s UTF8String]) : (SEL)0; }
NSString *NSStringFromRange(NSRange r) { return [NSString stringWithFormat:@"{%lu, %lu}", (unsigned long)r.location, (unsigned long)r.length]; }
NSString *NSUserName(void) { const char *u = getenv("USER"); if (!u) u = getenv("USERNAME"); return [NSString stringWithUTF8String:u ? u : "user"]; }
NSString *NSHomeDirectory(void) { const char *h = getenv("HOME"); return h ? [NSString stringWithUTF8String:h] : [@"/Users/" stringByAppendingString:NSUserName()]; }
NSString *NSTemporaryDirectory(void) { return @"/tmp/"; }

/* ================================================================ NSError */
NSString *const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain", *const NSCocoaErrorDomain = @"NSCocoaErrorDomain";
NSString *const NSLocalizedDescriptionKey = @"NSLocalizedDescription", *const NSFilePathErrorKey = @"NSFilePath";
@implementation NSError { NSString *_domain; NSInteger _code; NSDictionary *_info; }
+ (instancetype)errorWithDomain:(NSString *)d code:(NSInteger)c userInfo:(NSDictionary *)u { return [[[self alloc] initWithDomain:d code:c userInfo:u] autorelease]; }
- (instancetype)initWithDomain:(NSString *)d code:(NSInteger)c userInfo:(NSDictionary *)u { _domain = [d copy]; _code = c; _info = [u copy]; return self; }
- (void)dealloc { [_domain release]; [_info release]; [super dealloc]; }
- (NSString *)domain { return _domain; }
- (NSInteger)code { return _code; }
- (NSDictionary *)userInfo { return _info ? _info : [NSDictionary dictionary]; }
- (NSString *)localizedDescription {
    NSString *s = [_info objectForKey:NSLocalizedDescriptionKey];
    return s ? s : [NSString stringWithFormat:@"The operation couldn't be completed. (%@ error %ld.)", _domain, (long)_code];
}
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)description { return [NSString stringWithFormat:@"Error Domain=%@ Code=%ld \"%@\"", _domain, (long)_code, [self localizedDescription]]; }
@end

/* ================================================================ NSException (thrown through libobjc -> libc++abi) */
NSString *const NSGenericException = @"NSGenericException", *const NSRangeException = @"NSRangeException";
NSString *const NSInvalidArgumentException = @"NSInvalidArgumentException", *const NSInternalInconsistencyException = @"NSInternalInconsistencyException";
NSString *const NSMallocException = @"NSMallocException", *const NSUndefinedKeyException = @"NSUnknownKeyException";
void objc_exception_throw(id) __attribute__((noreturn));
typedef void (*objc_uncaught_exception_handler)(id);
objc_uncaught_exception_handler objc_setUncaughtExceptionHandler(objc_uncaught_exception_handler);
@implementation NSException { NSString *_name, *_reason; NSDictionary *_info; }
+ (NSException *)exceptionWithName:(NSString *)n reason:(NSString *)r userInfo:(NSDictionary *)u { return [[[self alloc] initWithName:n reason:r userInfo:u] autorelease]; }
- (instancetype)initWithName:(NSString *)n reason:(NSString *)r userInfo:(NSDictionary *)u { _name = [n copy]; _reason = [r copy]; _info = [u copy]; return self; }
+ (void)raise:(NSString *)n format:(NSString *)f arguments:(va_list)ap {
    NSString *r = [[[NSString alloc] initWithFormat:f arguments:ap] autorelease];
    [[self exceptionWithName:n reason:r userInfo:nil] raise];
}
+ (void)raise:(NSString *)n format:(NSString *)f, ... { va_list ap; va_start(ap, f); [self raise:n format:f arguments:ap]; va_end(ap); }
- (void)raise { objc_exception_throw(self); }
- (void)dealloc { [_name release]; [_reason release]; [_info release]; [super dealloc]; }
- (NSString *)name { return _name; }
- (NSString *)reason { return _reason; }
- (NSDictionary *)userInfo { return _info; }
- (NSArray *)callStackSymbols { return [NSArray array]; }          /* ponytail: no symbolized backtrace yet */
- (NSArray *)callStackReturnAddresses { return [NSArray array]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)description { return _reason ? _reason : _name; }
@end
static NSUncaughtExceptionHandler *user_uncaught;
void NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *h) { user_uncaught = h; }
NSUncaughtExceptionHandler *NSGetUncaughtExceptionHandler(void) { return user_uncaught; }
static void foundation_uncaught(id e) {
    if (user_uncaught && [e isKindOfClass:[NSException class]]) user_uncaught(e);
    char *m = 0;
    if ([e isKindOfClass:[NSException class]])
        asprintf(&m, "*** Terminating app due to uncaught exception '%s', reason: '%s'\n", [[e name] UTF8String], [[e reason] UTF8String] ?: "");
    else asprintf(&m, "*** Terminating app due to uncaught exception of class '%s'\n", class_getName(object_getClass(e)));
    write(2, m, strlen(m));
}

@implementation NSAssertionHandler
+ (NSAssertionHandler *)currentHandler { static NSAssertionHandler *h; if (!h) h = [[NSAssertionHandler alloc] init]; return h; }
- (void)handleFailureInMethod:(SEL)s object:(id)o file:(NSString *)f lineNumber:(NSInteger)l description:(NSString *)d, ... {
    va_list ap; va_start(ap, d); NSString *r = [[[NSString alloc] initWithFormat:d arguments:ap] autorelease]; va_end(ap);
    NSLog(@"*** Assertion failure in %c[%s %s], %@:%ld", object_getClass(o) && class_isMetaClass(object_getClass(o)) ? '+' : '-',
          class_getName(object_getClass(o)), sel_getName(s), [f lastPathComponent], (long)l);
    [NSException raise:NSInternalInconsistencyException format:@"%@", r];
}
- (void)handleFailureInFunction:(NSString *)fn file:(NSString *)f lineNumber:(NSInteger)l description:(NSString *)d, ... {
    va_list ap; va_start(ap, d); NSString *r = [[[NSString alloc] initWithFormat:d arguments:ap] autorelease]; va_end(ap);
    NSLog(@"*** Assertion failure in %@, %@:%ld", fn, [f lastPathComponent], (long)l);
    [NSException raise:NSInternalInconsistencyException format:@"%@", r];
}
@end

/* ================================================================ NSDate (reference date 2001-01-01 UTC) */
#define REF1970 978307200.0
static NSTimeInterval now_ref(void) { struct timespec t; clock_gettime(0, &t); return (double)t.tv_sec + t.tv_nsec / 1e9 - REF1970; }
@implementation NSDate { NSTimeInterval _t; }
- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)t { _t = t; return self; }
- (instancetype)init { _t = now_ref(); return self; }
+ (instancetype)dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)t { NSDate *d = [[self alloc] init]; d->_t = t; return [d autorelease]; }
+ (instancetype)date { return [self dateWithTimeIntervalSinceReferenceDate:now_ref()]; }
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)t { return [self dateWithTimeIntervalSinceReferenceDate:now_ref() + t]; }
+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)t { return [self dateWithTimeIntervalSinceReferenceDate:t - REF1970]; }
+ (instancetype)distantFuture { return [self dateWithTimeIntervalSinceReferenceDate:63113904000.0]; }
+ (instancetype)distantPast { return [self dateWithTimeIntervalSinceReferenceDate:-63114076800.0]; }
+ (NSTimeInterval)timeIntervalSinceReferenceDate { return now_ref(); }
- (NSTimeInterval)timeIntervalSinceReferenceDate { return _t; }
- (NSTimeInterval)timeIntervalSince1970 { return _t + REF1970; }
- (NSTimeInterval)timeIntervalSinceNow { return _t - now_ref(); }
- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)d { return _t - [d timeIntervalSinceReferenceDate]; }
- (instancetype)dateByAddingTimeInterval:(NSTimeInterval)t { return [NSDate dateWithTimeIntervalSinceReferenceDate:_t + t]; }
- (NSComparisonResult)compare:(NSDate *)d { NSTimeInterval o = [d timeIntervalSinceReferenceDate]; return _t < o ? NSOrderedAscending : _t > o ? NSOrderedDescending : NSOrderedSame; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSDate class]] && [self compare:o] == NSOrderedSame; }
- (NSUInteger)hash { return (NSUInteger)_t; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)description {
    struct tm tm; int64_t s = (int64_t)(_t + REF1970); localtime_r(&s, &tm);
    return [NSString stringWithFormat:@"%04d-%02d-%02d %02d:%02d:%02d +0000", tm.year + 1900, tm.mon + 1, tm.mday, tm.hour, tm.min, tm.sec];
}
@end

/* ================================================================ NSProcessInfo */
NSString *const NSProcessInfoThermalStateDidChangeNotification = @"NSProcessInfoThermalStateDidChangeNotification";
@implementation NSProcessInfo
- (NSProcessInfoThermalState)thermalState { return NSProcessInfoThermalStateNominal; }
- (BOOL)isLowPowerModeEnabled { return NO; }
+ (NSProcessInfo *)processInfo { static NSProcessInfo *p; if (!p) p = [[NSProcessInfo alloc] init]; return p; }
- (NSArray *)arguments {
    NSMutableArray *a = [NSMutableArray array]; char **v = *_NSGetArgv(); int n = *_NSGetArgc();
    for (int i = 0; i < n; i++) [a addObject:[NSString stringWithUTF8String:v[i]]];
    return a;
}
- (NSDictionary *)environment {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (char **e = *_NSGetEnviron(); e && *e; e++) {
        const char *eq = strchr(*e, '='); if (!eq) continue;
        [d setObject:[NSString stringWithUTF8String:eq + 1] forKey:[[[NSString alloc] initWithBytes:*e length:(NSUInteger)(eq - *e) encoding:NSUTF8StringEncoding] autorelease]];
    }
    return d;
}
- (int)processIdentifier { return getpid(); }
- (NSString *)processName { return [[[self arguments] firstObject] lastPathComponent]; }
- (NSString *)hostName { const char *h = getenv("COMPUTERNAME"); return [NSString stringWithUTF8String:h ? h : "localhost"]; }
- (NSString *)globallyUniqueString {
    unsigned char b[16]; extern int getentropy(void *, size_t); getentropy(b, 16);
    return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]];
}
- (NSUInteger)processorCount { return (NSUInteger)sysconf(58); }
- (NSUInteger)activeProcessorCount { return (NSUInteger)sysconf(58); }
- (unsigned long long)physicalMemory { uint64_t m = 0; size_t n = 8; if (sysctlbyname("hw.memsize", &m, &n, 0, 0) || !m) m = 8ull << 30; return m; }
- (NSTimeInterval)systemUptime { struct timespec t; clock_gettime(6, &t); return (double)t.tv_sec + t.tv_nsec / 1e9; }
- (NSOperatingSystemVersion)operatingSystemVersion { NSOperatingSystemVersion v = {14, 6, 0}; return v; }
- (NSString *)operatingSystemVersionString { return @"Version 14.6 (scion)"; }
- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)v { return v.majorVersion < 14 || (v.majorVersion == 14 && v.minorVersion <= 6); }
@end

/* ================================================================ NSFileManager */
NSString *const NSFileSize = @"NSFileSize", *const NSFileType = @"NSFileType", *const NSFileTypeDirectory = @"NSFileTypeDirectory";
NSString *const NSFileTypeRegular = @"NSFileTypeRegular", *const NSFileModificationDate = @"NSFileModificationDate";
#define S_IFMT 0170000
#define S_IFDIR 0040000
static BOOL fail(NSError **e, NSString *p) { if (e) *e = mw_posix_error(errno, p); return NO; }
@implementation NSFileManager
+ (NSFileManager *)defaultManager { static NSFileManager *m; if (!m) m = [[NSFileManager alloc] init]; return m; }
- (BOOL)fileExistsAtPath:(NSString *)p { return [self fileExistsAtPath:p isDirectory:0]; }
- (BOOL)fileExistsAtPath:(NSString *)p isDirectory:(BOOL *)d {
    struct dstat st; if (!p || stat([p fileSystemRepresentation], &st)) return NO;
    if (d) *d = (st.mode & S_IFMT) == S_IFDIR;
    return YES;
}
- (BOOL)isReadableFileAtPath:(NSString *)p { return [self fileExistsAtPath:p]; }
- (BOOL)createDirectoryAtPath:(NSString *)p withIntermediateDirectories:(BOOL)inter attributes:(NSDictionary *)a error:(NSError **)e {
    BOOL dir;
    if (inter) {
        if ([self fileExistsAtPath:p isDirectory:&dir] && dir) return YES;
        NSString *parent = [p stringByDeletingLastPathComponent];
        if ([parent length] && ![parent isEqualToString:p] && ![self createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:a error:e]) return NO;
    }
    return mkdir([p fileSystemRepresentation], 0755) == 0 || fail(e, p);
}
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)p error:(NSError **)e {
    DIR *d = opendir([p fileSystemRepresentation]);
    if (!d) { fail(e, p); return nil; }
    NSMutableArray *a = [NSMutableArray array]; struct ddirent ent, *r;
    while (!readdir_r(d, &ent, &r) && r)
        if (strcmp(ent.name, ".") && strcmp(ent.name, "..")) [a addObject:[NSString stringWithUTF8String:ent.name]];
    closedir(d);
    return a;
}
- (BOOL)removeItemAtPath:(NSString *)p error:(NSError **)e {
    BOOL dir;
    if (![self fileExistsAtPath:p isDirectory:&dir]) { errno = 2; return fail(e, p); }
    if (!dir) return unlink([p fileSystemRepresentation]) == 0 || fail(e, p);
    for (NSString *c in [self contentsOfDirectoryAtPath:p error:e])
        if (![self removeItemAtPath:[p stringByAppendingPathComponent:c] error:e]) return NO;
    return rmdir([p fileSystemRepresentation]) == 0 || fail(e, p);
}
- (BOOL)moveItemAtPath:(NSString *)a toPath:(NSString *)b error:(NSError **)e { return rename([a fileSystemRepresentation], [b fileSystemRepresentation]) == 0 || fail(e, a); }
- (BOOL)copyItemAtPath:(NSString *)a toPath:(NSString *)b error:(NSError **)e {
    BOOL dir;
    if (![self fileExistsAtPath:a isDirectory:&dir]) { errno = 2; return fail(e, a); }
    if (!dir) { NSData *d = [NSData dataWithContentsOfFile:a]; return (d && [d writeToFile:b atomically:YES]) || fail(e, b); }
    if (![self createDirectoryAtPath:b withIntermediateDirectories:NO attributes:nil error:e]) return NO;
    for (NSString *c in [self contentsOfDirectoryAtPath:a error:e])
        if (![self copyItemAtPath:[a stringByAppendingPathComponent:c] toPath:[b stringByAppendingPathComponent:c] error:e]) return NO;
    return YES;
}
- (NSDictionary *)attributesOfItemAtPath:(NSString *)p error:(NSError **)e {
    struct dstat st;
    if (stat([p fileSystemRepresentation], &st)) { fail(e, p); return nil; }
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:st.size], NSFileSize,
            (st.mode & S_IFMT) == S_IFDIR ? NSFileTypeDirectory : NSFileTypeRegular, NSFileType,
            [NSDate dateWithTimeIntervalSince1970:(double)st.mtime + st.mtime_ns / 1e9], NSFileModificationDate, nil];
}
- (BOOL)createFileAtPath:(NSString *)p contents:(NSData *)d attributes:(NSDictionary *)a { return [d ? d : [NSData data] writeToFile:p atomically:YES]; }
- (NSData *)contentsAtPath:(NSString *)p { return [NSData dataWithContentsOfFile:p]; }
- (NSString *)currentDirectoryPath { char b[4096]; return getcwd(b, sizeof b) ? [NSString stringWithUTF8String:b] : nil; }
- (BOOL)changeCurrentDirectoryPath:(NSString *)p { return chdir([p fileSystemRepresentation]) == 0; }
- (NSString *)stringWithFileSystemRepresentation:(const char *)s length:(NSUInteger)n { return [[[NSString alloc] initWithBytes:s length:n encoding:NSUTF8StringEncoding] autorelease]; }
@end

/* ================================================================ NSThread */
@implementation NSThread { NSString *_name; NSMutableDictionary *_dict; id _target; SEL _sel; id _arg; void (^_block)(void); }
static NSThread *thread_obj(void) {
    NSThread *t = pthread_getspecific(thread_key);
    if (!t) { t = [[NSThread alloc] init]; pthread_setspecific(thread_key, t); }
    return t;
}
static void *thread_start(void *p) {
    NSThread *t = p; pthread_setspecific(thread_key, t);
    void *pool = objc_autoreleasePoolPush();
    if (t->_block) t->_block(); else ((id (*)(id, SEL, id))objc_msgSend)(t->_target, t->_sel, t->_arg);
    objc_autoreleasePoolPop(pool);
    return 0;
}
static void spawn(NSThread *t) { void *th; pthread_create(&th, 0, thread_start, t); pthread_detach(th); }
+ (NSThread *)currentThread { return thread_obj(); }
+ (NSThread *)mainThread { return main_thread; }
+ (BOOL)isMainThread { return thread_obj() == main_thread; }
- (BOOL)isMainThread { return self == main_thread; }
+ (BOOL)isMultiThreaded { return YES; }
+ (void)sleepForTimeInterval:(NSTimeInterval)t { if (t > 0) usleep((unsigned)(t * 1e6)); }
+ (void)sleepUntilDate:(NSDate *)d { [self sleepForTimeInterval:[d timeIntervalSinceNow]]; }
+ (void)detachNewThreadWithBlock:(void (^)(void))b { NSThread *t = [[NSThread alloc] init]; t->_block = _Block_copy(b); spawn(t); }
+ (void)detachNewThreadSelector:(SEL)s toTarget:(id)tg withObject:(id)o { NSThread *t = [[NSThread alloc] init]; t->_target = [tg retain]; t->_sel = s; t->_arg = [o retain]; spawn(t); }
- (NSString *)name { return _name ? _name : @""; }
- (void)setName:(NSString *)n { [_name release]; _name = [n copy]; }
- (NSMutableDictionary *)threadDictionary { if (!_dict) _dict = [[NSMutableDictionary alloc] init]; return _dict; }
@end

/* ================================================================ locks */
@implementation NSLock { pthread_mutex_t _m; NSString *_name; }
- (void)lock { pthread_mutex_lock(&_m); }
- (void)unlock { pthread_mutex_unlock(&_m); }
- (BOOL)tryLock { return pthread_mutex_trylock(&_m) == 0; }
- (void)setName:(NSString *)n { [_name release]; _name = [n copy]; }
- (NSString *)name { return _name; }
@end
@implementation NSRecursiveLock { pthread_mutex_t _m; void *_owner; NSUInteger _depth; }
- (void)lock { void *me = pthread_self(); if (_owner == me) { _depth++; return; } pthread_mutex_lock(&_m); _owner = me; _depth = 1; }
- (void)unlock { if (--_depth == 0) { _owner = 0; pthread_mutex_unlock(&_m); } }
- (BOOL)tryLock { void *me = pthread_self(); if (_owner == me) { _depth++; return YES; } if (pthread_mutex_trylock(&_m)) return NO; _owner = me; _depth = 1; return YES; }
@end
@implementation NSCondition { pthread_mutex_t _m; pthread_cond_t _c; }
- (void)lock { pthread_mutex_lock(&_m); }
- (void)unlock { pthread_mutex_unlock(&_m); }
- (void)wait { pthread_cond_wait(&_c, &_m); }
- (BOOL)waitUntilDate:(NSDate *)d {
    NSTimeInterval t = [d timeIntervalSinceNow]; if (t < 0) t = 0;
    struct timespec ts = {(int64_t)t, (int64_t)((t - (int64_t)t) * 1e9)};
    return pthread_cond_timedwait_relative_np(&_c, &_m, &ts) == 0;
}
- (void)signal { pthread_cond_signal(&_c); }
- (void)broadcast { pthread_cond_broadcast(&_c); }
@end

/* ================================================================ NSAutoreleasePool */
@implementation NSAutoreleasePool { void *_tok; }
+ (id)allocWithZone:(NSZone *)z { NSAutoreleasePool *p = class_createInstance(self, 0); p->_tok = objc_autoreleasePoolPush(); return p; }
+ (void)addObject:(id)o { [o autorelease]; }
- (void)drain { void *t = _tok; object_dispose(self); objc_autoreleasePoolPop(t); }
- (oneway void)release { [self drain]; }
- (id)retain { mw_raise("NSInvalidArgumentException", "*** -[NSAutoreleasePool retain]: Cannot retain an autorelease pool"); }
- (id)autorelease { mw_raise("NSInvalidArgumentException", "*** -[NSAutoreleasePool autorelease]: Cannot autorelease an autorelease pool"); }
@end


/* ================================================================ CoreFoundation basics (toll-free: CF objects are ObjC objects) */
CFTypeRef CFRetain(CFTypeRef o) { return o ? (CFTypeRef)[(id)o retain] : o; }
void CFRelease(CFTypeRef o) { if (o) [(id)o release]; } /* NULL-tolerant: Go's x509 path releases our stubbed NULLs */
CFAbsoluteTime CFAbsoluteTimeGetCurrent(void) { return now_ref(); }
NSUInteger CFGetRetainCount(CFTypeRef o) { return [(id)o retainCount]; }
Boolean CFEqual(CFTypeRef a, CFTypeRef b) { return a == b || [(id)a isEqual:(id)b]; }
NSUInteger CFHash(CFTypeRef o) { return [(id)o hash]; }
CFStringRef CFCopyDescription(CFTypeRef o) { return (CFStringRef)[[(id)o description] retain]; }

/* ================================================================ load hook (called from __NSCFConstantString +load) */
id __NSArray0__, __NSDictionary0__; /* clang's empty @[] / @{} literals load these */
void mw_foundation_load(void) {
    static int done; if (done) return; done = 1;
    _scion_describe_object = describe;
    objc_setUncaughtExceptionHandler(foundation_uncaught);
    { extern void mw_runloop_setup(void); mw_runloop_setup(); }
    __NSArray0__ = [[NSArray alloc] init]; __NSDictionary0__ = [[NSDictionary alloc] init];
    { extern void mw_cf_booleans(void); mw_cf_booleans(); }
    pthread_key_create(&thread_key, 0);
    main_thread = [thread_obj() retain];
    [main_thread setName:@"main"];
}

/* a CFURLRef is an NSURL */
CFURLRef CFURLCreateFromFileSystemRepresentation(CFAllocatorRef a, const unsigned char *buffer, CFIndex length, unsigned char isDirectory) {
    NSString *path = [[[NSString alloc] initWithBytes:buffer length:(NSUInteger)length encoding:NSUTF8StringEncoding] autorelease];
    return path ? (CFURLRef)[[NSURL fileURLWithPath:path isDirectory:isDirectory] retain] : NULL;
}
