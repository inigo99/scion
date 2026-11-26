/* xpc.m — NSXPCConnection, NSXPCInterface, NSXPCListener. scion has no XPC
 * services: a connection resumes and is invalidated at once, and messages to its remote proxy call the error handler. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
void dispatch_async(void *q, void (^b)(void));
extern struct dqueue _dispatch_main_q;

NSString *const NSFileHandleOperationException = @"NSFileHandleOperationException";
NSString *NSHomeDirectoryForUser(NSString *user) { return NSHomeDirectory(); }

static NSError *xpc_error(void) {
    return [NSError errorWithDomain:NSCocoaErrorDomain code:4099 /* NSXPCConnectionInvalid */
                           userInfo:@{NSLocalizedDescriptionKey: @"scion no tiene servicios XPC"}];
}

@interface NSXPCInterface : NSObject { Protocol *_protocol; }
@end
@implementation NSXPCInterface
+ (NSXPCInterface *)interfaceWithProtocol:(Protocol *)p { NSXPCInterface *i = [[[self alloc] init] autorelease]; i->_protocol = p; return i; }
- (Protocol *)protocol { return _protocol; } - (void)setProtocol:(Protocol *)p { _protocol = p; }
- (void)setClasses:(NSSet *)c forSelector:(SEL)s argumentIndex:(NSUInteger)i ofReply:(BOOL)r { }
- (NSSet *)classesForSelector:(SEL)s argumentIndex:(NSUInteger)i ofReply:(BOOL)r { return [NSSet set]; }
- (void)setInterface:(NSXPCInterface *)i forSelector:(SEL)s argumentIndex:(NSUInteger)a ofReply:(BOOL)r { }
@end

/* the remote object: every message fails through the error handler */
@interface _MWXPCProxy : NSProxy { @public Protocol *_protocol; void (^_handler)(NSError *); }
@end
@implementation _MWXPCProxy
- (void)dealloc { [_handler release]; [super dealloc]; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s {
    struct objc_method_description d = _protocol ? protocol_getMethodDescription(_protocol, s, YES, YES) : (struct objc_method_description){0, 0};
    if (!d.name && _protocol) d = protocol_getMethodDescription(_protocol, s, NO, YES);
    return [NSMethodSignature signatureWithObjCTypes:d.types ? d.types : "v@:@"];
}
- (void)forwardInvocation:(NSInvocation *)inv {
    void (^h)(NSError *) = [[_handler retain] autorelease];
    if (h) dispatch_async(&_dispatch_main_q, ^{ h(xpc_error()); });
}
- (BOOL)respondsToSelector:(SEL)s { return YES; }
@end

@interface NSXPCListenerEndpoint : NSObject @end
@implementation NSXPCListenerEndpoint @end

@interface NSXPCConnection : NSObject {
    NSString *_name; NSXPCInterface *_remote, *_exported; id _exportedObject; void (^_invalidation)(void), (^_interruption)(void);
}
@end
@implementation NSXPCConnection
- (instancetype)initWithServiceName:(NSString *)n { if ((self = [super init])) _name = [n copy]; return self; }
- (instancetype)initWithMachServiceName:(NSString *)n options:(NSUInteger)o { return [self initWithServiceName:n]; }
- (instancetype)initWithListenerEndpoint:(NSXPCListenerEndpoint *)e { return [self initWithServiceName:nil]; }
- (void)dealloc { [_name release]; [_remote release]; [_exported release]; [_exportedObject release]; [_invalidation release]; [_interruption release]; [super dealloc]; }
- (NSString *)serviceName { return _name; }
- (NSXPCInterface *)remoteObjectInterface { return _remote; } - (void)setRemoteObjectInterface:(NSXPCInterface *)i { [i retain]; [_remote release]; _remote = i; }
- (NSXPCInterface *)exportedInterface { return _exported; } - (void)setExportedInterface:(NSXPCInterface *)i { [i retain]; [_exported release]; _exported = i; }
- (id)exportedObject { return _exportedObject; } - (void)setExportedObject:(id)o { [o retain]; [_exportedObject release]; _exportedObject = o; }
- (void (^)(void))invalidationHandler { return _invalidation; } - (void)setInvalidationHandler:(void (^)(void))h { [_invalidation release]; _invalidation = [h copy]; }
- (void (^)(void))interruptionHandler { return _interruption; } - (void)setInterruptionHandler:(void (^)(void))h { [_interruption release]; _interruption = [h copy]; }
- (int)processIdentifier { return 0; }
- (void)resume { [self invalidate]; }
- (void)activate { [self resume]; }
- (void)suspend { }
- (void)invalidate {
    void (^h)(void) = [[_invalidation retain] autorelease];
    self.invalidationHandler = nil;
    if (h) dispatch_async(&_dispatch_main_q, h);
}
- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *))h {
    _MWXPCProxy *p = [_MWXPCProxy alloc]; p->_protocol = _remote ? [_remote protocol] : nil; p->_handler = [h copy];
    return [p autorelease];
}
- (id)synchronousRemoteObjectProxyWithErrorHandler:(void (^)(NSError *))h { return [self remoteObjectProxyWithErrorHandler:h]; }
- (id)remoteObjectProxy { return [self remoteObjectProxyWithErrorHandler:nil]; }
@end

@interface NSXPCListener : NSObject { id _delegate; } @end
@implementation NSXPCListener
+ (NSXPCListener *)serviceListener { return [[[self alloc] init] autorelease]; }
+ (NSXPCListener *)anonymousListener { return [[[self alloc] init] autorelease]; }
- (instancetype)initWithMachServiceName:(NSString *)n { return [self init]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSXPCListenerEndpoint *)endpoint { return [[[NSXPCListenerEndpoint alloc] init] autorelease]; }
- (void)resume { } - (void)suspend { } - (void)invalidate { } - (void)activate { }
@end

/* ServiceManagement's SMAppService (macOS 13): login items cannot be registered (status: not registered) */
@interface SMAppService : NSObject @end
@implementation SMAppService
+ (SMAppService *)mainAppService { return [[[self alloc] init] autorelease]; }
+ (SMAppService *)loginItemServiceWithIdentifier:(NSString *)i { return [self mainAppService]; }
+ (SMAppService *)agentServiceWithPlistName:(NSString *)n { return [self mainAppService]; }
+ (SMAppService *)daemonServiceWithPlistName:(NSString *)n { return [self mainAppService]; }
+ (NSInteger)statusForLegacyURL:(NSURL *)u { return 0; }
+ (void)openSystemSettingsLoginItems { }
- (NSInteger)status { return 0; /* SMAppServiceStatusNotRegistered */ }
- (BOOL)registerAndReturnError:(NSError **)e {
    if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:3328 userInfo:@{NSLocalizedDescriptionKey: @"scion cannot open apps at login"}];
    return NO;
}
- (BOOL)unregisterAndReturnError:(NSError **)e { return YES; }
@end
