/* misc.m — smaller AppKit classes apps link against: gesture recognizers, NSGradient, NSPopover (shown as a small
 * window), the shared color and font panels and NSFontManager, NSLayoutManager/NSTextStorage/NSTextContainer for measuring,
 * NSUserDefaultsController and NSController, a WebView that shows nothing, segmented controls from nibs, and the
 * pasteboard, workspace and binding constants. */
#import "internal.h"
@interface NSView (MWNibDecode) - (void)_mwDecodeNib:(NSCoder *)c; @end
extern void (*mw_defaults_change_hook)(NSString *key, BOOL did);

/* ======================================================================= constants and functions */
NSPasteboardName const NSPasteboardNameGeneral = @"Apple CFPasteboard general", NSPasteboardNameFont = @"Apple CFPasteboard font",
    NSPasteboardNameRuler = @"Apple CFPasteboard ruler", NSPasteboardNameFind = @"Apple CFPasteboard find", NSPasteboardNameDrag = @"Apple CFPasteboard drag";
NSString *const NSPasteboardURLReadingFileURLsOnlyKey = @"NSPasteboardURLReadingFileURLsOnlyKey",
    *const NSPasteboardURLReadingContentsConformToTypesKey = @"NSPasteboardURLReadingContentsConformToTypesKey";
NSImageName const NSImageNameStopProgressTemplate = @"NSStopProgressTemplate", NSImageNameStopProgressFreestandingTemplate = @"NSStopProgressFreestandingTemplate",
    NSImageNameRefreshTemplate = @"NSRefreshTemplate", NSImageNameAddTemplate = @"NSAddTemplate", NSImageNameRemoveTemplate = @"NSRemoveTemplate",
    NSImageNameActionTemplate = @"NSActionTemplate", NSImageNameFolder = @"NSFolder", NSImageNameMultipleDocuments = @"NSMultipleDocuments",
    NSImageNameGoLeftTemplate = @"NSGoLeftTemplate", NSImageNameGoRightTemplate = @"NSGoRightTemplate", NSImageNameMenuOnStateTemplate = @"NSMenuOnStateTemplate",
    NSImageNameLockLockedTemplate = @"NSLockLockedTemplate", NSImageNameLockUnlockedTemplate = @"NSLockUnlockedTemplate";
NSString *const NSWorkspaceRecycleOperation = @"recycle", *const NSWorkspaceMoveOperation = @"move", *const NSWorkspaceCopyOperation = @"copy";
NSNotificationName const NSWorkspaceWillPowerOffNotification = @"NSWorkspaceWillPowerOffNotification",
    NSWorkspaceDidMountNotification = @"NSWorkspaceDidMountNotification", NSWorkspaceDidUnmountNotification = @"NSWorkspaceDidUnmountNotification",
    NSWorkspaceWillUnmountNotification = @"NSWorkspaceWillUnmountNotification";
NSNotificationName const NSColorPanelColorDidChangeNotification = @"NSColorPanelColorDidChangeNotification";
NSString *const NSObservedObjectKey = @"NSObservedObject", *const NSObservedKeyPathKey = @"NSObservedKeyPath", *const NSOptionsKey = @"NSOptions";
NSString *const NSValueTransformerBindingOption = @"NSValueTransformer", *const NSValueTransformerNameBindingOption = @"NSValueTransformerName",
    *const NSContinuouslyUpdatesValueBindingOption = @"NSContinuouslyUpdatesValue", *const NSNullPlaceholderBindingOption = @"NSNullPlaceholder",
    *const NSValueBinding = @"value", *const NSEnabledBinding = @"enabled", *const NSHiddenBinding = @"hidden", *const NSTitleBinding = @"title";
void NSFrameRectWithWidthUsingOperation(NSRect r, CGFloat w, NSCompositingOperation op) { NSFrameRectWithWidth(r, w); }
void NSRectFillListWithColors(const NSRect *r, NSColor *const *c, NSInteger n) { for (NSInteger i = 0; i < n; i++) { [c[i] set]; NSRectFill(r[i]); } }
void NSRectFillListWithColorsUsingOperation(const NSRect *r, NSColor *const *c, NSInteger n, NSCompositingOperation op) { NSRectFillListWithColors(r, c, n); }
void NSRectFillListWithGrays(const NSRect *r, const CGFloat *g, NSInteger n) { for (NSInteger i = 0; i < n; i++) { [[NSColor colorWithWhite:g[i] alpha:1] set]; NSRectFill(r[i]); } }
void NSRectFillListUsingOperation(const NSRect *r, NSInteger n, NSCompositingOperation op) { NSRectFillList(r, n); }
void NSSetFocusRingStyle(NSFocusRingPlacement p) { }

/* ======================================================================= gesture recognizers (state only: views get the mouse events) */
@implementation NSGestureRecognizer
- (instancetype)initWithTarget:(id)t action:(SEL)a { if ((self = [super init])) { _target = t; _action = a; _enabled = YES; } return self; }
- (instancetype)init { return [self initWithTarget:nil action:NULL]; }
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [self initWithTarget:[c decodeObjectForKey:@"NSGestureRecognizer.target"] action:NSSelectorFromString([c decodeObjectForKey:@"NSGestureRecognizer.action"])];
    if ([c containsValueForKey:@"NSGestureRecognizer.enabled"]) _enabled = [c decodeBoolForKey:@"NSGestureRecognizer.enabled"];
    return self;
}
- (NSPoint)locationInView:(NSView *)v { return [v convertPoint:[NSApp currentEvent].locationInWindow fromView:nil]; }
- (void)reset {}
@end
@implementation NSClickGestureRecognizer
- (instancetype)initWithTarget:(id)t action:(SEL)a { if ((self = [super initWithTarget:t action:a])) { _numberOfClicksRequired = 1; _buttonMask = 1; } return self; }
@end
@implementation NSPanGestureRecognizer
- (NSPoint)translationInView:(NSView *)v { return NSZeroPoint; }
- (void)setTranslation:(NSPoint)p inView:(NSView *)v {}
- (NSPoint)velocityInView:(NSView *)v { return NSZeroPoint; }
@end
@implementation NSMagnificationGestureRecognizer @end
@implementation NSPressGestureRecognizer @end
@implementation NSRotationGestureRecognizer @end
@implementation NSView (MWGestures)
- (NSArray *)gestureRecognizers { return objc_getAssociatedObject(self, "mw_gestures") ?: @[]; }
- (void)setGestureRecognizers:(NSArray *)g { objc_setAssociatedObject(self, "mw_gestures", g, OBJC_ASSOCIATION_COPY); for (NSGestureRecognizer *r in g) r.view = self; }
- (void)addGestureRecognizer:(NSGestureRecognizer *)g { self.gestureRecognizers = [self.gestureRecognizers arrayByAddingObject:g]; }
- (void)removeGestureRecognizer:(NSGestureRecognizer *)g { NSMutableArray *a = [[self.gestureRecognizers mutableCopy] autorelease]; [a removeObjectIdenticalTo:g]; self.gestureRecognizers = a; }
@end

/* ======================================================================= NSGradient */
@implementation NSGradient { NSArray *_colors; CGFloat *_locs; }
- (instancetype)initWithStartingColor:(NSColor *)a endingColor:(NSColor *)b { CGFloat l[2] = {0, 1}; return [self initWithColors:@[a, b] atLocations:l colorSpace:nil]; }
- (instancetype)initWithColors:(NSArray *)c {
    NSUInteger n = [c count]; CGFloat *l = malloc((n ? n : 1) * sizeof *l);
    for (NSUInteger i = 0; i < n; i++) l[i] = n > 1 ? (CGFloat)i / (n - 1) : 0;
    self = [self initWithColors:c atLocations:l colorSpace:nil]; free(l); return self;
}
- (instancetype)initWithColors:(NSArray *)c atLocations:(const CGFloat *)l colorSpace:(NSColorSpace *)s {
    if (![c count]) { [self release]; return nil; }
    _colors = [c copy]; _locs = malloc([c count] * sizeof *_locs); memcpy(_locs, l, [c count] * sizeof *_locs);
    return self;
}
- (instancetype)initWithColorsAndLocations:(NSColor *)first, ... {
    NSMutableArray *c = [NSMutableArray array]; CGFloat l[64]; va_list ap; va_start(ap, first);
    for (NSColor *k = first; k && [c count] < 64; k = va_arg(ap, NSColor *)) { l[[c count]] = va_arg(ap, double); [c addObject:k]; }
    va_end(ap);
    return [self initWithColors:c atLocations:l colorSpace:nil];
}
- (void)dealloc { [_colors release]; free(_locs); [super dealloc]; }
- (NSInteger)numberOfColorStops { return (NSInteger)[_colors count]; }
- (void)getColor:(NSColor **)c location:(CGFloat *)l atIndex:(NSInteger)i { if (c) *c = _colors[(NSUInteger)i]; if (l) *l = _locs[i]; }
- (NSColor *)interpolatedColorAtLocation:(CGFloat)t {
    NSUInteger n = [_colors count];
    if (n == 1 || t <= _locs[0]) return _colors[0];
    for (NSUInteger i = 1; i < n; i++) if (t <= _locs[i]) {
        CGFloat f = _locs[i] > _locs[i - 1] ? (t - _locs[i - 1]) / (_locs[i] - _locs[i - 1]) : 1;
        NSColor *a = [_colors[i - 1] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]], *b = [_colors[i] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        return [NSColor colorWithSRGBRed:a.redComponent + (b.redComponent - a.redComponent) * f green:a.greenComponent + (b.greenComponent - a.greenComponent) * f
                                    blue:a.blueComponent + (b.blueComponent - a.blueComponent) * f alpha:a.alphaComponent + (b.alphaComponent - a.alphaComponent) * f];
    }
    return [_colors lastObject];
}
/* ponytail: bands of solid color (32 steps) instead of a smooth shading */
- (void)drawInRect:(NSRect)r angle:(CGFloat)deg {
    BOOL vert = fmod(fabs(deg), 180) > 45 && fmod(fabs(deg), 180) < 135, rev = vert ? sin(deg * M_PI / 180) < 0 : cos(deg * M_PI / 180) < 0;
    int n = 32;
    for (int i = 0; i < n; i++) {
        CGFloat t0 = (CGFloat)i / n, t = (i + 0.5) / n;
        [[self interpolatedColorAtLocation:rev ? 1 - t : t] set];
        NSRectFill(vert ? NSMakeRect(r.origin.x, r.origin.y + r.size.height * t0, r.size.width, ceil(r.size.height / n) + 1)
                        : NSMakeRect(r.origin.x + r.size.width * t0, r.origin.y, ceil(r.size.width / n) + 1, r.size.height));
    }
}
- (void)drawInBezierPath:(NSBezierPath *)p angle:(CGFloat)a {
    [NSGraphicsContext saveGraphicsState]; [p addClip]; [self drawInRect:[p bounds] angle:a]; [NSGraphicsContext restoreGraphicsState];
}
- (void)drawFromPoint:(NSPoint)a toPoint:(NSPoint)b options:(NSGradientDrawingOptions)o {
    CGContextRef c = mw_cg(); CGRect clip = CGContextGetClipBoundingBox(c);
    [self drawInRect:clip angle:atan2(b.y - a.y, b.x - a.x) * 180 / M_PI];
}
- (void)drawInRect:(NSRect)r relativeCenterPosition:(NSPoint)p { [self drawInRect:r angle:90]; }
- (void)drawInBezierPath:(NSBezierPath *)p relativeCenterPosition:(NSPoint)c { [self drawInBezierPath:p angle:90]; }
@end

/* ======================================================================= NSPopover: its content in a small borderless window */
NSNotificationName const NSPopoverWillShowNotification = @"NSPopoverWillShowNotification", NSPopoverDidShowNotification = @"NSPopoverDidShowNotification",
    NSPopoverWillCloseNotification = @"NSPopoverWillCloseNotification", NSPopoverDidCloseNotification = @"NSPopoverDidCloseNotification";
@implementation NSPopover { NSWindow *_win; }
- (void)dealloc { if (_contentViewController) objc_setAssociatedObject(_contentViewController, "mw_popover", nil, OBJC_ASSOCIATION_ASSIGN); [_contentViewController release]; [_win close]; [_win release]; [super dealloc]; }
- (BOOL)isShown { return _win.isVisible; }
/* each dimension: the one set on the popover, else the controller's preferred size, else the view's fitting size */
- (NSSize)contentSize {
    NSViewController *c = _contentViewController;
    NSSize p = c.preferredContentSize, f = (p.width > 0 && p.height > 0) ? p : c.view.fittingSize, v = c.view.frame.size;
    return NSMakeSize(_contentSize.width > 0 ? _contentSize.width : p.width > 0 ? p.width : f.width > 0 ? f.width : v.width,
                      _contentSize.height > 0 ? _contentSize.height : p.height > 0 ? p.height : f.height > 0 ? f.height : v.height);
}
- (void)_mwContentSizeChanged {
    if (!_win.isVisible) return;
    NSSize sz = [self contentSize]; NSRect c = [_win contentRectForFrameRect:_win.frame];
    c.origin.y += c.size.height - sz.height; c.size = sz;   /* the top edge stays under the status item */
    [_win setFrame:[_win frameRectForContentRect:c] display:YES];
}
- (void)showRelativeToRect:(NSRect)r ofView:(NSView *)v preferredEdge:(NSRectEdge)e {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:NSPopoverWillShowNotification object:self];
    if (_contentViewController) objc_setAssociatedObject(_contentViewController, "mw_popover", self, OBJC_ASSOCIATION_ASSIGN);
    NSSize sz = [self contentSize];
    NSRect inWin = [v convertRect:r toView:nil], onScreen = [v.window convertRectToScreen:inWin];
    NSRect f = NSMakeRect(NSMidX(onScreen) - sz.width / 2, NSMinY(onScreen) - sz.height - 4, sz.width, sz.height);
    if (!_win) { _win = [[NSPanel alloc] initWithContentRect:f styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO]; _win.releasedWhenClosed = NO; }
    _win.contentViewController = _contentViewController;   /* (this sizes the window to the view: the frame comes after) */
    [_win setFrame:[_win frameRectForContentRect:f] display:NO];
    [_win makeKeyAndOrderFront:nil];
    if ([(id)_delegate respondsToSelector:@selector(popoverDidShow:)]) [_delegate popoverDidShow:[NSNotification notificationWithName:NSPopoverDidShowNotification object:self]];
    [nc postNotificationName:NSPopoverDidShowNotification object:self];
}
- (void)close { if (!_win.isVisible) return; [[NSNotificationCenter defaultCenter] postNotificationName:NSPopoverWillCloseNotification object:self]; [_win orderOut:nil]; [[NSNotificationCenter defaultCenter] postNotificationName:NSPopoverDidCloseNotification object:self]; }
- (void)performClose:(id)s { [self close]; }
@end

/* ======================================================================= color and font panels, font manager */
@implementation NSColorPanel { NSColor *_color; }
+ (NSColorPanel *)sharedColorPanel { static NSColorPanel *p; if (!p) { p = [[self alloc] initWithContentRect:NSMakeRect(0, 0, 220, 120) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:YES]; p.title = @"Colors"; p.releasedWhenClosed = NO; } return p; }
+ (BOOL)sharedColorPanelExists { return NO; }
+ (void)setPickerMask:(NSColorPanelOptions)m {} + (void)setPickerMode:(NSColorPanelMode)m {}
- (NSColor *)color { return _color ?: [NSColor whiteColor]; }
- (void)setColor:(NSColor *)c { [c retain]; [_color release]; _color = c; [[NSNotificationCenter defaultCenter] postNotificationName:NSColorPanelColorDidChangeNotification object:self]; }
- (void)setTarget:(id)t {} - (void)setAction:(SEL)a {}
- (void)setContinuous:(BOOL)c {} - (void)setShowsAlpha:(BOOL)a {}
- (void)attachColorList:(id)l {}
@end
@implementation NSFontPanel
+ (NSFontPanel *)sharedFontPanel { static NSFontPanel *p; if (!p) { p = [[self alloc] initWithContentRect:NSMakeRect(0, 0, 300, 120) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:YES]; p.title = @"Fonts"; p.releasedWhenClosed = NO; } return p; }
+ (BOOL)sharedFontPanelExists { return NO; }
- (void)setPanelFont:(NSFont *)f isMultiple:(BOOL)m {}
- (NSFont *)panelConvertFont:(NSFont *)f { return f; }
@end
@implementation NSFontManager { NSFont *_selected; }
+ (NSFontManager *)sharedFontManager { static NSFontManager *m; if (!m) m = [[self alloc] init]; return m; }
+ (void)setFontManagerFactory:(Class)c {} + (void)setFontPanelFactory:(Class)c {}
- (NSArray *)availableFonts { return @[@"Helvetica", @"Helvetica-Bold", @"Menlo-Regular", @"Menlo-Bold", @"Courier", @"Times-Roman", @"Monaco"]; }
- (NSArray *)availableFontFamilies { return @[@"Helvetica", @"Menlo", @"Courier", @"Times", @"Monaco"]; }
- (NSArray *)availableMembersOfFontFamily:(NSString *)f { return @[@[f, @"Regular", @5, @0]]; }
- (NSArray *)availableFontNamesWithTraits:(NSFontTraitMask)t { return (t & NSFixedPitchFontMask) ? @[@"Menlo-Regular", @"Courier", @"Monaco"] : [self availableFonts]; }
- (NSFont *)convertFont:(NSFont *)f { return f; }
- (NSFont *)convertFont:(NSFont *)f toSize:(CGFloat)s { return [NSFont fontWithName:f.fontName size:s] ?: f; }
- (NSFont *)convertFont:(NSFont *)f toHaveTrait:(NSFontTraitMask)t { return (t & NSBoldFontMask) ? ([NSFont fontWithName:[f.familyName stringByAppendingString:@"-Bold"] size:f.pointSize] ?: [NSFont boldSystemFontOfSize:f.pointSize]) : f; }
- (NSFont *)convertFont:(NSFont *)f toNotHaveTrait:(NSFontTraitMask)t { return f; }
- (NSFont *)convertFont:(NSFont *)f toFamily:(NSString *)fam { return [NSFont fontWithName:fam size:f.pointSize] ?: f; }
- (NSFontTraitMask)traitsOfFont:(NSFont *)f { return (f.isFixedPitch ? NSFixedPitchFontMask : 0) | ([f.fontName rangeOfString:@"Bold"].location != NSNotFound ? NSBoldFontMask : 0); }
- (NSInteger)weightOfFont:(NSFont *)f { return [f.fontName rangeOfString:@"Bold"].location != NSNotFound ? 9 : 5; }
- (NSFont *)fontWithFamily:(NSString *)fam traits:(NSFontTraitMask)t weight:(NSInteger)w size:(CGFloat)s { return [NSFont fontWithName:fam size:s]; }
- (NSFont *)selectedFont { return _selected; }
- (void)setSelectedFont:(NSFont *)f isMultiple:(BOOL)m { [f retain]; [_selected release]; _selected = f; }
- (void)orderFrontFontPanel:(id)s { [[NSFontPanel sharedFontPanel] makeKeyAndOrderFront:s]; }
- (void)addFontTrait:(id)s {} - (void)removeFontTrait:(id)s {} - (void)modifyFont:(id)s {} - (void)modifyFontViaPanel:(id)s {}
- (id)target { return nil; } - (void)setTarget:(id)t {} - (SEL)action { return @selector(changeFont:); } - (void)setAction:(SEL)a {}
- (id)delegate { return nil; } - (void)setDelegate:(id)d {}
- (BOOL)isEnabled { return YES; } - (void)setEnabled:(BOOL)e {}
- (NSMenu *)fontMenu:(BOOL)create { return nil; }
@end

/* ======================================================================= text system objects (measuring only) */
NSNotificationName const NSTextStorageWillProcessEditingNotification = @"NSTextStorageWillProcessEditingNotification",
    NSTextStorageDidProcessEditingNotification = @"NSTextStorageDidProcessEditingNotification";
@interface NSTextView (MWLayout) - (void)_mwLayout; @end
/* an edit (outside beginEditing/endEditing) is announced, and the text views showing the storage lay it out again */
@implementation NSTextStorage { int _editing; BOOL _edited; }
- (void)_mwEdited {
    if (_editing) { _edited = YES; return; }
    _edited = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTextStorageWillProcessEditingNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTextStorageDidProcessEditingNotification object:self];
    for (NSLayoutManager *m in _layoutManagers) for (NSTextContainer *c in m.textContainers) [c.textView _mwLayout];
}
- (void)beginEditing { _editing++; }
- (void)endEditing { if (_editing > 0 && !--_editing && _edited) [self _mwEdited]; }
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s { _editing++; [super replaceCharactersInRange:r withString:s]; _editing--; _edited = YES; [self _mwEdited]; }
- (void)replaceCharactersInRange:(NSRange)r withAttributedString:(NSAttributedString *)s { _editing++; [super replaceCharactersInRange:r withAttributedString:s]; _editing--; _edited = YES; [self _mwEdited]; }
- (void)setAttributes:(NSDictionary *)a range:(NSRange)r { _editing++; [super setAttributes:a range:r]; _editing--; _edited = YES; [self _mwEdited]; }
- (void)addAttributes:(NSDictionary *)a range:(NSRange)r { _editing++; [super addAttributes:a range:r]; _editing--; _edited = YES; [self _mwEdited]; }
- (void)removeAttribute:(NSString *)n range:(NSRange)r { _editing++; [super removeAttribute:n range:r]; _editing--; _edited = YES; [self _mwEdited]; }
- (void)addLayoutManager:(NSLayoutManager *)m { if (!_layoutManagers) _layoutManagers = [[NSMutableArray alloc] init]; [(NSMutableArray *)_layoutManagers addObject:m]; m.textStorage = self; }
- (void)removeLayoutManager:(NSLayoutManager *)m { [(NSMutableArray *)_layoutManagers removeObjectIdenticalTo:m]; }
- (void)dealloc { [_layoutManagers release]; [super dealloc]; }
@end
@implementation NSTextContainer
- (instancetype)initWithSize:(NSSize)s { if ((self = [super init])) { _size = s; _lineFragmentPadding = 5; } return self; }
- (instancetype)initWithContainerSize:(NSSize)s { return [self initWithSize:s]; }
- (instancetype)init { return [self initWithSize:NSMakeSize(1e7, 1e7)]; }
- (NSSize)containerSize { return _size; } - (void)setContainerSize:(NSSize)s { _size = s; }
@end
@implementation NSLayoutManager { NSMutableArray *_containers; }
- (instancetype)init { if ((self = [super init])) _containers = [[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [_containers release]; [super dealloc]; }
- (NSArray *)textContainers { return [[_containers copy] autorelease]; }
- (void)addTextContainer:(NSTextContainer *)c { [_containers addObject:c]; c.layoutManager = self; }
- (void)removeTextContainerAtIndex:(NSUInteger)i { [_containers removeObjectAtIndex:i]; }
- (CGFloat)defaultLineHeightForFont:(NSFont *)f { CGFloat a, d; mw_font_metrics(f, &a, &d); return ceil(a + d); }
- (CGFloat)defaultBaselineOffsetForFont:(NSFont *)f { CGFloat a, d; mw_font_metrics(f, &a, &d); return ceil(a); }
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)c { return NSMakeRange(0, [_textStorage length]); }
- (NSRect)usedRectForTextContainer:(NSTextContainer *)c {
    NSSize s = mw_attr_size(_textStorage, c.size.width < 1e6 ? c.size.width - 2 * c.lineFragmentPadding : 0);
    return NSMakeRect(0, 0, s.width + 2 * c.lineFragmentPadding, s.height);
}
- (void)ensureLayoutForTextContainer:(NSTextContainer *)c {}
- (NSUInteger)numberOfGlyphs { return [_textStorage length]; }
- (NSRect)boundingRectForGlyphRange:(NSRange)r inTextContainer:(NSTextContainer *)c { return [self usedRectForTextContainer:c]; }
- (void)drawGlyphsForGlyphRange:(NSRange)r atPoint:(NSPoint)p {
    NSTextContainer *c = [_containers firstObject];
    CGFloat w = c && c.size.width < 1e6 ? c.size.width - 2 * c.lineFragmentPadding : 0;
    mw_attr_draw(_textStorage, NSMakeRect(p.x + (c ? c.lineFragmentPadding : 0), p.y, w, 0), w > 0);
}
- (void)drawBackgroundForGlyphRange:(NSRange)r atPoint:(NSPoint)p {}
@end

/* ======================================================================= controllers for bindings */
@implementation NSController
- (BOOL)commitEditing { return YES; }
- (void)discardEditing {}
- (BOOL)isEditing { return NO; }
- (instancetype)initWithCoder:(NSCoder *)c { return [self init]; }
@end
/* values.<key> reads and writes the user defaults */
@interface _MWDefaultsValues : NSObject @end
@implementation _MWDefaultsValues
- (id)valueForKey:(NSString *)k { return [[NSUserDefaults standardUserDefaults] objectForKey:k]; }
- (void)setValue:(id)v forKey:(NSString *)k { [[NSUserDefaults standardUserDefaults] setObject:v forKey:k]; }
@end
@implementation NSUserDefaultsController { _MWDefaultsValues *_values; NSDictionary *_initial; }
static NSUserDefaultsController *g_udc;
static void defaults_changed(NSString *k, BOOL did) {   /* observers of values.<key> */
    NSString *p = [@"values." stringByAppendingString:k];
    if (did) { [g_udc->_values didChangeValueForKey:k]; [g_udc didChangeValueForKey:p]; }
    else { [g_udc->_values willChangeValueForKey:k]; [g_udc willChangeValueForKey:p]; }
}
+ (NSUserDefaultsController *)sharedUserDefaultsController {
    if (!g_udc) { g_udc = [[self alloc] initWithDefaults:nil initialValues:nil]; mw_defaults_change_hook = defaults_changed; }
    return g_udc;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)d initialValues:(NSDictionary *)v {
    if ((self = [super init])) { _values = [[_MWDefaultsValues alloc] init]; _initial = [v copy]; _appliesImmediately = YES; }
    return self;
}
- (instancetype)init { return [self initWithDefaults:nil initialValues:nil]; }
- (instancetype)initWithCoder:(NSCoder *)c {
    if ([c decodeBoolForKey:@"NSSharedInstance"] || ![c containsValueForKey:@"NSSharedInstance"]) { [self release]; return [[NSUserDefaultsController sharedUserDefaultsController] retain]; }
    return [self init];
}
- (void)dealloc { [_values release]; [_initial release]; [super dealloc]; }
- (NSUserDefaults *)defaults { return [NSUserDefaults standardUserDefaults]; }
- (id)values { return _values; }
- (NSDictionary *)initialValues { return _initial; }
- (void)setInitialValues:(NSDictionary *)v { [_initial release]; _initial = [v copy]; if (v) [[NSUserDefaults standardUserDefaults] registerDefaults:v]; }
- (void)revert:(id)s {} - (void)save:(id)s { [[NSUserDefaults standardUserDefaults] synchronize]; }
- (void)revertToInitialValues:(id)s { for (NSString *k in _initial) [_values setValue:_initial[k] forKey:k]; }
- (BOOL)hasUnappliedChanges { return NO; }
@end
@implementation NSObjectController
- (instancetype)initWithContent:(id)c { if ((self = [super init])) _content = [c retain]; return self; }
- (void)dealloc { [_content release]; [super dealloc]; }
- (id)selection { return _content; }
- (NSArray *)selectedObjects { return _content ? @[_content] : @[]; }
@end
@implementation NSArrayController
- (NSArray *)arrangedObjects { return [self.content isKindOfClass:[NSArray class]] ? self.content : @[]; }
- (void)addObject:(id)o { if (!self.content) self.content = [NSMutableArray array]; if ([self.content respondsToSelector:@selector(addObject:)]) [self.content addObject:o]; }
- (void)removeObject:(id)o { if ([self.content respondsToSelector:@selector(removeObject:)]) [self.content removeObject:o]; }
- (NSUInteger)selectionIndex { return NSNotFound; }
- (BOOL)setSelectionIndex:(NSUInteger)i { return NO; }
- (NSIndexSet *)selectionIndexes { return [NSIndexSet indexSet]; }
- (BOOL)setSelectionIndexes:(NSIndexSet *)i { return NO; }
- (void)rearrangeObjects {}
@end

/* ======================================================================= WebView (legacy WebKit): an empty view */
@implementation WebView
- (id)mainFrame { return nil; }
- (void)setFrameLoadDelegate:(id)d {} - (void)setPolicyDelegate:(id)d {} - (void)setUIDelegate:(id)d {} - (void)setResourceLoadDelegate:(id)d {}
- (void)setDrawsBackground:(BOOL)d {} - (void)setMainFrameURL:(NSString *)u {}
- (void)drawRect:(NSRect)r { mw_draw_text_in(@"Web content is not available in scion.", self.bounds, [NSFont systemFontOfSize:12], [NSColor secondaryLabelColor], NSTextAlignmentCenter, NSLineBreakByWordWrapping, YES, YES); }
@end

/* ======================================================================= segmented controls from nibs */
@interface NSSegmentItem : NSObject { @public NSString *label; NSImage *image; NSInteger tag; CGFloat width; BOOL selected, disabled; } @end
@implementation NSSegmentItem
- (instancetype)initWithCoder:(NSCoder *)c {
    label = [[c decodeObjectForKey:@"NSSegmentItemLabel"] copy]; image = [[c decodeObjectForKey:@"NSSegmentItemImage"] retain];
    tag = [c decodeIntegerForKey:@"NSSegmentItemTag"]; width = [c decodeDoubleForKey:@"NSSegmentItemWidth"];
    selected = [c decodeBoolForKey:@"NSSegmentItemSelected"]; disabled = [c decodeBoolForKey:@"NSSegmentItemDisabled"];
    return self;
}
- (void)dealloc { [label release]; [image release]; [super dealloc]; }
@end
@implementation NSSegmentedControl (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    NSCell *cell = [c decodeObjectForKey:@"NSCell"];
    NSArray *items = [cell respondsToSelector:@selector(_mwNib:)] ? [(id)cell performSelector:@selector(_mwNib:) withObject:@"NSSegmentImages"] : nil;
    if (![items isKindOfClass:[NSArray class]]) return;
    self.segmentCount = (NSInteger)[items count];
    for (NSUInteger i = 0; i < [items count]; i++) {
        NSSegmentItem *s = items[i];
        if (![s isKindOfClass:[NSSegmentItem class]]) continue;
        if (s->label) [self setLabel:s->label forSegment:(NSInteger)i];
        if (s->width > 0) [self setWidth:s->width forSegment:(NSInteger)i];
        if (s->disabled) [self setEnabled:NO forSegment:(NSInteger)i];
        if (s->selected) [self setSelected:YES forSegment:(NSInteger)i];
        if ([self respondsToSelector:@selector(setTag:forSegment:)]) [self setTag:s->tag forSegment:(NSInteger)i];
        if (s->image && [self respondsToSelector:@selector(setImage:forSegment:)]) [self setImage:s->image forSegment:(NSInteger)i];
    }
}
@end

/* ======================================================================= small additions apps call */
@implementation NSColor (MWMoreColors)
+ (NSArray *)alternatingContentBackgroundColors { return @[[NSColor controlBackgroundColor], [NSColor colorWithWhite:0.5 alpha:0.06]]; }
+ (NSArray *)controlAlternatingRowBackgroundColors { return [self alternatingContentBackgroundColors]; }
+ (NSColor *)textInsertionPointColor { return [NSColor textColor]; }
+ (NSColor *)unemphasizedSelectedTextBackgroundColor { return [NSColor colorWithWhite:0.5 alpha:0.3]; }
+ (NSColor *)colorWithCalibratedHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)b alpha:(CGFloat)a { return [NSColor colorWithHue:h saturation:s brightness:b alpha:a]; }
- (NSColor *)colorUsingType:(NSInteger)t { return self; }
@end
@implementation NSWindow (MWMore)
- (void)disableFlushWindow {} - (void)enableFlushWindow {}
- (void)setContentBorderThickness:(CGFloat)t forEdge:(NSRectEdge)e {} - (CGFloat)contentBorderThicknessForEdge:(NSRectEdge)e { return 0; }
- (void)setAutorecalculatesContentBorderThickness:(BOOL)f forEdge:(NSRectEdge)e {}
- (NSArray *)tabbedWindows { return nil; }
@end
@implementation NSView (MWMenuItem) - (NSMenuItem *)enclosingMenuItem { return nil; } @end
@implementation NSScrollView (MWSizes)
+ (NSSize)frameSizeForContentSize:(NSSize)s hasHorizontalScroller:(BOOL)h hasVerticalScroller:(BOOL)v borderType:(NSBorderType)b {
    CGFloat e = b == NSNoBorder ? 0 : 2; return NSMakeSize(s.width + e + (v ? 15 : 0), s.height + e + (h ? 15 : 0));
}
+ (NSSize)contentSizeForFrameSize:(NSSize)s hasHorizontalScroller:(BOOL)h hasVerticalScroller:(BOOL)v borderType:(NSBorderType)b {
    CGFloat e = b == NSNoBorder ? 0 : 2; return NSMakeSize(s.width - e - (v ? 15 : 0), s.height - e - (h ? 15 : 0));
}
- (void)setUsesPredominantAxisScrolling:(BOOL)f {} - (BOOL)usesPredominantAxisScrolling { return YES; }
@end
@implementation NSWorkspace (MWMore)
- (NSImage *)iconForFileType:(NSString *)t { return [NSImage imageNamed:@"NSMultipleDocuments"]; }
- (BOOL)performFileOperation:(NSString *)op source:(NSString *)src destination:(NSString *)dst files:(NSArray *)files tag:(NSInteger *)tag {
    if (tag) *tag = -1;
    return NO;   /* ponytail: no Trash yet; never delete for real in its place */
}
@end
@implementation NSImage (MWMore) - (void)lockFocusFlipped:(BOOL)f { [self lockFocus]; } @end
@implementation NSFont (MWMore)
- (NSSize)maximumAdvancement { return NSMakeSize(mw_text_size(@"W", self).width, 0); }
- (NSCharacterSet *)coveredCharacterSet { return [(id)CTFontCopyCharacterSet((CTFontRef)self) autorelease]; }
@end
@implementation NSApplication (MWDocuments) - (NSArray *)orderedDocuments { id dc = mw_document_controller_if_any(); return dc ? [dc documents] : @[]; } @end
@implementation NSPasteboard (MWMore)
+ (NSPasteboard *)pasteboardWithName:(NSPasteboardName)n { return [NSPasteboard generalPasteboard]; }   /* ponytail: one pasteboard (the Windows clipboard) */
- (id)propertyListForType:(NSPasteboardType)t { NSData *d = [self dataForType:t]; return d ? [NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:NULL] : nil; }
- (BOOL)setPropertyList:(id)p forType:(NSPasteboardType)t { NSData *d = [NSPropertyListSerialization dataWithPropertyList:p format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL]; return d && [self setData:d forType:t]; }
@end
@implementation NSTextView (MWFind) - (void)performFindPanelAction:(id)s {} @end
@implementation NSSavePanel (MWMore) - (void)setTreatsFilePackagesAsDirectories:(BOOL)f {} - (BOOL)treatsFilePackagesAsDirectories { return NO; } @end
@implementation NSOpenPanel (MWMore) - (void)setAccessoryViewDisclosed:(BOOL)f {} - (BOOL)isAccessoryViewDisclosed { return YES; } @end
@implementation WebView (MWPrefs) - (id)preferences { return nil; } - (void)setPreferences:(id)p {} - (void)stopLoading:(id)s {} @end

/* ======================================================================= bindings: the bound value follows the model through KVO */
@interface NSObject (MWBindingStore) - (NSMutableDictionary *)_mwBindings; @end
@interface _MWBinding : NSObject { @public id target; NSString *binding, *keyPath; id observed; NSDictionary *options; } @end
@implementation _MWBinding
- (void)dealloc { [observed removeObserver:self forKeyPath:keyPath]; [binding release]; [keyPath release]; [observed release]; [options release]; [super dealloc]; }
- (void)_mwApply {
    id v = [observed valueForKeyPath:keyPath];
    NSValueTransformer *t = options[NSValueTransformerBindingOption];
    if (!t && options[NSValueTransformerNameBindingOption]) t = [NSValueTransformer valueTransformerForName:options[NSValueTransformerNameBindingOption]];
    if (t) v = [t transformedValue:v];
    if (!v && options[NSNullPlaceholderBindingOption]) v = options[NSNullPlaceholderBindingOption];
    NSString *b = binding;
    @try {
        if ([b hasPrefix:@"displayPatternValue"] || [b hasPrefix:@"displayPatternTitle"]) {   /* "%{value1}@ of %{value2}@" */
            NSString *pattern = nil; NSMutableString *out = nil;
            BOOL title = [b hasPrefix:@"displayPatternTitle"];
            NSDictionary *all = [target _mwBindings];
            for (NSString *k in all) {
                _MWBinding *o = all[k];
                if (![k hasPrefix:title ? @"displayPatternTitle" : @"displayPatternValue"]) continue;
                if (!pattern) pattern = o->options[@"NSDisplayPattern"];
            }
            if (!pattern) return;
            out = [[pattern mutableCopy] autorelease];
            for (NSString *k in all) {
                if (![k hasPrefix:title ? @"displayPatternTitle" : @"displayPatternValue"]) continue;
                _MWBinding *o = all[k];
                id val = [o->observed valueForKeyPath:o->keyPath];
                NSString *tok = [NSString stringWithFormat:@"%%{%@%@}@", title ? @"title" : @"value", [k substringFromIndex:19]];
                [out replaceOccurrencesOfString:tok withString:val ? [val description] : @"" options:0 range:NSMakeRange(0, [out length])];
            }
            if (title && [target respondsToSelector:@selector(setTitle:)]) [target setTitle:out]; else if ([target respondsToSelector:@selector(setStringValue:)]) [target setStringValue:out];
            return;
        }
        if ([b isEqualToString:NSValueBinding] && [target isKindOfClass:[NSButton class]]) [(NSButton *)target setState:[v boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
        else if ([b isEqualToString:NSValueBinding] && [target respondsToSelector:@selector(setObjectValue:)]) [target setObjectValue:v];
        else if ([b isEqualToString:NSEnabledBinding] || [b hasPrefix:@"enabled"]) [target setValue:@([v boolValue]) forKey:@"enabled"];
        else if ([b isEqualToString:NSHiddenBinding]) [target setValue:@([v boolValue]) forKey:@"hidden"];
        else if ([b isEqualToString:@"selectedIndex"] && [target respondsToSelector:@selector(selectItemAtIndex:)]) [target selectItemAtIndex:[v integerValue]];
        else if ([b isEqualToString:@"selectedTag"] && [target respondsToSelector:@selector(selectItemWithTag:)]) [target selectItemWithTag:[v integerValue]];
        else [target setValue:v forKey:b];
    } @catch (NSException *e) {}
}
- (void)observeValueForKeyPath:(NSString *)p ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx { [self _mwApply]; }
@end
@implementation NSObject (NSKeyValueBindingCreation)
+ (void)exposeBinding:(NSString *)b {}
- (NSArray *)exposedBindings { return @[]; }
- (Class)valueClassForBinding:(NSString *)b { return Nil; }
- (NSMutableDictionary *)_mwBindings { NSMutableDictionary *d = objc_getAssociatedObject(self, "mw_bindings"); if (!d) { d = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, "mw_bindings", d, OBJC_ASSOCIATION_RETAIN); } return d; }
- (void)bind:(NSString *)b toObject:(id)o withKeyPath:(NSString *)p options:(NSDictionary *)opts {
    if (!b || !o || !p) return;
    [self unbind:b];
    _MWBinding *bi = [[[_MWBinding alloc] init] autorelease];
    bi->target = self; bi->binding = [b copy]; bi->keyPath = [p copy]; bi->observed = [o retain]; bi->options = [opts copy];
    [self _mwBindings][b] = bi;
    [o addObserver:bi forKeyPath:p options:0 context:NULL];
    [bi _mwApply];
}
- (void)unbind:(NSString *)b { [[self _mwBindings] removeObjectForKey:b]; }
- (NSDictionary *)infoForBinding:(NSString *)b {
    _MWBinding *bi = [self _mwBindings][b];
    return bi ? @{NSObservedObjectKey: bi->observed, NSObservedKeyPathKey: bi->keyPath, NSOptionsKey: bi->options ?: @{}} : nil;
}
@end
@implementation NSWindow (MWTabbing)
- (void)setUserInterfaceItemIdentifier:(NSString *)i { objc_setAssociatedObject(self, "mw_uiid", i, OBJC_ASSOCIATION_COPY); } - (NSString *)userInterfaceItemIdentifier { return objc_getAssociatedObject(self, "mw_uiid"); }
@end

/* ======================================================================= odds and ends Itsycal (and many apps) import */
NSString *const NSLinkAttributeName = @"NSLink", *const NSBaselineOffsetAttributeName = @"NSBaselineOffset";
NSString *const NSFontFeatureSettingsAttribute = @"NSCTFontFeatureSettingsAttribute", *const NSFontFeatureTypeIdentifierKey = @"CTFeatureTypeIdentifier",
    *const NSFontFeatureSelectorIdentifierKey = @"CTFeatureSelectorIdentifier";
NSString *const NSMultipleValuesPlaceholderBindingOption = @"NSMultipleValuesPlaceholder", *const NSNoSelectionPlaceholderBindingOption = @"NSNoSelectionPlaceholder",
    *const NSNotApplicablePlaceholderBindingOption = @"NSNotApplicablePlaceholder";
/* accessibility: no screen reader bridge (ponytail: UI Automation) */
NSString *const NSAccessibilityAnnouncementKey = @"AXAnnouncementKey", *const NSAccessibilityPriorityKey = @"AXPriorityKey",
    *const NSAccessibilityAnnouncementRequestedNotification = @"AXAnnouncementRequested", *const NSAccessibilityButtonRole = @"AXButton";
void NSAccessibilityPostNotificationWithUserInfo(id element, NSString *n, NSDictionary *info) {}

/* NSDictionaryOfVariableBindings(a, b) -> @{@"a": a, @"b": b} */
NSDictionary *_NSDictionaryOfVariableBindings(NSString *names, id first, ...) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSArray *keys = [names componentsSeparatedByString:@","];
    va_list ap; va_start(ap, first);
    id v = first;
    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *k = [keys[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (i) v = va_arg(ap, id);
        if (v && k.length) d[k] = v;
    }
    va_end(ap);
    return d;
}

/* NSAffineTransform (Foundation, more.m) drawing into the current context */
typedef struct { CGFloat m11, m12, m21, m22, tX, tY; } MWAffine;
@interface NSAffineTransform : NSObject - (MWAffine)transformStruct; @end
static CGAffineTransform affine(NSAffineTransform *t) { MWAffine a = [t transformStruct]; return CGAffineTransformMake(a.m11, a.m12, a.m21, a.m22, a.tX, a.tY); }
@implementation NSAffineTransform (MWDrawing)
- (void)concat { CGContextRef c = mw_cg(); if (c) CGContextConcatCTM(c, affine(self)); }
- (void)set {
    CGContextRef c = mw_cg(); if (!c) return;
    CGContextConcatCTM(c, CGAffineTransformInvert(CGContextGetCTM(c)));
    CGContextConcatCTM(c, affine(self));
}
@end

/* NSSound (declared in AppKit.h): no audio output for these (ponytail: AudioToolbox's queue when an app's sounds matter) */
@implementation NSSound
+ (instancetype)soundNamed:(NSString *)n { NSSound *s = [[[self alloc] init] autorelease]; s.name = n; return s; }
- (instancetype)initWithContentsOfFile:(NSString *)p byReference:(BOOL)r { if ((self = [super init])) { _name = [[p lastPathComponent] copy]; _volume = 1; } return self; }
- (instancetype)initWithContentsOfURL:(NSURL *)u byReference:(BOOL)r { return [self initWithContentsOfFile:u.path byReference:r]; }
- (instancetype)initWithData:(NSData *)d { return [self initWithContentsOfFile:@"" byReference:NO]; }
- (void)dealloc { [_name release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (BOOL)play { return YES; } - (BOOL)stop { return YES; } - (BOOL)pause { return YES; } - (BOOL)resume { return YES; }
- (BOOL)isPlaying { return NO; } - (NSTimeInterval)duration { return 0; } - (NSTimeInterval)currentTime { return 0; } - (void)setCurrentTime:(NSTimeInterval)t {}
- (BOOL)setName:(NSString *)n { [_name release]; _name = [n copy]; return YES; }
@end

/* NSToolbar: kept as data; windows show no toolbar strip (ponytail: draw the items under the title bar) */
@interface NSToolbarItem : NSObject <NSCopying>
@property(readonly, copy) NSString *itemIdentifier; @property(copy) NSString *label, *paletteLabel, *toolTip;
@property(retain) NSImage *image; @property(retain) NSView *view; @property(assign) id target; @property SEL action;
@property NSInteger tag; @property(getter=isEnabled) BOOL enabled; @property(getter=isBordered) BOOL bordered;
@end
@implementation NSToolbarItem
- (instancetype)initWithItemIdentifier:(NSString *)i { if ((self = [super init])) { _itemIdentifier = [i copy]; _enabled = YES; } return self; }
- (void)dealloc { [_itemIdentifier release]; [_label release]; [_paletteLabel release]; [_toolTip release]; [_image release]; [_view release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (void)validate {}
@end
@interface NSToolbar : NSObject
@property(readonly, copy) NSString *identifier; @property(assign) id delegate; @property(getter=isVisible) BOOL visible;
@property BOOL allowsUserCustomization, autosavesConfiguration, showsBaselineSeparator; @property NSInteger displayMode, sizeMode;
@property(copy) NSString *selectedItemIdentifier;
@end
@implementation NSToolbar { NSMutableArray *_items; }
- (instancetype)initWithIdentifier:(NSString *)i { if ((self = [super init])) { _identifier = [i copy]; _visible = YES; _items = [[NSMutableArray alloc] init]; } return self; }
- (instancetype)init { return [self initWithIdentifier:@""]; }
- (void)dealloc { [_identifier release]; [_items release]; [_selectedItemIdentifier release]; [super dealloc]; }
- (void)setDelegate:(id)d {
    _delegate = d;
    [_items removeAllObjects];
    if ([d respondsToSelector:@selector(toolbarDefaultItemIdentifiers:)] && [d respondsToSelector:@selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:)])
        for (NSString *i in [d toolbarDefaultItemIdentifiers:self]) { id it = [d toolbar:self itemForItemIdentifier:i willBeInsertedIntoToolbar:YES]; if (it) [_items addObject:it]; }
}
- (NSArray *)items { return [[_items copy] autorelease]; }
- (NSArray *)visibleItems { return [self items]; }
- (void)insertItemWithItemIdentifier:(NSString *)i atIndex:(NSInteger)n {}
- (void)removeItemAtIndex:(NSInteger)n { if (n >= 0 && n < (NSInteger)_items.count) [_items removeObjectAtIndex:(NSUInteger)n]; }
- (void)validateVisibleItems {}
@end

/* NSDatePicker: shows the date as text (ponytail: no stepper or calendar to pick with) */
@interface NSDatePicker : NSControl
@property(copy) NSDate *dateValue, *minDate, *maxDate; @property NSTimeInterval timeInterval;
@property NSInteger datePickerStyle, datePickerMode, datePickerElements;
@property(copy) NSCalendar *calendar; @property(copy) NSLocale *locale; @property(copy) NSTimeZone *timeZone;
@property(retain) NSColor *textColor, *backgroundColor; @property BOOL drawsBackground, bezeled, bordered, presentsCalendarOverlay;
@property(assign) id delegate;
@end
@implementation NSDatePicker
- (void)dealloc { [_dateValue release]; [_minDate release]; [_maxDate release]; [_calendar release]; [_locale release]; [_timeZone release]; [_textColor release]; [_backgroundColor release]; [super dealloc]; }
- (id)objectValue { return _dateValue; }
- (void)setObjectValue:(id)v { if ([v isKindOfClass:[NSDate class]]) self.dateValue = v; }
- (void)setDateValue:(NSDate *)d { [_dateValue release]; _dateValue = [d copy]; self.needsDisplay = YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(120, 22); }
- (void)drawRect:(NSRect)r {
    if (!_dateValue) return;
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    BOOL date = (_datePickerElements & 0xe0) != 0 || !_datePickerElements, time = (_datePickerElements & 0x0c) != 0;
    f.dateStyle = date ? NSDateFormatterMediumStyle : NSDateFormatterNoStyle; f.timeStyle = time ? NSDateFormatterShortStyle : NSDateFormatterNoStyle;
    if (_locale) f.locale = _locale;
    if (_timeZone) f.timeZone = _timeZone;
    mw_draw_text_in([f stringFromDate:_dateValue], NSInsetRect(self.bounds, 4, 2), self.font ?: [NSFont systemFontOfSize:13], _textColor ?: [NSColor controlTextColor], NSTextAlignmentLeft, NSLineBreakByTruncatingTail, NO, YES);
}
@end

/* WebKit 2 (WKWebView): like WebView, an empty view */
@interface WKUserContentController : NSObject @end
@implementation WKUserContentController - (void)addUserScript:(id)s {} - (void)removeAllUserScripts {} - (void)addScriptMessageHandler:(id)h name:(NSString *)n {} - (void)removeScriptMessageHandlerForName:(NSString *)n {} @end
@interface WKUserScript : NSObject @end
@implementation WKUserScript - (instancetype)initWithSource:(NSString *)s injectionTime:(NSInteger)t forMainFrameOnly:(BOOL)m { return [super init]; } @end
@interface WebPreferences : NSObject @end
@implementation WebPreferences
+ (instancetype)standardPreferences { static WebPreferences *p; if (!p) p = [[self alloc] init]; return p; }
- (void)setJavaScriptEnabled:(BOOL)f {} - (void)setPlugInsEnabled:(BOOL)f {} - (void)setJavaEnabled:(BOOL)f {} - (void)setAutosaves:(BOOL)f {}
- (void)setStandardFontFamily:(NSString *)f {} - (void)setDefaultFontSize:(int)s {} - (void)setJavaScriptCanOpenWindowsAutomatically:(BOOL)f {}
@end
@interface WKWebViewConfiguration : NSObject <NSCopying> @property(retain) WKUserContentController *userContentController; @property(retain) id preferences; @end
@implementation WKWebViewConfiguration
- (instancetype)init { if ((self = [super init])) _userContentController = [[WKUserContentController alloc] init]; return self; }
- (void)dealloc { [_userContentController release]; [_preferences release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end
@interface WKWebView : NSView @property(assign) id navigationDelegate, UIDelegate; @property(readonly) WKWebViewConfiguration *configuration; @end
@implementation WKWebView
- (instancetype)initWithFrame:(NSRect)r configuration:(WKWebViewConfiguration *)c { if ((self = [super initWithFrame:r])) _configuration = [c retain]; return self; }
- (void)dealloc { [_configuration release]; [super dealloc]; }
- (id)loadHTMLString:(NSString *)s baseURL:(NSURL *)u { return nil; }
- (id)loadRequest:(id)r { return nil; }
- (id)loadFileURL:(NSURL *)u allowingReadAccessToURL:(NSURL *)a { return nil; }
- (void)evaluateJavaScript:(NSString *)s completionHandler:(void (^)(id, NSError *))h { if (h) h(nil, [NSError errorWithDomain:@"WKErrorDomain" code:4 userInfo:nil]); }
- (void)setValue:(id)v forKey:(NSString *)k { if (![k isEqualToString:@"drawsBackground"]) [super setValue:v forKey:k]; }
- (BOOL)isLoading { return NO; } - (NSURL *)URL { return nil; } - (NSString *)title { return nil; }
- (void)drawRect:(NSRect)r { mw_draw_text_in(@"Web content is not available in scion.", self.bounds, [NSFont systemFontOfSize:12], [NSColor secondaryLabelColor], NSTextAlignmentCenter, NSLineBreakByWordWrapping, YES, YES); }
@end

/* NSUserInterfaceItemIdentification on view controllers */
@implementation NSViewController (MWIdentifier)
- (NSString *)identifier { return objc_getAssociatedObject(self, @selector(identifier)); }
- (void)setIdentifier:(NSString *)i { objc_setAssociatedObject(self, @selector(identifier), i, OBJC_ASSOCIATION_COPY_NONATOMIC); }
@end
@implementation NSLayoutConstraint (MWAnimator) - (instancetype)animator { return self; } @end
/* -[NSImage setName:]: registers the image for +imageNamed: (ponytail: kept here, +imageNamed: does not consult it yet) */
@implementation NSImage (MWName)
- (BOOL)setName:(NSString *)n { objc_setAssociatedObject(self, @selector(name), n, OBJC_ASSOCIATION_COPY_NONATOMIC); return YES; }
- (NSString *)name { return objc_getAssociatedObject(self, @selector(name)); }
@end
