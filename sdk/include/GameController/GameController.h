/* scion SDK — GameController subset (implemented in GameController.dylib): extended gamepads from XInput on Windows,
 * with haptics (CoreHaptics engines that drive the rumble motors). GCKeyboard / GCMouse are not provided yet. */
#pragma once
#import <Foundation/Foundation.h>
#import <CoreHaptics/CoreHaptics.h>
#include <dispatch/dispatch.h>

@class GCController, GCExtendedGamepad, GCControllerElement, GCControllerButtonInput, GCControllerAxisInput, GCControllerDirectionPad,
    GCDeviceHaptics, GCPhysicalInputProfile, GCMicroGamepad, GCGamepad, GCMotion, GCDeviceLight, GCDeviceBattery;
extern NSNotificationName const GCControllerDidConnectNotification, GCControllerDidDisconnectNotification,
    GCControllerDidBecomeCurrentNotification, GCControllerDidStopBeingCurrentNotification, GCControllerUserCustomizationsDidChangeNotification;
typedef NS_ENUM(NSInteger, GCControllerPlayerIndex) { GCControllerPlayerIndexUnset = -1, GCControllerPlayerIndex1 = 0, GCControllerPlayerIndex2,
    GCControllerPlayerIndex3, GCControllerPlayerIndex4 };
typedef NSString *GCHapticsLocality;
extern GCHapticsLocality const GCHapticsLocalityDefault, GCHapticsLocalityAll, GCHapticsLocalityHandles, GCHapticsLocalityLeftHandle,
    GCHapticsLocalityRightHandle, GCHapticsLocalityTriggers, GCHapticsLocalityLeftTrigger, GCHapticsLocalityRightTrigger;
extern const float GCHapticDurationInfinite;
extern NSString *const GCInputButtonA, *const GCInputButtonB, *const GCInputButtonX, *const GCInputButtonY, *const GCInputLeftShoulder,
    *const GCInputRightShoulder, *const GCInputLeftTrigger, *const GCInputRightTrigger, *const GCInputDirectionPad, *const GCInputLeftThumbstick,
    *const GCInputRightThumbstick, *const GCInputLeftThumbstickButton, *const GCInputRightThumbstickButton, *const GCInputButtonMenu,
    *const GCInputButtonOptions, *const GCInputButtonHome;
typedef NS_ENUM(NSInteger, GCSystemGestureState) { GCSystemGestureStateEnabled = 0, GCSystemGestureStateAlwaysReceive, GCSystemGestureStateDisabled };

@protocol GCDevice <NSObject>
@property(retain) dispatch_queue_t handlerQueue;
@property(readonly, copy) NSString *vendorName, *productCategory;
@property(readonly, retain) GCPhysicalInputProfile *physicalInputProfile;
@end

@interface GCControllerElement : NSObject
@property(readonly, assign) GCControllerElement *collection;
@property(readonly, getter=isAnalog) BOOL analog;
@property(readonly, getter=isBoundToSystemGesture) BOOL boundToSystemGesture;
@property GCSystemGestureState preferredSystemGestureState;
@property(copy) NSString *localizedName, *unmappedLocalizedName, *sfSymbolsName, *unmappedSfSymbolsName;
@property(readonly) NSSet<NSString *> *aliases;
@end
typedef void (^GCControllerButtonValueChangedHandler)(GCControllerButtonInput *b, float value, BOOL pressed);
typedef void (^GCControllerButtonTouchedChangedHandler)(GCControllerButtonInput *b, float value, BOOL pressed, BOOL touched);
@interface GCControllerButtonInput : GCControllerElement
@property(copy) GCControllerButtonValueChangedHandler valueChangedHandler, pressedChangedHandler;
@property(copy) GCControllerButtonTouchedChangedHandler touchedChangedHandler;
@property(readonly) float value;
@property(readonly, getter=isPressed) BOOL pressed;
@property(readonly, getter=isTouched) BOOL touched;
- (void)setValue:(float)v;
@end
typedef void (^GCControllerAxisValueChangedHandler)(GCControllerAxisInput *a, float value);
@interface GCControllerAxisInput : GCControllerElement
@property(copy) GCControllerAxisValueChangedHandler valueChangedHandler;
@property(readonly) float value;
- (void)setValue:(float)v;
@end
typedef void (^GCControllerDirectionPadValueChangedHandler)(GCControllerDirectionPad *d, float x, float y);
@interface GCControllerDirectionPad : GCControllerElement
@property(copy) GCControllerDirectionPadValueChangedHandler valueChangedHandler;
@property(readonly) GCControllerAxisInput *xAxis, *yAxis;
@property(readonly) GCControllerButtonInput *up, *down, *left, *right;
- (void)setValueForXAxis:(float)x yAxis:(float)y;
@end
@interface GCPhysicalInputProfile : NSObject
@property(readonly, assign) id<GCDevice> device;
@property(readonly) NSTimeInterval lastEventTimestamp;
@property(readonly) BOOL hasRemappedElements;
@property(readonly) NSDictionary<NSString *, GCControllerElement *> *elements;
@property(readonly) NSDictionary<NSString *, GCControllerButtonInput *> *buttons;
@property(readonly) NSDictionary<NSString *, GCControllerAxisInput *> *axes;
@property(readonly) NSDictionary<NSString *, GCControllerDirectionPad *> *dpads;
@property(readonly) NSSet<GCControllerElement *> *allElements;
@property(copy) void (^valueDidChangeHandler)(GCPhysicalInputProfile *p, GCControllerElement *e);
- (GCControllerElement *)objectForKeyedSubscript:(NSString *)key;
- (instancetype)capture;
@end
typedef void (^GCExtendedGamepadValueChangedHandler)(GCExtendedGamepad *g, GCControllerElement *e);
@interface GCExtendedGamepad : GCPhysicalInputProfile
@property(readonly, assign) GCController *controller;
@property(copy) GCExtendedGamepadValueChangedHandler valueChangedHandler;
@property(readonly) GCControllerDirectionPad *dpad, *leftThumbstick, *rightThumbstick;
@property(readonly) GCControllerButtonInput *buttonA, *buttonB, *buttonX, *buttonY, *leftShoulder, *rightShoulder, *leftTrigger, *rightTrigger,
    *leftThumbstickButton, *rightThumbstickButton, *buttonMenu, *buttonOptions, *buttonHome;
- (GCExtendedGamepad *)saveSnapshot;
- (void)setStateFromExtendedGamepad:(GCExtendedGamepad *)g;
@end
@interface GCXboxGamepad : GCExtendedGamepad
@property(readonly) GCControllerButtonInput *paddleButton1, *paddleButton2, *paddleButton3, *paddleButton4, *buttonShare;
@end
@interface GCDeviceHaptics : NSObject
@property(readonly) NSSet<GCHapticsLocality> *supportedLocalities;
- (CHHapticEngine *)createEngineWithLocality:(GCHapticsLocality)l;
@end
@interface GCController : NSObject <GCDevice>
+ (NSArray<GCController *> *)controllers;
@property(class, readonly) GCController *current;
@property(class) BOOL shouldMonitorBackgroundEvents;
+ (void)startWirelessControllerDiscoveryWithCompletionHandler:(void (^)(void))h;
+ (void)stopWirelessControllerDiscovery;
+ (GCController *)controllerWithExtendedGamepad;
@property(retain) dispatch_queue_t handlerQueue;
@property(readonly, copy) NSString *vendorName, *productCategory;
@property(readonly, getter=isAttachedToDevice) BOOL attachedToDevice;
@property(readonly, getter=isSnapshot) BOOL snapshot;
@property GCControllerPlayerIndex playerIndex;
@property(readonly, retain) GCExtendedGamepad *extendedGamepad;
@property(readonly, retain) GCMicroGamepad *microGamepad;
@property(readonly, retain) GCGamepad *gamepad;
@property(readonly, retain) GCPhysicalInputProfile *physicalInputProfile;
@property(readonly, retain) GCDeviceHaptics *haptics;
@property(readonly, retain) GCMotion *motion;
@property(readonly, retain) GCDeviceLight *light;
@property(readonly, retain) GCDeviceBattery *battery;
@property(copy) void (^controllerPausedHandler)(GCController *c);
- (instancetype)capture;
@end

/* ======================================================================= GCKeyboard / GCMouse: raw input while the app is in front */
typedef long GCKeyCode; /* USB HID usage, keyboard page */
extern const GCKeyCode GCKeyCodeKeyA, GCKeyCodeKeyB, GCKeyCodeKeyC, GCKeyCodeKeyD, GCKeyCodeKeyE, GCKeyCodeKeyF, GCKeyCodeKeyG,
    GCKeyCodeKeyH, GCKeyCodeKeyI, GCKeyCodeKeyJ, GCKeyCodeKeyK, GCKeyCodeKeyL, GCKeyCodeKeyM, GCKeyCodeKeyN, GCKeyCodeKeyO, GCKeyCodeKeyP,
    GCKeyCodeKeyQ, GCKeyCodeKeyR, GCKeyCodeKeyS, GCKeyCodeKeyT, GCKeyCodeKeyU, GCKeyCodeKeyV, GCKeyCodeKeyW, GCKeyCodeKeyX, GCKeyCodeKeyY,
    GCKeyCodeKeyZ, GCKeyCodeOne, GCKeyCodeTwo, GCKeyCodeThree, GCKeyCodeFour, GCKeyCodeFive, GCKeyCodeSix, GCKeyCodeSeven, GCKeyCodeEight,
    GCKeyCodeNine, GCKeyCodeZero, GCKeyCodeReturnOrEnter, GCKeyCodeEscape, GCKeyCodeDeleteOrBackspace, GCKeyCodeTab, GCKeyCodeSpacebar,
    GCKeyCodeHyphen, GCKeyCodeEqualSign, GCKeyCodeOpenBracket, GCKeyCodeCloseBracket, GCKeyCodeBackslash, GCKeyCodeNonUSPound,
    GCKeyCodeSemicolon, GCKeyCodeQuote, GCKeyCodeGraveAccentAndTilde, GCKeyCodeComma, GCKeyCodePeriod, GCKeyCodeSlash, GCKeyCodeCapsLock,
    GCKeyCodeF1, GCKeyCodeF2, GCKeyCodeF3, GCKeyCodeF4, GCKeyCodeF5, GCKeyCodeF6, GCKeyCodeF7, GCKeyCodeF8, GCKeyCodeF9, GCKeyCodeF10,
    GCKeyCodeF11, GCKeyCodeF12, GCKeyCodePrintScreen, GCKeyCodeScrollLock, GCKeyCodePause, GCKeyCodeInsert, GCKeyCodeHome, GCKeyCodePageUp,
    GCKeyCodeDeleteForward, GCKeyCodeEnd, GCKeyCodePageDown, GCKeyCodeRightArrow, GCKeyCodeLeftArrow, GCKeyCodeDownArrow, GCKeyCodeUpArrow,
    GCKeyCodeKeypadNumLock, GCKeyCodeKeypadSlash, GCKeyCodeKeypadAsterisk, GCKeyCodeKeypadHyphen, GCKeyCodeKeypadPlus, GCKeyCodeKeypadEnter,
    GCKeyCodeKeypad1, GCKeyCodeKeypad2, GCKeyCodeKeypad3, GCKeyCodeKeypad4, GCKeyCodeKeypad5, GCKeyCodeKeypad6, GCKeyCodeKeypad7,
    GCKeyCodeKeypad8, GCKeyCodeKeypad9, GCKeyCodeKeypad0, GCKeyCodeKeypadPeriod, GCKeyCodeNonUSBackslash, GCKeyCodeApplication,
    GCKeyCodePower, GCKeyCodeKeypadEqualSign, GCKeyCodeF13, GCKeyCodeF14, GCKeyCodeF15, GCKeyCodeF16, GCKeyCodeF17, GCKeyCodeF18,
    GCKeyCodeF19, GCKeyCodeF20, GCKeyCodeInternational1, GCKeyCodeInternational2, GCKeyCodeInternational3, GCKeyCodeInternational4,
    GCKeyCodeInternational5, GCKeyCodeInternational6, GCKeyCodeInternational7, GCKeyCodeInternational8, GCKeyCodeInternational9,
    GCKeyCodeLANG1, GCKeyCodeLANG2, GCKeyCodeLANG3, GCKeyCodeLANG4, GCKeyCodeLANG5, GCKeyCodeLANG6, GCKeyCodeLANG7, GCKeyCodeLANG8,
    GCKeyCodeLANG9, GCKeyCodeLeftControl, GCKeyCodeLeftShift, GCKeyCodeLeftAlt, GCKeyCodeLeftGUI, GCKeyCodeRightControl,
    GCKeyCodeRightShift, GCKeyCodeRightAlt, GCKeyCodeRightGUI;
extern NSNotificationName const GCKeyboardDidConnectNotification, GCKeyboardDidDisconnectNotification, GCMouseDidConnectNotification,
    GCMouseDidDisconnectNotification, GCMouseDidBecomeCurrentNotification, GCMouseDidStopBeingCurrentNotification;
@class GCKeyboardInput, GCMouseInput;
typedef void (^GCKeyboardValueChangedHandler)(GCKeyboardInput *keyboard, GCControllerButtonInput *key, GCKeyCode keyCode, BOOL pressed);
@interface GCKeyboardInput : GCPhysicalInputProfile
@property(copy) GCKeyboardValueChangedHandler keyChangedHandler;
@property(readonly, getter=isAnyKeyPressed) BOOL anyKeyPressed;
- (GCControllerButtonInput *)buttonForKeyCode:(GCKeyCode)code;
@end
@interface GCKeyboard : NSObject <GCDevice>
@property(class, readonly) GCKeyboard *coalescedKeyboard;
@property(readonly) GCKeyboardInput *keyboardInput;
@property(retain) dispatch_queue_t handlerQueue;
@property(readonly, copy) NSString *vendorName, *productCategory;
@property(readonly, retain) GCPhysicalInputProfile *physicalInputProfile;
@end
typedef void (^GCMouseMoved)(GCMouseInput *mouse, float deltaX, float deltaY);
@interface GCDeviceCursor : GCControllerDirectionPad @end
@interface GCMouseInput : GCPhysicalInputProfile
@property(copy) GCMouseMoved mouseMovedHandler;
@property(readonly) GCDeviceCursor *scroll;
@property(readonly) GCControllerButtonInput *leftButton, *rightButton, *middleButton;
@property(readonly) NSArray<GCControllerButtonInput *> *auxiliaryButtons;
@end
@interface GCMouse : NSObject <GCDevice>
+ (NSArray<GCMouse *> *)mice;
@property(class, readonly) GCMouse *current;
@property(readonly) GCMouseInput *mouseInput;
@property(retain) dispatch_queue_t handlerQueue;
@property(readonly, copy) NSString *vendorName, *productCategory;
@property(readonly, retain) GCPhysicalInputProfile *physicalInputProfile;
@end
