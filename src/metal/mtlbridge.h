/* mtlbridge.h — the only boundary between the guest Metal.framework (Mach-O, Objective-C) and the host Metal
 * implementation (scion-metal.dll: Indium on Vulkan + Iridium). One entry point:
 *     int64_t mw_metal(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e)
 * Objects are opaque handles (> 0). Enum values are Metal's raw values (MTLPixelFormat, MTLVertexFormat…).
 * Structs are plain C, identical on both sides (little-endian, 64-bit). */
#pragma once
#include <stdint.h>

/* Linux: the window a layer draws into (an X11 window, from the SDL window of an AppKit window or one of its own) */
typedef struct {
    void *display;                                        /* X11 Display* */
    uint64_t window;                                      /* X11 Window */
    void (*size)(void *ctx, uint32_t *w, uint32_t *h);   /* its current client size, pixels */
    int (*closed)(void *ctx);                             /* 1 once the user closed it (a window of the layer's own) */
    void *ctx;
} MwNativeWindow;

enum {
    MW_RELEASE = 1,           /* h */
    MW_DEVICE_CREATE,         /* -> device */
    MW_DEVICE_NAME,           /* device, char *buf, n */
    MW_NEW_BUFFER,            /* device, length, options, const void *bytes (0 = zeroed) -> buffer */
    MW_BUFFER_CONTENTS,       /* buffer -> pointer */
    MW_BUFFER_LENGTH,         /* buffer -> length */
    MW_NEW_LIBRARY,           /* device, data, length, char err[256] -> library */
    MW_LIBRARY_FUNCTION,      /* library, const char *name -> function | 0 */
    MW_NEW_COMPUTE_PSO,       /* device, function, char err[256] -> pso */
    MW_COMPUTE_PSO_INFO,      /* pso, which (0 maxTotalThreadsPerThreadgroup, 1 threadExecutionWidth) */
    MW_NEW_RENDER_PSO,        /* device, const MwRenderPipelineDesc*, char err[256] -> pso */
    MW_NEW_TEXTURE,           /* device, const MwTextureDesc* -> texture */
    MW_TEXTURE_REPLACE,       /* texture, const MwRegionCopy* */
    MW_TEXTURE_GETBYTES,      /* texture, const MwRegionCopy* */
    MW_NEW_SAMPLER,           /* device, const MwSamplerDesc* -> sampler */
    MW_NEW_DEPTH_STENCIL,     /* device, const MwDepthStencilDesc* -> state */
    MW_NEW_QUEUE,             /* device -> queue */
    MW_QUEUE_COMMAND_BUFFER,  /* queue -> command buffer */
    MW_CB_COMPUTE_ENCODER,    /* cb -> encoder */
    MW_CB_RENDER_ENCODER,     /* cb, const MwRenderPassDesc* -> encoder */
    MW_CB_BLIT_ENCODER,       /* cb -> encoder */
    MW_CB_COMMIT,             /* cb */
    MW_CB_WAIT,               /* cb */
    MW_CB_PRESENT,            /* cb, drawable */
    MW_ENC_END,               /* encoder */
    MW_CE_SET_PSO,            /* enc, pso */
    MW_CE_DISPATCH,           /* enc, const MwSize3 *grid, const MwSize3 *group, threads (1) / threadgroups (0) */
    MW_SET_BUFFER,            /* enc, stage (0 vertex/compute, 1 fragment), buffer, offset, index */
    MW_SET_BYTES,             /* enc, stage, bytes, length, index */
    MW_SET_TEXTURE,           /* enc, stage, texture, index */
    MW_SET_SAMPLER,           /* enc, stage, sampler, index */
    MW_RE_SET_PSO,            /* enc, pso */
    MW_RE_SET_VIEWPORT,       /* enc, const double[6] {x, y, w, h, znear, zfar} */
    MW_RE_SET_SCISSOR,        /* enc, const uint64_t[4] {x, y, w, h} */
    MW_RE_SET_STATE,          /* enc, what (0 cull, 1 winding, 2 fill mode, 3 depth clip, 4 stencil ref front/back, 5 depth bias float[3], 6 blend color float[4], 7 visibility mode + offset), value(s) */
    MW_RE_SET_DEPTH_STENCIL,  /* enc, state */
    MW_RE_DRAW,               /* enc, const MwDraw* */
    MW_BLIT,                  /* enc, const MwBlit* */
    MW_NEW_LAYER,             /* width, height, const char *title, pixel format, HWND (0: own window) / const MwNativeWindow* (Linux) -> layer (window + Vulkan swapchain) */
    MW_LAYER_NEXT_DRAWABLE,   /* layer, uint64_t out[4] {texture, width, height, pixel format} -> drawable | 0 (timeout); the size follows the window */
    MW_LAYER_POLL,            /* layer -> 0 open, 1 closed by the user */
    MW_DRAWABLE_PRESENT,      /* drawable */
    MW_FUNCTION_CONSTANTS,    /* function, const uint32_t *pairs {index, raw 32-bit value}, count */
    MW_FUNCTION_FC_INFO,      /* function, char *buf, size: writes "name\tindex\n" lines -> number of constants */
    MW_COMPILE_SOURCE,        /* const char *msl, const char *macros ("#define A B\n"), char *err, err size, uint64_t *len -> metallib (host memory) | 0 */
    MW_HOST_FREE,             /* pointer returned by MW_COMPILE_SOURCE */
    MW_LAYER_SET_FORMAT,      /* layer, pixel format: the swapchain is rebuilt at the next drawable */
    MW_LAYER_SET_SIZE,        /* layer, width, height: resizes the window's client area */
    MW_TEXTURE_VIEW,          /* texture, const uint64_t v[7] {pixel format, type, level start, levels, slice start, slices, swizzle rgba bytes} -> texture */
    MW_BUFFER_GPU_ADDRESS,    /* buffer -> its Vulkan device address (what shaders dereference) */
    MW_FUNCTION_ARG_LAYOUT,   /* function, buffer index, int64_t *out, max entries: out[0] = size, then {id, offset, kind, count} -> entries | -1 (unknown) */
    MW_RESOURCE_ID,           /* texture | sampler -> its index in the bindless table (its Metal resource ID; 0: none) */
    MW_CB_TIMESTAMP,          /* cb -> index of a GPU timestamp written here (-1: none) */
    MW_CB_TIMESTAMPS,         /* cb, uint64_t *out, max -> count: the timestamps in ns, after completion */
    MW_NEW_BUFFER_NOCOPY,     /* device, void *bytes, length, options -> buffer over those bytes | 0 (cannot import them) */
    MW_DEVICE_HOST_MEMORY,    /* device -> alignment of the memory MW_NEW_BUFFER_NOCOPY imports, 0 = none */
    MW_OP_COUNT
};

typedef struct { uint64_t w, h, d; } MwSize3;

typedef struct {
    uint64_t texture_type, pixel_format, width, height, depth, mip_levels, sample_count, array_length, resource_options, usage;
} MwTextureDesc;

typedef struct { /* replaceRegion / getBytes */
    uint64_t x, y, z, w, h, d, level, slice;
    uint64_t bytes, bytes_per_row, bytes_per_image;
} MwRegionCopy;

typedef struct {
    uint64_t min_filter, mag_filter, mip_filter, max_anisotropy, s_address, t_address, r_address, border_color, normalized, compare;
    float lod_min, lod_max;
} MwSamplerDesc;

typedef struct {
    uint64_t compare, read_mask, write_mask, stencil_fail, depth_fail, pass, enabled;
} MwStencilDesc;
typedef struct {
    uint64_t depth_compare, depth_write;
    MwStencilDesc front, back;
} MwDepthStencilDesc;

#define MW_MAX_COLOR 8
#define MW_MAX_VERTEX_ATTR 31
#define MW_MAX_VERTEX_BUF 31
typedef struct {
    uint64_t pixel_format, write_mask, blending, src_rgb, dst_rgb, op_rgb, src_a, dst_a, op_a;
} MwColorAttachmentPipe;
typedef struct {
    uint64_t vertex_function, fragment_function;           /* function handles */
    uint64_t color_count;
    MwColorAttachmentPipe color[MW_MAX_COLOR];
    uint64_t depth_format, stencil_format, sample_count, rasterization_enabled, topology_class, alpha_to_coverage;
    uint64_t has_vertex_desc;
    struct { uint64_t format, offset, buffer_index; } attr[MW_MAX_VERTEX_ATTR];
    struct { uint64_t stride, step_function, step_rate; } layout[MW_MAX_VERTEX_BUF];
} MwRenderPipelineDesc;

typedef struct {
    uint64_t texture, level, slice, depth_plane, resolve_texture, load_action, store_action;
    double clear[4];     /* color rgba, or clear depth in [0], clear stencil in [1] */
} MwPassAttachment;
typedef struct {
    uint64_t color_count;
    MwPassAttachment color[MW_MAX_COLOR];
    MwPassAttachment depth, stencil;           /* texture == 0: none */
    uint64_t width, height;                    /* renderTargetWidth/Height (0 = from attachments) */
    uint64_t visibility, visibility_accumulate; /* visibilityResultBuffer; Metal 4 MTLVisibilityResultTypeAccumulate */
    uint64_t array_length;                     /* renderTargetArrayLength: layered rendering */
} MwRenderPassDesc;

typedef struct {
    uint64_t indexed, primitive, vertex_start, count, instance_count, base_instance;
    uint64_t index_type, index_buffer, index_offset; int64_t base_vertex;
} MwDraw; /* indexed: 0 no, 1 yes, 2 indirect, 3 indirect indexed (indirect buffer in vertex_start, its offset in count) */

typedef struct {
    uint64_t kind;            /* 0 buffer->buffer, 1 buffer->texture, 2 texture->buffer, 3 texture->texture, 4 fill buffer, 5 mipmaps */
    uint64_t src, src_offset, src_bytes_per_row, src_bytes_per_image, src_slice, src_level, sx, sy, sz;
    uint64_t dst, dst_offset, dst_bytes_per_row, dst_bytes_per_image, dst_slice, dst_level, dx, dy, dz;
    uint64_t w, h, d, size, value;
} MwBlit;
