/* Test/demo: a spinning 3D cube in a window, presented with CAMetalLayer (QuartzCore) like a macOS app.
 * Usage: window [frames]   without an argument it spins until the window closes (it can be resized); with N it draws N
 * frames and exits, changing the size (drawableSize) halfway and then the format (BGRA8Unorm_sRGB) to test the swapchain.
 * Prints "METAL WINDOW OK". */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
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
int main(int argc, char **argv) {
    @autoreleasepool {
        const int W = 640, H = 480;
        long frames = argc > 1 ? atol(argv[1]) : -1;
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        NSString *dir = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithFile:[dir stringByAppendingPathComponent:@"cube.metallib"] error:&err];
        if (!lib) { printf("METAL: %s\n", err.localizedDescription.UTF8String); return 1; }
        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = dev; layer.pixelFormat = MTLPixelFormatBGRA8Unorm; layer.drawableSize = CGSizeMake(W, H);

        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [lib newFunctionWithName:@"vertex_project"];
        pd.fragmentFunction = [lib newFunctionWithName:@"fragment_flatcolor"];
        pd.colorAttachments[0].pixelFormat = layer.pixelFormat;
        pd.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        MTLDepthStencilDescriptor *dd = [MTLDepthStencilDescriptor new];
        dd.depthCompareFunction = MTLCompareFunctionLess; dd.depthWriteEnabled = YES;
        id<MTLDepthStencilState> ds = [dev newDepthStencilStateWithDescriptor:dd];
        static const Vertex v[] = {
            {{-1, 1, 1, 1}, {0, 1, 1, 1}}, {{-1, -1, 1, 1}, {0, 0, 1, 1}}, {{1, -1, 1, 1}, {1, 0, 1, 1}}, {{1, 1, 1, 1}, {1, 1, 1, 1}},
            {{-1, 1, -1, 1}, {0, 1, 0, 1}}, {{-1, -1, -1, 1}, {0, 0, 0, 1}}, {{1, -1, -1, 1}, {1, 0, 0, 1}}, {{1, 1, -1, 1}, {1, 1, 0, 1}},
        };
        static const uint16_t idx[] = {3, 2, 6, 6, 7, 3, 4, 5, 1, 1, 0, 4, 4, 0, 3, 3, 7, 4, 1, 5, 6, 6, 2, 1, 0, 1, 2, 2, 3, 0, 7, 6, 5, 5, 4, 7};
        id<MTLBuffer> vb = [dev newBufferWithBytes:v length:sizeof v options:MTLResourceStorageModeShared];
        id<MTLBuffer> ib = [dev newBufferWithBytes:idx length:sizeof idx options:MTLResourceStorageModeShared];
        id<MTLTexture> depth = nil;
        id<MTLCommandQueue> q = [dev newCommandQueue];
        matrix_float4x4 view = matrix_identity_float4x4;
        int resized = 0, srgb = 0;
        view.columns[3] = (vector_float4){0, 0, -5, 1};

        NSDate *t0 = [NSDate date];
        long n = 0;
        for (; frames < 0 || n < frames; n++) @autoreleasepool {
            id<CAMetalDrawable> drawable = [layer nextDrawable];   /* exits the program if the user closes the window */
            if (!drawable) { fprintf(stderr, "step: frame %ld without a drawable\n", n); continue; }
            if (n % 100 == 0) fprintf(stderr, "step: frame %ld\n", n);
            NSUInteger w = drawable.texture.width, h = drawable.texture.height; /* follows the window (resizable) */
            if (!depth || depth.width != w || depth.height != h) {
                MTLTextureDescriptor *zd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:w height:h mipmapped:NO];
                zd.usage = MTLTextureUsageRenderTarget; zd.storageMode = MTLStorageModePrivate;
                depth = [dev newTextureWithDescriptor:zd];
                fprintf(stderr, "step: frame %ld drawable %lux%lu\n", n, (unsigned long)w, (unsigned long)h);
                if (frames > 0 && n > 0 && w == 480 && h == 360) resized = 1;
            }
            if (drawable.texture.pixelFormat != pd.colorAttachments[0].pixelFormat) { /* the layer's format changed */
                pd.colorAttachments[0].pixelFormat = drawable.texture.pixelFormat;
                pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
                fprintf(stderr, "step: frame %ld format %lu pso %s\n", n, (unsigned long)drawable.texture.pixelFormat, pso ? "ok" : "NULL");
                srgb |= drawable.texture.pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB;
            }
            if (frames > 0 && n == frames / 2) { fprintf(stderr, "step: requesting 480x360\n"); layer.drawableSize = CGSizeMake(480, 360); }
            if (frames > 0 && n == frames * 3 / 4) { fprintf(stderr, "step: requesting BGRA8Unorm_sRGB\n"); layer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB; }
            matrix_float4x4 proj = perspective(2 * M_PI / 5, (float)w / h, 1, 100);
            float t = -[t0 timeIntervalSinceNow];
            Uniforms u = {matrix_multiply(proj, matrix_multiply(view, matrix_multiply(rot(t * 0.7f, (vector_float3){1, 0, 0}), rot(t, (vector_float3){0, 1, 0}))))};
            id<MTLCommandBuffer> cb = [q commandBuffer];
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = drawable.texture; rp.colorAttachments[0].loadAction = MTLLoadActionClear;
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            rp.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.1, 0.15, 1);
            rp.depthAttachment.texture = depth; rp.depthAttachment.loadAction = MTLLoadActionClear; rp.depthAttachment.clearDepth = 1.0;
            id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
            [e setViewport:(MTLViewport){0, 0, w, h, 0, 1}];
            [e setRenderPipelineState:pso];
            [e setDepthStencilState:ds];
            [e setCullMode:MTLCullModeBack];
            [e setFrontFacingWinding:MTLWindingCounterClockwise];
            [e setVertexBuffer:vb offset:0 atIndex:0];
            [e setVertexBytes:&u length:sizeof u atIndex:1];
            [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:36 indexType:MTLIndexTypeUInt16 indexBuffer:ib indexBufferOffset:0];
            [e endEncoding];
            [cb presentDrawable:drawable];
            [cb commit];
        }
        double s = -[t0 timeIntervalSinceNow];
        printf("%ld frames in %.2f s (%.0f fps)\n", n, s, n / s);
        if (frames > 0 && !resized) { printf("FAIL the swapchain did not follow the new size 480x360\n"); return 1; }
        if (frames > 0 && !srgb) { printf("FAIL the BGRA8Unorm_sRGB format was not applied\n"); return 1; }
        printf("METAL WINDOW OK\n");
        return 0;
    }
}
