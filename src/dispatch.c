/* dispatch.c — Blocks runtime (libclosure ABI) and a compact libdispatch for scion's libSystem.
 * Built only on public pthread/malloc APIs. Written from the public Block ABI spec and the
 * libdispatch API contract; queues are FIFO lists drained by a worker pool. */
#include <stdint.h>
#include <stddef.h>

typedef uint64_t pthread_mutex_t[8];
typedef uint64_t pthread_cond_t[6];
void *malloc(size_t); void free(void *); void *calloc(size_t, size_t);
void *memmove(void *, const void *, size_t); void *memcpy(void *, const void *, size_t);
int pthread_mutex_lock(void *); int pthread_mutex_unlock(void *);
int pthread_cond_wait(void *, void *); int pthread_cond_signal(void *); int pthread_cond_broadcast(void *);
struct timespec { int64_t tv_sec, tv_nsec; };
int pthread_cond_timedwait_relative_np(void *, void *, const struct timespec *);
int pthread_create(void **, const void *, void *(*)(void *), void *);
uint64_t mach_absolute_time(void);
long sysconf(int);
void *pthread_self(void);

/* ===================================================================== Blocks */
enum {
    BLOCK_DEALLOCATING = 0x0001, BLOCK_REFCOUNT_MASK = 0xfffe, BLOCK_NEEDS_FREE = 1 << 24,
    BLOCK_HAS_COPY_DISPOSE = 1 << 25, BLOCK_IS_GLOBAL = 1 << 28, BLOCK_BYREF_LAYOUT_EXTENDED = 1 << 28,
    BLOCK_FIELD_IS_OBJECT = 3, BLOCK_FIELD_IS_BLOCK = 7, BLOCK_FIELD_IS_BYREF = 8, BLOCK_FIELD_IS_WEAK = 16,
    BLOCK_BYREF_CALLER = 128,
};
struct Block_descriptor { uint64_t reserved, size; void (*copy)(void *, const void *); void (*dispose)(const void *); };
struct Block_layout { void *isa; volatile int32_t flags; int32_t reserved; void (*invoke)(void *, ...); struct Block_descriptor *descriptor; };
struct Block_byref { void *isa; struct Block_byref *forwarding; volatile int32_t flags; uint32_t size;
                     void (*keep)(struct Block_byref *, struct Block_byref *); void (*destroy)(struct Block_byref *); };

void *_NSConcreteStackBlock[32], *_NSConcreteMallocBlock[32], *_NSConcreteGlobalBlock[32];
void *_NSConcreteAutoBlock[32], *_NSConcreteFinalizingBlock[32], *_NSConcreteWeakBlockVariable[32];

/* libobjc installs retain/release for captured objects (same entry point Apple's runtime uses) */
struct Block_callbacks_RR { size_t size; void (*retain)(const void *); void (*release)(const void *); void (*destructInstance)(const void *); };
static void nop_obj(const void *o) {}
static void (*retain_obj)(const void *) = nop_obj, (*release_obj)(const void *) = nop_obj;
void _Block_use_RR2(const struct Block_callbacks_RR *cb) { retain_obj = cb->retain; release_obj = cb->release; }

static void latch_incr(volatile int32_t *f) {
    int32_t old = *f;
    while ((old & BLOCK_REFCOUNT_MASK) != BLOCK_REFCOUNT_MASK &&
           !__atomic_compare_exchange_n(f, &old, old + 2, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) ;
}
static int latch_decr(volatile int32_t *f) { /* 1 when the count reached zero */
    int32_t old = *f;
    for (;;) {
        if ((old & BLOCK_REFCOUNT_MASK) == BLOCK_REFCOUNT_MASK) return 0;
        if ((old & BLOCK_REFCOUNT_MASK) == 0) return 0;
        int32_t nw = (old & BLOCK_REFCOUNT_MASK) == 2 ? ((old - 2) | BLOCK_DEALLOCATING) : old - 2;
        if (__atomic_compare_exchange_n(f, &old, nw, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) return (old & BLOCK_REFCOUNT_MASK) == 2;
    }
}
void *_Block_copy(const void *arg) {
    struct Block_layout *b = (struct Block_layout *)arg;
    if (!b) return 0;
    if (b->flags & BLOCK_NEEDS_FREE) { latch_incr(&b->flags); return b; }
    if (b->flags & BLOCK_IS_GLOBAL) return b;
    struct Block_layout *r = malloc(b->descriptor->size);
    if (!r) return 0;
    memmove(r, b, b->descriptor->size);
    r->flags &= ~(BLOCK_REFCOUNT_MASK | BLOCK_DEALLOCATING);
    r->flags |= BLOCK_NEEDS_FREE | 2;
    r->isa = _NSConcreteMallocBlock;
    if (b->flags & BLOCK_HAS_COPY_DISPOSE) b->descriptor->copy(r, b);
    return r;
}
void _Block_release(const void *arg) {
    struct Block_layout *b = (struct Block_layout *)arg;
    if (!b || (b->flags & BLOCK_IS_GLOBAL) || !(b->flags & BLOCK_NEEDS_FREE)) return;
    if (latch_decr(&b->flags)) {
        if (b->flags & BLOCK_HAS_COPY_DISPOSE) b->descriptor->dispose(b);
        free(b);
    }
}
static struct Block_byref *byref_copy(struct Block_byref *src) {
    if ((src->forwarding->flags & BLOCK_REFCOUNT_MASK) == 0) { /* still on the stack: move to the heap */
        struct Block_byref *c = malloc(src->size);
        c->isa = 0;
        c->flags = src->flags | BLOCK_NEEDS_FREE | 4; /* one for the caller, one for the stack */
        c->forwarding = c; src->forwarding = c; c->size = src->size;
        if (src->flags & BLOCK_HAS_COPY_DISPOSE) {
            c->keep = src->keep; c->destroy = src->destroy;
            size_t hdr = sizeof *c;
            if (src->flags & BLOCK_BYREF_LAYOUT_EXTENDED) { ((void **)(c + 1))[0] = ((void **)(src + 1))[0]; hdr += 8; }
            (void)hdr;
            src->keep(c, src);
        } else memmove(&c->keep, &src->keep, src->size - 24);
    } else if (src->forwarding->flags & BLOCK_NEEDS_FREE) latch_incr(&src->forwarding->flags);
    return src->forwarding;
}
static void byref_release(struct Block_byref *b) {
    b = b->forwarding;
    if (!(b->flags & BLOCK_NEEDS_FREE)) return;
    if (latch_decr(&b->flags)) { if (b->flags & BLOCK_HAS_COPY_DISPOSE) b->destroy(b); free(b); }
}
void _Block_object_assign(void *dst, const void *obj, int flags) {
    switch (flags & (BLOCK_FIELD_IS_OBJECT | BLOCK_FIELD_IS_BLOCK | BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK | BLOCK_BYREF_CALLER)) {
    case BLOCK_FIELD_IS_OBJECT: retain_obj(obj); *(const void **)dst = obj; break;
    case BLOCK_FIELD_IS_BLOCK: *(void **)dst = _Block_copy(obj); break;
    case BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK:
    case BLOCK_FIELD_IS_BYREF: *(void **)dst = byref_copy((struct Block_byref *)obj); break;
    default: *(const void **)dst = obj; break; /* BYREF_CALLER variants: plain assignment */
    }
}
void _Block_object_dispose(const void *obj, int flags) {
    switch (flags & (BLOCK_FIELD_IS_OBJECT | BLOCK_FIELD_IS_BLOCK | BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK | BLOCK_BYREF_CALLER)) {
    case BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK:
    case BLOCK_FIELD_IS_BYREF: byref_release((struct Block_byref *)obj); break;
    case BLOCK_FIELD_IS_BLOCK: _Block_release(obj); break;
    case BLOCK_FIELD_IS_OBJECT: release_obj(obj); break;
    default: break;
    }
}
static void call_block(void *b) { ((void (*)(void *))((struct Block_layout *)b)->invoke)(b); }

/* ===================================================================== libdispatch */
typedef void (*dfunc)(void *);
struct ditem { dfunc fn; void *ctx; struct ditem *next; };
/* Every dispatch object starts with an isa: libobjc copies its OS_dispatch_object class here, so ARC code can
 * objc_retain/objc_release queues, groups and semaphores (as on macOS, where they are Objective-C objects). */
void *_dispatch_object_class[32];
/* The Objective-C class of each kind of object (OS_dispatch_queue, ...), set by libobjc when it loads: Swift casts
 * (a source to DispatchSourceTimer) look at the real class. Until then, the copy above. */
enum { DK_QUEUE, DK_GROUP, DK_SEMAPHORE, DK_SOURCE, DK_DATA, DK_IO, DK_ATTR, DK_COUNT };
static void *dk_class[DK_COUNT];
void *_scion_dispatch_isa(int k) { return dk_class[k] ? dk_class[k] : (void *)_dispatch_object_class; }
#define ISA(k) _scion_dispatch_isa(DK_##k)
struct dqueue {
    void *isa; const char *label; int serial, running, is_main, refs;
    pthread_mutex_t lock; struct ditem *head, *tail;
};
/* set by AppKit: wakes the main thread when it sleeps in the event loop */
void (*_scion_main_wake)(void);
void (*_scion_main_rl_wake)(void);   /* Foundation: the main NSRunLoop */
static pthread_cond_t main_cv;   /* zero = initialized, as pool_cv */
struct dqueue _dispatch_main_q = {_dispatch_object_class, "com.apple.main-thread", 1, 0, 1, 1};
struct dqueue_attr { void *isa; int concurrent; } _dispatch_queue_attr_concurrent = {_dispatch_object_class, 1};
static struct dqueue global_q[6] = {
    {_dispatch_object_class, "com.apple.root.default-qos", 0}, {_dispatch_object_class, "com.apple.root.user-interactive-qos", 0},
    {_dispatch_object_class, "com.apple.root.user-initiated-qos", 0}, {_dispatch_object_class, "com.apple.root.utility-qos", 0},
    {_dispatch_object_class, "com.apple.root.background-qos", 0}, {_dispatch_object_class, "com.apple.root.low-qos", 0},
};

/* worker pool: one shared FIFO */
static pthread_mutex_t pool_lock; static pthread_cond_t pool_cv;
static struct ditem *pool_head, *pool_tail;
static int pool_threads, pool_idle, pool_len; static unsigned long pool_taken;
static void *worker(void *a) {
    for (;;) {
        pthread_mutex_lock(&pool_lock);
        while (!pool_head) { pool_idle++; pthread_cond_wait(&pool_cv, &pool_lock); pool_idle--; }
        struct ditem *it = pool_head; pool_head = it->next; if (!pool_head) pool_tail = 0; pool_len--; pool_taken++;
        pthread_mutex_unlock(&pool_lock);
        it->fn(it->ctx);
        free(it);
    }
    return a;
}
/* like GCD's overcommit: if work is queued but nothing was dequeued for 20 ms (every worker blocked, e.g. waiting
 * for another queued item), add a worker, up to 256 */
int usleep(uint32_t);
static int watchdog_on;
static void *watchdog(void *a) {
    unsigned long last = 0;
    for (;;) {
        usleep(20000);
        pthread_mutex_lock(&pool_lock);
        if (pool_len && !pool_idle && pool_taken == last && pool_threads < 256) { void *t; pool_threads++; pthread_create(&t, 0, worker, 0); }
        last = pool_taken;
        pthread_mutex_unlock(&pool_lock);
    }
    return a;
}
static void pool_push(dfunc fn, void *ctx) {
    struct ditem *it = malloc(sizeof *it); it->fn = fn; it->ctx = ctx; it->next = 0;
    pthread_mutex_lock(&pool_lock);
    if (pool_tail) pool_tail->next = it; else pool_head = it;
    pool_tail = it;
    pool_len++;
    long ncpu = sysconf(58); if (ncpu < 2) ncpu = 2;
    if (pool_len > pool_idle && pool_threads < ncpu * 2) { void *t; pool_threads++; pthread_create(&t, 0, worker, 0); }
    if (!watchdog_on) { void *t; watchdog_on = 1; pthread_create(&t, 0, watchdog, 0); }
    pthread_cond_signal(&pool_cv);
    pthread_mutex_unlock(&pool_lock);
}
/* the serial queue (or the main queue) whose item this thread is running. ponytail: not tracked on concurrent queues */
int pthread_key_create(unsigned long *, void (*)(void *)); void *pthread_getspecific(unsigned long); int pthread_setspecific(unsigned long, const void *);
static unsigned long cur_key; static long cur_once;
static void cur_key_init(void *u) { pthread_key_create(&cur_key, 0); }
void dispatch_once_f(volatile long *pred, void *ctx, dfunc fn);
static void set_current(struct dqueue *q) { dispatch_once_f(&cur_once, 0, cur_key_init); pthread_setspecific(cur_key, q); }
static void drain(void *qp) { /* runs a serial queue's items one at a time on a worker */
    struct dqueue *q = qp;
    set_current(q);
    for (;;) {
        pthread_mutex_lock(&q->lock);
        struct ditem *it = q->head;
        if (!it) { q->running = 0; pthread_mutex_unlock(&q->lock); set_current(0); return; }
        q->head = it->next; if (!q->head) q->tail = 0;
        pthread_mutex_unlock(&q->lock);
        it->fn(it->ctx);
        free(it);
    }
}
void dispatch_async_f(struct dqueue *q, void *ctx, dfunc fn) {
    if (!q->serial) { pool_push(fn, ctx); return; }
    struct ditem *it = malloc(sizeof *it); it->fn = fn; it->ctx = ctx; it->next = 0;
    pthread_mutex_lock(&q->lock);
    if (q->tail) q->tail->next = it; else q->head = it;
    q->tail = it;
    int start = !q->running && !q->is_main;
    if (start) q->running = 1;
    pthread_mutex_unlock(&q->lock);
    if (start) pool_push(drain, q);
    if (q->is_main) {
        pthread_mutex_lock(&q->lock); pthread_cond_broadcast(&main_cv); pthread_mutex_unlock(&q->lock);   /* dispatch_main */
        if (_scion_main_rl_wake) _scion_main_rl_wake();
        if (_scion_main_wake) _scion_main_wake();
    }
}
static void run_and_release(void *b) { call_block(b); _Block_release(b); }
void dispatch_async(struct dqueue *q, void *block) { dispatch_async_f(q, _Block_copy(block), run_and_release); }
void dispatch_barrier_async(struct dqueue *q, void *block) { dispatch_async(q, block); } /* ponytail: concurrent barriers are not ordered */

/* main queue: drained by whoever runs the main run loop (dispatch_main, CFRunLoopRun, NSApplication) */
int _scion_dispatch_drain_main(void) {
    int n = 0;
    for (;;) {
        pthread_mutex_lock(&_dispatch_main_q.lock);
        struct ditem *it = _dispatch_main_q.head;
        if (it) { _dispatch_main_q.head = it->next; if (!_dispatch_main_q.head) _dispatch_main_q.tail = 0; }
        pthread_mutex_unlock(&_dispatch_main_q.lock);
        if (!it) return n;
        set_current(&_dispatch_main_q); it->fn(it->ctx); set_current(0); free(it); n++;
    }
}
void dispatch_main(void) {
    for (;;) {
        _scion_dispatch_drain_main();
        pthread_mutex_lock(&_dispatch_main_q.lock);
        while (!_dispatch_main_q.head) pthread_cond_wait(&main_cv, &_dispatch_main_q.lock);
        pthread_mutex_unlock(&_dispatch_main_q.lock);
    }
}

struct sync_ctx { dfunc fn; void *ctx; pthread_mutex_t m; pthread_cond_t cv; int done; };
static void sync_tramp(void *p) {
    struct sync_ctx *s = p; s->fn(s->ctx);
    pthread_mutex_lock(&s->m); s->done = 1; pthread_cond_signal(&s->cv); pthread_mutex_unlock(&s->m);
}
void dispatch_sync_f(struct dqueue *q, void *ctx, dfunc fn) {
    if (!q->serial) { fn(ctx); return; }
    if (!q->is_main) { /* like GCD: an idle serial queue runs the block on the calling thread (no worker needed) */
        pthread_mutex_lock(&q->lock);
        if (!q->running && !q->head) {
            q->running = 1; pthread_mutex_unlock(&q->lock);
            dispatch_once_f(&cur_once, 0, cur_key_init);
            void *prev = pthread_getspecific(cur_key);
            set_current(q); fn(ctx); set_current(prev);
            pthread_mutex_lock(&q->lock);
            int more = q->head != 0; if (!more) q->running = 0;
            pthread_mutex_unlock(&q->lock);
            if (more) pool_push(drain, q); /* items queued meanwhile: the queue stays running for them */
            return;
        }
        pthread_mutex_unlock(&q->lock);
    }
    struct sync_ctx s = {fn, ctx};
    dispatch_async_f(q, &s, sync_tramp);
    pthread_mutex_lock(&s.m); while (!s.done) pthread_cond_wait(&s.cv, &s.m); pthread_mutex_unlock(&s.m);
}
void dispatch_sync(struct dqueue *q, void *block) { dispatch_sync_f(q, block, call_block); }
void dispatch_barrier_sync(struct dqueue *q, void *block) { dispatch_sync(q, block); }

struct dqueue *dispatch_get_global_queue(long id, unsigned long flags) {
    switch (id) { case 0x21: return &global_q[1]; case 0x19: case 2: return &global_q[2]; case 0x11: case -2: return &global_q[3];
                  case 0x09: case (long)-32768: return &global_q[4]; }
    return &global_q[0];
}
struct dqueue *dispatch_queue_create(const char *label, struct dqueue_attr *attr) {
    struct dqueue *q = calloc(1, sizeof *q);
    q->isa = ISA(QUEUE); q->label = label; q->serial = !(attr && attr->concurrent); q->refs = 1;
    return q;
}
struct dqueue *dispatch_queue_create_with_target(const char *l, struct dqueue_attr *a, void *t) { return dispatch_queue_create(l, a); }
struct dqueue_attr *dispatch_queue_attr_make_with_qos_class(struct dqueue_attr *a, int qos, int prio) { return a; }
struct dqueue_attr *dispatch_queue_attr_make_initially_inactive(struct dqueue_attr *a) { return a; }
const char *dispatch_queue_get_label(struct dqueue *q) { return q ? q->label : "com.apple.main-thread"; }
struct dqueue *dispatch_get_current_queue(void) { return &global_q[0]; }
void dispatch_set_target_queue(void *o, void *q) {}
void dispatch_retain(void *o) {}
void dispatch_release(void *o) {} /* ponytail: dispatch objects are never freed */

/* once */
void dispatch_once_f(volatile long *pred, void *ctx, dfunc fn) {
    if (*pred == ~0l) return;
    long z = 0;
    if (__atomic_compare_exchange_n(pred, &z, 1, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) { fn(ctx); __atomic_store_n(pred, ~0l, __ATOMIC_RELEASE); return; }
    while (__atomic_load_n(pred, __ATOMIC_ACQUIRE) != ~0l) usleep(10);
}
void dispatch_once(volatile long *pred, void *block) { dispatch_once_f(pred, block, call_block); }

/* time: nanoseconds on the mach_absolute_time clock (timebase 1/1); wall-clock times are negative in libdispatch */
uint64_t dispatch_time(uint64_t when, int64_t delta) {
    if (when == ~0ull) return when;
    uint64_t base = when ? when : mach_absolute_time();
    return base + (uint64_t)delta;
}
uint64_t dispatch_walltime(const struct timespec *ts, int64_t delta) { return dispatch_time(0, delta); }

/* after: a timer thread with a sorted list */
struct timer { uint64_t when; struct dqueue *q; void *ctx; dfunc fn; struct timer *next; };
static pthread_mutex_t tlock; static pthread_cond_t tcv; static struct timer *timers; static int timer_started;
static void *timer_thread(void *a) {
    pthread_mutex_lock(&tlock);
    for (;;) {
        if (!timers) { pthread_cond_wait(&tcv, &tlock); continue; }
        uint64_t now = mach_absolute_time();
        if (timers->when <= now) {
            struct timer *t = timers; timers = t->next;
            pthread_mutex_unlock(&tlock);
            if (t->q) dispatch_async_f(t->q, t->ctx, t->fn); else t->fn(t->ctx); /* no queue: on this thread */
            free(t);
            pthread_mutex_lock(&tlock);
            continue;
        }
        uint64_t d = timers->when - now;
        struct timespec ts = {(int64_t)(d / 1000000000), (int64_t)(d % 1000000000)};
        pthread_cond_timedwait_relative_np(&tcv, &tlock, &ts);
    }
    return a;
}
void dispatch_after_f(uint64_t when, struct dqueue *q, void *ctx, dfunc fn) {
    if (when == ~0ull) return;
    if ((int64_t)when < 0) when = mach_absolute_time(); /* ponytail: wall-clock deadlines (dispatch_walltime) count from now */
    struct timer *t = malloc(sizeof *t); t->when = when; t->q = q; t->ctx = ctx; t->fn = fn;
    pthread_mutex_lock(&tlock);
    if (!timer_started) { void *th; timer_started = 1; pthread_create(&th, 0, timer_thread, 0); }
    struct timer **p = &timers; while (*p && (*p)->when <= when) p = &(*p)->next;
    t->next = *p; *p = t;
    pthread_cond_signal(&tcv);
    pthread_mutex_unlock(&tlock);
}
void dispatch_after(uint64_t when, struct dqueue *q, void *block) { dispatch_after_f(when, q, _Block_copy(block), run_and_release); }

/* apply: ponytail: sequential on the caller thread */
void dispatch_apply_f(size_t n, struct dqueue *q, void *ctx, void (*fn)(void *, size_t)) { for (size_t i = 0; i < n; i++) fn(ctx, i); }
void dispatch_apply(size_t n, struct dqueue *q, void *block) {
    for (size_t i = 0; i < n; i++) ((void (*)(void *, size_t))((struct Block_layout *)block)->invoke)(block, i);
}

/* groups */
struct dgroup { void *isa; pthread_mutex_t m; pthread_cond_t cv; long count; struct timer *notify; };
struct dgroup *dispatch_group_create(void) { struct dgroup *g = calloc(1, sizeof(struct dgroup)); if (g) g->isa = ISA(GROUP); return g; }
void dispatch_group_enter(struct dgroup *g) { pthread_mutex_lock(&g->m); g->count++; pthread_mutex_unlock(&g->m); }
void dispatch_group_leave(struct dgroup *g) {
    pthread_mutex_lock(&g->m);
    struct timer *n = 0;
    if (--g->count == 0) { n = g->notify; g->notify = 0; pthread_cond_broadcast(&g->cv); }
    pthread_mutex_unlock(&g->m);
    while (n) { struct timer *x = n->next; dispatch_async_f(n->q, n->ctx, n->fn); free(n); n = x; }
}
long dispatch_group_wait(struct dgroup *g, uint64_t timeout) {
    pthread_mutex_lock(&g->m);
    while (g->count > 0) {
        if (timeout == ~0ull) { pthread_cond_wait(&g->cv, &g->m); continue; }
        uint64_t now = mach_absolute_time();
        if (timeout <= now) { pthread_mutex_unlock(&g->m); return 1; }
        uint64_t d = timeout - now; struct timespec ts = {(int64_t)(d / 1000000000), (int64_t)(d % 1000000000)};
        pthread_cond_timedwait_relative_np(&g->cv, &g->m, &ts);
    }
    pthread_mutex_unlock(&g->m);
    return 0;
}
void dispatch_group_notify_f(struct dgroup *g, struct dqueue *q, void *ctx, dfunc fn) {
    pthread_mutex_lock(&g->m);
    if (g->count == 0) { pthread_mutex_unlock(&g->m); dispatch_async_f(q, ctx, fn); return; }
    struct timer *t = malloc(sizeof *t); t->q = q; t->ctx = ctx; t->fn = fn; t->next = g->notify; g->notify = t;
    pthread_mutex_unlock(&g->m);
}
void dispatch_group_notify(struct dgroup *g, struct dqueue *q, void *block) { dispatch_group_notify_f(g, q, _Block_copy(block), run_and_release); }
struct group_job { struct dgroup *g; void *ctx; dfunc fn; };
static void group_tramp(void *p) { struct group_job *j = p; j->fn(j->ctx); dispatch_group_leave(j->g); free(j); }
void dispatch_group_async_f(struct dgroup *g, struct dqueue *q, void *ctx, dfunc fn) {
    struct group_job *j = malloc(sizeof *j); j->g = g; j->ctx = ctx; j->fn = fn;
    dispatch_group_enter(g);
    dispatch_async_f(q, j, group_tramp);
}
void dispatch_group_async(struct dgroup *g, struct dqueue *q, void *block) { dispatch_group_async_f(g, q, _Block_copy(block), run_and_release); }

/* ===================================================================== sources
 * Timers ride the timer thread; data sources merge on the caller; signal sources count in an async-safe handler that
 * a poller (every 10 ms) turns into events. The event handler runs on the target queue, one delivery at a time, with
 * the data coalesced (dispatch_source_get_data). READ and WRITE sources ride a kqueue (below). PROC/VNODE/MACH/
 * MEMORYPRESSURE sources never fire.
 * dispatch_suspend/resume work on sources; on queues they are ignored (ponytail). */
struct dispatch_source_type_s { int kind; };
enum { SRC_ADD = 1, SRC_OR, SRC_REPLACE, SRC_TIMER, SRC_SIGNAL, SRC_INERT, SRC_READ, SRC_WRITE };
const struct dispatch_source_type_s _dispatch_source_type_data_add = {SRC_ADD}, _dispatch_source_type_data_or = {SRC_OR},
    _dispatch_source_type_data_replace = {SRC_REPLACE}, _dispatch_source_type_timer = {SRC_TIMER}, _dispatch_source_type_signal = {SRC_SIGNAL},
    _dispatch_source_type_read = {SRC_READ}, _dispatch_source_type_write = {SRC_WRITE}, _dispatch_source_type_proc = {SRC_INERT},
    _dispatch_source_type_vnode = {SRC_INERT}, _dispatch_source_type_mach_send = {SRC_INERT}, _dispatch_source_type_mach_recv = {SRC_INERT},
    _dispatch_source_type_memorypressure = {SRC_INERT};
#define SRC_MAGIC 0x6d77737263ull /* "mwsrc": tells a source from a queue in the generic calls */
struct dsource {
    void *isa; uint64_t magic; int kind;
    struct dqueue *q; uintptr_t handle; unsigned long mask;
    pthread_mutex_t m;
    void *handler, *cancel_handler, *reg_handler; int handler_is_f, cancel_is_f, reg_is_f; /* blocks, or functions (_f) */
    void *ctx;
    unsigned long data, last;          /* pending data; data seen by the running handler */
    int suspend, pending, canceled, cancel_done, activated;
    uint64_t start, interval; unsigned gen;
    struct dsource *next_signal;
    int always;                        /* READ/WRITE on a descriptor the kqueue cannot watch: always ready */
};
static int is_source(void *o) { return o && ((struct dsource *)o)->magic == SRC_MAGIC; }
static void src_call(struct dsource *s, void *h, int is_f) {
    if (!h) return;
    if (is_f) ((dfunc)h)(s->ctx); else call_block(h);
}
static void src_deliver(void *p);
static void fd_rearm(struct dsource *s);
static void src_signal(struct dsource *s) { /* call with s->m held */
    if (!s->data || s->suspend || s->canceled || s->pending || !s->handler) return;
    s->pending = 1;
    dispatch_async_f(s->q, s, src_deliver);
}
static void src_deliver(void *p) {
    struct dsource *s = p;
    pthread_mutex_lock(&s->m);
    s->last = s->data; s->data = 0;
    void *h = s->handler; int f = s->handler_is_f, skip = s->canceled;
    pthread_mutex_unlock(&s->m);
    if (!skip) src_call(s, h, f);
    pthread_mutex_lock(&s->m);
    s->pending = 0;
    src_signal(s);
    int rearm = (s->kind == SRC_READ || s->kind == SRC_WRITE) && !s->canceled;
    pthread_mutex_unlock(&s->m);
    if (rearm) fd_rearm(s);
}
static void src_reg_run(void *p) { struct dsource *s = p; src_call(s, s->reg_handler, s->reg_is_f); }
static void src_cancel_run(void *p) { struct dsource *s = p; src_call(s, s->cancel_handler, s->cancel_is_f); }
static void src_maybe_cancel(struct dsource *s) { /* with s->m held: the cancel handler runs once, when not suspended */
    if (s->canceled && !s->cancel_done && !s->suspend) { s->cancel_done = 1; if (s->cancel_handler) dispatch_async_f(s->q, s, src_cancel_run); }
}

/* timers */
struct tfire { struct dsource *s; unsigned gen; uint64_t when; };
static void src_timer_fire(void *p);
static void src_timer_arm(struct dsource *s, uint64_t when) { /* with s->m held */
    struct tfire *f = malloc(sizeof *f); f->s = s; f->gen = s->gen; f->when = when;
    dispatch_after_f(when, 0, f, src_timer_fire);
}
static void src_timer_fire(void *p) {
    struct tfire *f = p; struct dsource *s = f->s;
    pthread_mutex_lock(&s->m);
    if (f->gen == s->gen && !s->canceled) {
        uint64_t now = mach_absolute_time();
        s->data++;
        if (s->interval && s->interval != ~0ull) {
            uint64_t next = f->when + s->interval;
            if (next <= now) { uint64_t missed = (now - next) / s->interval + 1; s->data += missed; next += missed * s->interval; }
            src_timer_arm(s, next);
        }
        src_signal(s);
    }
    pthread_mutex_unlock(&s->m);
    free(f);
}

/* signals: counted by the handler, delivered by a poller */
static volatile long sig_count[32];
static struct dsource *sig_sources; static pthread_mutex_t sig_lock; static int sig_poller;
struct dsigaction_ { uint64_t handler; uint32_t mask; int32_t flags; };
int sigaction(int, const struct dsigaction_ *, struct dsigaction_ *);
int usleep(uint32_t);
static void sig_handler(int sig) { if (sig > 0 && sig < 32) __atomic_add_fetch(&sig_count[sig], 1, __ATOMIC_RELAXED); }
static void *sig_poll(void *a) {
    for (;;) {
        usleep(10000);
        pthread_mutex_lock(&sig_lock);
        for (int sig = 1; sig < 32; sig++) {
            long n = __atomic_exchange_n(&sig_count[sig], 0, __ATOMIC_RELAXED);
            if (!n) continue;
            for (struct dsource *s = sig_sources; s; s = s->next_signal)
                if ((int)s->handle == sig) { pthread_mutex_lock(&s->m); s->data += (unsigned long)n; src_signal(s); pthread_mutex_unlock(&s->m); }
        }
        pthread_mutex_unlock(&sig_lock);
    }
    return a;
}

/* descriptors: one kqueue for every READ and WRITE source, waited on by a thread. A registration is EV_DISPATCH: reported
 * once, then enabled again after the handler has run, so a source fires as long as its descriptor stays ready (as in
 * libdispatch) without the thread spinning meanwhile. The data is what kevent says: bytes to read, or room to write. */
struct dkev { uint64_t ident; int16_t filter; uint16_t flags; uint32_t fflags; int64_t data; uint64_t udata; };
int kqueue(void); int kevent(int, const struct dkev *, int, struct dkev *, int, const struct timespec *);
enum { KF_READ = -1, KF_WRITE = -2, KV_ADD = 1, KV_DELETE = 2, KV_ENABLE = 4, KV_DISPATCH = 0x80, KV_ERROR = 0x4000 };
static int fd_kq = -1; static pthread_mutex_t fd_lock;
static void *fd_watch(void *a) {
    struct dkev ev[16];
    for (;;) {
        int n = kevent(fd_kq, 0, 0, ev, 16, 0);
        for (int i = 0; i < n; i++) {
            struct dsource *s = (struct dsource *)(uintptr_t)ev[i].udata;
            if (!s || (ev[i].flags & KV_ERROR)) continue;
            pthread_mutex_lock(&s->m);
            if (!s->canceled) { s->data += ev[i].data > 0 ? (unsigned long)ev[i].data : 1; src_signal(s); }
            pthread_mutex_unlock(&s->m);
        }
    }
    return a;
}
static void fd_always(void *p) {   /* a descriptor kqueue cannot watch: ready again a moment after each delivery */
    struct dsource *s = p;
    pthread_mutex_lock(&s->m);
    if (!s->canceled) { s->data += 1; src_signal(s); }
    pthread_mutex_unlock(&s->m);
}
static int fd_change(struct dsource *s, int flags) {
    struct dkev c = {s->handle, (int16_t)(s->kind == SRC_READ ? KF_READ : KF_WRITE), (uint16_t)flags, 0, 0, (uint64_t)(uintptr_t)s};
    return kevent(fd_kq, &c, 1, 0, 0, 0);
}
static void fd_register(struct dsource *s) {   /* on activation */
    pthread_mutex_lock(&fd_lock);
    if (fd_kq < 0 && (fd_kq = kqueue()) >= 0) { void *t; pthread_create(&t, 0, fd_watch, 0); }
    pthread_mutex_unlock(&fd_lock);
    if (fd_kq < 0 || fd_change(s, KV_ADD | KV_DISPATCH) < 0) { s->always = 1; dispatch_async_f(s->q, s, fd_always); }
}
static void fd_rearm(struct dsource *s) {
    if (s->always) dispatch_after_f(dispatch_time(0, 1000000), s->q, s, fd_always);
    else fd_change(s, KV_ENABLE | KV_DISPATCH);
}

struct dsource *dispatch_source_create(const struct dispatch_source_type_s *type, uintptr_t handle, unsigned long mask, struct dqueue *q) {
    if (!type) return 0;
    struct dsource *s = calloc(1, sizeof *s);
    s->isa = ISA(SOURCE); s->magic = SRC_MAGIC; s->kind = type->kind;
    s->q = q ? q : &global_q[0]; s->handle = handle; s->mask = mask; s->suspend = 1; /* created inactive */
    s->start = ~0ull;
    if (s->kind == SRC_SIGNAL) {
        if (handle == 0 || handle >= 32) { free(s); return 0; }
        pthread_mutex_lock(&sig_lock);
        s->next_signal = sig_sources; sig_sources = s;
        if (!sig_poller) { void *t; sig_poller = 1; pthread_create(&t, 0, sig_poll, 0); }
        pthread_mutex_unlock(&sig_lock);
        struct dsigaction_ act = {(uint64_t)(uintptr_t)sig_handler, 0, 0x0002 /* SA_RESTART */};
        sigaction((int)handle, &act, 0); /* ponytail: replaces the disposition (libdispatch observes signals without taking them) */
    }
    return s;
}
static void set_handler(struct dsource *s, void **slot, int *is_f, void *h, int f) {
    pthread_mutex_lock(&s->m);
    if (*slot && !*is_f) _Block_release(*slot);
    *slot = h ? (f ? h : _Block_copy(h)) : 0; *is_f = f;
    if (slot == &s->handler) src_signal(s);
    pthread_mutex_unlock(&s->m);
}
void dispatch_source_set_event_handler(struct dsource *s, void *b) { set_handler(s, &s->handler, &s->handler_is_f, b, 0); }
void dispatch_source_set_event_handler_f(struct dsource *s, dfunc f) { set_handler(s, &s->handler, &s->handler_is_f, (void *)f, 1); }
void dispatch_source_set_cancel_handler(struct dsource *s, void *b) { set_handler(s, &s->cancel_handler, &s->cancel_is_f, b, 0); }
void dispatch_source_set_cancel_handler_f(struct dsource *s, dfunc f) { set_handler(s, &s->cancel_handler, &s->cancel_is_f, (void *)f, 1); }
void dispatch_source_set_registration_handler(struct dsource *s, void *b) { set_handler(s, &s->reg_handler, &s->reg_is_f, b, 0); }
void dispatch_source_set_registration_handler_f(struct dsource *s, dfunc f) { set_handler(s, &s->reg_handler, &s->reg_is_f, (void *)f, 1); }
void dispatch_source_set_timer(struct dsource *s, uint64_t start, uint64_t interval, uint64_t leeway) {
    if (!s || s->kind != SRC_TIMER) return;
    pthread_mutex_lock(&s->m);
    s->gen++; s->data = 0;
    s->start = start == 0 ? mach_absolute_time() : (int64_t)start < 0 && start != ~0ull ? mach_absolute_time() : start;
    s->interval = interval;
    if (s->activated && s->start != ~0ull) src_timer_arm(s, s->start);
    pthread_mutex_unlock(&s->m);
}
void dispatch_source_merge_data(struct dsource *s, unsigned long v) {
    if (!s) return;
    pthread_mutex_lock(&s->m);
    if (s->kind == SRC_OR) s->data |= v; else if (s->kind == SRC_REPLACE) s->data = v; else s->data += v;
    src_signal(s);
    pthread_mutex_unlock(&s->m);
}
void dispatch_source_cancel(struct dsource *s) {
    if (!s) return;
    pthread_mutex_lock(&s->m);
    int was = s->canceled;
    if (!s->canceled) { s->canceled = 1; s->gen++; src_maybe_cancel(s); }
    pthread_mutex_unlock(&s->m);
    if (!was && (s->kind == SRC_READ || s->kind == SRC_WRITE) && s->activated && !s->always) fd_change(s, KV_DELETE);
    if (s->kind == SRC_SIGNAL) {
        pthread_mutex_lock(&sig_lock);
        for (struct dsource **p = &sig_sources; *p; p = &(*p)->next_signal) if (*p == s) { *p = s->next_signal; break; }
        pthread_mutex_unlock(&sig_lock);
    }
}
long dispatch_source_testcancel(struct dsource *s) { return s && s->canceled; }
unsigned long dispatch_source_get_data(struct dsource *s) { return s ? s->last : 0; }
uintptr_t dispatch_source_get_handle(struct dsource *s) { return s ? s->handle : 0; }
unsigned long dispatch_source_get_mask(struct dsource *s) { return s ? s->mask : 0; }

/* generic object calls */
void dispatch_resume(void *o) {
    if (!is_source(o)) return;
    struct dsource *s = o;
    pthread_mutex_lock(&s->m);
    if (s->suspend > 0 && --s->suspend == 0) {
        if (!s->activated) {
            s->activated = 1;
            if (s->reg_handler) dispatch_async_f(s->q, s, src_reg_run);
            if (s->kind == SRC_TIMER && s->start != ~0ull && !s->canceled) src_timer_arm(s, s->start);
            if ((s->kind == SRC_READ || s->kind == SRC_WRITE) && !s->canceled) { pthread_mutex_unlock(&s->m); fd_register(s); pthread_mutex_lock(&s->m); }
        }
        src_signal(s);
        src_maybe_cancel(s);
    }
    pthread_mutex_unlock(&s->m);
}
void dispatch_activate(void *o) { if (is_source(o) && !((struct dsource *)o)->activated) dispatch_resume(o); }
void dispatch_suspend(void *o) {
    if (!is_source(o)) return;
    struct dsource *s = o;
    pthread_mutex_lock(&s->m); s->suspend++; pthread_mutex_unlock(&s->m);
}
/* contexts of other objects (queues, groups...): a small list (rarely used) */
struct octx { void *o, *c; struct octx *next; };
static struct octx *octxs; static pthread_mutex_t octx_lock;
void dispatch_set_context(void *o, void *c) {
    if (!o) return;
    if (is_source(o)) { ((struct dsource *)o)->ctx = c; return; }
    pthread_mutex_lock(&octx_lock);
    struct octx *x = octxs;
    while (x && x->o != o) x = x->next;
    if (!x) { x = calloc(1, sizeof *x); x->o = o; x->next = octxs; octxs = x; }
    x->c = c;
    pthread_mutex_unlock(&octx_lock);
}
void *dispatch_get_context(void *o) {
    if (!o) return 0;
    if (is_source(o)) return ((struct dsource *)o)->ctx;
    pthread_mutex_lock(&octx_lock);
    struct octx *x = octxs;
    while (x && x->o != o) x = x->next;
    void *c = x ? x->c : 0;
    pthread_mutex_unlock(&octx_lock);
    return c;
}
void dispatch_set_finalizer_f(void *o, dfunc f) { }

/* ======================================================================= dispatch_data (contiguous only) */
/* ponytail: a data object is one contiguous region and is never freed (retain/release are no-ops for dispatch objects);
 * concatenation copies. */
struct ddata { void *isa; const void *ptr; size_t size; };
struct ddata _dispatch_data_empty = {_dispatch_object_class, "", 0};
static char destr_free, destr_munmap, destr_none;
const void *const _dispatch_data_destructor_free = &destr_free, *const _dispatch_data_destructor_munmap = &destr_munmap,
                  *const _dispatch_data_destructor_none = &destr_none;
struct ddata *dispatch_data_create(const void *buf, size_t size, struct dqueue *q, void *destructor) {
    if (!size) return &_dispatch_data_empty;
    struct ddata *d = calloc(1, sizeof *d);
    d->isa = ISA(DATA); d->size = size;
    if (!destructor) { void *c = malloc(size); memcpy(c, buf, size); d->ptr = c; } /* DISPATCH_DATA_DESTRUCTOR_DEFAULT: copied */
    else d->ptr = buf;                                                              /* the owner keeps it alive */
    return d;
}
size_t dispatch_data_get_size(struct ddata *d) { return d ? d->size : 0; }
struct ddata *dispatch_data_create_map(struct ddata *d, const void **ptr, size_t *size) {
    if (ptr) *ptr = d ? d->ptr : 0;
    if (size) *size = d ? d->size : 0;
    return d;
}
struct ddata *dispatch_data_create_concat(struct ddata *a, struct ddata *b) {
    size_t n = a->size + b->size;
    char *c = malloc(n ? n : 1); memcpy(c, a->ptr, a->size); memcpy(c + a->size, b->ptr, b->size);
    struct ddata *d = dispatch_data_create(c, n, 0, (void *)_dispatch_data_destructor_free);
    return d;
}
struct ddata *dispatch_data_create_subrange(struct ddata *d, size_t off, size_t len) {
    if (off >= d->size) return &_dispatch_data_empty;
    if (len > d->size - off) len = d->size - off;
    return dispatch_data_create((const char *)d->ptr + off, len, 0, (void *)_dispatch_data_destructor_none);
}
int dispatch_data_apply(struct ddata *d, int (^f)(struct ddata *region, size_t offset, const void *buffer, size_t size)) {
    return d->size ? f(d, 0, d->ptr, d->size) : 1;
}

/* ======================================================================= Objective-C classes */
/* libobjc's OS_dispatch_* classes register here when they load; objects made before keep the generic class */
void _scion_dispatch_set_class(int k, void *cls) {
    if (k < 0 || k >= DK_COUNT) return;
    dk_class[k] = cls;
    if (k == DK_QUEUE) { _dispatch_main_q.isa = cls; for (int i = 0; i < 6; i++) global_q[i].isa = cls; }
    if (k == DK_ATTR) _dispatch_queue_attr_concurrent.isa = cls;
    if (k == DK_DATA) _dispatch_data_empty.isa = cls;
}

/* ======================================================================= more queue calls */
void dispatch_assert_queue(void *q) {} /* ponytail: assertions about the current queue always pass */
void dispatch_assert_queue_not(void *q) {}
void dispatch_assert_queue_barrier(void *q) {}
void mw_assert_queue_v2(void *q) __asm__("_dispatch_assert_queue$V2");
void mw_assert_queue_v2(void *q) {}
void mw_assert_queue_not_v2(void *q) __asm__("_dispatch_assert_queue_not$V2");
void mw_assert_queue_not_v2(void *q) {}
struct dqueue *mw_queue_create_with_target_v2(const char *l, struct dqueue_attr *a, void *t) __asm__("_dispatch_queue_create_with_target$V2");
struct dqueue *mw_queue_create_with_target_v2(const char *l, struct dqueue_attr *a, void *t) { return dispatch_queue_create(l, a); }
struct dqueue_attr *dispatch_queue_attr_make_with_autorelease_frequency(struct dqueue_attr *a, unsigned long f) { return a; }
unsigned dispatch_queue_get_qos_class(struct dqueue *q, int *relpri) { if (relpri) *relpri = 0; return 0x15; /* QOS_CLASS_DEFAULT */ }

/* queue-specific data: a list of (queue, key, value) */
struct dspec { struct dqueue *q; const void *key; void *v; dfunc dtor; struct dspec *next; };
static struct dspec *specs; static pthread_mutex_t spec_lock;
void dispatch_queue_set_specific(struct dqueue *q, const void *key, void *v, dfunc dtor) {
    pthread_mutex_lock(&spec_lock);
    struct dspec *x = specs;
    while (x && !(x->q == q && x->key == key)) x = x->next;
    if (!x) { x = calloc(1, sizeof *x); x->q = q; x->key = key; x->next = specs; specs = x; }
    else if (x->dtor && x->v) x->dtor(x->v);
    x->v = v; x->dtor = dtor;
    pthread_mutex_unlock(&spec_lock);
}
void *dispatch_queue_get_specific(struct dqueue *q, const void *key) {
    pthread_mutex_lock(&spec_lock);
    struct dspec *x = specs;
    while (x && !(x->q == q && x->key == key)) x = x->next;
    void *v = x ? x->v : 0;
    pthread_mutex_unlock(&spec_lock);
    return v;
}
int pthread_main_np(void);
void *dispatch_get_specific(const void *key) {
    dispatch_once_f(&cur_once, 0, cur_key_init);
    struct dqueue *q = pthread_getspecific(cur_key);
    if (!q && pthread_main_np()) q = &_dispatch_main_q; /* the main thread is the main queue's */
    return q ? dispatch_queue_get_specific(q, key) : 0;
}

/* ======================================================================= dispatch blocks (DispatchWorkItem)
 * dispatch_block_create wraps a block in a malloc block whose invoke runs it unless cancelled, then wakes waiters and
 * schedules the notification blocks. */
struct dblock_state { pthread_mutex_t m; pthread_cond_t cv; int cancelled, done; struct timer *notify; };
struct dblock { struct Block_layout h; struct dblock_state *st; void *inner; };
static void dblock_invoke(struct dblock *b) {
    struct dblock_state *st = b->st;
    if (!__atomic_load_n(&st->cancelled, __ATOMIC_ACQUIRE)) call_block(b->inner);
    pthread_mutex_lock(&st->m);
    st->done = 1; struct timer *n = st->notify; st->notify = 0;
    pthread_cond_broadcast(&st->cv);
    pthread_mutex_unlock(&st->m);
    while (n) { struct timer *x = n->next; dispatch_async_f(n->q, n->ctx, n->fn); free(n); n = x; }
}
static void dblock_copy(void *dst, const void *src) {}
static void dblock_dispose(const void *p) { const struct dblock *b = p; _Block_release(b->inner); free(b->st); }
static struct Block_descriptor dblock_desc = {0, sizeof(struct dblock), dblock_copy, dblock_dispose};
void *dispatch_block_create(unsigned long flags, void *block) {
    struct dblock *b = malloc(sizeof *b);
    b->h.isa = _NSConcreteMallocBlock; b->h.flags = BLOCK_NEEDS_FREE | BLOCK_HAS_COPY_DISPOSE | 2; b->h.reserved = 0;
    b->h.invoke = (void (*)(void *, ...))dblock_invoke; b->h.descriptor = &dblock_desc;
    b->st = calloc(1, sizeof *b->st); b->inner = _Block_copy(block);
    return b;
}
void *dispatch_block_create_with_qos_class(unsigned long flags, unsigned qos, int relpri, void *block) { return dispatch_block_create(flags, block); }
static struct dblock_state *dblock_of(void *p) {
    struct dblock *b = p;
    return b && b->h.invoke == (void (*)(void *, ...))dblock_invoke ? b->st : 0;
}
void dispatch_block_cancel(void *blk) { struct dblock_state *st = dblock_of(blk); if (st) __atomic_store_n(&st->cancelled, 1, __ATOMIC_RELEASE); }
long dispatch_block_testcancel(void *blk) { struct dblock_state *st = dblock_of(blk); return st && __atomic_load_n(&st->cancelled, __ATOMIC_ACQUIRE); }
long dispatch_block_wait(void *blk, uint64_t timeout) {
    struct dblock_state *st = dblock_of(blk);
    if (!st) return 0;
    pthread_mutex_lock(&st->m);
    while (!st->done) {
        if (timeout == ~0ull) { pthread_cond_wait(&st->cv, &st->m); continue; }
        uint64_t now = mach_absolute_time();
        if (timeout <= now) { pthread_mutex_unlock(&st->m); return 1; }
        uint64_t d = timeout - now; struct timespec ts = {(int64_t)(d / 1000000000), (int64_t)(d % 1000000000)};
        pthread_cond_timedwait_relative_np(&st->cv, &st->m, &ts);
    }
    pthread_mutex_unlock(&st->m);
    return 0;
}
void dispatch_block_notify(void *blk, struct dqueue *q, void *nb) {
    struct dblock_state *st = dblock_of(blk);
    void *c = _Block_copy(nb);
    if (!st) { dispatch_async_f(q, c, run_and_release); return; }
    pthread_mutex_lock(&st->m);
    if (st->done) { pthread_mutex_unlock(&st->m); dispatch_async_f(q, c, run_and_release); return; }
    struct timer *t = malloc(sizeof *t); t->q = q; t->ctx = c; t->fn = run_and_release; t->next = st->notify; st->notify = t;
    pthread_mutex_unlock(&st->m);
}
void dispatch_block_perform(unsigned long flags, void *block) { call_block(block); }

/* ======================================================================= data regions and file I/O */
struct ddata *dispatch_data_copy_region(struct ddata *d, size_t location, size_t *offset) { if (offset) *offset = 0; return d; }
/* dispatch_read/dispatch_write: done synchronously on a worker, the handler on the queue.
 * ponytail: I/O channels (dispatch_io_*) are not implemented: they return NULL and do nothing. */
long read(int, void *, size_t); long write(int, const void *, size_t);
struct dio_job { int fd; size_t len; struct ddata *data; struct dqueue *q; void *handler; int is_write; };
static void dio_run(void *p) {
    struct dio_job *j = p;
    int err = 0; struct ddata *res = &_dispatch_data_empty;
    if (!j->is_write) {
        size_t cap = j->len < 65536 ? j->len : 65536, n = 0; char *buf = malloc(cap ? cap : 1);
        while (n < j->len) {
            if (n == cap) { cap *= 2; if (cap > j->len) cap = j->len; char *nb = malloc(cap); memcpy(nb, buf, n); free(buf); buf = nb; }
            long r = read(j->fd, buf + n, cap - n);
            if (r < 0) { err = 5; break; } /* EIO */
            if (r == 0) break;
            n += (size_t)r;
        }
        res = n ? dispatch_data_create(buf, n, 0, (void *)_dispatch_data_destructor_free) : &_dispatch_data_empty;
        if (!n) free(buf);
    } else {
        size_t n = 0;
        while (n < j->data->size) {
            long r = write(j->fd, (const char *)j->data->ptr + n, j->data->size - n);
            if (r <= 0) { err = 5; break; }
            n += (size_t)r;
        }
        res = n < j->data->size ? dispatch_data_create_subrange(j->data, n, j->data->size - n) : 0;
    }
    void (^h)(struct ddata *, int) = j->handler;
    struct ddata *r2 = res; int e2 = err;
    dispatch_async(j->q, ^{ h(r2, e2); });
    _Block_release(j->handler); free(j);
}
void dispatch_read(int fd, size_t len, struct dqueue *q, void *handler) {
    struct dio_job *j = calloc(1, sizeof *j); j->fd = fd; j->len = len; j->q = q; j->handler = _Block_copy(handler);
    pool_push(dio_run, j);
}
void dispatch_write(int fd, struct ddata *d, struct dqueue *q, void *handler) {
    struct dio_job *j = calloc(1, sizeof *j); j->fd = fd; j->data = d; j->q = q; j->handler = _Block_copy(handler); j->is_write = 1;
    pool_push(dio_run, j);
}
void *dispatch_io_create(unsigned long type, int fd, struct dqueue *q, void *cleanup) { return 0; }
void *dispatch_io_create_with_path(unsigned long type, const char *path, int oflag, int mode, struct dqueue *q, void *cleanup) { return 0; }
void *dispatch_io_create_with_io(unsigned long type, void *io, struct dqueue *q, void *cleanup) { return 0; }
void dispatch_io_read(void *io, int64_t off, size_t len, struct dqueue *q, void *handler) {}
void dispatch_io_write(void *io, int64_t off, struct ddata *d, struct dqueue *q, void *handler) {}
void dispatch_io_close(void *io, unsigned long flags) {}
void dispatch_io_set_interval(void *io, uint64_t interval, unsigned long flags) {}
void dispatch_io_set_high_water(void *io, size_t n) {}
void dispatch_io_set_low_water(void *io, size_t n) {}
void dispatch_io_barrier(void *io, void *b) {}
int dispatch_io_get_descriptor(void *io) { return -1; }
/* Swift Concurrency's needs: QoS of the calling thread, and vouchers (none: adopting returns the previous, null) */
unsigned qos_class_self(void) { return 0x15; }   /* QOS_CLASS_DEFAULT */
unsigned qos_class_main(void) { return 0x21; }   /* QOS_CLASS_USER_INTERACTIVE */
void *voucher_copy(void) { return 0; }
void *voucher_adopt(void *v) { return 0; }
void *os_retain(void *o) { return o; }   /* ponytail: like dispatch_release, OS objects are never freed */
void os_release(void *o) {}
