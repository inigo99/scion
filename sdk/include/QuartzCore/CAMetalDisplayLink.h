/* scion: CAMetalDisplayLink (macOS 14): calls its delegate on its run loop at the display rate with the next drawable.
 * Here a timer at the preferred rate's preferred value (60 Hz when unset) drives it. */
#pragma once
#import <QuartzCore/CAMetalLayer.h>

typedef struct CAFrameRateRange { float minimum, maximum, preferred; } CAFrameRateRange;
static inline CAFrameRateRange CAFrameRateRangeMake(float minimum, float maximum, float preferred) {
    CAFrameRateRange r = {minimum, maximum, preferred}; return r;
}
extern const CAFrameRateRange CAFrameRateRangeDefault;

@class CAMetalDisplayLink;
@interface CAMetalDisplayLinkUpdate : NSObject
@property(readonly) id<CAMetalDrawable> drawable;
@property(readonly) CFTimeInterval targetTimestamp, targetPresentationTimestamp;
@end
@protocol CAMetalDisplayLinkDelegate <NSObject>
- (void)metalDisplayLink:(CAMetalDisplayLink *)link needsUpdate:(CAMetalDisplayLinkUpdate *)update;
@end
@interface CAMetalDisplayLink : NSObject
- (instancetype)initWithMetalLayer:(CAMetalLayer *)layer;
@property(weak) id<CAMetalDisplayLinkDelegate> delegate;
@property CAFrameRateRange preferredFrameRateRange;
@property NSInteger preferredFrameLatency;
@property(getter=isPaused) BOOL paused;
- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode;
- (void)removeFromRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode;
- (void)invalidate;
@end
