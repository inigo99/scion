/* gc.m — GameController + CoreHaptics for the guest (GameController.dylib; CoreHaptics maps onto it).
 * A thread polls the host's controllers (UI_PAD: XInput on Windows) at ~125 Hz and hands changes to the main queue,
 * where GCController objects are created (GCControllerDidConnectNotification), updated and their handlers called.
 * The same thread mixes the running haptic players into the two rumble motors (UI_RUMBLE). MRC. */
#import <GameController/GameController.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <math.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

#include "../uibridge.h"
#import <objc/runtime.h>
void *objc_autoreleasePoolPush(void); void objc_autoreleasePoolPop(void *);
@interface GCControllerElement (MW) - (void)_mwSetCollection:(GCControllerElement *)c; @end

int64_t _scion_ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
#define U(x) ((uint64_t)(uintptr_t)(x))
uint64_t mach_absolute_time(void);
static double now_s(void) { return mach_absolute_time() * 1e-9; } /* scion's mach time is in ns */

NSString *const GCControllerDidConnectNotification = @"GCControllerDidConnectNotification";
NSString *const GCControllerDidDisconnectNotification = @"GCControllerDidDisconnectNotification";
NSString *const GCControllerDidBecomeCurrentNotification = @"GCControllerDidBecomeCurrentNotification";
NSString *const GCControllerDidStopBeingCurrentNotification = @"GCControllerDidStopBeingCurrentNotification";
NSString *const GCControllerUserCustomizationsDidChangeNotification = @"GCControllerUserCustomizationsDidChangeNotification";
NSString *const GCHapticsLocalityDefault = @"Default", *const GCHapticsLocalityAll = @"All", *const GCHapticsLocalityHandles = @"Handles",
    *const GCHapticsLocalityLeftHandle = @"LeftHandle", *const GCHapticsLocalityRightHandle = @"RightHandle",
    *const GCHapticsLocalityTriggers = @"Triggers", *const GCHapticsLocalityLeftTrigger = @"LeftTrigger", *const GCHapticsLocalityRightTrigger = @"RightTrigger";
const float GCHapticDurationInfinite = INFINITY;
NSString *const GCInputButtonA = @"Button A", *const GCInputButtonB = @"Button B", *const GCInputButtonX = @"Button X", *const GCInputButtonY = @"Button Y",
    *const GCInputLeftShoulder = @"Left Shoulder", *const GCInputRightShoulder = @"Right Shoulder", *const GCInputLeftTrigger = @"Left Trigger",
    *const GCInputRightTrigger = @"Right Trigger", *const GCInputDirectionPad = @"Direction Pad", *const GCInputLeftThumbstick = @"Left Thumbstick",
    *const GCInputRightThumbstick = @"Right Thumbstick", *const GCInputLeftThumbstickButton = @"Left Thumbstick Button",
    *const GCInputRightThumbstickButton = @"Right Thumbstick Button", *const GCInputButtonMenu = @"Button Menu",
    *const GCInputButtonOptions = @"Button Options", *const GCInputButtonHome = @"Button Home";

/* ======================================================================= elements */
@implementation GCControllerElement
- (void)dealloc { [_localizedName release]; [_unmappedLocalizedName release]; [_sfSymbolsName release]; [_unmappedSfSymbolsName release]; [super dealloc]; }
- (GCControllerElement *)collection { return objc_getAssociatedObject(self, "mw_collection"); }
- (void)_mwSetCollection:(GCControllerElement *)c { objc_setAssociatedObject(self, "mw_collection", c, 0 /* assign */); }
- (BOOL)isAnalog { return NO; }
- (BOOL)isBoundToSystemGesture { return NO; }
- (NSSet *)aliases { return [NSSet setWithObject:_localizedName ? _localizedName : @""]; }
@end

@interface GCControllerButtonInput () { @public float _v; BOOL _analog; } @end
@implementation GCControllerButtonInput
- (void)dealloc { [_valueChangedHandler release]; [_pressedChangedHandler release]; [_touchedChangedHandler release]; [super dealloc]; }
- (float)value { return _v; }
- (BOOL)isPressed { return _v > 0; }
- (BOOL)isTouched { return _v > 0; }
- (BOOL)isAnalog { return _analog; }
- (void)setValue:(float)v { _v = v < 0 ? 0 : v > 1 ? 1 : v; } /* snapshots: no handlers */
/* returns YES if it changed; handlers are called by the gamepad (in AppKit's order: element, then collection, then pad) */
- (BOOL)_mwSet:(float)v {
    v = v < 0 ? 0 : v > 1 ? 1 : v;
    if (v == _v) return NO;
    BOOL was = _v > 0;
    _v = v;
    if (_valueChangedHandler) _valueChangedHandler(self, _v, _v > 0);
    if (_pressedChangedHandler && was != (_v > 0)) _pressedChangedHandler(self, _v, _v > 0);
    if (_touchedChangedHandler && was != (_v > 0)) _touchedChangedHandler(self, _v, _v > 0, _v > 0);
    return YES;
}
@end
@interface GCControllerAxisInput () { @public float _v; } @end
@implementation GCControllerAxisInput
- (void)dealloc { [_valueChangedHandler release]; [super dealloc]; }
- (float)value { return _v; }
- (BOOL)isAnalog { return YES; }
- (void)setValue:(float)v { _v = v < -1 ? -1 : v > 1 ? 1 : v; }
- (BOOL)_mwSet:(float)v {
    v = v < -1 ? -1 : v > 1 ? 1 : v;
    if (v == _v) return NO;
    _v = v;
    if (_valueChangedHandler) _valueChangedHandler(self, _v);
    return YES;
}
@end
@implementation GCControllerDirectionPad { BOOL _analog; }
- (instancetype)_mwInit:(NSString *)name analog:(BOOL)analog {
    if (!(self = [super init])) return nil;
    self.localizedName = name; _analog = analog;
    _xAxis = [[GCControllerAxisInput alloc] init]; _yAxis = [[GCControllerAxisInput alloc] init];
    _up = [[GCControllerButtonInput alloc] init]; _down = [[GCControllerButtonInput alloc] init];
    _left = [[GCControllerButtonInput alloc] init]; _right = [[GCControllerButtonInput alloc] init];
    for (GCControllerElement *e in @[_xAxis, _yAxis, _up, _down, _left, _right]) [e _mwSetCollection:self];
    return self;
}
- (void)dealloc { [_xAxis release]; [_yAxis release]; [_up release]; [_down release]; [_left release]; [_right release]; [_valueChangedHandler release]; [super dealloc]; }
- (BOOL)isAnalog { return _analog; }
- (void)setValueForXAxis:(float)x yAxis:(float)y { [_xAxis setValue:x]; [_yAxis setValue:y]; }
- (BOOL)_mwSetX:(float)x y:(float)y {
    BOOL c = NO;
    c |= [_xAxis _mwSet:x]; c |= [_yAxis _mwSet:y];
    c |= [_right _mwSet:x > 0 ? x : 0]; c |= [_left _mwSet:x < 0 ? -x : 0];
    c |= [_up _mwSet:y > 0 ? y : 0]; c |= [_down _mwSet:y < 0 ? -y : 0];
    if (c && _valueChangedHandler) _valueChangedHandler(self, _xAxis->_v, _yAxis->_v);
    return c;
}
@end

/* ======================================================================= profiles */
@implementation GCPhysicalInputProfile { @protected NSMutableDictionary *_elems; NSTimeInterval _stamp; id<GCDevice> _dev; }
- (void)dealloc { [_elems release]; [_valueDidChangeHandler release]; [super dealloc]; }
- (id<GCDevice>)device { return _dev; }
- (NSTimeInterval)lastEventTimestamp { return _stamp; }
- (BOOL)hasRemappedElements { return NO; }
- (NSDictionary *)elements { return [[_elems copy] autorelease]; }
- (NSDictionary *)_mwOfClass:(Class)c {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in _elems) if ([_elems[k] isKindOfClass:c]) d[k] = _elems[k];
    return d;
}
- (NSDictionary *)buttons { return [self _mwOfClass:[GCControllerButtonInput class]]; }
- (NSDictionary *)axes { return [self _mwOfClass:[GCControllerAxisInput class]]; }
- (NSDictionary *)dpads { return [self _mwOfClass:[GCControllerDirectionPad class]]; }
- (NSSet *)allElements { return [NSSet setWithArray:[_elems allValues]]; }
- (GCControllerElement *)objectForKeyedSubscript:(NSString *)k { return _elems[k]; }
- (instancetype)capture { return [self retain]; }
@end

@implementation GCExtendedGamepad
static GCControllerButtonInput *button(NSString *name, BOOL analog) {
    GCControllerButtonInput *b = [[[GCControllerButtonInput alloc] init] autorelease];
    b.localizedName = name; b->_analog = analog;
    return b;
}
- (instancetype)_mwInitWithController:(GCController *)c {
    if (!(self = [super init])) return nil;
    _controller = c; _dev = c;
    _buttonA = [button(GCInputButtonA, NO) retain]; _buttonB = [button(GCInputButtonB, NO) retain];
    _buttonX = [button(GCInputButtonX, NO) retain]; _buttonY = [button(GCInputButtonY, NO) retain];
    _leftShoulder = [button(GCInputLeftShoulder, NO) retain]; _rightShoulder = [button(GCInputRightShoulder, NO) retain];
    _leftTrigger = [button(GCInputLeftTrigger, YES) retain]; _rightTrigger = [button(GCInputRightTrigger, YES) retain];
    _leftThumbstickButton = [button(GCInputLeftThumbstickButton, NO) retain]; _rightThumbstickButton = [button(GCInputRightThumbstickButton, NO) retain];
    _buttonMenu = [button(GCInputButtonMenu, NO) retain]; _buttonOptions = [button(GCInputButtonOptions, NO) retain];
    _buttonHome = [button(GCInputButtonHome, NO) retain];
    _dpad = [[GCControllerDirectionPad alloc] _mwInit:GCInputDirectionPad analog:NO];
    _leftThumbstick = [[GCControllerDirectionPad alloc] _mwInit:GCInputLeftThumbstick analog:YES];
    _rightThumbstick = [[GCControllerDirectionPad alloc] _mwInit:GCInputRightThumbstick analog:YES];
    _elems = [[NSMutableDictionary alloc] init];
    for (GCControllerElement *e in @[_buttonA, _buttonB, _buttonX, _buttonY, _leftShoulder, _rightShoulder, _leftTrigger, _rightTrigger,
                                    _leftThumbstickButton, _rightThumbstickButton, _buttonMenu, _buttonOptions, _buttonHome, _dpad,
                                    _leftThumbstick, _rightThumbstick])
        _elems[e.localizedName] = e;
    return self;
}
- (void)dealloc {
    for (id e in @[_buttonA, _buttonB, _buttonX, _buttonY, _leftShoulder, _rightShoulder, _leftTrigger, _rightTrigger, _leftThumbstickButton,
                   _rightThumbstickButton, _buttonMenu, _buttonOptions, _buttonHome, _dpad, _leftThumbstick, _rightThumbstick]) [e release];
    [_valueChangedHandler release];
    [super dealloc];
}
- (void)_mwChanged:(GCControllerElement *)e {
    if (_valueChangedHandler) _valueChangedHandler(self, e);
    if (self.valueDidChangeHandler) self.valueDidChangeHandler(self, e);
}
/* the state from the host; fires the handlers of what changed */
- (void)_mwApply:(const MwPad *)p {
    _stamp = now_s();
    struct { GCControllerButtonInput *b; float v; } bs[] = {
        {_buttonA, (p->buttons & UI_PAD_A) ? 1 : 0}, {_buttonB, (p->buttons & UI_PAD_B) ? 1 : 0}, {_buttonX, (p->buttons & UI_PAD_X) ? 1 : 0},
        {_buttonY, (p->buttons & UI_PAD_Y) ? 1 : 0}, {_leftShoulder, (p->buttons & UI_PAD_LB) ? 1 : 0}, {_rightShoulder, (p->buttons & UI_PAD_RB) ? 1 : 0},
        {_leftTrigger, p->lt}, {_rightTrigger, p->rt}, {_leftThumbstickButton, (p->buttons & UI_PAD_LS) ? 1 : 0},
        {_rightThumbstickButton, (p->buttons & UI_PAD_RS) ? 1 : 0}, {_buttonMenu, (p->buttons & UI_PAD_MENU) ? 1 : 0},
        {_buttonOptions, (p->buttons & UI_PAD_VIEW) ? 1 : 0}, {_buttonHome, (p->buttons & UI_PAD_HOME) ? 1 : 0},
    };
    for (unsigned i = 0; i < sizeof bs / sizeof *bs; i++) if ([bs[i].b _mwSet:bs[i].v]) [self _mwChanged:bs[i].b];
    float dx = ((p->buttons & UI_PAD_RIGHT) ? 1 : 0) - ((p->buttons & UI_PAD_LEFT) ? 1 : 0);
    float dy = ((p->buttons & UI_PAD_UP) ? 1 : 0) - ((p->buttons & UI_PAD_DOWN) ? 1 : 0);
    if ([_dpad _mwSetX:dx y:dy]) [self _mwChanged:_dpad];
    if ([_leftThumbstick _mwSetX:p->lx y:p->ly]) [self _mwChanged:_leftThumbstick];
    if ([_rightThumbstick _mwSetX:p->rx y:p->ry]) [self _mwChanged:_rightThumbstick];
}
- (GCExtendedGamepad *)saveSnapshot {
    GCExtendedGamepad *s = [[[[self class] alloc] _mwInitWithController:nil] autorelease];
    [s setStateFromExtendedGamepad:self];
    return s;
}
- (void)setStateFromExtendedGamepad:(GCExtendedGamepad *)g {
    for (NSString *k in _elems) {
        id a = _elems[k], b = [g objectForKeyedSubscript:k];
        if ([a isKindOfClass:[GCControllerButtonInput class]]) [(GCControllerButtonInput *)a setValue:[(GCControllerButtonInput *)b value]];
        else if ([a isKindOfClass:[GCControllerDirectionPad class]])
            [(GCControllerDirectionPad *)a setValueForXAxis:[[(GCControllerDirectionPad *)b xAxis] value] yAxis:[[(GCControllerDirectionPad *)b yAxis] value]];
    }
}
@end
@implementation GCXboxGamepad
- (GCControllerButtonInput *)paddleButton1 { return nil; }
- (GCControllerButtonInput *)paddleButton2 { return nil; }
- (GCControllerButtonInput *)paddleButton3 { return nil; }
- (GCControllerButtonInput *)paddleButton4 { return nil; }
- (GCControllerButtonInput *)buttonShare { return nil; }
@end

/* ======================================================================= CoreHaptics */
NSString *const CHHapticEventTypeHapticTransient = @"HapticTransient", *const CHHapticEventTypeHapticContinuous = @"HapticContinuous",
    *const CHHapticEventTypeAudioContinuous = @"AudioContinuous", *const CHHapticEventTypeAudioCustom = @"AudioCustom";
NSString *const CHHapticEventParameterIDHapticIntensity = @"HapticIntensity", *const CHHapticEventParameterIDHapticSharpness = @"HapticSharpness",
    *const CHHapticEventParameterIDAttackTime = @"AttackTime", *const CHHapticEventParameterIDDecayTime = @"DecayTime",
    *const CHHapticEventParameterIDReleaseTime = @"ReleaseTime", *const CHHapticEventParameterIDSustained = @"Sustained",
    *const CHHapticEventParameterIDAudioVolume = @"AudioVolume", *const CHHapticEventParameterIDAudioPitch = @"AudioPitch",
    *const CHHapticEventParameterIDAudioPan = @"AudioPan", *const CHHapticEventParameterIDAudioBrightness = @"AudioBrightness";
NSString *const CHHapticDynamicParameterIDHapticIntensityControl = @"HapticIntensityControl",
    *const CHHapticDynamicParameterIDHapticSharpnessControl = @"HapticSharpnessControl",
    *const CHHapticDynamicParameterIDHapticAttackTimeControl = @"HapticAttackTimeControl",
    *const CHHapticDynamicParameterIDHapticDecayTimeControl = @"HapticDecayTimeControl",
    *const CHHapticDynamicParameterIDHapticReleaseTimeControl = @"HapticReleaseTimeControl",
    *const CHHapticDynamicParameterIDAudioVolumeControl = @"AudioVolumeControl";
const NSTimeInterval CHHapticTimeImmediate = 0;
NSString *const CHHapticErrorDomain = @"com.apple.CoreHaptics", *const CoreHapticsErrorDomain = @"com.apple.CoreHaptics";
static NSError *ch_error(NSInteger code) { return [NSError errorWithDomain:CHHapticErrorDomain code:code userInfo:nil]; }

@implementation CHHapticEventParameter
- (instancetype)initWithParameterID:(NSString *)p value:(float)v { if ((self = [super init])) { _parameterID = [p copy]; _value = v; } return self; }
- (void)dealloc { [_parameterID release]; [super dealloc]; }
@end
@implementation CHHapticDynamicParameter
- (instancetype)initWithParameterID:(NSString *)p value:(float)v relativeTime:(NSTimeInterval)t {
    if ((self = [super init])) { _parameterID = [p copy]; _value = v; _relativeTime = t; }
    return self;
}
- (void)dealloc { [_parameterID release]; [super dealloc]; }
@end
@implementation CHHapticParameterCurveControlPoint
- (instancetype)initWithRelativeTime:(NSTimeInterval)t value:(float)v { if ((self = [super init])) { _relativeTime = t; _value = v; } return self; }
@end
@implementation CHHapticParameterCurve
- (instancetype)initWithParameterID:(NSString *)p controlPoints:(NSArray *)c relativeTime:(NSTimeInterval)t {
    if ((self = [super init])) { _parameterID = [p copy]; _controlPoints = [c copy]; _relativeTime = t; }
    return self;
}
- (void)dealloc { [_parameterID release]; [_controlPoints release]; [super dealloc]; }
@end
@implementation CHHapticEvent
- (instancetype)initWithEventType:(NSString *)t parameters:(NSArray *)p relativeTime:(NSTimeInterval)rt {
    return [self initWithEventType:t parameters:p relativeTime:rt duration:[t isEqualToString:CHHapticEventTypeHapticTransient] ? 0 : 1];
}
- (instancetype)initWithEventType:(NSString *)t parameters:(NSArray *)p relativeTime:(NSTimeInterval)rt duration:(NSTimeInterval)d {
    if ((self = [super init])) { _type = [t copy]; _eventParameters = [p copy]; _relativeTime = rt; _duration = d; }
    return self;
}
- (void)dealloc { [_type release]; [_eventParameters release]; [super dealloc]; }
@end

/* a pattern flattened for the mixer: haptic events only */
#define TRANSIENT_S 0.06 /* rumble motors need some time to spin: a transient "tap" lasts this long */
struct hev { double t, end; float intensity, sharpness; };
struct hdyn { double t; float intensity, sharpness; int has_i, has_s; };
@interface CHHapticPattern () { @public struct hev *_ev; int _nev; struct hdyn *_dyn; int _ndyn; double _dur; } @end
@implementation CHHapticPattern
- (instancetype)initWithEvents:(NSArray *)events parameters:(NSArray *)params error:(NSError **)err {
    if (!(self = [super init])) return nil;
    _ev = calloc([events count] + 1, sizeof *_ev);
    for (CHHapticEvent *e in events) {
        BOOL transient = [e.type isEqualToString:CHHapticEventTypeHapticTransient];
        if (!transient && ![e.type isEqualToString:CHHapticEventTypeHapticContinuous]) continue; /* audio events: no sound here */
        struct hev *h = &_ev[_nev++];
        h->t = e.relativeTime; h->intensity = 1; h->sharpness = 0.5f;
        h->end = h->t + (transient ? TRANSIENT_S : e.duration);
        for (CHHapticEventParameter *p in e.eventParameters) {
            if ([p.parameterID isEqualToString:CHHapticEventParameterIDHapticIntensity]) h->intensity = p.value;
            else if ([p.parameterID isEqualToString:CHHapticEventParameterIDHapticSharpness]) h->sharpness = p.value;
        }
        if (h->end > _dur) _dur = h->end;
    }
    _dyn = calloc([params count] + 1, sizeof *_dyn);
    for (CHHapticDynamicParameter *p in params) {
        struct hdyn *d = &_dyn[_ndyn++];
        d->t = p.relativeTime;
        if ([p.parameterID isEqualToString:CHHapticDynamicParameterIDHapticIntensityControl]) { d->intensity = p.value; d->has_i = 1; }
        else if ([p.parameterID isEqualToString:CHHapticDynamicParameterIDHapticSharpnessControl]) { d->sharpness = p.value; d->has_s = 1; }
        else _ndyn--;
    }
    return self;
}
/* ponytail: parameter curves are ignored (the events play at their own intensity) */
- (instancetype)initWithEvents:(NSArray *)events parameterCurves:(NSArray *)curves error:(NSError **)err { return [self initWithEvents:events parameters:@[] error:err]; }
/* AHAP: {"Pattern": [{"Event": {...}}, {"Parameter": {...}}]} */
- (instancetype)initWithDictionary:(NSDictionary *)d error:(NSError **)err {
    NSMutableArray *events = [NSMutableArray array], *params = [NSMutableArray array];
    for (NSDictionary *item in d[@"Pattern"]) {
        NSDictionary *e = item[@"Event"], *p = item[@"Parameter"];
        if (e) {
            NSMutableArray *ps = [NSMutableArray array];
            for (NSDictionary *x in e[@"EventParameters"])
                [ps addObject:[[[CHHapticEventParameter alloc] initWithParameterID:x[@"ParameterID"] value:[x[@"ParameterValue"] floatValue]] autorelease]];
            NSString *type = e[@"EventType"];
            [events addObject:[[[CHHapticEvent alloc] initWithEventType:type parameters:ps relativeTime:[e[@"Time"] doubleValue]
                duration:e[@"EventDuration"] ? [e[@"EventDuration"] doubleValue] : [type isEqualToString:CHHapticEventTypeHapticTransient] ? 0 : 1] autorelease]];
        } else if (p) {
            [params addObject:[[[CHHapticDynamicParameter alloc] initWithParameterID:p[@"ParameterID"] value:[p[@"ParameterValue"] floatValue]
                                                                       relativeTime:[p[@"Time"] doubleValue]] autorelease]];
        }
    }
    return [self initWithEvents:events parameters:params error:err];
}
- (void)dealloc { free(_ev); free(_dyn); [super dealloc]; }
- (NSTimeInterval)duration { return _dur; }
@end

static pthread_mutex_t g_hmu = PTHREAD_MUTEX_INITIALIZER;   /* haptic state: changed on any thread, mixed on the poll thread */
static NSMutableArray *g_running;                           /* running players */

@class _MWHapticPlayer;
@interface CHHapticEngine () { @public int _pad; float _wl, _wh; BOOL _running; } @end
@interface _MWHapticPlayer : NSObject <CHHapticAdvancedPatternPlayer> {
@public
    CHHapticEngine *_engine; CHHapticPattern *_pattern; double _start, _pausedAt; BOOL _paused;
    float _iscale, _soff; int _dynDone;
}
@end
@implementation _MWHapticPlayer
@synthesize isMuted = _isMuted, loopEnabled = _loopEnabled, loopEnd = _loopEnd, playbackRate = _playbackRate, completionHandler = _completionHandler;
- (instancetype)_mwInit:(CHHapticEngine *)e pattern:(CHHapticPattern *)p {
    if ((self = [super init])) { _engine = [e retain]; _pattern = [p retain]; _iscale = 1; _playbackRate = 1; }
    return self;
}
- (void)dealloc { [_engine release]; [_pattern release]; [_completionHandler release]; [super dealloc]; }
- (BOOL)startAtTime:(NSTimeInterval)t error:(NSError **)e {
    if (!_engine->_running) { if (e) *e = ch_error(-4805 /* engine not running */); return NO; }
    pthread_mutex_lock(&g_hmu);
    _start = now_s(); _paused = NO; _dynDone = 0;
    if (![g_running containsObject:self]) [g_running addObject:self];
    pthread_mutex_unlock(&g_hmu);
    return YES;
}
- (BOOL)stopAtTime:(NSTimeInterval)t error:(NSError **)e {
    pthread_mutex_lock(&g_hmu); [g_running removeObjectIdenticalTo:self]; pthread_mutex_unlock(&g_hmu);
    return YES;
}
- (BOOL)cancelAndReturnError:(NSError **)e { return [self stopAtTime:0 error:e]; }
- (BOOL)sendParameters:(NSArray *)params atTime:(NSTimeInterval)t error:(NSError **)e {
    pthread_mutex_lock(&g_hmu);
    for (CHHapticDynamicParameter *p in params) {
        if ([p.parameterID isEqualToString:CHHapticDynamicParameterIDHapticIntensityControl]) _iscale = p.value;
        else if ([p.parameterID isEqualToString:CHHapticDynamicParameterIDHapticSharpnessControl]) _soff = p.value;
    }
    pthread_mutex_unlock(&g_hmu);
    return YES;
}
- (BOOL)scheduleParameterCurve:(CHHapticParameterCurve *)c atTime:(NSTimeInterval)t error:(NSError **)e { return YES; }
- (BOOL)pauseAtTime:(NSTimeInterval)t error:(NSError **)e { pthread_mutex_lock(&g_hmu); if (!_paused) { _paused = YES; _pausedAt = now_s(); } pthread_mutex_unlock(&g_hmu); return YES; }
- (BOOL)resumeAtTime:(NSTimeInterval)t error:(NSError **)e {
    pthread_mutex_lock(&g_hmu);
    if (_paused) { _start += now_s() - _pausedAt; _paused = NO; }
    if (![g_running containsObject:self]) { [g_running addObject:self]; }
    pthread_mutex_unlock(&g_hmu);
    return YES;
}
- (BOOL)seekToOffset:(NSTimeInterval)o error:(NSError **)e { pthread_mutex_lock(&g_hmu); _start = now_s() - o; _dynDone = 0; pthread_mutex_unlock(&g_hmu); return YES; }
@end

@interface _MWHapticCaps : NSObject <CHHapticDeviceCapability> @end
@implementation _MWHapticCaps
- (BOOL)supportsHaptics { return NO; } /* the Mac itself (no Taptic Engine to drive here) */
- (BOOL)supportsAudio { return NO; }
@end
@implementation CHHapticEngine
+ (id<CHHapticDeviceCapability>)capabilitiesForHardware { return [[[_MWHapticCaps alloc] init] autorelease]; }
- (instancetype)initAndReturnError:(NSError **)e { if ((self = [super init])) { _pad = -1; _autoShutdownEnabled = NO; } return self; }
- (instancetype)_mwInitPad:(int)pad low:(float)wl high:(float)wh { if ((self = [super init])) { _pad = pad; _wl = wl; _wh = wh; } return self; }
- (void)dealloc { [_stoppedHandler release]; [_resetHandler release]; [super dealloc]; }
- (NSTimeInterval)currentTime { return now_s(); }
- (BOOL)startAndReturnError:(NSError **)e { _running = YES; return YES; }
- (void)startWithCompletionHandler:(CHHapticCompletionHandler)h { _running = YES; if (h) h(nil); }
- (void)_mwStopPlayers {
    pthread_mutex_lock(&g_hmu);
    for (NSInteger i = (NSInteger)[g_running count] - 1; i >= 0; i--)
        if (((_MWHapticPlayer *)g_running[(NSUInteger)i])->_engine == self) [g_running removeObjectAtIndex:(NSUInteger)i];
    pthread_mutex_unlock(&g_hmu);
}
- (void)stopWithCompletionHandler:(CHHapticCompletionHandler)h { _running = NO; [self _mwStopPlayers]; if (h) h(nil); }
- (void)notifyWhenPlayersFinished:(CHHapticEngineFinishedHandler)h { } /* ponytail: not reported */
- (id<CHHapticPatternPlayer>)createPlayerWithPattern:(CHHapticPattern *)p error:(NSError **)e { return [self createAdvancedPlayerWithPattern:p error:e]; }
- (id<CHHapticAdvancedPatternPlayer>)createAdvancedPlayerWithPattern:(CHHapticPattern *)p error:(NSError **)e {
    if (!p) { if (e) *e = ch_error(-4810); return nil; }
    return [[[_MWHapticPlayer alloc] _mwInit:self pattern:p] autorelease];
}
- (BOOL)playPatternFromData:(NSData *)d error:(NSError **)e {
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:e];
    CHHapticPattern *p = j ? [[[CHHapticPattern alloc] initWithDictionary:j error:e] autorelease] : nil;
    id<CHHapticPatternPlayer> pl = p ? [self createPlayerWithPattern:p error:e] : nil;
    return pl && [pl startAtTime:0 error:e];
}
- (BOOL)playPatternFromURL:(NSURL *)u error:(NSError **)e { NSData *d = [NSData dataWithContentsOfURL:u]; return d && [self playPatternFromData:d error:e]; }
@end

/* the motors of one controller: sum of what its running players play now (called with g_hmu held) */
static void mix(int pad, float *low, float *high) {
    *low = *high = 0;
    double t = now_s();
    for (NSInteger i = (NSInteger)[g_running count] - 1; i >= 0; i--) {
        _MWHapticPlayer *p = g_running[(NSUInteger)i];
        CHHapticEngine *e = p->_engine;
        if (e->_pad != pad || !e->_running || p->_paused || p.isMuted || e.isMutedForHaptics) continue;
        CHHapticPattern *pat = p->_pattern;
        double rt = (t - p->_start) * p.playbackRate;
        if (p.loopEnabled && pat->_dur > 0 && pat->_dur < INFINITY) rt = fmod(rt, p.loopEnd > 0 ? p.loopEnd : pat->_dur);
        else if (rt > pat->_dur) { /* finished */
            [[p retain] autorelease];
            [g_running removeObjectAtIndex:(NSUInteger)i];
            if (p.completionHandler) { id h = [p.completionHandler copy]; dispatch_async(dispatch_get_main_queue(), ^{ ((CHHapticAdvancedPatternPlayerCompletionHandler)h)(nil); [h release]; }); }
            continue;
        }
        while (p->_dynDone < pat->_ndyn && pat->_dyn[p->_dynDone].t <= rt) { /* the pattern's own dynamic parameters */
            struct hdyn *d = &pat->_dyn[p->_dynDone++];
            if (d->has_i) p->_iscale = d->intensity;
            if (d->has_s) p->_soff = d->sharpness;
        }
        for (int k = 0; k < pat->_nev; k++) {
            struct hev *h = &pat->_ev[k];
            if (rt < h->t || rt >= h->end) continue;
            float in = h->intensity * p->_iscale, sh = h->sharpness + p->_soff;
            in = in < 0 ? 0 : in > 1 ? 1 : in; sh = sh < 0 ? 0 : sh > 1 ? 1 : sh;
            /* sharpness moves the energy from the heavy (low) motor to the light (high) one */
            float l = in * fminf(1, 1.5f - sh), hh = in * fminf(1, 0.5f + sh);
            *low += l * e->_wl; *high += hh * e->_wh;
        }
    }
    *low = fminf(*low, 1); *high = fminf(*high, 1);
}

@implementation GCDeviceHaptics { @public int _pad; }
- (NSSet *)supportedLocalities {
    return [NSSet setWithObjects:GCHapticsLocalityDefault, GCHapticsLocalityAll, GCHapticsLocalityHandles, GCHapticsLocalityLeftHandle,
                                 GCHapticsLocalityRightHandle, nil];
}
- (CHHapticEngine *)createEngineWithLocality:(GCHapticsLocality)l {
    float wl = 1, wh = 1;
    if ([l isEqualToString:GCHapticsLocalityLeftHandle]) wh = 0;
    else if ([l isEqualToString:GCHapticsLocalityRightHandle]) wl = 0;
    else if ([l hasSuffix:@"Trigger"] || [l isEqualToString:GCHapticsLocalityTriggers]) wl = wh = 0; /* XInput has no trigger motors */
    else if (![self.supportedLocalities containsObject:l]) return nil;
    CHHapticEngine *e = [[[CHHapticEngine alloc] _mwInitPad:_pad low:wl high:wh] autorelease];
    pthread_mutex_lock(&g_hmu);
    NSMutableArray *engines = objc_getAssociatedObject(self, "mw_engines");
    if (!engines) { engines = [NSMutableArray array]; objc_setAssociatedObject(self, "mw_engines", engines, 1); }
    [engines addObject:[NSValue valueWithPointer:e]];
    pthread_mutex_unlock(&g_hmu);
    return e;
}
@end

/* ======================================================================= GCController */
static GCController *g_slot[4];
static NSMutableArray *g_controllers;
static GCController *g_current;
@interface GCController () { @public int _index; } - (void)_mwSetup:(int)i pad:(MwPad *)p; - (void)_mwSnapshot; @end
@implementation GCController
@synthesize handlerQueue = _handlerQueue;
+ (NSArray *)controllers { return g_controllers ? [[g_controllers copy] autorelease] : @[]; }
+ (GCController *)current { return g_current; }
+ (BOOL)shouldMonitorBackgroundEvents { return NO; }
+ (void)setShouldMonitorBackgroundEvents:(BOOL)f { }
+ (void)startWirelessControllerDiscoveryWithCompletionHandler:(void (^)(void))h { if (h) dispatch_async(dispatch_get_main_queue(), h); }
+ (void)stopWirelessControllerDiscovery { }
+ (GCController *)controllerWithExtendedGamepad {
    GCController *c = [[[GCController alloc] init] autorelease];
    c->_index = -1;
    [c _mwSnapshot];
    return c;
}
- (instancetype)init { if ((self = [super init])) { _playerIndex = GCControllerPlayerIndexUnset; _handlerQueue = dispatch_get_main_queue(); } return self; }
- (void)dealloc { [_vendorName release]; [_productCategory release]; [_extendedGamepad release]; [_haptics release]; [_controllerPausedHandler release]; [super dealloc]; }
- (GCPhysicalInputProfile *)physicalInputProfile { return _extendedGamepad; }
- (void)_mwSnapshot { _extendedGamepad = [[GCXboxGamepad alloc] _mwInitWithController:self]; }
- (void)_mwSetup:(int)i pad:(MwPad *)p {
    _index = i;
    p->name[sizeof p->name - 1] = 0;
    _vendorName = [[NSString alloc] initWithUTF8String:p->name[0] ? p->name : "Xbox Wireless Controller"];
    _productCategory = [@"Xbox One" copy];
    _extendedGamepad = [[GCXboxGamepad alloc] _mwInitWithController:self];
    if (p->has_rumble) { GCDeviceHaptics *h = [[GCDeviceHaptics alloc] init]; h->_pad = i; _haptics = h; }
    [_extendedGamepad _mwApply:p];
}
- (GCMicroGamepad *)microGamepad { return nil; }
- (GCGamepad *)gamepad { return nil; }
- (GCMotion *)motion { return nil; }
- (GCDeviceLight *)light { return nil; }
- (GCDeviceBattery *)battery { return nil; }
- (BOOL)isAttachedToDevice { return NO; }
- (BOOL)isSnapshot { return _index < 0; }
- (instancetype)capture {
    GCController *c = [GCController controllerWithExtendedGamepad];
    [c.extendedGamepad setStateFromExtendedGamepad:_extendedGamepad];
    return c;
}
@end

static void set_current(GCController *c) {
    if (c == g_current) return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (g_current) [nc postNotificationName:GCControllerDidStopBeingCurrentNotification object:g_current];
    g_current = c;
    if (c) [nc postNotificationName:GCControllerDidBecomeCurrentNotification object:c];
}
/* main queue: a new state for slot i (connected = 0: unplugged) */
static void apply(int i, int connected, MwPad p) {
    GCController *c = g_slot[i];
    if (!connected) {
        if (!c) return;
        g_slot[i] = nil;
        [g_controllers removeObjectIdenticalTo:c];
        /* its engines stop: the controller is gone */
        NSArray *engines = objc_getAssociatedObject(c.haptics, "mw_engines");
        for (NSValue *v in engines) {
            CHHapticEngine *e = [v pointerValue];
            [e _mwStopPlayers]; e->_running = NO; e->_pad = -1;
            if (e.stoppedHandler) e.stoppedHandler(CHHapticEngineStoppedReasonGameControllerDisconnect);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:GCControllerDidDisconnectNotification object:c];
        if (g_current == c) set_current([g_controllers firstObject]);
        [c release];
        return;
    }
    if (!c) {
        c = [[GCController alloc] init];
        [c _mwSetup:i pad:&p];
        g_slot[i] = c;
        if (!g_controllers) g_controllers = [[NSMutableArray alloc] init];
        [g_controllers addObject:c];
        [[NSNotificationCenter defaultCenter] postNotificationName:GCControllerDidConnectNotification object:c];
        if (!g_current) set_current(c);
        return;
    }
    dispatch_queue_t q = c.handlerQueue;
    if (!q || q == dispatch_get_main_queue()) [(id)c.extendedGamepad _mwApply:&p];
    else { [c retain]; dispatch_async(q, ^{ [(id)c.extendedGamepad _mwApply:&p]; [c release]; }); }
    if (g_current != c) set_current(c);
}

/* ======================================================================= GCKeyboard / GCMouse
 * Raw input from the host (UI_RAW_NEXT: Windows Raw Input while one of the app's windows is in front): HID key codes and
 * unaccelerated mouse counts. One coalesced keyboard and one mouse, connected from launch, as on a Mac with both. */
const GCKeyCode GCKeyCodeKeyA = 0x4, GCKeyCodeKeyB = 0x5, GCKeyCodeKeyC = 0x6, GCKeyCodeKeyD = 0x7, GCKeyCodeKeyE = 0x8, GCKeyCodeKeyF =
    0x9, GCKeyCodeKeyG = 0xA, GCKeyCodeKeyH = 0xB, GCKeyCodeKeyI = 0xC, GCKeyCodeKeyJ = 0xD, GCKeyCodeKeyK = 0xE, GCKeyCodeKeyL = 0xF,
    GCKeyCodeKeyM = 0x10, GCKeyCodeKeyN = 0x11, GCKeyCodeKeyO = 0x12, GCKeyCodeKeyP = 0x13, GCKeyCodeKeyQ = 0x14, GCKeyCodeKeyR = 0x15,
    GCKeyCodeKeyS = 0x16, GCKeyCodeKeyT = 0x17, GCKeyCodeKeyU = 0x18, GCKeyCodeKeyV = 0x19, GCKeyCodeKeyW = 0x1A, GCKeyCodeKeyX = 0x1B,
    GCKeyCodeKeyY = 0x1C, GCKeyCodeKeyZ = 0x1D, GCKeyCodeOne = 0x1E, GCKeyCodeTwo = 0x1F, GCKeyCodeThree = 0x20, GCKeyCodeFour = 0x21,
    GCKeyCodeFive = 0x22, GCKeyCodeSix = 0x23, GCKeyCodeSeven = 0x24, GCKeyCodeEight = 0x25, GCKeyCodeNine = 0x26, GCKeyCodeZero = 0x27,
    GCKeyCodeReturnOrEnter = 0x28, GCKeyCodeEscape = 0x29, GCKeyCodeDeleteOrBackspace = 0x2A, GCKeyCodeTab = 0x2B, GCKeyCodeSpacebar = 0x2C,
    GCKeyCodeHyphen = 0x2D, GCKeyCodeEqualSign = 0x2E, GCKeyCodeOpenBracket = 0x2F, GCKeyCodeCloseBracket = 0x30, GCKeyCodeBackslash = 0x31,
    GCKeyCodeNonUSPound = 0x32, GCKeyCodeSemicolon = 0x33, GCKeyCodeQuote = 0x34, GCKeyCodeGraveAccentAndTilde = 0x35, GCKeyCodeComma =
    0x36, GCKeyCodePeriod = 0x37, GCKeyCodeSlash = 0x38, GCKeyCodeCapsLock = 0x39, GCKeyCodeF1 = 0x3A, GCKeyCodeF2 = 0x3B, GCKeyCodeF3 =
    0x3C, GCKeyCodeF4 = 0x3D, GCKeyCodeF5 = 0x3E, GCKeyCodeF6 = 0x3F, GCKeyCodeF7 = 0x40, GCKeyCodeF8 = 0x41, GCKeyCodeF9 = 0x42,
    GCKeyCodeF10 = 0x43, GCKeyCodeF11 = 0x44, GCKeyCodeF12 = 0x45, GCKeyCodePrintScreen = 0x46, GCKeyCodeScrollLock = 0x47, GCKeyCodePause =
    0x48, GCKeyCodeInsert = 0x49, GCKeyCodeHome = 0x4A, GCKeyCodePageUp = 0x4B, GCKeyCodeDeleteForward = 0x4C, GCKeyCodeEnd = 0x4D,
    GCKeyCodePageDown = 0x4E, GCKeyCodeRightArrow = 0x4F, GCKeyCodeLeftArrow = 0x50, GCKeyCodeDownArrow = 0x51, GCKeyCodeUpArrow = 0x52,
    GCKeyCodeKeypadNumLock = 0x53, GCKeyCodeKeypadSlash = 0x54, GCKeyCodeKeypadAsterisk = 0x55, GCKeyCodeKeypadHyphen = 0x56,
    GCKeyCodeKeypadPlus = 0x57, GCKeyCodeKeypadEnter = 0x58, GCKeyCodeKeypad1 = 0x59, GCKeyCodeKeypad2 = 0x5A, GCKeyCodeKeypad3 = 0x5B,
    GCKeyCodeKeypad4 = 0x5C, GCKeyCodeKeypad5 = 0x5D, GCKeyCodeKeypad6 = 0x5E, GCKeyCodeKeypad7 = 0x5F, GCKeyCodeKeypad8 = 0x60,
    GCKeyCodeKeypad9 = 0x61, GCKeyCodeKeypad0 = 0x62, GCKeyCodeKeypadPeriod = 0x63, GCKeyCodeNonUSBackslash = 0x64, GCKeyCodeApplication =
    0x65, GCKeyCodePower = 0x66, GCKeyCodeKeypadEqualSign = 0x67, GCKeyCodeF13 = 0x68, GCKeyCodeF14 = 0x69, GCKeyCodeF15 = 0x6A,
    GCKeyCodeF16 = 0x6B, GCKeyCodeF17 = 0x6C, GCKeyCodeF18 = 0x6D, GCKeyCodeF19 = 0x6E, GCKeyCodeF20 = 0x6F, GCKeyCodeInternational1 = 0x87,
    GCKeyCodeInternational2 = 0x88, GCKeyCodeInternational3 = 0x89, GCKeyCodeInternational4 = 0x8A, GCKeyCodeInternational5 = 0x8B,
    GCKeyCodeInternational6 = 0x8C, GCKeyCodeInternational7 = 0x8D, GCKeyCodeInternational8 = 0x8E, GCKeyCodeInternational9 = 0x8F,
    GCKeyCodeLANG1 = 0x90, GCKeyCodeLANG2 = 0x91, GCKeyCodeLANG3 = 0x92, GCKeyCodeLANG4 = 0x93, GCKeyCodeLANG5 = 0x94, GCKeyCodeLANG6 =
    0x95, GCKeyCodeLANG7 = 0x96, GCKeyCodeLANG8 = 0x97, GCKeyCodeLANG9 = 0x98, GCKeyCodeLeftControl = 0xE0, GCKeyCodeLeftShift = 0xE1,
    GCKeyCodeLeftAlt = 0xE2, GCKeyCodeLeftGUI = 0xE3, GCKeyCodeRightControl = 0xE4, GCKeyCodeRightShift = 0xE5, GCKeyCodeRightAlt = 0xE6,
    GCKeyCodeRightGUI = 0xE7;
NSString *const GCKeyboardDidConnectNotification = @"GCKeyboardDidConnectNotification", *const GCKeyboardDidDisconnectNotification = @"GCKeyboardDidDisconnectNotification",
    *const GCMouseDidConnectNotification = @"GCMouseDidConnectNotification", *const GCMouseDidDisconnectNotification = @"GCMouseDidDisconnectNotification",
    *const GCMouseDidBecomeCurrentNotification = @"GCMouseDidBecomeCurrentNotification", *const GCMouseDidStopBeingCurrentNotification = @"GCMouseDidStopBeingCurrentNotification";

@implementation GCKeyboardInput { NSMutableDictionary *_keys; int _down; }
- (instancetype)_mwInit { if ((self = [super init])) { _keys = [[NSMutableDictionary alloc] init]; _elems = [[NSMutableDictionary alloc] init]; } return self; }
- (void)dealloc { [_keys release]; [_keyChangedHandler release]; [super dealloc]; }
- (GCControllerButtonInput *)buttonForKeyCode:(GCKeyCode)code {
    NSNumber *k = @(code);
    GCControllerButtonInput *b = _keys[k];
    if (!b) {
        b = [[[GCControllerButtonInput alloc] init] autorelease];
        b.localizedName = [NSString stringWithFormat:@"Key %ld", code];
        _keys[k] = b; _elems[b.localizedName] = b;
    }
    return b;
}
- (BOOL)isAnyKeyPressed { return _down > 0; }
- (void)_mwKey:(GCKeyCode)code down:(BOOL)down {
    GCControllerButtonInput *b = [self buttonForKeyCode:code];
    BOOL was = b.pressed;
    if (![b _mwSet:down ? 1 : 0] && was == down) return; /* key repeat: no change */
    _down += down ? 1 : -1; if (_down < 0) _down = 0;
    _stamp = now_s();
    if (_keyChangedHandler) _keyChangedHandler(self, b, code, down);
    if (self.valueDidChangeHandler) self.valueDidChangeHandler(self, b);
}
@end
@implementation GCKeyboard
@synthesize handlerQueue = _handlerQueue;
static GCKeyboard *g_keyboard;
+ (GCKeyboard *)coalescedKeyboard { return g_keyboard; }
- (instancetype)_mwInit { if ((self = [super init])) { _keyboardInput = [[GCKeyboardInput alloc] _mwInit]; _handlerQueue = dispatch_get_main_queue(); } return self; }
- (NSString *)vendorName { return @"Keyboard"; }
- (NSString *)productCategory { return @"Keyboard"; }
- (GCPhysicalInputProfile *)physicalInputProfile { return _keyboardInput; }
@end
@implementation GCDeviceCursor
/* a scroll delta: not clamped to -1..1 like a stick */
- (BOOL)_mwSetX:(float)x y:(float)y {
    if (x == self.xAxis.value && y == self.yAxis.value) return NO;
    self.xAxis->_v = x; self.yAxis->_v = y;
    if (self.xAxis.valueChangedHandler) self.xAxis.valueChangedHandler(self.xAxis, x);
    if (self.yAxis.valueChangedHandler) self.yAxis.valueChangedHandler(self.yAxis, y);
    if (self.valueChangedHandler) self.valueChangedHandler(self, x, y);
    return YES;
}
- (void)setValueForXAxis:(float)x yAxis:(float)y { self.xAxis->_v = x; self.yAxis->_v = y; }
@end
@implementation GCMouseInput { NSArray *_aux; }
- (instancetype)_mwInit {
    if (!(self = [super init])) return nil;
    _leftButton = [button(@"Left Button", NO) retain]; _rightButton = [button(@"Right Button", NO) retain]; _middleButton = [button(@"Middle Button", NO) retain];
    _aux = [@[button(@"Button 4", NO), button(@"Button 5", NO)] retain];
    _scroll = [[GCDeviceCursor alloc] _mwInit:@"Scroll" analog:YES];
    _elems = [[NSMutableDictionary alloc] init];
    for (GCControllerElement *e in @[_leftButton, _rightButton, _middleButton, _scroll, _aux[0], _aux[1]]) _elems[e.localizedName] = e;
    return self;
}
- (void)dealloc { [_leftButton release]; [_rightButton release]; [_middleButton release]; [_aux release]; [_scroll release]; [_mouseMovedHandler release]; [super dealloc]; }
- (NSArray *)auxiliaryButtons { return _aux; }
- (void)_mwRaw:(const MwRaw *)r {
    _stamp = now_s();
    if (r->type == UI_RAW_MOVE) { if (_mouseMovedHandler) _mouseMovedHandler(self, r->dx, -r->dy); return; } /* GameController: y up */
    if (r->type == UI_RAW_SCROLL) {
        if ([_scroll _mwSetX:r->dx y:r->dy] && self.valueDidChangeHandler) self.valueDidChangeHandler(self, _scroll);
        [_scroll setValueForXAxis:0 yAxis:0]; /* a scroll is a delta: back to rest without events */
        return;
    }
    GCControllerButtonInput *b = r->code == 0 ? _leftButton : r->code == 1 ? _rightButton : r->code == 2 ? _middleButton
                               : r->code - 3 < [_aux count] ? _aux[r->code - 3] : nil;
    if ([b _mwSet:r->down ? 1 : 0] && self.valueDidChangeHandler) self.valueDidChangeHandler(self, b);
}
@end
@implementation GCMouse
@synthesize handlerQueue = _handlerQueue;
static GCMouse *g_mouse;
+ (NSArray *)mice { return g_mouse ? @[g_mouse] : @[]; }
+ (GCMouse *)current { return g_mouse; }
- (instancetype)_mwInit { if ((self = [super init])) { _mouseInput = [[GCMouseInput alloc] _mwInit]; _handlerQueue = dispatch_get_main_queue(); } return self; }
- (NSString *)vendorName { return @"Mouse"; }
- (NSString *)productCategory { return @"Mouse"; }
- (GCPhysicalInputProfile *)physicalInputProfile { return _mouseInput; }
@end

static void raw_apply(MwRaw *rs, int n) {
    for (int i = 0; i < n; i++) {
        MwRaw *r = &rs[i];
        if (r->type == UI_RAW_KEY) [g_keyboard.keyboardInput _mwKey:r->code down:r->down != 0];
        else [g_mouse.mouseInput _mwRaw:r];
    }
}
static void *raw_thread(void *unused) {
    enum { MAX = 64 };
    for (;;) {
        MwRaw *rs = malloc(MAX * sizeof *rs);
        int n = 0;
        if (_scion_ui(UI_RAW_NEXT, U(&rs[0]), (uint64_t)-1, 0, 0, 0) != 1) { free(rs); usleep(10000); continue; }
        n = 1;
        while (n < MAX && _scion_ui(UI_RAW_NEXT, U(&rs[n]), 0, 0, 0, 0) == 1) {
            if (rs[n].type == UI_RAW_MOVE && rs[n - 1].type == UI_RAW_MOVE) { rs[n - 1].dx += rs[n].dx; rs[n - 1].dy += rs[n].dy; continue; } /* coalesce */
            n++;
        }
        dispatch_queue_t q = g_keyboard.handlerQueue ? g_keyboard.handlerQueue : dispatch_get_main_queue(); /* ponytail: the keyboard's queue for both */
        dispatch_async(q, ^{ raw_apply(rs, n); free(rs); });
    }
    return unused;
}

/* ======================================================================= the poll threads */
/* XInput is slow on empty slots (the first call also loads the driver): a slow thread looks for new controllers four times
 * a second, the fast one only reads the connected ones */
static volatile int g_on[4];
static void *probe_thread(void *unused) {
    for (;;) {
        for (int i = 0; i < 4; i++) {
            if (g_on[i]) continue;
            MwPad p;
            if (_scion_ui(UI_PAD, (uint64_t)i, U(&p), 0, 0, 0) == 1) __atomic_store_n(&g_on[i], 1, __ATOMIC_RELEASE);
        }
        usleep(250000);
    }
    return unused;
}
static void *poll_thread(void *unused) {
    MwPad last[4]; int was[4] = {0};
    uint16_t rumble[4][2] = {{0}};
    memset(last, 0, sizeof last);
    for (;;) {
        for (int i = 0; i < 4; i++) {
            if (!__atomic_load_n(&g_on[i], __ATOMIC_ACQUIRE) && !was[i]) continue;
            MwPad p;
            memset(&p, 0, sizeof p);
            int on = _scion_ui(UI_PAD, (uint64_t)i, U(&p), 0, 0, 0) == 1;
            if (!on) __atomic_store_n(&g_on[i], 0, __ATOMIC_RELEASE);
            if (on != was[i] || (on && memcmp(&p, &last[i], sizeof p))) {
                int idx = i;
                dispatch_async(dispatch_get_main_queue(), ^{ apply(idx, on, p); });
                was[i] = on; last[i] = p;
            }
            if (on && p.has_rumble) {
                float lo, hi;
                pthread_mutex_lock(&g_hmu);
                void *pool = objc_autoreleasePoolPush();
                mix(i, &lo, &hi);
                objc_autoreleasePoolPop(pool);
                pthread_mutex_unlock(&g_hmu);
                uint16_t l = (uint16_t)lrintf(lo * 65535), h = (uint16_t)lrintf(hi * 65535);
                if (l != rumble[i][0] || h != rumble[i][1]) { _scion_ui(UI_RUMBLE, (uint64_t)i, l, h, 0, 0); rumble[i][0] = l; rumble[i][1] = h; }
            } else rumble[i][0] = rumble[i][1] = 0;
        }
        usleep(8000);
    }
    return unused;
}
__attribute__((constructor)) static void gc_start(void) {
    g_running = [[NSMutableArray alloc] init];
    pthread_t th;
    pthread_create(&th, NULL, poll_thread, NULL);
    pthread_detach(th);
    pthread_create(&th, NULL, probe_thread, NULL);
    pthread_detach(th);
    g_keyboard = [[GCKeyboard alloc] _mwInit];
    g_mouse = [[GCMouse alloc] _mwInit];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc postNotificationName:GCKeyboardDidConnectNotification object:g_keyboard];
        [nc postNotificationName:GCMouseDidConnectNotification object:g_mouse];
        [nc postNotificationName:GCMouseDidBecomeCurrentNotification object:g_mouse];
    });
    pthread_create(&th, NULL, raw_thread, NULL);
    pthread_detach(th);
}
