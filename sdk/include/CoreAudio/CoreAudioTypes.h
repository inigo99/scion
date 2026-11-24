/* scion SDK — CoreAudio types (Apple's layouts and values) */
#pragma once
#include <MacTypes.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef UInt32 AudioFormatID, AudioFormatFlags, AudioObjectID, AudioDeviceID, AudioObjectPropertySelector, AudioObjectPropertyScope,
    AudioObjectPropertyElement;
typedef struct AudioStreamBasicDescription {
    Float64 mSampleRate; AudioFormatID mFormatID; AudioFormatFlags mFormatFlags; UInt32 mBytesPerPacket, mFramesPerPacket, mBytesPerFrame,
    mChannelsPerFrame, mBitsPerChannel, mReserved;
} AudioStreamBasicDescription;
typedef struct AudioStreamPacketDescription { SInt64 mStartOffset; UInt32 mVariableFramesInPacket, mDataByteSize; } AudioStreamPacketDescription;
typedef struct AudioBuffer { UInt32 mNumberChannels, mDataByteSize; void *mData; } AudioBuffer;
typedef struct AudioBufferList { UInt32 mNumberBuffers; AudioBuffer mBuffers[1]; } AudioBufferList;
typedef struct SMPTETime { SInt16 mSubframes, mSubframeDivisor; UInt32 mCounter, mType, mFlags; SInt16 mHours, mMinutes, mSeconds, mFrames; } SMPTETime;
typedef struct AudioTimeStamp {
    Float64 mSampleTime; UInt64 mHostTime; Float64 mRateScalar; UInt64 mWordClockTime; SMPTETime mSMPTETime; UInt32 mFlags, mReserved;
} AudioTimeStamp;
enum { kAudioTimeStampSampleTimeValid = 1, kAudioTimeStampHostTimeValid = 2, kAudioTimeStampRateScalarValid = 4,
       kAudioTimeStampWordClockTimeValid = 8, kAudioTimeStampSMPTETimeValid = 16, kAudioTimeStampSampleHostTimeValid = 3 };
enum { kAudioFormatLinearPCM = 'lpcm', kAudioFormatAppleIMA4 = 'ima4', kAudioFormatMPEG4AAC = 'aac ', kAudioFormatMPEGLayer3 = '.mp3' };
enum {
    kAudioFormatFlagIsFloat = 1 << 0, kAudioFormatFlagIsBigEndian = 1 << 1, kAudioFormatFlagIsSignedInteger = 1 << 2,
    kAudioFormatFlagIsPacked = 1 << 3, kAudioFormatFlagIsAlignedHigh = 1 << 4, kAudioFormatFlagIsNonInterleaved = 1 << 5,
    kAudioFormatFlagIsNonMixable = 1 << 6, kAudioFormatFlagsAreAllClear = 0x80000000,
    kLinearPCMFormatFlagIsFloat = 1 << 0, kLinearPCMFormatFlagIsBigEndian = 1 << 1, kLinearPCMFormatFlagIsSignedInteger = 1 << 2,
    kLinearPCMFormatFlagIsPacked = 1 << 3, kLinearPCMFormatFlagIsAlignedHigh = 1 << 4, kLinearPCMFormatFlagIsNonInterleaved = 1 << 5,
    kAudioFormatFlagsNativeEndian = 0, kAudioFormatFlagsNativeFloatPacked = (1 << 0) | (1 << 3),
    kAudioFormatFlagsCanonical = (1 << 0) | (1 << 3),
};
enum { kAudio_UnimplementedError = -4, kAudio_FileNotFoundError = -43, kAudio_ParamError = -50, kAudio_MemFullError = -108 };
#ifdef __cplusplus
}
#endif
