/* scion SDK — MTLStencilDescriptor */
#ifndef _METAL_MTLSTENCILDESCRIPTOR_H_
#define _METAL_MTLSTENCILDESCRIPTOR_H_
#import <Foundation/Foundation.h>
typedef NS_ENUM(NSUInteger, MTLCompareFunction) {
    MTLCompareFunctionNever = 0, MTLCompareFunctionLess = 1, MTLCompareFunctionEqual = 2, MTLCompareFunctionLessEqual = 3,
    MTLCompareFunctionGreater = 4, MTLCompareFunctionNotEqual = 5, MTLCompareFunctionGreaterEqual = 6, MTLCompareFunctionAlways = 7,
};
typedef NS_ENUM(NSUInteger, MTLStencilOperation) {
    MTLStencilOperationKeep = 0, MTLStencilOperationZero = 1, MTLStencilOperationReplace = 2, MTLStencilOperationIncrementClamp = 3,
    MTLStencilOperationDecrementClamp = 4, MTLStencilOperationInvert = 5, MTLStencilOperationIncrementWrap = 6, MTLStencilOperationDecrementWrap = 7,
};
@interface MTLStencilDescriptor : NSObject <NSCopying>
@property (assign, nonatomic) MTLCompareFunction stencilCompareFunction;
@property (assign, nonatomic) MTLStencilOperation stencilFailureOperation, depthFailureOperation, depthStencilPassOperation;
@property (assign, nonatomic) uint32_t readMask, writeMask;
@end
#endif
