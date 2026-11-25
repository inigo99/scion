/* NSInvocation (calls and forwarding through -forwardInvocation:), NSUndoManager, NSSortDescriptor, NSByteCountFormatter.
 * Prints "INVOCATIONS OK". */
#import <Foundation/Foundation.h>
int printf(const char *, ...);
static int fails;
#define CHECK(...) do { if (__VA_ARGS__) printf("ok   %s\n", #__VA_ARGS__); else { printf("FAIL %s (line %d)\n", #__VA_ARGS__, __LINE__); fails++; } } while (0)
@interface Calc : NSObject @property double last; @property (nonatomic, copy) NSString *s; @end
@implementation Calc
- (long)sum:(long)a b:(long)b c:(long)c d:(long)d e:(long)e f:(long)f g:(long)g h:(long)h { return a+b+c+d+e+f+g+h; }
- (double)mix:(int)a x:(double)x y:(float)y { return a + x + y; }
- (NSRect)rect:(NSPoint)p size:(NSSize)s { return NSMakeRect(p.x, p.y, s.width, s.height); }
- (NSRange)range:(NSRange)r { return NSMakeRange(r.location + 1, r.length * 2); }
- (NSString *)join:(NSString *)a with:(NSString *)b { return [a stringByAppendingString:b]; }
- (void)setS:(NSString *)s { _s = [s copy]; }
@end
@interface Fwd : NSObject { Calc *_c; } @property int forwarded; @end
@implementation Fwd
- (instancetype)init { _c = [Calc new]; return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [_c methodSignatureForSelector:s]; }
- (void)forwardInvocation:(NSInvocation *)i { self.forwarded++; [i invokeWithTarget:_c]; }
@end
int main(void) {
  @autoreleasepool {
    Calc *c = [Calc new];
    NSInvocation *i = [NSInvocation invocationWithMethodSignature:[c methodSignatureForSelector:@selector(sum:b:c:d:e:f:g:h:)]];
    [i setTarget:c]; [i setSelector:@selector(sum:b:c:d:e:f:g:h:)];
    for (long k = 2; k < 10; k++) { long v = k; [i setArgument:&v atIndex:k]; }
    [i invoke]; long r = 0; [i getReturnValue:&r];
    CHECK(r == 2+3+4+5+6+7+8+9);
    i = [NSInvocation invocationWithMethodSignature:[c methodSignatureForSelector:@selector(mix:x:y:)]];
    int a = 1; double x = 2.5; float y = 0.25f;
    [i setSelector:@selector(mix:x:y:)]; [i setArgument:&a atIndex:2]; [i setArgument:&x atIndex:3]; [i setArgument:&y atIndex:4];
    [i invokeWithTarget:c]; double d = 0; [i getReturnValue:&d];
    CHECK(d == 3.75);
    i = [NSInvocation invocationWithMethodSignature:[c methodSignatureForSelector:@selector(rect:size:)]];
    NSPoint p = {1, 2}; NSSize s = {3, 4};
    [i setSelector:@selector(rect:size:)]; [i setArgument:&p atIndex:2]; [i setArgument:&s atIndex:3];
    [i invokeWithTarget:c]; NSRect rr; [i getReturnValue:&rr];
    CHECK(rr.origin.x == 1 && rr.origin.y == 2 && rr.size.width == 3 && rr.size.height == 4);
    Fwd *f = [Fwd new];
    CHECK([(id)f sum:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8] == 36);
    CHECK([(id)f mix:1 x:1.5 y:0.5f] == 3.0);
    NSRange nr = [(id)f range:NSMakeRange(5, 3)];
    CHECK(nr.location == 6 && nr.length == 6);
    CHECK([[(id)f join:@"ab" with:@"cd"] isEqualToString:@"abcd"]);
#if defined(__arm64__)
    NSRect fr = [(id)f rect:NSMakePoint(5, 6) size:NSMakeSize(7, 8)];
    CHECK(fr.origin.x == 5 && fr.size.height == 8);
#endif
    CHECK(f.forwarded >= 4);
    NSUndoManager *u = [NSUndoManager new]; [u setGroupsByEvent:NO];
    [u beginUndoGrouping]; [[u prepareWithInvocationTarget:c] setS:@"before"]; [u setActionName:@"Typing"]; [u endUndoGrouping];
    CHECK([u canUndo]); CHECK([[u undoMenuItemTitle] isEqualToString:@"Undo Typing"]);
    [u undo]; CHECK([c.s isEqualToString:@"before"]);
    NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"length" ascending:NO];
    NSArray *o = [@[@"a", @"ccc", @"bb"] sortedArrayUsingDescriptors:@[sd]];
    CHECK([o[0] isEqualToString:@"ccc"] && [o[2] isEqualToString:@"a"]);
    CHECK([[NSByteCountFormatter stringFromByteCount:1500000 countStyle:NSByteCountFormatterCountStyleFile] isEqualToString:@"1.5 MB"]);
    /* positional arguments in formats (as translations use them: "%2$@ by %1$@") */
    CHECK([[NSString stringWithFormat:@"%2$@ by %1$@ (%3$d, %1$@)", @"Sparkle", @"Hex Fiend", 7] isEqualToString:@"Hex Fiend by Sparkle (7, Sparkle)"]);
    CHECK([[NSString stringWithFormat:@"%1$.1f%%|%2$lld", 2.25, 1234567890123LL] isEqualToString:@"2.2%|1234567890123"]);
    printf(fails ? "INVOCATIONS FAIL\n" : "INVOCATIONS OK\n");
  }
  return fails;
}
