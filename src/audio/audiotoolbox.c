/* audiotoolbox.c — AudioToolbox / AudioUnit / CoreAudio for the guest (AudioToolbox.dylib). Sound goes to the host
 * (UI_AUDIO_*: WASAPI shared mode, float32; a null sink without a device or with SCION_AUDIO_NULL=1).
 * - Output AudioUnits: a guest thread calls the render callback slice by slice and writes the result to the host, which
 *   blocks while its buffer (~40 ms) is full: that is the clock that paces the callback, as the device does on macOS.
 * - AudioQueue output: a guest thread plays the enqueued buffers in order and hands each back through the callback.
 * Formats: linear PCM, float32 or signed 16/24/32-bit, interleaved or not, any channel count / rate (WASAPI converts). */
#include <AudioToolbox/AudioToolbox.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include "../uibridge.h"

int64_t _scion_ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
#define U(x) ((uint64_t)(uintptr_t)(x))
uint64_t mach_absolute_time(void);
void *_Block_copy(const void *); void _Block_release(const void *);
void *CFRunLoopGetMain(void);

/* ======================================================================= formats */
static int fmt_ok(const AudioStreamBasicDescription *f) {
    if (f->mFormatID != kAudioFormatLinearPCM || !f->mChannelsPerFrame || f->mSampleRate <= 0) return 0;
    if (f->mFormatFlags & kAudioFormatFlagIsBigEndian) return 0;
    if (f->mFormatFlags & kAudioFormatFlagIsFloat) return f->mBitsPerChannel == 32;
    return (f->mFormatFlags & kAudioFormatFlagIsSignedInteger) && (f->mBitsPerChannel == 16 || f->mBitsPerChannel == 24 || f->mBitsPerChannel == 32);
}
static int noninterleaved(const AudioStreamBasicDescription *f) { return (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0; }
/* bytes of one sample of one channel */
static UInt32 sample_bytes(const AudioStreamBasicDescription *f) {
    if (noninterleaved(f)) return f->mBytesPerFrame ? f->mBytesPerFrame : f->mBitsPerChannel / 8;
    return f->mBytesPerFrame ? f->mBytesPerFrame / f->mChannelsPerFrame : f->mBitsPerChannel / 8;
}
static float read_sample(const AudioStreamBasicDescription *f, const uint8_t *p) {
    UInt32 sb = sample_bytes(f);
    if (f->mFormatFlags & kAudioFormatFlagIsFloat) { float v; memcpy(&v, p, 4); return v; }
    int aligned_high = (f->mFormatFlags & kAudioFormatFlagIsAlignedHigh) || (f->mFormatFlags & kAudioFormatFlagIsPacked);
    if (f->mBitsPerChannel == 16) { int16_t v; memcpy(&v, p + (sb > 2 && aligned_high ? sb - 2 : 0), 2); return v / 32768.0f; }
    if (f->mBitsPerChannel == 24) {
        const uint8_t *q = p + (sb > 3 && aligned_high ? sb - 3 : 0);
        int32_t v = (int32_t)((uint32_t)q[0] << 8 | (uint32_t)q[1] << 16 | (uint32_t)q[2] << 24) >> 8;
        return v / 8388608.0f;
    }
    int32_t v; memcpy(&v, p, 4); return v / 2147483648.0f;
}
/* buffer list in the client format -> float32 interleaved */
static void to_float(const AudioStreamBasicDescription *f, const AudioBufferList *abl, UInt32 frames, float *out, float volume) {
    UInt32 ch = f->mChannelsPerFrame, sb = sample_bytes(f);
    if (noninterleaved(f)) {
        for (UInt32 c = 0; c < ch; c++) {
            const uint8_t *src = c < abl->mNumberBuffers ? abl->mBuffers[c].mData : NULL;
            for (UInt32 i = 0; i < frames; i++) out[i * ch + c] = src ? read_sample(f, src + i * sb) * volume : 0;
        }
    } else {
        const uint8_t *src = abl->mBuffers[0].mData;
        UInt32 stride = f->mBytesPerFrame ? f->mBytesPerFrame : sb * ch;
        for (UInt32 i = 0; i < frames; i++)
            for (UInt32 c = 0; c < ch; c++) out[i * ch + c] = src ? read_sample(f, src + i * stride + c * sb) * volume : 0;
    }
}
static int64_t host_rate(void) { return 48000; } /* ponytail: the shared-mode mix rate is almost always 48 kHz */

/* ======================================================================= AudioComponent / AudioUnit */
struct OpaqueAudioComponent { AudioComponentDescription d; const char *name; };
static struct OpaqueAudioComponent g_components[] = {
    {{kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0}, "Apple: DefaultOutputUnit"},
    {{kAudioUnitType_Output, kAudioUnitSubType_HALOutput, kAudioUnitManufacturer_Apple, 0, 0}, "Apple: AUHAL"},
    {{kAudioUnitType_Output, kAudioUnitSubType_SystemOutput, kAudioUnitManufacturer_Apple, 0, 0}, "Apple: SystemOutputUnit"},
    {{kAudioUnitType_Output, kAudioUnitSubType_RemoteIO, kAudioUnitManufacturer_Apple, 0, 0}, "Apple: RemoteIO"},
    {{kAudioUnitType_Output, kAudioUnitSubType_VoiceProcessingIO, kAudioUnitManufacturer_Apple, 0, 0}, "Apple: VoiceProcessingIO"},
};
#define NCOMP (sizeof g_components / sizeof *g_components)
static int matches(const AudioComponentDescription *w, const AudioComponentDescription *c) {
    return (!w->componentType || w->componentType == c->componentType) && (!w->componentSubType || w->componentSubType == c->componentSubType) &&
           (!w->componentManufacturer || w->componentManufacturer == c->componentManufacturer);
}
AudioComponent AudioComponentFindNext(AudioComponent after, const AudioComponentDescription *d) {
    size_t i = after ? (size_t)(after - g_components) + 1 : 0;
    for (; i < NCOMP; i++) if (!d || matches(d, &g_components[i].d)) return &g_components[i];
    return NULL;
}
UInt32 AudioComponentCount(const AudioComponentDescription *d) { UInt32 n = 0; for (size_t i = 0; i < NCOMP; i++) n += !d || matches(d, &g_components[i].d); return n; }
OSStatus AudioComponentGetDescription(AudioComponent c, AudioComponentDescription *d) { if (!c || !d) return kAudio_ParamError; *d = c->d; return noErr; }

struct ComponentInstanceRecord {
    AudioComponent comp;
    AudioStreamBasicDescription fmt;      /* the client format (input scope of the output element) */
    AURenderCallbackStruct cb;
    UInt32 max_frames;
    float volume;
    int initialized;
    volatile int running;
    pthread_t thread;
    int64_t stream;                       /* host stream, opened by AudioUnitInitialize */
    Float64 sample_time;
    pthread_mutex_t mu;
};
static AudioStreamBasicDescription default_format(Float64 rate) {
    AudioStreamBasicDescription f = {rate, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
                                     4, 1, 4, 2, 32, 0};
    return f;
}
OSStatus AudioComponentInstanceNew(AudioComponent c, AudioComponentInstance *out) {
    if (!c || !out) return kAudio_ParamError;
    AudioUnit u = calloc(1, sizeof *u);
    u->comp = c; u->fmt = default_format(host_rate()); u->max_frames = 1156; u->volume = 1;
    pthread_mutex_init(&u->mu, NULL);
    *out = u;
    return noErr;
}
AudioComponent AudioComponentInstanceGetComponent(AudioComponentInstance u) { return u ? u->comp : NULL; }
OSStatus AudioUnitInitialize(AudioUnit u) {
    if (!u) return kAudio_ParamError;
    if (u->initialized) return noErr;
    if (!fmt_ok(&u->fmt)) return kAudioUnitErr_FormatNotSupported;
    u->stream = _scion_ui(UI_AUDIO_OPEN, (uint64_t)(u->fmt.mSampleRate + 0.5), u->fmt.mChannelsPerFrame, 0, 0, 0);
    if (u->stream <= 0) return kAudioUnitErr_FailedInitialization;
    u->initialized = 1;
    return noErr;
}
OSStatus AudioOutputUnitStop(AudioUnit u);
OSStatus AudioUnitUninitialize(AudioUnit u) {
    if (!u || !u->initialized) return noErr;
    AudioOutputUnitStop(u);
    _scion_ui(UI_AUDIO_CTL, (uint64_t)u->stream, 2, 0, 0, 0);
    u->initialized = 0; u->stream = 0;
    return noErr;
}
OSStatus AudioComponentInstanceDispose(AudioComponentInstance u) { if (!u) return kAudio_ParamError; AudioUnitUninitialize(u); free(u); return noErr; }

static UInt32 prop_size(AudioUnitPropertyID id) {
    switch (id) {
    case kAudioUnitProperty_StreamFormat: return sizeof(AudioStreamBasicDescription);
    case kAudioUnitProperty_SetRenderCallback: return sizeof(AURenderCallbackStruct);
    case kAudioUnitProperty_SampleRate: case kAudioUnitProperty_Latency: return sizeof(Float64);
    case kAudioUnitProperty_MaximumFramesPerSlice: case kAudioUnitProperty_ElementCount: case kAudioOutputUnitProperty_CurrentDevice:
    case kAudioOutputUnitProperty_IsRunning: case kAudioOutputUnitProperty_EnableIO: case kAudioOutputUnitProperty_HasIO:
    case kAudioUnitProperty_ShouldAllocateBuffer: case kAudioUnitProperty_LastRenderError: return sizeof(UInt32);
    }
    return 0;
}
OSStatus AudioUnitGetPropertyInfo(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e, UInt32 *size, Boolean *writable) {
    UInt32 n = prop_size(id);
    if (!n) return kAudioUnitErr_InvalidProperty;
    if (size) *size = n;
    if (writable) *writable = id != kAudioOutputUnitProperty_IsRunning && id != kAudioUnitProperty_ElementCount && id != kAudioUnitProperty_Latency;
    return noErr;
}
OSStatus AudioUnitGetProperty(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e, void *data, UInt32 *size) {
    if (!u || !data || !size) return kAudio_ParamError;
    UInt32 n = prop_size(id);
    if (!n) return kAudioUnitErr_InvalidProperty;
    if (*size < n) return kAudio_ParamError;
    *size = n;
    switch (id) {
    case kAudioUnitProperty_StreamFormat: {
        AudioStreamBasicDescription f = s == kAudioUnitScope_Output ? default_format(host_rate()) : u->fmt; /* output scope: the device side */
        memcpy(data, &f, n); return noErr;
    }
    case kAudioUnitProperty_SetRenderCallback: memcpy(data, &u->cb, n); return noErr;
    case kAudioUnitProperty_SampleRate: { Float64 r = s == kAudioUnitScope_Output ? host_rate() : u->fmt.mSampleRate; memcpy(data, &r, n); return noErr; }
    case kAudioUnitProperty_Latency: { Float64 l = 0.04; memcpy(data, &l, n); return noErr; }
    case kAudioUnitProperty_MaximumFramesPerSlice: *(UInt32 *)data = u->max_frames; return noErr;
    case kAudioUnitProperty_ElementCount: *(UInt32 *)data = 1; return noErr;
    case kAudioOutputUnitProperty_CurrentDevice: *(UInt32 *)data = 1; return noErr;
    case kAudioOutputUnitProperty_IsRunning: *(UInt32 *)data = u->running; return noErr;
    case kAudioOutputUnitProperty_EnableIO: *(UInt32 *)data = e == 0; return noErr; /* output on, input (element 1) off */
    case kAudioOutputUnitProperty_HasIO: *(UInt32 *)data = e == 0; return noErr;
    default: *(UInt32 *)data = 0; return noErr;
    }
}
OSStatus AudioUnitSetProperty(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e, const void *data, UInt32 size) {
    if (!u) return kAudio_ParamError;
    switch (id) {
    case kAudioUnitProperty_StreamFormat: {
        if (!data || size < sizeof(AudioStreamBasicDescription)) return kAudio_ParamError;
        if (s == kAudioUnitScope_Output && e == 0) return noErr; /* the device side: WASAPI converts whatever the client gives */
        const AudioStreamBasicDescription *f = data;
        if (!fmt_ok(f)) return kAudioUnitErr_FormatNotSupported;
        if (u->initialized) return kAudioUnitErr_CannotDoInCurrentContext;
        u->fmt = *f;
        return noErr;
    }
    case kAudioUnitProperty_SetRenderCallback:
        if (data && size < sizeof(AURenderCallbackStruct)) return kAudio_ParamError;
        pthread_mutex_lock(&u->mu);
        if (data) memcpy(&u->cb, data, sizeof u->cb); else memset(&u->cb, 0, sizeof u->cb);
        pthread_mutex_unlock(&u->mu);
        return noErr;
    case kAudioUnitProperty_MaximumFramesPerSlice:
        if (!data || size < 4) return kAudio_ParamError;
        u->max_frames = *(const UInt32 *)data ? *(const UInt32 *)data : 1156;
        return noErr;
    case kAudioUnitProperty_SampleRate:
        if (!data || size < 8) return kAudio_ParamError;
        if (s != kAudioUnitScope_Output) u->fmt.mSampleRate = *(const Float64 *)data;
        return noErr;
    case kAudioOutputUnitProperty_CurrentDevice: case kAudioOutputUnitProperty_EnableIO: case kAudioUnitProperty_ShouldAllocateBuffer:
    case kAudioOutputUnitProperty_SetInputCallback:
        return noErr; /* one output device; no input */
    }
    return kAudioUnitErr_InvalidProperty;
}
OSStatus AudioUnitAddPropertyListener(AudioUnit u, AudioUnitPropertyID id, AudioUnitPropertyListenerProc p, void *refCon) { return noErr; }
OSStatus AudioUnitRemovePropertyListenerWithUserData(AudioUnit u, AudioUnitPropertyID id, AudioUnitPropertyListenerProc p, void *refCon) { return noErr; }
OSStatus AudioUnitGetParameter(AudioUnit u, AudioUnitParameterID id, AudioUnitScope s, AudioUnitElement e, AudioUnitParameterValue *v) {
    if (!u || !v) return kAudio_ParamError;
    if (id != kHALOutputParam_Volume) return kAudioUnitErr_InvalidParameter;
    *v = u->volume;
    return noErr;
}
OSStatus AudioUnitSetParameter(AudioUnit u, AudioUnitParameterID id, AudioUnitScope s, AudioUnitElement e, AudioUnitParameterValue v, UInt32 offset) {
    if (!u) return kAudio_ParamError;
    if (id != kHALOutputParam_Volume) return kAudioUnitErr_InvalidParameter;
    u->volume = v < 0 ? 0 : v > 1 ? 1 : v;
    return noErr;
}
OSStatus AudioUnitReset(AudioUnit u, AudioUnitScope s, AudioUnitElement e) { return noErr; }
OSStatus AudioUnitRender(AudioUnit u, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    return kAudioUnitErr_NoConnection; /* pulling from an output unit's input (microphone): no input */
}

/* the render thread */
static void *render_thread(void *p) {
    AudioUnit u = p;
    AudioStreamBasicDescription f = u->fmt;
    UInt32 frames = u->max_frames < 512 ? u->max_frames : 512; /* ~10 ms slices */
    UInt32 ch = f.mChannelsPerFrame, sb = sample_bytes(&f), nb = noninterleaved(&f) ? ch : 1;
    UInt32 bytes_per_buf = noninterleaved(&f) ? frames * sb : frames * (f.mBytesPerFrame ? f.mBytesPerFrame : sb * ch);
    AudioBufferList *abl = calloc(1, sizeof(AudioBufferList) + nb * sizeof(AudioBuffer));
    uint8_t *mem = calloc(nb, bytes_per_buf);
    float *out = malloc(frames * ch * sizeof(float));
    int started = 0;
    while (u->running) {
        abl->mNumberBuffers = nb;
        for (UInt32 b = 0; b < nb; b++) {
            abl->mBuffers[b].mNumberChannels = noninterleaved(&f) ? 1 : ch;
            abl->mBuffers[b].mDataByteSize = bytes_per_buf;
            abl->mBuffers[b].mData = mem + b * bytes_per_buf;
            memset(abl->mBuffers[b].mData, 0, bytes_per_buf);
        }
        AudioTimeStamp ts;
        memset(&ts, 0, sizeof ts);
        ts.mSampleTime = u->sample_time; ts.mHostTime = mach_absolute_time(); ts.mRateScalar = 1;
        ts.mFlags = kAudioTimeStampSampleTimeValid | kAudioTimeStampHostTimeValid | kAudioTimeStampRateScalarValid;
        AudioUnitRenderActionFlags fl = 0;
        pthread_mutex_lock(&u->mu);
        AURenderCallbackStruct cb = u->cb;
        pthread_mutex_unlock(&u->mu);
        OSStatus st = cb.inputProc ? cb.inputProc(cb.inputProcRefCon, &fl, &ts, 0, frames, abl) : noErr;
        if (st != noErr || !cb.inputProc || (fl & kAudioUnitRenderAction_OutputIsSilence)) memset(out, 0, frames * ch * sizeof(float));
        else to_float(&f, abl, frames, out, u->volume);
        UInt32 done = 0;
        while (done < frames && u->running) { /* blocks while the host buffer is full */
            int64_t n = _scion_ui(UI_AUDIO_WRITE, (uint64_t)u->stream, U(out + done * ch), frames - done, 0, 0);
            if (n < 0) break;
            done += (UInt32)n;
            if (!started) { _scion_ui(UI_AUDIO_CTL, (uint64_t)u->stream, 0, 0, 0, 0); started = 1; } /* start once something is queued */
        }
        u->sample_time += frames;
    }
    free(abl); free(mem); free(out);
    return NULL;
}
OSStatus AudioOutputUnitStart(AudioUnit u) {
    if (!u) return kAudio_ParamError;
    if (!u->initialized) { OSStatus r = AudioUnitInitialize(u); if (r) return r; }
    if (u->running) return noErr;
    u->running = 1;
    if (pthread_create(&u->thread, NULL, render_thread, u)) { u->running = 0; return kAudio_MemFullError; }
    return noErr;
}
OSStatus AudioOutputUnitStop(AudioUnit u) {
    if (!u || !u->running) return noErr;
    u->running = 0;
    _scion_ui(UI_AUDIO_CTL, (uint64_t)u->stream, 1, 0, 0, 0); /* stop + flush: a blocked write returns */
    if (!pthread_equal(pthread_self(), u->thread)) pthread_join(u->thread, NULL);
    else pthread_detach(u->thread);
    return noErr;
}

/* ======================================================================= AudioQueue (output) */
struct qbuf { AudioQueueBuffer b; struct qbuf *next; int queued; };
struct OpaqueAudioQueue {
    AudioStreamBasicDescription fmt;
    AudioQueueOutputCallback cb; void *user; AudioQueueOutputCallbackBlock block;
    dispatch_queue_t dq; int on_main;
    int64_t stream;
    pthread_mutex_t mu; pthread_cond_t cv;
    struct qbuf *head, *tail;
    volatile int running, paused, quit, stopping;
    pthread_t thread;
    float volume;
    Float64 played;
};
static void give_back(AudioQueueRef q, struct qbuf *b) {
    if (q->block) {
        AudioQueueOutputCallbackBlock blk = q->block;
        dispatch_async(q->dq ? q->dq : dispatch_get_global_queue(0, 0), ^{ blk(q, &b->b); });
    } else if (q->on_main) {
        dispatch_async(dispatch_get_main_queue(), ^{ q->cb(q->user, q, &b->b); });
    } else q->cb(q->user, q, &b->b);
}
static void *queue_thread(void *p) {
    AudioQueueRef q = p;
    UInt32 ch = q->fmt.mChannelsPerFrame;
    UInt32 bpf = q->fmt.mBytesPerFrame ? q->fmt.mBytesPerFrame : sample_bytes(&q->fmt) * ch;
    float *out = NULL; size_t cap = 0;
    int started = 0;
    for (;;) {
        pthread_mutex_lock(&q->mu);
        while (!q->quit && (!q->running || q->paused || !q->head)) {
            if (q->stopping && !q->head) { q->running = 0; q->stopping = 0; pthread_cond_broadcast(&q->cv); }
            pthread_cond_wait(&q->cv, &q->mu);
        }
        if (q->quit) { pthread_mutex_unlock(&q->mu); break; }
        struct qbuf *b = q->head;
        q->head = b->next; if (!q->head) q->tail = NULL;
        b->queued = 0;
        pthread_mutex_unlock(&q->mu);
        UInt32 frames = noninterleaved(&q->fmt) ? b->b.mAudioDataByteSize / sample_bytes(&q->fmt) / ch : b->b.mAudioDataByteSize / bpf;
        if ((size_t)frames * ch > cap) { cap = (size_t)frames * ch; out = realloc(out, cap * sizeof(float)); }
        /* non-interleaved queue buffers hold the channels one after another */
        AudioBufferList *abl = calloc(1, sizeof(AudioBufferList) + ch * sizeof(AudioBuffer));
        if (noninterleaved(&q->fmt)) {
            abl->mNumberBuffers = ch;
            for (UInt32 c = 0; c < ch; c++) abl->mBuffers[c].mData = (uint8_t *)b->b.mAudioData + c * frames * sample_bytes(&q->fmt);
        } else { abl->mNumberBuffers = 1; abl->mBuffers[0].mData = b->b.mAudioData; }
        to_float(&q->fmt, abl, frames, out, q->volume);
        free(abl);
        UInt32 done = 0;
        while (done < frames && q->running && !q->quit) {
            int64_t n = _scion_ui(UI_AUDIO_WRITE, (uint64_t)q->stream, U(out + done * ch), frames - done, 0, 0);
            if (n < 0) break;
            done += (UInt32)n;
            if (!started) { _scion_ui(UI_AUDIO_CTL, (uint64_t)q->stream, 0, 0, 0, 0); started = 1; }
            if (!n) break; /* stopped */
        }
        q->played += frames;
        give_back(q, b);
    }
    free(out);
    return NULL;
}
static OSStatus queue_new(const AudioStreamBasicDescription *f, AudioQueueRef *out, AudioQueueRef *qq) {
    if (!f || !out) return kAudio_ParamError;
    if (!fmt_ok(f)) return kAudioUnitErr_FormatNotSupported;
    AudioQueueRef q = calloc(1, sizeof *q);
    q->fmt = *f; q->volume = 1;
    pthread_mutex_init(&q->mu, NULL); pthread_cond_init(&q->cv, NULL);
    q->stream = _scion_ui(UI_AUDIO_OPEN, (uint64_t)(f->mSampleRate + 0.5), f->mChannelsPerFrame, 0, 0, 0);
    if (pthread_create(&q->thread, NULL, queue_thread, q)) { free(q); return kAudio_MemFullError; }
    *out = *qq = q;
    return noErr;
}
OSStatus AudioQueueNewOutput(const AudioStreamBasicDescription *f, AudioQueueOutputCallback cb, void *userData, const void *runLoop,
                             const void *runLoopMode, UInt32 flags, AudioQueueRef *out) {
    AudioQueueRef q;
    OSStatus r = queue_new(f, out, &q);
    if (r) return r;
    q->cb = cb; q->user = userData; q->on_main = runLoop && runLoop == CFRunLoopGetMain();
    return noErr;
}
OSStatus AudioQueueNewOutputWithDispatchQueue(AudioQueueRef *out, const AudioStreamBasicDescription *f, UInt32 flags, void *queue,
                                              AudioQueueOutputCallbackBlock cb) {
    AudioQueueRef q;
    OSStatus r = queue_new(f, out, &q);
    if (r) return r;
    q->block = _Block_copy(cb); q->dq = queue;
    return noErr;
}
OSStatus AudioQueueAllocateBufferWithPacketDescriptions(AudioQueueRef q, UInt32 size, UInt32 n, AudioQueueBufferRef *out) {
    if (!q || !out) return kAudio_ParamError;
    struct qbuf *b = calloc(1, sizeof *b);
    AudioQueueBuffer init = {size, calloc(1, size ? size : 1), 0, NULL, n, n ? calloc(n, sizeof(AudioStreamPacketDescription)) : NULL, 0};
    memcpy(&b->b, &init, sizeof init);
    *out = &b->b;
    return noErr;
}
OSStatus AudioQueueAllocateBuffer(AudioQueueRef q, UInt32 size, AudioQueueBufferRef *out) { return AudioQueueAllocateBufferWithPacketDescriptions(q, size, 0, out); }
OSStatus AudioQueueFreeBuffer(AudioQueueRef q, AudioQueueBufferRef b) {
    if (!b) return kAudio_ParamError;
    struct qbuf *x = (struct qbuf *)b;
    if (x->queued) return kAudioQueueErr_InvalidBuffer;
    free(b->mAudioData); free(b->mPacketDescriptions); free(x);
    return noErr;
}
OSStatus AudioQueueEnqueueBuffer(AudioQueueRef q, AudioQueueBufferRef b, UInt32 n, const AudioStreamPacketDescription *d) {
    if (!q || !b) return kAudio_ParamError;
    struct qbuf *x = (struct qbuf *)b;
    pthread_mutex_lock(&q->mu);
    x->next = NULL; x->queued = 1;
    if (q->tail) q->tail->next = x; else q->head = x;
    q->tail = x;
    pthread_cond_broadcast(&q->cv);
    pthread_mutex_unlock(&q->mu);
    return noErr;
}
OSStatus AudioQueueStart(AudioQueueRef q, const AudioTimeStamp *t) {
    if (!q) return kAudio_ParamError;
    pthread_mutex_lock(&q->mu); q->running = 1; q->paused = 0; q->stopping = 0; pthread_cond_broadcast(&q->cv); pthread_mutex_unlock(&q->mu);
    _scion_ui(UI_AUDIO_CTL, (uint64_t)q->stream, 0, 0, 0, 0);
    return noErr;
}
OSStatus AudioQueuePrime(AudioQueueRef q, UInt32 frames, UInt32 *prepared) { if (prepared) *prepared = frames; return noErr; }
OSStatus AudioQueuePause(AudioQueueRef q) {
    if (!q) return kAudio_ParamError;
    pthread_mutex_lock(&q->mu); q->paused = 1; pthread_mutex_unlock(&q->mu);
    return noErr;
}
OSStatus AudioQueueStop(AudioQueueRef q, Boolean immediate) {
    if (!q) return kAudio_ParamError;
    pthread_mutex_lock(&q->mu);
    if (!immediate) { q->stopping = 1; pthread_cond_broadcast(&q->cv); pthread_mutex_unlock(&q->mu); return noErr; } /* plays what is queued */
    q->running = 0;
    struct qbuf *b = q->head;
    q->head = q->tail = NULL;
    pthread_mutex_unlock(&q->mu);
    _scion_ui(UI_AUDIO_CTL, (uint64_t)q->stream, 1, 0, 0, 0);
    for (; b; ) { struct qbuf *n = b->next; b->queued = 0; give_back(q, b); b = n; } /* buffers come back, like on macOS */
    return noErr;
}
OSStatus AudioQueueFlush(AudioQueueRef q) { return noErr; }
OSStatus AudioQueueReset(AudioQueueRef q) { OSStatus r = AudioQueueStop(q, 1); if (!r && q) AudioQueueStart(q, NULL); return r; }
OSStatus AudioQueueDispose(AudioQueueRef q, Boolean immediate) {
    if (!q) return kAudio_ParamError;
    AudioQueueStop(q, 1);
    pthread_mutex_lock(&q->mu); q->quit = 1; pthread_cond_broadcast(&q->cv); pthread_mutex_unlock(&q->mu);
    if (!pthread_equal(pthread_self(), q->thread)) pthread_join(q->thread, NULL);
    _scion_ui(UI_AUDIO_CTL, (uint64_t)q->stream, 2, 0, 0, 0);
    if (q->block) _Block_release(q->block);
    /* ponytail: q itself is kept (a callback already dispatched may still name it) */
    return noErr;
}
OSStatus AudioQueueGetParameter(AudioQueueRef q, AudioQueueParameterID p, AudioQueueParameterValue *v) {
    if (!q || !v) return kAudio_ParamError;
    *v = p == kAudioQueueParam_Volume ? q->volume : p == kAudioQueueParam_PlayRate ? 1 : 0;
    return noErr;
}
OSStatus AudioQueueSetParameter(AudioQueueRef q, AudioQueueParameterID p, AudioQueueParameterValue v) {
    if (!q) return kAudio_ParamError;
    if (p == kAudioQueueParam_Volume) q->volume = v < 0 ? 0 : v > 1 ? 1 : v;
    return noErr;
}
OSStatus AudioQueueGetProperty(AudioQueueRef q, AudioQueuePropertyID p, void *data, UInt32 *size) {
    if (!q || !data || !size) return kAudio_ParamError;
    switch (p) {
    case kAudioQueueProperty_IsRunning: if (*size < 4) return kAudio_ParamError; *(UInt32 *)data = q->running; *size = 4; return noErr;
    case kAudioQueueDeviceProperty_SampleRate: if (*size < 8) return kAudio_ParamError; *(Float64 *)data = host_rate(); *size = 8; return noErr;
    case kAudioQueueDeviceProperty_NumberChannels: if (*size < 4) return kAudio_ParamError; *(UInt32 *)data = 2; *size = 4; return noErr;
    case kAudioQueueProperty_StreamDescription: if (*size < sizeof q->fmt) return kAudio_ParamError; memcpy(data, &q->fmt, sizeof q->fmt); *size = sizeof q->fmt; return noErr;
    }
    return kAudioQueueErr_InvalidProperty;
}
OSStatus AudioQueueSetProperty(AudioQueueRef q, AudioQueuePropertyID p, const void *data, UInt32 size) { return noErr; }
OSStatus AudioQueueGetPropertySize(AudioQueueRef q, AudioQueuePropertyID p, UInt32 *size) {
    if (!size) return kAudio_ParamError;
    *size = p == kAudioQueueProperty_StreamDescription ? sizeof(AudioStreamBasicDescription) : p == kAudioQueueDeviceProperty_SampleRate ? 8 : 4;
    return noErr;
}
OSStatus AudioQueueAddPropertyListener(AudioQueueRef q, AudioQueuePropertyID p, AudioQueuePropertyListenerProc l, void *data) { return noErr; }
OSStatus AudioQueueRemovePropertyListener(AudioQueueRef q, AudioQueuePropertyID p, AudioQueuePropertyListenerProc l, void *data) { return noErr; }
OSStatus AudioQueueGetCurrentTime(AudioQueueRef q, AudioQueueTimelineRef tl, AudioTimeStamp *t, Boolean *disc) {
    if (!q || !t) return kAudio_ParamError;
    int64_t queued = _scion_ui(UI_AUDIO_CTL, (uint64_t)q->stream, 3, 0, 0, 0);
    memset(t, 0, sizeof *t);
    t->mSampleTime = q->played - (queued > 0 ? queued : 0);
    t->mHostTime = mach_absolute_time();
    t->mFlags = kAudioTimeStampSampleTimeValid | kAudioTimeStampHostTimeValid;
    if (disc) *disc = 0;
    return noErr;
}
void AudioServicesPlaySystemSound(SystemSoundID s) { }
void AudioServicesPlayAlertSound(SystemSoundID s) { }

/* ======================================================================= CoreAudio HAL: one output device */
Boolean AudioObjectHasProperty(AudioObjectID o, const AudioObjectPropertyAddress *a) {
    switch (a->mSelector) {
    case kAudioHardwarePropertyDefaultOutputDevice: case kAudioHardwarePropertyDefaultSystemOutputDevice: case kAudioHardwarePropertyDevices:
        return o == kAudioObjectSystemObject;
    case kAudioDevicePropertyNominalSampleRate: case kAudioDevicePropertyBufferFrameSize: case kAudioDevicePropertyLatency:
    case kAudioDevicePropertyDeviceIsAlive: case kAudioDevicePropertySafetyOffset:
        return o == 1 && a->mScope != kAudioObjectPropertyScopeInput;
    }
    return 0;
}
OSStatus AudioObjectGetPropertyDataSize(AudioObjectID o, const AudioObjectPropertyAddress *a, UInt32 qn, const void *q, UInt32 *size) {
    if (!AudioObjectHasProperty(o, a)) return kAudioHardwareUnknownPropertyError;
    *size = a->mSelector == kAudioDevicePropertyNominalSampleRate ? sizeof(Float64) : sizeof(UInt32);
    return noErr;
}
OSStatus AudioObjectGetPropertyData(AudioObjectID o, const AudioObjectPropertyAddress *a, UInt32 qn, const void *q, UInt32 *size, void *data) {
    if (!a || !size || !data) return kAudio_ParamError;
    if (!AudioObjectHasProperty(o, a)) return kAudioHardwareUnknownPropertyError;
    switch (a->mSelector) {
    case kAudioDevicePropertyNominalSampleRate: if (*size < 8) return kAudio_ParamError; *(Float64 *)data = host_rate(); *size = 8; return noErr;
    case kAudioDevicePropertyBufferFrameSize: *(UInt32 *)data = 512; break;
    case kAudioDevicePropertyLatency: case kAudioDevicePropertySafetyOffset: *(UInt32 *)data = 0; break;
    case kAudioDevicePropertyDeviceIsAlive: *(UInt32 *)data = 1; break;
    default: *(UInt32 *)data = 1; break; /* the default device / the device list: device 1 */
    }
    *size = 4;
    return noErr;
}
OSStatus AudioObjectSetPropertyData(AudioObjectID o, const AudioObjectPropertyAddress *a, UInt32 qn, const void *q, UInt32 size, const void *data) {
    return a && AudioObjectHasProperty(o, a) ? noErr : kAudioHardwareUnknownPropertyError;
}
OSStatus AudioObjectAddPropertyListener(AudioObjectID o, const AudioObjectPropertyAddress *a, AudioObjectPropertyListenerProc p, void *data) { return noErr; }
OSStatus AudioObjectRemovePropertyListener(AudioObjectID o, const AudioObjectPropertyAddress *a, AudioObjectPropertyListenerProc p, void *data) { return noErr; }
