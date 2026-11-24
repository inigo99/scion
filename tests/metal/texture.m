/* A sampled texture with the shaders of Apple's "Creating and Sampling Textures" sample (texture.metallib, from Indium's
 * "sampler" test: texture2d<half> + a linear constexpr sampler declared in the shader). A 2x2 texture (red, green, blue,
 * white) on a quad that fills the target: the center of each quadrant must have its texel's color. Prints "METAL TEXTURE OK". */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <simd/simd.h>

typedef struct { vector_float2 position, textureCoordinate; } AAPLVertex;
#define STEP(x) fprintf(stderr, "step: %s\n", x)

int main(int argc, char **argv) {
    @autoreleasepool {
        const int W = 256, H = 256;
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        NSString *dir = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        NSError *err = nil;
        STEP("device");
        id<MTLLibrary> lib = [dev newLibraryWithFile:[dir stringByAppendingPathComponent:@"texture.metallib"] error:&err];
        if (!lib) { printf("METAL: %s\n", err.localizedDescription.UTF8String); return 1; }
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [lib newFunctionWithName:@"vertexShader"];
        pd.fragmentFunction = [lib newFunctionWithName:@"samplingShader"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        if (!pso) { printf("METAL: %s\n", err.localizedDescription.UTF8String); return 1; }
        STEP("pipeline");

        MTLTextureDescriptor *sd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:2 mipmapped:NO];
        id<MTLTexture> src = [dev newTextureWithDescriptor:sd];
        const uint8_t texels[16] = {255, 0, 0, 255, 0, 255, 0, 255, /* row 0: red, green */ 0, 0, 255, 255, 255, 255, 255, 255 /* row 1: blue, white */};
        [src replaceRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0 withBytes:texels bytesPerRow:8];
        uint8_t back[16] = {0};
        [src getBytes:back bytesPerRow:8 fromRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0];
        if (memcmp(back, texels, 16)) {
            printf("FAIL replaceRegion/getBytes:");
            for (int i = 0; i < 16; i++) printf(" %d", back[i]);
            printf("\n");
        }
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:H mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget;
        id<MTLTexture> target = [dev newTextureWithDescriptor:td];
        STEP("textures");

        static const AAPLVertex quad[] = {
            {{128, -128}, {1, 1}}, {{-128, -128}, {0, 1}}, {{-128, 128}, {0, 0}},
            {{128, -128}, {1, 1}}, {{-128, 128}, {0, 0}}, {{128, 128}, {1, 0}},
        };
        vector_uint2 viewport = {W, H};
        id<MTLCommandBuffer> cb = [[dev newCommandQueue] commandBuffer];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = target;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
        [e setViewport:(MTLViewport){0, 0, W, H, 0, 1}];
        [e setRenderPipelineState:pso];
        [e setVertexBytes:quad length:sizeof quad atIndex:0];
        [e setVertexBytes:&viewport length:sizeof viewport atIndex:1];
        [e setFragmentTexture:src atIndex:0];
        [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        [e endEncoding];
        [cb commit];
        [cb waitUntilCompleted];
        STEP("render done");

        uint8_t *px = malloc(W * H * 4);
        [target getBytes:px bytesPerRow:W * 4 fromRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0];
        int fails = 0;
        struct { int x, y; uint8_t r, g, b; const char *name; } want[] = {
            {64, 64, 255, 0, 0, "red"}, {192, 64, 0, 255, 0, "green"}, {64, 192, 0, 0, 255, "blue"}, {192, 192, 255, 255, 255, "white"}};
        for (int i = 0; i < 4; i++) {
            uint8_t *p = px + (want[i].y * W + want[i].x) * 4; /* B G R A */
            int ok = abs(p[2] - want[i].r) < 8 && abs(p[1] - want[i].g) < 8 && abs(p[0] - want[i].b) < 8;
            printf("(%d,%d) %d,%d,%d expected %s\n", want[i].x, want[i].y, p[2], p[1], p[0], want[i].name);
            fails += !ok;
        }
        uint8_t *mid = px + (128 * W + 128) * 4; /* center: linear blend of the four */
        if (!(mid[0] > 60 && mid[1] > 60 && mid[2] > 60)) { printf("FAIL the center does not blend (linear filter): %d,%d,%d\n", mid[2], mid[1], mid[0]); fails++; }
        printf(fails ? "METAL TEXTURE FAIL\n" : "METAL TEXTURE OK\n");
        return fails != 0;
    }
}
