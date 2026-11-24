/* widgets.m — the rest of AppKit: colors, fonts, appearance, pasteboard, alerts, panels, controllers, Auto Layout objects
 * and the controls (drawn and interactive). Stack and grid views lay out their subviews; constraints are solved in layout.m. */
#import "internal.h"
#include <string.h>
#include <stdlib.h>

/* ======================================================================= NSColorSpace, NSColor */
@implementation NSColorSpace
#define CS(name) + (NSColorSpace *)name { static NSColorSpace *s; if (!s) s = [[NSColorSpace alloc] init]; return s; }
CS(sRGBColorSpace) CS(genericRGBColorSpace) CS(deviceRGBColorSpace) CS(displayP3ColorSpace) CS(extendedSRGBColorSpace)
#undef CS
- (CGColorSpaceRef)CGColorSpace { return CGColorSpaceCreateWithName(kCGColorSpaceSRGB); }
- (NSString *)localizedName { return @"sRGB IEC61966-2.1"; }
@end

@interface NSColor () { @public CGFloat _c[4]; CGColorRef _cg; } @end
@implementation NSColor
static NSColor *rgba(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    NSColor *c = [[[NSColor alloc] init] autorelease];
    c->_c[0] = r; c->_c[1] = g; c->_c[2] = b; c->_c[3] = a;
    return c;
}
- (void)dealloc { if (_cg) CGColorRelease(_cg); [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a { return rgba(r, g, b, a); }
+ (NSColor *)colorWithSRGBRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a { return rgba(r, g, b, a); }
+ (NSColor *)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a { return rgba(r, g, b, a); }
+ (NSColor *)colorWithDeviceRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a { return rgba(r, g, b, a); }
+ (NSColor *)colorWithDisplayP3Red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a { return rgba(r, g, b, a); }
+ (NSColor *)colorWithWhite:(CGFloat)w alpha:(CGFloat)a { return rgba(w, w, w, a); }
+ (NSColor *)colorWithCalibratedWhite:(CGFloat)w alpha:(CGFloat)a { return rgba(w, w, w, a); }
+ (NSColor *)colorWithDeviceWhite:(CGFloat)w alpha:(CGFloat)a { return rgba(w, w, w, a); }
+ (NSColor *)colorWithGenericGamma22White:(CGFloat)w alpha:(CGFloat)a { return rgba(w, w, w, a); }
+ (NSColor *)colorWithHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)v alpha:(CGFloat)a {
    h = fmod(h, 1) * 6; int i = (int)h; CGFloat f = h - i, p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
    switch (i) { case 0: return rgba(v, t, p, a); case 1: return rgba(q, v, p, a); case 2: return rgba(p, v, t, a);
                 case 3: return rgba(p, q, v, a); case 4: return rgba(t, p, v, a); default: return rgba(v, p, q, a); }
}
+ (NSColor *)colorWithCGColor:(CGColorRef)c {
    const CGFloat *k = CGColorGetComponents(c);
    size_t n = CGColorGetNumberOfComponents(c);
    return n >= 4 ? rgba(k[0], k[1], k[2], k[3]) : n == 2 ? rgba(k[0], k[0], k[0], k[1]) : rgba(0, 0, 0, 1);
}
+ (NSColor *)colorWithName:(NSString *)n dynamicProvider:(NSColor * (^)(NSAppearance *))p { return p([NSApp effectiveAppearance]); }
+ (NSColor *)colorWithPatternImage:(NSImage *)i { return rgba(0.5, 0.5, 0.5, 1); }
#define C(name, r, g, b, a) + (NSColor *)name { return rgba(r, g, b, a); }
C(blackColor, 0, 0, 0, 1) C(whiteColor, 1, 1, 1, 1) C(clearColor, 0, 0, 0, 0) C(redColor, 1, 0, 0, 1) C(greenColor, 0, 1, 0, 1)
C(blueColor, 0, 0, 1, 1) C(yellowColor, 1, 1, 0, 1) C(orangeColor, 1, 0.5, 0, 1) C(purpleColor, 0.5, 0, 0.5, 1) C(brownColor, 0.6, 0.4, 0.2, 1)
C(cyanColor, 0, 1, 1, 1) C(magentaColor, 1, 0, 1, 1) C(grayColor, 0.5, 0.5, 0.5, 1) C(lightGrayColor, 2 / 3., 2 / 3., 2 / 3., 1)
C(darkGrayColor, 1 / 3., 1 / 3., 1 / 3., 1)
/* system colors: the dark appearance */
C(systemRedColor, 1, 0.271, 0.227, 1) C(systemGreenColor, 0.196, 0.843, 0.294, 1) C(systemBlueColor, 0.039, 0.518, 1, 1)
C(systemOrangeColor, 1, 0.624, 0.039, 1) C(systemYellowColor, 1, 0.839, 0.039, 1) C(systemPinkColor, 1, 0.216, 0.373, 1)
C(systemPurpleColor, 0.749, 0.353, 0.949, 1) C(systemTealColor, 0.353, 0.784, 0.98, 1) C(systemIndigoColor, 0.369, 0.361, 0.902, 1)
C(systemBrownColor, 0.675, 0.557, 0.408, 1) C(systemGrayColor, 0.596, 0.596, 0.616, 1) C(systemMintColor, 0.4, 0.831, 0.812, 1)
C(systemCyanColor, 0.392, 0.824, 1, 1) C(labelColor, 1, 1, 1, 0.85) C(secondaryLabelColor, 1, 1, 1, 0.55) C(tertiaryLabelColor, 1, 1, 1, 0.25)
C(quaternaryLabelColor, 1, 1, 1, 0.1) C(textColor, 1, 1, 1, 1) C(textBackgroundColor, 0.118, 0.118, 0.118, 1)
C(windowBackgroundColor, 0.196, 0.196, 0.196, 1) C(controlColor, 1, 1, 1, 0.25) C(controlBackgroundColor, 0.118, 0.118, 0.118, 1)
C(controlTextColor, 1, 1, 1, 0.85) C(disabledControlTextColor, 1, 1, 1, 0.25) C(controlAccentColor, 0.039, 0.518, 1, 1)
C(selectedControlColor, 0, 0.345, 0.816, 1) C(selectedTextBackgroundColor, 0.247, 0.388, 0.545, 1) C(separatorColor, 1, 1, 1, 0.1)
C(gridColor, 0.102, 0.102, 0.102, 1) C(linkColor, 0.255, 0.612, 1, 1) C(placeholderTextColor, 1, 1, 1, 0.25)
C(underPageBackgroundColor, 0.157, 0.157, 0.157, 1) C(unemphasizedSelectedContentBackgroundColor, 0.275, 0.275, 0.275, 1)
C(selectedContentBackgroundColor, 0, 0.345, 0.816, 1) C(keyboardFocusIndicatorColor, 0.102, 0.663, 1, 0.5) C(headerTextColor, 1, 1, 1, 1)
C(shadowColor, 0, 0, 0, 1) C(highlightColor, 0.706, 0.706, 0.706, 1) C(windowFrameTextColor, 1, 1, 1, 0.85)
C(alternateSelectedControlTextColor, 1, 1, 1, 1) C(selectedMenuItemTextColor, 1, 1, 1, 1) C(findHighlightColor, 1, 1, 0, 1)
#undef C
- (CGFloat)redComponent { return _c[0]; }
- (CGFloat)greenComponent { return _c[1]; }
- (CGFloat)blueComponent { return _c[2]; }
- (CGFloat)alphaComponent { return _c[3]; }
- (CGFloat)whiteComponent { return (_c[0] + _c[1] + _c[2]) / 3; }
- (void)getHue:(CGFloat *)h saturation:(CGFloat *)s brightness:(CGFloat *)b alpha:(CGFloat *)a {
    CGFloat mx = fmax(_c[0], fmax(_c[1], _c[2])), mn = fmin(_c[0], fmin(_c[1], _c[2])), d = mx - mn, hh = 0;
    if (d > 0) hh = mx == _c[0] ? fmod((_c[1] - _c[2]) / d, 6) : mx == _c[1] ? (_c[2] - _c[0]) / d + 2 : (_c[0] - _c[1]) / d + 4;
    if (h) *h = hh < 0 ? hh / 6 + 1 : hh / 6;
    if (s) *s = mx > 0 ? d / mx : 0;
    if (b) *b = mx;
    if (a) *a = _c[3];
}
- (CGFloat)hueComponent { CGFloat h; [self getHue:&h saturation:0 brightness:0 alpha:0]; return h; }
- (CGFloat)saturationComponent { CGFloat s; [self getHue:0 saturation:&s brightness:0 alpha:0]; return s; }
- (CGFloat)brightnessComponent { CGFloat b; [self getHue:0 saturation:0 brightness:&b alpha:0]; return b; }
- (CGColorRef)CGColor { if (!_cg) _cg = CGColorCreateSRGB(_c[0], _c[1], _c[2], _c[3]); return _cg; }
- (NSColorSpace *)colorSpace { return [NSColorSpace sRGBColorSpace]; }
- (NSInteger)numberOfComponents { return 4; }
- (void)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a { if (r) *r = _c[0]; if (g) *g = _c[1]; if (b) *b = _c[2]; if (a) *a = _c[3]; }
- (void)getComponents:(CGFloat *)c { memcpy(c, _c, sizeof _c); }
- (NSColor *)colorWithAlphaComponent:(CGFloat)a { return rgba(_c[0], _c[1], _c[2], a); }
- (NSColor *)colorUsingColorSpace:(NSColorSpace *)s { return self; }
- (NSColor *)colorUsingColorSpaceName:(NSString *)n { return self; }
- (NSColor *)blendedColorWithFraction:(CGFloat)f ofColor:(NSColor *)o {
    return rgba(_c[0] + (o->_c[0] - _c[0]) * f, _c[1] + (o->_c[1] - _c[1]) * f, _c[2] + (o->_c[2] - _c[2]) * f, _c[3] + (o->_c[3] - _c[3]) * f);
}
- (NSColor *)highlightWithLevel:(CGFloat)l { return [self blendedColorWithFraction:l ofColor:[NSColor whiteColor]]; }
- (NSColor *)shadowWithLevel:(CGFloat)l { return [self blendedColorWithFraction:l ofColor:[NSColor blackColor]]; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSColor class]] && !memcmp(_c, ((NSColor *)o)->_c, sizeof _c); }
- (NSUInteger)hash { return (NSUInteger)(_c[0] * 255) << 24 | (NSUInteger)(_c[1] * 255) << 16 | (NSUInteger)(_c[2] * 255) << 8 | (NSUInteger)(_c[3] * 255); }
- (NSString *)description { return [NSString stringWithFormat:@"sRGB %g %g %g %g", _c[0], _c[1], _c[2], _c[3]]; }
- (void)set { CGContextRef c = mw_cg(); CGContextSetRGBFillColor(c, _c[0], _c[1], _c[2], _c[3]); CGContextSetRGBStrokeColor(c, _c[0], _c[1], _c[2], _c[3]); }
- (void)setFill { CGContextSetRGBFillColor(mw_cg(), _c[0], _c[1], _c[2], _c[3]); }
- (void)setStroke { CGContextSetRGBStrokeColor(mw_cg(), _c[0], _c[1], _c[2], _c[3]); }
@end

/* ======================================================================= fonts */
@implementation NSFontDescriptor { @public CGFloat _size; }
- (CGFloat)pointSize { return _size; }
- (NSFontDescriptor *)fontDescriptorWithSymbolicTraits:(uint32_t)t { return self; }
@end
@interface NSFont () { @public CGFloat _size; NSFontWeight _weight; NSString *_name; BOOL _fixed; } @end
@implementation NSFont
static NSFont *font(NSString *name, CGFloat size, NSFontWeight w, BOOL fixed) {
    NSFont *f = [[[NSFont alloc] init] autorelease];
    f->_name = [name copy]; f->_size = size > 0 ? size : 13; f->_weight = w; f->_fixed = fixed;
    return f;
}
- (void)dealloc { [_name release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
+ (NSFont *)systemFontOfSize:(CGFloat)s { return font(@".AppleSystemUIFont", s, NSFontWeightRegular, NO); }
+ (NSFont *)systemFontOfSize:(CGFloat)s weight:(NSFontWeight)w { return font(@".AppleSystemUIFont", s, w, NO); }
/* text styles: macOS 14 sizes */
+ (NSFont *)preferredFontForTextStyle:(NSString *)st options:(NSDictionary *)o {
    static NSDictionary *sizes; if (!sizes) sizes = [@{NSFontTextStyleLargeTitle: @26, NSFontTextStyleTitle1: @22, NSFontTextStyleTitle2: @17, NSFontTextStyleTitle3: @15,
        NSFontTextStyleHeadline: @13, NSFontTextStyleSubheadline: @11, NSFontTextStyleBody: @13, NSFontTextStyleCallout: @12, NSFontTextStyleFootnote: @10,
        NSFontTextStyleCaption1: @10, NSFontTextStyleCaption2: @10} retain];
    CGFloat s = [sizes[st] doubleValue] ?: 13;
    return [st isEqualToString:NSFontTextStyleHeadline] ? [self boldSystemFontOfSize:s] : [self systemFontOfSize:s];
}
+ (NSFont *)preferredFontForTextStyle:(NSString *)st { return [self preferredFontForTextStyle:st options:@{}]; }
+ (NSFont *)boldSystemFontOfSize:(CGFloat)s { return font(@".AppleSystemUIFontBold", s, NSFontWeightBold, NO); }
+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)s weight:(NSFontWeight)w { return font(@".AppleSystemUIFontMonospaced", s, w, YES); }
+ (NSFont *)monospacedDigitSystemFontOfSize:(CGFloat)s weight:(NSFontWeight)w { return font(@".AppleSystemUIFont", s, w, NO); }
+ (NSFont *)userFixedPitchFontOfSize:(CGFloat)s { return font(@"Menlo-Regular", s, NSFontWeightRegular, YES); }
+ (NSFont *)userFontOfSize:(CGFloat)s { return font(@"Helvetica", s, NSFontWeightRegular, NO); }
+ (NSFont *)labelFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont *)menuFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont *)messageFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont *)controlContentFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont *)fontWithName:(NSString *)n size:(CGFloat)s { return font(n, s, NSFontWeightRegular, [n rangeOfString:@"Mono"].location != NSNotFound || [n hasPrefix:@"Menlo"] || [n hasPrefix:@"Courier"]); }
+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)d size:(CGFloat)s { return [self systemFontOfSize:s ? s : d.pointSize]; }
+ (CGFloat)systemFontSize { return 13; }
+ (CGFloat)smallSystemFontSize { return 11; }
+ (CGFloat)labelFontSize { return 10; }
+ (CGFloat)systemFontSizeForControlSize:(NSControlSize)c { return c == NSControlSizeMini ? 9 : c == NSControlSizeSmall ? 11 : 13; }
- (CGFloat)pointSize { return _size; }
- (CGFloat)ascender { CGFloat a; mw_font_metrics(self, &a, NULL); return a; }
- (CGFloat)descender { CGFloat d; mw_font_metrics(self, NULL, &d); return -d; }
- (CGFloat)capHeight { return _size * 0.7; }
- (CGFloat)xHeight { return _size * 0.52; }
- (CGFloat)leading { return 0; }
- (CGFloat)underlinePosition { return -_size * 0.1; }
- (NSFontWeight)weight { return _weight; }
- (NSString *)fontName { return _name; }
- (NSString *)familyName { return _name; }
- (NSString *)displayName { return _name; }
- (NSFontDescriptor *)fontDescriptor { NSFontDescriptor *d = [[[NSFontDescriptor alloc] init] autorelease]; d->_size = _size; return d; }
- (BOOL)isFixedPitch { return _fixed; }
- (NSRect)boundingRectForFont { return NSMakeRect(0, self.descender, _size, self.ascender - self.descender); }
- (CGFloat)defaultLineHeightForFont { return ceil(self.ascender - self.descender); }
@end
static NSSize text_size(NSString *s, NSFont *f) { return mw_text_size(s ? s : @"", f); }

/* ======================================================================= appearance */
@implementation NSAppearance { NSString *_name; }
static NSAppearance *g_current;
+ (NSAppearance *)appearanceNamed:(NSAppearanceName)n {
    static NSMutableDictionary *all;
    if (!all) all = [[NSMutableDictionary alloc] init];
    NSAppearance *a = all[n];
    if (!a) { a = [[[NSAppearance alloc] init] autorelease]; a->_name = [n copy]; all[n] = a; }
    return a;
}
+ (NSAppearance *)currentAppearance { return g_current ? g_current : [NSApp effectiveAppearance]; }
+ (void)setCurrentAppearance:(NSAppearance *)a { [a retain]; [g_current release]; g_current = a; }
+ (NSAppearance *)currentDrawingAppearance { return [self currentAppearance]; }
- (NSAppearanceName)name { return _name; }
- (NSAppearanceName)bestMatchFromAppearancesWithNames:(NSArray *)names {
    if ([names containsObject:_name]) return _name;
    BOOL dark = [_name rangeOfString:@"Dark"].location != NSNotFound;
    for (NSString *n in names) if (([n rangeOfString:@"Dark"].location != NSNotFound) == dark) return n;
    return nil;
}
- (void)performAsCurrentDrawingAppearance:(void (^)(void))b { b(); }
@end
@implementation NSShadow
- (void)dealloc { [_shadowColor release]; [super dealloc]; }
- (void)set { }
@end
@interface NSParagraphStyle (MW) - (void)_mwCopyFrom:(NSParagraphStyle *)p; @end
@implementation NSTextTab { NSTextAlignment _a; CGFloat _l; NSDictionary *_o; }
- (instancetype)initWithTextAlignment:(NSTextAlignment)a location:(CGFloat)l options:(NSDictionary *)o { _a = a; _l = l; _o = [o copy]; return self; }
- (void)dealloc { [_o release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSTextAlignment)alignment { return _a; } - (CGFloat)location { return _l; } - (NSDictionary *)options { return _o ?: @{}; }
@end
@implementation NSParagraphStyle
+ (NSParagraphStyle *)defaultParagraphStyle { static NSParagraphStyle *p; if (!p) p = [[NSParagraphStyle alloc] init]; return p; }
- (instancetype)init { if ((self = [super init])) { _alignment = NSTextAlignmentNatural; _lineBreakMode = NSLineBreakByWordWrapping; _baseWritingDirection = -1; } return self; }
- (void)dealloc { [_tabStops release]; [super dealloc]; }
- (NSTextAlignment)alignment { return _alignment; }
- (NSLineBreakMode)lineBreakMode { return _lineBreakMode; }
- (CGFloat)lineSpacing { return _lineSpacing; } - (CGFloat)paragraphSpacing { return _paragraphSpacing; } - (CGFloat)paragraphSpacingBefore { return _paragraphSpacingBefore; }
- (CGFloat)headIndent { return _headIndent; } - (CGFloat)tailIndent { return _tailIndent; } - (CGFloat)firstLineHeadIndent { return _firstLineHeadIndent; }
- (CGFloat)minimumLineHeight { return _minimumLineHeight; } - (CGFloat)maximumLineHeight { return _maximumLineHeight; }
- (CGFloat)lineHeightMultiple { return _lineHeightMultiple; } - (CGFloat)hyphenationFactor { return _hyphenationFactor; } - (CGFloat)defaultTabInterval { return _defaultTabInterval; }
- (NSInteger)baseWritingDirection { return _baseWritingDirection; } - (NSInteger)lineBreakStrategy { return _lineBreakStrategy; }
- (NSArray *)tabStops { return _tabStops ?: @[]; }
- (BOOL)allowsDefaultTighteningForTruncation { return _allowsDefaultTighteningForTruncation; }
- (void)_mwCopyFrom:(NSParagraphStyle *)p {
    _alignment = p->_alignment; _lineBreakMode = p->_lineBreakMode; _baseWritingDirection = p->_baseWritingDirection; _lineBreakStrategy = p->_lineBreakStrategy;
    _lineSpacing = p->_lineSpacing; _paragraphSpacing = p->_paragraphSpacing; _paragraphSpacingBefore = p->_paragraphSpacingBefore; _headIndent = p->_headIndent;
    _tailIndent = p->_tailIndent; _firstLineHeadIndent = p->_firstLineHeadIndent; _minimumLineHeight = p->_minimumLineHeight; _maximumLineHeight = p->_maximumLineHeight;
    _lineHeightMultiple = p->_lineHeightMultiple; _hyphenationFactor = p->_hyphenationFactor; _defaultTabInterval = p->_defaultTabInterval;
    [_tabStops release]; _tabStops = [p->_tabStops copy]; _allowsDefaultTighteningForTruncation = p->_allowsDefaultTighteningForTruncation;
}
- (id)copyWithZone:(NSZone *)z { if ([self class] == [NSParagraphStyle class]) return [self retain]; NSParagraphStyle *p = [[NSParagraphStyle alloc] init]; [p _mwCopyFrom:self]; return p; }
- (id)mutableCopyWithZone:(NSZone *)z { NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init]; [p _mwCopyFrom:self]; return p; }
@end
@implementation NSMutableParagraphStyle
@dynamic alignment, lineBreakMode, lineSpacing, paragraphSpacing, paragraphSpacingBefore, headIndent, tailIndent, firstLineHeadIndent,
    minimumLineHeight, maximumLineHeight, lineHeightMultiple, hyphenationFactor, defaultTabInterval, baseWritingDirection, lineBreakStrategy, tabStops,
    allowsDefaultTighteningForTruncation;
- (void)setAlignment:(NSTextAlignment)a { _alignment = a; } - (void)setLineBreakMode:(NSLineBreakMode)m { _lineBreakMode = m; }
- (void)setLineSpacing:(CGFloat)v { _lineSpacing = v; } - (void)setParagraphSpacing:(CGFloat)v { _paragraphSpacing = v; }
- (void)setParagraphSpacingBefore:(CGFloat)v { _paragraphSpacingBefore = v; } - (void)setHeadIndent:(CGFloat)v { _headIndent = v; }
- (void)setTailIndent:(CGFloat)v { _tailIndent = v; } - (void)setFirstLineHeadIndent:(CGFloat)v { _firstLineHeadIndent = v; }
- (void)setMinimumLineHeight:(CGFloat)v { _minimumLineHeight = v; } - (void)setMaximumLineHeight:(CGFloat)v { _maximumLineHeight = v; }
- (void)setLineHeightMultiple:(CGFloat)v { _lineHeightMultiple = v; } - (void)setHyphenationFactor:(CGFloat)v { _hyphenationFactor = v; }
- (void)setDefaultTabInterval:(CGFloat)v { _defaultTabInterval = v; } - (void)setBaseWritingDirection:(NSInteger)v { _baseWritingDirection = v; }
- (void)setLineBreakStrategy:(NSInteger)v { _lineBreakStrategy = v; } - (void)setTabStops:(NSArray *)t { [_tabStops release]; _tabStops = [t copy]; }
- (void)setAllowsDefaultTighteningForTruncation:(BOOL)f { _allowsDefaultTighteningForTruncation = f; }
- (void)setParagraphStyle:(NSParagraphStyle *)p { [self _mwCopyFrom:p]; }
- (void)addTabStop:(NSTextTab *)t { self.tabStops = [self.tabStops arrayByAddingObject:t]; }
- (void)removeTabStop:(NSTextTab *)t { NSMutableArray *a = [[self.tabStops mutableCopy] autorelease]; [a removeObject:t]; self.tabStops = a; }
- (id)copyWithZone:(NSZone *)z { NSParagraphStyle *p = [[NSParagraphStyle alloc] init]; [p _mwCopyFrom:self]; return p; }
@end
/* ======================================================================= NSPasteboard (the Windows clipboard, text only) */
@implementation NSPasteboard { NSInteger _changes; }
+ (NSPasteboard *)generalPasteboard { static NSPasteboard *p; if (!p) p = [[self alloc] init]; return p; }
- (NSArray *)types { return @[NSPasteboardTypeString]; }
- (NSInteger)changeCount { return _changes; }
- (NSInteger)clearContents { ui(UI_CLIPBOARD, 1, U(""), 0, 0, 0); return ++_changes; }
- (NSInteger)declareTypes:(NSArray *)t owner:(id)o { return ++_changes; }
static BOOL is_text(NSString *t) { return [t isEqualToString:NSPasteboardTypeString] || [t isEqualToString:NSStringPboardType] || [t isEqualToString:@"public.plain-text"]; }
- (BOOL)setString:(NSString *)s forType:(NSPasteboardType)t {
    if (!is_text(t)) return NO;
    ui(UI_CLIPBOARD, 1, U([s UTF8String]), 0, 0, 0);
    _changes++;
    return YES;
}
- (BOOL)setData:(NSData *)d forType:(NSPasteboardType)t {
    if (!is_text(t)) return NO;
    NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
    return s ? [self setString:s forType:t] : NO;
}
- (NSString *)stringForType:(NSPasteboardType)t {
    if (!is_text(t)) return nil;
    char *p = (char *)(uintptr_t)ui(UI_CLIPBOARD, 0, 0, 0, 0, 0);
    if (!p) return nil;
    NSString *s = [NSString stringWithUTF8String:p];
    ui(UI_FREE, U(p), 0, 0, 0, 0);
    return s;
}
- (NSData *)dataForType:(NSPasteboardType)t { return [[self stringForType:t] dataUsingEncoding:NSUTF8StringEncoding]; }
- (BOOL)writeObjects:(NSArray *)o {
    for (id x in o) if ([x isKindOfClass:[NSString class]]) return [self setString:x forType:NSPasteboardTypeString];
    return NO;
}
- (NSArray *)readObjectsForClasses:(NSArray *)c options:(NSDictionary *)o { NSString *s = [self stringForType:NSPasteboardTypeString]; return s ? @[s] : @[]; }
- (NSPasteboardType)availableTypeFromArray:(NSArray *)t { for (NSString *x in t) if (is_text(x) && [self stringForType:x]) return x; return nil; }
- (BOOL)canReadObjectForClasses:(NSArray *)c options:(NSDictionary *)o { return [self stringForType:NSPasteboardTypeString] != nil; }
@end

/* ======================================================================= NSAlert (a Windows message box), panels */
@implementation NSAlert { NSMutableArray *_btns; }
@synthesize delegate = _mwDelegate, helpAnchor = _mwHelpAnchor;
+ (NSAlert *)alertWithError:(NSError *)e {
    NSAlert *a = [[[self alloc] init] autorelease];
    a.messageText = e.localizedDescription ? e.localizedDescription : @"Error";
    a.alertStyle = NSAlertStyleCritical;
    return a;
}
- (instancetype)init { if ((self = [super init])) { _btns = [[NSMutableArray alloc] init]; _messageText = @""; _informativeText = @""; } return self; }
- (void)dealloc { [_btns release]; [_messageText release]; [_informativeText release]; [_icon release]; [_accessoryView release]; [super dealloc]; }
- (NSArray *)buttons { return [[_btns copy] autorelease]; }
- (NSButton *)addButtonWithTitle:(NSString *)t { NSButton *b = [NSButton buttonWithTitle:t target:nil action:NULL]; b.tag = NSAlertFirstButtonReturn + (NSInteger)[_btns count]; [_btns addObject:b]; return b; }
- (NSButton *)suppressionButton { return nil; }
- (NSWindow *)window { return nil; }
- (void)layout { }
- (NSModalResponse)runModal {
    int style = _alertStyle == NSAlertStyleCritical ? 2 : _alertStyle == NSAlertStyleWarning ? 1 : 0;
    NSUInteger n = [_btns count] ? [_btns count] : 1;
    /* ponytail: Windows button captions (OK / Yes, No, Cancel), not the app's titles */
    int64_t r = ui(UI_ALERT, U([_messageText UTF8String]), U([_informativeText UTF8String]), (uint64_t)style, n > 3 ? 3 : n, 0);
    return NSAlertFirstButtonReturn + r;
}
- (void)beginSheetModalForWindow:(NSWindow *)w completionHandler:(void (^)(NSModalResponse))h { NSModalResponse r = [self runModal]; if (h) h(r); }
@end
/* the Windows file dialogs (IFileOpenDialog / IFileSaveDialog), modal on the host */
@interface NSObject (MWUTType) - (NSString *)preferredFilenameExtension; @end
@implementation NSSavePanel { @protected NSURL *_url; NSMutableArray *_urls; }
- (instancetype)init {
    struct objc_super sup = {self, [NSResponder class]}; /* a panel needs no window of its own */
    self = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, @selector(init));
    if (self) { _canCreateDirectories = YES; _urls = [[NSMutableArray alloc] init]; }
    return self;
}
+ (NSSavePanel *)savePanel { return [[[self alloc] init] autorelease]; }
- (void)dealloc {
    [_url release]; [_urls release]; [_directoryURL release]; [_nameFieldStringValue release]; [_message release]; [_prompt release];
    [_allowedFileTypes release]; [_allowedContentTypes release];
    [super dealloc];
}
- (NSURL *)URL { return _url; }
- (uint32_t)_mwFlags { return UI_FD_SAVE | (_canCreateDirectories ? UI_FD_CREATE_DIRS : 0) | (_showsHiddenFiles ? UI_FD_HIDDEN : 0); }
- (NSModalResponse)_mwRun:(NSWindow *)owner {
    NSMutableArray *ext = [NSMutableArray array];
    for (NSString *t in _allowedFileTypes) [ext addObject:[t hasPrefix:@"."] ? [t substringFromIndex:1] : t];
    for (id t in _allowedContentTypes) if ([t respondsToSelector:@selector(preferredFilenameExtension)] && [t preferredFilenameExtension]) [ext addObject:[t preferredFilenameExtension]];
    NSString *types = [ext count] ? [ext componentsJoinedByString:@";"] : nil;
    NSString *title = self.message.length ? self.message : self.title;
    MwFileDialog d = {[self _mwFlags], owner ? [owner _mwId] : [[NSApp keyWindow] _mwId], [title UTF8String], [_prompt UTF8String],
                      [_directoryURL.path UTF8String], [_nameFieldStringValue UTF8String], [types UTF8String]};
    char *r = (char *)(uintptr_t)ui(UI_FILE_DIALOG, U(&d), 0, 0, 0, 0);
    [_urls removeAllObjects]; [_url release]; _url = nil;
    if (!r) return NSModalResponseCancel;
    for (NSString *line in [[NSString stringWithUTF8String:r] componentsSeparatedByString:@"\n"])
        if ([line length]) [_urls addObject:[NSURL fileURLWithPath:line]];
    ui(UI_FREE, U(r), 0, 0, 0, 0);
    _url = [[_urls firstObject] retain];
    return _url ? NSModalResponseOK : NSModalResponseCancel;
}
- (NSModalResponse)runModal { return [self _mwRun:nil]; }
- (NSInteger)runModalForDirectory:(NSString *)d file:(NSString *)f { self.directoryURL = d ? [NSURL fileURLWithPath:d] : nil; self.nameFieldStringValue = f; return [self runModal]; }
/* the dialog is modal on Windows: the handler runs right after, on the next pass of the main loop */
- (void)beginWithCompletionHandler:(void (^)(NSModalResponse))h { [self beginSheetModalForWindow:nil completionHandler:h]; }
- (void)beginSheetModalForWindow:(NSWindow *)w completionHandler:(void (^)(NSModalResponse))h {
    NSModalResponse r = [self _mwRun:w];
    if (!h) return;
    void (^c)(NSModalResponse) = [h copy];
    [self retain];
    dispatch_async(dispatch_get_main_queue(), ^{ c(r); [c release]; [self release]; });
}
@end
@implementation NSOpenPanel
+ (NSOpenPanel *)openPanel { NSOpenPanel *p = [[[self alloc] init] autorelease]; p.canChooseFiles = YES; return p; }
- (NSArray *)URLs { return [[_urls copy] autorelease]; }
- (uint32_t)_mwFlags {
    return (_canChooseFiles ? UI_FD_FILES : 0) | (_canChooseDirectories ? UI_FD_DIRS : 0) | (_allowsMultipleSelection ? UI_FD_MULTIPLE : 0)
         | (self.showsHiddenFiles ? UI_FD_HIDDEN : 0);
}
@end

/* ======================================================================= controllers */
@implementation NSViewController
@synthesize view = _view, preferredContentSize = _preferredContentSize;
- (instancetype)initWithNibName:(NSString *)n bundle:(NSBundle *)b { if ((self = [super init])) { _nibName = [n copy]; _nibBundle = [b retain]; } return self; }
- (instancetype)init { return [self initWithNibName:nil bundle:nil]; }
- (void)dealloc { [_view release]; [_title release]; [_representedObject release]; [_nibName release]; [_nibBundle release]; [super dealloc]; }
- (NSView *)view { if (!_view) { [self loadView]; [self viewDidLoad]; } return _view; }
- (void)setView:(NSView *)v { [v retain]; [_view release]; _view = v; }
- (BOOL)isViewLoaded { return _view != nil; }
/* a popover follows its content controller's preferred size (NSHostingController keeps it up to date) */
- (NSSize)preferredContentSize { return _preferredContentSize; }
- (void)setPreferredContentSize:(NSSize)s {
    _preferredContentSize = s;
    id pop = objc_getAssociatedObject(self, "mw_popover");
    if (pop) [pop performSelector:@selector(_mwContentSizeChanged)];
}
- (void)loadView {
    /* the named nib, or one named after the class (and without its "Controller" suffix), with the controller as File's Owner */
    NSBundle *b = _nibBundle ? _nibBundle : [NSBundle bundleForClass:[self class]];
    NSString *n = _nibName, *cn = NSStringFromClass([self class]);
    if (!n && [cn rangeOfString:@"."].location != NSNotFound) cn = [cn pathExtension]; /* Swift: Module.Class */
    if (!n && [b pathForResource:cn ofType:@"nib"]) n = cn;
    if (!n && [cn hasSuffix:@"Controller"] && [b pathForResource:[cn substringToIndex:[cn length] - 10] ofType:@"nib"]) n = [cn substringToIndex:[cn length] - 10];
    if (n) [b loadNibNamed:n owner:self topLevelObjects:NULL];
    if (!_view) _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 270)];
}
- (void)viewDidLoad { } - (void)viewWillAppear { } - (void)viewDidAppear { } - (void)viewWillDisappear { } - (void)viewDidDisappear { }
- (void)viewWillLayout { } - (void)viewDidLayout { } - (void)updateViewConstraints { }
- (void)addChildViewController:(NSViewController *)c { }
- (void)removeFromParentViewController { }
- (NSArray *)childViewControllers { return @[]; }
- (NSViewController *)parentViewController { return nil; }
- (void)presentViewControllerAsSheet:(NSViewController *)vc { [[NSWindow windowWithContentViewController:vc] makeKeyAndOrderFront:nil]; }
- (void)presentViewControllerAsModalWindow:(NSViewController *)vc { [self presentViewControllerAsSheet:vc]; }
- (void)dismissViewController:(NSViewController *)vc { [vc.view.window close]; }
- (void)dismissController:(id)s { [self.view.window close]; }
@end
@implementation NSWindowController
@synthesize window = _window;
- (instancetype)initWithWindow:(NSWindow *)w { if ((self = [super init])) { self.window = w; _shouldCascadeWindows = YES; } return self; }
- (instancetype)initWithWindowNibName:(NSString *)n { return [self initWithWindowNibName:n owner:self]; }
- (instancetype)initWithWindowNibName:(NSString *)n owner:(id)o { if ((self = [self initWithWindow:nil])) { _windowNibName = [n copy]; _owner = o; } return self; }
- (instancetype)initWithWindowNibPath:(NSString *)p owner:(id)o {
    if ((self = [self initWithWindow:nil])) { _windowNibPath = [p copy]; _windowNibName = [[[p lastPathComponent] stringByDeletingPathExtension] copy]; _owner = o; }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_window release]; [_contentViewController release]; [_windowFrameAutosaveName release]; [_windowNibName release]; [_windowNibPath release]; [super dealloc]; }
- (void)setWindow:(NSWindow *)w {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_window) [nc removeObserver:self name:NSWindowWillCloseNotification object:_window];
    [w retain]; [_window release]; _window = w; w.windowController = self; w.releasedWhenClosed = NO;
    if (w && [self respondsToSelector:@selector(_mwWindowWillClose:)]) [nc addObserver:self selector:@selector(_mwWindowWillClose:) name:NSWindowWillCloseNotification object:w];
}
- (NSWindow *)window { if (!_window) { [self windowWillLoad]; [self loadWindow]; [self windowDidLoad]; } return _window; }
- (BOOL)isWindowLoaded { return _window != nil; }
- (void)setContentViewController:(NSViewController *)vc { [vc retain]; [_contentViewController release]; _contentViewController = vc; self.window.contentViewController = vc; }
- (void)showWindow:(id)s { [self.window makeKeyAndOrderFront:s]; }
- (void)close { [_window close]; }
- (void)loadWindow {
    NSString *name = [self windowNibName], *p = [self windowNibPath];   /* subclasses override these */
    if (_window || (!name && !p)) return;
    NSBundle *b = [NSBundle bundleForClass:[_owner ?: self class]];
    if (!p) p = [b pathForResource:name ofType:@"nib"] ?: [[NSBundle mainBundle] pathForResource:name ofType:@"nib"];
    id doc = self.document;
    if ([doc respondsToSelector:@selector(windowControllerWillLoadNib:)]) [doc windowControllerWillLoadNib:self];
    if (p) [[[[NSNib alloc] initWithNibNamed:p bundle:b] autorelease] instantiateWithOwner:_owner ? _owner : self topLevelObjects:NULL];
    if (!_window) { NSLog(@"%@ could not load its window nib %@", self, name); return; }
    if (doc) [self synchronizeWindowTitleWithDocumentName];
    if ([doc respondsToSelector:@selector(windowControllerDidLoadNib:)]) [doc windowControllerDidLoadNib:self];
}
- (void)windowDidLoad { }
- (void)windowWillLoad { }
@end

/* ======================================================================= Auto Layout objects (solved in layout.m) */
@implementation NSLayoutConstraint
@synthesize firstItem = _first, secondItem = _second, firstAttribute = _fa, secondAttribute = _sa, relation = _rel, multiplier = _mul;
+ (instancetype)constraintWithItem:(id)a attribute:(NSLayoutAttribute)aa relatedBy:(NSLayoutRelation)r toItem:(id)b attribute:(NSLayoutAttribute)ba
    multiplier:(CGFloat)m constant:(CGFloat)c {
    NSLayoutConstraint *k = [[[self alloc] init] autorelease];
    k->_first = a; k->_second = b; k->_fa = aa; k->_sa = ba; k->_rel = r; k->_mul = m; k.constant = c; k.priority = NSLayoutPriorityRequired;
    return k;
}
/* the visual format language: "H:|-[a]-(>=8)-[b(==a)]-|", "V:|-20@750-[c(44)]" ... */
typedef struct { NSLayoutRelation rel; CGFloat c; id view; NSLayoutPriority p; } VflPred;
static NSString *vfl_word(NSScanner *sc) {
    NSString *w = nil;
    [sc scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"] intoString:&w];
    return w;
}
static BOOL vfl_number(NSScanner *sc, NSDictionary *metrics, CGFloat *out) {
    double d;
    if ([sc scanDouble:&d]) { *out = d; return YES; }
    NSUInteger at = sc.scanLocation;
    NSString *w = vfl_word(sc);
    if (w && [metrics[w] respondsToSelector:@selector(doubleValue)]) { *out = [metrics[w] doubleValue]; return YES; }
    sc.scanLocation = at;
    return NO;
}
/* one predicate: (relation)? (constant | metric | view) (@priority)? */
static BOOL vfl_pred(NSScanner *sc, NSDictionary *metrics, NSDictionary *views, VflPred *p) {
    p->rel = NSLayoutRelationEqual; p->c = 0; p->view = nil; p->p = NSLayoutPriorityRequired;
    if ([sc scanString:@"==" intoString:NULL]) p->rel = NSLayoutRelationEqual;
    else if ([sc scanString:@">=" intoString:NULL]) p->rel = NSLayoutRelationGreaterThanOrEqual;
    else if ([sc scanString:@"<=" intoString:NULL]) p->rel = NSLayoutRelationLessThanOrEqual;
    if (!vfl_number(sc, metrics, &p->c)) {
        NSString *w = vfl_word(sc);
        if (!w || !views[w]) return NO;
        p->view = views[w];
    }
    if ([sc scanString:@"@" intoString:NULL]) { CGFloat pr; if (vfl_number(sc, metrics, &pr)) p->p = (NSLayoutPriority)pr; }
    return YES;
}
/* a list: a single predicate, or "(pred,pred,...)" */
static NSUInteger vfl_preds(NSScanner *sc, NSDictionary *metrics, NSDictionary *views, VflPred *out, NSUInteger max) {
    NSUInteger n = 0;
    if ([sc scanString:@"(" intoString:NULL]) {
        do { if (n < max && vfl_pred(sc, metrics, views, &out[n])) n++; } while ([sc scanString:@"," intoString:NULL]);
        [sc scanString:@")" intoString:NULL];
    } else if (vfl_pred(sc, metrics, views, &out[0])) n = 1;
    return n;
}
/* b.lead (rel) a.trail + gap (the superview's own edges when a or b is it) */
static void vfl_connect(NSMutableArray *out, id a, BOOL aSuper, id b, BOOL bSuper, const VflPred *gap, NSUInteger ngap, BOOL pending, BOOL standard,
                        NSLayoutAttribute lead, NSLayoutAttribute trail) {
    VflPred one = {NSLayoutRelationEqual, 0, nil, NSLayoutPriorityRequired};
    if (!pending) { gap = &one; ngap = 1; }
    else if (standard) { one.c = (aSuper || bSuper) ? 20 : 8; gap = &one; ngap = 1; }
    for (NSUInteger i = 0; i < ngap; i++) {
        NSLayoutConstraint *c = [NSLayoutConstraint constraintWithItem:b attribute:bSuper ? trail : lead relatedBy:gap[i].rel toItem:a
                                                             attribute:aSuper ? lead : trail multiplier:1 constant:gap[i].c];
        c.priority = gap[i].p;
        [out addObject:c];
    }
}
+ (NSArray *)constraintsWithVisualFormat:(NSString *)f options:(NSLayoutFormatOptions)o metrics:(NSDictionary *)metrics views:(NSDictionary *)views {
    NSMutableArray *out = [NSMutableArray array];
    NSScanner *sc = [NSScanner scannerWithString:[f stringByReplacingOccurrencesOfString:@" " withString:@""]];
    sc.charactersToBeSkipped = nil;
    BOOL vertical = NO;
    if ([sc scanString:@"V:" intoString:NULL]) vertical = YES; else [sc scanString:@"H:" intoString:NULL];
    NSLayoutAttribute lead = vertical ? NSLayoutAttributeTop : NSLayoutAttributeLeading, trail = vertical ? NSLayoutAttributeBottom : NSLayoutAttributeTrailing,
                      size = vertical ? NSLayoutAttributeHeight : NSLayoutAttributeWidth;
    id prev = nil;           /* the item the next connection starts at (a view, or the superview) */
    BOOL prevIsSuper = NO;
    VflPred gap[4]; NSUInteger ngap = 0; BOOL pendingGap = NO, standard = NO;
    NSMutableArray *chain = [NSMutableArray array];
    NSView *superview = nil;
    for (id v in views.allValues) if ([v isKindOfClass:[NSView class]] && [v superview]) { superview = [v superview]; break; }
    while (!sc.isAtEnd) {
        if ([sc scanString:@"|" intoString:NULL]) {
            if (prev) vfl_connect(out, prev, prevIsSuper, superview, YES, gap, ngap, pendingGap, standard, lead, trail);
            prev = superview; prevIsSuper = YES; pendingGap = NO; standard = NO;
        } else if ([sc scanString:@"-" intoString:NULL]) {
            pendingGap = YES; standard = YES;
            NSUInteger at = sc.scanLocation;
            ngap = vfl_preds(sc, metrics, views, gap, 4);
            if (ngap) { standard = NO; [sc scanString:@"-" intoString:NULL]; } else sc.scanLocation = at;
        } else if ([sc scanString:@"[" intoString:NULL]) {
            NSString *name = vfl_word(sc);
            id view = name ? views[name] : nil;
            VflPred sp[4]; NSUInteger nsp = 0;
            if ([sc scanString:@"(" intoString:NULL]) {
                do { if (nsp < 4 && vfl_pred(sc, metrics, views, &sp[nsp])) nsp++; } while ([sc scanString:@"," intoString:NULL]);
                [sc scanString:@")" intoString:NULL];
            }
            [sc scanString:@"]" intoString:NULL];
            if (!view) { NSLog(@"*** VFL: no view named %@ in %@", name, f); return @[]; }
            for (NSUInteger i = 0; i < nsp; i++) {
                NSLayoutConstraint *c = sp[i].view
                    ? [NSLayoutConstraint constraintWithItem:view attribute:size relatedBy:sp[i].rel toItem:sp[i].view attribute:size multiplier:1 constant:0]
                    : [NSLayoutConstraint constraintWithItem:view attribute:size relatedBy:sp[i].rel toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:sp[i].c];
                c.priority = sp[i].p;
                [out addObject:c];
            }
            if (prev) vfl_connect(out, prev, prevIsSuper, view, NO, gap, ngap, pendingGap, standard, lead, trail);
            prev = view; prevIsSuper = NO; pendingGap = NO; standard = NO;
            [chain addObject:view];
        } else { NSLog(@"*** VFL: cannot parse %@ at %lu", f, (unsigned long)sc.scanLocation); return out; }
    }
    /* options: align every view of the chain to the first on these attributes */
    for (NSLayoutAttribute a = 1; a <= 12; a++) {
        if (!(o & (1u << a)) || chain.count < 2) continue;
        NSLayoutAttribute attr = a == 11 ? NSLayoutAttributeLastBaseline : a;
        for (NSUInteger i = 1; i < chain.count; i++)
            [out addObject:[NSLayoutConstraint constraintWithItem:chain[i] attribute:attr relatedBy:NSLayoutRelationEqual toItem:chain[0] attribute:attr multiplier:1 constant:0]];
    }
    return out;
}
- (void)_mwSetActiveFlag:(BOOL)a { _active = a; }
+ (void)activateConstraints:(NSArray *)c { for (NSLayoutConstraint *k in c) k.active = YES; }
+ (void)deactivateConstraints:(NSArray *)c { for (NSLayoutConstraint *k in c) k.active = NO; }
- (void)dealloc { [_identifier release]; [super dealloc]; }
- (void)_mwRelayout {
    for (id i in @[_first ? _first : [NSNull null], _second ? _second : [NSNull null]])
        if ([i isKindOfClass:[NSView class]]) { [i setNeedsLayout:YES]; [[i superview] setNeedsLayout:YES]; }
}
- (void)setActive:(BOOL)a {
    if (a == _active) return;
    _active = a;
    NSView *v = [_first isKindOfClass:[NSView class]] ? _first : nil;
    if (a) [v addConstraint:self]; else [v removeConstraint:self];
    [self _mwRelayout];
}
- (void)setConstant:(CGFloat)c { if (c == _constant) return; _constant = c; [self _mwRelayout]; }
- (void)setPriority:(NSLayoutPriority)p { _priority = p; [self _mwRelayout]; }
@end
@implementation NSLayoutAnchor { @public id _item; NSLayoutAttribute _attr; }
+ (instancetype)_mw:(id)item attr:(NSLayoutAttribute)a { NSLayoutAnchor *x = [[[self alloc] init] autorelease]; x->_item = item; x->_attr = a; return x; }
- (NSLayoutConstraint *)_mwTo:(NSLayoutAnchor *)a rel:(NSLayoutRelation)r m:(CGFloat)m c:(CGFloat)c {
    return [NSLayoutConstraint constraintWithItem:_item attribute:_attr relatedBy:r toItem:a ? a->_item : nil
                                        attribute:a ? a->_attr : NSLayoutAttributeNotAnAttribute multiplier:m constant:c];
}
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a { return [self _mwTo:a rel:NSLayoutRelationEqual m:1 c:0]; }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a { return [self _mwTo:a rel:NSLayoutRelationGreaterThanOrEqual m:1 c:0]; }
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a { return [self _mwTo:a rel:NSLayoutRelationLessThanOrEqual m:1 c:0]; }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c { return [self _mwTo:a rel:NSLayoutRelationEqual m:1 c:c]; }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c { return [self _mwTo:a rel:NSLayoutRelationGreaterThanOrEqual m:1 c:c]; }
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c { return [self _mwTo:a rel:NSLayoutRelationLessThanOrEqual m:1 c:c]; }
@end
@implementation NSLayoutXAxisAnchor
- (NSLayoutConstraint *)constraintEqualToSystemSpacingAfterAnchor:(NSLayoutXAxisAnchor *)a multiplier:(CGFloat)m { return [self _mwTo:a rel:NSLayoutRelationEqual m:1 c:8 * m]; }
@end
@implementation NSLayoutYAxisAnchor
- (NSLayoutConstraint *)constraintEqualToSystemSpacingBelowAnchor:(NSLayoutYAxisAnchor *)a multiplier:(CGFloat)m { return [self _mwTo:a rel:NSLayoutRelationEqual m:1 c:8 * m]; }
@end
@implementation NSLayoutDimension
- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c {
    if ([_item isKindOfClass:[NSView class]]) { /* the one constraint worth honoring without a solver: a fixed size */
        NSView *v = _item; NSSize s = v.frame.size;
        if (_attr == NSLayoutAttributeWidth) s.width = c; else s.height = c;
        [v setFrameSize:s];
    }
    return [self _mwTo:nil rel:NSLayoutRelationEqual m:1 c:c];
}
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToConstant:(CGFloat)c { return [self _mwTo:nil rel:NSLayoutRelationGreaterThanOrEqual m:1 c:c]; }
- (NSLayoutConstraint *)constraintLessThanOrEqualToConstant:(CGFloat)c { return [self _mwTo:nil rel:NSLayoutRelationLessThanOrEqual m:1 c:c]; }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m { return [self _mwTo:a rel:NSLayoutRelationEqual m:m c:0]; }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m constant:(CGFloat)c { return [self _mwTo:a rel:NSLayoutRelationEqual m:m c:c]; }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m { return [self _mwTo:a rel:NSLayoutRelationGreaterThanOrEqual m:m c:0]; }
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m { return [self _mwTo:a rel:NSLayoutRelationLessThanOrEqual m:m c:0]; }
@end
#define ANCHORS(cls) \
- (NSLayoutXAxisAnchor *)leadingAnchor { return [NSLayoutXAxisAnchor _mw:self attr:NSLayoutAttributeLeading]; } \
- (NSLayoutXAxisAnchor *)trailingAnchor { return [NSLayoutXAxisAnchor _mw:self attr:NSLayoutAttributeTrailing]; } \
- (NSLayoutXAxisAnchor *)leftAnchor { return [NSLayoutXAxisAnchor _mw:self attr:NSLayoutAttributeLeft]; } \
- (NSLayoutXAxisAnchor *)rightAnchor { return [NSLayoutXAxisAnchor _mw:self attr:NSLayoutAttributeRight]; } \
- (NSLayoutXAxisAnchor *)centerXAnchor { return [NSLayoutXAxisAnchor _mw:self attr:NSLayoutAttributeCenterX]; } \
- (NSLayoutYAxisAnchor *)topAnchor { return [NSLayoutYAxisAnchor _mw:self attr:NSLayoutAttributeTop]; } \
- (NSLayoutYAxisAnchor *)bottomAnchor { return [NSLayoutYAxisAnchor _mw:self attr:NSLayoutAttributeBottom]; } \
- (NSLayoutYAxisAnchor *)centerYAnchor { return [NSLayoutYAxisAnchor _mw:self attr:NSLayoutAttributeCenterY]; } \
- (NSLayoutDimension *)widthAnchor { return [NSLayoutDimension _mw:self attr:NSLayoutAttributeWidth]; } \
- (NSLayoutDimension *)heightAnchor { return [NSLayoutDimension _mw:self attr:NSLayoutAttributeHeight]; }
@interface NSLayoutAnchor (MW) + (instancetype)_mw:(id)item attr:(NSLayoutAttribute)a; @end
@implementation NSLayoutGuide
ANCHORS(NSLayoutGuide)
- (NSRect)frame { return _owningView ? (_mwSafeArea ? _owningView.safeAreaRect : _owningView.bounds) : NSZeroRect; }
- (void)dealloc { [_identifier release]; [super dealloc]; }
@end
@implementation NSView (MWAnchors)
ANCHORS(NSView)
- (NSLayoutYAxisAnchor *)firstBaselineAnchor { return [NSLayoutYAxisAnchor _mw:self attr:NSLayoutAttributeFirstBaseline]; }
- (NSLayoutYAxisAnchor *)lastBaselineAnchor { return [NSLayoutYAxisAnchor _mw:self attr:NSLayoutAttributeLastBaseline]; }
@end
@implementation NSView (NSLayoutGuideSupport)
- (void)addLayoutGuide:(NSLayoutGuide *)g { g.owningView = self; }
- (void)removeLayoutGuide:(NSLayoutGuide *)g { g.owningView = nil; }
- (NSArray *)layoutGuides { return @[]; }
- (NSLayoutGuide *)safeAreaLayoutGuide { NSLayoutGuide *g = [[[NSLayoutGuide alloc] init] autorelease]; g.owningView = self; g->_mwSafeArea = YES; return g; }
- (NSLayoutGuide *)layoutMarginsGuide { return [self safeAreaLayoutGuide]; }
@end
@implementation NSAnimationContext
+ (NSAnimationContext *)currentContext { static NSAnimationContext *c; if (!c) c = [[self alloc] init]; return c; }
/* no animations: the changes apply at once, the completion runs on the next pass of the main loop */
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *))changes completionHandler:(void (^)(void))done {
    if (changes) changes([self currentContext]);
    if (done) dispatch_async(dispatch_get_main_queue(), done);
}
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *))changes { [self runAnimationGroup:changes completionHandler:nil]; }
+ (void)beginGrouping { } + (void)endGrouping { }
@end

/* ======================================================================= controls
 * Drawn in an approximation of the macOS dark appearance. Setters that change what a control shows mark it for display. */
static NSColor *W(CGFloat a) { return [NSColor colorWithWhite:1 alpha:a]; }
static NSFont *cfont(NSControl *c) { return c.font ? c.font : [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:c.controlSize]]; }
static BOOL inside(NSView *v, NSEvent *e) { return NSMouseInRect([v convertPoint:e.locationInWindow fromView:nil], v.bounds, v.isFlipped); }
static NSPoint local(NSView *v, NSEvent *e) { return [v convertPoint:e.locationInWindow fromView:nil]; }
static NSRect center_rect(NSRect b, CGFloat w, CGFloat h) { return NSMakeRect(b.origin.x + (b.size.width - w) / 2, b.origin.y + (b.size.height - h) / 2, w, h); }
#define SET_OBJ(Name, ivar, Type) - (void)set##Name:(Type)v { [v retain]; [ivar release]; ivar = v; self.needsDisplay = YES; }
#define SET_VAL(Name, ivar, Type) - (void)set##Name:(Type)v { ivar = v; self.needsDisplay = YES; }

@implementation NSCell { NSString *_title; NSAttributedString *_attributedStringValue; }
- (instancetype)init { if ((self = [super init])) { _enabled = YES; _type = 1; } return self; }
- (instancetype)initTextCell:(NSString *)s { if ((self = [self init])) self.stringValue = s; return self; }
- (instancetype)initImageCell:(NSImage *)i { if ((self = [self init])) { _type = 2; self.image = i; } return self; }
- (void)dealloc { [_stringValue release]; [_title release]; [_objectValue release]; [_font release]; [_image release]; [_attributedStringValue release];
    [_formatter release]; [_representedObject release]; [_menu release]; [_keyEquivalent release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
    NSCell *c = [[[self class] alloc] init];
    c.objectValue = _objectValue; c.state = _state; c.font = _font; c.alignment = _alignment; c.image = _image; c.enabled = _enabled;
    c.tag = _tag; c.action = _action; c.target = _target; c.formatter = _formatter; c.lineBreakMode = _lineBreakMode; c.controlView = _controlView;
    return c;
}
/* the value: objectValue, with the string form kept in step */
- (void)setObjectValue:(id)o {
    [o retain]; [_objectValue release]; _objectValue = o;
    NSString *s = _formatter && o ? [_formatter stringForObjectValue:o] : [o isKindOfClass:[NSString class]] ? o : [o isKindOfClass:[NSAttributedString class]] ? [o string] : [o description];
    [_stringValue release]; _stringValue = [s ?: @"" copy];
    [_controlView setNeedsDisplay:YES];
}
- (void)setStringValue:(NSString *)s { self.objectValue = [[s ?: @"" copy] autorelease]; }
- (NSString *)title { return _title ?: _stringValue ?: @""; }
- (void)setTitle:(NSString *)t { [_title release]; _title = [t copy]; if (_type != 2) self.stringValue = t; }
- (NSAttributedString *)attributedStringValue { return _attributedStringValue ?: [[[NSAttributedString alloc] initWithString:self.stringValue ?: @""] autorelease]; }
- (void)setAttributedStringValue:(NSAttributedString *)a { [_attributedStringValue release]; _attributedStringValue = [a copy]; self.stringValue = a.string; }
- (int)intValue { return [_objectValue respondsToSelector:@selector(intValue)] ? [_objectValue intValue] : 0; }
- (void)setIntValue:(int)v { self.objectValue = @(v); }
- (NSInteger)integerValue { return [_objectValue respondsToSelector:@selector(integerValue)] ? [_objectValue integerValue] : 0; }
- (void)setIntegerValue:(NSInteger)v { self.objectValue = @(v); }
- (float)floatValue { return [_objectValue respondsToSelector:@selector(floatValue)] ? [_objectValue floatValue] : 0; }
- (void)setFloatValue:(float)v { self.objectValue = @(v); }
- (double)doubleValue { return [_objectValue respondsToSelector:@selector(doubleValue)] ? [_objectValue doubleValue] : 0; }
- (void)setDoubleValue:(double)v { self.objectValue = @(v); }
- (BOOL)boolValue { return [_objectValue respondsToSelector:@selector(boolValue)] && [_objectValue boolValue]; }
- (void)setNextState { self.state = _state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn; }
- (NSInteger)nextState { return _state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn; }
- (BOOL)acceptsFirstResponder { return _enabled && !_refusesFirstResponder; }
- (NSInteger)interiorBackgroundStyle { return _backgroundStyle; }
- (NSSize)cellSize { return [self cellSizeForBounds:NSMakeRect(0, 0, 1e5, 1e5)]; }
- (NSSize)cellSizeForBounds:(NSRect)r {
    if (_type == 2 && _image) return _image.size;
    NSSize t = mw_text_size(self.stringValue, _font ?: [NSFont systemFontOfSize:13]);
    return NSMakeSize(ceil(t.width) + 4, ceil(t.height) + 2);
}
- (NSRect)drawingRectForBounds:(NSRect)r { return NSInsetRect(r, 2, 0); }
- (NSRect)titleRectForBounds:(NSRect)r { return [self drawingRectForBounds:r]; }
- (NSRect)imageRectForBounds:(NSRect)r { return r; }
- (void)drawWithFrame:(NSRect)f inView:(NSView *)v { [self drawInteriorWithFrame:f inView:v]; }
- (void)drawInteriorWithFrame:(NSRect)f inView:(NSView *)v {
    if (_type == 2 || ([_objectValue isKindOfClass:[NSImage class]])) { mw_draw_image(_image ?: _objectValue, [self imageRectForBounds:f], nil, _enabled ? 1 : 0.5); return; }
    NSColor *c = [self respondsToSelector:@selector(textColor)] ? [(id)self textColor] : nil;
    if (!c) c = _enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
    mw_draw_text_in(self.stringValue, [self titleRectForBounds:f], _font ?: [NSFont systemFontOfSize:13], c, _alignment, _lineBreakMode ?: NSLineBreakByTruncatingTail, _wraps, YES);
}
- (void)highlight:(BOOL)f withFrame:(NSRect)r inView:(NSView *)v { _highlighted = f; [v setNeedsDisplay:YES]; }
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v untilMouseUp:(BOOL)u { return YES; }
- (NSRect)expansionFrameWithFrame:(NSRect)f inView:(NSView *)v { return NSZeroRect; }
- (NSUInteger)hitTestForEvent:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v { return 1; }
- (void)resetCursorRect:(NSRect)r inView:(NSView *)v {}
- (void)endEditing:(NSText *)t {}
- (void)drawFocusRingMaskWithFrame:(NSRect)f inView:(NSView *)v {}
- (NSRect)focusRingMaskBoundsForFrame:(NSRect)f inView:(NSView *)v { return f; }
@end
@implementation NSControl
+ (Class)cellClass { return [NSCell class]; }
+ (void)setCellClass:(Class)c { }
- (instancetype)initWithFrame:(NSRect)r { if ((self = [super initWithFrame:r])) { _enabled = YES; _stringValue = @""; } return self; }
- (void)dealloc { [_stringValue release]; [_attributedStringValue release]; [_objectValue release]; [_font release]; [_formatter release]; [_cell release]; [super dealloc]; }
- (void)setStringValue:(NSString *)s {
    s = [[s ? s : @"" copy] autorelease];
    if ([s isEqualToString:_stringValue] && [_objectValue isEqual:s]) return;
    [_stringValue release]; _stringValue = [s retain]; [_objectValue release]; _objectValue = [s retain];
    [self invalidateIntrinsicContentSize]; self.needsDisplay = YES;
}
- (void)setAttributedStringValue:(NSAttributedString *)s { [_attributedStringValue release]; _attributedStringValue = [s copy]; self.stringValue = s.string; }
- (void)setObjectValue:(id)o { [o retain]; [_objectValue release]; _objectValue = o; [_stringValue release]; _stringValue = [([o description] ? [o description] : @"") copy]; self.needsDisplay = YES; }
- (int)intValue { return [_stringValue intValue]; }
- (void)setIntValue:(int)v { self.stringValue = [NSString stringWithFormat:@"%d", v]; }
- (NSInteger)integerValue { return [_stringValue integerValue]; }
- (void)setIntegerValue:(NSInteger)v { self.stringValue = [NSString stringWithFormat:@"%ld", (long)v]; }
- (float)floatValue { return [_stringValue floatValue]; }
- (void)setFloatValue:(float)v { self.stringValue = [NSString stringWithFormat:@"%.9g", v]; }
- (double)doubleValue { return [_stringValue doubleValue]; }
- (void)setDoubleValue:(double)v { self.stringValue = [NSString stringWithFormat:@"%.17g", v]; }
- (void)setFont:(NSFont *)f { [f retain]; [_font release]; _font = f; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
- (void)setControlSize:(NSControlSize)s { _controlSize = s; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
SET_VAL(Enabled, _enabled, BOOL)
SET_VAL(Highlighted, _highlighted, BOOL)
SET_VAL(Alignment, _alignment, NSTextAlignment)
SET_VAL(LineBreakMode, _lineBreakMode, NSLineBreakMode)
- (BOOL)sendAction:(SEL)a to:(id)t { return a ? [NSApp sendAction:a to:t from:self] : NO; }
- (void)performClick:(id)s { if (_enabled) [self sendAction:_action to:_target]; }
- (void)sizeToFit { NSSize s = [self intrinsicContentSize]; if (s.width > 0 && s.height > 0) [self setFrameSize:s]; }
- (NSSize)sizeThatFits:(NSSize)s { return [self intrinsicContentSize]; }
- (void)takeStringValueFrom:(id)s { self.stringValue = [s stringValue]; }
- (void)takeIntValueFrom:(id)s { self.intValue = [s intValue]; }
- (void)takeDoubleValueFrom:(id)s { self.doubleValue = [s doubleValue]; }
/* pressed while the mouse is down inside; a click is a release inside */
- (void)mouseDown:(NSEvent *)e { if (_enabled) self.highlighted = YES; }
- (void)mouseDragged:(NSEvent *)e { if (_enabled && inside(self, e) != _highlighted) self.highlighted = !_highlighted; }
- (void)mouseUp:(NSEvent *)e { self.highlighted = NO; if (inside(self, e)) [self performClick:self]; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
@end

@implementation NSButton { NSButtonType _type; }
+ (instancetype)buttonWithTitle:(NSString *)t target:(id)tg action:(SEL)a {
    NSButton *b = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    b.title = t; b.target = tg; b.action = a; b.bezelStyle = NSBezelStyleRounded; [b sizeToFit];
    return b;
}
+ (instancetype)buttonWithImage:(NSImage *)i target:(id)tg action:(SEL)a { NSButton *b = [self buttonWithTitle:@"" target:tg action:a]; b.image = i; [b sizeToFit]; return b; }
+ (instancetype)buttonWithTitle:(NSString *)t image:(NSImage *)i target:(id)tg action:(SEL)a { NSButton *b = [self buttonWithTitle:t target:tg action:a]; b.image = i; [b sizeToFit]; return b; }
+ (instancetype)checkboxWithTitle:(NSString *)t target:(id)tg action:(SEL)a { NSButton *b = [self buttonWithTitle:t target:tg action:a]; [b setButtonType:NSButtonTypeSwitch]; [b sizeToFit]; return b; }
+ (instancetype)radioButtonWithTitle:(NSString *)t target:(id)tg action:(SEL)a { NSButton *b = [self buttonWithTitle:t target:tg action:a]; [b setButtonType:NSButtonTypeRadio]; [b sizeToFit]; return b; }
- (instancetype)initWithFrame:(NSRect)r { if ((self = [super initWithFrame:r])) { _title = @"Button"; _bordered = YES; _keyEquivalent = @""; _keyEquivalentModifierMask = 0; } return self; }
- (void)dealloc {
    [_title release]; [_alternateTitle release]; [_keyEquivalent release]; [_attributedTitle release]; [_image release]; [_alternateImage release];
    [_bezelColor release]; [_contentTintColor release]; [super dealloc];
}
- (void)setButtonType:(NSButtonType)t { _type = t; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
- (void)setTitle:(NSString *)t { [_title release]; _title = [t ? t : @"" copy]; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
- (void)setAttributedTitle:(NSAttributedString *)t { [_attributedTitle release]; _attributedTitle = [t copy]; self.title = t.string; }
- (void)setImage:(NSImage *)i { [i retain]; [_image release]; _image = i; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
SET_OBJ(ContentTintColor, _contentTintColor, NSColor *)
SET_OBJ(BezelColor, _bezelColor, NSColor *)
SET_VAL(State, _state, NSControlStateValue)
SET_VAL(Bordered, _bordered, BOOL)
SET_VAL(Transparent, _transparent, BOOL)
SET_VAL(ImagePosition, _imagePosition, NSInteger)
- (NSString *)stringValue { return [NSString stringWithFormat:@"%ld", (long)_state]; }
- (NSInteger)integerValue { return _state; }
- (int)intValue { return (int)_state; }
- (void)setIntValue:(int)v { self.state = v; }
- (void)setIntegerValue:(NSInteger)v { self.state = v; }
- (void)setNextState {
    if (_type == NSButtonTypeSwitch || _type == NSButtonTypePushOnPushOff || _type == NSButtonTypeToggle || _type == NSButtonTypeOnOff)
        self.state = (_allowsMixedState && _state == NSControlStateValueOff) ? NSControlStateValueMixed : _state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn;
    else if (_type == NSButtonTypeRadio) {
        self.state = NSControlStateValueOn;
        /* radio buttons with the same action in the same superview form a group */
        for (NSView *v in self.superview.subviews)
            if (v != self && [v isKindOfClass:[NSButton class]] && ((NSButton *)v)->_type == NSButtonTypeRadio && ((NSButton *)v).action == self.action) ((NSButton *)v).state = NSControlStateValueOff;
    }
}
- (void)performClick:(id)s { if (!self.isEnabled) return; [self setNextState]; [super performClick:s]; }
- (void)highlight:(BOOL)f { self.highlighted = f; }
- (BOOL)validateUserInterfaceItem:(id)i { return YES; }
- (BOOL)performKeyEquivalent:(NSEvent *)e {
    if (![_keyEquivalent length] || !self.isEnabled || self.isHiddenOrHasHiddenAncestor) return NO;
    NSEventModifierFlags m = e.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption);
    if (![e.charactersIgnoringModifiers isEqualToString:_keyEquivalent] || m != (_keyEquivalentModifierMask & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption))) return NO;
    [self performClick:self];
    return YES;
}
- (BOOL)_mwCheck { return _type == NSButtonTypeSwitch || _type == NSButtonTypeRadio; }
- (NSSize)intrinsicContentSize {
    NSSize t = [_title length] ? text_size(_title, cfont(self)) : NSZeroSize;
    if ([self _mwCheck]) return NSMakeSize(ceil(t.width) + 22, 18);
    CGFloat iw = _image ? fmax(_image.size.width, 16) : 0, gap = iw > 0 && t.width > 0 ? 4 : 0;
    CGFloat h = self.controlSize == NSControlSizeSmall ? 19 : self.controlSize == NSControlSizeMini ? 16 : 21;
    if (!_bordered && _image && !t.width) return NSMakeSize(iw + 4, fmax(_image.size.height, 16) + 4);
    return NSMakeSize(ceil(iw + gap + t.width) + (t.width > 0 ? 24 : 10), h);
}
- (void)drawRect:(NSRect)r {
    if (_transparent) return;
    NSRect b = self.bounds;
    BOOL en = self.isEnabled, on = _state == NSControlStateValueOn;
    NSFont *f = cfont(self);
    NSColor *text = en ? [NSColor labelColor] : [NSColor disabledControlTextColor];
    if ([self _mwCheck]) {
        NSRect box = NSMakeRect(b.origin.x + 1, b.origin.y + (b.size.height - 14) / 2, 14, 14);
        BOOL filled = on || _state == NSControlStateValueMixed;
        if (_type == NSButtonTypeRadio) {
            NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:box];
            [(filled ? [NSColor controlAccentColor] : W(self.isHighlighted ? 0.3 : 0.15)) setFill]; [o fill];
            if (!filled) { [W(0.3) setStroke]; o.lineWidth = 1; [o stroke]; }
            else { [[NSColor whiteColor] setFill]; [[NSBezierPath bezierPathWithOvalInRect:center_rect(box, 6, 6)] fill]; }
        } else {
            mw_fill_round(box, 3.5, filled ? [NSColor controlAccentColor] : W(self.isHighlighted ? 0.3 : 0.15));
            if (!filled) mw_stroke_round(box, 3.5, 1, W(0.3));
            [[NSColor whiteColor] setStroke];
            NSBezierPath *p = [NSBezierPath bezierPath];
            p.lineWidth = 2; p.lineCapStyle = NSLineCapStyleRound; p.lineJoinStyle = NSLineJoinStyleRound;
            BOOL up = !self.isFlipped;
            CGFloat x = box.origin.x, y = box.origin.y, k = up ? 1 : -1, y0 = up ? y : NSMaxY(box);
            if (_state == NSControlStateValueMixed) { [p moveToPoint:NSMakePoint(x + 3.5, y + 7)]; [p lineToPoint:NSMakePoint(x + 10.5, y + 7)]; [p stroke]; }
            else if (on) {
                [p moveToPoint:NSMakePoint(x + 3.5, y0 + k * 7.5)]; [p lineToPoint:NSMakePoint(x + 6, y0 + k * 4.5)]; [p lineToPoint:NSMakePoint(x + 10.5, y0 + k * 10)];
                [p stroke];
            }
        }
        mw_draw_text_in(_title, NSMakeRect(b.origin.x + 20, b.origin.y, fmax(0, b.size.width - 20), b.size.height), f, text, NSTextAlignmentLeft,
                        NSLineBreakByTruncatingTail, NO, YES);
        return;
    }
    CGFloat ch = fmin(b.size.height, self.controlSize == NSControlSizeMini ? 16 : self.controlSize == NSControlSizeSmall ? 19 : 22);
    NSRect bezel = _bordered ? NSInsetRect(center_rect(b, b.size.width, ch), 1, 0) : b;
    if (_bordered) {
        BOOL deflt = [_keyEquivalent isEqualToString:@"\r"];
        BOOL toggled = on && (_type == NSButtonTypePushOnPushOff || _type == NSButtonTypeToggle || _type == NSButtonTypeOnOff);
        NSColor *fill = deflt ? [NSColor controlAccentColor] : _bezelColor ? _bezelColor : W(toggled ? 0.32 : 0.2);
        mw_fill_round(bezel, fmin(5, ch / 2), en ? fill : W(0.1));
        if (self.isHighlighted) mw_fill_round(bezel, fmin(5, ch / 2), W(0.15));
    } else if (self.isHighlighted) text = [text colorWithAlphaComponent:text.alphaComponent * 0.6];
    NSColor *content = _contentTintColor ? (en ? _contentTintColor : [_contentTintColor colorWithAlphaComponent:0.3]) : text;
    NSString *title = _imagePosition == NSImageOnly ? @"" : _title;
    CGFloat tw = [title length] ? text_size(title, f).width : 0;
    NSSize is = _image ? _image.size : NSZeroSize;
    if (_image && [_image respondsToSelector:@selector(_mwSymbol)] && [(id)_image _mwSymbol]) { /* symbols scale with the control */
        CGFloat side = fmin(fmin(bezel.size.width, bezel.size.height) - 4, f.pointSize * 1.3);
        is = NSMakeSize(side, side);
    }
    CGFloat gap = _image && tw > 0 ? 4 : 0, total = is.width + gap + tw, x = bezel.origin.x + (bezel.size.width - total) / 2;
    if (_image) mw_draw_image(_image, NSMakeRect(round(x), bezel.origin.y + (bezel.size.height - is.height) / 2, is.width, is.height), content, 1);
    if (tw > 0) mw_draw_text_in(title, NSMakeRect(x + is.width + gap, bezel.origin.y, tw + 1, bezel.size.height), f, content, NSTextAlignmentLeft,
                                NSLineBreakByClipping, NO, YES);
}
@end

@implementation NSTextField { BOOL _mwWraps; }
+ (instancetype)labelWithString:(NSString *)s {
    NSTextField *f = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    f.stringValue = s; f.editable = NO; f.selectable = NO; f.bezeled = NO; f.bordered = NO; f.drawsBackground = NO; [f sizeToFit];
    return f;
}
+ (instancetype)wrappingLabelWithString:(NSString *)s { NSTextField *f = [self labelWithString:s]; f.selectable = YES; f->_mwWraps = YES; return f; }
+ (instancetype)labelWithAttributedString:(NSAttributedString *)s { NSTextField *f = [self labelWithString:s.string]; f.attributedStringValue = s; return f; }
+ (instancetype)textFieldWithString:(NSString *)s {
    NSTextField *f = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    f.stringValue = s; f.editable = YES; f.selectable = YES; f.bezeled = YES; f.drawsBackground = YES;
    [f setFrameSize:NSMakeSize(96, 21)];
    return f;
}
- (instancetype)initWithFrame:(NSRect)r { if ((self = [super initWithFrame:r])) { _editable = YES; _selectable = YES; _bezeled = YES; } return self; }
- (void)dealloc { [_placeholderString release]; [_placeholderAttributedString release]; [_textColor release]; [_backgroundColor release]; [super dealloc]; }
SET_OBJ(TextColor, _textColor, NSColor *)
SET_OBJ(BackgroundColor, _backgroundColor, NSColor *)
SET_VAL(DrawsBackground, _drawsBackground, BOOL)
SET_VAL(Bezeled, _bezeled, BOOL)
SET_VAL(Bordered, _bordered, BOOL)
- (void)setPlaceholderString:(NSString *)s { [_placeholderString release]; _placeholderString = [s copy]; self.needsDisplay = YES; }
- (void)_mwSetWraps:(BOOL)w { _mwWraps = w; }
- (BOOL)_mwWrapping { return _mwWraps || (_maximumNumberOfLines != 1 && _preferredMaxLayoutWidth > 0); }
- (NSSize)intrinsicContentSize {
    NSFont *f = cfont(self);
    /* a wrapping label without preferredMaxLayoutWidth wraps at the width layout gave it (Auto Layout's automatic width) */
    CGFloat maxw = _preferredMaxLayoutWidth > 0 ? _preferredMaxLayoutWidth : _mwWraps && self.frame.size.width > 4 ? self.frame.size.width : 0;
    NSSize t = [self _mwWrapping] || maxw > 0 ? mw_text_size_wrapped(self.stringValue, f, maxw - 4) : text_size(self.stringValue, f);
    if (maxw > 0 && _preferredMaxLayoutWidth <= 0) t.width = fmin(t.width, maxw - 4);
    if (![self.stringValue length]) t.height = text_size(@"X", f).height;
    return _bezeled || _bordered ? NSMakeSize(fmax(ceil(t.width) + 8, 40), ceil(t.height) + 5) : NSMakeSize(ceil(t.width) + 4, ceil(t.height));
}
- (BOOL)acceptsFirstResponder { return _editable || _selectable; }
- (BOOL)becomeFirstResponder { self.needsDisplay = YES; return YES; }
- (BOOL)resignFirstResponder { self.needsDisplay = YES; return YES; }
- (void)selectText:(id)s { [self.window makeFirstResponder:self]; }
- (BOOL)validateUserInterfaceItem:(id)i { return YES; }
- (void)mouseDown:(NSEvent *)e { if (_editable || _selectable) [self.window makeFirstResponder:self]; }
- (void)mouseUp:(NSEvent *)e { }
/* minimal editing: typing appends, Backspace deletes the last character, Return sends the action */
- (void)keyDown:(NSEvent *)e { if (_editable) [self interpretKeyEvents:@[e]]; else [super keyDown:e]; }
- (void)_mwChanged {
    if ([(id)self.delegate respondsToSelector:@selector(controlTextDidChange:)])
        [self.delegate controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:self]];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:self];
}
- (void)insertText:(id)s {
    NSString *t = [s isKindOfClass:[NSAttributedString class]] ? [s string] : s;
    self.stringValue = [self.stringValue stringByAppendingString:t];
    [self _mwChanged];
}
- (void)deleteBackward:(id)s { NSString *v = self.stringValue; if ([v length]) { self.stringValue = [v substringToIndex:[v length] - 1]; [self _mwChanged]; } }
- (void)insertNewline:(id)s { [self sendAction:self.action to:self.target]; }
- (void)insertTab:(id)s { [self.window selectNextKeyView:self]; }
- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds;
    BOOL en = self.isEnabled, field = _bezeled || _bordered;
    if (field) {
        mw_fill_round(b, _bezeled ? 4 : 0, _drawsBackground ? (_backgroundColor ? _backgroundColor : [NSColor textBackgroundColor]) : W(0.05));
        BOOL focus = self.window.firstResponder == self && _editable;
        mw_stroke_round(b, _bezeled ? 4 : 0, focus ? 2 : 1, focus ? [NSColor keyboardFocusIndicatorColor] : W(0.2));
    } else if (_drawsBackground && _backgroundColor) mw_fill_round(b, 0, _backgroundColor);
    NSString *s = self.stringValue;
    NSFont *f = cfont(self);
    NSColor *c = _textColor ? _textColor : field ? [NSColor textColor] : [NSColor labelColor];
    if (!en) c = [c colorWithAlphaComponent:c.alphaComponent * 0.35];
    if (![s length] && [_placeholderString length]) { s = _placeholderString; c = [NSColor placeholderTextColor]; }
    BOOL wrap = [self _mwWrapping] && !field;
    NSRect t = field ? NSInsetRect(b, 4, 1) : NSInsetRect(b, 2, 0);
    mw_draw_text_in(s, t, f, c, self.alignment, wrap ? self.lineBreakMode : (self.lineBreakMode == NSLineBreakByWordWrapping ? NSLineBreakByClipping : self.lineBreakMode),
                    wrap, field || !wrap);
}
@end
@implementation NSSecureTextField
- (void)drawRect:(NSRect)r {
    NSString *real = [[self.stringValue retain] autorelease], *dots = [@"" stringByPaddingToLength:[real length] withString:@"•" startingAtIndex:0];
    [super setStringValue:dots]; [super drawRect:r]; [super setStringValue:real];
}
@end
@implementation NSSearchField @end

@implementation NSSegmentedControl { NSMutableArray *_labels, *_widths, *_tags, *_images, *_enabledSegs; NSMutableSet *_sel; NSInteger _pressed; }
+ (instancetype)segmentedControlWithLabels:(NSArray *)l trackingMode:(NSSegmentSwitchTracking)m target:(id)t action:(SEL)a {
    NSSegmentedControl *c = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    c.segmentCount = (NSInteger)[l count];
    for (NSUInteger i = 0; i < [l count]; i++) [c setLabel:l[i] forSegment:(NSInteger)i];
    c.trackingMode = m; c.target = t; c.action = a;
    [c sizeToFit];
    return c;
}
+ (instancetype)segmentedControlWithImages:(NSArray *)i trackingMode:(NSSegmentSwitchTracking)m target:(id)t action:(SEL)a {
    NSMutableArray *l = [NSMutableArray array];
    for (NSUInteger k = 0; k < [i count]; k++) [l addObject:@""];
    NSSegmentedControl *c = [self segmentedControlWithLabels:l trackingMode:m target:t action:a];
    for (NSUInteger k = 0; k < [i count]; k++) [c setImage:i[k] forSegment:(NSInteger)k];
    return c;
}
- (instancetype)initWithFrame:(NSRect)r {
    if ((self = [super initWithFrame:r])) {
        _labels = [[NSMutableArray alloc] init]; _widths = [[NSMutableArray alloc] init]; _tags = [[NSMutableArray alloc] init];
        _images = [[NSMutableArray alloc] init]; _enabledSegs = [[NSMutableArray alloc] init]; _sel = [[NSMutableSet alloc] init];
        _selectedSegment = -1; _pressed = -1;
    }
    return self;
}
- (void)dealloc { [_labels release]; [_widths release]; [_tags release]; [_images release]; [_enabledSegs release]; [_sel release]; [_selectedSegmentBezelColor release]; [super dealloc]; }
- (void)setSegmentCount:(NSInteger)n {
    _segmentCount = n;
    while ((NSInteger)[_labels count] < n) { [_labels addObject:@""]; [_widths addObject:@0]; [_tags addObject:@0]; [_images addObject:[NSNull null]]; [_enabledSegs addObject:@YES]; }
    while ((NSInteger)[_labels count] > n) { [_labels removeLastObject]; [_widths removeLastObject]; [_tags removeLastObject]; [_images removeLastObject]; [_enabledSegs removeLastObject]; }
    [self invalidateIntrinsicContentSize]; self.needsDisplay = YES;
}
- (void)setSelectedSegment:(NSInteger)s {
    _selectedSegment = s;
    if (_trackingMode != NSSegmentSwitchTrackingSelectAny) [_sel removeAllObjects];
    if (s >= 0) [_sel addObject:@(s)];
    self.needsDisplay = YES;
}
SET_VAL(SegmentDistribution, _segmentDistribution, NSSegmentDistribution)
SET_OBJ(SelectedSegmentBezelColor, _selectedSegmentBezelColor, NSColor *)
- (NSInteger)indexOfSelectedItem { return _selectedSegment; }
- (void)setLabel:(NSString *)l forSegment:(NSInteger)s { if (s >= 0 && s < _segmentCount) { _labels[(NSUInteger)s] = l ? l : @""; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; } }
- (NSString *)labelForSegment:(NSInteger)s { return s >= 0 && s < _segmentCount ? _labels[(NSUInteger)s] : nil; }
- (void)setWidth:(CGFloat)w forSegment:(NSInteger)s { if (s >= 0 && s < _segmentCount) { _widths[(NSUInteger)s] = @(w); [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; } }
- (CGFloat)widthForSegment:(NSInteger)s { return s >= 0 && s < _segmentCount ? [_widths[(NSUInteger)s] doubleValue] : 0; }
- (void)setEnabled:(BOOL)e forSegment:(NSInteger)s { if (s >= 0 && s < _segmentCount) { _enabledSegs[(NSUInteger)s] = @(e); self.needsDisplay = YES; } }
- (BOOL)isEnabledForSegment:(NSInteger)s { return s >= 0 && s < _segmentCount && [_enabledSegs[(NSUInteger)s] boolValue]; }
- (void)setSelected:(BOOL)f forSegment:(NSInteger)s {
    if (f) { if (_trackingMode != NSSegmentSwitchTrackingSelectAny) [_sel removeAllObjects]; [_sel addObject:@(s)]; _selectedSegment = s; }
    else { [_sel removeObject:@(s)]; if (_selectedSegment == s) _selectedSegment = -1; }
    self.needsDisplay = YES;
}
- (BOOL)isSelectedForSegment:(NSInteger)s { return [_sel containsObject:@(s)]; }
- (void)setImage:(NSImage *)i forSegment:(NSInteger)s { if (s >= 0 && s < _segmentCount) { _images[(NSUInteger)s] = i ? (id)i : [NSNull null]; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; } }
- (NSImage *)imageForSegment:(NSInteger)s { id i = s >= 0 && s < _segmentCount ? _images[(NSUInteger)s] : nil; return i == [NSNull null] ? nil : i; }
- (void)setToolTip:(NSString *)t forSegment:(NSInteger)s { }
- (void)setTag:(NSInteger)t forSegment:(NSInteger)s { if (s >= 0 && s < _segmentCount) _tags[(NSUInteger)s] = @(t); }
- (NSInteger)tagForSegment:(NSInteger)s { return s >= 0 && s < _segmentCount ? [_tags[(NSUInteger)s] integerValue] : 0; }
- (BOOL)selectSegmentWithTag:(NSInteger)t { for (NSInteger i = 0; i < _segmentCount; i++) if ([self tagForSegment:i] == t) { self.selectedSegment = i; return YES; } return NO; }
- (void)setMenu:(NSMenu *)m forSegment:(NSInteger)s { }
- (NSInteger)integerValue { return _selectedSegment; }
- (CGFloat)_mwNatural:(NSInteger)i {
    CGFloat w = [self widthForSegment:i];
    if (w > 0) return w;
    return fmax(text_size(_labels[(NSUInteger)i], cfont(self)).width + 18, [self imageForSegment:i] ? 30 : 0);
}
- (NSSize)intrinsicContentSize {
    CGFloat w = 0;
    for (NSInteger i = 0; i < _segmentCount; i++) w += [self _mwNatural:i];
    return NSMakeSize(ceil(w) + 2, self.controlSize == NSControlSizeMini ? 16 : self.controlSize == NSControlSizeSmall ? 20 : 24);
}
/* the segments' widths across the bounds: fixed ones stay, the others share the rest (equally or by their natural size) */
- (void)_mwWidths:(CGFloat *)out {
    CGFloat fixed = 0, natural = 0, avail = self.bounds.size.width - 2;
    NSInteger loose = 0;
    for (NSInteger i = 0; i < _segmentCount; i++) {
        if ([self widthForSegment:i] > 0) fixed += [self widthForSegment:i];
        else { natural += [self _mwNatural:i]; loose++; }
    }
    for (NSInteger i = 0; i < _segmentCount; i++) {
        if ([self widthForSegment:i] > 0) out[i] = [self widthForSegment:i];
        else if (_segmentDistribution == NSSegmentDistributionFillEqually) out[i] = (avail - fixed) / loose;
        else out[i] = natural > 0 && _segmentDistribution != NSSegmentDistributionFit ? [self _mwNatural:i] * (avail - fixed) / natural : [self _mwNatural:i];
    }
}
- (NSInteger)_mwSegmentAt:(NSPoint)p {
    CGFloat w[_segmentCount > 0 ? _segmentCount : 1], x = self.bounds.origin.x + 1;
    [self _mwWidths:w];
    for (NSInteger i = 0; i < _segmentCount; i++) { if (p.x >= x && p.x < x + w[i]) return i; x += w[i]; }
    return -1;
}
- (void)mouseDown:(NSEvent *)e {
    NSInteger s = [self _mwSegmentAt:local(self, e)];
    _pressed = self.isEnabled && [self isEnabledForSegment:s] ? s : -1;
    self.needsDisplay = YES;
}
- (void)mouseDragged:(NSEvent *)e { }
- (void)mouseUp:(NSEvent *)e {
    NSInteger s = [self _mwSegmentAt:local(self, e)], p = _pressed;
    _pressed = -1; self.needsDisplay = YES;
    if (s < 0 || s != p) return;
    if (_trackingMode == NSSegmentSwitchTrackingSelectAny) [self setSelected:![self isSelectedForSegment:s] forSegment:s];
    else self.selectedSegment = s;
    [self sendAction:self.action to:self.target];
    if (_trackingMode == NSSegmentSwitchTrackingMomentary) { [_sel removeAllObjects]; _selectedSegment = -1; }
}
- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds;
    CGFloat h = fmin(b.size.height, [self intrinsicContentSize].height), w[_segmentCount > 0 ? _segmentCount : 1];
    NSRect track = center_rect(b, b.size.width, h);
    mw_fill_round(track, 6, W(0.1));
    [self _mwWidths:w];
    NSFont *f = cfont(self);
    CGFloat x = track.origin.x + 1;
    for (NSInteger i = 0; i < _segmentCount; i++) {
        NSRect seg = NSMakeRect(x, track.origin.y, w[i], h);
        BOOL sel = [self isSelectedForSegment:i], en = self.isEnabled && [self isEnabledForSegment:i];
        if (sel) mw_fill_round(NSInsetRect(seg, 1, 2), 5, en ? (_selectedSegmentBezelColor ? _selectedSegmentBezelColor : W(0.32)) : W(0.15));
        if (_pressed == i) mw_fill_round(NSInsetRect(seg, 1, 2), 5, W(0.12));
        if (i > 0 && !sel && ![self isSelectedForSegment:i - 1]) mw_fill_round(NSMakeRect(x - 0.5, seg.origin.y + h * 0.25, 1, h * 0.5), 0, W(0.15));
        NSColor *c = en ? [NSColor labelColor] : [NSColor tertiaryLabelColor];
        NSImage *img = [self imageForSegment:i];
        if (img) { CGFloat s = fmin(16, h - 6); mw_draw_image(img, center_rect(seg, s, s), c, 1); }
        else mw_draw_text_in(_labels[(NSUInteger)i], NSInsetRect(seg, 4, 0), f, c, NSTextAlignmentCenter, NSLineBreakByTruncatingTail, NO, YES);
        x += w[i];
    }
}
@end

@implementation NSSwitch
- (NSSize)intrinsicContentSize { return self.controlSize == NSControlSizeMini ? NSMakeSize(26, 15) : self.controlSize == NSControlSizeSmall ? NSMakeSize(32, 18) : NSMakeSize(38, 22); }
- (void)setState:(NSControlStateValue)s { _state = s; self.needsDisplay = YES; }
- (void)performClick:(id)s { if (!self.isEnabled) return; self.state = _state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn; [super performClick:s]; }
- (NSInteger)integerValue { return _state; }
- (void)drawRect:(NSRect)r {
    NSSize n = [self intrinsicContentSize];
    NSRect b = self.bounds;
    CGFloat h = fmin(b.size.height, n.height), w = fmin(b.size.width, h * n.width / n.height);
    NSRect track = center_rect(b, w, h);
    BOOL on = _state == NSControlStateValueOn;
    mw_fill_round(track, h / 2, on ? (self.isEnabled ? [NSColor controlAccentColor] : W(0.3)) : W(self.isHighlighted ? 0.3 : 0.2));
    CGFloat k = h - 3;
    NSRect knob = NSMakeRect(on ? NSMaxX(track) - 1.5 - k : track.origin.x + 1.5, track.origin.y + 1.5, k, k);
    [(self.isEnabled ? [NSColor colorWithWhite:0.95 alpha:1] : W(0.5)) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:knob] fill];
}
@end

@implementation NSSlider
+ (instancetype)sliderWithTarget:(id)t action:(SEL)a { return [self sliderWithValue:0 minValue:0 maxValue:1 target:t action:a]; }
+ (instancetype)sliderWithValue:(double)v minValue:(double)mn maxValue:(double)mx target:(id)t action:(SEL)a {
    NSSlider *s = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 96, 21)] autorelease];
    s.minValue = mn; s.maxValue = mx; s.doubleValue = v; s.target = t; s.action = a;
    return s;
}
- (instancetype)initWithFrame:(NSRect)r { if ((self = [super initWithFrame:r])) { _maxValue = 1; self.continuous = YES; } return self; }
- (void)dealloc { [_trackFillColor release]; [super dealloc]; }
SET_VAL(MinValue, _minValue, double)
SET_VAL(MaxValue, _maxValue, double)
SET_OBJ(TrackFillColor, _trackFillColor, NSColor *)
- (NSSize)intrinsicContentSize { return _vertical ? NSMakeSize(21, 96) : NSMakeSize(96, 21); }
- (BOOL)_mwVertical { return _vertical || self.bounds.size.height > self.bounds.size.width; }
- (CGFloat)_mwKnob { NSRect b = self.bounds; return fmin(fmin(b.size.width, b.size.height) / 2 - 1, 8); }
- (void)_mwTrack:(NSEvent *)e {
    NSPoint p = local(self, e);
    NSRect b = self.bounds;
    CGFloat k = [self _mwKnob], t;
    if ([self _mwVertical]) { t = (p.y - b.origin.y - k) / (b.size.height - 2 * k); if (self.isFlipped) t = 1 - t; }
    else t = (p.x - b.origin.x - k) / (b.size.width - 2 * k);
    t = fmax(0, fmin(1, t));
    double v = _minValue + t * (_maxValue - _minValue);
    if (_allowsTickMarkValuesOnly && _numberOfTickMarks > 1) { double step = (_maxValue - _minValue) / (_numberOfTickMarks - 1); v = _minValue + round((v - _minValue) / step) * step; }
    if (v != self.doubleValue) { self.doubleValue = v; if (self.isContinuous) [self sendAction:self.action to:self.target]; }
}
- (void)mouseDown:(NSEvent *)e { if (self.isEnabled) { self.highlighted = YES; [self _mwTrack:e]; } }
- (void)mouseDragged:(NSEvent *)e { if (self.isEnabled) [self _mwTrack:e]; }
- (void)mouseUp:(NSEvent *)e { if (!self.isHighlighted) return; self.highlighted = NO; [self sendAction:self.action to:self.target]; }
- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds;
    BOOL vert = [self _mwVertical];
    CGFloat k = [self _mwKnob], range = _maxValue - _minValue, t = range > 0 ? fmax(0, fmin(1, (self.doubleValue - _minValue) / range)) : 0;
    NSColor *fill = self.isEnabled ? (_trackFillColor ? _trackFillColor : [NSColor controlAccentColor]) : W(0.3);
    NSPoint c;
    if (vert) {
        NSRect track = NSMakeRect(NSMidX(b) - 2, b.origin.y + k, 4, b.size.height - 2 * k);
        mw_fill_round(track, 2, W(0.2));
        CGFloat y = self.isFlipped ? NSMaxY(track) - t * track.size.height : track.origin.y + t * track.size.height;
        mw_fill_round(self.isFlipped ? NSMakeRect(track.origin.x, y, 4, NSMaxY(track) - y) : NSMakeRect(track.origin.x, track.origin.y, 4, y - track.origin.y), 2, fill);
        c = NSMakePoint(NSMidX(b), y);
    } else {
        NSRect track = NSMakeRect(b.origin.x + k, NSMidY(b) - 2, b.size.width - 2 * k, 4);
        mw_fill_round(track, 2, W(0.2));
        CGFloat x = track.origin.x + t * track.size.width;
        mw_fill_round(NSMakeRect(track.origin.x, track.origin.y, x - track.origin.x, 4), 2, fill);
        c = NSMakePoint(x, NSMidY(b));
    }
    [[NSColor colorWithWhite:self.isHighlighted ? 0.85 : 0.95 alpha:self.isEnabled ? 1 : 0.5] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - k, c.y - k, 2 * k, 2 * k)] fill];
}
@end
@implementation NSStepper
- (instancetype)initWithFrame:(NSRect)r { if ((self = [super initWithFrame:r])) { _maxValue = 59; _increment = 1; _autorepeat = YES; } return self; }
- (NSSize)intrinsicContentSize { return NSMakeSize(15, 22); }
- (void)mouseUp:(NSEvent *)e {
    if (!self.isEnabled || !inside(self, e)) return;
    BOOL up = (local(self, e).y > NSMidY(self.bounds)) != self.isFlipped;
    double v = self.doubleValue + (up ? _increment : -_increment);
    if (v > _maxValue) v = _valueWraps ? _minValue : _maxValue;
    if (v < _minValue) v = _valueWraps ? _maxValue : _minValue;
    self.doubleValue = v;
    [self sendAction:self.action to:self.target];
}
- (void)drawRect:(NSRect)r {
    NSRect b = center_rect(self.bounds, fmin(self.bounds.size.width, 15), fmin(self.bounds.size.height, 22));
    mw_fill_round(b, 4, W(0.2));
    NSImage *u = [NSImage imageWithSystemSymbolName:@"chevron.up" accessibilityDescription:nil], *d = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:nil];
    CGFloat h = b.size.height / 2;
    BOOL fl = self.isFlipped;
    mw_draw_image(u, NSMakeRect(b.origin.x, fl ? b.origin.y : b.origin.y + h, b.size.width, h), nil, 1);
    mw_draw_image(d, NSMakeRect(b.origin.x, fl ? b.origin.y + h : b.origin.y, b.size.width, h), nil, 1);
}
@end

@implementation NSPopUpButton
- (instancetype)initWithFrame:(NSRect)r pullsDown:(BOOL)f { if ((self = [super initWithFrame:r])) { _pullsDown = f; _autoenablesItems = YES; _menu = [[NSMenu alloc] init]; objc_setAssociatedObject(self, "mw_sel", @(-1), 1); } return self; }
- (instancetype)initWithFrame:(NSRect)r { return [self initWithFrame:r pullsDown:NO]; }
+ (instancetype)popUpButtonWithMenu:(NSMenu *)m target:(id)t action:(SEL)a { NSPopUpButton *b = [[[self alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease]; b.menu = m; b.target = t; b.action = a; if (m.numberOfItems) [b selectItemAtIndex:0]; [b sizeToFit]; return b; }
+ (instancetype)pullDownButtonWithTitle:(NSString *)t menu:(NSMenu *)m { NSPopUpButton *b = [[[self alloc] initWithFrame:NSZeroRect pullsDown:YES] autorelease]; b.menu = m; b.title = t; [b sizeToFit]; return b; }
- (void)dealloc { [_menu release]; [super dealloc]; }
- (NSInteger)_sel { return [objc_getAssociatedObject(self, "mw_sel") integerValue]; }
- (NSInteger)numberOfItems { return _menu.numberOfItems; }
- (NSInteger)indexOfSelectedItem { return [self _sel]; }
- (NSArray *)itemArray { return _menu.itemArray; }
- (NSArray *)itemTitles { NSMutableArray *a = [NSMutableArray array]; for (NSMenuItem *i in _menu.itemArray) [a addObject:i.title]; return a; }
- (NSMenuItem *)selectedItem { return [self _sel] >= 0 && [self _sel] < _menu.numberOfItems ? [_menu itemAtIndex:[self _sel]] : nil; }
- (NSMenuItem *)lastItem { return [_menu.itemArray lastObject]; }
- (NSString *)titleOfSelectedItem { return self.selectedItem.title; }
- (NSInteger)selectedTag { return self.selectedItem.tag; }
- (void)addItemWithTitle:(NSString *)t { [_menu addItemWithTitle:t action:NULL keyEquivalent:@""]; if ([self _sel] < 0) [self selectItemAtIndex:0]; [self invalidateIntrinsicContentSize]; }
- (void)addItemsWithTitles:(NSArray *)t { for (NSString *s in t) [self addItemWithTitle:s]; }
- (void)insertItemWithTitle:(NSString *)t atIndex:(NSInteger)i { [_menu insertItemWithTitle:t action:NULL keyEquivalent:@"" atIndex:i]; [self invalidateIntrinsicContentSize]; }
- (void)removeItemWithTitle:(NSString *)t { [_menu removeItem:[_menu itemWithTitle:t]]; }
- (void)removeItemAtIndex:(NSInteger)i { [_menu removeItemAtIndex:i]; }
- (void)removeAllItems { [_menu removeAllItems]; objc_setAssociatedObject(self, "mw_sel", @(-1), 1); self.needsDisplay = YES; }
- (void)selectItem:(NSMenuItem *)i { [self selectItemAtIndex:[_menu indexOfItem:i]]; }
- (void)selectItemAtIndex:(NSInteger)i {
    objc_setAssociatedObject(self, "mw_sel", @(i), 1);
    for (NSMenuItem *m in _menu.itemArray) m.state = NSControlStateValueOff;
    if (i >= 0 && i < _menu.numberOfItems) [_menu itemAtIndex:i].state = NSControlStateValueOn;
    if (!_pullsDown && i >= 0 && i < _menu.numberOfItems) self.title = [_menu itemAtIndex:i].title;
    self.needsDisplay = YES;
}
- (void)selectItemWithTitle:(NSString *)t { [self selectItemAtIndex:[_menu indexOfItemWithTitle:t]]; }
- (BOOL)selectItemWithTag:(NSInteger)t { NSInteger i = [_menu indexOfItemWithTag:t]; if (i < 0) return NO; [self selectItemAtIndex:i]; return YES; }
- (NSMenuItem *)itemAtIndex:(NSInteger)i { return [_menu itemAtIndex:i]; }
- (NSMenuItem *)itemWithTitle:(NSString *)t { return [_menu itemWithTitle:t]; }
- (NSString *)itemTitleAtIndex:(NSInteger)i { return [_menu itemAtIndex:i].title; }
- (NSInteger)indexOfItemWithTitle:(NSString *)t { return [_menu indexOfItemWithTitle:t]; }
- (NSInteger)indexOfItemWithTag:(NSInteger)t { return [_menu indexOfItemWithTag:t]; }
- (NSInteger)indexOfItem:(NSMenuItem *)i { return [_menu indexOfItem:i]; }
- (void)synchronizeTitleAndSelectedItem { }
- (void)setNextState { }
- (NSSize)intrinsicContentSize { CGFloat w = text_size(self.title, cfont(self)).width; for (NSMenuItem *i in _menu.itemArray) w = fmax(w, text_size(i.title, cfont(self)).width); return NSMakeSize(ceil(w) + 40, 21); }
/* the menu opens below the button; the chosen item becomes the selection and the button sends its action */
- (void)mouseDown:(NSEvent *)e {
    if (!self.isEnabled || !_menu.numberOfItems) return;
    self.highlighted = YES;
    NSRect b = self.bounds;
    NSPoint at = [self convertPoint:NSMakePoint(b.origin.x, self.isFlipped ? NSMaxY(b) : b.origin.y) toView:nil];
    NSMenuItem *i = mw_popup_choose(_menu, self.window, at);
    self.highlighted = NO;
    if (!i || !i.enabled) return;
    if (!_pullsDown) [self selectItem:i];
    if (i.action) [NSApp sendAction:i.action to:i.target from:i];
    [self sendAction:self.action to:self.target];
}
- (void)mouseUp:(NSEvent *)e { }
- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds, bezel = NSInsetRect(center_rect(b, b.size.width, fmin(b.size.height, 22)), 1, 0);
    mw_fill_round(bezel, 5, W(self.isHighlighted ? 0.3 : 0.2));
    NSColor *c = self.isEnabled ? [NSColor labelColor] : [NSColor disabledControlTextColor];
    mw_draw_text_in(_pullsDown ? self.title : (self.titleOfSelectedItem ? self.titleOfSelectedItem : @""), NSMakeRect(bezel.origin.x + 8, bezel.origin.y, bezel.size.width - 30, bezel.size.height),
                    cfont(self), c, NSTextAlignmentLeft, NSLineBreakByTruncatingTail, NO, YES);
    NSRect arrow = NSMakeRect(NSMaxX(bezel) - 19, bezel.origin.y + (bezel.size.height - 16) / 2, 16, 16);
    mw_fill_round(arrow, 4, self.isEnabled ? [NSColor controlAccentColor] : W(0.2));
    mw_draw_image([NSImage imageWithSystemSymbolName:_pullsDown ? @"chevron.down" : @"chevron.up.chevron.down" accessibilityDescription:nil], NSInsetRect(arrow, 2, 2), [NSColor whiteColor], 1);
}
@end
@implementation NSColorWell
- (void)dealloc { [_color release]; [super dealloc]; }
- (void)setColor:(NSColor *)c { [_color release]; _color = [c copy]; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)r {
    mw_fill_round(self.bounds, 4, W(0.2));
    mw_fill_round(NSInsetRect(self.bounds, 3, 3), 2, _color ? _color : [NSColor blackColor]);
}
@end
@implementation NSProgressIndicator { NSTimer *_anim; BOOL _animating; }
- (instancetype)initWithFrame:(NSRect)r { if ((self = [super initWithFrame:r])) { _maxValue = 100; _indeterminate = YES; _usesThreadedAnimation = YES; } return self; }
- (void)dealloc { [_anim invalidate]; [super dealloc]; }
SET_VAL(DoubleValue, _doubleValue, double)
SET_VAL(MinValue, _minValue, double)
SET_VAL(MaxValue, _maxValue, double)
SET_VAL(Indeterminate, _indeterminate, BOOL)
SET_VAL(Style, _style, NSProgressIndicatorStyle)
/* animation: redraws ~30 times a second while it runs (the timer holds the view until it stops) */
- (void)startAnimation:(id)s {
    if (_animating) return;
    _animating = YES;
    _anim = [NSTimer timerWithTimeInterval:1.0 / 30 repeats:YES block:^(NSTimer *t) { if (self.window.isVisible && !self.isHiddenOrHasHiddenAncestor) self.needsDisplay = YES; }];
    [[NSRunLoop mainRunLoop] addTimer:_anim forMode:NSRunLoopCommonModes];
    self.needsDisplay = YES;
}
- (void)stopAnimation:(id)s { _animating = NO; [_anim invalidate]; _anim = nil; self.needsDisplay = YES; }
- (void)viewDidMoveToWindow { if (!self.window) [self stopAnimation:nil]; }
- (void)incrementBy:(double)d { self.doubleValue = _doubleValue + d; }
- (void)sizeToFit { [self setFrameSize:[self intrinsicContentSize]]; }
- (NSSize)intrinsicContentSize {
    if (_style == NSProgressIndicatorStyleSpinning) return _controlSize == NSControlSizeSmall ? NSMakeSize(16, 16) : _controlSize == NSControlSizeMini ? NSMakeSize(10, 10) : NSMakeSize(32, 32);
    return NSMakeSize(-1, _controlSize == NSControlSizeSmall ? 12 : 20);
}
- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds;
    double now = CACurrentMediaTime();
    if (_style == NSProgressIndicatorStyleSpinning) {
        if (!_animating && !_displayedWhenStopped) return;
        CGFloat rad = fmin(b.size.width, b.size.height) / 2 - 0.5;
        int step = (int)(now * 12) % 12;
        NSBezierPath *p = [NSBezierPath bezierPath];
        p.lineWidth = fmax(1, rad * 0.2); p.lineCapStyle = NSLineCapStyleRound;
        for (int i = 0; i < 12; i++) {
            CGFloat a = M_PI / 2 - i * M_PI / 6;
            [p removeAllPoints];
            [p moveToPoint:NSMakePoint(NSMidX(b) + cos(a) * rad * 0.5, NSMidY(b) + sin(a) * rad * 0.5)];
            [p lineToPoint:NSMakePoint(NSMidX(b) + cos(a) * (rad - p.lineWidth / 2), NSMidY(b) + sin(a) * (rad - p.lineWidth / 2))];
            [W(0.2 + 0.7 * (double)((i - step + 12) % 12 == 0 ? 1 : 1 - ((i - step + 12) % 12) / 12.0)) setStroke];
            [p stroke];
        }
        return;
    }
    CGFloat h = fmin(b.size.height, 6);
    NSRect track = center_rect(b, b.size.width, h);
    mw_fill_round(track, h / 2, W(0.15));
    if (_indeterminate) {
        if (!_animating) return;
        CGFloat w = track.size.width * 0.3, x = track.origin.x + fmod(now * 0.6, 1.3) * track.size.width - w;
        NSRect seg = NSIntersectionRect(NSMakeRect(x, track.origin.y, w, h), track);
        if (seg.size.width > 0) mw_fill_round(seg, h / 2, [NSColor controlAccentColor]);
        return;
    }
    double range = _maxValue - _minValue, t = range > 0 ? fmax(0, fmin(1, (_doubleValue - _minValue) / range)) : 0;
    if (t > 0) mw_fill_round(NSMakeRect(track.origin.x, track.origin.y, fmax(h, track.size.width * t), h), h / 2, [NSColor controlAccentColor]);
}
@end
@implementation NSImageView
+ (instancetype)imageViewWithImage:(NSImage *)i { NSImageView *v = [[[self alloc] initWithFrame:NSMakeRect(0, 0, i.size.width, i.size.height)] autorelease]; v.image = i; return v; }
- (void)dealloc { [_image release]; [_contentTintColor release]; [super dealloc]; }
SET_OBJ(Image, _image, NSImage *)
SET_OBJ(ContentTintColor, _contentTintColor, NSColor *)
SET_VAL(ImageScaling, _imageScaling, NSImageScaling)
- (NSSize)intrinsicContentSize { return _image ? _image.size : NSMakeSize(-1, -1); }
- (void)mouseDown:(NSEvent *)e { }
- (void)mouseUp:(NSEvent *)e { }
- (void)drawRect:(NSRect)r {
    if (!_image) return;
    NSRect b = self.bounds;
    NSSize s = _image.size;
    if (s.width <= 0 || s.height <= 0) s = b.size;
    CGFloat k = fmin(b.size.width / s.width, b.size.height / s.height);
    if (_imageScaling == NSImageScaleAxesIndependently) s = b.size;
    else if (_imageScaling == NSImageScaleProportionallyUpOrDown || (_imageScaling == NSImageScaleProportionallyDown && k < 1)) s = NSMakeSize(s.width * k, s.height * k);
    mw_draw_image(_image, center_rect(b, s.width, s.height), _contentTintColor, self.isEnabled ? 1 : 0.5);
}
@end
@implementation NSBox
- (instancetype)initWithFrame:(NSRect)r { if ((self = [super initWithFrame:r])) { _borderWidth = 1; NSView *c = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, r.size.height)]; c.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; self.contentView = c; [c release]; } return self; }
- (void)dealloc { [_title release]; [_fillColor release]; [_borderColor release]; [_contentView release]; [super dealloc]; }
- (void)setContentView:(NSView *)v { [_contentView removeFromSuperview]; [v retain]; [_contentView release]; _contentView = v; if (v) [self addSubview:v]; }
SET_OBJ(FillColor, _fillColor, NSColor *)
SET_OBJ(BorderColor, _borderColor, NSColor *)
SET_VAL(BoxType, _boxType, NSBoxType)
SET_VAL(BorderWidth, _borderWidth, CGFloat)
SET_VAL(CornerRadius, _cornerRadius, CGFloat)
SET_VAL(Transparent, _transparent, BOOL)
- (NSSize)intrinsicContentSize { return _boxType == NSBoxSeparator ? NSMakeSize(-1, 1) : NSMakeSize(-1, -1); }
- (void)drawRect:(NSRect)r {
    if (_transparent) return;
    NSRect b = self.bounds;
    if (_boxType == NSBoxSeparator) {
        NSRect line = b.size.width >= b.size.height ? NSMakeRect(b.origin.x, NSMidY(b) - 0.5, b.size.width, 1) : NSMakeRect(NSMidX(b) - 0.5, b.origin.y, 1, b.size.height);
        mw_fill_round(line, 0, [NSColor separatorColor]);
    } else if (_boxType == NSBoxCustom) {
        if (_fillColor) mw_fill_round(b, _cornerRadius, _fillColor);
        mw_stroke_round(b, _cornerRadius, _borderWidth, _borderColor ? _borderColor : W(0.1));
    } else { mw_fill_round(b, 5, W(0.04)); mw_stroke_round(b, 5, 1, W(0.1)); }
}
@end
@implementation NSVisualEffectView
- (void)dealloc { [_maskImage release]; [super dealloc]; }
/* no blur behind windows: a translucent dark material */
- (void)drawRect:(NSRect)r { mw_fill_round(self.bounds, self.layer ? self.layer.cornerRadius : 0, [NSColor colorWithWhite:0.14 alpha:0.94]); }
@end
@implementation NSClipView
- (void)dealloc { [_documentView release]; [_backgroundColor release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (void)setDocumentView:(NSView *)v { [_documentView removeFromSuperview]; [v retain]; [_documentView release]; _documentView = v; if (v) [self addSubview:v]; }
@end
@implementation NSScrollView
- (instancetype)initWithFrame:(NSRect)r {
    if ((self = [super initWithFrame:r])) {
        NSClipView *c = [[NSClipView alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
        c.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.contentView = c; [c release];
    }
    return self;
}
- (void)dealloc { [_contentView release]; [_backgroundColor release]; [super dealloc]; }
- (void)setContentView:(NSClipView *)c { [_contentView removeFromSuperview]; [c retain]; [_contentView release]; _contentView = c; if (c) [self addSubview:c]; }
- (NSView *)documentView { return _contentView.documentView; }
- (void)setDocumentView:(NSView *)v { _contentView.documentView = v; }
- (NSSize)contentSize { return _contentView.frame.size; }
@end
static void mw_text_option_set(id self, SEL _cmd, void *v) { }
@implementation NSText
- (void)dealloc { [_string release]; [_font release]; [_textColor release]; [_backgroundColor release]; [super dealloc]; }
- (BOOL)acceptsFirstResponder { return _editable || _selectable; }
- (void)keyDown:(NSEvent *)e { if (_editable) [self interpretKeyEvents:@[e]]; else [super keyDown:e]; }
- (void)insertText:(id)s { if (!_editable) return; NSString *t = [s isKindOfClass:[NSAttributedString class]] ? [s string] : s; self.string = [(_string ? _string : @"") stringByAppendingString:t]; }
- (void)deleteBackward:(id)s { if (_editable && [_string length]) self.string = [_string substringToIndex:[_string length] - 1]; }
/* the many text options apps set (spelling, substitutions, link detection...): accepted and ignored */
+ (BOOL)resolveInstanceMethod:(SEL)sel {
    const char *n = sel_getName(sel); size_t l = strlen(n);
    if (l > 4 && !strncmp(n, "set", 3) && strchr(n, ':') == n + l - 1) {
        class_addMethod(self, sel, (IMP)mw_text_option_set, "v@:@"); return YES;
    }
    return [super resolveInstanceMethod:sel];
}
@end
NSNotificationName const NSTextDidBeginEditingNotification = @"NSTextDidBeginEditingNotification", NSTextDidEndEditingNotification = @"NSTextDidEndEditingNotification",
    NSTextDidChangeNotification = @"NSTextDidChangeNotification", NSTextViewDidChangeSelectionNotification = @"NSTextViewDidChangeSelectionNotification";
/* a text view: the text is its NSTextStorage, drawn wrapped in one style (the first run's attributes); a caret at the
 * selection; typing, deleting, the arrows and copy/paste. ponytail: no glyph layout, so no per-run styles and the caret
 * is placed by measuring the text before it. */
@implementation NSTextView {
    NSTextStorage *_storage; NSLayoutManager *_lm; NSTextContainer *_tc; NSDictionary *_typing; NSColor *_ipColor;
    NSRange _sel; id<NSTextViewDelegate> _tvDelegate; BOOL _allowsUndo, _fieldEditor, _vres, _hres; NSSize _minSize, _maxSize, _inset;
}
@synthesize allowsUndo = _allowsUndo, fieldEditor = _fieldEditor, verticallyResizable = _vres, horizontallyResizable = _hres, minSize = _minSize, maxSize = _maxSize, textContainerInset = _inset;
/* a text view of this class inside a scroll view (macOS 10.14) */
+ (NSScrollView *)scrollableTextView {
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 240, 135)] autorelease];
    sv.hasVerticalScroller = YES;
    NSTextView *tv = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 240, 135)] autorelease];
    tv.autoresizingMask = NSViewWidthSizable;
    sv.documentView = tv;
    return sv;
}
+ (NSScrollView *)scrollablePlainDocumentContentTextView { return [self scrollableTextView]; }
+ (NSScrollView *)scrollableDocumentContentTextView { return [self scrollableTextView]; }
- (instancetype)initWithFrame:(NSRect)r textContainer:(NSTextContainer *)c {
    if ((self = [super initWithFrame:r])) {
        _storage = [[NSTextStorage alloc] init];
        _lm = [[NSLayoutManager alloc] init]; [_storage addLayoutManager:_lm];
        _tc = c ? [c retain] : [[NSTextContainer alloc] initWithSize:NSMakeSize(r.size.width, 1e7)];
        [_lm addTextContainer:_tc];
        self.editable = YES; self.selectable = YES; self.drawsBackground = YES; self.richText = YES;
        _vres = YES; _maxSize = NSMakeSize(1e7, 1e7);
        _typing = [@{NSFontAttributeName: [NSFont systemFontOfSize:12], NSForegroundColorAttributeName: [NSColor textColor]} copy];
    }
    return self;
}
- (instancetype)initWithFrame:(NSRect)r { return [self initWithFrame:r textContainer:nil]; }
- (void)dealloc { [_storage release]; [_lm release]; [_tc release]; [_typing release]; [_ipColor release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (NSTextStorage *)textStorage { return _storage; }
- (NSLayoutManager *)layoutManager { return _lm; }
- (NSTextContainer *)textContainer { return _tc; }
- (void)setTextContainer:(NSTextContainer *)c { [c retain]; [_tc release]; _tc = c; }
- (void)replaceTextContainer:(NSTextContainer *)c { self.textContainer = c; }
- (id<NSTextViewDelegate>)delegate { return _tvDelegate; }
- (void)setDelegate:(id<NSTextViewDelegate>)d { _tvDelegate = d; }
- (NSDictionary *)typingAttributes { return _typing; }
- (void)setTypingAttributes:(NSDictionary *)a { [_typing release]; _typing = [a copy]; }
- (NSColor *)insertionPointColor { return _ipColor ?: [NSColor textColor]; }
- (void)setInsertionPointColor:(NSColor *)c { [c retain]; [_ipColor release]; _ipColor = c; }
- (NSString *)string { return [[_storage.string copy] autorelease]; }
- (void)setString:(NSString *)s {
    [_storage replaceCharactersInRange:NSMakeRange(0, [_storage length]) withAttributedString:[[[NSAttributedString alloc] initWithString:s ?: @"" attributes:_typing] autorelease]];
    _sel = NSMakeRange([_storage length], 0); [self _mwLayout];
}
- (NSFont *)font { return [_storage length] ? [_storage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] : _typing[NSFontAttributeName]; }
- (void)setFont:(NSFont *)f { if (!f) return; [self _mwType:NSFontAttributeName value:f]; }
- (NSColor *)textColor { return _typing[NSForegroundColorAttributeName]; }
- (void)setTextColor:(NSColor *)c { if (!c) return; [self _mwType:NSForegroundColorAttributeName value:c]; }
- (void)_mwType:(NSString *)k value:(id)v {
    NSMutableDictionary *t = [[_typing mutableCopy] autorelease]; t[k] = v; self.typingAttributes = t;
    if ([_storage length]) [_storage addAttribute:k value:v range:NSMakeRange(0, [_storage length])];
    self.needsDisplay = YES;
}
- (NSRange)selectedRange { return _sel; }
- (void)setSelectedRange:(NSRange)r {
    NSUInteger n = [_storage length]; if (r.location > n) r = NSMakeRange(n, 0); if (NSMaxRange(r) > n) r.length = n - r.location;
    _sel = r; self.needsDisplay = YES;
    if ([(id)_tvDelegate respondsToSelector:@selector(textViewDidChangeSelection:)]) [_tvDelegate textViewDidChangeSelection:[NSNotification notificationWithName:NSTextViewDidChangeSelectionNotification object:self]];
}
- (NSArray *)selectedRanges { return @[[NSValue valueWithRange:_sel]]; }
- (void)setSelectedRanges:(NSArray *)a { if ([a count]) self.selectedRange = [a[0] rangeValue]; }
- (BOOL)hasMarkedText { return NO; }
- (NSUndoManager *)undoManager { return nil; }
/* geometry: the text wrapped at the view's width less the insets and the container's line padding */
- (NSRect)_mwTextRect { NSRect b = self.bounds; CGFloat pad = _tc ? _tc.lineFragmentPadding : 5; return NSMakeRect(_inset.width + pad, _inset.height, fmax(1, b.size.width - 2 * (_inset.width + pad)), b.size.height - 2 * _inset.height); }
- (NSSize)_mwTextSize:(NSString *)s { NSRect t = [self _mwTextRect]; return mw_text_size_wrapped([s length] ? s : @"X", self.font, t.size.width); }
- (void)_mwLayout {
    if (_vres) {   /* grow with the text, like a text view in a scroll view */
        CGFloat h = [self _mwTextSize:_storage.string].height + 2 * _inset.height;
        CGFloat want = fmin(fmax(h, _minSize.height), _maxSize.height), min = self.superview ? self.superview.bounds.size.height : 0;
        if (fabs(fmax(want, min) - self.frame.size.height) > 0.5) [self setFrameSize:NSMakeSize(self.frame.size.width, fmax(want, min))];
    }
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)r {
    if (self.drawsBackground) mw_fill_round(self.bounds, 0, self.backgroundColor ?: [NSColor textBackgroundColor]);
    NSRect t = [self _mwTextRect];
    NSString *s = _storage.string;
    mw_draw_text_in(s, t, self.font, self.textColor ?: [NSColor textColor], NSTextAlignmentLeft, NSLineBreakByWordWrapping, YES, NO);
    if (self.window.firstResponder == self && self.isEditable) {   /* the caret after the text before the selection */
        NSString *before = [s substringToIndex:_sel.location];
        NSArray *lines = [before componentsSeparatedByString:@"\n"];
        NSSize all = [before length] ? mw_text_size_wrapped(before, self.font, t.size.width) : NSZeroSize, last = mw_text_size([lines lastObject], self.font);
        CGFloat lh = mw_text_size(@"X", self.font).height, w = fmod(last.width, fmax(1, t.size.width));
        CGFloat y = t.origin.y + fmax(0, ([before length] ? all.height : lh) - lh);
        if ([before hasSuffix:@"\n"]) { y = t.origin.y + all.height; w = 0; }
        [self.insertionPointColor setFill];
        NSRectFill(NSMakeRect(t.origin.x + w, y, 1, lh));
    }
}
- (BOOL)acceptsFirstResponder { return self.isSelectable; }
- (BOOL)becomeFirstResponder {
    if ([(id)_tvDelegate respondsToSelector:@selector(textShouldBeginEditing:)] && ![_tvDelegate textShouldBeginEditing:self]) return NO;
    NSNotification *n = [NSNotification notificationWithName:NSTextDidBeginEditingNotification object:self];
    if ([(id)_tvDelegate respondsToSelector:@selector(textDidBeginEditing:)]) [_tvDelegate textDidBeginEditing:n];
    [[NSNotificationCenter defaultCenter] postNotification:n];
    self.needsDisplay = YES; return YES;
}
- (BOOL)resignFirstResponder {
    NSNotification *n = [NSNotification notificationWithName:NSTextDidEndEditingNotification object:self];
    if ([(id)_tvDelegate respondsToSelector:@selector(textDidEndEditing:)]) [_tvDelegate textDidEndEditing:n];
    [[NSNotificationCenter defaultCenter] postNotification:n];
    self.needsDisplay = YES; return YES;
}
- (void)mouseDown:(NSEvent *)e { [self.window makeFirstResponder:self]; self.selectedRange = NSMakeRange([_storage length], 0); }
- (void)keyDown:(NSEvent *)e { if (self.isEditable) [self interpretKeyEvents:@[e]]; else [super keyDown:e]; }
- (void)doCommandBySelector:(SEL)s {
    if ([(id)_tvDelegate respondsToSelector:@selector(textView:doCommandBySelector:)] && [_tvDelegate textView:self doCommandBySelector:s]) return;
    if ([self respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(self, s, self);
}
- (BOOL)shouldChangeTextInRange:(NSRange)r replacementString:(NSString *)s {
    if (!self.isEditable) return NO;
    return ![(id)_tvDelegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementString:)] || [_tvDelegate textView:self shouldChangeTextInRange:r replacementString:s];
}
- (void)didChangeText {
    [self _mwLayout];
    NSNotification *n = [NSNotification notificationWithName:NSTextDidChangeNotification object:self];
    if ([(id)_tvDelegate respondsToSelector:@selector(textDidChange:)]) [_tvDelegate textDidChange:n];
    [[NSNotificationCenter defaultCenter] postNotification:n];
}
- (void)_mwReplace:(NSRange)r with:(NSString *)t {
    if (![self shouldChangeTextInRange:r replacementString:t]) return;
    [_storage replaceCharactersInRange:r withAttributedString:[[[NSAttributedString alloc] initWithString:t attributes:_typing] autorelease]];
    _sel = NSMakeRange(r.location + [t length], 0);
    [self didChangeText];
    self.selectedRange = _sel;
}
- (void)insertText:(id)s replacementRange:(NSRange)r {
    NSString *t = [s isKindOfClass:[NSAttributedString class]] ? [s string] : s;
    [self _mwReplace:r.location == NSNotFound ? _sel : r with:t ?: @""];
}
- (void)insertText:(id)s { [self insertText:s replacementRange:NSMakeRange(NSNotFound, 0)]; }
- (void)insertNewline:(id)s { if (_fieldEditor) [self.window makeFirstResponder:nil]; else [self insertText:@"\n"]; }
- (void)insertLineBreak:(id)s { [self insertText:@"\n"]; }
- (void)insertNewlineIgnoringFieldEditor:(id)s { [self insertText:@"\n"]; }
- (void)insertTab:(id)s { if (_fieldEditor) [self.window selectNextKeyView:self]; else [self insertText:@"\t"]; }
- (void)insertBacktab:(id)s { [self.window selectPreviousKeyView:self]; }
- (void)deleteBackward:(id)s {
    if (_sel.length) [self _mwReplace:_sel with:@""];
    else if (_sel.location > 0) { NSRange c = [_storage.string rangeOfComposedCharacterSequenceAtIndex:_sel.location - 1]; [self _mwReplace:c with:@""]; }
}
- (void)deleteForward:(id)s {
    if (_sel.length) [self _mwReplace:_sel with:@""];
    else if (_sel.location < [_storage length]) [self _mwReplace:[_storage.string rangeOfComposedCharacterSequenceAtIndex:_sel.location] with:@""];
}
- (void)moveLeft:(id)s { self.selectedRange = NSMakeRange(_sel.length ? _sel.location : _sel.location ? [_storage.string rangeOfComposedCharacterSequenceAtIndex:_sel.location - 1].location : 0, 0); }
- (void)moveRight:(id)s { self.selectedRange = NSMakeRange(_sel.length ? NSMaxRange(_sel) : _sel.location < [_storage length] ? NSMaxRange([_storage.string rangeOfComposedCharacterSequenceAtIndex:_sel.location]) : _sel.location, 0); }
- (void)moveToBeginningOfLine:(id)s { self.selectedRange = NSMakeRange([_storage.string lineRangeForRange:NSMakeRange(_sel.location, 0)].location, 0); }
- (void)moveToEndOfLine:(id)s { NSRange l = [_storage.string lineRangeForRange:NSMakeRange(_sel.location, 0)]; NSUInteger e = NSMaxRange(l); if (e > l.location && [_storage.string characterAtIndex:e - 1] == '\n') e--; self.selectedRange = NSMakeRange(e, 0); }
- (void)moveUp:(id)s { [self moveToBeginningOfLine:s]; }
- (void)moveDown:(id)s { [self moveToEndOfLine:s]; }
- (void)moveToBeginningOfDocument:(id)s { self.selectedRange = NSMakeRange(0, 0); }
- (void)moveToEndOfDocument:(id)s { self.selectedRange = NSMakeRange([_storage length], 0); }
- (void)selectAll:(id)s { self.selectedRange = NSMakeRange(0, [_storage length]); }
- (void)cancelOperation:(id)s { }
- (void)complete:(id)s { }   /* ponytail: no completion list */
- (NSRange)rangeForUserCompletion { return NSMakeRange(_sel.location, 0); }
- (void)checkTextInDocument:(id)s { } - (void)showFindIndicatorForRange:(NSRange)r { }
- (void)copy:(id)s {
    if (!_sel.length) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard]; [pb clearContents]; [pb setString:[_storage.string substringWithRange:_sel] forType:NSPasteboardTypeString];
}
- (void)cut:(id)s { if (_sel.length && self.isEditable) { [self copy:s]; [self _mwReplace:_sel with:@""]; } }
- (void)paste:(id)s { NSString *t = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]; if (t) [self insertText:t]; }
- (void)pasteAsPlainText:(id)s { [self paste:s]; }
- (void)scrollRangeToVisible:(NSRange)r { }
- (void)setFrameSize:(NSSize)s { [super setFrameSize:s]; if (_tc && _tc.size.width < 1e6) _tc.size = NSMakeSize(s.width, _tc.size.height); }
- (void)sizeToFit { [self _mwLayout]; }
@end

/* ---------------------------------------------------------------- NSStackView: lays its arranged views out in a row or column */
@implementation NSStackView { NSMutableArray *_arranged; NSMapTable *_custom; }
+ (instancetype)stackViewWithViews:(NSArray *)v { NSStackView *s = [[[self alloc] initWithFrame:NSZeroRect] autorelease]; for (NSView *x in v) [s addArrangedSubview:x]; return s; }
- (instancetype)initWithFrame:(NSRect)r {
    if ((self = [super initWithFrame:r])) {
        _arranged = [[NSMutableArray alloc] init]; _spacing = 8; _detachesHiddenViews = YES;
        _alignment = NSLayoutAttributeCenterY; _distribution = NSStackViewDistributionFill;
        _custom = [[NSMapTable alloc] init];
    }
    return self;
}
- (void)dealloc { [_arranged release]; [_custom release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (void)setOrientation:(NSUserInterfaceLayoutOrientation)o {
    _orientation = o;
    if (o == NSUserInterfaceLayoutOrientationVertical && _alignment == NSLayoutAttributeCenterY) _alignment = NSLayoutAttributeCenterX;
    if (o == NSUserInterfaceLayoutOrientationHorizontal && _alignment == NSLayoutAttributeCenterX) _alignment = NSLayoutAttributeCenterY;
    self.needsLayout = YES;
}
- (NSArray *)arrangedSubviews { return [[_arranged copy] autorelease]; }
- (NSArray *)views { return [self arrangedSubviews]; }
- (NSArray *)detachedViews { return @[]; }
- (void)insertArrangedSubview:(NSView *)v atIndex:(NSInteger)i {
    [_arranged removeObjectIdenticalTo:v];
    [_arranged insertObject:v atIndex:(NSUInteger)(i < 0 ? 0 : i > (NSInteger)[_arranged count] ? (NSInteger)[_arranged count] : i)];
    if (v.superview != self) [self addSubview:v];
    self.needsLayout = YES;
}
- (void)addArrangedSubview:(NSView *)v { [self insertArrangedSubview:v atIndex:(NSInteger)[_arranged count]]; }
- (void)removeArrangedSubview:(NSView *)v { [_arranged removeObjectIdenticalTo:v]; self.needsLayout = YES; }
- (void)willRemoveSubview:(NSView *)v { [_arranged removeObjectIdenticalTo:v]; }
- (void)addView:(NSView *)v inGravity:(NSStackViewGravity)g { [self addArrangedSubview:v]; }
- (void)insertView:(NSView *)v atIndex:(NSUInteger)i inGravity:(NSStackViewGravity)g { [self insertArrangedSubview:v atIndex:(NSInteger)i]; }
- (void)removeView:(NSView *)v { [v removeFromSuperview]; }
- (void)setViews:(NSArray *)v inGravity:(NSStackViewGravity)g { for (NSView *x in [[_arranged copy] autorelease]) [x removeFromSuperview]; for (NSView *x in v) [self addArrangedSubview:x]; }
- (NSArray *)viewsInGravity:(NSStackViewGravity)g { return [self arrangedSubviews]; }
- (void)setCustomSpacing:(CGFloat)s afterView:(NSView *)v { [_custom setObject:@(s) forKey:v]; self.needsLayout = YES; }
- (CGFloat)customSpacingAfterView:(NSView *)v { NSNumber *n = [_custom objectForKey:v]; return n ? [n doubleValue] : _spacing; }
- (void)setHuggingPriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o { }
- (void)setClippingResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o { }
- (void)setVisibilityPriority:(float)p forView:(NSView *)v { }
static NSSize fit(NSView *v) {
    NSSize s = [v fittingSize];
    NSSize f = v.frame.size;
    if (s.width < 0 || (f.width > 0 && v.constraints.count)) s.width = f.width;
    if (s.height < 0 || (f.height > 0 && v.constraints.count)) s.height = f.height;
    return s;
}
- (NSSize)intrinsicContentSize { return [self fittingSize]; } /* AppKit's internal constraints size a stack to its views */
- (NSArray *)_shown { NSMutableArray *a = [NSMutableArray array]; for (NSView *v in _arranged) if (!(v.isHidden && _detachesHiddenViews)) [a addObject:v]; return a; }
- (NSSize)fittingSize {
    BOOL h = _orientation == NSUserInterfaceLayoutOrientationHorizontal;
    CGFloat main = 0, cross = 0;
    NSArray *shown = [self _shown];
    for (NSUInteger i = 0; i < [shown count]; i++) {
        NSSize s = fit(shown[i]);
        main += h ? s.width : s.height;
        if (i + 1 < [shown count]) main += [self customSpacingAfterView:shown[i]];
        cross = fmax(cross, h ? s.height : s.width);
    }
    return h ? NSMakeSize(main + _edgeInsets.left + _edgeInsets.right, cross + _edgeInsets.top + _edgeInsets.bottom)
             : NSMakeSize(cross + _edgeInsets.left + _edgeInsets.right, main + _edgeInsets.top + _edgeInsets.bottom);
}
- (void)layout {
    BOOL h = _orientation == NSUserInterfaceLayoutOrientationHorizontal;
    NSArray *shown = [self _shown];
    NSRect b = self.bounds;
    CGFloat x = _edgeInsets.left, y = _edgeInsets.top;
    CGFloat availMain = h ? b.size.width - _edgeInsets.left - _edgeInsets.right : b.size.height - _edgeInsets.top - _edgeInsets.bottom;
    CGFloat availCross = h ? b.size.height - _edgeInsets.top - _edgeInsets.bottom : b.size.width - _edgeInsets.left - _edgeInsets.right;
    CGFloat used = 0;
    for (NSUInteger i = 0; i < [shown count]; i++) { NSSize s = fit(shown[i]); used += h ? s.width : s.height; if (i + 1 < [shown count]) used += [self customSpacingAfterView:shown[i]]; }
    CGFloat extra = [shown count] && (_distribution == NSStackViewDistributionFillEqually || _distribution == NSStackViewDistributionEqualSpacing) ? (availMain - used) : 0;
    for (NSUInteger i = 0; i < [shown count]; i++) {
        NSView *v = shown[i];
        NSSize s = fit(v);
        CGFloat m = h ? s.width : s.height, c = h ? s.height : s.width;
        if (_distribution == NSStackViewDistributionFillEqually) m += extra / [shown count];
        if (_distribution == NSStackViewDistributionFill && i + 1 == [shown count] && availMain > used) m += availMain - used; /* the last one stretches */
        BOOL fillCross = (h && (_alignment == NSLayoutAttributeTop || _alignment == NSLayoutAttributeBottom) && NO) || _alignment == NSLayoutAttributeWidth || _alignment == NSLayoutAttributeHeight;
        if (fillCross) c = availCross;
        CGFloat off = (_alignment == NSLayoutAttributeCenterX || _alignment == NSLayoutAttributeCenterY) ? (availCross - c) / 2
                    : (_alignment == NSLayoutAttributeTrailing || _alignment == NSLayoutAttributeRight || _alignment == NSLayoutAttributeBottom) ? availCross - c : 0;
        if (h) [v setFrame:NSMakeRect(x, _edgeInsets.top + off, m, c)];
        else [v setFrame:NSMakeRect(_edgeInsets.left + off, y, c, m)];
        CGFloat gap = i + 1 < [shown count] ? [self customSpacingAfterView:v] : 0;
        if (_distribution == NSStackViewDistributionEqualSpacing && [shown count] > 1) gap += extra / ([shown count] - 1);
        if (h) x += m + gap; else y += m + gap;
    }
}
@end

/* ---------------------------------------------------------------- NSGridView: rows x columns, sized to the cells' contents */
@implementation NSGridCell
@synthesize column = _column, row = _row;
+ (NSView *)emptyContentView { static NSView *v; if (!v) v = [[NSView alloc] initWithFrame:NSZeroRect]; return v; }
- (void)dealloc { [_contentView release]; [_customPlacementConstraints release]; [super dealloc]; }
- (void)_mwSetColumn:(NSGridColumn *)c row:(NSGridRow *)r { _column = c; _row = r; }
@end
@interface NSGridColumn () { @public NSGridView *_grid; } @end
@interface NSGridRow () { @public NSGridView *_grid; } @end
@interface NSGridView () { @public NSMutableArray *_rows, *_cols, *_cells; /* _cells: rows of NSGridCell */ } @end
@implementation NSGridColumn
- (NSInteger)numberOfCells { return (NSInteger)[_grid->_rows count]; }
- (NSGridCell *)cellAtIndex:(NSInteger)i { return [_grid cellAtColumnIndex:[_grid indexOfColumn:self] rowIndex:i]; }
- (void)mergeCellsInRange:(NSRange)r { }
- (void)setWidth:(CGFloat)w { _width = w; _grid.needsLayout = YES; }
- (void)setHidden:(BOOL)h { _hidden = h; _grid.needsLayout = YES; }
@end
@implementation NSGridRow
- (NSInteger)numberOfCells { return (NSInteger)[_grid->_cols count]; }
- (NSGridCell *)cellAtIndex:(NSInteger)i { return [_grid cellAtColumnIndex:i rowIndex:[_grid indexOfRow:self]]; }
- (void)mergeCellsInRange:(NSRange)r { }
- (void)setHeight:(CGFloat)h { _height = h; _grid.needsLayout = YES; }
- (void)setHidden:(BOOL)h { _hidden = h; _grid.needsLayout = YES; }
@end
@implementation NSGridView
+ (instancetype)gridViewWithNumberOfColumns:(NSInteger)c rows:(NSInteger)r {
    NSGridView *g = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    for (NSInteger i = 0; i < c; i++) [g addColumnWithViews:@[]];
    for (NSInteger i = 0; i < r; i++) [g addRowWithViews:@[]];
    return g;
}
+ (instancetype)gridViewWithViews:(NSArray *)rows { NSGridView *g = [[[self alloc] initWithFrame:NSZeroRect] autorelease]; for (NSArray *r in rows) [g addRowWithViews:r]; return g; }
- (instancetype)initWithFrame:(NSRect)r {
    if ((self = [super initWithFrame:r])) {
        _rows = [[NSMutableArray alloc] init]; _cols = [[NSMutableArray alloc] init]; _cells = [[NSMutableArray alloc] init];
        _rowSpacing = 6; _columnSpacing = 6; _xPlacement = NSGridCellPlacementLeading; _yPlacement = NSGridCellPlacementCenter;
    }
    return self;
}
- (void)dealloc { [_rows release]; [_cols release]; [_cells release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (NSInteger)numberOfRows { return (NSInteger)[_rows count]; }
- (NSInteger)numberOfColumns { return (NSInteger)[_cols count]; }
- (NSGridRow *)rowAtIndex:(NSInteger)i { return [_rows objectAtIndex:(NSUInteger)i]; }
- (NSGridColumn *)columnAtIndex:(NSInteger)i { return [_cols objectAtIndex:(NSUInteger)i]; }
- (NSInteger)indexOfRow:(NSGridRow *)r { NSUInteger i = [_rows indexOfObjectIdenticalTo:r]; return i == NSNotFound ? -1 : (NSInteger)i; }
- (NSInteger)indexOfColumn:(NSGridColumn *)c { NSUInteger i = [_cols indexOfObjectIdenticalTo:c]; return i == NSNotFound ? -1 : (NSInteger)i; }
- (NSGridCell *)cellAtColumnIndex:(NSInteger)c rowIndex:(NSInteger)r { return _cells[(NSUInteger)r][(NSUInteger)c]; }
- (NSGridCell *)cellForView:(NSView *)v { for (NSArray *r in _cells) for (NSGridCell *c in r) if (c.contentView == v) return c; return nil; }
- (NSGridCell *)_newCell:(NSView *)v col:(NSGridColumn *)c row:(NSGridRow *)r {
    NSGridCell *cell = [[[NSGridCell alloc] init] autorelease];
    [cell _mwSetColumn:c row:r];
    if (v && v != [NSGridCell emptyContentView]) { cell.contentView = v; [self addSubview:v]; }
    return cell;
}
- (NSGridColumn *)_addColumn { NSGridColumn *c = [[[NSGridColumn alloc] init] autorelease]; c->_grid = self; [_cols addObject:c]; for (NSUInteger i = 0; i < [_rows count]; i++) [_cells[i] addObject:[self _newCell:nil col:c row:_rows[i]]]; return c; }
- (NSGridRow *)insertRowAtIndex:(NSInteger)idx withViews:(NSArray *)views {
    while ([_cols count] < [views count]) [self _addColumn];
    NSGridRow *r = [[[NSGridRow alloc] init] autorelease];
    r->_grid = self;
    NSMutableArray *cells = [NSMutableArray array];
    for (NSUInteger i = 0; i < [_cols count]; i++) [cells addObject:[self _newCell:i < [views count] ? views[i] : nil col:_cols[i] row:r]];
    NSUInteger at = (NSUInteger)(idx < 0 ? 0 : idx > (NSInteger)[_rows count] ? (NSInteger)[_rows count] : idx);
    [_rows insertObject:r atIndex:at];
    [_cells insertObject:cells atIndex:at];
    self.needsLayout = YES;
    return r;
}
- (NSGridRow *)addRowWithViews:(NSArray *)v { return [self insertRowAtIndex:(NSInteger)[_rows count] withViews:v]; }
- (NSGridColumn *)addColumnWithViews:(NSArray *)v {
    NSGridColumn *c = [self _addColumn];
    for (NSUInteger i = 0; i < [v count] && i < [_rows count]; i++) { NSGridCell *cell = _cells[i][[_cols count] - 1]; cell.contentView = v[i]; [self addSubview:v[i]]; }
    self.needsLayout = YES;
    return c;
}
- (void)removeRowAtIndex:(NSInteger)i { for (NSGridCell *c in _cells[(NSUInteger)i]) [c.contentView removeFromSuperview]; [_cells removeObjectAtIndex:(NSUInteger)i]; [_rows removeObjectAtIndex:(NSUInteger)i]; self.needsLayout = YES; }
- (void)removeColumnAtIndex:(NSInteger)i { for (NSMutableArray *r in _cells) { [[r[(NSUInteger)i] contentView] removeFromSuperview]; [r removeObjectAtIndex:(NSUInteger)i]; } [_cols removeObjectAtIndex:(NSUInteger)i]; self.needsLayout = YES; }
- (void)mergeCellsInHorizontalRange:(NSRange)h verticalRange:(NSRange)v { }
- (void)_mwSizes:(CGFloat *)cw rows:(CGFloat *)rh {
    for (NSUInteger c = 0; c < [_cols count]; c++) cw[c] = 0;
    for (NSUInteger r = 0; r < [_rows count]; r++) {
        rh[r] = 0;
        for (NSUInteger c = 0; c < [_cols count]; c++) {
            NSView *v = [_cells[r][c] contentView];
            if (!v || v.isHidden) continue;
            NSSize s = fit(v);
            cw[c] = fmax(cw[c], s.width); rh[r] = fmax(rh[r], s.height);
        }
    }
    for (NSUInteger c = 0; c < [_cols count]; c++) { NSGridColumn *k = _cols[c]; if (k.isHidden) cw[c] = 0; else if (k.width > 0 && k.width != NSGridViewSizeForContent) cw[c] = k.width; }
    for (NSUInteger r = 0; r < [_rows count]; r++) { NSGridRow *k = _rows[r]; if (k.isHidden) rh[r] = 0; else if (k.height > 0 && k.height != NSGridViewSizeForContent) rh[r] = k.height; }
}
- (NSSize)intrinsicContentSize { return [self fittingSize]; }
- (NSSize)fittingSize {
    NSUInteger nc = [_cols count], nr = [_rows count];
    CGFloat cw[nc ? nc : 1], rh[nr ? nr : 1], w = 0, h = 0;
    [self _mwSizes:cw rows:rh];
    for (NSUInteger c = 0; c < nc; c++) w += cw[c] + (c ? _columnSpacing : 0);
    for (NSUInteger r = 0; r < nr; r++) h += rh[r] + (r ? _rowSpacing : 0);
    return NSMakeSize(w, h);
}
static NSGridCellPlacement place(NSGridCellPlacement cell, NSGridCellPlacement line, NSGridCellPlacement grid) {
    return cell != NSGridCellPlacementInherited ? cell : line != NSGridCellPlacementInherited ? line : grid;
}
- (void)layout {
    NSUInteger nc = [_cols count], nr = [_rows count];
    CGFloat cw[nc ? nc : 1], rh[nr ? nr : 1];
    [self _mwSizes:cw rows:rh];
    CGFloat y = 0;
    for (NSUInteger r = 0; r < nr; r++) {
        CGFloat x = 0;
        for (NSUInteger c = 0; c < nc; c++) {
            NSGridCell *cell = _cells[r][c];
            NSView *v = cell.contentView;
            if (v && !v.isHidden) {
                NSSize s = fit(v);
                NSGridCellPlacement xp = place(cell.xPlacement, [_cols[c] xPlacement], _xPlacement), yp = place(cell.yPlacement, [_rows[r] yPlacement], _yPlacement);
                CGFloat w = xp == NSGridCellPlacementFill ? cw[c] : fmin(s.width, cw[c]), h = yp == NSGridCellPlacementFill ? rh[r] : fmin(s.height, rh[r]);
                CGFloat ox = xp == NSGridCellPlacementTrailing ? cw[c] - w : xp == NSGridCellPlacementCenter ? (cw[c] - w) / 2 : 0;
                CGFloat oy = yp == NSGridCellPlacementBottom ? rh[r] - h : yp == NSGridCellPlacementCenter ? (rh[r] - h) / 2 : 0;
                [v setFrame:NSMakeRect(x + ox, y + oy, w, h)];
            }
            x += cw[c] + (cw[c] > 0 ? _columnSpacing : 0);
        }
        y += rh[r] + (rh[r] > 0 ? _rowSpacing : 0);
    }
}
@end
@implementation NSSplitView @end
@implementation NSTabViewItem
- (instancetype)initWithIdentifier:(id)i { if ((self = [super init])) self.identifier = i; return self; }
+ (instancetype)tabViewItemWithViewController:(NSViewController *)vc { NSTabViewItem *t = [[[self alloc] initWithIdentifier:nil] autorelease]; t.view = vc.view; t.label = vc.title; return t; }
- (void)dealloc { [_label release]; [_view release]; [_identifier release]; [super dealloc]; }
@end
@implementation NSTabView { NSMutableArray *_items; NSInteger _sel; }
- (void)dealloc { [_items release]; [super dealloc]; }
- (void)addTabViewItem:(NSTabViewItem *)i { if (!_items) _items = [[NSMutableArray alloc] init]; [_items addObject:i]; if ([_items count] == 1) [self selectTabViewItemAtIndex:0]; }
- (void)selectTabViewItemAtIndex:(NSInteger)i {
    [[self selectedTabViewItem].view removeFromSuperview];
    _sel = i;
    NSView *v = [self selectedTabViewItem].view;
    if (v) { v.frame = self.bounds; v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; [self addSubview:v]; }
}
- (NSArray *)tabViewItems { return _items ? [[_items copy] autorelease] : @[]; }
- (NSTabViewItem *)selectedTabViewItem { return _sel >= 0 && _sel < (NSInteger)[_items count] ? _items[(NSUInteger)_sel] : nil; }
@end
