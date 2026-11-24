/* runloop.m — scion Foundation: NSRunLoop, NSTimer, NSNotificationCenter, NSOperation(Queue), NSHashTable,
 * NSNumberFormatter, perform-selector helpers and the CFRunLoop entry points. MRC.
 * The main run loop also drains the main dispatch queue, as on macOS.
 * ponytail: run loop modes are accepted but not separated (every timer fires in every mode); the loop polls the main
 * dispatch queue every millisecond instead of waiting on a port. */
#import "internal.h"

typedef struct dqueue *dq_t; typedef struct dgroup *dg_t;
extern struct dqueue _dispatch_main_q; extern int _dispatch_queue_attr_concurrent;
void dispatch_async(dq_t, void (^)(void)); void dispatch_sync(dq_t, void (^)(void));
dq_t dispatch_get_global_queue(long, unsigned long); dq_t dispatch_queue_create(const char *, void *);
dg_t dispatch_group_create(void); void dispatch_group_async(dg_t, dq_t, void (^)(void)); long dispatch_group_wait(dg_t, uint64_t);
int _scion_dispatch_drain_main(void); int usleep(unsigned);
int pthread_key_create(unsigned long *, void (*)(void *)); void *pthread_getspecific(unsigned long); int pthread_setspecific(unsigned long, const void *);
id objc_storeWeak(id *, id); id objc_loadWeakRetained(id *); void objc_destroyWeak(id *);
void *_Block_copy(const void *); void _Block_release(const void *);
#define MAIN_Q (&_dispatch_main_q)

NSString *const NSDefaultRunLoopMode = @"kCFRunLoopDefaultMode", *const NSRunLoopCommonModes = @"kCFRunLoopCommonModes";
const CFStringRef kCFRunLoopDefaultMode = (CFStringRef)@"kCFRunLoopDefaultMode", kCFRunLoopCommonModes = (CFStringRef)@"kCFRunLoopCommonModes";
static NSTimeInterval now(void) { return [NSDate timeIntervalSinceReferenceDate]; }

/* ================================================================ NSTimer */
@implementation NSTimer { NSTimeInterval _fire, _interval, _tolerance; BOOL _repeats, _valid; id _target; SEL _sel; id _info; void (^_block)(NSTimer *); }
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)t repeats:(BOOL)r block:(void (^)(NSTimer *))b {
    return [[[self alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:t] interval:t repeats:r block:b] autorelease];
}
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)t repeats:(BOOL)r block:(void (^)(NSTimer *))b {
    NSTimer *x = [self timerWithTimeInterval:t repeats:r block:b]; [[NSRunLoop currentRunLoop] addTimer:x forMode:NSDefaultRunLoopMode]; return x;
}
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)t target:(id)tg selector:(SEL)s userInfo:(id)u repeats:(BOOL)r {
    return [[[self alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:t] interval:t target:tg selector:s userInfo:u repeats:r] autorelease];
}
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)t target:(id)tg selector:(SEL)s userInfo:(id)u repeats:(BOOL)r {
    NSTimer *x = [self timerWithTimeInterval:t target:tg selector:s userInfo:u repeats:r]; [[NSRunLoop currentRunLoop] addTimer:x forMode:NSDefaultRunLoopMode]; return x;
}
- (instancetype)initWithFireDate:(NSDate *)d interval:(NSTimeInterval)i repeats:(BOOL)r block:(void (^)(NSTimer *))b {
    _fire = [d timeIntervalSinceReferenceDate]; _interval = i <= 0 ? 0.0001 : i; _repeats = r; _valid = YES; _block = _Block_copy(b); return self;
}
- (instancetype)initWithFireDate:(NSDate *)d interval:(NSTimeInterval)i target:(id)tg selector:(SEL)s userInfo:(id)u repeats:(BOOL)r {
    _fire = [d timeIntervalSinceReferenceDate]; _interval = i <= 0 ? 0.0001 : i; _repeats = r; _valid = YES;
    _target = [tg retain]; _sel = s; _info = [u retain]; return self;
}
- (void)dealloc { [_target release]; [_info release]; if (_block) _Block_release(_block); [super dealloc]; }
- (void)fire {
    if (!_valid) return;
    [[self retain] autorelease];
    if (_block) _block(self); else ((id (*)(id, SEL, id))objc_msgSend)(_target, _sel, self);
    if (!_repeats) [self invalidate];
}
- (void)invalidate {
    if (!_valid) return;
    _valid = NO;
    id t = _target; _target = nil; [t release];       /* breaks the usual target <-> timer cycle, as on macOS */
    if (_block) { _Block_release(_block); _block = nil; }
}
- (BOOL)isValid { return _valid; }
- (NSDate *)fireDate { return [NSDate dateWithTimeIntervalSinceReferenceDate:_fire]; }
- (void)setFireDate:(NSDate *)d { _fire = [d timeIntervalSinceReferenceDate]; }
- (NSTimeInterval)timeInterval { return _repeats ? _interval : 0; }
- (NSTimeInterval)tolerance { return _tolerance; }
- (void)setTolerance:(NSTimeInterval)t { _tolerance = t; }
- (id)userInfo { return _info; }
- (NSTimeInterval)_fireTime { return _fire; }
- (BOOL)_fireIfDue:(NSTimeInterval)t { /* returns YES if it fired */
    if (!_valid || t < _fire) return NO;
    if (_repeats) { _fire += _interval; if (_fire <= t) _fire = t + _interval - __builtin_fmod(t - _fire, _interval); }
    [self fire];
    return YES;
}
@end

/* ================================================================ NSRunLoop */
@interface NSTimer (MWRunLoop) - (NSTimeInterval)_fireTime; - (BOOL)_fireIfDue:(NSTimeInterval)t; @end
extern void (*_scion_main_wake)(void);
/* set by AppKit: dispatches pending window events; returns how many */
int (*_scion_ui_pump)(void);
static unsigned long rl_key;
static NSRunLoop *main_rl;
/* CFRunLoopObserver: called with kCFRunLoopBeforeWaiting after a pass that handled something (ponytail: the other
 * activities are not reported) */
@interface _MWRunLoopObserver : NSObject { @public unsigned long _act; BOOL _repeats, _valid; void (^_block)(id, unsigned long); }
@end
@implementation _MWRunLoopObserver
- (void)dealloc { [_block release]; [super dealloc]; }
@end
@implementation NSRunLoop { NSMutableArray *_timers, *_blocks, *_observers; pthread_mutex_t _m; pthread_cond_t _cv; BOOL _isMain, _stop; NSString *_mode; }
+ (void)_mwSetup { pthread_key_create(&rl_key, 0); main_rl = [[NSRunLoop alloc] _initMain:YES]; pthread_setspecific(rl_key, main_rl); }
- (instancetype)_initMain:(BOOL)m { _timers = [[NSMutableArray alloc] init]; _blocks = [[NSMutableArray alloc] init]; _isMain = m; return self; }
+ (NSRunLoop *)currentRunLoop {
    NSRunLoop *r = pthread_getspecific(rl_key);
    if (!r) { r = [[NSRunLoop alloc] _initMain:NO]; pthread_setspecific(rl_key, r); } /* ponytail: per-thread run loops are never freed */
    return r;
}
+ (NSRunLoop *)mainRunLoop { return main_rl; }
- (NSString *)currentMode { return _mode; }
- (void *)getCFRunLoop { return self; }
/* run loop modes, for timers: a timer fires only in the modes it was added for (common modes: default, modal panel and
 * event tracking). ponytail: blocks, the main queue and window events are serviced in every mode. */
static BOOL mode_matches(NSSet *modes, NSString *m) {
    if (!m || !modes || [modes containsObject:m]) return YES;
    return [modes containsObject:NSRunLoopCommonModes] && ([m isEqualToString:NSDefaultRunLoopMode] || [m isEqualToString:@"NSModalPanelRunLoopMode"] || [m isEqualToString:@"NSEventTrackingRunLoopMode"]);
}
- (void)addTimer:(NSTimer *)t forMode:(NSString *)mode {
    pthread_mutex_lock(&_m);
    NSSet *old = objc_getAssociatedObject(t, "mw_modes");
    objc_setAssociatedObject(t, "mw_modes", old ? [old setByAddingObject:mode ?: NSDefaultRunLoopMode] : [NSSet setWithObject:mode ?: NSDefaultRunLoopMode], OBJC_ASSOCIATION_RETAIN);
    if ([_timers indexOfObjectIdenticalTo:t] == NSNotFound) [_timers addObject:t];
    pthread_cond_signal(&_cv); pthread_mutex_unlock(&_m);
}
- (void)performBlock:(void (^)(void))b {
    pthread_mutex_lock(&_m); id c = [b copy]; [_blocks addObject:c]; [c release]; pthread_cond_signal(&_cv); pthread_mutex_unlock(&_m);
}
- (void)_addObserver:(id)o { if (!_observers) _observers = [[NSMutableArray alloc] init]; if ([_observers indexOfObjectIdenticalTo:o] == NSNotFound) [_observers addObject:o]; }
- (void)_removeObserver:(id)o { [_observers removeObjectIdenticalTo:o]; }
- (void)performInModes:(NSArray *)modes block:(void (^)(void))b { [self performBlock:b]; }
- (void)_wake { pthread_mutex_lock(&_m); pthread_cond_signal(&_cv); pthread_mutex_unlock(&_m); if (_isMain && _scion_main_wake) _scion_main_wake(); }
/* one pass: perform blocks, fire due timers, drain the main queue. Returns the number of things handled. */
- (int)_pass {
    int n = 0;
    pthread_mutex_lock(&_m);
    NSArray *blocks = [[_blocks copy] autorelease]; [_blocks removeAllObjects];
    NSArray *timers = [[_timers copy] autorelease];
    pthread_mutex_unlock(&_m);
    for (void (^b)(void) in blocks) { b(); n++; }
    NSTimeInterval t = now();
    for (NSTimer *x in timers) if (mode_matches(objc_getAssociatedObject(x, "mw_modes"), _mode) && [x _fireIfDue:t]) n++;
    pthread_mutex_lock(&_m);
    for (NSInteger i = (NSInteger)[_timers count] - 1; i >= 0; i--) if (![[_timers objectAtIndex:(NSUInteger)i] isValid]) [_timers removeObjectAtIndex:(NSUInteger)i];
    pthread_mutex_unlock(&_m);
    if (_isMain) n += _scion_dispatch_drain_main();
    if (_isMain && _scion_ui_pump) n += _scion_ui_pump(); /* AppKit: window events while the app runs the run loop itself */
    if (n && [_observers count]) for (_MWRunLoopObserver *o in [[_observers copy] autorelease]) {
        if (!o->_valid || !(o->_act & 0x20 /* kCFRunLoopBeforeWaiting */)) continue;
        o->_block(o, 0x20);
        if (!o->_repeats) { o->_valid = NO; [_observers removeObjectIdenticalTo:o]; }
    }
    return n;
}
- (int)_passInMode:(NSString *)m { NSString *old = _mode; _mode = m; int n = [self _pass]; _mode = old; return n; }
- (NSTimeInterval)_nextTimer {
    NSTimeInterval next = 1e300;
    pthread_mutex_lock(&_m);
    for (NSTimer *x in _timers) if ([x isValid] && [x _fireTime] < next) next = [x _fireTime];
    pthread_mutex_unlock(&_m);
    return next;
}
- (BOOL)runMode:(NSString *)mode beforeDate:(NSDate *)limit {
    NSTimeInterval deadline = limit ? [limit timeIntervalSinceReferenceDate] : 0;
    NSString *old = _mode; _mode = mode;
    BOOL handled = NO;
    for (;;) {
        void *pool = objc_autoreleasePoolPush();
        int n = [self _pass];
        objc_autoreleasePoolPop(pool);
        if (n) { handled = YES; break; }
        NSTimeInterval t = now(), next = [self _nextTimer];
        if (!_isMain && next > 1e299 && ![_blocks count]) break;           /* no sources: return immediately (NO) */
        if (t >= deadline || _stop) break;
        NSTimeInterval wait = (next < deadline ? next : deadline) - t;
        if (_isMain && wait > 0.001) wait = 0.001;                          /* poll the main dispatch queue */
        if (wait > 0) {
            struct timespec ts = {(int64_t)wait, (int64_t)((wait - (int64_t)wait) * 1e9)};
            pthread_mutex_lock(&_m);
            if (![_blocks count]) pthread_cond_timedwait_relative_np(&_cv, &_m, &ts);
            pthread_mutex_unlock(&_m);
        }
    }
    _mode = old;
    return handled || _isMain || [self _nextTimer] < 1e299;
}
- (void)runUntilDate:(NSDate *)d {
    _stop = NO;
    while ([d timeIntervalSinceNow] > 0 && !_stop) if (![self runMode:NSDefaultRunLoopMode beforeDate:d]) break;
    _stop = NO;
}
- (void)run { _stop = NO; while (!_stop && [self runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {} _stop = NO; }
- (void)acceptInputForMode:(NSString *)m beforeDate:(NSDate *)d { [self runMode:m beforeDate:d]; }
- (void)_stop { _stop = YES; [self _wake]; }
- (void)_runUntilStopped { _stop = NO; while (!_stop) [self runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]; _stop = NO; }
@end

/* CoreFoundation run loop entry points (a CFRunLoopRef is the NSRunLoop) */
CFRunLoopRef CFRunLoopGetCurrent(void) { return (CFRunLoopRef)[NSRunLoop currentRunLoop]; }
CFRunLoopRef CFRunLoopGetMain(void) { return (CFRunLoopRef)[NSRunLoop mainRunLoop]; }
void CFRunLoopRun(void) { [[NSRunLoop currentRunLoop] _runUntilStopped]; }
void CFRunLoopStop(CFRunLoopRef rl) { [(NSRunLoop *)(rl ? (id)rl : [NSRunLoop currentRunLoop]) _stop]; }
void CFRunLoopWakeUp(CFRunLoopRef rl) { [(NSRunLoop *)rl _wake]; }
int CFRunLoopRunInMode(CFRunLoopMode mode, CFTimeInterval seconds, unsigned char returnAfterSource) {
    NSRunLoop *rl = [NSRunLoop currentRunLoop];
    NSDate *lim = [NSDate dateWithTimeIntervalSinceNow:seconds];
    do { if ([rl runMode:(NSString *)mode beforeDate:lim] && returnAfterSource) return 4; /* kCFRunLoopRunHandledSource */ }
    while ([lim timeIntervalSinceNow] > 0);
    return 3; /* kCFRunLoopRunTimedOut */
}
void CFRunLoopPerformBlock(CFRunLoopRef rl, CFTypeRef mode, void (^b)(void)) { [(NSRunLoop *)rl performBlock:b]; }
unsigned char CFRunLoopIsWaiting(CFRunLoopRef rl) { return NO; }
void *CFRunLoopObserverCreateWithHandler(void *alloc, unsigned long activities, unsigned char repeats, long order, void (^b)(void *obs, unsigned long act)) {
    _MWRunLoopObserver *o = [[_MWRunLoopObserver alloc] init];
    o->_act = activities; o->_repeats = repeats; o->_valid = YES; o->_block = (void (^)(id, unsigned long))[b copy];
    return o;
}
void CFRunLoopAddObserver(CFRunLoopRef rl, void *obs, CFTypeRef mode) { [(NSRunLoop *)rl _addObserver:obs]; }
void CFRunLoopRemoveObserver(CFRunLoopRef rl, void *obs, CFTypeRef mode) { [(NSRunLoop *)rl _removeObserver:obs]; }
void CFRunLoopObserverInvalidate(void *obs) { ((_MWRunLoopObserver *)obs)->_valid = NO; }

/* ================================================================ perform-selector helpers */
@implementation NSObject (NSThreadPerformAdditions)
- (void)performSelectorOnMainThread:(SEL)s withObject:(id)o waitUntilDone:(BOOL)w {
    if (w && [NSThread isMainThread]) { ((id (*)(id, SEL, id))objc_msgSend)(self, s, o); return; }
    [self retain]; [o retain];
    void (^b)(void) = ^{ ((id (*)(id, SEL, id))objc_msgSend)(self, s, o); [o release]; [self release]; };
    if (w) dispatch_sync(MAIN_Q, b); else dispatch_async(MAIN_Q, b);
}
- (void)performSelectorOnMainThread:(SEL)s withObject:(id)o waitUntilDone:(BOOL)w modes:(NSArray *)m { [self performSelectorOnMainThread:s withObject:o waitUntilDone:w]; }
- (void)performSelectorInBackground:(SEL)s withObject:(id)o { [NSThread detachNewThreadSelector:s toTarget:self withObject:o]; }
- (void)performSelector:(SEL)s withObject:(id)o afterDelay:(NSTimeInterval)d {
    [self retain]; [o retain];
    NSTimer *t = [NSTimer timerWithTimeInterval:d repeats:NO block:^(NSTimer *x) { ((id (*)(id, SEL, id))objc_msgSend)(self, s, o); [o release]; [self release]; }];
    [[NSRunLoop currentRunLoop] addTimer:t forMode:NSDefaultRunLoopMode];
}
- (void)performSelector:(SEL)s withObject:(id)o afterDelay:(NSTimeInterval)d inModes:(NSArray *)m {
    [self retain]; [o retain];
    NSTimer *t = [NSTimer timerWithTimeInterval:d repeats:NO block:^(NSTimer *x) { ((id (*)(id, SEL, id))objc_msgSend)(self, s, o); [o release]; [self release]; }];
    for (NSString *mode in ([m count] ? m : @[NSDefaultRunLoopMode])) [[NSRunLoop currentRunLoop] addTimer:t forMode:mode];
}
+ (void)cancelPreviousPerformRequestsWithTarget:(id)t { } /* ponytail: delayed performs cannot be cancelled yet */
+ (void)cancelPreviousPerformRequestsWithTarget:(id)t selector:(SEL)s object:(id)o { }
@end

/* ================================================================ NSNotification / NSNotificationCenter */
@implementation NSNotification { NSString *_name; id _object; NSDictionary *_info; }
+ (instancetype)notificationWithName:(NSString *)n object:(id)o { return [self notificationWithName:n object:o userInfo:nil]; }
+ (instancetype)notificationWithName:(NSString *)n object:(id)o userInfo:(NSDictionary *)u { return [[[self alloc] initWithName:n object:o userInfo:u] autorelease]; }
- (instancetype)initWithName:(NSString *)n object:(id)o userInfo:(NSDictionary *)u { _name = [n copy]; _object = [o retain]; _info = [u copy]; return self; }
- (void)dealloc { [_name release]; [_object release]; [_info release]; [super dealloc]; }
- (NSString *)name { return _name; }
- (id)object { return _object; }
- (NSDictionary *)userInfo { return _info; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)description { return [NSString stringWithFormat:@"NSConcreteNotification %p {name = %@}", self, _name]; }
@end

@interface __NSObserver : NSObject { @public id _weak; SEL _sel; NSString *_name; void *_object; void (^_block)(NSNotification *); NSOperationQueue *_queue; } @end
@implementation __NSObserver
- (void)dealloc { objc_destroyWeak(&_weak); [_name release]; [_queue release]; if (_block) _Block_release(_block); [super dealloc]; }
@end
@implementation NSNotificationCenter { NSMutableArray *_obs; pthread_mutex_t _m; }
+ (NSNotificationCenter *)defaultCenter { static NSNotificationCenter *c; if (!c) c = [[NSNotificationCenter alloc] init]; return c; }
- (instancetype)init { _obs = [[NSMutableArray alloc] init]; return self; }
- (void)_add:(__NSObserver *)o { pthread_mutex_lock(&_m); [_obs addObject:o]; pthread_mutex_unlock(&_m); }
- (void)addObserver:(id)obs selector:(SEL)s name:(NSString *)n object:(id)obj {
    __NSObserver *o = [[__NSObserver alloc] init];
    objc_storeWeak(&o->_weak, obs); o->_sel = s; o->_name = [n copy]; o->_object = obj;
    [self _add:o]; [o release];
}
- (id)addObserverForName:(NSString *)n object:(id)obj queue:(NSOperationQueue *)q usingBlock:(void (^)(NSNotification *))b {
    __NSObserver *o = [[__NSObserver alloc] init];
    o->_name = [n copy]; o->_object = obj; o->_block = _Block_copy(b); o->_queue = [q retain];
    [self _add:o];
    return [o autorelease];   /* the token: pass it to -removeObserver: */
}
- (void)removeObserver:(id)obs name:(NSString *)n object:(id)obj {
    pthread_mutex_lock(&_m);
    for (NSInteger i = (NSInteger)[_obs count] - 1; i >= 0; i--) {
        __NSObserver *o = [_obs objectAtIndex:(NSUInteger)i];
        id w = objc_loadWeakRetained(&o->_weak);
        BOOL match = (o == obs || w == obs) && (!n || [n isEqual:o->_name]) && (!obj || obj == o->_object);
        [w release];
        if (match) [_obs removeObjectAtIndex:(NSUInteger)i];
    }
    pthread_mutex_unlock(&_m);
}
- (void)removeObserver:(id)obs { [self removeObserver:obs name:nil object:nil]; }
- (void)postNotification:(NSNotification *)note {
    pthread_mutex_lock(&_m);
    NSArray *list = [[_obs copy] autorelease];
    pthread_mutex_unlock(&_m);
    NSString *n = [note name]; id obj = [note object];
    for (__NSObserver *o in list) {
        if ((o->_name && ![o->_name isEqual:n]) || (o->_object && o->_object != obj)) continue;
        if (o->_block) {
            NSOperationQueue *q = o->_queue;
            if (!q || (q == [NSOperationQueue mainQueue] && [NSThread isMainThread]) || q == [NSOperationQueue currentQueue]) o->_block(note);
            else { NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{ o->_block(note); }]; [q addOperations:[NSArray arrayWithObject:op] waitUntilFinished:YES]; }
        } else {
            id w = objc_loadWeakRetained(&o->_weak);
            if (w) { ((id (*)(id, SEL, id))objc_msgSend)(w, o->_sel, note); [w release]; }
        }
    }
}
- (void)postNotificationName:(NSString *)n object:(id)o { [self postNotification:[NSNotification notificationWithName:n object:o userInfo:nil]]; }
- (void)postNotificationName:(NSString *)n object:(id)o userInfo:(NSDictionary *)u { [self postNotification:[NSNotification notificationWithName:n object:o userInfo:u]]; }
@end

/* ================================================================ NSOperation / NSBlockOperation / NSOperationQueue */
@implementation NSOperation { @protected BOOL _cancelled, _executing, _finished; void (^_completion)(void); NSMutableArray *_deps; NSCondition *_done; NSString *_name; NSInteger _prio; }
- (instancetype)init { _done = [[NSCondition alloc] init]; _deps = [[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [_done release]; [_deps release]; [_name release]; if (_completion) _Block_release(_completion); [super dealloc]; }
- (void)main { }
- (void)start {
    for (NSOperation *d in [[_deps copy] autorelease]) [d waitUntilFinished];   /* ponytail: dependencies wait inside the worker */
    _executing = YES;
    if (!_cancelled) { void *pool = objc_autoreleasePoolPush(); [self main]; objc_autoreleasePoolPop(pool); }
    _executing = NO;
    [_done lock]; _finished = YES; [_done broadcast]; [_done unlock];
    if (_completion) _completion();
}
- (void)cancel { _cancelled = YES; }
- (BOOL)isCancelled { return _cancelled; }
- (BOOL)isExecuting { return _executing; }
- (BOOL)isFinished { return _finished; }
- (BOOL)isReady { return YES; }
- (BOOL)isConcurrent { return NO; }
- (BOOL)isAsynchronous { return NO; }
- (void)waitUntilFinished { [_done lock]; while (!_finished) [_done wait]; [_done unlock]; }
- (void)addDependency:(NSOperation *)o { [_deps addObject:o]; }
- (void)removeDependency:(NSOperation *)o { [_deps removeObjectIdenticalTo:o]; }
- (NSArray *)dependencies { return [[_deps copy] autorelease]; }
- (void (^)(void))completionBlock { return _completion; }
- (void)setCompletionBlock:(void (^)(void))b { if (_completion) _Block_release(_completion); _completion = b ? _Block_copy(b) : 0; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)n { [_name release]; _name = [n copy]; }
- (NSInteger)queuePriority { return _prio; }
- (void)setQueuePriority:(NSInteger)p { _prio = p; }
- (void)setQualityOfService:(NSInteger)q { }
@end
@implementation NSBlockOperation { NSMutableArray *_blocks; }
+ (instancetype)blockOperationWithBlock:(void (^)(void))b { NSBlockOperation *o = [[[self alloc] init] autorelease]; [o addExecutionBlock:b]; return o; }
- (void)addExecutionBlock:(void (^)(void))b { if (!_blocks) _blocks = [[NSMutableArray alloc] init]; id c = [b copy]; [_blocks addObject:c]; [c release]; }
- (NSArray *)executionBlocks { return [[_blocks copy] autorelease]; }
- (void)dealloc { [_blocks release]; [super dealloc]; }
- (void)main { for (void (^b)(void) in _blocks) b(); }
@end

static unsigned long current_q_key;
@implementation NSOperationQueue { dq_t _q; dg_t _g; NSInteger _max; NSString *_name; BOOL _suspended, _isMain; NSMutableArray *_ops; pthread_mutex_t _m; }
+ (void)_mwSetup { pthread_key_create(&current_q_key, 0); }
+ (NSOperationQueue *)mainQueue {
    static NSOperationQueue *m;
    if (!m) { m = [[NSOperationQueue alloc] init]; m->_q = MAIN_Q; m->_isMain = YES; m->_max = 1; m->_name = @"NSOperationQueue Main Queue"; }
    return m;
}
+ (NSOperationQueue *)currentQueue { NSOperationQueue *q = pthread_getspecific(current_q_key); return q ? q : ([NSThread isMainThread] ? [self mainQueue] : nil); }
- (instancetype)init { _max = -1; _g = dispatch_group_create(); _ops = [[NSMutableArray alloc] init]; return self; }
- (dq_t)_dq {
    if (!_q) _q = _max == 1 ? dispatch_queue_create("NSOperationQueue", 0) : dispatch_get_global_queue(0, 0); /* ponytail: max>1 not throttled */
    return _q;
}
- (void)addOperation:(NSOperation *)op {
    [op retain];
    pthread_mutex_lock(&_m); [_ops addObject:op]; pthread_mutex_unlock(&_m);
    dispatch_group_async(_g, [self _dq], ^{
        void *prev = pthread_getspecific(current_q_key); pthread_setspecific(current_q_key, self);
        [op start];
        pthread_setspecific(current_q_key, prev);
        pthread_mutex_lock(&_m); [_ops removeObjectIdenticalTo:op]; pthread_mutex_unlock(&_m);
        [op release];
    });
}
- (void)addOperations:(NSArray *)ops waitUntilFinished:(BOOL)w {
    for (NSOperation *o in ops) [self addOperation:o];
    if (w) for (NSOperation *o in ops) [o waitUntilFinished];
}
- (void)addOperationWithBlock:(void (^)(void))b { [self addOperation:[NSBlockOperation blockOperationWithBlock:b]]; }
- (void)addBarrierBlock:(void (^)(void))b { [self waitUntilAllOperationsAreFinished]; [self addOperationWithBlock:b]; } /* ponytail: blocks the caller */
- (void)waitUntilAllOperationsAreFinished {
    if (_isMain) { while ([self operationCount]) { if ([NSThread isMainThread]) _scion_dispatch_drain_main(); else usleep(1000); } return; }
    dispatch_group_wait(_g, ~0ull);
}
- (void)cancelAllOperations { pthread_mutex_lock(&_m); for (NSOperation *o in _ops) [o cancel]; pthread_mutex_unlock(&_m); }
- (NSUInteger)operationCount { pthread_mutex_lock(&_m); NSUInteger n = [_ops count]; pthread_mutex_unlock(&_m); return n; }
- (NSArray *)operations { pthread_mutex_lock(&_m); NSArray *a = [[_ops copy] autorelease]; pthread_mutex_unlock(&_m); return a; }
- (NSInteger)maxConcurrentOperationCount { return _max; }
- (void)setMaxConcurrentOperationCount:(NSInteger)n { if (!_isMain && !_q) _max = n; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)n { [_name release]; _name = [n copy]; }
- (BOOL)isSuspended { return _suspended; }
- (void)setSuspended:(BOOL)s { _suspended = s; } /* ponytail: suspension is not enforced */
- (void)setQualityOfService:(NSInteger)q { }
- (dq_t)underlyingQueue { return [self _dq]; }
- (void)setUnderlyingQueue:(dq_t)q { _q = q; }
@end

/* ================================================================ NSHashTable (weak or strong object sets) */
enum { PF_STRONG = 0, PF_OPAQUE = 2, PF_WEAK = 5, PF_COPYIN = 1 << 16, PF_OBJECT_PERSONALITY = 0, PF_POINTER_PERSONALITY = 1 << 9 };
@implementation NSHashTable { id **_slots; NSUInteger _n, _cap; NSUInteger _opt; unsigned long _mut; }
+ (NSHashTable *)weakObjectsHashTable { return [[[self alloc] initWithOptions:PF_WEAK capacity:0] autorelease]; }
+ (NSHashTable *)hashTableWithOptions:(NSUInteger)o { return [[[self alloc] initWithOptions:o capacity:0] autorelease]; }
+ (NSHashTable *)hashTableWithWeakObjects { return [self weakObjectsHashTable]; }
- (instancetype)init { return [self initWithOptions:PF_STRONG capacity:0]; }
- (instancetype)initWithOptions:(NSUInteger)o capacity:(NSUInteger)c { _opt = o; return self; }
- (BOOL)_weak { return (_opt & 0xFF) == PF_WEAK; }
- (id)_get:(NSUInteger)i { return [self _weak] ? [objc_loadWeakRetained(_slots[i]) autorelease] : *_slots[i]; }
- (void)_compact {
    for (NSUInteger i = 0; i < _n;) {
        if ([self _weak] && !*_slots[i]) { objc_destroyWeak(_slots[i]); free(_slots[i]); _slots[i] = _slots[--_n]; _mut++; } else i++;
    }
}
- (BOOL)_same:(id)a as:(id)b { return a == b || (!(_opt & PF_POINTER_PERSONALITY) && [a isEqual:b]); }
- (NSInteger)_find:(id)o { [self _compact]; for (NSUInteger i = 0; i < _n; i++) if ([self _same:[self _get:i] as:o]) return (NSInteger)i; return -1; }
- (void)addObject:(id)o {
    if (!o || [self _find:o] >= 0) return;
    if (_n == _cap) { _cap = _cap * 2 + 8; _slots = realloc(_slots, _cap * sizeof(id *)); }
    id *box = calloc(1, sizeof(id));
    if ([self _weak]) objc_storeWeak(box, o); else *box = (_opt & PF_COPYIN) ? [o copy] : [o retain];
    _slots[_n++] = box; _mut++;
}
- (void)removeObject:(id)o {
    NSInteger i = [self _find:o]; if (i < 0) return;
    if ([self _weak]) objc_destroyWeak(_slots[i]); else [*_slots[i] release];
    free(_slots[i]); _slots[i] = _slots[--_n]; _mut++;
}
- (void)removeAllObjects { while (_n) { if ([self _weak]) objc_destroyWeak(_slots[_n - 1]); else [*_slots[_n - 1] release]; free(_slots[--_n]); } _mut++; }
- (void)dealloc { [self removeAllObjects]; free(_slots); [super dealloc]; }
- (BOOL)containsObject:(id)o { return o && [self _find:o] >= 0; }
- (id)member:(id)o { NSInteger i = o ? [self _find:o] : -1; return i >= 0 ? [self _get:(NSUInteger)i] : nil; }
- (NSUInteger)count { [self _compact]; return _n; }
- (NSArray *)allObjects { NSMutableArray *a = [NSMutableArray array]; [self _compact]; for (NSUInteger i = 0; i < _n; i++) { id o = [self _get:i]; if (o) [a addObject:o]; } return a; }
- (id)anyObject { return [[self allObjects] firstObject]; }
- (NSSet *)setRepresentation { return [NSSet setWithArray:[self allObjects]]; }
- (NSEnumerator *)objectEnumerator { return [[self allObjects] objectEnumerator]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)b count:(NSUInteger)n {
    /* ponytail: iterates a snapshot (kept in extra[0]); mutating the table while enumerating is allowed */
    if (!s->state) { s->extra[0] = (unsigned long)[[self allObjects] retain]; s->state = 1; }
    NSArray *a = (NSArray *)s->extra[0];
    if (!a) return 0;
    NSUInteger i = s->state - 1, k = 0, total = [a count];
    while (k < n && i + k < total) { b[k] = [a objectAtIndex:i + k]; k++; }
    s->state += k; s->itemsPtr = b; s->mutationsPtr = &s->extra[1];
    if (!k) { [a autorelease]; s->extra[0] = 0; }
    return k;
}
- (id)copyWithZone:(NSZone *)z { NSHashTable *h = [[NSHashTable alloc] initWithOptions:_opt capacity:0]; for (id o in [self allObjects]) [h addObject:o]; return h; }
@end

/* ================================================================ NSMapTable (weak or strong keys and values; keys are not copied)
 * ponytail: linear search, fine for the caches apps keep in them; a hash index if one grows large */
@implementation NSMapTable { id **_k, **_v; NSUInteger _n, _cap, _ko, _vo; }
+ (NSMapTable *)mapTableWithKeyOptions:(NSUInteger)k valueOptions:(NSUInteger)v { return [[[self alloc] initWithKeyOptions:k valueOptions:v capacity:0] autorelease]; }
+ (NSMapTable *)strongToStrongObjectsMapTable { return [self mapTableWithKeyOptions:PF_STRONG valueOptions:PF_STRONG]; }
+ (NSMapTable *)strongToWeakObjectsMapTable { return [self mapTableWithKeyOptions:PF_STRONG valueOptions:PF_WEAK]; }
+ (NSMapTable *)weakToStrongObjectsMapTable { return [self mapTableWithKeyOptions:PF_WEAK valueOptions:PF_STRONG]; }
+ (NSMapTable *)weakToWeakObjectsMapTable { return [self mapTableWithKeyOptions:PF_WEAK valueOptions:PF_WEAK]; }
- (instancetype)init { return [self initWithKeyOptions:PF_STRONG valueOptions:PF_STRONG capacity:0]; }
- (instancetype)initWithKeyOptions:(NSUInteger)k valueOptions:(NSUInteger)v capacity:(NSUInteger)c { _ko = k; _vo = v; return self; }
static id *mt_box(id o, NSUInteger opt) {
    id *b = calloc(1, sizeof(id));
    if ((opt & 0xFF) == PF_WEAK) objc_storeWeak(b, o); else *b = (opt & PF_COPYIN) ? [o copy] : [o retain];
    return b;
}
static void mt_free(id *b, NSUInteger opt) { if ((opt & 0xFF) == PF_WEAK) objc_destroyWeak(b); else [*b release]; free(b); }
static id mt_get(id *b, NSUInteger opt) { return (opt & 0xFF) == PF_WEAK ? [objc_loadWeakRetained(b) autorelease] : *b; }
- (void)_drop:(NSUInteger)i { mt_free(_k[i], _ko); mt_free(_v[i], _vo); _n--; _k[i] = _k[_n]; _v[i] = _v[_n]; }
- (void)_compact { for (NSUInteger i = 0; i < _n;) if (!mt_get(_k[i], _ko) || !mt_get(_v[i], _vo)) [self _drop:i]; else i++; }
- (NSInteger)_find:(id)key {
    [self _compact];
    BOOL ptr = (_ko & PF_POINTER_PERSONALITY) != 0;
    for (NSUInteger i = 0; i < _n; i++) { id k = mt_get(_k[i], _ko); if (k == key || (!ptr && [k isEqual:key])) return (NSInteger)i; }
    return -1;
}
- (id)objectForKey:(id)key { NSInteger i = key ? [self _find:key] : -1; return i >= 0 ? mt_get(_v[i], _vo) : nil; }
- (void)setObject:(id)o forKey:(id)key {
    if (!key) return;
    if (!o) { [self removeObjectForKey:key]; return; }
    NSInteger i = [self _find:key];
    if (i >= 0) { id *nb = mt_box(o, _vo); mt_free(_v[i], _vo); _v[i] = nb; return; }
    if (_n == _cap) { _cap = _cap * 2 + 8; _k = realloc(_k, _cap * sizeof(id *)); _v = realloc(_v, _cap * sizeof(id *)); }
    _k[_n] = mt_box(key, _ko); _v[_n] = mt_box(o, _vo); _n++;
}
- (void)removeObjectForKey:(id)key { NSInteger i = key ? [self _find:key] : -1; if (i >= 0) [self _drop:(NSUInteger)i]; }
- (void)removeAllObjects { while (_n) [self _drop:_n - 1]; }
- (void)dealloc { [self removeAllObjects]; free(_k); free(_v); [super dealloc]; }
- (NSUInteger)count { [self _compact]; return _n; }
- (NSArray *)_keys { NSMutableArray *a = [NSMutableArray array]; [self _compact]; for (NSUInteger i = 0; i < _n; i++) [a addObject:mt_get(_k[i], _ko)]; return a; }
- (NSEnumerator *)keyEnumerator { return [[self _keys] objectEnumerator]; }
- (NSEnumerator *)objectEnumerator { NSMutableArray *a = [NSMutableArray array]; [self _compact]; for (NSUInteger i = 0; i < _n; i++) [a addObject:mt_get(_v[i], _vo)]; return [a objectEnumerator]; }
- (NSDictionary *)dictionaryRepresentation { NSMutableDictionary *d = [NSMutableDictionary dictionary]; [self _compact]; for (NSUInteger i = 0; i < _n; i++) [d setObject:mt_get(_v[i], _vo) forKey:mt_get(_k[i], _ko)]; return d; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)b count:(NSUInteger)n {
    if (!s->state) { s->extra[0] = (unsigned long)[[self _keys] retain]; s->state = 1; }
    NSArray *a = (NSArray *)s->extra[0];
    if (!a) return 0;
    NSUInteger i = s->state - 1, k = 0, total = [a count];
    while (k < n && i + k < total) { b[k] = [a objectAtIndex:i + k]; k++; }
    s->state += k; s->itemsPtr = b; s->mutationsPtr = &s->extra[1];
    if (!k) { [a autorelease]; s->extra[0] = 0; }
    return k;
}
- (id)copyWithZone:(NSZone *)z {
    NSMapTable *m = [[NSMapTable alloc] initWithKeyOptions:_ko valueOptions:_vo capacity:0];
    [self _compact];
    for (NSUInteger i = 0; i < _n; i++) [m setObject:mt_get(_v[i], _vo) forKey:mt_get(_k[i], _ko)];
    return m;
}
@end

/* ================================================================ NSNumberFormatter (en_US conventions) */
@implementation NSNumberFormatter { NSUInteger _style, _minFrac, _maxFrac; BOOL _grouping, _groupingSet; NSString *_gsep, *_dsep; }
- (instancetype)init { _maxFrac = 3; _gsep = @","; _dsep = @"."; return self; }
- (NSUInteger)numberStyle { return _style; }
- (void)setNumberStyle:(NSUInteger)s { _style = s; if (!_groupingSet) _grouping = s == 1 || s == 2 || s == 3; if (s == 0) _maxFrac = 0; if (s == 3) _maxFrac = 0; if (s == 2) { _minFrac = 2; _maxFrac = 2; } }
- (BOOL)usesGroupingSeparator { return _grouping; }
- (void)setUsesGroupingSeparator:(BOOL)g { _grouping = g; _groupingSet = YES; }
- (NSString *)groupingSeparator { return _gsep; }
- (void)setGroupingSeparator:(NSString *)s { [_gsep release]; _gsep = [s copy]; }
- (NSString *)decimalSeparator { return _dsep; }
- (void)setDecimalSeparator:(NSString *)s { [_dsep release]; _dsep = [s copy]; }
- (NSUInteger)minimumFractionDigits { return _minFrac; }
- (void)setMinimumFractionDigits:(NSUInteger)n { _minFrac = n; if (_maxFrac < n) _maxFrac = n; }
- (NSUInteger)maximumFractionDigits { return _maxFrac; }
- (void)setMaximumFractionDigits:(NSUInteger)n { _maxFrac = n; if (_minFrac > n) _minFrac = n; }
- (void)setLocale:(id)l { }
- (NSString *)stringFromNumber:(NSNumber *)num {
    if (!num) return nil;
    double v = [num doubleValue]; if (_style == 3) v *= 100;
    char buf[64]; snprintf(buf, sizeof buf, "%.*f", (int)_maxFrac, v < 0 ? -v : v);
    char *dot = strchr(buf, '.');
    size_t ilen = dot ? (size_t)(dot - buf) : strlen(buf);
    NSMutableString *s = [NSMutableString string];
    if (v < 0 && strspn(buf, "0.") != strlen(buf)) [s appendString:@"-"];
    if (_style == 2) [s appendString:@"$"];
    for (size_t i = 0; i < ilen; i++) {
        [s appendFormat:@"%c", buf[i]];
        if (_grouping && (ilen - i - 1) % 3 == 0 && i + 1 < ilen) [s appendString:_gsep];
    }
    if (dot) {
        size_t f = strlen(dot + 1);
        while (f > _minFrac && dot[f] == '0') f--;
        if (f) { [s appendString:_dsep]; for (size_t i = 1; i <= f; i++) [s appendFormat:@"%c", dot[i]]; }
    }
    if (_style == 3) [s appendString:@"%"];
    return s;
}
- (NSNumber *)numberFromString:(NSString *)str {
    NSString *t = [[str stringByReplacingOccurrencesOfString:_gsep withString:@""] stringByReplacingOccurrencesOfString:_dsep withString:@"."];
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([t hasPrefix:@"$"]) t = [t substringFromIndex:1];
    BOOL pct = [t hasSuffix:@"%"]; if (pct) t = [t substringToIndex:[t length] - 1];
    const char *c = [t UTF8String]; char *end; double v = strtod(c, &end);
    if (end == c || *end) return nil;
    if (pct) v /= 100;
    return v == (double)(long long)v && !strchr(c, '.') ? [NSNumber numberWithLongLong:(long long)v] : [NSNumber numberWithDouble:v];
}
+ (NSString *)localizedStringFromNumber:(NSNumber *)n numberStyle:(NSUInteger)s { NSNumberFormatter *f = [[[NSNumberFormatter alloc] init] autorelease]; [f setNumberStyle:s]; return [f stringFromNumber:n]; }
- (NSString *)stringForObjectValue:(id)o { return [o isKindOfClass:[NSNumber class]] ? [self stringFromNumber:o] : nil; }
@end

void mw_runloop_setup(void) { [NSRunLoop _mwSetup]; [NSOperationQueue _mwSetup]; }
