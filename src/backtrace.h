/* backtrace.h — stack trace of host code (scion.exe and its DLLs) for crash reports: one line per frame,
 * module+offset, unwound with the x64 unwind tables. Resolve offsets with the linker map of the same build. */
#pragma once
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

static inline void mw_backtrace(CONTEXT c) {
    for (int i = 0; i < 32 && c.Rip; i++) {
        HMODULE m = nullptr; wchar_t name[MAX_PATH] = L"?";
        if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCWSTR)c.Rip, &m))
            GetModuleFileNameW(m, name, MAX_PATH);
        const wchar_t *base = wcsrchr(name, L'\\');
        if (m) fprintf(stderr, "  #%d %ls+0x%llx\n", i, base ? base + 1 : name, (unsigned long long)(c.Rip - (DWORD64)m));
        else fprintf(stderr, "  #%d %#llx (generated code)\n", i, (unsigned long long)c.Rip);
        DWORD64 image = 0;
        PRUNTIME_FUNCTION f = RtlLookupFunctionEntry(c.Rip, &image, nullptr);
        if (!f) {   /* leaf function, or code without unwind data: the return address is on top of the stack */
            if (IsBadReadPtr((void *)c.Rsp, 8)) break;
            c.Rip = *(DWORD64 *)c.Rsp; c.Rsp += 8;
            continue;
        }
        void *handler_data; DWORD64 frame;
        RtlVirtualUnwind(UNW_FLAG_NHANDLER, image, c.Rip, f, &c, &handler_data, &frame, nullptr);
    }
    fflush(stderr);
}
