/* Foundation (ARC, literals, subscripting, blocks, NSLog, files, threads). Prints "FOUNDATION OK". */
#import <Foundation/Foundation.h>
int printf(const char *, ...);
static int fails;
#define CHECK(...) do { if (__VA_ARGS__) printf("ok   %s\n", #__VA_ARGS__); else { printf("FAIL %s (line %d)\n", #__VA_ARGS__, __LINE__); fails++; } } while (0)

@interface Vec : NSObject
@property NSInteger x, y;
@property (copy) NSString *name;
@end
@implementation Vec
- (NSString *)description { return [NSString stringWithFormat:@"<Vec %@ (%ld,%ld)>", self.name, (long)self.x, (long)self.y]; }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        /* NSString */
        NSString *s = @"Hello world";
        CHECK(s.length == 11);
        CHECK([[s uppercaseString] isEqualToString:@"HELLO WORLD"]);
        CHECK([s rangeOfString:@"world"].location == 6);
        NSString *u = @"ñandú 😀";
        CHECK(u.length == 8 && strlen(u.UTF8String) == 12);
        NSString *f = [NSString stringWithFormat:@"%d-%@-%.2f-%s", 7, @"x", 3.14159, "c"];
        CHECK([f isEqualToString:@"7-x-3.14-c"]);
        NSArray *parts = [@"a,b,,c" componentsSeparatedByString:@","];
        CHECK(parts.count == 4 && [parts[3] isEqualToString:@"c"]);
        CHECK([[@"/usr/local/lib/libfoo.dylib" lastPathComponent] isEqualToString:@"libfoo.dylib"]);
        CHECK([[@"/usr/local/lib/libfoo.dylib" pathExtension] isEqualToString:@"dylib"]);
        CHECK([@"file10" compare:@"file9" options:NSNumericSearch] == NSOrderedDescending);
        NSMutableString *m = [NSMutableString stringWithString:@"abc"];
        [m appendFormat:@"%d", 123]; [m insertString:@"X" atIndex:0];
        CHECK([m isEqualToString:@"Xabc123"]);
        CHECK([@"  test \n" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 4);
        CHECK([@"42" intValue] == 42 && [@"2.5" doubleValue] == 2.5);

        /* collections with literals */
        NSArray *a = @[@3, @1, @2];
        NSArray *ord = [a sortedArrayUsingSelector:@selector(compare:)];
        CHECK([ord isEqualToArray:@[@1, @2, @3]]);
        NSMutableArray *ma = [a mutableCopy];
        [ma addObject:@"four"]; ma[0] = @30; [ma removeObjectAtIndex:1];
        CHECK(ma.count == 3 && [ma[0] intValue] == 30);
        NSInteger sum = 0; for (NSNumber *n in ord) sum += n.integerValue;
        CHECK(sum == 6);
        NSDictionary *d = @{@"one": @1, @"two": @2, @"three": @[@"x", @"y"]};
        CHECK(d.count == 3 && [d[@"two"] intValue] == 2 && [d[@"three"][1] isEqualToString:@"y"]);
        NSMutableDictionary *md = [NSMutableDictionary dictionary];
        for (int i = 0; i < 1000; i++) md[[NSString stringWithFormat:@"k%d", i]] = @(i * i);
        [md removeObjectForKey:@"k500"];
        CHECK(md.count == 999 && [md[@"k999"] intValue] == 998001 && md[@"k500"] == nil);
        __block int seen = 0;
        [md enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { seen++; }];
        CHECK(seen == 999);
        NSSet *set = [NSSet setWithArray:@[@"a", @"b", @"a"]];
        CHECK(set.count == 2 && [set containsObject:@"b"]);
        CHECK([@(YES) boolValue] && [@(2.5) doubleValue] == 2.5 && [@(-7LL) longLongValue] == -7);
        CHECK([@1 isEqual:@1.0] && [NSNull null] == [NSNull null]);

        /* %@ and description */
        Vec *p = [Vec new]; p.x = 3; p.y = 4; p.name = @"P";
        CHECK([[NSString stringWithFormat:@"%@", p] isEqualToString:@"<Vec P (3,4)>"]);
        CHECK([[@[@1, @"two"] description] containsString:@"two"]);
        CHECK([[p valueForKey:@"name"] isEqualToString:@"P"]);
        NSLog(@"NSLog from scion: %@ %@", p, @{@"key": @[@1, @2]});

        /* NSData and files */
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"scion_fnd"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:dir error:nil];
        NSError *err = nil;
        CHECK([fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"a/b"] withIntermediateDirectories:YES attributes:nil error:&err]);
        NSString *file = [dir stringByAppendingPathComponent:@"a/b/hello.txt"];
        CHECK([@"contents: ñ" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&err]);
        NSString *got = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:&err];
        CHECK([got isEqualToString:@"contents: ñ"]);
        CHECK([[fm attributesOfItemAtPath:file error:nil][NSFileSize] intValue] == 12);
        CHECK([[fm contentsOfDirectoryAtPath:[dir stringByAppendingPathComponent:@"a/b"] error:nil] isEqualToArray:@[@"hello.txt"]]);
        CHECK(![NSData dataWithContentsOfFile:@"/does/not/exist"]);
        CHECK([NSString stringWithContentsOfFile:@"/does/not/exist" encoding:NSUTF8StringEncoding error:&err] == nil && err.code == 2);
        CHECK([fm removeItemAtPath:dir error:nil] && ![fm fileExistsAtPath:dir]);
        NSMutableData *md2 = [NSMutableData data];
        [md2 appendBytes:"abc" length:3]; [md2 appendData:[@"de" dataUsingEncoding:NSUTF8StringEncoding]];
        CHECK(md2.length == 5 && memcmp(md2.bytes, "abcde", 5) == 0);

        /* threads, conditions, processes */
        NSCondition *c = [NSCondition new];
        __block int done = 0;
        [NSThread detachNewThreadWithBlock:^{
            @autoreleasepool { [c lock]; done = [NSThread isMainThread] ? -1 : 1; [c signal]; [c unlock]; }
        }];
        [c lock]; while (!done) [c wait]; [c unlock];
        CHECK(done == 1 && [NSThread isMainThread]);
        NSRecursiveLock *rl = [NSRecursiveLock new];
        [rl lock]; [rl lock]; [rl unlock]; [rl unlock];
        CHECK([rl tryLock]);
        CHECK([NSProcessInfo processInfo].arguments.count == (NSUInteger)argc && [NSProcessInfo processInfo].processorCount > 0);
        NSDate *t0 = [NSDate date]; [NSThread sleepForTimeInterval:0.05];
        CHECK([[NSDate date] timeIntervalSinceDate:t0] >= 0.04);
        [[NSUserDefaults standardUserDefaults] setInteger:9 forKey:@"n"];
        CHECK([[NSUserDefaults standardUserDefaults] integerForKey:@"n"] == 9);

        /* ARC + weak */
        __weak NSObject *weakref;
        @autoreleasepool { NSObject *o = [NSObject new]; weakref = o; CHECK(weakref != nil); }
        CHECK(weakref == nil);

        /* CF toll-free */
        CFTypeRef cf = CFBridgingRetain([NSString stringWithFormat:@"cf%d", 1]);
        NSString *back = CFBridgingRelease(cf);
        CHECK([back isEqualToString:@"cf1"] && CFAbsoluteTimeGetCurrent() > 7e8);
    }
    printf(fails ? "FOUNDATION: %d FAILURES\n" : "FOUNDATION OK\n", fails);
    return fails;
}
