/* coder.m — keyed archives: NSKeyedUnarchiver reads binary/XML keyed archives ($archiver/$objects/$top) and compiled nibs
 * (the NIBArchive format Xcode writes), NSKeyedArchiver writes binary keyed archives, and the NSCoding of Foundation's
 * own classes. Both readers turn the file into the same table of objects (class name + keyed values) that decoding walks.
 * Formats: Apple's NSKeyedArchiver documentation and the public descriptions of NIBArchive. Input is untrusted. */
#include "internal.h"

NSString *const NSInvalidArchiveOperationException = @"NSInvalidArchiveOperationException";
NSString *const NSInvalidUnarchiveOperationException = @"NSInvalidUnarchiveOperationException";
NSString *const NSKeyedArchiveRootObjectKey = @"root";

/* ======================================================================= NSCoder: the parts every coder shares */
@implementation NSCoder
- (BOOL)allowsKeyedCoding { return NO; }
- (BOOL)requiresSecureCoding { return NO; }
- (NSInteger)versionForClassName:(NSString *)n { return 0; }
- (id)decodeObject { return nil; }
- (id)decodeObjectForKey:(NSString *)k { return nil; }
- (id)decodeObjectOfClass:(Class)c forKey:(NSString *)k { return [self decodeObjectForKey:k]; }
- (id)decodeObjectOfClasses:(NSSet *)c forKey:(NSString *)k { return [self decodeObjectForKey:k]; }
- (id)decodeArrayOfObjectsOfClass:(Class)c forKey:(NSString *)k { return [self decodeObjectForKey:k]; }
- (id)decodeArrayOfObjectsOfClasses:(NSSet *)c forKey:(NSString *)k { return [self decodeObjectForKey:k]; }
- (id)decodeDictionaryWithKeysOfClass:(Class)a objectsOfClass:(Class)b forKey:(NSString *)k { return [self decodeObjectForKey:k]; }
- (id)decodeTopLevelObjectForKey:(NSString *)k error:(NSError **)e { return [self decodeObjectForKey:k]; }
- (id)decodeTopLevelObjectAndReturnError:(NSError **)e { return [self decodeTopLevelObjectForKey:NSKeyedArchiveRootObjectKey error:e]; }
- (id)decodeTopLevelObjectOfClass:(Class)c forKey:(NSString *)k error:(NSError **)e { return [self decodeTopLevelObjectForKey:k error:e]; }
- (id)decodeTopLevelObjectOfClasses:(NSSet *)c forKey:(NSString *)k error:(NSError **)e { return [self decodeTopLevelObjectForKey:k error:e]; }
- (BOOL)containsValueForKey:(NSString *)k { return NO; }
- (int64_t)decodeInt64ForKey:(NSString *)k { return 0; }
- (double)decodeDoubleForKey:(NSString *)k { return 0; }
- (BOOL)decodeBoolForKey:(NSString *)k { return [self decodeInt64ForKey:k] != 0; }
- (NSInteger)decodeIntegerForKey:(NSString *)k { return (NSInteger)[self decodeInt64ForKey:k]; }
- (int)decodeIntForKey:(NSString *)k { return (int)[self decodeInt64ForKey:k]; }
- (int32_t)decodeInt32ForKey:(NSString *)k { return (int32_t)[self decodeInt64ForKey:k]; }
- (float)decodeFloatForKey:(NSString *)k { return (float)[self decodeDoubleForKey:k]; }
- (const uint8_t *)decodeBytesForKey:(NSString *)k returnedLength:(NSUInteger *)n { if (n) *n = 0; return NULL; }
- (NSPoint)decodePointForKey:(NSString *)k { id s = [self decodeObjectForKey:k]; return [s isKindOfClass:[NSString class]] ? NSPointFromString(s) : NSMakePoint(0, 0); }
- (NSSize)decodeSizeForKey:(NSString *)k { id s = [self decodeObjectForKey:k]; return [s isKindOfClass:[NSString class]] ? NSSizeFromString(s) : NSMakeSize(0, 0); }
- (NSRect)decodeRectForKey:(NSString *)k { id s = [self decodeObjectForKey:k]; return [s isKindOfClass:[NSString class]] ? NSRectFromString(s) : NSMakeRect(0, 0, 0, 0); }
- (void)encodeObject:(id)o {}
- (void)encodeRootObject:(id)o { [self encodeObject:o]; }
- (void)encodeObject:(id)o forKey:(NSString *)k {}
- (void)encodeConditionalObject:(id)o forKey:(NSString *)k { [self encodeObject:o forKey:k]; }
- (void)encodeBool:(BOOL)v forKey:(NSString *)k { [self encodeInt64:v forKey:k]; }
- (void)encodeInt:(int)v forKey:(NSString *)k { [self encodeInt64:v forKey:k]; }
- (void)encodeInt32:(int32_t)v forKey:(NSString *)k { [self encodeInt64:v forKey:k]; }
- (void)encodeInteger:(NSInteger)v forKey:(NSString *)k { [self encodeInt64:v forKey:k]; }
- (void)encodeInt64:(int64_t)v forKey:(NSString *)k {}
- (void)encodeFloat:(float)v forKey:(NSString *)k { [self encodeDouble:v forKey:k]; }
- (void)encodeDouble:(double)v forKey:(NSString *)k {}
- (void)encodeBytes:(const uint8_t *)b length:(NSUInteger)n forKey:(NSString *)k {}
- (void)encodePoint:(NSPoint)p forKey:(NSString *)k { [self encodeObject:NSStringFromPoint(p) forKey:k]; }
- (void)encodeSize:(NSSize)s forKey:(NSString *)k { [self encodeObject:NSStringFromSize(s) forKey:k]; }
- (void)encodeRect:(NSRect)r forKey:(NSString *)k { [self encodeObject:NSStringFromRect(r) forKey:k]; }
- (void)failWithError:(NSError *)e {}
- (NSError *)error { return nil; }
- (NSDecodingFailurePolicy)decodingFailurePolicy { return 0; }
@end

/* ======================================================================= the decoded table */
enum { V_NIL, V_INT, V_REAL, V_BYTES, V_OBJ, V_LIT };
typedef struct { NSString *key; int type; long long i; double d; NSData *bytes; NSUInteger ref; id lit; } mwval;
typedef struct { NSString *cls; mwval *v; NSUInteger nv; id inst; int state; id literal; } mwobj; /* state: 0 new, 1 decoding, 2 done */

static NSMutableDictionary *class_map; /* +setClass:forClassName: */

@implementation NSKeyedUnarchiver {
    mwobj *_o; NSUInteger _n;
    NSUInteger *_stack; NSUInteger _depth, _cap;
    NSUInteger _top;          /* the object $top/"root" lives in (keyed archives: a pseudo object for $top) */
    NSMutableDictionary *_classes;
    id _delegate; BOOL _secure; NSError *_error;
    NSMutableArray *_decoded; /* every object made, kept alive with the unarchiver */
}
- (BOOL)allowsKeyedCoding { return YES; }
- (BOOL)requiresSecureCoding { return _secure; }
- (void)setRequiresSecureCoding:(BOOL)s { _secure = s; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (NSDecodingFailurePolicy)decodingFailurePolicy { return 1; }
- (void)setDecodingFailurePolicy:(NSDecodingFailurePolicy)p {}
- (NSError *)error { return _error; }
- (void)failWithError:(NSError *)e { if (!_error) _error = [e retain]; }
- (void)dealloc {
    for (NSUInteger i = 0; i < _n; i++) {
        for (NSUInteger j = 0; j < _o[i].nv; j++) { [_o[i].v[j].key release]; [_o[i].v[j].bytes release]; [_o[i].v[j].lit release]; }
        free(_o[i].v); [_o[i].cls release]; [_o[i].literal release];
    }
    free(_o); free(_stack); [_classes release]; [_error release]; [_decoded release];
    [super dealloc];
}
static void add_val(mwobj *o, mwval v) { o->v = realloc(o->v, (o->nv + 1) * sizeof *o->v); o->v[o->nv++] = v; }

/* binary or XML keyed archive: $objects holds literals (strings, numbers, data) and dictionaries with a $class */
- (BOOL)_loadKeyedArchive:(NSData *)data {
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:0 error:0];
    if (![plist isKindOfClass:[NSDictionary class]]) return NO;
    NSArray *objs = plist[@"$objects"]; NSDictionary *top = plist[@"$top"];
    if (![objs isKindOfClass:[NSArray class]] || ![top isKindOfClass:[NSDictionary class]]) return NO;
    _n = [objs count] + 1; _o = calloc(_n, sizeof *_o);
    NSUInteger (^uid)(id) = ^NSUInteger(id v) {
        return [v isKindOfClass:[NSDictionary class]] && [v count] == 1 && [v[@"CF$UID"] isKindOfClass:[NSNumber class]] ? [v[@"CF$UID"] unsignedIntegerValue] : NSNotFound;
    };
    for (NSUInteger i = 0; i < _n - 1; i++) {
        id e = objs[i]; mwobj *o = &_o[i];
        if (![e isKindOfClass:[NSDictionary class]] || !e[@"$class"]) { /* a literal, or "$null" at index 0 */
            o->literal = [e isKindOfClass:[NSString class]] && [e isEqualToString:@"$null"] && i == 0 ? nil : [e retain];
            o->state = 2; continue;
        }
        NSUInteger ci = uid(e[@"$class"]);
        NSDictionary *cd = ci < [objs count] ? objs[ci] : nil;
        o->cls = [cd isKindOfClass:[NSDictionary class]] && [cd[@"$classname"] isKindOfClass:[NSString class]] ? [cd[@"$classname"] copy] : [@"NSObject" copy];
        for (NSString *k in e) {
            if ([k isEqualToString:@"$class"]) continue;
            id v = e[k]; mwval mv = {[k copy]};
            NSUInteger r = uid(v);
            if (r != NSNotFound) { mv.type = V_OBJ; mv.ref = r; }
            else if ([v isKindOfClass:[NSNumber class]]) { if (mw_number_is_real(v)) { mv.type = V_REAL; mv.d = [v doubleValue]; } else { mv.type = V_INT; mv.i = [v longLongValue]; mv.d = (double)mv.i; } }
            else if ([v isKindOfClass:[NSData class]]) { mv.type = V_BYTES; mv.bytes = [v retain]; }
            else if ([v isKindOfClass:[NSArray class]]) { /* arrays of UIDs (NS.objects, NS.keys) */
                NSMutableArray *refs = [NSMutableArray array]; for (id x in v) { NSUInteger rr = uid(x); [refs addObject:[NSNumber numberWithUnsignedInteger:rr]]; }
                mv.type = V_LIT; mv.lit = [refs retain];
            } else { mv.type = V_LIT; mv.lit = [v retain]; }
            add_val(o, mv);
        }
    }
    /* $top as a pseudo object at the end */
    _top = _n - 1; mwobj *t = &_o[_top]; t->cls = [@"$top" copy]; t->state = 2;
    for (NSString *k in top) { NSUInteger r = uid(top[k]); if (r != NSNotFound) { mwval mv = {[k copy], V_OBJ}; mv.ref = r; add_val(t, mv); } }
    return YES;
}
/* NIBArchive: header, then objects (class, first value, value count), keys, values and class names, all varint-indexed */
static BOOL varint(const uint8_t *b, NSUInteger n, NSUInteger *p, NSUInteger *out) {
    NSUInteger v = 0; int s = 0;
    while (*p < n && s < 63) { uint8_t c = b[(*p)++]; v |= (NSUInteger)(c & 0x7f) << s; s += 7; if (c & 0x80) { *out = v; return YES; } }
    return NO;
}
- (BOOL)_loadNibArchive:(NSData *)data {
    const uint8_t *b = [data bytes]; NSUInteger n = [data length];
    if (n < 50 || memcmp(b, "NIBArchive", 10)) return NO;
    uint32_t h[10]; memcpy(h, b + 10, 40);
    NSUInteger nobj = h[2], oobj = h[3], nkey = h[4], okey = h[5], nval = h[6], oval = h[7], ncls = h[8], ocls = h[9];
    if (nobj > n || nkey > n || nval > n || ncls > n || oobj > n || okey > n || oval > n || ocls > n) return NO;
    NSMutableArray *keys = [NSMutableArray array], *classes = [NSMutableArray array];
    NSUInteger p = okey, len, extra;
    for (NSUInteger i = 0; i < nkey; i++) {
        if (!varint(b, n, &p, &len) || p + len > n) return NO;
        NSString *k = [[[NSString alloc] initWithBytes:b + p length:len encoding:NSUTF8StringEncoding] autorelease]; [keys addObject:k ? k : @""]; p += len;
    }
    p = ocls;
    for (NSUInteger i = 0; i < ncls; i++) {
        if (!varint(b, n, &p, &len) || !varint(b, n, &p, &extra) || p + extra * 4 + len > n) return NO;
        p += extra * 4;
        NSUInteger l = len; while (l && !b[p + l - 1]) l--;
        NSString *c = [[[NSString alloc] initWithBytes:b + p length:l encoding:NSUTF8StringEncoding] autorelease]; [classes addObject:c ? c : @"NSObject"]; p += len;
    }
    mwval *vals = calloc(nval ? nval : 1, sizeof *vals);
    p = oval;
    for (NSUInteger i = 0; i < nval; i++) {
        NSUInteger ki; if (!varint(b, n, &p, &ki) || ki >= nkey || p >= n) { free(vals); return NO; }
        mwval *v = &vals[i]; v->key = keys[ki]; uint8_t t = b[p++];
        #define NEED(k) if (p + (k) > n) { free(vals); return NO; }
        switch (t) {
        case 0: NEED(1); v->type = V_INT; v->i = (int8_t)b[p]; p += 1; break;
        case 1: { NEED(2); int16_t x; memcpy(&x, b + p, 2); v->type = V_INT; v->i = x; p += 2; break; }
        case 2: { NEED(4); int32_t x; memcpy(&x, b + p, 4); v->type = V_INT; v->i = x; p += 4; break; }
        case 3: { NEED(8); int64_t x; memcpy(&x, b + p, 8); v->type = V_INT; v->i = x; p += 8; break; }
        case 4: v->type = V_INT; v->i = 1; break;
        case 5: v->type = V_INT; v->i = 0; break;
        case 6: { NEED(4); float x; memcpy(&x, b + p, 4); v->type = V_REAL; v->d = x; p += 4; break; }
        case 7: { NEED(8); double x; memcpy(&x, b + p, 8); v->type = V_REAL; v->d = x; p += 8; break; }
        case 8: { NSUInteger l; if (!varint(b, n, &p, &l)) { free(vals); return NO; } NEED(l); v->type = V_BYTES; v->bytes = [NSData dataWithBytes:b + p length:l]; p += l; break; }
        case 9: v->type = V_NIL; break;
        case 10: { NEED(4); uint32_t x; memcpy(&x, b + p, 4); v->type = V_OBJ; v->ref = x; p += 4; break; }
        default: free(vals); return NO;
        }
        if (v->type == V_INT) v->d = (double)v->i; else if (v->type == V_REAL) v->i = (long long)v->d;
    }
    _n = nobj; _o = calloc(_n ? _n : 1, sizeof *_o);
    p = oobj;
    for (NSUInteger i = 0; i < nobj; i++) {
        NSUInteger ci, vi, vc;
        if (!varint(b, n, &p, &ci) || !varint(b, n, &p, &vi) || !varint(b, n, &p, &vc) || ci >= ncls || vi + vc > nval) { free(vals); return NO; }
        _o[i].cls = [classes[ci] copy];
        for (NSUInteger j = 0; j < vc; j++) { mwval v = vals[vi + j]; [v.key retain]; [v.bytes retain]; add_val(&_o[i], v); }
    }
    free(vals);
    _top = 0;
    return YES;
}
- (instancetype)_init {
    _decoded = [[NSMutableArray alloc] init]; _classes = [[NSMutableDictionary alloc] init];
    _cap = 64; _stack = malloc(_cap * sizeof *_stack);
    return self;
}
- (instancetype)initForReadingFromData:(NSData *)d error:(NSError **)e {
    [self _init];
    if (!d || !([self _loadKeyedArchive:d] || [self _loadNibArchive:d])) {
        if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:4864 userInfo:@{NSDebugDescriptionErrorKey: @"*** incomprehensible archive"}];
        [self release]; return nil;
    }
    _stack[_depth++] = _top;
    return self;
}
- (instancetype)initForReadingWithData:(NSData *)d { return [self initForReadingFromData:d error:0]; }
- (instancetype)initForReadingFromData:(NSData *)d { return [self initForReadingFromData:d error:0]; }
- (void)finishDecoding {}
- (void)setClass:(Class)c forClassName:(NSString *)n { if (c) _classes[n] = c; else [_classes removeObjectForKey:n]; }
- (Class)classForClassName:(NSString *)n { return _classes[n]; }
+ (void)setClass:(Class)c forClassName:(NSString *)n {
    @synchronized(self) { if (!class_map) class_map = [[NSMutableDictionary alloc] init]; if (c) class_map[n] = c; else [class_map removeObjectForKey:n]; }
}
+ (Class)classForClassName:(NSString *)n { @synchronized(self) { return class_map[n]; } }

static mwval *find(mwobj *o, NSString *k) {
    for (NSUInteger i = 0; i < o->nv; i++) if ([o->v[i].key isEqualToString:k]) return &o->v[i];
    return NULL;
}
- (mwval *)_val:(NSString *)k { return _depth ? find(&_o[_stack[_depth - 1]], k) : NULL; }
- (BOOL)containsValueForKey:(NSString *)k { return [self _val:k] != NULL; }
- (int64_t)decodeInt64ForKey:(NSString *)k {
    mwval *v = [self _val:k]; if (!v) return 0;
    if (v->type == V_INT || v->type == V_REAL) return v->i;
    if (v->type == V_OBJ) { id o = [self _object:v->ref]; return [o respondsToSelector:@selector(longLongValue)] ? [o longLongValue] : 0; }
    return 0;
}
- (double)decodeDoubleForKey:(NSString *)k {
    mwval *v = [self _val:k]; if (!v) return 0;
    if (v->type == V_INT || v->type == V_REAL) return v->d;
    if (v->type == V_OBJ) { id o = [self _object:v->ref]; return [o respondsToSelector:@selector(doubleValue)] ? [o doubleValue] : 0; }
    return 0;
}
- (const uint8_t *)decodeBytesForKey:(NSString *)k returnedLength:(NSUInteger *)n {
    mwval *v = [self _val:k]; NSData *d = v && v->type == V_BYTES ? v->bytes : v && v->type == V_OBJ ? [self _object:v->ref] : nil;
    if (![d isKindOfClass:[NSData class]]) { if (n) *n = 0; return NULL; }
    if (n) *n = [d length];
    return [d bytes];
}
- (id)decodeObjectForKey:(NSString *)k {
    mwval *v = [self _val:k]; if (!v) return nil;
    if (v->type == V_OBJ) return [self _object:v->ref];
    if (v->type == V_BYTES) return v->bytes;
    if (v->type == V_LIT && [v->lit isKindOfClass:[NSArray class]]) { /* NS.objects in keyed archives: an array of references */
        NSMutableArray *a = [NSMutableArray array]; for (NSNumber *r in v->lit) { id o = [self _object:[r unsignedIntegerValue]]; [a addObject:o ? o : [NSNull null]]; } return a;
    }
    if (v->type == V_LIT) return v->lit;
    if (v->type == V_INT || v->type == V_REAL) return v->type == V_INT ? [NSNumber numberWithLongLong:v->i] : [NSNumber numberWithDouble:v->d];
    return nil;
}
/* the values of an object that are a list (nibs: repeated UINibEncoderEmptyKey; keyed archives: NS.objects) */
- (NSArray *)_listOf:(NSUInteger)ref key:(NSString *)key {
    mwobj *o = &_o[ref]; NSMutableArray *a = [NSMutableArray array];
    for (NSUInteger i = 0; i < o->nv; i++) {
        mwval *v = &o->v[i];
        if (![v->key isEqualToString:key]) continue;
        if (v->type == V_OBJ) { id x = [self _object:v->ref]; [a addObject:x ? x : [NSNull null]]; }
        else if (v->type == V_LIT && [v->lit isKindOfClass:[NSArray class]]) for (NSNumber *r in v->lit) { id x = [self _object:[r unsignedIntegerValue]]; [a addObject:x ? x : [NSNull null]]; }
    }
    return a;
}
- (Class)_classNamed:(NSString *)name {
    Class c = _classes[name]; if (!c) c = [NSKeyedUnarchiver classForClassName:name];
    if (!c && [_delegate respondsToSelector:@selector(unarchiver:cannotDecodeObjectOfClassName:originalClasses:)])
        c = [_delegate unarchiver:self cannotDecodeObjectOfClassName:name originalClasses:@[name]];
    if (!c) c = NSClassFromString(name);
    return c;
}
/* Foundation's own classes are rebuilt here; anything else gets alloc + initWithCoder: */
- (id)_object:(NSUInteger)ref {
    if (ref >= _n) return nil;
    mwobj *o = &_o[ref];
    if (o->state == 2) return o->literal ? o->literal : o->inst;
    if (o->state == 1) return o->inst; /* a cycle: the object being decoded */
    o->state = 1;
    if (_depth == _cap) _stack = realloc(_stack, (_cap *= 2) * sizeof *_stack);
    _stack[_depth++] = ref;
    NSString *cn = o->cls; id result = nil;
    BOOL mutableKind = [cn hasPrefix:@"NSMutable"];
    if ([cn isEqualToString:@"NSString"] || [cn isEqualToString:@"NSMutableString"] || [cn isEqualToString:@"NSLocalizableString"]) {
        NSUInteger len; const uint8_t *b = [self decodeBytesForKey:@"NS.bytes" returnedLength:&len];
        NSString *s = b ? [[[NSString alloc] initWithBytes:b length:len encoding:NSUTF8StringEncoding] autorelease] : [self decodeObjectForKey:@"NS.string"];
        if (!s) s = @"";
        result = mutableKind ? [[s mutableCopy] autorelease] : s;
    } else if ([cn isEqualToString:@"NSNumber"]) {
        mwval *v;
        if ((v = [self _val:@"NS.intval"]) || (v = [self _val:@"NS.boolval"])) result = [v->key isEqualToString:@"NS.boolval"] ? [NSNumber numberWithBool:v->i != 0] : [NSNumber numberWithLongLong:v->i];
        else if ((v = [self _val:@"NS.dblval"])) result = [NSNumber numberWithDouble:v->d];
        else result = [NSNumber numberWithInt:0];
    } else if ([cn isEqualToString:@"NSArray"] || [cn isEqualToString:@"NSMutableArray"] || [cn isEqualToString:@"NSSet"] || [cn isEqualToString:@"NSMutableSet"]
               || [cn isEqualToString:@"NSOrderedSet"] || [cn isEqualToString:@"NSMutableOrderedSet"]) {
        NSArray *items = [self containsValueForKey:@"NS.objects"] ? [self _listOf:ref key:@"NS.objects"] : [self _listOf:ref key:@"UINibEncoderEmptyKey"];
        BOOL set = [cn hasSuffix:@"Set"] && ![cn hasSuffix:@"OrderedSet"], ordered = [cn hasSuffix:@"OrderedSet"];
        if (set) result = mutableKind ? [NSMutableSet setWithArray:items] : [NSSet setWithArray:items];
        else if (ordered) result = mutableKind ? [NSMutableOrderedSet orderedSetWithArray:items] : [NSOrderedSet orderedSetWithArray:items];
        else result = mutableKind ? [NSMutableArray arrayWithArray:items] : [NSArray arrayWithArray:items];
    } else if ([cn isEqualToString:@"NSDictionary"] || [cn isEqualToString:@"NSMutableDictionary"]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        if ([self containsValueForKey:@"NS.keys"]) {
            NSArray *ks = [self _listOf:ref key:@"NS.keys"], *vs = [self _listOf:ref key:@"NS.objects"];
            for (NSUInteger i = 0; i < [ks count] && i < [vs count]; i++) d[ks[i]] = vs[i];
        } else { /* nibs: keys and values alternate */
            NSArray *kv = [self _listOf:ref key:@"UINibEncoderEmptyKey"];
            for (NSUInteger i = 0; i + 1 < [kv count]; i += 2) d[kv[i]] = kv[i + 1];
        }
        result = mutableKind ? d : [NSDictionary dictionaryWithDictionary:d];
    } else if ([cn isEqualToString:@"NSData"] || [cn isEqualToString:@"NSMutableData"]) {
        NSUInteger len; const uint8_t *b = [self decodeBytesForKey:@"NS.bytes" returnedLength:&len];
        id d = [self decodeObjectForKey:@"NS.data"];
        NSData *data = b ? [NSData dataWithBytes:b length:len] : [d isKindOfClass:[NSData class]] ? d : [NSData data];
        result = mutableKind ? [[data mutableCopy] autorelease] : data;
    } else if ([cn isEqualToString:@"NSDate"]) {
        result = [NSDate dateWithTimeIntervalSinceReferenceDate:[self decodeDoubleForKey:@"NS.time"]];
    } else if ([cn isEqualToString:@"NSURL"]) {
        id base = [self decodeObjectForKey:@"NS.base"], rel = [self decodeObjectForKey:@"NS.relative"];
        result = [rel isKindOfClass:[NSString class]] ? [NSURL URLWithString:rel relativeToURL:[base isKindOfClass:[NSURL class]] ? base : nil] : nil;
    } else if ([cn isEqualToString:@"NSUUID"]) {
        NSUInteger len; const uint8_t *b = [self decodeBytesForKey:@"NS.uuidbytes" returnedLength:&len];
        result = b && len == 16 ? [[[NSUUID alloc] initWithUUIDBytes:b] autorelease] : nil;
    } else if ([cn isEqualToString:@"NSNull"]) {
        result = [NSNull null];
    } else {
        Class c = [self _classNamed:cn];
        if (!c) {
            if (_depth) _depth--; o->state = 2;
            [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:4864 userInfo:@{NSDebugDescriptionErrorKey: [NSString stringWithFormat:@"cannot decode object of class (%@)", cn]}]];
            return nil;
        }
        id inst = [c alloc];
        o->inst = inst;
        id r = [inst respondsToSelector:@selector(initWithCoder:)] ? [inst initWithCoder:self] : [inst init];
        if (r && [r respondsToSelector:@selector(awakeAfterUsingCoder:)]) { id a = [r awakeAfterUsingCoder:self]; if (a != r) { [a retain]; [r release]; r = a; } }
        if (r && [_delegate respondsToSelector:@selector(unarchiver:didDecodeObject:)]) { id a = [_delegate unarchiver:self didDecodeObject:r]; if (a != r) { [a retain]; [r release]; r = a; } }
        if (r) { [_decoded addObject:r]; [r release]; }
        result = r;
    }
    _depth--;
    o->state = 2;
    if (result && !o->inst) { o->inst = result; [_decoded addObject:result]; }
    else o->inst = result;
    return result;
}
- (id)decodeTopLevelObjectForKey:(NSString *)k error:(NSError **)e {
    id o = [self decodeObjectForKey:k];
    if (!o && _error && e) *e = _error;
    return o;
}
/* nibs: the File's Owner placeholder (NSIBObjectData's NSRoot) decodes to the owner given to the nib */
- (void)_mwSetNibOwner:(id)owner {
    mwval *v = _n ? find(&_o[_top], @"IB.objectdata") : NULL;   /* keyed-archive nibs keep it in $top, NIBArchive in object 0 */ if (!v || v->type != V_OBJ || v->ref >= _n) return;
    mwval *r = find(&_o[v->ref], @"NSRoot"); if (!r || r->type != V_OBJ || r->ref >= _n) return;
    _o[r->ref].inst = owner; _o[r->ref].state = 2;
}
- (id)decodeObject { return nil; }

+ (id)unarchivedObjectOfClass:(Class)c fromData:(NSData *)d error:(NSError **)e { return [self unarchivedObjectOfClasses:[NSSet setWithObject:c] fromData:d error:e]; }
+ (id)unarchivedObjectOfClasses:(NSSet *)cs fromData:(NSData *)d error:(NSError **)e {
    NSKeyedUnarchiver *u = [[[self alloc] initForReadingFromData:d error:e] autorelease];
    id o = [u decodeTopLevelObjectForKey:NSKeyedArchiveRootObjectKey error:e];
    if (o && cs) { BOOL ok = NO; for (Class c in cs) ok |= [o isKindOfClass:c]; if (!ok) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:4864 userInfo:nil]; return nil; } }
    return [[o retain] autorelease];
}
+ (id)unarchivedArrayOfObjectsOfClass:(Class)c fromData:(NSData *)d error:(NSError **)e { return [self unarchivedObjectOfClasses:nil fromData:d error:e]; }
+ (id)unarchivedDictionaryWithKeysOfClass:(Class)k objectsOfClass:(Class)c fromData:(NSData *)d error:(NSError **)e { return [self unarchivedObjectOfClasses:nil fromData:d error:e]; }
+ (id)unarchiveObjectWithData:(NSData *)d { return [self unarchivedObjectOfClasses:nil fromData:d error:0]; }
+ (id)unarchiveTopLevelObjectWithData:(NSData *)d error:(NSError **)e { return [self unarchivedObjectOfClasses:nil fromData:d error:e]; }
+ (id)unarchiveObjectWithFile:(NSString *)p { NSData *d = [NSData dataWithContentsOfFile:p]; return d ? [self unarchiveObjectWithData:d] : nil; }
@end

/* ======================================================================= NSKeyedArchiver: binary keyed archives */
static NSMutableDictionary *archiver_class_names;
@implementation NSKeyedArchiver {
    NSMutableArray *_objects;           /* $objects */
    NSMapTable *_uids;                  /* object -> uid */
    NSMutableDictionary *_classUids;    /* class name -> uid of its $class dictionary */
    NSMutableArray *_stack;             /* the dictionaries being filled */
    NSMutableDictionary *_top;
    NSData *_data; BOOL _secure, _finished; NSPropertyListFormat _fmt; id _delegate;
    NSMutableDictionary *_names;
}
- (instancetype)initRequiringSecureCoding:(BOOL)s {
    _objects = [[NSMutableArray alloc] initWithObjects:@"$null", nil];
    _uids = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsObjectPointerPersonality | NSPointerFunctionsOpaqueMemory valueOptions:NSPointerFunctionsStrongMemory capacity:64];
    _classUids = [[NSMutableDictionary alloc] init]; _stack = [[NSMutableArray alloc] init]; _top = [[NSMutableDictionary alloc] init];
    _names = [[NSMutableDictionary alloc] init];
    _secure = s; _fmt = NSPropertyListBinaryFormat_v1_0;
    [_stack addObject:_top];
    return self;
}
- (instancetype)init { return [self initRequiringSecureCoding:NO]; }
- (instancetype)initForWritingWithMutableData:(NSMutableData *)d { return [self init]; } /* ponytail: the data is not filled in */
- (void)dealloc { [_objects release]; [_uids release]; [_classUids release]; [_stack release]; [_top release]; [_data release]; [_names release]; [super dealloc]; }
- (BOOL)allowsKeyedCoding { return YES; }
- (BOOL)requiresSecureCoding { return _secure; }
- (void)setRequiresSecureCoding:(BOOL)s { _secure = s; }
- (NSPropertyListFormat)outputFormat { return _fmt; }
- (void)setOutputFormat:(NSPropertyListFormat)f { _fmt = f; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (void)setClassName:(NSString *)n forClass:(Class)c { _names[NSStringFromClass(c)] = n; }
+ (void)setClassName:(NSString *)n forClass:(Class)c { @synchronized(self) { if (!archiver_class_names) archiver_class_names = [[NSMutableDictionary alloc] init]; archiver_class_names[NSStringFromClass(c)] = n; } }
static NSDictionary *uid_of(NSUInteger u) { return @{@"CF$UID": [NSNumber numberWithUnsignedInteger:u]}; }
- (NSDictionary *)_classRef:(Class)c {
    NSString *name = _names[NSStringFromClass(c)]; if (!name) @synchronized([NSKeyedArchiver class]) { name = archiver_class_names[NSStringFromClass(c)]; }
    if (!name) name = NSStringFromClass(c);
    NSNumber *u = _classUids[name];
    if (!u) {
        NSMutableArray *chain = [NSMutableArray arrayWithObject:name];
        for (Class s = class_getSuperclass(c); s; s = class_getSuperclass(s)) [chain addObject:NSStringFromClass(s)];
        u = [NSNumber numberWithUnsignedInteger:[_objects count]];
        [_objects addObject:@{@"$classname": name, @"$classes": chain}];
        _classUids[name] = u;
    }
    return uid_of([u unsignedIntegerValue]);
}
- (NSDictionary *)_encode:(id)o {
    if (!o) return uid_of(0);
    if ([_delegate respondsToSelector:@selector(archiver:willEncodeObject:)]) { o = [_delegate archiver:self willEncodeObject:o]; if (!o) return uid_of(0); }
    if ([o respondsToSelector:@selector(replacementObjectForKeyedArchiver:)]) { id r = [o replacementObjectForKeyedArchiver:self]; if (r) o = r; }
    NSNumber *have = [_uids objectForKey:o];
    if (have) return uid_of([have unsignedIntegerValue]);
    NSUInteger u = [_objects count];
    [_uids setObject:[NSNumber numberWithUnsignedInteger:u] forKey:o];
    /* strings, numbers and data are stored as themselves */
    if ([o isKindOfClass:[NSString class]] && ![o isKindOfClass:[NSMutableString class]]) { [_objects addObject:[[o copy] autorelease]]; return uid_of(u); }
    if ([o isKindOfClass:[NSNumber class]]) { [_objects addObject:o]; return uid_of(u); }
    if ([o isKindOfClass:[NSData class]] && ![o isKindOfClass:[NSMutableData class]]) { [_objects addObject:o]; return uid_of(u); }
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [_objects addObject:d];
    [_stack addObject:d];
    Class cls = [o respondsToSelector:@selector(classForKeyedArchiver)] ? [o classForKeyedArchiver] : [o class];
    if ([o isKindOfClass:[NSMutableString class]]) { d[@"NS.string"] = [[o copy] autorelease]; cls = [NSMutableString class]; }
    else if ([o isKindOfClass:[NSMutableData class]]) { d[@"NS.data"] = [[o copy] autorelease]; cls = [NSMutableData class]; }
    else if ([o isKindOfClass:[NSArray class]] || [o isKindOfClass:[NSSet class]] || [o isKindOfClass:[NSOrderedSet class]]) {
        NSMutableArray *refs = [NSMutableArray array];
        for (id e in [o isKindOfClass:[NSOrderedSet class]] ? [o array] : o) [refs addObject:[self _encode:e]];
        d[@"NS.objects"] = refs;
        cls = [o isKindOfClass:[NSArray class]] ? ([o isKindOfClass:[NSMutableArray class]] ? [NSMutableArray class] : [NSArray class])
            : [o isKindOfClass:[NSSet class]] ? ([o isKindOfClass:[NSMutableSet class]] ? [NSMutableSet class] : [NSSet class])
            : ([o isKindOfClass:[NSMutableOrderedSet class]] ? [NSMutableOrderedSet class] : [NSOrderedSet class]);
    } else if ([o isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *ks = [NSMutableArray array], *vs = [NSMutableArray array];
        for (id k in o) { [ks addObject:[self _encode:k]]; [vs addObject:[self _encode:[o objectForKey:k]]]; }
        d[@"NS.keys"] = ks; d[@"NS.objects"] = vs;
        cls = [o isKindOfClass:[NSMutableDictionary class]] ? [NSMutableDictionary class] : [NSDictionary class];
    } else if ([o isKindOfClass:[NSDate class]]) { d[@"NS.time"] = [NSNumber numberWithDouble:[o timeIntervalSinceReferenceDate]]; cls = [NSDate class]; }
    else if ([o isKindOfClass:[NSURL class]]) { d[@"NS.base"] = [self _encode:[o baseURL]]; d[@"NS.relative"] = [self _encode:[o relativeString]]; cls = [NSURL class]; }
    else if ([o isKindOfClass:[NSUUID class]]) { unsigned char b[16]; [o getUUIDBytes:b]; d[@"NS.uuidbytes"] = [NSData dataWithBytes:b length:16]; cls = [NSUUID class]; }
    else if ([o isKindOfClass:[NSNull class]]) cls = [NSNull class];
    else if ([o respondsToSelector:@selector(encodeWithCoder:)]) [o encodeWithCoder:self];
    else { [_stack removeLastObject]; [NSException raise:NSInvalidArchiveOperationException format:@"*** -[NSKeyedArchiver encodeObject:]: %@ does not implement encodeWithCoder:", NSStringFromClass([o class])]; }
    d[@"$class"] = [self _classRef:cls];
    [_stack removeLastObject];
    return uid_of(u);
}
- (NSMutableDictionary *)_cur { return [_stack lastObject]; }
- (void)encodeObject:(id)o forKey:(NSString *)k { [self _cur][k] = [self _encode:o]; }
- (void)encodeConditionalObject:(id)o forKey:(NSString *)k { [self encodeObject:o forKey:k]; }
- (void)encodeInt64:(int64_t)v forKey:(NSString *)k { [self _cur][k] = [NSNumber numberWithLongLong:v]; }
- (void)encodeBool:(BOOL)v forKey:(NSString *)k { [self _cur][k] = [NSNumber numberWithBool:v]; }
- (void)encodeDouble:(double)v forKey:(NSString *)k { [self _cur][k] = [NSNumber numberWithDouble:v]; }
- (void)encodeBytes:(const uint8_t *)b length:(NSUInteger)n forKey:(NSString *)k { [self _cur][k] = [NSData dataWithBytes:b length:n]; }
- (void)finishEncoding {
    if (_finished) return;
    _finished = YES;
    NSDictionary *plist = @{@"$version": [NSNumber numberWithInt:100000], @"$archiver": @"NSKeyedArchiver", @"$top": _top, @"$objects": _objects};
    _data = [[NSPropertyListSerialization dataWithPropertyList:plist format:_fmt options:0 error:0] retain];
}
- (NSData *)encodedData { [self finishEncoding]; return _data; }
+ (NSData *)archivedDataWithRootObject:(id)o requiringSecureCoding:(BOOL)s error:(NSError **)e {
    NSKeyedArchiver *a = [[[self alloc] initRequiringSecureCoding:s] autorelease];
    @try { [a encodeObject:o forKey:NSKeyedArchiveRootObjectKey]; }
    @catch (NSException *x) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:4866 userInfo:@{NSDebugDescriptionErrorKey: [x reason] ?: @""}]; return nil; }
    return [a encodedData];
}
+ (NSData *)archivedDataWithRootObject:(id)o { return [self archivedDataWithRootObject:o requiringSecureCoding:NO error:0]; }
+ (BOOL)archiveRootObject:(id)o toFile:(NSString *)p { return [[self archivedDataWithRootObject:o] writeToFile:p atomically:YES]; }
@end

/* ======================================================================= coding hooks on NSObject */
@implementation NSObject (NSKeyedArchiverObjectSubstitution)
- (Class)classForCoder { return [self class]; }
- (Class)classForKeyedArchiver { return [self classForCoder]; }
- (id)replacementObjectForCoder:(NSCoder *)c { return self; }
- (id)replacementObjectForKeyedArchiver:(NSKeyedArchiver *)a { return [self replacementObjectForCoder:a]; }
- (id)awakeAfterUsingCoder:(NSCoder *)c { return self; }
+ (NSArray *)classFallbacksForKeyedArchiver { return @[]; }
+ (Class)classForKeyedUnarchiver { return self; }
+ (NSInteger)version { return 0; }
+ (void)setVersion:(NSInteger)v {}
@end
