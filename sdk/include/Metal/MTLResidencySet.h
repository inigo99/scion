// scion: residency sets (macOS 15). Every allocation is always resident here: the sets only remember what they hold.
#import <Foundation/Foundation.h>
#import <Metal/MTLDefines.h>
#import <Metal/MTLResource.h>

METAL_DECLARATIONS_BEGIN
@protocol MTLDevice;
@interface MTLResidencySetDescriptor : NSObject <NSCopying>
@property(nullable, copy, nonatomic) NSString *label;
@property(nonatomic) NSUInteger initialCapacity;
@end
@protocol MTLResidencySet <NSObject>
@property(readonly) id<MTLDevice> device;
@property(nullable, readonly) NSString *label;
@property(readonly) uint64_t allocatedSize;
@property(readonly) NSUInteger allocationCount;
@property(readonly) NSArray<id<MTLAllocation>> *allAllocations;
- (void)requestResidency; - (void)endResidency;
- (void)addAllocation:(id<MTLAllocation>)a; - (void)addAllocations:(const id<MTLAllocation> _Nonnull [_Nonnull])a count:(NSUInteger)n;
- (void)removeAllocation:(id<MTLAllocation>)a; - (void)removeAllocations:(const id<MTLAllocation> _Nonnull [_Nonnull])a count:(NSUInteger)n;
- (void)removeAllAllocations;
- (BOOL)containsAllocation:(id<MTLAllocation>)a;
- (void)commit;
@end
METAL_DECLARATIONS_END
