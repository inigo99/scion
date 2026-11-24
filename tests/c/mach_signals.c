/* C: signals with sigaltstack + siglongjmp, the Mach memory API and thread_suspend/get_state. Prints "failures=0". */
typedef unsigned long size_t; typedef unsigned long long u64; typedef unsigned int u32;
int printf(const char *, ...); /* not used: output goes through write */
long write(int, const void *, size_t); size_t strlen(const char *);
struct sigact { void *h; u32 mask; int flags; };
struct stk { void *sp; size_t size; int flags; };
int sigaction(int, const struct sigact *, struct sigact *); int sigaltstack(const struct stk *, struct stk *);
int sigsetjmp(int *, int); void siglongjmp(int *, int);
void *malloc(size_t);
int vm_allocate(u32, u64 *, u64, int); int vm_protect(u32, u64, u64, int, int);
int mach_vm_write(u32, u64, u64, u32); int mach_vm_read_overwrite(u32, u64, u64, u64, u64 *);
extern u32 mach_task_self_;
typedef void *pthread_t;
int pthread_create(pthread_t *, void *, void *(*)(void *), void *); int pthread_join(pthread_t, void **);
u32 pthread_mach_thread_np(pthread_t); int thread_suspend(u32); int thread_resume(u32);
int thread_get_state(u32, int, u32 *, u32 *);

static void out(const char *s) { write(1, s, strlen(s)); }
static void num(const char *k, u64 v) { char b[32]; int i = 31; b[i] = 0; do b[--i] = '0' + v % 10; while (v /= 10); out(k); out(b + i); out("\n"); }
static int jb[64]; static volatile u64 fault_addr; static volatile int failures;
static void handler(int sig, void **info, void *uc) { fault_addr = (u64)info[3]; siglongjmp(jb, sig); }
static volatile int stop; static volatile u64 counter;
static void *spin(void *a) { while (!stop) counter++; return 0; }

int main(void) {
    struct stk ss = {malloc(65536), 65536, 0};
    sigaltstack(&ss, 0);
    struct sigact sa = {(void *)handler, 0, 0x40 | 1 /* SA_SIGINFO|SA_ONSTACK */};
    sigaction(11, &sa, 0); sigaction(10, &sa, 0);
    int s = sigsetjmp(jb, 1);
    if (!s) { *(volatile int *)0x58 = 1; out("FAIL: no SIGSEGV\n"); failures++; }
    else { num("SIGSEGV caught, signal=", s); num("  address=", fault_addr); }

    u64 a = 0; u32 t = mach_task_self_;
    if (vm_allocate(t, &a, 3 * 0x4000, 1)) { out("FAIL vm_allocate\n"); failures++; }
    vm_protect(t, a + 0x4000, 0x4000, 0, 1 /* read-only */);
    u64 v = 0x1122334455667788ull, r = 0, n = 0;
    int w_ok = mach_vm_write(t, a, (u64)&v, 8), w_ro = mach_vm_write(t, a + 0x4000, (u64)&v, 8);
    int r_ok = mach_vm_read_overwrite(t, a, 8, (u64)&r, &n), r_bad = mach_vm_read_overwrite(t, 0x10, 8, (u64)&r, &n);
    num("vm_write RW (0 expected)=", w_ok); num("vm_write RO (!=0 expected)=", w_ro != 0);
    num("vm_read valid (0)=", r_ok); num("vm_read invalid (!=0)=", r_bad != 0);
    if (w_ok || !w_ro || r_ok || !r_bad || r != v) { out("FAIL mach_vm\n"); failures++; }
    s = sigsetjmp(jb, 1);
    if (!s) { *(volatile int *)(a + 0x4000) = 5; out("FAIL: writing to RO memory raised no signal\n"); failures++; }
    else num("write to RO page -> signal ", s);

    pthread_t th; pthread_create(&th, 0, spin, 0);
    while (counter < 1000) ;
    u32 port = pthread_mach_thread_np(th);
    u32 st[68], cnt = 68;
#ifdef __aarch64__
    int flavor = 6;
#else
    int flavor = 4; cnt = 42;
#endif
    int ks = thread_suspend(port);
    u64 c1 = counter; for (volatile int i = 0; i < 2000000; i++) {} u64 c2 = counter;
    int kg = thread_get_state(port, flavor, st, &cnt);
    u64 pc = flavor == 6 ? *(u64 *)&st[64] : *(u64 *)&st[32];
    thread_resume(port);
    num("thread_suspend stops the thread (1)=", ks == 0 && c1 == c2);
    num("thread_get_state pc!=0 (1)=", kg == 0 && pc != 0);
    stop = 1; pthread_join(th, 0);
    if (ks || c1 != c2 || kg || !pc) { out("FAIL thread_suspend/get_state\n"); failures++; }
    num("failures=", failures);
    return failures;
}
