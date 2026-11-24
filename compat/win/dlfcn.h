/* Minimal dlfcn.h for Windows so Indium/Iridium build unchanged.
 * ponytail: maps Linux sonames to Windows DLL names by substring; add a real table if more libs appear. */
#pragma once
#include <windows.h>
#include <string.h>
#define RTLD_LAZY 1
static inline void *dlopen(const char *name, int) {
    if (strstr(name, "vulkan")) name = "vulkan-1.dll";
    else if (strstr(name, "LLVM")) { /* LLVM is linked statically and exported from this module (exe or dll) */
        HMODULE h = 0;
        GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)(void *)&dlopen, &h);
        return (void *)h;
    }
    return (void *)LoadLibraryA(name);
}
static inline void *dlsym(void *h, const char *s) { return (void *)GetProcAddress((HMODULE)h, s); }
static inline int dlclose(void *h) { return !FreeLibrary((HMODULE)h); }
