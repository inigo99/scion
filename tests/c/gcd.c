/* C + blocks: the Blocks runtime and libdispatch. Prints "failures=0". */
typedef unsigned long size_t; typedef unsigned long long u64;
long write(int, const void *, size_t); size_t strlen(const char *);
typedef struct dq *dispatch_queue_t; typedef struct dg *dispatch_group_t; typedef void *dispatch_semaphore_t;
typedef void (^dispatch_block_t)(void);
extern struct dq _dispatch_main_q; extern struct { int c; } _dispatch_queue_attr_concurrent;
dispatch_queue_t dispatch_get_global_queue(long, unsigned long);
dispatch_queue_t dispatch_queue_create(const char *, void *);
void dispatch_async(dispatch_queue_t, dispatch_block_t); void dispatch_sync(dispatch_queue_t, dispatch_block_t);
dispatch_group_t dispatch_group_create(void); void dispatch_group_async(dispatch_group_t, dispatch_queue_t, dispatch_block_t);
long dispatch_group_wait(dispatch_group_t, u64);
void dispatch_once(long *, dispatch_block_t);
u64 dispatch_time(u64, long long); void dispatch_after(u64, dispatch_queue_t, dispatch_block_t);
dispatch_semaphore_t dispatch_semaphore_create(long); long dispatch_semaphore_signal(dispatch_semaphore_t); long dispatch_semaphore_wait(dispatch_semaphore_t, u64);
void *_Block_copy(const void *); void _Block_release(const void *);
u64 mach_absolute_time(void);

static void out(const char *s) { write(1, s, strlen(s)); }
static void num(const char *k, long v) { char b[32]; int i = 31, neg = v < 0; unsigned long u = neg ? -v : v; b[i] = 0; do b[--i] = '0' + u % 10; while (u /= 10); if (neg) b[--i] = '-'; out(k); out(b + i); out("\n"); }
static int failures;
static void check(const char *n, int ok) { out(ok ? "OK    " : "FAIL "); out(n); out("\n"); if (!ok) failures++; }

int main(void) {
    /* blocks: copy to heap, __block captured by reference */
    __block int x = 1;
    int capt = 41;
    int (^b)(int) = ^(int k) { x += k; return capt + x; };
    int (^h)(int) = _Block_copy(b);
    int r1 = h(0);           /* 41 + 1 */
    x = 10; int r2 = h(0);   /* the copied block sees the same __block: 51 */
    _Block_release(h);
    check("Block_copy + shared __block", r1 == 42 && r2 == 51);

    /* concurrent global queue + group */
    dispatch_queue_t g = dispatch_get_global_queue(0, 0);
    dispatch_group_t grp = dispatch_group_create();
    __block long total = 0;
    for (int i = 1; i <= 100; i++) dispatch_group_async(grp, g, ^{ __atomic_fetch_add(&total, i, __ATOMIC_SEQ_CST); });
    check("dispatch_group_wait", dispatch_group_wait(grp, ~0ull) == 0);
    num("  sum 1..100 = ", total); check("all concurrent jobs done", total == 5050);

    /* serial queue: FIFO order */
    dispatch_queue_t s = dispatch_queue_create("dev.scion.serial", 0);
    static int order[50]; __block int n = 0;
    for (int i = 0; i < 50; i++) dispatch_async(s, ^{ order[n++] = i; });
    dispatch_sync(s, ^{});
    int ok = n == 50; for (int i = 0; i < 50; i++) ok &= order[i] == i;
    check("serial queue FIFO + dispatch_sync", ok);

    /* once */
    static long pred; __block int count = 0;
    for (int i = 0; i < 3; i++) dispatch_once(&pred, ^{ count++; });
    check("dispatch_once", count == 1);

    /* after + semaphore */
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    u64 t0 = mach_absolute_time();
    dispatch_after(dispatch_time(0, 50 * 1000000ll), g, ^{ dispatch_semaphore_signal(sem); });
    long w = dispatch_semaphore_wait(sem, dispatch_time(0, 5000 * 1000000ll));
    long ms = (long)((mach_absolute_time() - t0) / 1000000);
    num("  dispatch_after expected ~50 ms, actual = ", ms);
    check("dispatch_after", w == 0 && ms >= 45);
    num("failures=", failures);
    return failures;
}
