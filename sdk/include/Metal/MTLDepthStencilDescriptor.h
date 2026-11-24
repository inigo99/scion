/* scion SDK — MTLDepthStencilDescriptor */
#ifndef _METAL_MTLDEPTHSTENCILDESCRIPTOR_H_
#define _METAL_MTLDEPTHSTENCILDESCRIPTOR_H_
#import <Foundation/Foundation.h>
#import <Metal/MTLStencilDescriptor.h>
@protocol MTLDevice;
@interface MTLDepthStencilDescriptor : NSObject <NSCopying>
@property (assign, nonatomic) MTLCompareFunction depthCompareFunction;
@property (assign, nonatomic, getter=isDepthWriteEnabled) BOOL depthWriteEnabled;
@property (copy, nonatomic) MTLStencilDescriptor *frontFaceStencil, *backFaceStencil;
@property (copy, nonatomic) NSString *label;
@end
@protocol MTLDepthStencilState <NSObject>
@property (readonly) id<MTLDevice> device;
@property (readonly) NSString *label;
@end
#endif
