/* NSOpenPanel / NSSavePanel (Windows file dialogs) and context menus (TrackPopupMenu). The host answers through
 * UI_TEST instead of showing them, so the test runs unattended. Prints "DIALOGS OK". ARC. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <stdlib.h>

int64_t _scion_ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
enum { UI_INJECT = 20, UI_TEST = 25 };
static void answer_dialog(const char *paths) { _scion_ui(UI_TEST, 1, (uint64_t)(uintptr_t)paths, 0, 0, 0); }
static void answer_popup(int id) { _scion_ui(UI_TEST, 2, (uint64_t)id, 0, 0, 0); }

static int fails;
#define CHECK(c, ...) do { if (c) printf("  ok: " __VA_ARGS__); else { printf("  FAIL: " __VA_ARGS__); fails++; } printf("\n"); fflush(stdout); } while (0)

@interface Target : NSObject
@property NSMutableArray *hits;
@end
@implementation Target
- (void)one:(id)s { [_hits addObject:@"one"]; }
- (void)two:(id)s { [_hits addObject:@"two"]; }
- (void)three:(id)s { [_hits addObject:@"three"]; }
- (BOOL)validateMenuItem:(NSMenuItem *)i { return i.action != @selector(three:); }
@end

/* "dialogs_x86_64 real": the real dialogs and menu, to try them by hand */
static int interactive(void) {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.allowsMultipleSelection = YES; op.message = @"scion: choose one or more files";
    if ([op runModal] == NSModalResponseOK) for (NSURL *u in op.URLs) printf("open: %s\n", u.path.UTF8String); else printf("open: cancelled\n");
    NSSavePanel *sp = [NSSavePanel savePanel];
    sp.nameFieldStringValue = @"test.txt"; sp.allowedFileTypes = @[@"txt"];
    printf("save: %s\n", [sp runModal] == NSModalResponseOK ? sp.URL.path.UTF8String : "cancelled");
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 300, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [w makeKeyAndOrderFront:nil];
    Target *t = [Target new]; t.hits = [NSMutableArray array];
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"ctx"];
    for (NSString *s in @[@"one", @"two", @"three"]) [m addItemWithTitle:s action:NSSelectorFromString([s stringByAppendingString:@":"]) keyEquivalent:@""].target = t;
    [m popUpMenuPositioningItem:nil atLocation:NSMakePoint(150, 100) inView:w.contentView];
    printf("menu: %s\n", t.hits.count ? [t.hits[0] UTF8String] : "nothing");
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (argc > 1) return interactive();
        printf("step: open\n");
        answer_dialog("/c/Windows/win.ini\n");
        NSOpenPanel *op = [NSOpenPanel openPanel];
        op.allowedFileTypes = @[@"ini", @"txt"];
        NSModalResponse r = [op runModal];
        CHECK(r == NSModalResponseOK && [op.URL.path isEqualToString:@"/c/Windows/win.ini"], "NSOpenPanel returns the chosen path (%s)", op.URL.path.UTF8String);
        answer_dialog("/c/a.txt\n/c/b.txt\n");
        op.allowsMultipleSelection = YES;
        r = [op runModal];
        CHECK(r == NSModalResponseOK && op.URLs.count == 2 && [op.URLs[1].path isEqualToString:@"/c/b.txt"], "multiple selection (%lu)", (unsigned long)op.URLs.count);
        answer_dialog("");
        r = [op runModal];
        CHECK(r == NSModalResponseCancel && op.URLs.count == 0, "cancel");

        printf("step: save\n");
        answer_dialog("/c/Users/Public/savegame.sav\n");
        NSSavePanel *sp = [NSSavePanel savePanel];
        sp.nameFieldStringValue = @"savegame.sav";
        __block NSModalResponse got = -1;
        [sp beginWithCompletionHandler:^(NSModalResponse x) { got = x; }];
        CHECK(got == -1, "the handler does not run inside the call");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        CHECK(got == NSModalResponseOK && [sp.URL.path isEqualToString:@"/c/Users/Public/savegame.sav"], "NSSavePanel with a handler (%s)", sp.URL.path.UTF8String);

        printf("step: menu contextual\n");
        Target *t = [Target new];
        t.hits = [NSMutableArray array];
        NSMenu *m = [[NSMenu alloc] initWithTitle:@"ctx"];
        for (NSString *s in @[@"one", @"two"]) [m addItemWithTitle:s action:NSSelectorFromString([s stringByAppendingString:@":"]) keyEquivalent:@""].target = t;
        [m addItem:[NSMenuItem separatorItem]];
        [m addItemWithTitle:@"three" action:@selector(three:) keyEquivalent:@""].target = t;
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 300, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        w.releasedWhenClosed = NO;
        [w makeKeyAndOrderFront:nil];
        answer_popup(2);
        BOOL chosen = [m popUpMenuPositioningItem:nil atLocation:NSMakePoint(10, 10) inView:w.contentView];
        CHECK(chosen && [t.hits isEqualToArray:@[@"two"]], "popUpMenuPositioningItem runs the chosen item");
        answer_popup(4);
        [m popUpMenuPositioningItem:nil atLocation:NSMakePoint(10, 10) inView:w.contentView];
        CHECK(t.hits.count == 1 && ![m itemAtIndex:3].enabled, "an item disabled by validateMenuItem: does not run");
        w.contentView.menu = m;
        answer_popup(1);
        _scion_ui(UI_INJECT, (uint64_t)w.windowNumber, 0x204 /* WM_RBUTTONDOWN */, 2, 20 | 30 << 16, 0);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        CHECK([t.hits.lastObject isEqualToString:@"one"], "a right click on the view opens its context menu (%s)", [t.hits.lastObject UTF8String]);
        [w close];
        printf(fails ? "DIALOGS FAIL (%d)\n" : "DIALOGS OK\n", fails);
    }
    return fails != 0;
}
