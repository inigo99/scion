// scion: heaps, fences, events and argument encoders.
#import <Foundation/Foundation.h>
#import <Metal/MTLDefines.h>
#import <Metal/MTLTypes.h>
#import <Metal/MTLResource.h>
#include <dispatch/dispatch.h>

METAL_DECLARATIONS_BEGIN
@protocol MTLDevice, MTLBuffer, MTLTexture, MTLSamplerState, MTLRenderPipelineState, MTLComputePipelineState;
@class MTLTextureDescriptor;

typedef NS_ENUM(NSInteger, MTLHeapType) { MTLHeapTypeAutomatic = 0, MTLHeapTypePlacement = 1, MTLHeapTypeSparse = 2 };
typedef NS_ENUM(NSUInteger, MTLPurgeableState) { MTLPurgeableStateKeepCurrent = 1, MTLPurgeableStateNonVolatile = 2, MTLPurgeableStateVolatile = 3, MTLPurgeableStateEmpty = 4 };
typedef struct { NSUInteger size; NSUInteger align; } MTLSizeAndAlign;

MTL_EXPORT @interface MTLHeapDescriptor : NSObject <NSCopying>
@property(nonatomic) NSUInteger size;
@property(nonatomic) MTLStorageMode storageMode;
@property(nonatomic) MTLCPUCacheMode cpuCacheMode;
@property(nonatomic) MTLHazardTrackingMode hazardTrackingMode;
@property(nonatomic) MTLResourceOptions resourceOptions;
@property(nonatomic) MTLHeapType type;
@end
@protocol MTLHeap <NSObject>
@property(nullable, copy, atomic) NSString *label;
@property(readonly) id<MTLDevice> device;
@property(readonly) MTLStorageMode storageMode;
@property(readonly) MTLCPUCacheMode cpuCacheMode;
@property(readonly) MTLHazardTrackingMode hazardTrackingMode;
@property(readonly) MTLResourceOptions resourceOptions;
@property(readonly) NSUInteger size;
@property(readonly) NSUInteger usedSize;
@property(readonly) NSUInteger currentAllocatedSize;
@property(readonly) MTLHeapType type;
- (NSUInteger)maxAvailableSizeWithAlignment:(NSUInteger)alignment;
- (nullable id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
- (nullable id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options offset:(NSUInteger)offset;
- (nullable id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (nullable id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset;
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state;
@end

@protocol MTLFence <NSObject>
@property(readonly) id<MTLDevice> device;
@property(nullable, copy, atomic) NSString *label;
@end
@protocol MTLEvent <NSObject>
@property(nullable, readonly) id<MTLDevice> device;
@property(nullable, copy, atomic) NSString *label;
@end
@class MTLSharedEventListener;
@protocol MTLSharedEvent;
typedef void (^MTLSharedEventNotificationBlock)(id<MTLSharedEvent>, uint64_t value);
@protocol MTLSharedEvent <MTLEvent>
@property(readwrite) uint64_t signaledValue;
- (void)notifyListener:(MTLSharedEventListener *)listener atValue:(uint64_t)value block:(MTLSharedEventNotificationBlock)block;
- (BOOL)waitUntilSignaledValue:(uint64_t)value timeoutMS:(uint64_t)milliseconds;
@end
MTL_EXPORT @interface MTLSharedEventListener : NSObject
- (instancetype)initWithDispatchQueue:(dispatch_queue_t)dispatchQueue;
@property(nonatomic, readonly) dispatch_queue_t dispatchQueue;
+ (MTLSharedEventListener *)sharedListener;
@end

/* argument buffers (tier 2 layout: 8 bytes per buffer address, texture or sampler ID) */
@protocol MTLArgumentEncoder <NSObject>
@property(readonly) id<MTLDevice> device;
@property(nullable, copy, atomic) NSString *label;
@property(readonly) NSUInteger encodedLength;
@property(readonly) NSUInteger alignment;
- (void)setArgumentBuffer:(nullable id<MTLBuffer>)argumentBuffer offset:(NSUInteger)offset;
- (void)setArgumentBuffer:(nullable id<MTLBuffer>)argumentBuffer startOffset:(NSUInteger)startOffset arrayElement:(NSUInteger)arrayElement;
- (void)setBuffer:(nullable id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setBuffers:(const id<MTLBuffer> __nullable[_Nonnull])buffers offsets:(const NSUInteger[_Nonnull])offsets withRange:(NSRange)range;
- (void)setTexture:(nullable id<MTLTexture>)texture atIndex:(NSUInteger)index;
- (void)setTextures:(const id<MTLTexture> __nullable[_Nonnull])textures withRange:(NSRange)range;
- (void)setSamplerState:(nullable id<MTLSamplerState>)sampler atIndex:(NSUInteger)index;
- (void)setSamplerStates:(const id<MTLSamplerState> __nullable[_Nonnull])samplers withRange:(NSRange)range;
- (void *)constantDataAtIndex:(NSUInteger)index;
- (nullable id<MTLArgumentEncoder>)newArgumentEncoderForBufferAtIndex:(NSUInteger)index;
@end
METAL_DECLARATIONS_END
