/* NSObject.m — root class, Protocol and block classes for scion's libobjc (compiled without ARC). */
#include <stdint.h>
#include <stddef.h>
typedef signed char BOOL;
typedef unsigned long NSUInteger;
typedef struct _NSZone NSZone;
#define YES ((BOOL)1)
#define NO ((BOOL)0)

id _objc_rootAllocWithZone(Class, void *);
id _scion_objc_rootRetain(id); BOOL _scion_objc_rootRelease(id); BOOL _scion_objc_rootTryRetain(id);
uintptr_t _scion_objc_rootRetainCount(id); id _scion_objc_rootAutorelease(id);
id object_dispose(id); Class object_getClass(id); Class class_getSuperclass(Class); BOOL class_respondsToSelector(Class, SEL);
BOOL class_conformsToProtocol(Class, id); BOOL class_isMetaClass(Class); void *class_getMethodImplementation(Class, SEL);
const char *class_getName(Class); const char *sel_getName(SEL); SEL sel_registerName(const char *);
id objc_msgSend(id, SEL, ...);
void *_Block_copy(const void *); void _Block_release(const void *);
void _scion_objc_setup_blocks(Class, Class, Class); Class objc_getClass(const char *);
long write(int, const void *, size_t); size_t strlen(const char *); void abort(void);

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
@end

@implementation NSObject
+ (void)load { }
+ (void)initialize { }
+ (id)alloc { return [self allocWithZone:NULL]; }   /* class clusters override +allocWithZone: */
+ (id)allocWithZone:(NSZone *)z { return _objc_rootAllocWithZone(self, 0); }
+ (id)new { return [[self alloc] init]; }
+ (Class)class { return self; }
+ (Class)superclass { return class_getSuperclass(self); }
+ (id)self { return self; }
+ (BOOL)isSubclassOfClass:(Class)c { for (Class k = self; k; k = class_getSuperclass(k)) if (k == c) return YES; return NO; }
+ (BOOL)instancesRespondToSelector:(SEL)s { return class_respondsToSelector(self, s); }
+ (BOOL)respondsToSelector:(SEL)s { return class_respondsToSelector(object_getClass(self), s); }
+ (BOOL)conformsToProtocol:(id)p { for (Class k = self; k; k = class_getSuperclass(k)) if (class_conformsToProtocol(k, p)) return YES; return NO; }
+ (BOOL)isKindOfClass:(Class)c { for (Class k = object_getClass(self); k; k = class_getSuperclass(k)) if (k == c) return YES; return NO; }
+ (BOOL)isMemberOfClass:(Class)c { return object_getClass(self) == c; }
+ (void *)instanceMethodForSelector:(SEL)s { return class_getMethodImplementation(self, s); }
+ (void *)methodForSelector:(SEL)s { return class_getMethodImplementation(object_getClass(self), s); }
+ (BOOL)resolveClassMethod:(SEL)s { return NO; }
+ (BOOL)resolveInstanceMethod:(SEL)s { return NO; }
+ (id)retain { return self; }
+ (oneway void)release { }
+ (id)autorelease { return self; }
+ (NSUInteger)retainCount { return (NSUInteger)-1; }
+ (NSUInteger)hash { return (NSUInteger)self; }
+ (BOOL)isEqual:(id)o { return self == o; }
+ (id)copy { return self; }
+ (id)copyWithZone:(NSZone *)z { return self; }
+ (id)mutableCopy { return self; }
+ (BOOL)isProxy { return NO; }
+ (id)performSelector:(SEL)s { return objc_msgSend(self, s); }
+ (id)performSelector:(SEL)s withObject:(id)a { return ((id (*)(id, SEL, id))objc_msgSend)(self, s, a); }
- (id)init { return self; }
- (void)dealloc { object_dispose(self); }
- (void)finalize { }
- (id)retain { return _scion_objc_rootRetain(self); }
- (oneway void)release { if (_scion_objc_rootRelease(self)) [self dealloc]; }
- (id)autorelease { return _scion_objc_rootAutorelease(self); }
- (NSUInteger)retainCount { return _scion_objc_rootRetainCount(self); }
- (BOOL)_tryRetain { return _scion_objc_rootTryRetain(self); }
- (BOOL)allowsWeakReference { return YES; }
- (BOOL)retainWeakReference { return _scion_objc_rootTryRetain(self); }
- (Class)class { return object_getClass(self); }
- (Class)superclass { return class_getSuperclass(object_getClass(self)); }
- (id)self { return self; }
- (NSZone *)zone { return 0; }
- (BOOL)isKindOfClass:(Class)c { for (Class k = object_getClass(self); k; k = class_getSuperclass(k)) if (k == c) return YES; return NO; }
- (BOOL)isMemberOfClass:(Class)c { return object_getClass(self) == c; }
- (BOOL)respondsToSelector:(SEL)s { return class_respondsToSelector(object_getClass(self), s); }
- (BOOL)conformsToProtocol:(id)p { for (Class k = object_getClass(self); k; k = class_getSuperclass(k)) if (class_conformsToProtocol(k, p)) return YES; return NO; }
- (NSUInteger)hash { return (NSUInteger)self; }
- (BOOL)isEqual:(id)o { return self == o; }
- (BOOL)isProxy { return NO; }
- (id)copy { return ((id (*)(id, SEL, void *))objc_msgSend)(self, sel_registerName("copyWithZone:"), (void *)0); }
- (id)mutableCopy { return ((id (*)(id, SEL, void *))objc_msgSend)(self, sel_registerName("mutableCopyWithZone:"), (void *)0); }
- (id)performSelector:(SEL)s { return objc_msgSend(self, s); }
- (id)performSelector:(SEL)s withObject:(id)a { return ((id (*)(id, SEL, id))objc_msgSend)(self, s, a); }
- (id)performSelector:(SEL)s withObject:(id)a withObject:(id)b { return ((id (*)(id, SEL, id, id))objc_msgSend)(self, s, a, b); }
- (void *)methodForSelector:(SEL)s { return class_getMethodImplementation(object_getClass(self), s); }
- (id)forwardingTargetForSelector:(SEL)s { return 0; }
- (void)doesNotRecognizeSelector:(SEL)s {
    const char *a = "*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '-[";
    write(2, a, strlen(a)); write(2, class_getName(object_getClass(self)), strlen(class_getName(object_getClass(self))));
    write(2, " ", 1); write(2, sel_getName(s), strlen(sel_getName(s))); a = "]: unrecognized selector sent to instance'\n"; write(2, a, strlen(a));
    abort();
}
@end

/* Protocol objects (isa of every protocol_t) */
@interface Protocol : NSObject @end
@implementation Protocol
- (id)retain { return self; }
- (oneway void)release { }
- (id)autorelease { return self; }
@end

/* dispatch objects are Objective-C objects (ARC retains queues): never freed here, like dispatch_release */
void _scion_objc_setup_dispatch(Class c);
@interface OS_dispatch_object : NSObject @end
@implementation OS_dispatch_object
- (id)retain { return self; }
- (oneway void)release { }
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return ~(NSUInteger)0; }
+ (void)load { _scion_objc_setup_dispatch(objc_getClass("OS_dispatch_object")); }
@end
/* one class per kind of dispatch object, as on macOS (Swift's Dispatch overlay casts to them) */
void _scion_dispatch_set_class(int kind, Class c);
#define DISPATCH_CLASS(name, kind) \
    @interface OS_dispatch_##name : OS_dispatch_object @end \
    @implementation OS_dispatch_##name + (void)load { _scion_dispatch_set_class(kind, self); } @end
DISPATCH_CLASS(queue, 0) DISPATCH_CLASS(group, 1) DISPATCH_CLASS(semaphore, 2) DISPATCH_CLASS(source, 3)
DISPATCH_CLASS(data, 4) DISPATCH_CLASS(io, 5) DISPATCH_CLASS(queue_attr, 6)

/* os_log objects (OS_LOG_DEFAULT, os_log_create's): immortal, as dispatch objects; Swift's OSLog is this class */
void _scion_os_log_set_class(void *c);
@interface OS_object : NSObject @end
@implementation OS_object
- (id)retain { return self; }
- (oneway void)release { }
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return ~(NSUInteger)0; }
@end
@interface OS_os_log : OS_object @end
@implementation OS_os_log
+ (void)load { _scion_os_log_set_class(self); }
@end

/* Blocks are objects too: the runtime copies these classes into _NSConcrete*Block */
@interface __NSStackBlock : NSObject @end
@interface __NSMallocBlock : NSObject @end
@interface __NSGlobalBlock : NSObject @end
@implementation __NSStackBlock
- (id)copy { return _Block_copy(self); }
- (id)copyWithZone:(NSZone *)z { return _Block_copy(self); }
- (id)retain { return self; }
- (oneway void)release { }
- (id)autorelease { return self; }
+ (void)load { _scion_objc_setup_blocks(objc_getClass("__NSStackBlock"), objc_getClass("__NSMallocBlock"), objc_getClass("__NSGlobalBlock")); }
@end
@implementation __NSMallocBlock
- (id)copy { return _Block_copy(self); }
- (id)copyWithZone:(NSZone *)z { return _Block_copy(self); }
- (id)retain { return _Block_copy(self); }
- (oneway void)release { _Block_release(self); }
- (NSUInteger)retainCount { return 1; }
@end
@implementation __NSGlobalBlock
- (id)copy { return self; }
- (id)copyWithZone:(NSZone *)z { return self; }
- (id)retain { return self; }
- (oneway void)release { }
- (id)autorelease { return self; }
@end
