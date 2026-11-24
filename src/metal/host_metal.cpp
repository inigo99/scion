#include <algorithm>
/* host_metal.cpp — scion-metal.dll: the host half of Metal. Implements mtlbridge.h on top of Indium (Metal on
 * Vulkan) and Iridium (AIR -> SPIR-V). Loaded on first use by scion.exe's "metal" hostcall. */
#include <cmath>
#include <indium/indium.hpp>
#include <indium-kit/layer.hpp>
#include <indium-kit/layer.private.hpp>
#include <indium/dynamic-vk.hpp>
#include <indium/instance.private.hpp>
#include <indium/library.private.hpp>
#include <indium/render-command-encoder.private.hpp>
#include <indium/compute-command-encoder.private.hpp>
#include <indium/texture.private.hpp>
#include <indium/command-buffer.private.hpp>
#include <indium/sampler.private.hpp>
#ifdef _WIN32
#include <windows.h>
#include <vulkan/vulkan_win32.h>
#else
#include <dlfcn.h>
/* VK_KHR_xlib_surface without Xlib.h (its Window would clash with ours) */
struct XlibSurfaceInfo { VkStructureType sType; const void *pNext; VkFlags flags; void *dpy; unsigned long window; };
typedef VkResult (VKAPI_PTR *PFN_xlib_create)(VkInstance, const XlibSurfaceInfo *, const VkAllocationCallbacks *, VkSurfaceKHR *);
#include <sys/stat.h>
#endif
#include <atomic>
#include <csignal>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>
#include "mtlbridge.h"
#ifdef _WIN32
#include "../backtrace.h"
#endif
#include <exception>

using namespace Indium;
enum Kind { K_NONE, K_DEVICE, K_BUFFER, K_LIBRARY, K_FUNCTION, K_CPSO, K_RPSO, K_TEXTURE, K_SAMPLER, K_DSS, K_QUEUE, K_CB,
            K_CENC, K_RENC, K_BENC, K_LAYER, K_DRAWABLE };
struct Entry { std::shared_ptr<void> p; Kind kind; };
static std::mutex g_mu;
static std::vector<Entry> g_objs;
static std::vector<uint64_t> g_free;

template <class T> static uint64_t put(std::shared_ptr<T> p, Kind k) {
    if (!p) return 0;
    std::lock_guard<std::mutex> l(g_mu);
    Entry e{std::static_pointer_cast<void>(p), k};
    if (!g_free.empty()) { uint64_t h = g_free.back(); g_free.pop_back(); g_objs[h - 1] = e; return h; }
    g_objs.push_back(e);
    return g_objs.size();
}
static Entry entry(uint64_t h) {
    std::lock_guard<std::mutex> l(g_mu);
    return h && h <= g_objs.size() ? g_objs[h - 1] : Entry{nullptr, K_NONE};
}
template <class T> static std::shared_ptr<T> get(uint64_t h) { return std::static_pointer_cast<T>(entry(h).p); }
static void release(uint64_t h) {
    std::lock_guard<std::mutex> l(g_mu);
    if (!h || h > g_objs.size() || !g_objs[h - 1].p) return;
    g_objs[h - 1] = Entry{nullptr, K_NONE};
    g_free.push_back(h);
}
static void seterr(uint64_t buf, const char *m) { if (buf) { strncpy((char *)buf, m, 255); ((char *)buf)[255] = 0; } }

static int64_t compile_source(const char *src, const char *macros, char *err, size_t errsz, uint64_t *len);

/* ------------------------------------------------------------------ device */
static std::shared_ptr<Device> g_device;
static std::shared_ptr<Device> device() {
    static std::once_flag once;
    std::call_once(once, [] {
        /* Indium calls abort() on Vulkan errors it does not handle: say so instead of dying silently */
        signal(SIGABRT, [](int) {
            fputs("scion-metal: abort() in Indium (unhandled Vulkan error; try SCION_METAL_VALIDATION=1)\n", stderr);
#ifdef _WIN32
            CONTEXT c; RtlCaptureContext(&c); mw_backtrace(c);
#endif
            _exit(3);
        });
        std::set_terminate([] {
            try { if (auto e = std::current_exception()) std::rethrow_exception(e); } catch (const std::exception &e) { fprintf(stderr, "scion-metal: Indium exception: %s\n", e.what()); } catch (...) {}
            abort();
        });
#ifdef _WIN32
        static const char *ext[] = {VK_KHR_WIN32_SURFACE_EXTENSION_NAME};
#else
        static const char *ext[] = {"VK_KHR_xlib_surface"};
#endif
        Indium::init(ext, 1, getenv("SCION_METAL_VALIDATION") != nullptr);
        g_device = Indium::createSystemDefaultDevice();
        if (g_device && getenv("SCION_METAL_INFO")) { /* GPU and memory types (flags: 1 device-local, 2 host-visible, 4 coherent, 8 cached) */
            fprintf(stderr, "scion-metal: GPU %s\n", g_device->name().c_str());
            auto pd = std::dynamic_pointer_cast<PrivateDevice>(g_device); const auto &mp = pd->memoryProperties();
            for (uint32_t i = 0; i < mp.memoryTypeCount; i++) fprintf(stderr, "  memory type %u: flags %#x heap %u (%llu MB)\n", i, mp.memoryTypes[i].propertyFlags,
                mp.memoryTypes[i].heapIndex, (unsigned long long)(mp.memoryHeaps[mp.memoryTypes[i].heapIndex].size >> 20));
            fprintf(stderr, "  Private -> %zd, Shared -> %zd\n", (ssize_t)pd->memoryTypeFor(~0u, StorageMode::Private), (ssize_t)pd->memoryTypeFor(~0u, StorageMode::Shared));
        }
        if (g_device) std::thread([] { for (;;) g_device->pollEvents(UINT64_MAX); }).detach();
    });
    return g_device;
}

#ifndef _WIN32
/* ------------------------------------------------------------------ CAMetalLayer on Linux: the host's X11 window + swapchain */
struct Window {
    MwNativeWindow nw{};
    std::atomic<bool> closed{false};
    std::atomic<uint32_t> cw{0}, ch{0};
    std::atomic<uint64_t> format{0};
    bool external = true;                 /* the host (scion) owns every window: it sizes and closes them */
    std::shared_ptr<IndiumKit::Layer> layer;
    ~Window() { layer.reset(); }
    void query() { uint32_t w = 0, h = 0; if (nw.size) nw.size(nw.ctx, &w, &h); if (w && h) { cw = w; ch = h; } if (nw.closed && nw.closed(nw.ctx)) closed = true; }
};
static std::shared_ptr<Window> new_window(int w, int h, const char *, uint64_t pixelFormat, const MwNativeWindow *host) {
    if (!host || !host->display || !host->window) return nullptr;
    auto win = std::make_shared<Window>();
    win->nw = *host; win->cw = w; win->ch = h; win->query();
    XlibSurfaceInfo si{(VkStructureType)1000004000 /* XLIB_SURFACE_CREATE_INFO_KHR */, nullptr, 0, host->display, (unsigned long)host->window};
    auto create = (PFN_xlib_create)DynamicVK::vkGetInstanceProcAddr(Indium::globalInstance, "vkCreateXlibSurfaceKHR");
    VkSurfaceKHR surface;
    if (!create || create(Indium::globalInstance, &si, nullptr, &surface) != VK_SUCCESS) throw std::runtime_error("vkCreateXlibSurfaceKHR");
    win->layer = IndiumKit::Layer::make(surface, device(), win->cw, win->ch);
    if (pixelFormat) win->layer->setPixelFormat((PixelFormat)pixelFormat);
    if (getenv("SCION_METAL_INFO")) fprintf(stderr, "scion-metal: layer in X11 window %#llx (%ux%u)\n", (unsigned long long)host->window, win->cw.load(), win->ch.load());
    return win;
}
#else
/* ------------------------------------------------------------------ CAMetalLayer: Win32 window + swapchain */
/* The window lives on its own thread with its own message loop, so it stays responsive whatever the guest does. */
struct Window {
    HWND hwnd = nullptr;
    std::atomic<bool> closed{false};
    std::atomic<uint32_t> cw{0}, ch{0}; /* client area, kept by WM_SIZE */
    std::atomic<uint64_t> format{0};      /* pixel format asked for, applied at the next drawable */
    bool external = false;                /* an AppKit window's (ui.cpp): its owner sizes and closes it */
    std::shared_ptr<IndiumKit::Layer> layer;
    ~Window() { layer.reset(); if (hwnd && !external) PostMessageW(hwnd, WM_USER, 0, 0); }
};
static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_CLOSE) { /* like an app quitting after its last window closes: the guest sees it in nextDrawable */
        if (auto *win = (Window *)GetWindowLongPtrW(h, GWLP_USERDATA)) win->closed = true;
        ShowWindow(h, SW_HIDE);
        return 0;
    }
    if (m == WM_USER) { DestroyWindow(h); return 0; }
    if (m == WM_SIZE) {
        if (auto *win = (Window *)GetWindowLongPtrW(h, GWLP_USERDATA); win && LOWORD(l) && HIWORD(l)) { win->cw = LOWORD(l); win->ch = HIWORD(l); }
        return 0;
    }
    if (m == WM_APP) { /* resize the client area to (w, h) */
        RECT r{0, 0, (LONG)w, (LONG)l};
        AdjustWindowRect(&r, (DWORD)GetWindowLongW(h, GWL_STYLE), FALSE);
        SetWindowPos(h, nullptr, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
        return 0;
    }
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}
static std::shared_ptr<Window> new_window(int w, int h, const char *title, uint64_t pixelFormat, HWND host) {
    auto win = std::make_shared<Window>();
    if (host) { /* the layer of an NSView: draw into its window's client area */
        RECT rc; GetClientRect(host, &rc);
        win->hwnd = host; win->external = true;
        if (rc.right > 0 && rc.bottom > 0) { w = rc.right; h = rc.bottom; }
        win->cw = w; win->ch = h;
        if (getenv("SCION_METAL_INFO")) fprintf(stderr, "scion-metal: layer in an AppKit window (%dx%d)\n", w, h);
    } else {
    HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    wchar_t wt[256] = L"scion";
    if (title && *title) MultiByteToWideChar(CP_UTF8, 0, title, -1, wt, 256);
    Window *p = win.get();
    std::thread([=, &wt] {
        static WNDCLASSW wc = [] { WNDCLASSW c{}; c.lpfnWndProc = wndproc; c.hInstance = GetModuleHandleW(nullptr);
            c.hCursor = LoadCursorA(nullptr, IDC_ARROW); c.lpszClassName = L"scion-metal"; RegisterClassW(&c); return c; }();
        DWORD st = WS_OVERLAPPEDWINDOW; /* resizable: the swapchain follows the client area */
        RECT r{0, 0, w, h};
        AdjustWindowRect(&r, st, FALSE);
        p->hwnd = CreateWindowExW(0, wc.lpszClassName, wt, st | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, r.right - r.left,
                                  r.bottom - r.top, nullptr, nullptr, wc.hInstance, nullptr);
        if (p->hwnd) { p->cw = w; p->ch = h; SetWindowLongPtrW(p->hwnd, GWLP_USERDATA, (LONG_PTR)p); }
        SetEvent(ready);
        MSG m;
        while (GetMessageW(&m, nullptr, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageW(&m); }
    }).detach();
    WaitForSingleObject(ready, INFINITE); /* wt outlives the thread's use of it: CreateWindowExW runs before SetEvent */
    CloseHandle(ready);
    }
    if (!win->hwnd) return nullptr;
    VkWin32SurfaceCreateInfoKHR si{VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR};
    si.hinstance = GetModuleHandleW(nullptr);
    si.hwnd = win->hwnd;
    auto create = (PFN_vkCreateWin32SurfaceKHR)DynamicVK::vkGetInstanceProcAddr(Indium::globalInstance, "vkCreateWin32SurfaceKHR");
    VkSurfaceKHR surface;
    if (!create || create(Indium::globalInstance, &si, nullptr, &surface) != VK_SUCCESS) throw std::runtime_error("vkCreateWin32SurfaceKHR");
    win->layer = IndiumKit::Layer::make(surface, device(), w, h);
    if (pixelFormat) win->layer->setPixelFormat((PixelFormat)pixelFormat);
    return win;
}

#endif

/* Metal rounds a clear color to the nearest 8-bit value (0.5 -> 128); Vulkan lets drivers truncate (NVIDIA: 127).
   Clearing to a quarter step above that byte gives it both ways. (8-bit formats only.) */
static double snap8(double v, bool srgb) {
    if (!(v > 0)) return 0; if (v >= 1) return 1;
    auto byte = [](double x) { double k = std::round(x * 255); return k >= 255 ? 1.0 : (k + 0.25) / 255; };
    if (!srgb) return byte(v);
    double e = v <= 0.0031308 ? v * 12.92 : 1.055 * std::pow(v, 1 / 2.4) - 0.055, q = byte(e);
    return q <= 0.04045 ? q / 12.92 : std::pow((q + 0.055) / 1.055, 2.4);
}
static ClearColor clear_color(const std::shared_ptr<Texture> &t, const double *c) {
    int f = t ? (int)t->pixelFormat() : 0;
    bool b8 = f == 10 || f == 11 || f == 30 || f == 31 || f == 70 || f == 71 || f == 80 || f == 81, srgb = f & 1;
    if (!b8) return ClearColor(c[0], c[1], c[2], c[3]);
    return ClearColor(snap8(c[0], srgb), snap8(c[1], srgb), snap8(c[2], srgb), snap8(c[3], false));
}
static RenderPassAttachmentDescriptor pass_att(const MwPassAttachment &a) {
    RenderPassAttachmentDescriptor d;
    d.texture = get<Texture>(a.texture);
    d.level = a.level; d.slice = a.slice; d.depthPlane = a.depth_plane;
    d.resolveTexture = get<Texture>(a.resolve_texture);
    d.loadAction = (LoadAction)a.load_action; d.storeAction = (StoreAction)a.store_action;
    return d;
}
static StencilDescriptor stencil(const MwStencilDesc &s) {
    StencilDescriptor d;
    d.stencilCompareFunction = (CompareFunction)s.compare; d.stencilFailureOperation = (StencilOperation)s.stencil_fail;
    d.depthFailureOperation = (StencilOperation)s.depth_fail; d.depthStencilPassOperation = (StencilOperation)s.pass;
    d.readMask = (uint32_t)s.read_mask; d.writeMask = (uint32_t)s.write_mask;
    return d;
}
/* textures have no getBytes in Indium: blit into a shared buffer and copy out */
static int texture_getbytes(std::shared_ptr<Texture> t, const MwRegionCopy &r) {
    size_t n = r.bytes_per_image ? r.bytes_per_image * r.d : r.bytes_per_row * r.h * r.d;
    auto dev = device();
    auto buf = dev->newBuffer(n, ResourceOptions::StorageModeShared);
    auto q = dev->newCommandQueue(); auto cb = q->commandBuffer(); auto b = cb->blitCommandEncoder();
    b->copy(t, r.slice, r.level, Origin{r.x, r.y, r.z}, Size{r.w, r.h, r.d}, buf, 0, r.bytes_per_row, r.bytes_per_image);
    b->endEncoding(); cb->commit(); cb->waitUntilCompleted();
    memcpy((void *)r.bytes, buf->contents(), n);
    return 0;
}

static int64_t dispatch(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e) {
    static const bool trace = getenv("SCION_METAL_TRACE") != nullptr;
    if (trace) { fprintf(stderr, "scion-metal: op %d %llx %llx %llx\n", op, (unsigned long long)a, (unsigned long long)b, (unsigned long long)c); fflush(stderr); }
    switch (op) {
    case MW_RELEASE: release(a); return 0;
    case MW_DEVICE_CREATE: { auto dv = device(); return dv ? (int64_t)put(dv, K_DEVICE) : 0; }
    case MW_DEVICE_NAME: { auto n = get<Device>(a)->name(); strncpy((char *)b, n.c_str(), c - 1); ((char *)b)[c - 1] = 0; return 0; }
    case MW_NEW_BUFFER: {
        auto dv = get<Device>(a);
        std::shared_ptr<Buffer> buf;
        try { buf = dv->newBuffer(b, (ResourceOptions)c); }   /* out of memory: nil, as in Metal */
        catch (const std::exception &e) { fprintf(stderr, "scion-metal: newBuffer: %s\n", e.what()); return 0; }
        if (buf && d) memcpy(buf->contents(), (const void *)d, b);
        else if (buf && buf->contents()) memset(buf->contents(), 0, b);
        return put(buf, K_BUFFER);
    }
    case MW_NEW_BUFFER_NOCOPY: {
        auto dv = std::dynamic_pointer_cast<PrivateDevice>(get<Device>(a));
        return dv ? (int64_t)put(dv->newBufferNoCopy((void *)b, c, (ResourceOptions)d), K_BUFFER) : 0;
    }
    case MW_DEVICE_HOST_MEMORY: { auto dv = std::dynamic_pointer_cast<PrivateDevice>(get<Device>(a)); return dv ? (int64_t)dv->hostPointerAlignment : 0; }
    case MW_BUFFER_CONTENTS: return (int64_t)get<Buffer>(a)->contents();
    case MW_BUFFER_LENGTH: return (int64_t)get<Buffer>(a)->length();
    case MW_CB_TIMESTAMP: { auto cb = std::dynamic_pointer_cast<PrivateCommandBuffer>(get<CommandBuffer>(a)); uint32_t i = cb ? cb->writeTimestamp() : UINT32_MAX; return i == UINT32_MAX ? -1 : (int64_t)i; }
    case MW_CB_TIMESTAMPS: {
        auto cb = std::dynamic_pointer_cast<PrivateCommandBuffer>(get<CommandBuffer>(a));
        if (!cb) return 0;
        size_t n = std::min<size_t>(cb->timestamps.size(), c);
        memcpy((void *)b, cb->timestamps.data(), n * 8);
        return (int64_t)n;
    }
    case MW_RESOURCE_ID: {
        Entry en = entry(a);
        if (en.kind == K_TEXTURE) { auto t = std::dynamic_pointer_cast<PrivateTexture>(std::static_pointer_cast<Texture>(en.p)); return t ? t->bindlessIndex() : 0; }
        if (en.kind == K_SAMPLER) { auto s = std::dynamic_pointer_cast<PrivateSamplerState>(std::static_pointer_cast<SamplerState>(en.p)); return s ? s->bindlessIndex() : 0; }
        return 0;
    }
    case MW_FUNCTION_ARG_LAYOUT: {
        auto f = std::dynamic_pointer_cast<PrivateFunction>(get<Function>(a));
        if (!f) return -1;
        auto &fi = f->functionInfo(); int64_t *out = (int64_t *)c;
        auto it = fi.argumentIds.find(b); auto sz = fi.argumentSizes.find(b);
        if (it == fi.argumentIds.end()) return -1;
        out[0] = sz != fi.argumentSizes.end() ? (int64_t)sz->second : 0;
        int64_t n = 0;
        for (auto &e : it->second) { if (n == (int64_t)d) break; memcpy(&out[1 + 4 * n], e.data(), 32); n++; }
        return n;
    }
    case MW_BUFFER_GPU_ADDRESS: return (int64_t)get<Buffer>(a)->gpuAddress();
    case MW_NEW_LIBRARY: { if (getenv("SCION_DIAG_NOLIB")) { seterr(d, "SCION_DIAG_NOLIB"); return 0; }   /* diagnostic (memory) */
        auto l = get<Device>(a)->newLibrary((const void *)b, c); if (!l) seterr(d, "invalid metallib"); return put(l, K_LIBRARY); }
    case MW_LIBRARY_FUNCTION: return put(get<Library>(a)->newFunction((const char *)b), K_FUNCTION);
    case MW_NEW_COMPUTE_PSO: { auto p = get<Device>(a)->newComputePipelineState(get<Function>(b)); if (!p) seterr(c, "could not create the compute pipeline"); return put(p, K_CPSO); }
    case MW_COMPUTE_PSO_INFO: { auto p = get<ComputePipelineState>(a); return b == 0 ? (int64_t)p->maxTotalThreadsPerThreadgroup() : (int64_t)p->threadExecutionWidth(); }
    case MW_NEW_RENDER_PSO: {
        const MwRenderPipelineDesc &s = *(const MwRenderPipelineDesc *)b;
        RenderPipelineDescriptor dd;
        dd.vertexFunction = get<Function>(s.vertex_function); dd.fragmentFunction = get<Function>(s.fragment_function);
        /* Metal validates what Vulkan allows: a fragment function that writes depth needs a depth attachment */
        if (auto pf = std::dynamic_pointer_cast<PrivateFunction>(dd.fragmentFunction); pf && pf->functionInfo().writesDepth && !s.depth_format) {
            seterr(c, "fragment function writes depth but the pipeline has no depth attachment"); return 0;
        }
        for (uint64_t i = 0; i < s.color_count && i < MW_MAX_COLOR; i++) {
            RenderPipelineColorAttachmentDescriptor ca; const MwColorAttachmentPipe &x = s.color[i];
            ca.pixelFormat = (PixelFormat)x.pixel_format; ca.writeMask = (ColorWriteMask)x.write_mask; ca.blendingEnabled = x.blending;
            ca.sourceRGBBlendFactor = (BlendFactor)x.src_rgb; ca.destinationRGBBlendFactor = (BlendFactor)x.dst_rgb; ca.rgbBlendOperation = (BlendOperation)x.op_rgb;
            ca.sourceAlphaBlendFactor = (BlendFactor)x.src_a; ca.destinationAlphaBlendFactor = (BlendFactor)x.dst_a; ca.alphaBlendOperation = (BlendOperation)x.op_a;
            dd.colorAttachments.push_back(ca);
        }
        dd.depthAttachmentPixelFormat = (PixelFormat)s.depth_format; dd.stencilAttachmentPixelFormat = (PixelFormat)s.stencil_format;
        dd.rasterSampleCount = s.sample_count ? s.sample_count : 1; dd.rasterizationEnabled = s.rasterization_enabled;
        dd.inputPrimitiveTopology = (PrimitiveTopologyClass)s.topology_class; dd.alphaToCoverageEnabled = s.alpha_to_coverage;
        if (s.has_vertex_desc) {
            VertexDescriptor vd;
            for (size_t i = 0; i < MW_MAX_VERTEX_ATTR; i++) if (s.attr[i].format)
                vd.attributes[i] = VertexAttributeDescriptor{(VertexFormat)s.attr[i].format, s.attr[i].offset, s.attr[i].buffer_index};
            for (size_t i = 0; i < MW_MAX_VERTEX_BUF; i++) if (s.layout[i].stride)
                vd.layouts[i] = VertexBufferLayoutDescriptor{s.layout[i].stride, (VertexStepFunction)s.layout[i].step_function, s.layout[i].step_rate ? s.layout[i].step_rate : 1};
            dd.vertexDescriptor = vd;
        }
        auto p = get<Device>(a)->newRenderPipelineState(dd);
        if (!p) seterr(c, "could not create the render pipeline");
        return put(p, K_RPSO);
    }
    case MW_NEW_TEXTURE: {
        const MwTextureDesc &s = *(const MwTextureDesc *)b;
        TextureDescriptor t;
        t.textureType = (TextureType)s.texture_type; t.pixelFormat = (PixelFormat)s.pixel_format;
        t.width = s.width; t.height = s.height; t.depth = s.depth ? s.depth : 1; t.mipmapLevelCount = s.mip_levels ? s.mip_levels : 1;
        t.sampleCount = s.sample_count ? s.sample_count : 1; t.arrayLength = s.array_length ? s.array_length : 1;
        t.resourceOptions = (ResourceOptions)s.resource_options; t.usage = (TextureUsage)s.usage;
        try { return put(get<Device>(a)->newTexture(t), K_TEXTURE); }
        catch (const std::exception &e) { fprintf(stderr, "scion-metal: newTexture %llux%llu: %s\n", (unsigned long long)t.width, (unsigned long long)t.height, e.what()); return 0; }
    }
    case MW_TEXTURE_REPLACE: {
        const MwRegionCopy &r = *(const MwRegionCopy *)b;
        get<Texture>(a)->replaceRegion(Region{Origin{r.x, r.y, r.z}, Size{r.w, r.h, r.d}}, r.level, r.slice, (const void *)r.bytes, r.bytes_per_row, r.bytes_per_image);
        return 0;
    }
    case MW_TEXTURE_GETBYTES: return texture_getbytes(get<Texture>(a), *(const MwRegionCopy *)b);
    case MW_TEXTURE_VIEW: {
        const uint64_t *v = (const uint64_t *)b;
        TextureSwizzleChannels sw;
        sw.red = (TextureSwizzle)(v[6] & 255); sw.green = (TextureSwizzle)((v[6] >> 8) & 255);
        sw.blue = (TextureSwizzle)((v[6] >> 16) & 255); sw.alpha = (TextureSwizzle)((v[6] >> 24) & 255);
        try {
            auto t = get<Texture>(a)->newTextureView((PixelFormat)v[0], (TextureType)v[1], Range<size_t>{v[2], v[3]}, Range<size_t>{v[4], v[5]}, sw);
            return t ? put(t, K_TEXTURE) : 0;
        } catch (...) { return 0; }
    }
    case MW_NEW_SAMPLER: {
        const MwSamplerDesc &s = *(const MwSamplerDesc *)b;
        SamplerDescriptor sd;
        sd.minFilter = (SamplerMinMagFilter)s.min_filter; sd.magFilter = (SamplerMinMagFilter)s.mag_filter; sd.mipFilter = (SamplerMipFilter)s.mip_filter;
        sd.maxAnisotropy = s.max_anisotropy ? s.max_anisotropy : 1;
        sd.sAddressMode = (SamplerAddressMode)s.s_address; sd.tAddressMode = (SamplerAddressMode)s.t_address; sd.rAddressMode = (SamplerAddressMode)s.r_address;
        sd.borderColor = (SamplerBorderColor)s.border_color; sd.normalizedCoordinates = s.normalized; sd.compareFunction = (CompareFunction)s.compare;
        sd.lodMinClamp = s.lod_min; sd.lodMaxClamp = s.lod_max;
        return put(get<Device>(a)->newSamplerState(sd), K_SAMPLER);
    }
    case MW_NEW_DEPTH_STENCIL: {
        const MwDepthStencilDesc &s = *(const MwDepthStencilDesc *)b;
        DepthStencilDescriptor ds;
        ds.depthCompareFunction = (CompareFunction)s.depth_compare; ds.depthWriteEnabled = s.depth_write;
        if (s.front.enabled) ds.frontFaceStencil = stencil(s.front);
        if (s.back.enabled) ds.backFaceStencil = stencil(s.back);
        return put(get<Device>(a)->newDepthStencilState(ds), K_DSS);
    }
    case MW_NEW_QUEUE: return put(get<Device>(a)->newCommandQueue(), K_QUEUE);
    case MW_QUEUE_COMMAND_BUFFER: return put(get<CommandQueue>(a)->commandBuffer(), K_CB);
    case MW_CB_COMPUTE_ENCODER: return put(get<CommandBuffer>(a)->computeCommandEncoder(), K_CENC);
    case MW_CB_BLIT_ENCODER: return put(get<CommandBuffer>(a)->blitCommandEncoder(), K_BENC);
    case MW_CB_RENDER_ENCODER: {
        const MwRenderPassDesc &s = *(const MwRenderPassDesc *)b;
        RenderPassDescriptor rp;
        for (uint64_t i = 0; i < s.color_count && i < MW_MAX_COLOR; i++) {
            RenderPassColorAttachmentDescriptor ca;
            static_cast<RenderPassAttachmentDescriptor &>(ca) = pass_att(s.color[i]);
            ca.clearColor = clear_color(ca.texture, s.color[i].clear);
            rp.colorAttachments.push_back(ca);
        }
        if (s.depth.texture) { RenderPassDepthAttachmentDescriptor da; static_cast<RenderPassAttachmentDescriptor &>(da) = pass_att(s.depth); da.clearDepth = s.depth.clear[0]; rp.depthAttachment = da; }
        if (s.stencil.texture) { RenderPassStencilAttachmentDescriptor sa; static_cast<RenderPassAttachmentDescriptor &>(sa) = pass_att(s.stencil); sa.clearStencil = (uint32_t)s.stencil.clear[1]; rp.stencilAttachment = sa; }
        rp.renderTargetWidth = s.width; rp.renderTargetHeight = s.height;
        if (s.visibility) { rp.visibilityResultBuffer = get<Buffer>(s.visibility); rp.visibilityAccumulate = s.visibility_accumulate; }
        rp.renderTargetArrayLength = s.array_length; rp.defaultRasterSampleCount = 1;
        return put(get<CommandBuffer>(a)->renderCommandEncoder(rp), K_RENC);
    }
    case MW_CB_COMMIT: get<CommandBuffer>(a)->commit(); return 0;
    case MW_CB_WAIT: get<CommandBuffer>(a)->waitUntilCompleted(); return 0;
    case MW_CB_PRESENT: get<CommandBuffer>(a)->presentDrawable(get<Drawable>(b)); return 0;
    case MW_ENC_END: {
        Entry en = entry(a);
        if (en.kind == K_CENC) std::static_pointer_cast<ComputeCommandEncoder>(en.p)->endEncoding();
        else if (en.kind == K_RENC) std::static_pointer_cast<RenderCommandEncoder>(en.p)->endEncoding();
        else if (en.kind == K_BENC) std::static_pointer_cast<BlitCommandEncoder>(en.p)->endEncoding();
        return 0;
    }
    case MW_CE_SET_PSO: get<ComputeCommandEncoder>(a)->setComputePipelineState(get<ComputePipelineState>(b)); return 0;
    case MW_CE_DISPATCH: {
        const MwSize3 &g = *(const MwSize3 *)b, &t = *(const MwSize3 *)c;
        auto en = get<ComputeCommandEncoder>(a);
        if (d == 2) std::dynamic_pointer_cast<PrivateComputeCommandEncoder>(en)->dispatchIndirect(get<Buffer>(g.w), g.h, Size{t.w, t.h, t.d}); /* g: {indirect buffer, offset} */
        else if (d) en->dispatchThreads(Size{g.w, g.h, g.d}, Size{t.w, t.h, t.d}); else en->dispatchThreadgroups(Size{g.w, g.h, g.d}, Size{t.w, t.h, t.d});
        return 0;
    }
    case MW_SET_BUFFER: case MW_SET_BYTES: case MW_SET_TEXTURE: case MW_SET_SAMPLER: {
        Entry en = entry(a);
        if (en.kind == K_CENC) {
            auto ce = std::static_pointer_cast<ComputeCommandEncoder>(en.p);
            if (op == MW_SET_BUFFER) ce->setBuffer(get<Buffer>(c), d, e);
            else if (op == MW_SET_BYTES) ce->setBytes((const void *)c, d, e);
            else if (op == MW_SET_TEXTURE) ce->setTexture(get<Texture>(c), d);
            else ce->setSamplerState(get<SamplerState>(c), d);
        } else if (en.kind == K_RENC) {
            auto re = std::static_pointer_cast<RenderCommandEncoder>(en.p);
            bool frag = b == 1;
            if (op == MW_SET_BUFFER) frag ? re->setFragmentBuffer(get<Buffer>(c), d, e) : re->setVertexBuffer(get<Buffer>(c), d, e);
            else if (op == MW_SET_BYTES) frag ? re->setFragmentBytes((const void *)c, d, e) : re->setVertexBytes((const void *)c, d, e);
            else if (op == MW_SET_TEXTURE) frag ? re->setFragmentTexture(get<Texture>(c), d) : re->setVertexTexture(get<Texture>(c), d);
            else frag ? re->setFragmentSamplerState(get<SamplerState>(c), d) : re->setVertexSamplerState(get<SamplerState>(c), d);
        }
        return 0;
    }
    case MW_RE_SET_PSO: get<RenderCommandEncoder>(a)->setRenderPipelineState(get<RenderPipelineState>(b)); return 0;
    case MW_RE_SET_VIEWPORT: { /* c viewports of six doubles */
        const double *v = (const double *)b; std::vector<Viewport> vp;
        for (uint64_t i = 0; i < (c ? c : 1); i++, v += 6) vp.push_back(Viewport{v[0], v[1], v[2], v[3], v[4], v[5]});
        get<RenderCommandEncoder>(a)->setViewports(vp); return 0;
    }
    case MW_RE_SET_SCISSOR: { /* c rects of four uint64 (x, y, width, height) */
        const uint64_t *v = (const uint64_t *)b; std::vector<ScissorRect> rs;
        for (uint64_t i = 0; i < (c ? c : 1); i++, v += 4) { ScissorRect r; r.x = v[0]; r.y = v[1]; r.width = v[2]; r.height = v[3]; rs.push_back(r); }
        get<RenderCommandEncoder>(a)->setScissorRects(rs); return 0;
    }
    case MW_RE_SET_STATE: {
        auto re = get<RenderCommandEncoder>(a);
        if (b == 0) re->setCullMode((CullMode)c);
        else if (b == 1) re->setFrontFacingWinding((Winding)c);
        else if (b == 2) re->setTriangleFillMode((TriangleFillMode)c);
        else if (b == 3) re->setDepthClipMode((DepthClipMode)c);
        else if (b == 4) re->setStencilReferenceValue((uint32_t)c, (uint32_t)d);
        else if (b == 5) { const float *f = (const float *)c; re->setDepthBias(f[0], f[1], f[2]); }
        else if (b == 6) { const float *f = (const float *)c; re->setBlendColor(f[0], f[1], f[2], f[3]); }
        else if (b == 7) re->setVisibilityResultMode((VisibilityResultMode)c, d);
        else if (b == 8) re->barrier();
        return 0;
    }
    case MW_RE_SET_DEPTH_STENCIL: get<RenderCommandEncoder>(a)->setDepthStencilState(get<DepthStencilState>(b)); return 0;
    case MW_RE_DRAW: {
        const MwDraw &s = *(const MwDraw *)b; auto re = get<RenderCommandEncoder>(a);
        size_t inst = s.instance_count ? s.instance_count : 1;
        if (s.indexed >= 2) /* indirect: buffer in vertex_start, offset in count */
            std::dynamic_pointer_cast<PrivateRenderCommandEncoder>(re)->drawIndirect((PrimitiveType)s.primitive, (IndexType)s.index_type, s.indexed == 3 ? get<Buffer>(s.index_buffer) : nullptr, s.index_offset, get<Buffer>(s.vertex_start), s.count);
        else if (s.indexed) re->drawIndexedPrimitives((PrimitiveType)s.primitive, s.count, (IndexType)s.index_type, get<Buffer>(s.index_buffer), s.index_offset, inst, s.base_vertex, s.base_instance);
        else re->drawPrimitives((PrimitiveType)s.primitive, s.vertex_start, s.count, inst, s.base_instance);
        return 0;
    }
    case MW_BLIT: {
        const MwBlit &s = *(const MwBlit *)b; auto be = get<BlitCommandEncoder>(a);
        switch (s.kind) {
        case 0: be->copy(get<Buffer>(s.src), s.src_offset, get<Buffer>(s.dst), s.dst_offset, s.size); break;
        case 1: be->copy(get<Buffer>(s.src), s.src_offset, s.src_bytes_per_row, s.src_bytes_per_image, Size{s.w, s.h, s.d}, get<Texture>(s.dst), s.dst_slice, s.dst_level, Origin{s.dx, s.dy, s.dz}, (BlitOption)s.value); break;
        case 2: be->copy(get<Texture>(s.src), s.src_slice, s.src_level, Origin{s.sx, s.sy, s.sz}, Size{s.w, s.h, s.d}, get<Buffer>(s.dst), s.dst_offset, s.dst_bytes_per_row, s.dst_bytes_per_image, (BlitOption)s.value); break;
        case 3: be->copy(get<Texture>(s.src), s.src_slice, s.src_level, Origin{s.sx, s.sy, s.sz}, Size{s.w, s.h, s.d}, get<Texture>(s.dst), s.dst_slice, s.dst_level, Origin{s.dx, s.dy, s.dz}); break;
        case 4: be->fillBuffer(get<Buffer>(s.dst), Range<size_t>{s.dst_offset, s.size}, (uint8_t)s.value); break;
        case 5: be->generateMipmapsForTexture(get<Texture>(s.dst)); break;
        }
        return 0;
    }
#ifdef _WIN32
    case MW_NEW_LAYER: return device() ? put(new_window((int)a, (int)b, (const char *)c, d, (HWND)e), K_LAYER) : 0;
#else
    case MW_NEW_LAYER: return device() ? put(new_window((int)a, (int)b, (const char *)c, d, (const MwNativeWindow *)e), K_LAYER) : 0;
#endif
    case MW_LAYER_NEXT_DRAWABLE: {
        auto win = get<Window>(a);
        auto layer = std::dynamic_pointer_cast<IndiumKit::PrivateLayer>(win->layer);
        /* size and format changes apply here, between frames: the drawable the app holds now must stay valid */
        if (uint64_t f = win->format.exchange(0)) layer->setPixelFormat((PixelFormat)f);
#ifdef _WIN32
        if (win->external) { /* ponytail: the whole client area, even for a view that covers only part of it */
            RECT rc; GetClientRect(win->hwnd, &rc);
            if (rc.right > 0 && rc.bottom > 0) { win->cw = rc.right; win->ch = rc.bottom; }
        }
#else
        win->query();
#endif
        if (win->cw && win->ch) layer->resize(win->cw, win->ch); /* the user resized the window */
        auto dr = layer->nextDrawable();
        if (!dr) return 0;
        uint64_t *out = (uint64_t *)b;
        out[0] = put(dr->texture(), K_TEXTURE);
        out[1] = layer->width(); out[2] = layer->height(); out[3] = (uint64_t)layer->pixelFormat();
        return put(std::static_pointer_cast<Indium::Drawable>(dr), K_DRAWABLE);
    }
    case MW_LAYER_SET_FORMAT: get<Window>(a)->format = b; return 0;
    case MW_LAYER_SET_SIZE: {
        auto win = get<Window>(a);
#ifdef _WIN32
        if (!win->external && b && c && (b != win->cw || c != win->ch)) PostMessageW(win->hwnd, WM_APP, (WPARAM)b, (LPARAM)c);
#endif
        return 0;
    }
#ifndef _WIN32
    case MW_LAYER_POLL: { auto w = get<Window>(a); w->query(); return w->closed; }
#else
    case MW_LAYER_POLL: return get<Window>(a)->closed;
#endif
    case MW_DRAWABLE_PRESENT: get<Indium::Drawable>(a)->present(); return 0;
    case MW_FUNCTION_CONSTANTS: {
        auto f = std::dynamic_pointer_cast<PrivateFunction>(get<Function>(a));
        const uint32_t *p = (const uint32_t *)b;
        for (uint64_t i = 0; i < c; i++) f->specConstants.push_back({p[2 * i], p[2 * i + 1]});
        return 0;
    }
    case MW_FUNCTION_FC_INFO: {
        auto f = std::dynamic_pointer_cast<PrivateFunction>(get<Function>(a));
        std::string s;
        for (auto &[name, index] : f->functionInfo().functionConstants) s += name + "\t" + std::to_string(index) + "\n";
        if (b && c) { strncpy((char *)b, s.c_str(), c - 1); ((char *)b)[c - 1] = 0; }
        return (int64_t)f->functionInfo().functionConstants.size();
    }
    case MW_COMPILE_SOURCE: return compile_source((const char *)a, (const char *)b, (char *)c, d, (uint64_t *)e);
    case MW_HOST_FREE: free((void *)a); return 0;
    }
    return -38; /* ENOSYS */
}

/* ------------------------------------------------------------------ MSL source -> metallib
 * The compiler (clang + metal_stdlib) lives in scion-msl.dll, next to this DLL, loaded on first use. Results are cached
 * on disk (%LOCALAPPDATA%\\scion\\msl\\<hash>.metallib): apps that build shaders at run time compile the same ones every launch. */
static struct Msl {
    const char *(*version)();
    void *(*compile)(const char *, const char *, size_t *, char *, size_t);
    void (*release)(void *);
} g_msl;
static bool msl_load(std::string &why) {
    static std::once_flag once;
    static std::string error;
    std::call_once(once, [] {
#ifndef _WIN32
        Dl_info di{};
        dladdr((void *)&msl_load, &di);
        std::string dir = di.dli_fname ? di.dli_fname : "";
        dir = dir.substr(0, dir.find_last_of('/') + 1);
        void *m = dlopen((dir + "scion-msl.so").c_str(), RTLD_NOW | RTLD_LOCAL);
        if (!m) { error = "scion: scion-msl.so (the MSL compiler) is missing"; return; }
        g_msl.version = (const char *(*)())dlsym(m, "mw_msl_version");
        g_msl.compile = (void *(*)(const char *, const char *, size_t *, char *, size_t))dlsym(m, "mw_msl_compile");
        g_msl.release = (void (*)(void *))dlsym(m, "mw_msl_free");
        if (!g_msl.version || !g_msl.compile || !g_msl.release) { g_msl = {}; error = "scion: invalid scion-msl.so"; }
#else
        HMODULE self = nullptr;
        GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)&msl_load, &self);
        char path[MAX_PATH];
        DWORD n = GetModuleFileNameA(self, path, MAX_PATH);
        std::string dir(path, n);
        dir = dir.substr(0, dir.find_last_of("\\/") + 1);
        HMODULE m = LoadLibraryA((dir + "scion-msl.dll").c_str());
        if (!m) { error = "scion: scion-msl.dll (the MSL compiler) is missing"; return; }
        g_msl.version = (const char *(*)())GetProcAddress(m, "mw_msl_version");
        g_msl.compile = (void *(*)(const char *, const char *, size_t *, char *, size_t))GetProcAddress(m, "mw_msl_compile");
        g_msl.release = (void (*)(void *))GetProcAddress(m, "mw_msl_free");
        if (!g_msl.version || !g_msl.compile || !g_msl.release) { g_msl = {}; error = "scion: invalid scion-msl.dll"; }
#endif
    });
    why = error;
    return g_msl.compile != nullptr;
}
static std::string msl_cache_path(const std::string &src, const std::string &macros) {
    uint64_t h = 1469598103934665603ull;
    auto mix = [&](const std::string &x) { for (unsigned char ch : x) { h ^= ch; h *= 1099511628211ull; } h ^= 0xff; h *= 1099511628211ull; };
    mix(g_msl.version());
    mix(macros);
    mix(src);
#ifdef _WIN32
    const char *base = getenv("LOCALAPPDATA");
    if (!base || getenv("SCION_MSL_NOCACHE")) return "";
    std::string dir = std::string(base) + "\\scion";
    CreateDirectoryA(dir.c_str(), nullptr);
    dir += "\\msl";
    CreateDirectoryA(dir.c_str(), nullptr);
    char name[32];
    snprintf(name, sizeof name, "\\%016llx.metallib", (unsigned long long)h);
#else   /* $XDG_CACHE_HOME/scion/msl */
    const char *xdg = getenv("XDG_CACHE_HOME"), *home = getenv("HOME");
    if ((!xdg && !home) || getenv("SCION_MSL_NOCACHE")) return "";
    std::string dir = xdg ? xdg : std::string(home) + "/.cache";
    mkdir(dir.c_str(), 0755); dir += "/scion"; mkdir(dir.c_str(), 0755); dir += "/msl"; mkdir(dir.c_str(), 0755);
    char name[32];
    snprintf(name, sizeof name, "/%016llx.metallib", (unsigned long long)h);
#endif
    return dir + name;
}
static int64_t compile_source(const char *src, const char *macros, char *err, size_t errsz, uint64_t *len) {
    std::string why;
    if (!msl_load(why)) {
        if (err && errsz) { strncpy(err, why.c_str(), errsz - 1); err[errsz - 1] = 0; }
        return 0;
    }
    std::string s(src), mac(macros ? macros : "");
    /* CRLF sources (written on Windows): the compiler would not recognise `#include <metal_stdlib>\r` */
    s.erase(std::remove(s.begin(), s.end(), '\r'), s.end());
    std::string path = msl_cache_path(s, mac);
    if (FILE *f = path.empty() ? nullptr : fopen(path.c_str(), "rb")) {
        fseek(f, 0, SEEK_END);
        size_t n = size_t(ftell(f));
        fseek(f, 0, SEEK_SET);
        void *p = malloc(n);
        bool ok = n && fread(p, 1, n, f) == n;
        fclose(f);
        if (ok) { *len = n; return (int64_t)p; }
        free(p);
    }
    size_t n = 0;
    void *lib = g_msl.compile(s.c_str(), mac.c_str(), &n, err, errsz);
    if (!lib) {
        if (getenv("SCION_METAL_INFO") && err) fprintf(stderr, "scion-metal: MSL:\n%s\n", err);
        return 0;
    }
    if (!path.empty())
        if (FILE *f = fopen(path.c_str(), "wb")) { fwrite(lib, 1, n, f); fclose(f); }
    void *p = malloc(n); /* our own heap: MW_HOST_FREE frees it here */
    memcpy(p, lib, n);
    g_msl.release(lib);
    *len = n;
    return (int64_t)p;
}

#ifdef _WIN32
#define MW_EXPORT __declspec(dllexport)
#else
#define MW_EXPORT __attribute__((visibility("default")))
#endif
extern "C" MW_EXPORT int64_t mw_metal(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e) {
    try {
        return dispatch(op, a, b, c, d, e);
    } catch (const std::exception &x) {
        fprintf(stderr, "scion-metal: op %d: %s\n", op, x.what());
    } catch (...) {
        fprintf(stderr, "scion-metal: op %d: exception\n", op);
    }
    return 0;
}
