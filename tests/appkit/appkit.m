/* an AppKit app. Window + MTKView drawing with Metal, a menu bar with key equivalents, keyboard and mouse
 * input injected into the host window (UI_INJECT), local monitors, resize, CVDisplayLink, and close -> terminate.
 * Prints "APPKIT OK" when every step passed. */
#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#import <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>

int64_t _scion_ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
enum { UI_INJECT = 20 };
enum { WM_KEYDOWN = 0x100, WM_KEYUP = 0x101, WM_MOUSEMOVE = 0x200, WM_LBUTTONDOWN = 0x201, WM_LBUTTONUP = 0x202, WM_MOUSEWHEEL = 0x20A, WM_CLOSE = 0x10 };
static void inject(NSWindow *w, unsigned msg, uint64_t wp, uint64_t lp) { _scion_ui(UI_INJECT, (uint64_t)w.windowNumber, msg, wp, lp, 0); }
static void key(NSWindow *w, unsigned vk, unsigned scan, int down) {
    inject(w, down ? WM_KEYDOWN : WM_KEYUP, vk, 1 | (uint64_t)scan << 16 | (down ? 0 : 0xC0000000ull));
}
static uint64_t xy(int x, int y) { return (uint64_t)(uint16_t)x | (uint64_t)(uint16_t)y << 16; }

static int fails;
#define CHECK(c, ...) do { if (c) printf("  ok: " __VA_ARGS__); else { printf("  FAIL: " __VA_ARGS__); fails++; } printf("\n"); fflush(stdout); } while (0)

/* ------------------------------------------------------------------ the view: records input */
@interface TestView : MTKView <MTKViewDelegate>
@property NSMutableArray *log;
@property int frames;
@property CGSize lastSize;
@end
@implementation TestView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)e { [_log addObject:[NSString stringWithFormat:@"down %u %@", e.keyCode, e.characters]]; }
- (void)keyUp:(NSEvent *)e { [_log addObject:[NSString stringWithFormat:@"up %u", e.keyCode]]; }
- (void)mouseDown:(NSEvent *)e { NSPoint p = [self convertPoint:e.locationInWindow fromView:nil]; [_log addObject:[NSString stringWithFormat:@"mdown %.0f %.0f %ld", p.x, p.y, (long)e.clickCount]]; }
- (void)mouseUp:(NSEvent *)e { [_log addObject:@"mup"]; }
- (void)scrollWheel:(NSEvent *)e { [_log addObject:[NSString stringWithFormat:@"scroll %.0f", e.scrollingDeltaY]]; }
- (void)mtkView:(MTKView *)v drawableSizeWillChange:(CGSize)s { _lastSize = s; }
- (void)drawInMTKView:(MTKView *)v {
    static id<MTLCommandQueue> q;
    if (!q) q = [self.device newCommandQueue];
    MTLRenderPassDescriptor *rp = self.currentRenderPassDescriptor;
    if (!rp) return;
    self.clearColor = MTLClearColorMake(0.1 * (_frames % 10), 0.4, 0.8, 1);
    id<MTLCommandBuffer> cb = [q commandBuffer];
    [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
    [cb presentDrawable:self.currentDrawable];
    [cb commit];
    _frames++;
}
@end

/* ------------------------------------------------------------------ the app */
@interface App : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property NSWindow *win;
@property TestView *view;
@property int step, waits, menuHits, resizes, monitorKeys, willClose, becameKey;
@end
static atomic_int g_ticks;
static CVReturn tick(CVDisplayLinkRef l, const CVTimeStamp *n, const CVTimeStamp *o, CVOptionFlags fi, CVOptionFlags *fo, void *c) { g_ticks++; return kCVReturnSuccess; }

@implementation App
- (void)menuAction:(NSMenuItem *)i { _menuHits++; }
- (BOOL)validateMenuItem:(NSMenuItem *)i { return i.action != @selector(disabledAction:); }
- (void)disabledAction:(id)s { _menuHits += 100; }
- (void)windowDidResize:(NSNotification *)n { _resizes++; }
- (void)windowDidBecomeKey:(NSNotification *)n { _becameKey++; }
- (void)windowWillClose:(NSNotification *)n { _willClose++; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }
- (void)applicationWillTerminate:(NSNotification *)n {
    CHECK(_willClose == 1, "closing the window -> windowWillClose and the app ends");
    printf(fails ? "APPKIT FAIL (%d)\n" : "APPKIT OK\n", fails);
    fflush(stdout);
}
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    printf("step: launched\n");
    NSMenu *bar = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new]; NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Test"];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu; [bar addItem:appItem];
    NSMenuItem *editItem = [NSMenuItem new]; NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    NSMenuItem *k = [edit addItemWithTitle:@"Action K" action:@selector(menuAction:) keyEquivalent:@"k"]; k.target = self;
    NSMenuItem *d = [edit addItemWithTitle:@"Disabled" action:@selector(disabledAction:) keyEquivalent:@"j"]; d.target = self;
    editItem.submenu = edit; [bar addItem:editItem];
    NSApp.mainMenu = bar;

    _win = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    _win.releasedWhenClosed = NO;
    _win.title = @"scion AppKit";
    _win.delegate = self;
    _view = [[TestView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300) device:MTLCreateSystemDefaultDevice()];
    _view.log = [NSMutableArray array];
    _view.delegate = _view;
    _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    _win.contentView = _view;
    [_win makeFirstResponder:_view];
    [_win center];
    [_win makeKeyAndOrderFront:nil];
    CHECK(NSEqualSizes(_view.frame.size, NSMakeSize(400, 300)), "contentView 400x300 (is %gx%g)", _view.frame.size.width, _view.frame.size.height);
    CHECK([NSScreen mainScreen] && [NSScreen mainScreen].frame.size.width > 0, "NSScreen %gx%g scale %g", [NSScreen mainScreen].frame.size.width,
          [NSScreen mainScreen].frame.size.height, [NSScreen mainScreen].backingScaleFactor);

    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        self.monitorKeys++;
        return e.keyCode == 7 /* x */ ? nil : e;   /* the monitor swallows X */
    }];
    CVDisplayLinkRef link;
    CVDisplayLinkCreateWithActiveCGDisplays(&link);
    CVDisplayLinkSetOutputCallback(link, tick, NULL);
    CVDisplayLinkStart(link);
    { /* ARC retains GCD objects (they are Objective-C objects on macOS) */
        dispatch_queue_t q = dispatch_queue_create("test.serial", DISPATCH_QUEUE_SERIAL), mainq = dispatch_get_main_queue();
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        dispatch_group_t grp = dispatch_group_create();
        __block int hits = 0;
        dispatch_group_async(grp, q, ^{ hits++; dispatch_semaphore_signal(sem); });
        long w = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2000000000));
        dispatch_group_wait(grp, DISPATCH_TIME_FOREVER);
        CHECK(w == 0 && hits == 1 && mainq != nil, "GCD with ARC (queue, group, semaphore retained as objects)");
    }
    [NSTimer scheduledTimerWithTimeInterval:0.15 target:self selector:@selector(next:) userInfo:nil repeats:YES];
}
- (void)next:(NSTimer *)t {
    NSArray *log = _view.log;
    switch (_step++) {
    case 0: /* a, x (swallowed), mouse click, wheel */
        printf("step: input\n");
        key(_win, 'A', 0x1E, 1); key(_win, 'A', 0x1E, 0);
        key(_win, 'X', 0x2D, 1);
        inject(_win, WM_LBUTTONDOWN, 1, xy(10, 20)); inject(_win, WM_LBUTTONUP, 0, xy(10, 20));
        { /* the wheel message carries screen coordinates (pixels, top-left origin) */
            NSRect c = [_win convertRectToScreen:_view.bounds];
            CGFloat s = _win.backingScaleFactor, top = NSScreen.screens[0].frame.size.height - NSMaxY(c);
            inject(_win, WM_MOUSEWHEEL, (uint64_t)(120 << 16), xy((int)((c.origin.x + 200) * s), (int)((top + 150) * s)));
        }
        break;
    case 1:
        /* the events arrive through the window procedure and the run loop: on a busy machine (or while arm64 code is
           still being translated) that can take longer than one tick; wait up to 3 s for the last one */
        if (![log containsObject:@"scroll 1"] && ++_waits < 20) { _step--; break; }
        CHECK([log containsObject:@"down 0 a"], "keyDown A -> keyCode 0, \"a\"");
        CHECK([log containsObject:@"up 0"], "keyUp A");
        CHECK(![log containsObject:@"down 7 x"] && _monitorKeys >= 2, "the local monitor sees the keys and swallows the X");
        CHECK([log containsObject:@"mdown 10 280 1"], "mouseDown at (10,280) in the view (bottom-left origin)");
        CHECK([log containsObject:@"mup"], "mouseUp to the same view");
        CHECK([log containsObject:@"scroll 1"], "scrollWheel one line");
        printf("step: menu\n");
        key(_win, 0xA2 /* VK_LCONTROL */, 0x1D, 1); key(_win, 'K', 0x25, 1); key(_win, 'K', 0x25, 0);
        key(_win, 'J', 0x24, 1); key(_win, 'J', 0x24, 0); key(_win, 0xA2, 0x1D, 0);
        break;
    case 2:
        CHECK(_menuHits == 1, "Ctrl+K runs the menu's Cmd+K shortcut and validation blocks Cmd+J (hits=%d)", _menuHits);
        printf("step: resize\n");
        [_win setContentSize:NSMakeSize(480, 360)];
        break;
    case 3:
        CHECK(_resizes >= 1, "windowDidResize");
        CHECK(NSEqualSizes(_view.frame.size, NSMakeSize(480, 360)), "the view follows the window (%gx%g)", _view.frame.size.width, _view.frame.size.height);
        break;
    case 6: /* give the view time to draw at the new size */
        CHECK(_view.frames >= 5, "MTKView draws with Metal in the window (%d frames)", _view.frames);
        CHECK(_view.lastSize.width == 480 * _win.backingScaleFactor, "drawableSizeWillChange with the new size (%g)", _view.lastSize.width);
        CHECK(g_ticks >= 3, "CVDisplayLink (%d ticks)", (int)g_ticks);
        CHECK(_win.isVisible, "window visible");
        printf("step: close\n");
        inject(_win, WM_CLOSE, 0, 0); /* like the close button: performClose: */
        break;
    case 30: printf("FAIL: the app did not terminate when its window closed\n"); exit(1);
    }
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        App *a = [App new];
        NSApp.delegate = a;
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp run];
    }
    return 0;
}
