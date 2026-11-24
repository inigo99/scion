/* GCKeyboard / GCMouse with raw input injected on the host (UI_RAW_INJECT): connect notifications, key codes
 * (HID usages), keyChangedHandler, anyKeyPressed, mouse deltas (y up), buttons and scroll. Prints "KEYBOARD OK". ARC. */
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#include <stdio.h>
#include <stdlib.h>

int64_t _scion_ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
typedef struct { uint32_t type, code; int32_t down; float dx, dy; uint64_t time_ns; } Raw;
enum { UI_RAW_INJECT = 27, KEY = 1, MOVE, BUTTON, SCROLL };
static void raw(uint32_t type, uint32_t code, int down, float dx, float dy) {
    Raw r = {type, code, down, dx, dy, 0};
    _scion_ui(UI_RAW_INJECT, (uint64_t)(uintptr_t)&r, 0, 0, 0, 0);
}

static int fails;
#define CHECK(c, ...) do { if (c) printf("  ok: " __VA_ARGS__); else { printf("  FAIL: " __VA_ARGS__); fails++; } printf("\n"); fflush(stdout); } while (0)

int main(void) {
    @autoreleasepool {
        __block int kbConn = 0, mouseConn = 0;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:GCKeyboardDidConnectNotification object:nil queue:nil usingBlock:^(NSNotification *n) { kbConn++; }];
        [nc addObserverForName:GCMouseDidConnectNotification object:nil queue:nil usingBlock:^(NSNotification *n) { mouseConn++; }];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        CHECK(kbConn == 1 && mouseConn == 1 && GCKeyboard.coalescedKeyboard && GCMouse.current && GCMouse.mice.count == 1, "keyboard and mouse connected at launch");

        NSMutableArray *keys = [NSMutableArray array];
        GCKeyboardInput *kb = GCKeyboard.coalescedKeyboard.keyboardInput;
        kb.keyChangedHandler = ^(GCKeyboardInput *k, GCControllerButtonInput *b, GCKeyCode code, BOOL pressed) {
            [keys addObject:[NSString stringWithFormat:@"%ld%c", code, pressed ? '+' : '-']];
        };
        raw(KEY, 0x1A /* W */, 1, 0, 0); raw(KEY, 0x1A, 1, 0, 0); /* the second is a repeat */
        raw(KEY, 0xE1 /* left shift */, 1, 0, 0);
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        CHECK(([keys isEqualToArray:@[@"26+", @"225+"]]), "keyChangedHandler with HID codes, no repeats (%s)", [[keys componentsJoinedByString:@" "] UTF8String]);
        CHECK(kb.anyKeyPressed && [kb buttonForKeyCode:GCKeyCodeKeyW].pressed && [kb buttonForKeyCode:GCKeyCodeLeftShift].pressed, "anyKeyPressed and buttonForKeyCode:");
        raw(KEY, 0x1A, 0, 0, 0); raw(KEY, 0xE1, 0, 0, 0);
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        CHECK(!kb.anyKeyPressed && keys.count == 4, "after release no key stays pressed");

        GCMouseInput *m = GCMouse.current.mouseInput;
        __block float sx = 0, sy = 0; __block int moves = 0, left = 0; __block float wheel = 0;
        m.mouseMovedHandler = ^(GCMouseInput *mi, float dx, float dy) { sx += dx; sy += dy; moves++; };
        m.leftButton.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) { if (p) left++; };
        m.scroll.valueChangedHandler = ^(GCControllerDirectionPad *d, float x, float y) { wheel += y; };
        raw(MOVE, 0, 0, 5, 3); raw(MOVE, 0, 0, 7, -10);
        raw(BUTTON, 0, 1, 0, 0); raw(BUTTON, 0, 0, 0, 0);
        raw(SCROLL, 0, 0, 0, 2);
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        CHECK(sx == 12 && sy == 7 && moves >= 1, "mouseMovedHandler: raw deltas with y up (%g, %g in %d)", sx, sy, moves);
        CHECK(left == 1 && !m.leftButton.pressed, "left button");
        CHECK(wheel == 2 && m.scroll.yAxis.value == 0, "wheel: one delta and back to rest");
        printf(fails ? "KEYBOARD FAIL (%d)\n" : "KEYBOARD OK\n", fails);
    }
    return fails != 0;
}
