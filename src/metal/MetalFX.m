/* MetalFX.m — MetalFX on scion (linked into Metal.dylib; dyld maps MetalFX.framework to it).
 * Both scalers draw the input's content region onto the output with a bilinear filter plus a light sharpening pass
 * (a shader compiled from MSL at first use). The temporal scaler has no history: it ignores depth/motion and only undoes
 * the camera jitter, so an app gets a correct, slightly softer image instead of an error. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>

static NSString *const kFXSource = @
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct VO { float4 pos [[position]]; float2 uv; };\n"
    "vertex VO mwfx_vs(uint vid [[vertex_id]], constant float4 &r [[buffer(0)]]) {\n"
    "    float2 p = float2(float((vid << 1) & 2), float(vid & 2));\n"
    "    VO o;\n"
    "    o.pos = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);\n"
    "    o.uv = r.xy + p * r.zw;\n"
    "    return o;\n"
    "}\n"
    "fragment float4 mwfx_fs(VO in [[stage_in]], texture2d<float> t [[texture(0)]], constant float4 &k [[buffer(0)]]) {\n"
    "    constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
    "    float4 c = t.sample(s, in.uv);\n"
    "    float4 n = t.sample(s, in.uv + float2(k.x, 0.0)) + t.sample(s, in.uv - float2(k.x, 0.0)) +\n"
    "               t.sample(s, in.uv + float2(0.0, k.y)) + t.sample(s, in.uv - float2(0.0, k.y));\n"
    "    float3 rgb = max(c.rgb + (c.rgb - n.rgb * 0.25) * k.z, float3(0.0));\n"
    "    return float4(rgb, c.a);\n"
    "}\n";

/* one pipeline per (device, output format) */
static id<MTLRenderPipelineState> fx_pipeline(id<MTLDevice> dev, MTLPixelFormat fmt) {
    static NSMutableDictionary *cache;
    static id<MTLLibrary> lib;
    @synchronized([MTLFXSpatialScalerDescriptor class]) {
        if (!cache) cache = [NSMutableDictionary new];
        NSNumber *key = [NSNumber numberWithUnsignedInteger:fmt];
        id<MTLRenderPipelineState> p = [cache objectForKey:key];
        if (p) return p;
        NSError *err = nil;
        if (!lib) lib = [dev newLibraryWithSource:kFXSource options:nil error:&err];
        if (!lib) { NSLog(@"MetalFX (scion): %@", err.localizedDescription); return nil; }
        MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
        d.vertexFunction = [[lib newFunctionWithName:@"mwfx_vs"] autorelease];
        d.fragmentFunction = [[lib newFunctionWithName:@"mwfx_fs"] autorelease];
        d.colorAttachments[0].pixelFormat = fmt;
        p = [dev newRenderPipelineStateWithDescriptor:d error:&err];
        [d release];
        if (!p) { NSLog(@"MetalFX (scion): %@", err.localizedDescription); return nil; }
        [cache setObject:p forKey:key];
        [p release];
        return p;
    }
}

@class MTLFXSpatialScalerDescriptor, MTLFXTemporalScalerDescriptor;
@interface _MWFXScaler : NSObject <MTLFXSpatialScaler, MTLFXTemporalScaler> {
@public
    id<MTLDevice> _dev;
    BOOL _temporal;
}
- (instancetype)initWithDevice:(id<MTLDevice>)dev spatial:(MTLFXSpatialScalerDescriptor *)sd temporal:(MTLFXTemporalScalerDescriptor *)td;
@end
@implementation _MWFXScaler
@synthesize inputContentWidth = _inputContentWidth, inputContentHeight = _inputContentHeight, colorTexture = _colorTexture,
            outputTexture = _outputTexture, depthTexture = _depthTexture, motionTexture = _motionTexture, exposureTexture = _exposureTexture,
            reactiveMaskTexture = _reactiveMaskTexture, preExposure = _preExposure, jitterOffsetX = _jitterOffsetX, jitterOffsetY = _jitterOffsetY,
            motionVectorScaleX = _motionVectorScaleX, motionVectorScaleY = _motionVectorScaleY, reset = _reset, depthReversed = _depthReversed,
            colorTextureFormat = _colorTextureFormat, depthTextureFormat = _depthTextureFormat, motionTextureFormat = _motionTextureFormat,
            outputTextureFormat = _outputTextureFormat, reactiveMaskTextureFormat = _reactiveMaskTextureFormat, inputWidth = _inputWidth,
            inputHeight = _inputHeight, outputWidth = _outputWidth, outputHeight = _outputHeight, colorProcessingMode = _colorProcessingMode,
            inputContentMinScale = _inputContentMinScale, inputContentMaxScale = _inputContentMaxScale, fence = _fence;
- (instancetype)initWithDevice:(id<MTLDevice>)dev spatial:(MTLFXSpatialScalerDescriptor *)sd temporal:(MTLFXTemporalScalerDescriptor *)td {
    if (!(self = [super init])) return nil;
    _dev = [dev retain];
    if (sd) {
        _colorTextureFormat = sd.colorTextureFormat; _outputTextureFormat = sd.outputTextureFormat;
        _inputWidth = sd.inputWidth; _inputHeight = sd.inputHeight; _outputWidth = sd.outputWidth; _outputHeight = sd.outputHeight;
        _colorProcessingMode = sd.colorProcessingMode;
    } else {
        _temporal = YES;
        _colorTextureFormat = td.colorTextureFormat; _depthTextureFormat = td.depthTextureFormat; _motionTextureFormat = td.motionTextureFormat;
        _outputTextureFormat = td.outputTextureFormat; _reactiveMaskTextureFormat = td.reactiveMaskTextureFormat;
        _inputWidth = td.inputWidth; _inputHeight = td.inputHeight; _outputWidth = td.outputWidth; _outputHeight = td.outputHeight;
        _inputContentMinScale = td.inputContentMinScale ? td.inputContentMinScale : 1; _inputContentMaxScale = td.inputContentMaxScale ? td.inputContentMaxScale : 3;
        _motionVectorScaleX = _motionVectorScaleY = 1;
    }
    _inputContentWidth = _inputWidth; _inputContentHeight = _inputHeight;
    return self;
}
- (MTLTextureUsage)colorTextureUsage { return MTLTextureUsageShaderRead; }
- (MTLTextureUsage)depthTextureUsage { return MTLTextureUsageShaderRead; }
- (MTLTextureUsage)motionTextureUsage { return MTLTextureUsageShaderRead; }
- (MTLTextureUsage)reactiveTextureUsage { return MTLTextureUsageShaderRead; }
- (MTLTextureUsage)outputTextureUsage { return MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite; }
- (void)dealloc {
    [_colorTexture release]; [_outputTexture release]; [_depthTexture release]; [_motionTexture release]; [_exposureTexture release];
    [_reactiveMaskTexture release]; [_fence release]; [_dev release];
    [super dealloc];
}
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)cb {
    id<MTLTexture> in = _colorTexture, out = _outputTexture;
    if (!in || !out) return;
    id<MTLRenderPipelineState> pso = fx_pipeline(_dev, out.pixelFormat);
    if (!pso) return;
    float tw = in.width, th = in.height;
    float cw = _inputContentWidth ? _inputContentWidth : (_inputWidth ? _inputWidth : tw);
    float ch = _inputContentHeight ? _inputContentHeight : (_inputHeight ? _inputHeight : th);
    /* region of the input to show (uv offset, uv scale); the temporal scaler removes the projection jitter */
    float r[4] = {_temporal ? _jitterOffsetX / tw : 0, _temporal ? _jitterOffsetY / th : 0, cw / tw, ch / th};
    float upscale = out.width / cw;
    float k[4] = {1 / tw, 1 / th, upscale > 1.01f ? 0.35f : 0.0f, 0};
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = out;
    rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
    [e setViewport:(MTLViewport){0, 0, out.width, out.height, 0, 1}];
    [e setRenderPipelineState:pso];
    [e setVertexBytes:r length:sizeof r atIndex:0];
    [e setFragmentBytes:k length:sizeof k atIndex:0];
    [e setFragmentTexture:in atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [e endEncoding];
    _reset = NO;
}
@end

/* Metal 4: encodes into the Metal 3 command buffer the Metal 4 one records onto (Metal4.m) */
@interface NSObject (MW4Legacy) - (id<MTLCommandBuffer>)_mwLegacyCommandBuffer; @end
@interface _MW4FXScaler : _MWFXScaler @end
@implementation _MW4FXScaler
- (void)encodeToCommandBuffer:(id)cb {
    if ([cb respondsToSelector:@selector(_mwLegacyCommandBuffer)]) cb = [cb _mwLegacyCommandBuffer];
    if (cb) [super encodeToCommandBuffer:cb];
}
@end

@implementation MTLFXSpatialScalerDescriptor
@synthesize colorTextureFormat = _colorTextureFormat, outputTextureFormat = _outputTextureFormat, inputWidth = _inputWidth,
            inputHeight = _inputHeight, outputWidth = _outputWidth, outputHeight = _outputHeight, colorProcessingMode = _colorProcessingMode;
+ (BOOL)supportsDevice:(id<MTLDevice>)device { return device != nil; }
- (id)copyWithZone:(NSZone *)z {
    MTLFXSpatialScalerDescriptor *c = [[[self class] alloc] init];
    c.colorTextureFormat = _colorTextureFormat; c.outputTextureFormat = _outputTextureFormat; c.inputWidth = _inputWidth;
    c.inputHeight = _inputHeight; c.outputWidth = _outputWidth; c.outputHeight = _outputHeight; c.colorProcessingMode = _colorProcessingMode;
    return c;
}
- (id<MTLFXSpatialScaler>)newSpatialScalerWithDevice:(id<MTLDevice>)device { return [[_MWFXScaler alloc] initWithDevice:device spatial:self temporal:nil]; }
- (id<MTL4FXSpatialScaler>)newSpatialScalerWithDevice:(id<MTLDevice>)device compiler:(id<MTL4Compiler>)compiler {
    return (id<MTL4FXSpatialScaler>)[[_MW4FXScaler alloc] initWithDevice:device spatial:self temporal:nil];
}
@end

@implementation MTLFXTemporalScalerDescriptor
@synthesize colorTextureFormat = _colorTextureFormat, depthTextureFormat = _depthTextureFormat, motionTextureFormat = _motionTextureFormat,
            outputTextureFormat = _outputTextureFormat, reactiveMaskTextureFormat = _reactiveMaskTextureFormat, inputWidth = _inputWidth,
            inputHeight = _inputHeight, outputWidth = _outputWidth, outputHeight = _outputHeight, autoExposureEnabled = _autoExposureEnabled,
            inputContentPropertiesEnabled = _inputContentPropertiesEnabled, reactiveMaskTextureEnabled = _reactiveMaskTextureEnabled,
            requiresSynchronousInitialization = _requiresSynchronousInitialization, inputContentMinScale = _inputContentMinScale,
            inputContentMaxScale = _inputContentMaxScale;
+ (BOOL)supportsDevice:(id<MTLDevice>)device { return device != nil; }
+ (float)supportedInputContentMinScaleForDevice:(id<MTLDevice>)device { return 1.0f; }
+ (float)supportedInputContentMaxScaleForDevice:(id<MTLDevice>)device { return 3.0f; }
- (id)copyWithZone:(NSZone *)z {
    MTLFXTemporalScalerDescriptor *c = [[[self class] alloc] init];
    c.colorTextureFormat = _colorTextureFormat; c.depthTextureFormat = _depthTextureFormat; c.motionTextureFormat = _motionTextureFormat;
    c.outputTextureFormat = _outputTextureFormat; c.reactiveMaskTextureFormat = _reactiveMaskTextureFormat; c.inputWidth = _inputWidth;
    c.inputHeight = _inputHeight; c.outputWidth = _outputWidth; c.outputHeight = _outputHeight; c.autoExposureEnabled = _autoExposureEnabled;
    c.inputContentPropertiesEnabled = _inputContentPropertiesEnabled; c.reactiveMaskTextureEnabled = _reactiveMaskTextureEnabled;
    c.requiresSynchronousInitialization = _requiresSynchronousInitialization; c.inputContentMinScale = _inputContentMinScale;
    c.inputContentMaxScale = _inputContentMaxScale;
    return c;
}
- (id<MTLFXTemporalScaler>)newTemporalScalerWithDevice:(id<MTLDevice>)device { return [[_MWFXScaler alloc] initWithDevice:device spatial:nil temporal:self]; }
@end
