/* scion SDK — MetalKit subset: MTKView (implemented in AppKit.dylib; dyld maps MetalKit to it).
 * MTKTextureLoader and the model I/O helpers are not provided. */
#pragma once
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@class MTKView;
@protocol MTKViewDelegate <NSObject>
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInMTKView:(MTKView *)view;
@end

@interface MTKView : NSView
- (instancetype)initWithFrame:(CGRect)r device:(id<MTLDevice>)d;
@property(retain) id<MTLDevice> device;
@property(assign) id<MTKViewDelegate> delegate;
@property(readonly) id<CAMetalDrawable> currentDrawable;
@property(readonly) MTLRenderPassDescriptor *currentRenderPassDescriptor;
@property(readonly) id<MTLTexture> depthStencilTexture, multisampleColorTexture;
@property MTLPixelFormat colorPixelFormat, depthStencilPixelFormat;
@property MTLTextureUsage depthStencilAttachmentTextureUsage;
@property MTLStorageMode depthStencilStorageMode;
@property NSUInteger sampleCount;
@property MTLClearColor clearColor;
@property double clearDepth;
@property uint32_t clearStencil;
@property NSInteger preferredFramesPerSecond;
@property(getter=isPaused) BOOL paused;
@property BOOL enableSetNeedsDisplay, autoResizeDrawable, framebufferOnly, presentsWithTransaction;
@property CGSize drawableSize;
@property(readonly) CGSize preferredDrawableSize;
@property(readonly) id<MTLDevice> preferredDevice;
@property CGColorSpaceRef colorspace;
- (void)draw;
- (void)releaseDrawables;
@end
