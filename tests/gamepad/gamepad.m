/* GameController + CoreHaptics with a virtual controller (UI_PAD_INJECT): connect/disconnect notifications,
 * buttons, sticks and handlers, and rumble driven by haptic patterns (the host reports the motor values back).
 * Prints "GAMEPAD OK". ARC. */
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <CoreHaptics/CoreHaptics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int64_t _scion_ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
enum { UI_PAD_INJECT = 14 };
typedef struct { uint32_t buttons; float lx, ly, rx, ry, lt, rt; char name[48]; uint32_t has_rumble; } Pad;
enum { A = 1, B = 2, LB = 16, MENU = 256, UP = 1024 };
static Pad pad;
static int64_t inject(int on) { return _scion_ui(UI_PAD_INJECT, 0, on ? (uint64_t)(uintptr_t)&pad : 0, 0, 0, 0); }
static int low(void) { return (int)(inject(1) >> 16 & 0xFFFF); }
static int high(void) { return (int)(inject(1) & 0xFFFF); }

static int fails;
#define CHECK(c, ...) do { if (c) printf("  ok: " __VA_ARGS__); else { printf("  FAIL: " __VA_ARGS__); fails++; } printf("\n"); fflush(stdout); } while (0)

static GCController *ctl;
static int connects, disconnects, padChanges, bPressed, stopReason = -100;
static NSMutableSet *changed;
static CHHapticEngine *engine, *leftEngine;
static id<CHHapticPatternPlayer> player;
static int step, waited;

static CHHapticPattern *pattern(NSString *type, float intensity, float sharp, NSTimeInterval dur) {
    CHHapticEvent *e = [[CHHapticEvent alloc] initWithEventType:type parameters:@[
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:intensity],
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:sharp]] relativeTime:0 duration:dur];
    NSError *err;
    return [[CHHapticPattern alloc] initWithEvents:@[e] parameters:@[] error:&err];
}

static void next(void) {
    NSError *err = nil;
    if (step == 0 && !ctl && ++waited < 30) return; /* the controller shows up within ~0.25 s (empty slots are polled slowly) */
    switch (step++) {
    case 0:
        CHECK(connects == 1 && ctl, "GCControllerDidConnectNotification");
        CHECK([ctl.vendorName isEqualToString:@"Virtual controller"] && [ctl.extendedGamepad isKindOfClass:[GCXboxGamepad class]], "vendorName and GCXboxGamepad (%s)", ctl.vendorName.UTF8String);
        CHECK(ctl.extendedGamepad.buttonA.pressed && fabsf(ctl.extendedGamepad.leftThumbstick.xAxis.value - 0.5f) < 1e-6, "initial state: A pressed, left stick x=0.5");
        CHECK(GCController.controllers.count == 1 && GCController.current == ctl, "GCController.controllers / current");
        changed = [NSMutableSet set];
        ctl.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *e) { padChanges++; [changed addObject:e]; };
        ctl.extendedGamepad.buttonB.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) { if (p) bPressed++; };
        pad.buttons = A | B | UP; pad.ly = -1; pad.lt = 0.75f;
        inject(1);
        break;
    case 1: {
        GCExtendedGamepad *g = ctl.extendedGamepad;
        CHECK(bPressed == 1 && g.buttonB.pressed, "pressedChangedHandler for B");
        CHECK([changed containsObject:g.buttonB] && [changed containsObject:g.leftThumbstick] && [changed containsObject:g.dpad] && [changed containsObject:g.leftTrigger],
              "controller valueChangedHandler with B, stick, d-pad and trigger (%d changes)", padChanges);
        CHECK(g.leftThumbstick.down.value == 1 && g.dpad.up.pressed && fabsf(g.leftTrigger.value - 0.75f) < 1e-6 && g.leftTrigger.isAnalog, "stick down, d-pad up, analog trigger 0.75");
        CHECK(ctl.haptics && [ctl.haptics.supportedLocalities containsObject:GCHapticsLocalityLeftHandle], "haptics with localities");
        engine = [ctl.haptics createEngineWithLocality:GCHapticsLocalityDefault];
        engine.stoppedHandler = ^(CHHapticEngineStoppedReason r) { stopReason = (int)r; };
        CHECK([engine startAndReturnError:&err], "CHHapticEngine starts");
        player = [engine createPlayerWithPattern:pattern(CHHapticEventTypeHapticContinuous, 1, 0.5f, GCHapticDurationInfinite) error:&err];
        CHECK(player && [player startAtTime:CHHapticTimeImmediate error:&err], "endless continuous player");
        break;
    }
    case 2:
        CHECK(low() == 65535 && high() == 65535, "full rumble on both motors (%d, %d)", low(), high());
        [player sendParameters:@[[[CHHapticDynamicParameter alloc] initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:0.5f relativeTime:0]]
                        atTime:CHHapticTimeImmediate error:&err];
        break;
    case 3:
        CHECK(abs(low() - 32768) < 2 && abs(high() - 32768) < 2, "dynamic parameter: half intensity (%d, %d)", low(), high());
        [player stopAtTime:CHHapticTimeImmediate error:&err];
        leftEngine = [ctl.haptics createEngineWithLocality:GCHapticsLocalityLeftHandle];
        [leftEngine startAndReturnError:&err];
        player = [leftEngine createPlayerWithPattern:pattern(CHHapticEventTypeHapticContinuous, 0.8f, 0, 0.3) error:&err];
        [player startAtTime:0 error:&err];
        break;
    case 4:
        CHECK(abs(low() - 52428) < 2 && high() == 0, "LeftHandle locality: only the low-frequency motor (%d, %d)", low(), high());
        break;
    case 7: /* 0.3 s later the pattern has ended */
        CHECK(low() == 0 && high() == 0, "the 0.3 s pattern ends and the motors stop (%d, %d)", low(), high());
        [engine createPlayerWithPattern:pattern(CHHapticEventTypeHapticContinuous, 1, 1, 10) error:&err];
        inject(0);
        break;
    case 8:
        CHECK(disconnects == 1 && GCController.controllers.count == 0, "GCControllerDidDisconnectNotification");
        CHECK(stopReason == CHHapticEngineStoppedReasonGameControllerDisconnect, "the haptic engine stops on disconnect (reason %d)", stopReason);
        printf(fails ? "GAMEPAD FAIL (%d)\n" : "GAMEPAD OK\n", fails);
        exit(fails != 0);
    }
}

int main(void) {
    @autoreleasepool {
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:GCControllerDidConnectNotification object:nil queue:nil usingBlock:^(NSNotification *n) { connects++; ctl = n.object; }];
        [nc addObserverForName:GCControllerDidDisconnectNotification object:nil queue:nil usingBlock:^(NSNotification *n) { disconnects++; }];
        strcpy(pad.name, "Virtual controller"); pad.has_rumble = 1; pad.buttons = A; pad.lx = 0.5f;
        inject(1);
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) { next(); }];
        [NSTimer scheduledTimerWithTimeInterval:10 repeats:NO block:^(NSTimer *t) { printf("FAIL: timed out at step %d\n", step); exit(1); }];
        [[NSRunLoop mainRunLoop] run];
    }
}
