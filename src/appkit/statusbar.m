/* statusbar.m — NSStatusBar / NSStatusItem: the menu-bar extras of macOS become icons in the Windows notification area.
 * Each item keeps its button in a hidden window whose frame is the icon's rect (apps place their popovers relative to
 * it); the button is drawn into a bitmap that becomes the tray icon whenever it changes. A click on the icon runs the
 * local event monitors (as a mouse-down in that window would), then shows the item's menu or sends the button's action. */
#import "internal.h"

@interface NSStatusItem () {
@public
    int _sid;
    NSWindow *_win;
    BOOL _pending;
}
- (void)_mwScheduleIcon;
@end

static NSMutableArray *g_items;
static NSTimeInterval g_click_time;   /* the last click on an icon (mw_status_place) */
static NSRect g_click_rect;

@implementation NSStatusBarButton {
@public
    __unsafe_unretained NSStatusItem *_item;
    NSEventMask _sendMask;
}
@synthesize appearsDisabled = _appearsDisabled;
- (instancetype)initWithFrame:(NSRect)r {
    if ((self = [super initWithFrame:r])) { self.bordered = NO; _sendMask = NSEventMaskLeftMouseUp; self.imagePosition = NSImageLeft; }
    return self;
}
- (void)setNeedsDisplay:(BOOL)f { [super setNeedsDisplay:f]; if (f) [_item _mwScheduleIcon]; }
- (void)setToolTip:(NSString *)t { [super setToolTip:t]; [_item _mwScheduleIcon]; }
- (void)setFont:(NSFont *)f { [super setFont:f]; [_item _mwScheduleIcon]; }
- (NSInteger)sendActionOn:(NSInteger)m { NSInteger old = (NSInteger)_sendMask; _sendMask = (NSEventMask)m; return old; }
@end

@implementation NSControl (MWSendActionOn)
- (NSInteger)sendActionOn:(NSInteger)m { return NSEventMaskLeftMouseUp; }   /* ponytail: controls act on mouse-up */
@end
@implementation NSCell (MWHighlightsBy)
- (void)setHighlightsBy:(NSInteger)m { }
- (NSInteger)highlightsBy { return 0; }
- (void)setShowsStateBy:(NSInteger)m { }
- (NSInteger)showsStateBy { return 0; }
@end

@implementation NSStatusBar
+ (NSStatusBar *)systemStatusBar { static NSStatusBar *b; if (!b) b = [[NSStatusBar alloc] init]; return b; }
- (CGFloat)thickness { return 22; }
- (BOOL)isVertical { return NO; }
- (NSStatusItem *)statusItemWithLength:(CGFloat)l {
    static int next;
    NSStatusItem *i = [[[NSStatusItem alloc] init] autorelease];
    i->_sid = ++next;
    i.length = l;
    if (!g_items) g_items = [[NSMutableArray alloc] init];
    [g_items addObject:i];
    i.visible = YES;
    return i;
}
- (void)removeStatusItem:(NSStatusItem *)i {
    if (![g_items containsObject:i]) return;
    ui(UI_STATUS_ITEM, (uint64_t)i->_sid, 0, 0, 0, 0);
    [g_items removeObject:i];
}
@end

@implementation NSStatusItem {
    CGFloat _length;
    NSStatusBarButton *_button;
    NSMenu *_menu;
    NSView *_view;
    NSString *_autosaveName;
    BOOL _visible;
    NSStatusItemBehavior _behavior;
}
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 22, 22) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
    _win.releasedWhenClosed = NO;
    _win.level = NSStatusWindowLevel;
    _button = [[NSStatusBarButton alloc] initWithFrame:NSMakeRect(0, 0, 22, 22)];
    _button->_item = self;
    [_win.contentView addSubview:_button];
    return self;
}
- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    _button->_item = nil;
    [_button release]; [_menu release]; [_view release]; [_autosaveName release];
    [_win close]; [_win release];
    [super dealloc];
}
- (NSStatusBar *)statusBar { return [NSStatusBar systemStatusBar]; }
- (NSStatusBarButton *)button { return _button; }
- (CGFloat)length { return _length; }
- (void)setLength:(CGFloat)l { _length = l; [self _mwScheduleIcon]; }
- (NSMenu *)menu { return _menu; }
- (void)setMenu:(NSMenu *)m { [m retain]; [_menu release]; _menu = m; }
- (NSView *)view { return _view; }
- (void)setView:(NSView *)v { [v retain]; [_view release]; _view = v; [self _mwScheduleIcon]; }
- (NSString *)autosaveName { return _autosaveName; }
- (void)setAutosaveName:(NSString *)n { [_autosaveName release]; _autosaveName = [n copy]; }
- (NSStatusItemBehavior)behavior { return _behavior; }
- (void)setBehavior:(NSStatusItemBehavior)b { _behavior = b; }
- (BOOL)isVisible { return _visible; }
- (void)setVisible:(BOOL)v {
    if (v == _visible) return;
    _visible = v;
    if (v) [self _mwUpdateIcon]; else ui(UI_STATUS_ITEM, (uint64_t)_sid, 0, 0, 0, 0);
}
/* the old API (before the button) */
- (NSString *)title { return _button.title; }
- (void)setTitle:(NSString *)t { _button.title = t; }
- (NSAttributedString *)attributedTitle { return _button.attributedTitle; }
- (void)setAttributedTitle:(NSAttributedString *)t { _button.attributedTitle = t; }
- (NSImage *)image { return _button.image; }
- (void)setImage:(NSImage *)i { _button.image = i; }
- (NSImage *)alternateImage { return _button.alternateImage; }
- (void)setAlternateImage:(NSImage *)i { _button.alternateImage = i; }
- (NSString *)toolTip { return _button.toolTip; }
- (void)setToolTip:(NSString *)t { _button.toolTip = t; }
- (id)target { return _button.target; }
- (void)setTarget:(id)t { _button.target = t; }
- (SEL)action { return _button.action; }
- (void)setAction:(SEL)a { _button.action = a; }
- (SEL)doubleAction { return NULL; }
- (void)setDoubleAction:(SEL)a { }
- (BOOL)highlightMode { return NO; }
- (void)setHighlightMode:(BOOL)h { }
- (BOOL)isEnabled { return _button.enabled; }
- (void)setEnabled:(BOOL)e { _button.enabled = e; }
- (NSInteger)sendActionOn:(NSInteger)m { return [_button sendActionOn:m]; }
- (void)popUpStatusItemMenu:(NSMenu *)m {
    NSMenuItem *i = mw_popup_choose(m, _win, NSMakePoint(0, 0));
    if (i.enabled) [i.menu performActionForItemAtIndex:[i.menu indexOfItem:i]];
}
- (void)drawStatusBarBackgroundInRect:(NSRect)r withHighlight:(BOOL)h { }

- (void)_mwScheduleIcon {
    if (_pending || !_visible) return;
    _pending = YES;
    [self performSelector:@selector(_mwUpdateIcon) withObject:nil afterDelay:0];
}
/* the button (or the custom view) drawn at 2x, cropped to what it draws and fitted into a 32x32 icon */
- (void)_mwUpdateIcon {
    _pending = NO;
    if (!_visible) return;
    NSView *v = _view ? _view : _button;
    if (_view && _view.superview != _win.contentView) [_win.contentView addSubview:_view];
    _button.hidden = _view != nil;
    NSSize sz = v.frame.size;
    if (!_view) {
        NSSize is = _button.intrinsicContentSize;
        sz = NSMakeSize(_length > 0 ? _length : fmax(is.width + 8, 22), 22);
        [_button setFrame:NSMakeRect(0, 0, sz.width, sz.height)];
    }
    const int S = 2, D = 32;
    size_t pw = (size_t)ceil(sz.width * S), ph = (size_t)ceil(sz.height * S);
    if (!pw || !ph) return;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, pw, ph, 8, pw * 4, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!c) return;
    CGContextScaleCTM(c, S, S);
    CGContextTranslateCTM(c, -v.frame.origin.x, -v.frame.origin.y);
    mw_render_view_into(v, c, NULL);
    const uint8_t *px = CGBitmapContextGetData(c);
    size_t x0 = pw, y0 = ph, x1 = 0, y1 = 0;
    for (size_t y = 0; y < ph; y++) for (size_t x = 0; x < pw; x++)
        if (px[(y * pw + x) * 4 + 3]) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    uint32_t out[D * D];
    memset(out, 0, sizeof out);
    if (x0 <= x1) {
        size_t bw = x1 - x0 + 1, bh = y1 - y0 + 1;
        double f = fmin(1, fmin((double)D / bw, (double)D / bh));
        int ox = (int)((D - bw * f) / 2), oy = (int)((D - bh * f) / 2);
        static uint32_t sum[D * D][4], cnt[D * D];
        memset(sum, 0, sizeof sum); memset(cnt, 0, sizeof cnt);
        for (size_t y = y0; y <= y1; y++) for (size_t x = x0; x <= x1; x++) {   /* area average (premultiplied) */
            int dx = ox + (int)((x - x0) * f), dy = oy + (int)((y - y0) * f);
            if (dx < 0 || dy < 0 || dx >= D || dy >= D) continue;
            const uint8_t *p = &px[(y * pw + x) * 4];
            for (int k = 0; k < 4; k++) sum[dy * D + dx][k] += p[k];
            cnt[dy * D + dx]++;
        }
        for (int i = 0; i < D * D; i++) if (cnt[i]) {
            uint8_t *o = (uint8_t *)&out[i];
            for (int k = 0; k < 4; k++) o[k] = (uint8_t)(sum[i][k] / cnt[i]);
        }
    }
    CGContextRelease(c);
    MwImage img = {D, D, out};
    NSString *tip = v.toolTip ? v.toolTip : [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    ui(UI_STATUS_ITEM, (uint64_t)_sid, 1, U(&img), U(tip ? [tip UTF8String] : ""), 0);
}
- (void)_mwClick:(const MwEvent *)h {
    CGFloat s = mw_scale0();
    NSRect r = NSMakeRect(h->x / s, mw_height0() - (h->y + h->dy) / s, fmax(h->dx / s, 1), fmax(h->dy / s, 1));
    g_click_time = 0;   /* the item's own window is not a popover */
    [_win setFrame:r display:NO];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidMoveNotification object:_win];
    NSView *v = _view ? _view : _button;
    [v setFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
    g_click_time = [NSDate timeIntervalSinceReferenceDate]; g_click_rect = r;
    BOOL right = h->button == 1;
    NSEvent *e = [NSEvent mouseEventWithType:right ? NSEventTypeRightMouseDown : NSEventTypeLeftMouseDown
                                    location:NSMakePoint(r.size.width / 2, r.size.height / 2) modifierFlags:h->modifiers
                                   timestamp:h->time_ns / 1e9 windowNumber:_win.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    e = mw_run_event_monitors(e);
    if (!e) return;
    if (_view) { if (right) [_view rightMouseDown:e]; else [_view mouseDown:e]; return; }
    if (_menu) { [self popUpStatusItemMenu:_menu]; return; }
    NSEventMask m = _button->_sendMask;
    BOOL send = right ? (m & (NSEventMaskRightMouseDown | NSEventMaskRightMouseUp)) != 0 : YES;
    if (send && _button.enabled && _button.action) [NSApp sendAction:_button.action to:_button.target from:_button];
}
@end

void mw_status_event(const MwEvent *h) {
    for (NSStatusItem *i in [[g_items copy] autorelease])
        if (i->_sid == (int)h->a) { [i _mwClick:h]; return; }
}

/* A window opened by a click on an icon is placed under it, as under the menu bar on a Mac; the notification area is
   at the bottom, so the window goes up until it is on the screen (just above the icon). */
NSRect mw_status_place(NSRect c) {
    if (!g_items.count || [NSDate timeIntervalSinceReferenceDate] - g_click_time > 2) return c;
    NSScreen *sc = [NSScreen mainScreen];
    for (NSScreen *s in [NSScreen screens]) if (NSIntersectsRect(s.frame, g_click_rect)) sc = s;
    NSRect vis = sc.visibleFrame;
    if (NSMinY(c) < NSMinY(vis) && NSMaxY(c) > NSMinY(sc.frame) - 50 && NSMinY(g_click_rect) < NSMidY(sc.frame))
        c.origin.y = fmin(NSMinY(vis), NSMaxY(vis) - c.size.height);
    if (NSMaxY(c) > NSMaxY(vis) && NSMinY(c) > NSMinY(sc.frame) - 50) c.origin.y = NSMaxY(vis) - c.size.height;   /* not above the top either */
    if (NSIntersectsRect(c, sc.frame))   /* and sideways, inside the screen */
        c.origin.x = fmax(NSMinX(vis), fmin(c.origin.x, NSMaxX(vis) - c.size.width));
    return c;
}

/* SCION_TEST_GUI: "icons: N (P pixels)" — the icons and how many of their pixels are drawn; clicks the first one */
NSString *mw_status_report(void) {
    if (!g_items.count) return @"";
    int drawn = 0;
    for (NSStatusItem *i in g_items) {
        MwImage img = {0};
        if (ui(UI_TEST, 5, (uint64_t)i->_sid, U(&img), 0, 0) == 1 && img.pixels) {
            for (uint32_t k = 0; k < img.w * img.h; k++) if (((uint32_t *)img.pixels)[k] >> 24) drawn++;
            ui(UI_FREE, U(img.pixels), 0, 0, 0, 0);
        }
    }
    return [NSString stringWithFormat:@"; icons: %lu (%d pixels)", (unsigned long)g_items.count, drawn];
}
void mw_status_test_click(int button) { if (g_items.count) ui(UI_TEST, 4, (uint64_t)((NSStatusItem *)g_items[0])->_sid, (uint64_t)button, 0, 0); }
