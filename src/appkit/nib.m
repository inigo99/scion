/* nib.m — compiled nibs (Xcode's NIBArchive files, decoded by Foundation's NSKeyedUnarchiver): NSNib, the NSBundle loading
 * methods and NSApplicationMain's main nib, and the -initWithCoder: side of the AppKit classes nibs contain. The nib is a
 * graph rooted in NSIBObjectData: placeholders (File's Owner, First Responder, the application), the objects, the outlet,
 * action and binding connections, and the windows to show. Keys and flag bits follow the public behavior of Interface
 * Builder files (and GNUstep's reading of them). */
#import "internal.h"
#import <objc/message.h>

@interface NSKeyedUnarchiver (MWNib) - (void)_mwSetNibOwner:(id)owner; @end
@interface NSView (MWNib) - (void)_mwDecodeNib:(NSCoder *)c; @end

@implementation NSObject (NSNibAwaking) - (void)awakeFromNib {} - (void)prepareForInterfaceBuilder {} @end

/* ======================================================================= placeholders and nib-only classes */
@interface _MWFirstResponder : NSObject @end   /* First Responder: actions sent to it go up the responder chain */
@implementation _MWFirstResponder
+ (id)shared { static _MWFirstResponder *f; if (!f) f = [[self alloc] init]; return f; }
@end
static id real(id o) { return [o isKindOfClass:[_MWFirstResponder class]] ? nil : o; }

@interface NSCustomObject : NSObject @end
@implementation NSCustomObject
- (instancetype)initWithCoder:(NSCoder *)c {
    NSString *name = [c decodeObjectForKey:@"NSClassName"];
    [self release];
    if ([name isEqualToString:@"FirstResponder"]) return [[_MWFirstResponder shared] retain];
    Class cls = name ? NSClassFromString(name) : Nil;
    if ([name isEqualToString:@"NSApplication"] || (cls && [cls isSubclassOfClass:[NSApplication class]])) return (id)[[(cls ? cls : [NSApplication class]) sharedApplication] retain];
    if (!cls) { NSLog(@"Unknown class %@ in Interface Builder file, creating generic object instead.", name); cls = [NSObject class]; }
    if ([cls respondsToSelector:@selector(sharedFontManager)] && [name isEqualToString:@"NSFontManager"]) return [[cls performSelector:@selector(sharedFontManager)] retain];
    return [[cls alloc] init];
}
@end
/* a view of a custom class: made with initWithFrame: like Interface Builder does */
@interface NSCustomView : NSView @end
@implementation NSCustomView
- (instancetype)initWithCoder:(NSCoder *)c {
    NSString *name = [c decodeObjectForKey:@"NSClassName"];
    Class cls = name ? NSClassFromString(name) : Nil;
    if (!cls || ![cls isSubclassOfClass:[NSView class]]) { if (name) NSLog(@"Unknown view class %@ in Interface Builder file.", name); cls = [NSView class]; }
    [self release];
    NSView *v = [[cls alloc] initWithFrame:[c containsValueForKey:@"NSFrame"] ? [c decodeRectForKey:@"NSFrame"] : (NSRect){NSZeroPoint, [c decodeSizeForKey:@"NSFrameSize"]}];
    [v _mwDecodeNib:c];
    return (id)v;
}
@end
/* "Custom Class" set on a standard object: decoded as the original class's data, made as the custom class */
@interface NSClassSwapper : NSObject @end
@implementation NSClassSwapper
- (instancetype)initWithCoder:(NSCoder *)c {
    NSString *name = [c decodeObjectForKey:@"NSClassName"], *orig = [c decodeObjectForKey:@"NSOriginalClassName"];
    Class cls = name ? NSClassFromString(name) : Nil;
    if (!cls) { if (name) NSLog(@"Unknown class %@ in Interface Builder file.", name); cls = orig ? NSClassFromString(orig) : [NSObject class]; }
    [self release];
    id o = [cls alloc];
    return [o respondsToSelector:@selector(initWithCoder:)] ? [o initWithCoder:c] : [o init];
}
@end
@interface IBClassReference : NSObject @end
@implementation IBClassReference - (instancetype)initWithCoder:(NSCoder *)c { return [self init]; } @end
@interface NSNibConnector : NSObject { @public id _src, _dst; NSString *_label; } - (void)establishConnection; @end
@implementation NSNibConnector
- (instancetype)initWithCoder:(NSCoder *)c {
    _src = [[c decodeObjectForKey:@"NSSource"] retain]; _dst = [[c decodeObjectForKey:@"NSDestination"] retain]; _label = [[c decodeObjectForKey:@"NSLabel"] copy];
    return self;
}
- (void)dealloc { [_src release]; [_dst release]; [_label release]; [super dealloc]; }
- (void)establishConnection {}
@end
@interface NSNibOutletConnector : NSNibConnector @end
@implementation NSNibOutletConnector
- (void)establishConnection {
    id src = real(_src), dst = real(_dst);
    if (!src || !_label) return;
    @try { [src setValue:dst forKey:_label]; }
    @catch (NSException *e) { NSLog(@"Failed to connect (%@) outlet from (%@) to (%@): missing setter or instance variable", _label, src, dst); }
}
@end
@interface NSNibControlConnector : NSNibConnector @end
@implementation NSNibControlConnector
- (void)establishConnection {
    id src = real(_src);
    if (!src || !_label) return;
    SEL a = NSSelectorFromString(_label);
    if ([src respondsToSelector:@selector(setAction:)]) ((void (*)(id, SEL, SEL))objc_msgSend)(src, @selector(setAction:), a);
    if ([src respondsToSelector:@selector(setTarget:)]) [src setTarget:real(_dst)];
}
@end
@interface NSNibBindingConnector : NSNibConnector { NSString *_binding, *_keyPath; NSDictionary *_options; } @end
@implementation NSNibBindingConnector
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super initWithCoder:c];
    _binding = [[c decodeObjectForKey:@"NSBinding"] copy]; _keyPath = [[c decodeObjectForKey:@"NSKeyPath"] copy]; _options = [[c decodeObjectForKey:@"NSOptions"] copy];
    return self;
}
- (void)dealloc { [_binding release]; [_keyPath release]; [_options release]; [super dealloc]; }
- (void)establishConnection {   /* a live binding (misc.m: KVO from the model to the view) */
    id src = real(_src), dst = real(_dst);
    if (!src || !dst || !_binding || !_keyPath) return;
    @try { [src bind:_binding toObject:dst withKeyPath:_keyPath options:_options]; } @catch (NSException *e) {}
}
@end
@interface NSIBHelpConnector : NSNibConnector @end
@implementation NSIBHelpConnector @end
@interface NSIBObjectData : NSObject { @public id _root; NSArray *_connections, *_objectsKeys, *_objectsValues; NSSet *_visible; } @end
@implementation NSIBObjectData
- (instancetype)initWithCoder:(NSCoder *)c {
    _root = [[c decodeObjectForKey:@"NSRoot"] retain];
    _objectsKeys = [[c decodeObjectForKey:@"NSObjectsKeys"] retain]; _objectsValues = [[c decodeObjectForKey:@"NSObjectsValues"] retain];
    _connections = [[c decodeObjectForKey:@"NSConnections"] retain];
    _visible = [[c decodeObjectForKey:@"NSVisibleWindows"] retain];
    return self;
}
- (void)dealloc { [_root release]; [_objectsKeys release]; [_objectsValues release]; [_connections release]; [_visible release]; [super dealloc]; }
@end
/* images and sounds named in the nib */
@interface NSCustomResource : NSObject @end
@implementation NSCustomResource
- (instancetype)initWithCoder:(NSCoder *)c {
    NSString *cls = [c decodeObjectForKey:@"NSClassName"], *name = [c decodeObjectForKey:@"NSResourceName"];
    [self release];
    if ([cls isEqualToString:@"NSImage"] && name) { NSImage *i = [NSImage imageNamed:name]; if (!i) i = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]; return (id)[i retain]; }
    return nil;
}
@end
@interface NSButtonImageSource : NSObject { @public NSString *_name; } @end
@implementation NSButtonImageSource
- (instancetype)initWithCoder:(NSCoder *)c { _name = [[c decodeObjectForKey:@"NSImageName"] copy]; return self; }
- (void)dealloc { [_name release]; [super dealloc]; }
@end

/* ======================================================================= values, fonts and colors */
@implementation NSValue (MWNib)
- (instancetype)initWithCoder:(NSCoder *)c {
    [self release];
    if ([c containsValueForKey:@"NS.sizeval"]) return [[NSValue valueWithSize:[c decodeSizeForKey:@"NS.sizeval"]] retain];
    if ([c containsValueForKey:@"NS.rectval"]) return [[NSValue valueWithRect:[c decodeRectForKey:@"NS.rectval"]] retain];
    if ([c containsValueForKey:@"NS.pointval"]) return [[NSValue valueWithPoint:[c decodePointForKey:@"NS.pointval"]] retain];
    if ([c containsValueForKey:@"NS.rangeval.location"]) return [[NSValue valueWithRange:NSMakeRange((NSUInteger)[c decodeIntegerForKey:@"NS.rangeval.location"], (NSUInteger)[c decodeIntegerForKey:@"NS.rangeval.length"])] retain];
    return [[NSValue valueWithSize:NSZeroSize] retain];
}
@end
@implementation NSFont (MWNib)
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:self.fontName forKey:@"NSName"]; [c encodeDouble:self.pointSize forKey:@"NSSize"]; }
- (instancetype)initWithCoder:(NSCoder *)c {
    NSString *name = [c decodeObjectForKey:@"NSName"]; double size = [c decodeDoubleForKey:@"NSSize"];
    [self release];
    NSFont *f = nil;
    if ([name hasPrefix:@".AppleSystemUIFont"] || [name hasPrefix:@".SF"]) f = [name rangeOfString:@"Bold"].location != NSNotFound ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    if (!f && name) f = [NSFont fontWithName:name size:size];
    if (!f) f = [NSFont systemFontOfSize:size > 0 ? size : [NSFont systemFontSize]];
    return [f retain];
}
@end
@implementation NSFontDescriptor (MWNib) - (instancetype)initWithCoder:(NSCoder *)c { [self release]; return [[[NSFont systemFontOfSize:0] fontDescriptor] retain]; } @end
@implementation NSColorSpace (MWNib) - (instancetype)initWithCoder:(NSCoder *)c { [self release]; return [[NSColorSpace sRGBColorSpace] retain]; } @end
@implementation NSColor (MWNib)
- (void)encodeWithCoder:(NSCoder *)c {   /* as AppKit archives sRGB colors (NSColorSpace 2, "r g b a") */
    NSColor *k = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: self;
    const char *s = [[NSString stringWithFormat:@"%g %g %g %g", k.redComponent, k.greenComponent, k.blueComponent, k.alphaComponent] UTF8String];
    [c encodeInt:2 forKey:@"NSColorSpace"];
    [c encodeBytes:(const uint8_t *)s length:strlen(s) + 1 forKey:@"NSRGB"];
}
static NSColor *named_color(NSString *name) { /* catalog colors: the NSColor class method of that name */
    if (!name) return nil;
    SEL s = NSSelectorFromString(name);
    if ([NSColor respondsToSelector:s]) { id c = [NSColor performSelector:s]; if ([c isKindOfClass:[NSColor class]]) return c; }
    return nil;
}
- (instancetype)initWithCoder:(NSCoder *)c {
    int space = [c decodeIntForKey:@"NSColorSpace"];
    [self release];
    NSColor *col = nil; NSUInteger n; const uint8_t *b;
    if (space == 6) { col = named_color([c decodeObjectForKey:@"NSColorName"]); if (!col) col = [c decodeObjectForKey:@"NSColor"]; }
    else if (space == 1 || space == 2) {
        double v[4] = {0, 0, 0, 1};
        if ((b = [c decodeBytesForKey:@"NSRGB" returnedLength:&n])) { NSString *s = [[[NSString alloc] initWithBytes:b length:n encoding:NSASCIIStringEncoding] autorelease]; NSArray *p = [s componentsSeparatedByString:@" "]; for (NSUInteger i = 0; i < 4 && i < [p count]; i++) v[i] = [p[i] doubleValue]; }
        col = [NSColor colorWithSRGBRed:v[0] green:v[1] blue:v[2] alpha:v[3]];
    } else if (space == 3 || space == 4) {
        double v[2] = {0, 1};
        if ((b = [c decodeBytesForKey:@"NSWhite" returnedLength:&n])) { NSString *s = [[[NSString alloc] initWithBytes:b length:n encoding:NSASCIIStringEncoding] autorelease]; NSArray *p = [s componentsSeparatedByString:@" "]; for (NSUInteger i = 0; i < 2 && i < [p count]; i++) v[i] = [p[i] doubleValue]; }
        col = [NSColor colorWithWhite:v[0] alpha:v[1]];
    } else if (space == 10) col = named_color([c decodeObjectForKey:@"NSColorName"]); /* asset catalog colors */
    if (!col) col = [NSColor blackColor];
    return [col retain];
}
@end

/* ======================================================================= menus */
@implementation NSMenu (MWNib)
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [self initWithTitle:[c decodeObjectForKey:@"NSTitle"] ?: @""];
    for (NSMenuItem *i in [c decodeObjectForKey:@"NSMenuItems"]) if ([i isKindOfClass:[NSMenuItem class]]) [self addItem:i];
    NSString *name = [c decodeObjectForKey:@"NSName"];
    if ([name isEqualToString:@"_NSMainMenu"]) [NSApp setMainMenu:self];
    else if ([name isEqualToString:@"_NSWindowsMenu"]) [NSApp setWindowsMenu:self];
    else if ([name isEqualToString:@"_NSServicesMenu"]) [NSApp setServicesMenu:self];
    else if ([name isEqualToString:@"_NSHelpMenu"]) [NSApp setHelpMenu:self];
    return self;
}
@end
@implementation NSMenuItem (MWNib)
- (instancetype)initWithCoder:(NSCoder *)c {
    if ([c decodeBoolForKey:@"NSIsSeparator"]) { [self release]; return [[NSMenuItem separatorItem] retain]; }
    NSString *act = [c decodeObjectForKey:@"NSAction"];
    self = [self initWithTitle:[c decodeObjectForKey:@"NSTitle"] ?: @"" action:act ? NSSelectorFromString(act) : NULL keyEquivalent:[c decodeObjectForKey:@"NSKeyEquiv"] ?: @""];
    self.keyEquivalentModifierMask = (NSEventModifierFlags)[c decodeIntegerForKey:@"NSKeyEquivModMask"];
    self.target = real([c decodeObjectForKey:@"NSTarget"]);
    self.tag = [c decodeIntegerForKey:@"NSTag"];
    self.state = [c decodeIntegerForKey:@"NSState"];
    if ([c decodeBoolForKey:@"NSIsDisabled"]) self.enabled = NO;
    if ([c decodeBoolForKey:@"NSIsHidden"]) self.hidden = YES;
    NSMenu *sub = [c decodeObjectForKey:@"NSSubmenu"];
    if ([sub isKindOfClass:[NSMenu class]]) self.submenu = sub;
    NSImage *img = [c decodeObjectForKey:@"NSImage"]; if ([img isKindOfClass:[NSImage class]]) self.image = img;
    return self;
}
@end

/* ======================================================================= cells: what the controls copy from them */
@interface NSActionCell () { @public NSMutableDictionary *_nib; } @end
@implementation NSActionCell
- (void)dealloc { [_nib release]; [super dealloc]; }
- (id)_mwNib:(NSString *)k { return _nib[k]; }
@end
@implementation NSButtonCell
- (void)dealloc { [_alternateTitle release]; [_alternateImage release]; [_backgroundColor release]; [_attributedTitle release]; [_attributedAlternateTitle release]; [_sound release]; [super dealloc]; }
- (void)setButtonType:(NSButtonType)t { }
- (void)drawBezelWithFrame:(NSRect)f inView:(NSView *)v {
    if (self.isTransparent || !self.isBordered) return;
    mw_fill_round(NSInsetRect(f, 1, 1), 5, self.isHighlighted ? [NSColor colorWithWhite:0.5 alpha:0.45] : [NSColor colorWithWhite:0.5 alpha:0.25]);
}
- (void)drawImage:(NSImage *)i withFrame:(NSRect)f inView:(NSView *)v { mw_draw_image(i, f, nil, self.isEnabled ? 1 : 0.5); }
- (NSRect)drawTitle:(NSAttributedString *)t withFrame:(NSRect)f inView:(NSView *)v {
    mw_draw_text_in(t.string, f, self.font ?: [NSFont systemFontOfSize:13], self.isEnabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor], NSTextAlignmentCenter, NSLineBreakByTruncatingTail, NO, YES);
    return f;
}
- (void)drawWithFrame:(NSRect)f inView:(NSView *)v { [self drawBezelWithFrame:f inView:v]; [self drawInteriorWithFrame:f inView:v]; }
- (void)drawInteriorWithFrame:(NSRect)f inView:(NSView *)v {
    if (self.image) { NSSize is = self.image.size; [self drawImage:self.image withFrame:NSMakeRect(NSMidX(f) - is.width / 2, NSMidY(f) - is.height / 2, is.width, is.height) inView:v]; }
    else if ([self.title length]) [self drawTitle:self.attributedTitle ?: [[[NSAttributedString alloc] initWithString:self.title] autorelease] withFrame:f inView:v];
}
- (void)mouseEntered:(NSEvent *)e {} - (void)mouseExited:(NSEvent *)e {}
@end
@implementation NSTextFieldCell
- (void)dealloc { [_textColor release]; [_backgroundColor release]; [_placeholderString release]; [_placeholderAttributedString release]; [_allowedInputSourceLocales release]; [super dealloc]; }
- (void)setWantsNotificationForMarkedText:(BOOL)f {}
- (void)drawWithFrame:(NSRect)f inView:(NSView *)v {
    if (self.drawsBackground && self.backgroundColor) { [self.backgroundColor set]; NSRectFill(f); }
    [self drawInteriorWithFrame:f inView:v];
}
@end
@implementation NSPopUpButtonCell
- (instancetype)initTextCell:(NSString *)s pullsDown:(BOOL)p { if ((self = [self initTextCell:s])) self.pullsDown = p; return self; }
@end
@implementation NSSearchFieldCell @end
@implementation NSSecureTextFieldCell @end
@implementation NSTableHeaderCell @end
@implementation NSSegmentedCell @end
@implementation NSImageCell @end
@implementation NSSliderCell @end
@implementation NSComboBoxCell @end
@interface NSLevelIndicatorCell : NSActionCell @end @implementation NSLevelIndicatorCell @end
@interface NSStepperCell : NSActionCell @end @implementation NSStepperCell @end
@interface NSDatePickerCell : NSActionCell @end @implementation NSDatePickerCell @end
@interface NSPathCell : NSActionCell @end @implementation NSPathCell @end
@interface NSTokenFieldCell : NSTextFieldCell @end @implementation NSTokenFieldCell @end
@interface NSFormCell : NSActionCell @end @implementation NSFormCell @end
@implementation NSCell (MWNib)
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [self init];
    if (![self isKindOfClass:[NSActionCell class]]) return self;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"NSContents", @"NSSupport", @"NSTarget", @"NSTextColor", @"NSBackgroundColor", @"NSPlaceholderString", @"NSKeyEquivalent",
                          @"NSAlternateContents", @"NSNormalImage", @"NSAlternateImage", @"NSMenu", @"NSMenuItem", @"NSSegmentImages", @"NSFormatter"]) {
        id v = [c decodeObjectForKey:k]; if (v) d[k] = v;
    }
    NSString *act = [c decodeObjectForKey:@"NSAction"]; if (act) d[@"NSAction"] = act;
    for (NSString *k in @[@"NSCellFlags", @"NSCellFlags2", @"NSButtonFlags", @"NSButtonFlags2", @"NSBezelStyle", @"NSSelectedIndex", @"NSControlSize2", @"NSPreferredEdge", @"NSArrowPosition"])
        if ([c containsValueForKey:k]) d[k] = [NSNumber numberWithLongLong:[c decodeInt64ForKey:k]];
    for (NSString *k in @[@"NSDrawsBackground", @"NSPullDown", @"NSAltersState", @"NSUsesItemFromMenu"])
        if ([c containsValueForKey:k]) d[k] = [NSNumber numberWithBool:[c decodeBoolForKey:k]];
    ((NSActionCell *)self)->_nib = [d retain];
    id contents = d[@"NSContents"];
    if ([contents isKindOfClass:[NSString class]]) self.stringValue = contents;
    if ([d[@"NSSupport"] isKindOfClass:[NSFont class]]) self.font = d[@"NSSupport"];
    if ([self isKindOfClass:[NSTextFieldCell class]] && [d[@"NSTextColor"] isKindOfClass:[NSColor class]]) ((NSTextFieldCell *)self).textColor = d[@"NSTextColor"];
    uint32_t cf = [d[@"NSCellFlags"] unsignedIntValue];
    if (cf & 0x20000000u) self.enabled = NO;
    if ([c containsValueForKey:@"NSAlignment"] || d[@"NSCellFlags2"]) self.alignment = (NSTextAlignment)(([d[@"NSCellFlags2"] unsignedIntValue] >> 26) & 7);
    return self;
}
@end
static NSDictionary *cell_attrs(NSCell *c) { return [c isKindOfClass:[NSActionCell class]] ? ((NSActionCell *)c)->_nib : nil; }
static NSImage *image_of(id v) {
    if ([v isKindOfClass:[NSImage class]]) return v;
    if ([v isKindOfClass:[NSButtonImageSource class]]) return [NSImage imageNamed:((NSButtonImageSource *)v)->_name];
    return nil;
}

/* ======================================================================= views */
NSView *mw_nib_init_view(NSView *self, NSCoder *c) {
    NSRect f = [c containsValueForKey:@"NSFrame"] ? [c decodeRectForKey:@"NSFrame"] : (NSRect){NSZeroPoint, [c decodeSizeForKey:@"NSFrameSize"]};
    self = [self initWithFrame:f];
    [self _mwDecodeNib:c];
    return self;
}
@implementation NSView (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    uint32_t vf = (uint32_t)[c decodeInt64ForKey:@"NSvFlags"];
    self.autoresizingMask = vf & 0x3f;
    if (vf & 0x80000000u) self.hidden = YES;
    if ([c decodeBoolForKey:@"NSDoNotTranslateAutoresizingMask"]) self.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *ident = [c decodeObjectForKey:@"NSReuseIdentifierKey"]; if (ident) self.identifier = ident;
    for (NSView *v in [c decodeObjectForKey:@"NSSubviews"]) if ([v isKindOfClass:[NSView class]] && v.superview != self) [self addSubview:v];
    NSArray *cons = [c decodeObjectForKey:@"NSViewConstraints"];
    for (id k in cons) if ([k isKindOfClass:[NSLayoutConstraint class]]) [self addConstraint:k];
    NSString *hug = [c decodeObjectForKey:@"NSHuggingPriority"];
    if ([hug isKindOfClass:[NSString class]]) { NSPoint p = NSPointFromString(hug); [self setContentHuggingPriority:p.x forOrientation:NSLayoutConstraintOrientationHorizontal]; [self setContentHuggingPriority:p.y forOrientation:NSLayoutConstraintOrientationVertical]; }
    NSString *anti = [c decodeObjectForKey:@"NSAntiCompressionPriority"];
    if ([anti isKindOfClass:[NSString class]]) { NSPoint p = NSPointFromString(anti); [self setContentCompressionResistancePriority:p.x forOrientation:NSLayoutConstraintOrientationHorizontal]; [self setContentCompressionResistancePriority:p.y forOrientation:NSLayoutConstraintOrientationVertical]; }
}
@end
@implementation NSControl (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    NSCell *cell = [c decodeObjectForKey:@"NSCell"]; NSDictionary *a = cell_attrs(cell);
    if ([cell isKindOfClass:[NSCell class]]) { self.cell = cell; cell.controlView = self; }
    if ([c containsValueForKey:@"NSControlTextAlignment"]) self.alignment = (NSTextAlignment)[c decodeIntegerForKey:@"NSControlTextAlignment"];
    if ([c containsValueForKey:@"NSControlLineBreakMode"]) self.lineBreakMode = (NSLineBreakMode)[c decodeIntegerForKey:@"NSControlLineBreakMode"];
    if ([c containsValueForKey:@"NSControlSize"]) self.controlSize = (NSControlSize)[c decodeIntegerForKey:@"NSControlSize"];
    if (!a) return;
    if ([a[@"NSSupport"] isKindOfClass:[NSFont class]]) self.font = a[@"NSSupport"];
    if (a[@"NSAction"]) self.action = NSSelectorFromString(a[@"NSAction"]);
    if (a[@"NSTarget"]) self.target = real(a[@"NSTarget"]);
    if ([a[@"NSContents"] isKindOfClass:[NSString class]] && ![self isKindOfClass:[NSButton class]]) self.stringValue = a[@"NSContents"];
    if (a[@"NSFormatter"] && [self respondsToSelector:@selector(setFormatter:)]) [(id)self setFormatter:a[@"NSFormatter"]];
    uint32_t cf = [a[@"NSCellFlags"] unsignedIntValue];
    if (cf & 0x20000000u) self.enabled = NO;   /* the "NSEnabled" key of the control is not it: the cell's flags say it */
}
@end
@implementation NSButton (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    NSDictionary *a = cell_attrs([c decodeObjectForKey:@"NSCell"]); if (!a) return;
    id contents = a[@"NSContents"];
    if ([contents isKindOfClass:[NSString class]]) self.title = contents;
    else if ([contents isKindOfClass:[NSImage class]]) { self.title = @""; self.image = contents; }
    if ([a[@"NSAlternateContents"] isKindOfClass:[NSString class]]) self.alternateTitle = a[@"NSAlternateContents"];
    NSImage *img = image_of(a[@"NSNormalImage"]);
    NSString *src = [a[@"NSNormalImage"] isKindOfClass:[NSButtonImageSource class]] ? ((NSButtonImageSource *)a[@"NSNormalImage"])->_name : nil;
    if ([src isEqualToString:@"NSSwitch"]) [self setButtonType:NSButtonTypeSwitch];
    else if ([src isEqualToString:@"NSRadioButton"]) [self setButtonType:NSButtonTypeRadio];
    else if (img && ![self isKindOfClass:[NSPopUpButton class]]) self.image = img;
    if (a[@"NSBezelStyle"]) self.bezelStyle = (NSBezelStyle)[a[@"NSBezelStyle"] integerValue];
    if ([a[@"NSKeyEquivalent"] isKindOfClass:[NSString class]]) self.keyEquivalent = a[@"NSKeyEquivalent"];
    uint32_t cf = [a[@"NSCellFlags"] unsignedIntValue], bf = [a[@"NSButtonFlags"] unsignedIntValue];
    if (cf & 0x80000000u) self.state = NSControlStateValueOn;
    if (!(bf & 0x00800000u) && !a[@"NSBezelStyle"]) self.bordered = NO;
}
@end
@implementation NSPopUpButton (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    NSDictionary *a = cell_attrs([c decodeObjectForKey:@"NSCell"]); if (!a) return;
    if ([a[@"NSPullDown"] boolValue]) self.pullsDown = YES;
    if ([a[@"NSMenu"] isKindOfClass:[NSMenu class]]) self.menu = a[@"NSMenu"];
    if (a[@"NSSelectedIndex"] && !self.pullsDown) [self selectItemAtIndex:[a[@"NSSelectedIndex"] integerValue]];
}
@end
@implementation NSTextField (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    NSDictionary *a = cell_attrs([c decodeObjectForKey:@"NSCell"]); if (!a) return;
    uint32_t cf = [a[@"NSCellFlags"] unsignedIntValue];
    self.editable = (cf & 0x10000000u) != 0;
    self.selectable = (cf & 0x00200000u) != 0 || self.editable;
    self.bezeled = (cf & 0x00400000u) != 0;
    self.bordered = (cf & 0x00800000u) != 0;
    self.drawsBackground = [a[@"NSDrawsBackground"] boolValue];
    if (!(cf & 0x40) && !self.bezeled && !self.bordered) [(id)self _mwSetWraps:YES];   /* bit 0x40 set = "does not wrap" */
    if ([a[@"NSTextColor"] isKindOfClass:[NSColor class]]) self.textColor = a[@"NSTextColor"];
    if ([a[@"NSBackgroundColor"] isKindOfClass:[NSColor class]]) self.backgroundColor = a[@"NSBackgroundColor"];
    if ([a[@"NSPlaceholderString"] isKindOfClass:[NSString class]]) self.placeholderString = a[@"NSPlaceholderString"];
    if ([c containsValueForKey:@"NSPreferredMaxLayoutWidth"]) self.preferredMaxLayoutWidth = [c decodeDoubleForKey:@"NSPreferredMaxLayoutWidth"];
}
@end
@implementation NSClipView (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    NSView *doc = [c decodeObjectForKey:@"NSDocView"];
    if ([doc isKindOfClass:[NSView class]]) self.documentView = doc;
    if ([[c decodeObjectForKey:@"NSBGColor"] isKindOfClass:[NSColor class]]) self.backgroundColor = [c decodeObjectForKey:@"NSBGColor"];
}
@end
@implementation NSScrollView (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    NSClipView *clip = [c decodeObjectForKey:@"NSContentView"];
    [super _mwDecodeNib:c];   /* subviews include the clip view and the scrollers */
    for (NSView *v in [[self.subviews copy] autorelease]) [v removeFromSuperview];
    uint32_t sf = (uint32_t)[c decodeInt64ForKey:@"NSsFlags"];
    self.hasVerticalScroller = (sf & 0x10) != 0;
    self.hasHorizontalScroller = (sf & 0x20) != 0;
    self.autohidesScrollers = (sf & 0x200) != 0;
    self.borderType = (NSBorderType)(sf & 3);
    if ([clip isKindOfClass:[NSClipView class]] && clip.documentView) { NSView *doc = [[clip.documentView retain] autorelease]; [doc removeFromSuperview]; self.documentView = doc; }
}
@end
@implementation NSStackView (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    self.orientation = (NSUserInterfaceLayoutOrientation)[c decodeIntegerForKey:@"NSStackViewOrientation"];
    if ([c containsValueForKey:@"NSStackViewAlignment"]) self.alignment = (NSLayoutAttribute)[c decodeIntegerForKey:@"NSStackViewAlignment"];
    if ([c containsValueForKey:@"NSStackViewSpacing"]) self.spacing = [c decodeDoubleForKey:@"NSStackViewSpacing"];
    self.edgeInsets = NSEdgeInsetsMake([c decodeDoubleForKey:@"NSStackViewEdgeInsets.top"], [c decodeDoubleForKey:@"NSStackViewEdgeInsets.left"],
                                       [c decodeDoubleForKey:@"NSStackViewEdgeInsets.bottom"], [c decodeDoubleForKey:@"NSStackViewEdgeInsets.right"]);
    if ([c containsValueForKey:@"NSStackViewdistribution"]) self.distribution = (NSStackViewDistribution)[c decodeIntegerForKey:@"NSStackViewdistribution"];
    /* the views live in NSStackViewContainer objects (one per gravity) */
    for (NSString *k in @[@"NSStackViewBeginningContainer", @"NSStackViewMiddleContainer", @"NSStackViewEndContainer"]) {
        id cont = [c decodeObjectForKey:k];
        if ([cont respondsToSelector:@selector(_mwViews)]) for (NSView *v in [cont performSelector:@selector(_mwViews)]) [self addArrangedSubview:v];
    }
}
@end
@interface NSStackViewContainer : NSObject { NSArray *_views; } - (NSArray *)_mwViews; @end
@implementation NSStackViewContainer
- (instancetype)initWithCoder:(NSCoder *)c { _views = [[c decodeObjectForKey:@"NSStackViewContainerNonDroppedViews"] ?: [c decodeObjectForKey:@"NSStackViewContainerViews"] retain]; return self; }
- (void)dealloc { [_views release]; [super dealloc]; }
- (NSArray *)_mwViews { return _views ?: @[]; }
@end
@implementation NSSplitView (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    self.vertical = [c decodeBoolForKey:@"NSIsVertical"] || ((uint32_t)[c decodeInt64ForKey:@"NSvFlags"] & 0x1000);
}
@end
@implementation NSBox (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    NSString *t = [[c decodeObjectForKey:@"NSTitleCell"] stringValue]; if (t) self.title = t;
    NSView *content = [c decodeObjectForKey:@"NSContentView"]; if ([content isKindOfClass:[NSView class]] && content != self) self.contentView = content;
}
@end
@implementation NSImageView (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    NSDictionary *a = cell_attrs([c decodeObjectForKey:@"NSCell"]);
    NSImage *i = image_of(a[@"NSContents"]); if (i) self.image = i;
}
@end
@implementation NSProgressIndicator (MWNib)
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    if ([c containsValueForKey:@"NSMaxValue"]) self.maxValue = [c decodeDoubleForKey:@"NSMaxValue"];
    if ([c containsValueForKey:@"NSMinValue"]) self.minValue = [c decodeDoubleForKey:@"NSMinValue"];
    uint32_t pf = (uint32_t)[c decodeInt64ForKey:@"NSpiFlags"];
    self.indeterminate = (pf & 2) != 0;
    if (pf & 0x1000) self.style = NSProgressIndicatorStyleSpinning;
}
@end
@implementation NSLayoutConstraint (MWNib)
- (instancetype)initWithCoder:(NSCoder *)c {
    id first = [c decodeObjectForKey:@"NSFirstItem"], second = [c decodeObjectForKey:@"NSSecondItem"];
    NSLayoutAttribute fa = (NSLayoutAttribute)([c containsValueForKey:@"NSFirstAttributeV2"] ? [c decodeIntegerForKey:@"NSFirstAttributeV2"] : [c decodeIntegerForKey:@"NSFirstAttribute"]);
    NSLayoutAttribute sa = (NSLayoutAttribute)([c containsValueForKey:@"NSSecondAttributeV2"] ? [c decodeIntegerForKey:@"NSSecondAttributeV2"] : [c decodeIntegerForKey:@"NSSecondAttribute"]);
    double mult = [c containsValueForKey:@"NSMultiplier"] ? [c decodeDoubleForKey:@"NSMultiplier"] : 1;
    double k = [c containsValueForKey:@"NSConstantV2"] ? [c decodeDoubleForKey:@"NSConstantV2"] : [c decodeDoubleForKey:@"NSConstant"];
    [self release];
    if (!first) return nil;
    NSLayoutConstraint *lc = [NSLayoutConstraint constraintWithItem:first attribute:fa relatedBy:(NSLayoutRelation)[c decodeIntegerForKey:@"NSRelation"]
                                                             toItem:second attribute:second ? sa : NSLayoutAttributeNotAnAttribute multiplier:mult constant:k];
    if ([c containsValueForKey:@"NSPriority"]) lc.priority = (NSLayoutPriority)[c decodeDoubleForKey:@"NSPriority"];
    NSString *ident = [c decodeObjectForKey:@"NSLayoutIdentifier"]; if (ident) lc.identifier = ident;
    return [lc retain];
}
@end

/* ======================================================================= windows */
@interface NSWindowTemplate : NSObject @end
@implementation NSWindowTemplate
- (instancetype)initWithCoder:(NSCoder *)c {
    NSString *cn = [c decodeObjectForKey:@"NSWindowClass"];
    Class cls = cn ? NSClassFromString(cn) : Nil;
    if (!cls || ![cls isSubclassOfClass:[NSWindow class]]) cls = [NSWindow class];
    NSRect r = [c decodeRectForKey:@"NSWindowRect"];
    NSWindowStyleMask style = (NSWindowStyleMask)[c decodeIntegerForKey:@"NSWindowStyleMask"];
    [self release];
    NSWindow *w = [[cls alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:YES];
    NSString *t = [c decodeObjectForKey:@"NSWindowTitle"]; if (t) w.title = t;
    NSView *content = [c decodeObjectForKey:@"NSWindowView"]; if ([content isKindOfClass:[NSView class]]) w.contentView = content;
    if ([c containsValueForKey:@"NSWindowContentMinSize"]) w.contentMinSize = [c decodeSizeForKey:@"NSWindowContentMinSize"];
    if ([c containsValueForKey:@"NSMinSize"]) w.minSize = [c decodeSizeForKey:@"NSMinSize"];
    if ([c containsValueForKey:@"NSMaxSize"]) { NSSize m = [c decodeSizeForKey:@"NSMaxSize"]; if (m.width > 0 && m.height > 0) w.maxSize = m; }
    NSString *autosave = [c decodeObjectForKey:@"NSFrameAutosaveName"]; if ([autosave length]) [w setFrameAutosaveName:autosave];
    uint32_t flags = (uint32_t)[c decodeInt64ForKey:@"NSWTFlags"];
    w.releasedWhenClosed = (flags & 0x20000000u) == 0; /* "release when closed" unless the template says otherwise */
    if ([c containsValueForKey:@"NSWindowCollectionBehavior"]) w.collectionBehavior = (NSWindowCollectionBehavior)[c decodeIntegerForKey:@"NSWindowCollectionBehavior"];
    return (id)w;
}
@end

/* ======================================================================= loading */
static NSString *mw_nib_path(NSString *name, NSBundle *b) {
    NSString *p = [name isAbsolutePath] ? ([[NSFileManager defaultManager] fileExistsAtPath:name] ? name : nil) : [b pathForResource:name ofType:@"nib"];
    if (p) {
        BOOL dir = NO; [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&dir];
        if (dir) { /* a nib folder: keyedobjects.nib inside (and keyedobjects-101000.nib for newer systems) */
            for (NSString *f in @[@"keyedobjects-110000.nib", @"keyedobjects-101000.nib", @"keyedobjects.nib"]) {
                NSString *q = [p stringByAppendingPathComponent:f];
                if ([[NSFileManager defaultManager] fileExistsAtPath:q]) return q;
            }
            return nil;
        }
    }
    return p;
}
@implementation NSNib { NSData *_data; NSBundle *_bundle; }
- (instancetype)initWithNibData:(NSData *)d bundle:(NSBundle *)b { if (!d) { [self release]; return nil; } _data = [d retain]; _bundle = [b ?: [NSBundle mainBundle] retain]; return self; }
- (instancetype)initWithNibNamed:(NSString *)n bundle:(NSBundle *)b {
    NSString *p = mw_nib_path(n, b ?: [NSBundle mainBundle]);
    return [self initWithNibData:p ? [NSData dataWithContentsOfFile:p] : nil bundle:b];
}
- (instancetype)initWithContentsOfURL:(NSURL *)u { return [self initWithNibData:[NSData dataWithContentsOfURL:u] bundle:nil]; }
- (void)dealloc { [_data release]; [_bundle release]; [super dealloc]; }
- (BOOL)instantiateWithOwner:(id)owner topLevelObjects:(NSArray **)top {
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:_data error:0];
    if (!u) return NO;
    [u _mwSetNibOwner:owner ? owner : [NSApp self]];
    NSIBObjectData *od = [u decodeObjectForKey:@"IB.objectdata"];
    if (![od isKindOfClass:[NSIBObjectData class]]) { [u release]; return NO; }
    /* top level: objects whose parent is the File's Owner, placeholders excluded */
    NSMutableArray *topObjs = [NSMutableArray array];
    for (NSUInteger i = 0; i < [od->_objectsKeys count] && i < [od->_objectsValues count]; i++) {
        id o = od->_objectsKeys[i], parent = od->_objectsValues[i];
        if (parent == od->_root && o != od->_root && o != [NSApp self] && ![o isKindOfClass:[_MWFirstResponder class]] && o != [NSNull null]) [topObjs addObject:o];
    }
    for (NSNibConnector *conn in od->_connections) if ([conn isKindOfClass:[NSNibConnector class]]) [conn establishConnection];
    /* awakeFromNib: every object of the nib, then the owner */
    NSMutableSet *seen = [NSMutableSet set];
    for (id o in od->_objectsKeys) {
        if (o == [NSNull null] || o == od->_root || [o isKindOfClass:[_MWFirstResponder class]] || [seen containsObject:[NSValue valueWithPointer:o]]) continue;
        [seen addObject:[NSValue valueWithPointer:o]];
        if ([o respondsToSelector:@selector(awakeFromNib)]) [o awakeFromNib];
    }
    if (owner && [owner respondsToSelector:@selector(awakeFromNib)] && owner != [NSApp self]) [owner awakeFromNib];
    /* the top level objects belong to whoever asked: retained once more (MRC rules of NSNib) */
    for (id o in topObjs) [o retain];
    if (top) *top = topObjs;
    for (NSWindow *w in od->_visible) if ([w isKindOfClass:[NSWindow class]]) [w makeKeyAndOrderFront:nil];
    [u release];
    return YES;
}
- (BOOL)instantiateNibWithOwner:(id)owner topLevelObjects:(NSArray **)top { return [self instantiateWithOwner:owner topLevelObjects:top]; }
@end
@implementation NSBundle (NSNibLoading)
- (BOOL)loadNibNamed:(NSNibName)n owner:(id)owner topLevelObjects:(NSArray **)top {
    NSNib *nib = [[[NSNib alloc] initWithNibNamed:n bundle:self] autorelease];
    if (!nib) { NSLog(@"Could not load the nib '%@' in bundle %@", n, self); return NO; }
    return [nib instantiateWithOwner:owner topLevelObjects:top];
}
+ (BOOL)loadNibNamed:(NSString *)n owner:(id)owner { return [[NSBundle mainBundle] loadNibNamed:n owner:owner topLevelObjects:NULL]; }
- (BOOL)loadNibFile:(NSString *)f externalNameTable:(NSDictionary *)t withZone:(NSZone *)z {
    id owner = t[@"NSOwner"];
    NSNib *nib = [[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:f] bundle:self] autorelease];
    NSArray *top = nil;
    BOOL ok = [nib instantiateWithOwner:owner topLevelObjects:&top];
    if ([t[@"NSTopLevelObjects"] isKindOfClass:[NSMutableArray class]]) [t[@"NSTopLevelObjects"] addObjectsFromArray:top];
    return ok;
}
@end

/* the main nib named in Info.plist, with the application as File's Owner */
void mw_load_main_nib(void) {
    NSString *main = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSMainNibFile"];
    if (![main length]) return;
    if (![[NSBundle mainBundle] loadNibNamed:main owner:NSApp topLevelObjects:NULL]) NSLog(@"Unable to load nib file: %@, exiting", main);
}
