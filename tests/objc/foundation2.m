/* More Foundation (JSON, NSRunLoop/NSTimer, notifications, NSOperationQueue, NSHashTable, NSNumberFormatter). Prints "FOUNDATION2 OK". */
#import <Foundation/Foundation.h>
int printf(const char *, ...);
static int fails;
#define CHECK(...) do { if (__VA_ARGS__) printf("ok   %s\n", #__VA_ARGS__); else { printf("FAIL %s (line %d)\n", #__VA_ARGS__, __LINE__); fails++; } } while (0)

@interface Listener : NSObject @property int hits; @property (copy) NSString *last; @end
@implementation Listener
- (void)notice:(NSNotification *)n { self.hits++; self.last = n.userInfo[@"k"]; }
- (void)tic:(NSTimer *)t { self.hits++; }
@end
@interface MyOp : NSOperation @property int *counter; @end
@implementation MyOp - (void)main { (*self.counter)++; } @end

static NSString *str(NSData *d) { return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; }

int main(void) {
    @autoreleasepool {
        /* JSON: reading */
        NSData *d = [@"{\"name\":\"Ana\",\"age\":30,\"pi\":3.25,\"ok\":true,\"none\":null,\"list\":[1,\"two\",[3]],\"esc\":\"a\\\"b\\\\c\\u00f1\\ud83d\\ude00\\/\"}" dataUsingEncoding:NSUTF8StringEncoding];
        NSError *e = nil;
        NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:&e];
        CHECK(j && [j[@"name"] isEqualToString:@"Ana"] && [j[@"age"] intValue] == 30 && [j[@"pi"] doubleValue] == 3.25);
        CHECK([j[@"ok"] boolValue] && j[@"none"] == [NSNull null] && [j[@"list"][2][0] intValue] == 3);
        CHECK([j[@"esc"] isEqualToString:@"a\"b\\cñ😀/"]);
        CHECK([NSJSONSerialization JSONObjectWithData:[@"{\"a\":}" dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&e] == nil && e.code == 3840);
        CHECK([NSJSONSerialization JSONObjectWithData:[@"42" dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] == nil);
        CHECK([[NSJSONSerialization JSONObjectWithData:[@"42" dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:nil] intValue] == 42);
        NSMutableDictionary *mut = [NSJSONSerialization JSONObjectWithData:[@"{\"a\":[1]}" dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil];
        [mut[@"a"] addObject:@2]; mut[@"b"] = @3;
        CHECK([mut[@"a"] count] == 2 && [mut[@"b"] intValue] == 3);
        /* JSON: writing */
        NSDictionary *o = @{@"b": @[@1, @2.5, @YES], @"a": @"x/y", @"c": @{}};
        CHECK([str([NSJSONSerialization dataWithJSONObject:o options:NSJSONWritingSortedKeys error:nil]) isEqualToString:@"{\"a\":\"x\\/y\",\"b\":[1,2.5,true],\"c\":{}}"]);
        CHECK([str([NSJSONSerialization dataWithJSONObject:@{@"k": @[@1]} options:NSJSONWritingPrettyPrinted error:nil]) isEqualToString:@"{\n  \"k\" : [\n    1\n  ]\n}"]);
        CHECK([str([NSJSONSerialization dataWithJSONObject:@[@"a/b"] options:NSJSONWritingWithoutEscapingSlashes error:nil]) isEqualToString:@"[\"a/b\"]"]);
        CHECK([NSJSONSerialization isValidJSONObject:o] && ![NSJSONSerialization isValidJSONObject:@[[NSObject new]]] && ![NSJSONSerialization isValidJSONObject:@"x"]);
        NSData *roundtrip = [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];
        CHECK([[NSJSONSerialization JSONObjectWithData:roundtrip options:0 error:nil] isEqual:j]);

        /* NSTimer + NSRunLoop */
        __block int n = 0;
        NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer *x) { if (++n == 5) [x invalidate]; }];
        NSDate *t0 = [NSDate date];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        CHECK(n == 5 && !t.isValid && [[NSDate date] timeIntervalSinceDate:t0] >= 0.25);
        Listener *lst = [Listener new];
        [NSTimer scheduledTimerWithTimeInterval:0.02 target:lst selector:@selector(tic:) userInfo:nil repeats:NO];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        CHECK(lst.hits == 1);
        __block BOOL from_other = NO;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{ dispatch_async(dispatch_get_main_queue(), ^{ from_other = YES; }); });
        for (int i = 0; i < 100 && !from_other; i++) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        CHECK(from_other);
        __block BOOL performed = NO;
        [lst performSelector:@selector(tic:) withObject:nil afterDelay:0.01];
        [[NSRunLoop currentRunLoop] performBlock:^{ performed = YES; }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        CHECK(lst.hits == 2 && performed);
        /* CFRunLoopRun / CFRunLoopStop */
        [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *x) { CFRunLoopStop(CFRunLoopGetMain()); }];
        CFRunLoopRun();
        CHECK(YES);

        /* notifications */
        Listener *a = [Listener new];
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:a selector:@selector(notice:) name:@"Event" object:nil];
        __block int blocks = 0;
        id tok = [nc addObserverForName:@"Event" object:nil queue:nil usingBlock:^(NSNotification *note) { blocks++; }];
        [nc postNotificationName:@"Event" object:nil userInfo:@{@"k": @"v1"}];
        [nc postNotificationName:@"Other" object:nil];
        [nc postNotificationName:@"Event" object:nc userInfo:@{@"k": @"v2"}];
        if (a.hits != 2 || blocks != 2 || ![a.last isEqualToString:@"v2"]) printf("hits=%d last=%s blocks=%d\n", a.hits, a.last.UTF8String, blocks);
        CHECK(a.hits == 2 && [a.last isEqualToString:@"v2"] && blocks == 2);
        [nc removeObserver:tok];
        [nc removeObserver:a];
        [nc postNotificationName:@"Event" object:nil];
        CHECK(a.hits == 2 && blocks == 2);
        @autoreleasepool { Listener *temp = [Listener new]; [nc addObserver:temp selector:@selector(notice:) name:@"Event" object:nil]; }
        [nc postNotificationName:@"Event" object:nil];   /* the observer is gone: must not crash (weak reference) */
        CHECK(YES);

        /* NSOperationQueue */
        NSOperationQueue *q = [NSOperationQueue new];
        __block int sum = 0; NSLock *l = [NSLock new];
        for (int i = 1; i <= 100; i++) [q addOperationWithBlock:^{ [l lock]; sum += i; [l unlock]; }];
        [q waitUntilAllOperationsAreFinished];
        CHECK(sum == 5050 && q.operationCount == 0);
        NSOperationQueue *serial = [NSOperationQueue new]; serial.maxConcurrentOperationCount = 1;
        NSMutableString *order = [NSMutableString string];
        for (int i = 0; i < 5; i++) [serial addOperationWithBlock:^{ [order appendFormat:@"%d", i]; }];
        [serial waitUntilAllOperationsAreFinished];
        CHECK([order isEqualToString:@"01234"]);
        int cnt = 0; MyOp *op = [MyOp new]; op.counter = &cnt;
        __block BOOL completed = NO; op.completionBlock = ^{ completed = YES; };
        NSBlockOperation *after = [NSBlockOperation blockOperationWithBlock:^{}];
        [after addDependency:op];
        [q addOperations:@[after, op] waitUntilFinished:YES];
        for (int i = 0; i < 100 && !completed; i++) [NSThread sleepForTimeInterval:0.01];   /* completionBlock runs after the operation finishes, as on macOS */
        CHECK(cnt == 1 && op.isFinished && after.isFinished && completed);
        __block BOOL on_main = NO;
        [NSOperationQueue.mainQueue addOperationWithBlock:^{ on_main = [NSThread isMainThread]; }];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        CHECK(on_main);

        /* weak NSHashTable */
        NSHashTable *h = [NSHashTable weakObjectsHashTable];
        NSObject *alive = [NSObject new];
        [h addObject:alive]; [h addObject:alive];
        @autoreleasepool { NSObject *dies = [NSObject new]; [h addObject:dies]; CHECK(h.count == 2); }
        CHECK(h.count == 1 && [h containsObject:alive] && h.allObjects.firstObject == alive);
        int iter = 0; for (id x in h) { (void)x; iter++; }
        CHECK(iter == 1);
        NSHashTable *strong = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];
        @autoreleasepool { [strong addObject:[NSObject new]]; }
        CHECK(strong.count == 1);

        /* NSNumberFormatter */
        NSNumberFormatter *nf = [NSNumberFormatter new]; nf.numberStyle = NSNumberFormatterDecimalStyle;
        CHECK([[nf stringFromNumber:@1234567] isEqualToString:@"1,234,567"] && [[nf stringFromNumber:@-1234.5] isEqualToString:@"-1,234.5"]);
        CHECK([[nf stringFromNumber:@0.1234] isEqualToString:@"0.123"] && [[nf numberFromString:@"1,234"] intValue] == 1234);
        CHECK([[NSNumberFormatter localizedStringFromNumber:@0.25 numberStyle:NSNumberFormatterPercentStyle] isEqualToString:@"25%"]);
    }
    printf(fails ? "FOUNDATION2: %d FAILURES\n" : "FOUNDATION2 OK\n", fails);
    return fails;
}
