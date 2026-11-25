/* Objective-C exceptions (@try/@catch/@finally) on scion's libunwind + libc++abi. Prints "EXCEPTIONS OK";
 * with an argument, raises an uncaught exception (Apple's message, then abort). */
#import <Foundation/Foundation.h>
int printf(const char *, ...);
static int fails;
#define CHECK(...) do { if (__VA_ARGS__) printf("ok   %s\n", #__VA_ARGS__); else { printf("FAIL %s (line %d)\n", #__VA_ARGS__, __LINE__); fails++; } } while (0)

@interface MyException : NSException @end
@implementation MyException @end
@interface Thrower : NSObject
- (void)throwAt:(int)n;
- (void)validate:(int)x;
@end
@implementation Thrower
- (void)throwAt:(int)n { if (n == 0) [MyException raise:@"Mine" format:@"depth %d", 0]; [self throwAt:n - 1]; }
- (void)validate:(int)x { NSParameterAssert(x > 0); }
@end
static int finally_count;

int main(int argc, char **argv) {
    if (argc > 1) { @autoreleasepool { [@[@1] objectAtIndex:9]; } return 0; } /* uncaught: Apple's message and abort */
    @autoreleasepool {
        @try { [[Thrower new] throwAt:20]; }
        @catch (MyException *e) { CHECK([e.name isEqualToString:@"Mine"] && [e.reason isEqualToString:@"depth 0"]); }
        @finally { finally_count++; }
        CHECK(finally_count == 1);

        @try { [@[@1, @2] objectAtIndex:5]; }
        @catch (NSException *e) { CHECK([e.name isEqualToString:NSRangeException]); }

        @try { [[NSObject new] performSelector:@selector(doesNotExist)]; }
        @catch (NSException *e) { CHECK([e.name isEqualToString:NSInvalidArgumentException] && [e.reason containsString:@"unrecognized selector"]); }

        @try { [[Thrower new] validate:0]; }
        @catch (NSException *e) { CHECK([e.name isEqualToString:NSInternalInconsistencyException] && [e.reason containsString:@"x > 0"]); }

        @try { @throw @"a string"; }
        @catch (NSException *e) { CHECK(0); }
        @catch (id o) { CHECK([o isEqual:@"a string"]); }

        /* rethrow and nesting */
        int layers = 0;
        @try {
            @try { [NSException raise:@"A" format:@"inner"]; }
            @catch (NSException *e) { layers++; @throw; }
            @finally { layers += 10; }
        } @catch (NSException *e) { layers += 100; CHECK([e.reason isEqualToString:@"inner"]); }
        CHECK(layers == 111);

        /* @synchronized releases its lock when an exception leaves it */
        NSObject *lock = [NSObject new];
        @try { @synchronized (lock) { [NSException raise:@"S" format:@"inside"]; } } @catch (NSException *e) {}
        __block BOOL acquired = NO;
        [NSThread detachNewThreadWithBlock:^{ @synchronized (lock) { acquired = YES; } }];
        for (int i = 0; i < 200 && !acquired; i++) [NSThread sleepForTimeInterval:0.01];
        CHECK(acquired);

        /* exceptions on another thread and inside blocks */
        __block BOOL caught = NO;
        dispatch_semaphore_t s = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            @try { [NSException raise:@"Thread" format:@"x"]; } @catch (NSException *e) { caught = [e.name isEqualToString:@"Thread"]; }
            dispatch_semaphore_signal(s);
        });
        dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
        CHECK(caught);

        /* many exceptions in a row (no leaks, no corruption) */
        int n = 0;
        for (int i = 0; i < 2000; i++) { @try { [NSException raise:@"Loop" format:@"%d", i]; } @catch (NSException *e) { n += [e.reason intValue] == i; } }
        CHECK(n == 2000);
    }
    printf(fails ? "EXCEPTIONS: %d FAILURES\n" : "EXCEPTIONS OK\n", fails);
    return fails;
}
