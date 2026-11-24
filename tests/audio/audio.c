/* AudioToolbox. An output AudioUnit with a render callback (float32 stereo and int16 non-interleaved mono), paced
 * by the device clock; an AudioQueue that plays and recycles its buffers; the CoreAudio HAL defaults. Prints "AUDIO OK". */
#include <AudioToolbox/AudioToolbox.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <unistd.h>

static int fails;
#define CHECK(c, ...) do { if (c) printf("  ok: " __VA_ARGS__); else { printf("  FAIL: " __VA_ARGS__); fails++; } printf("\n"); fflush(stdout); } while (0)
uint64_t mach_absolute_time(void);
static double now(void) { return mach_absolute_time() * 1e-9; }

static volatile long frames_out, calls; static double last_sample = -1; static int monotonic = 1; static double phase;
static OSStatus render(void *ref, AudioUnitRenderActionFlags *fl, const AudioTimeStamp *ts, UInt32 bus, UInt32 n, AudioBufferList *io) {
    if (ts->mSampleTime <= last_sample) monotonic = 0;
    last_sample = ts->mSampleTime;
    const AudioStreamBasicDescription *f = ref;
    for (UInt32 i = 0; i < n; i++) {
        float v = 0.2f * sinf((float)phase); phase += 2 * M_PI * 440 / f->mSampleRate;
        if (f->mFormatFlags & kAudioFormatFlagIsFloat) { float *o = io->mBuffers[0].mData; o[i * 2] = o[i * 2 + 1] = v; }
        else ((int16_t *)io->mBuffers[0].mData)[i] = (int16_t)(v * 32767);
    }
    frames_out += n; calls++;
    return noErr;
}
static void unit_test(AudioStreamBasicDescription f, const char *name) {
    AudioComponentDescription d = {kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent c = AudioComponentFindNext(NULL, &d);
    AudioUnit u = NULL;
    CHECK(c && !AudioComponentInstanceNew(c, &u), "%s: AudioComponentFindNext + InstanceNew", name);
    AURenderCallbackStruct cb = {render, &f};
    OSStatus e1 = AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &f, sizeof f);
    OSStatus e2 = AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, sizeof cb);
    OSStatus e3 = AudioUnitInitialize(u);
    CHECK(!e1 && !e2 && !e3, "%s: format, callback and initialize (%d %d %d)", name, (int)e1, (int)e2, (int)e3);
    AudioStreamBasicDescription g; UInt32 sz = sizeof g;
    CHECK(!AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &g, &sz) && g.mSampleRate == f.mSampleRate, "%s: GetProperty of the format", name);
    frames_out = calls = 0; last_sample = -1; monotonic = 1;
    double t0 = now();
    AudioOutputUnitStart(u);
    usleep(600000);
    AudioOutputUnitStop(u);
    double secs = now() - t0, expect = secs * f.mSampleRate;
    /* paced by the device: about real time (plus the ~40 ms buffer filled at the start) */
    CHECK(frames_out > expect * 0.6 && frames_out < expect * 1.4 + f.mSampleRate * 0.1, "%s: the callback keeps the device's pace (%ld frames in %.2f s, expected ~%.0f)",
          name, frames_out, secs, expect);
    CHECK(monotonic && calls > 5, "%s: mSampleTime increases (%ld calls)", name, calls);
    long after = frames_out; usleep(100000);
    CHECK(frames_out == after, "%s: AudioOutputUnitStop stops the callback", name);
    CHECK(!AudioUnitUninitialize(u) && !AudioComponentInstanceDispose(u), "%s: Uninitialize + Dispose", name);
}

static volatile long q_done;
static void qcb(void *user, AudioQueueRef q, AudioQueueBufferRef b) {
    q_done++;
    memset(b->mAudioData, 0, b->mAudioDataBytesCapacity);
    b->mAudioDataByteSize = b->mAudioDataBytesCapacity;
    AudioQueueEnqueueBuffer(q, b, 0, NULL);
}

int main(void) {
    printf("step: AudioUnit float32 stereo 48 kHz\n");
    AudioStreamBasicDescription f32 = {48000, kAudioFormatLinearPCM, kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 8, 1, 8, 2, 32, 0};
    unit_test(f32, "float32");
    printf("step: AudioUnit int16 mono non-interleaved 22050 Hz\n");
    AudioStreamBasicDescription i16 = {22050, kAudioFormatLinearPCM, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                                      2, 1, 2, 1, 16, 0};
    unit_test(i16, "int16");

    printf("step: AudioQueue\n");
    AudioStreamBasicDescription qf = {44100, kAudioFormatLinearPCM, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 4, 1, 4, 2, 16, 0};
    AudioQueueRef q;
    CHECK(!AudioQueueNewOutput(&qf, qcb, NULL, NULL, NULL, 0, &q), "AudioQueueNewOutput");
    for (int i = 0; i < 3; i++) {
        AudioQueueBufferRef b;
        AudioQueueAllocateBuffer(q, 4096, &b);
        b->mAudioDataByteSize = 4096;
        AudioQueueEnqueueBuffer(q, b, 0, NULL);
    }
    AudioQueueSetParameter(q, kAudioQueueParam_Volume, 0.5f);
    AudioQueueParameterValue vol = 0; AudioQueueGetParameter(q, kAudioQueueParam_Volume, &vol);
    double t0 = now();
    AudioQueueStart(q, NULL);
    usleep(600000);
    UInt32 running = 0, sz = 4;
    AudioQueueGetProperty(q, kAudioQueueProperty_IsRunning, &running, &sz);
    AudioQueueStop(q, 1);
    double secs = now() - t0, buffers = secs * 44100 * 4 / 4096;
    CHECK(q_done > buffers * 0.6 && q_done < buffers * 1.4 + 4, "AudioQueue recycles its buffers at the device's pace (%ld, expected ~%.0f)", q_done, buffers);
    CHECK(running == 1 && vol == 0.5f, "IsRunning and volume");
    CHECK(!AudioQueueDispose(q, 1), "AudioQueueDispose");

    printf("step: HAL\n");
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioDeviceID dev = 0; sz = sizeof dev;
    OSStatus e = AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &dev);
    Float64 rate = 0; sz = sizeof rate;
    a.mSelector = kAudioDevicePropertyNominalSampleRate;
    e |= AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &rate);
    CHECK(!e && dev && rate > 0, "default output device %u at %.0f Hz", (unsigned)dev, rate);
    printf(fails ? "AUDIO FAIL (%d)\n" : "AUDIO OK\n", fails);
    return fails != 0;
}
