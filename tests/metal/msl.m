/* MSL compiled at run time (newLibraryWithSource:). msl_compute.metal: vector and matrix math, structs from buffers,
 * function constants, threadgroup memory + barriers + atomics, writable textures and constexpr samplers.
 * msl_render.metal: vertex descriptor ([[stage_in]]), output struct, sampled half texture. Prints "METAL MSL OK". */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <math.h>

#define STEP(x) fprintf(stderr, "step: %s\n", x)
static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL " __VA_ARGS__); } } while (0)

typedef struct { float p[4]; uint16_t h, pad; float q[3]; uint32_t tag; uint8_t pad2[12]; } Item; /* 48 bytes, as in the shader */
typedef struct { float scale; uint32_t n; uint32_t pad[2]; float m[16]; } Params;

static id<MTLLibrary> compile(id<MTLDevice> dev, NSString *dir, NSString *file) {
    NSString *src = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:file] encoding:NSUTF8StringEncoding error:nil];
    if (!src) { printf("FAIL could not read %s\n", file.UTF8String); return nil; }
    NSError *err = nil;
    id<MTLLibrary> lib = [dev newLibraryWithSource:src options:[MTLCompileOptions new] error:&err];
    if (!lib) printf("FAIL compiling %s:\n%s\n", file.UTF8String, err.localizedDescription.UTF8String);
    return lib;
}

static void basics(id<MTLDevice> dev, id<MTLCommandQueue> q, id<MTLLibrary> lib) {
    MTLFunctionConstantValues *cv = [MTLFunctionConstantValues new];
    bool yes = true; float b = 0.5f;
    [cv setConstantValue:&yes type:MTLDataTypeBool atIndex:0];
    [cv setConstantValue:&b type:MTLDataTypeFloat atIndex:1];
    NSError *err = nil;
    id<MTLFunction> f = [lib newFunctionWithName:@"basics" constantValues:cv error:&err];
    id<MTLComputePipelineState> pso = f ? [dev newComputePipelineStateWithFunction:f error:&err] : nil;
    if (!pso) { CHECK(0, "pipeline basics: %s\n", err.localizedDescription.UTF8String); return; }
    id<MTLBuffer> out = [dev newBufferWithLength:64 * 4 options:MTLResourceStorageModeShared];
    Params p = {2, 1, {0}, {0}};
    for (int i = 0; i < 16; i++) p.m[i] = i + 1;
    Item items[2] = {{{0}}, {{7, 8, 9, 0}, 0x3e00 /* 1.5 */, 0, {10, 11, 12}, 42, {0}}};
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
    [e setComputePipelineState:pso];
    [e setBuffer:out offset:0 atIndex:0];
    [e setBytes:&p length:sizeof p atIndex:1];
    [e setBytes:items length:sizeof items atIndex:2];
    [e dispatchThreads:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
    [e endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    const float want[] = {5, 10, 5, 90, 100, 120, 5, 2.5, 8, 10, 8, 1.5, 12, 42, 6, 2, 2, 1, 1, 15, 6, 1, -1.25, 4.5, 1024, 9, 2.5, 13, 5, 12,
                          0.5, 12, 20, 35, 1.5, 0.8, 1, 5, 1.5, 2};
    const float *r = out.contents;
    for (int i = 0; i < (int)(sizeof want / sizeof *want); i++) CHECK(fabsf(r[i] - want[i]) < 1e-3f, "basics out[%d] = %g, expected %g\n", i, r[i], want[i]);
}

static void reduce(id<MTLDevice> dev, id<MTLCommandQueue> q, id<MTLLibrary> lib) {
    NSError *err = nil;
    id<MTLComputePipelineState> pso = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"reduce"] error:&err];
    if (!pso) { CHECK(0, "pipeline reduce: %s\n", err.localizedDescription.UTF8String); return; }
    uint32_t in[256];
    for (int i = 0; i < 256; i++) in[i] = i + 1;
    id<MTLBuffer> bin = [dev newBufferWithBytes:in length:sizeof in options:MTLResourceStorageModeShared];
    id<MTLBuffer> total = [dev newBufferWithLength:4 options:MTLResourceStorageModeShared];
    id<MTLBuffer> part = [dev newBufferWithLength:16 options:MTLResourceStorageModeShared];
    memset(total.contents, 0, 4);
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
    [e setComputePipelineState:pso];
    [e setBuffer:bin offset:0 atIndex:0];
    [e setBuffer:total offset:0 atIndex:1];
    [e setBuffer:part offset:0 atIndex:2];
    [e dispatchThreadgroups:MTLSizeMake(4, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
    [e endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    const uint32_t *pt = part.contents;
    for (int g = 0; g < 4; g++) {
        uint32_t s = 0;
        for (int i = 0; i < 64; i++) s += in[g * 64 + i];
        CHECK(pt[g] == s, "reduce group %d = %u, expected %u\n", g, pt[g], s);
    }
    CHECK(*(uint32_t *)total.contents == 32896, "reduce atomic total = %u, expected 32896\n", *(uint32_t *)total.contents);
}

static void image(id<MTLDevice> dev, id<MTLCommandQueue> q, id<MTLLibrary> lib) {
    NSError *err = nil;
    id<MTLComputePipelineState> pso = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"image"] error:&err];
    if (!pso) { CHECK(0, "pipeline image: %s\n", err.localizedDescription.UTF8String); return; }
    MTLTextureDescriptor *sd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    id<MTLTexture> src = [dev newTextureWithDescriptor:sd];
    uint8_t texels[64];
    for (int i = 0; i < 16; i++) { texels[4 * i] = i * 16; texels[4 * i + 1] = 255 - i * 16; texels[4 * i + 2] = i * 8 + 3; texels[4 * i + 3] = 255; }
    [src replaceRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0 withBytes:texels bytesPerRow:16];
    MTLTextureDescriptor *dd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
    dd.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    id<MTLTexture> dst = [dev newTextureWithDescriptor:dd];
    MTLSamplerDescriptor *smd = [MTLSamplerDescriptor new];
    smd.minFilter = smd.magFilter = MTLSamplerMinMagFilterNearest;
    id<MTLSamplerState> smp = [dev newSamplerStateWithDescriptor:smd];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
    [e setComputePipelineState:pso];
    [e setTexture:dst atIndex:0];
    [e setTexture:src atIndex:1];
    [e setSamplerState:smp atIndex:0];
    [e dispatchThreads:MTLSizeMake(8, 8, 1) threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
    [e endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    uint8_t px[8 * 8 * 4];
    [dst getBytes:px bytesPerRow:32 fromRegion:MTLRegionMake2D(0, 0, 8, 8) mipmapLevel:0];
    int bad = 0;
    for (int y = 0; y < 8; y++)
        for (int x = 0; x < 8; x++) {
            const uint8_t *p = px + (y * 8 + x) * 4, *t = texels + ((y / 2) * 4 + x / 2) * 4;
            if (abs(p[0] - t[0]) > 1 || abs(p[1] - t[1]) > 1 || abs(p[2] - t[2]) > 1 || p[3] != 255) {
                if (bad++ < 4) printf("FAIL image (%d,%d) = %d,%d,%d,%d expected %d,%d,%d,255\n", x, y, p[0], p[1], p[2], p[3], t[0], t[1], t[2]);
            }
        }
    fails += bad != 0;
}

static void render(id<MTLDevice> dev, id<MTLCommandQueue> q, id<MTLLibrary> lib) {
    const int W = 64, H = 64;
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [lib newFunctionWithName:@"vmain"];
    pd.fragmentFunction = [lib newFunctionWithName:@"fmain"];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    MTLVertexDescriptor *vd = [MTLVertexDescriptor vertexDescriptor];
    vd.attributes[0].format = MTLVertexFormatFloat2; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0;
    vd.attributes[1].format = MTLVertexFormatFloat2; vd.attributes[1].offset = 8; vd.attributes[1].bufferIndex = 0;
    vd.layouts[0].stride = 16;
    pd.vertexDescriptor = vd;
    NSError *err = nil;
    id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
    if (!pso) { CHECK(0, "pipeline render: %s\n", err.localizedDescription.UTF8String); return; }
    MTLTextureDescriptor *sd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:2 mipmapped:NO];
    id<MTLTexture> src = [dev newTextureWithDescriptor:sd];
    const uint8_t texels[16] = {255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255};
    [src replaceRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0 withBytes:texels bytesPerRow:8];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:H mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [dev newTextureWithDescriptor:td];
    static const float quad[] = {-1, -1, 0, 1, 1, -1, 1, 1, -1, 1, 0, 0, 1, -1, 1, 1, 1, 1, 1, 0, -1, 1, 0, 0};
    struct { float scale[2], pad[2], tint[4]; } u = {{1, 1}, {0}, {1, 0.5f, 1, 1}};
    id<MTLCommandBuffer> cb = [q commandBuffer];
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = target;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
    [e setViewport:(MTLViewport){0, 0, W, H, 0, 1}];
    [e setRenderPipelineState:pso];
    [e setVertexBytes:quad length:sizeof quad atIndex:0];
    [e setVertexBytes:&u length:sizeof u atIndex:1];
    [e setFragmentTexture:src atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [e endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    uint8_t *px = malloc(W * H * 4);
    [target getBytes:px bytesPerRow:W * 4 fromRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0];
    struct { int x, y, r, g, b; const char *n; } want[] = {{16, 16, 255, 0, 0, "red"}, {48, 16, 0, 128, 0, "green"}, {16, 48, 0, 0, 255, "blue"}, {48, 48, 255, 128, 255, "white"}};
    for (int i = 0; i < 4; i++) {
        uint8_t *p = px + (want[i].y * W + want[i].x) * 4; /* B G R A */
        CHECK(abs(p[2] - want[i].r) < 4 && abs(p[1] - want[i].g) < 4 && abs(p[0] - want[i].b) < 4, "render (%d,%d) = %d,%d,%d expected %s\n", want[i].x, want[i].y, p[2], p[1], p[0], want[i].n);
    }
    free(px);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        NSString *dir = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        id<MTLCommandQueue> q = [dev newCommandQueue];
        STEP("compile msl_compute.metal");
        id<MTLLibrary> cl = compile(dev, dir, @"msl_compute.metal");
        if (cl) {
            STEP("basics"); basics(dev, q, cl);
            STEP("reduce"); reduce(dev, q, cl);
            STEP("image"); image(dev, q, cl);
        } else fails++;
        STEP("compile msl_render.metal");
        id<MTLLibrary> rl = compile(dev, dir, @"msl_render.metal");
        if (rl) { STEP("render"); render(dev, q, rl); } else fails++;
        printf(fails ? "METAL MSL FAIL\n" : "METAL MSL OK\n");
        return fails != 0;
    }
}
