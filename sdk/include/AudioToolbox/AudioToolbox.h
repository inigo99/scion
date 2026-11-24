/* scion SDK — AudioToolbox subset: AudioUnit output units, AudioQueue output and the CoreAudio HAL basics
 * (AudioToolbox.dylib; AudioUnit and CoreAudio map onto it). No AudioConverter / AudioFile / ExtAudioFile yet. */
#pragma once
#include <CoreAudio/CoreAudioTypes.h>
#include <CoreAudio/CoreAudio.h>
#include <AudioUnit/AudioUnit.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct OpaqueAudioQueue *AudioQueueRef;
typedef struct AudioQueueBuffer {
    const UInt32 mAudioDataBytesCapacity; void *const mAudioData; UInt32 mAudioDataByteSize; void *mUserData;
    const UInt32 mPacketDescriptionCapacity; AudioStreamPacketDescription *const mPacketDescriptions; UInt32 mPacketDescriptionCount;
} AudioQueueBuffer, *AudioQueueBufferRef;
typedef void (*AudioQueueOutputCallback)(void *userData, AudioQueueRef q, AudioQueueBufferRef b);
typedef void (^AudioQueueOutputCallbackBlock)(AudioQueueRef q, AudioQueueBufferRef b);
typedef UInt32 AudioQueuePropertyID, AudioQueueParameterID;
typedef Float32 AudioQueueParameterValue;
typedef void (*AudioQueuePropertyListenerProc)(void *userData, AudioQueueRef q, AudioQueuePropertyID id);
typedef struct OpaqueAudioQueueTimeline *AudioQueueTimelineRef;
enum { kAudioQueueParam_Volume = 1, kAudioQueueParam_PlayRate = 2, kAudioQueueParam_Pitch = 3, kAudioQueueParam_VolumeRampTime = 4, kAudioQueueParam_Pan = 13 };
enum { kAudioQueueProperty_IsRunning = 'aqrn', kAudioQueueDeviceProperty_SampleRate = 'aqsr', kAudioQueueDeviceProperty_NumberChannels = 'aqdc',
       kAudioQueueProperty_CurrentDevice = 'aqcd', kAudioQueueProperty_StreamDescription = 'aqft' };
enum { kAudioQueueErr_InvalidBuffer = -66687, kAudioQueueErr_BufferEmpty = -66686, kAudioQueueErr_InvalidQueueType = -66682,
       kAudioQueueErr_InvalidProperty = -66680, kAudioQueueErr_InvalidParameter = -66673, kAudioQueueErr_InvalidRunState = -66672 };
OSStatus AudioQueueNewOutput(const AudioStreamBasicDescription *f, AudioQueueOutputCallback cb, void *userData, const void *runLoop,
                             const void *runLoopMode, UInt32 flags, AudioQueueRef *out);
OSStatus AudioQueueNewOutputWithDispatchQueue(AudioQueueRef *out, const AudioStreamBasicDescription *f, UInt32 flags, void *queue,
                                              AudioQueueOutputCallbackBlock cb);
OSStatus AudioQueueDispose(AudioQueueRef q, Boolean immediate);
OSStatus AudioQueueAllocateBuffer(AudioQueueRef q, UInt32 size, AudioQueueBufferRef *out);
OSStatus AudioQueueAllocateBufferWithPacketDescriptions(AudioQueueRef q, UInt32 size, UInt32 n, AudioQueueBufferRef *out);
OSStatus AudioQueueFreeBuffer(AudioQueueRef q, AudioQueueBufferRef b);
OSStatus AudioQueueEnqueueBuffer(AudioQueueRef q, AudioQueueBufferRef b, UInt32 n, const AudioStreamPacketDescription *d);
OSStatus AudioQueueStart(AudioQueueRef q, const AudioTimeStamp *t);
OSStatus AudioQueuePrime(AudioQueueRef q, UInt32 frames, UInt32 *prepared);
OSStatus AudioQueueStop(AudioQueueRef q, Boolean immediate);
OSStatus AudioQueuePause(AudioQueueRef q);
OSStatus AudioQueueFlush(AudioQueueRef q);
OSStatus AudioQueueReset(AudioQueueRef q);
OSStatus AudioQueueGetParameter(AudioQueueRef q, AudioQueueParameterID p, AudioQueueParameterValue *v);
OSStatus AudioQueueSetParameter(AudioQueueRef q, AudioQueueParameterID p, AudioQueueParameterValue v);
OSStatus AudioQueueGetProperty(AudioQueueRef q, AudioQueuePropertyID p, void *data, UInt32 *size);
OSStatus AudioQueueSetProperty(AudioQueueRef q, AudioQueuePropertyID p, const void *data, UInt32 size);
OSStatus AudioQueueGetPropertySize(AudioQueueRef q, AudioQueuePropertyID p, UInt32 *size);
OSStatus AudioQueueAddPropertyListener(AudioQueueRef q, AudioQueuePropertyID p, AudioQueuePropertyListenerProc l, void *data);
OSStatus AudioQueueRemovePropertyListener(AudioQueueRef q, AudioQueuePropertyID p, AudioQueuePropertyListenerProc l, void *data);
OSStatus AudioQueueGetCurrentTime(AudioQueueRef q, AudioQueueTimelineRef tl, AudioTimeStamp *t, Boolean *discontinuity);
typedef UInt32 SystemSoundID;
void AudioServicesPlaySystemSound(SystemSoundID s);
void AudioServicesPlayAlertSound(SystemSoundID s);
#ifdef __cplusplus
}
#endif
