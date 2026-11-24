/* swift.m — the Foundation API that Swift's Foundation overlay (libswiftFoundation, src/build_swift_overlays.sh) is built
 * on: index sets, decimal numbers, NSString and NSData additions, and the CoreFoundation functions the overlay calls
 * (character sets, sets, errors, booleans, strings). Calendars, locales, time zones and date formatters are in
 * calendar.m, URLs in url.m. Written from Apple's public documentation. ponytail: decimals are computed as doubles. */
#include "internal.h"
int pipe(int[2]);
__attribute__((visibility("hidden"))) NSString *pct_encode(NSString *s, NSCharacterSet *allowed), *pct_decode(NSString *s);   /* url.m */

/* ======================================================================= string constants */
#define STR(n) NSString *const n = @#n;
#define KEY(n) NSURLResourceKey const n = @#n;
NSCalendarIdentifier const NSCalendarIdentifierGregorian = @"gregorian", NSCalendarIdentifierBuddhist = @"buddhist",
    NSCalendarIdentifierChinese = @"chinese", NSCalendarIdentifierCoptic = @"coptic",
    NSCalendarIdentifierEthiopicAmeteMihret = @"ethiopic", NSCalendarIdentifierEthiopicAmeteAlem = @"ethiopic-amete-alem",
    NSCalendarIdentifierHebrew = @"hebrew", NSCalendarIdentifierISO8601 = @"iso8601", NSCalendarIdentifierIndian = @"indian",
    NSCalendarIdentifierIslamic = @"islamic", NSCalendarIdentifierIslamicCivil = @"islamic-civil", NSCalendarIdentifierJapanese = @"japanese",
    NSCalendarIdentifierPersian = @"persian", NSCalendarIdentifierRepublicOfChina = @"roc",
    NSCalendarIdentifierIslamicTabular = @"islamic-tbla", NSCalendarIdentifierIslamicUmmAlQura = @"islamic-umalqura";
NSLocaleKey const NSLocaleIdentifier = @"locale:id", NSLocaleLanguageCode = @"locale:language code", NSLocaleCountryCode = @"locale:country code",
    NSLocaleScriptCode = @"locale:script code", NSLocaleVariantCode = @"locale:variant code",
    NSLocaleExemplarCharacterSet = @"locale:exemplar characters", NSLocaleCalendar = @"locale:calendarref",
    NSLocaleCollationIdentifier = @"collation", NSLocaleUsesMetricSystem = @"locale:uses metric",
    NSLocaleMeasurementSystem = @"locale:measurement system", NSLocaleDecimalSeparator = @"locale:decimal separator",
    NSLocaleGroupingSeparator = @"locale:grouping separator", NSLocaleCurrencySymbol = @"locale:currency symbol",
    NSLocaleCurrencyCode = @"currency", NSLocaleCollatorIdentifier = @"locale:collator identifier",
    NSLocaleQuotationBeginDelimiterKey = @"locale:quotation begin", NSLocaleQuotationEndDelimiterKey = @"locale:quotation end",
    NSLocaleAlternateQuotationBeginDelimiterKey = @"locale:alternate quotation begin",
    NSLocaleAlternateQuotationEndDelimiterKey = @"locale:alternate quotation end";
CFLocaleKey const kCFLocaleIdentifier = (CFLocaleKey)@"locale:id", kCFLocaleLanguageCode = (CFLocaleKey)@"locale:language code",
    kCFLocaleCountryCode = (CFLocaleKey)@"locale:country code", kCFLocaleScriptCode = (CFLocaleKey)@"locale:script code",
    kCFLocaleVariantCode = (CFLocaleKey)@"locale:variant code", kCFLocaleExemplarCharacterSet = (CFLocaleKey)@"locale:exemplar characters",
    kCFLocaleCalendarIdentifier = (CFLocaleKey)@"calendar", kCFLocaleCalendar = (CFLocaleKey)@"locale:calendarref",
    kCFLocaleCollationIdentifier = (CFLocaleKey)@"collation", kCFLocaleUsesMetricSystem = (CFLocaleKey)@"locale:uses metric",
    kCFLocaleMeasurementSystem = (CFLocaleKey)@"locale:measurement system", kCFLocaleDecimalSeparator = (CFLocaleKey)@"locale:decimal separator",
    kCFLocaleGroupingSeparator = (CFLocaleKey)@"locale:grouping separator", kCFLocaleCurrencySymbol = (CFLocaleKey)@"locale:currency symbol",
    kCFLocaleCurrencyCode = (CFLocaleKey)@"currency", kCFLocaleCollatorIdentifier = (CFLocaleKey)@"locale:collator identifier",
    kCFLocaleQuotationBeginDelimiterKey = (CFLocaleKey)@"locale:quotation begin", kCFLocaleQuotationEndDelimiterKey = (CFLocaleKey)@"locale:quotation end",
    kCFLocaleAlternateQuotationBeginDelimiterKey = (CFLocaleKey)@"locale:alternate quotation begin",
    kCFLocaleAlternateQuotationEndDelimiterKey = (CFLocaleKey)@"locale:alternate quotation end";
NSNotificationName const NSCurrentLocaleDidChangeNotification = @"kCFLocaleCurrentLocaleDidChangeNotification",
    NSSystemTimeZoneDidChangeNotification = @"NSSystemTimeZoneDidChangeNotification";
NSErrorDomain const NSOSStatusErrorDomain = @"NSOSStatusErrorDomain", NSMachErrorDomain = @"NSMachErrorDomain",
    NSURLErrorDomain = @"NSURLErrorDomain", NSStreamSocketSSLErrorDomain = @"NSStreamSocketSSLErrorDomain",
    NSStreamSOCKSErrorDomain = @"NSStreamSOCKSErrorDomain";
NSErrorUserInfoKey const NSMultipleUnderlyingErrorsKey = @"NSMultipleUnderlyingErrorsKey",
    NSLocalizedRecoveryOptionsErrorKey = @"NSLocalizedRecoveryOptions", NSRecoveryAttempterErrorKey = @"NSRecoveryAttempter",
    NSHelpAnchorErrorKey = @"NSHelpAnchor", NSDebugDescriptionErrorKey = @"NSDebugDescription",
    NSLocalizedFailureErrorKey = @"NSLocalizedFailure", NSStringEncodingErrorKey = @"NSStringEncodingErrorKey",
    NSURLErrorKey = @"NSURL", NSURLErrorFailingURLErrorKey = @"NSErrorFailingURLKey",
    NSURLErrorFailingURLStringErrorKey = @"NSErrorFailingURLStringKey", NSURLErrorFailingURLPeerTrustErrorKey = @"NSURLErrorFailingURLPeerTrustErrorKey",
    NSURLErrorBackgroundTaskCancelledReasonKey = @"NSURLErrorBackgroundTaskCancelledReasonKey",
    NSURLErrorNetworkUnavailableReasonKey = @"NSURLErrorNetworkUnavailableReasonKey";
STR(NSURLSessionDownloadTaskResumeData)
KEY(NSURLKeysOfUnsetValuesKey) KEY(NSURLNameKey) KEY(NSURLLocalizedNameKey) KEY(NSURLIsRegularFileKey) KEY(NSURLIsDirectoryKey)
KEY(NSURLIsSymbolicLinkKey) KEY(NSURLIsVolumeKey) KEY(NSURLIsPackageKey) KEY(NSURLIsApplicationKey) KEY(NSURLApplicationIsScriptableKey)
KEY(NSURLIsSystemImmutableKey) KEY(NSURLIsUserImmutableKey) KEY(NSURLIsHiddenKey) KEY(NSURLHasHiddenExtensionKey) KEY(NSURLCreationDateKey)
KEY(NSURLContentAccessDateKey) KEY(NSURLContentModificationDateKey) KEY(NSURLAttributeModificationDateKey) KEY(NSURLLinkCountKey)
KEY(NSURLParentDirectoryURLKey) KEY(NSURLVolumeURLKey) KEY(NSURLTypeIdentifierKey) KEY(NSURLContentTypeKey)
KEY(NSURLLocalizedTypeDescriptionKey) KEY(NSURLLabelNumberKey) KEY(NSURLLabelColorKey) KEY(NSURLLocalizedLabelKey)
KEY(NSURLEffectiveIconKey) KEY(NSURLCustomIconKey) KEY(NSURLFileResourceIdentifierKey) KEY(NSURLVolumeIdentifierKey)
KEY(NSURLPreferredIOBlockSizeKey) KEY(NSURLIsReadableKey) KEY(NSURLIsWritableKey) KEY(NSURLIsExecutableKey) KEY(NSURLFileSecurityKey)
KEY(NSURLIsExcludedFromBackupKey) KEY(NSURLTagNamesKey) KEY(NSURLPathKey) KEY(NSURLCanonicalPathKey) KEY(NSURLIsMountTriggerKey)
KEY(NSURLGenerationIdentifierKey) KEY(NSURLDocumentIdentifierKey) KEY(NSURLAddedToDirectoryDateKey) KEY(NSURLQuarantinePropertiesKey)
KEY(NSURLFileResourceTypeKey) KEY(NSURLFileContentIdentifierKey) KEY(NSURLMayShareFileContentKey) KEY(NSURLMayHaveExtendedAttributesKey)
KEY(NSURLIsPurgeableKey) KEY(NSURLIsSparseKey) KEY(NSURLThumbnailDictionaryKey) KEY(NSURLThumbnailKey) KEY(NSURLFileSizeKey)
KEY(NSURLFileAllocatedSizeKey) KEY(NSURLTotalFileSizeKey) KEY(NSURLTotalFileAllocatedSizeKey) KEY(NSURLIsAliasFileKey)
KEY(NSURLFileProtectionKey) KEY(NSURLDirectoryEntryCountKey) KEY(NSURLVolumeLocalizedFormatDescriptionKey) KEY(NSURLVolumeTotalCapacityKey)
KEY(NSURLVolumeAvailableCapacityKey) KEY(NSURLVolumeResourceCountKey) KEY(NSURLVolumeNameKey) KEY(NSURLVolumeLocalizedNameKey)
KEY(NSURLVolumeIsLocalKey) KEY(NSURLVolumeIsReadOnlyKey) KEY(NSURLVolumeIsRemovableKey) KEY(NSURLVolumeIsEjectableKey)
KEY(NSURLVolumeIsInternalKey) KEY(NSURLVolumeUUIDStringKey) KEY(NSURLIsUbiquitousItemKey) KEY(NSURLUbiquitousItemHasUnresolvedConflictsKey)
KEY(NSURLUbiquitousItemIsDownloadingKey) KEY(NSURLUbiquitousItemIsUploadedKey) KEY(NSURLUbiquitousItemIsUploadingKey)
KEY(NSURLUbiquitousItemDownloadingStatusKey) KEY(NSURLUbiquitousItemDownloadingErrorKey) KEY(NSURLUbiquitousItemUploadingErrorKey)
KEY(NSURLUbiquitousItemContainerDisplayNameKey) KEY(NSURLUbiquitousItemIsSharedKey) KEY(NSURLVolumeAvailableCapacityForImportantUsageKey)
KEY(NSURLVolumeAvailableCapacityForOpportunisticUsageKey) KEY(NSURLVolumeSupportsFileCloningKey) KEY(NSURLUbiquitousItemDownloadRequestedKey)
KEY(NSURLUbiquitousSharedItemCurrentUserPermissionsKey) KEY(NSURLUbiquitousSharedItemCurrentUserRoleKey)
KEY(NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey) KEY(NSURLUbiquitousSharedItemOwnerNameComponentsKey)
KEY(NSURLVolumeCreationDateKey) KEY(NSURLVolumeIsAutomountedKey) KEY(NSURLVolumeIsBrowsableKey) KEY(NSURLVolumeIsEncryptedKey)
KEY(NSURLVolumeIsJournalingKey) KEY(NSURLVolumeIsRootFileSystemKey) KEY(NSURLVolumeMaximumFileSizeKey)
KEY(NSURLVolumeSupportsAccessPermissionsKey) KEY(NSURLVolumeSupportsAdvisoryFileLockingKey) KEY(NSURLVolumeSupportsCasePreservedNamesKey)
KEY(NSURLVolumeSupportsCaseSensitiveNamesKey) KEY(NSURLVolumeSupportsCompressionKey) KEY(NSURLVolumeSupportsExclusiveRenamingKey)
KEY(NSURLVolumeSupportsExtendedSecurityKey) KEY(NSURLVolumeSupportsHardLinksKey) KEY(NSURLVolumeSupportsImmutableFilesKey)
KEY(NSURLVolumeSupportsJournalingKey) KEY(NSURLVolumeSupportsPersistentIDsKey) KEY(NSURLVolumeSupportsRenamingKey)
KEY(NSURLVolumeSupportsRootDirectoryDatesKey) KEY(NSURLVolumeSupportsSparseFilesKey) KEY(NSURLVolumeSupportsSwapRenamingKey)
KEY(NSURLVolumeSupportsSymbolicLinksKey) KEY(NSURLVolumeSupportsVolumeSizesKey) KEY(NSURLVolumeSupportsZeroRunsKey)
KEY(NSURLVolumeURLForRemountingKey)
NSURLFileResourceType const NSURLFileResourceTypeNamedPipe = @"NSURLFileResourceTypeNamedPipe",
    NSURLFileResourceTypeCharacterSpecial = @"NSURLFileResourceTypeCharacterSpecial", NSURLFileResourceTypeDirectory = @"NSURLFileResourceTypeDirectory",
    NSURLFileResourceTypeBlockSpecial = @"NSURLFileResourceTypeBlockSpecial", NSURLFileResourceTypeRegular = @"NSURLFileResourceTypeRegular",
    NSURLFileResourceTypeSymbolicLink = @"NSURLFileResourceTypeSymbolicLink", NSURLFileResourceTypeSocket = @"NSURLFileResourceTypeSocket",
    NSURLFileResourceTypeUnknown = @"NSURLFileResourceTypeUnknown";
STR(NSStringEncodingDetectionSuggestedEncodingsKey) STR(NSStringEncodingDetectionDisallowedEncodingsKey)
STR(NSStringEncodingDetectionUseOnlySuggestedEncodingsKey) STR(NSStringEncodingDetectionAllowLossyKey) STR(NSStringEncodingDetectionFromWindowsKey)
STR(NSStringEncodingDetectionLossySubstitutionKey) STR(NSStringEncodingDetectionLikelyLanguageKey)
NSStringTransform const NSStringTransformLatinToKatakana = @"Latin-Katakana", NSStringTransformLatinToHiragana = @"Latin-Hiragana",
    NSStringTransformLatinToHangul = @"Latin-Hangul", NSStringTransformLatinToArabic = @"Latin-Arabic", NSStringTransformLatinToHebrew = @"Latin-Hebrew",
    NSStringTransformLatinToThai = @"Latin-Thai", NSStringTransformLatinToCyrillic = @"Latin-Cyrillic", NSStringTransformLatinToGreek = @"Latin-Greek",
    NSStringTransformToLatin = @"Any-Latin", NSStringTransformMandarinToLatin = @"Han-Latin", NSStringTransformHiraganaToKatakana = @"Hiragana-Katakana",
    NSStringTransformFullwidthToHalfwidth = @"Fullwidth-Halfwidth", NSStringTransformToXMLHex = @"Any-Hex/XML",
    NSStringTransformToUnicodeName = @"Any-Name", NSStringTransformStripCombiningMarks = @"NFD; [:Nonspacing Mark:] Remove; NFC",
    NSStringTransformStripDiacritics = @"NFD; [:Nonspacing Mark:] Remove; NFC";
double NSFoundationVersionNumber = 2048.0; /* macOS 14-era Foundation */

/* ======================================================================= memory pages */
NSUInteger NSPageSize(void) { return 4096; }
NSUInteger NSLogPageSize(void) { return 12; }
NSUInteger NSRoundUpToMultipleOfPageSize(NSUInteger b) { return (b + 4095) & ~(NSUInteger)4095; }
NSUInteger NSRoundDownToMultipleOfPageSize(NSUInteger b) { return b & ~(NSUInteger)4095; }
void NSCopyMemoryPages(const void *src, void *dst, NSUInteger n) { memmove(dst, src, n); }

/* ======================================================================= NSData support for the overlay */
int munmap(void *, size_t);
typedef void (^NSDataDeallocator)(void *, NSUInteger);
const NSDataDeallocator NSDataDeallocatorVM = ^(void *p, NSUInteger n) { munmap(p, n); };
const NSDataDeallocator NSDataDeallocatorUnmap = ^(void *p, NSUInteger n) { munmap(p, n); };
const NSDataDeallocator NSDataDeallocatorFree = ^(void *p, NSUInteger n) { free(p); };
const NSDataDeallocator NSDataDeallocatorNone = ^(void *p, NSUInteger n) { };
/* data and url are consumed (NS_RELEASES_ARGUMENT) */
BOOL __NSDataWriteToURL(NSData *data, NSURL *url, NSDataWritingOptions opts, NSError **err) {
    BOOL ok = [url isFileURL] && [data writeToFile:[url path] options:opts error:err];
    if (![url isFileURL] && err) *err = [NSError errorWithDomain:NSCocoaErrorDomain code:518 userInfo:nil]; /* unsupported scheme */
    [data release]; [url release];
    return ok;
}

/* ======================================================================= CoreFoundation for the overlay */
const CFAllocatorRef kCFAllocatorSystemDefault = 0, kCFAllocatorMalloc = 0, kCFAllocatorNull = 0;
/* NSNumber booleans, set when Foundation loads (the constants live in writable data) */
const CFBooleanRef kCFBooleanTrue __attribute__((section("__DATA,__data"))) = 0;
const CFBooleanRef kCFBooleanFalse __attribute__((section("__DATA,__data"))) = 0;
/* @YES / @NO compile to the address of the objects __kCFBooleanTrue / __kCFBooleanFalse themselves: static, immortal
   NSNumbers (filled in from the heap ones when Foundation loads); numberWithBool: returns them from then on */
@interface __NSCFBoolean : NSNumber @end
@implementation __NSCFBoolean
- (id)retain { return self; } - (oneway void)release { } - (id)autorelease { return self; } - (NSUInteger)retainCount { return NSUIntegerMax; } - (void)dealloc { }
@end
struct mw_static_object { uint64_t words[8]; };
struct mw_static_object __kCFBooleanTrue, __kCFBooleanFalse;
void mw_cf_booleans(void) { /* from mw_foundation_load: classes must be registered first */
    size_t sz = class_getInstanceSize([NSNumber class]);
    if (sz > sizeof __kCFBooleanTrue) abort();
    memcpy(&__kCFBooleanTrue, [NSNumber numberWithBool:YES], sz);
    memcpy(&__kCFBooleanFalse, [NSNumber numberWithBool:NO], sz);
    object_setClass((id)(void *)&__kCFBooleanTrue, [__NSCFBoolean class]);
    object_setClass((id)(void *)&__kCFBooleanFalse, [__NSCFBoolean class]);
    /* volatile: the constants are declared const, a plain store may be dropped */
    *(CFBooleanRef volatile *)&kCFBooleanTrue = (CFBooleanRef)(void *)&__kCFBooleanTrue;
    *(CFBooleanRef volatile *)&kCFBooleanFalse = (CFBooleanRef)(void *)&__kCFBooleanFalse;
}
Boolean CFBooleanGetValue(CFBooleanRef b) { return [(NSNumber *)b boolValue]; }
NSStringEncoding ns_encoding(CFStringEncoding e) {
    switch (e) {
    case kCFStringEncodingASCII: return NSASCIIStringEncoding;
    case kCFStringEncodingUTF8: return NSUTF8StringEncoding;
    case kCFStringEncodingISOLatin1: case kCFStringEncodingWindowsLatin1: return NSISOLatin1StringEncoding;
    case kCFStringEncodingUTF16LE: return NSUTF16LittleEndianStringEncoding;
    case kCFStringEncodingUTF16: return NSUTF16StringEncoding;
    }
    return NSUTF8StringEncoding;
}
CFStringRef CFStringCreateWithBytes(CFAllocatorRef a, const UInt8 *bytes, CFIndex n, CFStringEncoding e, Boolean ext) {
    return (CFStringRef)[[NSString alloc] initWithBytes:bytes length:(NSUInteger)n encoding:ns_encoding(e)];
}
CFStringRef CFStringCreateWithCString(CFAllocatorRef a, const char *s, CFStringEncoding e) {
    return (CFStringRef)[[NSString alloc] initWithBytes:s length:strlen(s) encoding:ns_encoding(e)];
}
CFIndex CFSetGetCount(CFSetRef s) { return (CFIndex)[(NSSet *)s count]; }
void CFSetGetValues(CFSetRef s, const void **values) { NSUInteger i = 0; for (id o in (NSSet *)s) values[i++] = o; }
CFSetRef CFSetCreateCopy(CFAllocatorRef a, CFSetRef s) { return (CFSetRef)[(NSSet *)s copy]; }
CFArrayRef CFArrayCreateCopy(CFAllocatorRef a, CFArrayRef s) { return (CFArrayRef)[(NSArray *)s copy]; }
CFDictionaryRef CFDictionaryCreateCopy(CFAllocatorRef a, CFDictionaryRef s) { return (CFDictionaryRef)[(NSDictionary *)s copy]; }
CFIndex CFArrayGetCount(CFArrayRef a) { return (CFIndex)[(NSArray *)a count]; }
CFIndex CFDictionaryGetCount(CFDictionaryRef d) { return (CFIndex)[(NSDictionary *)d count]; }
CFErrorDomain CFErrorGetDomain(CFErrorRef e) { return (CFErrorDomain)[(NSError *)e domain]; }
CFIndex CFErrorGetCode(CFErrorRef e) { return [(NSError *)e code]; }
CFDictionaryRef CFErrorCopyUserInfo(CFErrorRef e) { return (CFDictionaryRef)[[(NSError *)e userInfo] copy]; }
CFStringRef CFErrorCopyDescription(CFErrorRef e) { return (CFStringRef)[[(NSError *)e localizedDescription] copy]; }
CFStringRef CFLocaleCopyDisplayNameForPropertyValue(CFLocaleRef l, CFLocaleKey k, CFStringRef v) {
    return (CFStringRef)[[(NSLocale *)l displayNameForKey:(NSLocaleKey)k value:(id)v] copy];
}

/* character sets: CF calls on NSCharacterSet / NSMutableCharacterSet */
CFCharacterSetRef CFCharacterSetGetPredefined(CFCharacterSetPredefinedSet w) {
    switch (w) {
    case kCFCharacterSetControl: return (CFCharacterSetRef)[NSCharacterSet controlCharacterSet];
    case kCFCharacterSetWhitespace: return (CFCharacterSetRef)[NSCharacterSet whitespaceCharacterSet];
    case kCFCharacterSetWhitespaceAndNewline: return (CFCharacterSetRef)[NSCharacterSet whitespaceAndNewlineCharacterSet];
    case kCFCharacterSetDecimalDigit: return (CFCharacterSetRef)[NSCharacterSet decimalDigitCharacterSet];
    case kCFCharacterSetLetter: return (CFCharacterSetRef)[NSCharacterSet letterCharacterSet];
    case kCFCharacterSetLowercaseLetter: return (CFCharacterSetRef)[NSCharacterSet lowercaseLetterCharacterSet];
    case kCFCharacterSetUppercaseLetter: return (CFCharacterSetRef)[NSCharacterSet uppercaseLetterCharacterSet];
    case kCFCharacterSetNonBase: return (CFCharacterSetRef)[NSCharacterSet nonBaseCharacterSet];
    case kCFCharacterSetDecomposable: return (CFCharacterSetRef)[NSCharacterSet decomposableCharacterSet];
    case kCFCharacterSetAlphaNumeric: return (CFCharacterSetRef)[NSCharacterSet alphanumericCharacterSet];
    case kCFCharacterSetPunctuation: return (CFCharacterSetRef)[NSCharacterSet punctuationCharacterSet];
    case kCFCharacterSetIllegal: return (CFCharacterSetRef)[NSCharacterSet illegalCharacterSet];
    case kCFCharacterSetCapitalizedLetter: return (CFCharacterSetRef)[NSCharacterSet capitalizedLetterCharacterSet];
    case kCFCharacterSetSymbol: return (CFCharacterSetRef)[NSCharacterSet symbolCharacterSet];
    case kCFCharacterSetNewline: return (CFCharacterSetRef)[NSCharacterSet newlineCharacterSet];
    }
    return (CFCharacterSetRef)[NSCharacterSet characterSetWithCharactersInString:@""];
}
CFMutableCharacterSetRef CFCharacterSetCreateMutable(CFAllocatorRef a) { return (CFMutableCharacterSetRef)[[NSMutableCharacterSet alloc] init]; }
CFMutableCharacterSetRef CFCharacterSetCreateMutableCopy(CFAllocatorRef a, CFCharacterSetRef s) { return (CFMutableCharacterSetRef)[(NSCharacterSet *)s mutableCopy]; }
CFCharacterSetRef CFCharacterSetCreateWithCharactersInRange(CFAllocatorRef a, CFRange r) {
    NSMutableCharacterSet *s = [[NSMutableCharacterSet alloc] init]; [s addCharactersInRange:NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length)]; return (CFCharacterSetRef)s;
}
CFCharacterSetRef CFCharacterSetCreateWithCharactersInString(CFAllocatorRef a, CFStringRef str) {
    return (CFCharacterSetRef)[[NSCharacterSet characterSetWithCharactersInString:(NSString *)str] retain];
}
CFCharacterSetRef CFCharacterSetCreateWithBitmapRepresentation(CFAllocatorRef a, CFDataRef d) {
    return (CFCharacterSetRef)[[NSCharacterSet characterSetWithBitmapRepresentation:(NSData *)d] retain];
}
CFCharacterSetRef CFCharacterSetCreateInvertedSet(CFAllocatorRef a, CFCharacterSetRef s) { return (CFCharacterSetRef)[[(NSCharacterSet *)s invertedSet] retain]; }
CFDataRef CFCharacterSetCreateBitmapRepresentation(CFAllocatorRef a, CFCharacterSetRef s) { return (CFDataRef)[[(NSCharacterSet *)s bitmapRepresentation] retain]; }
Boolean CFCharacterSetIsSupersetOfSet(CFCharacterSetRef s, CFCharacterSetRef o) { return [(NSCharacterSet *)s isSupersetOfSet:(NSCharacterSet *)o]; }
Boolean CFCharacterSetHasMemberInPlane(CFCharacterSetRef s, CFIndex p) { return [(NSCharacterSet *)s hasMemberInPlane:(uint8_t)p]; }
Boolean CFCharacterSetIsLongCharacterMember(CFCharacterSetRef s, UTF32Char c) { return [(NSCharacterSet *)s longCharacterIsMember:c]; }
void CFCharacterSetAddCharactersInRange(CFMutableCharacterSetRef s, CFRange r) { [(NSMutableCharacterSet *)s addCharactersInRange:NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length)]; }
void CFCharacterSetRemoveCharactersInRange(CFMutableCharacterSetRef s, CFRange r) { [(NSMutableCharacterSet *)s removeCharactersInRange:NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length)]; }
void CFCharacterSetAddCharactersInString(CFMutableCharacterSetRef s, CFStringRef str) { [(NSMutableCharacterSet *)s addCharactersInString:(NSString *)str]; }
void CFCharacterSetRemoveCharactersInString(CFMutableCharacterSetRef s, CFStringRef str) { [(NSMutableCharacterSet *)s removeCharactersInString:(NSString *)str]; }
void CFCharacterSetInvert(CFMutableCharacterSetRef s) { [(NSMutableCharacterSet *)s invert]; }
void CFCharacterSetUnion(CFMutableCharacterSetRef s, CFCharacterSetRef o) { [(NSMutableCharacterSet *)s formUnionWithCharacterSet:(NSCharacterSet *)o]; }
void CFCharacterSetIntersect(CFMutableCharacterSetRef s, CFCharacterSetRef o) { [(NSMutableCharacterSet *)s formIntersectionWithCharacterSet:(NSCharacterSet *)o]; }
/* RFC 3986 character classes */
static NSCharacterSet *url_set(NSString *extra) {
    NSMutableCharacterSet *s = [[NSMutableCharacterSet alloc] init];
    [s addCharactersInRange:NSMakeRange('a', 26)]; [s addCharactersInRange:NSMakeRange('A', 26)]; [s addCharactersInRange:NSMakeRange('0', 10)];
    [s addCharactersInString:extra];
    return [s autorelease];
}
#define URL_SET(fn, extra) CFCharacterSetRef fn(void) { return (CFCharacterSetRef)url_set(extra); }
URL_SET(_CFURLComponentsGetURLUserAllowedCharacterSet, @"-._~!$&'()*+,;=")
URL_SET(_CFURLComponentsGetURLPasswordAllowedCharacterSet, @"-._~!$&'()*+,;=")
URL_SET(_CFURLComponentsGetURLHostAllowedCharacterSet, @"-._~!$&'()*+,;=:[]")
URL_SET(_CFURLComponentsGetURLPathAllowedCharacterSet, @"-._~!$&'()*+,;=:@/")
URL_SET(_CFURLComponentsGetURLQueryAllowedCharacterSet, @"-._~!$&'()*+,;=:@/?")
URL_SET(_CFURLComponentsGetURLFragmentAllowedCharacterSet, @"-._~!$&'()*+,;=:@/?")
@implementation NSCharacterSet (NSExtendedCharacterSet)
+ (NSCharacterSet *)URLUserAllowedCharacterSet { return url_set(@"-._~!$&'()*+,;="); }
+ (NSCharacterSet *)URLPasswordAllowedCharacterSet { return url_set(@"-._~!$&'()*+,;="); }
+ (NSCharacterSet *)URLHostAllowedCharacterSet { return url_set(@"-._~!$&'()*+,;=:[]"); }
+ (NSCharacterSet *)URLPathAllowedCharacterSet { return url_set(@"-._~!$&'()*+,;=:@/"); }
+ (NSCharacterSet *)URLQueryAllowedCharacterSet { return url_set(@"-._~!$&'()*+,;=:@/?"); }
+ (NSCharacterSet *)URLFragmentAllowedCharacterSet { return url_set(@"-._~!$&'()*+,;=:@/?"); }
static NSCharacterSet *range_set(unichar a, unichar b) { NSMutableCharacterSet *s = [[NSMutableCharacterSet alloc] init]; [s addCharactersInRange:NSMakeRange(a, (NSUInteger)(b - a + 1))]; return [s autorelease]; }
+ (NSCharacterSet *)controlCharacterSet { NSMutableCharacterSet *s = (NSMutableCharacterSet *)range_set(0, 0x1f); [s addCharactersInRange:NSMakeRange(0x7f, 0x21)]; return s; }
+ (NSCharacterSet *)decomposableCharacterSet { return range_set(0xc0, 0x17f); } /* ponytail: Latin-1 and Latin Extended-A */
+ (NSCharacterSet *)illegalCharacterSet { return range_set(0xfffe, 0xffff); }
+ (NSCharacterSet *)capitalizedLetterCharacterSet { return [NSCharacterSet uppercaseLetterCharacterSet]; }
+ (NSCharacterSet *)symbolCharacterSet { return [NSCharacterSet characterSetWithCharactersInString:@"$+<=>^`|~¢£¤¥¦¨©¬®¯°±´¸×÷"]; }
+ (NSCharacterSet *)nonBaseCharacterSet { return range_set(0x300, 0x36f); }
+ (NSCharacterSet *)characterSetWithRange:(NSRange)r { NSMutableCharacterSet *s = [[NSMutableCharacterSet alloc] init]; [s addCharactersInRange:r]; return [s autorelease]; }
+ (NSCharacterSet *)characterSetWithBitmapRepresentation:(NSData *)d {
    NSMutableCharacterSet *s = [[NSMutableCharacterSet alloc] init];
    const uint8_t *b = [d bytes]; NSUInteger n = [d length] < 8192 ? [d length] : 8192;
    for (NSUInteger i = 0; i < n * 8; i++) if (b[i >> 3] & (1 << (i & 7))) [s addCharactersInRange:NSMakeRange(i, 1)];
    return [s autorelease];
}
+ (NSCharacterSet *)characterSetWithContentsOfFile:(NSString *)f { NSData *d = [NSData dataWithContentsOfFile:f]; return d ? [self characterSetWithBitmapRepresentation:d] : nil; }
- (instancetype)initWithCoder:(NSCoder *)c { [self release]; return nil; }
- (BOOL)longCharacterIsMember:(uint32_t)c { return c <= 0xffff ? [self characterIsMember:(unichar)c] : [self characterIsMember:0xfffd] && ![self characterIsMember:'a'] ; }
- (NSData *)bitmapRepresentation {
    NSMutableData *d = [NSMutableData dataWithLength:8192]; uint8_t *b = [d mutableBytes];
    for (NSUInteger i = 0; i < 65536; i++) if ([self characterIsMember:(unichar)i]) b[i >> 3] |= (uint8_t)(1 << (i & 7));
    return d;
}
- (BOOL)isSupersetOfSet:(NSCharacterSet *)o { for (NSUInteger i = 0; i < 65536; i++) if ([o characterIsMember:(unichar)i] && ![self characterIsMember:(unichar)i]) return NO; return YES; }
- (BOOL)hasMemberInPlane:(uint8_t)p { if (p) return NO; for (NSUInteger i = 0; i < 65536; i++) if ([self characterIsMember:(unichar)i]) return YES; return NO; }
@end

/* ======================================================================= NSDecimal (ponytail: through double) */
static double dec_to_double(const NSDecimal *d) {
    double m = 0; for (int i = (int)d->_length - 1; i >= 0; i--) m = m * 65536.0 + d->_mantissa[i];
    double p = 1; int e = d->_exponent; double b = e < 0 ? 0.1 : 10; for (int i = 0; i < (e < 0 ? -e : e); i++) p *= b;
    return (d->_isNegative ? -m : m) * p;
}
static NSDecimal dec_from_double(double v) {
    NSDecimal d; memset(&d, 0, sizeof d);
    if (v != v) { d._length = 0; d._isNegative = 1; return d; } /* NaN */
    if (v < 0) { d._isNegative = 1; v = -v; }
    int e = 0;
    while (v != 0 && v < 1e17 && v != (double)(unsigned long long)v && e > -40) { v *= 10; e--; }
    while (v >= 1.8e19) { v /= 10; e++; }
    unsigned long long m = (unsigned long long)(v + 0.5);
    while (m && m % 10 == 0 && e < 0) { m /= 10; e++; }
    d._exponent = e; int n = 0; while (m) { d._mantissa[n++] = (unsigned short)(m & 0xffff); m >>= 16; }
    d._length = (unsigned)n; d._isCompact = 1;
    return d;
}
void NSDecimalCopy(NSDecimal *dst, const NSDecimal *src) { *dst = *src; }
void NSDecimalCompact(NSDecimal *n) { *n = dec_from_double(dec_to_double(n)); }
NSComparisonResult NSDecimalCompare(const NSDecimal *a, const NSDecimal *b) {
    double x = dec_to_double(a), y = dec_to_double(b); return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
}
double round(double); double floor(double); double ceil(double); double pow(double, double); double fabs(double);
void NSDecimalRound(NSDecimal *r, const NSDecimal *n, NSInteger scale, NSRoundingMode mode) {
    double v = dec_to_double(n), p = pow(10, (double)scale), x = v * p;
    x = mode == NSRoundDown ? floor(x) : mode == NSRoundUp ? ceil(x) : round(x);
    *r = dec_from_double(x / p);
}
NSCalculationError NSDecimalNormalize(NSDecimal *a, NSDecimal *b, NSRoundingMode m) { return NSCalculationNoError; }
#define DEC_OP(name, expr) NSCalculationError name(NSDecimal *r, const NSDecimal *a, const NSDecimal *b, NSRoundingMode m) { \
    double x = dec_to_double(a), y = dec_to_double(b); *r = dec_from_double(expr); return NSCalculationNoError; }
DEC_OP(NSDecimalAdd, x + y) DEC_OP(NSDecimalSubtract, x - y) DEC_OP(NSDecimalMultiply, x * y)
NSCalculationError NSDecimalDivide(NSDecimal *r, const NSDecimal *a, const NSDecimal *b, NSRoundingMode m) {
    double y = dec_to_double(b); if (y == 0) { *r = dec_from_double(0.0 / 0.0); return NSCalculationDivideByZero; }
    *r = dec_from_double(dec_to_double(a) / y); return NSCalculationNoError;
}
NSCalculationError NSDecimalPower(NSDecimal *r, const NSDecimal *n, NSUInteger p, NSRoundingMode m) { *r = dec_from_double(pow(dec_to_double(n), (double)p)); return NSCalculationNoError; }
NSCalculationError NSDecimalMultiplyByPowerOf10(NSDecimal *r, const NSDecimal *n, short p, NSRoundingMode m) { *r = *n; r->_exponent += p; return NSCalculationNoError; }
NSString *NSDecimalString(const NSDecimal *d, id locale) {
    if (d->_length == 0 && d->_isNegative) return @"NaN";
    char buf[64]; snprintf(buf, sizeof buf, "%.17g", dec_to_double(d));
    /* shortest form that reads back the same */
    for (int p = 1; p <= 17; p++) { char t[64]; snprintf(t, sizeof t, "%.*g", p, dec_to_double(d)); if (strtod(t, 0) == dec_to_double(d)) { memcpy(buf, t, sizeof t); break; } }
    return [NSString stringWithUTF8String:buf];
}
@implementation NSDecimalNumber { NSDecimal _d; }
- (instancetype)initWithDecimal:(NSDecimal)d { _d = d; return self; }
- (instancetype)initWithMantissa:(unsigned long long)m exponent:(short)e isNegative:(BOOL)neg {
    NSDecimal d; memset(&d, 0, sizeof d); d._exponent = e; d._isNegative = neg; int n = 0;
    while (m) { d._mantissa[n++] = (unsigned short)(m & 0xffff); m >>= 16; } d._length = (unsigned)n; return [self initWithDecimal:d];
}
- (instancetype)initWithString:(NSString *)s { return [self initWithString:s locale:nil]; }
- (instancetype)initWithString:(NSString *)s locale:(id)l { return [self initWithDecimal:dec_from_double(strtod([s UTF8String], 0))]; }
+ (NSDecimalNumber *)decimalNumberWithDecimal:(NSDecimal)d { return [[[self alloc] initWithDecimal:d] autorelease]; }
+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)s { return [[[self alloc] initWithString:s] autorelease]; }
+ (NSDecimalNumber *)zero { return [self decimalNumberWithDecimal:dec_from_double(0)]; }
+ (NSDecimalNumber *)one { return [self decimalNumberWithDecimal:dec_from_double(1)]; }
+ (NSDecimalNumber *)minimumDecimalNumber { return [self decimalNumberWithDecimal:dec_from_double(-1.8e19)]; }
+ (NSDecimalNumber *)maximumDecimalNumber { return [self decimalNumberWithDecimal:dec_from_double(1.8e19)]; }
+ (NSDecimalNumber *)notANumber { return [self decimalNumberWithDecimal:dec_from_double(0.0 / 0.0)]; }
- (NSDecimal)decimalValue { return _d; }
- (double)doubleValue { return dec_to_double(&_d); }
- (long long)longLongValue { return (long long)dec_to_double(&_d); }
- (NSInteger)integerValue { return (NSInteger)dec_to_double(&_d); }
- (int)intValue { return (int)dec_to_double(&_d); }
- (BOOL)boolValue { return dec_to_double(&_d) != 0; }
- (const char *)objCType { return "d"; }
- (NSString *)stringValue { return NSDecimalString(&_d, nil); }
- (NSString *)description { return NSDecimalString(&_d, nil); }
- (NSString *)descriptionWithLocale:(id)l { return NSDecimalString(&_d, l); }
@end
@implementation NSNumber (NSDecimalValue)
- (NSDecimal)decimalValue { return dec_from_double([self doubleValue]); }
@end

/* ======================================================================= index sets (sorted, coalesced ranges) */
@implementation NSIndexSet { @public NSRange *_r; NSUInteger _n, _cap; }
- (instancetype)init { return self; }
- (instancetype)initWithIndexesInRange:(NSRange)r { if (r.length) { _r = malloc(sizeof *_r); _r[0] = r; _n = _cap = 1; } return self; }
- (instancetype)initWithIndexSet:(NSIndexSet *)s { if (s->_n) { _r = malloc(s->_n * sizeof *_r); memcpy(_r, s->_r, s->_n * sizeof *_r); _n = _cap = s->_n; } return self; }
- (instancetype)initWithIndex:(NSUInteger)v { return [self initWithIndexesInRange:NSMakeRange(v, 1)]; }
- (void)dealloc { free(_r); [super dealloc]; }
+ (instancetype)indexSet { return [[[self alloc] init] autorelease]; }
+ (instancetype)indexSetWithIndex:(NSUInteger)v { return [[[self alloc] initWithIndex:v] autorelease]; }
+ (instancetype)indexSetWithIndexesInRange:(NSRange)r { return [[[self alloc] initWithIndexesInRange:r] autorelease]; }
- (id)copyWithZone:(NSZone *)z { return [[NSIndexSet alloc] initWithIndexSet:self]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableIndexSet alloc] initWithIndexSet:self]; }
- (NSUInteger)count { NSUInteger c = 0; for (NSUInteger i = 0; i < _n; i++) c += _r[i].length; return c; }
- (NSUInteger)firstIndex { return _n ? _r[0].location : NSNotFound; }
- (NSUInteger)lastIndex { return _n ? NSMaxRange(_r[_n - 1]) - 1 : NSNotFound; }
- (NSUInteger)rangeCount { return _n; }
- (NSRange)rangeAtIndex:(NSUInteger)i { return _r[i]; }
- (NSUInteger)_indexOfRangeContainingIndex:(NSUInteger)v { for (NSUInteger i = 0; i < _n; i++) if (NSLocationInRange(v, _r[i])) return i; return NSNotFound; }
- (BOOL)containsIndex:(NSUInteger)v { return [self _indexOfRangeContainingIndex:v] != NSNotFound; }
- (BOOL)containsIndexesInRange:(NSRange)r { for (NSUInteger i = 0; i < _n; i++) if (r.location >= _r[i].location && NSMaxRange(r) <= NSMaxRange(_r[i])) return YES; return r.length == 0; }
- (BOOL)containsIndexes:(NSIndexSet *)s { for (NSUInteger i = 0; i < s->_n; i++) if (![self containsIndexesInRange:s->_r[i]]) return NO; return YES; }
- (BOOL)intersectsIndexesInRange:(NSRange)r { for (NSUInteger i = 0; i < _n; i++) if (_r[i].location < NSMaxRange(r) && r.location < NSMaxRange(_r[i])) return YES; return NO; }
- (NSUInteger)countOfIndexesInRange:(NSRange)r {
    NSUInteger c = 0; for (NSUInteger i = 0; i < _n; i++) { NSUInteger a = _r[i].location > r.location ? _r[i].location : r.location, b = NSMaxRange(_r[i]) < NSMaxRange(r) ? NSMaxRange(_r[i]) : NSMaxRange(r); if (b > a) c += b - a; }
    return c;
}
- (NSUInteger)indexGreaterThanOrEqualToIndex:(NSUInteger)v { for (NSUInteger i = 0; i < _n; i++) { if (NSLocationInRange(v, _r[i])) return v; if (_r[i].location > v) return _r[i].location; } return NSNotFound; }
- (NSUInteger)indexGreaterThanIndex:(NSUInteger)v { return v == NSNotFound - 1 ? NSNotFound : [self indexGreaterThanOrEqualToIndex:v + 1]; }
- (NSUInteger)indexLessThanOrEqualToIndex:(NSUInteger)v { for (NSUInteger i = _n; i-- > 0;) { if (NSLocationInRange(v, _r[i])) return v; if (NSMaxRange(_r[i]) <= v) return NSMaxRange(_r[i]) - 1; } return NSNotFound; }
- (NSUInteger)indexLessThanIndex:(NSUInteger)v { return v == 0 ? NSNotFound : [self indexLessThanOrEqualToIndex:v - 1]; }
- (NSUInteger)getIndexes:(NSUInteger *)buf maxCount:(NSUInteger)max inIndexRange:(NSRangePointer)rp {
    NSRange r = rp ? *rp : NSMakeRange(0, NSNotFound); NSUInteger c = 0, v = [self indexGreaterThanOrEqualToIndex:r.location];
    while (c < max && v != NSNotFound && v < NSMaxRange(r)) { buf[c++] = v; v = [self indexGreaterThanIndex:v]; }
    if (rp) { NSUInteger end = NSMaxRange(r); rp->location = v == NSNotFound || v >= end ? end : v; rp->length = end - rp->location; }
    return c;
}
- (BOOL)isEqualToIndexSet:(NSIndexSet *)s { if (s->_n != _n) return NO; for (NSUInteger i = 0; i < _n; i++) if ((_r[i].location != s->_r[i].location || _r[i].length != s->_r[i].length)) return NO; return YES; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSIndexSet class]] && [self isEqualToIndexSet:o]; }
- (NSUInteger)hash { return [self count] ^ (_n ? _r[0].location : 0); }
- (void)enumerateIndexesUsingBlock:(void (^)(NSUInteger, BOOL *))b { [self enumerateIndexesInRange:NSMakeRange(0, NSNotFound) options:0 usingBlock:b]; }
- (void)enumerateIndexesInRange:(NSRange)r options:(NSEnumerationOptions)o usingBlock:(void (^)(NSUInteger, BOOL *))b {
    BOOL stop = NO;
    if (o & NSEnumerationReverse) { for (NSUInteger v = [self indexLessThanOrEqualToIndex:NSMaxRange(r) - 1]; !stop && v != NSNotFound && v >= r.location; v = [self indexLessThanIndex:v]) b(v, &stop); }
    else for (NSUInteger v = [self indexGreaterThanOrEqualToIndex:r.location]; !stop && v != NSNotFound && v < NSMaxRange(r); v = [self indexGreaterThanIndex:v]) b(v, &stop);
}
- (void)enumerateRangesUsingBlock:(void (^)(NSRange, BOOL *))b { BOOL stop = NO; for (NSUInteger i = 0; i < _n && !stop; i++) b(_r[i], &stop); }
- (NSIndexSet *)indexesInRange:(NSRange)r options:(NSEnumerationOptions)o passingTest:(BOOL (^)(NSUInteger, BOOL *))t {
    NSMutableIndexSet *s = [NSMutableIndexSet indexSet];
    [self enumerateIndexesInRange:r options:o usingBlock:^(NSUInteger v, BOOL *stop) { if (t(v, stop)) [s addIndex:v]; }];
    return s;
}
- (NSIndexSet *)indexesPassingTest:(BOOL (^)(NSUInteger, BOOL *))t { return [self indexesInRange:NSMakeRange(0, NSNotFound) options:0 passingTest:t]; }
- (NSUInteger)indexPassingTest:(BOOL (^)(NSUInteger, BOOL *))t {
    __block NSUInteger found = NSNotFound;
    [self enumerateIndexesUsingBlock:^(NSUInteger v, BOOL *stop) { if (t(v, stop)) { found = v; *stop = YES; } }];
    return found;
}
- (NSString *)description { NSMutableString *s = [NSMutableString stringWithString:@"<NSIndexSet>["]; for (NSUInteger i = 0; i < _n; i++) [s appendFormat:@"%@(%lu-%lu)", i ? @" " : @"", (unsigned long)_r[i].location, (unsigned long)NSMaxRange(_r[i]) - 1]; [s appendString:@"]"]; return s; }
@end
@implementation NSMutableIndexSet
- (id)copyWithZone:(NSZone *)z { return [[NSIndexSet alloc] initWithIndexSet:self]; }
static void is_put(NSIndexSet *s, NSRange r) { /* add, keeping ranges sorted and merged */
    if (!r.length) return;
    NSRange *out = malloc((s->_n + 1) * sizeof *out); NSUInteger k = 0; BOOL placed = NO;
    for (NSUInteger i = 0; i < s->_n; i++) {
        NSRange c = s->_r[i];
        if (NSMaxRange(c) < r.location) { out[k++] = c; continue; }
        if (NSMaxRange(r) < c.location) { if (!placed) { out[k++] = r; placed = YES; } out[k++] = c; continue; }
        NSUInteger a = c.location < r.location ? c.location : r.location, b = NSMaxRange(c) > NSMaxRange(r) ? NSMaxRange(c) : NSMaxRange(r); r = NSMakeRange(a, b - a);
    }
    if (!placed) { out[k++] = r; for (NSUInteger i = 0; i + 1 < k; i++) if (out[i].location > out[i + 1].location) { NSRange t = out[i]; out[i] = out[i + 1]; out[i + 1] = t; } }
    free(s->_r); s->_r = out; s->_n = k;
}
static void is_cut(NSIndexSet *s, NSRange r) {
    if (!r.length) return;
    NSRange *out = malloc((s->_n + 1) * sizeof *out); NSUInteger k = 0;
    for (NSUInteger i = 0; i < s->_n; i++) {
        NSRange c = s->_r[i];
        if (NSMaxRange(c) <= r.location || NSMaxRange(r) <= c.location) { out[k++] = c; continue; }
        if (c.location < r.location) out[k++] = NSMakeRange(c.location, r.location - c.location);
        if (NSMaxRange(c) > NSMaxRange(r)) out[k++] = NSMakeRange(NSMaxRange(r), NSMaxRange(c) - NSMaxRange(r));
    }
    free(s->_r); s->_r = out; s->_n = k;
}
- (void)addIndex:(NSUInteger)v { is_put(self, NSMakeRange(v, 1)); }
- (void)addIndexesInRange:(NSRange)r { is_put(self, r); }
- (void)addIndexes:(NSIndexSet *)s { for (NSUInteger i = 0; i < s->_n; i++) is_put(self, s->_r[i]); }
- (void)removeIndex:(NSUInteger)v { is_cut(self, NSMakeRange(v, 1)); }
- (void)removeIndexesInRange:(NSRange)r { is_cut(self, r); }
- (void)removeIndexes:(NSIndexSet *)s { for (NSUInteger i = 0; i < s->_n; i++) is_cut(self, s->_r[i]); }
- (void)removeAllIndexes { _n = 0; }
- (void)shiftIndexesStartingAtIndex:(NSUInteger)start by:(NSInteger)delta {
    NSMutableIndexSet *keep = [NSMutableIndexSet indexSet], *moved = [NSMutableIndexSet indexSet];
    [self enumerateIndexesUsingBlock:^(NSUInteger v, BOOL *stop) {
        if (v < start) [keep addIndex:v];
        else if ((NSInteger)v + delta >= (NSInteger)start || delta > 0) { if ((NSInteger)v + delta >= 0) [moved addIndex:(NSUInteger)((NSInteger)v + delta)]; }
    }];
    if (delta < 0) [keep removeIndexesInRange:NSMakeRange((NSUInteger)((NSInteger)start + delta), (NSUInteger)-delta)];
    [keep addIndexes:moved];
    free(_r); _n = keep->_n; _r = malloc((_n ? _n : 1) * sizeof *_r); memcpy(_r, keep->_r, _n * sizeof *_r);
}
@end

/* ======================================================================= small classes */
@implementation NSPersonNameComponents { NSString *_s[6]; NSPersonNameComponents *_ph; }
- (void)dealloc { for (int i = 0; i < 6; i++) [_s[i] release]; [_ph release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSPersonNameComponents *c = [[NSPersonNameComponents alloc] init]; for (int i = 0; i < 6; i++) c->_s[i] = [_s[i] copy]; c->_ph = [_ph copy]; return c; }
#define NAME(get, set, i) - (NSString *)get { return _s[i]; } - (void)set:(NSString *)v { [_s[i] release]; _s[i] = [v copy]; }
NAME(namePrefix, setNamePrefix, 0) NAME(givenName, setGivenName, 1) NAME(middleName, setMiddleName, 2) NAME(familyName, setFamilyName, 3)
NAME(nameSuffix, setNameSuffix, 4) NAME(nickname, setNickname, 5)
- (NSPersonNameComponents *)phoneticRepresentation { return _ph; } - (void)setPhoneticRepresentation:(NSPersonNameComponents *)p { [_ph release]; _ph = [p copy]; }
- (BOOL)isEqual:(id)o {
    if (![o isKindOfClass:[NSPersonNameComponents class]]) return NO;
    NSPersonNameComponents *c = o; for (int i = 0; i < 6; i++) if (_s[i] != c->_s[i] && ![_s[i] isEqual:c->_s[i]]) return NO; return YES;
}
- (NSUInteger)hash { return [_s[1] hash] ^ [_s[3] hash]; }
@end
@implementation NSFileSecurity
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end
@implementation NSOrthography
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)dominantScript { return @"Latn"; }
- (NSDictionary *)languageMap { return @{@"Latn": @[@"en"]}; }
+ (instancetype)defaultOrthographyForLanguage:(NSString *)l { return [[[self alloc] init] autorelease]; }
@end
@implementation NSLinguisticTagger
@end
/* ======================================================================= NSString additions the Swift overlay calls */
static BOOL is_line_end(unichar c, BOOL para) { return c == '\n' || c == '\r' || c == 0x85 || c == 0x2029 || (!para && c == 0x2028); }
static void line_bounds(NSString *s, NSRange r, NSUInteger *start, NSUInteger *end, NSUInteger *cend, BOOL para) {
    NSUInteger n = [s length], a = r.location, b = NSMaxRange(r);
    while (a > 0 && !is_line_end([s characterAtIndex:a - 1], para)) a--;
    if (b > a && b <= n && is_line_end([s characterAtIndex:b - 1], para)) b--; /* the range already ends at a terminator */
    if (b > 0 && b < n && [s characterAtIndex:b - 1] == '\r' && [s characterAtIndex:b] == '\n') b--;
    NSUInteger ce = b; while (ce < n && !is_line_end([s characterAtIndex:ce], para)) ce++;
    NSUInteger e = ce;
    if (e < n) { e++; if ([s characterAtIndex:e - 1] == '\r' && e < n && [s characterAtIndex:e] == '\n') e++; }
    if (start) *start = a; if (end) *end = e; if (cend) *cend = ce;
}
static BOOL is_mark(unichar c) { return (c >= 0x300 && c < 0x370) || (c >= 0x1ab0 && c < 0x1b00) || (c >= 0x20d0 && c < 0x2100) || (c >= 0xfe20 && c < 0xfe30) || c == 0x200d || (c >= 0xfe00 && c < 0xfe10); }
static unichar strip_accent(unichar c) {
    static const char map[] = "AAAAAA?CEEEEIIIIDNOOOOO?OUUUUY??aaaaaa?ceeeeiiiidnooooo?ouuuuy?y";
    if (c >= 0xc0 && c <= 0xff && map[c - 0xc0] != '?') return (unichar)map[c - 0xc0];
    return c;
}
@implementation NSString (MWSwiftOverlay)
/* the Swift runtime's fast paths into NSString storage: none, it falls back to getCharacters / getBytes */
- (const char *)_fastCStringContents:(BOOL)nulTerminated { return NULL; }
- (const unichar *)_fastCharacterContents { return NULL; }
+ (const NSStringEncoding *)availableStringEncodings {
    static const NSStringEncoding e[] = {NSASCIIStringEncoding, NSUTF8StringEncoding, NSISOLatin1StringEncoding, 12, NSUTF16StringEncoding,
                                         NSUTF16LittleEndianStringEncoding, 0x90000100, 0};
    return e;
}
+ (NSStringEncoding)defaultCStringEncoding { return NSUTF8StringEncoding; }
+ (NSString *)localizedNameOfStringEncoding:(NSStringEncoding)e {
    switch (e) { case NSASCIIStringEncoding: return @"Western (ASCII)"; case NSUTF8StringEncoding: return @"Unicode (UTF-8)";
                 case NSISOLatin1StringEncoding: return @"Western (ISO Latin 1)"; case 12: return @"Western (Windows Latin 1)";
                 case NSUTF16StringEncoding: return @"Unicode (UTF-16)"; case NSUTF16LittleEndianStringEncoding: return @"Unicode (UTF-16LE)";
                 case 0x90000100: return @"Unicode (UTF-16BE)"; }
    return @"";
}
- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)e { return [self dataUsingEncoding:e] != nil; }
- (NSStringEncoding)fastestEncoding { return NSUTF16StringEncoding; }
- (NSStringEncoding)smallestEncoding { return [self canBeConvertedToEncoding:NSASCIIStringEncoding] ? NSASCIIStringEncoding : NSUTF8StringEncoding; }
- (instancetype)initWithBytesNoCopy:(void *)b length:(NSUInteger)n encoding:(NSStringEncoding)e freeWhenDone:(BOOL)f {
    id r = [self initWithBytes:b length:n encoding:e]; if (f) free(b); return r;
}
- (instancetype)initWithCString:(const char *)s encoding:(NSStringEncoding)e { return [self initWithBytes:s length:strlen(s) encoding:e]; }
static id adopt(NSString *me, NSString *s) { if (!s) { [me release]; return nil; } return [me initWithString:s]; }
- (instancetype)initWithContentsOfFile:(NSString *)p encoding:(NSStringEncoding)e error:(NSError **)err { return adopt(self, [NSString stringWithContentsOfFile:p encoding:e error:err]); }
- (instancetype)initWithContentsOfFile:(NSString *)p usedEncoding:(NSStringEncoding *)e error:(NSError **)err { return adopt(self, [NSString stringWithContentsOfFile:p usedEncoding:e error:err]); }
- (instancetype)initWithContentsOfURL:(NSURL *)u encoding:(NSStringEncoding)e error:(NSError **)err { return adopt(self, [NSString stringWithContentsOfFile:[u path] encoding:e error:err]); }
- (instancetype)initWithContentsOfURL:(NSURL *)u usedEncoding:(NSStringEncoding *)e error:(NSError **)err { return adopt(self, [NSString stringWithContentsOfFile:[u path] usedEncoding:e error:err]); }
- (instancetype)initWithFormat:(NSString *)f locale:(id)l arguments:(va_list)ap { return [self initWithFormat:f arguments:ap]; }
- (BOOL)writeToURL:(NSURL *)u atomically:(BOOL)a encoding:(NSStringEncoding)e error:(NSError **)err {
    if (![u isFileURL]) { if (err) *err = [NSError errorWithDomain:NSCocoaErrorDomain code:518 userInfo:nil]; return NO; }
    return [self writeToFile:[u path] atomically:a encoding:e error:err];
}
- (NSString *)capitalizedStringWithLocale:(NSLocale *)l { return [self capitalizedString]; }
- (NSString *)lowercaseStringWithLocale:(NSLocale *)l { return [self lowercaseString]; }
- (NSString *)uppercaseStringWithLocale:(NSLocale *)l { return [self uppercaseString]; }
- (NSString *)localizedCapitalizedString { return [self capitalizedString]; }
- (NSString *)localizedLowercaseString { return [self lowercaseString]; }
- (NSString *)localizedUppercaseString { return [self uppercaseString]; }
- (NSComparisonResult)compare:(NSString *)o options:(NSStringCompareOptions)m range:(NSRange)r locale:(id)l { return [self compare:o options:m range:r]; }
- (NSRange)rangeOfString:(NSString *)s options:(NSStringCompareOptions)m range:(NSRange)r locale:(NSLocale *)l { return [self rangeOfString:s options:m range:r]; }
- (BOOL)localizedStandardContainsString:(NSString *)s { return [self rangeOfString:s options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound; }
- (NSRange)localizedStandardRangeOfString:(NSString *)s { return [self rangeOfString:s options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch]; }
- (NSString *)commonPrefixWithString:(NSString *)o options:(NSStringCompareOptions)m {
    NSUInteger n = MIN([self length], [o length]), i = 0;
    for (; i < n; i++) {
        unichar a = [self characterAtIndex:i], b = [o characterAtIndex:i];
        if (m & NSCaseInsensitiveSearch) { a = (unichar)(a < 128 ? tolower(a) : a); b = (unichar)(b < 128 ? tolower(b) : b); }
        if (a != b) break;
    }
    return [self substringToIndex:i];
}
- (NSString *)decomposedStringWithCompatibilityMapping { return [self decomposedStringWithCanonicalMapping]; }
- (NSString *)precomposedStringWithCompatibilityMapping { return [self precomposedStringWithCanonicalMapping]; }
- (NSString *)stringByFoldingWithOptions:(NSStringCompareOptions)o locale:(NSLocale *)l {
    NSString *s = (o & NSCaseInsensitiveSearch) ? [self lowercaseString] : self;
    return (o & NSDiacriticInsensitiveSearch) ? [s stringByApplyingTransform:NSStringTransformStripDiacritics reverse:NO] : [[s copy] autorelease];
}
- (NSString *)stringByApplyingTransform:(NSStringTransform)t reverse:(BOOL)rev {
    if (rev || !([t isEqualToString:NSStringTransformStripDiacritics] || [t isEqualToString:NSStringTransformStripCombiningMarks])) return nil; /* ponytail: no ICU transforms */
    NSUInteger n, k = 0; unichar *u = mw_chars(self, &n);
    for (NSUInteger i = 0; i < n; i++) if (!is_mark(u[i])) u[k++] = strip_accent(u[i]);
    return mw_str_take(u, k);
}
- (NSRange)lineRangeForRange:(NSRange)r { NSUInteger a, e; line_bounds(self, r, &a, &e, 0, NO); return NSMakeRange(a, e - a); }
- (NSRange)paragraphRangeForRange:(NSRange)r { NSUInteger a, e; line_bounds(self, r, &a, &e, 0, YES); return NSMakeRange(a, e - a); }
- (void)getLineStart:(NSUInteger *)s end:(NSUInteger *)e contentsEnd:(NSUInteger *)c forRange:(NSRange)r { line_bounds(self, r, s, e, c, NO); }
- (void)getParagraphStart:(NSUInteger *)s end:(NSUInteger *)e contentsEnd:(NSUInteger *)c forRange:(NSRange)r { line_bounds(self, r, s, e, c, YES); }
- (NSRange)rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)i {
    NSUInteger n = [self length], a = i, e = i + 1;
    while (a > 0 && ((is_mark([self characterAtIndex:a]) ) || ([self characterAtIndex:a] >= 0xdc00 && [self characterAtIndex:a] < 0xe000))) a--;
    while (e < n && (is_mark([self characterAtIndex:e]) || ([self characterAtIndex:e] >= 0xdc00 && [self characterAtIndex:e] < 0xe000) || [self characterAtIndex:e - 1] == 0x200d)) e++;
    return NSMakeRange(a, e - a);
}
- (NSRange)rangeOfComposedCharacterSequencesForRange:(NSRange)r {
    if (![self length]) return r;
    NSRange a = [self rangeOfComposedCharacterSequenceAtIndex:r.location];
    NSRange b = r.length ? [self rangeOfComposedCharacterSequenceAtIndex:NSMaxRange(r) - 1] : a;
    return NSMakeRange(a.location, NSMaxRange(b) - a.location);
}
- (void)enumerateSubstringsInRange:(NSRange)r options:(NSStringEnumerationOptions)o usingBlock:(void (^)(NSString *, NSRange, NSRange, BOOL *))block {
    NSUInteger kind = o & 0xff, end = NSMaxRange(r), i = r.location; BOOL stop = NO, want = !(o & NSStringEnumerationSubstringNotRequired);
    NSMutableArray *found = [NSMutableArray array]; /* pairs of ranges, so reverse order is easy */
    while (i < end) {
        NSRange sub, encl;
        if (kind == NSStringEnumerationByLines || kind == NSStringEnumerationByParagraphs) {
            NSUInteger a, e, c; line_bounds(self, NSMakeRange(i, 0), &a, &e, &c, kind == NSStringEnumerationByParagraphs);
            a = MAX(a, r.location); sub = NSMakeRange(a, MIN(c, end) - a); encl = NSMakeRange(a, MIN(e, end) - a); i = MAX(e, i + 1);
        } else if (kind == NSStringEnumerationByComposedCharacterSequences) {
            sub = encl = [self rangeOfComposedCharacterSequenceAtIndex:i]; i = NSMaxRange(sub);
        } else { /* words and sentences: runs of letters/digits (words) or text up to . ! ? (sentences) */
            NSCharacterSet *w = [NSCharacterSet alphanumericCharacterSet]; NSUInteger a = i;
            if (kind == NSStringEnumerationByWords) {
                while (i < end && ![w characterIsMember:[self characterAtIndex:i]]) i++;
                NSUInteger s = i; while (i < end && ([w characterIsMember:[self characterAtIndex:i]] || [self characterAtIndex:i] == '\'')) i++;
                if (s == i) break;
                sub = NSMakeRange(s, i - s); NSUInteger t = i; while (t < end && ![w characterIsMember:[self characterAtIndex:t]]) t++;
                encl = NSMakeRange(a, t - a);
            } else {
                while (i < end && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[self characterAtIndex:i]]) i++;
                NSUInteger s = i; while (i < end && !strchr(".!?", [self characterAtIndex:i] < 128 ? (int)[self characterAtIndex:i] : 1)) i++;
                if (i < end) i++;
                if (s == i) break;
                sub = NSMakeRange(s, i - s); NSUInteger t = i; while (t < end && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[self characterAtIndex:t]]) t++;
                encl = NSMakeRange(a, t - a);
            }
        }
        [found addObject:[NSValue valueWithRange:sub]]; [found addObject:[NSValue valueWithRange:encl]];
    }
    NSUInteger m = [found count] / 2;
    for (NSUInteger j = 0; j < m && !stop; j++) {
        NSUInteger k = (o & NSStringEnumerationReverse) ? m - 1 - j : j;
        NSRange sub = [found[2 * k] rangeValue], encl = [found[2 * k + 1] rangeValue];
        block(want ? [self substringWithRange:sub] : nil, sub, encl, &stop);
    }
}
- (BOOL)getBytes:(void *)buf maxLength:(NSUInteger)max usedLength:(NSUInteger *)used encoding:(NSStringEncoding)enc options:(NSStringEncodingConversionOptions)opt
           range:(NSRange)r remainingRange:(NSRangePointer)rest {
    NSUInteger i = r.location, end = NSMaxRange(r), k = 0; unsigned char *out = buf;
    while (i < end) {
        uint32_t c = [self characterAtIndex:i]; NSUInteger w = 1;
        if (c >= 0xd800 && c < 0xdc00 && i + 1 < end) { unichar lo = [self characterAtIndex:i + 1]; if (lo >= 0xdc00 && lo < 0xe000) { c = 0x10000 + ((c - 0xd800) << 10) + (lo - 0xdc00); w = 2; } }
        unsigned char b[4]; NSUInteger nb = 0;
        if (enc == NSUTF8StringEncoding) {
            if (c < 0x80) b[nb++] = (unsigned char)c;
            else if (c < 0x800) { b[nb++] = (unsigned char)(0xc0 | c >> 6); b[nb++] = (unsigned char)(0x80 | (c & 63)); }
            else if (c < 0x10000) { b[nb++] = (unsigned char)(0xe0 | c >> 12); b[nb++] = (unsigned char)(0x80 | (c >> 6 & 63)); b[nb++] = (unsigned char)(0x80 | (c & 63)); }
            else { b[nb++] = (unsigned char)(0xf0 | c >> 18); b[nb++] = (unsigned char)(0x80 | (c >> 12 & 63)); b[nb++] = (unsigned char)(0x80 | (c >> 6 & 63)); b[nb++] = (unsigned char)(0x80 | (c & 63)); }
        } else if (enc == NSUTF16StringEncoding || enc == NSUTF16LittleEndianStringEncoding || enc == 0x90000100) {
            BOOL be = enc == 0x90000100;
            for (NSUInteger j = 0; j < w; j++) { unichar ch = [self characterAtIndex:i + j]; b[nb++] = (unsigned char)(be ? ch >> 8 : ch); b[nb++] = (unsigned char)(be ? ch : ch >> 8); }
        } else {
            uint32_t lim = enc == NSASCIIStringEncoding ? 0x80 : 0x100;
            if (c < lim) b[nb++] = (unsigned char)c; else if (opt & NSStringEncodingConversionAllowLossy) b[nb++] = '?'; else break;
        }
        if (buf && k + nb > max) break;
        if (buf) memcpy(out + k, b, nb);
        k += nb; i += w;
    }
    if (used) *used = k;
    if (rest) *rest = NSMakeRange(i, end - i);
    return i > r.location || r.length == 0;
}
- (id)propertyList { return [NSPropertyListSerialization propertyListWithData:[self dataUsingEncoding:NSUTF8StringEncoding] options:0 format:0 error:0]; }
- (NSDictionary *)propertyListFromStringsFileFormat { id p = [self propertyList]; return [p isKindOfClass:[NSDictionary class]] ? p : nil; }
- (NSUInteger)completePathIntoString:(NSString **)out caseSensitive:(BOOL)cs matchesIntoArray:(NSArray **)m filterTypes:(NSArray *)t { return 0; }
- (NSArray *)linguisticTagsInRange:(NSRange)r scheme:(NSString *)s options:(NSLinguisticTaggerOptions)o orthography:(NSOrthography *)orth tokenRanges:(NSArray **)tr {
    if (tr) *tr = @[]; return @[]; /* ponytail: no linguistic tagging */
}
- (void)enumerateLinguisticTagsInRange:(NSRange)r scheme:(NSString *)s options:(NSLinguisticTaggerOptions)o orthography:(NSOrthography *)orth
                            usingBlock:(void (^)(NSString *, NSRange, NSRange, BOOL *))b {}
- (NSString *)stringByAddingPercentEncodingWithAllowedCharacters:(NSCharacterSet *)a { return pct_encode(self, a); }
- (NSString *)stringByRemovingPercentEncoding { return pct_decode(self); }
- (NSString *)stringByAddingPercentEscapesUsingEncoding:(NSStringEncoding)e { return pct_encode(self, url_set(@"!$&'()*+,-./:;=?@_~#")); }
- (NSString *)stringByReplacingPercentEscapesUsingEncoding:(NSStringEncoding)e { return pct_decode(self); }
@end

/* ======================================================================= NSData additions */
static const char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static NSData *b64_encode(NSData *d, NSDataBase64EncodingOptions o) {
    const unsigned char *p = [d bytes]; NSUInteger n = [d length], line = (o & NSDataBase64Encoding64CharacterLineLength) ? 64 : (o & NSDataBase64Encoding76CharacterLineLength) ? 76 : 0;
    const char *eol = (o & NSDataBase64EncodingEndLineWithCarriageReturn) && !(o & NSDataBase64EncodingEndLineWithLineFeed) ? "\r"
                    : !(o & NSDataBase64EncodingEndLineWithCarriageReturn) && (o & NSDataBase64EncodingEndLineWithLineFeed) ? "\n" : "\r\n";
    NSMutableData *out = [NSMutableData dataWithCapacity:n * 4 / 3 + 4]; NSUInteger col = 0;
    for (NSUInteger i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)p[i] << 16 | (i + 1 < n ? (uint32_t)p[i + 1] << 8 : 0) | (i + 2 < n ? p[i + 2] : 0);
        char q[4] = {b64[v >> 18], b64[v >> 12 & 63], i + 1 < n ? b64[v >> 6 & 63] : '=', i + 2 < n ? b64[v & 63] : '='};
        if (line && col == line) { [out appendBytes:eol length:strlen(eol)]; col = 0; }
        [out appendBytes:q length:4]; col += 4;
    }
    return out;
}
static NSData *b64_decode(const unsigned char *p, NSUInteger n, BOOL ignore) {
    NSMutableData *out = [NSMutableData dataWithCapacity:n * 3 / 4]; uint32_t acc = 0; int bits = 0, pad = 0;
    for (NSUInteger i = 0; i < n; i++) {
        unsigned char c = p[i]; int v = c >= 'A' && c <= 'Z' ? c - 'A' : c >= 'a' && c <= 'z' ? c - 'a' + 26 : c >= '0' && c <= '9' ? c - '0' + 52 : c == '+' ? 62 : c == '/' ? 63 : -1;
        if (c == '=') { pad++; continue; }
        if (v < 0 || pad) { if (ignore && v < 0) continue; return nil; }
        acc = acc << 6 | (uint32_t)v; bits += 6;
        if (bits >= 8) { bits -= 8; unsigned char b = (unsigned char)(acc >> bits); [out appendBytes:&b length:1]; }
    }
    if (pad > 2 || bits >= 6) return nil;
    return out;
}
@implementation NSData (MWSwiftOverlay)
- (NSString *)base64EncodedStringWithOptions:(NSDataBase64EncodingOptions)o { return [[[NSString alloc] initWithData:b64_encode(self, o) encoding:NSASCIIStringEncoding] autorelease]; }
- (NSData *)base64EncodedDataWithOptions:(NSDataBase64EncodingOptions)o { return b64_encode(self, o); }
- (instancetype)initWithBase64EncodedString:(NSString *)s options:(NSDataBase64DecodingOptions)o {
    NSData *a = [s dataUsingEncoding:NSUTF8StringEncoding]; NSData *d = a ? b64_decode([a bytes], [a length], o & NSDataBase64DecodingIgnoreUnknownCharacters) : nil;
    if (!d) { [self release]; return nil; }
    return [self initWithData:d];
}
- (instancetype)initWithBase64EncodedData:(NSData *)a options:(NSDataBase64DecodingOptions)o {
    NSData *d = b64_decode([a bytes], [a length], o & NSDataBase64DecodingIgnoreUnknownCharacters);
    if (!d) { [self release]; return nil; }
    return [self initWithData:d];
}
- (instancetype)initWithBytesNoCopy:(void *)b length:(NSUInteger)n { return [self initWithBytesNoCopy:b length:n freeWhenDone:YES]; }
/* copies, then hands the bytes back to their owner right away */
- (instancetype)initWithBytesNoCopy:(void *)b length:(NSUInteger)n deallocator:(void (^)(void *, NSUInteger))dealloc {
    self = [self initWithBytes:b length:n]; if (dealloc) dealloc(b, n); return self;
}
- (instancetype)initWithContentsOfFile:(NSString *)p options:(NSDataReadingOptions)o error:(NSError **)e {
    NSData *d = [NSData dataWithContentsOfFile:p options:o error:e]; if (!d) { [self release]; return nil; } return [self initWithData:d];
}
- (instancetype)initWithContentsOfURL:(NSURL *)u options:(NSDataReadingOptions)o error:(NSError **)e {
    if (![u isFileURL]) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:262 userInfo:nil]; [self release]; return nil; }
    return [self initWithContentsOfFile:[u path] options:o error:e];
}
- (instancetype)initWithContentsOfURL:(NSURL *)u { return [self initWithContentsOfURL:u options:0 error:0]; }
+ (instancetype)dataWithContentsOfURL:(NSURL *)u options:(NSDataReadingOptions)o error:(NSError **)e { return [[[self alloc] initWithContentsOfURL:u options:o error:e] autorelease]; }
- (BOOL)writeToURL:(NSURL *)u options:(NSDataWritingOptions)o error:(NSError **)e {
    if (![u isFileURL]) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:518 userInfo:nil]; return NO; }
    return [self writeToFile:[u path] options:o error:e];
}
- (BOOL)writeToURL:(NSURL *)u atomically:(BOOL)a { return [self writeToURL:u options:0 error:0]; }
@end

/* ======================================================================= the rest of the overlay's needs */
@implementation NSIndexPath { NSUInteger *_ix, _len; }
- (instancetype)initWithIndexes:(const NSUInteger [])ix length:(NSUInteger)n { _ix = malloc((n ? n : 1) * sizeof *_ix); memcpy(_ix, ix, n * sizeof *_ix); _len = n; return self; }
- (instancetype)initWithIndex:(NSUInteger)i { return [self initWithIndexes:&i length:1]; }
- (instancetype)init { return [self initWithIndexes:0 length:0]; }
+ (instancetype)indexPathWithIndex:(NSUInteger)i { return [[[self alloc] initWithIndex:i] autorelease]; }
+ (instancetype)indexPathWithIndexes:(const NSUInteger [])ix length:(NSUInteger)n { return [[[self alloc] initWithIndexes:ix length:n] autorelease]; }
- (void)dealloc { free(_ix); [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSUInteger)length { return _len; }
- (NSUInteger)indexAtPosition:(NSUInteger)p { return p < _len ? _ix[p] : NSNotFound; }
- (void)getIndexes:(NSUInteger *)out range:(NSRange)r { memcpy(out, _ix + r.location, r.length * sizeof *_ix); }
- (void)getIndexes:(NSUInteger *)out { memcpy(out, _ix, _len * sizeof *_ix); }
- (NSIndexPath *)indexPathByAddingIndex:(NSUInteger)i {
    NSUInteger *t = malloc((_len + 1) * sizeof *t); memcpy(t, _ix, _len * sizeof *t); t[_len] = i;
    NSIndexPath *p = [NSIndexPath indexPathWithIndexes:t length:_len + 1]; free(t); return p;
}
- (NSIndexPath *)indexPathByRemovingLastIndex { return [NSIndexPath indexPathWithIndexes:_ix length:_len ? _len - 1 : 0]; }
- (NSComparisonResult)compare:(NSIndexPath *)o {
    NSUInteger n = MIN(_len, [o length]);
    for (NSUInteger i = 0; i < n; i++) { NSUInteger b = [o indexAtPosition:i]; if (_ix[i] != b) return _ix[i] < b ? NSOrderedAscending : NSOrderedDescending; }
    return _len < [o length] ? NSOrderedAscending : _len > [o length] ? NSOrderedDescending : NSOrderedSame;
}
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSIndexPath class]] && [self compare:o] == NSOrderedSame; }
- (NSUInteger)hash { NSUInteger h = _len; for (NSUInteger i = 0; i < _len; i++) h = h * 31 + _ix[i]; return h; }
@end
@implementation NSArray (MWDescriptionWithLocale)
- (NSString *)descriptionWithLocale:(id)l { return [self description]; }
- (NSString *)descriptionWithLocale:(id)l indent:(NSUInteger)i { return [self description]; }
@end
@implementation NSDictionary (MWDescriptionWithLocale)
- (NSString *)descriptionWithLocale:(id)l { return [self description]; }
- (NSString *)descriptionWithLocale:(id)l indent:(NSUInteger)i { return [self description]; }
- (void)getObjects:(id *)objs andKeys:(id *)keys count:(NSUInteger)n {
    NSUInteger i = 0;
    for (id k in self) { if (i >= n) break; if (keys) keys[i] = k; if (objs) objs[i] = [self objectForKey:k]; i++; }
}
@end
@implementation NSSet (MWDescriptionWithLocale)
- (NSString *)descriptionWithLocale:(id)l { return [self description]; }
- (instancetype)initWithObjects:(const id *)objs count:(NSUInteger)n { return [self initWithArray:[NSArray arrayWithObjects:objs count:n]]; }
@end
@implementation NSNumber (MWSwiftOverlay)
- (NSString *)descriptionWithLocale:(id)l { return [self description]; }
- (instancetype)initWithChar:(char)v { [self release]; return [[NSNumber numberWithChar:v] retain]; }
- (instancetype)initWithUnsignedChar:(unsigned char)v { [self release]; return [[NSNumber numberWithUnsignedChar:v] retain]; }
- (instancetype)initWithShort:(short)v { [self release]; return [[NSNumber numberWithShort:v] retain]; }
- (instancetype)initWithUnsignedShort:(unsigned short)v { [self release]; return [[NSNumber numberWithUnsignedShort:v] retain]; }
- (instancetype)initWithUnsignedInt:(unsigned)v { [self release]; return [[NSNumber numberWithUnsignedInt:v] retain]; }
- (instancetype)initWithLong:(long)v { [self release]; return [[NSNumber numberWithLong:v] retain]; }
- (instancetype)initWithUnsignedLong:(unsigned long)v { [self release]; return [[NSNumber numberWithUnsignedLong:v] retain]; }
- (instancetype)initWithUnsignedInteger:(NSUInteger)v { [self release]; return [[NSNumber numberWithUnsignedInteger:v] retain]; }
@end
static NSMutableDictionary *value_providers;
@implementation NSError (MWValueProviders)
+ (void)setUserInfoValueProviderForDomain:(NSErrorDomain)d provider:(id (^)(NSError *, NSErrorUserInfoKey))p {
    @synchronized(self) {
        if (!value_providers) value_providers = [[NSMutableDictionary alloc] init];
        if (p) { id c = [p copy]; value_providers[d] = c; [c release]; } else [value_providers removeObjectForKey:d];
    }
}
+ (id (^)(NSError *, NSErrorUserInfoKey))userInfoValueProviderForDomain:(NSErrorDomain)d { @synchronized(self) { return value_providers[d]; } }
@end
@implementation NSObject (NSErrorRecoveryAttempting)
- (BOOL)attemptRecoveryFromError:(NSError *)e optionIndex:(NSUInteger)i { return NO; }
- (void)attemptRecoveryFromError:(NSError *)e optionIndex:(NSUInteger)i delegate:(id)d didRecoverSelector:(SEL)s contextInfo:(void *)c {}
@end
@implementation NSScanner (MWSwiftOverlay)
- (id)locale { return nil; } - (void)setLocale:(id)l {}
- (BOOL)scanDecimal:(NSDecimal *)d { double v; if (![self scanDouble:&v]) return NO; if (d) *d = dec_from_double(v); return YES; }
@end

/* ======================================================================= CF type IDs and string hashes (Apple's values; the Swift runtime
 * finds these with dlsym to tell NSStrings apart and to hash bridged strings like NSString does) */
CFTypeID CFStringGetTypeID(void) { return 7; }
CFTypeID CFArrayGetTypeID(void) { return 19; }
CFTypeID CFDictionaryGetTypeID(void) { return 18; }
CFTypeID CFSetGetTypeID(void) { return 17; }
CFTypeID CFDataGetTypeID(void) { return 20; }
CFTypeID CFNumberGetTypeID(void) { return 22; }
CFTypeID CFBooleanGetTypeID(void) { return 21; }
CFTypeID CFDateGetTypeID(void) { return 42; }
CFTypeID CFURLGetTypeID(void) { return 29; }
CFTypeID CFErrorGetTypeID(void) { return 43; }
CFTypeID CFCharacterSetGetTypeID(void) { return 25; }
CFTypeID CFGetTypeID(CFTypeRef o) {
    id x = (id)o;
    if ([x isKindOfClass:[NSString class]]) return 7;
    if ([x isKindOfClass:[NSArray class]]) return 19;
    if ([x isKindOfClass:[NSDictionary class]]) return 18;
    if ([x isKindOfClass:[NSSet class]]) return 17;
    if ([x isKindOfClass:[NSData class]]) return 20;
    if ([x isKindOfClass:[NSNumber class]]) return o == kCFBooleanTrue || o == kCFBooleanFalse ? 21 : 22;
    if ([x isKindOfClass:[NSDate class]]) return 42;
    if ([x isKindOfClass:[NSURL class]]) return 29;
    if ([x isKindOfClass:[NSError class]]) return 43;
    if ([x isKindOfClass:[NSCharacterSet class]]) return 25;
    return 1;
}
/* both must agree with -[NSString hash] (FNV-1a over UTF-16 units) */
CFHashCode CFStringHashNSString(id s) { /* not [s hash]: Swift's own NSStrings implement hash with this function */
    NSUInteger n; unichar *u = mw_chars(s, &n); uint64_t h = 1469598103934665603ull;
    for (NSUInteger i = 0; i < n; i++) h = (h ^ u[i]) * 1099511628211ull;
    free(u); return (CFHashCode)h;
}
CFHashCode CFStringHashCString(const uint8_t *b, CFIndex n) {
    uint64_t h = 1469598103934665603ull; for (CFIndex i = 0; i < n; i++) h = (h ^ b[i]) * 1099511628211ull; return (CFHashCode)h;
}

/* ======================================================================= file system odds and ends */
NSString *const NSFileCreationDate = @"NSFileCreationDate", *const NSFilePosixPermissions = @"NSFilePosixPermissions",
    *const NSFileReferenceCount = @"NSFileReferenceCount", *const NSFileOwnerAccountName = @"NSFileOwnerAccountName",
    *const NSFileGroupOwnerAccountName = @"NSFileGroupOwnerAccountName", *const NSFileSystemNumber = @"NSFileSystemNumber",
    *const NSFileSystemFileNumber = @"NSFileSystemFileNumber", *const NSFileExtensionHidden = @"NSFileExtensionHidden",
    *const NSFileImmutable = @"NSFileImmutable", *const NSFileAppendOnly = @"NSFileAppendOnly",
    *const NSFileTypeSymbolicLink = @"NSFileTypeSymbolicLink", *const NSFileTypeUnknown = @"NSFileTypeUnknown";
static NSString *search_dir(NSSearchPathDirectory d) {
    switch (d) {
    case NSApplicationDirectory: case NSAllApplicationsDirectory: return @"Applications";
    case NSDemoApplicationDirectory: return @"Applications/Demos"; case NSDeveloperApplicationDirectory: return @"Developer/Applications";
    case NSAdminApplicationDirectory: return @"Applications/Utilities"; case NSLibraryDirectory: case NSAllLibrariesDirectory: return @"Library";
    case NSDeveloperDirectory: return @"Developer"; case NSDocumentationDirectory: return @"Library/Documentation"; case NSDocumentDirectory: return @"Documents";
    case NSCoreServiceDirectory: return @"Library/CoreServices"; case NSAutosavedInformationDirectory: return @"Library/Autosave Information";
    case NSDesktopDirectory: return @"Desktop"; case NSCachesDirectory: return @"Library/Caches"; case NSApplicationSupportDirectory: return @"Library/Application Support";
    case NSDownloadsDirectory: return @"Downloads"; case NSInputMethodsDirectory: return @"Library/Input Methods"; case NSMoviesDirectory: return @"Movies";
    case NSMusicDirectory: return @"Music"; case NSPicturesDirectory: return @"Pictures"; case NSPrinterDescriptionDirectory: return @"Library/Printers/PPDs";
    case NSSharedPublicDirectory: return @"Public"; case NSPreferencePanesDirectory: return @"Library/PreferencePanes";
    case NSApplicationScriptsDirectory: return @"Library/Application Scripts"; case NSTrashDirectory: return @".Trash";
    default: return nil;
    }
}
NSArray *NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory d, NSSearchPathDomainMask m, BOOL expand) {
    NSString *rel = search_dir(d); NSMutableArray *a = [NSMutableArray array];
    if (!rel) return a;
    if (m & NSUserDomainMask) [a addObject:[(expand ? NSHomeDirectory() : @"~") stringByAppendingPathComponent:rel]];
    if ((m & NSLocalDomainMask) && d != NSDesktopDirectory && d != NSDocumentDirectory && d != NSDownloadsDirectory && d != NSTrashDirectory) [a addObject:[@"/" stringByAppendingString:rel]];
    if ((m & NSSystemDomainMask) && [rel hasPrefix:@"Library"]) [a addObject:[@"/System/" stringByAppendingString:rel]];
    /* Windows and Linux have no Applications folder: wherever the user keeps a Mac app is its Applications folder (apps
       that refuse to run elsewhere check for it). ponytail: the folder of the running app, not a list of installed ones */
    if ((d == NSApplicationDirectory || d == NSAllApplicationsDirectory) && (m & NSLocalDomainMask)) {
        NSString *here = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
        if ([[[NSBundle mainBundle] bundlePath] hasSuffix:@".app"] && here.length) [a addObject:here];
    }
    return a;
}
@implementation NSPipe { NSFileHandle *_r, *_w; }
+ (NSPipe *)pipe { return [[[self alloc] init] autorelease]; }
- (instancetype)init {
    int fd[2]; if (pipe(fd)) { [self release]; return nil; }
    _r = [[NSFileHandle alloc] initWithFileDescriptor:fd[0] closeOnDealloc:YES]; _w = [[NSFileHandle alloc] initWithFileDescriptor:fd[1] closeOnDealloc:YES];
    return self;
}
- (void)dealloc { [_r release]; [_w release]; [super dealloc]; }
- (NSFileHandle *)fileHandleForReading { return _r; }
- (NSFileHandle *)fileHandleForWriting { return _w; }
@end
@implementation NSFileManager (NSURLAPI)
- (NSArray *)contentsOfDirectoryAtURL:(NSURL *)u includingPropertiesForKeys:(NSArray *)k options:(NSDirectoryEnumerationOptions)o error:(NSError **)e {
    NSArray *names = [self contentsOfDirectoryAtPath:[u path] error:e];
    if (!names) return nil;
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *n in names) {
        if ((o & NSDirectoryEnumerationSkipsHiddenFiles) && [n hasPrefix:@"."]) continue;
        [a addObject:[u URLByAppendingPathComponent:n]];
    }
    return a;
}
- (BOOL)createDirectoryAtURL:(NSURL *)u withIntermediateDirectories:(BOOL)i attributes:(NSDictionary *)a error:(NSError **)e { return [self createDirectoryAtPath:[u path] withIntermediateDirectories:i attributes:a error:e]; }
- (BOOL)removeItemAtURL:(NSURL *)u error:(NSError **)e { return [self removeItemAtPath:[u path] error:e]; }
- (BOOL)moveItemAtURL:(NSURL *)a toURL:(NSURL *)b error:(NSError **)e { return [self moveItemAtPath:[a path] toPath:[b path] error:e]; }
- (BOOL)copyItemAtURL:(NSURL *)a toURL:(NSURL *)b error:(NSError **)e { return [self copyItemAtPath:[a path] toPath:[b path] error:e]; }
- (BOOL)setAttributes:(NSDictionary *)a ofItemAtPath:(NSString *)p error:(NSError **)e { return YES; } /* ponytail: attributes are not written */
- (NSURL *)temporaryDirectory { return [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]; }
- (NSArray *)URLsForDirectory:(NSSearchPathDirectory)d inDomains:(NSSearchPathDomainMask)m {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *p in NSSearchPathForDirectoriesInDomains(d, m, YES)) [a addObject:[NSURL fileURLWithPath:p isDirectory:YES]];
    return a;
}
- (NSURL *)URLForDirectory:(NSSearchPathDirectory)d inDomain:(NSSearchPathDomainMask)m appropriateForURL:(NSURL *)u create:(BOOL)c error:(NSError **)e {
    if (d == NSItemReplacementDirectory) {
        NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        return [self createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:e] ? [NSURL fileURLWithPath:p isDirectory:YES] : nil;
    }
    NSURL *r = [[self URLsForDirectory:d inDomains:m] firstObject];
    if (!r) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:4 userInfo:nil]; return nil; }
    if (c && ![self createDirectoryAtPath:[r path] withIntermediateDirectories:YES attributes:nil error:e]) return nil;
    return r;
}
@end
