/* swift.m — the Foundation API that Swift's Foundation overlay (libswiftFoundation, src/build_swift_overlays.sh) is built
 * on: calendars and date components, locales, time zones, date formatters, index sets, decimal numbers, URL components,
 * and the CoreFoundation functions the overlay calls (character sets, sets, errors, booleans, strings).
 * Written from Apple's public documentation. ponytail: the Gregorian calendar only; time zones are fixed offsets (no
 * daylight saving rules); locales know their identifier and the en_US conventions; decimals are computed as doubles. */
#include "internal.h"
int pipe(int[2]);

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

/* ======================================================================= time zones (fixed offsets) */
struct tm_ { int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst; long tm_gmtoff; char *tm_zone; };
struct tm_ *localtime_r(const long *, struct tm_ *); long time(long *);
static const struct { const char *name, *abbr; int offset; } known_zones[] = {
    {"GMT", "GMT", 0}, {"UTC", "UTC", 0}, {"Europe/London", "GMT", 0}, {"Europe/Lisbon", "WET", 0}, {"Europe/Madrid", "CET", 3600},
    {"Europe/Paris", "CET", 3600}, {"Europe/Berlin", "CET", 3600}, {"Europe/Rome", "CET", 3600}, {"Europe/Amsterdam", "CET", 3600},
    {"Europe/Brussels", "CET", 3600}, {"Europe/Vienna", "CET", 3600}, {"Europe/Zurich", "CET", 3600}, {"Europe/Stockholm", "CET", 3600},
    {"Europe/Warsaw", "CET", 3600}, {"Europe/Athens", "EET", 7200}, {"Europe/Helsinki", "EET", 7200}, {"Europe/Kiev", "EET", 7200},
    {"Europe/Istanbul", "TRT", 10800}, {"Europe/Moscow", "MSK", 10800}, {"Atlantic/Canary", "WET", 0}, {"Africa/Cairo", "EET", 7200},
    {"Africa/Johannesburg", "SAST", 7200}, {"Africa/Lagos", "WAT", 3600}, {"Asia/Dubai", "GST", 14400}, {"Asia/Karachi", "PKT", 18000},
    {"Asia/Kolkata", "IST", 19800}, {"Asia/Dhaka", "BST", 21600}, {"Asia/Bangkok", "ICT", 25200}, {"Asia/Shanghai", "CST", 28800},
    {"Asia/Hong_Kong", "HKT", 28800}, {"Asia/Singapore", "SGT", 28800}, {"Asia/Tokyo", "JST", 32400}, {"Asia/Seoul", "KST", 32400},
    {"Australia/Sydney", "AEST", 36000}, {"Pacific/Auckland", "NZST", 43200}, {"America/Sao_Paulo", "BRT", -10800},
    {"America/Argentina/Buenos_Aires", "ART", -10800}, {"America/Halifax", "AST", -14400}, {"America/New_York", "EST", -18000},
    {"America/Toronto", "EST", -18000}, {"America/Chicago", "CST", -21600}, {"America/Mexico_City", "CST", -21600},
    {"America/Denver", "MST", -25200}, {"America/Phoenix", "MST", -25200}, {"America/Los_Angeles", "PST", -28800},
    {"America/Anchorage", "AKST", -32400}, {"Pacific/Honolulu", "HST", -36000},
};
#define NZONES (sizeof known_zones / sizeof *known_zones)
@implementation NSTimeZone { NSString *_name, *_abbr; NSInteger _off; }
- (instancetype)initWithName:(NSString *)n offset:(NSInteger)off abbreviation:(NSString *)a {
    _name = [n copy]; _off = off; _abbr = [a copy]; return self;
}
- (void)dealloc { [_name release]; [_abbr release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
static NSString *gmt_name(NSInteger off) {
    if (!off) return @"GMT";
    NSInteger a = off < 0 ? -off : off;
    return [NSString stringWithFormat:@"GMT%c%02ld%02ld", off < 0 ? '-' : '+', (long)(a / 3600), (long)(a / 60 % 60)];
}
+ (instancetype)timeZoneForSecondsFromGMT:(NSInteger)s {
    if (s < -18 * 3600 || s > 18 * 3600) return nil;
    return [[[self alloc] initWithName:gmt_name(s) offset:s abbreviation:gmt_name(s)] autorelease];
}
static NSInteger parse_gmt(const char *s, BOOL *ok) { /* GMT+2, GMT-0530, UTC+01:00 */
    *ok = NO; int sign = 1;
    if (!strncmp(s, "GMT", 3) || !strncmp(s, "UTC", 3)) s += 3; else return 0;
    if (!*s) { *ok = YES; return 0; }
    if (*s == '+') s++; else if (*s == '-') { sign = -1; s++; } else return 0;
    int h = 0, m = 0, digits = 0;
    while (isdigit(*s) && digits < 2) { h = h * 10 + (*s++ - '0'); digits++; }
    if (*s == ':') s++;
    if (isdigit(*s)) { m = (s[0] - '0') * 10 + (isdigit(s[1]) ? s[1] - '0' : 0); s += isdigit(s[1]) ? 2 : 1; }
    if (*s || h > 18) return 0;
    *ok = YES; return sign * (h * 3600 + m * 60);
}
- (instancetype)initWithName:(NSString *)n {
    const char *c = [n UTF8String];
    for (unsigned i = 0; i < NZONES; i++) if (!strcmp(c, known_zones[i].name))
        return [self initWithName:n offset:known_zones[i].offset abbreviation:[NSString stringWithUTF8String:known_zones[i].abbr]];
    BOOL ok; NSInteger off = parse_gmt(c, &ok);
    if (ok) return [self initWithName:gmt_name(off) offset:off abbreviation:gmt_name(off)];
    [self release]; return nil;
}
- (instancetype)initWithName:(NSString *)n data:(NSData *)d { return [self initWithName:n]; }
+ (instancetype)timeZoneWithName:(NSString *)n { return [[[self alloc] initWithName:n] autorelease]; }
+ (instancetype)timeZoneWithName:(NSString *)n data:(NSData *)d { return [self timeZoneWithName:n]; }
+ (instancetype)timeZoneWithAbbreviation:(NSString *)a {
    NSString *name = [[self abbreviationDictionary] objectForKey:a];
    if (name) return [self timeZoneWithName:name];
    BOOL ok; NSInteger off = parse_gmt([a UTF8String], &ok);
    return ok ? [self timeZoneForSecondsFromGMT:off] : nil;
}
static NSTimeZone *system_tz, *default_tz;
+ (NSTimeZone *)systemTimeZone {
    @synchronized(self) {
        if (!system_tz) {
            const char *tz = getenv("TZ");
            if (tz && *tz) system_tz = [[NSTimeZone alloc] initWithName:[NSString stringWithUTF8String:tz]];
            if (!system_tz) {
                long now = time(0); struct tm_ t; memset(&t, 0, sizeof t); localtime_r(&now, &t);
                for (unsigned i = 0; i < NZONES && !system_tz; i++) if (known_zones[i].offset == t.tm_gmtoff - (t.tm_isdst > 0 ? 3600 : 0) && i > 1)
                    system_tz = [[NSTimeZone alloc] initWithName:[NSString stringWithUTF8String:known_zones[i].name] offset:t.tm_gmtoff
                                                     abbreviation:t.tm_zone ? [NSString stringWithUTF8String:t.tm_zone] : gmt_name(t.tm_gmtoff)];
                if (!system_tz) system_tz = [[NSTimeZone alloc] initWithName:gmt_name(t.tm_gmtoff) offset:t.tm_gmtoff abbreviation:gmt_name(t.tm_gmtoff)];
            }
        }
        return system_tz;
    }
}
+ (NSTimeZone *)localTimeZone { return [self defaultTimeZone]; }
+ (NSTimeZone *)defaultTimeZone { return default_tz ? default_tz : [self systemTimeZone]; }
+ (void)setDefaultTimeZone:(NSTimeZone *)tz { [default_tz release]; default_tz = [tz retain]; }
+ (void)resetSystemTimeZone { @synchronized(self) { [system_tz release]; system_tz = nil; } }
+ (NSArray<NSString *> *)knownTimeZoneNames {
    NSMutableArray *a = [NSMutableArray array];
    for (unsigned i = 2; i < NZONES; i++) [a addObject:[NSString stringWithUTF8String:known_zones[i].name]];
    return a;
}
static NSDictionary *abbr_dict;
+ (NSDictionary<NSString *, NSString *> *)abbreviationDictionary {
    @synchronized(self) {
        if (!abbr_dict) abbr_dict = [@{@"GMT": @"GMT", @"UTC": @"UTC", @"BST": @"Europe/London", @"WET": @"Europe/Lisbon", @"CET": @"Europe/Paris",
            @"CEST": @"Europe/Paris", @"EET": @"Europe/Athens", @"MSK": @"Europe/Moscow", @"IST": @"Asia/Kolkata", @"PKT": @"Asia/Karachi",
            @"ICT": @"Asia/Bangkok", @"HKT": @"Asia/Hong_Kong", @"SGT": @"Asia/Singapore", @"JST": @"Asia/Tokyo", @"KST": @"Asia/Seoul",
            @"NZST": @"Pacific/Auckland", @"BRT": @"America/Sao_Paulo", @"ART": @"America/Argentina/Buenos_Aires", @"AST": @"America/Halifax",
            @"EST": @"America/New_York", @"EDT": @"America/New_York", @"CST": @"America/Chicago", @"CDT": @"America/Chicago",
            @"MST": @"America/Denver", @"MDT": @"America/Denver", @"PST": @"America/Los_Angeles", @"PDT": @"America/Los_Angeles",
            @"AKST": @"America/Anchorage", @"HST": @"Pacific/Honolulu", @"WAT": @"Africa/Lagos", @"SAST": @"Africa/Johannesburg"} retain];
        return abbr_dict;
    }
}
+ (void)setAbbreviationDictionary:(NSDictionary *)d { @synchronized(self) { [abbr_dict release]; abbr_dict = [d copy]; } }
+ (NSString *)timeZoneDataVersion { return @"2024a"; }
- (NSString *)name { return _name; }
- (NSData *)data { return [NSData data]; }
- (NSInteger)secondsFromGMTForDate:(NSDate *)d { return _off; }
- (NSInteger)secondsFromGMT { return _off; }
- (NSString *)abbreviationForDate:(NSDate *)d { return _abbr; }
- (NSString *)abbreviation { return _abbr; }
- (BOOL)isDaylightSavingTimeForDate:(NSDate *)d { return NO; }
- (BOOL)isDaylightSavingTime { return NO; }
- (NSTimeInterval)daylightSavingTimeOffsetForDate:(NSDate *)d { return 0; }
- (NSTimeInterval)daylightSavingTimeOffset { return 0; }
- (NSDate *)nextDaylightSavingTimeTransitionAfterDate:(NSDate *)d { return nil; }
- (NSDate *)nextDaylightSavingTimeTransition { return nil; }
- (BOOL)isEqualToTimeZone:(NSTimeZone *)o { return [_name isEqualToString:[o name]] && _off == [o secondsFromGMT]; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSTimeZone class]] && [self isEqualToTimeZone:o]); }
- (NSUInteger)hash { return [_name hash]; }
- (NSString *)localizedName:(NSTimeZoneNameStyle)style locale:(NSLocale *)l { return style == NSTimeZoneNameStyleShortStandard ? _abbr : _name; }
- (NSString *)description { return [NSString stringWithFormat:@"%@ (%@) offset %ld", _name, _abbr, (long)_off]; }
@end

/* ======================================================================= locales */
@implementation NSLocale { NSString *_id; }
- (instancetype)initWithLocaleIdentifier:(NSString *)s { _id = [s copy]; return self; }
- (void)dealloc { [_id release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
+ (instancetype)localeWithLocaleIdentifier:(NSString *)s { return [[[self alloc] initWithLocaleIdentifier:s] autorelease]; }
static NSLocale *current_locale;
+ (NSLocale *)currentLocale {
    @synchronized(self) {
        if (!current_locale) {
            const char *l = getenv("LC_ALL"); if (!l || !*l) l = getenv("LANG");
            char buf[32] = "en_US";
            if (l && *l && strcmp(l, "C") && strcmp(l, "POSIX")) { size_t i = 0; while (l[i] && l[i] != '.' && l[i] != '@' && i < 31) { buf[i] = l[i]; i++; } buf[i] = 0; }
            current_locale = [[NSLocale alloc] initWithLocaleIdentifier:[NSString stringWithUTF8String:buf]];
        }
        return current_locale;
    }
}
+ (NSLocale *)autoupdatingCurrentLocale { return [self currentLocale]; }
+ (NSLocale *)systemLocale { return [self localeWithLocaleIdentifier:@""]; }
+ (NSArray<NSString *> *)availableLocaleIdentifiers {
    return @[@"en", @"en_US", @"en_GB", @"en_AU", @"en_CA", @"es", @"es_ES", @"es_MX", @"fr", @"fr_FR", @"de", @"de_DE", @"it", @"it_IT",
             @"pt", @"pt_BR", @"pt_PT", @"nl", @"nl_NL", @"sv", @"sv_SE", @"da", @"nb", @"fi", @"pl", @"ru", @"tr", @"ja", @"ja_JP",
             @"ko", @"ko_KR", @"zh", @"zh_CN", @"zh_TW", @"ar", @"he", @"hi", @"th", @"el", @"cs", @"ca", @"eu", @"gl", @"en_US_POSIX"];
}
+ (NSArray<NSString *> *)ISOLanguageCodes { return @[@"ar", @"ca", @"cs", @"da", @"de", @"el", @"en", @"es", @"eu", @"fi", @"fr", @"gl", @"he", @"hi", @"it", @"ja", @"ko", @"nb", @"nl", @"pl", @"pt", @"ru", @"sv", @"th", @"tr", @"zh"]; }
+ (NSArray<NSString *> *)ISOCountryCodes { return @[@"AR", @"AU", @"BR", @"CA", @"CN", @"DE", @"ES", @"FR", @"GB", @"IN", @"IT", @"JP", @"KR", @"MX", @"NL", @"PT", @"RU", @"SE", @"TW", @"US"]; }
+ (NSArray<NSString *> *)ISOCurrencyCodes { return @[@"EUR", @"USD", @"GBP", @"JPY", @"CNY", @"BRL", @"MXN", @"CAD", @"AUD", @"CHF", @"SEK", @"INR", @"KRW", @"RUB"]; }
+ (NSArray<NSString *> *)commonISOCurrencyCodes { return [self ISOCurrencyCodes]; }
+ (NSArray<NSString *> *)preferredLanguages { NSString *l = [[self currentLocale] languageCode]; return @[l ? l : @"en"]; }
+ (NSDictionary *)componentsFromLocaleIdentifier:(NSString *)s {
    NSLocale *l = [self localeWithLocaleIdentifier:s]; NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if ([l languageCode]) d[NSLocaleLanguageCode] = [l languageCode];
    if ([l countryCode]) d[NSLocaleCountryCode] = [l countryCode];
    if ([l scriptCode]) d[NSLocaleScriptCode] = [l scriptCode];
    return d;
}
+ (NSString *)localeIdentifierFromComponents:(NSDictionary *)d {
    NSMutableString *s = [NSMutableString stringWithString:d[NSLocaleLanguageCode] ? d[NSLocaleLanguageCode] : @""];
    if (d[NSLocaleScriptCode]) [s appendFormat:@"_%@", d[NSLocaleScriptCode]];
    if (d[NSLocaleCountryCode]) [s appendFormat:@"_%@", d[NSLocaleCountryCode]];
    return s;
}
+ (NSString *)canonicalLocaleIdentifierFromString:(NSString *)s { return [s stringByReplacingOccurrencesOfString:@"-" withString:@"_"]; }
+ (NSString *)canonicalLanguageIdentifierFromString:(NSString *)s { return [s stringByReplacingOccurrencesOfString:@"_" withString:@"-"]; }
+ (NSString *)localeIdentifierFromWindowsLocaleCode:(uint32_t)l { return l == 0x0c0a ? @"es_ES" : @"en_US"; }
+ (uint32_t)windowsLocaleCodeFromLocaleIdentifier:(NSString *)s { return [s hasPrefix:@"es"] ? 0x0c0a : 0x0409; }
+ (NSLocaleLanguageDirection)characterDirectionForLanguage:(NSString *)l { return [l hasPrefix:@"ar"] || [l hasPrefix:@"he"] ? NSLocaleLanguageDirectionRightToLeft : NSLocaleLanguageDirectionLeftToRight; }
+ (NSLocaleLanguageDirection)lineDirectionForLanguage:(NSString *)l { return NSLocaleLanguageDirectionTopToBottom; }
- (NSString *)localeIdentifier { return _id; }
static NSArray *id_parts(NSString *s) { return [[s stringByReplacingOccurrencesOfString:@"-" withString:@"_"] componentsSeparatedByString:@"_"]; }
- (NSString *)languageCode { NSString *l = [id_parts(_id) firstObject]; return [l length] ? l : @"en"; }
- (NSString *)countryCode { for (NSString *p in [id_parts(_id) subarrayWithRange:NSMakeRange(1, [id_parts(_id) count] - 1)]) if ([p length] == 2 || [p length] == 3) { if ([p isEqualToString:[p uppercaseString]]) return p; } return nil; }
- (NSString *)scriptCode { for (NSString *p in id_parts(_id)) if ([p length] == 4 && ([p characterAtIndex:0] >= 'A' && [p characterAtIndex:0] <= 'Z')) return p; return nil; }
- (NSString *)variantCode { return [_id isEqualToString:@"en_US_POSIX"] ? @"POSIX" : nil; }
- (NSString *)calendarIdentifier { return NSCalendarIdentifierGregorian; }
- (NSString *)collationIdentifier { return nil; }
- (NSString *)collatorIdentifier { return _id; }
static BOOL comma_locale(NSString *lang) { return [@[@"es", @"fr", @"de", @"it", @"pt", @"nl", @"sv", @"da", @"nb", @"fi", @"pl", @"ru", @"tr", @"cs", @"ca", @"eu", @"gl", @"el"] containsObject:lang]; }
- (NSString *)decimalSeparator { return comma_locale([self languageCode]) ? @"," : @"."; }
- (NSString *)groupingSeparator { return comma_locale([self languageCode]) ? @"." : @","; }
- (NSString *)currencyCode { NSString *c = [self countryCode]; if (!c) return nil; return [c isEqualToString:@"US"] ? @"USD" : [c isEqualToString:@"GB"] ? @"GBP" : [c isEqualToString:@"JP"] ? @"JPY" : comma_locale([self languageCode]) ? @"EUR" : @"USD"; }
- (NSString *)currencySymbol { NSString *c = [self currencyCode]; return [c isEqualToString:@"EUR"] ? @"€" : [c isEqualToString:@"GBP"] ? @"£" : [c isEqualToString:@"JPY"] ? @"¥" : @"$"; }
- (BOOL)usesMetricSystem { return ![[self countryCode] isEqualToString:@"US"]; }
- (NSString *)quotationBeginDelimiter { return @"“"; } - (NSString *)quotationEndDelimiter { return @"”"; }
- (NSString *)alternateQuotationBeginDelimiter { return @"‘"; } - (NSString *)alternateQuotationEndDelimiter { return @"’"; }
- (NSCharacterSet *)exemplarCharacterSet { return [NSCharacterSet letterCharacterSet]; }
- (id)objectForKey:(NSLocaleKey)k {
    if ([k isEqualToString:NSLocaleIdentifier]) return _id;
    if ([k isEqualToString:NSLocaleLanguageCode]) return [self languageCode];
    if ([k isEqualToString:NSLocaleCountryCode]) return [self countryCode];
    if ([k isEqualToString:NSLocaleScriptCode]) return [self scriptCode];
    if ([k isEqualToString:NSLocaleVariantCode]) return [self variantCode];
    if ([k isEqualToString:NSLocaleCalendar]) return [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    if ([k isEqualToString:NSLocaleUsesMetricSystem]) return [NSNumber numberWithBool:[self usesMetricSystem]];
    if ([k isEqualToString:NSLocaleMeasurementSystem]) return [self usesMetricSystem] ? @"Metric" : @"U.S.";
    if ([k isEqualToString:NSLocaleDecimalSeparator]) return [self decimalSeparator];
    if ([k isEqualToString:NSLocaleGroupingSeparator]) return [self groupingSeparator];
    if ([k isEqualToString:NSLocaleCurrencySymbol]) return [self currencySymbol];
    if ([k isEqualToString:NSLocaleCurrencyCode]) return [self currencyCode];
    if ([k isEqualToString:NSLocaleExemplarCharacterSet]) return [self exemplarCharacterSet];
    return nil;
}
- (NSString *)displayNameForKey:(NSLocaleKey)k value:(id)v { return [v isKindOfClass:[NSString class]] ? v : nil; } /* ponytail: no localized names */
- (NSString *)localizedStringForLocaleIdentifier:(NSString *)s { return s; }
- (NSString *)localizedStringForLanguageCode:(NSString *)s { return s; }
- (NSString *)localizedStringForCountryCode:(NSString *)s { return s; }
- (NSString *)localizedStringForScriptCode:(NSString *)s { return s; }
- (NSString *)localizedStringForVariantCode:(NSString *)s { return s; }
- (NSString *)localizedStringForCalendarIdentifier:(NSString *)s { return s; }
- (NSString *)localizedStringForCollationIdentifier:(NSString *)s { return s; }
- (NSString *)localizedStringForCurrencyCode:(NSString *)s { return s; }
- (NSString *)localizedStringForCollatorIdentifier:(NSString *)s { return s; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSLocale class]] && [_id isEqualToString:[o localeIdentifier]]); }
- (NSUInteger)hash { return [_id hash]; }
- (NSString *)description { return [NSString stringWithFormat:@"%@ (fixed)", _id]; }
@end

/* ======================================================================= the Gregorian calendar */
/* days since 1970-01-01 <-> civil date (Howard Hinnant's algorithms) */
static long days_from_civil(long y, long m, long d) {
    y -= m <= 2; long era = (y >= 0 ? y : y - 399) / 400; long yoe = y - era * 400;
    long doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1; long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}
static void civil_from_days(long z, long *y, long *m, long *d) {
    z += 719468; long era = (z >= 0 ? z : z - 146096) / 146097; long doe = z - era * 146097;
    long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; long yy = yoe + era * 400;
    long doy = doe - (365 * yoe + yoe / 4 - yoe / 100); long mp = (5 * doy + 2) / 153;
    *d = doy - (153 * mp + 2) / 5 + 1; *m = mp + (mp < 10 ? 3 : -9); *y = yy + (*m <= 2);
}
static BOOL is_leap(long y) { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0; }
static long days_in_month(long y, long m) { static const int dm[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}; return m == 2 && is_leap(y) ? 29 : dm[(m - 1) % 12]; }
static long floordiv(long a, long b) { return a / b - ((a % b != 0) && ((a < 0) != (b < 0))); }
#define REF1970 978307200.0
typedef struct { long era, year, month, day, hour, minute, second, nanosecond, weekday, weekdayOrdinal, quarter, weekOfMonth, weekOfYear, yearForWeekOfYear; } mw_fields;
@implementation NSCalendar { NSString *_ident; NSTimeZone *_tz; NSLocale *_locale; NSUInteger _firstWeekday, _minDays; }
- (id)initWithCalendarIdentifier:(NSCalendarIdentifier)ident {
    if (![ident isEqualToString:NSCalendarIdentifierGregorian] && ![ident isEqualToString:NSCalendarIdentifierISO8601]) { [self release]; return nil; }
    _ident = [ident copy]; _tz = [[NSTimeZone defaultTimeZone] retain]; _locale = [[NSLocale currentLocale] retain];
    BOOL iso = [ident isEqualToString:NSCalendarIdentifierISO8601];
    _firstWeekday = iso ? 2 : 1; _minDays = iso ? 4 : 1;
    return self;
}
- (void)dealloc { [_ident release]; [_tz release]; [_locale release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSCalendar *c = [[NSCalendar alloc] initWithCalendarIdentifier:_ident]; [c setTimeZone:_tz]; [c setLocale:_locale]; c->_firstWeekday = _firstWeekday; c->_minDays = _minDays; return c; }
+ (NSCalendar *)currentCalendar { return [[[self alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease]; }
+ (NSCalendar *)autoupdatingCurrentCalendar { return [self currentCalendar]; }
+ (NSCalendar *)calendarWithIdentifier:(NSCalendarIdentifier)i { return [[[self alloc] initWithCalendarIdentifier:i] autorelease]; }
- (NSCalendarIdentifier)calendarIdentifier { return _ident; }
- (NSTimeZone *)timeZone { return _tz; }
- (void)setTimeZone:(NSTimeZone *)tz { if (!tz) tz = [NSTimeZone defaultTimeZone]; [_tz release]; _tz = [tz retain]; }
- (NSLocale *)locale { return _locale; }
- (void)setLocale:(NSLocale *)l { [_locale release]; _locale = [l retain]; }
- (NSUInteger)firstWeekday { return _firstWeekday; } - (void)setFirstWeekday:(NSUInteger)w { _firstWeekday = w; }
- (NSUInteger)minimumDaysInFirstWeek { return _minDays; } - (void)setMinimumDaysInFirstWeek:(NSUInteger)m { _minDays = m; }
- (NSArray *)monthSymbols { return @[@"January", @"February", @"March", @"April", @"May", @"June", @"July", @"August", @"September", @"October", @"November", @"December"]; }
- (NSArray *)shortMonthSymbols { return @[@"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun", @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec"]; }
- (NSArray *)veryShortMonthSymbols { return @[@"J", @"F", @"M", @"A", @"M", @"J", @"J", @"A", @"S", @"O", @"N", @"D"]; }
- (NSArray *)standaloneMonthSymbols { return [self monthSymbols]; } - (NSArray *)shortStandaloneMonthSymbols { return [self shortMonthSymbols]; }
- (NSArray *)veryShortStandaloneMonthSymbols { return [self veryShortMonthSymbols]; }
- (NSArray *)weekdaySymbols { return @[@"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday"]; }
- (NSArray *)shortWeekdaySymbols { return @[@"Sun", @"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat"]; }
- (NSArray *)veryShortWeekdaySymbols { return @[@"S", @"M", @"T", @"W", @"T", @"F", @"S"]; }
- (NSArray *)standaloneWeekdaySymbols { return [self weekdaySymbols]; } - (NSArray *)shortStandaloneWeekdaySymbols { return [self shortWeekdaySymbols]; }
- (NSArray *)veryShortStandaloneWeekdaySymbols { return [self veryShortWeekdaySymbols]; }
- (NSArray *)eraSymbols { return @[@"BC", @"AD"]; } - (NSArray *)longEraSymbols { return @[@"Before Christ", @"Anno Domini"]; }
- (NSArray *)quarterSymbols { return @[@"1st quarter", @"2nd quarter", @"3rd quarter", @"4th quarter"]; }
- (NSArray *)shortQuarterSymbols { return @[@"Q1", @"Q2", @"Q3", @"Q4"]; }
- (NSArray *)standaloneQuarterSymbols { return [self quarterSymbols]; } - (NSArray *)shortStandaloneQuarterSymbols { return [self shortQuarterSymbols]; }
- (NSString *)AMSymbol { return @"AM"; } - (NSString *)PMSymbol { return @"PM"; }
- (NSInteger)formattingContext { return 0; } - (void)setFormattingContext:(NSInteger)c { }
static mw_fields fields_of(NSCalendar *c, NSDate *date, NSTimeZone *tz) {
    mw_fields f; memset(&f, 0, sizeof f);
    double t = [date timeIntervalSinceReferenceDate] + REF1970 + (double)[tz secondsFromGMTForDate:date];
    double ts = floor(t); long secs = (long)ts; long days = floordiv(secs, 86400), rem = secs - days * 86400;
    civil_from_days(days, &f.year, &f.month, &f.day);
    f.hour = rem / 3600; f.minute = rem / 60 % 60; f.second = rem % 60; f.nanosecond = (long)((t - ts) * 1e9 + 0.5);
    if (f.nanosecond >= 1000000000) f.nanosecond = 999999999;
    f.weekday = floordiv(days + 4, 7) * -7 + days + 4 + 1; /* 1970-01-01 was a Thursday: 1 = Sunday */
    f.era = f.year > 0; if (f.year <= 0) f.year = 1 - f.year;
    f.quarter = (f.month - 1) / 3 + 1; f.weekdayOrdinal = (f.day - 1) / 7 + 1;
    long fw = (long)c->_firstWeekday, md = (long)c->_minDays;
    long jan1 = days_from_civil(f.era ? f.year : 1 - f.year, 1, 1), doy = days - jan1;
    long jan1wd = ((jan1 + 4) % 7 + 7) % 7 + 1, off = ((jan1wd - fw) + 7) % 7; /* days of week 1 before Jan 1 */
    long week = (doy + off) / 7 + ((7 - off) >= md ? 1 : 0);
    f.yearForWeekOfYear = f.era ? f.year : 1 - f.year;
    if (week == 0) { /* belongs to the last week of the previous year */
        long py = f.yearForWeekOfYear - 1, pj = days_from_civil(py, 1, 1), pwd = ((pj + 4) % 7 + 7) % 7 + 1, poff = ((pwd - fw) + 7) % 7;
        week = (days - pj + poff) / 7 + ((7 - poff) >= md ? 1 : 0); f.yearForWeekOfYear = py;
    } else {
        long ny = f.yearForWeekOfYear + 1, nj = days_from_civil(ny, 1, 1), nwd = ((nj + 4) % 7 + 7) % 7 + 1, noff = ((nwd - fw) + 7) % 7;
        if ((7 - noff) >= md && days >= nj - noff) { week = 1; f.yearForWeekOfYear = ny; }
    }
    f.weekOfYear = week;
    long first = days - (f.day - 1), fwd = ((first + 4) % 7 + 7) % 7 + 1, moff = ((fwd - fw) + 7) % 7;
    f.weekOfMonth = (f.day - 1 + moff) / 7 + ((7 - moff) >= md ? 1 : 0);
    return f;
}
static NSDate *date_of(long era, long y, long mo, long d, long h, long mi, long s, long ns, NSTimeZone *tz) {
    if (!era) y = 1 - y;
    y += floordiv(mo - 1, 12); mo = mo - 1 - floordiv(mo - 1, 12) * 12 + 1;
    double days = (double)days_from_civil(y, mo, 1) + (double)(d - 1);
    double t = days * 86400 + (double)h * 3600 + (double)mi * 60 + (double)s + (double)ns / 1e9 - REF1970;
    NSDate *guess = [NSDate dateWithTimeIntervalSinceReferenceDate:t];
    return [NSDate dateWithTimeIntervalSinceReferenceDate:t - (double)[tz secondsFromGMTForDate:guess]];
}
#define U(x) NSCalendarUnit##x
- (NSDateComponents *)components:(NSCalendarUnit)units fromDate:(NSDate *)date { return [self _components:units fromDate:date timeZone:_tz]; }
- (NSDateComponents *)componentsInTimeZone:(NSTimeZone *)tz fromDate:(NSDate *)date {
    NSDateComponents *c = [self _components:(NSCalendarUnit)~0ul fromDate:date timeZone:tz]; [c setCalendar:self]; [c setTimeZone:tz]; return c;
}
- (NSDateComponents *)_components:(NSCalendarUnit)u fromDate:(NSDate *)date timeZone:(NSTimeZone *)tz {
    mw_fields f = fields_of(self, date, tz); NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    if (u & U(Era)) [c setEra:f.era]; if (u & U(Year)) [c setYear:f.year]; if (u & U(Month)) [c setMonth:f.month];
    if (u & U(Day)) [c setDay:f.day]; if (u & U(Hour)) [c setHour:f.hour]; if (u & U(Minute)) [c setMinute:f.minute];
    if (u & U(Second)) [c setSecond:f.second]; if (u & U(Nanosecond)) [c setNanosecond:f.nanosecond]; if (u & U(Weekday)) [c setWeekday:f.weekday];
    if (u & U(WeekdayOrdinal)) [c setWeekdayOrdinal:f.weekdayOrdinal]; if (u & U(Quarter)) [c setQuarter:f.quarter];
    if (u & U(WeekOfMonth)) [c setWeekOfMonth:f.weekOfMonth]; if (u & U(WeekOfYear)) [c setWeekOfYear:f.weekOfYear];
    if (u & U(YearForWeekOfYear)) [c setYearForWeekOfYear:f.yearForWeekOfYear];
    if (u & U(Calendar)) [c setCalendar:self]; if (u & U(TimeZone)) [c setTimeZone:tz];
    return c;
}
static long cv(NSInteger v, long dflt) { return v == NSDateComponentUndefined ? dflt : (long)v; }
- (NSDate *)dateFromComponents:(NSDateComponents *)c {
    NSTimeZone *tz = [c timeZone] ? [c timeZone] : _tz;
    long year = cv([c year], 1), month = cv([c month], 1), day = cv([c day], 1);
    if ([c year] == NSDateComponentUndefined && [c yearForWeekOfYear] != NSDateComponentUndefined) {
        /* week-based date: Monday-or-firstWeekday of the week, then the weekday */
        long y = [c yearForWeekOfYear], wk = cv([c weekOfYear], 1), wd = cv([c weekday], (long)_firstWeekday);
        long jan1 = days_from_civil(y, 1, 1), jwd = ((jan1 + 4) % 7 + 7) % 7 + 1, off = ((jwd - (long)_firstWeekday) + 7) % 7;
        long start = jan1 - off + ((7 - off) >= (long)_minDays ? 0 : 7) + (wk - 1) * 7 + ((wd - (long)_firstWeekday) + 7) % 7;
        civil_from_days(start, &year, &month, &day);
    }
    return date_of(cv([c era], 1), year, month, day, cv([c hour], 0), cv([c minute], 0), cv([c second], 0), cv([c nanosecond], 0), tz);
}
- (NSInteger)component:(NSCalendarUnit)unit fromDate:(NSDate *)date { return [[self components:unit fromDate:date] valueForComponent:unit]; }
- (void)getEra:(NSInteger *)e year:(NSInteger *)y month:(NSInteger *)m day:(NSInteger *)d fromDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); if (e) *e = f.era; if (y) *y = f.year; if (m) *m = f.month; if (d) *d = f.day;
}
- (void)getEra:(NSInteger *)e yearForWeekOfYear:(NSInteger *)y weekOfYear:(NSInteger *)w weekday:(NSInteger *)wd fromDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); if (e) *e = f.era; if (y) *y = f.yearForWeekOfYear; if (w) *w = f.weekOfYear; if (wd) *wd = f.weekday;
}
- (void)getHour:(NSInteger *)h minute:(NSInteger *)m second:(NSInteger *)s nanosecond:(NSInteger *)ns fromDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); if (h) *h = f.hour; if (m) *m = f.minute; if (s) *s = f.second; if (ns) *ns = f.nanosecond;
}
- (NSDate *)dateWithEra:(NSInteger)e year:(NSInteger)y month:(NSInteger)m day:(NSInteger)d hour:(NSInteger)h minute:(NSInteger)mi second:(NSInteger)s nanosecond:(NSInteger)ns {
    return date_of(e, y, m, d, h, mi, s, ns, _tz);
}
- (NSDate *)dateWithEra:(NSInteger)e yearForWeekOfYear:(NSInteger)y weekOfYear:(NSInteger)w weekday:(NSInteger)wd hour:(NSInteger)h minute:(NSInteger)mi second:(NSInteger)s nanosecond:(NSInteger)ns {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    [c setEra:e]; [c setYearForWeekOfYear:y]; [c setWeekOfYear:w]; [c setWeekday:wd]; [c setHour:h]; [c setMinute:mi]; [c setSecond:s]; [c setNanosecond:ns];
    return [self dateFromComponents:c];
}
- (NSDate *)dateByAddingComponents:(NSDateComponents *)c toDate:(NSDate *)date options:(NSCalendarOptions)opts {
    mw_fields f = fields_of(self, date, _tz);
    long y = f.era ? f.year : 1 - f.year, mo = f.month + cv([c month], 0) + 12 * cv([c year], 0) + 3 * cv([c quarter], 0);
    y += floordiv(mo - 1, 12); mo = mo - 1 - floordiv(mo - 1, 12) * 12 + 1;
    long d = f.day; if (d > days_in_month(y, mo)) d = days_in_month(y, mo); /* Jan 31 + 1 month = Feb 28/29 */
    d += cv([c day], 0) + 7 * (cv([c weekOfYear], 0) + cv([c weekOfMonth], 0)) + cv([c weekday], 0);
    NSDate *r = date_of(1, y, mo, d, f.hour, f.minute, f.second, f.nanosecond, _tz);
    double extra = (double)cv([c hour], 0) * 3600 + (double)cv([c minute], 0) * 60 + (double)cv([c second], 0) + (double)cv([c nanosecond], 0) / 1e9;
    return [r dateByAddingTimeInterval:extra];
}
- (NSDate *)dateByAddingUnit:(NSCalendarUnit)unit value:(NSInteger)v toDate:(NSDate *)date options:(NSCalendarOptions)o {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease]; [c setValue:v forComponent:unit];
    return [self dateByAddingComponents:c toDate:date options:o];
}
- (NSDateComponents *)components:(NSCalendarUnit)u fromDate:(NSDate *)a toDate:(NSDate *)b options:(NSCalendarOptions)o {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    NSDate *cur = a; BOOL neg = [b compare:a] == NSOrderedAscending;
    static const NSCalendarUnit order[] = {NSCalendarUnitEra, NSCalendarUnitYear, NSCalendarUnitMonth, NSCalendarUnitWeekOfYear, NSCalendarUnitDay, NSCalendarUnitHour,
                                           NSCalendarUnitMinute, NSCalendarUnitSecond, NSCalendarUnitNanosecond};
    for (unsigned i = 0; i < sizeof order / sizeof *order; i++) {
        NSCalendarUnit k = order[i]; if (!(u & k) || k == NSCalendarUnitEra) continue;
        NSInteger n = 0;
        if (k == NSCalendarUnitNanosecond) n = (NSInteger)(([b timeIntervalSinceReferenceDate] - [cur timeIntervalSinceReferenceDate]) * 1e9);
        else if (k >= NSCalendarUnitDay && k <= NSCalendarUnitSecond) {
            double per = k == NSCalendarUnitDay ? 86400 : k == NSCalendarUnitHour ? 3600 : k == NSCalendarUnitMinute ? 60 : 1;
            n = (NSInteger)(([b timeIntervalSinceReferenceDate] - [cur timeIntervalSinceReferenceDate]) / per);
        } else {
            NSCalendarUnit step = k == NSCalendarUnitWeekOfYear ? NSCalendarUnitDay : k; NSInteger mult = k == NSCalendarUnitWeekOfYear ? 7 : 1;
            for (;;) { NSDate *nx = [self dateByAddingUnit:step value:(n + (neg ? -1 : 1)) * mult toDate:cur options:0];
                       if (neg ? [nx compare:b] == NSOrderedAscending : [nx compare:b] == NSOrderedDescending) break; n += neg ? -1 : 1; if (n > 100000 || n < -100000) break; }
        }
        [c setValue:n forComponent:k];
        if (k != NSCalendarUnitNanosecond) cur = [self dateByAddingUnit:(k == NSCalendarUnitWeekOfYear ? NSCalendarUnitDay : k) value:(k == NSCalendarUnitWeekOfYear ? n * 7 : n) toDate:cur options:0];
    }
    return c;
}
- (NSDateComponents *)components:(NSCalendarUnit)u fromDateComponents:(NSDateComponents *)a toDateComponents:(NSDateComponents *)b options:(NSCalendarOptions)o {
    return [self components:u fromDate:[self dateFromComponents:a] toDate:[self dateFromComponents:b] options:o];
}
- (NSRange)minimumRangeOfUnit:(NSCalendarUnit)u {
    switch (u) { case U(Era): return NSMakeRange(0, 2); case U(Year): return NSMakeRange(1, 140742); case U(Month): return NSMakeRange(1, 12);
                 case U(Day): return NSMakeRange(1, 28); case U(Hour): return NSMakeRange(0, 24); case U(Minute): case U(Second): return NSMakeRange(0, 60);
                 case U(Weekday): return NSMakeRange(1, 7); case U(WeekdayOrdinal): return NSMakeRange(1, 4); case U(Quarter): return NSMakeRange(1, 4);
                 case U(WeekOfMonth): return NSMakeRange(1, 4); case U(WeekOfYear): return NSMakeRange(1, 52); case U(Nanosecond): return NSMakeRange(0, 1000000000);
                 default: return NSMakeRange(NSNotFound, NSNotFound); }
}
- (NSRange)maximumRangeOfUnit:(NSCalendarUnit)u {
    switch (u) { case U(Day): return NSMakeRange(1, 31); case U(WeekdayOrdinal): return NSMakeRange(1, 5); case U(WeekOfMonth): return NSMakeRange(1, 6);
                 case U(WeekOfYear): return NSMakeRange(1, 53); case U(Year): return NSMakeRange(1, 144683); default: return [self minimumRangeOfUnit:u]; }
}
- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); long y = f.era ? f.year : 1 - f.year;
    if (smaller == U(Day) && larger == U(Month)) return NSMakeRange(1, (NSUInteger)days_in_month(y, f.month));
    if (smaller == U(Day) && larger == U(Year)) return NSMakeRange(1, is_leap(y) ? 366 : 365);
    if (smaller == U(Month) && larger == U(Year)) return NSMakeRange(1, 12);
    if (smaller == U(Hour) && larger == U(Day)) return NSMakeRange(0, 24);
    if (smaller == U(Minute) && larger == U(Hour)) return NSMakeRange(0, 60);
    if (smaller == U(Second) && larger == U(Minute)) return NSMakeRange(0, 60);
    if (smaller == U(Weekday)) return NSMakeRange(1, 7);
    return [self maximumRangeOfUnit:smaller];
}
- (NSUInteger)ordinalityOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); long y = f.era ? f.year : 1 - f.year;
    if (smaller == U(Day) && larger == U(Month)) return (NSUInteger)f.day;
    if (smaller == U(Day) && larger == U(Year)) return (NSUInteger)(days_from_civil(y, f.month, f.day) - days_from_civil(y, 1, 1) + 1);
    if (smaller == U(Month) && larger == U(Year)) return (NSUInteger)f.month;
    if (smaller == U(Hour) && larger == U(Day)) return (NSUInteger)f.hour + 1;
    if (smaller == U(Weekday) && larger == U(WeekOfYear)) return (NSUInteger)(((f.weekday - (long)_firstWeekday) + 7) % 7 + 1);
    if (smaller == U(WeekOfYear) && larger == U(Year)) return (NSUInteger)f.weekOfYear;
    return NSNotFound;
}
- (BOOL)rangeOfUnit:(NSCalendarUnit)u startDate:(NSDate **)start interval:(NSTimeInterval *)iv forDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); long y = f.era ? f.year : 1 - f.year; NSDate *s; double len;
    switch (u) {
    case U(Year): s = date_of(1, y, 1, 1, 0, 0, 0, 0, _tz); len = (is_leap(y) ? 366 : 365) * 86400.0; break;
    case U(Month): s = date_of(1, y, f.month, 1, 0, 0, 0, 0, _tz); len = (double)days_in_month(y, f.month) * 86400; break;
    case U(Day): s = date_of(1, y, f.month, f.day, 0, 0, 0, 0, _tz); len = 86400; break;
    case U(Hour): s = date_of(1, y, f.month, f.day, f.hour, 0, 0, 0, _tz); len = 3600; break;
    case U(Minute): s = date_of(1, y, f.month, f.day, f.hour, f.minute, 0, 0, _tz); len = 60; break;
    case U(Second): s = date_of(1, y, f.month, f.day, f.hour, f.minute, f.second, 0, _tz); len = 1; break;
    case U(WeekOfYear): case U(WeekOfMonth): {
        long back = ((f.weekday - (long)_firstWeekday) + 7) % 7;
        s = [date_of(1, y, f.month, f.day, 0, 0, 0, 0, _tz) dateByAddingTimeInterval:-86400.0 * (double)back]; len = 7 * 86400; break;
    }
    default: return NO;
    }
    if (start) *start = s; if (iv) *iv = len; return YES;
}
- (NSDate *)startOfDayForDate:(NSDate *)d { NSDate *s = nil; [self rangeOfUnit:NSCalendarUnitDay startDate:&s interval:0 forDate:d]; return s; }
- (NSComparisonResult)compareDate:(NSDate *)a toDate:(NSDate *)b toUnitGranularity:(NSCalendarUnit)u {
    NSDate *sa = nil, *sb = nil; [self rangeOfUnit:u startDate:&sa interval:0 forDate:a]; [self rangeOfUnit:u startDate:&sb interval:0 forDate:b];
    return [sa ? sa : a compare:sb ? sb : b];
}
- (BOOL)isDate:(NSDate *)a equalToDate:(NSDate *)b toUnitGranularity:(NSCalendarUnit)u { return [self compareDate:a toDate:b toUnitGranularity:u] == NSOrderedSame; }
- (BOOL)isDate:(NSDate *)a inSameDayAsDate:(NSDate *)b { return [self isDate:a equalToDate:b toUnitGranularity:NSCalendarUnitDay]; }
- (BOOL)isDateInToday:(NSDate *)d { return [self isDate:d inSameDayAsDate:[NSDate date]]; }
- (BOOL)isDateInYesterday:(NSDate *)d { return [self isDate:d inSameDayAsDate:[NSDate dateWithTimeIntervalSinceNow:-86400]]; }
- (BOOL)isDateInTomorrow:(NSDate *)d { return [self isDate:d inSameDayAsDate:[NSDate dateWithTimeIntervalSinceNow:86400]]; }
- (BOOL)isDateInWeekend:(NSDate *)d { NSInteger w = [self component:NSCalendarUnitWeekday fromDate:d]; return w == 1 || w == 7; }
- (BOOL)rangeOfWeekendStartDate:(NSDate **)s interval:(NSTimeInterval *)iv containingDate:(NSDate *)d {
    if (![self isDateInWeekend:d]) return NO;
    NSDate *day = [self startOfDayForDate:d]; if ([self component:NSCalendarUnitWeekday fromDate:d] == 1) day = [day dateByAddingTimeInterval:-86400];
    if (s) *s = day; if (iv) *iv = 2 * 86400; return YES;
}
- (BOOL)nextWeekendStartDate:(NSDate **)s interval:(NSTimeInterval *)iv options:(NSCalendarOptions)o afterDate:(NSDate *)d {
    NSDate *day = [self startOfDayForDate:d];
    for (int i = 1; i <= 7; i++) { NSDate *n = [day dateByAddingTimeInterval:(o & NSCalendarSearchBackwards ? -86400.0 : 86400.0) * i];
        if ([self component:NSCalendarUnitWeekday fromDate:n] == 7) { if (s) *s = n; if (iv) *iv = 2 * 86400; return YES; } }
    return NO;
}
- (BOOL)date:(NSDate *)date matchesComponents:(NSDateComponents *)c {
    NSDateComponents *have = [self componentsInTimeZone:_tz fromDate:date];
    static const NSCalendarUnit all[] = {U(Era), U(Year), U(Month), U(Day), U(Hour), U(Minute), U(Second), U(Weekday), U(WeekdayOrdinal), U(Quarter),
                                         U(WeekOfMonth), U(WeekOfYear), U(YearForWeekOfYear), U(Nanosecond)};
    for (unsigned i = 0; i < sizeof all / sizeof *all; i++) { NSInteger v = [c valueForComponent:all[i]]; if (v != NSDateComponentUndefined && v != [have valueForComponent:all[i]]) return NO; }
    return YES;
}
- (NSDate *)nextDateAfterDate:(NSDate *)date matchingComponents:(NSDateComponents *)c options:(NSCalendarOptions)o {
    /* ponytail: steps by the smallest unit the components name, up to 4 years */
    NSCalendarUnit step = [c second] != NSDateComponentUndefined ? U(Second) : [c minute] != NSDateComponentUndefined ? U(Minute)
                        : [c hour] != NSDateComponentUndefined ? U(Hour) : U(Day);
    NSDate *d = date;
    if (step != U(Second)) { NSDate *s = nil; [self rangeOfUnit:step startDate:&s interval:0 forDate:d]; d = s ? s : d; }
    BOOL back = (o & NSCalendarSearchBackwards) != 0;
    for (int i = 0; i < 1500 * (step == U(Day) ? 1 : step == U(Hour) ? 24 : 60); i++) {
        d = [self dateByAddingUnit:step value:back ? -1 : 1 toDate:d options:0];
        if ([self date:d matchesComponents:c]) return d;
    }
    return nil;
}
- (void)enumerateDatesStartingAfterDate:(NSDate *)start matchingComponents:(NSDateComponents *)c options:(NSCalendarOptions)o usingBlock:(void (^)(NSDate *, BOOL, BOOL *))block {
    NSDate *d = start; BOOL stop = NO;
    while (!stop && (d = [self nextDateAfterDate:d matchingComponents:c options:o])) block(d, YES, &stop);
}
- (NSDate *)nextDateAfterDate:(NSDate *)date matchingUnit:(NSCalendarUnit)u value:(NSInteger)v options:(NSCalendarOptions)o {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease]; [c setValue:v forComponent:u]; return [self nextDateAfterDate:date matchingComponents:c options:o];
}
- (NSDate *)nextDateAfterDate:(NSDate *)date matchingHour:(NSInteger)h minute:(NSInteger)m second:(NSInteger)s options:(NSCalendarOptions)o {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease]; [c setHour:h]; [c setMinute:m]; [c setSecond:s]; return [self nextDateAfterDate:date matchingComponents:c options:o];
}
- (NSDate *)dateBySettingUnit:(NSCalendarUnit)u value:(NSInteger)v ofDate:(NSDate *)date options:(NSCalendarOptions)o {
    NSDateComponents *c = [self componentsInTimeZone:_tz fromDate:date]; [c setValue:v forComponent:u];
    if (u != U(Weekday)) [c setWeekday:NSDateComponentUndefined]; [c setWeekOfYear:NSDateComponentUndefined]; [c setYearForWeekOfYear:NSDateComponentUndefined];
    return [self dateFromComponents:c];
}
- (NSDate *)dateBySettingHour:(NSInteger)h minute:(NSInteger)m second:(NSInteger)s ofDate:(NSDate *)date options:(NSCalendarOptions)o {
    mw_fields f = fields_of(self, date, _tz); return date_of(f.era, f.year, f.month, f.day, h, m, s, 0, _tz);
}
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSCalendar class]] && [_ident isEqualToString:[o calendarIdentifier]] && [_tz isEqual:[o timeZone]]); }
- (NSUInteger)hash { return [_ident hash]; }
@end

@implementation NSDateComponents { NSInteger _v[14]; BOOL _leap; NSCalendar *_cal; NSTimeZone *_tz; }
- (instancetype)init { for (int i = 0; i < 14; i++) _v[i] = NSDateComponentUndefined; return self; }
- (void)dealloc { [_cal release]; [_tz release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSDateComponents *c = [[NSDateComponents alloc] init]; memcpy(c->_v, _v, sizeof _v); c->_leap = _leap; c->_cal = [_cal retain]; c->_tz = [_tz retain]; return c; }
static int slot(NSCalendarUnit u) {
    switch (u) { case U(Era): return 0; case U(Year): return 1; case U(Month): return 2; case U(Day): return 3; case U(Hour): return 4;
                 case U(Minute): return 5; case U(Second): return 6; case U(Nanosecond): return 7; case U(Weekday): return 8;
                 case U(WeekdayOrdinal): return 9; case U(Quarter): return 10; case U(WeekOfMonth): return 11; case U(WeekOfYear): return 12;
                 case U(YearForWeekOfYear): return 13; default: return -1; }
}
- (void)setValue:(NSInteger)v forComponent:(NSCalendarUnit)u { int s = slot(u); if (s >= 0) _v[s] = v; }
- (NSInteger)valueForComponent:(NSCalendarUnit)u { int s = slot(u); return s >= 0 ? _v[s] : NSDateComponentUndefined; }
#define ACC(get, set, i) - (NSInteger)get { return _v[i]; } - (void)set:(NSInteger)v { _v[i] = v; }
ACC(era, setEra, 0) ACC(year, setYear, 1) ACC(month, setMonth, 2) ACC(day, setDay, 3) ACC(hour, setHour, 4) ACC(minute, setMinute, 5)
ACC(second, setSecond, 6) ACC(nanosecond, setNanosecond, 7) ACC(weekday, setWeekday, 8) ACC(weekdayOrdinal, setWeekdayOrdinal, 9)
ACC(quarter, setQuarter, 10) ACC(weekOfMonth, setWeekOfMonth, 11) ACC(weekOfYear, setWeekOfYear, 12) ACC(yearForWeekOfYear, setYearForWeekOfYear, 13)
- (BOOL)isLeapMonth { return _leap; } - (void)setLeapMonth:(BOOL)l { _leap = l; }
- (NSCalendar *)calendar { return _cal; } - (void)setCalendar:(NSCalendar *)c { [_cal release]; _cal = [c copy]; }
- (NSTimeZone *)timeZone { return _tz; } - (void)setTimeZone:(NSTimeZone *)t { [_tz release]; _tz = [t retain]; }
- (NSDate *)date { return _cal ? [_cal dateFromComponents:self] : nil; }
- (BOOL)isValidDate { return _cal ? [self isValidDateInCalendar:_cal] : NO; }
- (BOOL)isValidDateInCalendar:(NSCalendar *)cal {
    if (_v[2] != NSDateComponentUndefined && (_v[2] < 1 || _v[2] > 12)) return NO;
    if (_v[3] != NSDateComponentUndefined && (_v[3] < 1 || _v[3] > days_in_month(_v[1] == NSDateComponentUndefined ? 2001 : _v[1], _v[2] == NSDateComponentUndefined ? 1 : _v[2]))) return NO;
    if (_v[4] != NSDateComponentUndefined && (_v[4] < 0 || _v[4] > 23)) return NO;
    if (_v[5] != NSDateComponentUndefined && (_v[5] < 0 || _v[5] > 59)) return NO;
    if (_v[6] != NSDateComponentUndefined && (_v[6] < 0 || _v[6] > 59)) return NO;
    return YES;
}
- (BOOL)isEqual:(id)o {
    if (o == self) return YES; if (![o isKindOfClass:[NSDateComponents class]]) return NO;
    NSDateComponents *c = o; return !memcmp(_v, c->_v, sizeof _v) && _leap == c->_leap;
}
- (NSUInteger)hash { NSUInteger h = 0; for (int i = 0; i < 14; i++) h = h * 31 + (NSUInteger)_v[i]; return h; }
@end

@implementation NSDateInterval { NSDate *_start; NSTimeInterval _dur; }
- (instancetype)init { return [self initWithStartDate:[NSDate date] duration:0]; }
- (instancetype)initWithStartDate:(NSDate *)s duration:(NSTimeInterval)d { _start = [s copy]; _dur = d; return self; }
- (instancetype)initWithStartDate:(NSDate *)s endDate:(NSDate *)e { return [self initWithStartDate:s duration:[e timeIntervalSinceDate:s]]; }
- (void)dealloc { [_start release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSDate *)startDate { return _start; } - (NSDate *)endDate { return [_start dateByAddingTimeInterval:_dur]; } - (NSTimeInterval)duration { return _dur; }
- (NSComparisonResult)compare:(NSDateInterval *)o { NSComparisonResult r = [_start compare:[o startDate]]; return r != NSOrderedSame ? r : _dur < [o duration] ? NSOrderedAscending : _dur > [o duration] ? NSOrderedDescending : NSOrderedSame; }
- (BOOL)isEqualToDateInterval:(NSDateInterval *)o { return [self compare:o] == NSOrderedSame; }
- (BOOL)intersectsDateInterval:(NSDateInterval *)o { return [[self startDate] compare:[o endDate]] != NSOrderedDescending && [[o startDate] compare:[self endDate]] != NSOrderedDescending; }
- (NSDateInterval *)intersectionWithDateInterval:(NSDateInterval *)o {
    if (![self intersectsDateInterval:o]) return nil;
    NSDate *s = [[self startDate] laterDate:[o startDate]], *e = [[self endDate] earlierDate:[o endDate]];
    return [[[NSDateInterval alloc] initWithStartDate:s endDate:e] autorelease];
}
- (BOOL)containsDate:(NSDate *)d { return [d compare:_start] != NSOrderedAscending && [d compare:[self endDate]] != NSOrderedDescending; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSDateInterval class]] && [self isEqualToDateInterval:o]; }
- (NSUInteger)hash { return [_start hash] ^ (NSUInteger)_dur; }
@end

@implementation NSDate (NSExtendedDate)
- (instancetype)initWithTimeIntervalSinceNow:(NSTimeInterval)s { return [self initWithTimeIntervalSinceReferenceDate:[NSDate timeIntervalSinceReferenceDate] + s]; }
- (instancetype)initWithTimeIntervalSince1970:(NSTimeInterval)s { return [self initWithTimeIntervalSinceReferenceDate:s - REF1970]; }
- (instancetype)initWithTimeInterval:(NSTimeInterval)s sinceDate:(NSDate *)d { return [self initWithTimeIntervalSinceReferenceDate:[d timeIntervalSinceReferenceDate] + s]; }
- (BOOL)isEqualToDate:(NSDate *)o { return [o timeIntervalSinceReferenceDate] == [self timeIntervalSinceReferenceDate]; }
- (NSDate *)earlierDate:(NSDate *)o { return [self compare:o] == NSOrderedDescending ? o : self; }
- (NSDate *)laterDate:(NSDate *)o { return [self compare:o] == NSOrderedAscending ? o : self; }
- (NSString *)descriptionWithLocale:(id)l { return [self description]; }
@end

/* ======================================================================= date formatters (Unicode date patterns) */
@implementation NSFormatter
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)stringForObjectValue:(id)o { return [o description]; }
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)s errorDescription:(NSString **)e { if (obj) *obj = s; return YES; }
@end
static NSString *format_date(NSString *fmt, NSDate *date, NSTimeZone *tz, NSCalendar *cal) {
    mw_fields f = fields_of(cal, date, tz); NSMutableString *out = [NSMutableString string];
    NSUInteger n; unichar *u = mw_chars(fmt, &n);
    for (NSUInteger i = 0; i < n;) {
        unichar c = u[i];
        if (c == '\'') { /* quoted literal; '' is a quote */
            i++; if (i < n && u[i] == '\'') { [out appendString:@"'"]; i++; continue; }
            while (i < n && u[i] != '\'') { [out appendString:[NSString stringWithCharacters:&u[i] length:1]]; i++; }
            i++; continue;
        }
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) { [out appendString:[NSString stringWithCharacters:&c length:1]]; i++; continue; }
        NSUInteger k = 1; while (i + k < n && u[i + k] == c) k++;
        long off = (long)[tz secondsFromGMTForDate:date], ao = off < 0 ? -off : off;
        switch (c) {
        case 'y': case 'u': if (k == 2) [out appendFormat:@"%02ld", f.year % 100]; else [out appendFormat:@"%0*ld", (int)k, f.year]; break;
        case 'Y': [out appendFormat:@"%0*ld", (int)(k == 2 ? 2 : k), k == 2 ? f.yearForWeekOfYear % 100 : f.yearForWeekOfYear]; break;
        case 'M': case 'L':
            if (k >= 4) [out appendString:[cal monthSymbols][(NSUInteger)f.month - 1]];
            else if (k == 3) [out appendString:[cal shortMonthSymbols][(NSUInteger)f.month - 1]];
            else [out appendFormat:@"%0*ld", (int)k, f.month]; break;
        case 'd': [out appendFormat:@"%0*ld", (int)k, f.day]; break;
        case 'D': [out appendFormat:@"%0*ld", (int)k, days_from_civil(f.year, f.month, f.day) - days_from_civil(f.year, 1, 1) + 1]; break;
        case 'E': case 'e': case 'c':
            if (k >= 4) [out appendString:[cal weekdaySymbols][(NSUInteger)f.weekday - 1]];
            else if (k == 3 || c == 'E') [out appendString:[cal shortWeekdaySymbols][(NSUInteger)f.weekday - 1]];
            else [out appendFormat:@"%ld", f.weekday]; break;
        case 'a': [out appendString:f.hour < 12 ? @"AM" : @"PM"]; break;
        case 'H': [out appendFormat:@"%0*ld", (int)k, f.hour]; break;
        case 'k': [out appendFormat:@"%0*ld", (int)k, f.hour ? f.hour : 24]; break;
        case 'h': [out appendFormat:@"%0*ld", (int)k, f.hour % 12 ? f.hour % 12 : 12]; break;
        case 'K': [out appendFormat:@"%0*ld", (int)k, f.hour % 12]; break;
        case 'm': [out appendFormat:@"%0*ld", (int)k, f.minute]; break;
        case 's': [out appendFormat:@"%0*ld", (int)k, f.second]; break;
        case 'S': { long v = f.nanosecond; int digits = 9; while (digits > (int)k) { v /= 10; digits--; } [out appendFormat:@"%0*ld", (int)k, v]; break; }
        case 'G': [out appendString:f.era ? @"AD" : @"BC"]; break;
        case 'Q': case 'q': [out appendFormat:k >= 3 ? @"Q%ld" : @"%ld", f.quarter]; break;
        case 'w': [out appendFormat:@"%0*ld", (int)k, f.weekOfYear]; break;
        case 'W': [out appendFormat:@"%ld", f.weekOfMonth]; break;
        case 'Z': if (k == 4) { if (!off) [out appendString:@"GMT"]; else [out appendFormat:@"GMT%c%02ld:%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60]; }
                  else if (k == 5) { if (!off) [out appendString:@"Z"]; else [out appendFormat:@"%c%02ld:%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60]; }
                  else [out appendFormat:@"%c%02ld%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60]; break;
        case 'X': case 'x':
            if (!off && c == 'X') [out appendString:@"Z"];
            else if (k == 1) [out appendFormat:@"%c%02ld", off < 0 ? '-' : '+', ao / 3600];
            else if (k == 2 || k == 4) [out appendFormat:@"%c%02ld%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60];
            else [out appendFormat:@"%c%02ld:%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60]; break;
        case 'z': case 'v': case 'V': case 'O': [out appendString:k >= 4 ? [tz name] : [tz abbreviation] ? [tz abbreviation] : [tz name]]; break;
        default: break;
        }
        i += k;
    }
    free(u);
    return out;
}
static NSDate *parse_date(NSString *fmt, NSString *str, NSTimeZone *tz, NSCalendar *cal) {
    NSUInteger n, m; unichar *u = mw_chars(fmt, &n), *s = mw_chars(str, &m); NSUInteger p = 0;
    long y = 2000, mo = 1, d = 1, h = 0, mi = 0, sec = 0, ns = 0; BOOL pm = NO, ampm = NO, haveOff = NO; long off = 0; BOOL ok = YES;
    for (NSUInteger i = 0; i < n && ok;) {
        unichar c = u[i];
        if (c == '\'') { i++; while (i < n && u[i] != '\'') { if (p >= m || s[p] != u[i]) ok = NO; p++; i++; } i++; continue; }
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) { if (p >= m || s[p] != c) ok = NO; p++; i++; continue; }
        NSUInteger k = 1; while (i + k < n && u[i + k] == c) k++;
        long v = 0; NSUInteger digits = 0;
        #define NUM(maxd) do { v = 0; digits = 0; BOOL neg = NO; if (c == 'y' && p < m && s[p] == '-') { neg = YES; p++; } \
            while (p < m && s[p] >= '0' && s[p] <= '9' && digits < (maxd)) { v = v * 10 + (s[p++] - '0'); digits++; } if (!digits) ok = NO; if (neg) v = -v; } while (0)
        switch (c) {
        case 'y': case 'u': case 'Y': NUM(k == 2 ? 2 : 9); y = k == 2 && digits == 2 ? 2000 + v : v; break;
        case 'M': case 'L':
            if (k >= 3) { NSArray *names = k >= 4 ? [cal monthSymbols] : [cal shortMonthSymbols]; BOOL found = NO;
                for (NSUInteger j = 0; j < 12 && !found; j++) { NSString *nm = names[j]; NSUInteger l = [nm length];
                    if (p + l <= m && [[NSString stringWithCharacters:s + p length:l] caseInsensitiveCompare:nm] == NSOrderedSame) { mo = (long)j + 1; p += l; found = YES; } }
                if (!found) ok = NO; }
            else { NUM(2); mo = v; } break;
        case 'd': NUM(2); d = v; break;
        case 'H': case 'k': NUM(2); h = v; break;
        case 'h': case 'K': NUM(2); h = v; ampm = YES; break;
        case 'm': NUM(2); mi = v; break;
        case 's': NUM(2); sec = v; break;
        case 'S': NUM(9); ns = v; while (digits < 9) { ns *= 10; digits++; } break;
        case 'a': if (p + 2 <= m) { pm = s[p] == 'P' || s[p] == 'p'; p += 2; ampm = YES; } else ok = NO; break;
        case 'E': case 'e': case 'c': while (p < m && ((s[p] >= 'a' && s[p] <= 'z') || (s[p] >= 'A' && s[p] <= 'Z'))) p++; break;
        case 'Z': case 'X': case 'x': case 'z': case 'O': {
            if (p < m && s[p] == 'Z') { p++; haveOff = YES; off = 0; break; }
            if (p + 3 <= m && (s[p] == 'G' || s[p] == 'U')) p += 3; /* GMT / UTC */
            if (p < m && (s[p] == '+' || s[p] == '-')) {
                int sign = s[p++] == '-' ? -1 : 1; long hh = 0, mm = 0; int dg = 0;
                while (p < m && isdigit(s[p]) && dg < 2) { hh = hh * 10 + (s[p++] - '0'); dg++; }
                if (p < m && s[p] == ':') p++;
                dg = 0; while (p < m && isdigit(s[p]) && dg < 2) { mm = mm * 10 + (s[p++] - '0'); dg++; }
                haveOff = YES; off = sign * (hh * 3600 + mm * 60);
            } else haveOff = YES;
            break;
        }
        default: break;
        }
        i += k;
    }
    BOOL full = ok && p == m;
    free(u); free(s);
    if (!full) return nil;
    if (ampm) { h %= 12; if (pm) h += 12; }
    if (haveOff) return date_of(1, y, mo, d, h, mi, sec, ns, [NSTimeZone timeZoneForSecondsFromGMT:off]);
    return date_of(1, y, mo, d, h, mi, sec, ns, tz);
}
@implementation NSDateFormatter { NSString *_fmt; NSDateFormatterStyle _ds, _ts; NSLocale *_loc; NSTimeZone *_tz; NSCalendar *_cal; NSDate *_two, *_def; BOOL _lenient, _rel, _gen; }
/* the calendar's names (ponytail: English for every locale, like the styles below) */
#define SYM(n) - (NSArray *)n { return [(_cal ?: [NSCalendar currentCalendar]) n]; } - (void)set##n:(NSArray *)a { }
SYM(monthSymbols) SYM(shortMonthSymbols) SYM(veryShortMonthSymbols) SYM(standaloneMonthSymbols) SYM(shortStandaloneMonthSymbols)
SYM(veryShortStandaloneMonthSymbols) SYM(weekdaySymbols) SYM(shortWeekdaySymbols) SYM(veryShortWeekdaySymbols) SYM(standaloneWeekdaySymbols)
SYM(shortStandaloneWeekdaySymbols) SYM(veryShortStandaloneWeekdaySymbols) SYM(eraSymbols) SYM(longEraSymbols) SYM(quarterSymbols) SYM(shortQuarterSymbols)
#undef SYM
- (NSString *)AMSymbol { return @"AM"; } - (NSString *)PMSymbol { return @"PM"; }
- (NSInteger)formattingContext { return 0; } - (void)setFormattingContext:(NSInteger)c { }
- (void)dealloc { [_fmt release]; [_loc release]; [_tz release]; [_cal release]; [_two release]; [_def release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSDateFormatter *f = [[NSDateFormatter alloc] init]; [f setDateFormat:_fmt]; [f setLocale:_loc]; [f setTimeZone:_tz]; f->_ds = _ds; f->_ts = _ts; return f; }
static NSString *style_format(NSDateFormatterStyle ds, NSDateFormatterStyle ts) {
    static NSString *const d[] = {@"", @"M/d/yy", @"MMM d, y", @"MMMM d, y", @"EEEE, MMMM d, y"};
    static NSString *const t[] = {@"", @"h:mm a", @"h:mm:ss a", @"h:mm:ss a z", @"h:mm:ss a zzzz"};
    if (ds && ts) return [NSString stringWithFormat:@"%@, %@", d[ds], t[ts]];
    return ds ? d[ds] : t[ts];
}
- (NSString *)dateFormat { return _fmt ? _fmt : style_format(_ds, _ts); }
- (void)setDateFormat:(NSString *)f { [_fmt release]; _fmt = [f copy]; }
- (NSDateFormatterStyle)dateStyle { return _ds; } - (void)setDateStyle:(NSDateFormatterStyle)s { _ds = s; [_fmt release]; _fmt = nil; }
- (NSDateFormatterStyle)timeStyle { return _ts; } - (void)setTimeStyle:(NSDateFormatterStyle)s { _ts = s; [_fmt release]; _fmt = nil; }
- (NSLocale *)locale { return _loc ? _loc : [NSLocale currentLocale]; } - (void)setLocale:(NSLocale *)l { [_loc release]; _loc = [l retain]; }
- (NSTimeZone *)timeZone { return _tz ? _tz : [NSTimeZone defaultTimeZone]; } - (void)setTimeZone:(NSTimeZone *)t { [_tz release]; _tz = [t retain]; }
- (NSCalendar *)calendar { if (!_cal) _cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; return _cal; }
- (void)setCalendar:(NSCalendar *)c { [_cal release]; _cal = [c copy]; }
- (BOOL)generatesCalendarDates { return _gen; } - (void)setGeneratesCalendarDates:(BOOL)b { _gen = b; }
- (BOOL)lenient { return _lenient; } - (void)setLenient:(BOOL)b { _lenient = b; }
- (BOOL)doesRelativeDateFormatting { return _rel; } - (void)setDoesRelativeDateFormatting:(BOOL)b { _rel = b; }
- (NSDate *)twoDigitStartDate { return _two; } - (void)setTwoDigitStartDate:(NSDate *)d { [_two release]; _two = [d copy]; }
- (NSDate *)defaultDate { return _def; } - (void)setDefaultDate:(NSDate *)d { [_def release]; _def = [d copy]; }
- (NSString *)stringFromDate:(NSDate *)d { return d ? format_date([self dateFormat], d, [self timeZone], [self calendar]) : nil; }
- (NSDate *)dateFromString:(NSString *)s { return s ? parse_date([self dateFormat], s, [self timeZone], [self calendar]) : nil; }
- (NSString *)stringForObjectValue:(id)o { return [o isKindOfClass:[NSDate class]] ? [self stringFromDate:o] : nil; }
+ (NSString *)localizedStringFromDate:(NSDate *)d dateStyle:(NSDateFormatterStyle)ds timeStyle:(NSDateFormatterStyle)ts {
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateStyle:ds]; [f setTimeStyle:ts]; return [f stringFromDate:d];
}
/* a skeleton ("dMMM", "EEEEdMMMMy", "jmm") to a pattern for the locale. ponytail: two orders (US "MMM d, y" and the
   day-first one most locales use) and 12/24 h by locale; the full CLDR tables when an app needs them */
+ (NSString *)dateFormatFromTemplate:(NSString *)t options:(NSUInteger)o locale:(NSLocale *)l {
    NSString *loc = [(l ?: [NSLocale currentLocale]) localeIdentifier] ?: @"";
    BOOL us = [loc hasPrefix:@"en_US"] || [loc isEqualToString:@"en"], h12 = us || [loc hasPrefix:@"en_AU"] || [loc hasPrefix:@"en_CA"];
    NSMutableDictionary *tok = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < t.length;) {
        unichar c = [t characterAtIndex:i]; NSUInteger j = i;
        while (j < t.length && [t characterAtIndex:j] == c) j++;
        tok[[NSString stringWithCharacters:&c length:1]] = [t substringWithRange:NSMakeRange(i, j - i)];
        i = j;
    }
    NSMutableArray *date = [NSMutableArray array];
    NSString *E = tok[@"E"] ?: tok[@"c"], *d = tok[@"d"], *M = tok[@"M"] ?: tok[@"L"], *y = tok[@"y"];
    if (us) { if (M) [date addObject:M]; if (d) [date addObject:d]; }
    else { if (d) [date addObject:d]; if (M) [date addObject:M]; }
    NSString *ds = [date componentsJoinedByString:(M && M.length <= 2 ? (us ? @"/" : @"/") : @" ")];
    if (y) ds = ds.length ? [NSString stringWithFormat:(us && M.length > 2 ? @"%@, %@" : M.length <= 2 ? @"%@/%@" : @"%@ %@"), ds, y] : y;
    if (E) ds = ds.length ? [NSString stringWithFormat:@"%@, %@", E, ds] : E;
    NSString *hour = tok[@"j"] ?: tok[@"h"] ?: tok[@"H"] ?: tok[@"k"] ?: tok[@"K"], *time = nil;
    if (hour) {
        BOOL twelve = tok[@"h"] || tok[@"K"] || (tok[@"j"] && h12);
        NSString *hp = twelve ? (hour.length > 1 ? @"hh" : @"h") : (hour.length > 1 ? @"HH" : @"H");
        time = tok[@"m"] ? [NSString stringWithFormat:@"%@:%@", hp, tok[@"m"]] : hp;
        if (tok[@"s"]) time = [time stringByAppendingFormat:@":%@", tok[@"s"]];
        if (twelve) time = [time stringByAppendingString:@" a"];
    } else if (tok[@"m"]) time = tok[@"s"] ? [NSString stringWithFormat:@"%@:%@", tok[@"m"], tok[@"s"]] : tok[@"m"];
    if (ds.length && time) return [NSString stringWithFormat:@"%@ %@", ds, time];
    return ds.length ? ds : time ?: t;
}
- (void)setLocalizedDateFormatFromTemplate:(NSString *)t { [self setDateFormat:[NSDateFormatter dateFormatFromTemplate:t options:0 locale:_loc]]; }
@end
@implementation NSISO8601DateFormatter { NSTimeZone *_tz; NSISO8601DateFormatOptions _opt; }
- (instancetype)init { _opt = NSISO8601DateFormatWithInternetDateTime; _tz = [[NSTimeZone timeZoneForSecondsFromGMT:0] retain]; return self; }
- (void)dealloc { [_tz release]; [super dealloc]; }
- (NSTimeZone *)timeZone { return _tz; } - (void)setTimeZone:(NSTimeZone *)t { [_tz release]; _tz = [(t ? t : [NSTimeZone timeZoneForSecondsFromGMT:0]) retain]; }
- (NSISO8601DateFormatOptions)formatOptions { return _opt; } - (void)setFormatOptions:(NSISO8601DateFormatOptions)o { _opt = o; }
static NSString *iso_pattern(NSISO8601DateFormatOptions o) {
    NSMutableString *p = [NSMutableString string]; BOOL dash = (o & NSISO8601DateFormatWithDashSeparatorInDate) != 0, colon = (o & NSISO8601DateFormatWithColonSeparatorInTime) != 0;
    if (o & NSISO8601DateFormatWithYear) [p appendString:(o & NSISO8601DateFormatWithWeekOfYear) ? @"YYYY" : @"yyyy"];
    if (o & NSISO8601DateFormatWithMonth) [p appendString:dash ? @"-MM" : @"MM"];
    if (o & NSISO8601DateFormatWithWeekOfYear) [p appendString:dash ? @"-'W'ww" : @"'W'ww"];
    if (o & NSISO8601DateFormatWithDay) [p appendString:(o & NSISO8601DateFormatWithWeekOfYear) ? (dash ? @"-ee" : @"ee") : (o & NSISO8601DateFormatWithMonth) ? (dash ? @"-dd" : @"dd") : (dash ? @"-DDD" : @"DDD")];
    if ((o & NSISO8601DateFormatWithTime) && [p length]) [p appendString:(o & NSISO8601DateFormatWithSpaceBetweenDateAndTime) ? @" " : @"'T'"];
    if (o & NSISO8601DateFormatWithTime) [p appendString:colon ? @"HH:mm:ss" : @"HHmmss"];
    if ((o & NSISO8601DateFormatWithTime) && (o & NSISO8601DateFormatWithFractionalSeconds)) [p appendString:@".SSS"];
    if (o & NSISO8601DateFormatWithTimeZone) [p appendString:(o & NSISO8601DateFormatWithColonSeparatorInTimeZone) ? @"XXXXX" : @"XXXX"];
    return p;
}
- (NSString *)stringFromDate:(NSDate *)d { return [NSISO8601DateFormatter stringFromDate:d timeZone:_tz formatOptions:_opt]; }
- (NSDate *)dateFromString:(NSString *)s {
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601];
    return parse_date(iso_pattern(_opt), s, _tz, cal);
}
- (NSString *)stringForObjectValue:(id)o { return [o isKindOfClass:[NSDate class]] ? [self stringFromDate:o] : nil; }
+ (NSString *)stringFromDate:(NSDate *)d timeZone:(NSTimeZone *)tz formatOptions:(NSISO8601DateFormatOptions)o {
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601];
    return format_date(iso_pattern(o), d, tz, cal);
}
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

/* ======================================================================= URL components and query items */
/* percent-encoding by code point: allowed BMP characters stay, everything else becomes %XX of its UTF-8 bytes */
static NSString *pct_encode(NSString *s, NSCharacterSet *allowed) {
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
static NSString *pct_decode(NSString *s) {
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
