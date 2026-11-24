/* scion SDK — MTLSamplerDescriptor */
#ifndef _METAL_MTLSAMPLERDESCRIPTOR_H_
#define _METAL_MTLSAMPLERDESCRIPTOR_H_
#import <Foundation/Foundation.h>
#import <Metal/MTLDepthStencilDescriptor.h>
#import <Metal/MTLTypes.h>
@protocol MTLDevice;
typedef NS_ENUM(NSUInteger, MTLSamplerMinMagFilter) { MTLSamplerMinMagFilterNearest = 0, MTLSamplerMinMagFilterLinear = 1 };
typedef NS_ENUM(NSUInteger, MTLSamplerMipFilter) { MTLSamplerMipFilterNotMipmapped = 0, MTLSamplerMipFilterNearest = 1, MTLSamplerMipFilterLinear = 2 };
typedef NS_ENUM(NSUInteger, MTLSamplerAddressMode) {
    MTLSamplerAddressModeClampToEdge = 0, MTLSamplerAddressModeMirrorClampToEdge = 1, MTLSamplerAddressModeRepeat = 2,
    MTLSamplerAddressModeMirrorRepeat = 3, MTLSamplerAddressModeClampToZero = 4, MTLSamplerAddressModeClampToBorderColor = 5,
};
typedef NS_ENUM(NSUInteger, MTLSamplerBorderColor) { MTLSamplerBorderColorTransparentBlack = 0, MTLSamplerBorderColorOpaqueBlack = 1, MTLSamplerBorderColorOpaqueWhite = 2 };
@interface MTLSamplerDescriptor : NSObject <NSCopying>
@property (assign, nonatomic) MTLSamplerMinMagFilter minFilter, magFilter;
@property (assign, nonatomic) MTLSamplerMipFilter mipFilter;
@property (assign, nonatomic) NSUInteger maxAnisotropy;
@property (assign, nonatomic) MTLSamplerAddressMode sAddressMode, tAddressMode, rAddressMode;
@property (assign, nonatomic) MTLSamplerBorderColor borderColor;
@property (assign, nonatomic) BOOL normalizedCoordinates, supportArgumentBuffers, lodAverage;
@property (assign, nonatomic) float lodMinClamp, lodMaxClamp;
@property (assign, nonatomic) MTLCompareFunction compareFunction;
@property (copy, nonatomic) NSString *label;
@end
@protocol MTLSamplerState <NSObject>
@property (readonly) id<MTLDevice> device;
@property (readonly) MTLResourceID gpuResourceID;
@property (readonly) NSString *label;
@end
#endif
