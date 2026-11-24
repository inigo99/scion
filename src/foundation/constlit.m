/* constlit.m — constant literals: recent clang compiles @42, @1.5, @[...] and @{...} with constant contents into
 * static objects in the binary (sections __objc_intobj, __objc_doubleobj, __objc_arrayobj, __objc_dictobj) whose isa
 * is one of these classes. Their memory layout is fixed by the compiler, so they do not use their superclasses' ivars:
 * every method that would read them is overridden here. They are immortal. */
#import <Foundation/Foundation.h>

@interface NSNumber (MWType) - (char)_mwType; @end

#define IMMORTAL \
    - (id)retain { return self; } - (oneway void)release { } - (id)autorelease { return self; } \
    - (NSUInteger)retainCount { return NSUIntegerMax; } - (void)dealloc { } - (id)copyWithZone:(NSZone *)z { return self; }

/* numbers: everything else in NSNumber goes through these */
#define NUMBER_COMMON \
    - (char)charValue { return (char)[self longLongValue]; } - (int)intValue { return (int)[self longLongValue]; } \
    - (long)longValue { return (long)[self longLongValue]; } - (NSInteger)integerValue { return (NSInteger)[self longLongValue]; } \
    - (unsigned)unsignedIntValue { return (unsigned)[self unsignedLongLongValue]; } \
    - (NSUInteger)unsignedIntegerValue { return (NSUInteger)[self unsignedLongLongValue]; } \
    - (unsigned long)unsignedLongValue { return (unsigned long)[self unsignedLongLongValue]; } \
    - (float)floatValue { return (float)[self doubleValue]; } - (BOOL)boolValue { return [self doubleValue] != 0; } \
    - (NSString *)stringValue { return [self description]; } \
    - (NSComparisonResult)compare:(NSNumber *)o { \
        char a = [self _mwType], b = [o _mwType]; \
        if (a == 'd' || a == 'f' || b == 'd' || b == 'f') { double x = [self doubleValue], y = [o doubleValue]; return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame; } \
        long long x = [self longLongValue], y = [o longLongValue]; return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame; } \
    - (BOOL)isEqualToNumber:(NSNumber *)n { return [self compare:n] == NSOrderedSame; } \
    - (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSNumber class]] && [self isEqualToNumber:o]); } \
    - (NSUInteger)hash { double d = [self doubleValue]; return d == (double)(long long)d ? (NSUInteger)(long long)d : (NSUInteger)[self longLongValue]; }

@interface NSConstantIntegerNumber : NSNumber @end
@implementation NSConstantIntegerNumber   /* { isa; const char *encoding; long long value; } */
static const char *enc(id s) { return *(const char **)((char *)s + 8); }
static long long ival(id s) { return *(long long *)((char *)s + 16); }
static BOOL is_unsigned(id s) { char e = enc(s)[0]; return e == 'C' || e == 'S' || e == 'I' || e == 'L' || e == 'Q'; }
IMMORTAL
- (char)_mwType { char e = enc(self)[0]; return e == 'B' ? 'B' : e == 'c' ? 'c' : is_unsigned(self) ? 'u' : 'q'; }
- (const char *)objCType { return enc(self); }
- (long long)longLongValue { return ival(self); }
- (unsigned long long)unsignedLongLongValue { return (unsigned long long)ival(self); }
- (double)doubleValue { return is_unsigned(self) ? (double)(unsigned long long)ival(self) : (double)ival(self); }
- (NSString *)description { return is_unsigned(self) ? [NSString stringWithFormat:@"%llu", (unsigned long long)ival(self)] : [NSString stringWithFormat:@"%lld", ival(self)]; }
NUMBER_COMMON
@end

@interface NSConstantDoubleNumber : NSNumber @end
@implementation NSConstantDoubleNumber    /* { isa; double value; } */
IMMORTAL
- (char)_mwType { return 'd'; }
- (const char *)objCType { return "d"; }
- (double)doubleValue { return *(double *)((char *)self + 8); }
- (long long)longLongValue { return (long long)[self doubleValue]; }
- (unsigned long long)unsignedLongLongValue { return (unsigned long long)[self doubleValue]; }
- (NSString *)description { return [NSString stringWithFormat:@"%.15g", [self doubleValue]]; }
NUMBER_COMMON
@end

@interface NSConstantFloatNumber : NSNumber @end
@implementation NSConstantFloatNumber     /* { isa; float value; } */
IMMORTAL
- (char)_mwType { return 'f'; }
- (const char *)objCType { return "f"; }
- (double)doubleValue { return *(float *)((char *)self + 8); }
- (long long)longLongValue { return (long long)[self doubleValue]; }
- (unsigned long long)unsignedLongLongValue { return (unsigned long long)[self doubleValue]; }
- (NSString *)description { return [NSString stringWithFormat:@"%.7g", [self doubleValue]]; }
NUMBER_COMMON
@end

@interface NSConstantArray : NSArray @end
@implementation NSConstantArray           /* { isa; NSUInteger count; const id *objects; } */
IMMORTAL
- (NSUInteger)count { return *(NSUInteger *)((char *)self + 8); }
- (id)objectAtIndex:(NSUInteger)i {
    if (i >= [self count]) [NSException raise:NSRangeException format:@"*** -[NSConstantArray objectAtIndex:]: index %lu beyond bounds [0 .. %ld]", (unsigned long)i, (long)[self count] - 1];
    return (*(id **)((char *)self + 16))[i];
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)b count:(NSUInteger)n {
    if (s->state) return 0;
    s->state = 1; s->itemsPtr = *(id **)((char *)self + 16); s->mutationsPtr = &s->extra[0];
    return [self count];
}
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableArray alloc] initWithArray:self]; }
@end

@interface NSConstantDictionary : NSDictionary @end
@implementation NSConstantDictionary      /* { isa; NSUInteger options; NSUInteger count; const id *keys; const id *objects; } */
static NSUInteger dcount(id s) { return *(NSUInteger *)((char *)s + 16); }
static const id *dkeys(id s) { return *(const id **)((char *)s + 24); }
static const id *dobjs(id s) { return *(const id **)((char *)s + 32); }
IMMORTAL
- (NSUInteger)count { return dcount(self); }
- (id)objectForKey:(id)k {
    if (!k) return nil;
    const id *ks = dkeys(self);
    for (NSUInteger i = 0; i < dcount(self); i++) if (ks[i] == k || [ks[i] isEqual:k]) return dobjs(self)[i];   /* ponytail: linear */
    return nil;
}
- (NSEnumerator *)keyEnumerator { return [[NSArray arrayWithObjects:dkeys(self) count:dcount(self)] objectEnumerator]; }
- (NSArray *)allKeys { return [NSArray arrayWithObjects:dkeys(self) count:dcount(self)]; }
- (NSArray *)allValues { return [NSArray arrayWithObjects:dobjs(self) count:dcount(self)]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)b count:(NSUInteger)n {
    if (s->state) return 0;
    s->state = 1; s->itemsPtr = (id *)dkeys(self); s->mutationsPtr = &s->extra[0];
    return dcount(self);
}
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableDictionary alloc] initWithDictionary:self]; }
@end

/* @[] in recent clang: the empty array is a static object in Foundation */
struct { void *isa; NSUInteger count; const id *objects; } __NSArray0__struct;
@implementation NSConstantArray (MWEmpty)
+ (void)load { object_setClass((id)(void *)&__NSArray0__struct, [NSConstantArray class]); }
@end
