/* MetalFX (spatial and temporal upscaling) on scion's Metal. An 8x8 input (left half red, right half blue) scaled to
 * 16x16; then only the left region (inputContentWidth = 4) must fill the output with red. Prints "METALFX OK". */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>

static int fails;
static void check(id<MTLTexture> out, int x, int y, int r, int g, int b, const char *what) {
    uint8_t px[4];
    [out getBytes:px bytesPerRow:4 fromRegion:MTLRegionMake2D(x, y, 1, 1) mipmapLevel:0]; /* BGRA */
    if (abs(px[2] - r) > 6 || abs(px[1] - g) > 6 || abs(px[0] - b) > 6) { printf("FAIL %s (%d,%d) = %d,%d,%d expected %d,%d,%d\n", what, x, y, px[2], px[1], px[0], r, g, b); fails++; }
}
int main(void) {
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        id<MTLCommandQueue> q = [dev newCommandQueue];
        MTLTextureDescriptor *id_ = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
        id<MTLTexture> in = [dev newTextureWithDescriptor:id_];
        uint8_t texels[8 * 8 * 4];
        for (int i = 0; i < 64; i++) { int left = (i % 8) < 4; texels[4 * i] = left ? 255 : 0; texels[4 * i + 1] = 0; texels[4 * i + 2] = left ? 0 : 255; texels[4 * i + 3] = 255; }
        [in replaceRegion:MTLRegionMake2D(0, 0, 8, 8) mipmapLevel:0 withBytes:texels bytesPerRow:32];

        MTLFXSpatialScalerDescriptor *sd = [MTLFXSpatialScalerDescriptor new];
        sd.colorTextureFormat = MTLPixelFormatRGBA8Unorm; sd.outputTextureFormat = MTLPixelFormatBGRA8Unorm;
        sd.inputWidth = sd.inputHeight = 8; sd.outputWidth = sd.outputHeight = 16;
        if (![MTLFXSpatialScalerDescriptor supportsDevice:dev]) { printf("FAIL supportsDevice\n"); return 1; }
        id<MTLFXSpatialScaler> sp = [sd newSpatialScalerWithDevice:dev];
        MTLTextureDescriptor *od = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:16 height:16 mipmapped:NO];
        od.usage = sp.outputTextureUsage; od.storageMode = MTLStorageModePrivate;
        id<MTLTexture> out = [dev newTextureWithDescriptor:od];
        sp.colorTexture = in; sp.outputTexture = out;
        id<MTLCommandBuffer> cb = [q commandBuffer];
        [sp encodeToCommandBuffer:cb];
        [cb commit]; [cb waitUntilCompleted];
        check(out, 3, 8, 255, 0, 0, "spatial left");
        check(out, 12, 8, 0, 0, 255, "spatial right");

        MTLFXTemporalScalerDescriptor *td = [MTLFXTemporalScalerDescriptor new];
        td.colorTextureFormat = MTLPixelFormatRGBA8Unorm; td.outputTextureFormat = MTLPixelFormatBGRA8Unorm;
        td.depthTextureFormat = MTLPixelFormatDepth32Float; td.motionTextureFormat = MTLPixelFormatRG16Float;
        td.inputWidth = td.inputHeight = 8; td.outputWidth = td.outputHeight = 16;
        id<MTLFXTemporalScaler> tp = [td newTemporalScalerWithDevice:dev];
        tp.colorTexture = in; tp.outputTexture = out;
        tp.inputContentWidth = 4; tp.inputContentHeight = 8; /* only the red half */
        cb = [q commandBuffer];
        [tp encodeToCommandBuffer:cb];
        [cb commit]; [cb waitUntilCompleted];
        check(out, 2, 8, 255, 0, 0, "temporal region");
        check(out, 13, 8, 255, 0, 0, "temporal region");
        printf(fails ? "METALFX FAIL\n" : "METALFX OK\n");
        return fails != 0;
    }
}
