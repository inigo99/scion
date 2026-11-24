// SPDX-FileCopyrightText: 2026 Darling Developers
// SPDX-License-Identifier: MPL-2.0

#import <Foundation/Foundation.h>

#import <Metal/MTLDefines.h>

METAL_DECLARATIONS_BEGIN

@protocol MTLDevice;

typedef NS_OPTIONS(NSUInteger, MTLResourceUsage) { MTLResourceUsageRead = 1, MTLResourceUsageWrite = 2, MTLResourceUsageSample = 4 };
typedef NS_OPTIONS(NSUInteger, MTLBarrierScope) { MTLBarrierScopeBuffers = 1, MTLBarrierScopeTextures = 2, MTLBarrierScopeRenderTargets = 4 };
typedef NS_OPTIONS(NSUInteger, MTLRenderStages) { MTLRenderStageVertex = 1, MTLRenderStageFragment = 2, MTLRenderStageTile = 4,
    MTLRenderStageObject = 8, MTLRenderStageMesh = 16 };

@protocol MTLCommandEncoder <NSObject>

@property(readonly) id<MTLDevice> device;
@property(nullable, copy, atomic) NSString* label;

- (void)endEncoding;

@end

METAL_DECLARATIONS_END
