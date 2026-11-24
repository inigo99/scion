/* scion SDK: root class interface */
#pragma once
#include <objc/objc.h>
#ifdef __OBJC__
#pragma clang assume_nonnull begin
typedef struct _NSZone NSZone;
@class Protocol, NSString;
@protocol NSObject
- (BOOL)isEqual:(nullable id)object; - (Class)class; - (instancetype)self;
@property (readonly) NSUInteger hash;
@property (readonly, nullable) Class superclass;
@property (readonly, copy) NSString *description;
- (BOOL)isKindOfClass:(Class)c; - (BOOL)isMemberOfClass:(Class)c; - (BOOL)respondsToSelector:(SEL)s; - (BOOL)conformsToProtocol:(Protocol *)p;
- (nullable id)performSelector:(SEL)s; - (nullable id)performSelector:(SEL)s withObject:(nullable id)o; - (BOOL)isProxy;
- (instancetype)retain; - (oneway void)release; - (instancetype)autorelease; - (NSUInteger)retainCount;
@optional
@property (readonly, copy) NSString *debugDescription;
@end
__attribute__((objc_root_class))
@interface NSObject <NSObject> { Class isa; }
+ (void)load; + (void)initialize; + (instancetype)new; + (instancetype)alloc; + (instancetype)allocWithZone:(nullable NSZone *)z;
- (instancetype)init; - (void)dealloc; - (id)copy; - (id)mutableCopy; + (Class)class; + (nullable Class)superclass;
+ (BOOL)instancesRespondToSelector:(SEL)s; + (BOOL)isSubclassOfClass:(Class)c; + (BOOL)resolveInstanceMethod:(SEL)s; + (BOOL)resolveClassMethod:(SEL)s;
- (nullable id)forwardingTargetForSelector:(SEL)s; - (void)doesNotRecognizeSelector:(SEL)s; - (nullable IMP)methodForSelector:(SEL)s;
@end
#pragma clang assume_nonnull end
#endif
