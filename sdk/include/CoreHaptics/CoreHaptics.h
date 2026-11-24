/* scion SDK — CoreHaptics subset (implemented in GameController.dylib; dyld maps CoreHaptics to it).
 * Engines created from a game controller (GCDeviceHaptics) drive its rumble motors; an engine without a controller
 * (the Mac's own hardware) plays nothing. Patterns: events with intensity/sharpness, dynamic parameters. */
#pragma once
#import <Foundation/Foundation.h>

typedef NSString *CHHapticEventType;
extern CHHapticEventType const CHHapticEventTypeHapticTransient, CHHapticEventTypeHapticContinuous, CHHapticEventTypeAudioContinuous,
    CHHapticEventTypeAudioCustom;
typedef NSString *CHHapticEventParameterID;
extern CHHapticEventParameterID const CHHapticEventParameterIDHapticIntensity, CHHapticEventParameterIDHapticSharpness,
    CHHapticEventParameterIDAttackTime, CHHapticEventParameterIDDecayTime, CHHapticEventParameterIDReleaseTime,
    CHHapticEventParameterIDSustained, CHHapticEventParameterIDAudioVolume, CHHapticEventParameterIDAudioPitch,
    CHHapticEventParameterIDAudioPan, CHHapticEventParameterIDAudioBrightness;
typedef NSString *CHHapticDynamicParameterID;
extern CHHapticDynamicParameterID const CHHapticDynamicParameterIDHapticIntensityControl, CHHapticDynamicParameterIDHapticSharpnessControl,
    CHHapticDynamicParameterIDHapticAttackTimeControl, CHHapticDynamicParameterIDHapticDecayTimeControl,
    CHHapticDynamicParameterIDHapticReleaseTimeControl, CHHapticDynamicParameterIDAudioVolumeControl;
extern const NSTimeInterval CHHapticTimeImmediate;
extern NSString *const CHHapticErrorDomain, *const CoreHapticsErrorDomain;
typedef NS_ENUM(NSInteger, CHHapticErrorCode) {
    CHHapticErrorCodeEngineNotRunning = -4805, CHHapticErrorCodeOperationNotPermitted = -4806, CHHapticErrorCodeEngineStartTimeout = -4808,
    CHHapticErrorCodeNotSupported = -4809, CHHapticErrorCodeServerInitFailed = -4810, CHHapticErrorCodeServerInterrupted = -4811,
    CHHapticErrorCodeInvalidPatternPlayer = -4812, CHHapticErrorCodeInvalidPatternData = -4813, CHHapticErrorCodeInvalidPatternDictionary = -4814,
    CHHapticErrorCodeInvalidAudioSession = -4815, CHHapticErrorCodeInvalidEngineParameter = -4816, CHHapticErrorCodeInvalidParameterType = -4820,
    CHHapticErrorCodeInvalidEventType = -4821, CHHapticErrorCodeInvalidEventTime = -4822, CHHapticErrorCodeInvalidEventDuration = -4823,
    CHHapticErrorCodeInvalidAudioResource = -4824, CHHapticErrorCodeResourceNotAvailable = -4825, CHHapticErrorCodeBadEventEntry = -4830,
    CHHapticErrorCodeBadParameterEntry = -4831, CHHapticErrorCodeInvalidTime = -4840, CHHapticErrorCodeFileNotFound = -4851,
    CHHapticErrorCodeInsufficientPower = -4897, CHHapticErrorCodeUnknownError = -4898, CHHapticErrorCodeMemoryError = -4899,
};
typedef NS_ENUM(NSInteger, CHHapticEngineStoppedReason) {
    CHHapticEngineStoppedReasonAudioSessionInterrupt = 1, CHHapticEngineStoppedReasonApplicationSuspended = 2,
    CHHapticEngineStoppedReasonIdleTimeout = 3, CHHapticEngineStoppedReasonNotifyWhenFinished = 4,
    CHHapticEngineStoppedReasonEngineDestroyed = 5, CHHapticEngineStoppedReasonGameControllerDisconnect = 6,
    CHHapticEngineStoppedReasonSystemError = -1,
};
typedef NS_ENUM(NSInteger, CHHapticEngineFinishedAction) { CHHapticEngineFinishedActionStopEngine = 1, CHHapticEngineFinishedActionLeaveEngineRunning = 2 };
typedef void (^CHHapticEngineStoppedHandler)(CHHapticEngineStoppedReason r);
typedef void (^CHHapticEngineResetHandler)(void);
typedef void (^CHHapticCompletionHandler)(NSError *e);
typedef CHHapticEngineFinishedAction (^CHHapticEngineFinishedHandler)(NSError *e);
typedef void (^CHHapticAdvancedPatternPlayerCompletionHandler)(NSError *e);

@interface CHHapticEventParameter : NSObject
- (instancetype)initWithParameterID:(CHHapticEventParameterID)p value:(float)v;
@property(readonly) CHHapticEventParameterID parameterID;
@property float value;
@end
@interface CHHapticDynamicParameter : NSObject
- (instancetype)initWithParameterID:(CHHapticDynamicParameterID)p value:(float)v relativeTime:(NSTimeInterval)t;
@property(readonly) CHHapticDynamicParameterID parameterID;
@property float value;
@property NSTimeInterval relativeTime;
@end
@interface CHHapticParameterCurveControlPoint : NSObject
- (instancetype)initWithRelativeTime:(NSTimeInterval)t value:(float)v;
@property NSTimeInterval relativeTime;
@property float value;
@end
@interface CHHapticParameterCurve : NSObject
- (instancetype)initWithParameterID:(CHHapticDynamicParameterID)p controlPoints:(NSArray<CHHapticParameterCurveControlPoint *> *)c relativeTime:(NSTimeInterval)t;
@property(readonly) CHHapticDynamicParameterID parameterID;
@property NSTimeInterval relativeTime;
@property(readonly) NSArray<CHHapticParameterCurveControlPoint *> *controlPoints;
@end
@interface CHHapticEvent : NSObject
- (instancetype)initWithEventType:(CHHapticEventType)t parameters:(NSArray<CHHapticEventParameter *> *)p relativeTime:(NSTimeInterval)rt;
- (instancetype)initWithEventType:(CHHapticEventType)t parameters:(NSArray<CHHapticEventParameter *> *)p relativeTime:(NSTimeInterval)rt duration:(NSTimeInterval)d;
@property(readonly) CHHapticEventType type;
@property(readonly) NSArray<CHHapticEventParameter *> *eventParameters;
@property NSTimeInterval relativeTime, duration;
@end
@interface CHHapticPattern : NSObject
- (instancetype)initWithEvents:(NSArray<CHHapticEvent *> *)e parameters:(NSArray<CHHapticDynamicParameter *> *)p error:(NSError **)err;
- (instancetype)initWithEvents:(NSArray<CHHapticEvent *> *)e parameterCurves:(NSArray<CHHapticParameterCurve *> *)c error:(NSError **)err;
- (instancetype)initWithDictionary:(NSDictionary *)d error:(NSError **)err;
@property(readonly) NSTimeInterval duration;
@end
@protocol CHHapticPatternPlayer <NSObject>
- (BOOL)startAtTime:(NSTimeInterval)t error:(NSError **)e;
- (BOOL)stopAtTime:(NSTimeInterval)t error:(NSError **)e;
- (BOOL)sendParameters:(NSArray<CHHapticDynamicParameter *> *)p atTime:(NSTimeInterval)t error:(NSError **)e;
- (BOOL)scheduleParameterCurve:(CHHapticParameterCurve *)c atTime:(NSTimeInterval)t error:(NSError **)e;
- (BOOL)cancelAndReturnError:(NSError **)e;
@property BOOL isMuted;
@end
@protocol CHHapticAdvancedPatternPlayer <CHHapticPatternPlayer>
- (BOOL)pauseAtTime:(NSTimeInterval)t error:(NSError **)e;
- (BOOL)resumeAtTime:(NSTimeInterval)t error:(NSError **)e;
- (BOOL)seekToOffset:(NSTimeInterval)o error:(NSError **)e;
@property BOOL loopEnabled;
@property NSTimeInterval loopEnd;
@property float playbackRate;
@property(copy) CHHapticAdvancedPatternPlayerCompletionHandler completionHandler;
@end
@protocol CHHapticDeviceCapability
@property(readonly) BOOL supportsHaptics, supportsAudio;
@end
@interface CHHapticEngine : NSObject
+ (id<CHHapticDeviceCapability>)capabilitiesForHardware;
- (instancetype)initAndReturnError:(NSError **)e;
@property(readonly) NSTimeInterval currentTime;
@property(copy) CHHapticEngineStoppedHandler stoppedHandler;
@property(copy) CHHapticEngineResetHandler resetHandler;
@property BOOL playsHapticsOnly, playsAudioOnly, isMutedForAudio, isMutedForHaptics, autoShutdownEnabled;
- (void)startWithCompletionHandler:(CHHapticCompletionHandler)h;
- (BOOL)startAndReturnError:(NSError **)e;
- (void)stopWithCompletionHandler:(CHHapticCompletionHandler)h;
- (void)notifyWhenPlayersFinished:(CHHapticEngineFinishedHandler)h;
- (id<CHHapticPatternPlayer>)createPlayerWithPattern:(CHHapticPattern *)p error:(NSError **)e;
- (id<CHHapticAdvancedPatternPlayer>)createAdvancedPlayerWithPattern:(CHHapticPattern *)p error:(NSError **)e;
- (BOOL)playPatternFromURL:(NSURL *)u error:(NSError **)e;
- (BOOL)playPatternFromData:(NSData *)d error:(NSError **)e;
@end
