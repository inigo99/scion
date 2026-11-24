/* scion SDK — MetalFX: spatial and temporal upscalers (implemented in Metal.dylib with a bilinear + sharpen pass;
 * the temporal scaler ignores depth/motion and only removes the camera jitter). */
#pragma once
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

typedef NS_ENUM(NSInteger, MTLFXSpatialScalerColorProcessingMode) {
    MTLFXSpatialScalerColorProcessingModePerceptual = 0, MTLFXSpatialScalerColorProcessingModeLinear = 1, MTLFXSpatialScalerColorProcessingModeHDR = 2,
};

@protocol MTLFXSpatialScaler <NSObject>
@property(readonly) MTLTextureUsage colorTextureUsage, outputTextureUsage;
@property NSUInteger inputContentWidth, inputContentHeight;
@property(retain) id<MTLTexture> colorTexture, outputTexture;
@property(readonly) MTLPixelFormat colorTextureFormat, outputTextureFormat;
@property(readonly) NSUInteger inputWidth, inputHeight, outputWidth, outputHeight;
@property(readonly) MTLFXSpatialScalerColorProcessingMode colorProcessingMode;
@property(retain) id fence;
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;
@end

@protocol MTLFXTemporalScaler <NSObject>
@property(readonly) MTLTextureUsage colorTextureUsage, depthTextureUsage, motionTextureUsage, reactiveTextureUsage, outputTextureUsage;
@property NSUInteger inputContentWidth, inputContentHeight;
@property(retain) id<MTLTexture> colorTexture, depthTexture, motionTexture, outputTexture, exposureTexture, reactiveMaskTexture;
@property float preExposure, jitterOffsetX, jitterOffsetY, motionVectorScaleX, motionVectorScaleY;
@property BOOL reset;
@property(getter=isDepthReversed) BOOL depthReversed;
@property(readonly) MTLPixelFormat colorTextureFormat, depthTextureFormat, motionTextureFormat, outputTextureFormat, reactiveMaskTextureFormat;
@property(readonly) NSUInteger inputWidth, inputHeight, outputWidth, outputHeight;
@property(readonly) float inputContentMinScale, inputContentMaxScale;
@property(retain) id fence;
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;
@end

/* Metal 4: the same scaler, encoded into a Metal 4 command buffer (the host orders it; the fence is not needed) */
@protocol MTL4FXSpatialScaler <NSObject>
@property(readonly) MTLTextureUsage colorTextureUsage, outputTextureUsage;
@property NSUInteger inputContentWidth, inputContentHeight;
@property(retain) id<MTLTexture> colorTexture, outputTexture;
@property(readonly) MTLPixelFormat colorTextureFormat, outputTextureFormat;
@property(readonly) NSUInteger inputWidth, inputHeight, outputWidth, outputHeight;
@property(readonly) MTLFXSpatialScalerColorProcessingMode colorProcessingMode;
@property(retain) id<MTLFence> fence;
- (void)encodeToCommandBuffer:(id<MTL4CommandBuffer>)commandBuffer;
@end

@interface MTLFXSpatialScalerDescriptor : NSObject <NSCopying>
@property MTLPixelFormat colorTextureFormat, outputTextureFormat;
@property NSUInteger inputWidth, inputHeight, outputWidth, outputHeight;
@property MTLFXSpatialScalerColorProcessingMode colorProcessingMode;
- (id<MTLFXSpatialScaler>)newSpatialScalerWithDevice:(id<MTLDevice>)device;
- (id<MTL4FXSpatialScaler>)newSpatialScalerWithDevice:(id<MTLDevice>)device compiler:(id<MTL4Compiler>)compiler;
+ (BOOL)supportsDevice:(id<MTLDevice>)device;
@end

@interface MTLFXTemporalScalerDescriptor : NSObject <NSCopying>
@property MTLPixelFormat colorTextureFormat, depthTextureFormat, motionTextureFormat, outputTextureFormat, reactiveMaskTextureFormat;
@property NSUInteger inputWidth, inputHeight, outputWidth, outputHeight;
@property(getter=isAutoExposureEnabled) BOOL autoExposureEnabled;
@property(getter=isInputContentPropertiesEnabled) BOOL inputContentPropertiesEnabled;
@property(getter=isReactiveMaskTextureEnabled) BOOL reactiveMaskTextureEnabled;
@property BOOL requiresSynchronousInitialization;
@property float inputContentMinScale, inputContentMaxScale;
- (id<MTLFXTemporalScaler>)newTemporalScalerWithDevice:(id<MTLDevice>)device;
+ (BOOL)supportsDevice:(id<MTLDevice>)device;
+ (float)supportedInputContentMinScaleForDevice:(id<MTLDevice>)device;
+ (float)supportedInputContentMaxScaleForDevice:(id<MTLDevice>)device;
@end
