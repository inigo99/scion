/* status_item.m: an NSStatusItem (icon in the notification area) with a title, an image and a menu.
   SCION_TEST_GUI reports the icons; SCION_TEST_CLICK clicks the first one, whose action opens a borderless window. */
#import <AppKit/AppKit.h>
@interface Del : NSObject <NSApplicationDelegate> { NSStatusItem *_item; NSWindow *_pop; } @end
@implementation Del
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    _item = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
    NSImage *img = [NSImage imageWithSize:NSMakeSize(18, 16) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [[NSColor blackColor] set];
        NSFrameRectWithWidth(NSInsetRect(r, 1, 1), 2);
        [@"6" drawAtPoint:NSMakePoint(5, 1) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:11]}];
        return YES;
    }];
    img.template = YES;
    _item.button.image = img;
    _item.button.toolTip = @"NSStatusItem test";
    _item.button.target = self;
    _item.button.action = @selector(click:);
    [_item.button sendActionOn:NSEventMaskLeftMouseDown];
    printf("STATUS: thickness %.0f, button %s\n", [NSStatusBar systemStatusBar].thickness, _item.button ? "yes" : "no");
    fflush(stdout);
}
- (void)click:(id)s {
    NSRect r = _item.button.window.frame;
    _pop = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 150) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    _pop.title = @"popover";
    [_pop setFrameTopLeftPoint:NSMakePoint(NSMidX(r) - 100, NSMinY(r) - 2)];   /* under the icon, as on a Mac */
    [_pop orderFront:nil];
    BOOL onScreen = NSContainsRect([NSScreen mainScreen].frame, _pop.frame);
    _pop.title = onScreen ? @"popover inside" : @"popover OUTSIDE";   /* SCION_TEST_GUI reports the titles */
    printf("STATUS: click, window %s\n", onScreen ? "on screen" : "OFF screen");
    if (!onScreen) printf("  icon %s, window %s, screen %s\n", [NSStringFromRect(r) UTF8String], [NSStringFromRect(_pop.frame) UTF8String], [NSStringFromRect([NSScreen mainScreen].frame) UTF8String]);
    fflush(stdout);
}
@end
int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Del *d = [[Del alloc] init];
        NSApp.delegate = d;
        [NSApp run];
    }
    return 0;
}
