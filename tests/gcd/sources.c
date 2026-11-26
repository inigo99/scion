/* dispatch sources. Repeating and one-shot timers, cancel handlers, suspend/resume with coalesced data,
 * DATA_ADD / DATA_OR merged from several threads, SIGNAL sources, contexts and the _f variants, READ and WRITE sources on
 * a socket pair (and a READ source on a file). Prints "SOURCES OK". */
#include <dispatch/dispatch.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>
#include <stdatomic.h>
#include <string.h>
#include <fcntl.h>
#include <sys/socket.h>

static int fails;
#define CHECK(c, ...) do { if (c) printf("  ok: " __VA_ARGS__); else { printf("  FAIL: " __VA_ARGS__); fails++; } printf("\n"); fflush(stdout); } while (0)

static atomic_long f_calls; static long f_ctx_ok;
static void handler_f(void *ctx) { f_calls++; if (ctx == (void *)0x1234) f_ctx_ok = 1; }

int main(void) {
    dispatch_queue_t q = dispatch_queue_create("fuentes", DISPATCH_QUEUE_SERIAL);

    printf("step: repeating timer\n");
    __block atomic_long ticks = 0, data_sum = 0;
    __block atomic_int cancelled = 0;
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), 20 * NSEC_PER_MSEC, 1 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(t, ^{ ticks++; data_sum += (long)dispatch_source_get_data(t); });
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_source_set_cancel_handler(t, ^{ cancelled = 1; dispatch_semaphore_signal(done); });
    usleep(100000);
    CHECK(ticks == 0, "a new source does not fire until dispatch_resume");
    dispatch_resume(t);
    usleep(330000);
    long n = ticks;
    CHECK(n >= 8 && n <= 20, "~15 fires in 0.33 s every 20 ms (%ld)", n);
    dispatch_suspend(t);
    usleep(20000);
    long before = ticks;
    usleep(150000);
    CHECK(ticks == before, "suspended: delivers no events");
    dispatch_resume(t);
    usleep(50000);
    CHECK(data_sum >= before + 6, "on resume, get_data adds up the missed fires (sum %ld, events %ld)", (long)data_sum, (long)ticks);
    dispatch_source_cancel(t);
    long w = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    long after = ticks;
    usleep(100000);
    CHECK(w == 0 && cancelled && ticks == after && dispatch_source_testcancel(t), "cancel: cancel handler and no more fires");

    printf("step: one-shot timer\n");
    __block atomic_int once = 0;
    dispatch_source_t o = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(0, 0));
    dispatch_source_set_timer(o, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(o, ^{ once++; });
    dispatch_activate(o);
    usleep(200000);
    CHECK(once == 1, "a single fire (%d)", (int)once);

    printf("step: DATA_ADD and DATA_OR from several threads\n");
    __block atomic_long added = 0, calls = 0;
    dispatch_source_t a = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, q);
    dispatch_source_set_event_handler(a, ^{ added += (long)dispatch_source_get_data(a); calls++; });
    dispatch_group_t g = dispatch_group_create();
    for (int i = 0; i < 4; i++) dispatch_group_async(g, dispatch_get_global_queue(0, 0), ^{ for (int k = 0; k < 250; k++) dispatch_source_merge_data(a, 1); });
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
    CHECK(added == 0, "suspended: the data waits");
    dispatch_resume(a);
    usleep(100000);
    CHECK(added == 1000 && calls >= 1 && calls < 1000, "sum 1000 in %ld calls (coalesced)", (long)calls);
    __block unsigned long ored = 0;
    dispatch_source_t b = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_OR, 0, 0, q);
    dispatch_source_set_event_handler(b, ^{ ored |= dispatch_source_get_data(b); });
    dispatch_source_merge_data(b, 1); dispatch_source_merge_data(b, 4); dispatch_source_merge_data(b, 16);
    dispatch_resume(b);
    usleep(50000);
    CHECK(ored == 21, "DATA_OR 1|4|16 = %lu", ored);

    printf("step: signals\n");
    signal(SIGUSR1, SIG_IGN);
    __block atomic_long sigs = 0;
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGUSR1, 0, q);
    dispatch_source_set_event_handler(s, ^{ sigs += (long)dispatch_source_get_data(s); });
    dispatch_resume(s);
    raise(SIGUSR1); raise(SIGUSR1); raise(SIGUSR1);
    usleep(150000);
    CHECK(sigs == 3, "3 x SIGUSR1 -> data 3 (%ld)", (long)sigs);

    printf("step: context and _f\n");
    dispatch_source_t c = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, q);
    dispatch_set_context(c, (void *)0x1234);
    dispatch_source_set_event_handler_f(c, handler_f);
    dispatch_resume(c);
    dispatch_source_merge_data(c, 5);
    usleep(50000);
    CHECK(f_calls == 1 && f_ctx_ok && dispatch_get_context(c) == (void *)0x1234, "_f handler with the context");
    dispatch_set_context(q, (void *)0x99);
    CHECK(dispatch_get_context(q) == (void *)0x99, "a queue's context");

    printf("step: READ and WRITE sources\n");
    int sv[2];
    CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0, "socketpair");
    int s0 = sv[0], s1 = sv[1];
    fcntl(s0, F_SETFL, O_NONBLOCK);
    __block atomic_long got = 0, reads = 0, last = 0;
    dispatch_semaphore_t rd = dispatch_semaphore_create(0);
    dispatch_source_t r = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)s0, 0, q);
    dispatch_source_set_event_handler(r, ^{
        char buf[64];
        last = (long)dispatch_source_get_data(r);
        long n = read(s0, buf, sizeof buf);   /* (a part of it: the source fires again for the rest) */
        if (n > 0) { got += n; reads++; }
        if (got >= 100) dispatch_semaphore_signal(rd);
    });
    dispatch_resume(r);
    usleep(50000);
    CHECK(reads == 0, "nothing to read: no fire");
    char data[100]; memset(data, 'x', sizeof data);
    write(s1, data, sizeof data);
    CHECK(dispatch_semaphore_wait(rd, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0 && got == 100 && reads >= 2,
          "100 bytes read in %ld pieces as they stayed readable", (long)reads);
    CHECK(last > 0, "the data is the bytes available (%ld)", (long)last);
    __block atomic_int canc = 0;
    dispatch_semaphore_t cs = dispatch_semaphore_create(0);
    dispatch_source_set_cancel_handler(r, ^{ canc = 1; dispatch_semaphore_signal(cs); });
    dispatch_source_cancel(r);
    CHECK(dispatch_semaphore_wait(cs, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0 && canc, "read source cancelled");
    long reads_then = reads;
    write(s1, data, 10);
    usleep(100000);
    CHECK(reads == reads_then, "no fires after cancel");
    __block atomic_long writable = 0;
    dispatch_source_t w2 = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, (uintptr_t)s1, 0, q);
    dispatch_source_set_event_handler(w2, ^{ writable = (long)dispatch_source_get_data(w2) + 1; dispatch_source_cancel(w2); });
    dispatch_resume(w2);
    usleep(150000);
    CHECK(writable > 0, "a socket with room is writable");
    /* a file (which kqueue does not watch everywhere) is always readable */
    int fd = open("sources_file.tmp", O_RDWR | O_CREAT | O_TRUNC, 0644);
    write(fd, "abc", 3); lseek(fd, 0, SEEK_SET);
    __block atomic_int file_fires = 0;
    dispatch_source_t fr = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, q);
    dispatch_source_set_event_handler(fr, ^{ char b[8]; read(fd, b, sizeof b); file_fires++; dispatch_source_cancel(fr); });
    dispatch_resume(fr);
    usleep(150000);
    CHECK(file_fires == 1, "a file fires (%d)", (int)file_fires);
    close(fd); unlink("sources_file.tmp");

    printf(fails ? "SOURCES FAIL (%d)\n" : "SOURCES OK\n", fails);
    return fails != 0;
}
