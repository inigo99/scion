/* Code generated at run time (like a guest JIT): write, run, rewrite the same address, flush the instruction cache
 * and run again. Prints "JIT OK". */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>
#include <pthread.h>

static int fails;
#define CHECK(c) do { if (c) printf("ok   %s\n", #c); else { printf("FAIL %s (line %d)\n", #c, __LINE__); fails++; } } while (0)

/* "return k" in the binary's architecture */
static size_t emit_ret(uint8_t *p, uint32_t k) {
#if defined(__aarch64__)
    uint32_t ins[2] = {0xD2800000u | ((k & 0xFFFF) << 5), 0xD65F03C0u}; /* movz x0, #k ; ret */
    memcpy(p, ins, sizeof ins); return sizeof ins;
#else
    p[0] = 0xB8; memcpy(p + 1, &k, 4); p[5] = 0xC3;                    /* mov eax, k ; ret */
    return 6;
#endif
}
typedef int (*fn_t)(void);

int main(void) {
    uint8_t *code = mmap(NULL, 16384, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    CHECK(code != MAP_FAILED);
    pthread_jit_write_protect_np(0);
    size_t n = emit_ret(code, 1);
    pthread_jit_write_protect_np(1);
    sys_icache_invalidate(code, n);
    CHECK(((fn_t)code)() == 1);
    for (uint32_t k = 2; k <= 50; k++) {          /* rewrite the same address many times */
        pthread_jit_write_protect_np(0); emit_ret(code, k); pthread_jit_write_protect_np(1);
        sys_icache_invalidate(code, n);
        if (((fn_t)code)() != (int)k) { printf("FAIL rewrite %u\n", k); fails++; break; }
    }
    CHECK(((fn_t)code)() == 50);
    /* munmap + mmap again at the same address with different code */
    munmap(code, 16384);
    uint8_t *again = mmap(code, 16384, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
    CHECK(again == code);
    emit_ret(again, 77);
    __builtin___clear_cache((char *)again, (char *)again + n);
    CHECK(((fn_t)again)() == 77);
    printf(fails ? "JIT: %d FAILURES\n" : "JIT OK\n", fails);
    return fails;
}
