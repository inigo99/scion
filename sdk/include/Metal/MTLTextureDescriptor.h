/* scion SDK — MTLTextureDescriptor */
#ifndef _METAL_MTLTEXTUREDESCRIPTOR_H_
#define _METAL_MTLTEXTUREDESCRIPTOR_H_
#import <Foundation/Foundation.h>
#import <Metal/MTLResource.h>
#import <Metal/MTLPixelFormat.h>
#import <Metal/MTLTexture.h>
@interface MTLTextureDescriptor : NSObject <NSCopying>
+ (MTLTextureDescriptor *)texture2DDescriptorWithPixelFormat:(MTLPixelFormat)f width:(NSUInteger)w height:(NSUInteger)h mipmapped:(BOOL)m;
+ (MTLTextureDescriptor *)textureCubeDescriptorWithPixelFormat:(MTLPixelFormat)f size:(NSUInteger)s mipmapped:(BOOL)m;
+ (MTLTextureDescriptor *)textureBufferDescriptorWithPixelFormat:(MTLPixelFormat)f width:(NSUInteger)w resourceOptions:(MTLResourceOptions)o usage:(MTLTextureUsage)u;
@property (assign, nonatomic) MTLTextureType textureType;
@property (assign, nonatomic) MTLPixelFormat pixelFormat;
@property (assign, nonatomic) NSUInteger width, height, depth, mipmapLevelCount, sampleCount, arrayLength;
@property (assign, nonatomic) MTLResourceOptions resourceOptions;
@property (assign, nonatomic) MTLCPUCacheMode cpuCacheMode;
@property (assign, nonatomic) MTLStorageMode storageMode;
@property (assign, nonatomic) MTLHazardTrackingMode hazardTrackingMode;
@property (assign, nonatomic) MTLTextureUsage usage;
@property (assign, nonatomic) BOOL allowGPUOptimizedContents;
@property (assign, nonatomic) MTLTextureSwizzleChannels swizzle;
@end
#endif
