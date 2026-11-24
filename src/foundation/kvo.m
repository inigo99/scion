/* kvo.m — key-value observing. Observations are kept per observed object; -willChangeValueForKey: / -didChangeValueForKey:
 * notify them. Automatic notifications work like Apple's: the first observation of a key gives the object a hidden
 * subclass (NSKVONotifying_<Class>, whose -class answers the original) whose setter for that key wraps the original
 * between will/did. Dependent keys come from +keyPathsForValuesAffecting<Key> / +keyPathsForValuesAffectingValueForKey:.
 * ponytail: a dotted key path is observed on its first key only (changes deeper down are not seen). */
#include "internal.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString *const NSKeyValueChangeKindKey = @"kind", *const NSKeyValueChangeNewKey = @"new", *const NSKeyValueChangeOldKey = @"old",
    *const NSKeyValueChangeIndexesKey = @"indexes", *const NSKeyValueChangeNotificationIsPriorKey = @"notificationIsPrior";

@interface _MWObservation : NSObject {
@public
    id observer; NSString *keyPath, *first; NSKeyValueObservingOptions opts; void *ctx; NSSet *deps; NSMutableArray *olds;
}
@end
@implementation _MWObservation
- (void)dealloc { [keyPath release]; [first release]; [deps release]; [olds release]; [super dealloc]; }
@end

static NSMutableArray *observations(id o, BOOL make) {
    NSMutableArray *a = objc_getAssociatedObject(o, "mw_kvo");
    if (!a && make) { a = [NSMutableArray array]; objc_setAssociatedObject(o, "mw_kvo", a, OBJC_ASSOCIATION_RETAIN); }
    return a;
}
static NSString *first_key(NSString *p) { NSRange r = [p rangeOfString:@"."]; return r.location == NSNotFound ? p : [p substringToIndex:r.location]; }
static NSString *cap(NSString *k) { return [k length] ? [[[k substringToIndex:1] uppercaseString] stringByAppendingString:[k substringFromIndex:1]] : k; }

/* ---------------------------------------------------------------- the notifying subclass */
static NSMutableDictionary *setter_keys;   /* "Class|setFoo:" -> key */
static Class kvo_class_class(id self, SEL _cmd) { return class_getSuperclass(object_getClass(self)); }
static NSString *key_of_setter(id self, SEL s) {
    @synchronized ([_MWObservation class]) { return setter_keys[[NSString stringWithFormat:@"%s|%s", class_getName(object_getClass(self)), sel_getName(s)]]; }
}
static IMP orig_imp(id self, SEL s) { return class_getMethodImplementation(class_getSuperclass(object_getClass(self)), s); }
#define KVO_SETTER(name, T) \
    static void name(id self, SEL s, T v) { \
        NSString *k = key_of_setter(self, s); \
        if (k) [self willChangeValueForKey:k]; \
        ((void (*)(id, SEL, T))orig_imp(self, s))(self, s, v); \
        if (k) [self didChangeValueForKey:k]; \
    }
KVO_SETTER(kvo_set_id, id)
KVO_SETTER(kvo_set_long, long long)
KVO_SETTER(kvo_set_double, double)
KVO_SETTER(kvo_set_float, float)
KVO_SETTER(kvo_set_rect, NSRect)
KVO_SETTER(kvo_set_size, NSSize)
KVO_SETTER(kvo_set_point, NSPoint)
KVO_SETTER(kvo_set_range, NSRange)

static void ensure_notifying_setter(id obj, NSString *key) {
    Class cls = object_getClass(obj);
    if (!cls || class_isMetaClass(cls)) return;
    Class real = [obj class];
    if (![real automaticallyNotifiesObserversForKey:key]) return;
    SEL s = sel_registerName([[NSString stringWithFormat:@"set%@:", cap(key)] UTF8String]);
    Method m = class_getInstanceMethod(real, s);
    if (!m) return;
    char t[64]; method_getArgumentType(m, 2, t, sizeof t);
    const char *at = t; while (*at && strchr("rnNoORV", *at)) at++;
    IMP imp = NULL;
    switch (*at) {
    case '@': case '#': case '*': case '^': imp = (IMP)kvo_set_id; break;
    case 'c': case 'C': case 'B': case 's': case 'S': case 'i': case 'I': case 'l': case 'L': case 'q': case 'Q': imp = (IMP)kvo_set_long; break;
    case 'd': imp = (IMP)kvo_set_double; break;
    case 'f': imp = (IMP)kvo_set_float; break;
    case '{':
        if (!strncmp(at, "{CGRect", 7) || !strncmp(at, "{_NSRect", 8)) imp = (IMP)kvo_set_rect;
        else if (!strncmp(at, "{CGSize", 7) || !strncmp(at, "{_NSSize", 8)) imp = (IMP)kvo_set_size;
        else if (!strncmp(at, "{CGPoint", 8) || !strncmp(at, "{_NSPoint", 9)) imp = (IMP)kvo_set_point;
        else if (!strncmp(at, "{_NSRange", 9)) imp = (IMP)kvo_set_range;
        break;
    }
    if (!imp) return;
    @synchronized ([_MWObservation class]) {
    Class k = cls;
    if (strncmp(class_getName(cls), "NSKVONotifying_", 15)) {
        char name[256]; snprintf(name, sizeof name, "NSKVONotifying_%s", class_getName(cls));
        k = objc_getClass(name);
        if (!k) {
            k = objc_allocateClassPair(cls, name, 0);
            class_addMethod(k, @selector(class), (IMP)kvo_class_class, "#@:");
            objc_registerClassPair(k);
        }
        object_setClass(obj, k);
    }
    if (!setter_keys) setter_keys = [[NSMutableDictionary alloc] init];
    NSString *sk = [NSString stringWithFormat:@"%s|%s", class_getName(k), sel_getName(s)];
    if (!setter_keys[sk]) { setter_keys[sk] = key; class_addMethod(k, s, imp, method_getTypeEncoding(m)); }
    }
}

/* ---------------------------------------------------------------- NSObject */
@implementation NSObject (NSKeyValueObserving)
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)k {
    SEL s = sel_registerName([[NSString stringWithFormat:@"automaticallyNotifiesObserversOf%@", cap(k)] UTF8String]);
    if (class_getClassMethod(self, s)) return ((BOOL (*)(id, SEL))objc_msgSend)(self, s);
    return YES;
}
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)k {
    SEL s = sel_registerName([[NSString stringWithFormat:@"keyPathsForValuesAffecting%@", cap(k)] UTF8String]);
    if (class_getClassMethod(self, s)) return ((id (*)(id, SEL))objc_msgSend)(self, s);
    return [NSSet set];
}
- (void)addObserver:(NSObject *)o forKeyPath:(NSString *)p options:(NSKeyValueObservingOptions)opts context:(void *)ctx {
    if (!o || !p) return;
    _MWObservation *ob = [[[_MWObservation alloc] init] autorelease];
    ob->observer = o; ob->keyPath = [p copy]; ob->first = [first_key(p) copy]; ob->opts = opts; ob->ctx = ctx;
    NSMutableSet *deps = [NSMutableSet set];
    for (NSString *d in [[self class] keyPathsForValuesAffectingValueForKey:ob->first]) [deps addObject:first_key(d)];
    ob->deps = [deps copy];
    @synchronized (self) { [observations(self, YES) addObject:ob]; }
    ensure_notifying_setter(self, ob->first);
    for (NSString *d in deps) ensure_notifying_setter(self, d);
    if (opts & NSKeyValueObservingOptionInitial) {
        NSMutableDictionary *ch = [NSMutableDictionary dictionaryWithObject:@(NSKeyValueChangeSetting) forKey:NSKeyValueChangeKindKey];
        if (opts & NSKeyValueObservingOptionNew) ch[NSKeyValueChangeNewKey] = [self valueForKeyPath:p] ?: [NSNull null];
        [o observeValueForKeyPath:p ofObject:self change:ch context:ctx];
    }
}
- (void)removeObserver:(NSObject *)o forKeyPath:(NSString *)p context:(void *)ctx {
    @synchronized (self) {
        NSMutableArray *a = observations(self, NO);
        for (NSInteger i = (NSInteger)[a count] - 1; i >= 0; i--) {
            _MWObservation *ob = a[(NSUInteger)i];
            if (ob->observer == o && [ob->keyPath isEqualToString:p] && ob->ctx == ctx) { [a removeObjectAtIndex:(NSUInteger)i]; return; }
        }
    }
}
- (void)removeObserver:(NSObject *)o forKeyPath:(NSString *)p {
    @synchronized (self) {
        NSMutableArray *a = observations(self, NO);
        for (NSInteger i = (NSInteger)[a count] - 1; i >= 0; i--) {
            _MWObservation *ob = a[(NSUInteger)i];
            if (ob->observer == o && [ob->keyPath isEqualToString:p]) { [a removeObjectAtIndex:(NSUInteger)i]; return; }
        }
    }
}
- (void)observeValueForKeyPath:(NSString *)p ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx {}
- (void *)observationInfo { return observations(self, NO); }
- (void)setObservationInfo:(void *)i {}
static NSArray *matching(id self, NSString *k) {
    NSMutableArray *r = nil;
    @synchronized (self) {
        for (_MWObservation *ob in observations(self, NO))
            if ([k rangeOfString:@"."].location != NSNotFound ? [ob->keyPath isEqualToString:k] : ([ob->first isEqualToString:k] || [ob->deps containsObject:k])) { if (!r) r = [NSMutableArray array]; [r addObject:ob]; }
    }
    return r;
}
- (void)willChangeValueForKey:(NSString *)k {
    for (_MWObservation *ob in matching(self, k)) {
        if (!ob->olds) ob->olds = [[NSMutableArray alloc] init];
        [ob->olds addObject:(ob->opts & NSKeyValueObservingOptionOld) ? ([self valueForKeyPath:ob->keyPath] ?: [NSNull null]) : [NSNull null]];
        if (ob->opts & NSKeyValueObservingOptionPrior)
            [ob->observer observeValueForKeyPath:ob->keyPath ofObject:self change:@{NSKeyValueChangeKindKey: @(NSKeyValueChangeSetting), NSKeyValueChangeNotificationIsPriorKey: @YES} context:ob->ctx];
    }
}
- (void)didChangeValueForKey:(NSString *)k {
    for (_MWObservation *ob in matching(self, k)) {
        NSMutableDictionary *ch = [NSMutableDictionary dictionaryWithObject:@(NSKeyValueChangeSetting) forKey:NSKeyValueChangeKindKey];
        id old = [[[ob->olds lastObject] retain] autorelease];
        if ([ob->olds count]) [ob->olds removeLastObject];
        if (ob->opts & NSKeyValueObservingOptionOld) ch[NSKeyValueChangeOldKey] = old ?: [NSNull null];
        if (ob->opts & NSKeyValueObservingOptionNew) ch[NSKeyValueChangeNewKey] = [self valueForKeyPath:ob->keyPath] ?: [NSNull null];
        [ob->observer observeValueForKeyPath:ob->keyPath ofObject:self change:ch context:ob->ctx];
    }
}
- (void)willChange:(NSKeyValueChange)c valuesAtIndexes:(NSIndexSet *)i forKey:(NSString *)k { [self willChangeValueForKey:k]; }
- (void)didChange:(NSKeyValueChange)c valuesAtIndexes:(NSIndexSet *)i forKey:(NSString *)k { [self didChangeValueForKey:k]; }
- (void)willChangeValueForKey:(NSString *)k withSetMutation:(NSKeyValueSetMutationKind)m usingObjects:(NSSet *)o { [self willChangeValueForKey:k]; }
- (void)didChangeValueForKey:(NSString *)k withSetMutation:(NSKeyValueSetMutationKind)m usingObjects:(NSSet *)o { [self didChangeValueForKey:k]; }
@end
