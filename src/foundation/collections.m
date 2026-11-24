/* collections.m — scion Foundation: NSArray, NSDictionary, NSSet, NSEnumerator, NSNull, NSValue/NSNumber, NSData. MRC. */
#import "internal.h"

static void range_check(NSUInteger i, NSUInteger n, const char *what) {
    if (i >= n) { char b[160]; snprintf(b, sizeof b, "*** %s: index %lu beyond bounds [0 .. %ld]", what, (unsigned long)i, (long)n - 1); mw_raise("NSRangeException", b); }
}

/* ================================================================ enumerators */
@interface __NSArrayEnumerator : NSEnumerator { NSArray *_a; NSUInteger _i; BOOL _rev; } - (id)initWithArray:(NSArray *)a reverse:(BOOL)r; @end
@implementation NSEnumerator
- (id)nextObject { return nil; }
- (NSArray *)allObjects { NSMutableArray *a = [NSMutableArray array]; id o; while ((o = [self nextObject])) [a addObject:o]; return a; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)b count:(NSUInteger)n {
    s->mutationsPtr = &s->extra[0];
    id o = [self nextObject]; if (!o) return 0;
    b[0] = o; s->itemsPtr = b; return 1;
}
@end
@implementation __NSArrayEnumerator
- (id)initWithArray:(NSArray *)a reverse:(BOOL)r { _a = [a retain]; _rev = r; _i = r ? [a count] : 0; return self; }
- (void)dealloc { [_a release]; [super dealloc]; }
- (id)nextObject { if (_rev) return _i ? [_a objectAtIndex:--_i] : nil; return _i < [_a count] ? [_a objectAtIndex:_i++] : nil; }
@end

/* ================================================================ NSArray (concrete, immutable) */
@implementation NSArray { @protected id *_o; NSUInteger _n, _cap; unsigned long _mut; }
+ (instancetype)array { return [[[self alloc] initWithObjects:0 count:0] autorelease]; }
+ (instancetype)arrayWithObject:(id)o { return [[[self alloc] initWithObjects:&o count:1] autorelease]; }
+ (instancetype)arrayWithObjects:(const id [])objs count:(NSUInteger)n { return [[[self alloc] initWithObjects:objs count:n] autorelease]; }
+ (instancetype)arrayWithArray:(NSArray *)a { return [[[self alloc] initWithArray:a] autorelease]; }
+ (instancetype)arrayWithObjects:(id)first, ... {
    va_list ap; va_start(ap, first); NSUInteger n = 0, cap = 8; id *v = malloc(cap * sizeof(id));
    for (id o = first; o; o = va_arg(ap, id)) { if (n == cap) v = realloc(v, (cap *= 2) * sizeof(id)); v[n++] = o; }
    va_end(ap);
    id r = [[[self alloc] initWithObjects:v count:n] autorelease]; free(v); return r;
}
- (instancetype)initWithObjects:(id)first, ... {
    va_list ap; va_start(ap, first); NSUInteger n = 0, cap = 8; id *v = malloc(cap * sizeof(id));
    for (id o = first; o; o = va_arg(ap, id)) { if (n == cap) v = realloc(v, (cap *= 2) * sizeof(id)); v[n++] = o; }
    va_end(ap);
    id r = [self initWithObjects:v count:n]; free(v); return r;
}
- (instancetype)init { return [self initWithObjects:0 count:0]; }
- (instancetype)initWithObjects:(const id [])objs count:(NSUInteger)n {
    _cap = n ? n : 4; _o = malloc(_cap * sizeof(id)); _n = n;
    for (NSUInteger i = 0; i < n; i++) {
        if (!objs[i]) { char b[96]; snprintf(b, sizeof b, "*** -[NSArray initWithObjects:count:]: attempt to insert nil object from objects[%lu]", (unsigned long)i); mw_raise("NSInvalidArgumentException", b); }
        _o[i] = [objs[i] retain];
    }
    return self;
}
- (instancetype)initWithArray:(NSArray *)a { NSUInteger n = [a count]; id *v = malloc((n + 1) * sizeof(id)); for (NSUInteger i = 0; i < n; i++) v[i] = [a objectAtIndex:i]; id r = [self initWithObjects:v count:n]; free(v); return r; }
- (instancetype)initWithArray:(NSArray *)a copyItems:(BOOL)c { return [self initWithArray:a]; }
- (void)dealloc { for (NSUInteger i = 0; i < _n; i++) [_o[i] release]; free(_o); [super dealloc]; }
- (NSUInteger)count { return _n; }
- (id)objectAtIndex:(NSUInteger)i { range_check(i, _n, "-[NSArray objectAtIndex:]"); return _o[i]; }
- (id)objectAtIndexedSubscript:(NSUInteger)i { return [self objectAtIndex:i]; }
/* everything below count and objectAtIndex: works through them: subclasses (Swift's bridged arrays) override only those */
#define N [self count]
#define AT(i) [self objectAtIndex:(i)]
- (id)firstObject { return N ? AT(0) : nil; }
- (id)lastObject { NSUInteger n = N; return n ? AT(n - 1) : nil; }
- (NSUInteger)indexOfObject:(id)o { NSUInteger n = N; for (NSUInteger i = 0; i < n; i++) { id e = AT(i); if (e == o || [e isEqual:o]) return i; } return NSNotFound; }
- (NSUInteger)indexOfObjectIdenticalTo:(id)o { NSUInteger n = N; for (NSUInteger i = 0; i < n; i++) if (AT(i) == o) return i; return NSNotFound; }
- (BOOL)containsObject:(id)o { return [self indexOfObject:o] != NSNotFound; }
- (NSArray *)arrayByAddingObject:(id)o { NSMutableArray *m = [[self mutableCopy] autorelease]; [m addObject:o]; return [NSArray arrayWithArray:m]; }
- (NSArray *)arrayByAddingObjectsFromArray:(NSArray *)a { NSMutableArray *m = [[self mutableCopy] autorelease]; [m addObjectsFromArray:a]; return [NSArray arrayWithArray:m]; }
- (NSString *)componentsJoinedByString:(NSString *)sep {
    NSMutableString *s = [NSMutableString string];
    NSUInteger n = N; for (NSUInteger i = 0; i < n; i++) { if (i) [s appendString:sep]; [s appendString:[AT(i) description]]; }
    return [NSString stringWithString:s];
}
- (NSArray *)subarrayWithRange:(NSRange)r {
    if (NSMaxRange(r) > N) mw_raise("NSRangeException", "subarrayWithRange: range out of bounds");
    id *v = malloc((r.length + 1) * sizeof(id)); [self getObjects:v range:r]; NSArray *a = [NSArray arrayWithObjects:v count:r.length]; free(v); return a;
}
- (void)getObjects:(id *)b range:(NSRange)r { if ([self class] == [NSArray class] || [self class] == [NSMutableArray class]) memcpy(b, _o + r.location, r.length * sizeof(id)); else for (NSUInteger i = 0; i < r.length; i++) b[i] = AT(r.location + i); }
- (void)enumerateObjectsUsingBlock:(void (^)(id, NSUInteger, BOOL *))b { BOOL stop = NO; NSUInteger n = N; for (NSUInteger i = 0; i < n && !stop; i++) b(AT(i), i, &stop); }
- (void)enumerateObjectsWithOptions:(NSUInteger)opt usingBlock:(void (^)(id, NSUInteger, BOOL *))b {
    BOOL stop = NO;
    if (opt & 2) { for (NSUInteger i = N; i-- && !stop;) b(AT(i), i, &stop); } else [self enumerateObjectsUsingBlock:b];
}
- (NSUInteger)indexOfObjectPassingTest:(BOOL (^)(id, NSUInteger, BOOL *))t { BOOL stop = NO; NSUInteger n = N; for (NSUInteger i = 0; i < n && !stop; i++) if (t(AT(i), i, &stop)) return i; return NSNotFound; }
static void merge_sort(id *v, NSUInteger n, NSComparisonResult (^cmp)(id, id)) { /* stable */
    if (n < 2) return;
    NSUInteger h = n / 2; merge_sort(v, h, cmp); merge_sort(v + h, n - h, cmp);
    id *t = malloc(n * sizeof(id)); NSUInteger i = 0, j = h, k = 0;
    while (i < h && j < n) t[k++] = cmp(v[j], v[i]) == NSOrderedAscending ? v[j++] : v[i++];
    while (i < h) t[k++] = v[i++];
    while (j < n) t[k++] = v[j++];
    memcpy(v, t, n * sizeof(id)); free(t);
}
- (NSArray *)sortedArrayUsingComparator:(NSComparator)c { NSMutableArray *m = [[self mutableCopy] autorelease]; [m sortUsingComparator:c]; return [NSArray arrayWithArray:m]; }
- (NSArray *)sortedArrayUsingSelector:(SEL)s { return [self sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return ((NSComparisonResult (*)(id, SEL, id))objc_msgSend)(a, s, b); }]; }
- (NSArray *)sortedArrayUsingFunction:(NSInteger (*)(id, id, void *))f context:(void *)ctx { return [self sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return (NSComparisonResult)f(a, b, ctx); }]; }
- (NSEnumerator *)objectEnumerator { return [[[__NSArrayEnumerator alloc] initWithArray:self reverse:NO] autorelease]; }
- (NSEnumerator *)reverseObjectEnumerator { return [[[__NSArrayEnumerator alloc] initWithArray:self reverse:YES] autorelease]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)b count:(NSUInteger)n {
    if ([self class] != [NSArray class] && [self class] != [NSMutableArray class]) { /* a subclass: through objectAtIndex: */
        NSUInteger total = N, k = 0; s->mutationsPtr = &s->extra[0]; s->itemsPtr = b;
        while (s->state < total && k < n) b[k++] = AT(s->state++);
        return k;
    }
    if (s->state) return 0;
    s->state = 1; s->itemsPtr = _o; s->mutationsPtr = &_mut;
    return _n;
}
- (BOOL)isEqualToArray:(NSArray *)a {
    NSUInteger n = N; if ([a count] != n) return NO;
    for (NSUInteger i = 0; i < n; i++) if (![AT(i) isEqual:[a objectAtIndex:i]]) return NO;
    return YES;
}
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSArray class]] && [self isEqualToArray:o]); }
- (NSUInteger)hash { return N; }
- (void)makeObjectsPerformSelector:(SEL)s { for (id o in [[self copy] autorelease]) objc_msgSend(o, s); }
- (void)makeObjectsPerformSelector:(SEL)s withObject:(id)a { for (id o in [[self copy] autorelease]) ((id (*)(id, SEL, id))objc_msgSend)(o, s, a); }
- (id)valueForKey:(NSString *)k { NSMutableArray *r = [NSMutableArray array]; for (id o in self) { id v = [o valueForKey:k]; [r addObject:v ? v : [NSNull null]]; } return r; }
- (NSArray *)filteredArrayUsingBlock:(BOOL (^)(id))f { NSMutableArray *r = [NSMutableArray array]; for (id o in self) if (f(o)) [r addObject:o]; return r; }
- (id)copyWithZone:(NSZone *)z { return [self isMemberOfClass:[NSArray class]] ? [self retain] : [[NSArray alloc] initWithArray:self]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableArray alloc] initWithArray:self]; }
- (NSString *)descriptionWithIndent:(int)ind {
    NSMutableString *s = [NSMutableString stringWithString:@"(\n"];
    NSUInteger n = N;
    for (NSUInteger i = 0; i < n; i++) {
        for (int k = 0; k <= ind; k++) [s appendString:@"    "];
        id o = AT(i);
        [s appendString:[o respondsToSelector:@selector(descriptionWithIndent:)] ? [(id)o descriptionWithIndent:ind + 1] : [o description]];
        [s appendString:i + 1 < n ? @",\n" : @"\n"];
    }
    for (int k = 0; k < ind; k++) [s appendString:@"    "];
    [s appendString:@")"];
    return s;
}
- (NSString *)description { return [self descriptionWithIndent:0]; }
#undef N
#undef AT
@end

@implementation NSMutableArray
+ (instancetype)arrayWithCapacity:(NSUInteger)n { return [[[self alloc] initWithCapacity:n] autorelease]; }
- (instancetype)initWithCapacity:(NSUInteger)n { return [self initWithObjects:0 count:0]; }
- (void)_grow { if (_n == _cap) { _cap = _cap * 2 + 4; _o = realloc(_o, _cap * sizeof(id)); } }
- (void)insertObject:(id)o atIndex:(NSUInteger)i {
    if (!o) mw_raise("NSInvalidArgumentException", "*** -[NSMutableArray insertObject:atIndex:]: object cannot be nil");
    if (i > _n) range_check(i, _n + 1, "-[NSMutableArray insertObject:atIndex:]");
    [self _grow]; memmove(_o + i + 1, _o + i, (_n - i) * sizeof(id)); _o[i] = [o retain]; _n++; _mut++;
}
- (void)addObject:(id)o { [self insertObject:o atIndex:_n]; }
- (void)addObjectsFromArray:(NSArray *)a { for (id o in a) [self addObject:o]; }
- (void)removeObjectAtIndex:(NSUInteger)i { range_check(i, _n, "-[NSMutableArray removeObjectAtIndex:]"); id o = _o[i]; memmove(_o + i, _o + i + 1, (_n - i - 1) * sizeof(id)); _n--; _mut++; [o release]; }
- (void)removeLastObject { if (_n) [self removeObjectAtIndex:_n - 1]; }
- (void)removeAllObjects { while (_n) [self removeObjectAtIndex:_n - 1]; }
- (void)removeObjectsInRange:(NSRange)r { for (NSUInteger k = 0; k < r.length; k++) [self removeObjectAtIndex:r.location]; }
- (void)replaceObjectsInRange:(NSRange)r withObjectsFromArray:(NSArray *)a {
    a = [[a copy] autorelease]; /* a may be self */
    [self removeObjectsInRange:r];
    NSUInteger i = r.location; for (id o in a) [self insertObject:o atIndex:i++];
}
- (void)removeObject:(id)o { for (NSUInteger i = _n; i--;) if (_o[i] == o || [_o[i] isEqual:o]) [self removeObjectAtIndex:i]; }
- (void)removeObjectIdenticalTo:(id)o { for (NSUInteger i = _n; i--;) if (_o[i] == o) [self removeObjectAtIndex:i]; }
- (void)removeObjectsInArray:(NSArray *)a { for (id o in a) [self removeObject:o]; }
- (void)replaceObjectAtIndex:(NSUInteger)i withObject:(id)o { range_check(i, _n, "-[NSMutableArray replaceObjectAtIndex:withObject:]"); [o retain]; [_o[i] release]; _o[i] = o; _mut++; }
- (void)setObject:(id)o atIndexedSubscript:(NSUInteger)i { if (i == _n) [self addObject:o]; else [self replaceObjectAtIndex:i withObject:o]; }
- (void)exchangeObjectAtIndex:(NSUInteger)a withObjectAtIndex:(NSUInteger)b { range_check(a, _n, "exchange"); range_check(b, _n, "exchange"); id t = _o[a]; _o[a] = _o[b]; _o[b] = t; _mut++; }
- (void)sortUsingComparator:(NSComparator)c { merge_sort(_o, _n, c); _mut++; }
- (void)sortUsingSelector:(SEL)s { [self sortUsingComparator:^NSComparisonResult(id a, id b) { return ((NSComparisonResult (*)(id, SEL, id))objc_msgSend)(a, s, b); }]; }
- (void)setArray:(NSArray *)a { [self removeAllObjects]; [self addObjectsFromArray:a]; }
- (id)copyWithZone:(NSZone *)z { return [[NSArray alloc] initWithArray:self]; }
@end

/* ================================================================ hash table shared by NSDictionary and NSSet */
struct htab { id *k, *v; NSUInteger cap, n; };
static NSUInteger hslot(struct htab *t, id k) {
    NSUInteger h = [k hash] * 0x9E3779B97F4A7C15ull, m = t->cap - 1;
    for (NSUInteger i = h & m;; i = (i + 1) & m) if (!t->k[i] || t->k[i] == k || [t->k[i] isEqual:k]) return i;
}
static void hgrow(struct htab *t) {
    struct htab n = {calloc(t->cap ? t->cap * 2 : 8, sizeof(id)), calloc(t->cap ? t->cap * 2 : 8, sizeof(id)), t->cap ? t->cap * 2 : 8, t->n};
    for (NSUInteger i = 0; i < t->cap; i++) if (t->k[i]) { NSUInteger j = hslot(&n, t->k[i]); n.k[j] = t->k[i]; n.v[j] = t->v[i]; }
    free(t->k); free(t->v); *t = n;
}
static id hget(struct htab *t, id k) { if (!t->n || !k) return nil; NSUInteger i = hslot(t, k); return t->k[i] ? t->v[i] : nil; }
static void hput(struct htab *t, id k, id v) { /* takes ownership of retained k and v */
    if ((t->n + 1) * 2 > t->cap) hgrow(t);
    NSUInteger i = hslot(t, k);
    if (t->k[i]) { [t->k[i] release]; [t->v[i] release]; } else t->n++;
    t->k[i] = k; t->v[i] = v;
}
static void hdel(struct htab *t, id k) {
    if (!t->n || !k) return;
    NSUInteger i = hslot(t, k), m = t->cap - 1;
    if (!t->k[i]) return;
    [t->k[i] release]; [t->v[i] release]; t->k[i] = t->v[i] = nil; t->n--;
    for (NSUInteger j = (i + 1) & m; t->k[j]; j = (j + 1) & m) { /* re-insert the rest of the cluster */
        id kk = t->k[j], vv = t->v[j]; t->k[j] = t->v[j] = nil;
        NSUInteger s = hslot(t, kk); t->k[s] = kk; t->v[s] = vv;
    }
}
static void hfree(struct htab *t) { for (NSUInteger i = 0; i < t->cap; i++) if (t->k[i]) { [t->k[i] release]; [t->v[i] release]; } free(t->k); free(t->v); }

@interface __NSKeyEnumerator : NSEnumerator { id _d; id *_items; NSUInteger _n, _i; } - (id)initWithOwner:(id)d items:(id *)it count:(NSUInteger)n; @end
@implementation __NSKeyEnumerator
- (id)initWithOwner:(id)d items:(id *)it count:(NSUInteger)n { _d = [d retain]; _items = malloc((n + 1) * sizeof(id)); memcpy(_items, it, n * sizeof(id)); _n = n; return self; }
- (void)dealloc { [_d release]; free(_items); [super dealloc]; }
- (id)nextObject { return _i < _n ? _items[_i++] : nil; }
@end

/* ================================================================ NSDictionary */
@implementation NSDictionary { @protected struct htab _t; unsigned long _mut; }
+ (instancetype)dictionary { return [[[self alloc] init] autorelease]; }
+ (instancetype)dictionaryWithObject:(id)o forKey:(id)k { return [[[self alloc] initWithObjects:&o forKeys:&k count:1] autorelease]; }
+ (instancetype)dictionaryWithObjects:(const id [])o forKeys:(const id [])k count:(NSUInteger)n { return [[[self alloc] initWithObjects:o forKeys:k count:n] autorelease]; }
+ (instancetype)dictionaryWithDictionary:(NSDictionary *)d { return [[[self alloc] initWithDictionary:d] autorelease]; }
+ (instancetype)dictionaryWithObjects:(NSArray *)o forKeys:(NSArray *)k {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < [k count]; i++) [d setObject:[o objectAtIndex:i] forKey:[k objectAtIndex:i]];
    return [[[self alloc] initWithDictionary:d] autorelease];
}
+ (instancetype)dictionaryWithObjectsAndKeys:(id)first, ... {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    va_list ap; va_start(ap, first);
    for (id v = first; v; v = va_arg(ap, id)) { id k = va_arg(ap, id); [d setObject:v forKey:k]; }
    va_end(ap);
    return [[[self alloc] initWithDictionary:d] autorelease];
}
- (instancetype)init { return self; }
- (instancetype)initWithObjects:(const id [])o forKeys:(const id [])k count:(NSUInteger)n {
    for (NSUInteger i = 0; i < n; i++) {
        if (!o[i] || !k[i]) { char b[128]; snprintf(b, sizeof b, "*** -[NSDictionary initWithObjects:forKeys:count:]: attempt to insert nil %s from %s[%lu]", o[i] ? "key" : "object", o[i] ? "keys" : "objects", (unsigned long)i); mw_raise("NSInvalidArgumentException", b); }
        hput(&_t, [k[i] copyWithZone:0], [o[i] retain]);
    }
    return self;
}
- (instancetype)initWithDictionary:(NSDictionary *)d { for (id k in d) hput(&_t, [k copyWithZone:0], [[d objectForKey:k] retain]); return self; }
- (instancetype)initWithDictionary:(NSDictionary *)d copyItems:(BOOL)c { return [self initWithDictionary:d]; }
- (void)dealloc { hfree(&_t); [super dealloc]; }
- (NSUInteger)count { return _t.n; }
- (id)objectForKey:(id)k { return hget(&_t, k); }
/* beyond count, objectForKey: and enumeration everything goes through them (Swift's bridged dictionaries subclass NSDictionary) */
- (id)objectForKeyedSubscript:(id)k { return [self objectForKey:k]; }
- (id)valueForKey:(NSString *)k { return [self objectForKey:k]; }
- (NSArray *)allKeys { NSMutableArray *a = [NSMutableArray array]; for (id k in self) [a addObject:k]; return a; }
- (NSArray *)allValues { NSMutableArray *a = [NSMutableArray array]; for (id k in self) [a addObject:[self objectForKey:k]]; return a; }
- (NSArray *)keysSortedByValueUsingComparator:(NSComparator)c {
    return [[self allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return c([self objectForKey:a], [self objectForKey:b]); }];
}
- (NSArray *)allKeysForObject:(id)o { NSMutableArray *a = [NSMutableArray array]; for (id k in self) if ([[self objectForKey:k] isEqual:o]) [a addObject:k]; return a; }
- (NSEnumerator *)keyEnumerator { NSArray *k = [self allKeys]; id *v = malloc(([k count] + 1) * sizeof(id)); [k getObjects:v range:NSMakeRange(0, [k count])]; id e = [[[__NSKeyEnumerator alloc] initWithOwner:k items:v count:[k count]] autorelease]; free(v); return e; }
- (NSEnumerator *)objectEnumerator { return [[self allValues] objectEnumerator]; }
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id, id, BOOL *))b {
    NSArray *keys = [self allKeys]; BOOL stop = NO;
    for (NSUInteger i = 0; i < [keys count] && !stop; i++) { id k = [keys objectAtIndex:i]; b(k, [self objectForKey:k], &stop); }
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)b count:(NSUInteger)n {
    if ([self class] != [NSDictionary class] && [self class] != [NSMutableDictionary class]) { /* a subclass: through keyEnumerator */
        if (!s->state) { s->state = 1; s->extra[1] = (unsigned long)[[self keyEnumerator] retain]; }
        NSEnumerator *e = (NSEnumerator *)s->extra[1]; NSUInteger k = 0; id o = nil;
        s->mutationsPtr = &s->extra[0]; s->itemsPtr = b;
        while (k < n && (o = [e nextObject])) b[k++] = o;
        if (!o && k < n) { [e autorelease]; s->extra[1] = 0; } /* ponytail: leaks the enumerator if the loop breaks early */
        return k;
    }
    NSUInteger k = 0;
    s->mutationsPtr = &_mut; s->itemsPtr = b;
    while (s->state < _t.cap && k < n) { if (_t.k[s->state]) b[k++] = _t.k[s->state]; s->state++; }
    return k;
}
- (BOOL)isEqualToDictionary:(NSDictionary *)d {
    if ([d count] != [self count]) return NO;
    for (id k in self) if (![[self objectForKey:k] isEqual:[d objectForKey:k]]) return NO;
    return YES;
}
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSDictionary class]] && [self isEqualToDictionary:o]); }
- (NSUInteger)hash { return [self count]; }
- (id)copyWithZone:(NSZone *)z { return [self isMemberOfClass:[NSDictionary class]] ? [self retain] : [[NSDictionary alloc] initWithDictionary:self]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableDictionary alloc] initWithDictionary:self]; }
- (NSString *)descriptionWithIndent:(int)ind {
    NSMutableString *s = [NSMutableString stringWithString:@"{\n"];
    NSArray *keys = [[self allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return [[a description] compare:[b description]]; }];
    for (id k in keys) {
        for (int q = 0; q <= ind; q++) [s appendString:@"    "];
        id v = [self objectForKey:k];
        [s appendFormat:@"%@ = %@;\n", k, [v respondsToSelector:@selector(descriptionWithIndent:)] ? [(id)v descriptionWithIndent:ind + 1] : [v description]];
    }
    for (int q = 0; q < ind; q++) [s appendString:@"    "];
    [s appendString:@"}"];
    return s;
}
- (NSString *)description { return [self descriptionWithIndent:0]; }
@end

@implementation NSMutableDictionary
+ (instancetype)dictionaryWithCapacity:(NSUInteger)n { return [[[self alloc] init] autorelease]; }
- (instancetype)initWithCapacity:(NSUInteger)n { return [self init]; }
- (void)setObject:(id)o forKey:(id)k {
    if (!k) mw_raise("NSInvalidArgumentException", "*** -[NSMutableDictionary setObject:forKey:]: key cannot be nil");
    if (!o) mw_raise("NSInvalidArgumentException", "*** -[NSMutableDictionary setObject:forKey:]: object cannot be nil");
    hput(&_t, [k copyWithZone:0], [o retain]); _mut++;
}
- (void)setObject:(id)o forKeyedSubscript:(id)k { if (o) [self setObject:o forKey:k]; else [self removeObjectForKey:k]; }
- (void)setValue:(id)v forKey:(NSString *)k { [self setObject:v forKeyedSubscript:k]; }
- (void)removeObjectForKey:(id)k { hdel(&_t, k); _mut++; }
- (void)removeObjectsForKeys:(NSArray *)ks { for (id k in ks) [self removeObjectForKey:k]; }
- (void)removeAllObjects { hfree(&_t); memset(&_t, 0, sizeof _t); _mut++; }
- (void)addEntriesFromDictionary:(NSDictionary *)d { for (id k in d) [self setObject:[d objectForKey:k] forKey:k]; }
- (void)setDictionary:(NSDictionary *)d { [self removeAllObjects]; [self addEntriesFromDictionary:d]; }
- (id)copyWithZone:(NSZone *)z { return [[NSDictionary alloc] initWithDictionary:self]; }
@end

/* ================================================================ NSSet */
@implementation NSSet { @protected struct htab _t; unsigned long _mut; }
+ (instancetype)set { return [[[self alloc] init] autorelease]; }
+ (instancetype)setWithArray:(NSArray *)a { return [[[self alloc] initWithArray:a] autorelease]; }
+ (instancetype)setWithObject:(id)o { return [self setWithArray:[NSArray arrayWithObject:o]]; }
+ (instancetype)setWithObjects:(id)first, ... {
    NSMutableArray *a = [NSMutableArray array]; va_list ap; va_start(ap, first);
    for (id o = first; o; o = va_arg(ap, id)) [a addObject:o];
    va_end(ap); return [self setWithArray:a];
}
+ (instancetype)setWithSet:(NSSet *)s { return [self setWithArray:[s allObjects]]; }
- (instancetype)init { return self; }
- (instancetype)initWithArray:(NSArray *)a { for (id o in a) hput(&_t, [o retain], [o retain]); return self; }
- (void)dealloc { hfree(&_t); [super dealloc]; }
- (NSUInteger)count { return _t.n; }
- (id)member:(id)o { return hget(&_t, o); }
- (BOOL)containsObject:(id)o { return [self member:o] != nil; }
- (NSArray *)allObjects { NSMutableArray *a = [NSMutableArray array]; for (id o in self) [a addObject:o]; return a; }
- (id)anyObject { for (id o in self) return o; return nil; }
- (NSEnumerator *)objectEnumerator { return [[self allObjects] objectEnumerator]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)b count:(NSUInteger)n {
    if ([self class] != [NSSet class] && [self class] != [NSMutableSet class]) { /* a subclass: through objectEnumerator */
        if (!s->state) { s->state = 1; s->extra[1] = (unsigned long)[[self objectEnumerator] retain]; }
        NSEnumerator *e = (NSEnumerator *)s->extra[1]; NSUInteger k = 0; id o = nil;
        s->mutationsPtr = &s->extra[0]; s->itemsPtr = b;
        while (k < n && (o = [e nextObject])) b[k++] = o;
        if (!o && k < n) { [e autorelease]; s->extra[1] = 0; }
        return k;
    }
    NSUInteger k = 0; s->mutationsPtr = &_mut; s->itemsPtr = b;
    while (s->state < _t.cap && k < n) { if (_t.k[s->state]) b[k++] = _t.k[s->state]; s->state++; }
    return k;
}
- (void)enumerateObjectsUsingBlock:(void (^)(id, BOOL *))b { BOOL stop = NO; for (id o in [self allObjects]) { b(o, &stop); if (stop) break; } }
- (BOOL)isSubsetOfSet:(NSSet *)s { for (id o in self) if (![s containsObject:o]) return NO; return YES; }
- (BOOL)intersectsSet:(NSSet *)s { for (id o in self) if ([s containsObject:o]) return YES; return NO; }
- (BOOL)isEqualToSet:(NSSet *)s { return [s count] == [self count] && [self isSubsetOfSet:s]; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSSet class]] && [self isEqualToSet:o]); }
- (NSUInteger)hash { return _t.n; }
- (NSSet *)setByAddingObject:(id)o { NSMutableSet *m = [[self mutableCopy] autorelease]; [m addObject:o]; return [NSSet setWithSet:m]; }
- (id)copyWithZone:(NSZone *)z { return [self isMemberOfClass:[NSSet class]] ? [self retain] : [[NSSet alloc] initWithArray:[self allObjects]]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableSet alloc] initWithArray:[self allObjects]]; }
- (NSString *)description { return [NSString stringWithFormat:@"{(%@)}", [[self allObjects] componentsJoinedByString:@", "]]; }
@end
@implementation NSMutableSet
+ (instancetype)setWithCapacity:(NSUInteger)n { return [[[self alloc] init] autorelease]; }
- (instancetype)initWithCapacity:(NSUInteger)n { return [self init]; }
- (void)addObject:(id)o { if (!o) mw_raise("NSInvalidArgumentException", "*** -[NSMutableSet addObject:]: object cannot be nil"); if (!hget(&_t, o)) { hput(&_t, [o retain], [o retain]); _mut++; } }
- (void)removeObject:(id)o { hdel(&_t, o); _mut++; }
- (void)removeAllObjects { hfree(&_t); memset(&_t, 0, sizeof _t); _mut++; }
- (void)addObjectsFromArray:(NSArray *)a { for (id o in a) [self addObject:o]; }
- (void)unionSet:(NSSet *)s { for (id o in [s allObjects]) [self addObject:o]; }
- (void)minusSet:(NSSet *)s { for (id o in [s allObjects]) [self removeObject:o]; }
- (void)intersectSet:(NSSet *)s { for (id o in [self allObjects]) if (![s containsObject:o]) [self removeObject:o]; }
- (id)copyWithZone:(NSZone *)z { return [[NSSet alloc] initWithArray:[self allObjects]]; }
@end

/* ================================================================ NSNull */
@implementation NSNull
static NSNull *the_null;
+ (NSNull *)null { if (!the_null) the_null = [[NSNull alloc] init]; return the_null; }
- (id)retain { return self; }
- (oneway void)release { }
- (id)autorelease { return self; }
- (id)copyWithZone:(NSZone *)z { return self; }
- (NSString *)description { return @"<null>"; }
@end

/* ================================================================ NSValue / NSNumber */
@implementation NSValue { @protected char _type; union { long long i; unsigned long long u; double d; NSRange r; void *p; NSRect rect; } _v; }
static NSValue *mkval(char t, const void *v, size_t n) { NSValue *x = [[NSValue alloc] init]; x->_type = t; memcpy(&x->_v, v, n); return [x autorelease]; }
/* any type: up to the union's size inline ('X'), larger on the heap ('Y'); the encoding is kept beside the object */
const char *NSGetSizeAndAlignment(const char *t, NSUInteger *size, NSUInteger *align);
+ (NSValue *)valueWithBytes:(const void *)b objCType:(const char *)t { return [[[self alloc] initWithBytes:b objCType:t] autorelease]; }
+ (NSValue *)value:(const void *)b withObjCType:(const char *)t { return [self valueWithBytes:b objCType:t]; }
- (instancetype)initWithBytes:(const void *)b objCType:(const char *)t {
    NSUInteger n = 0; NSGetSizeAndAlignment(t, &n, NULL);
    if (n <= sizeof _v) { _type = 'X'; memcpy(&_v, b, n); }
    else { _type = 'Y'; _v.p = malloc(n); memcpy(_v.p, b, n); }
    objc_setAssociatedObject(self, "mw_enc", [NSString stringWithUTF8String:t], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}
- (void)getValue:(void *)out size:(NSUInteger)n {
    NSString *e = objc_getAssociatedObject(self, "mw_enc");
    NSUInteger have = sizeof _v;
    if (e) NSGetSizeAndAlignment([e UTF8String], &have, NULL);
    memcpy(out, _type == 'Y' ? _v.p : (void *)&_v, n < have ? n : have);
}
- (void)dealloc { if (_type == 'Y') free(_v.p); [super dealloc]; }
- (const char *)objCType {
    NSString *e = objc_getAssociatedObject(self, "mw_enc");
    if (e) return [e UTF8String];
    return _type == 'R' ? @encode(NSRange) : _type == 'P' ? @encode(NSPoint) : _type == 'S' ? @encode(NSSize) : _type == 'Q' ? @encode(NSRect) : "^v";
}
- (void)getValue:(void *)out { NSString *e = objc_getAssociatedObject(self, "mw_enc"); NSUInteger n = sizeof _v; if (e) NSGetSizeAndAlignment([e UTF8String], &n, NULL); [self getValue:out size:n]; }
+ (NSValue *)valueWithRange:(NSRange)r { return mkval('R', &r, sizeof r); }
+ (NSValue *)valueWithPointer:(const void *)p { return mkval('^', &p, sizeof p); }
+ (NSValue *)valueWithNonretainedObject:(id)o { return mkval('^', &o, sizeof o); }
+ (NSValue *)valueWithPoint:(NSPoint)p { NSRect r = {p, {0, 0}}; return mkval('P', &r, sizeof r); }
+ (NSValue *)valueWithSize:(NSSize)s { NSRect r = {{0, 0}, s}; return mkval('S', &r, sizeof r); }
+ (NSValue *)valueWithRect:(NSRect)r { return mkval('Q', &r, sizeof r); }
- (NSRange)rangeValue { return _v.r; }
- (void *)pointerValue { return _v.p; }
- (id)nonretainedObjectValue { return (id)_v.p; }
- (NSPoint)pointValue { return _v.rect.origin; }
- (NSSize)sizeValue { return _v.rect.size; }
- (NSRect)rectValue { return _v.rect; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSValue class]] && !memcmp(&_v, &((NSValue *)o)->_v, sizeof _v)); }
- (NSUInteger)hash { return (NSUInteger)_v.u; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)description {
    if (_type == 'R') return [NSString stringWithFormat:@"NSRange: {%lu, %lu}", (unsigned long)_v.r.location, (unsigned long)_v.r.length];
    return [NSString stringWithFormat:@"<%p>", _v.p];
}
@end

/* type tags: c=char/BOOL q=signed u=unsigned d=double f=float B=bool */
@implementation NSNumber
static NSNumber *mknum(char t, long long i, unsigned long long u, double d) {
    NSNumber *n = [[NSNumber alloc] init]; n->_type = t;
    if (t == 'd' || t == 'f') n->_v.d = d; else if (t == 'u') n->_v.u = u; else n->_v.i = i;
    return [n autorelease];
}
+ (NSNumber *)numberWithBool:(BOOL)v { /* two shared objects, like CFBoolean */
    static NSNumber *yes, *no;
    if (kCFBooleanTrue) return v ? (NSNumber *)kCFBooleanTrue : (NSNumber *)kCFBooleanFalse;   /* swift.m: the static ones */
    if (!yes) { NSNumber *y = [mknum('B', 1, 0, 0) retain], *n = [mknum('B', 0, 0, 0) retain]; no = n; yes = y; }
    return v ? yes : no;
}
/* what CFBoolean is on Apple: numbers made with numberWithBool: (property lists and JSON tell them apart) */
BOOL mw_number_is_bool(NSNumber *n) { return [n _mwType] == 'B'; }   /* methods: the constant literals (constlit.m) have another layout */
BOOL mw_number_is_real(NSNumber *n) { char t = [n _mwType]; return t == 'd' || t == 'f'; }
+ (NSNumber *)numberWithChar:(char)v { return mknum('c', v, 0, 0); }
+ (NSNumber *)numberWithUnsignedChar:(unsigned char)v { return mknum('q', v, 0, 0); }
+ (NSNumber *)numberWithShort:(short)v { return mknum('q', v, 0, 0); }
+ (NSNumber *)numberWithUnsignedShort:(unsigned short)v { return mknum('q', v, 0, 0); }
+ (NSNumber *)numberWithInt:(int)v { return mknum('q', v, 0, 0); }
+ (NSNumber *)numberWithUnsignedInt:(unsigned)v { return mknum('q', v, 0, 0); }
+ (NSNumber *)numberWithLong:(long)v { return mknum('q', v, 0, 0); }
+ (NSNumber *)numberWithUnsignedLong:(unsigned long)v { return mknum('u', 0, v, 0); }
+ (NSNumber *)numberWithLongLong:(long long)v { return mknum('q', v, 0, 0); }
+ (NSNumber *)numberWithUnsignedLongLong:(unsigned long long)v { return mknum('u', 0, v, 0); }
+ (NSNumber *)numberWithInteger:(NSInteger)v { return mknum('q', v, 0, 0); }
+ (NSNumber *)numberWithUnsignedInteger:(NSUInteger)v { return mknum('u', 0, v, 0); }
+ (NSNumber *)numberWithFloat:(float)v { return mknum('f', 0, 0, v); }
+ (NSNumber *)numberWithDouble:(double)v { return mknum('d', 0, 0, v); }
- (instancetype)initWithInt:(int)v { _type = 'q'; _v.i = v; return self; }
- (instancetype)initWithInteger:(NSInteger)v { _type = 'q'; _v.i = v; return self; }
- (instancetype)initWithLongLong:(long long)v { _type = 'q'; _v.i = v; return self; }
- (instancetype)initWithUnsignedLongLong:(unsigned long long)v { _type = 'u'; _v.u = v; return self; }
- (instancetype)initWithDouble:(double)v { _type = 'd'; _v.d = v; return self; }
- (instancetype)initWithFloat:(float)v { _type = 'f'; _v.d = v; return self; }
- (instancetype)initWithBool:(BOOL)v { _type = 'B'; _v.i = v ? 1 : 0; return self; }
- (double)doubleValue { return _type == 'd' || _type == 'f' ? _v.d : _type == 'u' ? (double)_v.u : (double)_v.i; }
- (long long)longLongValue { return _type == 'd' || _type == 'f' ? (long long)_v.d : _v.i; }
- (unsigned long long)unsignedLongLongValue { return _type == 'd' || _type == 'f' ? (unsigned long long)_v.d : _v.u; }
- (BOOL)boolValue { return _type == 'd' || _type == 'f' ? _v.d != 0 : _v.i != 0; }
- (char)charValue { return (char)[self longLongValue]; }
- (unsigned char)unsignedCharValue { return (unsigned char)[self longLongValue]; }
- (short)shortValue { return (short)[self longLongValue]; }
- (unsigned short)unsignedShortValue { return (unsigned short)[self longLongValue]; }
- (int)intValue { return (int)[self longLongValue]; }
- (unsigned)unsignedIntValue { return (unsigned)[self longLongValue]; }
- (long)longValue { return (long)[self longLongValue]; }
- (unsigned long)unsignedLongValue { return (unsigned long)[self unsignedLongLongValue]; }
- (NSInteger)integerValue { return (NSInteger)[self longLongValue]; }
- (NSUInteger)unsignedIntegerValue { return (NSUInteger)[self unsignedLongLongValue]; }
- (float)floatValue { return (float)[self doubleValue]; }
- (const char *)objCType { return _type == 'd' ? "d" : _type == 'f' ? "f" : _type == 'u' ? "Q" : _type == 'B' || _type == 'c' ? "c" : "q"; }
- (char)_mwType { return _type; }
- (NSString *)stringValue { return [self description]; }
- (NSString *)description {
    if (_type == 'd' || _type == 'f') return [NSString stringWithFormat:@"%.*g", _type == 'f' ? 7 : 15, _v.d];
    if (_type == 'u') return [NSString stringWithFormat:@"%llu", _v.u];
    return [NSString stringWithFormat:@"%lld", _v.i];
}
- (NSComparisonResult)compare:(NSNumber *)o {
    char ot = [o _mwType];
    if (_type == 'd' || _type == 'f' || ot == 'd' || ot == 'f') { double a = [self doubleValue], b = [o doubleValue]; return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame; }
    long long a = [self longLongValue], b = [o longLongValue]; return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
}
- (BOOL)isEqualToNumber:(NSNumber *)n { return [self compare:n] == NSOrderedSame; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSNumber class]] && [self isEqualToNumber:o]); }
- (NSUInteger)hash { double d = [self doubleValue]; return d == (double)(long long)d ? (NSUInteger)(long long)d : (NSUInteger)_v.u; }
@end

/* ================================================================ NSData */
@implementation NSData { @protected unsigned char *_b; NSUInteger _n, _cap; BOOL _free; }
+ (instancetype)data { return [[[self alloc] initWithBytes:0 length:0] autorelease]; }
+ (instancetype)dataWithBytes:(const void *)b length:(NSUInteger)n { return [[[self alloc] initWithBytes:b length:n] autorelease]; }
+ (instancetype)dataWithBytesNoCopy:(void *)b length:(NSUInteger)n { return [self dataWithBytesNoCopy:b length:n freeWhenDone:YES]; }
+ (instancetype)dataWithBytesNoCopy:(void *)b length:(NSUInteger)n freeWhenDone:(BOOL)f { NSData *d = [[self alloc] initWithBytes:0 length:0]; free(d->_b); d->_b = b; d->_n = d->_cap = n; d->_free = f; return [d autorelease]; }
+ (instancetype)dataWithContentsOfFile:(NSString *)p { return [[[self alloc] initWithContentsOfFile:p] autorelease]; }
+ (instancetype)dataWithContentsOfFile:(NSString *)p options:(NSDataReadingOptions)o error:(NSError **)e { id d = [self dataWithContentsOfFile:p]; if (!d && e) *e = mw_posix_error(errno, p); return d; }
+ (instancetype)dataWithData:(NSData *)d { return [self dataWithBytes:[d bytes] length:[d length]]; }
- (instancetype)initWithBytes:(const void *)b length:(NSUInteger)n { _cap = n; _b = malloc(n ? n : 1); if (n) memcpy(_b, b, n); _n = n; _free = YES; return self; }
- (instancetype)initWithBytesNoCopy:(void *)b length:(NSUInteger)n freeWhenDone:(BOOL)f { _b = b; _n = _cap = n; _free = f; return self; }
- (instancetype)initWithData:(NSData *)d { return [self initWithBytes:[d bytes] length:[d length]]; }
- (instancetype)initWithContentsOfFile:(NSString *)p {
    int fd = open([p fileSystemRepresentation], 0);
    if (fd < 0) { [self release]; return nil; }
    NSUInteger cap = 65536, n = 0; unsigned char *b = malloc(cap); long r;
    while ((r = read(fd, b + n, cap - n)) > 0) { n += (NSUInteger)r; if (n == cap) b = realloc(b, cap *= 2); }
    close(fd);
    _b = b; _n = n; _cap = cap; _free = YES; return self;
}
- (void)dealloc { if (_free) free(_b); [super dealloc]; }
- (const void *)bytes { return _b; }
- (NSUInteger)length { return _n; }
- (void)getBytes:(void *)buf length:(NSUInteger)n { memcpy(buf, _b, n < _n ? n : _n); }
- (void)getBytes:(void *)buf range:(NSRange)r { if (NSMaxRange(r) > _n) mw_raise("NSRangeException", "getBytes:range: range out of bounds"); memcpy(buf, _b + r.location, r.length); }
- (BOOL)isEqualToData:(NSData *)d { return [d length] == _n && !memcmp([d bytes], _b, _n); }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSData class]] && [self isEqualToData:o]); }
- (NSUInteger)hash { NSUInteger h = 5381; for (NSUInteger i = 0; i < _n && i < 80; i++) h = h * 33 + _b[i]; return h; }
- (NSData *)subdataWithRange:(NSRange)r { if (NSMaxRange(r) > _n) mw_raise("NSRangeException", "subdataWithRange: range out of bounds"); return [NSData dataWithBytes:_b + r.location length:r.length]; }
- (NSRange)rangeOfData:(NSData *)d options:(NSUInteger)o range:(NSRange)r {
    NSUInteger m = [d length];
    for (NSUInteger i = r.location; m && i + m <= NSMaxRange(r); i++) if (!memcmp(_b + i, [d bytes], m)) return NSMakeRange(i, m);
    return NSMakeRange(NSNotFound, 0);
}
- (BOOL)writeToFile:(NSString *)p atomically:(BOOL)a {
    int fd = open([p fileSystemRepresentation], 1 | 0x200 | 0x400, 0644);
    if (fd < 0) return NO;
    NSUInteger off = 0;
    while (off < _n) { long w = write(fd, _b + off, _n - off); if (w <= 0) break; off += (NSUInteger)w; }
    close(fd); return off == _n;
}
- (BOOL)writeToFile:(NSString *)p options:(NSUInteger)o error:(NSError **)e { BOOL ok = [self writeToFile:p atomically:YES]; if (!ok && e) *e = mw_posix_error(errno, p); return ok; }
- (id)copyWithZone:(NSZone *)z { return [self isMemberOfClass:[NSData class]] ? [self retain] : [[NSData alloc] initWithData:self]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableData alloc] initWithData:self]; }
- (NSString *)description {
    NSMutableString *s = [NSMutableString stringWithString:@"{length = "];
    [s appendFormat:@"%lu, bytes = 0x", (unsigned long)_n];
    for (NSUInteger i = 0; i < _n && i < 24; i++) { [s appendFormat:@"%02x", _b[i]]; if (i % 4 == 3 && i + 1 < _n && i < 23) [s appendString:@" "]; }
    if (_n > 24) [s appendString:@" ... "];
    [s appendString:@"}"]; return s;
}
- (void)enumerateByteRangesUsingBlock:(void (^)(const void *, NSRange, BOOL *))b { BOOL stop = NO; b(_b, NSMakeRange(0, _n), &stop); }
@end

@implementation NSMutableData
+ (instancetype)dataWithCapacity:(NSUInteger)n { return [[[self alloc] initWithCapacity:n] autorelease]; }
+ (instancetype)dataWithLength:(NSUInteger)n { return [[[self alloc] initWithLength:n] autorelease]; }
- (instancetype)initWithCapacity:(NSUInteger)n { self = [self initWithBytes:0 length:0]; return self; }
- (instancetype)initWithLength:(NSUInteger)n { self = [self initWithBytes:0 length:0]; [self setLength:n]; return self; }
- (void)_reserve:(NSUInteger)n {
    if (n <= _cap && _free) return;
    NSUInteger c = n > _cap * 2 ? n : _cap * 2 + 16;
    unsigned char *b = malloc(c); memcpy(b, _b, _n);
    if (_free) free(_b);
    _b = b; _cap = c; _free = YES;
}
- (void *)mutableBytes { return _b; }
- (void)setLength:(NSUInteger)n { [self _reserve:n]; if (n > _n) memset(_b + _n, 0, n - _n); _n = n; }
- (void)increaseLengthBy:(NSUInteger)n { [self setLength:_n + n]; }
- (void)appendBytes:(const void *)b length:(NSUInteger)n { [self _reserve:_n + n]; memcpy(_b + _n, b, n); _n += n; }
- (void)appendData:(NSData *)d { [self appendBytes:[d bytes] length:[d length]]; }
- (void)replaceBytesInRange:(NSRange)r withBytes:(const void *)b { if (NSMaxRange(r) > _n) [self setLength:NSMaxRange(r)]; memcpy(_b + r.location, b, r.length); }
- (void)replaceBytesInRange:(NSRange)r withBytes:(const void *)b length:(NSUInteger)n {
    NSUInteger nn = _n - r.length + n; [self _reserve:nn];
    memmove(_b + r.location + n, _b + NSMaxRange(r), _n - NSMaxRange(r)); memcpy(_b + r.location, b, n); _n = nn;
}
- (void)resetBytesInRange:(NSRange)r { memset(_b + r.location, 0, r.length); }
- (void)setData:(NSData *)d { _n = 0; [self appendData:d]; }
- (id)copyWithZone:(NSZone *)z { return [[NSData alloc] initWithData:self]; }
@end

/* ================================================================ NSOrderedSet, NSMutableOrderedSet
 * An array without duplicates. ponytail: membership is a linear search; a hash index when sets get large */
@implementation NSOrderedSet { @protected NSMutableArray *_a; }
+ (instancetype)orderedSet { return [[[self alloc] init] autorelease]; }
+ (instancetype)orderedSetWithArray:(NSArray *)a { return [[[self alloc] initWithArray:a] autorelease]; }
+ (instancetype)orderedSetWithObject:(id)o { return [[[self alloc] initWithArray:@[o]] autorelease]; }
- (instancetype)init { return [self initWithArray:@[]]; }
- (instancetype)initWithArray:(NSArray *)a {
    if ((self = [super init])) { _a = [NSMutableArray new]; for (id o in a) if (![_a containsObject:o]) [_a addObject:o]; }
    return self;
}
- (void)dealloc { [_a release]; [super dealloc]; }
- (NSUInteger)count { return _a.count; }
- (id)objectAtIndex:(NSUInteger)i { return [_a objectAtIndex:i]; }
- (id)objectAtIndexedSubscript:(NSUInteger)i { return [_a objectAtIndex:i]; }
- (NSUInteger)indexOfObject:(id)o { return [_a indexOfObject:o]; }
- (BOOL)containsObject:(id)o { return [_a containsObject:o]; }
- (id)firstObject { return _a.firstObject; }
- (id)lastObject { return _a.lastObject; }
- (NSArray *)array { return [[_a copy] autorelease]; }
- (NSEnumerator *)objectEnumerator { return [_a objectEnumerator]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)b count:(NSUInteger)n { return [_a countByEnumeratingWithState:s objects:b count:n]; }
- (id)copyWithZone:(NSZone *)z { return [[NSOrderedSet alloc] initWithArray:_a]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableOrderedSet alloc] initWithArray:_a]; }
- (NSString *)description { return [_a description]; }
@end
@implementation NSMutableOrderedSet
+ (instancetype)orderedSetWithCapacity:(NSUInteger)n { return [self orderedSet]; }
- (void)addObject:(id)o { if (![_a containsObject:o]) [_a addObject:o]; }
- (void)addObjectsFromArray:(NSArray *)a { for (id o in a) [self addObject:o]; }
- (void)insertObject:(id)o atIndex:(NSUInteger)i { if (![_a containsObject:o]) [_a insertObject:o atIndex:i]; }
- (void)removeObject:(id)o { [_a removeObject:o]; }
- (void)removeObjectAtIndex:(NSUInteger)i { [_a removeObjectAtIndex:i]; }
- (void)removeAllObjects { [_a removeAllObjects]; }
@end
