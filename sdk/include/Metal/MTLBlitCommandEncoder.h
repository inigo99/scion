/* scion SDK — MTLBlitCommandEncoder */
#ifndef _METAL_MTLBLITCOMMANDENCODER_H_
#define _METAL_MTLBLITCOMMANDENCODER_H_
#import <Foundation/Foundation.h>
#import <Metal/MTLCommandEncoder.h>
#import <Metal/MTLTypes.h>
@protocol MTLBuffer, MTLTexture, MTLResource;
typedef NS_OPTIONS(NSUInteger, MTLBlitOption) { MTLBlitOptionNone = 0, MTLBlitOptionDepthFromDepthStencil = 1, MTLBlitOptionStencilFromDepthStencil = 2, MTLBlitOptionRowLinearPVRTC = 4 };
@protocol MTLBlitCommandEncoder <MTLCommandEncoder>
- (void)copyFromBuffer:(id<MTLBuffer>)src sourceOffset:(NSUInteger)so toBuffer:(id<MTLBuffer>)dst destinationOffset:(NSUInteger)doff size:(NSUInteger)size;
- (void)copyFromBuffer:(id<MTLBuffer>)src sourceOffset:(NSUInteger)so sourceBytesPerRow:(NSUInteger)bpr sourceBytesPerImage:(NSUInteger)bpi
            sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)dst destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)o;
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)size
               toBuffer:(id<MTLBuffer>)dst destinationOffset:(NSUInteger)doff destinationBytesPerRow:(NSUInteger)bpr destinationBytesPerImage:(NSUInteger)bpi;
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)size
              toTexture:(id<MTLTexture>)dst destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)o;
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)size
               toBuffer:(id<MTLBuffer>)dst destinationOffset:(NSUInteger)doff destinationBytesPerRow:(NSUInteger)bpr destinationBytesPerImage:(NSUInteger)bpi options:(MTLBlitOption)options;
- (void)copyFromTexture:(id<MTLTexture>)src toTexture:(id<MTLTexture>)dst;
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl toTexture:(id<MTLTexture>)dst
       destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl sliceCount:(NSUInteger)sc levelCount:(NSUInteger)lc;
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value;
- (void)generateMipmapsForTexture:(id<MTLTexture>)texture;
- (void)synchronizeResource:(id<MTLResource>)resource;
@end
#endif
