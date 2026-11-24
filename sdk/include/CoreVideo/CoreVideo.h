/* scion SDK — CoreVideo subset: CVDisplayLink and the host clock (implemented in AppKit.dylib; dyld maps CoreVideo to it).
 * The display link calls back on its own thread once per refresh of the main display. */
#pragma once
#include <stdint.h>
#import <CoreGraphics/CoreGraphics.h>
CF_EXTERN_C_BEGIN
typedef int32_t CVReturn;
enum { kCVReturnSuccess = 0, kCVReturnError = -6660, kCVReturnInvalidArgument = -6661, kCVReturnAllocationFailed = -6662,
       kCVReturnInvalidDisplay = -6670, kCVReturnDisplayLinkAlreadyRunning = -6671, kCVReturnDisplayLinkNotRunning = -6672,
       kCVReturnDisplayLinkCallbacksNotSet = -6673 };
typedef uint64_t CVOptionFlags;
typedef struct CVSMPTETime { int16_t subframes, subframeDivisor; uint32_t counter, type, flags; int16_t hours, minutes, seconds, frames; } CVSMPTETime;
typedef struct CVTimeStamp {
    uint32_t version; int32_t videoTimeScale; int64_t videoTime; uint64_t hostTime; double rateScalar; int64_t videoRefreshPeriod;
    CVSMPTETime smpteTime; uint64_t flags; uint64_t reserved;
} CVTimeStamp;
enum { kCVTimeStampVideoTimeValid = 1 << 0, kCVTimeStampHostTimeValid = 1 << 1, kCVTimeStampSMPTETimeValid = 1 << 2,
       kCVTimeStampVideoRefreshPeriodValid = 1 << 3, kCVTimeStampRateScalarValid = 1 << 4 };
typedef struct CVTime { int64_t timeValue; int32_t timeScale; int32_t flags; } CVTime;
enum { kCVTimeIsIndefinite = 1 << 0 };
typedef struct __CVDisplayLink *CVDisplayLinkRef;
typedef CVReturn (*CVDisplayLinkOutputCallback)(CVDisplayLinkRef link, const CVTimeStamp *now, const CVTimeStamp *outputTime,
                                               CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *context);
typedef CVReturn (^CVDisplayLinkOutputHandler)(CVDisplayLinkRef link, const CVTimeStamp *now, const CVTimeStamp *outputTime,
                                               CVOptionFlags flagsIn, CVOptionFlags *flagsOut);
CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef *out);
CVReturn CVDisplayLinkCreateWithCGDisplay(CGDirectDisplayID d, CVDisplayLinkRef *out);
CVReturn CVDisplayLinkCreateWithCGDisplays(CGDirectDisplayID *d, long count, CVDisplayLinkRef *out);
CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef l, CVDisplayLinkOutputCallback cb, void *context);
CVReturn CVDisplayLinkSetOutputHandler(CVDisplayLinkRef l, CVDisplayLinkOutputHandler h);
CVReturn CVDisplayLinkSetCurrentCGDisplay(CVDisplayLinkRef l, CGDirectDisplayID d);
CGDirectDisplayID CVDisplayLinkGetCurrentCGDisplay(CVDisplayLinkRef l);
CVReturn CVDisplayLinkStart(CVDisplayLinkRef l);
CVReturn CVDisplayLinkStop(CVDisplayLinkRef l);
int CVDisplayLinkIsRunning(CVDisplayLinkRef l);
CVDisplayLinkRef CVDisplayLinkRetain(CVDisplayLinkRef l);
void CVDisplayLinkRelease(CVDisplayLinkRef l);
CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod(CVDisplayLinkRef l);
double CVDisplayLinkGetActualOutputVideoRefreshPeriod(CVDisplayLinkRef l);
CVReturn CVDisplayLinkGetCurrentTime(CVDisplayLinkRef l, CVTimeStamp *out);
uint64_t CVGetCurrentHostTime(void);
double CVGetHostClockFrequency(void);
uint32_t CVGetHostClockMinimumTimeDelta(void);
CF_EXTERN_C_END
