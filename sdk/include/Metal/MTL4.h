// scion: Metal 4 (macOS 26): queues, allocators and command buffers made apart, argument tables bound by GPU
// address and resource ID, explicit barriers, residency sets, commit feedback, counter heaps.
// The implementation (src/metal/Metal4.m) records onto Metal 3 command buffers.
#import <Foundation/Foundation.h>
#import <Metal/MTLDefines.h>
#import <Metal/MTLTypes.h>
#import <Metal/MTLResource.h>
#import <Metal/MTLCommandEncoder.h>
#import <Metal/MTLRenderCommandEncoder.h>
#import <Metal/MTLComputeCommandEncoder.h>
#import <Metal/MTLBlitCommandEncoder.h>
#import <Metal/MTLResidencySet.h>
#import <Metal/MTLHeap.h>
#include <dispatch/dispatch.h>

METAL_DECLARATIONS_BEGIN
@protocol MTLDevice, MTLDrawable, MTLRenderPipelineState, MTLComputePipelineState, MTLDepthStencilState;
@protocol MTL4CommandBuffer, MTL4CommandQueue;

typedef NS_OPTIONS(NSUInteger, MTLStages) {
    MTLStageVertex = 1 << 0, MTLStageFragment = 1 << 1, MTLStageTile = 1 << 2, MTLStageObject = 1 << 3, MTLStageMesh = 1 << 4,
    MTLStageResourceState = 1 << 26, MTLStageDispatch = 1 << 27, MTLStageBlit = 1 << 28, MTLStageAccelerationStructure = 1 << 29,
    MTLStageMachineLearning = 1 << 30, MTLStageAll = NSIntegerMax,
};
typedef NS_OPTIONS(NSUInteger, MTL4VisibilityOptions) {
    MTL4VisibilityOptionNone = 0, MTL4VisibilityOptionDevice = 1 << 0, MTL4VisibilityOptionResourceAlias = 1 << 1,
};
typedef NS_OPTIONS(NSUInteger, MTL4RenderEncoderOptions) {
    MTL4RenderEncoderOptionNone = 0, MTL4RenderEncoderOptionSuspending = 1 << 0, MTL4RenderEncoderOptionResuming = 1 << 1,
};
typedef NS_ENUM(NSInteger, MTL4CounterHeapType) { MTL4CounterHeapTypeInvalid = 0, MTL4CounterHeapTypeTimestamp = 1 };
typedef NS_ENUM(NSInteger, MTL4TimestampGranularity) { MTL4TimestampGranularityRelaxed = 0, MTL4TimestampGranularityPrecise = 1 };
typedef NS_ENUM(NSInteger, MTLVisibilityResultType) { MTLVisibilityResultTypeReset = 0, MTLVisibilityResultTypeAccumulate = 1 };
typedef struct { uint64_t timestamp; } MTL4TimestampHeapEntry;
typedef struct { uint64_t bufferAddress; uint64_t length; } MTL4BufferRange;
static inline MTL4BufferRange MTL4BufferRangeMake(uint64_t a, uint64_t n) { MTL4BufferRange r = {a, n}; return r; }

/* ---- argument tables */
MTL_EXPORT @interface MTL4ArgumentTableDescriptor : NSObject <NSCopying>
@property(nonatomic) NSUInteger maxBufferBindCount;
@property(nonatomic) NSUInteger maxTextureBindCount;
@property(nonatomic) NSUInteger maxSamplerStateBindCount;
@property(nonatomic) BOOL initializeBindings;
@property(nonatomic) BOOL supportAttributeStrides;
@property(nullable, copy, nonatomic) NSString *label;
@end
@protocol MTL4ArgumentTable <NSObject>
@property(readonly) id<MTLDevice> device;
@property(nullable, readonly) NSString *label;
- (void)setAddress:(MTLGPUAddress)gpuAddress atIndex:(NSUInteger)bindingIndex;
- (void)setAddress:(MTLGPUAddress)gpuAddress attributeStride:(NSUInteger)stride atIndex:(NSUInteger)bindingIndex;
- (void)setResource:(MTLResourceID)resourceID atBufferIndex:(NSUInteger)bindingIndex;
- (void)setTexture:(MTLResourceID)resourceID atIndex:(NSUInteger)bindingIndex;
- (void)setSamplerState:(MTLResourceID)resourceID atIndex:(NSUInteger)bindingIndex;
@end

/* ---- allocators, commit options and feedback */
/* ---- compiler (scion: only creation; pipelines are built through the MTLDevice methods) */
MTL_EXPORT @interface MTL4CompilerDescriptor : NSObject <NSCopying>
@property(nullable, copy, nonatomic) NSString *label;
@property(nullable, retain, nonatomic) id pipelineDataSetSerializer;
@end
@protocol MTL4Compiler <NSObject>
@property(readonly) id<MTLDevice> device;
@property(nullable, readonly) NSString *label;
@end

MTL_EXPORT @interface MTL4CommandAllocatorDescriptor : NSObject <NSCopying>
@property(nullable, copy, nonatomic) NSString *label;
@end
@protocol MTL4CommandAllocator <NSObject>
@property(readonly) id<MTLDevice> device;
@property(nullable, readonly) NSString *label;
- (uint64_t)allocatedSize;
- (void)reset;
@end
@protocol MTL4CommitFeedback <NSObject>
@property(nullable, readonly) NSError *error;
@property(readonly) CFTimeInterval GPUStartTime;
@property(readonly) CFTimeInterval GPUEndTime;
@end
typedef void (^MTL4CommitFeedbackHandler)(id<MTL4CommitFeedback> commitFeedback);
MTL_EXPORT @interface MTL4CommitOptions : NSObject
- (void)addFeedbackHandler:(MTL4CommitFeedbackHandler)block;
@end
MTL_EXPORT @interface MTL4CommandBufferOptions : NSObject
@property(nullable, nonatomic, retain) id logState;
@end
MTL_EXPORT @interface MTL4CommandQueueDescriptor : NSObject <NSCopying>
@property(nullable, copy, nonatomic) NSString *label;
@property(nullable, nonatomic, retain) dispatch_queue_t feedbackQueue;
@end

/* ---- counter heaps (timestamps) */
MTL_EXPORT @interface MTL4CounterHeapDescriptor : NSObject <NSCopying>
@property(nonatomic) MTL4CounterHeapType type;
@property(nonatomic) NSUInteger count;
@end
@protocol MTL4CounterHeap <NSObject>
@property(nullable, copy, atomic) NSString *label;
@property(readonly) NSUInteger count;
@property(readonly) MTL4CounterHeapType type;
- (nullable NSData *)resolveCounterRange:(NSRange)range;
- (void)invalidateCounterRange:(NSRange)range;
@end

/* ---- render passes: the Metal 3 attachment descriptors */
MTL_EXPORT @interface MTL4RenderPassDescriptor : MTLRenderPassDescriptor
@property(nonatomic) MTLVisibilityResultType visibilityResultType;
@property(nonatomic) NSUInteger defaultRasterSampleCount;
@property(nonatomic) NSUInteger tileWidth;
@property(nonatomic) NSUInteger tileHeight;
@property(nonatomic) BOOL supportColorAttachmentMapping;
@end

/* ---- encoders */
@protocol MTL4CommandEncoder <NSObject>
@property(nullable, copy, atomic) NSString *label;
@property(readonly, nonatomic) id<MTL4CommandBuffer> commandBuffer;
- (void)barrierAfterQueueStages:(MTLStages)afterQueueStages beforeStages:(MTLStages)beforeStages visibilityOptions:(MTL4VisibilityOptions)options;
- (void)barrierAfterStages:(MTLStages)afterStages beforeQueueStages:(MTLStages)beforeQueueStages visibilityOptions:(MTL4VisibilityOptions)options;
- (void)barrierAfterEncoderStages:(MTLStages)afterEncoderStages beforeEncoderStages:(MTLStages)beforeEncoderStages visibilityOptions:(MTL4VisibilityOptions)options;
- (void)updateFence:(id<MTLFence>)fence afterEncoderStages:(MTLStages)afterEncoderStages;
- (void)waitForFence:(id<MTLFence>)fence beforeEncoderStages:(MTLStages)beforeEncoderStages;
- (void)insertDebugSignpost:(NSString *)string;
- (void)pushDebugGroup:(NSString *)string;
- (void)popDebugGroup;
- (void)endEncoding;
@end

@protocol MTL4ComputeCommandEncoder <MTL4CommandEncoder>
- (MTLStages)stages;
- (void)setComputePipelineState:(id<MTLComputePipelineState>)state;
- (void)setArgumentTable:(nullable id<MTL4ArgumentTable>)argumentTable;
- (void)setThreadgroupMemoryLength:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setImageblockWidth:(NSUInteger)width height:(NSUInteger)height;
- (void)dispatchThreads:(MTLSize)threadsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup;
- (void)dispatchThreadgroups:(MTLSize)threadgroupsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup;
- (void)dispatchThreadgroupsWithIndirectBuffer:(MTLGPUAddress)indirectBuffer threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup;
- (void)dispatchThreadsWithIndirectBuffer:(MTLGPUAddress)indirectBuffer;
- (void)copyFromBuffer:(id<MTLBuffer>)sourceBuffer sourceOffset:(NSUInteger)sourceOffset toBuffer:(id<MTLBuffer>)destinationBuffer
     destinationOffset:(NSUInteger)destinationOffset size:(NSUInteger)size;
- (void)copyFromBuffer:(id<MTLBuffer>)sourceBuffer sourceOffset:(NSUInteger)sourceOffset sourceBytesPerRow:(NSUInteger)sourceBytesPerRow
   sourceBytesPerImage:(NSUInteger)sourceBytesPerImage sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>)destinationTexture
      destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin;
- (void)copyFromBuffer:(id<MTLBuffer>)sourceBuffer sourceOffset:(NSUInteger)sourceOffset sourceBytesPerRow:(NSUInteger)sourceBytesPerRow
   sourceBytesPerImage:(NSUInteger)sourceBytesPerImage sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>)destinationTexture
      destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin options:(MTLBlitOption)options;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel
           sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toBuffer:(id<MTLBuffer>)destinationBuffer
      destinationOffset:(NSUInteger)destinationOffset destinationBytesPerRow:(NSUInteger)destinationBytesPerRow
destinationBytesPerImage:(NSUInteger)destinationBytesPerImage;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel
           sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toBuffer:(id<MTLBuffer>)destinationBuffer
      destinationOffset:(NSUInteger)destinationOffset destinationBytesPerRow:(NSUInteger)destinationBytesPerRow
destinationBytesPerImage:(NSUInteger)destinationBytesPerImage options:(MTLBlitOption)options;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel
           sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>)destinationTexture
       destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel
              toTexture:(id<MTLTexture>)destinationTexture destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel
             sliceCount:(NSUInteger)sliceCount levelCount:(NSUInteger)levelCount;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture toTexture:(id<MTLTexture>)destinationTexture;
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value;
- (void)generateMipmapsForTexture:(id<MTLTexture>)texture;
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)texture;
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)texture;
- (void)writeTimestampWithGranularity:(MTL4TimestampGranularity)granularity intoHeap:(id<MTL4CounterHeap>)counterHeap atIndex:(NSUInteger)index;
@end

@protocol MTL4RenderCommandEncoder <MTL4CommandEncoder>
@property(readonly) NSUInteger tileWidth;
@property(readonly) NSUInteger tileHeight;
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)pipelineState;
- (void)setArgumentTable:(id<MTL4ArgumentTable>)argumentTable atStages:(MTLRenderStages)stages;
- (void)setViewport:(MTLViewport)viewport;
- (void)setViewports:(const MTLViewport[_Nonnull])viewports count:(NSUInteger)count;
- (void)setScissorRect:(MTLScissorRect)rect;
- (void)setScissorRects:(const MTLScissorRect[_Nonnull])scissorRects count:(NSUInteger)count;
- (void)setCullMode:(MTLCullMode)cullMode;
- (void)setFrontFacingWinding:(MTLWinding)frontFacingWinding;
- (void)setTriangleFillMode:(MTLTriangleFillMode)fillMode;
- (void)setDepthClipMode:(MTLDepthClipMode)depthClipMode;
- (void)setDepthBias:(float)depthBias slopeScale:(float)slopeScale clamp:(float)clamp;
- (void)setDepthTestMinBound:(float)minBound maxBound:(float)maxBound;
- (void)setDepthStencilState:(nullable id<MTLDepthStencilState>)depthStencilState;
- (void)setStencilReferenceValue:(uint32_t)referenceValue;
- (void)setStencilFrontReferenceValue:(uint32_t)frontReferenceValue backReferenceValue:(uint32_t)backReferenceValue;
- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)mode offset:(NSUInteger)offset;
- (void)setColorStoreAction:(MTLStoreAction)storeAction atIndex:(NSUInteger)colorAttachmentIndex;
- (void)setDepthStoreAction:(MTLStoreAction)storeAction;
- (void)setStencilStoreAction:(MTLStoreAction)storeAction;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount
         instanceCount:(NSUInteger)instanceCount;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount
         instanceCount:(NSUInteger)instanceCount baseInstance:(NSUInteger)baseInstance;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType
                  indexBuffer:(MTLGPUAddress)indexBuffer indexBufferLength:(NSUInteger)indexBufferLength;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType
                  indexBuffer:(MTLGPUAddress)indexBuffer indexBufferLength:(NSUInteger)indexBufferLength instanceCount:(NSUInteger)instanceCount;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType
                  indexBuffer:(MTLGPUAddress)indexBuffer indexBufferLength:(NSUInteger)indexBufferLength instanceCount:(NSUInteger)instanceCount
                   baseVertex:(NSInteger)baseVertex baseInstance:(NSUInteger)baseInstance;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType indirectBuffer:(MTLGPUAddress)indirectBuffer;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexType:(MTLIndexType)indexType indexBuffer:(MTLGPUAddress)indexBuffer
            indexBufferLength:(NSUInteger)indexBufferLength indirectBuffer:(MTLGPUAddress)indirectBuffer;
- (void)writeTimestampWithGranularity:(MTL4TimestampGranularity)granularity afterStage:(MTLRenderStages)stage
                             intoHeap:(id<MTL4CounterHeap>)counterHeap atIndex:(NSUInteger)index;
@end

/* ---- command buffers and queues */
@protocol MTL4CommandBuffer <NSObject>
@property(readonly) id<MTLDevice> device;
@property(nullable, copy, atomic) NSString *label;
- (void)beginCommandBufferWithAllocator:(id<MTL4CommandAllocator>)allocator;
- (void)beginCommandBufferWithAllocator:(id<MTL4CommandAllocator>)allocator options:(MTL4CommandBufferOptions *)options;
- (void)endCommandBuffer;
- (nullable id<MTL4RenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTL4RenderPassDescriptor *)descriptor;
- (nullable id<MTL4RenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTL4RenderPassDescriptor *)descriptor options:(MTL4RenderEncoderOptions)options;
- (nullable id<MTL4ComputeCommandEncoder>)computeCommandEncoder;
- (void)useResidencySet:(id<MTLResidencySet>)residencySet;
- (void)useResidencySets:(const id<MTLResidencySet> _Nonnull[_Nonnull])residencySets count:(NSUInteger)count;
- (void)pushDebugGroup:(NSString *)string;
- (void)popDebugGroup;
- (void)writeTimestampIntoHeap:(id<MTL4CounterHeap>)counterHeap atIndex:(NSUInteger)index;
- (void)resolveCounterHeap:(id<MTL4CounterHeap>)counterHeap withRange:(NSRange)range intoBuffer:(MTL4BufferRange)bufferRange
                 waitFence:(nullable id<MTLFence>)fenceToWait updateFence:(nullable id<MTLFence>)fenceToUpdate;
@end

@protocol MTL4CommandQueue <NSObject>
@property(readonly) id<MTLDevice> device;
@property(nullable, readonly) NSString *label;
- (void)commit:(const id<MTL4CommandBuffer> _Nonnull[_Nonnull])commandBuffers count:(NSUInteger)count;
- (void)commit:(const id<MTL4CommandBuffer> _Nonnull[_Nonnull])commandBuffers count:(NSUInteger)count options:(MTL4CommitOptions *)options;
- (void)signalEvent:(id<MTLEvent>)event value:(uint64_t)value;
- (void)waitForEvent:(id<MTLEvent>)event value:(uint64_t)value;
- (void)signalDrawable:(id<MTLDrawable>)drawable;
- (void)waitForDrawable:(id<MTLDrawable>)drawable;
- (void)addResidencySet:(id<MTLResidencySet>)residencySet;
- (void)addResidencySets:(const id<MTLResidencySet> _Nonnull[_Nonnull])residencySets count:(NSUInteger)count;
- (void)removeResidencySet:(id<MTLResidencySet>)residencySet;
- (void)removeResidencySets:(const id<MTLResidencySet> _Nonnull[_Nonnull])residencySets count:(NSUInteger)count;
@end
METAL_DECLARATIONS_END
