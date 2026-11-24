/* mach_vm_remap(copy=FALSE): two addresses for the same pages (arm64). Prints "REMAP OK". */
#include <stdio.h>
#include <string.h>
#include <stdatomic.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
static int fails;
#define CHECK(c) do { if (c) printf("ok   %s\n", #c); else { printf("FAIL %s (line %d)\n", #c, __LINE__); fails++; } } while (0)
int main(void) {
    size_t n = 0x40000;
    char *src = mmap(NULL, n, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    strcpy(src + 0x4000, "origin");
    mach_vm_address_t a = 0; vm_prot_t cur = 0, max = 0;
    kern_return_t kr = mach_vm_remap(mach_task_self(), &a, n - 0x4000, 0, VM_FLAGS_ANYWHERE, mach_task_self(),
                                     (mach_vm_address_t)(src + 0x4000), FALSE, &cur, &max, VM_INHERIT_NONE);
#if defined(__x86_64__)
    CHECK(kr == KERN_FAILURE); /* x86_64: copy only */
#else
    CHECK(kr == KERN_SUCCESS && (cur & 3) == 3);
    char *alias = (char *)a;
    CHECK(strcmp(alias, "origin") == 0);
    strcpy(alias + 100, "written via alias"); CHECK(strcmp(src + 0x4000 + 100, "written via alias") == 0);
    src[0x4000 + 0x30000] = 'Z'; CHECK(alias[0x30000] == 'Z');
    _Atomic long *c1 = (_Atomic long *)(alias + 0x1000), *c2 = (_Atomic long *)(src + 0x5000);
    for (int i = 0; i < 1000; i++) { atomic_fetch_add(c1, 1); atomic_fetch_add(c2, 1); }
    CHECK(atomic_load(c1) == 2000 && atomic_load(c2) == 2000);
    /* fixed target inside an existing reservation (like a GPU driver's virtual memory pools) */
    char *virt = mmap(NULL, 0x10000, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    mach_vm_address_t b = (mach_vm_address_t)virt;
    kr = mach_vm_remap(mach_task_self(), &b, 0x10000, 0, VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE, mach_task_self(),
                       (mach_vm_address_t)src, FALSE, &cur, &max, VM_INHERIT_NONE);
    CHECK(kr == KERN_SUCCESS && b == (mach_vm_address_t)virt && strcmp(virt + 0x4000, "origin") == 0);
    memcpy(virt + 0x8000, "memcpy", 7); CHECK(strcmp(src + 0x8000, "memcpy") == 0);
    /* system calls and locks get pointers into the alias: the host must use the source pages */
    int fd = open("remap_tmp.bin", O_RDWR | O_CREAT | O_TRUNC, 0644);
    CHECK(fd >= 0 && write(fd, virt + 0x4000, 7) == 7);
    CHECK(pread(fd, virt + 0x9000, 7, 0) == 7 && strcmp(src + 0x9000, "origin") == 0);
    lseek(fd, 0, SEEK_SET); CHECK(read(fd, virt + 0xA000, 7) == 7 && strcmp(src + 0xA000, "origin") == 0);
    close(fd); unlink("remap_tmp.bin");
    pthread_mutex_t *m = (pthread_mutex_t *)(virt + 0xB000); pthread_mutex_init(m, NULL);
    CHECK(pthread_mutex_lock(m) == 0 && pthread_mutex_trylock(m) != 0 && pthread_mutex_unlock(m) == 0);
    CHECK(munmap(virt, 0x10000) == 0 && strcmp(src + 0x4000, "origin") == 0);
#endif
    printf(fails ? "REMAP: %d FAILURES\n" : "REMAP OK\n", fails);
    return fails;
}
