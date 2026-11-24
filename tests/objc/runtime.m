/* scion's Objective-C runtime (+ ARC), without Foundation. Prints "all OK". */
#import <objc/NSObject.h>
#import <objc/runtime.h>
long write(int, const void *, unsigned long); unsigned long strlen(const char *);
static void out(const char *s) { write(1, s, strlen(s)); }
static int failures;
static void check(const char *n, int ok) { out(ok ? "OK    " : "FAIL "); out(n); out("\n"); if (!ok) failures++; }

static int deallocs, loads, inits;
@protocol Barks <NSObject> - (int)bark; @end

@interface Animal : NSObject
@property (nonatomic, strong) id friend;
@property (nonatomic, weak) id boss;
@property (nonatomic, copy) int (^trick)(int);
@property int legs;
- (int)sound;
+ (int)kingdom;
@end
@implementation Animal
+ (void)load { loads++; }
+ (void)initialize { if (self == [Animal class]) inits++; }
- (instancetype)init { if ((self = [super init])) _legs = 4; return self; }
- (int)sound { return 1; }
+ (int)kingdom { return 100; }
- (void)dealloc { deallocs++; }
@end

@interface Dog : Animal <Barks> { int _extra; } @end
@implementation Dog
- (int)sound { return [super sound] + 10; }   /* objc_msgSendSuper2 */
- (int)bark { return 3; }
@end

@interface Dog (Tricks) - (int)flip; @end
@implementation Dog (Tricks) - (int)flip { return [self sound] * 2; } @end

@interface Echo : NSObject @property (strong) id target; @end
@implementation Echo - (id)forwardingTargetForSelector:(SEL)s { return self.target; } @end

static int swz(id self, SEL _cmd) { return 99; }

int main(void) {
    check("+load called once", loads == 1);
    @autoreleasepool {
        Dog *p = [Dog new];
        check("+initialize", inits == 1);
        check("init + atomic property", p.legs == 4);
        check("super (msgSendSuper2)", [p sound] == 11);
        check("category", [p flip] == 22);
        check("inherited class method", [Dog kingdom] == 100);
        check("protocol", [p conformsToProtocol:@protocol(Barks)] && [p bark] == 3);
        check("isKindOfClass / respondsToSelector", [p isKindOfClass:[Animal class]] && [p respondsToSelector:@selector(flip)] && ![p respondsToSelector:@selector(fly)]);

        Animal *a = [Animal new];
        p.friend = a;
        a.boss = p;
        check("weak points to the object", a.boss == p);
        __weak Animal *w = a;
        a = nil;
        check("strong property keeps it alive", w != nil && deallocs == 0);
        p.friend = nil;
        check("dealloc when the last reference goes", deallocs == 1);
        check("__weak set to nil after dealloc", w == nil);

        __block int captures = 0;
        Animal *b = [Animal new];
        b.trick = ^(int x) { captures++; return x + b.legs; };   /* copied block that captures an object */
        check("copied block with a captured object", b.trick(1) == 5 && captures == 1);
        b.trick = nil;   /* breaks the cycle */

        static char key;
        objc_setAssociatedObject(p, &key, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        check("associated objects", objc_getAssociatedObject(p, &key) == b);

        @synchronized (p) { @synchronized (p) { captures++; } }
        check("recursive @synchronized", captures == 2);

        Method m = class_getInstanceMethod([Dog class], @selector(bark));
        IMP old = method_setImplementation(m, (IMP)swz);
        check("swizzling", [p bark] == 99);
        method_setImplementation(m, old);
        check("swizzling reverted", [p bark] == 3);

        Class Cat = objc_allocateClassPair([Animal class], "Cat", 0);
        class_addMethod(Cat, @selector(sound), (IMP)swz, "i@:");
        objc_registerClassPair(Cat);
        id g = [objc_getClass("Cat") new];
        check("dynamic class", [g sound] == 99 && [g legs] == 4);

        Echo *e = [Echo new]; e.target = p;
        check("forwardingTargetForSelector", [(Dog *)e bark] == 3);
    }
    check("autoreleasepool drained without dealloc leaks", deallocs >= 1);
    out(failures ? "FAILURES\n" : "all OK\n");
    return failures;
}
