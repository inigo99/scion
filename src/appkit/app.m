/* app.m — NSApplication (event loop), NSEvent, NSResponder, NSScreen, NSCursor.
 * Host window events arrive through UI_NEXT_EVENT. The run loop pumps them on every pass (_scion_ui_pump): input becomes
 * NSEvents sent with -sendEvent: (or queued for -nextEventMatchingMask: when the app pulls events itself); window changes
 * (resize, focus, close...) become delegate calls and notifications, like AppKit does inside its event loop. */
#import "internal.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int (*_scion_ui_pump)(void);
extern void (*_scion_main_wake)(void);

NSApplication *NSApp;
static NSMutableArray *g_queue;          /* NSEvents waiting for -nextEventMatchingMask: */
static int g_collect;                    /* > 0: inside -nextEventMatchingMask:, queue input instead of sending it */
static NSEventModifierFlags g_mods;
static int32_t g_delta[2];               /* CGGetLastMouseDelta */
static NSMutableArray *g_monitors;       /* local monitors: [mask, handler] */

/* ======================================================================= screens */
static NSMutableArray *g_screens;
static CGFloat g_s0 = 1, g_h0 = 768;
@interface NSScreen () { @public MwScreen _s; NSRect _frame, _visible; CGFloat _scale; } @end
static void load_screens(void) {
    NSMutableArray *a = [NSMutableArray array];
    MwScreen s;
    int64_t n = ui(UI_SCREEN, 0, U(&s), 0, 0, 0);
    if (n <= 0) { memset(&s, 0, sizeof s); s.w = s.vw = 1280; s.h = s.vh = 800; s.dpi = 96; s.refresh_mhz = 60000; strcpy(s.name, "Display"); n = 1; }
    g_s0 = s.dpi ? s.dpi / 96.0 : 1;
    g_h0 = s.h / g_s0;
    for (int64_t i = 0; i < n; i++) {
        if (i && ui(UI_SCREEN, (uint64_t)i, U(&s), 0, 0, 0) <= i) break;
        NSScreen *sc = [[NSScreen alloc] init];
        sc->_s = s;
        sc->_scale = s.dpi ? s.dpi / 96.0 : 1;
        sc->_frame = NSMakeRect(s.x / g_s0, g_h0 - s.y / g_s0 - s.h / sc->_scale, s.w / sc->_scale, s.h / sc->_scale);
        sc->_visible = NSMakeRect(s.vx / g_s0, g_h0 - s.vy / g_s0 - s.vh / sc->_scale, s.vw / sc->_scale, s.vh / sc->_scale);
        [a addObject:sc];
        [sc release];
    }
    [g_screens release];
    g_screens = [a retain];
}
CGFloat mw_scale0(void) { if (!g_screens) load_screens(); return g_s0; }
CGFloat mw_height0(void) { if (!g_screens) load_screens(); return g_h0; }
void mw_screens_changed(void) {
    load_screens();
    [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationDidChangeScreenParametersNotification object:NSApp];
}

@implementation NSScreen
+ (NSArray *)screens { if (!g_screens) load_screens(); return [[g_screens copy] autorelease]; }
+ (NSScreen *)mainScreen {
    NSWindow *k = [NSApp keyWindow];
    if (k && k.screen) return k.screen;
    if (!g_screens) load_screens();
    return [g_screens firstObject];
}
+ (NSScreen *)deepestScreen { return [self mainScreen]; }
+ (BOOL)screensHaveSeparateSpaces { return NO; }
- (NSRect)frame { return _frame; }
- (NSRect)visibleFrame { return _visible; }
- (CGFloat)backingScaleFactor { return _scale; }
- (NSString *)localizedName { return [NSString stringWithUTF8String:_s.name]; }
- (NSDictionary *)deviceDescription {
    return @{@"NSScreenNumber": @((uint32_t)([g_screens indexOfObjectIdenticalTo:self] + 1)), NSDeviceSize: [NSValue valueWithSize:_frame.size],
             NSDeviceResolution: [NSValue valueWithSize:NSMakeSize(72 * _scale, 72 * _scale)], NSDeviceIsScreen: @"YES"};
}
- (NSInteger)maximumFramesPerSecond { return (NSInteger)((_s.refresh_mhz + 500) / 1000); }
- (NSTimeInterval)minimumRefreshInterval { return 1000.0 / (_s.refresh_mhz ? _s.refresh_mhz : 60000); }
- (NSTimeInterval)maximumRefreshInterval { return [self minimumRefreshInterval]; }
- (NSTimeInterval)displayUpdateGranularity { return 0; }
- (NSEdgeInsets)safeAreaInsets { return NSEdgeInsetsZero; }
- (CGFloat)maximumExtendedDynamicRangeColorComponentValue { return 1; }
- (CGFloat)maximumPotentialExtendedDynamicRangeColorComponentValue { return 1; }
- (NSRect)convertRectToBacking:(NSRect)r { return NSMakeRect(r.origin.x * _scale, r.origin.y * _scale, r.size.width * _scale, r.size.height * _scale); }
- (NSRect)convertRectFromBacking:(NSRect)r { return NSMakeRect(r.origin.x / _scale, r.origin.y / _scale, r.size.width / _scale, r.size.height / _scale); }
- (CGFloat)backingAlignedRect:(NSRect)r options:(NSAlignmentOptions)o { return 0; }
- (uint32_t)_mwDisplayID { return (uint32_t)([g_screens indexOfObjectIdenticalTo:self] + 1); }
@end

/* ======================================================================= NSEvent */
@interface NSEvent () {
@public
    NSEventType _type; NSEventModifierFlags _mods; NSTimeInterval _ts; NSWindow *_win; NSPoint _loc;
    NSInteger _button, _clicks, _data1, _data2; short _subtype;
    CGFloat _dx, _dy, _sdx, _sdy; BOOL _precise, _repeat; unsigned short _key; NSString *_chars, *_nomod; NSTrackingArea *_area;
}
@end
@implementation NSEvent
- (void)dealloc { [_win release]; [_chars release]; [_nomod release]; [_area release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSEventType)type { return _type; }
- (NSEventModifierFlags)modifierFlags { return _mods; }
- (NSTimeInterval)timestamp { return _ts; }
- (NSWindow *)window { return _win; }
- (NSInteger)windowNumber { return _win ? _win.windowNumber : 0; }
- (NSPoint)locationInWindow { return _loc; }
- (NSInteger)buttonNumber { return _button; }
- (NSInteger)clickCount { return _clicks; }
- (float)pressure { return (_type == NSEventTypeLeftMouseDown || _type == NSEventTypeLeftMouseDragged) ? 1 : 0; }
- (CGFloat)deltaX { return _dx; }
- (CGFloat)deltaY { return _dy; }
- (CGFloat)deltaZ { return 0; }
- (CGFloat)scrollingDeltaX { return _sdx; }
- (CGFloat)scrollingDeltaY { return _sdy; }
- (CGFloat)magnification { return 0; }
- (CGFloat)rotation { return 0; }
- (BOOL)hasPreciseScrollingDeltas { return _precise; }
- (BOOL)isDirectionInvertedFromDevice { return NO; }
- (NSEventPhase)phase { return NSEventPhaseNone; }
- (NSEventPhase)momentumPhase { return NSEventPhaseNone; }
- (unsigned short)keyCode { return _key; }
- (NSString *)characters { return _chars; }
- (NSString *)charactersIgnoringModifiers { return _nomod; }
- (BOOL)isARepeat { return _repeat; }
- (NSEventSubtype)subtype { return _subtype; }
- (NSInteger)data1 { return _data1; }
- (NSInteger)data2 { return _data2; }
- (NSInteger)eventNumber { return 0; }
- (NSInteger)trackingNumber { return 0; }
- (NSTrackingArea *)trackingArea { return _area; }
- (void *)userData { return [_area userInfo]; }
- (void *)CGEvent { return NULL; }
- (NSString *)description { return [NSString stringWithFormat:@"NSEvent: type=%lu loc=(%g,%g) flags=0x%lx keyCode=%u chars=\"%@\"",
                                       (unsigned long)_type, _loc.x, _loc.y, (unsigned long)_mods, _key, _chars ? _chars : @""]; }

+ (NSPoint)mouseLocation {
    int32_t p[2] = {0, 0};
    ui(UI_MOUSE_POS, U(p), 0, 0, 0, 0);
    return NSMakePoint(p[0] / mw_scale0(), mw_height0() - p[1] / mw_scale0());
}
+ (NSEventModifierFlags)modifierFlags { return g_mods; }
+ (NSUInteger)pressedMouseButtons { int32_t p[2]; return (NSUInteger)ui(UI_MOUSE_POS, U(p), 0, 0, 0, 0); }
+ (NSTimeInterval)doubleClickInterval { return 0.5; }
+ (NSTimeInterval)keyRepeatDelay { return 0.5; }
+ (NSTimeInterval)keyRepeatInterval { return 0.033; }
+ (BOOL)isMouseCoalescingEnabled { return YES; }
+ (void)setMouseCoalescingEnabled:(BOOL)f { }
+ (id)addLocalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(NSEvent * (^)(NSEvent *))h {
    if (!g_monitors) g_monitors = [[NSMutableArray alloc] init];
    id b = [h copy];
    NSArray *m = [NSArray arrayWithObjects:[NSNumber numberWithUnsignedLongLong:mask], b, nil];
    [b release];
    [g_monitors addObject:m];
    return m;
}
+ (id)addGlobalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(void (^)(NSEvent *))h { return [[[NSObject alloc] init] autorelease]; } /* events of other apps: none */
+ (void)removeMonitor:(id)m { [g_monitors removeObjectIdenticalTo:m]; }
static NSEvent *make(NSEventType t, NSPoint p, NSEventModifierFlags f, NSTimeInterval ts, NSInteger wn) {
    NSEvent *e = [[[NSEvent alloc] init] autorelease];
    e->_type = t; e->_loc = p; e->_mods = f; e->_ts = ts; e->_win = [[NSApp windowWithWindowNumber:wn] retain];
    return e;
}
+ (NSEvent *)keyEventWithType:(NSEventType)t location:(NSPoint)p modifierFlags:(NSEventModifierFlags)f timestamp:(NSTimeInterval)ts
    windowNumber:(NSInteger)w context:(id)c characters:(NSString *)ch charactersIgnoringModifiers:(NSString *)chn isARepeat:(BOOL)r keyCode:(unsigned short)k {
    NSEvent *e = make(t, p, f, ts, w);
    e->_chars = [ch copy]; e->_nomod = [chn copy]; e->_repeat = r; e->_key = k;
    return e;
}
+ (NSEvent *)mouseEventWithType:(NSEventType)t location:(NSPoint)p modifierFlags:(NSEventModifierFlags)f timestamp:(NSTimeInterval)ts
    windowNumber:(NSInteger)w context:(id)c eventNumber:(NSInteger)n clickCount:(NSInteger)cc pressure:(float)pr {
    NSEvent *e = make(t, p, f, ts, w);
    e->_clicks = cc;
    e->_button = t == NSEventTypeRightMouseDown || t == NSEventTypeRightMouseUp || t == NSEventTypeRightMouseDragged ? 1
               : t == NSEventTypeOtherMouseDown || t == NSEventTypeOtherMouseUp || t == NSEventTypeOtherMouseDragged ? 2 : 0;
    return e;
}
+ (NSEvent *)otherEventWithType:(NSEventType)t location:(NSPoint)p modifierFlags:(NSEventModifierFlags)f timestamp:(NSTimeInterval)ts
    windowNumber:(NSInteger)w context:(id)c subtype:(short)s data1:(NSInteger)d1 data2:(NSInteger)d2 {
    NSEvent *e = make(t, p, f, ts, w);
    e->_subtype = s; e->_data1 = d1; e->_data2 = d2;
    return e;
}
+ (void)startPeriodicEventsAfterDelay:(NSTimeInterval)d withPeriod:(NSTimeInterval)p { }
+ (void)stopPeriodicEvents { }
@end

static NSString *str16(const char *s) { return [NSString stringWithUTF8String:s] ? [NSString stringWithUTF8String:s] : @""; }

/* host event -> NSEvent (input only; nil for window events) */
NSEvent *mw_event_from_host(const MwEvent *h, NSWindow *w) {
    NSEvent *e = [[[NSEvent alloc] init] autorelease];
    CGFloat sc = w ? w.backingScaleFactor : 1;
    NSRect content = w ? [w contentRectForFrameRect:w.frame] : NSZeroRect;
    e->_win = [w retain];
    e->_ts = h->time_ns / 1e9;
    e->_mods = h->modifiers;
    e->_loc = NSMakePoint(h->x / sc, content.size.height - h->y / sc);
    switch (h->type) {
    case UI_EV_KEY_DOWN: case UI_EV_KEY_UP:
        e->_type = h->type == UI_EV_KEY_DOWN ? NSEventTypeKeyDown : NSEventTypeKeyUp;
        e->_key = (unsigned short)h->keycode; e->_repeat = h->a != 0;
        e->_chars = [str16(h->chars) retain]; e->_nomod = [str16(h->chars_nomod) retain];
        e->_loc = NSZeroPoint;
        /* Windows convention: Ctrl+key runs the menu's Command+key shortcut */
        if (e->_type == NSEventTypeKeyDown && (e->_mods & NSEventModifierFlagControl) && !(e->_mods & NSEventModifierFlagCommand)) {
            NSEventModifierFlags m = (e->_mods & ~(NSEventModifierFlags)NSEventModifierFlagControl) | NSEventModifierFlagCommand;
            if (mw_menu_has_key_equivalent(e->_nomod, m)) e->_mods = m;
        }
        return e;
    case UI_EV_FLAGS: e->_type = NSEventTypeFlagsChanged; e->_key = (unsigned short)h->keycode; e->_loc = NSZeroPoint; return e;
    case UI_EV_MOUSE_DOWN: case UI_EV_MOUSE_UP: {
        BOOL down = h->type == UI_EV_MOUSE_DOWN;
        e->_button = h->button; e->_clicks = h->clicks;
        e->_type = h->button == 0 ? (down ? NSEventTypeLeftMouseDown : NSEventTypeLeftMouseUp)
                 : h->button == 1 ? (down ? NSEventTypeRightMouseDown : NSEventTypeRightMouseUp)
                                  : (down ? NSEventTypeOtherMouseDown : NSEventTypeOtherMouseUp);
        return e;
    }
    case UI_EV_MOUSE_MOVE:
        e->_dx = h->dx / sc; e->_dy = h->dy / sc;   /* deltaY grows downwards, like CoreGraphics */
        g_delta[0] += (int32_t)h->dx; g_delta[1] += (int32_t)h->dy;
        e->_type = (h->b & 1) ? NSEventTypeLeftMouseDragged : (h->b & 2) ? NSEventTypeRightMouseDragged
                 : (h->b & 4) ? NSEventTypeOtherMouseDragged : NSEventTypeMouseMoved;
        e->_button = (h->b & 1) ? 0 : (h->b & 2) ? 1 : (h->b & 4) ? 2 : 0;
        return e;
    case UI_EV_SCROLL:
        e->_type = NSEventTypeScrollWheel;
        e->_dx = e->_sdx = h->dx; e->_dy = e->_sdy = h->dy; e->_precise = h->b != 0; /* lines (a wheel notch is one) */
        return e;
    }
    return nil;
}

void mw_event_set_area(NSEvent *e, NSTrackingArea *a) { [a retain]; [e->_area release]; e->_area = a; }
void mw_get_last_mouse_delta(int32_t *dx, int32_t *dy) { if (dx) *dx = g_delta[0]; if (dy) *dy = g_delta[1]; g_delta[0] = g_delta[1] = 0; }

/* ======================================================================= the pump */
NSEvent *mw_run_event_monitors(NSEvent *e) {
    for (NSArray *m in [[g_monitors copy] autorelease]) {
        if (!([[m objectAtIndex:0] unsignedLongLongValue] & NSEventMaskFromType(e.type))) continue;
        NSEvent *(^h)(NSEvent *) = [m objectAtIndex:1];
        e = h(e);
        if (!e) return nil;
    }
    [NSApp performSelector:@selector(_mwSetCurrentEvent:) withObject:e];
    return e;
}
static void dispatch_input(NSEvent *e) {
    if (g_collect) { if (!g_queue) g_queue = [[NSMutableArray alloc] init]; [g_queue addObject:e]; }
    else [NSApp sendEvent:e];
}
static BOOL g_check_active;
static void handle(const MwEvent *h) {
    if (h->type == UI_EV_MENU || h->type == UI_EV_MENU_OPEN) { mw_menu_event(h); return; }
    if (h->type == UI_EV_QUIT) { [NSApp terminate:nil]; return; }
    if (h->type == UI_EV_STATUS) { mw_status_event(h); return; }
    NSWindow *w = mw_window_by_id(h->window);
    if (h->type != UI_EV_FOCUS) g_mods = h->modifiers;
    NSEvent *e = mw_event_from_host(h, w);
    if (e && w) { dispatch_input(e); return; }
    if (e) return;
    if (h->type == UI_EV_FOCUS && !h->a) g_check_active = YES;
    if (h->type == UI_EV_DPI) load_screens();
    if (w) mw_window_event(w, h);
}
static int pump(void) {
    int n = 0;
    MwEvent h;
    while (ui(UI_NEXT_EVENT, U(&h), 0, 0, 0, 0) == 1) { handle(&h); n++; }
    if (g_check_active) { /* focus may just be moving between two of our windows */
        g_check_active = NO;
        if (![NSApp keyWindow] && [NSApp isActive]) [NSApp performSelector:@selector(_mwSetActive:) withObject:nil];
    }
    mw_menu_sync();
    mw_windows_update();
    return n;
}
static void main_wake(void) { ui(UI_WAKE, 0, 0, 0, 0, 0); }
void mw_app_activate(void) {
    if (_scion_ui_pump) return;
    _scion_main_wake = main_wake;
    _scion_ui_pump = pump;
}

/* ======================================================================= NSResponder */
@implementation NSResponder
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)becomeFirstResponder { return YES; }
- (BOOL)resignFirstResponder { return YES; }
#define FORWARD(sel) - (void)sel:(NSEvent *)e { if (_nextResponder) [_nextResponder sel:e]; else [self noResponderFor:@selector(sel:)]; }
FORWARD(mouseDown) FORWARD(mouseUp) FORWARD(mouseDragged) FORWARD(mouseMoved) FORWARD(rightMouseDown) FORWARD(rightMouseUp)
FORWARD(rightMouseDragged) FORWARD(otherMouseDown) FORWARD(otherMouseUp) FORWARD(otherMouseDragged) FORWARD(mouseEntered)
FORWARD(mouseExited) FORWARD(scrollWheel) FORWARD(keyDown) FORWARD(keyUp) FORWARD(flagsChanged) FORWARD(cursorUpdate)
FORWARD(magnifyWithEvent) FORWARD(rotateWithEvent) FORWARD(swipeWithEvent) FORWARD(pressureChangeWithEvent)
#undef FORWARD
- (BOOL)performKeyEquivalent:(NSEvent *)e { return NO; }
- (void)noResponderFor:(SEL)s { } /* AppKit beeps for an unhandled keyDown: */
- (void)interpretKeyEvents:(NSArray *)events {
    for (NSEvent *e in events) {
        NSString *c = e.characters;
        if (![c length]) continue;
        unichar ch = [c characterAtIndex:0];
        SEL s = 0;
        switch (ch) {
        case '\r': case 3: s = @selector(insertNewline:); break;
        case '\t': s = @selector(insertTab:); break;
        case 0x1b: s = @selector(cancelOperation:); break;
        case 0x7f: s = @selector(deleteBackward:); break;
        case 0xF700: s = @selector(moveUp:); break;
        case 0xF701: s = @selector(moveDown:); break;
        case 0xF702: s = @selector(moveLeft:); break;
        case 0xF703: s = @selector(moveRight:); break;
        case 0xF728: s = @selector(deleteForward:); break;
        }
        if (s) [self doCommandBySelector:s];
        else if (ch >= 0x20 && (ch < 0xF700 || ch > 0xF8FF)) {
            if ([self respondsToSelector:@selector(insertText:replacementRange:)]) [(id)self insertText:c replacementRange:NSMakeRange(NSNotFound, 0)];
            else [self insertText:c];
        }
    }
}
- (void)insertText:(id)s { if (_nextResponder) [_nextResponder insertText:s]; }
- (void)doCommandBySelector:(SEL)s { if ([self respondsToSelector:s]) [self performSelector:s withObject:nil]; else if (_nextResponder) [_nextResponder doCommandBySelector:s]; }
- (BOOL)tryToPerform:(SEL)s with:(id)o {
    if ([self respondsToSelector:s]) { [self performSelector:s withObject:o]; return YES; }
    return [_nextResponder tryToPerform:s with:o];
}
- (id)validRequestorForSendType:(NSPasteboardType)s returnType:(NSPasteboardType)r { return [_nextResponder validRequestorForSendType:s returnType:r]; }
- (BOOL)presentError:(NSError *)e { NSLog(@"%@", e); return NO; }
- (void)flushBufferedKeyEvents { }
- (NSMenu *)menu { return objc_getAssociatedObject(self, "mw_menu"); }
- (void)setMenu:(NSMenu *)m { objc_setAssociatedObject(self, "mw_menu", m, 1 /* retain nonatomic */); }
@end

/* ======================================================================= NSApplication */
@interface NSApplication () { BOOL _launched, _active, _hidden, _stop, _running; NSApplicationActivationPolicy _policy; NSEvent *_current; NSInteger _modal; } @end
@implementation NSApplication
+ (NSApplication *)sharedApplication {
    if (!NSApp) { NSApp = [[self alloc] init]; mw_app_activate(); }
    return NSApp;
}
- (void)dealloc { [_current release]; [super dealloc]; }
- (NSArray *)windows { return [[g_windows_list() copy] autorelease]; }
- (NSArray *)orderedWindows { return [self windows]; }
- (NSWindow *)windowWithWindowNumber:(NSInteger)n { for (NSWindow *w in g_windows_list()) if (w.windowNumber == n) return w; return nil; }
- (NSWindow *)keyWindow { for (NSWindow *w in g_windows_list()) if (w.isKeyWindow) return w; return nil; }
- (NSWindow *)mainWindow { return [self keyWindow]; }
- (NSWindow *)modalWindow { return objc_getAssociatedObject(self, "mw_modal_window"); }
- (NSEvent *)currentEvent { return _current; }
- (BOOL)isActive { return _active; }
- (BOOL)isHidden { return _hidden; }
- (BOOL)isRunning { return _running; }
- (NSAppearance *)effectiveAppearance { return _appearance ? _appearance : [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; }
- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection { return NSUserInterfaceLayoutDirectionLeftToRight; }
- (NSWindowOcclusionState)occlusionState { return NSWindowOcclusionStateVisible; }
- (NSApplicationPresentationOptions)currentSystemPresentationOptions { return _presentationOptions; }
- (NSApplicationActivationPolicy)activationPolicy { return _policy; }
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p { _policy = p; return YES; }
- (void)setMainMenu:(NSMenu *)m { [m retain]; [_mainMenu release]; _mainMenu = m; mw_menu_mark_dirty(); }
- (void)setDelegate:(id<NSApplicationDelegate>)d {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_delegate) [nc removeObserver:_delegate name:nil object:self];
    _delegate = d;
    static const struct { const char *sel; NSString *const *name; } map[] = {
        {"applicationWillFinishLaunching:", &NSApplicationWillFinishLaunchingNotification}, {"applicationDidFinishLaunching:", &NSApplicationDidFinishLaunchingNotification},
        {"applicationWillTerminate:", &NSApplicationWillTerminateNotification}, {"applicationDidBecomeActive:", &NSApplicationDidBecomeActiveNotification},
        {"applicationDidResignActive:", &NSApplicationDidResignActiveNotification}, {"applicationWillBecomeActive:", &NSApplicationWillBecomeActiveNotification},
        {"applicationWillResignActive:", &NSApplicationWillResignActiveNotification}, {"applicationDidHide:", &NSApplicationDidHideNotification},
        {"applicationDidUnhide:", &NSApplicationDidUnhideNotification}, {"applicationDidChangeScreenParameters:", &NSApplicationDidChangeScreenParametersNotification},
    };
    for (unsigned i = 0; d && i < sizeof map / sizeof *map; i++) {
        SEL s = sel_registerName(map[i].sel);
        if ([(id)d respondsToSelector:s]) [nc addObserver:d selector:s name:*map[i].name object:self];
    }
}
- (void)_mwSetActive:(id)on {
    BOOL a = on != nil;
    if (a == _active) return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:a ? NSApplicationWillBecomeActiveNotification : NSApplicationWillResignActiveNotification object:self];
    _active = a;
    [nc postNotificationName:a ? NSApplicationDidBecomeActiveNotification : NSApplicationDidResignActiveNotification object:self];
}
- (void)activateIgnoringOtherApps:(BOOL)f { [[self keyWindow] makeKeyAndOrderFront:nil]; }
- (void)activate { [self activateIgnoringOtherApps:YES]; }
- (void)deactivate { }
- (void)yieldActivationToApplication:(NSRunningApplication *)a { }
- (void)finishLaunching {
    if (_launched) return;
    _launched = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:NSApplicationWillFinishLaunchingNotification object:self];
    [nc postNotificationName:NSApplicationDidFinishLaunchingNotification object:self];
    mw_open_launch_documents();
    /* SCION_TEST_GUI=<s>: smoke test for GUI apps; after <s> seconds of running, report the windows and quit */
    const char *t = getenv("SCION_TEST_GUI");
    /* SCION_TEST_CLICK=<s>: a left click on the first status item after <s> seconds (its popover counts as a window) */
    const char *k = getenv("SCION_TEST_CLICK");
    if (k && atof(k) > 0) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(atof(k) * 1e9)), dispatch_get_main_queue(), ^{ mw_status_test_click(0); });
    if (t && atof(t) > 0)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(atof(t) * 1e9)), dispatch_get_main_queue(), ^{
            NSUInteger n = 0; NSMutableString *titles = [NSMutableString string];
            for (NSWindow *w in self.windows) if (w.isVisible) {
                n++; [titles appendFormat:@" \"%@\"", w.title];
                if (getenv("SCION_TEST_FRAMES")) [titles appendFormat:@" %@ (%@)", NSStringFromRect(w.frame), NSStringFromRect(w.contentView.frame)];
            }
            NSDocument *d = [mw_document_controller_if_any() currentDocument] ?: [[mw_document_controller_if_any() documents] firstObject];
            printf("APP OK: %lu visible windows%s; documents: %lu%s%s%s\n", (unsigned long)n, [titles UTF8String],
                   (unsigned long)[[mw_document_controller_if_any() documents] count], d ? ", " : "", d ? [[d displayName] UTF8String] : "",
                   [mw_status_report() UTF8String]);
            fflush(stdout);
            exit(0);
        });
}
- (void)run {
    [self finishLaunching];
    _running = YES; _stop = NO;
    while (!_stop) {
        void *pool = objc_autoreleasePoolPush();
        NSEvent *e = [self nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture] inMode:NSDefaultRunLoopMode dequeue:YES];
        if (e) [self sendEvent:e];
        objc_autoreleasePoolPop(pool);
    }
    _running = NO;
}
- (void)stop:(id)s { _stop = YES; main_wake(); }
- (void)terminate:(id)s {
    if ([(id)_delegate respondsToSelector:@selector(applicationShouldTerminate:)] && [_delegate applicationShouldTerminate:self] != NSTerminateNow) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationWillTerminateNotification object:self];
    [[NSUserDefaults standardUserDefaults] synchronize];
    exit(0);
}
- (void)replyToApplicationShouldTerminate:(BOOL)f { if (f) { _delegate = nil; [self terminate:nil]; } }
- (void)hide:(id)s { for (NSWindow *w in g_windows_list()) if (w.isVisible) [w miniaturize:nil]; _hidden = YES; }
- (void)unhide:(id)s { for (NSWindow *w in g_windows_list()) if (w.isMiniaturized) [w deminiaturize:nil]; _hidden = NO; }
- (void)unhideWithoutActivation { [self unhide:nil]; }
- (void)hideOtherApplications:(id)s { }
- (void)unhideAllApplications:(id)s { }
- (NSEvent *)nextEventMatchingMask:(NSEventMask)mask untilDate:(NSDate *)until inMode:(NSRunLoopMode)mode dequeue:(BOOL)dq {
    NSTimeInterval deadline = until ? [until timeIntervalSinceReferenceDate] : 0;
    NSRunLoop *rl = [NSRunLoop currentRunLoop];
    g_collect++;
    NSEvent *found = nil;
    for (;;) {
        /* a pool per pass: with no input the loop can run timers and redraw windows for hours before returning
         * (each redraw autoreleases its bitmap context: 2 MB for a 960x540 window) */
        void *pool = objc_autoreleasePoolPush();
        [rl _passInMode:mode]; /* timers of this mode, the main queue and (through the pump hook) window events */
        for (NSEvent *e in g_queue)
            if (mask & NSEventMaskFromType([e type])) { found = [e retain]; if (dq) [g_queue removeObjectIdenticalTo:e]; break; }
        NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
        if (found || t >= deadline || _stop) { objc_autoreleasePoolPop(pool); break; }
        NSTimeInterval wait = fmin(deadline, [rl _nextTimer]) - t;
        if (wait > 0.05) wait = 0.05;  /* ponytail: wake at least every 50 ms (sources the wake hook does not cover) */
        MwEvent h;
        if (wait > 0 && ui(UI_NEXT_EVENT, U(&h), (uint64_t)(wait * 1e9), 0, 0, 0) == 1) { handle(&h); }
        objc_autoreleasePoolPop(pool);
    }
    [found autorelease];
    g_collect--;
    if (found && dq) { [_current release]; _current = [found retain]; }
    return found;
}
- (void)discardEventsMatchingMask:(NSEventMask)m beforeEvent:(NSEvent *)e {
    for (NSInteger i = (NSInteger)[g_queue count] - 1; i >= 0; i--)
        if (m & NSEventMaskFromType([(NSEvent *)[g_queue objectAtIndex:(NSUInteger)i] type])) [g_queue removeObjectAtIndex:(NSUInteger)i];
}
- (void)postEvent:(NSEvent *)e atStart:(BOOL)f {
    if (!g_queue) g_queue = [[NSMutableArray alloc] init];
    if (f) [g_queue insertObject:e atIndex:0]; else [g_queue addObject:e];
    main_wake();
}
- (void)_mwSetCurrentEvent:(NSEvent *)e { if (e != _current) { [_current release]; _current = [e retain]; } }
- (void)sendEvent:(NSEvent *)e {
    if (!(e = mw_run_event_monitors(e))) return;
    if (e.type == NSEventTypeKeyDown && (e.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
        if ([e.window performKeyEquivalent:e]) return;
        if ([_mainMenu performKeyEquivalent:e]) return;
    }
    if (e.type == NSEventTypeApplicationDefined || !e.window) return;
    [e.window sendEvent:e];
}
- (id)targetForAction:(SEL)a { return [self targetForAction:a to:nil from:nil]; }
- (id)targetForAction:(SEL)a to:(id)t from:(id)s {
    if (!a) return nil;
    if (t) return [t respondsToSelector:a] ? t : nil;
    NSWindow *k = [self keyWindow];
    for (NSResponder *r = k.firstResponder; r; r = r.nextResponder) if ([r respondsToSelector:a]) return r;
    if (k && [k respondsToSelector:a]) return k;
    if ([(id)k.delegate respondsToSelector:a]) return k.delegate;
    if ([k.windowController respondsToSelector:a]) return k.windowController;
    id doc = k.windowController.document;
    if ([doc respondsToSelector:a]) return doc;
    if ([self respondsToSelector:a]) return self;
    if ([(id)_delegate respondsToSelector:a]) return _delegate;
    id dc = mw_document_controller_if_any();
    if ([dc respondsToSelector:a]) return dc;
    return nil;
}
- (BOOL)sendAction:(SEL)a to:(id)t from:(id)s {
    id target = [self targetForAction:a to:t from:s];
    if (!target) return NO;
    [target performSelector:a withObject:s];
    return YES;
}
- (BOOL)tryToPerform:(SEL)a with:(id)o {
    if ([self respondsToSelector:a]) { [self performSelector:a withObject:o]; return YES; }
    if ([(id)_delegate respondsToSelector:a]) { [(id)_delegate performSelector:a withObject:o]; return YES; }
    return NO;
}
- (BOOL)validateUserInterfaceItem:(id)i { return YES; }
- (void)updateWindows { }
- (void)setWindowsNeedUpdate:(BOOL)f { }
- (void)miniaturizeAll:(id)s { for (NSWindow *w in g_windows_list()) [w miniaturize:s]; }
- (void)arrangeInFront:(id)s { }
- (NSModalResponse)runModalForWindow:(NSWindow *)w {
    [w _mwSetNoMenu:YES];
    [w makeKeyAndOrderFront:nil];
    NSWindow *outer = [[self.modalWindow retain] autorelease];
    objc_setAssociatedObject(self, "mw_modal_window", w, OBJC_ASSOCIATION_RETAIN);
    NSInteger mine = ++_modal;
    _stop = NO;
    while (_modal >= mine && w.isVisible) {
        void *pool = objc_autoreleasePoolPush();
        NSEvent *e = [self nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture] inMode:NSModalPanelRunLoopMode dequeue:YES];
        if (e) [self sendEvent:e];
        objc_autoreleasePoolPop(pool);
    }
    NSModalResponse r = (NSModalResponse)objc_getAssociatedObject(self, "mw_modal");
    if (_modal >= mine) _modal = mine - 1;
    objc_setAssociatedObject(self, "mw_modal_window", outer, OBJC_ASSOCIATION_RETAIN);
    return r ? r : NSModalResponseStop;
}
- (void)stopModal { [self stopModalWithCode:NSModalResponseStop]; }
- (void)stopModalWithCode:(NSModalResponse)c { objc_setAssociatedObject(self, "mw_modal", (id)c, 0); if (_modal) _modal--; main_wake(); }
- (void)abortModal { [self stopModalWithCode:NSModalResponseAbort]; }
- (NSInteger)requestUserAttention:(NSRequestUserAttentionType)t { return 0; }
- (void)cancelUserAttentionRequest:(NSInteger)r { }
- (void)orderFrontStandardAboutPanel:(id)s { [self orderFrontStandardAboutPanelWithOptions:nil]; }
- (void)orderFrontStandardAboutPanelWithOptions:(NSDictionary *)o {
    NSString *name = [NSProcessInfo processInfo].processName;
    const char *text = [[NSString stringWithFormat:@"%@\n(scion)", name] UTF8String];
    ui(UI_ALERT, U([name UTF8String]), U(text), 0, 1, 0);
}
- (void)orderFrontCharacterPalette:(id)s { }
- (void)registerForRemoteNotifications { }
- (void)registerServicesMenuSendTypes:(NSArray *)s returnTypes:(NSArray *)r { }
- (void)enumerateWindowsWithOptions:(NSUInteger)o usingBlock:(void (^)(NSWindow *, BOOL *))b {
    BOOL stop = NO;
    for (NSWindow *w in [self windows]) { b(w, &stop); if (stop) break; }
}
- (void)addWindowsItem:(NSWindow *)w title:(NSString *)t filename:(BOOL)f { }
- (void)toggleTouchBarCustomizationPalette:(id)s { }
- (void)setAppearance:(NSAppearance *)a { [a retain]; [_appearance release]; _appearance = a; }
@end

int NSApplicationMain(int argc, const char *argv[]) {
    /* the principal class from Info.plist if any, else NSApplication; then the main nib (menus, the delegate, windows) */
    Class c = nil;
    NSString *pc = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSPrincipalClass"];
    if (pc) c = NSClassFromString(pc);
    [(c ? c : [NSApplication class]) sharedApplication];
    mw_load_main_nib();
    [NSApp run];
    return 0;
}
void NSBeep(void) { }

/* ======================================================================= NSRunningApplication, NSWorkspace */
@implementation NSRunningApplication
+ (NSRunningApplication *)currentApplication { static NSRunningApplication *a; if (!a) a = [[self alloc] init]; return a; }
- (int)processIdentifier { return getpid(); }
- (NSString *)localizedName { return [NSProcessInfo processInfo].processName; }
- (NSString *)bundleIdentifier { return [[NSBundle mainBundle] bundleIdentifier]; }
- (BOOL)isActive { return [NSApp isActive]; }
- (BOOL)isHidden { return [NSApp isHidden]; }
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)o { [NSApp activateIgnoringOtherApps:YES]; return YES; }
- (BOOL)hide { [NSApp hide:nil]; return YES; }
- (BOOL)unhide { [NSApp unhide:nil]; return YES; }
- (BOOL)terminate { [NSApp terminate:nil]; return YES; }
- (BOOL)forceTerminate { exit(0); }
@end
@implementation NSWorkspace { NSNotificationCenter *_nc; }
+ (NSWorkspace *)sharedWorkspace { static NSWorkspace *w; if (!w) w = [[self alloc] init]; return w; }
- (NSNotificationCenter *)notificationCenter { if (!_nc) _nc = [[NSNotificationCenter alloc] init]; return _nc; }
- (NSRunningApplication *)frontmostApplication { return [NSRunningApplication currentApplication]; }
- (NSRunningApplication *)menuBarOwningApplication { return [NSRunningApplication currentApplication]; }
- (NSArray *)runningApplications { return @[[NSRunningApplication currentApplication]]; }
- (BOOL)accessibilityDisplayShouldReduceMotion { return NO; }
- (BOOL)accessibilityDisplayShouldIncreaseContrast { return NO; }
- (BOOL)accessibilityDisplayShouldReduceTransparency { return NO; }
- (BOOL)accessibilityDisplayShouldDifferentiateWithoutColor { return NO; }
- (BOOL)accessibilityDisplayShouldInvertColors { return NO; }
- (BOOL)isVoiceOverEnabled { return NO; }
- (BOOL)isSwitchControlEnabled { return NO; }
- (BOOL)openURL:(NSURL *)u { return NO; } /* ponytail: no shell integration yet */
- (BOOL)openFile:(NSString *)f { return NO; }
- (void)activateFileViewerSelectingURLs:(NSArray *)u { }
- (BOOL)selectFile:(NSString *)f inFileViewerRootedAtPath:(NSString *)r { return NO; }
- (NSImage *)iconForFile:(NSString *)f { return [[[NSImage alloc] initWithSize:NSMakeSize(32, 32)] autorelease]; }
- (void)openURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)c completionHandler:(void (^)(NSRunningApplication *, NSError *))h {
    BOOL ok = [self openURL:url];
    if (h) h(nil, ok ? nil : [NSError errorWithDomain:NSCocoaErrorDomain code:4 userInfo:nil]);
}
- (void)openApplicationAtURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)c completionHandler:(void (^)(NSRunningApplication *, NSError *))h {
    if (h) h(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:4 userInfo:nil]);
}
@end
@implementation NSWorkspaceOpenConfiguration
@synthesize promptsUserIfNeeded, addsToRecentItems, activates, hides, hidesOthers, createsNewApplicationInstance, allowsRunningApplicationSubstitution, arguments, environment;
+ (instancetype)configuration { NSWorkspaceOpenConfiguration *c = [[[self alloc] init] autorelease]; c.activates = YES; c.addsToRecentItems = YES; return c; }
- (id)copyWithZone:(NSZone *)z { NSWorkspaceOpenConfiguration *c = [[[self class] alloc] init]; c.activates = activates; c.hides = hides; c.arguments = arguments; c.environment = environment; return c; }
- (void)dealloc { [arguments release]; [environment release]; [super dealloc]; }
@end

/* ======================================================================= NSCursor */
static int g_cursor_hidden;
@implementation NSCursor { NSImage *_image; NSPoint _hot; }
#define CUR(name) + (NSCursor *)name { static NSCursor *c; if (!c) c = [[NSCursor alloc] init]; return c; }
CUR(arrowCursor) CUR(IBeamCursor) CUR(pointingHandCursor) CUR(closedHandCursor) CUR(openHandCursor) CUR(crosshairCursor)
CUR(resizeLeftRightCursor) CUR(resizeUpDownCursor) CUR(resizeLeftCursor) CUR(resizeRightCursor) CUR(resizeUpCursor) CUR(resizeDownCursor)
CUR(operationNotAllowedCursor) CUR(disappearingItemCursor) CUR(dragCopyCursor) CUR(dragLinkCursor) CUR(contextualMenuCursor)
#undef CUR
+ (NSCursor *)currentCursor { return [self arrowCursor]; }
+ (NSCursor *)currentSystemCursor { return [self arrowCursor]; }
- (instancetype)initWithImage:(NSImage *)i hotSpot:(NSPoint)p { if ((self = [super init])) { _image = [i retain]; _hot = p; } return self; }
- (void)dealloc { [_image release]; [super dealloc]; }
- (NSImage *)image { return _image; }
- (NSPoint)hotSpot { return _hot; }
/* hide/unhide nest like on the Mac */
+ (void)hide { if (g_cursor_hidden++ == 0) ui(UI_CURSOR, 0, 0, 0, 0, 0); }
+ (void)unhide { if (g_cursor_hidden > 0 && --g_cursor_hidden == 0) ui(UI_CURSOR, 1, 0, 0, 0, 0); }
+ (void)setHiddenUntilMouseMoves:(BOOL)f { }
+ (void)pop { }
- (void)set { } /* ponytail: always the arrow (custom cursors would need the image) */
- (void)push { }
- (void)pop { }
@end

/* ======================================================================= notification names, constants */
#define N(x) NSString *const x = @#x;
N(NSApplicationWillFinishLaunchingNotification) N(NSApplicationDidFinishLaunchingNotification) N(NSApplicationWillTerminateNotification)
N(NSApplicationDidBecomeActiveNotification) N(NSApplicationDidResignActiveNotification) N(NSApplicationWillBecomeActiveNotification)
N(NSApplicationWillResignActiveNotification) N(NSApplicationDidHideNotification) N(NSApplicationDidUnhideNotification)
N(NSApplicationDidChangeScreenParametersNotification) N(NSApplicationDidUpdateNotification) N(NSApplicationWillUpdateNotification)
N(NSApplicationDidChangeOcclusionStateNotification)
N(NSWindowDidBecomeKeyNotification) N(NSWindowDidResignKeyNotification) N(NSWindowDidBecomeMainNotification) N(NSWindowDidResignMainNotification)
N(NSWindowWillCloseNotification) N(NSWindowDidResizeNotification) N(NSWindowWillStartLiveResizeNotification) N(NSWindowDidEndLiveResizeNotification)
N(NSWindowDidMoveNotification) N(NSWindowWillMoveNotification) N(NSWindowDidMiniaturizeNotification) N(NSWindowWillMiniaturizeNotification)
N(NSWindowDidDeminiaturizeNotification) N(NSWindowWillEnterFullScreenNotification) N(NSWindowDidEnterFullScreenNotification)
N(NSWindowWillExitFullScreenNotification) N(NSWindowDidExitFullScreenNotification) N(NSWindowDidChangeBackingPropertiesNotification)
N(NSWindowDidChangeScreenNotification) N(NSWindowDidChangeOcclusionStateNotification) N(NSWindowDidExposeNotification) N(NSWindowDidUpdateNotification)
N(NSViewFrameDidChangeNotification) N(NSViewBoundsDidChangeNotification) N(NSViewGlobalFrameDidChangeNotification)
N(NSControlTextDidChangeNotification) N(NSControlTextDidBeginEditingNotification) N(NSControlTextDidEndEditingNotification)
N(NSMenuDidSendActionNotification) N(NSMenuWillSendActionNotification) N(NSWorkspaceDidActivateApplicationNotification)
N(NSWorkspaceWillSleepNotification) N(NSWorkspaceDidWakeNotification) N(NSWorkspaceScreensDidSleepNotification) N(NSWorkspaceScreensDidWakeNotification)
N(NSSystemColorsDidChangeNotification) N(NSMenuDidBeginTrackingNotification) N(NSMenuDidEndTrackingNotification)
N(NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification)
N(NSFontTextStyleLargeTitle) N(NSFontTextStyleTitle1) N(NSFontTextStyleTitle2) N(NSFontTextStyleTitle3) N(NSFontTextStyleHeadline)
N(NSFontTextStyleSubheadline) N(NSFontTextStyleBody) N(NSFontTextStyleCallout) N(NSFontTextStyleFootnote) N(NSFontTextStyleCaption1) N(NSFontTextStyleCaption2)
N(NSModalPanelRunLoopMode) N(NSEventTrackingRunLoopMode)
N(NSDeviceResolution) N(NSDeviceSize) N(NSDeviceIsScreen) N(NSDeviceColorSpaceName)
N(NSAppearanceNameAqua) N(NSAppearanceNameDarkAqua) N(NSAppearanceNameVibrantLight) N(NSAppearanceNameVibrantDark)
N(NSFontAttributeName) N(NSForegroundColorAttributeName) N(NSBackgroundColorAttributeName) N(NSParagraphStyleAttributeName)
N(NSImageNameApplicationIcon) N(NSImageNameCaution) N(NSImageNameInfo) N(NSCalibratedRGBColorSpace) N(NSDeviceRGBColorSpace)
#undef N
NSString *const NSPasteboardTypeString = @"public.utf8-plain-text", *const NSPasteboardTypeURL = @"public.url",
    *const NSPasteboardTypeFileURL = @"public.file-url", *const NSPasteboardTypePNG = @"public.png", *const NSStringPboardType = @"NSStringPboardType";
const NSFontWeight NSFontWeightUltraLight = -0.8, NSFontWeightThin = -0.6, NSFontWeightLight = -0.4, NSFontWeightRegular = 0,
    NSFontWeightMedium = 0.23, NSFontWeightSemibold = 0.3, NSFontWeightBold = 0.4, NSFontWeightHeavy = 0.56, NSFontWeightBlack = 0.62;
const CGFloat NSGridViewSizeForContent = 1.1754943508222875e-38; /* FLT_MIN, like AppKit */
