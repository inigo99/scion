/* scion SDK — CoreText: fonts (a CTFontRef is an NSFont, a CTFontDescriptorRef an NSFontDescriptor), font registration,
 * and text layout (lines, runs, typesetters, framesetters, frames) on attributed strings. Implemented in AppKit.dylib
 * (dyld maps CoreText.framework to it). A glyph is the UTF-16 character it stands for. */
#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>

CF_EXTERN_C_BEGIN
#pragma clang arc_cf_code_audited begin
typedef const struct CF_BRIDGED_TYPE(id) __CTFont *CTFontRef;
typedef const struct CF_BRIDGED_TYPE(id) __CTFontDescriptor *CTFontDescriptorRef;
typedef const struct CF_BRIDGED_TYPE(id) __CTFontCollection *CTFontCollectionRef;
typedef const struct CF_BRIDGED_TYPE(id) __CTLine *CTLineRef;
typedef const struct CF_BRIDGED_TYPE(id) __CTRun *CTRunRef;
typedef const struct CF_BRIDGED_TYPE(id) __CTTypesetter *CTTypesetterRef;
typedef const struct CF_BRIDGED_TYPE(id) __CTFramesetter *CTFramesetterRef;
typedef const struct CF_BRIDGED_TYPE(id) __CTFrame *CTFrameRef;
typedef const struct CF_BRIDGED_TYPE(id) __CTParagraphStyle *CTParagraphStyleRef;
typedef const struct CF_BRIDGED_TYPE(id) __CTTextTab *CTTextTabRef;

/* ---------------------------------------------------------------- string attributes */
extern const CFStringRef kCTFontAttributeName, kCTForegroundColorAttributeName, kCTForegroundColorFromContextAttributeName,
    kCTBackgroundColorAttributeName, kCTParagraphStyleAttributeName, kCTKernAttributeName, kCTTrackingAttributeName,
    kCTUnderlineStyleAttributeName, kCTUnderlineColorAttributeName, kCTStrokeWidthAttributeName, kCTStrokeColorAttributeName,
    kCTLigatureAttributeName, kCTSuperscriptAttributeName, kCTBaselineOffsetAttributeName, kCTVerticalFormsAttributeName,
    kCTGlyphInfoAttributeName, kCTLanguageAttributeName, kCTWritingDirectionAttributeName;
typedef CF_OPTIONS(int32_t, CTUnderlineStyle) { kCTUnderlineStyleNone = 0, kCTUnderlineStyleSingle = 1, kCTUnderlineStyleThick = 2, kCTUnderlineStyleDouble = 9 };

/* ---------------------------------------------------------------- fonts */
typedef CF_OPTIONS(uint32_t, CTFontSymbolicTraits) {
    kCTFontTraitItalic = 1 << 0, kCTFontTraitBold = 1 << 1, kCTFontTraitExpanded = 1 << 5, kCTFontTraitCondensed = 1 << 6,
    kCTFontTraitMonoSpace = 1 << 10, kCTFontTraitVertical = 1 << 11, kCTFontTraitUIOptimized = 1 << 12,
    kCTFontTraitColorGlyphs = 1 << 13, kCTFontTraitComposite = 1 << 14, kCTFontTraitClassMask = 15U << 28,
};
typedef CF_ENUM(uint32_t, CTFontOrientation) { kCTFontOrientationDefault = 0, kCTFontOrientationHorizontal = 1, kCTFontOrientationVertical = 2 };
typedef CF_ENUM(uint32_t, CTFontUIFontType) {
    kCTFontUIFontNone = (uint32_t)-1, kCTFontUIFontUser = 0, kCTFontUIFontUserFixedPitch = 1, kCTFontUIFontSystem = 2,
    kCTFontUIFontEmphasizedSystem = 3, kCTFontUIFontSmallSystem = 4, kCTFontUIFontSmallEmphasizedSystem = 5,
    kCTFontUIFontMiniSystem = 6, kCTFontUIFontMiniEmphasizedSystem = 7, kCTFontUIFontViews = 8, kCTFontUIFontApplication = 9,
    kCTFontUIFontLabel = 10, kCTFontUIFontMenuTitle = 11, kCTFontUIFontMenuItem = 12, kCTFontUIFontMenuItemMark = 13,
    kCTFontUIFontMenuItemCmdKey = 14, kCTFontUIFontWindowTitle = 15, kCTFontUIFontPushButton = 16, kCTFontUIFontUtilityWindowTitle = 17,
    kCTFontUIFontAlertHeader = 18, kCTFontUIFontSystemDetail = 19, kCTFontUIFontEmphasizedSystemDetail = 20, kCTFontUIFontToolbar = 21,
    kCTFontUIFontSmallToolbar = 22, kCTFontUIFontMessage = 23, kCTFontUIFontPalette = 24, kCTFontUIFontToolTip = 25, kCTFontUIFontControlContent = 26,
};
extern const CFStringRef kCTFontNameAttribute, kCTFontDisplayNameAttribute, kCTFontFamilyNameAttribute, kCTFontStyleNameAttribute,
    kCTFontTraitsAttribute, kCTFontSizeAttribute, kCTFontMatrixAttribute, kCTFontURLAttribute, kCTFontFeatureSettingsAttribute,
    kCTFontSymbolicTrait, kCTFontWeightTrait, kCTFontWidthTrait, kCTFontSlantTrait,
    kCTFontCopyrightNameKey, kCTFontFamilyNameKey, kCTFontSubFamilyNameKey, kCTFontStyleNameKey, kCTFontUniqueNameKey,
    kCTFontFullNameKey, kCTFontVersionNameKey, kCTFontPostScriptNameKey;
CTFontRef CTFontCreateWithName(CFStringRef _Nullable name, CGFloat size, const CGAffineTransform *_Nullable matrix);
CTFontRef CTFontCreateWithNameAndOptions(CFStringRef name, CGFloat size, const CGAffineTransform *_Nullable matrix, CFOptionFlags options);
CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef d, CGFloat size, const CGAffineTransform *_Nullable matrix);
CTFontRef _Nullable CTFontCreateUIFontForLanguage(CTFontUIFontType type, CGFloat size, CFStringRef _Nullable language);
CTFontRef CTFontCreateCopyWithAttributes(CTFontRef f, CGFloat size, const CGAffineTransform *_Nullable matrix, CTFontDescriptorRef _Nullable attributes);
CTFontRef _Nullable CTFontCreateCopyWithSymbolicTraits(CTFontRef f, CGFloat size, const CGAffineTransform *_Nullable matrix, CTFontSymbolicTraits value, CTFontSymbolicTraits mask);
CTFontRef _Nullable CTFontCreateCopyWithFamily(CTFontRef f, CGFloat size, const CGAffineTransform *_Nullable matrix, CFStringRef family);
CTFontRef CTFontCreateForString(CTFontRef current, CFStringRef string, CFRange range);
CTFontDescriptorRef CTFontCopyFontDescriptor(CTFontRef f);
CFTypeRef _Nullable CTFontCopyAttribute(CTFontRef f, CFStringRef attribute);
CGFloat CTFontGetSize(CTFontRef f);
CGAffineTransform CTFontGetMatrix(CTFontRef f);
CTFontSymbolicTraits CTFontGetSymbolicTraits(CTFontRef f);
CFDictionaryRef CTFontCopyTraits(CTFontRef f);
CFStringRef CTFontCopyPostScriptName(CTFontRef f);
CFStringRef CTFontCopyFamilyName(CTFontRef f);
CFStringRef CTFontCopyFullName(CTFontRef f);
CFStringRef CTFontCopyDisplayName(CTFontRef f);
CFStringRef _Nullable CTFontCopyName(CTFontRef f, CFStringRef nameKey);
CFCharacterSetRef CTFontCopyCharacterSet(CTFontRef f);
CGFloat CTFontGetAscent(CTFontRef f); CGFloat CTFontGetDescent(CTFontRef f); CGFloat CTFontGetLeading(CTFontRef f);
unsigned CTFontGetUnitsPerEm(CTFontRef f); CFIndex CTFontGetGlyphCount(CTFontRef f);
CGRect CTFontGetBoundingBox(CTFontRef f);
CGFloat CTFontGetUnderlinePosition(CTFontRef f); CGFloat CTFontGetUnderlineThickness(CTFontRef f);
CGFloat CTFontGetSlantAngle(CTFontRef f); CGFloat CTFontGetCapHeight(CTFontRef f); CGFloat CTFontGetXHeight(CTFontRef f);
CGGlyph CTFontGetGlyphWithName(CTFontRef f, CFStringRef glyphName);
bool CTFontGetGlyphsForCharacters(CTFontRef f, const UniChar characters[], CGGlyph glyphs[], CFIndex count);
CGRect CTFontGetBoundingRectsForGlyphs(CTFontRef f, CTFontOrientation o, const CGGlyph glyphs[], CGRect *_Nullable rects, CFIndex count);
double CTFontGetAdvancesForGlyphs(CTFontRef f, CTFontOrientation o, const CGGlyph glyphs[], CGSize *_Nullable advances, CFIndex count);
CGPathRef _Nullable CTFontCreatePathForGlyph(CTFontRef f, CGGlyph glyph, const CGAffineTransform *_Nullable matrix);
void CTFontDrawGlyphs(CTFontRef f, const CGGlyph glyphs[], const CGPoint positions[], size_t count, CGContextRef c);

CTFontDescriptorRef CTFontDescriptorCreateWithNameAndSize(CFStringRef name, CGFloat size);
CTFontDescriptorRef CTFontDescriptorCreateWithAttributes(CFDictionaryRef attributes);
CTFontDescriptorRef CTFontDescriptorCreateCopyWithAttributes(CTFontDescriptorRef d, CFDictionaryRef attributes);
CTFontDescriptorRef _Nullable CTFontDescriptorCreateCopyWithFamily(CTFontDescriptorRef d, CFStringRef family);
CTFontDescriptorRef _Nullable CTFontDescriptorCreateCopyWithSymbolicTraits(CTFontDescriptorRef d, CTFontSymbolicTraits value, CTFontSymbolicTraits mask);
CFTypeRef _Nullable CTFontDescriptorCopyAttribute(CTFontDescriptorRef d, CFStringRef attribute);
CFDictionaryRef CTFontDescriptorCopyAttributes(CTFontDescriptorRef d);
CFArrayRef _Nullable CTFontDescriptorCreateMatchingFontDescriptors(CTFontDescriptorRef d, CFSetRef _Nullable mandatoryAttributes);
CTFontDescriptorRef _Nullable CTFontDescriptorCreateMatchingFontDescriptor(CTFontDescriptorRef d, CFSetRef _Nullable mandatoryAttributes);

CTFontCollectionRef CTFontCollectionCreateFromAvailableFonts(CFDictionaryRef _Nullable options);
CFArrayRef _Nullable CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionRef c);

/* registering font files: they are usable by name (PostScript or family) for the rest of the process */
typedef CF_ENUM(uint32_t, CTFontManagerScope) { kCTFontManagerScopeNone = 0, kCTFontManagerScopeProcess = 1,
    kCTFontManagerScopePersistent = 2, kCTFontManagerScopeSession = 3, kCTFontManagerScopeUser = 2 };
bool CTFontManagerRegisterFontsForURL(CFURLRef url, CTFontManagerScope scope, CFErrorRef _Nullable *_Nullable error);
bool CTFontManagerUnregisterFontsForURL(CFURLRef url, CTFontManagerScope scope, CFErrorRef _Nullable *_Nullable error);
bool CTFontManagerRegisterFontsForURLs(CFArrayRef urls, CTFontManagerScope scope, CFArrayRef _Nullable *_Nullable errors);
#if __BLOCKS__
void CTFontManagerRegisterFontURLs(CFArrayRef urls, CTFontManagerScope scope, bool enabled, bool (^_Nullable handler)(CFArrayRef errors, bool done));
#endif
CFArrayRef _Nullable CTFontManagerCreateFontDescriptorsFromURL(CFURLRef url);
CFArrayRef CTFontManagerCopyAvailablePostScriptNames(void);
CFArrayRef CTFontManagerCopyAvailableFontFamilyNames(void);

/* ---------------------------------------------------------------- paragraph styles (an NSParagraphStyle) */
typedef CF_ENUM(uint8_t, CTTextAlignment) { kCTTextAlignmentLeft = 0, kCTTextAlignmentRight = 1, kCTTextAlignmentCenter = 2,
    kCTTextAlignmentJustified = 3, kCTTextAlignmentNatural = 4 };
typedef CF_ENUM(uint8_t, CTLineBreakMode) { kCTLineBreakByWordWrapping = 0, kCTLineBreakByCharWrapping = 1, kCTLineBreakByClipping = 2,
    kCTLineBreakByTruncatingHead = 3, kCTLineBreakByTruncatingTail = 4, kCTLineBreakByTruncatingMiddle = 5 };
typedef CF_ENUM(int8_t, CTWritingDirection) { kCTWritingDirectionNatural = -1, kCTWritingDirectionLeftToRight = 0, kCTWritingDirectionRightToLeft = 1 };
typedef CF_ENUM(uint32_t, CTParagraphStyleSpecifier) {
    kCTParagraphStyleSpecifierAlignment = 0, kCTParagraphStyleSpecifierFirstLineHeadIndent = 1, kCTParagraphStyleSpecifierHeadIndent = 2,
    kCTParagraphStyleSpecifierTailIndent = 3, kCTParagraphStyleSpecifierTabStops = 4, kCTParagraphStyleSpecifierDefaultTabInterval = 5,
    kCTParagraphStyleSpecifierLineBreakMode = 6, kCTParagraphStyleSpecifierLineHeightMultiple = 7, kCTParagraphStyleSpecifierMaximumLineHeight = 8,
    kCTParagraphStyleSpecifierMinimumLineHeight = 9, kCTParagraphStyleSpecifierLineSpacing = 10, kCTParagraphStyleSpecifierParagraphSpacing = 11,
    kCTParagraphStyleSpecifierParagraphSpacingBefore = 12, kCTParagraphStyleSpecifierBaseWritingDirection = 13,
    kCTParagraphStyleSpecifierMaximumLineSpacing = 14, kCTParagraphStyleSpecifierMinimumLineSpacing = 15,
    kCTParagraphStyleSpecifierLineSpacingAdjustment = 16, kCTParagraphStyleSpecifierLineBoundsOptions = 17, kCTParagraphStyleSpecifierCount = 18,
};
typedef struct CTParagraphStyleSetting { CTParagraphStyleSpecifier spec; size_t valueSize; const void *value; } CTParagraphStyleSetting;
CTParagraphStyleRef CTParagraphStyleCreate(const CTParagraphStyleSetting *_Nullable settings, size_t count);
CTParagraphStyleRef CTParagraphStyleCreateCopy(CTParagraphStyleRef p);
bool CTParagraphStyleGetValueForSpecifier(CTParagraphStyleRef p, CTParagraphStyleSpecifier spec, size_t valueBufferSize, void *valueBuffer);

/* ---------------------------------------------------------------- lines and runs */
typedef CF_OPTIONS(CFOptionFlags, CTLineBoundsOptions) {
    kCTLineBoundsExcludeTypographicLeading = 1 << 0, kCTLineBoundsExcludeTypographicShifts = 1 << 1, kCTLineBoundsUseHangingPunctuation = 1 << 2,
    kCTLineBoundsUseGlyphPathBounds = 1 << 3, kCTLineBoundsUseOpticalBounds = 1 << 4, kCTLineBoundsIncludeLanguageExtents = 1 << 5,
};
typedef CF_ENUM(uint32_t, CTLineTruncationType) { kCTLineTruncationStart = 0, kCTLineTruncationEnd = 1, kCTLineTruncationMiddle = 2 };
typedef CF_OPTIONS(uint32_t, CTRunStatus) { kCTRunStatusNoStatus = 0, kCTRunStatusRightToLeft = 1 << 0, kCTRunStatusNonMonotonic = 1 << 1,
    kCTRunStatusHasNonIdentityMatrix = 1 << 2 };
CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef s);
CTLineRef _Nullable CTLineCreateTruncatedLine(CTLineRef line, double width, CTLineTruncationType type, CTLineRef _Nullable token);
CTLineRef _Nullable CTLineCreateJustifiedLine(CTLineRef line, CGFloat factor, double width);
CFIndex CTLineGetGlyphCount(CTLineRef line);
CFArrayRef CTLineGetGlyphRuns(CTLineRef line);
CFRange CTLineGetStringRange(CTLineRef line);
double CTLineGetPenOffsetForFlush(CTLineRef line, CGFloat flushFactor, double flushWidth);
void CTLineDraw(CTLineRef line, CGContextRef c);
CGRect CTLineGetBoundsWithOptions(CTLineRef line, CTLineBoundsOptions options);
double CTLineGetTypographicBounds(CTLineRef line, CGFloat *_Nullable ascent, CGFloat *_Nullable descent, CGFloat *_Nullable leading);
CGRect CTLineGetImageBounds(CTLineRef line, CGContextRef _Nullable c);
double CTLineGetTrailingWhitespaceWidth(CTLineRef line);
CFIndex CTLineGetStringIndexForPosition(CTLineRef line, CGPoint position);
CGFloat CTLineGetOffsetForStringIndex(CTLineRef line, CFIndex charIndex, CGFloat *_Nullable secondaryOffset);
#if __BLOCKS__
void CTLineEnumerateCaretOffsets(CTLineRef line, void (^block)(double offset, CFIndex charIndex, bool leadingEdge, bool *stop));
#endif

CFIndex CTRunGetGlyphCount(CTRunRef run);
CFDictionaryRef CTRunGetAttributes(CTRunRef run);
CTRunStatus CTRunGetStatus(CTRunRef run);
const CGGlyph *_Nullable CTRunGetGlyphsPtr(CTRunRef run);
void CTRunGetGlyphs(CTRunRef run, CFRange range, CGGlyph buffer[]);
const CGPoint *_Nullable CTRunGetPositionsPtr(CTRunRef run);
void CTRunGetPositions(CTRunRef run, CFRange range, CGPoint buffer[]);
const CGSize *_Nullable CTRunGetAdvancesPtr(CTRunRef run);
void CTRunGetAdvances(CTRunRef run, CFRange range, CGSize buffer[]);
const CFIndex *_Nullable CTRunGetStringIndicesPtr(CTRunRef run);
void CTRunGetStringIndices(CTRunRef run, CFRange range, CFIndex buffer[]);
CFRange CTRunGetStringRange(CTRunRef run);
double CTRunGetTypographicBounds(CTRunRef run, CFRange range, CGFloat *_Nullable ascent, CGFloat *_Nullable descent, CGFloat *_Nullable leading);
CGRect CTRunGetImageBounds(CTRunRef run, CGContextRef _Nullable c, CFRange range);
CGAffineTransform CTRunGetTextMatrix(CTRunRef run);
void CTRunDraw(CTRunRef run, CGContextRef c, CFRange range);

/* ---------------------------------------------------------------- typesetters, framesetters, frames */
CTTypesetterRef CTTypesetterCreateWithAttributedString(CFAttributedStringRef s);
CTTypesetterRef CTTypesetterCreateWithAttributedStringAndOptions(CFAttributedStringRef s, CFDictionaryRef _Nullable options);
CTLineRef CTTypesetterCreateLine(CTTypesetterRef t, CFRange range);
CTLineRef CTTypesetterCreateLineWithOffset(CTTypesetterRef t, CFRange range, double offset);
CFIndex CTTypesetterSuggestLineBreak(CTTypesetterRef t, CFIndex start, double width);
CFIndex CTTypesetterSuggestLineBreakWithOffset(CTTypesetterRef t, CFIndex start, double width, double offset);
CFIndex CTTypesetterSuggestClusterBreak(CTTypesetterRef t, CFIndex start, double width);
CFIndex CTTypesetterSuggestClusterBreakWithOffset(CTTypesetterRef t, CFIndex start, double width, double offset);

typedef CF_ENUM(uint32_t, CTFrameProgression) { kCTFrameProgressionTopToBottom = 0, kCTFrameProgressionRightToLeft = 1, kCTFrameProgressionLeftToRight = 2 };
extern const CFStringRef kCTFrameProgressionAttributeName, kCTFramePathFillRuleAttributeName, kCTFramePathWidthAttributeName;
CTFramesetterRef CTFramesetterCreateWithAttributedString(CFAttributedStringRef s);
CTFramesetterRef CTFramesetterCreateWithTypesetter(CTTypesetterRef t);
CTFrameRef CTFramesetterCreateFrame(CTFramesetterRef f, CFRange range, CGPathRef path, CFDictionaryRef _Nullable attributes);
CTTypesetterRef CTFramesetterGetTypesetter(CTFramesetterRef f);
CGSize CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterRef f, CFRange range, CFDictionaryRef _Nullable attributes, CGSize constraints, CFRange *_Nullable fitRange);
CFRange CTFrameGetStringRange(CTFrameRef f);
CFRange CTFrameGetVisibleStringRange(CTFrameRef f);
CGPathRef CTFrameGetPath(CTFrameRef f);
CFDictionaryRef _Nullable CTFrameGetFrameAttributes(CTFrameRef f);
CFArrayRef CTFrameGetLines(CTFrameRef f);
void CTFrameGetLineOrigins(CTFrameRef f, CFRange range, CGPoint origins[]);
void CTFrameDraw(CTFrameRef f, CGContextRef c);
#pragma clang arc_cf_code_audited end
CF_EXTERN_C_END
