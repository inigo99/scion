/* scion SDK — clean-room Foundation subset. Declares exactly what scion's Foundation.dylib implements.
 * Apps built with Apple's SDK do not need this header; it is for code compiled against scion itself. */
#pragma once
#import <objc/NSObject.h>
#import <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h> /* CGFloat and the CG geometry types (NSPoint is CGPoint) */
#include <stdarg.h>
#include <stdint.h>
#if !defined(MW_FOUNDATION_INTERNAL) && __has_include(<libkern/OSByteOrder.h>)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <limits.h>
#include <math.h>
#include <stdbool.h>
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <locale.h>
#include <setjmp.h>
#include <signal.h>
#include <stddef.h>
#include <time.h>
#include <sys/types.h> /* what CoreFoundation.h brings in */
#include <libkern/OSByteOrder.h>
#include <mach/mach.h>
#include <dispatch/dispatch.h>
#endif

#define NS_FORMAT_FUNCTION(F, A) __attribute__((format(__NSString__, F, A)))
/* the usual Foundation/ObjC macros, as Apple defines them (the attributes tell Swift how to import the declarations) */
#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum __attribute__((enum_extensibility(open))) _name : _type _name; \
    enum __attribute__((enum_extensibility(open))) _name : _type
#define NS_OPTIONS(_type, _name) enum __attribute__((enum_extensibility(open), flag_enum)) _name : _type _name; \
    enum __attribute__((enum_extensibility(open), flag_enum)) _name : _type
#define NS_CLOSED_ENUM(_type, _name) enum __attribute__((enum_extensibility(closed))) _name : _type _name; \
    enum __attribute__((enum_extensibility(closed))) _name : _type
#define NS_ERROR_ENUM(_domain, _name) enum __attribute__((ns_error_domain(_domain))) _name : NSInteger _name; \
    enum __attribute__((ns_error_domain(_domain))) _name : NSInteger
#define NS_TYPED_ENUM __attribute__((swift_wrapper(struct)))
#define NS_TYPED_EXTENSIBLE_ENUM __attribute__((swift_wrapper(struct)))
#define NS_STRING_ENUM NS_TYPED_ENUM
#define NS_EXTENSIBLE_STRING_ENUM NS_TYPED_EXTENSIBLE_ENUM
#endif
#define NS_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#define NS_ASSUME_NONNULL_END _Pragma("clang assume_nonnull end")
#define NS_SWIFT_NAME(x) __attribute__((swift_name(#x)))
#define NS_SWIFT_UNAVAILABLE(msg) __attribute__((availability(swift, unavailable, message = msg)))
#define NS_REFINED_FOR_SWIFT __attribute__((swift_private))
#define NS_SWIFT_SENDABLE
#define NS_SWIFT_NOTHROW __attribute__((swift_error(none)))
#define NS_SWIFT_BRIDGE(t) __attribute__((swift_bridge(#t))) /* Swift: the value type it bridges to */
#define NS_SWIFT_BRIDGED_TYPEDEF __attribute__((swift_bridged_typedef))
#define NS_RELEASES_ARGUMENT __attribute__((ns_consumed))
#define NS_SWIFT_RETURNS_INTERNAL_REFERENCE
#define NS_HEADER_AUDIT_BEGIN(...) NS_ASSUME_NONNULL_BEGIN
#define NS_HEADER_AUDIT_END(...) NS_ASSUME_NONNULL_END
#define NS_DESIGNATED_INITIALIZER __attribute__((objc_designated_initializer))
#define NS_UNAVAILABLE __attribute__((unavailable))
#define NS_RETURNS_RETAINED __attribute__((ns_returns_retained))
#define NS_RETURNS_NOT_RETAINED __attribute__((ns_returns_not_retained))
#define NS_REQUIRES_NIL_TERMINATION __attribute__((sentinel(0, 1)))
#define NS_NOESCAPE __attribute__((noescape))
#define NS_INLINE static inline __attribute__((always_inline))
#define NS_ROOT_CLASS __attribute__((objc_root_class))
#define NS_REQUIRES_SUPER __attribute__((objc_requires_super))
#define NS_AUTOMATED_REFCOUNT_UNAVAILABLE
#define FOUNDATION_EXPORT extern
#define FOUNDATION_EXTERN extern
#define NS_AVAILABLE(...)
#define NS_AVAILABLE_MAC(...)
#define NS_AVAILABLE_IOS(...)
#define NS_DEPRECATED(...)
#define NS_DEPRECATED_MAC(...)
#ifndef API_AVAILABLE
#define API_AVAILABLE(...)
#define API_UNAVAILABLE(...)
#define API_DEPRECATED(...)
#define API_DEPRECATED_WITH_REPLACEMENT(...)
#define API_TO_BE_DEPRECATED
#endif
#define NSIntegerMax LONG_MAX
#define NSIntegerMin (-NSIntegerMax - 1)
#define NSUIntegerMax (~(NSUInteger)0)
#ifndef LONG_MAX
#define LONG_MAX 9223372036854775807L
#endif
enum { NSNotFound = 9223372036854775807L };
typedef double NSTimeInterval NS_SWIFT_NAME(TimeInterval);
typedef NSUInteger NSStringEncoding;
enum { NSASCIIStringEncoding = 1, NSUTF8StringEncoding = 4, NSISOLatin1StringEncoding = 5, NSUTF16StringEncoding = 10, NSUTF16LittleEndianStringEncoding = 0x94000100,
    NSNEXTSTEPStringEncoding = 2, NSJapaneseEUCStringEncoding = 3, NSSymbolStringEncoding = 6, NSNonLossyASCIIStringEncoding = 7, NSShiftJISStringEncoding = 8,
    NSISOLatin2StringEncoding = 9, NSUnicodeStringEncoding = 10, NSWindowsCP1251StringEncoding = 11, NSWindowsCP1252StringEncoding = 12,
    NSWindowsCP1253StringEncoding = 13, NSWindowsCP1254StringEncoding = 14, NSWindowsCP1250StringEncoding = 15, NSISO2022JPStringEncoding = 21,
    NSMacOSRomanStringEncoding = 30, NSUTF16BigEndianStringEncoding = 0x90000100, NSUTF32StringEncoding = 0x8c000100,
    NSUTF32BigEndianStringEncoding = 0x98000100, NSUTF32LittleEndianStringEncoding = 0x9c000100 };
typedef NS_OPTIONS(NSUInteger, NSStringCompareOptions) {
    NSCaseInsensitiveSearch NS_SWIFT_NAME(caseInsensitive) = 1, NSLiteralSearch NS_SWIFT_NAME(literal) = 2, NSBackwardsSearch NS_SWIFT_NAME(backwards) = 4, NSAnchoredSearch NS_SWIFT_NAME(anchored) = 8, NSNumericSearch NS_SWIFT_NAME(numeric) = 64,
    NSDiacriticInsensitiveSearch NS_SWIFT_NAME(diacriticInsensitive) = 128, NSWidthInsensitiveSearch NS_SWIFT_NAME(widthInsensitive) = 256, NSForcedOrderingSearch NS_SWIFT_NAME(forcedOrdering) = 512, NSRegularExpressionSearch NS_SWIFT_NAME(regularExpression) = 1024,
} NS_SWIFT_NAME(NSString.CompareOptions);
typedef NS_CLOSED_ENUM(NSInteger, NSComparisonResult) { NSOrderedAscending = -1L, NSOrderedSame, NSOrderedDescending } NS_SWIFT_NAME(ComparisonResult);
typedef NSComparisonResult (^NSComparator)(id a, id b);
typedef struct _NSRange { NSUInteger location, length; } NSRange;
static inline NSRange NSMakeRange(NSUInteger l, NSUInteger n) { NSRange r = {l, n}; return r; }
static inline NSUInteger NSMaxRange(NSRange r) { return r.location + r.length; }
static inline BOOL NSLocationInRange(NSUInteger l, NSRange r) { return l >= r.location && l - r.location < r.length; }
typedef CGPoint NSPoint;
typedef CGSize NSSize;
typedef CGRect NSRect;
static inline NSPoint NSMakePoint(CGFloat x, CGFloat y) { NSPoint p = {x, y}; return p; }
static inline NSSize NSMakeSize(CGFloat w, CGFloat h) { NSSize s = {w, h}; return s; }
static inline NSRect NSMakeRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { NSRect r = {{x, y}, {w, h}}; return r; }
typedef unsigned short unichar;
/* NSGeometry (inline parts) */
typedef struct NSEdgeInsets { CGFloat top, left, bottom, right; } NSEdgeInsets;
static inline NSEdgeInsets NSEdgeInsetsMake(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { NSEdgeInsets e = {t, l, b, r}; return e; }
static inline CGFloat NSMinX(NSRect r) { return r.origin.x; } static inline CGFloat NSMinY(NSRect r) { return r.origin.y; }
static inline CGFloat NSMaxX(NSRect r) { return r.origin.x + r.size.width; } static inline CGFloat NSMaxY(NSRect r) { return r.origin.y + r.size.height; }
static inline CGFloat NSMidX(NSRect r) { return r.origin.x + r.size.width / 2; } static inline CGFloat NSMidY(NSRect r) { return r.origin.y + r.size.height / 2; }
static inline CGFloat NSWidth(NSRect r) { return r.size.width; } static inline CGFloat NSHeight(NSRect r) { return r.size.height; }
static inline NSRect NSRectFromCGRect(CGRect r) { return r; } static inline CGRect NSRectToCGRect(NSRect r) { return r; }
static inline NSSize NSSizeFromCGSize(CGSize s) { return s; } static inline CGSize NSSizeToCGSize(NSSize s) { return s; }
static inline NSPoint NSPointFromCGPoint(CGPoint p) { return p; } static inline CGPoint NSPointToCGPoint(NSPoint p) { return p; }
typedef enum { NSMinXEdge = 0, NSMinYEdge = 1, NSMaxXEdge = 2, NSMaxYEdge = 3 } NSRectEdge;
typedef unsigned long long NSAlignmentOptions;

NS_ASSUME_NONNULL_BEGIN
@class NSString, NSData, NSError, NSCharacterSet, NSDate, NSCoder;
@class NSArray<ObjectType>, NSDictionary<KeyType, ObjectType>, NSSet<ObjectType>, NSEnumerator<ObjectType>;
typedef NSString *NSErrorDomain NS_SWIFT_BRIDGED_TYPEDEF;
typedef NSString *NSErrorUserInfoKey NS_SWIFT_BRIDGED_TYPEDEF;
typedef NSRange *NSRangePointer;

@protocol NSCopying - (id)copyWithZone:(nullable NSZone *)z; @end
@protocol NSMutableCopying - (id)mutableCopyWithZone:(nullable NSZone *)z; @end
typedef struct { unsigned long state; __unsafe_unretained id *itemsPtr; unsigned long *mutationsPtr; unsigned long extra[5]; } NSFastEnumerationState;
@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id __unsafe_unretained _Nullable [_Nonnull])b count:(NSUInteger)n;
@end

@interface NSObject (Foundation)
+ (NSString *)description; - (NSString *)debugDescription;
- (nullable id)valueForKey:(NSString *)k; - (void)setValue:(nullable id)v forKey:(NSString *)k;
@end

NS_SWIFT_BRIDGE(Swift.String)
@interface NSString : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)string;
+ (instancetype)stringWithString:(NSString *)s;
+ (nullable instancetype)stringWithUTF8String:(const char *)s;
+ (nullable instancetype)stringWithCString:(const char *)s encoding:(NSStringEncoding)e;
+ (instancetype)stringWithCharacters:(const unichar *)c length:(NSUInteger)n;
+ (instancetype)stringWithFormat:(NSString *)f, ... NS_FORMAT_FUNCTION(1, 2);
+ (nullable instancetype)stringWithContentsOfFile:(NSString *)p encoding:(NSStringEncoding)e error:(NSError **)err;
- (nullable instancetype)initWithUTF8String:(const char *)s;
- (instancetype)initWithString:(NSString *)s;
- (instancetype)initWithCharacters:(const unichar *)c length:(NSUInteger)n;
- (nullable instancetype)initWithBytes:(const void *)b length:(NSUInteger)n encoding:(NSStringEncoding)e;
- (nullable instancetype)initWithData:(NSData *)d encoding:(NSStringEncoding)e;
- (instancetype)initWithFormat:(NSString *)f, ... NS_FORMAT_FUNCTION(1, 2);
- (instancetype)initWithFormat:(NSString *)f arguments:(va_list)ap;
@property (readonly) NSUInteger length;
- (unichar)characterAtIndex:(NSUInteger)i;
- (void)getCharacters:(unichar *)buf range:(NSRange)r;
@property (nullable, readonly) const char *UTF8String;
- (nullable const char *)cStringUsingEncoding:(NSStringEncoding)e NS_SWIFT_NAME(cString(using:));
- (BOOL)getCString:(char *)buf maxLength:(NSUInteger)n encoding:(NSStringEncoding)e NS_SWIFT_NAME(getCString(_:maxLength:encoding:));
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)e NS_SWIFT_NAME(lengthOfBytes(using:));
- (nullable NSData *)dataUsingEncoding:(NSStringEncoding)e NS_SWIFT_NAME(data(using:));
- (BOOL)isEqualToString:(NSString *)s;
- (NSComparisonResult)compare:(NSString *)s;
- (NSComparisonResult)compare:(NSString *)s options:(NSStringCompareOptions)o;
- (NSComparisonResult)caseInsensitiveCompare:(NSString *)s;
- (BOOL)hasPrefix:(NSString *)s; - (BOOL)hasSuffix:(NSString *)s; - (BOOL)containsString:(NSString *)s;
- (NSRange)rangeOfString:(NSString *)s;
- (NSRange)rangeOfString:(NSString *)s options:(NSStringCompareOptions)o;
- (NSRange)rangeOfString:(NSString *)s options:(NSStringCompareOptions)o range:(NSRange)r;
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set;
- (NSString *)substringFromIndex:(NSUInteger)i; - (NSString *)substringToIndex:(NSUInteger)i; - (NSString *)substringWithRange:(NSRange)r;
- (NSString *)stringByAppendingString:(NSString *)s;
- (NSString *)stringByAppendingFormat:(NSString *)f, ... NS_FORMAT_FUNCTION(1, 2);
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)a withString:(NSString *)b;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)a withString:(NSString *)b options:(NSStringCompareOptions)o range:(NSRange)r;
- (NSString *)stringByReplacingCharactersInRange:(NSRange)r withString:(NSString *)s;
- (NSString *)stringByPaddingToLength:(NSUInteger)len withString:(NSString *)pad startingAtIndex:(NSUInteger)i NS_SWIFT_NAME(padding(toLength:withPad:startingAt:));
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set;
- (NSArray<NSString *> *)componentsSeparatedByString:(NSString *)sep NS_SWIFT_NAME(components(separatedBy:));
- (NSArray<NSString *> *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)set NS_SWIFT_NAME(components(separatedBy:));
@property (readonly, copy) NSString *lowercaseString, *uppercaseString, *capitalizedString;
@property (readonly) int intValue; @property (readonly) NSInteger integerValue; @property (readonly) long long longLongValue;
@property (readonly) double doubleValue; @property (readonly) float floatValue; @property (readonly) BOOL boolValue;
- (NSString *)stringByAppendingPathComponent:(NSString *)c;
- (NSString *)stringByAppendingPathExtension:(NSString *)e;
@property (readonly, copy) NSString *lastPathComponent, *stringByDeletingLastPathComponent, *pathExtension, *stringByDeletingPathExtension, *stringByExpandingTildeInPath, *stringByStandardizingPath;
@property (readonly, copy) NSArray *pathComponents;
@property (readonly) BOOL isAbsolutePath;
@property (readonly) const char *fileSystemRepresentation;
- (BOOL)writeToFile:(NSString *)p atomically:(BOOL)a encoding:(NSStringEncoding)e error:(NSError **)err;
- (void)enumerateLinesUsingBlock:(void (^)(NSString *line, BOOL *stop))b;
@end

@interface NSMutableString : NSString
+ (instancetype)stringWithCapacity:(NSUInteger)n;
- (instancetype)initWithCapacity:(NSUInteger)n;
- (void)appendString:(NSString *)s;
- (void)appendFormat:(NSString *)f, ... NS_FORMAT_FUNCTION(1, 2);
- (void)insertString:(NSString *)s atIndex:(NSUInteger)i;
- (void)deleteCharactersInRange:(NSRange)r;
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s;
- (void)setString:(NSString *)s;
- (NSUInteger)replaceOccurrencesOfString:(NSString *)a withString:(NSString *)b options:(NSStringCompareOptions)o range:(NSRange)r;
@end

NS_SWIFT_BRIDGE(CharacterSet)
@interface NSCharacterSet : NSObject <NSCopying>
+ (NSCharacterSet *)whitespaceCharacterSet; + (NSCharacterSet *)whitespaceAndNewlineCharacterSet; + (NSCharacterSet *)newlineCharacterSet;
+ (NSCharacterSet *)decimalDigitCharacterSet; + (NSCharacterSet *)letterCharacterSet; + (NSCharacterSet *)alphanumericCharacterSet;
+ (NSCharacterSet *)punctuationCharacterSet; + (NSCharacterSet *)uppercaseLetterCharacterSet; + (NSCharacterSet *)lowercaseLetterCharacterSet;
+ (NSCharacterSet *)characterSetWithCharactersInString:(NSString *)s;
- (BOOL)characterIsMember:(unichar)c;
@property (readonly, copy) NSCharacterSet *invertedSet;
@end

@interface NSValue : NSObject <NSCopying>
+ (NSValue *)valueWithRange:(NSRange)r; + (NSValue *)valueWithPointer:(const void *)p;
+ (NSValue *)valueWithBytes:(const void *)v objCType:(const char *)t; - (void)getValue:(void *)v;
+ (NSValue *)valueWithPoint:(NSPoint)p; + (NSValue *)valueWithSize:(NSSize)s; + (NSValue *)valueWithRect:(NSRect)r;
@property (readonly) NSRange rangeValue; @property (nullable, readonly) void *pointerValue;
@property (readonly) NSPoint pointValue; @property (readonly) NSSize sizeValue; @property (readonly) NSRect rectValue;
@end

@interface NSNumber : NSValue
+ (NSNumber *)numberWithBool:(BOOL)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)"); + (NSNumber *)numberWithChar:(char)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)"); + (NSNumber *)numberWithUnsignedChar:(unsigned char)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)");
+ (NSNumber *)numberWithShort:(short)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)"); + (NSNumber *)numberWithUnsignedShort:(unsigned short)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)");
+ (NSNumber *)numberWithInt:(int)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)"); + (NSNumber *)numberWithUnsignedInt:(unsigned)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)");
+ (NSNumber *)numberWithLong:(long)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)"); + (NSNumber *)numberWithUnsignedLong:(unsigned long)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)");
+ (NSNumber *)numberWithLongLong:(long long)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)"); + (NSNumber *)numberWithUnsignedLongLong:(unsigned long long)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)");
+ (NSNumber *)numberWithInteger:(NSInteger)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)"); + (NSNumber *)numberWithUnsignedInteger:(NSUInteger)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)");
+ (NSNumber *)numberWithFloat:(float)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)"); + (NSNumber *)numberWithDouble:(double)v NS_SWIFT_UNAVAILABLE("Use NSNumber(value:)");
- (instancetype)initWithInt:(int)v NS_SWIFT_NAME(init(value:)); - (instancetype)initWithInteger:(NSInteger)v NS_SWIFT_NAME(init(value:)); - (instancetype)initWithDouble:(double)v NS_SWIFT_NAME(init(value:)); - (instancetype)initWithBool:(BOOL)v NS_SWIFT_NAME(init(value:));
@property (readonly) BOOL boolValue; @property (readonly) char charValue NS_SWIFT_NAME(int8Value); @property (readonly) unsigned char unsignedCharValue NS_SWIFT_NAME(uint8Value);
@property (readonly) short shortValue NS_SWIFT_NAME(int16Value); @property (readonly) unsigned short unsignedShortValue NS_SWIFT_NAME(uint16Value);
@property (readonly) int intValue NS_SWIFT_NAME(int32Value); @property (readonly) unsigned unsignedIntValue NS_SWIFT_NAME(uint32Value);
@property (readonly) long longValue; @property (readonly) unsigned long unsignedLongValue;
@property (readonly) long long longLongValue NS_SWIFT_NAME(int64Value); @property (readonly) unsigned long long unsignedLongLongValue NS_SWIFT_NAME(uint64Value);
@property (readonly) NSInteger integerValue NS_SWIFT_NAME(intValue); @property (readonly) NSUInteger unsignedIntegerValue NS_SWIFT_NAME(uintValue);
@property (readonly) float floatValue; @property (readonly) double doubleValue;
@property (readonly, copy) NSString *stringValue;
@property (readonly) const char *objCType;
- (NSComparisonResult)compare:(NSNumber *)n;
- (BOOL)isEqualToNumber:(NSNumber *)n;
@end

@interface NSEnumerator<ObjectType> : NSObject <NSFastEnumeration>
- (nullable ObjectType)nextObject;
@property (readonly, copy) NSArray *allObjects;
@end

NS_SWIFT_BRIDGE(Swift.Array)
@interface NSArray<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration>
+ (instancetype)array; + (instancetype)arrayWithObject:(id)o; + (instancetype)arrayWithObjects:(id)first, ... __attribute__((sentinel));
+ (instancetype)arrayWithObjects:(const id [])objs count:(NSUInteger)n; + (instancetype)arrayWithArray:(NSArray *)a;
- (instancetype)initWithObjects:(const id [])objs count:(NSUInteger)n; - (instancetype)initWithArray:(NSArray *)a;
- (instancetype)initWithObjects:(id)first, ... __attribute__((sentinel));
@property (readonly) NSUInteger count;
- (ObjectType)objectAtIndex:(NSUInteger)i; - (ObjectType)objectAtIndexedSubscript:(NSUInteger)i;
@property (nullable, readonly) ObjectType firstObject, lastObject;
- (BOOL)containsObject:(id)o; - (NSUInteger)indexOfObject:(id)o; - (NSUInteger)indexOfObjectIdenticalTo:(id)o;
- (NSUInteger)indexOfObjectPassingTest:(BOOL (^)(id o, NSUInteger i, BOOL *stop))t;
- (NSArray *)arrayByAddingObject:(id)o; - (NSArray *)arrayByAddingObjectsFromArray:(NSArray *)a;
- (NSString *)componentsJoinedByString:(NSString *)sep;
- (NSArray *)subarrayWithRange:(NSRange)r;
- (void)enumerateObjectsUsingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))b;
- (NSArray *)sortedArrayUsingSelector:(SEL)s; - (NSArray *)sortedArrayUsingComparator:(NSComparator)c;
- (NSEnumerator *)objectEnumerator; - (NSEnumerator *)reverseObjectEnumerator;
- (BOOL)isEqualToArray:(NSArray *)a;
- (void)makeObjectsPerformSelector:(SEL)s;
@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
+ (instancetype)arrayWithCapacity:(NSUInteger)n; - (instancetype)initWithCapacity:(NSUInteger)n;
- (void)addObject:(ObjectType)o; - (void)addObjectsFromArray:(NSArray<ObjectType> *)a; - (void)insertObject:(ObjectType)o atIndex:(NSUInteger)i;
- (void)removeObjectAtIndex:(NSUInteger)i; - (void)removeLastObject; - (void)removeAllObjects; - (void)removeObject:(id)o;
- (void)removeObjectsInRange:(NSRange)r; - (void)replaceObjectsInRange:(NSRange)r withObjectsFromArray:(NSArray *)a; - (void)removeObjectIdenticalTo:(id)o; - (void)removeObjectsInArray:(NSArray *)a; - (void)setArray:(NSArray *)a;
- (void)replaceObjectAtIndex:(NSUInteger)i withObject:(nullable id)o; - (void)setObject:(id)o atIndexedSubscript:(NSUInteger)i;
- (void)exchangeObjectAtIndex:(NSUInteger)a withObjectAtIndex:(NSUInteger)b;
- (void)sortUsingSelector:(SEL)s; - (void)sortUsingComparator:(NSComparator)c;
@end

NS_SWIFT_BRIDGE(Swift.Dictionary)
@interface NSDictionary<__covariant KeyType, __covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration>
+ (instancetype)dictionary; + (instancetype)dictionaryWithObject:(id)o forKey:(id)k;
+ (instancetype)dictionaryWithObjects:(const id [])o forKeys:(const id [])k count:(NSUInteger)n;
+ (instancetype)dictionaryWithObjectsAndKeys:(id)first, ... __attribute__((sentinel));
+ (instancetype)dictionaryWithDictionary:(NSDictionary *)d;
- (instancetype)initWithObjects:(const ObjectType _Nonnull [_Nullable])o forKeys:(const KeyType <NSCopying> _Nonnull [_Nullable])k count:(NSUInteger)n;
- (instancetype)initWithDictionary:(NSDictionary *)d;
- (NSArray<KeyType> *)keysSortedByValueUsingComparator:(NSComparator)c;
@property (readonly) NSUInteger count;
- (nullable ObjectType)objectForKey:(KeyType)k; - (nullable ObjectType)objectForKeyedSubscript:(KeyType)k;
@property (readonly, copy) NSArray<KeyType> *allKeys; @property (readonly, copy) NSArray<ObjectType> *allValues;
- (NSEnumerator *)keyEnumerator; - (NSEnumerator *)objectEnumerator;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))b;
- (BOOL)isEqualToDictionary:(NSDictionary *)d;
@end

@interface NSMutableDictionary<KeyType, ObjectType> : NSDictionary<KeyType, ObjectType>
+ (instancetype)dictionaryWithCapacity:(NSUInteger)n; - (instancetype)initWithCapacity:(NSUInteger)n;
- (void)setObject:(ObjectType)o forKey:(KeyType)k; - (void)setObject:(ObjectType)o forKeyedSubscript:(KeyType)k;
- (void)removeObjectForKey:(id)k; - (void)removeAllObjects; - (void)addEntriesFromDictionary:(NSDictionary *)d; - (void)setDictionary:(NSDictionary *)d;
- (void)removeObjectsForKeys:(NSArray *)keys;
@end

NS_SWIFT_BRIDGE(Swift.Set)
@interface NSSet<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration>
+ (instancetype)set; + (instancetype)setWithArray:(NSArray *)a; + (instancetype)setWithObject:(id)o;
+ (instancetype)setWithObjects:(id)first, ... __attribute__((sentinel));
- (instancetype)initWithArray:(NSArray *)a;
@property (readonly) NSUInteger count;
- (nullable id)member:(id)o; - (BOOL)containsObject:(id)o;
@property (readonly, copy) NSArray *allObjects; @property (nullable, readonly) id anyObject;
- (NSEnumerator *)objectEnumerator;
+ (instancetype)setWithSet:(NSSet *)s;
- (void)enumerateObjectsUsingBlock:(void (^)(ObjectType o, BOOL *stop))b;
- (BOOL)isSubsetOfSet:(NSSet *)s; - (BOOL)intersectsSet:(NSSet *)s; - (BOOL)isEqualToSet:(NSSet *)s;
- (NSSet *)setByAddingObject:(id)o;
@end
@interface NSMutableSet<ObjectType> : NSSet<ObjectType>
+ (instancetype)setWithCapacity:(NSUInteger)n; - (instancetype)initWithCapacity:(NSUInteger)n;
- (void)addObject:(id)o; - (void)removeObject:(id)o; - (void)removeAllObjects; - (void)addObjectsFromArray:(NSArray *)a;
- (void)unionSet:(NSSet *)s; - (void)minusSet:(NSSet *)s; - (void)intersectSet:(NSSet *)s;
@end
/* NSOrderedSet: an array without duplicates (ponytail: linear membership tests) */
@interface NSOrderedSet<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration>
+ (instancetype)orderedSet; + (instancetype)orderedSetWithArray:(NSArray<ObjectType> *)a; + (instancetype)orderedSetWithObject:(ObjectType)o;
- (instancetype)initWithArray:(NSArray<ObjectType> *)a;
@property (readonly) NSUInteger count;
- (ObjectType)objectAtIndex:(NSUInteger)i; - (ObjectType)objectAtIndexedSubscript:(NSUInteger)i;
- (NSUInteger)indexOfObject:(ObjectType)o; - (BOOL)containsObject:(ObjectType)o;
@property (readonly) ObjectType firstObject; @property (readonly) ObjectType lastObject;
@property (readonly, copy) NSArray<ObjectType> *array;
- (NSEnumerator *)objectEnumerator;
@end
@interface NSMutableOrderedSet<ObjectType> : NSOrderedSet<ObjectType>
+ (instancetype)orderedSetWithCapacity:(NSUInteger)n;
- (void)addObject:(ObjectType)o; - (void)addObjectsFromArray:(NSArray<ObjectType> *)a; - (void)insertObject:(ObjectType)o atIndex:(NSUInteger)i;
- (void)removeObject:(ObjectType)o; - (void)removeObjectAtIndex:(NSUInteger)i; - (void)removeAllObjects;
@end

@interface NSNull : NSObject <NSCopying> + (NSNull *)null; @end
/* NSAttributedString: ponytail: one set of attributes for the whole string (what labels and drawing code use) */
typedef NSString *NSAttributedStringKey NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSAttributedString.Key);
@interface NSAttributedString : NSObject <NSCopying, NSMutableCopying>
- (instancetype)initWithString:(NSString *)s;
- (instancetype)initWithString:(NSString *)s attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)a;
- (instancetype)initWithAttributedString:(NSAttributedString *)s;
@property(readonly, copy) NSString *string;
@property(readonly) NSUInteger length;
- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)i effectiveRange:(nullable NSRangePointer)r;
- (nullable id)attribute:(NSAttributedStringKey)name atIndex:(NSUInteger)i effectiveRange:(nullable NSRangePointer)r;
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)r;
- (void)enumerateAttributesInRange:(NSRange)r options:(NSUInteger)o usingBlock:(void (^)(NSDictionary<NSAttributedStringKey, id> *a, NSRange r, BOOL *stop))b;
@end
@interface NSMutableAttributedString : NSAttributedString
- (void)appendAttributedString:(NSAttributedString *)s;
- (void)addAttribute:(NSAttributedStringKey)name value:(id)v range:(NSRange)r;
- (void)addAttributes:(NSDictionary<NSAttributedStringKey, id> *)a range:(NSRange)r;
- (void)setAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)a range:(NSRange)r;
- (void)removeAttribute:(NSAttributedStringKey)name range:(NSRange)r;
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s;
- (void)replaceCharactersInRange:(NSRange)r withAttributedString:(NSAttributedString *)s;
- (void)insertAttributedString:(NSAttributedString *)s atIndex:(NSUInteger)i; - (void)deleteCharactersInRange:(NSRange)r;
- (void)setAttributedString:(NSAttributedString *)s;
- (void)beginEditing; - (void)endEditing;
@property(readonly, retain) NSMutableString *mutableString;
@end

NS_SWIFT_BRIDGE(Data)
@interface NSData : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)data; + (instancetype)dataWithBytes:(nullable const void *)b length:(NSUInteger)n;
+ (instancetype)dataWithBytesNoCopy:(void *)b length:(NSUInteger)n; + (instancetype)dataWithBytesNoCopy:(void *)b length:(NSUInteger)n freeWhenDone:(BOOL)f;
+ (nullable instancetype)dataWithContentsOfFile:(NSString *)p; + (instancetype)dataWithData:(NSData *)d;
- (instancetype)initWithBytes:(nullable const void *)b length:(NSUInteger)n; - (nullable instancetype)initWithContentsOfFile:(NSString *)p;
@property (readonly) const void *bytes; @property (readonly) NSUInteger length;
- (void)getBytes:(void *)buf length:(NSUInteger)n; - (void)getBytes:(void *)buf range:(NSRange)r;
- (BOOL)isEqualToData:(NSData *)d; - (NSData *)subdataWithRange:(NSRange)r;
- (BOOL)writeToFile:(NSString *)p atomically:(BOOL)a;
- (BOOL)writeToFile:(NSString *)p options:(NSUInteger)o error:(NSError **)e;
@end
@interface NSMutableData : NSData
+ (instancetype)dataWithCapacity:(NSUInteger)n; + (instancetype)dataWithLength:(NSUInteger)n;
@property (readonly) void *mutableBytes; @property NSUInteger length;
- (void)appendBytes:(const void *)b length:(NSUInteger)n; - (void)appendData:(NSData *)d; - (void)increaseLengthBy:(NSUInteger)n;
- (void)replaceBytesInRange:(NSRange)r withBytes:(const void *)b; - (void)resetBytesInRange:(NSRange)r;
@end

extern NSString *const NSPOSIXErrorDomain, *const NSCocoaErrorDomain, *const NSLocalizedDescriptionKey, *const NSFilePathErrorKey;
enum { NSFileNoSuchFileError = 4, NSFileLockingError = 255, NSFileReadUnknownError = 256, NSFileReadNoPermissionError = 257, NSFileReadInvalidFileNameError = 258,
    NSFileReadCorruptFileError = 259, NSFileReadNoSuchFileError = 260, NSFileReadInapplicableStringEncodingError = 261, NSFileReadUnsupportedSchemeError = 262,
    NSFileReadTooLargeError = 263, NSFileWriteUnknownError = 512, NSFileWriteNoPermissionError = 513, NSFileWriteInvalidFileNameError = 514,
    NSFileWriteFileExistsError = 516, NSFileWriteOutOfSpaceError = 640, NSUserCancelledError = 3072, NSFeatureUnsupportedError = 3328 };
@interface NSError : NSObject <NSCopying>
+ (instancetype)errorWithDomain:(NSErrorDomain)d code:(NSInteger)c userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)u;
- (instancetype)initWithDomain:(NSErrorDomain)d code:(NSInteger)c userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)u;
@property (readonly, copy) NSErrorDomain domain; @property (readonly) NSInteger code;
@property (readonly, copy) NSDictionary<NSErrorUserInfoKey, id> *userInfo;
@property (readonly, copy) NSString *localizedDescription;
@end

@class NSRegularExpression;
@interface NSTextCheckingResult : NSObject <NSCopying>
@property (readonly) NSRange range; @property (readonly) NSUInteger numberOfRanges;
- (NSRange)rangeAtIndex:(NSUInteger)i; - (NSRange)rangeWithName:(NSString *)name;
@property (nullable, readonly) NSRegularExpression *regularExpression;
- (NSTextCheckingResult *)resultByAdjustingRangesWithOffset:(NSInteger)offset;
@end
typedef NSUInteger NSRegularExpressionOptions;
enum { NSRegularExpressionCaseInsensitive = 1, NSRegularExpressionAllowCommentsAndWhitespace = 2, NSRegularExpressionIgnoreMetacharacters = 4,
       NSRegularExpressionDotMatchesLineSeparators = 8, NSRegularExpressionAnchorsMatchLines = 16, NSRegularExpressionUseUnixLineSeparators = 32,
       NSRegularExpressionUseUnicodeWordBoundaries = 64 };
typedef NSUInteger NSMatchingOptions;
enum { NSMatchingReportProgress = 1, NSMatchingReportCompletion = 2, NSMatchingAnchored = 4, NSMatchingWithTransparentBounds = 8, NSMatchingWithoutAnchoringBounds = 16 };
typedef NSUInteger NSMatchingFlags;
enum { NSMatchingProgress = 1, NSMatchingCompleted = 2, NSMatchingHitEnd = 4, NSMatchingRequiredEnd = 8, NSMatchingInternalError = 16 };
@interface NSRegularExpression : NSObject <NSCopying>
+ (nullable NSRegularExpression *)regularExpressionWithPattern:(NSString *)p options:(NSRegularExpressionOptions)o error:(NSError **)e;
- (nullable instancetype)initWithPattern:(NSString *)p options:(NSRegularExpressionOptions)o error:(NSError **)e;
@property (readonly, copy) NSString *pattern; @property (readonly) NSRegularExpressionOptions options; @property (readonly) NSUInteger numberOfCaptureGroups;
- (void)enumerateMatchesInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r usingBlock:(void (^)(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop))b;
- (NSArray *)matchesInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r;
- (NSUInteger)numberOfMatchesInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r;
- (nullable NSTextCheckingResult *)firstMatchInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r;
- (NSRange)rangeOfFirstMatchInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r;
- (NSString *)stringByReplacingMatchesInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r withTemplate:(NSString *)t;
- (NSUInteger)replaceMatchesInString:(NSMutableString *)s options:(NSMatchingOptions)o range:(NSRange)r withTemplate:(NSString *)t;
- (NSString *)replacementStringForResult:(NSTextCheckingResult *)res inString:(NSString *)s offset:(NSInteger)off template:(NSString *)t;
+ (NSString *)escapedPatternForString:(NSString *)s; + (NSString *)escapedTemplateForString:(NSString *)s;
@end

extern NSString *const NSGenericException, *const NSRangeException, *const NSInvalidArgumentException,
    *const NSInternalInconsistencyException, *const NSMallocException, *const NSUndefinedKeyException;
__attribute__((objc_exception))
@interface NSException : NSObject <NSCopying>
+ (NSException *)exceptionWithName:(NSString *)n reason:(nullable NSString *)r userInfo:(nullable NSDictionary *)u;
- (instancetype)initWithName:(NSString *)n reason:(nullable NSString *)r userInfo:(nullable NSDictionary *)u;
+ (void)raise:(NSString *)n format:(NSString *)f, ... NS_FORMAT_FUNCTION(2, 3);
+ (void)raise:(NSString *)n format:(NSString *)f arguments:(va_list)ap;
- (void)raise;
@property (readonly, copy) NSString *name; @property (nullable, readonly, copy) NSString *reason; @property (nullable, readonly, copy) NSDictionary *userInfo;
@property (readonly, copy) NSArray *callStackSymbols, *callStackReturnAddresses;
@end
typedef void NSUncaughtExceptionHandler(NSException *exception);
void NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *h);
NSUncaughtExceptionHandler *NSGetUncaughtExceptionHandler(void);

@interface NSAssertionHandler : NSObject
+ (NSAssertionHandler *)currentHandler;
- (void)handleFailureInMethod:(SEL)s object:(nullable id)o file:(NSString *)f lineNumber:(NSInteger)l description:(NSString *)d, ... NS_FORMAT_FUNCTION(5, 6);
- (void)handleFailureInFunction:(NSString *)fn file:(NSString *)f lineNumber:(NSInteger)l description:(NSString *)d, ... NS_FORMAT_FUNCTION(4, 5);
@end
#ifdef NS_BLOCK_ASSERTIONS
#define NSAssert(c, desc, ...) do {} while (0)
#define NSCAssert(c, desc, ...) do {} while (0)
#else
#define NSAssert(c, desc, ...) do { if (__builtin_expect(!(c), 0)) [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd \
    object:self file:[NSString stringWithUTF8String:__FILE__] lineNumber:__LINE__ description:(desc), ##__VA_ARGS__]; } while (0)
#define NSCAssert(c, desc, ...) do { if (__builtin_expect(!(c), 0)) [[NSAssertionHandler currentHandler] handleFailureInFunction: \
    [NSString stringWithUTF8String:__PRETTY_FUNCTION__] file:[NSString stringWithUTF8String:__FILE__] lineNumber:__LINE__ description:(desc), ##__VA_ARGS__]; } while (0)
#endif
#define NSParameterAssert(c) NSAssert((c), @"Invalid parameter not satisfying: %s", #c)
#define NSCParameterAssert(c) NSCAssert((c), @"Invalid parameter not satisfying: %s", #c)

NS_SWIFT_BRIDGE(Date)
@interface NSDate : NSObject <NSCopying>
+ (instancetype)date; + (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)t; + (instancetype)distantFuture; + (instancetype)distantPast;
+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)t; + (instancetype)dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)t;
+ (NSTimeInterval)timeIntervalSinceReferenceDate;
@property (readonly) NSTimeInterval timeIntervalSince1970, timeIntervalSinceReferenceDate, timeIntervalSinceNow;
- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)d; - (NSComparisonResult)compare:(NSDate *)d;
- (instancetype)dateByAddingTimeInterval:(NSTimeInterval)t;
@end

typedef struct { NSInteger majorVersion, minorVersion, patchVersion; } NSOperatingSystemVersion;
typedef NS_ENUM(NSInteger, NSProcessInfoThermalState) { NSProcessInfoThermalStateNominal, NSProcessInfoThermalStateFair,
    NSProcessInfoThermalStateSerious, NSProcessInfoThermalStateCritical };
extern NSString *const NSProcessInfoThermalStateDidChangeNotification;
NS_SWIFT_NAME(ProcessInfo)
@interface NSProcessInfo : NSObject
@property (readonly) NSProcessInfoThermalState thermalState;
@property (readonly, getter=isLowPowerModeEnabled) BOOL lowPowerModeEnabled;
@property (class, readonly, strong) NSProcessInfo *processInfo;
@property (readonly, copy) NSArray *arguments; @property (readonly, copy) NSDictionary *environment;
@property (readonly) int processIdentifier; @property (readonly, copy) NSString *processName, *globallyUniqueString, *hostName;
@property (readonly) NSUInteger processorCount, activeProcessorCount; @property (readonly) unsigned long long physicalMemory;
@property (readonly) NSTimeInterval systemUptime; @property (readonly) NSOperatingSystemVersion operatingSystemVersion;
@end

extern NSString *const NSFileSize, *const NSFileType, *const NSFileTypeDirectory, *const NSFileTypeRegular, *const NSFileModificationDate;
extern NSString *const NSFileCreationDate, *const NSFilePosixPermissions, *const NSFileReferenceCount, *const NSFileOwnerAccountName,
    *const NSFileGroupOwnerAccountName, *const NSFileSystemNumber, *const NSFileSystemFileNumber, *const NSFileExtensionHidden, *const NSFileImmutable,
    *const NSFileAppendOnly, *const NSFileTypeSymbolicLink, *const NSFileTypeUnknown;
typedef NS_ENUM(NSUInteger, NSSearchPathDirectory) {
    NSApplicationDirectory = 1, NSDemoApplicationDirectory, NSDeveloperApplicationDirectory, NSAdminApplicationDirectory, NSLibraryDirectory,
    NSDeveloperDirectory, NSUserDirectory, NSDocumentationDirectory, NSDocumentDirectory, NSCoreServiceDirectory, NSAutosavedInformationDirectory = 11,
    NSDesktopDirectory = 12, NSCachesDirectory = 13, NSApplicationSupportDirectory = 14, NSDownloadsDirectory = 15, NSInputMethodsDirectory = 16,
    NSMoviesDirectory = 17, NSMusicDirectory = 18, NSPicturesDirectory = 19, NSPrinterDescriptionDirectory = 20, NSSharedPublicDirectory = 21,
    NSPreferencePanesDirectory = 22, NSApplicationScriptsDirectory = 23, NSItemReplacementDirectory = 99, NSAllApplicationsDirectory = 100,
    NSAllLibrariesDirectory = 101, NSTrashDirectory = 102 };
typedef NS_OPTIONS(NSUInteger, NSSearchPathDomainMask) {
    NSUserDomainMask = 1, NSLocalDomainMask = 2, NSNetworkDomainMask = 4, NSSystemDomainMask = 8, NSAllDomainsMask = 0x0ffff };
typedef NS_OPTIONS(NSUInteger, NSDirectoryEnumerationOptions) {
    NSDirectoryEnumerationSkipsSubdirectoryDescendants = 1 << 0, NSDirectoryEnumerationSkipsPackageDescendants = 1 << 1,
    NSDirectoryEnumerationSkipsHiddenFiles = 1 << 2, NSDirectoryEnumerationIncludesDirectoriesPostOrder = 1 << 3,
    NSDirectoryEnumerationProducesRelativePathURLs = 1 << 4 };
FOUNDATION_EXPORT NSArray<NSString *> *NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory directory, NSSearchPathDomainMask domainMask, BOOL expandTilde);
NS_SWIFT_NAME(FileManager)
@interface NSFileManager : NSObject
@property (class, readonly, strong) NSFileManager *defaultManager;
- (BOOL)fileExistsAtPath:(NSString *)p; - (BOOL)fileExistsAtPath:(NSString *)p isDirectory:(nullable BOOL *)d; - (BOOL)isReadableFileAtPath:(NSString *)p;
- (BOOL)createDirectoryAtPath:(NSString *)p withIntermediateDirectories:(BOOL)i attributes:(nullable NSDictionary *)a error:(NSError **)e;
- (nullable NSArray *)contentsOfDirectoryAtPath:(NSString *)p error:(NSError **)e;
- (BOOL)removeItemAtPath:(NSString *)p error:(NSError **)e;
- (BOOL)moveItemAtPath:(NSString *)a toPath:(NSString *)b error:(NSError **)e;
- (BOOL)copyItemAtPath:(NSString *)a toPath:(NSString *)b error:(NSError **)e;
- (nullable NSDictionary *)attributesOfItemAtPath:(NSString *)p error:(NSError **)e;
- (BOOL)createFileAtPath:(NSString *)p contents:(nullable NSData *)d attributes:(nullable NSDictionary *)a;
- (nullable NSData *)contentsAtPath:(NSString *)p;
@property (readonly, copy) NSString *currentDirectoryPath;
- (BOOL)changeCurrentDirectoryPath:(NSString *)p;
@end

NS_SWIFT_NAME(Thread)
@interface NSThread : NSObject
@property (class, readonly, strong) NSThread *currentThread, *mainThread; @property (class, readonly) BOOL isMainThread; @property (readonly) BOOL isMainThread;
+ (void)sleepForTimeInterval:(NSTimeInterval)t; + (void)detachNewThreadWithBlock:(void (^)(void))b;
+ (void)detachNewThreadSelector:(SEL)s toTarget:(id)t withObject:(nullable id)o;
@property (nullable, copy) NSString *name; @property (readonly) NSMutableDictionary *threadDictionary;
@end

@protocol NSLocking - (void)lock; - (void)unlock; @end
@interface NSLock : NSObject <NSLocking> - (BOOL)tryLock; @end
@interface NSRecursiveLock : NSObject <NSLocking> - (BOOL)tryLock; @end
@interface NSCondition : NSObject <NSLocking> - (void)wait; - (BOOL)waitUntilDate:(NSDate *)d; - (void)signal; - (void)broadcast; @end

@interface NSAutoreleasePool : NSObject - (void)drain; @end

@class NSURL;
NS_SWIFT_NAME(UserDefaults)
@interface NSUserDefaults : NSObject
@property (class, readonly, strong) NSUserDefaults *standardUserDefaults;
- (nullable id)objectForKey:(NSString *)k; - (void)setObject:(nullable id)o forKey:(NSString *)k NS_SWIFT_NAME(set(_:forKey:)); - (void)removeObjectForKey:(NSString *)k;
- (nullable NSString *)stringForKey:(NSString *)k; - (NSInteger)integerForKey:(NSString *)k; - (BOOL)boolForKey:(NSString *)k; - (double)doubleForKey:(NSString *)k;
- (void)setInteger:(NSInteger)v forKey:(NSString *)k NS_SWIFT_NAME(set(_:forKey:)); - (void)setBool:(BOOL)v forKey:(NSString *)k NS_SWIFT_NAME(set(_:forKey:)); - (void)setDouble:(double)v forKey:(NSString *)k NS_SWIFT_NAME(set(_:forKey:));
- (void)registerDefaults:(NSDictionary<NSString *, id> *)d NS_SWIFT_NAME(register(defaults:)); - (BOOL)synchronize;
- (nullable instancetype)initWithSuiteName:(nullable NSString *)suite;
- (nullable NSArray *)arrayForKey:(NSString *)k; - (nullable NSDictionary<NSString *, id> *)dictionaryForKey:(NSString *)k;
- (nullable NSData *)dataForKey:(NSString *)k; - (nullable NSArray<NSString *> *)stringArrayForKey:(NSString *)k;
- (float)floatForKey:(NSString *)k; - (nullable NSURL *)URLForKey:(NSString *)k;
- (void)setFloat:(float)v forKey:(NSString *)k NS_SWIFT_NAME(set(_:forKey:)); - (void)setURL:(nullable NSURL *)u forKey:(NSString *)k NS_SWIFT_NAME(set(_:forKey:));
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
- (nullable NSDictionary<NSString *, id> *)persistentDomainForName:(NSString *)n;
- (void)setPersistentDomain:(NSDictionary<NSString *, id> *)d forName:(NSString *)n; - (void)removePersistentDomainForName:(NSString *)n;
+ (void)resetStandardUserDefaults;
@end
extern NSString *const NSGlobalDomain, *const NSArgumentDomain, *const NSRegistrationDomain;
extern NSString *const NSUserDefaultsDidChangeNotification;
@interface NSDictionary<KeyType, ObjectType> (NSPropertyListFiles)
+ (nullable NSDictionary<KeyType, ObjectType> *)dictionaryWithContentsOfFile:(NSString *)path;
+ (nullable NSDictionary<KeyType, ObjectType> *)dictionaryWithContentsOfURL:(NSURL *)url;
+ (nullable NSDictionary<NSString *, ObjectType> *)dictionaryWithContentsOfURL:(NSURL *)url error:(NSError **)error;
- (nullable NSDictionary<KeyType, ObjectType> *)initWithContentsOfFile:(NSString *)path;
- (nullable NSDictionary<KeyType, ObjectType> *)initWithContentsOfURL:(NSURL *)url;
- (nullable NSDictionary<NSString *, ObjectType> *)initWithContentsOfURL:(NSURL *)url error:(NSError **)error;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile;
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically;
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error;
@end
@interface NSArray<ObjectType> (NSPropertyListFiles)
+ (nullable NSArray<ObjectType> *)arrayWithContentsOfFile:(NSString *)path;
+ (nullable NSArray<ObjectType> *)arrayWithContentsOfURL:(NSURL *)url;
+ (nullable NSArray<ObjectType> *)arrayWithContentsOfURL:(NSURL *)url error:(NSError **)error;
- (nullable NSArray<ObjectType> *)initWithContentsOfFile:(NSString *)path;
- (nullable NSArray<ObjectType> *)initWithContentsOfURL:(NSURL *)url;
- (nullable NSArray<ObjectType> *)initWithContentsOfURL:(NSURL *)url error:(NSError **)error;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile;
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically;
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error;
@end

/* JSON */
typedef NS_OPTIONS(NSUInteger, NSJSONReadingOptions) {
    NSJSONReadingMutableContainers = 1, NSJSONReadingMutableLeaves = 2, NSJSONReadingFragmentsAllowed = 4, NSJSONReadingJSON5Allowed = 8,
    NSJSONReadingTopLevelDictionaryAssumed = 16, NSJSONReadingAllowFragments NS_SWIFT_NAME(allowFragments) = 4,
} NS_SWIFT_NAME(JSONSerialization.ReadingOptions);
typedef NS_OPTIONS(NSUInteger, NSJSONWritingOptions) {
    NSJSONWritingPrettyPrinted = 1, NSJSONWritingSortedKeys = 2, NSJSONWritingFragmentsAllowed = 4, NSJSONWritingWithoutEscapingSlashes = 8,
} NS_SWIFT_NAME(JSONSerialization.WritingOptions);
NS_SWIFT_NAME(JSONSerialization)
@interface NSJSONSerialization : NSObject
+ (BOOL)isValidJSONObject:(id)o;
+ (nullable id)JSONObjectWithData:(NSData *)d options:(NSJSONReadingOptions)o error:(NSError **)e;
+ (nullable NSData *)dataWithJSONObject:(id)o options:(NSJSONWritingOptions)opt error:(NSError **)e;
@end

/* run loops, timers, notifications, operations */
typedef NSString *NSRunLoopMode NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(RunLoop.Mode);
extern NSRunLoopMode const NSDefaultRunLoopMode NS_SWIFT_NAME(default);
extern NSRunLoopMode const NSRunLoopCommonModes NS_SWIFT_NAME(common);
@class NSTimer;
NS_SWIFT_NAME(RunLoop)
@interface NSRunLoop : NSObject
@property (class, readonly, strong) NSRunLoop *currentRunLoop, *mainRunLoop;
@property (nullable, readonly, copy) NSRunLoopMode currentMode;
- (void)addTimer:(NSTimer *)t forMode:(NSRunLoopMode)m;
- (void)run; - (void)runUntilDate:(NSDate *)d; - (BOOL)runMode:(NSRunLoopMode)m beforeDate:(NSDate *)d;
- (void)performBlock:(void (^)(void))b; - (void)performInModes:(NSArray<NSRunLoopMode> *)modes block:(void (^)(void))b;
- (void *)getCFRunLoop;
@end
NS_SWIFT_NAME(Timer)
@interface NSTimer : NSObject
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)t repeats:(BOOL)r block:(void (^)(NSTimer *timer))b;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)t repeats:(BOOL)r block:(void (^)(NSTimer *timer))b;
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)t target:(id)tg selector:(SEL)s userInfo:(nullable id)u repeats:(BOOL)r;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)t target:(id)tg selector:(SEL)s userInfo:(nullable id)u repeats:(BOOL)r;
- (instancetype)initWithFireDate:(NSDate *)d interval:(NSTimeInterval)i repeats:(BOOL)r block:(void (^)(NSTimer *timer))b;
- (instancetype)initWithFireDate:(NSDate *)d interval:(NSTimeInterval)i target:(id)tg selector:(SEL)s userInfo:(nullable id)u repeats:(BOOL)r;
- (void)fire; - (void)invalidate;
@property (readonly, getter=isValid) BOOL valid; @property (copy) NSDate *fireDate; @property (readonly) NSTimeInterval timeInterval;
@property NSTimeInterval tolerance; @property (nullable, readonly) id userInfo;
@end
@interface NSObject (NSThreadPerformAdditions)
- (void)performSelectorOnMainThread:(SEL)s withObject:(nullable id)o waitUntilDone:(BOOL)w;
- (void)performSelectorInBackground:(SEL)s withObject:(nullable id)o;
- (void)performSelector:(SEL)s withObject:(nullable id)o afterDelay:(NSTimeInterval)d;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)t;
@end
typedef NSString *NSNotificationName NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSNotification.Name);
NS_SWIFT_BRIDGE(Notification)
@interface NSNotification : NSObject <NSCopying>
+ (instancetype)notificationWithName:(NSNotificationName)n object:(nullable id)o;
+ (instancetype)notificationWithName:(NSNotificationName)n object:(nullable id)o userInfo:(nullable NSDictionary *)u;
- (instancetype)initWithName:(NSNotificationName)n object:(nullable id)o userInfo:(nullable NSDictionary *)u NS_DESIGNATED_INITIALIZER;
@property (readonly, copy) NSNotificationName name; @property (nullable, readonly) id object; @property (nullable, readonly, copy) NSDictionary *userInfo;
@end
@class NSOperationQueue;
NS_SWIFT_NAME(NotificationCenter)
@interface NSNotificationCenter : NSObject
@property (class, readonly) NSNotificationCenter *defaultCenter;
- (void)addObserver:(id)o selector:(SEL)s name:(nullable NSNotificationName)n object:(nullable id)obj;
- (id<NSObject>)addObserverForName:(nullable NSNotificationName)n object:(nullable id)obj queue:(nullable NSOperationQueue *)q usingBlock:(void (^)(NSNotification *note))b;
- (void)removeObserver:(id)o; - (void)removeObserver:(id)o name:(nullable NSNotificationName)n object:(nullable id)obj;
- (void)postNotification:(NSNotification *)n;
- (void)postNotificationName:(NSNotificationName)n object:(nullable id)o NS_SWIFT_NAME(post(name:object:));
- (void)postNotificationName:(NSNotificationName)n object:(nullable id)o userInfo:(nullable NSDictionary *)u NS_SWIFT_NAME(post(name:object:userInfo:));
@end
NS_SWIFT_NAME(Operation)
@interface NSOperation : NSObject
- (void)start; - (void)main; - (void)cancel; - (void)waitUntilFinished;
@property (readonly, getter=isCancelled) BOOL cancelled; @property (readonly, getter=isExecuting) BOOL executing;
@property (readonly, getter=isFinished) BOOL finished; @property (readonly, getter=isReady) BOOL ready;
@property (nullable, copy) void (^completionBlock)(void); @property (nullable, copy) NSString *name; @property NSInteger queuePriority;
- (void)addDependency:(NSOperation *)o; - (void)removeDependency:(NSOperation *)o; @property (readonly, copy) NSArray *dependencies;
@end
NS_SWIFT_NAME(BlockOperation)
@interface NSBlockOperation : NSOperation
+ (instancetype)blockOperationWithBlock:(void (^)(void))b; - (void)addExecutionBlock:(void (^)(void))b;
@property (readonly, copy) NSArray *executionBlocks;
@end
NS_SWIFT_NAME(OperationQueue)
@interface NSOperationQueue : NSObject
@property (class, readonly) NSOperationQueue *mainQueue; @property (class, readonly, nullable) NSOperationQueue *currentQueue;
- (void)addOperation:(NSOperation *)o; - (void)addOperations:(NSArray *)ops waitUntilFinished:(BOOL)w;
- (void)addOperationWithBlock:(void (^)(void))b; - (void)addBarrierBlock:(void (^)(void))b;
- (void)waitUntilAllOperationsAreFinished; - (void)cancelAllOperations;
@property (readonly) NSUInteger operationCount; @property (readonly, copy) NSArray *operations;
@property NSInteger maxConcurrentOperationCount; @property (nullable, copy) NSString *name; @property (getter=isSuspended) BOOL suspended;
@end
enum { NSPointerFunctionsStrongMemory = 0, NSPointerFunctionsOpaqueMemory = 2, NSPointerFunctionsWeakMemory = 5,
       NSPointerFunctionsObjectPersonality = 0, NSPointerFunctionsObjectPointerPersonality = 1 << 9, NSPointerFunctionsCopyIn = 1 << 16 };
enum { NSHashTableStrongMemory = 0, NSHashTableWeakMemory = 5, NSHashTableCopyIn = 1 << 16, NSHashTableObjectPointerPersonality = 1 << 9 };
@interface NSHashTable<ObjectType> : NSObject <NSCopying, NSFastEnumeration>
+ (NSHashTable *)weakObjectsHashTable; + (NSHashTable *)hashTableWithOptions:(NSUInteger)o;
- (instancetype)initWithOptions:(NSUInteger)o capacity:(NSUInteger)c;
- (void)addObject:(id)o; - (void)removeObject:(id)o; - (void)removeAllObjects; - (BOOL)containsObject:(id)o; - (nullable id)member:(id)o;
@property (readonly) NSUInteger count; @property (readonly, copy) NSArray *allObjects; @property (nullable, readonly) id anyObject;
- (NSEnumerator *)objectEnumerator;
@end
@interface NSMapTable<KeyType, ObjectType> : NSObject <NSCopying, NSFastEnumeration>
+ (NSMapTable *)strongToStrongObjectsMapTable; + (NSMapTable *)strongToWeakObjectsMapTable;
+ (NSMapTable *)weakToStrongObjectsMapTable; + (NSMapTable *)weakToWeakObjectsMapTable;
+ (NSMapTable *)mapTableWithKeyOptions:(NSUInteger)k valueOptions:(NSUInteger)v;
- (instancetype)initWithKeyOptions:(NSUInteger)k valueOptions:(NSUInteger)v capacity:(NSUInteger)c;
- (nullable ObjectType)objectForKey:(KeyType)k; - (void)setObject:(ObjectType)o forKey:(KeyType)k; - (void)removeObjectForKey:(KeyType)k;
- (void)removeAllObjects; @property (readonly) NSUInteger count;
- (NSEnumerator *)keyEnumerator; - (NSEnumerator *)objectEnumerator; - (NSDictionary *)dictionaryRepresentation;
@end
typedef NSUInteger NSNumberFormatterStyle;
enum { NSNumberFormatterNoStyle = 0, NSNumberFormatterDecimalStyle = 1, NSNumberFormatterCurrencyStyle = 2, NSNumberFormatterPercentStyle = 3 };
NS_SWIFT_NAME(NumberFormatter)
@interface NSNumberFormatter : NSObject
@property NSNumberFormatterStyle numberStyle; @property BOOL usesGroupingSeparator;
@property (copy) NSString *groupingSeparator, *decimalSeparator; @property NSUInteger minimumFractionDigits, maximumFractionDigits;
- (nullable NSString *)stringFromNumber:(NSNumber *)n; - (nullable NSNumber *)numberFromString:(NSString *)s;
+ (NSString *)localizedStringFromNumber:(NSNumber *)n numberStyle:(NSNumberFormatterStyle)s;
@end

@interface NSMutableCharacterSet : NSCharacterSet <NSCopying>
- (void)formUnionWithCharacterSet:(NSCharacterSet *)o; - (void)addCharactersInString:(NSString *)s;
- (void)addCharactersInRange:(NSRange)r; - (void)invert;
@end
@interface NSCharacterSet (MutableCopy) - (id)mutableCopy; @end

NS_SWIFT_NAME(Scanner)
@interface NSScanner : NSObject <NSCopying>
+ (instancetype)scannerWithString:(NSString *)s; - (instancetype)initWithString:(NSString *)s;
@property (readonly, copy) NSString *string; @property NSUInteger scanLocation;
@property (nullable, copy) NSCharacterSet *charactersToBeSkipped; @property BOOL caseSensitive;
@property (readonly, getter=isAtEnd) BOOL atEnd;
- (BOOL)scanString:(NSString *)s intoString:(NSString * _Nullable * _Nullable)out;
- (BOOL)scanUpToString:(NSString *)s intoString:(NSString * _Nullable * _Nullable)out;
- (BOOL)scanCharactersFromSet:(NSCharacterSet *)set intoString:(NSString * _Nullable * _Nullable)out;
- (BOOL)scanUpToCharactersFromSet:(NSCharacterSet *)set intoString:(NSString * _Nullable * _Nullable)out;
- (BOOL)scanInt:(nullable int *)v NS_SWIFT_NAME(scanInt32(_:)); - (BOOL)scanInteger:(nullable NSInteger *)v NS_SWIFT_NAME(scanInt(_:)); - (BOOL)scanLongLong:(nullable long long *)v NS_SWIFT_NAME(scanInt64(_:));
- (BOOL)scanUnsignedLongLong:(nullable unsigned long long *)v; - (BOOL)scanHexInt:(nullable unsigned *)v NS_SWIFT_NAME(scanHexInt32(_:));
- (BOOL)scanHexLongLong:(nullable unsigned long long *)v NS_SWIFT_NAME(scanHexInt64(_:)); - (BOOL)scanDouble:(nullable double *)v; - (BOOL)scanFloat:(nullable float *)v;
@end

NS_SWIFT_BRIDGE(UUID)
@interface NSUUID : NSObject <NSCopying>
+ (instancetype)UUID; - (nullable instancetype)initWithUUIDString:(NSString *)s; - (instancetype)initWithUUIDBytes:(const unsigned char *)b;
- (void)getUUIDBytes:(unsigned char *)b; @property (readonly, copy) NSString *UUIDString;
@end

NS_SWIFT_NAME(FileHandle)
@interface NSFileHandle : NSObject
+ (NSFileHandle *)fileHandleWithStandardInput; + (NSFileHandle *)fileHandleWithStandardOutput; + (NSFileHandle *)fileHandleWithStandardError;
+ (nullable instancetype)fileHandleForReadingAtPath:(NSString *)p; + (nullable instancetype)fileHandleForWritingAtPath:(NSString *)p;
- (instancetype)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)c; - (instancetype)initWithFileDescriptor:(int)fd;
@property (readonly) int fileDescriptor;
- (void)writeData:(NSData *)d; - (NSData *)readDataToEndOfFile; - (NSData *)readDataOfLength:(NSUInteger)n; @property (readonly, copy) NSData *availableData;
- (unsigned long long)seekToEndOfFile; - (void)seekToFileOffset:(unsigned long long)o; @property (readonly) unsigned long long offsetInFile;
- (void)synchronizeFile; - (void)closeFile;
@end
@interface NSPipe : NSObject
+ (NSPipe *)pipe;
@property (readonly, retain) NSFileHandle *fileHandleForReading, *fileHandleForWriting;
@end
@class NSURL;
@interface NSFileManager (NSURLAPI)
- (nullable NSArray<NSURL *> *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(nullable NSArray *)keys options:(NSDirectoryEnumerationOptions)mask error:(NSError **)error;
- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)i attributes:(nullable NSDictionary *)a error:(NSError **)error;
- (BOOL)removeItemAtURL:(NSURL *)url error:(NSError **)error;
- (BOOL)moveItemAtURL:(NSURL *)a toURL:(NSURL *)b error:(NSError **)error;
- (BOOL)copyItemAtURL:(NSURL *)a toURL:(NSURL *)b error:(NSError **)error;
- (BOOL)setAttributes:(NSDictionary *)a ofItemAtPath:(NSString *)p error:(NSError **)error;
@property (readonly, copy) NSURL *temporaryDirectory;
- (NSArray<NSURL *> *)URLsForDirectory:(NSSearchPathDirectory)d inDomains:(NSSearchPathDomainMask)m;
- (nullable NSURL *)URLForDirectory:(NSSearchPathDirectory)d inDomain:(NSSearchPathDomainMask)m appropriateForURL:(nullable NSURL *)u create:(BOOL)c error:(NSError **)error;
@end
@class NSURL;
/* NSTask: scion cannot start processes yet: -launchAndReturnError: fails (ENOSYS), -launch raises */
typedef NS_ENUM(NSInteger, NSTaskTerminationReason) { NSTaskTerminationReasonExit = 1, NSTaskTerminationReasonUncaughtSignal = 2 };
NS_SWIFT_NAME(Process)
@interface NSTask : NSObject
@property (nullable, copy) NSURL *executableURL; @property (nullable, copy) NSString *launchPath; @property (nullable, copy) NSArray<NSString *> *arguments;
@property (nullable, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nullable, copy) NSURL *currentDirectoryURL; @property (copy) NSString *currentDirectoryPath;
@property (nullable, retain) id standardInput; @property (nullable, retain) id standardOutput; @property (nullable, retain) id standardError;
@property (readonly) int processIdentifier; @property (readonly) int terminationStatus;
@property (readonly) NSTaskTerminationReason terminationReason; @property (readonly, getter=isRunning) BOOL running;
@property (nullable, copy) void (^terminationHandler)(NSTask *);
- (BOOL)launchAndReturnError:(NSError **)error; - (void)launch; - (void)waitUntilExit; - (void)terminate;
@end

NS_SWIFT_NAME(Bundle)
@interface NSBundle : NSObject
@property (class, readonly, strong) NSBundle *mainBundle; + (nullable instancetype)bundleWithPath:(NSString *)p;
@property (readonly, copy) NSString *bundlePath;
@property (nullable, readonly, copy) NSString *executablePath, *bundleIdentifier, *resourcePath;
@property (nullable, readonly, copy) NSDictionary<NSString *, id> *infoDictionary;
- (nullable id)objectForInfoDictionaryKey:(NSString *)k;
- (nullable NSString *)pathForResource:(NSString *)n ofType:(NSString *)t;
@end
extern NSString *const NSLocalizedFailureReasonErrorKey, *const NSLocalizedRecoverySuggestionErrorKey, *const NSUnderlyingErrorKey;
@interface NSFileManager (Representation) - (NSString *)stringWithFileSystemRepresentation:(const char *)s length:(NSUInteger)n; @end

#ifndef MIN
#define MIN(a, b) ({ __typeof__(a) __a = (a); __typeof__(b) __b = (b); __a < __b ? __a : __b; })
#endif
#ifndef MAX
#define MAX(a, b) ({ __typeof__(a) __a = (a); __typeof__(b) __b = (b); __a < __b ? __b : __a; })
#endif
#ifndef ABS
#define ABS(a) ({ __typeof__(a) __a = (a); __a < 0 ? -__a : __a; })
#endif
@interface NSObject (KeyPath) - (nullable id)valueForKeyPath:(NSString *)p; @end
@interface NSError (Reason) @property (nullable, readonly, copy) NSString *localizedFailureReason, *localizedRecoverySuggestion; @end
@interface NSFileManager (Access)
- (BOOL)isWritableFileAtPath:(NSString *)p; - (BOOL)isExecutableFileAtPath:(NSString *)p;
@end
@interface NSString (Paths2)
+ (NSString *)pathWithComponents:(NSArray<NSString *> *)c;
@property (readonly, copy) NSString *stringByResolvingSymlinksInPath, *decomposedStringWithCanonicalMapping, *precomposedStringWithCanonicalMapping;
@end
@interface NSMutableData (Length) - (instancetype)initWithLength:(NSUInteger)n; - (instancetype)initWithCapacity:(NSUInteger)n; @end
@interface NSData (Mapped) + (nullable instancetype)dataWithContentsOfMappedFile:(NSString *)p; @end

NS_SWIFT_BRIDGE(URL)
@interface NSURL : NSObject <NSCopying>
+ (instancetype)fileURLWithPath:(NSString *)p; + (instancetype)fileURLWithPath:(NSString *)p isDirectory:(BOOL)d;
+ (nullable instancetype)URLWithString:(NSString *)s; - (instancetype)initFileURLWithPath:(NSString *)p; - (nullable instancetype)initWithString:(NSString *)s;
@property (nullable, readonly, copy) NSString *absoluteString, *path, *scheme, *host, *lastPathComponent, *pathExtension;
@property (readonly, getter=isFileURL) BOOL fileURL;
- (nullable NSURL *)URLByAppendingPathComponent:(NSString *)c;
@property (nullable, readonly, copy) NSURL *URLByDeletingLastPathComponent;
@property (readonly) const char *fileSystemRepresentation;
@end
@interface NSData (URL) + (nullable instancetype)dataWithContentsOfURL:(NSURL *)u; @end
@interface NSString (URL) + (nullable instancetype)stringWithContentsOfURL:(NSURL *)u encoding:(NSStringEncoding)e error:(NSError **)err; @end

void NSLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void NSLogv(NSString *format, va_list ap);
NSString *NSStringFromClass(Class c); Class NSClassFromString(NSString *s);
NSString *NSStringFromSelector(SEL s); SEL NSSelectorFromString(NSString *s);
NSString *NSStringFromRange(NSRange r);

/* NSGeometry (exported) */
extern const NSPoint NSZeroPoint; extern const NSSize NSZeroSize; extern const NSRect NSZeroRect; extern const NSEdgeInsets NSEdgeInsetsZero;
BOOL NSEqualPoints(NSPoint a, NSPoint b); BOOL NSEqualSizes(NSSize a, NSSize b); BOOL NSEqualRects(NSRect a, NSRect b);
BOOL NSIsEmptyRect(NSRect r); BOOL NSPointInRect(NSPoint p, NSRect r); BOOL NSMouseInRect(NSPoint p, NSRect r, BOOL flipped);
BOOL NSContainsRect(NSRect a, NSRect b); BOOL NSIntersectsRect(NSRect a, NSRect b);
NSRect NSInsetRect(NSRect r, CGFloat dx, CGFloat dy); NSRect NSOffsetRect(NSRect r, CGFloat dx, CGFloat dy);
NSRect NSIntegralRect(NSRect r); NSRect NSUnionRect(NSRect a, NSRect b); NSRect NSIntersectionRect(NSRect a, NSRect b);
void NSDivideRect(NSRect r, NSRect *slice, NSRect *rem, CGFloat amount, NSRectEdge edge);
BOOL NSEdgeInsetsEqual(NSEdgeInsets a, NSEdgeInsets b);
NSString *NSStringFromPoint(NSPoint p); NSString *NSStringFromSize(NSSize s); NSString *NSStringFromRect(NSRect r);
NSPoint NSPointFromString(NSString *s); NSSize NSSizeFromString(NSString *s); NSRect NSRectFromString(NSString *s);
NSString *NSHomeDirectory(void); NSString *NSTemporaryDirectory(void); NSString *NSUserName(void);


/* ======================================================================================================================
 * The rest of Foundation's API that Swift's Foundation overlay (src/build_swift_overlays.sh) builds on: dates and
 * calendars, locales, time zones, character and index sets, URLs, errors, numbers, coding. Declared as on macOS, with
 * the Swift names Apple's SDK gives them. ponytail: declared here does not mean implemented: Foundation.dylib grows as
 * apps need these (an unimplemented method is an "unrecognized selector" at run time).
 * ==================================================================================================================== */
@class NSLocale, NSTimeZone, NSCalendar, NSDateComponents, NSIndexSet, NSURL, NSCoder, NSDecimalNumber, NSFileHandle, NSURLQueryItem, NSOrthography, NSLinguisticTagger;
typedef NS_OPTIONS(NSUInteger, NSLinguisticTaggerOptions) {
    NSLinguisticTaggerOmitWords = 1 << 0, NSLinguisticTaggerOmitPunctuation = 1 << 1, NSLinguisticTaggerOmitWhitespace = 1 << 2,
    NSLinguisticTaggerOmitOther = 1 << 3, NSLinguisticTaggerJoinNames = 1 << 4,
} NS_SWIFT_NAME(NSLinguisticTagger.Options);

/* ---- typed string constants */
typedef NSString *NSURLResourceKey NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(URLResourceKey);
typedef NSString *NSURLFileResourceType NS_TYPED_ENUM NS_SWIFT_NAME(URLFileResourceType);
typedef NSString *NSURLThumbnailDictionaryItem NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(URLThumbnailDictionaryItem);
typedef NSString *NSURLFileProtectionType NS_TYPED_ENUM NS_SWIFT_NAME(URLFileProtection);
typedef NSString *NSURLUbiquitousItemDownloadingStatus NS_TYPED_ENUM NS_SWIFT_NAME(URLUbiquitousItemDownloadingStatus);
typedef NSString *NSURLUbiquitousSharedItemRole NS_TYPED_ENUM NS_SWIFT_NAME(URLUbiquitousSharedItemRole);
typedef NSString *NSURLUbiquitousSharedItemPermissions NS_TYPED_ENUM NS_SWIFT_NAME(URLUbiquitousSharedItemPermissions);
typedef NSString *NSCalendarIdentifier NS_TYPED_ENUM NS_SWIFT_NAME(NSCalendar.Identifier);
typedef NSString *NSLocaleKey NS_TYPED_ENUM NS_SWIFT_NAME(NSLocale.Key);
typedef NSString *NSFileAttributeKey NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(FileAttributeKey);
typedef NSString *NSFileAttributeType NS_TYPED_ENUM NS_SWIFT_NAME(FileAttributeType);
typedef NSString *NSFileProtectionType NS_TYPED_ENUM NS_SWIFT_NAME(FileProtectionType);
typedef NSString *NSStringEncodingDetectionOptionsKey NS_TYPED_ENUM NS_SWIFT_NAME(StringEncodingDetectionOptionsKey);
typedef NSString *NSStringTransform NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(StringTransform);
typedef NSString *NSLinguisticTag NS_TYPED_EXTENSIBLE_ENUM;
typedef NSString *NSLinguisticTagScheme NS_TYPED_EXTENSIBLE_ENUM;
typedef NSString *NSExceptionName NS_TYPED_EXTENSIBLE_ENUM;
typedef NSString *NSKeyValueChangeKey NS_TYPED_ENUM;
typedef NSString *NSValueTransformerName NS_TYPED_EXTENSIBLE_ENUM;

/* ---- calendars and dates */
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierGregorian, NSCalendarIdentifierBuddhist, NSCalendarIdentifierChinese,
    NSCalendarIdentifierCoptic, NSCalendarIdentifierEthiopicAmeteMihret, NSCalendarIdentifierEthiopicAmeteAlem,
    NSCalendarIdentifierHebrew, NSCalendarIdentifierISO8601, NSCalendarIdentifierIndian, NSCalendarIdentifierIslamic,
    NSCalendarIdentifierIslamicCivil, NSCalendarIdentifierJapanese, NSCalendarIdentifierPersian, NSCalendarIdentifierRepublicOfChina,
    NSCalendarIdentifierIslamicTabular, NSCalendarIdentifierIslamicUmmAlQura;
typedef NS_OPTIONS(NSUInteger, NSCalendarUnit) {
    NSCalendarUnitEra = 2, NSCalendarUnitYear = 4, NSCalendarUnitMonth = 8, NSCalendarUnitDay = 16, NSCalendarUnitHour = 32,
    NSCalendarUnitMinute = 64, NSCalendarUnitSecond = 128, NSCalendarUnitWeekday = 512, NSCalendarUnitWeekdayOrdinal = 1024,
    NSCalendarUnitQuarter = 2048, NSCalendarUnitWeekOfMonth = 4096, NSCalendarUnitWeekOfYear = 8192, NSCalendarUnitYearForWeekOfYear = 16384,
    NSCalendarUnitNanosecond = 32768, NSCalendarUnitCalendar = 1048576, NSCalendarUnitTimeZone = 2097152,
} NS_SWIFT_NAME(NSCalendar.Unit);
typedef NS_OPTIONS(NSUInteger, NSCalendarOptions) {
    NSCalendarWrapComponents = 1, NSCalendarMatchStrictly = 2, NSCalendarSearchBackwards = 4,
    NSCalendarMatchPreviousTimePreservingSmallerUnits = 256, NSCalendarMatchNextTimePreservingSmallerUnits = 512,
    NSCalendarMatchNextTime = 1024, NSCalendarMatchFirst = 4096, NSCalendarMatchLast = 8192,
} NS_SWIFT_NAME(NSCalendar.Options);
enum : NSInteger { NSDateComponentUndefined = 9223372036854775807L };

NS_SWIFT_BRIDGE(Calendar)
@interface NSCalendar : NSObject <NSCopying>
@property (class, readonly, copy) NSCalendar *currentCalendar;
@property (class, readonly, strong) NSCalendar *autoupdatingCurrentCalendar;
+ (nullable NSCalendar *)calendarWithIdentifier:(NSCalendarIdentifier)identifier;
- (nullable id)initWithCalendarIdentifier:(NSCalendarIdentifier)ident NS_DESIGNATED_INITIALIZER;
@property (readonly, copy) NSCalendarIdentifier calendarIdentifier;
@property (nullable, copy) NSLocale *locale; @property (copy) NSTimeZone *timeZone;
@property NSUInteger firstWeekday; @property NSUInteger minimumDaysInFirstWeek;
@property (readonly, copy) NSArray<NSString *> *eraSymbols, *longEraSymbols, *monthSymbols, *shortMonthSymbols, *veryShortMonthSymbols,
    *standaloneMonthSymbols, *shortStandaloneMonthSymbols, *veryShortStandaloneMonthSymbols, *weekdaySymbols, *shortWeekdaySymbols,
    *veryShortWeekdaySymbols, *standaloneWeekdaySymbols, *shortStandaloneWeekdaySymbols, *veryShortStandaloneWeekdaySymbols,
    *quarterSymbols, *shortQuarterSymbols, *standaloneQuarterSymbols, *shortStandaloneQuarterSymbols;
@property (readonly, copy) NSString *AMSymbol, *PMSymbol;
- (NSRange)minimumRangeOfUnit:(NSCalendarUnit)unit;
- (NSRange)maximumRangeOfUnit:(NSCalendarUnit)unit;
- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date;
- (NSUInteger)ordinalityOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date;
- (BOOL)rangeOfUnit:(NSCalendarUnit)unit startDate:(NSDate * _Nullable * _Nullable)datep interval:(NSTimeInterval *)tip forDate:(NSDate *)date;
- (nullable NSDate *)dateFromComponents:(NSDateComponents *)comps;
- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)date;
- (nullable NSDate *)dateByAddingComponents:(NSDateComponents *)comps toDate:(NSDate *)date options:(NSCalendarOptions)opts;
- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)startingDate toDate:(NSDate *)resultDate options:(NSCalendarOptions)opts;
- (void)getEra:(NSInteger *)eraValuePointer year:(NSInteger *)yearValuePointer month:(NSInteger *)monthValuePointer day:(NSInteger *)dayValuePointer fromDate:(NSDate *)date;
- (void)getEra:(NSInteger *)eraValuePointer yearForWeekOfYear:(NSInteger *)yearValuePointer weekOfYear:(NSInteger *)weekValuePointer weekday:(NSInteger *)weekdayValuePointer fromDate:(NSDate *)date;
- (void)getHour:(NSInteger *)hourValuePointer minute:(NSInteger *)minuteValuePointer second:(NSInteger *)secondValuePointer nanosecond:(NSInteger *)nanosecondValuePointer fromDate:(NSDate *)date;
- (NSInteger)component:(NSCalendarUnit)unit fromDate:(NSDate *)date;
- (nullable NSDate *)dateWithEra:(NSInteger)eraValue year:(NSInteger)yearValue month:(NSInteger)monthValue day:(NSInteger)dayValue hour:(NSInteger)hourValue minute:(NSInteger)minuteValue second:(NSInteger)secondValue nanosecond:(NSInteger)nanosecondValue;
- (nullable NSDate *)dateWithEra:(NSInteger)eraValue yearForWeekOfYear:(NSInteger)yearValue weekOfYear:(NSInteger)weekValue weekday:(NSInteger)weekdayValue hour:(NSInteger)hourValue minute:(NSInteger)minuteValue second:(NSInteger)secondValue nanosecond:(NSInteger)nanosecondValue;
- (NSDate *)startOfDayForDate:(NSDate *)date;
- (NSDateComponents *)componentsInTimeZone:(NSTimeZone *)timezone fromDate:(NSDate *)date;
- (NSComparisonResult)compareDate:(NSDate *)date1 toDate:(NSDate *)date2 toUnitGranularity:(NSCalendarUnit)unit;
- (BOOL)isDate:(NSDate *)date1 equalToDate:(NSDate *)date2 toUnitGranularity:(NSCalendarUnit)unit;
- (BOOL)isDate:(NSDate *)date1 inSameDayAsDate:(NSDate *)date2;
- (BOOL)isDateInToday:(NSDate *)date NS_SWIFT_NAME(isDateInToday(_:)); - (BOOL)isDateInYesterday:(NSDate *)date NS_SWIFT_NAME(isDateInYesterday(_:)); - (BOOL)isDateInTomorrow:(NSDate *)date NS_SWIFT_NAME(isDateInTomorrow(_:));
- (BOOL)isDateInWeekend:(NSDate *)date NS_SWIFT_NAME(isDateInWeekend(_:));
- (BOOL)rangeOfWeekendStartDate:(NSDate * _Nullable * _Nullable)datep interval:(NSTimeInterval *)tip containingDate:(NSDate *)date;
- (BOOL)nextWeekendStartDate:(NSDate * _Nullable * _Nullable)datep interval:(NSTimeInterval *)tip options:(NSCalendarOptions)options afterDate:(NSDate *)date;
- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDateComponents:(NSDateComponents *)startingDateComp toDateComponents:(NSDateComponents *)resultDateComp options:(NSCalendarOptions)options;
- (nullable NSDate *)dateByAddingUnit:(NSCalendarUnit)unit value:(NSInteger)value toDate:(NSDate *)date options:(NSCalendarOptions)options;
- (void)enumerateDatesStartingAfterDate:(NSDate *)start matchingComponents:(NSDateComponents *)comps options:(NSCalendarOptions)opts usingBlock:(void (NS_NOESCAPE ^)(NSDate * _Nullable date, BOOL exactMatch, BOOL *stop))block NS_SWIFT_NAME(enumerateDates(startingAfter:matching:options:using:));
- (nullable NSDate *)nextDateAfterDate:(NSDate *)date matchingComponents:(NSDateComponents *)comps options:(NSCalendarOptions)options;
- (nullable NSDate *)nextDateAfterDate:(NSDate *)date matchingUnit:(NSCalendarUnit)unit value:(NSInteger)value options:(NSCalendarOptions)options;
- (nullable NSDate *)nextDateAfterDate:(NSDate *)date matchingHour:(NSInteger)hourValue minute:(NSInteger)minuteValue second:(NSInteger)secondValue options:(NSCalendarOptions)options;
- (nullable NSDate *)dateBySettingUnit:(NSCalendarUnit)unit value:(NSInteger)v ofDate:(NSDate *)date options:(NSCalendarOptions)opts;
- (nullable NSDate *)dateBySettingHour:(NSInteger)h minute:(NSInteger)m second:(NSInteger)s ofDate:(NSDate *)date options:(NSCalendarOptions)opts;
- (BOOL)date:(NSDate *)date matchesComponents:(NSDateComponents *)components;
@end

NS_SWIFT_BRIDGE(DateComponents)
@interface NSDateComponents : NSObject <NSCopying>
@property (nullable, copy) NSCalendar *calendar; @property (nullable, copy) NSTimeZone *timeZone;
@property NSInteger era, year, month, day, hour, minute, second, nanosecond, weekday, weekdayOrdinal, quarter, weekOfMonth, weekOfYear, yearForWeekOfYear;
@property (getter=isLeapMonth) BOOL leapMonth;
@property (nullable, readonly, copy) NSDate *date;
- (void)setValue:(NSInteger)value forComponent:(NSCalendarUnit)unit;
- (NSInteger)valueForComponent:(NSCalendarUnit)unit;
@property (getter=isValidDate, readonly) BOOL validDate;
- (BOOL)isValidDateInCalendar:(NSCalendar *)calendar;
@end

@interface NSDate (NSExtendedDate)
- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)ti;
- (instancetype)initWithTimeIntervalSinceNow:(NSTimeInterval)secs;
- (instancetype)initWithTimeIntervalSince1970:(NSTimeInterval)secs;
- (instancetype)initWithTimeInterval:(NSTimeInterval)secsToBeAdded sinceDate:(NSDate *)date;
- (BOOL)isEqualToDate:(NSDate *)otherDate;
- (NSDate *)earlierDate:(NSDate *)anotherDate; - (NSDate *)laterDate:(NSDate *)anotherDate;
- (NSString *)descriptionWithLocale:(nullable id)locale NS_SWIFT_NAME(description(with:));
@property (class, readonly) NSTimeInterval timeIntervalSinceReferenceDate;
@end
#define NSTimeIntervalSince1970 978307200.0

NS_SWIFT_BRIDGE(DateInterval)
@interface NSDateInterval : NSObject <NSCopying>
@property (readonly, copy) NSDate *startDate, *endDate; @property (readonly) NSTimeInterval duration;
- (instancetype)initWithStartDate:(NSDate *)startDate duration:(NSTimeInterval)duration NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate;
- (NSComparisonResult)compare:(NSDateInterval *)dateInterval;
- (BOOL)isEqualToDateInterval:(NSDateInterval *)dateInterval;
- (BOOL)intersectsDateInterval:(NSDateInterval *)dateInterval;
- (NSDateInterval *)intersectionWithDateInterval:(NSDateInterval *)dateInterval;
- (BOOL)containsDate:(NSDate *)date;
@end

/* ---- locales and time zones */
FOUNDATION_EXPORT NSLocaleKey const NSLocaleIdentifier, NSLocaleLanguageCode, NSLocaleCountryCode, NSLocaleScriptCode, NSLocaleVariantCode,
    NSLocaleExemplarCharacterSet, NSLocaleCalendar, NSLocaleCollationIdentifier, NSLocaleUsesMetricSystem, NSLocaleMeasurementSystem,
    NSLocaleDecimalSeparator, NSLocaleGroupingSeparator, NSLocaleCurrencySymbol, NSLocaleCurrencyCode, NSLocaleCollatorIdentifier,
    NSLocaleQuotationBeginDelimiterKey, NSLocaleQuotationEndDelimiterKey, NSLocaleAlternateQuotationBeginDelimiterKey,
    NSLocaleAlternateQuotationEndDelimiterKey;
typedef NS_ENUM(NSUInteger, NSLocaleLanguageDirection) {
    NSLocaleLanguageDirectionUnknown = 0, NSLocaleLanguageDirectionLeftToRight = 1, NSLocaleLanguageDirectionRightToLeft = 2,
    NSLocaleLanguageDirectionTopToBottom = 3, NSLocaleLanguageDirectionBottomToTop = 4,
} NS_SWIFT_NAME(NSLocale.LanguageDirection);
FOUNDATION_EXPORT NSNotificationName const NSCurrentLocaleDidChangeNotification, NSSystemTimeZoneDidChangeNotification;
NS_SWIFT_BRIDGE(Locale)
@interface NSLocale : NSObject <NSCopying>
- (nullable id)objectForKey:(NSLocaleKey)key;
- (nullable NSString *)displayNameForKey:(NSLocaleKey)key value:(id)value;
- (instancetype)initWithLocaleIdentifier:(NSString *)string NS_DESIGNATED_INITIALIZER;
+ (instancetype)localeWithLocaleIdentifier:(NSString *)ident;
@property (class, readonly, strong) NSLocale *autoupdatingCurrentLocale, *currentLocale, *systemLocale;
@property (nullable, readonly, copy) NSString *countryCode, *scriptCode, *variantCode, *collationIdentifier, *currencyCode;
@property (readonly, copy) NSString *localeIdentifier, *languageCode, *calendarIdentifier, *decimalSeparator, *groupingSeparator, *currencySymbol, *collatorIdentifier,
    *quotationBeginDelimiter, *quotationEndDelimiter, *alternateQuotationBeginDelimiter, *alternateQuotationEndDelimiter;
@property (readonly) BOOL usesMetricSystem;
@property (nullable, readonly, copy) NSCharacterSet *exemplarCharacterSet;
- (nullable NSString *)localizedStringForLocaleIdentifier:(NSString *)localeIdentifier;
- (nullable NSString *)localizedStringForLanguageCode:(NSString *)languageCode;
- (nullable NSString *)localizedStringForCountryCode:(NSString *)countryCode;
- (nullable NSString *)localizedStringForScriptCode:(NSString *)scriptCode;
- (nullable NSString *)localizedStringForVariantCode:(NSString *)variantCode;
- (nullable NSString *)localizedStringForCalendarIdentifier:(NSString *)calendarIdentifier;
- (nullable NSString *)localizedStringForCollationIdentifier:(NSString *)collationIdentifier;
- (nullable NSString *)localizedStringForCurrencyCode:(NSString *)currencyCode;
- (nullable NSString *)localizedStringForCollatorIdentifier:(NSString *)collatorIdentifier;
@property (class, readonly, copy) NSArray<NSString *> *availableLocaleIdentifiers, *ISOLanguageCodes, *ISOCountryCodes, *ISOCurrencyCodes,
    *commonISOCurrencyCodes, *preferredLanguages;
+ (NSDictionary<NSString *, NSString *> *)componentsFromLocaleIdentifier:(NSString *)string;
+ (NSString *)localeIdentifierFromComponents:(NSDictionary<NSString *, NSString *> *)dict;
+ (NSString *)canonicalLocaleIdentifierFromString:(NSString *)string;
+ (NSString *)canonicalLanguageIdentifierFromString:(NSString *)string;
+ (NSString *)localeIdentifierFromWindowsLocaleCode:(uint32_t)lcid;
+ (uint32_t)windowsLocaleCodeFromLocaleIdentifier:(NSString *)localeIdentifier;
+ (NSLocaleLanguageDirection)characterDirectionForLanguage:(NSString *)isoLangCode;
+ (NSLocaleLanguageDirection)lineDirectionForLanguage:(NSString *)isoLangCode;
@end

typedef NS_ENUM(NSInteger, NSTimeZoneNameStyle) {
    NSTimeZoneNameStyleStandard, NSTimeZoneNameStyleShortStandard, NSTimeZoneNameStyleDaylightSaving, NSTimeZoneNameStyleShortDaylightSaving,
    NSTimeZoneNameStyleGeneric, NSTimeZoneNameStyleShortGeneric,
} NS_SWIFT_NAME(NSTimeZone.NameStyle);
NS_SWIFT_BRIDGE(TimeZone)
@interface NSTimeZone : NSObject <NSCopying>
@property (readonly, copy) NSString *name; @property (readonly, copy) NSData *data;
- (NSInteger)secondsFromGMTForDate:(NSDate *)aDate;
- (nullable NSString *)abbreviationForDate:(NSDate *)aDate;
- (BOOL)isDaylightSavingTimeForDate:(NSDate *)aDate;
- (NSTimeInterval)daylightSavingTimeOffsetForDate:(NSDate *)aDate;
- (nullable NSDate *)nextDaylightSavingTimeTransitionAfterDate:(NSDate *)aDate;
@property (class, readonly, copy) NSTimeZone *systemTimeZone, *localTimeZone;
@property (class, copy) NSTimeZone *defaultTimeZone;
+ (void)resetSystemTimeZone;
@property (class, readonly, copy) NSArray<NSString *> *knownTimeZoneNames;
@property (class, copy) NSDictionary<NSString *, NSString *> *abbreviationDictionary;
@property (class, readonly, copy) NSString *timeZoneDataVersion;
@property (readonly) NSInteger secondsFromGMT;
@property (nullable, readonly, copy) NSString *abbreviation;
@property (readonly, getter=isDaylightSavingTime) BOOL daylightSavingTime;
@property (readonly) NSTimeInterval daylightSavingTimeOffset;
@property (nullable, readonly, copy) NSDate *nextDaylightSavingTimeTransition;
- (BOOL)isEqualToTimeZone:(NSTimeZone *)aTimeZone;
- (nullable NSString *)localizedName:(NSTimeZoneNameStyle)style locale:(nullable NSLocale *)locale;
+ (nullable instancetype)timeZoneWithName:(NSString *)tzName;
+ (nullable instancetype)timeZoneWithName:(NSString *)tzName data:(NSData *)aData;
- (nullable instancetype)initWithName:(NSString *)tzName;
- (nullable instancetype)initWithName:(NSString *)tzName data:(NSData *)aData;
+ (instancetype)timeZoneForSecondsFromGMT:(NSInteger)seconds;
+ (nullable instancetype)timeZoneWithAbbreviation:(NSString *)abbreviation;
@end

/* ---- character sets */
@interface NSCharacterSet (NSExtendedCharacterSet)
@property (class, readonly, copy) NSCharacterSet *controlCharacterSet, *decomposableCharacterSet, *illegalCharacterSet,
    *capitalizedLetterCharacterSet, *symbolCharacterSet, *nonBaseCharacterSet, *URLUserAllowedCharacterSet,
    *URLPasswordAllowedCharacterSet, *URLHostAllowedCharacterSet, *URLPathAllowedCharacterSet, *URLQueryAllowedCharacterSet,
    *URLFragmentAllowedCharacterSet;
+ (NSCharacterSet *)characterSetWithRange:(NSRange)aRange;
+ (NSCharacterSet *)characterSetWithBitmapRepresentation:(NSData *)data;
+ (nullable NSCharacterSet *)characterSetWithContentsOfFile:(NSString *)fName;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (BOOL)longCharacterIsMember:(uint32_t)theLongChar;
@property (readonly, copy) NSData *bitmapRepresentation;
- (BOOL)isSupersetOfSet:(NSCharacterSet *)theOtherSet;
- (BOOL)hasMemberInPlane:(uint8_t)thePlane;
@end
@interface NSMutableCharacterSet (NSExtendedMutableCharacterSet)
- (void)addCharactersInRange:(NSRange)aRange; - (void)removeCharactersInRange:(NSRange)aRange;
- (void)addCharactersInString:(NSString *)aString; - (void)removeCharactersInString:(NSString *)aString;
- (void)formUnionWithCharacterSet:(NSCharacterSet *)otherSet; - (void)formIntersectionWithCharacterSet:(NSCharacterSet *)otherSet;
- (void)invert;
+ (NSMutableCharacterSet *)characterSetWithCharactersInString:(NSString *)aString;
+ (NSMutableCharacterSet *)characterSetWithRange:(NSRange)aRange;
@end

/* ---- index sets */
typedef NS_OPTIONS(NSUInteger, NSEnumerationOptions) { NSEnumerationConcurrent = 1UL << 0, NSEnumerationReverse = 1UL << 1 };
typedef NS_OPTIONS(NSUInteger, NSSortOptions) { NSSortConcurrent = 1UL << 0, NSSortStable = 1UL << 4 };
NS_SWIFT_BRIDGE(IndexSet)
@interface NSIndexSet : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)indexSet; + (instancetype)indexSetWithIndex:(NSUInteger)value; + (instancetype)indexSetWithIndexesInRange:(NSRange)range;
- (instancetype)initWithIndexesInRange:(NSRange)range NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithIndexSet:(NSIndexSet *)indexSet NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithIndex:(NSUInteger)value;
- (BOOL)isEqualToIndexSet:(NSIndexSet *)indexSet;
@property (readonly) NSUInteger count, firstIndex, lastIndex;
- (NSUInteger)indexGreaterThanIndex:(NSUInteger)value; - (NSUInteger)indexLessThanIndex:(NSUInteger)value;
- (NSUInteger)indexGreaterThanOrEqualToIndex:(NSUInteger)value; - (NSUInteger)indexLessThanOrEqualToIndex:(NSUInteger)value;
- (NSUInteger)getIndexes:(NSUInteger *)indexBuffer maxCount:(NSUInteger)bufferSize inIndexRange:(NSRangePointer)range;
- (NSUInteger)countOfIndexesInRange:(NSRange)range;
- (BOOL)containsIndex:(NSUInteger)value; - (BOOL)containsIndexesInRange:(NSRange)range; - (BOOL)containsIndexes:(NSIndexSet *)indexSet;
- (BOOL)intersectsIndexesInRange:(NSRange)range;
- (void)enumerateIndexesUsingBlock:(void (^)(NSUInteger idx, BOOL *stop))block;
- (void)enumerateRangesUsingBlock:(void (NS_NOESCAPE ^)(NSRange range, BOOL *stop))block;
- (NSIndexSet *)indexesInRange:(NSRange)range options:(NSEnumerationOptions)opts passingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate;
- (NSIndexSet *)indexesPassingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate;
- (NSUInteger)indexPassingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate;
- (void)enumerateIndexesInRange:(NSRange)range options:(NSEnumerationOptions)opts usingBlock:(void (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))block;
@end
@interface NSMutableIndexSet : NSIndexSet
- (void)addIndexes:(NSIndexSet *)indexSet; - (void)removeIndexes:(NSIndexSet *)indexSet; - (void)removeAllIndexes;
- (void)addIndex:(NSUInteger)value; - (void)removeIndex:(NSUInteger)value;
- (void)addIndexesInRange:(NSRange)range; - (void)removeIndexesInRange:(NSRange)range;
- (void)shiftIndexesStartingAtIndex:(NSUInteger)index by:(NSInteger)delta;
@end
@interface NSIndexPath : NSObject <NSCopying>
+ (instancetype)indexPathWithIndex:(NSUInteger)index; + (instancetype)indexPathWithIndexes:(const NSUInteger [])indexes length:(NSUInteger)length;
- (instancetype)initWithIndexes:(const NSUInteger [])indexes length:(NSUInteger)length NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithIndex:(NSUInteger)index;
- (NSUInteger)indexAtPosition:(NSUInteger)position;
@property (readonly) NSUInteger length;
- (void)getIndexes:(NSUInteger *)indexes range:(NSRange)positionRange;
- (NSComparisonResult)compare:(NSIndexPath *)otherObject;
@end

/* ---- data */
typedef NS_OPTIONS(NSUInteger, NSDataReadingOptions) {
    NSDataReadingMappedIfSafe = 1, NSDataReadingUncached = 2, NSDataReadingMappedAlways = 8,
} NS_SWIFT_NAME(NSData.ReadingOptions);
typedef NS_OPTIONS(NSUInteger, NSDataWritingOptions) {
    NSDataWritingAtomic = 1, NSDataWritingWithoutOverwriting = 2, NSDataWritingFileProtectionNone = 0x10000000,
    NSDataWritingFileProtectionComplete = 0x20000000, NSDataWritingFileProtectionCompleteUnlessOpen = 0x30000000,
    NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication = 0x40000000, NSDataWritingFileProtectionMask = 0xf0000000,
} NS_SWIFT_NAME(NSData.WritingOptions);
typedef NS_OPTIONS(NSUInteger, NSDataSearchOptions) {
    NSDataSearchBackwards = 1, NSDataSearchAnchored = 2,
} NS_SWIFT_NAME(NSData.SearchOptions);
typedef NS_OPTIONS(NSUInteger, NSDataBase64EncodingOptions) {
    NSDataBase64Encoding64CharacterLineLength = 1, NSDataBase64Encoding76CharacterLineLength = 2,
    NSDataBase64EncodingEndLineWithCarriageReturn = 16, NSDataBase64EncodingEndLineWithLineFeed = 32,
} NS_SWIFT_NAME(NSData.Base64EncodingOptions);
typedef NS_OPTIONS(NSUInteger, NSDataBase64DecodingOptions) {
    NSDataBase64DecodingIgnoreUnknownCharacters = 1,
} NS_SWIFT_NAME(NSData.Base64DecodingOptions);
@interface NSData (NSExtendedData)
- (NSString *)description;
- (void)getBytes:(void *)buffer length:(NSUInteger)length;
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically;
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)writeOptionsMask error:(NSError **)errorPtr;
- (BOOL)writeToURL:(NSURL *)url options:(NSDataWritingOptions)writeOptionsMask error:(NSError **)errorPtr;
- (NSRange)rangeOfData:(NSData *)dataToFind options:(NSDataSearchOptions)mask range:(NSRange)searchRange NS_SWIFT_NAME(range(of:options:in:));
- (void)enumerateByteRangesUsingBlock:(void (NS_NOESCAPE ^)(const void *bytes, NSRange byteRange, BOOL *stop))block NS_SWIFT_NAME(enumerateBytes(_:));
+ (nullable instancetype)dataWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)readOptionsMask error:(NSError **)errorPtr;
+ (nullable instancetype)dataWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)readOptionsMask error:(NSError **)errorPtr;
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length;
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b;
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length deallocator:(nullable void (^)(void *bytes, NSUInteger length))deallocator;
- (nullable instancetype)initWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)readOptionsMask error:(NSError **)errorPtr;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)readOptionsMask error:(NSError **)errorPtr;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url;
- (instancetype)initWithData:(NSData *)data;
- (nullable instancetype)initWithBase64EncodedString:(NSString *)base64String options:(NSDataBase64DecodingOptions)options NS_SWIFT_NAME(init(base64Encoded:options:));
- (NSString *)base64EncodedStringWithOptions:(NSDataBase64EncodingOptions)options;
- (nullable instancetype)initWithBase64EncodedData:(NSData *)base64Data options:(NSDataBase64DecodingOptions)options NS_SWIFT_NAME(init(base64Encoded:options:));
- (NSData *)base64EncodedDataWithOptions:(NSDataBase64EncodingOptions)options;
@end
@interface NSMutableData (NSExtendedMutableData)
- (instancetype)initWithCapacity:(NSUInteger)capacity; - (instancetype)initWithLength:(NSUInteger)length;
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)replacementBytes length:(NSUInteger)replacementLength;
- (void)setData:(NSData *)data;
@end

/* ---- errors */
FOUNDATION_EXPORT NSErrorDomain const NSOSStatusErrorDomain, NSMachErrorDomain, NSURLErrorDomain, NSStreamSocketSSLErrorDomain,
    NSStreamSOCKSErrorDomain;
FOUNDATION_EXPORT NSErrorUserInfoKey const NSUnderlyingErrorKey, NSMultipleUnderlyingErrorsKey, NSLocalizedFailureReasonErrorKey,
    NSLocalizedRecoverySuggestionErrorKey, NSLocalizedRecoveryOptionsErrorKey, NSRecoveryAttempterErrorKey, NSHelpAnchorErrorKey,
    NSDebugDescriptionErrorKey, NSLocalizedFailureErrorKey, NSStringEncodingErrorKey, NSURLErrorKey, NSURLErrorFailingURLErrorKey,
    NSURLErrorFailingURLStringErrorKey, NSURLErrorFailingURLPeerTrustErrorKey, NSURLErrorBackgroundTaskCancelledReasonKey,
    NSURLErrorNetworkUnavailableReasonKey;
FOUNDATION_EXPORT NSString * const NSURLSessionDownloadTaskResumeData;
@interface NSError (NSExtendedError)
@property (nullable, readonly, copy) NSString *localizedFailureReason, *localizedRecoverySuggestion, *helpAnchor;
@property (nullable, readonly, copy) NSArray<NSString *> *localizedRecoveryOptions;
@property (nullable, readonly, strong) id recoveryAttempter;
@property (readonly, copy) NSArray<NSError *> *underlyingErrors;
+ (void)setUserInfoValueProviderForDomain:(NSErrorDomain)errorDomain provider:(id _Nullable (^ _Nullable)(NSError *err, NSErrorUserInfoKey userInfoKey))provider NS_SWIFT_NAME(setUserInfoValueProvider(forDomain:provider:));
+ (id _Nullable (^ _Nullable)(NSError *err, NSErrorUserInfoKey userInfoKey))userInfoValueProviderForDomain:(NSErrorDomain)errorDomain;
@end
@interface NSObject (NSErrorRecoveryAttempting)
- (void)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex delegate:(id)delegate didRecoverSelector:(SEL)didRecoverSelector contextInfo:(void *)contextInfo;
- (BOOL)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex;
@end


/* ---- collections */
@interface NSArray<ObjectType> (NSExtendedArray)
- (void)getObjects:(ObjectType __unsafe_unretained [])objects range:(NSRange)range;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array copyItems:(BOOL)flag;
- (nullable ObjectType)firstObjectCommonWithArray:(NSArray<ObjectType> *)otherArray;
- (NSArray<ObjectType> *)objectsAtIndexes:(NSIndexSet *)indexes;
- (NSUInteger)indexOfObject:(ObjectType)anObject inRange:(NSRange)range;
- (NSString *)descriptionWithLocale:(nullable id)locale NS_SWIFT_NAME(description(with:));
@end
@interface NSDictionary<KeyType, ObjectType> (NSExtendedDictionary)
- (void)getObjects:(ObjectType __unsafe_unretained [])objects andKeys:(KeyType __unsafe_unretained [])keys count:(NSUInteger)count;
- (instancetype)initWithDictionary:(NSDictionary<KeyType, ObjectType> *)otherDictionary copyItems:(BOOL)flag;
- (NSArray<KeyType> *)allKeysForObject:(ObjectType)anObject;
- (NSArray<ObjectType> *)objectsForKeys:(NSArray<KeyType> *)keys notFoundMarker:(ObjectType)marker;
- (NSString *)descriptionWithLocale:(nullable id)locale NS_SWIFT_NAME(description(with:));
@end
@interface NSSet<ObjectType> (NSExtendedSet)
- (instancetype)initWithSet:(NSSet<ObjectType> *)set copyItems:(BOOL)flag;
- (instancetype)initWithObjects:(const ObjectType [])objects count:(NSUInteger)cnt;
+ (instancetype)setWithObjects:(const ObjectType [])objects count:(NSUInteger)cnt;
- (NSString *)descriptionWithLocale:(nullable id)locale NS_SWIFT_NAME(description(with:));
@end

/* ---- numbers */
typedef struct {
    signed int _exponent:8; unsigned int _length:4; unsigned int _isNegative:1; unsigned int _isCompact:1; unsigned int _reserved:18;
    unsigned short _mantissa[8];
} NSDecimal NS_SWIFT_NAME(Decimal);
typedef NS_ENUM(NSUInteger, NSRoundingMode) { NSRoundPlain NS_SWIFT_NAME(plain), NSRoundDown NS_SWIFT_NAME(down), NSRoundUp NS_SWIFT_NAME(up), NSRoundBankers NS_SWIFT_NAME(bankers) } NS_SWIFT_NAME(NSDecimalNumber.RoundingMode);
typedef NS_ENUM(NSUInteger, NSCalculationError) {
    NSCalculationNoError NS_SWIFT_NAME(noError) = 0, NSCalculationLossOfPrecision NS_SWIFT_NAME(lossOfPrecision), NSCalculationUnderflow NS_SWIFT_NAME(underflow),
    NSCalculationOverflow NS_SWIFT_NAME(overflow), NSCalculationDivideByZero NS_SWIFT_NAME(divideByZero),
} NS_SWIFT_NAME(NSDecimalNumber.CalculationError);
#define NSDecimalMaxSize (8)
FOUNDATION_EXPORT NSUInteger NSPageSize(void);
FOUNDATION_EXPORT void NSCopyMemoryPages(const void *source, void *dest, NSUInteger bytes);
FOUNDATION_EXPORT double NSFoundationVersionNumber;
#define NSFoundationVersionNumber10_11_Max 1299
FOUNDATION_EXPORT NSUInteger NSLogPageSize(void);
FOUNDATION_EXPORT NSUInteger NSRoundUpToMultipleOfPageSize(NSUInteger bytes);
FOUNDATION_EXPORT NSUInteger NSRoundDownToMultipleOfPageSize(NSUInteger bytes);
#define NSDecimalNoScale SHRT_MAX
FOUNDATION_EXPORT void NSDecimalCopy(NSDecimal *destination, const NSDecimal *source);
FOUNDATION_EXPORT void NSDecimalCompact(NSDecimal *number);
FOUNDATION_EXPORT NSComparisonResult NSDecimalCompare(const NSDecimal *leftOperand, const NSDecimal *rightOperand);
FOUNDATION_EXPORT void NSDecimalRound(NSDecimal *result, const NSDecimal *number, NSInteger scale, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalNormalize(NSDecimal *number1, NSDecimal *number2, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalAdd(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalSubtract(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalMultiply(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalDivide(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalPower(NSDecimal *result, const NSDecimal *number, NSUInteger power, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalMultiplyByPowerOf10(NSDecimal *result, const NSDecimal *number, short power, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSString *NSDecimalString(const NSDecimal *dcm, id _Nullable locale);
@interface NSNumber (NSExtendedNumber)
- (instancetype)initWithChar:(char)value NS_SWIFT_NAME(init(value:)); - (instancetype)initWithUnsignedChar:(unsigned char)value NS_SWIFT_NAME(init(value:));
- (instancetype)initWithShort:(short)value NS_SWIFT_NAME(init(value:)); - (instancetype)initWithUnsignedShort:(unsigned short)value NS_SWIFT_NAME(init(value:));
- (instancetype)initWithUnsignedInt:(unsigned int)value NS_SWIFT_NAME(init(value:)); - (instancetype)initWithLong:(long)value NS_SWIFT_NAME(init(value:));
- (instancetype)initWithUnsignedLong:(unsigned long)value NS_SWIFT_NAME(init(value:)); - (instancetype)initWithLongLong:(long long)value NS_SWIFT_NAME(init(value:));
- (instancetype)initWithUnsignedLongLong:(unsigned long long)value NS_SWIFT_NAME(init(value:)); - (instancetype)initWithFloat:(float)value NS_SWIFT_NAME(init(value:));
- (instancetype)initWithUnsignedInteger:(NSUInteger)value NS_SWIFT_NAME(init(value:));
@property (readonly) NSDecimal decimalValue;
- (NSString *)descriptionWithLocale:(nullable id)locale NS_SWIFT_NAME(description(with:));
@end
@interface NSScanner (NSDecimalScanning)
@property (nullable, retain) id locale;
- (BOOL)scanDecimal:(nullable NSDecimal *)dcm;
@end
@interface NSDecimalNumber : NSNumber
- (instancetype)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)flag;
- (instancetype)initWithDecimal:(NSDecimal)dcm NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithString:(NSString *)numberValue;
- (nullable instancetype)initWithString:(NSString *)numberValue locale:(nullable id)locale;
+ (NSDecimalNumber *)decimalNumberWithDecimal:(NSDecimal)dcm;
+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)numberValue;
@property (class, readonly, copy) NSDecimalNumber *zero, *one, *minimumDecimalNumber, *maximumDecimalNumber, *notANumber;
@property (readonly) NSDecimal decimalValue;
@property (readonly) double doubleValue;
@end

/* ---- strings */
typedef NS_OPTIONS(NSUInteger, NSStringEnumerationOptions) {
    NSStringEnumerationByLines = 0, NSStringEnumerationByParagraphs = 1, NSStringEnumerationByComposedCharacterSequences = 2,
    NSStringEnumerationByWords = 3, NSStringEnumerationBySentences = 4, NSStringEnumerationByCaretPositions = 5,
    NSStringEnumerationByDeletionClusters = 6, NSStringEnumerationReverse = 1UL << 8, NSStringEnumerationSubstringNotRequired = 1UL << 9,
    NSStringEnumerationLocalized = 1UL << 10,
} NS_SWIFT_NAME(NSString.EnumerationOptions);
typedef NS_OPTIONS(NSUInteger, NSStringEncodingConversionOptions) {
    NSStringEncodingConversionAllowLossy = 1, NSStringEncodingConversionExternalRepresentation = 2,
} NS_SWIFT_NAME(NSString.EncodingConversionOptions);
@interface NSString (NSExtendedStringForSwift)
@property (readonly, copy) NSString *decomposedStringWithCanonicalMapping, *precomposedStringWithCanonicalMapping,
    *decomposedStringWithCompatibilityMapping, *precomposedStringWithCompatibilityMapping, *localizedUppercaseString,
    *localizedLowercaseString, *localizedCapitalizedString;
@property (nullable, readonly, copy) NSString *stringByRemovingPercentEncoding;
@property (readonly) NSStringEncoding fastestEncoding, smallestEncoding;
@property (class, readonly) const NSStringEncoding *availableStringEncodings;
@property (class, readonly) NSStringEncoding defaultCStringEncoding;
+ (NSString *)localizedNameOfStringEncoding:(NSStringEncoding)encoding NS_SWIFT_NAME(localizedName(of:));
- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)encoding NS_SWIFT_NAME(canBeConverted(to:));
- (nullable NSData *)dataUsingEncoding:(NSStringEncoding)encoding allowLossyConversion:(BOOL)lossy NS_SWIFT_NAME(data(using:allowLossyConversion:));
- (NSUInteger)maximumLengthOfBytesUsingEncoding:(NSStringEncoding)enc NS_SWIFT_NAME(maximumLengthOfBytes(using:));
- (BOOL)getBytes:(void *)buffer maxLength:(NSUInteger)maxBufferCount usedLength:(NSUInteger *)usedBufferCount encoding:(NSStringEncoding)encoding options:(NSStringEncodingConversionOptions)options range:(NSRange)range remainingRange:(nullable NSRangePointer)leftover;
- (BOOL)getFileSystemRepresentation:(char *)cname maxLength:(NSUInteger)max;
- (NSComparisonResult)compare:(NSString *)string options:(NSStringCompareOptions)mask range:(NSRange)rangeOfReceiverToCompare;
- (NSComparisonResult)compare:(NSString *)string options:(NSStringCompareOptions)mask range:(NSRange)rangeOfReceiverToCompare locale:(nullable id)locale;
- (NSComparisonResult)localizedCompare:(NSString *)string;
- (NSComparisonResult)localizedCaseInsensitiveCompare:(NSString *)string;
- (NSComparisonResult)localizedStandardCompare:(NSString *)string;
- (BOOL)localizedCaseInsensitiveContainsString:(NSString *)str;
- (BOOL)localizedStandardContainsString:(NSString *)str;
- (NSRange)localizedStandardRangeOfString:(NSString *)str;
- (NSRange)rangeOfString:(NSString *)searchString options:(NSStringCompareOptions)mask range:(NSRange)rangeOfReceiverToSearch locale:(nullable NSLocale *)locale;
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)searchSet options:(NSStringCompareOptions)mask;
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)searchSet options:(NSStringCompareOptions)mask range:(NSRange)rangeOfReceiverToSearch;
- (NSRange)rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)index;
- (NSRange)rangeOfComposedCharacterSequencesForRange:(NSRange)range;
- (NSString *)commonPrefixWithString:(NSString *)str options:(NSStringCompareOptions)mask;
- (NSString *)capitalizedStringWithLocale:(nullable NSLocale *)locale NS_SWIFT_NAME(capitalized(with:));
- (NSString *)lowercaseStringWithLocale:(nullable NSLocale *)locale NS_SWIFT_NAME(lowercased(with:));
- (NSString *)uppercaseStringWithLocale:(nullable NSLocale *)locale NS_SWIFT_NAME(uppercased(with:));
- (void)getLineStart:(nullable NSUInteger *)startPtr end:(nullable NSUInteger *)lineEndPtr contentsEnd:(nullable NSUInteger *)contentsEndPtr forRange:(NSRange)range;
- (NSRange)lineRangeForRange:(NSRange)range;
- (void)getParagraphStart:(nullable NSUInteger *)startPtr end:(nullable NSUInteger *)parEndPtr contentsEnd:(nullable NSUInteger *)contentsEndPtr forRange:(NSRange)range;
- (NSRange)paragraphRangeForRange:(NSRange)range;
- (void)enumerateSubstringsInRange:(NSRange)range options:(NSStringEnumerationOptions)opts usingBlock:(void (^)(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop))block;
- (NSString *)stringByFoldingWithOptions:(NSStringCompareOptions)options locale:(nullable NSLocale *)locale;
- (nullable NSString *)stringByAddingPercentEncodingWithAllowedCharacters:(NSCharacterSet *)allowedCharacters;
- (nullable NSString *)stringByApplyingTransform:(NSStringTransform)transform reverse:(BOOL)reverse;
- (NSArray<NSString *> *)stringsByAppendingPaths:(NSArray<NSString *> *)paths;
- (NSUInteger)completePathIntoString:(NSString * _Nullable * _Nullable)outputName caseSensitive:(BOOL)flag matchesIntoArray:(NSArray<NSString *> * _Nullable * _Nullable)outputArray filterTypes:(nullable NSArray<NSString *> *)filterTypes;
@property (readonly, copy) NSString *stringByAbbreviatingWithTildeInPath, *stringByResolvingSymlinksInPath;
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)useAuxiliaryFile encoding:(NSStringEncoding)enc error:(NSError **)error;
- (nullable instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)len encoding:(NSStringEncoding)encoding freeWhenDone:(BOOL)freeBuffer;
- (instancetype)initWithCharactersNoCopy:(unichar *)characters length:(NSUInteger)length freeWhenDone:(BOOL)freeBuffer;
- (nullable instancetype)initWithCString:(const char *)nullTerminatedCString encoding:(NSStringEncoding)encoding;
- (instancetype)initWithFormat:(NSString *)format locale:(nullable id)locale, ... NS_FORMAT_FUNCTION(1, 3);
- (instancetype)initWithFormat:(NSString *)format locale:(nullable id)locale arguments:(va_list)argList NS_FORMAT_FUNCTION(1, 0);
+ (instancetype)localizedStringWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url encoding:(NSStringEncoding)enc error:(NSError **)error;
- (nullable instancetype)initWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url usedEncoding:(nullable NSStringEncoding *)enc error:(NSError **)error;
- (nullable instancetype)initWithContentsOfFile:(NSString *)path usedEncoding:(nullable NSStringEncoding *)enc error:(NSError **)error;
+ (nullable instancetype)stringWithContentsOfFile:(NSString *)path usedEncoding:(nullable NSStringEncoding *)enc error:(NSError **)error;
+ (nullable instancetype)stringWithContentsOfURL:(NSURL *)url usedEncoding:(nullable NSStringEncoding *)enc error:(NSError **)error;
- (nullable NSString *)stringByReplacingPercentEscapesUsingEncoding:(NSStringEncoding)enc NS_SWIFT_NAME(replacingPercentEscapes(using:));
- (nullable NSString *)stringByAddingPercentEscapesUsingEncoding:(NSStringEncoding)enc NS_SWIFT_NAME(addingPercentEscapes(using:));
- (NSArray<NSString *> *)componentsSeparatedByString:(NSString *)separator NS_SWIFT_NAME(components(separatedBy:));
- (NSArray<NSString *> *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)separator NS_SWIFT_NAME(components(separatedBy:));
- (BOOL)containsString:(NSString *)str;
- (NSString *)substringWithRange:(NSRange)range;
- (id)propertyList;
- (nullable NSDictionary *)propertyListFromStringsFileFormat;
- (void)enumerateLinguisticTagsInRange:(NSRange)range scheme:(NSLinguisticTagScheme)scheme options:(NSLinguisticTaggerOptions)options orthography:(nullable NSOrthography *)orthography usingBlock:(void (NS_NOESCAPE ^)(NSLinguisticTag _Nullable tag, NSRange tokenRange, NSRange sentenceRange, BOOL *stop))block NS_SWIFT_NAME(enumerateLinguisticTags(in:scheme:options:orthography:using:));
- (NSArray<NSString *> *)linguisticTagsInRange:(NSRange)range scheme:(NSLinguisticTagScheme)scheme options:(NSLinguisticTaggerOptions)opts orthography:(nullable NSOrthography *)orthography tokenRanges:(NSArray<NSValue *> * _Nullable * _Nullable)tokenRanges;
@end
@interface NSMutableString (NSExtendedMutableStringForSwift)
- (BOOL)applyTransform:(NSStringTransform)transform reverse:(BOOL)reverse range:(NSRange)range updatedRange:(NSRangePointer)resultingRange;
@end
FOUNDATION_EXPORT NSStringEncodingDetectionOptionsKey const NSStringEncodingDetectionSuggestedEncodingsKey,
    NSStringEncodingDetectionDisallowedEncodingsKey, NSStringEncodingDetectionUseOnlySuggestedEncodingsKey,
    NSStringEncodingDetectionAllowLossyKey, NSStringEncodingDetectionFromWindowsKey, NSStringEncodingDetectionLossySubstitutionKey,
    NSStringEncodingDetectionLikelyLanguageKey;
FOUNDATION_EXPORT NSStringTransform const NSStringTransformLatinToKatakana, NSStringTransformLatinToHiragana,
    NSStringTransformLatinToHangul, NSStringTransformLatinToArabic, NSStringTransformLatinToHebrew, NSStringTransformLatinToThai,
    NSStringTransformLatinToCyrillic, NSStringTransformLatinToGreek, NSStringTransformToLatin, NSStringTransformMandarinToLatin,
    NSStringTransformHiraganaToKatakana, NSStringTransformFullwidthToHalfwidth, NSStringTransformToXMLHex,
    NSStringTransformToUnicodeName, NSStringTransformStripCombiningMarks, NSStringTransformStripDiacritics;


/* ---- bundles */
@interface NSBundle (NSExtendedBundle)
+ (nullable NSBundle *)bundleForClass:(Class)aClass;
+ (nullable NSBundle *)bundleWithIdentifier:(NSString *)identifier;
+ (nullable instancetype)bundleWithURL:(NSURL *)url;
- (nullable instancetype)initWithPath:(NSString *)path; - (instancetype)initWithURL:(NSURL *)url;
@property (class, readonly, copy) NSArray<NSBundle *> *allBundles, *allFrameworks;
@property (readonly, copy) NSURL *bundleURL;
@property (nullable, readonly, copy) NSURL *resourceURL, *executableURL, *privateFrameworksURL, *sharedFrameworksURL, *builtInPlugInsURL;
@property (nullable, readonly, copy) NSDictionary<NSString *, id> *localizedInfoDictionary;
- (nullable id)objectForInfoDictionaryKey:(NSString *)key;
- (nullable NSURL *)URLForResource:(NSString *)name withExtension:(nullable NSString *)ext;
- (nullable NSURL *)URLForResource:(NSString *)name withExtension:(nullable NSString *)ext subdirectory:(nullable NSString *)subpath;
- (nullable NSString *)pathForResource:(NSString *)name ofType:(nullable NSString *)ext;
- (nullable NSString *)pathForResource:(NSString *)name ofType:(nullable NSString *)ext inDirectory:(nullable NSString *)subpath;
- (NSString *)localizedStringForKey:(NSString *)key value:(nullable NSString *)value table:(nullable NSString *)tableName;
- (BOOL)load; @property (readonly, getter=isLoaded) BOOL loaded; - (BOOL)unload;
- (nullable Class)principalClass; - (Class)classNamed:(NSString *)className;
@property (readonly, copy) NSArray<NSString *> *preferredLocalizations, *localizations;
@property (nullable, readonly, copy) NSString *developmentLocalization;
@end

/* ---- formatters */
NS_SWIFT_NAME(Formatter)
@interface NSFormatter : NSObject <NSCopying>
- (nullable NSString *)stringForObjectValue:(id)obj;
- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string errorDescription:(out NSString * _Nullable * _Nullable)error;
@end
typedef NS_ENUM(NSUInteger, NSDateFormatterStyle) {
    NSDateFormatterNoStyle NS_SWIFT_NAME(none) = 0, NSDateFormatterShortStyle NS_SWIFT_NAME(short) = 1,
    NSDateFormatterMediumStyle NS_SWIFT_NAME(medium) = 2, NSDateFormatterLongStyle NS_SWIFT_NAME(long) = 3,
    NSDateFormatterFullStyle NS_SWIFT_NAME(full) = 4,
} NS_SWIFT_NAME(DateFormatter.Style);
NS_SWIFT_NAME(DateFormatter)
@interface NSDateFormatter : NSFormatter
@property (null_resettable, copy) NSString *dateFormat; @property NSDateFormatterStyle dateStyle, timeStyle;
@property (null_resettable, copy) NSLocale *locale; @property (null_resettable, copy) NSTimeZone *timeZone; @property (null_resettable, copy) NSCalendar *calendar;
@property BOOL generatesCalendarDates, lenient, doesRelativeDateFormatting;
@property (nullable, copy) NSDate *twoDigitStartDate, *defaultDate;
- (NSString *)stringFromDate:(NSDate *)date;
- (nullable NSDate *)dateFromString:(NSString *)string;
+ (NSString *)localizedStringFromDate:(NSDate *)date dateStyle:(NSDateFormatterStyle)dstyle timeStyle:(NSDateFormatterStyle)tstyle;
+ (nullable NSString *)dateFormatFromTemplate:(NSString *)tmplate options:(NSUInteger)opts locale:(nullable NSLocale *)locale;
- (void)setLocalizedDateFormatFromTemplate:(NSString *)dateFormatTemplate;
@end
typedef NS_OPTIONS(NSUInteger, NSISO8601DateFormatOptions) {
    NSISO8601DateFormatWithYear = 1, NSISO8601DateFormatWithMonth = 2, NSISO8601DateFormatWithWeekOfYear = 4,
    NSISO8601DateFormatWithDay = 16, NSISO8601DateFormatWithTime = 32, NSISO8601DateFormatWithTimeZone = 64,
    NSISO8601DateFormatWithSpaceBetweenDateAndTime = 128, NSISO8601DateFormatWithDashSeparatorInDate = 256,
    NSISO8601DateFormatWithColonSeparatorInTime = 512, NSISO8601DateFormatWithColonSeparatorInTimeZone = 1024,
    NSISO8601DateFormatWithFractionalSeconds = 2048, NSISO8601DateFormatWithFullDate = 16 | 2 | 1 | 256,
    NSISO8601DateFormatWithFullTime = 32 | 512 | 64 | 1024,
    NSISO8601DateFormatWithInternetDateTime = (16 | 2 | 1 | 256) | (32 | 512 | 64 | 1024),
} NS_SWIFT_NAME(ISO8601DateFormatter.Options);
NS_SWIFT_NAME(ISO8601DateFormatter)
@interface NSISO8601DateFormatter : NSFormatter
@property (null_resettable, copy) NSTimeZone *timeZone; @property NSISO8601DateFormatOptions formatOptions;
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (NSString *)stringFromDate:(NSDate *)date;
- (nullable NSDate *)dateFromString:(NSString *)string;
+ (NSString *)stringFromDate:(NSDate *)date timeZone:(NSTimeZone *)timeZone formatOptions:(NSISO8601DateFormatOptions)formatOptions;
@end

/* ---- property lists and archiving */
typedef NS_OPTIONS(NSUInteger, NSPropertyListMutabilityOptions) {
    NSPropertyListImmutable = 0, NSPropertyListMutableContainers = 1, NSPropertyListMutableContainersAndLeaves = 2,
} NS_SWIFT_NAME(PropertyListSerialization.MutabilityOptions);
typedef NS_ENUM(NSUInteger, NSPropertyListFormat) {
    NSPropertyListOpenStepFormat NS_SWIFT_NAME(openStep) = 1, NSPropertyListXMLFormat_v1_0 NS_SWIFT_NAME(xml) = 100, NSPropertyListBinaryFormat_v1_0 NS_SWIFT_NAME(binary) = 200,
} NS_SWIFT_NAME(PropertyListSerialization.PropertyListFormat);
typedef NSPropertyListMutabilityOptions NSPropertyListReadOptions NS_SWIFT_NAME(PropertyListSerialization.ReadOptions);
typedef NSUInteger NSPropertyListWriteOptions NS_SWIFT_NAME(PropertyListSerialization.WriteOptions);
NS_SWIFT_NAME(PropertyListSerialization)
@interface NSPropertyListSerialization : NSObject
+ (BOOL)propertyList:(id)plist isValidForFormat:(NSPropertyListFormat)format;
+ (nullable NSData *)dataWithPropertyList:(id)plist format:(NSPropertyListFormat)format options:(NSPropertyListWriteOptions)opt error:(out NSError **)error NS_SWIFT_NAME(data(fromPropertyList:format:options:));
+ (nullable id)propertyListWithData:(NSData *)data options:(NSPropertyListReadOptions)opt format:(nullable NSPropertyListFormat *)format error:(out NSError **)error NS_SWIFT_NAME(propertyList(from:options:format:));
@end
typedef NS_ENUM(NSInteger, NSDecodingFailurePolicy) { NSDecodingFailurePolicyRaiseException, NSDecodingFailurePolicySetErrorAndReturn };
@interface NSCoder : NSObject
- (void)encodeObject:(nullable id)object; - (id)decodeObject;
- (void)encodeObject:(nullable id)object forKey:(NSString *)key; - (id)decodeObjectForKey:(NSString *)key;
- (void)encodeBool:(BOOL)value forKey:(NSString *)key; - (BOOL)decodeBoolForKey:(NSString *)key;
- (void)encodeInteger:(NSInteger)value forKey:(NSString *)key; - (NSInteger)decodeIntegerForKey:(NSString *)key;
- (void)encodeDouble:(double)value forKey:(NSString *)key; - (double)decodeDoubleForKey:(NSString *)key;
- (void)encodeInt64:(int64_t)value forKey:(NSString *)key; - (int64_t)decodeInt64ForKey:(NSString *)key;
- (BOOL)containsValueForKey:(NSString *)key;
@property (readonly) BOOL allowsKeyedCoding, requiresSecureCoding;
- (nullable id)decodeObjectOfClass:(Class)aClass forKey:(NSString *)key;
- (nullable id)decodeObjectOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key;
- (nullable id)decodeTopLevelObjectAndReturnError:(NSError **)error;
- (nullable id)decodeTopLevelObjectForKey:(NSString *)key error:(NSError **)error;
- (int)decodeIntForKey:(NSString *)key; - (int32_t)decodeInt32ForKey:(NSString *)key; - (float)decodeFloatForKey:(NSString *)key;
- (nullable const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(nullable NSUInteger *)lengthp;
- (void)encodeInt:(int)v forKey:(NSString *)k; - (void)encodeInt32:(int32_t)v forKey:(NSString *)k; - (void)encodeFloat:(float)v forKey:(NSString *)k;
- (void)encodeBytes:(nullable const uint8_t *)b length:(NSUInteger)n forKey:(NSString *)k;
- (void)encodeConditionalObject:(nullable id)o forKey:(NSString *)k;
- (nullable id)decodeArrayOfObjectsOfClass:(Class)cls forKey:(NSString *)key;
- (nullable id)decodeDictionaryWithKeysOfClass:(Class)keyCls objectsOfClass:(Class)objectCls forKey:(NSString *)key;
- (void)failWithError:(NSError *)error; @property (nullable, readonly, copy) NSError *error; @property (readonly) NSDecodingFailurePolicy decodingFailurePolicy;
- (nullable id)decodeTopLevelObjectOfClass:(Class)aClass forKey:(NSString *)key error:(NSError **)error;
- (nullable id)decodeTopLevelObjectOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key error:(NSError **)error;
@end
@interface NSCoder (NSGeometryKeyedCoding)
- (void)encodePoint:(NSPoint)p forKey:(NSString *)k; - (void)encodeSize:(NSSize)s forKey:(NSString *)k; - (void)encodeRect:(NSRect)r forKey:(NSString *)k;
- (NSPoint)decodePointForKey:(NSString *)k; - (NSSize)decodeSizeForKey:(NSString *)k; - (NSRect)decodeRectForKey:(NSString *)k;
@end
@protocol NSCoding - (void)encodeWithCoder:(NSCoder *)coder; - (nullable instancetype)initWithCoder:(NSCoder *)coder; @end
@class NSKeyedArchiver;
extern NSString *const NSKeyedArchiveRootObjectKey, *const NSInvalidArchiveOperationException, *const NSInvalidUnarchiveOperationException;
@interface NSObject (NSCoderMethods)
@property (readonly) Class classForCoder; @property (nullable, readonly) Class classForKeyedArchiver;
- (nullable id)awakeAfterUsingCoder:(NSCoder *)coder; - (nullable id)replacementObjectForKeyedArchiver:(NSKeyedArchiver *)archiver;
@end
@protocol NSSecureCoding <NSCoding> @property (class, readonly) BOOL supportsSecureCoding; @end
@interface NSKeyedArchiver : NSCoder
- (instancetype)initRequiringSecureCoding:(BOOL)requiresSecureCoding;
@property NSPropertyListFormat outputFormat;
+ (BOOL)archiveRootObject:(id)rootObject toFile:(NSString *)path;
- (void)setClassName:(nullable NSString *)codedName forClass:(Class)cls; + (void)setClassName:(nullable NSString *)codedName forClass:(Class)cls;
+ (nullable NSData *)archivedDataWithRootObject:(id)object requiringSecureCoding:(BOOL)requiresSecureCoding error:(NSError **)error;
+ (nullable NSData *)archivedDataWithRootObject:(id)rootObject;
@property (readonly, strong) NSData *encodedData;
- (void)finishEncoding;
@end
@interface NSKeyedUnarchiver : NSCoder
- (nullable instancetype)initForReadingFromData:(NSData *)data error:(NSError **)error;
- (nullable instancetype)initForReadingWithData:(NSData *)data;
- (void)finishDecoding; @property BOOL requiresSecureCoding;
- (void)setClass:(nullable Class)cls forClassName:(NSString *)codedName; - (nullable Class)classForClassName:(NSString *)codedName;
+ (nullable id)unarchiveObjectWithFile:(NSString *)path;
+ (nullable id)unarchivedObjectOfClass:(Class)cls fromData:(NSData *)data error:(NSError **)error;
+ (nullable id)unarchivedObjectOfClasses:(NSSet<Class> *)classes fromData:(NSData *)data error:(NSError **)error;
+ (nullable id)unarchiveObjectWithData:(NSData *)data;
+ (nullable id)unarchiveTopLevelObjectWithData:(NSData *)data error:(NSError **)error;
+ (void)setClass:(Class)cls forClassName:(NSString *)codedName;
+ (nullable Class)classForClassName:(NSString *)codedName;
@end

/* ---- URLs */
typedef NS_OPTIONS(NSUInteger, NSURLBookmarkCreationOptions) {
    NSURLBookmarkCreationPreferFileIDResolution = 1UL << 8, NSURLBookmarkCreationMinimalBookmark = 1UL << 9,
    NSURLBookmarkCreationSuitableForBookmarkFile = 1UL << 10, NSURLBookmarkCreationWithSecurityScope = 1 << 11,
    NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess = 1 << 12, NSURLBookmarkCreationWithoutImplicitSecurityScope = 1 << 29,
} NS_SWIFT_NAME(NSURL.BookmarkCreationOptions);
typedef NS_OPTIONS(NSUInteger, NSURLBookmarkResolutionOptions) {
    NSURLBookmarkResolutionWithoutUI = 1UL << 8, NSURLBookmarkResolutionWithoutMounting = 1UL << 9,
    NSURLBookmarkResolutionWithSecurityScope = 1 << 10, NSURLBookmarkResolutionWithoutImplicitStartAccessing = 1 << 15,
} NS_SWIFT_NAME(NSURL.BookmarkResolutionOptions);
typedef NSUInteger NSURLBookmarkFileCreationOptions NS_SWIFT_NAME(NSURL.BookmarkFileCreationOptions);
FOUNDATION_EXPORT NSURLResourceKey const NSURLKeysOfUnsetValuesKey, NSURLNameKey, NSURLLocalizedNameKey, NSURLIsRegularFileKey,
    NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey, NSURLIsVolumeKey, NSURLIsPackageKey, NSURLIsApplicationKey,
    NSURLApplicationIsScriptableKey, NSURLIsSystemImmutableKey, NSURLIsUserImmutableKey, NSURLIsHiddenKey, NSURLHasHiddenExtensionKey,
    NSURLCreationDateKey, NSURLContentAccessDateKey, NSURLContentModificationDateKey, NSURLAttributeModificationDateKey,
    NSURLLinkCountKey, NSURLParentDirectoryURLKey, NSURLVolumeURLKey, NSURLTypeIdentifierKey, NSURLContentTypeKey,
    NSURLLocalizedTypeDescriptionKey, NSURLLabelNumberKey, NSURLLabelColorKey, NSURLLocalizedLabelKey, NSURLEffectiveIconKey,
    NSURLCustomIconKey, NSURLFileResourceIdentifierKey, NSURLVolumeIdentifierKey, NSURLPreferredIOBlockSizeKey,
    NSURLIsReadableKey, NSURLIsWritableKey, NSURLIsExecutableKey, NSURLFileSecurityKey, NSURLIsExcludedFromBackupKey,
    NSURLTagNamesKey, NSURLPathKey, NSURLCanonicalPathKey, NSURLIsMountTriggerKey, NSURLGenerationIdentifierKey,
    NSURLDocumentIdentifierKey, NSURLAddedToDirectoryDateKey, NSURLQuarantinePropertiesKey, NSURLFileResourceTypeKey,
    NSURLFileContentIdentifierKey, NSURLMayShareFileContentKey, NSURLMayHaveExtendedAttributesKey, NSURLIsPurgeableKey,
    NSURLIsSparseKey, NSURLThumbnailDictionaryKey, NSURLThumbnailKey, NSURLFileSizeKey, NSURLFileAllocatedSizeKey,
    NSURLTotalFileSizeKey, NSURLTotalFileAllocatedSizeKey, NSURLIsAliasFileKey, NSURLFileProtectionKey,
    NSURLDirectoryEntryCountKey, NSURLVolumeLocalizedFormatDescriptionKey, NSURLVolumeTotalCapacityKey,
    NSURLVolumeAvailableCapacityKey, NSURLVolumeResourceCountKey, NSURLVolumeNameKey, NSURLVolumeLocalizedNameKey,
    NSURLVolumeIsLocalKey, NSURLVolumeIsReadOnlyKey, NSURLVolumeIsRemovableKey, NSURLVolumeIsEjectableKey,
    NSURLVolumeIsInternalKey, NSURLVolumeUUIDStringKey, NSURLIsUbiquitousItemKey, NSURLUbiquitousItemHasUnresolvedConflictsKey,
    NSURLUbiquitousItemIsDownloadingKey, NSURLUbiquitousItemIsUploadedKey, NSURLUbiquitousItemIsUploadingKey,
    NSURLUbiquitousItemDownloadingStatusKey, NSURLUbiquitousItemDownloadingErrorKey, NSURLUbiquitousItemUploadingErrorKey,
    NSURLUbiquitousItemContainerDisplayNameKey, NSURLUbiquitousItemIsSharedKey, NSURLVolumeAvailableCapacityForImportantUsageKey,
    NSURLVolumeAvailableCapacityForOpportunisticUsageKey, NSURLVolumeSupportsFileCloningKey,
    NSURLUbiquitousItemDownloadRequestedKey, NSURLUbiquitousSharedItemCurrentUserPermissionsKey, NSURLUbiquitousSharedItemCurrentUserRoleKey, NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey, NSURLUbiquitousSharedItemOwnerNameComponentsKey, NSURLVolumeCreationDateKey, NSURLVolumeIsAutomountedKey, NSURLVolumeIsBrowsableKey, NSURLVolumeIsEncryptedKey, NSURLVolumeIsJournalingKey, NSURLVolumeIsRootFileSystemKey, NSURLVolumeMaximumFileSizeKey, NSURLVolumeSupportsAccessPermissionsKey, NSURLVolumeSupportsAdvisoryFileLockingKey, NSURLVolumeSupportsCasePreservedNamesKey, NSURLVolumeSupportsCaseSensitiveNamesKey, NSURLVolumeSupportsCompressionKey, NSURLVolumeSupportsExclusiveRenamingKey, NSURLVolumeSupportsExtendedSecurityKey, NSURLVolumeSupportsHardLinksKey, NSURLVolumeSupportsImmutableFilesKey, NSURLVolumeSupportsJournalingKey, NSURLVolumeSupportsPersistentIDsKey, NSURLVolumeSupportsRenamingKey, NSURLVolumeSupportsRootDirectoryDatesKey, NSURLVolumeSupportsSparseFilesKey, NSURLVolumeSupportsSwapRenamingKey, NSURLVolumeSupportsSymbolicLinksKey, NSURLVolumeSupportsVolumeSizesKey, NSURLVolumeSupportsZeroRunsKey, NSURLVolumeURLForRemountingKey;
FOUNDATION_EXPORT NSURLFileResourceType const NSURLFileResourceTypeNamedPipe, NSURLFileResourceTypeCharacterSpecial,
    NSURLFileResourceTypeDirectory, NSURLFileResourceTypeBlockSpecial, NSURLFileResourceTypeRegular,
    NSURLFileResourceTypeSymbolicLink, NSURLFileResourceTypeSocket, NSURLFileResourceTypeUnknown;
@interface NSURL (NSExtendedURL) <NSSecureCoding>
- (nullable instancetype)initWithScheme:(NSString *)scheme host:(nullable NSString *)host path:(NSString *)path;
- (instancetype)initFileURLWithPath:(NSString *)path isDirectory:(BOOL)isDir relativeToURL:(nullable NSURL *)baseURL;
- (instancetype)initFileURLWithPath:(NSString *)path relativeToURL:(nullable NSURL *)baseURL;
- (instancetype)initFileURLWithPath:(NSString *)path isDirectory:(BOOL)isDir;
+ (NSURL *)fileURLWithPath:(NSString *)path isDirectory:(BOOL)isDir relativeToURL:(nullable NSURL *)baseURL;
+ (NSURL *)fileURLWithPath:(NSString *)path relativeToURL:(nullable NSURL *)baseURL;
- (instancetype)initFileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL)isDir relativeToURL:(nullable NSURL *)baseURL;
+ (NSURL *)fileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL)isDir relativeToURL:(nullable NSURL *)baseURL;
- (nullable instancetype)initWithString:(NSString *)URLString relativeToURL:(nullable NSURL *)baseURL;
+ (nullable instancetype)URLWithString:(NSString *)URLString relativeToURL:(nullable NSURL *)baseURL;
- (instancetype)initWithDataRepresentation:(NSData *)data relativeToURL:(nullable NSURL *)baseURL;
+ (NSURL *)URLWithDataRepresentation:(NSData *)data relativeToURL:(nullable NSURL *)baseURL;
- (instancetype)initAbsoluteURLWithDataRepresentation:(NSData *)data relativeToURL:(nullable NSURL *)baseURL;
+ (NSURL *)absoluteURLWithDataRepresentation:(NSData *)data relativeToURL:(nullable NSURL *)baseURL;
@property (readonly, copy) NSData *dataRepresentation;
@property (readonly, copy) NSString *relativeString;
@property (nullable, readonly, copy) NSString *resourceSpecifier, *user, *password, *relativePath, *fragment, *parameterString, *query;
@property (nullable, readonly, copy) NSURL *baseURL NS_SWIFT_NAME(baseURL);
@property (nullable, readonly, copy) NSURL *absoluteURL NS_SWIFT_NAME(absoluteURL);
@property (nullable, readonly, copy) NSURL *standardizedURL NS_SWIFT_NAME(standardized);
@property (nullable, readonly, copy) NSURL *filePathURL NS_SWIFT_NAME(filePathURL);
- (nullable NSURL *)fileReferenceURL;
@property (nullable, readonly, copy) NSNumber *port;
@property (readonly) BOOL hasDirectoryPath;
- (BOOL)getFileSystemRepresentation:(char *)buffer maxLength:(NSUInteger)maxBufferLength;
- (BOOL)isFileReferenceURL;
- (BOOL)getResourceValue:(out id _Nullable * _Nullable)value forKey:(NSURLResourceKey)key error:(out NSError **)error;
- (nullable NSDictionary<NSURLResourceKey, id> *)resourceValuesForKeys:(NSArray<NSURLResourceKey> *)keys error:(NSError **)error;
- (BOOL)setResourceValue:(nullable id)value forKey:(NSURLResourceKey)key error:(NSError **)error;
- (BOOL)setResourceValues:(NSDictionary<NSURLResourceKey, id> *)keyedValues error:(NSError **)error;
- (void)removeCachedResourceValueForKey:(NSURLResourceKey)key; - (void)removeAllCachedResourceValues;
- (void)setTemporaryResourceValue:(nullable id)value forKey:(NSURLResourceKey)key;
- (nullable NSData *)bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)options includingResourceValuesForKeys:(nullable NSArray<NSURLResourceKey> *)keys relativeToURL:(nullable NSURL *)relativeURL error:(NSError **)error;
- (nullable instancetype)initByResolvingBookmarkData:(NSData *)bookmarkData options:(NSURLBookmarkResolutionOptions)options relativeToURL:(nullable NSURL *)relativeURL bookmarkDataIsStale:(nullable BOOL *)isStale error:(NSError **)error NS_SWIFT_NAME(init(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:));
+ (nullable instancetype)URLByResolvingBookmarkData:(NSData *)bookmarkData options:(NSURLBookmarkResolutionOptions)options relativeToURL:(nullable NSURL *)relativeURL bookmarkDataIsStale:(nullable BOOL *)isStale error:(NSError **)error;
+ (nullable NSDictionary<NSURLResourceKey, id> *)resourceValuesForKeys:(NSArray<NSURLResourceKey> *)keys fromBookmarkData:(NSData *)bookmarkData;
+ (BOOL)writeBookmarkData:(NSData *)bookmarkData toURL:(NSURL *)bookmarkFileURL options:(NSURLBookmarkFileCreationOptions)options error:(NSError **)error;
+ (nullable NSData *)bookmarkDataWithContentsOfURL:(NSURL *)bookmarkFileURL error:(NSError **)error;
+ (nullable instancetype)URLByResolvingAliasFileAtURL:(NSURL *)url options:(NSURLBookmarkResolutionOptions)options error:(NSError **)error NS_SWIFT_NAME(init(resolvingAliasFileAt:options:));
- (BOOL)startAccessingSecurityScopedResource; - (void)stopAccessingSecurityScopedResource;
- (BOOL)checkResourceIsReachableAndReturnError:(NSError **)error NS_SWIFT_NOTHROW;
- (BOOL)checkPromisedItemIsReachableAndReturnError:(NSError **)error NS_SWIFT_NOTHROW;
- (BOOL)getPromisedItemResourceValue:(id _Nullable * _Nullable)value forKey:(NSURLResourceKey)key error:(NSError **)error;
- (nullable NSDictionary<NSURLResourceKey, id> *)promisedItemResourceValuesForKeys:(NSArray<NSURLResourceKey> *)keys error:(NSError **)error;
+ (nullable NSURL *)fileURLWithPathComponents:(NSArray<NSString *> *)components;
@property (nullable, readonly, copy) NSArray<NSString *> *pathComponents;
- (nullable NSURL *)URLByAppendingPathComponent:(NSString *)pathComponent isDirectory:(BOOL)isDirectory;
- (nullable NSURL *)URLByAppendingPathExtension:(NSString *)pathExtension;
@property (nullable, readonly, copy) NSURL *URLByDeletingPathExtension NS_SWIFT_NAME(deletingPathExtension);
@property (nullable, readonly, copy) NSURL *URLByStandardizingPath NS_SWIFT_NAME(standardizingPath);
@property (nullable, readonly, copy) NSURL *URLByResolvingSymlinksInPath NS_SWIFT_NAME(resolvingSymlinksInPath);
@end
NS_SWIFT_BRIDGE(URLComponents)
@interface NSURLComponents : NSObject <NSCopying>
- (instancetype)init;
- (nullable instancetype)initWithURL:(NSURL *)url resolvingAgainstBaseURL:(BOOL)resolve;
+ (nullable instancetype)componentsWithURL:(NSURL *)url resolvingAgainstBaseURL:(BOOL)resolve;
- (nullable instancetype)initWithString:(NSString *)URLString;
+ (nullable instancetype)componentsWithString:(NSString *)URLString;
@property (nullable, readonly, copy) NSURL *URL;
- (nullable NSURL *)URLRelativeToURL:(nullable NSURL *)baseURL NS_SWIFT_NAME(url(relativeTo:));
@property (nullable, readonly, copy) NSString *string;
@property (nullable, copy) NSString *scheme, *user, *password, *host, *query, *fragment;
@property (null_resettable, copy) NSString *path;
@property (nullable, copy) NSNumber *port;
@property (nullable, copy) NSString *percentEncodedUser, *percentEncodedPassword, *percentEncodedHost, *percentEncodedPath,
    *percentEncodedQuery, *percentEncodedFragment, *encodedHost;
@property (readonly) NSRange rangeOfScheme, rangeOfUser, rangeOfPassword, rangeOfHost, rangeOfPort, rangeOfPath, rangeOfQuery, rangeOfFragment;
@property (nullable, copy) NSArray<NSURLQueryItem *> *queryItems, *percentEncodedQueryItems;
@end
NS_SWIFT_BRIDGE(URLQueryItem)
@interface NSURLQueryItem : NSObject <NSCopying>
- (instancetype)initWithName:(NSString *)name value:(nullable NSString *)value NS_DESIGNATED_INITIALIZER;
+ (instancetype)queryItemWithName:(NSString *)name value:(nullable NSString *)value;
@property (readonly) NSString *name; @property (nullable, readonly) NSString *value;
@end


/* ---- small classes the overlay names */
@interface NSOrthography : NSObject <NSCopying>
@property (readonly, copy) NSString *dominantScript;
@property (readonly, copy) NSDictionary<NSString *, NSArray<NSString *> *> *languageMap;
+ (instancetype)defaultOrthographyForLanguage:(NSString *)language;
@end
@interface NSLinguisticTagger : NSObject
@end
@interface NSFileSecurity : NSObject <NSCopying>
@end
NS_SWIFT_BRIDGE(PersonNameComponents)
@interface NSPersonNameComponents : NSObject <NSCopying>
@property (nullable, copy) NSString *namePrefix, *givenName, *middleName, *familyName, *nameSuffix, *nickname;
@property (nullable, copy) NSPersonNameComponents *phoneticRepresentation;
@end

/* ---------------- more.m: invocations, undo, sorting, transformers, streams, URL requests, scripting stand-ins */
NS_SWIFT_UNAVAILABLE("NSInvocation and related APIs not available")
@interface NSMethodSignature : NSObject
+ (nullable NSMethodSignature *)signatureWithObjCTypes:(const char *)types;
@property (readonly) NSUInteger numberOfArguments, frameLength, methodReturnLength;
- (const char *)getArgumentTypeAtIndex:(NSUInteger)i;
@property (readonly) const char *methodReturnType;
- (BOOL)isOneway;
@end
NS_SWIFT_UNAVAILABLE("NSInvocation and related APIs not available")
@interface NSInvocation : NSObject
+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig;
@property (readonly, retain) NSMethodSignature *methodSignature;
- (void)retainArguments; @property (readonly) BOOL argumentsRetained;
@property (nullable, assign) id target; @property SEL selector;
- (void)getReturnValue:(void *)b; - (void)setReturnValue:(void *)b;
- (void)getArgument:(void *)b atIndex:(NSInteger)i; - (void)setArgument:(void *)b atIndex:(NSInteger)i;
- (void)invoke; - (void)invokeWithTarget:(id)t;
@end
@interface NSObject (MWForwarding)
- (nullable NSMethodSignature *)methodSignatureForSelector:(SEL)s NS_SWIFT_UNAVAILABLE("");
+ (nullable NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)s NS_SWIFT_UNAVAILABLE("");
- (void)forwardInvocation:(NSInvocation *)i NS_SWIFT_UNAVAILABLE("");
- (BOOL)isEqualTo:(nullable id)o; - (BOOL)isNotEqualTo:(nullable id)o; - (BOOL)isLessThan:(nullable id)o; - (BOOL)isLessThanOrEqualTo:(nullable id)o;
- (BOOL)isGreaterThan:(nullable id)o; - (BOOL)isGreaterThanOrEqualTo:(nullable id)o; - (BOOL)doesContain:(id)o;
- (id)performSelector:(SEL)s withObject:(nullable id)a withObject:(nullable id)b;
@end
__attribute__((objc_root_class))
@interface NSProxy <NSObject> { Class isa; }
+ (id)alloc; + (id)allocWithZone:(nullable NSZone *)z; + (Class)class; + (BOOL)respondsToSelector:(SEL)s;
- (void)forwardInvocation:(NSInvocation *)i; - (nullable NSMethodSignature *)methodSignatureForSelector:(SEL)s;
- (void)dealloc; - (void)finalize;
@property (readonly, copy) NSString *description, *debugDescription;
@end
FOUNDATION_EXPORT NSNotificationName const NSUndoManagerCheckpointNotification, NSUndoManagerWillUndoChangeNotification, NSUndoManagerWillRedoChangeNotification,
    NSUndoManagerDidUndoChangeNotification, NSUndoManagerDidRedoChangeNotification, NSUndoManagerDidOpenUndoGroupNotification,
    NSUndoManagerWillCloseUndoGroupNotification, NSUndoManagerDidCloseUndoGroupNotification;
FOUNDATION_EXPORT NSString *const NSUndoManagerGroupIsDiscardableKey;
NS_SWIFT_NAME(UndoManager)
@interface NSUndoManager : NSObject
- (void)beginUndoGrouping; - (void)endUndoGrouping; @property (readonly) NSInteger groupingLevel;
- (void)disableUndoRegistration; - (void)enableUndoRegistration; @property (readonly, getter=isUndoRegistrationEnabled) BOOL undoRegistrationEnabled;
@property BOOL groupsByEvent; @property NSUInteger levelsOfUndo; @property (copy) NSArray<NSString *> *runLoopModes;
- (void)undo; - (void)redo; - (void)undoNestedGroup;
@property (readonly) BOOL canUndo, canRedo; @property (readonly, getter=isUndoing) BOOL undoing; @property (readonly, getter=isRedoing) BOOL redoing;
- (void)removeAllActions; - (void)removeAllActionsWithTarget:(id)t;
- (void)registerUndoWithTarget:(id)t selector:(SEL)s object:(nullable id)o;
- (void)registerUndoWithTarget:(id)t handler:(void (^)(id target))h;
- (id)prepareWithInvocationTarget:(id)t;
- (void)setActionIsDiscardable:(BOOL)d; @property (readonly) BOOL undoActionIsDiscardable, redoActionIsDiscardable;
@property (readonly, copy) NSString *undoActionName, *redoActionName, *undoMenuItemTitle, *redoMenuItemTitle;
- (void)setActionName:(NSString *)n;
- (NSString *)undoMenuTitleForUndoActionName:(NSString *)n; - (NSString *)redoMenuTitleForUndoActionName:(NSString *)n;
@end
NS_SWIFT_NAME(NSSortDescriptor)
@interface NSSortDescriptor : NSObject <NSCopying>
+ (instancetype)sortDescriptorWithKey:(nullable NSString *)k ascending:(BOOL)a;
+ (instancetype)sortDescriptorWithKey:(nullable NSString *)k ascending:(BOOL)a selector:(nullable SEL)s;
+ (instancetype)sortDescriptorWithKey:(nullable NSString *)k ascending:(BOOL)a comparator:(NSComparator)c;
- (instancetype)initWithKey:(nullable NSString *)k ascending:(BOOL)a;
- (instancetype)initWithKey:(nullable NSString *)k ascending:(BOOL)a selector:(nullable SEL)s;
- (instancetype)initWithKey:(nullable NSString *)k ascending:(BOOL)a comparator:(NSComparator)c;
@property (nullable, readonly, copy) NSString *key; @property (readonly) BOOL ascending; @property (nullable, readonly) SEL selector;
@property (readonly) NSComparator comparator; @property (readonly, retain) id reversedSortDescriptor;
- (NSComparisonResult)compareObject:(id)a toObject:(id)b;
@end
@interface NSArray<ObjectType> (MWSortDescriptors) - (NSArray<ObjectType> *)sortedArrayUsingDescriptors:(NSArray<NSSortDescriptor *> *)d; @end
@interface NSMutableArray<ObjectType> (MWSortDescriptors) - (void)sortUsingDescriptors:(NSArray<NSSortDescriptor *> *)d; @end
typedef NSString *NSValueTransformerName NS_EXTENSIBLE_STRING_ENUM;
FOUNDATION_EXPORT NSValueTransformerName const NSNegateBooleanTransformerName, NSIsNilTransformerName, NSIsNotNilTransformerName,
    NSUnarchiveFromDataTransformerName, NSKeyedUnarchiveFromDataTransformerName, NSSecureUnarchiveFromDataTransformerName;
@interface NSValueTransformer : NSObject
+ (void)setValueTransformer:(nullable NSValueTransformer *)t forName:(NSValueTransformerName)n;
+ (nullable NSValueTransformer *)valueTransformerForName:(NSValueTransformerName)n;
+ (NSArray<NSValueTransformerName> *)valueTransformerNames;
+ (Class)transformedValueClass; + (BOOL)allowsReverseTransformation;
- (nullable id)transformedValue:(nullable id)v; - (nullable id)reverseTransformedValue:(nullable id)v;
@end
typedef NS_OPTIONS(NSUInteger, NSByteCountFormatterUnits) {
    NSByteCountFormatterUseDefault = 0, NSByteCountFormatterUseBytes = 1, NSByteCountFormatterUseKB = 2, NSByteCountFormatterUseMB = 4,
    NSByteCountFormatterUseGB = 8, NSByteCountFormatterUseTB = 16, NSByteCountFormatterUsePB = 32, NSByteCountFormatterUseEB = 64,
    NSByteCountFormatterUseZB = 128, NSByteCountFormatterUseYBOrHigher = 0xFF00, NSByteCountFormatterUseAll = 0xFFFF };
typedef NS_ENUM(NSInteger, NSByteCountFormatterCountStyle) {
    NSByteCountFormatterCountStyleFile = 0, NSByteCountFormatterCountStyleMemory = 1, NSByteCountFormatterCountStyleDecimal = 2, NSByteCountFormatterCountStyleBinary = 3 };
NS_SWIFT_NAME(ByteCountFormatter)
@interface NSByteCountFormatter : NSFormatter
+ (NSString *)stringFromByteCount:(long long)n countStyle:(NSByteCountFormatterCountStyle)s;
- (NSString *)stringFromByteCount:(long long)n;
@property NSByteCountFormatterUnits allowedUnits; @property NSByteCountFormatterCountStyle countStyle;
@property BOOL allowsNonnumericFormatting, includesUnit, includesCount, includesActualByteCount, adaptive, zeroPadsFractionDigits;
@property NSInteger formattingContext;
@end
typedef NS_ENUM(NSUInteger, NSStreamStatus) { NSStreamStatusNotOpen = 0, NSStreamStatusOpening, NSStreamStatusOpen, NSStreamStatusReading,
    NSStreamStatusWriting, NSStreamStatusAtEnd, NSStreamStatusClosed, NSStreamStatusError };
typedef NSString *NSStreamPropertyKey NS_TYPED_EXTENSIBLE_ENUM;
FOUNDATION_EXPORT NSStreamPropertyKey const NSStreamFileCurrentOffsetKey, NSStreamDataWrittenToMemoryStreamKey;
NS_SWIFT_NAME(Stream)
@interface NSStream : NSObject
- (void)open; - (void)close;
@property (nullable, assign) id delegate;
- (nullable id)propertyForKey:(NSStreamPropertyKey)k; - (BOOL)setProperty:(nullable id)p forKey:(NSStreamPropertyKey)k;
- (void)scheduleInRunLoop:(NSRunLoop *)r forMode:(NSRunLoopMode)m; - (void)removeFromRunLoop:(NSRunLoop *)r forMode:(NSRunLoopMode)m;
@property (readonly) NSStreamStatus streamStatus; @property (nullable, readonly, copy) NSError *streamError;
@end
NS_SWIFT_NAME(InputStream)
@interface NSInputStream : NSStream
+ (nullable instancetype)inputStreamWithData:(NSData *)d; + (nullable instancetype)inputStreamWithFileAtPath:(NSString *)p; + (nullable instancetype)inputStreamWithURL:(NSURL *)u;
- (instancetype)initWithData:(NSData *)d; - (nullable instancetype)initWithFileAtPath:(NSString *)p; - (nullable instancetype)initWithURL:(NSURL *)u;
- (NSInteger)read:(uint8_t *)b maxLength:(NSUInteger)n; - (BOOL)getBuffer:(uint8_t * _Nullable * _Nonnull)b length:(NSUInteger *)n;
@property (readonly) BOOL hasBytesAvailable;
@end
NS_SWIFT_NAME(OutputStream)
@interface NSOutputStream : NSStream
+ (instancetype)outputStreamToMemory; + (nullable instancetype)outputStreamToFileAtPath:(NSString *)p append:(BOOL)a;
+ (nullable instancetype)outputStreamWithURL:(NSURL *)u append:(BOOL)a;
- (instancetype)initToMemory; - (nullable instancetype)initToFileAtPath:(NSString *)p append:(BOOL)a; - (nullable instancetype)initWithURL:(NSURL *)u append:(BOOL)a;
- (instancetype)initToBuffer:(uint8_t *)b capacity:(NSUInteger)c;
- (NSInteger)write:(const uint8_t *)b maxLength:(NSUInteger)n;
@property (readonly) BOOL hasSpaceAvailable;
@end
typedef NS_ENUM(NSUInteger, NSURLRequestCachePolicy) { NSURLRequestUseProtocolCachePolicy = 0, NSURLRequestReloadIgnoringLocalCacheData = 1,
    NSURLRequestReloadIgnoringLocalAndRemoteCacheData = 4, NSURLRequestReturnCacheDataElseLoad = 2, NSURLRequestReturnCacheDataDontLoad = 3,
    NSURLRequestReloadRevalidatingCacheData = 5 };
@class NSURLResponse;
NS_SWIFT_NAME(NSURLRequest)
@interface NSURLRequest : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)requestWithURL:(NSURL *)u; + (instancetype)requestWithURL:(NSURL *)u cachePolicy:(NSURLRequestCachePolicy)p timeoutInterval:(NSTimeInterval)t;
- (instancetype)initWithURL:(NSURL *)u; - (instancetype)initWithURL:(NSURL *)u cachePolicy:(NSURLRequestCachePolicy)p timeoutInterval:(NSTimeInterval)t;
@property (nullable, readonly, copy) NSURL *URL; @property (nullable, readonly, copy) NSString *HTTPMethod;
@property (nullable, readonly, copy) NSDictionary<NSString *, NSString *> *allHTTPHeaderFields; @property (nullable, readonly, copy) NSData *HTTPBody;
@property (readonly) NSTimeInterval timeoutInterval; @property (readonly) NSURLRequestCachePolicy cachePolicy;
- (nullable NSString *)valueForHTTPHeaderField:(NSString *)f;
@end
NS_SWIFT_NAME(NSMutableURLRequest)
@interface NSMutableURLRequest : NSURLRequest
- (void)setURL:(nullable NSURL *)u; - (void)setHTTPMethod:(NSString *)m; - (void)setHTTPBody:(nullable NSData *)b;
- (void)setTimeoutInterval:(NSTimeInterval)t; - (void)setCachePolicy:(NSURLRequestCachePolicy)p;
- (void)setValue:(nullable NSString *)v forHTTPHeaderField:(NSString *)f; - (void)addValue:(NSString *)v forHTTPHeaderField:(NSString *)f;
- (void)setAllHTTPHeaderFields:(nullable NSDictionary<NSString *, NSString *> *)d;
@end
NS_SWIFT_NAME(URLSessionConfiguration)
@interface NSURLSessionConfiguration : NSObject <NSCopying>
@property (class, readonly, retain) NSURLSessionConfiguration *defaultSessionConfiguration, *ephemeralSessionConfiguration;
@end
NS_SWIFT_NAME(URLSession)
@interface NSURLSession : NSObject
@property (class, readonly, retain) NSURLSession *sharedSession;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)c;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)c delegate:(nullable id)d delegateQueue:(nullable NSOperationQueue *)q;
- (id)dataTaskWithRequest:(NSURLRequest *)r completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))h;
- (id)dataTaskWithURL:(NSURL *)u completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))h;
- (id)dataTaskWithRequest:(NSURLRequest *)r; - (id)dataTaskWithURL:(NSURL *)u;
- (id)downloadTaskWithRequest:(NSURLRequest *)r completionHandler:(void (^)(NSURL * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))h;
- (id)downloadTaskWithURL:(NSURL *)u completionHandler:(void (^)(NSURL * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))h;
- (id)downloadTaskWithRequest:(NSURLRequest *)r;
- (void)invalidateAndCancel; - (void)finishTasksAndInvalidate;
@end
NS_SWIFT_NAME(NSFileCoordinator)
@interface NSFileCoordinator : NSObject
+ (void)addFilePresenter:(id)p; + (void)removeFilePresenter:(id)p; @property (class, readonly, copy) NSArray *filePresenters;
- (instancetype)initWithFilePresenter:(nullable id)p;
- (void)coordinateReadingItemAtURL:(NSURL *)u options:(NSUInteger)o error:(NSError **)e byAccessor:(void (NS_NOESCAPE ^)(NSURL *newURL))a;
- (void)coordinateWritingItemAtURL:(NSURL *)u options:(NSUInteger)o error:(NSError **)e byAccessor:(void (NS_NOESCAPE ^)(NSURL *newURL))a;
- (void)coordinateReadingItemAtURL:(NSURL *)r options:(NSUInteger)ro writingItemAtURL:(NSURL *)w options:(NSUInteger)wo error:(NSError **)e byAccessor:(void (NS_NOESCAPE ^)(NSURL *, NSURL *))a;
- (void)coordinateWritingItemAtURL:(NSURL *)u1 options:(NSUInteger)o1 writingItemAtURL:(NSURL *)u2 options:(NSUInteger)o2 error:(NSError **)e byAccessor:(void (NS_NOESCAPE ^)(NSURL *, NSURL *))a;
- (void)itemAtURL:(NSURL *)o didMoveToURL:(NSURL *)n; - (void)itemAtURL:(NSURL *)o willMoveToURL:(NSURL *)n; - (void)cancel;
@end
@interface NSArchiver : NSCoder
+ (NSData *)archivedDataWithRootObject:(id)o; + (BOOL)archiveRootObject:(id)o toFile:(NSString *)p;
@end
@interface NSUnarchiver : NSCoder
+ (nullable id)unarchiveObjectWithData:(NSData *)d; + (nullable id)unarchiveObjectWithFile:(NSString *)p;
@end
@interface NSDistributedNotificationCenter : NSNotificationCenter
+ (instancetype)defaultCenter; + (instancetype)notificationCenterForType:(NSString *)t;
- (void)postNotificationName:(NSNotificationName)n object:(nullable NSString *)o userInfo:(nullable NSDictionary *)u deliverImmediately:(BOOL)d;
- (void)postNotificationName:(NSNotificationName)n object:(nullable NSString *)o userInfo:(nullable NSDictionary *)u options:(NSUInteger)opts;
- (void)addObserver:(id)o selector:(SEL)s name:(nullable NSNotificationName)n object:(nullable NSString *)obj suspensionBehavior:(NSUInteger)b;
@end
FOUNDATION_EXPORT NSString *const NSAppleScriptErrorMessage, *const NSAppleScriptErrorNumber, *const NSAppleScriptErrorBriefMessage,
    *const NSAppleScriptErrorAppName, *const NSAppleScriptErrorRange;
@interface NSAppleScript : NSObject <NSCopying>
- (nullable instancetype)initWithSource:(NSString *)s; - (nullable instancetype)initWithContentsOfURL:(NSURL *)u error:(NSDictionary * _Nullable * _Nullable)e;
@property (nullable, readonly, copy) NSString *source; @property (readonly, getter=isCompiled) BOOL compiled;
- (BOOL)compileAndReturnError:(NSDictionary * _Nullable * _Nullable)e;
- (nullable id)executeAndReturnError:(NSDictionary * _Nullable * _Nullable)e;
@end
@interface NSXMLNode : NSObject
@property (nullable, readonly, copy) NSString *stringValue, *name, *XMLString; @property (nullable, readonly, copy) NSArray *children;
- (nullable NSArray *)nodesForXPath:(NSString *)x error:(NSError **)e;
@end
@interface NSXMLElement : NSXMLNode
- (instancetype)initWithName:(NSString *)n; - (NSArray *)elementsForName:(NSString *)n; - (nullable NSXMLNode *)attributeForName:(NSString *)n;
@end
@interface NSXMLDocument : NSXMLNode
- (nullable instancetype)initWithData:(NSData *)d options:(NSUInteger)o error:(NSError **)e;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)u options:(NSUInteger)o error:(NSError **)e;
- (nullable instancetype)initWithXMLString:(NSString *)s options:(NSUInteger)o error:(NSError **)e;
- (nullable NSXMLElement *)rootElement;
@end
@interface NSPort : NSObject
+ (NSPort *)port; - (void)invalidate; @property (readonly, getter=isValid) BOOL valid;
- (void)setDelegate:(nullable id)d; - (nullable id)delegate;
- (void)scheduleInRunLoop:(NSRunLoop *)r forMode:(NSRunLoopMode)m; - (void)removeFromRunLoop:(NSRunLoop *)r forMode:(NSRunLoopMode)m;
@end
@interface NSMachPort : NSPort + (NSPort *)portWithMachPort:(uint32_t)p; @property (readonly) uint32_t machPort; @end
@interface NSPortNameServer : NSObject + (NSPortNameServer *)systemDefaultPortNameServer; @end
@interface NSMachBootstrapServer : NSPortNameServer
+ (id)sharedInstance; - (nullable NSPort *)portForName:(NSString *)n; - (nullable NSPort *)portForName:(NSString *)n host:(nullable NSString *)h;
- (BOOL)registerPort:(NSPort *)p name:(NSString *)n;
@end
NS_SWIFT_UNAVAILABLE("NSInvocation and related APIs not available")
@interface NSInvocationOperation : NSOperation
- (nullable instancetype)initWithTarget:(id)t selector:(SEL)s object:(nullable id)o; - (instancetype)initWithInvocation:(NSInvocation *)i;
@property (readonly, retain) NSInvocation *invocation; @property (nullable, readonly, retain) id result;
@end
FOUNDATION_EXPORT NSString *const NSFileOwnerAccountID, *const NSFileGroupOwnerAccountID;
FOUNDATION_EXPORT NSRange NSIntersectionRange(NSRange a, NSRange b); FOUNDATION_EXPORT NSRange NSUnionRange(NSRange a, NSRange b);
typedef NS_OPTIONS(NSUInteger, NSFileWrapperReadingOptions) { NSFileWrapperReadingImmediate = 1, NSFileWrapperReadingWithoutMapping = 2 };
typedef NS_OPTIONS(NSUInteger, NSFileWrapperWritingOptions) { NSFileWrapperWritingAtomic = 1, NSFileWrapperWritingWithNameUpdating = 2 };
NS_SWIFT_NAME(FileWrapper)
@interface NSFileWrapper : NSObject
- (nullable instancetype)initWithURL:(NSURL *)u options:(NSFileWrapperReadingOptions)o error:(NSError **)e;
- (instancetype)initRegularFileWithContents:(NSData *)d; - (instancetype)initDirectoryWithFileWrappers:(NSDictionary<NSString *, NSFileWrapper *> *)c;
@property (readonly, getter=isRegularFile) BOOL regularFile; @property (readonly, getter=isDirectory) BOOL directory; @property (readonly, getter=isSymbolicLink) BOOL symbolicLink;
@property (nullable, readonly, copy) NSData *regularFileContents; @property (nullable, readonly, copy) NSDictionary<NSString *, NSFileWrapper *> *fileWrappers;
@property (nullable, copy) NSString *filename, *preferredFilename; @property (copy) NSDictionary<NSString *, id> *fileAttributes;
- (NSString *)addFileWrapper:(NSFileWrapper *)w; - (NSString *)addRegularFileWithContents:(NSData *)d preferredFilename:(NSString *)n;
- (void)removeFileWrapper:(NSFileWrapper *)w; - (BOOL)matchesContentsOfURL:(NSURL *)u;
- (BOOL)readFromURL:(NSURL *)u options:(NSFileWrapperReadingOptions)o error:(NSError **)e;
- (BOOL)writeToURL:(NSURL *)u options:(NSFileWrapperWritingOptions)o originalContentsURL:(nullable NSURL *)orig error:(NSError **)e;
@property (nullable, readonly, copy) NSData *serializedRepresentation;
@end
@interface NSFileManager (MWDisplayName) - (NSString *)displayNameAtPath:(NSString *)p; @end
typedef NS_OPTIONS(NSUInteger, NSKeyValueObservingOptions) { NSKeyValueObservingOptionNew = 1, NSKeyValueObservingOptionOld = 2,
    NSKeyValueObservingOptionInitial = 4, NSKeyValueObservingOptionPrior = 8 };
typedef NS_ENUM(NSUInteger, NSKeyValueChange) { NSKeyValueChangeSetting = 1, NSKeyValueChangeInsertion = 2, NSKeyValueChangeRemoval = 3, NSKeyValueChangeReplacement = 4 };
typedef NS_ENUM(NSUInteger, NSKeyValueSetMutationKind) { NSKeyValueUnionSetMutation = 1, NSKeyValueMinusSetMutation = 2, NSKeyValueIntersectSetMutation = 3, NSKeyValueSetSetMutation = 4 };
typedef NSString *NSKeyValueChangeKey NS_STRING_ENUM;
FOUNDATION_EXPORT NSKeyValueChangeKey const NSKeyValueChangeKindKey, NSKeyValueChangeNewKey, NSKeyValueChangeOldKey, NSKeyValueChangeIndexesKey, NSKeyValueChangeNotificationIsPriorKey;
@interface NSObject (NSKeyValueObserving)
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)k; + (NSSet<NSString *> *)keyPathsForValuesAffectingValueForKey:(NSString *)k;
- (void)addObserver:(NSObject *)o forKeyPath:(NSString *)p options:(NSKeyValueObservingOptions)opts context:(nullable void *)c;
- (void)removeObserver:(NSObject *)o forKeyPath:(NSString *)p context:(nullable void *)c; - (void)removeObserver:(NSObject *)o forKeyPath:(NSString *)p;
- (void)observeValueForKeyPath:(nullable NSString *)p ofObject:(nullable id)o change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)c context:(nullable void *)ctx;
- (void)willChangeValueForKey:(NSString *)k; - (void)didChangeValueForKey:(NSString *)k;
- (void)willChange:(NSKeyValueChange)c valuesAtIndexes:(NSIndexSet *)i forKey:(NSString *)k; - (void)didChange:(NSKeyValueChange)c valuesAtIndexes:(NSIndexSet *)i forKey:(NSString *)k;
- (void)willChangeValueForKey:(NSString *)k withSetMutation:(NSKeyValueSetMutationKind)m usingObjects:(NSSet *)o;
- (void)didChangeValueForKey:(NSString *)k withSetMutation:(NSKeyValueSetMutationKind)m usingObjects:(NSSet *)o;
@property (nullable) void *observationInfo;
@end
NS_SWIFT_NAME(NSPredicate)
@interface NSPredicate : NSObject <NSCopying>
+ (NSPredicate *)predicateWithFormat:(NSString *)f, ...; + (NSPredicate *)predicateWithFormat:(NSString *)f arguments:(va_list)ap;
+ (NSPredicate *)predicateWithFormat:(NSString *)f argumentArray:(nullable NSArray *)a;
+ (NSPredicate *)predicateWithValue:(BOOL)v; + (NSPredicate *)predicateWithBlock:(BOOL (^)(id _Nullable, NSDictionary<NSString *, id> * _Nullable))b;
@property (readonly, copy) NSString *predicateFormat;
- (BOOL)evaluateWithObject:(nullable id)o; - (BOOL)evaluateWithObject:(nullable id)o substitutionVariables:(nullable NSDictionary<NSString *, id> *)v;
- (void)allowEvaluation;
@end
@interface NSArray<ObjectType> (MWPredicate) - (NSArray<ObjectType> *)filteredArrayUsingPredicate:(NSPredicate *)p; @end
@interface NSMutableArray<ObjectType> (MWPredicate) - (void)filterUsingPredicate:(NSPredicate *)p; @end
@interface NSSet<ObjectType> (MWPredicate) - (NSSet<ObjectType> *)filteredSetUsingPredicate:(NSPredicate *)p; @end
@interface NSDirectoryEnumerator<ObjectType> : NSEnumerator<ObjectType>
- (void)skipDescendants; - (void)skipDescendents; @property (readonly) NSUInteger level;
@property (nullable, readonly, copy) NSDictionary *fileAttributes, *directoryAttributes; @property (readonly) BOOL isEnumeratingDirectoryPostOrder;
@end
@interface NSFileManager (MWEnumerators)
- (nullable NSDirectoryEnumerator<NSString *> *)enumeratorAtPath:(NSString *)p;
- (nullable NSDirectoryEnumerator<NSURL *> *)enumeratorAtURL:(NSURL *)u includingPropertiesForKeys:(nullable NSArray *)k options:(NSDirectoryEnumerationOptions)o errorHandler:(nullable BOOL (^)(NSURL *, NSError *))h;
- (nullable NSArray<NSString *> *)subpathsAtPath:(NSString *)p;
@end
@interface NSCoder (MWBytes) - (void)encodeBytes:(nullable const void *)b length:(NSUInteger)n; - (nullable void *)decodeBytesWithReturnedLength:(NSUInteger *)n; @end
@interface NSData (MWBase64Old) - (nullable instancetype)initWithBase64Encoding:(NSString *)s; - (NSString *)base64Encoding; @end
@interface NSDictionary (MWObjectsAndKeys) - (instancetype)initWithObjectsAndKeys:(id)first, ... NS_REQUIRES_NIL_TERMINATION; + (instancetype)dictionaryWithObjects:(NSArray *)o forKeys:(NSArray *)k; @end
@interface NSMutableArray (MWMore) - (void)removeObjectsAtIndexes:(NSIndexSet *)i; - (void)sortUsingFunction:(NSInteger (*)(id, id, void * _Nullable))f context:(nullable void *)ctx; @end
@interface NSArray (MWMore) - (NSArray *)sortedArrayUsingFunction:(NSInteger (*)(id, id, void * _Nullable))f context:(nullable void *)ctx; @end
@interface NSObject (MWKeyPathSet) - (void)setValue:(nullable id)v forKeyPath:(NSString *)p; @end
@interface NSString (MWTilde) @property (readonly, copy) NSString *stringByAbbreviatingWithTildeInPath; @end
@interface NSProcessInfo (MWTermination) - (void)disableSuddenTermination; - (void)enableSuddenTermination;
- (void)disableAutomaticTermination:(NSString *)r; - (void)enableAutomaticTermination:(NSString *)r; @property BOOL automaticTerminationSupportEnabled; @end
@interface NSTask (MWLaunched) + (NSTask *)launchedTaskWithLaunchPath:(NSString *)p arguments:(NSArray<NSString *> *)a;
+ (nullable NSTask *)launchedTaskWithExecutableURL:(NSURL *)u arguments:(NSArray<NSString *> *)a error:(NSError **)e terminationHandler:(void (^ _Nullable)(NSTask *))h; @end
@interface NSFileHandle (MWHandlers) @property (nullable, copy) void (^readabilityHandler)(NSFileHandle *); @property (nullable, copy) void (^writeabilityHandler)(NSFileHandle *); @end
NS_ASSUME_NONNULL_END
/* CoreFoundation: <CoreFoundation/CoreFoundation.h> */
#if __has_feature(objc_arc)
static inline CFTypeRef CFBridgingRetain(id x) { return (__bridge_retained CFTypeRef)x; }
static inline id CFBridgingRelease(CFTypeRef x) { return (__bridge_transfer id)x; }
#else
static inline CFTypeRef CFBridgingRetain(id x) { return CFRetain((CFTypeRef)x); }
static inline id CFBridgingRelease(CFTypeRef x) { return [(id)x autorelease]; }
#endif
