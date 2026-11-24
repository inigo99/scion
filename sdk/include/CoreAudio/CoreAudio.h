/* scion SDK — CoreAudio HAL subset: the default output device and its nominal rate (implemented in AudioToolbox.dylib) */
#pragma once
#include <CoreAudio/CoreAudioTypes.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct AudioObjectPropertyAddress { AudioObjectPropertySelector mSelector; AudioObjectPropertyScope mScope; AudioObjectPropertyElement mElement; } AudioObjectPropertyAddress;
typedef OSStatus (*AudioObjectPropertyListenerProc)(AudioObjectID o, UInt32 n, const AudioObjectPropertyAddress *a, void *data);
enum { kAudioObjectSystemObject = 1, kAudioObjectUnknown = 0 };
enum {
    kAudioObjectPropertyScopeGlobal = 'glob', kAudioObjectPropertyScopeInput = 'inpt', kAudioObjectPropertyScopeOutput = 'outp',
    kAudioObjectPropertyElementMain = 0, kAudioObjectPropertyElementMaster = 0, kAudioObjectPropertyName = 'lnam',
    kAudioHardwarePropertyDefaultOutputDevice = 'dOut', kAudioHardwarePropertyDefaultSystemOutputDevice = 'sOut',
    kAudioHardwarePropertyDefaultInputDevice = 'dIn ', kAudioHardwarePropertyDevices = 'dev#',
    kAudioDevicePropertyNominalSampleRate = 'nsrt', kAudioDevicePropertyBufferFrameSize = 'fsiz', kAudioDevicePropertyLatency = 'ltnc',
    kAudioDevicePropertyDeviceIsAlive = 'livn', kAudioDevicePropertyStreamFormat = 'sfmt', kAudioDevicePropertyDeviceUID = 'uid ',
    kAudioDevicePropertyDeviceNameCFString = 'lnam', kAudioDevicePropertyVolumeScalar = 'volm', kAudioDevicePropertyMute = 'mute',
    kAudioDevicePropertySafetyOffset = 'saft', kAudioDevicePropertyStreamConfiguration = 'slay',
};
enum { kAudioHardwareNoError = 0, kAudioHardwareUnknownPropertyError = 'who?', kAudioHardwareBadObjectError = '!obj',
       kAudioHardwareUnspecifiedError = 'what', kAudioHardwareIllegalOperationError = 'nope' };
Boolean AudioObjectHasProperty(AudioObjectID o, const AudioObjectPropertyAddress *a);
OSStatus AudioObjectGetPropertyDataSize(AudioObjectID o, const AudioObjectPropertyAddress *a, UInt32 qn, const void *q, UInt32 *size);
OSStatus AudioObjectGetPropertyData(AudioObjectID o, const AudioObjectPropertyAddress *a, UInt32 qn, const void *q, UInt32 *size, void *data);
OSStatus AudioObjectSetPropertyData(AudioObjectID o, const AudioObjectPropertyAddress *a, UInt32 qn, const void *q, UInt32 size, const void *data);
OSStatus AudioObjectAddPropertyListener(AudioObjectID o, const AudioObjectPropertyAddress *a, AudioObjectPropertyListenerProc p, void *data);
OSStatus AudioObjectRemovePropertyListener(AudioObjectID o, const AudioObjectPropertyAddress *a, AudioObjectPropertyListenerProc p, void *data);
#ifdef __cplusplus
}
#endif
