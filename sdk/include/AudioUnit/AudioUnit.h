/* scion SDK — AudioUnit subset: the output units (default / HAL / system output) with a render callback.
 * Implemented in AudioToolbox.dylib (dyld maps AudioUnit and CoreAudio to it); sound goes to WASAPI on Windows. */
#pragma once
#include <CoreAudio/CoreAudioTypes.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct OpaqueAudioComponent *AudioComponent;
typedef struct ComponentInstanceRecord *AudioComponentInstance;
typedef AudioComponentInstance AudioUnit;
typedef struct AudioComponentDescription { OSType componentType, componentSubType, componentManufacturer; UInt32 componentFlags, componentFlagsMask; } AudioComponentDescription;
typedef UInt32 AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, AudioUnitParameterID, AudioUnitRenderActionFlags;
typedef Float32 AudioUnitParameterValue;
typedef OSStatus (*AURenderCallback)(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *data);
typedef struct AURenderCallbackStruct { AURenderCallback inputProc; void *inputProcRefCon; } AURenderCallbackStruct;
typedef void (*AudioUnitPropertyListenerProc)(void *refCon, AudioUnit u, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e);
enum { kAudioUnitType_Output = 'auou', kAudioUnitType_Mixer = 'aumx', kAudioUnitType_FormatConverter = 'aufc', kAudioUnitType_Effect = 'aufx' };
enum { kAudioUnitSubType_DefaultOutput = 'def ', kAudioUnitSubType_HALOutput = 'ahal', kAudioUnitSubType_SystemOutput = 'sys ',
       kAudioUnitSubType_RemoteIO = 'rioc', kAudioUnitSubType_VoiceProcessingIO = 'vpio', kAudioUnitSubType_GenericOutput = 'genr' };
enum { kAudioUnitManufacturer_Apple = 'appl' };
enum { kAudioUnitScope_Global = 0, kAudioUnitScope_Input = 1, kAudioUnitScope_Output = 2 };
enum {
    kAudioUnitProperty_ClassInfo = 0, kAudioUnitProperty_SampleRate = 2, kAudioUnitProperty_StreamFormat = 8, kAudioUnitProperty_ElementCount = 11,
    kAudioUnitProperty_Latency = 12, kAudioUnitProperty_MaximumFramesPerSlice = 14, kAudioUnitProperty_SetRenderCallback = 23,
    kAudioUnitProperty_ShouldAllocateBuffer = 51, kAudioUnitProperty_LastRenderError = 22,
    kAudioOutputUnitProperty_CurrentDevice = 2000, kAudioOutputUnitProperty_IsRunning = 2001, kAudioOutputUnitProperty_EnableIO = 2003,
    kAudioOutputUnitProperty_SetInputCallback = 2005, kAudioOutputUnitProperty_HasIO = 2006,
};
enum { kHALOutputParam_Volume = 14 };
enum { kAudioUnitRenderAction_PreRender = 1 << 2, kAudioUnitRenderAction_PostRender = 1 << 3, kAudioUnitRenderAction_OutputIsSilence = 1 << 4 };
enum {
    kAudioUnitErr_InvalidProperty = -10879, kAudioUnitErr_InvalidParameter = -10878, kAudioUnitErr_InvalidElement = -10877,
    kAudioUnitErr_NoConnection = -10876, kAudioUnitErr_FailedInitialization = -10875, kAudioUnitErr_TooManyFramesToProcess = -10874,
    kAudioUnitErr_FormatNotSupported = -10868, kAudioUnitErr_Uninitialized = -10867, kAudioUnitErr_InvalidScope = -10866,
    kAudioUnitErr_PropertyNotWritable = -10865, kAudioUnitErr_CannotDoInCurrentContext = -10863, kAudioUnitErr_InvalidPropertyValue = -10851,
};
AudioComponent AudioComponentFindNext(AudioComponent after, const AudioComponentDescription *d);
UInt32 AudioComponentCount(const AudioComponentDescription *d);
OSStatus AudioComponentGetDescription(AudioComponent c, AudioComponentDescription *d);
OSStatus AudioComponentInstanceNew(AudioComponent c, AudioComponentInstance *out);
OSStatus AudioComponentInstanceDispose(AudioComponentInstance u);
AudioComponent AudioComponentInstanceGetComponent(AudioComponentInstance u);
OSStatus AudioUnitInitialize(AudioUnit u);
OSStatus AudioUnitUninitialize(AudioUnit u);
OSStatus AudioUnitGetPropertyInfo(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e, UInt32 *size, Boolean *writable);
OSStatus AudioUnitGetProperty(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e, void *data, UInt32 *size);
OSStatus AudioUnitSetProperty(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e, const void *data, UInt32 size);
OSStatus AudioUnitAddPropertyListener(AudioUnit u, AudioUnitPropertyID id, AudioUnitPropertyListenerProc p, void *refCon);
OSStatus AudioUnitRemovePropertyListenerWithUserData(AudioUnit u, AudioUnitPropertyID id, AudioUnitPropertyListenerProc p, void *refCon);
OSStatus AudioUnitGetParameter(AudioUnit u, AudioUnitParameterID id, AudioUnitScope s, AudioUnitElement e, AudioUnitParameterValue *v);
OSStatus AudioUnitSetParameter(AudioUnit u, AudioUnitParameterID id, AudioUnitScope s, AudioUnitElement e, AudioUnitParameterValue v, UInt32 offset);
OSStatus AudioUnitReset(AudioUnit u, AudioUnitScope s, AudioUnitElement e);
OSStatus AudioUnitRender(AudioUnit u, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *data);
OSStatus AudioOutputUnitStart(AudioUnit u);
OSStatus AudioOutputUnitStop(AudioUnit u);
#ifdef __cplusplus
}
#endif
