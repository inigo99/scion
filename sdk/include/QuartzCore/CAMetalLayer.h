/* scion: minimal QuartzCore subset for Metal presentation (CALayer, CAMetalLayer, CAMetalDrawable).
 * On Windows each CAMetalLayer shows its own window sized to drawableSize, created on the first -nextDrawable;
 * closing that window ends the program (like an app that quits after its last window closes). */
#pragma once
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CALayer : NSObject
+ (instancetype)layer;
@property(nonatomic) CGRect frame, bounds;
@property(nonatomic) CGPoint position;
@property CGPoint anchorPoint;
@property CGFloat contentsScale, zPosition;
@property(nonatomic) CGFloat cornerRadius, borderWidth;
@property(nonatomic) float opacity;
@property(getter=isOpaque) BOOL opaque;
@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic) BOOL masksToBounds;
@property BOOL needsDisplayOnBoundsChange, geometryFlipped;
@property(nonatomic) CGColorRef backgroundColor, borderColor;
@property(nonatomic, retain) id contents;
@property(copy) NSString *name;
@property(assign) id delegate;
@property(readonly) CALayer *superlayer;
@property(copy) NSArray *sublayers;
@property(copy) NSDictionary *actions;
@property(copy) NSString *contentsGravity;
- (void)addSublayer:(CALayer *)l;
- (void)insertSublayer:(CALayer *)l atIndex:(unsigned)i;
- (void)removeFromSuperlayer;
- (void)setNeedsDisplay;
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
- (void)displayIfNeeded;
- (void)removeAllAnimations;
@end

@interface CATransaction : NSObject
+ (void)begin; + (void)commit; + (void)flush;
+ (void)setDisableActions:(BOOL)b; + (void)setAnimationDuration:(CFTimeInterval)d;
@end
typedef NSString *CALayerContentsGravity;
CFTimeInterval CACurrentMediaTime(void);
extern NSString *const kCAGravityResize, *const kCAGravityResizeAspect, *const kCAGravityResizeAspectFill, *const kCAGravityCenter;

@protocol CAMetalDrawable <MTLDrawable>
@property(readonly) id<MTLTexture> texture;
@property(readonly) id layer;
@end

@interface CAMetalLayer : CALayer
@property(retain) id<MTLDevice> device;
@property(readonly) id<MTLDevice> preferredDevice;
@property(nonatomic) MTLPixelFormat pixelFormat;
@property BOOL framebufferOnly;
@property(nonatomic) CGSize drawableSize;
@property NSUInteger maximumDrawableCount;
@property BOOL presentsWithTransaction;
@property BOOL displaySyncEnabled;
@property BOOL allowsNextDrawableTimeout;
@property(readonly) id<MTLResidencySet> residencySet; /* scion: everything is resident; a set for the queue */
- (id<CAMetalDrawable>)nextDrawable;
@end
