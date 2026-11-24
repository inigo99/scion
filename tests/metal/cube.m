/* A 3D cube with Metal (cube.metallib, from Indium's "cube" test): vertex/index buffers, uniforms, depth (Depth32Float)
 * and indexed drawing. Offscreen render -> cube.bmp + checks. Prints "METAL CUBE OK". */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <simd/simd.h>
#include <math.h>

typedef struct { vector_float4 position, color; } Vertex;
typedef struct { matrix_float4x4 mvp; } Uniforms;

static matrix_float4x4 rot(float a, vector_float3 ax) {
    float c = cosf(a), s = sinf(a), t = 1 - c, x = ax.x, y = ax.y, z = ax.z;
    return simd_matrix((vector_float4){t * x * x + c, t * x * y + z * s, t * x * z - y * s, 0},
                       (vector_float4){t * x * y - z * s, t * y * y + c, t * y * z + x * s, 0},
                       (vector_float4){t * x * z + y * s, t * y * z - x * s, t * z * z + c, 0}, (vector_float4){0, 0, 0, 1});
}
static matrix_float4x4 perspective(float fovy, float aspect, float n, float f) {  /* right-handed, depth 0..1 (Metal) */
    float ys = 1 / tanf(fovy * 0.5f), xs = ys / aspect, zs = f / (n - f);
    return simd_matrix((vector_float4){xs, 0, 0, 0}, (vector_float4){0, ys, 0, 0}, (vector_float4){0, 0, zs, -1}, (vector_float4){0, 0, zs * n, 0});
}
static void save_bmp(const char *path, const uint8_t *bgra, int w, int h) {
    FILE *f = fopen(path, "wb"); if (!f) return;
    uint32_t size = 54 + w * h * 4; uint8_t hd[54] = {'B', 'M'}; memcpy(hd + 2, &size, 4); hd[10] = 54; hd[14] = 40;
    memcpy(hd + 18, &w, 4); int nh = -h; memcpy(hd + 22, &nh, 4); hd[26] = 1; hd[28] = 32;
    fwrite(hd, 1, 54, f); fwrite(bgra, 1, w * h * 4, f); fclose(f);
}

#define STEP(x) fprintf(stderr, "step: %s\n", x)   /* unbuffered stderr: shows how far it got if something fails */

int main(int argc, char **argv) {
    @autoreleasepool {
        const int W = 320, H = 240;
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        NSString *dir = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        NSError *err = nil;
        STEP("device");
        id<MTLLibrary> lib = [dev newLibraryWithFile:[dir stringByAppendingPathComponent:@"cube.metallib"] error:&err];
        if (!lib) { printf("METAL: %s\n", err.localizedDescription.UTF8String); return 1; }
        STEP("metallib");
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [lib newFunctionWithName:@"vertex_project"];
        pd.fragmentFunction = [lib newFunctionWithName:@"fragment_flatcolor"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pd.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        MTLDepthStencilDescriptor *dd = [MTLDepthStencilDescriptor new];
        dd.depthCompareFunction = MTLCompareFunctionLess; dd.depthWriteEnabled = YES;
        id<MTLDepthStencilState> ds = [dev newDepthStencilStateWithDescriptor:dd];

        STEP("pipeline");
        static const Vertex v[] = {
            {{-1, 1, 1, 1}, {0, 1, 1, 1}}, {{-1, -1, 1, 1}, {0, 0, 1, 1}}, {{1, -1, 1, 1}, {1, 0, 1, 1}}, {{1, 1, 1, 1}, {1, 1, 1, 1}},
            {{-1, 1, -1, 1}, {0, 1, 0, 1}}, {{-1, -1, -1, 1}, {0, 0, 0, 1}}, {{1, -1, -1, 1}, {1, 0, 0, 1}}, {{1, 1, -1, 1}, {1, 1, 0, 1}},
        };
        static const uint16_t idx[] = {3, 2, 6, 6, 7, 3, 4, 5, 1, 1, 0, 4, 4, 0, 3, 3, 7, 4, 1, 5, 6, 6, 2, 1, 0, 1, 2, 2, 3, 0, 7, 6, 5, 5, 4, 7};
        id<MTLBuffer> vb = [dev newBufferWithBytes:v length:sizeof v options:MTLResourceStorageModeShared];
        id<MTLBuffer> ib = [dev newBufferWithBytes:idx length:sizeof idx options:MTLResourceStorageModeShared];
        id<MTLBuffer> ub = [dev newBufferWithLength:sizeof(Uniforms) options:MTLResourceStorageModeShared];
        matrix_float4x4 model = matrix_multiply(rot(0.6f, (vector_float3){1, 0, 0}), rot(0.8f, (vector_float3){0, 1, 0}));
        matrix_float4x4 view = matrix_identity_float4x4; view.columns[3] = (vector_float4){0, 0, -5, 1};
        ((Uniforms *)ub.contents)->mvp = matrix_multiply(perspective(2 * M_PI / 5, (float)W / H, 1, 100), matrix_multiply(view, model));

        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:H mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        STEP("buffers");
        id<MTLTexture> color = [dev newTextureWithDescriptor:td];
        MTLTextureDescriptor *zd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:W height:H mipmapped:NO];
        zd.usage = MTLTextureUsageRenderTarget; zd.storageMode = MTLStorageModePrivate;
        STEP("color texture");
        id<MTLTexture> depth = [dev newTextureWithDescriptor:zd];

        STEP("depth texture");
        id<MTLCommandQueue> q = [dev newCommandQueue];
        id<MTLCommandBuffer> cb = [q commandBuffer];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = color; rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.1, 0.15, 1);
        rp.depthAttachment.texture = depth; rp.depthAttachment.loadAction = MTLLoadActionClear; rp.depthAttachment.clearDepth = 1.0;
        id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
        [e setViewport:(MTLViewport){0, 0, W, H, 0, 1}];
        [e setRenderPipelineState:pso];
        [e setDepthStencilState:ds];
        [e setCullMode:MTLCullModeBack];
        [e setFrontFacingWinding:MTLWindingCounterClockwise];
        [e setVertexBuffer:vb offset:0 atIndex:0];
        [e setVertexBuffer:ub offset:0 atIndex:1];
        [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:36 indexType:MTLIndexTypeUInt16 indexBuffer:ib indexBufferOffset:0];
        [e endEncoding];
        STEP("encoded");
        [cb commit]; [cb waitUntilCompleted];

        STEP("render done");
        uint8_t *px = malloc(W * H * 4);
        [color getBytes:px bytesPerRow:W * 4 fromRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0];
        STEP("getBytes");
        save_bmp([[dir stringByAppendingPathComponent:@"cube.bmp"] fileSystemRepresentation], px, W, H);
        int lit = 0, colors = 0; int seen[8] = {0};
        for (int i = 0; i < W * H; i++) {
            uint8_t *p = px + i * 4;
            if (abs(p[0] - 38) + abs(p[1] - 25) + abs(p[2] - 25) > 12) { lit++; seen[(p[2] > 127) * 4 + (p[1] > 127) * 2 + (p[0] > 127)] = 1; }
        }
        for (int i = 0; i < 8; i++) colors += seen[i];
        uint8_t *corner = px, *center = px + (H / 2 * W + W / 2) * 4;
        printf("cube pixels: %d of %d, color octants seen: %d, corner %d,%d,%d, center %d,%d,%d (RGB)\n",
               lit, W * H, colors, corner[2], corner[1], corner[0], center[2], center[1], center[0]);
        int ok = lit > W * H / 20 && lit < W * H * 7 / 10 && colors >= 4 && corner[2] < 40;
        printf(ok ? "METAL CUBE OK\n" : "METAL CUBE FAIL\n");
        return !ok;
    }
}
