/* window.m — NSWindow (a host window, ui.cpp) and NSView (geometry, hierarchy, hit testing, layers, tracking areas).
 * A view whose layer is a CAMetalLayer presents into its window through Metal; the other views are drawn by the compositor
 * (draw.m) once per event-loop pass after something asked for display, and shown by the host or over the Metal image. */
#import "internal.h"
#include <string.h>

static NSMutableArray *g_windows;
NSMutableArray *g_windows_list(void) { if (!g_windows) g_windows = [[NSMutableArray alloc] init]; return g_windows; }
NSWindow *mw_window_by_id(uint32_t id) { for (NSWindow *w in g_windows) if ([w _mwId] == id) return w; return nil; }
static BOOL g_needs_update;  /* some view needs layout or display */
static NSSize g_insets = {0, 28}; /* frame - content of the last titled window (points), for +frameRectForContentRect: */

static NSRect px2pt(int x, int y, int w, int h, CGFloat sc) {
    CGFloat s0 = mw_scale0();
    return NSMakeRect(x / s0, mw_height0() - y / s0 - h / sc, w / sc, h / sc);
}

/* ======================================================================= NSWindow */
@interface NSWindow () {
    uint32_t _wid; uint64_t _hwnd; MwWindowInfo _info; NSRect _frameRect, _contentRect; CGFloat _scale;
    BOOL _isKey, _isVisible, _isMini, _isFS, _closed, _needsRender; NSString *_frameAutosaveName; NSResponder *_first; NSView *_mouseDownView; NSMutableSet *_inside; NSRect _unzoomed;
}
@end

static const struct { const char *sel; NSString *const *name; } g_window_notes[] = {
    {"windowDidBecomeKey:", &NSWindowDidBecomeKeyNotification}, {"windowDidResignKey:", &NSWindowDidResignKeyNotification},
    {"windowDidBecomeMain:", &NSWindowDidBecomeMainNotification}, {"windowDidResignMain:", &NSWindowDidResignMainNotification},
    {"windowWillClose:", &NSWindowWillCloseNotification}, {"windowDidResize:", &NSWindowDidResizeNotification},
    {"windowWillStartLiveResize:", &NSWindowWillStartLiveResizeNotification}, {"windowDidEndLiveResize:", &NSWindowDidEndLiveResizeNotification},
    {"windowDidMove:", &NSWindowDidMoveNotification}, {"windowWillMiniaturize:", &NSWindowWillMiniaturizeNotification},
    {"windowDidMiniaturize:", &NSWindowDidMiniaturizeNotification}, {"windowDidDeminiaturize:", &NSWindowDidDeminiaturizeNotification},
    {"windowWillEnterFullScreen:", &NSWindowWillEnterFullScreenNotification}, {"windowDidEnterFullScreen:", &NSWindowDidEnterFullScreenNotification},
    {"windowWillExitFullScreen:", &NSWindowWillExitFullScreenNotification}, {"windowDidExitFullScreen:", &NSWindowDidExitFullScreenNotification},
    {"windowDidChangeBackingProperties:", &NSWindowDidChangeBackingPropertiesNotification}, {"windowDidChangeScreen:", &NSWindowDidChangeScreenNotification},
    {"windowDidChangeOcclusionState:", &NSWindowDidChangeOcclusionStateNotification}, {"windowDidExpose:", &NSWindowDidExposeNotification},
    {"windowDidUpdate:", &NSWindowDidUpdateNotification},
};

@implementation NSWindow
+ (BOOL)allowsAutomaticWindowTabbing { return NO; }
+ (void)setAllowsAutomaticWindowTabbing:(BOOL)f { }
+ (NSRect)frameRectForContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s {
    if (!(s & NSWindowStyleMaskTitled) || (s & NSWindowStyleMaskFullScreen)) return r;
    return NSMakeRect(r.origin.x - g_insets.width / 2, r.origin.y - g_insets.width / 2, r.size.width + g_insets.width, r.size.height + g_insets.height);
}
+ (NSRect)contentRectForFrameRect:(NSRect)r styleMask:(NSWindowStyleMask)s {
    if (!(s & NSWindowStyleMaskTitled) || (s & NSWindowStyleMaskFullScreen)) return r;
    return NSMakeRect(r.origin.x + g_insets.width / 2, r.origin.y + g_insets.width / 2, r.size.width - g_insets.width, r.size.height - g_insets.height);
}
+ (instancetype)windowWithContentViewController:(NSViewController *)vc {
    NSView *v = vc.view;
    NSWindow *w = [[[self alloc] initWithContentRect:NSMakeRect(0, 0, v.frame.size.width ? v.frame.size.width : 480, v.frame.size.height ? v.frame.size.height : 270)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO] autorelease];
    w.contentViewController = vc;
    if (vc.title) w.title = vc.title;
    return w;
}
- (instancetype)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d {
    return [self initWithContentRect:r styleMask:s backing:b defer:d screen:nil];
}
- (instancetype)init {
    return [self initWithContentRect:NSMakeRect(0, 0, 480, 270) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
}
- (instancetype)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d screen:(NSScreen *)sc {
    if (!(self = [super init])) return nil;
    [NSApplication sharedApplication];
    _styleMask = s; _releasedWhenClosed = YES; _hasShadow = YES; _alphaValue = 1; _opaque = YES; _movable = YES; _restorable = YES;
    _canHide = YES; _autorecalculatesKeyViewLoop = YES; _contentMaxSize = _maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _title = @""; _inside = [[NSMutableSet alloc] init];
    CGFloat s0 = mw_scale0(), h0 = mw_height0();
    if (r.size.width < 1) r.size.width = 1;
    if (r.size.height < 1) r.size.height = 1;
    MwWindowDesc desc = {(int32_t)lround(r.origin.x * s0), (int32_t)lround((h0 - r.origin.y - r.size.height) * s0),
                         (int32_t)lround(r.size.width * s0), (int32_t)lround(r.size.height * s0), (uint32_t)(s & 0xF) | ([self isKindOfClass:[NSPanel class]] ? UI_STYLE_NOMENU : 0), 0, ""};
    _wid = (uint32_t)ui(UI_WINDOW_CREATE, U(&desc), 0, 0, 0, 0);
    _hwnd = (uint64_t)ui(UI_WINDOW_HWND, _wid, 0, 0, 0, 0);
    _scale = s0;
    [self _mwRefresh];
    if (_scale != s0) /* created on a screen with another scale: keep the size in points */
        ui(UI_WINDOW_SET, _wid, UI_W_FRAME, (uint64_t)_info.x, (uint64_t)_info.y,
           (uint64_t)lround(r.size.width * _scale) | (uint64_t)lround(r.size.height * _scale) << 32), [self _mwRefresh];
    [g_windows_list() addObject:self];
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, _contentRect.size.width, _contentRect.size.height)];
    [self setContentView:v];
    [v release];
    _first = self;
    return self;
}
- (void)dealloc {
    if (!_closed && _wid) ui(UI_WINDOW_SET, _wid, UI_W_CLOSE, 0, 0, 0);
    [[NSNotificationCenter defaultCenter] removeObserver:(id)_delegate name:nil object:self];
    [_contentView _mwSetWindow:nil];
    [_contentView release]; [_title release]; [_inside release]; [_backgroundColor release]; [_contentViewController release];
    [_subtitle release]; [_representedFilename release]; [_frameAutosaveName release]; [_representedURL release];
    [_toolbar release]; [_appearance release]; [_colorSpace release];
    [super dealloc];
}
- (uint32_t)_mwId { return _wid; }
- (NSView *)_mwRootView { return _contentView; }
- (BOOL)_mwTransparent { return [objc_getAssociatedObject(self, "mw_transparent") boolValue]; }
- (void)_mwSetTransparent:(BOOL)t { objc_setAssociatedObject(self, "mw_transparent", @(t), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (uint64_t)_mwHwnd { return _hwnd; }
/* reads the host window's geometry; returns YES if the content size changed */
- (BOOL)_mwRefresh {
    MwWindowInfo i;
    if (ui(UI_WINDOW_INFO, _wid, U(&i), 0, 0, 0) < 0) return NO;
    _isKey = i.key != 0; _isVisible = i.visible != 0; _isFS = i.fullscreen != 0;
    if (i.minimized || i.w <= 0 || i.h <= 0) { _isMini = i.minimized != 0; return NO; }
    _info = i;
    _scale = i.dpi ? i.dpi / 96.0 : mw_scale0();
    NSSize old = _contentRect.size;
    _contentRect = px2pt(i.x, i.y, i.w, i.h, _scale);
    _frameRect = px2pt(i.fx, i.fy, i.fw, i.fh, _scale);
    /* as on a Mac, the frame is the content plus what is above it: the host's side and bottom borders are not counted,
       so apps that size the frame from the content width (Hex Fiend: bytes per line) do not lose those pixels each time */
    _frameRect = NSMakeRect(_contentRect.origin.x, _contentRect.origin.y, _contentRect.size.width, NSMaxY(_frameRect) - _contentRect.origin.y);
    if ((_styleMask & NSWindowStyleMaskTitled) && !_isFS)
        g_insets = NSMakeSize(_frameRect.size.width - _contentRect.size.width, _frameRect.size.height - _contentRect.size.height);
    return !NSEqualSizes(old, _contentRect.size);
}
- (void)_mwPost:(NSString *)name { [[NSNotificationCenter defaultCenter] postNotificationName:name object:self]; }
/* geometry from the host: content view size, layout, notification */
- (void)_mwGeometry {
    NSRect oldFrame = _frameRect;
    if ([self _mwRefresh]) {
        [_contentView setFrame:NSMakeRect(0, 0, _contentRect.size.width, _contentRect.size.height)];
        [_contentView layoutSubtreeIfNeeded];
        [self _mwPost:NSWindowDidResizeNotification];
    } else if (!NSEqualPoints(oldFrame.origin, _frameRect.origin)) [self _mwPost:NSWindowDidMoveNotification];
}
- (void)_mwHandle:(const MwEvent *)e {
    switch (e->type) {
    case UI_EV_RESIZE:
        if (_isMini) { _isMini = NO; [self _mwGeometry]; [self _mwPost:NSWindowDidDeminiaturizeNotification]; break; }
        [self _mwGeometry];
        break;
    case UI_EV_MOVE: [self _mwGeometry]; break;
    case UI_EV_DPI: {
        CGFloat old = _scale;
        [self _mwGeometry];
        if (old != _scale) { [self _mwSetNeedsRender]; [_contentView _mwBackingChanged]; [self _mwPost:NSWindowDidChangeBackingPropertiesNotification]; }
        break;
    }
    case UI_EV_FOCUS:
        if (e->a && !_isKey) {
            _isKey = YES;
            [NSApp performSelector:@selector(_mwSetActive:) withObject:self];
            [self becomeKeyWindow]; [self becomeMainWindow];
        } else if (!e->a && _isKey) {
            _isKey = NO;
            [self resignKeyWindow]; [self resignMainWindow];
            mw_tracking_update(self, nil, YES);
        }
        break;
    case UI_EV_CLOSE_REQUEST: [self performClose:nil]; break;
    case UI_EV_MINIMIZE:
        if (e->a && !_isMini) { _isMini = YES; [self _mwPost:NSWindowDidMiniaturizeNotification]; }
        break;
    case UI_EV_FULLSCREEN:
        _isFS = e->a != 0;
        if (_isFS) _styleMask |= NSWindowStyleMaskFullScreen; else _styleMask &= ~(NSWindowStyleMask)NSWindowStyleMaskFullScreen;
        [self _mwGeometry];
        [self _mwPost:_isFS ? NSWindowDidEnterFullScreenNotification : NSWindowDidExitFullScreenNotification];
        break;
    case UI_EV_MOUSE_EXIT: mw_tracking_update(self, nil, YES); break;
    }
}
- (void)setDelegate:(id<NSWindowDelegate>)d {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_delegate) [nc removeObserver:(id)_delegate name:nil object:self];
    _delegate = d;
    for (unsigned i = 0; d && i < sizeof g_window_notes / sizeof *g_window_notes; i++) {
        SEL s = sel_registerName(g_window_notes[i].sel);
        if ([(id)d respondsToSelector:s]) [nc addObserver:d selector:s name:*g_window_notes[i].name object:self];
    }
}
- (void)setTitle:(NSString *)t {
    t = [[t copy] autorelease];
    [_title release]; _title = [t ? t : @"" retain];
    ui(UI_WINDOW_SET, _wid, UI_W_TITLE, U([_title UTF8String]), 0, 0);
}
- (void)setContentView:(NSView *)v {
    if (v == _contentView) return;
    [v retain];
    [v removeFromSuperview];
    [_contentView _mwSetWindow:nil];
    [_contentView setNextResponder:nil];
    [_contentView release];
    _contentView = v;
    [v setFrame:NSMakeRect(0, 0, _contentRect.size.width, _contentRect.size.height)];
    [v setNextResponder:self];
    [v _mwSetWindow:self];
}
- (void)setContentViewController:(NSViewController *)vc {
    [vc retain]; [_contentViewController release]; _contentViewController = vc;
    if (vc) {
        NSSize s = vc.view.frame.size;
        if (s.width >= 1 && s.height >= 1) [self setContentSize:s];
        [self setContentView:vc.view];
    }
}
- (void)_mwSetNoMenu:(BOOL)f { objc_setAssociatedObject(self, "mw_nomenu", f ? @YES : nil, OBJC_ASSOCIATION_RETAIN); self.styleMask = _styleMask; }   /* modal windows */
- (void)setStyleMask:(NSWindowStyleMask)s {
    BOOL fs = (s & NSWindowStyleMaskFullScreen) != 0;
    _styleMask = (s & ~(NSWindowStyleMask)NSWindowStyleMaskFullScreen) | (_styleMask & NSWindowStyleMaskFullScreen);
    ui(UI_WINDOW_SET, _wid, UI_W_STYLE, (uint64_t)(s & 0xF) | ([self isKindOfClass:[NSPanel class]] || objc_getAssociatedObject(self, "mw_nomenu") ? UI_STYLE_NOMENU : 0), 0, 0);
    if (fs != _isFS) [self toggleFullScreen:nil];
    [self _mwGeometry];
}
- (NSRect)frame { return _frameRect; }
- (NSRect)contentLayoutRect { return NSMakeRect(0, 0, _contentRect.size.width, _contentRect.size.height); }
- (CGFloat)titlebarHeight { return _frameRect.size.height - _contentRect.size.height; }
- (NSRect)contentRectForFrameRect:(NSRect)r {
    return NSMakeRect(r.origin.x + _contentRect.origin.x - _frameRect.origin.x, r.origin.y + _contentRect.origin.y - _frameRect.origin.y,
                      r.size.width - (_frameRect.size.width - _contentRect.size.width), r.size.height - (_frameRect.size.height - _contentRect.size.height));
}
- (NSRect)frameRectForContentRect:(NSRect)r {
    return NSMakeRect(r.origin.x - (_contentRect.origin.x - _frameRect.origin.x), r.origin.y - (_contentRect.origin.y - _frameRect.origin.y),
                      r.size.width + (_frameRect.size.width - _contentRect.size.width), r.size.height + (_frameRect.size.height - _contentRect.size.height));
}
/* content rect in points -> host (pixels) */
- (void)_mwSetContentRect:(NSRect)c {
    if (!(_styleMask & NSWindowStyleMaskTitled)) c = mw_status_place(c);
    CGFloat s0 = mw_scale0();
    int64_t x = lround(c.origin.x * s0), y = lround((mw_height0() - c.origin.y - c.size.height) * s0);
    uint64_t wh = (uint64_t)lround(c.size.width * _scale) | (uint64_t)lround(c.size.height * _scale) << 32;
    ui(UI_WINDOW_SET, _wid, UI_W_FRAME, (uint64_t)x, (uint64_t)y, wh);
    [self _mwGeometry];
}
- (void)setFrame:(NSRect)r display:(BOOL)d { [self _mwSetContentRect:[self contentRectForFrameRect:r]]; }
- (void)setFrame:(NSRect)r display:(BOOL)d animate:(BOOL)a {   /* unlike setFrame:display:, this one asks the delegate (Cocoa) */
    if ([(id)_delegate respondsToSelector:@selector(windowWillResize:toSize:)] && !NSEqualSizes(r.size, _frameRect.size))
        r.size = [_delegate windowWillResize:self toSize:r.size];
    [self setFrame:r display:d];
}
- (void)setFrameOrigin:(NSPoint)p { [self setFrame:NSMakeRect(p.x, p.y, _frameRect.size.width, _frameRect.size.height) display:YES]; }
- (void)setFrameTopLeftPoint:(NSPoint)p { [self setFrameOrigin:NSMakePoint(p.x, p.y - _frameRect.size.height)]; }
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)p {
    if (p.x == 0 && p.y == 0) return NSMakePoint(_frameRect.origin.x, NSMaxY(_frameRect));
    [self setFrameTopLeftPoint:p];
    return NSMakePoint(p.x + 20, p.y - 20);
}
- (void)setContentSize:(NSSize)s {  /* keeps the top-left corner */
    NSRect c = _contentRect;
    [self _mwSetContentRect:NSMakeRect(c.origin.x, NSMaxY(c) - s.height, s.width, s.height)];
}
- (BOOL)setFrameUsingName:(NSString *)n { return NO; }
- (void)saveFrameUsingName:(NSString *)n { }
- (NSString *)frameAutosaveName { return _frameAutosaveName; }
- (BOOL)setFrameAutosaveName:(NSString *)n { [_frameAutosaveName release]; _frameAutosaveName = [n copy]; return YES; }
- (void)center {
    MwScreen s;
    if (ui(UI_SCREEN, 0, U(&s), 0, 0, 0) <= 0) return;
    int fx = s.vx + (s.vw - _info.fw) / 2, fy = s.vy + (s.vh - _info.fh) / 3; /* a little above the middle, like AppKit */
    uint64_t wh = (uint64_t)(uint32_t)_info.w | (uint64_t)(uint32_t)_info.h << 32;
    ui(UI_WINDOW_SET, _wid, UI_W_FRAME, (uint64_t)(int64_t)(fx + _info.x - _info.fx), (uint64_t)(int64_t)(fy + _info.y - _info.fy), wh);
    [self _mwGeometry];
}
static void set_size_limit(NSWindow *w, uint32_t wid, int what, NSSize s, CGFloat sc) {
    int64_t cw = s.width >= 100000 ? 0 : lround(s.width * sc), ch = s.height >= 100000 ? 0 : lround(s.height * sc);
    ui(UI_WINDOW_SET, wid, (uint64_t)what, (uint64_t)cw, (uint64_t)ch, 0);
}
- (void)setContentMinSize:(NSSize)s { _contentMinSize = s; set_size_limit(self, _wid, UI_W_MIN_SIZE, s, _scale); }
- (void)setContentMaxSize:(NSSize)s { _contentMaxSize = s; set_size_limit(self, _wid, UI_W_MAX_SIZE, s, _scale); }
- (void)setMinSize:(NSSize)s { _minSize = s; [self setContentMinSize:[self contentRectForFrameRect:NSMakeRect(0, 0, s.width, s.height)].size]; }
- (void)setMaxSize:(NSSize)s {
    _maxSize = s;
    [self setContentMaxSize:s.width >= 100000 ? s : [self contentRectForFrameRect:NSMakeRect(0, 0, s.width, s.height)].size];
}
- (void)setContentAspectRatio:(NSSize)s {
    _contentAspectRatio = s;
    ui(UI_WINDOW_SET, _wid, UI_W_ASPECT, (uint64_t)lround(s.width * 1000), (uint64_t)lround(s.height * 1000), 0);
}
- (void)setAspectRatio:(NSSize)s { _aspectRatio = s; [self setContentAspectRatio:s]; }
- (CGFloat)backingScaleFactor { return _scale; }
- (NSScreen *)screen {
    NSPoint c = NSMakePoint(NSMidX(_frameRect), NSMidY(_frameRect));
    for (NSScreen *s in [NSScreen screens]) if (NSPointInRect(c, s.frame)) return s;
    return [[NSScreen screens] firstObject];
}
- (NSScreen *)deepestScreen { return [self screen]; }
- (NSInteger)windowNumber { return _wid; }
- (BOOL)isKeyWindow { return _isKey; }
- (BOOL)isMainWindow { return _isKey; }
- (BOOL)isVisible { return _isVisible && !_closed; }
- (BOOL)isMiniaturized { return _isMini; }
- (BOOL)isZoomed { return !NSIsEmptyRect(_unzoomed); }
- (BOOL)canBecomeKeyWindow { return (_styleMask & NSWindowStyleMaskTitled) || [self isKindOfClass:[NSPanel class]]; }
- (BOOL)canBecomeMainWindow { return [self canBecomeKeyWindow]; }
- (BOOL)isOnActiveSpace { return YES; }
- (BOOL)isSheet { return NO; }
- (BOOL)inLiveResize { return NO; }
- (NSWindowOcclusionState)occlusionState { return (_isVisible && !_isMini) ? NSWindowOcclusionStateVisible : 0; }
- (NSResponder *)firstResponder { return _first ? _first : self; }
- (NSAppearance *)effectiveAppearance { return _appearance ? _appearance : [NSApp effectiveAppearance]; }
- (NSWindow *)parentWindow { return nil; }
- (NSWindow *)sheetParent { return nil; }
- (NSWindow *)attachedSheet { return nil; }
- (NSArray *)childWindows { return @[]; }
- (NSArray *)sheets { return @[]; }
- (NSEvent *)currentEvent { return [NSApp currentEvent]; }
- (NSPoint)mouseLocationOutsideOfEventStream { return [self convertPointFromScreen:[NSEvent mouseLocation]]; }

- (void)_mwShow:(int)how {
    if (_closed) return;
    BOOL was = _isVisible;
    ui(UI_WINDOW_SET, _wid, UI_W_SHOW, (uint64_t)how, 0, 0);
    _isVisible = how != 0;
    if (_isVisible && !was) { g_needs_update = YES; [_contentView setNeedsLayout:YES]; [self _mwSetNeedsRender]; }
    if (how == 2) [self _mwRefresh];
}
- (void)makeKeyAndOrderFront:(id)s { [self _mwShow:2]; }
- (void)orderFront:(id)s { [self _mwShow:1]; }
- (void)orderFrontRegardless { [self _mwShow:1]; }
- (void)orderBack:(id)s { [self _mwShow:1]; }
- (void)orderOut:(id)s { [self _mwShow:0]; }
- (void)orderWindow:(NSWindowOrderingMode)m relativeTo:(NSInteger)w { [self _mwShow:m == NSWindowOut ? 0 : 1]; }
- (void)setIsVisible:(BOOL)f { [self _mwShow:f ? 1 : 0]; }
- (void)makeKeyWindow { [self _mwShow:2]; }
- (void)makeMainWindow { }
- (void)becomeKeyWindow { [self _mwPost:NSWindowDidBecomeKeyNotification]; }
- (void)resignKeyWindow { [self _mwPost:NSWindowDidResignKeyNotification]; }
- (void)becomeMainWindow { [self _mwPost:NSWindowDidBecomeMainNotification]; }
- (void)resignMainWindow { [self _mwPost:NSWindowDidResignMainNotification]; }
- (void)close {
    if (_closed) return;
    [self retain];
    [self _mwPost:NSWindowWillCloseNotification];
    _closed = YES; _isVisible = NO;
    [_contentView _mwDetachLayers]; /* Metal stops presenting before the host window goes */
    ui(UI_WINDOW_SET, _wid, UI_W_CLOSE, 0, 0, 0);
    [g_windows removeObjectIdenticalTo:self];
    if (_releasedWhenClosed) [self autorelease];
    [self release];
    BOOL any = NO;
    for (NSWindow *w in g_windows) if (w.isVisible) any = YES;
    id d = [NSApp delegate];
    if (!any && [d respondsToSelector:@selector(applicationShouldTerminateAfterLastWindowClosed:)] && [d applicationShouldTerminateAfterLastWindowClosed:NSApp])
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0];
}
- (void)performClose:(id)s {
    if ([(id)_delegate respondsToSelector:@selector(windowShouldClose:)] && ![_delegate windowShouldClose:self]) return;
    if ([self respondsToSelector:@selector(windowShouldClose:)] && ![(id)self windowShouldClose:self]) return;
    if ([self.windowController respondsToSelector:@selector(_mwWindowShouldClose)] && !((BOOL (*)(id, SEL))objc_msgSend)(self.windowController, @selector(_mwWindowShouldClose))) return;
    [self close];
}
- (void)miniaturize:(id)s { [self _mwPost:NSWindowWillMiniaturizeNotification]; ui(UI_WINDOW_SET, _wid, UI_W_MINIMIZE, 1, 0, 0); }
- (void)performMiniaturize:(id)s { [self miniaturize:s]; }
- (void)deminiaturize:(id)s { ui(UI_WINDOW_SET, _wid, UI_W_MINIMIZE, 0, 0, 0); }
- (void)zoom:(id)s {
    if (!NSIsEmptyRect(_unzoomed)) { NSRect r = _unzoomed; _unzoomed = NSZeroRect; [self setFrame:r display:YES]; return; }
    NSRect old = _frameRect;
    [self setFrame:self.screen.visibleFrame display:YES];
    _unzoomed = old;
}
- (void)performZoom:(id)s { [self zoom:s]; }
- (void)toggleFullScreen:(id)s {
    [self _mwPost:_isFS ? NSWindowWillExitFullScreenNotification : NSWindowWillEnterFullScreenNotification];
    ui(UI_WINDOW_SET, _wid, UI_W_FULLSCREEN, _isFS ? 0 : 1, 0, 0);
}
- (BOOL)makeFirstResponder:(NSResponder *)r {
    NSResponder *cur = [self firstResponder];
    if (r == cur) return YES;
    if (![cur resignFirstResponder]) return NO;
    if (r && r != self && (![r acceptsFirstResponder] || ![r becomeFirstResponder])) { _first = self; return NO; }
    _first = r ? r : self;
    return YES;
}
- (BOOL)validateUserInterfaceItem:(id)i { return YES; }

/* ---------------------------------------------------------------- events */
- (void)sendEvent:(NSEvent *)e {
    switch (e.type) { /* clicks and keys usually change what controls show */
    case NSEventTypeKeyDown: case NSEventTypeKeyUp: case NSEventTypeLeftMouseDown: case NSEventTypeLeftMouseUp: case NSEventTypeRightMouseDown:
    case NSEventTypeRightMouseUp: case NSEventTypeScrollWheel: [self _mwSetNeedsRender]; break;
    default: break;
    }
    switch (e.type) {
    case NSEventTypeKeyDown: [[self firstResponder] keyDown:e]; break;
    case NSEventTypeKeyUp: [[self firstResponder] keyUp:e]; break;
    case NSEventTypeFlagsChanged: [[self firstResponder] flagsChanged:e]; break;
    case NSEventTypeLeftMouseDown: case NSEventTypeRightMouseDown: case NSEventTypeOtherMouseDown: {
        NSView *v = [_contentView hitTest:e.locationInWindow];
        [_mouseDownView release]; _mouseDownView = [v retain];
        if (!v) break;
        if (e.type == NSEventTypeLeftMouseDown && v != [self firstResponder] && [v acceptsFirstResponder]) [self makeFirstResponder:v];
        if (e.type == NSEventTypeLeftMouseDown) [v mouseDown:e];
        else if (e.type == NSEventTypeRightMouseDown) [v rightMouseDown:e];
        else [v otherMouseDown:e];
        break;
    }
    case NSEventTypeLeftMouseUp: case NSEventTypeRightMouseUp: case NSEventTypeOtherMouseUp: {
        NSView *v = _mouseDownView ? [[_mouseDownView retain] autorelease] : [_contentView hitTest:e.locationInWindow];
        [_mouseDownView release]; _mouseDownView = nil;
        if (e.type == NSEventTypeLeftMouseUp) [v mouseUp:e];
        else if (e.type == NSEventTypeRightMouseUp) [v rightMouseUp:e];
        else [v otherMouseUp:e];
        break;
    }
    case NSEventTypeLeftMouseDragged: case NSEventTypeRightMouseDragged: case NSEventTypeOtherMouseDragged: {
        mw_tracking_update(self, e, NO);
        NSView *v = _mouseDownView ? _mouseDownView : [_contentView hitTest:e.locationInWindow];
        if (e.type == NSEventTypeLeftMouseDragged) [v mouseDragged:e];
        else if (e.type == NSEventTypeRightMouseDragged) [v rightMouseDragged:e];
        else [v otherMouseDragged:e];
        break;
    }
    case NSEventTypeMouseMoved:
        mw_tracking_update(self, e, NO);
        if (_acceptsMouseMovedEvents) [[self firstResponder] mouseMoved:e];
        break;
    case NSEventTypeScrollWheel: [[_contentView hitTest:e.locationInWindow] scrollWheel:e]; break;
    case NSEventTypeMouseEntered: [(NSResponder *)e.trackingArea.owner mouseEntered:e]; break;
    case NSEventTypeMouseExited: [(NSResponder *)e.trackingArea.owner mouseExited:e]; break;
    default: break;
    }
}
- (BOOL)performKeyEquivalent:(NSEvent *)e { return [_contentView performKeyEquivalent:e]; }
- (NSEvent *)nextEventMatchingMask:(NSEventMask)m { return [NSApp nextEventMatchingMask:m untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES]; }
- (NSEvent *)nextEventMatchingMask:(NSEventMask)m untilDate:(NSDate *)d inMode:(NSRunLoopMode)mode dequeue:(BOOL)dq {
    return [NSApp nextEventMatchingMask:m untilDate:d inMode:mode dequeue:dq];
}
- (void)postEvent:(NSEvent *)e atStart:(BOOL)f { [NSApp postEvent:e atStart:f]; }
- (void)trackEventsMatchingMask:(NSEventMask)m timeout:(NSTimeInterval)t mode:(NSRunLoopMode)mode handler:(void (^)(NSEvent *, BOOL *))h {
    BOOL stop = NO;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:t];
    while (!stop) {
        NSEvent *e = [NSApp nextEventMatchingMask:m untilDate:until inMode:mode dequeue:YES];
        if (!e) { h(nil, &stop); break; }
        h(e, &stop);
    }
}
- (void)_mwHandleMouse:(NSEvent *)e { [self sendEvent:e]; }
- (void)_mwSetNeedsRender { _needsRender = YES; g_needs_update = YES; }
- (void)_mwRenderNow {
    if (!_isVisible || _closed) return;
    _needsRender = NO;
    mw_render_window(self);
    [_contentView _mwClearNeedsDisplay];
}
- (NSMutableSet *)_mwInside { return _inside; }

/* ---------------------------------------------------------------- drawing, conversions, misc */
- (void)display { [_contentView layoutSubtreeIfNeeded]; [self _mwRenderNow]; }
- (void)displayIfNeeded { if (_needsRender) [self display]; }
- (void)setViewsNeedDisplay:(BOOL)f { if (f) [self _mwSetNeedsRender]; }
- (BOOL)viewsNeedDisplay { return _needsRender; }
- (void)setBackgroundColor:(NSColor *)c { [c retain]; [_backgroundColor release]; _backgroundColor = c; [self _mwSetNeedsRender]; }
- (void)update { }
- (void)disableScreenUpdatesUntilFlush { }
- (void)invalidateShadow { }
- (void)invalidateCursorRectsForView:(NSView *)v { }
- (void)disableCursorRects { }
- (void)enableCursorRects { }
- (void)resetCursorRects { }
- (NSRect)convertRectToBacking:(NSRect)r { return NSMakeRect(r.origin.x * _scale, r.origin.y * _scale, r.size.width * _scale, r.size.height * _scale); }
- (NSRect)convertRectFromBacking:(NSRect)r { return NSMakeRect(r.origin.x / _scale, r.origin.y / _scale, r.size.width / _scale, r.size.height / _scale); }
- (NSPoint)convertPointToBacking:(NSPoint)p { return NSMakePoint(p.x * _scale, p.y * _scale); }
- (NSPoint)convertPointFromBacking:(NSPoint)p { return NSMakePoint(p.x / _scale, p.y / _scale); }
- (NSRect)backingAlignedRect:(NSRect)r options:(NSAlignmentOptions)o { return [self convertRectFromBacking:NSIntegralRect([self convertRectToBacking:r])]; }
- (NSRect)convertRectToScreen:(NSRect)r { return NSOffsetRect(r, _contentRect.origin.x, _contentRect.origin.y); }
- (NSRect)convertRectFromScreen:(NSRect)r { return NSOffsetRect(r, -_contentRect.origin.x, -_contentRect.origin.y); }
- (NSPoint)convertPointToScreen:(NSPoint)p { return NSMakePoint(p.x + _contentRect.origin.x, p.y + _contentRect.origin.y); }
- (NSPoint)convertPointFromScreen:(NSPoint)p { return NSMakePoint(p.x - _contentRect.origin.x, p.y - _contentRect.origin.y); }
- (NSButton *)standardWindowButton:(NSWindowButton)b { return nil; }
- (void)addChildWindow:(NSWindow *)w ordered:(NSWindowOrderingMode)o { [w orderFront:nil]; }
- (void)removeChildWindow:(NSWindow *)w { }
/* sheets: shown as their own window; the handler runs when -endSheet: is called */
- (void)beginSheet:(NSWindow *)w completionHandler:(void (^)(NSModalResponse))h {
    objc_setAssociatedObject(w, "mw_sheet", h, 3 /* copy nonatomic */);
    [w makeKeyAndOrderFront:nil];
}
- (void)beginCriticalSheet:(NSWindow *)w completionHandler:(void (^)(NSModalResponse))h { [self beginSheet:w completionHandler:h]; }
- (void)endSheet:(NSWindow *)w { [self endSheet:w returnCode:NSModalResponseStop]; }
- (void)endSheet:(NSWindow *)w returnCode:(NSModalResponse)r {
    void (^h)(NSModalResponse) = [[objc_getAssociatedObject(w, "mw_sheet") retain] autorelease];
    objc_setAssociatedObject(w, "mw_sheet", nil, 3);
    [w orderOut:nil];
    if (h) h(r);
}
- (void)selectNextKeyView:(id)s { }
- (void)selectPreviousKeyView:(id)s { }
- (void)recalculateKeyViewLoop { }
- (void)setDynamicDepthLimit:(BOOL)f { }
- (void)registerForDraggedTypes:(NSArray *)t { }
- (instancetype)animator { return self; }
- (void)setAppearance:(NSAppearance *)a { [a retain]; [_appearance release]; _appearance = a; }
@end
@implementation NSPanel @end

void mw_window_event(NSWindow *w, const MwEvent *e) { [w _mwHandle:e]; }

/* layout and display pass, once per event-loop pass when something asked for it */
void mw_windows_update(void) {
    if (!g_needs_update) return;
    g_needs_update = NO;
    for (NSWindow *w in [[g_windows copy] autorelease]) {
        if (!w.isVisible) continue;
        [[w _mwRootView] layoutSubtreeIfNeeded];   /* the real root: apps may override -contentView */
        [w displayIfNeeded];
    }
}

/* ======================================================================= tracking areas */
@implementation NSTrackingArea { NSRect _rect; NSTrackingAreaOptions _options; id _owner; NSDictionary *_userInfo; @public NSView *_view; }
- (instancetype)initWithRect:(NSRect)r options:(NSTrackingAreaOptions)o owner:(id)owner userInfo:(NSDictionary *)u {
    if ((self = [super init])) { _rect = r; _options = o; _owner = owner; _userInfo = [u copy]; }
    return self;
}
- (void)dealloc { [_userInfo release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [[NSTrackingArea alloc] initWithRect:_rect options:_options owner:_owner userInfo:_userInfo]; }
- (NSRect)rect { return _rect; }
- (NSTrackingAreaOptions)options { return _options; }
- (id)owner { return _owner; }
- (NSDictionary *)userInfo { return _userInfo; }
@end

static void collect_areas(NSView *v, NSMutableArray *out) {
    if (v.isHidden) return;
    for (NSTrackingArea *a in v.trackingAreas) [out addObject:@[a, v]];
    for (NSView *s in v.subviews) collect_areas(s, out);
}
static NSEvent *area_event(NSEventType t, NSEvent *src, NSTrackingArea *a, NSWindow *w) {
    NSEvent *e = [NSEvent otherEventWithType:t location:src ? src.locationInWindow : NSZeroPoint modifierFlags:[NSEvent modifierFlags]
                                   timestamp:src ? src.timestamp : 0 windowNumber:w.windowNumber context:nil subtype:0 data1:0 data2:0];
    mw_event_set_area(e, a);
    return e;
}
/* mouse moved inside the window (e) or left it (exited): mouseEntered:/mouseExited:/mouseMoved: for the tracking areas */
void mw_tracking_update(NSWindow *w, NSEvent *e, BOOL exited) {
    NSMutableSet *inside = [w _mwInside];
    NSMutableArray *areas = [NSMutableArray array];
    if (!exited) collect_areas([w _mwRootView], areas);
    NSMutableSet *now = [NSMutableSet set];
    for (NSArray *p in areas) {
        NSTrackingArea *a = p[0]; NSView *v = p[1];
        NSRect r = (a.options & NSTrackingInVisibleRect) ? v.bounds : a.rect;
        NSPoint q = [v convertPoint:e.locationInWindow fromView:nil];
        if (!NSMouseInRect(q, r, v.isFlipped)) continue;
        NSValue *k = [NSValue valueWithPointer:a];
        [now addObject:k];
        if (![inside containsObject:k] && (a.options & NSTrackingMouseEnteredAndExited)) [a.owner mouseEntered:area_event(NSEventTypeMouseEntered, e, a, w)];
        if ((a.options & NSTrackingMouseMoved) && e.type == NSEventTypeMouseMoved && a.owner != [w firstResponder]) [a.owner mouseMoved:e];
    }
    for (NSValue *k in [[inside copy] autorelease]) {
        if ([now containsObject:k]) continue;
        NSTrackingArea *a = [k pointerValue];
        BOOL alive = NO;
        if (!exited) for (NSArray *p in areas) if (p[0] == a) alive = YES;
        if ((alive || exited) && (a.options & NSTrackingMouseEnteredAndExited)) [a.owner mouseExited:area_event(NSEventTypeMouseExited, e, a, w)];
        [inside removeObject:k];
    }
    for (id k in now) [inside addObject:k];
}

/* ======================================================================= NSView */
@interface NSView () {
    NSMutableArray *_subs, *_areas, *_cons;
    NSView *_super; NSWindow *_win;
    BOOL _backing; /* the layer is ours (makeBackingLayer) */
    NSMutableDictionary *_prio;
}
@end
@implementation NSView
+ (void)initialize { }
- (instancetype)init { return [self initWithFrame:NSZeroRect]; }
- (instancetype)initWithFrame:(NSRect)r {
    if ((self = [super init])) {
        _frame = r; _bounds = NSMakeRect(0, 0, r.size.width, r.size.height);
        _autoresizesSubviews = YES; _alphaValue = 1; _translatesAutoresizingMaskIntoConstraints = YES; _postsFrameChangedNotifications = YES;
        _needsDisplay = YES;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)c { return mw_nib_init_view(self, c); }
- (void)dealloc {
    for (NSView *v in _subs) { v->_super = nil; [v setNextResponder:nil]; }
    [_subs release]; [_areas release]; [_cons release]; [_layer release]; [_prio release];
    [_identifier release]; [_toolTip release]; [_appearance release];
    [_accessibilityLabel release]; [_accessibilityIdentifier release]; [_accessibilityHelp release]; [_accessibilityTitle release]; [_accessibilityValue release];
    [super dealloc];
}
- (NSWindow *)window { return _win; }
- (NSView *)superview { return _super; }
- (NSArray *)subviews { return _subs ? [[_subs copy] autorelease] : @[]; }
- (void)setSubviews:(NSArray *)a {
    for (NSView *v in [[_subs copy] autorelease]) if (![a containsObject:v]) [v removeFromSuperview];
    for (NSView *v in a) if (v->_super != self) [self addSubview:v];
    [_subs setArray:a];
}
- (BOOL)isFlipped { return NO; }
- (BOOL)isOpaque { return NO; }
- (BOOL)wantsUpdateLayer { return NO; }
- (BOOL)inLiveResize { return NO; }
- (BOOL)canBecomeKeyView { return [self acceptsFirstResponder] && !self.isHiddenOrHasHiddenAncestor; }
- (BOOL)needsPanelToBecomeKey { return NO; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)isHiddenOrHasHiddenAncestor { for (NSView *v = self; v; v = v->_super) if (v.isHidden) return YES; return NO; }
- (NSAppearance *)effectiveAppearance { return _appearance ? _appearance : _super ? _super.effectiveAppearance : _win ? _win.effectiveAppearance : [NSApp effectiveAppearance]; }
- (void)setAppearance:(NSAppearance *)a { [a retain]; [_appearance release]; _appearance = a; }
- (NSRect)visibleRect { return _bounds; }
- (NSSize)intrinsicContentSize { return NSMakeSize(-1, -1); } /* NSViewNoIntrinsicMetric */
- (NSSize)fittingSize { NSSize s = [self intrinsicContentSize]; return s.width >= 0 && s.height >= 0 ? s : _frame.size; }
- (NSEdgeInsets)safeAreaInsets { return self.additionalSafeAreaInsets; }   /* no title bar overlaps the content here */
- (NSEdgeInsets)additionalSafeAreaInsets { NSValue *v = objc_getAssociatedObject(self, @selector(additionalSafeAreaInsets)); NSEdgeInsets e = NSEdgeInsetsZero; if (v) [v getValue:&e]; return e; }
- (void)setAdditionalSafeAreaInsets:(NSEdgeInsets)e {
    objc_setAssociatedObject(self, @selector(additionalSafeAreaInsets), [NSValue valueWithBytes:&e objCType:@encode(NSEdgeInsets)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.needsLayout = YES;
}
- (NSRect)safeAreaRect {
    NSEdgeInsets e = self.safeAreaInsets; NSRect b = _bounds;
    return NSMakeRect(b.origin.x + e.left, b.origin.y + (self.isFlipped ? e.top : e.bottom), b.size.width - e.left - e.right, b.size.height - e.top - e.bottom);
}
- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection { return NSUserInterfaceLayoutDirectionLeftToRight; }
- (NSViewController *)viewController { return nil; }
- (CGFloat)firstBaselineOffsetFromTop { return 0; }
- (CGFloat)lastBaselineOffsetFromBottom { return 0; }
- (CGFloat)baselineOffsetFromBottom { return 0; }
- (instancetype)animator { return self; }

/* ---------------------------------------------------------------- geometry */
/* -setFrame: goes through -setFrameOrigin: and -setFrameSize: (as in AppKit), so subclasses that override those see every change */
- (void)setFrame:(NSRect)r {
    BOOL post = _postsFrameChangedNotifications; _postsFrameChangedNotifications = NO;
    BOOL changed = !NSEqualRects(r, _frame);
    [self setFrameOrigin:r.origin];
    [self setFrameSize:r.size];
    _postsFrameChangedNotifications = post;
    if (post && changed) [[NSNotificationCenter defaultCenter] postNotificationName:NSViewFrameDidChangeNotification object:self];
}
- (void)setFrameOrigin:(NSPoint)p {
    if (NSEqualPoints(p, _frame.origin)) return;
    _frame.origin = p;
    [_win _mwSetNeedsRender];
    if (_postsFrameChangedNotifications) [[NSNotificationCenter defaultCenter] postNotificationName:NSViewFrameDidChangeNotification object:self];
}
- (void)setFrameSize:(NSSize)s {
    NSSize old = _frame.size;
    if (NSEqualSizes(old, s)) return;
    _frame.size = s;
    [_win _mwSetNeedsRender];
    _bounds.size = s;
    if (_autoresizesSubviews) [self resizeSubviewsWithOldSize:old];
    if (_layer && _backing) _layer.frame = NSMakeRect(0, 0, s.width, s.height);
    _needsLayout = YES; g_needs_update = YES;
    _needsDisplay = YES;
    if (_postsFrameChangedNotifications) [[NSNotificationCenter defaultCenter] postNotificationName:NSViewFrameDidChangeNotification object:self];
}
- (void)setBounds:(NSRect)b {
    _bounds = b;
    [_win _mwSetNeedsRender];
    if (_postsBoundsChangedNotifications) [[NSNotificationCenter defaultCenter] postNotificationName:NSViewBoundsDidChangeNotification object:self];
}
- (void)setBoundsOrigin:(NSPoint)p { [self setBounds:NSMakeRect(p.x, p.y, _bounds.size.width, _bounds.size.height)]; }
- (void)setBoundsSize:(NSSize)s { [self setBounds:NSMakeRect(_bounds.origin.x, _bounds.origin.y, s.width, s.height)]; }
- (void)resizeSubviewsWithOldSize:(NSSize)old { for (NSView *v in [[_subs copy] autorelease]) [v resizeWithOldSuperviewSize:old]; }
static void spread(CGFloat delta, CGFloat *a, BOOL fa, CGFloat *b, BOOL fb, CGFloat *c, BOOL fc) {
    CGFloat total = (fa ? *a : 0) + (fb ? *b : 0) + (fc ? *c : 0);
    int n = fa + fb + fc;
    if (!n) return;
    if (total > 0) { if (fa) *a += delta * *a / total; if (fb) *b += delta * *b / total; if (fc) *c += delta * *c / total; }
    else { if (fa) *a += delta / n; if (fb) *b += delta / n; if (fc) *c += delta / n; }
}
- (void)resizeWithOldSuperviewSize:(NSSize)old {
    NSSize now = _super.bounds.size;
    NSAutoresizingMaskOptions m = _autoresizingMask;
    NSRect f = _frame;
    CGFloat l = f.origin.x, w = f.size.width, r = old.width - NSMaxX(f);
    spread(now.width - old.width, &l, (m & NSViewMinXMargin) != 0, &w, (m & NSViewWidthSizable) != 0, &r, (m & NSViewMaxXMargin) != 0);
    CGFloat b = f.origin.y, h = f.size.height, t = old.height - NSMaxY(f);
    spread(now.height - old.height, &b, (m & NSViewMinYMargin) != 0, &h, (m & NSViewHeightSizable) != 0, &t, (m & NSViewMaxYMargin) != 0);
    if (!(m & (NSViewMinYMargin | NSViewHeightSizable | NSViewMaxYMargin)) && !_super.isFlipped) b = f.origin.y; /* pinned to the bottom */
    [self setFrame:NSMakeRect(l, b, fmax(w, 0), fmax(h, 0))];
}

/* ---------------------------------------------------------------- hierarchy */
- (void)addSubview:(NSView *)v { [self addSubview:v positioned:NSWindowAbove relativeTo:nil]; }
- (void)addSubview:(NSView *)v positioned:(NSWindowOrderingMode)place relativeTo:(NSView *)other {
    if (!v || v == self) return;
    [v retain];
    if (v->_super) [v removeFromSuperview];
    if (!_subs) _subs = [[NSMutableArray alloc] init];
    NSUInteger i = other ? [_subs indexOfObjectIdenticalTo:other] : NSNotFound;
    if (i == NSNotFound) { if (place == NSWindowBelow) [_subs insertObject:v atIndex:0]; else [_subs addObject:v]; }
    else [_subs insertObject:v atIndex:place == NSWindowBelow ? i : i + 1];
    [v viewWillMoveToSuperview:self];
    v->_super = self;
    [v setNextResponder:self];
    [v _mwSetWindow:_win];
    [v viewDidMoveToSuperview];
    [self didAddSubview:v];
    [v release];
    _needsLayout = YES; g_needs_update = YES;
    [_win _mwSetNeedsRender];
}
- (void)removeFromSuperview {
    NSView *s = _super;
    if (!s) return;
    [s willRemoveSubview:self];
    /* as in Cocoa: the ancestors' constraints that mention this view (or a view inside it) go away with it */
    for (NSView *a = s; a; a = a->_super) {
        if (!a->_cons.count) continue;
        for (NSLayoutConstraint *c in [[a->_cons copy] autorelease]) {
            id f = c.firstItem, g = c.secondItem;
            BOOL inside = ([f isKindOfClass:[NSView class]] && [f isDescendantOf:self]) || ([g isKindOfClass:[NSView class]] && [g isDescendantOf:self]);
            if (inside) [a removeConstraint:c];
        }
    }
    [self retain];
    if (_win && [_win firstResponder] == self) [_win makeFirstResponder:nil];
    [_win _mwSetNeedsRender];
    [self viewWillMoveToSuperview:nil];
    _super = nil;
    [self setNextResponder:nil];
    [self _mwSetWindow:nil];
    [s->_subs removeObjectIdenticalTo:self];
    [self viewDidMoveToSuperview];
    [self release];
}
- (void)replaceSubview:(NSView *)old with:(NSView *)v {
    NSUInteger i = [_subs indexOfObjectIdenticalTo:old];
    if (i == NSNotFound) { [self addSubview:v]; return; }
    NSView *before = i ? [_subs objectAtIndex:i - 1] : nil;
    [old removeFromSuperview];
    if (before) [self addSubview:v positioned:NSWindowAbove relativeTo:before];
    else [self addSubview:v positioned:NSWindowBelow relativeTo:nil];
}
- (void)sortSubviewsUsingFunction:(NSComparisonResult (*)(id, id, void *))f context:(void *)c {
    [_subs sortUsingComparator:^NSComparisonResult(id a, id b) { return f(a, b, c); }];
}
- (BOOL)isDescendantOf:(NSView *)v { for (NSView *s = self; s; s = s->_super) if (s == v) return YES; return NO; }
- (NSView *)ancestorSharedWithView:(NSView *)v { for (NSView *s = self; s; s = s->_super) if ([v isDescendantOf:s]) return s; return nil; }
- (NSView *)viewWithTag:(NSInteger)t {
    if (self.tag == t) return self;
    for (NSView *v in _subs) { NSView *r = [v viewWithTag:t]; if (r) return r; }
    return nil;
}
- (void)viewWillMoveToWindow:(NSWindow *)w { }
- (void)viewDidMoveToWindow { }
- (void)viewWillMoveToSuperview:(NSView *)v { }
- (void)viewDidMoveToSuperview { }
- (void)didAddSubview:(NSView *)v { }
- (void)willRemoveSubview:(NSView *)v { }
- (void)viewDidChangeBackingProperties { }
- (void)viewDidChangeEffectiveAppearance { }
- (void)viewDidHide { }
- (void)viewDidUnhide { }
- (void)viewWillStartLiveResize { }
- (void)viewDidEndLiveResize { }
- (void)_mwBindLayer {
    if (!_win || !_layer) return;
    if ([_layer respondsToSelector:@selector(_mwSetHostWindow:)]) [_layer _mwSetHostWindow:[_win _mwHwnd]];
    if (_backing) _layer.contentsScale = _win.backingScaleFactor;
}
- (void)_mwSetWindow:(NSWindow *)w {
    if (w != _win) {
        [self viewWillMoveToWindow:w];
        if (_win && !w && [_layer respondsToSelector:@selector(_mwSetHostWindow:)]) [_layer _mwSetHostWindow:~0ull];
        _win = w;
        [self _mwBindLayer];
        for (NSView *v in [[_subs copy] autorelease]) [v _mwSetWindow:w];
        _needsDisplay = _needsLayout = YES; g_needs_update = YES;
        [w _mwSetNeedsRender];
        [self viewDidMoveToWindow];
        if (w) [self updateTrackingAreas];
    }
}
- (void)_mwDetachLayers {
    if ([_layer respondsToSelector:@selector(_mwSetHostWindow:)]) [_layer _mwSetHostWindow:~0ull];
    for (NSView *v in [[_subs copy] autorelease]) [v _mwDetachLayers];
}
- (void)_mwBackingChanged {
    if (_layer && _backing) _layer.contentsScale = _win.backingScaleFactor;
    [self viewDidChangeBackingProperties];
    for (NSView *v in [[_subs copy] autorelease]) [v _mwBackingChanged];
}
- (void)setHidden:(BOOL)h {
    if (h == _hidden) return;
    _hidden = h;
    [_win _mwSetNeedsRender];
    if (_layer) _layer.hidden = h;
    if (h) [self viewDidHide]; else [self viewDidUnhide];
    if (_super) { _super.needsLayout = YES; }
}

/* ---------------------------------------------------------------- layers */
- (CALayer *)makeBackingLayer { return [CALayer layer]; }
- (void)setWantsLayer:(BOOL)f {
    _wantsLayer = f;
    if (f && !_layer) {
        _layer = [[self makeBackingLayer] retain];
        _backing = YES;
        _layer.frame = NSMakeRect(0, 0, _frame.size.width, _frame.size.height);
        _layer.delegate = self;
        [self _mwBindLayer];
    }
}
- (void)setLayer:(CALayer *)l {
    if (l == _layer) return;
    [l retain]; [_layer release]; _layer = l;
    _backing = NO;
    if (l && NSIsEmptyRect(l.frame)) l.frame = NSMakeRect(0, 0, _frame.size.width, _frame.size.height);
    [self _mwBindLayer];
}

/* ---------------------------------------------------------------- display and layout */
/* a Metal view's own content is not in the window bitmap: it redraws through Metal */
- (void)setNeedsDisplay:(BOOL)f { _needsDisplay = f; if (f && _win && ![_layer isKindOfClass:NSClassFromString(@"CAMetalLayer")]) [_win _mwSetNeedsRender]; }
- (void)setNeedsDisplayInRect:(NSRect)r { [self setNeedsDisplay:YES]; }
- (void)_mwClearNeedsDisplay { _needsDisplay = NO; for (NSView *v in _subs) [v _mwClearNeedsDisplay]; }
- (void)_mwLayerChanged { [_win _mwSetNeedsRender]; } /* our layer's background, corners, border or opacity changed */
- (void)setAlphaValue:(CGFloat)a { if (a == _alphaValue) return; _alphaValue = a; [_win _mwSetNeedsRender]; }
- (void)setNeedsLayout:(BOOL)f { _needsLayout = f; if (f) g_needs_update = YES; }
- (void)drawRect:(NSRect)r { }
- (void)updateLayer { }
- (void)display { [_win display]; }
- (void)displayRect:(NSRect)r { [_win display]; }
- (void)displayIfNeeded { [_win displayIfNeeded]; }
- (void)displayRectIgnoringOpacity:(NSRect)r { [_win display]; }
- (void)lockFocus { }
- (void)unlockFocus { }
- (void)layout { }
- (void)layoutSubtreeIfNeeded {
    static int depth;
    if (!depth++) mw_solve_layout(self); /* constraints first (whole subtree), then each view's -layout */
    if (_needsLayout) { _needsLayout = NO; [self layout]; }
    for (NSView *v in [[_subs copy] autorelease]) [v layoutSubtreeIfNeeded];
    depth--;
}
- (void)updateConstraints { }
- (void)updateConstraintsForSubtreeIfNeeded { }
- (void)setNeedsUpdateConstraints:(BOOL)f { }
- (NSArray *)constraints { return _cons ? [[_cons copy] autorelease] : @[]; }
- (void)addConstraint:(NSLayoutConstraint *)c { if (!_cons) _cons = [[NSMutableArray alloc] init]; if (c && ![_cons containsObject:c]) { [_cons addObject:c]; [(id)c _mwSetActiveFlag:YES]; self.needsLayout = YES; } }   /* adding activates (Cocoa) */
- (void)addConstraints:(NSArray *)a { for (NSLayoutConstraint *c in a) [self addConstraint:c]; }
- (void)removeConstraint:(NSLayoutConstraint *)c { if ([_cons containsObject:c]) [(id)c _mwSetActiveFlag:NO]; [_cons removeObjectIdenticalTo:c]; self.needsLayout = YES; }
- (void)removeConstraints:(NSArray *)a { for (NSLayoutConstraint *c in a) [self removeConstraint:c]; }
- (NSLayoutPriority)contentHuggingPriorityForOrientation:(NSLayoutConstraintOrientation)o {
    NSNumber *n = _prio[[NSString stringWithFormat:@"h%ld", (long)o]]; return n ? [n floatValue] : NSLayoutPriorityDefaultLow;
}
- (void)setContentHuggingPriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o {
    if (!_prio) _prio = [[NSMutableDictionary alloc] init];
    _prio[[NSString stringWithFormat:@"h%ld", (long)o]] = @(p);
}
- (NSLayoutPriority)contentCompressionResistancePriorityForOrientation:(NSLayoutConstraintOrientation)o {
    NSNumber *n = _prio[[NSString stringWithFormat:@"c%ld", (long)o]]; return n ? [n floatValue] : NSLayoutPriorityDefaultHigh;
}
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o {
    if (!_prio) _prio = [[NSMutableDictionary alloc] init];
    _prio[[NSString stringWithFormat:@"c%ld", (long)o]] = @(p);
}
- (void)invalidateIntrinsicContentSize { if (_super) _super.needsLayout = YES; }

/* ---------------------------------------------------------------- coordinates */
/* a point in this view -> its superview (or the window when there is none) */
- (NSPoint)_mwToSuper:(NSPoint)p {
    CGFloat dx = p.x - _bounds.origin.x, dy = p.y - _bounds.origin.y;
    CGFloat up = self.isFlipped ? _bounds.size.height - dy : dy;
    BOOL sf = _super && _super.isFlipped;
    return NSMakePoint(_frame.origin.x + dx, sf ? _frame.origin.y + _frame.size.height - up : _frame.origin.y + up);
}
- (NSPoint)_mwFromSuper:(NSPoint)q {
    BOOL sf = _super && _super.isFlipped;
    CGFloat dx = q.x - _frame.origin.x, up = sf ? _frame.size.height - (q.y - _frame.origin.y) : q.y - _frame.origin.y;
    return NSMakePoint(_bounds.origin.x + dx, _bounds.origin.y + (self.isFlipped ? _bounds.size.height - up : up));
}
- (NSPoint)_mwToWindow:(NSPoint)p { for (NSView *v = self; v; v = v->_super) p = [v _mwToSuper:p]; return p; }
- (NSPoint)_mwFromWindow:(NSPoint)p {
    NSMutableArray *chain = [NSMutableArray array];
    for (NSView *v = self; v; v = v->_super) [chain insertObject:v atIndex:0];
    for (NSView *v in chain) p = [v _mwFromSuper:p];
    return p;
}
- (NSPoint)convertPoint:(NSPoint)p fromView:(NSView *)v { return [self _mwFromWindow:v ? [v _mwToWindow:p] : p]; }
- (NSPoint)convertPoint:(NSPoint)p toView:(NSView *)v { NSPoint w = [self _mwToWindow:p]; return v ? [v _mwFromWindow:w] : w; }
- (NSSize)convertSize:(NSSize)s fromView:(NSView *)v { return s; }
- (NSSize)convertSize:(NSSize)s toView:(NSView *)v { return s; }
static NSRect rect_of(NSPoint a, NSPoint b) { return NSMakeRect(fmin(a.x, b.x), fmin(a.y, b.y), fabs(b.x - a.x), fabs(b.y - a.y)); }
- (NSRect)convertRect:(NSRect)r fromView:(NSView *)v {
    return rect_of([self convertPoint:r.origin fromView:v], [self convertPoint:NSMakePoint(NSMaxX(r), NSMaxY(r)) fromView:v]);
}
- (NSRect)convertRect:(NSRect)r toView:(NSView *)v {
    return rect_of([self convertPoint:r.origin toView:v], [self convertPoint:NSMakePoint(NSMaxX(r), NSMaxY(r)) toView:v]);
}
- (CGFloat)_mwScale { return _win ? _win.backingScaleFactor : mw_scale0(); }
- (NSRect)convertRectToBacking:(NSRect)r { CGFloat s = [self _mwScale]; return NSMakeRect(r.origin.x * s, r.origin.y * s, r.size.width * s, r.size.height * s); }
- (NSRect)convertRectFromBacking:(NSRect)r { CGFloat s = [self _mwScale]; return NSMakeRect(r.origin.x / s, r.origin.y / s, r.size.width / s, r.size.height / s); }
- (NSSize)convertSizeToBacking:(NSSize)z { CGFloat s = [self _mwScale]; return NSMakeSize(z.width * s, z.height * s); }
- (NSSize)convertSizeFromBacking:(NSSize)z { CGFloat s = [self _mwScale]; return NSMakeSize(z.width / s, z.height / s); }
- (NSPoint)convertPointToBacking:(NSPoint)p { CGFloat s = [self _mwScale]; return NSMakePoint(p.x * s, p.y * s); }
- (NSPoint)convertPointFromBacking:(NSPoint)p { CGFloat s = [self _mwScale]; return NSMakePoint(p.x / s, p.y / s); }
- (NSRect)backingAlignedRect:(NSRect)r options:(NSAlignmentOptions)o { return [self convertRectFromBacking:NSIntegralRect([self convertRectToBacking:r])]; }

/* ---------------------------------------------------------------- events */
- (NSView *)hitTest:(NSPoint)p {
    if (_hidden) return nil;
    BOOL sf = _super ? _super.isFlipped : NO;
    if (!NSMouseInRect(p, _frame, sf)) return nil;
    NSPoint local = [self _mwFromSuper:p];
    for (NSView *v in [_subs reverseObjectEnumerator]) { NSView *h = [v hitTest:local]; if (h) return h; }
    return self;
}
- (BOOL)mouse:(NSPoint)p inRect:(NSRect)r { return NSMouseInRect(p, r, self.isFlipped); }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return NO; }
- (NSMenu *)menuForEvent:(NSEvent *)e { return [self menu]; }
- (void)rightMouseDown:(NSEvent *)e { /* the view's context menu, like AppKit */
    NSMenu *m = [self menuForEvent:e];
    if (m) [NSMenu popUpContextMenu:m withEvent:e forView:self]; else [super rightMouseDown:e];
}
- (BOOL)performKeyEquivalent:(NSEvent *)e {
    for (NSView *v in [[_subs copy] autorelease]) if ([v performKeyEquivalent:e]) return YES;
    return NO;
}
- (NSArray *)trackingAreas { return _areas ? [[_areas copy] autorelease] : @[]; }
- (void)addTrackingArea:(NSTrackingArea *)a { if (!_areas) _areas = [[NSMutableArray alloc] init]; [_areas addObject:a]; }
- (void)removeTrackingArea:(NSTrackingArea *)a { [_areas removeObjectIdenticalTo:a]; }
- (void)updateTrackingAreas { }
- (void)addCursorRect:(NSRect)r cursor:(NSCursor *)c { }
- (void)removeCursorRect:(NSRect)r cursor:(NSCursor *)c { }
- (void)discardCursorRects { }
- (void)resetCursorRects { }
- (BOOL)enterFullScreenMode:(NSScreen *)s withOptions:(NSDictionary *)o { if (!(_win.styleMask & NSWindowStyleMaskFullScreen)) [_win toggleFullScreen:nil]; return YES; }
- (void)exitFullScreenModeWithOptions:(NSDictionary *)o { if (_win.styleMask & NSWindowStyleMaskFullScreen) [_win toggleFullScreen:nil]; }
- (BOOL)isInFullScreenMode { return (_win.styleMask & NSWindowStyleMaskFullScreen) != 0; }
- (NSBitmapImageRep *)bitmapImageRepForCachingDisplayInRect:(NSRect)r {
    CGFloat s = [self _mwScale];
    NSBitmapImageRep *b = [[[NSBitmapImageRep alloc] _mwInitWidth:(size_t)lround(r.size.width * s) height:(size_t)lround(r.size.height * s)] autorelease];
    b.size = r.size;
    return b;
}
- (void)cacheDisplayInRect:(NSRect)r toBitmapImageRep:(NSBitmapImageRep *)b { [self layoutSubtreeIfNeeded]; mw_cache_display(self, r, b); }
- (void)registerForDraggedTypes:(NSArray *)t { }
- (void)unregisterDraggedTypes { }
@end
