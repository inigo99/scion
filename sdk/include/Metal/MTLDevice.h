// SPDX-FileCopyrightText: 2026 Darling Developers
// SPDX-License-Identifier: MPL-2.0

#ifndef _METAL_MTLDEVICE_H_
#define _METAL_MTLDEVICE_H_

#import <Foundation/Foundation.h>
#import <Metal/MTLTypes.h>
#import <Metal/MTLCompileOptions.h>

#if __has_include(<dispatch/dispatch.h>)
#include <dispatch/dispatch.h>
#else
typedef struct dispatch_data_s *dispatch_data_t;
#endif
#import <Metal/MTLResource.h>
#import <Metal/MTLDefines.h>
#import <Metal/MTLResidencySet.h>

METAL_DECLARATIONS_BEGIN

@protocol MTLComputePipelineState;
@protocol MTLFunction;
@protocol MTLCommandQueue;
@protocol MTLDevice;
@protocol MTLBuffer;
@protocol MTLLibrary;
@protocol MTLRenderPipelineState;

@class MTLComputePipelineDescriptor;
@class MTLAutoreleasedComputePipelineReflection;
@class MTLRenderPipelineDescriptor, MTLTextureDescriptor, MTLSamplerDescriptor, MTLDepthStencilDescriptor, MTLCompileOptions;
@protocol MTLTexture, MTLSamplerState, MTLDepthStencilState;

typedef NS_OPTIONS(NSUInteger, MTLPipelineOption) {
	MTLPipelineOptionNone = 0,
	MTLPipelineOptionArgumentInfo = 1 << 0,
	MTLPipelineOptionBufferTypeInfo = 1 << 1,
	MTLPipelineOptionFailOnBinaryArchiveMiss = 1 << 2,
};

typedef NSString* MTLDeviceNotificationName;
typedef void (^MTLDeviceNotificationHandler)(id<MTLDevice> device, MTLDeviceNotificationName notifyName);

MTL_EXPORT MTL_EXTERN const MTLDeviceNotificationName MTLDeviceWasAddedNotification;
MTL_EXPORT MTL_EXTERN const MTLDeviceNotificationName MTLDeviceRemovalRequestedNotification;
MTL_EXPORT MTL_EXTERN const MTLDeviceNotificationName MTLDeviceWasRemovedNotification;

MTL_EXPORT id<MTLDevice> MTLCreateSystemDefaultDevice(void) NS_RETURNS_RETAINED;
MTL_EXPORT NSArray<id<MTLDevice>>* MTLCopyAllDevices(void) NS_RETURNS_RETAINED;
MTL_EXPORT NSArray<id<MTLDevice>>* MTLCopyAllDevicesWithObserver(id<NSObject>* observer, MTLDeviceNotificationHandler handler);
MTL_EXPORT void MTLRemoveDeviceObserver(id<NSObject> observer);

@protocol MTLHeap, MTLFence, MTLEvent, MTLSharedEvent, MTLArgumentEncoder, MTL4CommandQueue, MTL4CommandBuffer, MTL4CommandAllocator, MTL4ArgumentTable, MTL4CounterHeap;
@class MTLHeapDescriptor, MTL4CommandQueueDescriptor, MTL4CommandAllocatorDescriptor, MTL4ArgumentTableDescriptor, MTL4CounterHeapDescriptor;
#import <Metal/MTLHeap.h>
#import <Metal/MTL4.h>
@protocol MTLDevice <NSObject>

- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor: (MTLComputePipelineDescriptor*)descriptor
                                                             options: (MTLPipelineOption)options
                                                          reflection: (MTLAutoreleasedComputePipelineReflection*)reflection
                                                               error: (NSError**)error;

- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction: (id<MTLFunction>)computeFunction 
                                                             error: (NSError**)error;

- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction: (id<MTLFunction>)computeFunction 
                                                           options: (MTLPipelineOption)options 
                                                        reflection: (MTLAutoreleasedComputePipelineReflection*)reflection 
                                                             error: (NSError**)error;

- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor: (MTLRenderPipelineDescriptor*)descriptor
                                                             error: (NSError**)error;

- (id<MTLCommandQueue>)newCommandQueue;

- (id<MTLBuffer>)newBufferWithLength: (NSUInteger)length
                             options: (MTLResourceOptions)options;

- (id<MTLBuffer>)newBufferWithBytes: (const void*)pointer
                             length: (NSUInteger)length
                            options: (MTLResourceOptions)options;

- (id<MTLLibrary>)newDefaultLibrary;

- (id<MTLLibrary>)newDefaultLibraryWithBundle: (NSBundle*)bundle
                                        error: (NSError**)error;

- (id<MTLLibrary>)newLibraryWithURL: (NSURL*)url
                              error: (NSError**)error;

- (id<MTLLibrary>)newLibraryWithData: (dispatch_data_t)data
                               error: (NSError**)error;

// TODO: other methods and properties

@property (readonly) NSString *name;
@property (readonly) MTLSize maxThreadsPerThreadgroup;
@property (readonly) BOOL hasUnifiedMemory;
@property (readonly, getter=isLowPower) BOOL lowPower;
@property (readonly, getter=isHeadless) BOOL headless;
@property (readonly, getter=isRemovable) BOOL removable;
@property (readonly) uint64_t registryID, recommendedMaxWorkingSetSize;
@property (readonly) NSUInteger currentAllocatedSize;
@property (readonly) NSUInteger maxThreadgroupMemoryLength, maxBufferLength;
- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)n;
- (id<MTLBuffer>)newBufferWithBytesNoCopy:(void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options deallocator:(void (^)(void *pointer, NSUInteger length))deallocator;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (id<MTLSamplerState>)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)descriptor;
- (id<MTLDepthStencilState>)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)descriptor;
- (id<MTLLibrary>)newLibraryWithFile:(NSString *)filepath error:(NSError **)error;
- (id<MTLLibrary>)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options error:(NSError **)error;
- (void)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options completionHandler:(void (^)(id<MTLLibrary> library, NSError *error))completionHandler;
- (BOOL)supportsFamily:(NSInteger)family;
- (BOOL)supportsTextureSampleCount:(NSUInteger)sampleCount;
- (nullable id<MTLResidencySet>)newResidencySetWithDescriptor:(MTLResidencySetDescriptor *)d error:(NSError **)error;
/* heaps, fences, events */
- (nullable id<MTLHeap>)newHeapWithDescriptor:(MTLHeapDescriptor *)descriptor;
- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)desc;
- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
- (nullable id<MTLFence>)newFence;
- (nullable id<MTLEvent>)newEvent;
- (nullable id<MTLSharedEvent>)newSharedEvent;
- (nullable id<MTLArgumentEncoder>)newArgumentEncoderWithArguments:(NSArray *)arguments;
@property(readonly) NSUInteger argumentBuffersSupport;
@property(readonly) BOOL supportsBCTextureCompression;
/* Metal 4 */
- (nullable id<MTL4CommandQueue>)newMTL4CommandQueue;
- (nullable id<MTL4CommandQueue>)newMTL4CommandQueueWithDescriptor:(MTL4CommandQueueDescriptor *)descriptor error:(NSError **)error;
- (nullable id<MTL4CommandBuffer>)newCommandBuffer;
- (nullable id<MTL4CommandAllocator>)newCommandAllocator;
- (nullable id<MTL4CommandAllocator>)newCommandAllocatorWithDescriptor:(MTL4CommandAllocatorDescriptor *)descriptor error:(NSError **)error;
- (nullable id<MTL4ArgumentTable>)newArgumentTableWithDescriptor:(MTL4ArgumentTableDescriptor *)descriptor error:(NSError **)error;
- (nullable id<MTL4CounterHeap>)newCounterHeapWithDescriptor:(MTL4CounterHeapDescriptor *)descriptor error:(NSError **)error;
- (NSUInteger)sizeOfCounterHeapEntry:(MTL4CounterHeapType)type;
- (uint64_t)queryTimestampFrequency;
- (nullable id<MTL4Compiler>)newCompilerWithDescriptor:(MTL4CompilerDescriptor *)descriptor error:(NSError **)error;
- (NSUInteger)minimumLinearTextureAlignmentForPixelFormat:(MTLPixelFormat)format;
- (NSUInteger)minimumTextureBufferAlignmentForPixelFormat:(MTLPixelFormat)format;
@end

METAL_DECLARATIONS_END

#endif // _METAL_MTLDEVICE_H_
