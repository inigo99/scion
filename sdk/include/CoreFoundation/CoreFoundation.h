/* scion SDK (clean-room): CoreFoundation basic types. CF objects are the Foundation objects (toll-free); the functions
 * scion provides live in Foundation.dylib. Usable from C, C++ and Objective-C. */
#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#if !defined(MW_FOUNDATION_INTERNAL) && __has_include(<libkern/OSByteOrder.h>)
#include <assert.h> /* with the SDK; scion's own freestanding builds have no libc headers */
#if __has_include(<_scion_darwin.h>)
#include <_scion_darwin.h> /* as on macOS, CoreFoundation brings in the C library (Swift: the Darwin module) */
#endif
#endif
#ifndef MW_CF_BASE
#define MW_CF_BASE
#define CF_EXPORT extern
#define CF_INLINE static inline
#define CF_ENUM(_type, _name) enum __attribute__((enum_extensibility(open))) _name : _type _name; \
    enum __attribute__((enum_extensibility(open))) _name : _type
#define CF_OPTIONS(_type, _name) enum __attribute__((enum_extensibility(open), flag_enum)) _name : _type _name; \
    enum __attribute__((enum_extensibility(open), flag_enum)) _name : _type
#define CF_CLOSED_ENUM(_type, _name) enum __attribute__((enum_extensibility(closed))) _name : _type _name; \
    enum __attribute__((enum_extensibility(closed))) _name : _type
#define CF_STRING_ENUM __attribute__((swift_wrapper(struct)))
#define CF_EXTENSIBLE_STRING_ENUM __attribute__((swift_wrapper(struct)))
#define CF_SWIFT_NAME(_name) __attribute__((swift_name(#_name)))
#define CF_REFINED_FOR_SWIFT __attribute__((swift_private))
#define CF_RETURNS_RETAINED __attribute__((cf_returns_retained))
#define CF_IMPLICIT_BRIDGING_ENABLED _Pragma("clang arc_cf_code_audited begin")
#define CF_IMPLICIT_BRIDGING_DISABLED _Pragma("clang arc_cf_code_audited end")
#define CF_RETURNS_NOT_RETAINED __attribute__((cf_returns_not_retained))
#if __has_attribute(objc_bridge)
#define CF_BRIDGED_TYPE(T) __attribute__((objc_bridge(T)))
#define CF_BRIDGED_MUTABLE_TYPE(T) __attribute__((objc_bridge_mutable(T)))
#else
#define CF_BRIDGED_TYPE(T)
#define CF_BRIDGED_MUTABLE_TYPE(T)
#endif
typedef const void *CFTypeRef;
typedef unsigned long CFTypeID;
typedef unsigned long CFHashCode;
typedef unsigned long CFOptionFlags;
typedef long CFIndex;
typedef unsigned short UniChar;
typedef double CFTimeInterval;
typedef double CFAbsoluteTime;
typedef unsigned char Boolean;
typedef unsigned char UInt8;
/* the CF types are the Foundation classes (toll-free bridged): Swift imports them as CFString, CFArray, ... */
typedef const struct CF_BRIDGED_TYPE(NSString) __CFString *CFStringRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableString) __CFString *CFMutableStringRef;
typedef const struct CF_BRIDGED_TYPE(id) __CFAllocator *CFAllocatorRef;
typedef const struct CF_BRIDGED_TYPE(NSDictionary) __CFDictionary *CFDictionaryRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableDictionary) __CFDictionary *CFMutableDictionaryRef;
typedef const struct CF_BRIDGED_TYPE(NSArray) __CFArray *CFArrayRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableArray) __CFArray *CFMutableArrayRef;
typedef const struct CF_BRIDGED_TYPE(NSData) __CFData *CFDataRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableData) __CFData *CFMutableDataRef;
typedef const struct CF_BRIDGED_TYPE(NSNumber) __CFNumber *CFNumberRef;
typedef const struct CF_BRIDGED_TYPE(NSNumber) __CFBoolean *CFBooleanRef;
typedef const struct CF_BRIDGED_TYPE(NSURL) __CFURL *CFURLRef;
typedef struct CF_BRIDGED_TYPE(NSError) __CFError *CFErrorRef;
typedef const struct CF_BRIDGED_TYPE(NSCharacterSet) __CFCharacterSet *CFCharacterSetRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableCharacterSet) __CFCharacterSet *CFMutableCharacterSetRef;
typedef const struct CF_BRIDGED_TYPE(NSSet) __CFSet *CFSetRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableSet) __CFSet *CFMutableSetRef;
typedef const struct CF_BRIDGED_TYPE(NSDate) __CFDate *CFDateRef;
typedef const struct CF_BRIDGED_TYPE(NSTimeZone) __CFTimeZone *CFTimeZoneRef;
typedef const struct CF_BRIDGED_TYPE(NSLocale) __CFLocale *CFLocaleRef;
typedef struct CF_BRIDGED_TYPE(NSCalendar) __CFCalendar *CFCalendarRef;
typedef struct { CFIndex location, length; } CFRange;
static inline CFRange CFRangeMake(CFIndex loc, CFIndex len) { CFRange r = {loc, len}; return r; }
typedef CF_ENUM(CFIndex, CFComparisonResult) { kCFCompareLessThan = -1L, kCFCompareEqualTo = 0, kCFCompareGreaterThan = 1 };
typedef uint32_t CFStringEncoding;
typedef CF_ENUM(CFStringEncoding, CFStringBuiltInEncodings) {
    kCFStringEncodingMacRoman = 0, kCFStringEncodingWindowsLatin1 = 0x0500, kCFStringEncodingISOLatin1 = 0x0201,
    kCFStringEncodingNextStepLatin = 0x0B01, kCFStringEncodingASCII = 0x0600, kCFStringEncodingUnicode = 0x0100,
    kCFStringEncodingUTF8 = 0x08000100, kCFStringEncodingNonLossyASCII = 0x0BFF, kCFStringEncodingUTF16 = 0x0100,
    kCFStringEncodingUTF16BE = 0x10000100, kCFStringEncodingUTF16LE = 0x14000100, kCFStringEncodingUTF32 = 0x0c000100,
    kCFStringEncodingUTF32BE = 0x18000100, kCFStringEncodingUTF32LE = 0x1c000100,
};
#define kCFAllocatorDefault ((CFAllocatorRef)0)
#ifndef CFSTR
#define CFSTR(s) ((CFStringRef)__builtin___CFStringMakeConstantString("" s ""))
#endif
#define kCFNotFound ((CFIndex)-1)
#endif
#ifndef CF_EXTERN_C_BEGIN
#ifdef __cplusplus
#define CF_EXTERN_C_BEGIN extern "C" {
#define CF_EXTERN_C_END }
#else
#define CF_EXTERN_C_BEGIN
#define CF_EXTERN_C_END
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif
CFTypeRef CFRetain(CFTypeRef cf);
void CFRelease(CFTypeRef cf);
CFTypeID CFGetTypeID(CFTypeRef cf);
CFTypeID CFStringGetTypeID(void);
CFIndex CFStringGetLength(CFStringRef s);
extern const CFAllocatorRef kCFAllocatorSystemDefault, kCFAllocatorMalloc, kCFAllocatorNull;
CF_IMPLICIT_BRIDGING_ENABLED
CFStringRef CFStringCreateWithBytes(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes, CFStringEncoding encoding, Boolean isExternalRepresentation);
CFStringRef CFStringCreateWithCString(CFAllocatorRef alloc, const char *cStr, CFStringEncoding encoding);
CF_IMPLICIT_BRIDGING_DISABLED
const char *CFStringGetCStringPtr(CFStringRef s, CFStringEncoding encoding);
CFHashCode CFHash(CFTypeRef cf);
Boolean CFEqual(CFTypeRef a, CFTypeRef b);
CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);
CFHashCode CFHashBytes(uint8_t *bytes, CFIndex len);
/* character sets (an NSCharacterSet) */
typedef CF_ENUM(CFIndex, CFCharacterSetPredefinedSet) {
    kCFCharacterSetControl = 1, kCFCharacterSetWhitespace, kCFCharacterSetWhitespaceAndNewline, kCFCharacterSetDecimalDigit,
    kCFCharacterSetLetter, kCFCharacterSetLowercaseLetter, kCFCharacterSetUppercaseLetter, kCFCharacterSetNonBase,
    kCFCharacterSetDecomposable, kCFCharacterSetAlphaNumeric, kCFCharacterSetPunctuation, kCFCharacterSetIllegal = 12,
    kCFCharacterSetCapitalizedLetter = 13, kCFCharacterSetSymbol = 14, kCFCharacterSetNewline = 15,
};
CF_IMPLICIT_BRIDGING_ENABLED
CFCharacterSetRef CFCharacterSetGetPredefined(CFCharacterSetPredefinedSet theSetIdentifier);
extern const CFBooleanRef kCFBooleanTrue, kCFBooleanFalse;
Boolean CFBooleanGetValue(CFBooleanRef boolean);
CFIndex CFSetGetCount(CFSetRef theSet);
void CFSetGetValues(CFSetRef theSet, const void * _Nullable * _Nullable values);
CFSetRef CFSetCreateCopy(CFAllocatorRef _Nullable allocator, CFSetRef theSet);
CFArrayRef CFArrayCreateCopy(CFAllocatorRef _Nullable allocator, CFArrayRef theArray);
CFDictionaryRef CFDictionaryCreateCopy(CFAllocatorRef _Nullable allocator, CFDictionaryRef theDict);
CFIndex CFArrayGetCount(CFArrayRef theArray);
const void *CFArrayGetValueAtIndex(CFArrayRef theArray, CFIndex idx);
CFIndex CFDictionaryGetCount(CFDictionaryRef theDict);
CFStringRef CFCopyDescription(CFTypeRef cf);
typedef uint32_t UTF32Char;
CFMutableCharacterSetRef CFCharacterSetCreateMutable(CFAllocatorRef _Nullable alloc);
CFMutableCharacterSetRef CFCharacterSetCreateMutableCopy(CFAllocatorRef _Nullable alloc, CFCharacterSetRef theSet);
CFCharacterSetRef CFCharacterSetCreateWithCharactersInRange(CFAllocatorRef _Nullable alloc, CFRange theRange);
CFCharacterSetRef CFCharacterSetCreateWithCharactersInString(CFAllocatorRef _Nullable alloc, CFStringRef theString);
CFCharacterSetRef CFCharacterSetCreateWithBitmapRepresentation(CFAllocatorRef _Nullable alloc, CFDataRef theData);
CFCharacterSetRef CFCharacterSetCreateInvertedSet(CFAllocatorRef _Nullable alloc, CFCharacterSetRef theSet);
CFDataRef CFCharacterSetCreateBitmapRepresentation(CFAllocatorRef _Nullable alloc, CFCharacterSetRef theSet);
Boolean CFCharacterSetIsSupersetOfSet(CFCharacterSetRef theSet, CFCharacterSetRef theOtherset);
Boolean CFCharacterSetHasMemberInPlane(CFCharacterSetRef theSet, CFIndex thePlane);
Boolean CFCharacterSetIsLongCharacterMember(CFCharacterSetRef theSet, UTF32Char theChar);
void CFCharacterSetAddCharactersInRange(CFMutableCharacterSetRef theSet, CFRange theRange);
void CFCharacterSetRemoveCharactersInRange(CFMutableCharacterSetRef theSet, CFRange theRange);
void CFCharacterSetAddCharactersInString(CFMutableCharacterSetRef theSet, CFStringRef theString);
void CFCharacterSetRemoveCharactersInString(CFMutableCharacterSetRef theSet, CFStringRef theString);
void CFCharacterSetInvert(CFMutableCharacterSetRef theSet);
void CFCharacterSetUnion(CFMutableCharacterSetRef theSet, CFCharacterSetRef theOtherSet);
void CFCharacterSetIntersect(CFMutableCharacterSetRef theSet, CFCharacterSetRef theOtherSet);
typedef CFStringRef CFLocaleKey CF_EXTENSIBLE_STRING_ENUM;
extern const CFLocaleKey kCFLocaleIdentifier, kCFLocaleLanguageCode, kCFLocaleCountryCode, kCFLocaleScriptCode, kCFLocaleVariantCode,
    kCFLocaleExemplarCharacterSet, kCFLocaleCalendarIdentifier, kCFLocaleCalendar, kCFLocaleCollationIdentifier,
    kCFLocaleUsesMetricSystem, kCFLocaleMeasurementSystem, kCFLocaleDecimalSeparator, kCFLocaleGroupingSeparator,
    kCFLocaleCurrencySymbol, kCFLocaleCurrencyCode, kCFLocaleCollatorIdentifier, kCFLocaleQuotationBeginDelimiterKey,
    kCFLocaleQuotationEndDelimiterKey, kCFLocaleAlternateQuotationBeginDelimiterKey, kCFLocaleAlternateQuotationEndDelimiterKey;
CFStringRef _Nullable CFLocaleCopyDisplayNameForPropertyValue(CFLocaleRef displayLocale, CFLocaleKey key, CFStringRef value);
typedef CFStringRef CFErrorDomain;
CFErrorDomain CFErrorGetDomain(CFErrorRef err);
CFIndex CFErrorGetCode(CFErrorRef err);
CFDictionaryRef CFErrorCopyUserInfo(CFErrorRef err);
CFStringRef CFErrorCopyDescription(CFErrorRef err);
CF_IMPLICIT_BRIDGING_DISABLED
/* a CFURLRef is an NSURL */
CFURLRef CFURLCreateFromFileSystemRepresentation(CFAllocatorRef a, const unsigned char *buffer, CFIndex length, Boolean isDirectory);
/* a CFAttributedStringRef is an NSAttributedString */
typedef const struct CF_BRIDGED_TYPE(NSAttributedString) __CFAttributedString *CFAttributedStringRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableAttributedString) __CFAttributedString *CFMutableAttributedStringRef;
CFAttributedStringRef CFAttributedStringCreate(CFAllocatorRef a, CFStringRef s, CFDictionaryRef _Nullable attrs);
CFAttributedStringRef CFAttributedStringCreateCopy(CFAllocatorRef a, CFAttributedStringRef s);
CFAttributedStringRef CFAttributedStringCreateWithSubstring(CFAllocatorRef a, CFAttributedStringRef s, CFRange r);
CFMutableAttributedStringRef CFAttributedStringCreateMutable(CFAllocatorRef a, CFIndex maxLength);
CFMutableAttributedStringRef CFAttributedStringCreateMutableCopy(CFAllocatorRef a, CFIndex maxLength, CFAttributedStringRef s);
CFIndex CFAttributedStringGetLength(CFAttributedStringRef s);
CFStringRef CFAttributedStringGetString(CFAttributedStringRef s);
CFDictionaryRef CFAttributedStringGetAttributes(CFAttributedStringRef s, CFIndex loc, CFRange *_Nullable effectiveRange);
CFTypeRef _Nullable CFAttributedStringGetAttribute(CFAttributedStringRef s, CFIndex loc, CFStringRef name, CFRange *_Nullable effectiveRange);
CFDictionaryRef CFAttributedStringGetAttributesAndLongestEffectiveRange(CFAttributedStringRef s, CFIndex loc, CFRange inRange, CFRange *_Nullable longestEffectiveRange);
void CFAttributedStringReplaceString(CFMutableAttributedStringRef s, CFRange r, CFStringRef replacement);
CFMutableStringRef CFAttributedStringGetMutableString(CFMutableAttributedStringRef s);
void CFAttributedStringSetAttributes(CFMutableAttributedStringRef s, CFRange r, CFDictionaryRef _Nullable replacement, Boolean clearOtherAttributes);
void CFAttributedStringSetAttribute(CFMutableAttributedStringRef s, CFRange r, CFStringRef name, CFTypeRef value);
void CFAttributedStringRemoveAttribute(CFMutableAttributedStringRef s, CFRange r, CFStringRef name);
void CFAttributedStringReplaceAttributedString(CFMutableAttributedStringRef s, CFRange r, CFAttributedStringRef replacement);
void CFAttributedStringBeginEditing(CFMutableAttributedStringRef s); void CFAttributedStringEndEditing(CFMutableAttributedStringRef s);
/* a CFRunLoopRef is the NSRunLoop */
typedef struct __CFRunLoop *CFRunLoopRef; typedef CFStringRef CFRunLoopMode;
extern const CFStringRef kCFRunLoopDefaultMode, kCFRunLoopCommonModes;
CFRunLoopRef CFRunLoopGetCurrent(void); CFRunLoopRef CFRunLoopGetMain(void); void CFRunLoopRun(void);
void CFRunLoopStop(CFRunLoopRef rl); void CFRunLoopWakeUp(CFRunLoopRef rl); Boolean CFRunLoopIsWaiting(CFRunLoopRef rl);
int CFRunLoopRunInMode(CFRunLoopMode mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled);
#if __BLOCKS__
void CFRunLoopPerformBlock(CFRunLoopRef rl, CFTypeRef mode, void (^block)(void));
#endif
#ifdef __cplusplus
}
#endif
