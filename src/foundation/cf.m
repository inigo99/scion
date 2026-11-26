/* cf.m — more of CoreFoundation, on the toll-free bridged Foundation objects: mutable arrays and dictionaries, preferences,
 * UUIDs, encodings, bundle info, Uniform Type Identifiers, and the CFString constants of the C frameworks stubbed in
 * libSystem (stubs.c). Callback structs are accepted and ignored: CF collections here always retain like NS ones. */
#include "internal.h"
#undef kCFAllocatorDefault
#undef CFSTR
#define CFSTR(s) ((CFStringRef)@s)

NSStringEncoding ns_encoding(CFStringEncoding e); /* swift.m */
const CFAllocatorRef kCFAllocatorDefault = 0;
const double kCFCoreFoundationVersionNumber = 1953.3; /* macOS 13-era */
const CFStringRef kCFBundleIdentifierKey = CFSTR("CFBundleIdentifier"), kCFBundleNameKey = CFSTR("CFBundleName"),
    kCFBundleVersionKey = CFSTR("CFBundleVersion"), kCFBundleExecutableKey = CFSTR("CFBundleExecutable"),
    kCFBundleInfoDictionaryVersionKey = CFSTR("CFBundleInfoDictionaryVersion"), kCFBundleDevelopmentRegionKey = CFSTR("CFBundleDevelopmentRegion");
const CFStringRef kCFPreferencesAnyApplication = CFSTR("kCFPreferencesAnyApplication"), kCFPreferencesCurrentApplication = CFSTR("kCFPreferencesCurrentApplication"),
    kCFPreferencesAnyHost = CFSTR("kCFPreferencesAnyHost"), kCFPreferencesCurrentHost = CFSTR("kCFPreferencesCurrentHost"),
    kCFPreferencesAnyUser = CFSTR("kCFPreferencesAnyUser"), kCFPreferencesCurrentUser = CFSTR("kCFPreferencesCurrentUser");
typedef struct { CFIndex version; const void *retain, *release, *copyDescription, *equal, *hash; } mw_cb;
const mw_cb kCFTypeDictionaryKeyCallBacks = {0, (void *)1, (void *)1, (void *)1, (void *)1, (void *)1},
    kCFCopyStringDictionaryKeyCallBacks = {0, (void *)1, (void *)1, (void *)1, (void *)1, (void *)1},
    kCFTypeDictionaryValueCallBacks = {0, (void *)1, (void *)1, (void *)1, (void *)1, 0},
    kCFTypeArrayCallBacks = {0, (void *)1, (void *)1, (void *)1, (void *)1, 0},
    kCFTypeSetCallBacks = {0, (void *)1, (void *)1, (void *)1, (void *)1, (void *)1};

/* ---------------- arrays ---------------- */
CFMutableArrayRef CFArrayCreateMutable(CFAllocatorRef a, CFIndex cap, const void *cb) { return (CFMutableArrayRef)[[NSMutableArray alloc] init]; }
CFArrayRef CFArrayCreate(CFAllocatorRef a, const void **v, CFIndex n, const void *cb) { return (CFArrayRef)[[NSArray alloc] initWithObjects:(id *)v count:(NSUInteger)n]; }
CFMutableArrayRef CFArrayCreateMutableCopy(CFAllocatorRef a, CFIndex cap, CFArrayRef s) { return (CFMutableArrayRef)[(NSArray *)s mutableCopy]; }
const void *CFArrayGetValueAtIndex(CFArrayRef a, CFIndex i) { return [(NSArray *)a objectAtIndex:(NSUInteger)i]; }
void CFArrayGetValues(CFArrayRef a, CFRange r, const void **v) { [(NSArray *)a getObjects:(id *)v range:NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length)]; }
void CFArrayAppendValue(CFMutableArrayRef a, const void *v) { [(NSMutableArray *)a addObject:(id)v]; }
void CFArrayInsertValueAtIndex(CFMutableArrayRef a, CFIndex i, const void *v) { [(NSMutableArray *)a insertObject:(id)v atIndex:(NSUInteger)i]; }
void CFArraySetValueAtIndex(CFMutableArrayRef a, CFIndex i, const void *v) {
    if ((NSUInteger)i == [(NSArray *)a count]) [(NSMutableArray *)a addObject:(id)v]; else [(NSMutableArray *)a replaceObjectAtIndex:(NSUInteger)i withObject:(id)v];
}
void CFArrayRemoveValueAtIndex(CFMutableArrayRef a, CFIndex i) { [(NSMutableArray *)a removeObjectAtIndex:(NSUInteger)i]; }
void CFArrayRemoveAllValues(CFMutableArrayRef a) { [(NSMutableArray *)a removeAllObjects]; }
void CFArrayAppendArray(CFMutableArrayRef a, CFArrayRef o, CFRange r) {
    [(NSMutableArray *)a addObjectsFromArray:[(NSArray *)o subarrayWithRange:NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length)]];
}
void CFArrayReplaceValues(CFMutableArrayRef a, CFRange r, const void **v, CFIndex n) {
    [(NSMutableArray *)a replaceObjectsInRange:NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length) withObjectsFromArray:[NSArray arrayWithObjects:(id *)v count:(NSUInteger)n]];
}
Boolean CFArrayContainsValue(CFArrayRef a, CFRange r, const void *v) {
    return [[(NSArray *)a subarrayWithRange:NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length)] containsObject:(id)v];
}
CFIndex CFArrayGetFirstIndexOfValue(CFArrayRef a, CFRange r, const void *v) {
    for (CFIndex i = r.location; i < r.location + r.length; i++) if ([[(NSArray *)a objectAtIndex:(NSUInteger)i] isEqual:(id)v]) return i;
    return -1;
}
typedef CFComparisonResult (*CFComparatorFunction)(const void *, const void *, void *);
/* where v would be inserted to keep the range sorted (CF's documented result) */
CFIndex CFArrayBSearchValues(CFArrayRef a, CFRange r, const void *v, CFComparatorFunction cmp, void *ctx) {
    CFIndex lo = r.location, hi = r.location + r.length;
    while (lo < hi) { CFIndex m = lo + (hi - lo) / 2; if (cmp([(NSArray *)a objectAtIndex:(NSUInteger)m], v, ctx) < 0) lo = m + 1; else hi = m; }
    return lo;
}
void CFArraySortValues(CFMutableArrayRef a, CFRange r, CFComparatorFunction cmp, void *ctx) {
    NSMutableArray *m = (NSMutableArray *)a;
    NSRange nr = NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length);
    NSArray *s = [[m subarrayWithRange:nr] sortedArrayUsingComparator:^NSComparisonResult(id x, id y) { return (NSComparisonResult)cmp(x, y, ctx); }];
    [m replaceObjectsInRange:nr withObjectsFromArray:s];
}

/* ---------------- dictionaries ---------------- */
CFMutableDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef a, CFIndex cap, const void *kcb, const void *vcb) { return (CFMutableDictionaryRef)[[NSMutableDictionary alloc] init]; }
CFDictionaryRef CFDictionaryCreate(CFAllocatorRef a, const void **k, const void **v, CFIndex n, const void *kcb, const void *vcb) {
    return (CFDictionaryRef)[[NSDictionary alloc] initWithObjects:(id *)v forKeys:(id *)k count:(NSUInteger)n];
}
CFMutableDictionaryRef CFDictionaryCreateMutableCopy(CFAllocatorRef a, CFIndex cap, CFDictionaryRef d) { return (CFMutableDictionaryRef)[(NSDictionary *)d mutableCopy]; }
const void *CFDictionaryGetValue(CFDictionaryRef d, const void *k) { return k ? [(NSDictionary *)d objectForKey:(id)k] : NULL; }
Boolean CFDictionaryGetValueIfPresent(CFDictionaryRef d, const void *k, const void **v) {
    id o = k ? [(NSDictionary *)d objectForKey:(id)k] : nil;
    if (o && v) *v = o;
    return o != nil;
}
Boolean CFDictionaryContainsKey(CFDictionaryRef d, const void *k) { return k && [(NSDictionary *)d objectForKey:(id)k] != nil; }
void CFDictionarySetValue(CFMutableDictionaryRef d, const void *k, const void *v) { if (k && v) [(NSMutableDictionary *)d setObject:(id)v forKey:(id)k]; else if (k) [(NSMutableDictionary *)d removeObjectForKey:(id)k]; }
void CFDictionaryAddValue(CFMutableDictionaryRef d, const void *k, const void *v) { if (k && v && ![(NSDictionary *)d objectForKey:(id)k]) [(NSMutableDictionary *)d setObject:(id)v forKey:(id)k]; }
void CFDictionaryReplaceValue(CFMutableDictionaryRef d, const void *k, const void *v) { if (k && v && [(NSDictionary *)d objectForKey:(id)k]) [(NSMutableDictionary *)d setObject:(id)v forKey:(id)k]; }
void CFDictionaryRemoveValue(CFMutableDictionaryRef d, const void *k) { if (k) [(NSMutableDictionary *)d removeObjectForKey:(id)k]; }
void CFDictionaryRemoveAllValues(CFMutableDictionaryRef d) { [(NSMutableDictionary *)d removeAllObjects]; }
void CFDictionaryGetKeysAndValues(CFDictionaryRef d, const void **k, const void **v) {
    NSUInteger i = 0;
    for (id key in (NSDictionary *)d) { if (k) k[i] = key; if (v) v[i] = [(NSDictionary *)d objectForKey:key]; i++; }
}

/* ---------------- strings, encodings, URLs, UUIDs ---------------- */
CFStringEncoding CFStringConvertNSStringEncodingToEncoding(NSStringEncoding e) {
    switch (e) {
    case NSASCIIStringEncoding: return kCFStringEncodingASCII;
    case NSUTF8StringEncoding: return kCFStringEncodingUTF8;
    case NSISOLatin1StringEncoding: return kCFStringEncodingISOLatin1;
    case NSWindowsCP1252StringEncoding: return kCFStringEncodingWindowsLatin1;
    case NSMacOSRomanStringEncoding: return kCFStringEncodingMacRoman;
    case NSNEXTSTEPStringEncoding: return kCFStringEncodingNextStepLatin;
    case NSNonLossyASCIIStringEncoding: return kCFStringEncodingNonLossyASCII;
    case NSUTF16StringEncoding: return kCFStringEncodingUTF16;
    case NSUTF16BigEndianStringEncoding: return kCFStringEncodingUTF16BE;
    case NSUTF16LittleEndianStringEncoding: return kCFStringEncodingUTF16LE;
    case NSUTF32StringEncoding: return kCFStringEncodingUTF32;
    case NSUTF32BigEndianStringEncoding: return kCFStringEncodingUTF32BE;
    case NSUTF32LittleEndianStringEncoding: return kCFStringEncodingUTF32LE;
    case NSISOLatin2StringEncoding: return 0x0202; case NSWindowsCP1250StringEncoding: return 0x0501; case NSWindowsCP1251StringEncoding: return 0x0502;
    case NSWindowsCP1253StringEncoding: return 0x0503; case NSWindowsCP1254StringEncoding: return 0x0504; case NSShiftJISStringEncoding: return 0x0A01;
    case NSJapaneseEUCStringEncoding: return 0x0920; case NSISO2022JPStringEncoding: return 0x0820; case NSSymbolStringEncoding: return 33;
    }
    return (e & 0x80000000u) ? (CFStringEncoding)(e & 0x7fffffffu) : 0xffffffffu; /* kCFStringEncodingInvalidId */
}
NSStringEncoding CFStringConvertEncodingToNSStringEncoding(CFStringEncoding e) {
    switch (e) {
    case kCFStringEncodingMacRoman: return NSMacOSRomanStringEncoding;
    case kCFStringEncodingWindowsLatin1: return NSWindowsCP1252StringEncoding;
    case kCFStringEncodingNextStepLatin: return NSNEXTSTEPStringEncoding;
    case kCFStringEncodingNonLossyASCII: return NSNonLossyASCIIStringEncoding;
    case kCFStringEncodingUTF16BE: return NSUTF16BigEndianStringEncoding;
    case kCFStringEncodingUTF32: return NSUTF32StringEncoding;
    case kCFStringEncodingUTF32BE: return NSUTF32BigEndianStringEncoding;
    case kCFStringEncodingUTF32LE: return NSUTF32LittleEndianStringEncoding;
    case 0x0202: return NSISOLatin2StringEncoding; case 0x0501: return NSWindowsCP1250StringEncoding; case 0x0502: return NSWindowsCP1251StringEncoding;
    case 0x0503: return NSWindowsCP1253StringEncoding; case 0x0504: return NSWindowsCP1254StringEncoding; case 0x0A01: return NSShiftJISStringEncoding;
    case 0x0920: return NSJapaneseEUCStringEncoding; case 0x0820: return NSISO2022JPStringEncoding; case 33: return NSSymbolStringEncoding;
    case kCFStringEncodingASCII: case kCFStringEncodingUTF8: case kCFStringEncodingISOLatin1: case kCFStringEncodingUTF16: case kCFStringEncodingUTF16LE:
        return ns_encoding(e);
    }
    return 0x80000000u | e;
}
CFStringRef CFStringGetNameOfEncoding(CFStringEncoding e) { return (CFStringRef)[NSString localizedNameOfStringEncoding:CFStringConvertEncodingToNSStringEncoding(e)]; }
const char *CFStringGetCStringPtr(CFStringRef s, CFStringEncoding e) { return NULL; } /* allowed: callers fall back to CFStringGetCString */
Boolean CFStringGetCString(CFStringRef s, char *buf, CFIndex n, CFStringEncoding e) {
    return [(NSString *)s getCString:buf maxLength:(NSUInteger)n encoding:ns_encoding(e)];
}
Boolean CFStringGetFileSystemRepresentation(CFStringRef s, char *buf, CFIndex n) { return [(NSString *)s getFileSystemRepresentation:buf maxLength:(NSUInteger)n]; }
Boolean CFURLGetFileSystemRepresentation(CFURLRef u, Boolean resolve, UInt8 *buf, CFIndex n) {
    NSString *p = [(NSURL *)u path];
    return p && [p getFileSystemRepresentation:(char *)buf maxLength:(NSUInteger)n];
}
const void *CFUUIDCreate(CFAllocatorRef a) { return [[NSUUID alloc] init]; } /* CFUUIDRef: only CFUUIDCreateString reads it */
CFStringRef CFUUIDCreateString(CFAllocatorRef a, const void *u) { return (CFStringRef)[[(NSUUID *)u UUIDString] copy]; }

/* ---------------- bundles and preferences ---------------- */
CFDictionaryRef CFBundleCopyInfoDictionaryInDirectory(CFURLRef url) {
    NSString *d = [(NSURL *)url path];
    for (NSString *p in @[@"Contents/Info.plist", @"Resources/Info.plist", @"Info.plist"]) {
        NSDictionary *i = [NSDictionary dictionaryWithContentsOfFile:[d stringByAppendingPathComponent:p]];
        if (i) return (CFDictionaryRef)[i retain];
    }
    return NULL;
}
static NSUserDefaults *prefs_for(CFStringRef app) {
    if (!app || [(NSString *)app isEqualToString:(NSString *)kCFPreferencesCurrentApplication] || [(NSString *)app isEqualToString:[[NSBundle mainBundle] bundleIdentifier]])
        return [NSUserDefaults standardUserDefaults];
    return [[[NSUserDefaults alloc] initWithSuiteName:(NSString *)app] autorelease];
}
const void *CFPreferencesCopyAppValue(CFStringRef k, CFStringRef app) { return [[prefs_for(app) objectForKey:(NSString *)k] retain]; }
Boolean CFPreferencesGetAppBooleanValue(CFStringRef k, CFStringRef app, Boolean *ok) {
    id v = [prefs_for(app) objectForKey:(NSString *)k];
    if (ok) *ok = v != nil;
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}
CFIndex CFPreferencesGetAppIntegerValue(CFStringRef k, CFStringRef app, Boolean *ok) {
    id v = [prefs_for(app) objectForKey:(NSString *)k];
    if (ok) *ok = v != nil;
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}
void CFPreferencesSetAppValue(CFStringRef k, const void *v, CFStringRef app) { [prefs_for(app) setObject:(id)v forKey:(NSString *)k]; }
void CFPreferencesSetValue(CFStringRef k, const void *v, CFStringRef app, CFStringRef user, CFStringRef host) { CFPreferencesSetAppValue(k, v, app); }
const void *CFPreferencesCopyValue(CFStringRef k, CFStringRef app, CFStringRef user, CFStringRef host) { return CFPreferencesCopyAppValue(k, app); }
Boolean CFPreferencesAppSynchronize(CFStringRef app) { return [prefs_for(app) synchronize]; }
Boolean CFPreferencesSynchronize(CFStringRef app, CFStringRef user, CFStringRef host) { return [prefs_for(app) synchronize]; }

/* seconds since 1904 (Carbon UTCDateTime seconds) to CFAbsoluteTime */
int32_t UCConvertSecondsToCFAbsoluteTime(uint32_t secs, CFAbsoluteTime *t) { if (t) *t = (double)secs - 3061152000.0; return 0; }

/* ---------------- Uniform Type Identifiers (the old CoreServices calls) ---------------- */
const CFStringRef kUTTagClassFilenameExtension = CFSTR("public.filename-extension"), kUTTagClassMIMEType = CFSTR("public.mime-type");
const CFStringRef kUTTypeItem = CFSTR("public.item"), kUTTypeData = CFSTR("public.data"), kUTTypeContent = CFSTR("public.content"),
    kUTTypeText = CFSTR("public.text"), kUTTypePlainText = CFSTR("public.plain-text"), kUTTypeUTF8PlainText = CFSTR("public.utf8-plain-text"),
    kUTTypeURL = CFSTR("public.url"), kUTTypeFileURL = CFSTR("public.file-url"), kUTTypeImage = CFSTR("public.image"),
    kUTTypePNG = CFSTR("public.png"), kUTTypeJPEG = CFSTR("public.jpeg"), kUTTypeTIFF = CFSTR("public.tiff"), kUTTypePDF = CFSTR("com.adobe.pdf"),
    kUTTypeFolder = CFSTR("public.folder"), kUTTypeDirectory = CFSTR("public.directory"), kUTTypeVolume = CFSTR("public.volume"),
    kUTTypePackage = CFSTR("com.apple.package"), kUTTypeBundle = CFSTR("com.apple.bundle"), kUTTypeApplication = CFSTR("com.apple.application"),
    kUTTypeApplicationBundle = CFSTR("com.apple.application-bundle"), kUTTypeExecutable = CFSTR("public.executable"),
    kUTTypeSymLink = CFSTR("public.symlink"), kUTTypeArchive = CFSTR("public.archive"), kUTTypeDiskImage = CFSTR("public.disk-image"),
    kUTTypeJSON = CFSTR("public.json"), kUTTypeXML = CFSTR("public.xml"), kUTTypeSourceCode = CFSTR("public.source-code");
Boolean UTTypeEqual(CFStringRef a, CFStringRef b) { return a && b && [(NSString *)a isEqualToString:(NSString *)b]; }
/* ponytail: a small built-in hierarchy (everything is public.item; files are public.data; texts and images are content) */
Boolean UTTypeConformsTo(CFStringRef a, CFStringRef b) {
    if (!a || !b) return false;
    NSString *t = (NSString *)a, *u = (NSString *)b;
    if ([t isEqualToString:u] || [u isEqualToString:@"public.item"]) return true;
    static NSDictionary *parent;
    if (!parent) parent = [@{@"public.plain-text": @"public.text", @"public.utf8-plain-text": @"public.plain-text", @"public.text": @"public.data",
        @"public.source-code": @"public.plain-text", @"public.json": @"public.text", @"public.xml": @"public.text", @"public.png": @"public.image",
        @"public.jpeg": @"public.image", @"public.tiff": @"public.image", @"public.image": @"public.data", @"com.adobe.pdf": @"public.data",
        @"public.folder": @"public.directory", @"com.apple.package": @"public.directory", @"com.apple.bundle": @"public.directory",
        @"com.apple.application-bundle": @"com.apple.application", @"com.apple.application": @"com.apple.bundle", @"public.archive": @"public.data",
        @"public.disk-image": @"public.archive", @"public.executable": @"public.data", @"public.file-url": @"public.url", @"public.url": @"public.data"} retain];
    for (NSString *p = parent[t]; p; p = parent[p]) if ([p isEqualToString:u]) return true;
    return false;
}
CFStringRef UTTypeCreatePreferredIdentifierForTag(CFStringRef tagClass, CFStringRef tag, CFStringRef conforming) {
    static NSDictionary *ext;
    if (!ext) ext = [@{@"txt": @"public.plain-text", @"text": @"public.plain-text", @"png": @"public.png", @"jpg": @"public.jpeg", @"jpeg": @"public.jpeg",
        @"tif": @"public.tiff", @"tiff": @"public.tiff", @"pdf": @"com.adobe.pdf", @"json": @"public.json", @"xml": @"public.xml", @"app": @"com.apple.application-bundle"} retain];
    NSString *u = ext[[(NSString *)tag lowercaseString]];
    return (CFStringRef)[(u ?: [@"dyn.ah62d4rv4ge8" stringByAppendingString:(NSString *)tag]) copy];
}

/* ---------------- CFString constants of the C frameworks in stubs.c ---------------- */
const CFStringRef kDADiskDescriptionBusNameKey = CFSTR("DABusName"), kDADiskDescriptionMediaBSDNameKey = CFSTR("DAMediaBSDName"),
    kDADiskDescriptionMediaNameKey = CFSTR("DAMediaName"), kDADiskDescriptionMediaWholeKey = CFSTR("DAMediaWhole"),
    kDADiskDescriptionVolumeNameKey = CFSTR("DAVolumeName"), kDADiskDescriptionVolumeNetworkKey = CFSTR("DAVolumeNetwork"),
    kDADiskDescriptionMediaSizeKey = CFSTR("DAMediaSize");
const CFStringRef kSMDomainSystemLaunchd = CFSTR("kSMDomainSystemLaunchd"), kSMDomainUserLaunchd = CFSTR("kSMDomainUserLaunchd");
const CFStringRef kSecDigestSHA1 = CFSTR("SHA1"), kSecDigestSHA2 = CFSTR("SHA2"), kSecTransformInputAttributeName = CFSTR("INPUT"),
    kSecTransformOutputAttributeName = CFSTR("OUTPUT");

/* ---------------- attributed strings (NSAttributedString; CoreText lays them out) ---------------- */
#define AS(x) ((NSAttributedString *)(x))
#define MAS(x) ((NSMutableAttributedString *)(x))
static NSRange ns_range(CFRange r) { return NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length); }
static void out_range(CFRange *eff, NSRange r) { if (eff) *eff = (CFRange){(CFIndex)r.location, (CFIndex)r.length}; }
CFAttributedStringRef CFAttributedStringCreate(CFAllocatorRef a, CFStringRef s, CFDictionaryRef attrs) {
    return (CFAttributedStringRef)[[NSAttributedString alloc] initWithString:(NSString *)s attributes:(NSDictionary *)attrs];
}
CFAttributedStringRef CFAttributedStringCreateCopy(CFAllocatorRef a, CFAttributedStringRef s) { return (CFAttributedStringRef)[AS(s) copy]; }
CFAttributedStringRef CFAttributedStringCreateWithSubstring(CFAllocatorRef a, CFAttributedStringRef s, CFRange r) {
    return (CFAttributedStringRef)[[AS(s) attributedSubstringFromRange:ns_range(r)] copy];
}
CFMutableAttributedStringRef CFAttributedStringCreateMutable(CFAllocatorRef a, CFIndex max) { return (CFMutableAttributedStringRef)[[NSMutableAttributedString alloc] init]; }
CFMutableAttributedStringRef CFAttributedStringCreateMutableCopy(CFAllocatorRef a, CFIndex max, CFAttributedStringRef s) { return (CFMutableAttributedStringRef)[AS(s) mutableCopy]; }
CFIndex CFAttributedStringGetLength(CFAttributedStringRef s) { return (CFIndex)[AS(s) length]; }
CFStringRef CFAttributedStringGetString(CFAttributedStringRef s) { return (CFStringRef)[AS(s) string]; }
CFDictionaryRef CFAttributedStringGetAttributes(CFAttributedStringRef s, CFIndex i, CFRange *eff) {
    NSRange r; NSDictionary *d = [AS(s) attributesAtIndex:(NSUInteger)i effectiveRange:&r];
    out_range(eff, r);
    return (CFDictionaryRef)d;
}
CFTypeRef CFAttributedStringGetAttribute(CFAttributedStringRef s, CFIndex i, CFStringRef name, CFRange *eff) {
    NSRange r; id v = [AS(s) attribute:(NSString *)name atIndex:(NSUInteger)i effectiveRange:&r];
    out_range(eff, r);
    return v;
}
CFDictionaryRef CFAttributedStringGetAttributesAndLongestEffectiveRange(CFAttributedStringRef s, CFIndex i, CFRange in, CFRange *eff) {
    NSRange r; NSDictionary *d = [AS(s) attributesAtIndex:(NSUInteger)i longestEffectiveRange:&r inRange:ns_range(in)];
    out_range(eff, r);
    return (CFDictionaryRef)d;
}
void CFAttributedStringReplaceString(CFMutableAttributedStringRef s, CFRange r, CFStringRef str) { [MAS(s) replaceCharactersInRange:ns_range(r) withString:(NSString *)str]; }
CFMutableStringRef CFAttributedStringGetMutableString(CFMutableAttributedStringRef s) { return (CFMutableStringRef)[MAS(s) mutableString]; }
void CFAttributedStringSetAttributes(CFMutableAttributedStringRef s, CFRange r, CFDictionaryRef a, Boolean clear) {
    if (clear) [MAS(s) setAttributes:(NSDictionary *)a range:ns_range(r)]; else [MAS(s) addAttributes:(NSDictionary *)a range:ns_range(r)];
}
void CFAttributedStringSetAttribute(CFMutableAttributedStringRef s, CFRange r, CFStringRef name, CFTypeRef v) { [MAS(s) addAttribute:(NSString *)name value:(id)v range:ns_range(r)]; }
void CFAttributedStringRemoveAttribute(CFMutableAttributedStringRef s, CFRange r, CFStringRef name) { [MAS(s) removeAttribute:(NSString *)name range:ns_range(r)]; }
void CFAttributedStringReplaceAttributedString(CFMutableAttributedStringRef s, CFRange r, CFAttributedStringRef with) {
    [MAS(s) replaceCharactersInRange:ns_range(r) withAttributedString:AS(with)];
}
void CFAttributedStringBeginEditing(CFMutableAttributedStringRef s) { [MAS(s) beginEditing]; }
void CFAttributedStringEndEditing(CFMutableAttributedStringRef s) { [MAS(s) endEditing]; }
