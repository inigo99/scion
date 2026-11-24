/* Offscreen Metal render with the shaders of Apple's "Hello Triangle" sample (AAPLShaders.metallib, from Indium's test
 * suite). Draws the triangle into a texture, reads it with getBytes, checks the colors and saves triangle.bmp.
 * Prints "METAL TRIANGLE OK". */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <simd/simd.h>

typedef struct { vector_float2 position; vector_float4 color; } AAPLVertex;

static void save_bmp(const char *path, const uint8_t *bgra, int w, int h) {
    FILE *f = fopen(path, "wb"); if (!f) return;
    uint32_t size = 54 + w * h * 4;
    uint8_t hd[54] = {'B', 'M'}; memcpy(hd + 2, &size, 4); hd[10] = 54; hd[14] = 40;
    memcpy(hd + 18, &w, 4); int nh = -h; memcpy(hd + 22, &nh, 4); hd[26] = 1; hd[28] = 32;
    fwrite(hd, 1, 54, f); fwrite(bgra, 1, w * h * 4, f); fclose(f);
}

#define STEP(x) fprintf(stderr, "step: %s\n", x)   /* unbuffered stderr: shows how far it got if something fails */

int main(int argc, char **argv) {
    @autoreleasepool {
        const int W = 256, H = 256;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        NSString *dir = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        NSError *error = nil;
        STEP("device");
        id<MTLLibrary> lib = [device newLibraryWithFile:[dir stringByAppendingPathComponent:@"AAPLShaders.metallib"] error:&error];
        if (!lib) { printf("METAL: %s\n", error.localizedDescription.UTF8String); return 1; }

        STEP("metallib");
        MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
        pd.vertexFunction = [lib newFunctionWithName:@"vertexShader"];
        pd.fragmentFunction = [lib newFunctionWithName:@"fragmentShader"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        id<MTLRenderPipelineState> pso = [device newRenderPipelineStateWithDescriptor:pd error:&error];
        if (!pso) { printf("METAL: %s\n", error.localizedDescription.UTF8String); return 1; }

        STEP("pipeline");
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:H mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        id<MTLTexture> target = [device newTextureWithDescriptor:td];

        STEP("texture");
        static const AAPLVertex tri[] = {
            {{ 100, -100}, {1, 0, 0, 1}},
            {{-100, -100}, {0, 1, 0, 1}},
            {{   0,  100}, {0, 0, 1, 1}},
        };
        vector_uint2 viewport = {W, H};

        id<MTLCommandQueue> q = [device newCommandQueue];
        id<MTLCommandBuffer> cb = [q commandBuffer];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = target;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        [enc setViewport:(MTLViewport){0, 0, W, H, 0, 1}];
        [enc setRenderPipelineState:pso];
        [enc setVertexBytes:tri length:sizeof tri atIndex:0];
        [enc setVertexBytes:&viewport length:sizeof viewport atIndex:1];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
        STEP("encoded");
        [cb commit];
        [cb waitUntilCompleted];

        STEP("render done");
        uint8_t *px = malloc(W * H * 4);
        [target getBytes:px bytesPerRow:W * 4 fromRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0];
        STEP("getBytes");
        save_bmp([[dir stringByAppendingPathComponent:@"triangle.bmp"] fileSystemRepresentation], px, W, H);
        #define PX(x, y) (px + ((y) * W + (x)) * 4)   /* B G R A */
        int fails = 0;
        uint8_t *c = PX(5, 5), *top = PX(128, 128 - 85), *bl = PX(128 - 85, 128 + 95), *br = PX(128 + 85, 128 + 95), *mid = PX(128, 150);
        printf("corner %d,%d,%d  top %d,%d,%d  bottom-left %d,%d,%d  bottom-right %d,%d,%d  center %d,%d,%d (RGB)\n",
               c[2], c[1], c[0], top[2], top[1], top[0], bl[2], bl[1], bl[0], br[2], br[1], br[0], mid[2], mid[1], mid[0]);
        if (c[0] || c[1] || c[2]) { printf("FAIL background not black\n"); fails++; }
        if (!(top[0] > 150 && top[1] < 80 && top[2] < 80)) { printf("FAIL top vertex not blue\n"); fails++; }
        if (!(bl[1] > 150 && bl[0] < 80 && bl[2] < 80)) { printf("FAIL bottom-left vertex not green\n"); fails++; }
        if (!(br[2] > 150 && br[0] < 80 && br[1] < 80)) { printf("FAIL bottom-right vertex not red\n"); fails++; }
        if (!(mid[0] > 40 && mid[1] > 40 && mid[2] > 40)) { printf("FAIL the center does not blend the three colors\n"); fails++; }
        printf(fails ? "METAL TRIANGLE FAIL\n" : "METAL TRIANGLE OK\n");
        return fails;
    }
}
