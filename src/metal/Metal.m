/* Metal.m — scion's Metal.framework for the guest (Objective-C, MRC). Every object wraps a handle of the host
 * implementation (scion-metal.dll: Indium on Vulkan); calls cross through one hostcall (see mtlbridge.h).
 * Buffer contents live in host-visible Vulkan memory mapped into the same address space, so -contents is a plain pointer. */
#import <Metal/Metal.h>
#include "mtlbridge.h"

int64_t _scion_metal(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
#define U(x) ((uint64_t)(uintptr_t)(x))
static int64_t mw(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e) { return _scion_metal(op, a, b, c, d, e); }

static NSError *mw_error(NSInteger code, const char *msg) {
    return [NSError errorWithDomain:@"MTLLibraryErrorDomain" code:code
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:msg[0] ? msg : "error"]}];
}

/* ====================================================================== base */
@interface _MWObject : NSObject { @public uint64_t _h; id<MTLDevice> _device; NSString *_label; }
@end
@implementation _MWObject
- (void)dealloc { if (_h) mw(MW_RELEASE, _h, 0, 0, 0, 0); [_device release]; [_label release]; [super dealloc]; }
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [_label release]; _label = [l copy]; }
@end
static id mw_wrap(Class c, uint64_t h, id<MTLDevice> dev) {
    if (!h) return nil;
    _MWObject *o = [[c alloc] init]; o->_h = h; o->_device = [dev retain];
    return o;
}
static uint64_t H_(id o) { return o ? ((_MWObject *)o)->_h : 0; }

/* ====================================================================== descriptors (plain property bags) */
@implementation MTLVertexBufferLayoutDescriptor
- (instancetype)init { if ((self = [super init])) { _stepFunction = MTLVertexStepFunctionPerVertex; _stepRate = 1; } return self; }
- (id)copyWithZone:(NSZone *)z { MTLVertexBufferLayoutDescriptor *c = [[[self class] alloc] init]; c.stride = _stride; c.stepFunction = _stepFunction; c.stepRate = _stepRate; return c; }
@end
@implementation MTLVertexAttributeDescriptor
- (id)copyWithZone:(NSZone *)z { MTLVertexAttributeDescriptor *c = [[[self class] alloc] init]; c.format = _format; c.offset = _offset; c.bufferIndex = _bufferIndex; return c; }
@end
/* indexed arrays of descriptor objects, created on first access (one class per Metal array type) */
@interface NSObject (MWDescArray)
- (id)existingAtIndex:(NSUInteger)i; - (void)removeAllDescriptors; - (void)copyDescriptorsInto:(id)o; - (NSMutableDictionary *)_mwDict;
@end
#define DESC_ARRAY(NAME, ELEM) \
@implementation NAME { NSMutableDictionary *_d; } \
- (instancetype)init { if ((self = [super init])) _d = [[NSMutableDictionary alloc] init]; return self; } \
- (void)dealloc { [_d release]; [super dealloc]; } \
- (NSMutableDictionary *)_mwDict { return _d; } \
- (ELEM *)objectAtIndexedSubscript:(NSUInteger)i { \
    NSNumber *k = @(i); id o = [_d objectForKey:k]; \
    if (!o) { o = [[[ELEM alloc] init] autorelease]; [_d setObject:o forKey:k]; } \
    return o; \
} \
- (void)setObject:(ELEM *)o atIndexedSubscript:(NSUInteger)i { if (o) [_d setObject:[[o copy] autorelease] forKey:@(i)]; else [_d removeObjectForKey:@(i)]; } \
- (id)existingAtIndex:(NSUInteger)i { return [_d objectForKey:@(i)]; } \
- (void)removeAllDescriptors { [_d removeAllObjects]; } \
- (void)copyDescriptorsInto:(id)o { for (NSNumber *k in _d) [[o _mwDict] setObject:[[[_d objectForKey:k] copy] autorelease] forKey:k]; } \
@end
DESC_ARRAY(MTLVertexBufferLayoutDescriptorArray, MTLVertexBufferLayoutDescriptor)
DESC_ARRAY(MTLVertexAttributeDescriptorArray, MTLVertexAttributeDescriptor)
DESC_ARRAY(MTLRenderPipelineColorAttachmentDescriptorArray, MTLRenderPipelineColorAttachmentDescriptor)
DESC_ARRAY(MTLRenderPassColorAttachmentDescriptorArray, MTLRenderPassColorAttachmentDescriptor)
DESC_ARRAY(MTLPipelineBufferDescriptorArray, MTLPipelineBufferDescriptor)

@implementation MTLVertexDescriptor { MTLVertexBufferLayoutDescriptorArray *_layouts; MTLVertexAttributeDescriptorArray *_attributes; }
+ (MTLVertexDescriptor *)vertexDescriptor { return [[[self alloc] init] autorelease]; }
- (instancetype)init {
    if ((self = [super init])) {
        _layouts = [[MTLVertexBufferLayoutDescriptorArray alloc] init];
        _attributes = [[MTLVertexAttributeDescriptorArray alloc] init];
    }
    return self;
}
- (void)dealloc { [_layouts release]; [_attributes release]; [super dealloc]; }
- (MTLVertexBufferLayoutDescriptorArray *)layouts { return _layouts; }
- (MTLVertexAttributeDescriptorArray *)attributes { return _attributes; }
- (void)reset { [_layouts removeAllDescriptors]; [_attributes removeAllDescriptors]; }
- (id)copyWithZone:(NSZone *)z { MTLVertexDescriptor *c = [[MTLVertexDescriptor alloc] init]; [_layouts copyDescriptorsInto:c->_layouts]; [_attributes copyDescriptorsInto:c->_attributes]; return c; }
@end

@implementation MTLPipelineBufferDescriptor
- (id)copyWithZone:(NSZone *)z { MTLPipelineBufferDescriptor *c = [[[self class] alloc] init]; c.mutability = self.mutability; return c; }
@end

@implementation MTLRenderPipelineColorAttachmentDescriptor
- (instancetype)init {
    if ((self = [super init])) {
        self.writeMask = MTLColorWriteMaskAll; self.sourceRGBBlendFactor = MTLBlendFactorOne; self.sourceAlphaBlendFactor = MTLBlendFactorOne;
        self.destinationRGBBlendFactor = MTLBlendFactorZero; self.destinationAlphaBlendFactor = MTLBlendFactorZero;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)z {
    MTLRenderPipelineColorAttachmentDescriptor *c = [[[self class] alloc] init];
    c.pixelFormat = self.pixelFormat; c.writeMask = self.writeMask; c.blendingEnabled = self.blendingEnabled;
    c.rgbBlendOperation = self.rgbBlendOperation; c.alphaBlendOperation = self.alphaBlendOperation;
    c.sourceRGBBlendFactor = self.sourceRGBBlendFactor; c.destinationRGBBlendFactor = self.destinationRGBBlendFactor;
    c.sourceAlphaBlendFactor = self.sourceAlphaBlendFactor; c.destinationAlphaBlendFactor = self.destinationAlphaBlendFactor;
    return c;
}
@end

@implementation MTLRenderPipelineDescriptor { MTLRenderPipelineColorAttachmentDescriptorArray *_colors; MTLPipelineBufferDescriptorArray *_vbufs, *_fbufs; }
@synthesize vertexFunction = _vertexFunction, fragmentFunction = _fragmentFunction, vertexDescriptor = _vertexDescriptor, label = _label;
- (instancetype)init {
    if ((self = [super init])) {
        _colors = [[MTLRenderPipelineColorAttachmentDescriptorArray alloc] init];
        _vbufs = [[MTLPipelineBufferDescriptorArray alloc] init];
        _fbufs = [[MTLPipelineBufferDescriptorArray alloc] init];
        self.rasterizationEnabled = YES; self.sampleCount = 1; self.rasterSampleCount = 1;
    }
    return self;
}
- (void)dealloc { [_colors release]; [_vbufs release]; [_fbufs release]; [_vertexFunction release]; [_fragmentFunction release]; [_vertexDescriptor release]; [_label release]; [super dealloc]; }
- (MTLRenderPipelineColorAttachmentDescriptorArray *)colorAttachments { return _colors; }
- (MTLPipelineBufferDescriptorArray *)vertexBuffers { return _vbufs; }
- (MTLPipelineBufferDescriptorArray *)fragmentBuffers { return _fbufs; }
- (void)reset { [_colors removeAllDescriptors]; self.vertexFunction = nil; self.fragmentFunction = nil; self.vertexDescriptor = nil; }
- (id)copyWithZone:(NSZone *)z {
    MTLRenderPipelineDescriptor *c = [[MTLRenderPipelineDescriptor alloc] init];
    c.vertexFunction = _vertexFunction; c.fragmentFunction = _fragmentFunction; c.vertexDescriptor = _vertexDescriptor;
    [_colors copyDescriptorsInto:c->_colors];
    c.depthAttachmentPixelFormat = self.depthAttachmentPixelFormat; c.stencilAttachmentPixelFormat = self.stencilAttachmentPixelFormat;
    c.sampleCount = self.sampleCount; c.rasterSampleCount = self.rasterSampleCount; c.rasterizationEnabled = self.rasterizationEnabled;
    c.inputPrimitiveTopology = self.inputPrimitiveTopology; c.alphaToCoverageEnabled = self.alphaToCoverageEnabled; c.label = _label;
    return c;
}
@end

@implementation MTLRenderPassAttachmentDescriptor
@synthesize texture = _texture, resolveTexture = _resolveTexture;
- (instancetype)init { if ((self = [super init])) { self.storeAction = MTLStoreActionStore; } return self; }
- (void)dealloc { [_texture release]; [_resolveTexture release]; [super dealloc]; }
- (void)copyBaseTo:(MTLRenderPassAttachmentDescriptor *)c {
    c.texture = _texture; c.resolveTexture = _resolveTexture; c.level = self.level; c.slice = self.slice; c.depthPlane = self.depthPlane;
    c.loadAction = self.loadAction; c.storeAction = self.storeAction; c.storeActionOptions = self.storeActionOptions;
    c.resolveLevel = self.resolveLevel; c.resolveSlice = self.resolveSlice; c.resolveDepthPlane = self.resolveDepthPlane;
}
- (id)copyWithZone:(NSZone *)z { MTLRenderPassAttachmentDescriptor *c = [[[self class] alloc] init]; [self copyBaseTo:c]; return c; }
@end
@implementation MTLRenderPassColorAttachmentDescriptor
- (instancetype)init { if ((self = [super init])) { self.clearColor = MTLClearColorMake(0, 0, 0, 1); } return self; }
- (id)copyWithZone:(NSZone *)z { MTLRenderPassColorAttachmentDescriptor *c = [super copyWithZone:z]; c.clearColor = self.clearColor; return c; }
@end
@implementation MTLRenderPassDepthAttachmentDescriptor
- (instancetype)init { if ((self = [super init])) { self.clearDepth = 1.0; self.storeAction = MTLStoreActionDontCare; } return self; }
- (id)copyWithZone:(NSZone *)z { MTLRenderPassDepthAttachmentDescriptor *c = [super copyWithZone:z]; c.clearDepth = self.clearDepth; return c; }
@end
@implementation MTLRenderPassStencilAttachmentDescriptor
- (instancetype)init { if ((self = [super init])) { self.storeAction = MTLStoreActionDontCare; } return self; }
- (id)copyWithZone:(NSZone *)z { MTLRenderPassStencilAttachmentDescriptor *c = [super copyWithZone:z]; c.clearStencil = self.clearStencil; return c; }
@end
@implementation MTLRenderPassDescriptor { MTLRenderPassColorAttachmentDescriptorArray *_colors; }
@synthesize depthAttachment = _depthAttachment, stencilAttachment = _stencilAttachment, visibilityResultBuffer = _visibilityResultBuffer;
+ (MTLRenderPassDescriptor *)renderPassDescriptor { return [[[self alloc] init] autorelease]; }
- (instancetype)init {
    if ((self = [super init])) {
        _colors = [[MTLRenderPassColorAttachmentDescriptorArray alloc] init];
        _depthAttachment = [[MTLRenderPassDepthAttachmentDescriptor alloc] init];
        _stencilAttachment = [[MTLRenderPassStencilAttachmentDescriptor alloc] init];
    }
    return self;
}
- (void)dealloc { [_colors release]; [_depthAttachment release]; [_stencilAttachment release]; [_visibilityResultBuffer release]; [super dealloc]; }
- (MTLRenderPassColorAttachmentDescriptorArray *)colorAttachments { return _colors; }
- (id)copyWithZone:(NSZone *)z {
    MTLRenderPassDescriptor *c = [[[self class] alloc] init];
    [_colors copyDescriptorsInto:c->_colors]; c.depthAttachment = _depthAttachment; c.stencilAttachment = _stencilAttachment;
    c.renderTargetWidth = self.renderTargetWidth; c.renderTargetHeight = self.renderTargetHeight;
    c.visibilityResultBuffer = _visibilityResultBuffer; c.renderTargetArrayLength = self.renderTargetArrayLength;
    return c;
}
- (NSUInteger)getSamplePositions:(MTLSamplePosition *)p count:(NSUInteger)n { return 0; }
- (void)setSamplePositions:(const MTLSamplePosition *)p count:(NSUInteger)n { }
- (MTLRenderPassSampleBufferAttachmentDescriptorArray *)sampleBufferAttachments { return nil; }
@end

@implementation MTLTextureDescriptor
+ (MTLTextureDescriptor *)texture2DDescriptorWithPixelFormat:(MTLPixelFormat)f width:(NSUInteger)w height:(NSUInteger)h mipmapped:(BOOL)m {
    MTLTextureDescriptor *d = [[[self alloc] init] autorelease];
    d.pixelFormat = f; d.width = w; d.height = h;
    if (m) { NSUInteger n = 1, s = w > h ? w : h; while (s > 1) { s >>= 1; n++; } d.mipmapLevelCount = n; }
    return d;
}
+ (MTLTextureDescriptor *)textureCubeDescriptorWithPixelFormat:(MTLPixelFormat)f size:(NSUInteger)s mipmapped:(BOOL)m {
    MTLTextureDescriptor *d = [self texture2DDescriptorWithPixelFormat:f width:s height:s mipmapped:m]; d.textureType = MTLTextureTypeCube; return d;
}
+ (MTLTextureDescriptor *)textureBufferDescriptorWithPixelFormat:(MTLPixelFormat)f width:(NSUInteger)w resourceOptions:(MTLResourceOptions)o usage:(MTLTextureUsage)u {
    MTLTextureDescriptor *d = [self texture2DDescriptorWithPixelFormat:f width:w height:1 mipmapped:NO];
    d.textureType = MTLTextureTypeTextureBuffer; d.resourceOptions = o; d.usage = u; return d;
}
- (instancetype)init {
    if ((self = [super init])) {
        self.textureType = MTLTextureType2D; self.pixelFormat = MTLPixelFormatRGBA8Unorm; self.width = self.height = self.depth = 1;
        self.mipmapLevelCount = self.sampleCount = self.arrayLength = 1; self.usage = MTLTextureUsageShaderRead;
        self.allowGPUOptimizedContents = YES; self.resourceOptions = MTLResourceStorageModeManaged;
        self.swizzle = MTLTextureSwizzleChannelsMake(MTLTextureSwizzleRed, MTLTextureSwizzleGreen, MTLTextureSwizzleBlue, MTLTextureSwizzleAlpha);
    }
    return self;
}
- (MTLStorageMode)storageMode { return (MTLStorageMode)((self.resourceOptions >> 4) & 0xF); }
- (void)setStorageMode:(MTLStorageMode)m { self.resourceOptions = (self.resourceOptions & ~(MTLResourceOptions)0xF0) | ((MTLResourceOptions)m << 4); }
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)(self.resourceOptions & 0xF); }
- (void)setCpuCacheMode:(MTLCPUCacheMode)m { self.resourceOptions = (self.resourceOptions & ~(MTLResourceOptions)0xF) | m; }
- (MTLHazardTrackingMode)hazardTrackingMode { return (MTLHazardTrackingMode)((self.resourceOptions >> 8) & 0x3); }
- (void)setHazardTrackingMode:(MTLHazardTrackingMode)m { self.resourceOptions = (self.resourceOptions & ~(MTLResourceOptions)0x300) | ((MTLResourceOptions)m << 8); }
- (id)copyWithZone:(NSZone *)z {
    MTLTextureDescriptor *c = [[MTLTextureDescriptor alloc] init];
    c.textureType = self.textureType; c.pixelFormat = self.pixelFormat; c.width = self.width; c.height = self.height; c.depth = self.depth;
    c.mipmapLevelCount = self.mipmapLevelCount; c.sampleCount = self.sampleCount; c.arrayLength = self.arrayLength;
    c.resourceOptions = self.resourceOptions; c.usage = self.usage; c.allowGPUOptimizedContents = self.allowGPUOptimizedContents; c.swizzle = self.swizzle;
    return c;
}
@end

@implementation MTLSamplerDescriptor
- (instancetype)init { if ((self = [super init])) { self.maxAnisotropy = 1; self.normalizedCoordinates = YES; self.lodMaxClamp = 3.402823466e+38f; } return self; }
- (void)dealloc { [_label release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
    MTLSamplerDescriptor *c = [[MTLSamplerDescriptor alloc] init];
    c.minFilter = self.minFilter; c.magFilter = self.magFilter; c.mipFilter = self.mipFilter; c.maxAnisotropy = self.maxAnisotropy;
    c.sAddressMode = self.sAddressMode; c.tAddressMode = self.tAddressMode; c.rAddressMode = self.rAddressMode; c.borderColor = self.borderColor;
    c.normalizedCoordinates = self.normalizedCoordinates; c.lodMinClamp = self.lodMinClamp; c.lodMaxClamp = self.lodMaxClamp; c.compareFunction = self.compareFunction;
    return c;
}
@end
@implementation MTLStencilDescriptor
- (instancetype)init { if ((self = [super init])) { self.stencilCompareFunction = MTLCompareFunctionAlways; self.readMask = self.writeMask = 0xFFFFFFFF; } return self; }
- (id)copyWithZone:(NSZone *)z {
    MTLStencilDescriptor *c = [[MTLStencilDescriptor alloc] init];
    c.stencilCompareFunction = self.stencilCompareFunction; c.stencilFailureOperation = self.stencilFailureOperation;
    c.depthFailureOperation = self.depthFailureOperation; c.depthStencilPassOperation = self.depthStencilPassOperation;
    c.readMask = self.readMask; c.writeMask = self.writeMask;
    return c;
}
@end
@implementation MTLDepthStencilDescriptor
- (instancetype)init { if ((self = [super init])) { self.depthCompareFunction = MTLCompareFunctionAlways; } return self; }
- (void)dealloc { [_frontFaceStencil release]; [_backFaceStencil release]; [_label release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
    MTLDepthStencilDescriptor *c = [[MTLDepthStencilDescriptor alloc] init];
    c.depthCompareFunction = self.depthCompareFunction; c.depthWriteEnabled = self.depthWriteEnabled;
    c.frontFaceStencil = self.frontFaceStencil; c.backFaceStencil = self.backFaceStencil; return c;
}
@end
@implementation MTLCompileOptions
- (instancetype)init { if ((self = [super init])) { self.fastMathEnabled = YES; self.languageVersion = MTLLanguageVersion3_0; self.mathMode = MTLMathModeFast; } return self; }
- (void)setMathMode:(MTLMathMode)m { _mathMode = m; _fastMathEnabled = m == MTLMathModeFast; } /* ponytail: only fast vs not reaches the compiler */
- (void)dealloc { [_preprocessorMacros release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { MTLCompileOptions *c = [[MTLCompileOptions alloc] init]; c.preprocessorMacros = self.preprocessorMacros; c.fastMathEnabled = self.fastMathEnabled; c.languageVersion = self.languageVersion; c.mathMode = self.mathMode; c.mathFloatingPointFunctions = self.mathFloatingPointFunctions; return c; }
@end
@implementation MTLComputePipelineDescriptor
@synthesize computeFunction = _computeFunction, label = _label;
- (void)dealloc { [_computeFunction release]; [_label release]; [super dealloc]; }
- (MTLPipelineBufferDescriptorArray *)buffers { return nil; }
- (void)reset { self.computeFunction = nil; }
- (id)copyWithZone:(NSZone *)z { MTLComputePipelineDescriptor *c = [[MTLComputePipelineDescriptor alloc] init]; c.computeFunction = _computeFunction; return c; }
@end
@implementation MTLComputePassDescriptor
+ (MTLComputePassDescriptor *)computePassDescriptor { return [[[self alloc] init] autorelease]; }
- (MTLComputePassSampleBufferAttachmentDescriptorArray *)sampleBufferAttachments { return nil; }
- (id)copyWithZone:(NSZone *)z { MTLComputePassDescriptor *c = [[MTLComputePassDescriptor alloc] init]; c.dispatchType = self.dispatchType; return c; }
@end

/* ====================================================================== resources */
@interface _MWBuffer : _MWObject <MTLBuffer> { @public NSUInteger _len; MTLResourceOptions _opts; void *_ptr; uint64_t _gpu; void (^_dealloc)(void *, NSUInteger); } @end
/* ---- GPU addresses: the buffer's real Vulkan device address (shaders dereference pointers stored in buffers), kept
 * in a sorted table so an address maps back to its buffer (Metal 4 argument tables, setBuffer by address) */
static struct { uint64_t base, len; id buf; } *g_gpu; static size_t g_ngpu, g_capgpu;
static NSObject *g_gpu_lock;
static uint64_t mw_gpu_register(id b, uint64_t base, NSUInteger len) {
    if (!g_gpu_lock) g_gpu_lock = [[NSObject alloc] init];
    @synchronized(g_gpu_lock) {
        if (g_ngpu == g_capgpu) { g_capgpu = g_capgpu ? g_capgpu * 2 : 256; g_gpu = realloc(g_gpu, g_capgpu * sizeof *g_gpu); }
        size_t i = g_ngpu; while (i && g_gpu[i - 1].base > base) i--;
        memmove(&g_gpu[i + 1], &g_gpu[i], (g_ngpu - i) * sizeof *g_gpu);
        g_gpu[i].base = base; g_gpu[i].len = len; g_gpu[i].buf = b; g_ngpu++;
        return base;
    }
}
static void mw_gpu_unregister(id b) {
    @synchronized(g_gpu_lock) {
        for (size_t i = 0; i < g_ngpu; i++) if (g_gpu[i].buf == b) { memmove(&g_gpu[i], &g_gpu[i + 1], (g_ngpu - i - 1) * sizeof *g_gpu); g_ngpu--; break; }
    }
}
/* the buffer that holds a GPU address, and the offset in it (nil if none) */
id mw_buffer_at(uint64_t addr, NSUInteger *offset) {
    if (!g_gpu_lock) return nil;
    @synchronized(g_gpu_lock) {
        size_t lo = 0, hi = g_ngpu;
        while (lo < hi) { size_t m = (lo + hi) / 2; if (g_gpu[m].base <= addr) lo = m + 1; else hi = m; }
        if (!lo) return nil;
        size_t i = lo - 1;
        if (addr - g_gpu[i].base > g_gpu[i].len) return nil;
        if (offset) *offset = (NSUInteger)(addr - g_gpu[i].base);
        return g_gpu[i].buf;
    }
}
@implementation _MWBuffer
- (NSUInteger)length { return _len; }
- (void *)contents { if (!_ptr) _ptr = (void *)(uintptr_t)mw(MW_BUFFER_CONTENTS, _h, 0, 0, 0, 0); return _ptr; }
- (void)didModifyRange:(NSRange)r { }
/* the device address shaders see (Metal 3 / Metal 4 code passes addresses around; mw_buffer_at maps back) */
- (uint64_t)gpuAddress {
    if (!_gpu) _gpu = mw_gpu_register(self, (uint64_t)mw(MW_BUFFER_GPU_ADDRESS, _h, 0, 0, 0, 0), _len);
    return _gpu;
}
- (NSUInteger)allocatedSize { return _len; }
- (void)dealloc {
    if (_gpu) mw_gpu_unregister(self);
    void (^d)(void *, NSUInteger) = _dealloc; void *p = _ptr; NSUInteger n = _len;
    [super dealloc];   /* the host buffer goes first: then the memory under it can */
    if (d) { d(p, n); [d release]; }
}
- (MTLResourceOptions)resourceOptions { return _opts; }
- (MTLStorageMode)storageMode { return (MTLStorageMode)((_opts >> 4) & 0xF); }
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)(_opts & 0xF); }
- (MTLHazardTrackingMode)hazardTrackingMode { return (MTLHazardTrackingMode)((_opts >> 8) & 0x3); }
@end

/* ---- resource IDs: a texture's or sampler's index in the host's bindless table (what shaders read from argument buffers);
 * these tables map an ID back to its object (Metal 4 argument tables). Without bindless support the ID is the object. */
#define MW_RID_TEX 8192
#define MW_RID_SAMP 1024
static id g_rid_tex[MW_RID_TEX], g_rid_samp[MW_RID_SAMP]; static NSObject *g_rid_lock;
static uint64_t mw_rid(id obj, uint64_t h, BOOL sampler) {
    uint64_t r = (uint64_t)mw(MW_RESOURCE_ID, h, 0, 0, 0, 0);
    if (!r || r >= (sampler ? MW_RID_SAMP : MW_RID_TEX)) return (uint64_t)(uintptr_t)obj;
    if (!g_rid_lock) g_rid_lock = [[NSObject alloc] init];
    @synchronized(g_rid_lock) { (sampler ? g_rid_samp : g_rid_tex)[r] = obj; } /* unretained: cleared in dealloc */
    return r;
}
static void mw_rid_clear(uint64_t r, BOOL sampler) {
    if (r && r < (sampler ? MW_RID_SAMP : MW_RID_TEX)) @synchronized(g_rid_lock) { (sampler ? g_rid_samp : g_rid_tex)[r] = nil; }
}
id mw_resource_for_id(uint64_t r, BOOL sampler) {
    if (r && r < (sampler ? MW_RID_SAMP : MW_RID_TEX) && g_rid_lock) @synchronized(g_rid_lock) { return (sampler ? g_rid_samp : g_rid_tex)[r]; }
    return (id)(uintptr_t)r;
}
@interface _MWTexture : _MWObject <MTLTexture> {
@public uint64_t _rid;
@public MwTextureDesc _d; BOOL _framebufferOnly; id<MTLTexture> _parent; NSUInteger _plevel, _pslice; MTLTextureSwizzleChannels _swz; BOOL _hasSwz;
    id _buffer, _heap; NSUInteger _bufOffset, _bufBpr, _heapOffset; /* made from a buffer or in a heap (ponytail: their memory is not shared) */
} @end
@implementation _MWTexture
- (MTLTextureType)textureType { return (MTLTextureType)_d.texture_type; }
- (MTLPixelFormat)pixelFormat { return (MTLPixelFormat)_d.pixel_format; }
- (NSUInteger)width { return _d.width; }
- (NSUInteger)height { return _d.height; }
- (NSUInteger)depth { return _d.depth; }
- (NSUInteger)mipmapLevelCount { return _d.mip_levels; }
- (NSUInteger)arrayLength { return _d.array_length; }
- (NSUInteger)sampleCount { return _d.sample_count; }
- (BOOL)isFramebufferOnly { return _framebufferOnly; }
- (MTLTextureUsage)usage { return (MTLTextureUsage)_d.usage; }
- (BOOL)allowGPUOptimizedContents { return YES; }
- (BOOL)isShareable { return NO; }
- (MTLTextureSwizzleChannels)swizzle { MTLTextureSwizzleChannels s = {MTLTextureSwizzleRed, MTLTextureSwizzleGreen, MTLTextureSwizzleBlue, MTLTextureSwizzleAlpha}; return _hasSwz ? _swz : s; }
- (id<MTLTexture>)parentTexture { return _parent; }
- (NSUInteger)parentRelativeLevel { return _plevel; }
- (NSUInteger)parentRelativeSlice { return _pslice; }
/* resource IDs are the objects themselves: Metal 4 argument tables map them back (valid while the texture lives) */
- (MTLResourceID)gpuResourceID { if (!_rid) _rid = mw_rid(self, _h, NO); MTLResourceID r = {_rid}; return r; }
- (id<MTLBuffer>)buffer { return _buffer; }
- (NSUInteger)bufferOffset { return _bufOffset; }
- (NSUInteger)bufferBytesPerRow { return _bufBpr; }
- (id<MTLHeap>)heap { return _heap; }
- (NSUInteger)heapOffset { return _heapOffset; }
- (BOOL)isAliasable { return NO; }
- (void)makeAliasable { }
- (void)dealloc { mw_rid_clear(_rid, NO); [_parent release]; [_buffer release]; [_heap release]; [super dealloc]; }
/* an estimate: the levels' texels at 4 bytes (8 or 16 for wide formats), times layers and samples */
- (NSUInteger)allocatedSize {
    if (_parent) return 0;
    NSUInteger f = _d.pixel_format, bpp = f >= 110 && f <= 125 ? 8 : f >= 120 && f <= 129 ? 8 : f == 125 || f == 126 || f == 127 ? 16 : 4, total = 0;
    for (NSUInteger l = 0; l < (_d.mip_levels ? _d.mip_levels : 1); l++)
        total += MAX(1, _d.width >> l) * MAX(1, _d.height >> l) * MAX(1, (_d.depth ? _d.depth : 1) >> l);
    return total * bpp * MAX(1, _d.array_length) * MAX(1, _d.sample_count) * (_d.texture_type == MTLTextureTypeCube || _d.texture_type == MTLTextureTypeCubeArray ? 6 : 1);
}
- (MTLResourceOptions)resourceOptions { return (MTLResourceOptions)_d.resource_options; }
- (MTLStorageMode)storageMode { return (MTLStorageMode)((_d.resource_options >> 4) & 0xF); }
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)(_d.resource_options & 0xF); }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeDefault; }
- (void)replaceRegion:(MTLRegion)r mipmapLevel:(NSUInteger)l slice:(NSUInteger)s withBytes:(const void *)b bytesPerRow:(NSUInteger)bpr bytesPerImage:(NSUInteger)bpi {
    MwRegionCopy c = {r.origin.x, r.origin.y, r.origin.z, r.size.width, r.size.height, r.size.depth, l, s, U(b), bpr, bpi};
    mw(MW_TEXTURE_REPLACE, _h, U(&c), 0, 0, 0);
}
- (void)replaceRegion:(MTLRegion)r mipmapLevel:(NSUInteger)l withBytes:(const void *)b bytesPerRow:(NSUInteger)bpr {
    [self replaceRegion:r mipmapLevel:l slice:0 withBytes:b bytesPerRow:bpr bytesPerImage:bpr * r.size.height];
}
- (void)getBytes:(void *)b bytesPerRow:(NSUInteger)bpr bytesPerImage:(NSUInteger)bpi fromRegion:(MTLRegion)r mipmapLevel:(NSUInteger)l slice:(NSUInteger)s {
    MwRegionCopy c = {r.origin.x, r.origin.y, r.origin.z, r.size.width, r.size.height, r.size.depth, l, s, U(b), bpr, bpi ? bpi : bpr * r.size.height};
    mw(MW_TEXTURE_GETBYTES, _h, U(&c), 0, 0, 0);
}
- (void)getBytes:(void *)b bytesPerRow:(NSUInteger)bpr fromRegion:(MTLRegion)r mipmapLevel:(NSUInteger)l {
    [self getBytes:b bytesPerRow:bpr bytesPerImage:0 fromRegion:r mipmapLevel:l slice:0];
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)f textureType:(MTLTextureType)t levels:(NSRange)l slices:(NSRange)s swizzle:(MTLTextureSwizzleChannels)w {
    uint64_t v[7] = {f, t, l.location, l.length, s.location, s.length, (uint64_t)w.red | (uint64_t)w.green << 8 | (uint64_t)w.blue << 16 | (uint64_t)w.alpha << 24};
    uint64_t h = (uint64_t)mw(MW_TEXTURE_VIEW, _h, U(v), 0, 0, 0);
    if (!h) return nil;
    _MWTexture *x = mw_wrap([_MWTexture class], h, _device);
    x->_d = _d; x->_d.pixel_format = f; x->_d.texture_type = t; x->_d.mip_levels = l.length;
    x->_d.array_length = t == MTLTextureTypeCube || t == MTLTextureTypeCubeArray ? MAX(1, s.length / 6) : t == MTLTextureType3D ? 1 : s.length;
    x->_d.width = MAX(1, _d.width >> l.location); x->_d.height = MAX(1, _d.height >> l.location);
    if (t != MTLTextureType3D) x->_d.depth = 1; else x->_d.depth = MAX(1, _d.depth >> l.location);
    x->_framebufferOnly = _framebufferOnly; x->_swz = w; x->_hasSwz = YES;
    x->_parent = [self retain]; x->_plevel = l.location; x->_pslice = s.location; /* as Metal: relative to the texture it was made from */
    return x; /* mw_wrap: +1, as new... wants */
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)f textureType:(MTLTextureType)t levels:(NSRange)l slices:(NSRange)s {
    return [self newTextureViewWithPixelFormat:f textureType:t levels:l slices:s swizzle:[self swizzle]];
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)f {
    NSUInteger slices = _d.texture_type == MTLTextureType3D ? 1 : MAX(1, _d.array_length) * (_d.texture_type == MTLTextureTypeCube || _d.texture_type == MTLTextureTypeCubeArray ? 6 : 1);
    return [self newTextureViewWithPixelFormat:f textureType:(MTLTextureType)_d.texture_type levels:NSMakeRange(0, MAX(1, _d.mip_levels)) slices:NSMakeRange(0, slices)];
}
@end

@interface _MWSampler : _MWObject <MTLSamplerState> { uint64_t _rid; } @end
@implementation _MWSampler
- (MTLResourceID)gpuResourceID { if (!_rid) _rid = mw_rid(self, _h, YES); MTLResourceID r = {_rid}; return r; }
- (void)dealloc { mw_rid_clear(_rid, YES); [super dealloc]; }
@end
@interface _MWDepthStencil : _MWObject <MTLDepthStencilState> @end
@implementation _MWDepthStencil @end

/* ====================================================================== libraries and pipelines */
/* ---- function constants */
@interface MTLFunctionConstant () { @public NSString *_name; MTLDataType _type; NSUInteger _index; BOOL _required; } @end
@implementation MTLFunctionConstant
- (void)dealloc { [_name release]; [super dealloc]; }
- (NSString *)name { return _name; }
- (MTLDataType)type { return _type; }
- (NSUInteger)index { return _index; }
- (BOOL)required { return _required; }
@end
@interface MTLFunctionConstantValues () { @public NSMutableDictionary *_byIndex, *_byName; } @end
@implementation MTLFunctionConstantValues
- (instancetype)init { if ((self = [super init])) { _byIndex = [NSMutableDictionary new]; _byName = [NSMutableDictionary new]; } return self; }
- (void)dealloc { [_byIndex release]; [_byName release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
    MTLFunctionConstantValues *c = [[MTLFunctionConstantValues alloc] init];
    [c->_byIndex addEntriesFromDictionary:_byIndex]; [c->_byName addEntriesFromDictionary:_byName];
    return c;
}
static uint32_t fc_raw(const void *v, MTLDataType t) { /* scalars only: the shader reads a 32-bit specialization constant */
    switch (t) {
    case MTLDataTypeBool: return *(const uint8_t *)v ? 1 : 0;
    case MTLDataTypeChar: case MTLDataTypeUChar: return *(const uint8_t *)v;
    case MTLDataTypeShort: case MTLDataTypeUShort: case MTLDataTypeHalf: return *(const uint16_t *)v;
    default: return *(const uint32_t *)v;
    }
}
static NSUInteger fc_size(MTLDataType t) { return t == MTLDataTypeBool || t == MTLDataTypeChar || t == MTLDataTypeUChar ? 1 : t == MTLDataTypeShort || t == MTLDataTypeUShort || t == MTLDataTypeHalf ? 2 : 4; }
- (void)setConstantValue:(const void *)v type:(MTLDataType)t atIndex:(NSUInteger)i { _byIndex[@(i)] = @(fc_raw(v, t)); }
- (void)setConstantValues:(const void *)v type:(MTLDataType)t withRange:(NSRange)r {
    for (NSUInteger i = 0; i < r.length; i++) [self setConstantValue:(const uint8_t *)v + i * fc_size(t) type:t atIndex:r.location + i];
}
- (void)setConstantValue:(const void *)v type:(MTLDataType)t withName:(NSString *)n { _byName[n] = @(fc_raw(v, t)); }
- (void)reset { [_byIndex removeAllObjects]; [_byName removeAllObjects]; }
@end
static NSArray *mw_fc_info(uint64_t fn) { /* [[name, index], ...] as reported by the shader translator */
    char buf[4096] = {0};
    mw(MW_FUNCTION_FC_INFO, fn, U(buf), sizeof buf, 0, 0);
    NSMutableArray *r = [NSMutableArray array];
    for (NSString *line in [[NSString stringWithUTF8String:buf] componentsSeparatedByString:@"\n"]) {
        NSArray *p = [line componentsSeparatedByString:@"\t"];
        if (p.count == 2) [r addObject:@[p[0], @([p[1] integerValue])]];
    }
    return r;
}

/* ---- argument buffers (Tier 2): a plain struct of 8-byte GPU addresses and resource IDs; the layout comes from the
 * function ([[id(n)]] fields, scion's MSL compiler). ponytail: without it (precompiled metallibs), id n is at 8 * n */
@interface _MWArgumentEncoder : _MWObject <MTLArgumentEncoder> {
@public int64_t _size, _n, _e[4 * 256]; id<MTLBuffer> _buf; NSUInteger _off;
} @end
@implementation _MWArgumentEncoder
- (void)dealloc { [_buf release]; [super dealloc]; }
- (NSUInteger)encodedLength { return (NSUInteger)_size; }
- (NSUInteger)alignment { return 8; }
- (void)setArgumentBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o { [b retain]; [_buf release]; _buf = b; _off = o; }
- (void)setArgumentBuffer:(id<MTLBuffer>)b startOffset:(NSUInteger)o arrayElement:(NSUInteger)e { [self setArgumentBuffer:b offset:o + e * ((_size + 7) & ~7)]; }
/* where id `index` lives in the current argument buffer (0 if outside) */
- (uint8_t *)_mwSlot:(NSUInteger)index {
    if (!_buf) return 0;
    int64_t off = -1;
    for (int64_t k = 0; k < _n && off < 0; k++) {
        int64_t *e = &_e[4 * k];
        if ((int64_t)index >= e[0] && (int64_t)index < e[0] + e[3]) off = e[1] + ((int64_t)index - e[0]) * (e[2] ? 8 : 0);
    }
    if (off < 0 && !_n) off = (int64_t)index * 8;
    if (off < 0 || _off + (NSUInteger)off + 8 > _buf.length) return 0;
    return (uint8_t *)_buf.contents + _off + off;
}
- (void)setBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i {
    uint8_t *p = [self _mwSlot:i]; uint64_t v = b ? b.gpuAddress + o : 0;
    if (p) memcpy(p, &v, 8);
}
- (void)setBuffers:(const id<MTLBuffer> *)b offsets:(const NSUInteger *)o withRange:(NSRange)r {
    for (NSUInteger k = 0; k < r.length; k++) [self setBuffer:b[k] offset:o[k] atIndex:r.location + k];
}
- (void)setTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i { uint8_t *p = [self _mwSlot:i]; uint64_t v = t ? t.gpuResourceID._impl : 0; if (p) memcpy(p, &v, 8); }
- (void)setTextures:(const id<MTLTexture> *)t withRange:(NSRange)r { for (NSUInteger k = 0; k < r.length; k++) [self setTexture:t[k] atIndex:r.location + k]; }
- (void)setSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i { uint8_t *p = [self _mwSlot:i]; uint64_t v = s ? s.gpuResourceID._impl : 0; if (p) memcpy(p, &v, 8); }
- (void)setSamplerStates:(const id<MTLSamplerState> *)s withRange:(NSRange)r { for (NSUInteger k = 0; k < r.length; k++) [self setSamplerState:s[k] atIndex:r.location + k]; }
- (void *)constantDataAtIndex:(NSUInteger)i { return [self _mwSlot:i]; }
- (id<MTLArgumentEncoder>)newArgumentEncoderForBufferAtIndex:(NSUInteger)i { return nil; } /* ponytail: no nested argument buffers */
@end
static id<MTLArgumentEncoder> mw_argument_encoder(id f, NSUInteger index);
@interface _MWFunction : _MWObject <MTLFunction> { @public NSString *_name; MTLFunctionType _type; } 
- (void)applyConstants:(MTLFunctionConstantValues *)cv;
@end
@implementation _MWFunction
- (void)dealloc { [_name release]; [super dealloc]; }
- (NSString *)name { return _name; }
- (MTLFunctionType)functionType { return _type; }
- (MTLFunctionOptions)options { return 0; }
- (MTLPatchType)patchType { return 0; }
- (NSInteger)patchControlPointCount { return -1; }
- (NSArray *)vertexAttributes { return @[]; }
- (NSArray *)stageInputAttributes { return @[]; }
- (NSDictionary *)functionConstantsDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSArray *e in mw_fc_info(_h)) {
        MTLFunctionConstant *c = [[MTLFunctionConstant alloc] init];
        c->_name = [e[0] copy]; c->_index = [e[1] unsignedIntegerValue]; c->_type = MTLDataTypeNone; c->_required = YES;
        d[e[0]] = c;
        [c release];
    }
    return d;
}
- (void)applyConstants:(MTLFunctionConstantValues *)cv {
    /* index -> raw 32-bit value; named values resolved with the names the translator reported */
    NSMutableDictionary *byIndex = [cv->_byIndex mutableCopy];
    for (NSArray *e in mw_fc_info(_h)) {
        NSNumber *v = cv->_byName[e[0]];
        if (v) byIndex[e[1]] = v;
    }
    NSUInteger n = byIndex.count, i = 0;
    uint32_t *pairs = malloc(n * 8 + 8);
    for (NSNumber *k in byIndex) { pairs[2 * i] = (uint32_t)k.unsignedIntValue; pairs[2 * i + 1] = (uint32_t)[byIndex[k] unsignedIntValue]; i++; }
    if (n) mw(MW_FUNCTION_CONSTANTS, _h, U(pairs), n, 0, 0);
    free(pairs);
    [byIndex release];
}
- (id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex:(NSUInteger)i { return mw_argument_encoder(self, i); }
- (id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex:(NSUInteger)i reflection:(MTLAutoreleasedArgument *)r { if (r) *r = nil; return mw_argument_encoder(self, i); }
@end
static id<MTLArgumentEncoder> mw_argument_encoder(id f, NSUInteger index) {
    _MWArgumentEncoder *e = [[_MWArgumentEncoder alloc] init];
    e->_device = [((_MWObject *)f)->_device retain];
    e->_e[0] = 0;
    e->_n = mw(MW_FUNCTION_ARG_LAYOUT, ((_MWObject *)f)->_h, index, U(e->_e), 255, 0);
    e->_size = e->_e[0];
    if (e->_n < 0) e->_n = 0;
    else memmove(e->_e, e->_e + 1, sizeof(int64_t) * 4 * (size_t)e->_n);
    if (!e->_size) for (int64_t k = 0; k < e->_n; k++) { int64_t end = e->_e[4 * k + 1] + 8 * e->_e[4 * k + 3]; if (end > e->_size) e->_size = end; }
    if (!e->_size) e->_size = 8 * 64; /* ponytail: unknown layout */
    return e;
}

/* metallib (MTLB) function list: names and types, read directly from the container */
static NSDictionary *metallib_functions(NSData *data) {
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    const uint8_t *p = [data bytes]; NSUInteger n = [data length];
    if (n < 88 || memcmp(p, "MTLB", 4)) return r;
    uint64_t list; memcpy(&list, p + 24, 8);
    if (list + 4 > n) return r;
    uint32_t count; memcpy(&count, p + list, 4);
    const uint8_t *q = p + list + 4, *end = p + n;
    for (uint32_t i = 0; i < count && q + 4 <= end; i++) {
        uint32_t gsize; memcpy(&gsize, q, 4);
        const uint8_t *t = q + 4, *gend = q + gsize; NSString *name = nil; int type = -1;
        while (t + 6 <= gend && memcmp(t, "ENDT", 4)) {
            uint16_t sz; memcpy(&sz, t + 4, 2);
            if (!memcmp(t, "NAME", 4)) name = [NSString stringWithUTF8String:(const char *)t + 6];
            else if (!memcmp(t, "TYPE", 4)) type = t[6];
            t += 6 + sz;
        }
        if (name) [r setObject:@(type == 0 ? MTLFunctionTypeVertex : type == 1 ? MTLFunctionTypeFragment : type == 2 ? MTLFunctionTypeKernel : MTLFunctionTypeVisible) forKey:name];
        q = gend;
    }
    return r;
}
@interface _MWLibrary : _MWObject <MTLLibrary> { @public NSDictionary *_funcs; } @end
@implementation _MWLibrary
- (void)dealloc { [_funcs release]; [super dealloc]; }
- (NSArray *)functionNames { return [_funcs allKeys]; }
- (NSString *)installName { return nil; }
- (MTLLibraryType)type { return 0; }
- (id<MTLFunction>)newFunctionWithName:(NSString *)n {
    uint64_t h = (uint64_t)mw(MW_LIBRARY_FUNCTION, _h, U([n UTF8String]), 0, 0, 0);
    _MWFunction *f = mw_wrap([_MWFunction class], h, _device);
    if (f) { f->_name = [n copy]; f->_type = (MTLFunctionType)[[_funcs objectForKey:n] unsignedIntegerValue]; }
    return f;
}
- (id<MTLFunction>)newFunctionWithName:(NSString *)n constantValues:(MTLFunctionConstantValues *)cv error:(NSError **)error {
    _MWFunction *f = [self newFunctionWithName:n];
    if (!f) { if (error) *error = mw_error(4, "function not found"); return nil; }
    [f applyConstants:cv];
    return f;
}
- (void)newFunctionWithName:(NSString *)n constantValues:(MTLFunctionConstantValues *)cv completionHandler:(void (^)(id<MTLFunction>, NSError *))h {
    NSError *e = nil;
    id<MTLFunction> f = [self newFunctionWithName:n constantValues:cv error:&e];
    h(f, e);
    [f release];
}
@end

@interface _MWComputePSO : _MWObject <MTLComputePipelineState> @end
@implementation _MWComputePSO
- (NSUInteger)maxTotalThreadsPerThreadgroup { return (NSUInteger)mw(MW_COMPUTE_PSO_INFO, _h, 0, 0, 0, 0); }
- (NSUInteger)threadExecutionWidth { return (NSUInteger)mw(MW_COMPUTE_PSO_INFO, _h, 1, 0, 0, 0); }
- (NSUInteger)staticThreadgroupMemoryLength { return 0; }
- (BOOL)supportIndirectCommandBuffers { return NO; }
- (NSUInteger)imageblockMemoryLengthForDimensions:(MTLSize)d { return 0; }
- (id<MTLFunctionHandle>)functionHandleWithFunction:(id<MTLFunction>)f { return nil; }
- (id<MTLComputePipelineState>)newComputePipelineStateWithAdditionalBinaryFunctions:(NSArray *)f error:(NSError **)e { return nil; }
- (id<MTLVisibleFunctionTable>)newVisibleFunctionTableWithDescriptor:(MTLVisibleFunctionTableDescriptor *)d { return nil; }
- (id<MTLIntersectionFunctionTable>)newIntersectionFunctionTableWithDescriptor:(MTLIntersectionFunctionTableDescriptor *)d { return nil; }
@end
@interface _MWRenderPSO : _MWObject <MTLRenderPipelineState> @end
@implementation _MWRenderPSO @end

/* ====================================================================== commands */
@interface _MWCommandQueue : _MWObject <MTLCommandQueue> @end
@interface _MWCommandBuffer : _MWObject <MTLCommandBuffer> {
    @public id<MTLCommandQueue> _queue; NSMutableArray *_completed, *_scheduled; volatile MTLCommandBufferStatus _status;
    double _gpu0, _gpu1; /* GPU start and end (seconds, mach time), when measured (Metal 4 command buffers) */
}
@end
@interface _MWEncoder : _MWObject { @public _MWCommandBuffer *_cb; } @end
@implementation _MWEncoder
- (void)dealloc { [_cb release]; [super dealloc]; }
- (void)endEncoding { mw(MW_ENC_END, _h, 0, 0, 0, 0); }
- (void)pushDebugGroup:(NSString *)s { }
- (void)popDebugGroup { }
- (void)insertDebugSignpost:(NSString *)s { }
@end
static id mw_encoder(Class c, uint64_t h, _MWCommandBuffer *cb) {
    _MWEncoder *e = mw_wrap(c, h, cb->_device); if (e) e->_cb = [cb retain];
    return [e autorelease];
}

@interface _MWComputeEncoder : _MWEncoder <MTLComputeCommandEncoder> @end
@implementation _MWComputeEncoder
- (MTLDispatchType)dispatchType { return MTLDispatchTypeSerial; }
- (void)setComputePipelineState:(id<MTLComputePipelineState>)s { mw(MW_CE_SET_PSO, _h, H_(s), 0, 0, 0); }
- (void)setBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i { mw(MW_SET_BUFFER, _h, 0, H_(b), o, i); }
- (void)setBuffers:(const id<MTLBuffer> *)b offsets:(const NSUInteger *)o withRange:(NSRange)r { for (NSUInteger k = 0; k < r.length; k++) [self setBuffer:b[k] offset:o[k] atIndex:r.location + k]; }
- (void)setBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i { } /* ponytail: needs the last buffer per index */
- (void)setBytes:(const void *)p length:(NSUInteger)n atIndex:(NSUInteger)i { mw(MW_SET_BYTES, _h, 0, U(p), n, i); }
- (void)setTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i { mw(MW_SET_TEXTURE, _h, 0, H_(t), i, 0); }
- (void)setSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i { mw(MW_SET_SAMPLER, _h, 0, H_(s), i, 0); }
- (void)setThreadgroupMemoryLength:(NSUInteger)n atIndex:(NSUInteger)i { }
- (void)dispatchThreadgroupsWithIndirectBuffer:(id<MTLBuffer>)ib indirectBufferOffset:(NSUInteger)o threadsPerThreadgroup:(MTLSize)t {
    MwSize3 a = {H_(ib), o, 0}, b = {t.width, t.height, t.depth}; mw(MW_CE_DISPATCH, _h, U(&a), U(&b), 2, 0);
}
- (void)dispatchThreadgroups:(MTLSize)g threadsPerThreadgroup:(MTLSize)t {
    MwSize3 a = {g.width, g.height, g.depth}, b = {t.width, t.height, t.depth}; mw(MW_CE_DISPATCH, _h, U(&a), U(&b), 0, 0);
}
- (void)dispatchThreads:(MTLSize)g threadsPerThreadgroup:(MTLSize)t {
    MwSize3 a = {g.width, g.height, g.depth}, b = {t.width, t.height, t.depth}; mw(MW_CE_DISPATCH, _h, U(&a), U(&b), 1, 0);
}
@end

@interface _MWRenderEncoder : _MWEncoder <MTLRenderCommandEncoder> @end
@implementation _MWRenderEncoder
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)s { mw(MW_RE_SET_PSO, _h, H_(s), 0, 0, 0); }
- (void)setTriangleFillMode:(MTLTriangleFillMode)m { mw(MW_RE_SET_STATE, _h, 2, m, 0, 0); }
- (void)setFrontFacingWinding:(MTLWinding)w { mw(MW_RE_SET_STATE, _h, 1, w, 0, 0); }
- (void)setCullMode:(MTLCullMode)c { mw(MW_RE_SET_STATE, _h, 0, c, 0, 0); }
- (void)setDepthClipMode:(MTLDepthClipMode)m { mw(MW_RE_SET_STATE, _h, 3, m, 0, 0); }
- (void)setViewport:(MTLViewport)v { [self setViewports:&v count:1]; }
- (void)setViewports:(const MTLViewport *)v count:(NSUInteger)n { /* MTLViewport is six doubles */ if (n) mw(MW_RE_SET_VIEWPORT, _h, U(v), n, 0, 0); }
- (void)setScissorRect:(MTLScissorRect)r { [self setScissorRects:&r count:1]; }
- (void)setScissorRects:(const MTLScissorRect *)r count:(NSUInteger)n { /* x, y, width, height: four NSUIntegers */ if (n) mw(MW_RE_SET_SCISSOR, _h, U(r), n, 0, 0); }
- (void)setVertexBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i { mw(MW_SET_BUFFER, _h, 0, H_(b), o, i); }
- (void)setVertexBuffers:(const id<MTLBuffer> *)b offsets:(const NSUInteger *)o withRange:(NSRange)r { for (NSUInteger k = 0; k < r.length; k++) [self setVertexBuffer:b[k] offset:o[k] atIndex:r.location + k]; }
- (void)setVertexBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i { }
- (void)setVertexBytes:(const void *)p length:(NSUInteger)n atIndex:(NSUInteger)i { mw(MW_SET_BYTES, _h, 0, U(p), n, i); }
- (void)setFragmentBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i { mw(MW_SET_BUFFER, _h, 1, H_(b), o, i); }
- (void)setFragmentBuffers:(const id<MTLBuffer> *)b offsets:(const NSUInteger *)o withRange:(NSRange)r { for (NSUInteger k = 0; k < r.length; k++) [self setFragmentBuffer:b[k] offset:o[k] atIndex:r.location + k]; }
- (void)setFragmentBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i { }
- (void)setFragmentBytes:(const void *)p length:(NSUInteger)n atIndex:(NSUInteger)i { mw(MW_SET_BYTES, _h, 1, U(p), n, i); }
- (void)setVertexTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i { mw(MW_SET_TEXTURE, _h, 0, H_(t), i, 0); }
- (void)setFragmentTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i { mw(MW_SET_TEXTURE, _h, 1, H_(t), i, 0); }
- (void)setVertexSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i { mw(MW_SET_SAMPLER, _h, 0, H_(s), i, 0); }
- (void)setFragmentSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i { mw(MW_SET_SAMPLER, _h, 1, H_(s), i, 0); }
- (void)setDepthStencilState:(id<MTLDepthStencilState>)s { mw(MW_RE_SET_DEPTH_STENCIL, _h, H_(s), 0, 0, 0); }
- (void)setDepthBias:(float)b slopeScale:(float)s clamp:(float)c { float f[3] = {b, s, c}; mw(MW_RE_SET_STATE, _h, 5, U(f), 0, 0); }
- (void)setBlendColorRed:(float)r green:(float)g blue:(float)b alpha:(float)a { float f[4] = {r, g, b, a}; mw(MW_RE_SET_STATE, _h, 6, U(f), 0, 0); }
- (void)setStencilReferenceValue:(uint32_t)v { mw(MW_RE_SET_STATE, _h, 4, v, v, 0); }
- (void)setStencilFrontReferenceValue:(uint32_t)f backReferenceValue:(uint32_t)b { mw(MW_RE_SET_STATE, _h, 4, f, b, 0); }
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n instanceCount:(NSUInteger)ic baseInstance:(NSUInteger)bi {
    MwDraw d = {0, t, s, n, ic, bi, 0, 0, 0, 0}; mw(MW_RE_DRAW, _h, U(&d), 0, 0, 0);
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n instanceCount:(NSUInteger)ic { [self drawPrimitives:t vertexStart:s vertexCount:n instanceCount:ic baseInstance:0]; }
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n { [self drawPrimitives:t vertexStart:s vertexCount:n instanceCount:1 baseInstance:0]; }
- (void)drawPrimitives:(MTLPrimitiveType)t indirectBuffer:(id<MTLBuffer>)a indirectBufferOffset:(NSUInteger)o {
    MwDraw d = {2, t, H_(a), o, 0, 0, 0, 0, 0, 0}; mw(MW_RE_DRAW, _h, U(&d), 0, 0, 0);
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)io
               indirectBuffer:(id<MTLBuffer>)a indirectBufferOffset:(NSUInteger)o {
    MwDraw d = {3, t, H_(a), o, 0, 0, it, H_(ib), io, 0}; mw(MW_RE_DRAW, _h, U(&d), 0, 0, 0);
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)io
                instanceCount:(NSUInteger)ic baseVertex:(NSInteger)bv baseInstance:(NSUInteger)bi {
    MwDraw d = {1, t, 0, n, ic, bi, it, H_(ib), io, bv}; mw(MW_RE_DRAW, _h, U(&d), 0, 0, 0);
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)io instanceCount:(NSUInteger)ic {
    [self drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferOffset:io instanceCount:ic baseVertex:0 baseInstance:0];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)io {
    [self drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferOffset:io instanceCount:1 baseVertex:0 baseInstance:0];
}
@end

@interface _MWBlitEncoder : _MWEncoder <MTLBlitCommandEncoder> @end
@implementation _MWBlitEncoder
- (void)copyFromBuffer:(id<MTLBuffer>)s sourceOffset:(NSUInteger)so toBuffer:(id<MTLBuffer>)d destinationOffset:(NSUInteger)doff size:(NSUInteger)n {
    MwBlit b = {0}; b.kind = 0; b.src = H_(s); b.src_offset = so; b.dst = H_(d); b.dst_offset = doff; b.size = n; mw(MW_BLIT, _h, U(&b), 0, 0, 0);
}
- (void)copyFromBuffer:(id<MTLBuffer>)s sourceOffset:(NSUInteger)so sourceBytesPerRow:(NSUInteger)bpr sourceBytesPerImage:(NSUInteger)bpi
            sourceSize:(MTLSize)z toTexture:(id<MTLTexture>)d destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)o {
    [self copyFromBuffer:s sourceOffset:so sourceBytesPerRow:bpr sourceBytesPerImage:bpi sourceSize:z toTexture:d destinationSlice:ds destinationLevel:dl destinationOrigin:o options:MTLBlitOptionNone];
}
- (void)copyFromBuffer:(id<MTLBuffer>)s sourceOffset:(NSUInteger)so sourceBytesPerRow:(NSUInteger)bpr sourceBytesPerImage:(NSUInteger)bpi
            sourceSize:(MTLSize)z toTexture:(id<MTLTexture>)d destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)o options:(MTLBlitOption)opt {
    MwBlit b = {0}; b.kind = 1; b.value = opt; b.src = H_(s); b.src_offset = so; b.src_bytes_per_row = bpr; b.src_bytes_per_image = bpi;
    b.w = z.width; b.h = z.height; b.d = z.depth; b.dst = H_(d); b.dst_slice = ds; b.dst_level = dl; b.dx = o.x; b.dy = o.y; b.dz = o.z;
    mw(MW_BLIT, _h, U(&b), 0, 0, 0);
}
- (void)copyFromTexture:(id<MTLTexture>)s sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)z
               toBuffer:(id<MTLBuffer>)d destinationOffset:(NSUInteger)doff destinationBytesPerRow:(NSUInteger)bpr destinationBytesPerImage:(NSUInteger)bpi {
    [self copyFromTexture:s sourceSlice:ss sourceLevel:sl sourceOrigin:so sourceSize:z toBuffer:d destinationOffset:doff destinationBytesPerRow:bpr destinationBytesPerImage:bpi options:MTLBlitOptionNone];
}
- (void)copyFromTexture:(id<MTLTexture>)s sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)z
              toTexture:(id<MTLTexture>)d destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)o {
    MwBlit b = {0}; b.kind = 3; b.src = H_(s); b.src_slice = ss; b.src_level = sl; b.sx = so.x; b.sy = so.y; b.sz = so.z;
    b.w = z.width; b.h = z.height; b.d = z.depth; b.dst = H_(d); b.dst_slice = ds; b.dst_level = dl; b.dx = o.x; b.dy = o.y; b.dz = o.z;
    mw(MW_BLIT, _h, U(&b), 0, 0, 0);
}
- (void)copyFromTexture:(id<MTLTexture>)s sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)z
               toBuffer:(id<MTLBuffer>)d destinationOffset:(NSUInteger)doff destinationBytesPerRow:(NSUInteger)bpr destinationBytesPerImage:(NSUInteger)bpi options:(MTLBlitOption)o {
    MwBlit b = {0}; b.kind = 2; b.src = H_(s); b.src_slice = ss; b.src_level = sl; b.sx = so.x; b.sy = so.y; b.sz = so.z;
    b.w = z.width; b.h = z.height; b.d = z.depth; b.dst = H_(d); b.dst_offset = doff; b.dst_bytes_per_row = bpr; b.dst_bytes_per_image = bpi;
    b.value = o; /* depth or stencil plane of a combined format */
    mw(MW_BLIT, _h, U(&b), 0, 0, 0);
}
/* whole levels and slices, one region copy each */
- (void)copyFromTexture:(id<MTLTexture>)s sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl toTexture:(id<MTLTexture>)d
       destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl sliceCount:(NSUInteger)sc levelCount:(NSUInteger)lc {
    for (NSUInteger l = 0; l < lc; l++) for (NSUInteger i = 0; i < sc; i++) {
        NSUInteger lv = sl + l;
        MTLSize z = MTLSizeMake(MAX(s.width >> lv, 1u), MAX(s.height >> lv, 1u), s.textureType == MTLTextureType3D ? MAX(s.depth >> lv, 1u) : 1);
        [self copyFromTexture:s sourceSlice:ss + i sourceLevel:lv sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:z
                    toTexture:d destinationSlice:ds + i destinationLevel:dl + l destinationOrigin:MTLOriginMake(0, 0, 0)];
    }
}
- (void)copyFromTexture:(id<MTLTexture>)s toTexture:(id<MTLTexture>)d {
    [self copyFromTexture:s sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(s.width, s.height, s.depth)
                toTexture:d destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
}
- (void)fillBuffer:(id<MTLBuffer>)buf range:(NSRange)r value:(uint8_t)v {
    MwBlit b = {0}; b.kind = 4; b.dst = H_(buf); b.dst_offset = r.location; b.size = r.length; b.value = v; mw(MW_BLIT, _h, U(&b), 0, 0, 0);
}
- (void)generateMipmapsForTexture:(id<MTLTexture>)t { MwBlit b = {0}; b.kind = 5; b.dst = H_(t); mw(MW_BLIT, _h, U(&b), 0, 0, 0); }
- (void)synchronizeResource:(id<MTLResource>)r { } /* shared memory: nothing to do */
@end

static void fill_pass(MwRenderPassDesc *p, MTLRenderPassDescriptor *d) {
    memset(p, 0, sizeof *p);
    id colors = d.colorAttachments;
    for (NSUInteger i = 0; i < MW_MAX_COLOR; i++) {
        MTLRenderPassColorAttachmentDescriptor *c = [colors existingAtIndex:i];
        if (!c.texture) continue;
        MwPassAttachment *a = &p->color[i]; MTLClearColor cc = c.clearColor;
        a->texture = H_(c.texture); a->level = c.level; a->slice = c.slice; a->depth_plane = c.depthPlane; a->resolve_texture = H_(c.resolveTexture);
        a->load_action = c.loadAction; a->store_action = c.storeAction;
        a->clear[0] = cc.red; a->clear[1] = cc.green; a->clear[2] = cc.blue; a->clear[3] = cc.alpha;
    }
    p->color_count = MW_MAX_COLOR; /* every slot, empty ones unused: Vulkan wants a pipeline's blend states to match the pass */
    MTLRenderPassDepthAttachmentDescriptor *dp = d.depthAttachment;
    if (dp.texture) { p->depth.texture = H_(dp.texture); p->depth.level = dp.level; p->depth.slice = dp.slice; p->depth.load_action = dp.loadAction; p->depth.store_action = dp.storeAction; p->depth.clear[0] = dp.clearDepth; }
    MTLRenderPassStencilAttachmentDescriptor *sp = d.stencilAttachment;
    if (sp.texture) { p->stencil.texture = H_(sp.texture); p->stencil.load_action = sp.loadAction; p->stencil.store_action = sp.storeAction; p->stencil.clear[1] = sp.clearStencil; }
    p->width = d.renderTargetWidth; p->height = d.renderTargetHeight;
    p->visibility = H_(d.visibilityResultBuffer); p->array_length = d.renderTargetArrayLength;
    p->visibility_accumulate = [d isKindOfClass:[MTL4RenderPassDescriptor class]] && ((MTL4RenderPassDescriptor *)d).visibilityResultType == MTLVisibilityResultTypeAccumulate;
}

static void mw_overlay_composite(id<MTLCommandBuffer> cb, id<MTLDrawable> d); /* CAMetalLayer, below */
@implementation _MWCommandBuffer
- (void)dealloc { [_queue release]; [_completed release]; [_scheduled release]; [super dealloc]; }
- (id<MTLCommandQueue>)commandQueue { return _queue; }
- (MTLCommandBufferStatus)status { return _status; }
- (NSError *)error { return nil; }
- (CFTimeInterval)GPUStartTime { return _gpu0; }
- (CFTimeInterval)GPUEndTime { return _gpu1; }
- (CFTimeInterval)kernelStartTime { return 0; }
- (CFTimeInterval)kernelEndTime { return 0; }
- (id<MTLComputeCommandEncoder>)computeCommandEncoder { return mw_encoder([_MWComputeEncoder class], (uint64_t)mw(MW_CB_COMPUTE_ENCODER, _h, 0, 0, 0, 0), self); }
- (id<MTLComputeCommandEncoder>)computeCommandEncoderWithDispatchType:(MTLDispatchType)t { return [self computeCommandEncoder]; }
- (id<MTLComputeCommandEncoder>)computeCommandEncoderWithDescriptor:(MTLComputePassDescriptor *)d { return [self computeCommandEncoder]; }
- (id<MTLBlitCommandEncoder>)blitCommandEncoder { return mw_encoder([_MWBlitEncoder class], (uint64_t)mw(MW_CB_BLIT_ENCODER, _h, 0, 0, 0, 0), self); }
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)d {
    MwRenderPassDesc p; fill_pass(&p, d);
    return mw_encoder([_MWRenderEncoder class], (uint64_t)mw(MW_CB_RENDER_ENCODER, _h, U(&p), 0, 0, 0), self);
}
- (void)addCompletedHandler:(MTLCommandBufferHandler)b { if (!_completed) _completed = [[NSMutableArray alloc] init]; [_completed addObject:[[b copy] autorelease]]; }
- (void)addScheduledHandler:(MTLCommandBufferHandler)b { if (!_scheduled) _scheduled = [[NSMutableArray alloc] init]; [_scheduled addObject:[[b copy] autorelease]]; }
- (void)enqueue { if (_status < MTLCommandBufferStatusEnqueued) _status = MTLCommandBufferStatusEnqueued; }
- (void)presentDrawable:(id<MTLDrawable>)d { mw_overlay_composite(self, d); mw(MW_CB_PRESENT, _h, H_(d), 0, 0, 0); }
- (void)presentDrawable:(id<MTLDrawable>)d atTime:(CFTimeInterval)t { [self presentDrawable:d]; }
- (void)presentDrawable:(id<MTLDrawable>)d afterMinimumDuration:(CFTimeInterval)t { [self presentDrawable:d]; }
- (void)pushDebugGroup:(NSString *)s { }
- (void)popDebugGroup { }
- (void)commit {
    mw(MW_CB_COMMIT, _h, 0, 0, 0, 0);
    _status = MTLCommandBufferStatusCommitted;
    for (MTLCommandBufferHandler b in _scheduled) b(self);
    if (![_completed count]) return;
    [self retain];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{   /* completion is observed in the guest: no host->guest callbacks */
        [self waitUntilCompleted];
        for (MTLCommandBufferHandler b in _completed) b(self);
        [self release];
    });
}
- (void)waitUntilScheduled { }
- (void)waitUntilCompleted { mw(MW_CB_WAIT, _h, 0, 0, 0, 0); _status = MTLCommandBufferStatusCompleted; }
@end

@implementation _MWCommandQueue
- (id<MTLCommandBuffer>)commandBuffer {
    _MWCommandBuffer *cb = mw_wrap([_MWCommandBuffer class], (uint64_t)mw(MW_QUEUE_COMMAND_BUFFER, _h, 0, 0, 0, 0), _device);
    if (cb) cb->_queue = [self retain];
    return [cb autorelease];
}
- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences { return [self commandBuffer]; }
@end

/* ====================================================================== device */
@interface _MWDevice : _MWObject <MTLDevice> { NSString *_name; } @end
@implementation _MWDevice
- (NSString *)name {
    if (!_name) { char b[256] = {0}; mw(MW_DEVICE_NAME, _h, U(b), sizeof b, 0, 0); _name = [[NSString alloc] initWithUTF8String:b]; }
    return _name;
}
- (MTLSize)maxThreadsPerThreadgroup { return MTLSizeMake(1024, 1024, 1024); }
- (BOOL)isLowPower { return NO; }
- (BOOL)isHeadless { return NO; }
- (BOOL)isRemovable { return NO; }
- (uint64_t)registryID { return 1; }
- (uint64_t)recommendedMaxWorkingSetSize { return 4ull << 30; }
- (NSUInteger)currentAllocatedSize { return 0; } /* ponytail: not tracked */
- (NSUInteger)maxThreadgroupMemoryLength { return 32768; }
- (NSUInteger)maxBufferLength { return 1ull << 32; }
- (BOOL)supportsFamily:(NSInteger)f { return f < 3000; } /* Apple and Common families: answer yes, Metal 3+ specifics: no */
- (BOOL)supportsTextureSampleCount:(NSUInteger)n { return n == 1 || n == 4; }
- (id<MTLCommandQueue>)newCommandQueue { return mw_wrap([_MWCommandQueue class], (uint64_t)mw(MW_NEW_QUEUE, _h, 0, 0, 0, 0), self); }
- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)n { return [self newCommandQueue]; }
- (id<MTLBuffer>)newBufferWithBytes:(const void *)p length:(NSUInteger)n options:(MTLResourceOptions)o {
    _MWBuffer *b = mw_wrap([_MWBuffer class], (uint64_t)mw(MW_NEW_BUFFER, _h, n, o, U(p), 0), self);
    if (b) { b->_len = n; b->_opts = o; }
    return b;
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)n options:(MTLResourceOptions)o { return [self newBufferWithBytes:0 length:n options:o]; }
/* the buffer is the caller's memory (Vulkan imports it: VK_EXT_external_memory_host), so CPU writes after creation
 * reach the GPU; the deallocator runs when the buffer goes. A device or a pointer that cannot be imported (the
 * driver's alignment) gets a copy. */
- (id<MTLBuffer>)newBufferWithBytesNoCopy:(void *)p length:(NSUInteger)n options:(MTLResourceOptions)o deallocator:(void (^)(void *, NSUInteger))d {
    static int off = -1; if (off < 0) { const char *e = getenv("SCION_METAL_NOCOPY"); off = e && *e == '0'; }   /* =0: always copy (to compare) */
    uint64_t h = off ? 0 : (uint64_t)mw(MW_NEW_BUFFER_NOCOPY, _h, U(p), n, o, 0);
    if (!h) {
        if (getenv("SCION_METAL_INFO")) fprintf(stderr, "scion-metal: newBufferWithBytesNoCopy %p+%lu is copied\n", p, (unsigned long)n);
        id<MTLBuffer> b = [self newBufferWithBytes:p length:n options:o];
        if (d) d(p, n);
        return b;
    }
    _MWBuffer *b = mw_wrap([_MWBuffer class], h, self);
    if (b) { b->_len = n; b->_opts = o; b->_ptr = p; b->_dealloc = [d copy]; }
    return b;
}
/* shared buffers are host memory the GPU reads directly: unified, as far as an app can tell, when the device can
 * also take the app's own memory (newBufferWithBytesNoCopy) */
- (BOOL)hasUnifiedMemory { return mw(MW_DEVICE_HOST_MEMORY, _h, 0, 0, 0, 0) > 0; }
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d {
    MwTextureDesc t = {d.textureType, d.pixelFormat, d.width, d.height, d.depth, d.mipmapLevelCount, d.sampleCount, d.arrayLength, d.resourceOptions, d.usage};
    uint64_t h = (uint64_t)mw(MW_NEW_TEXTURE, _h, U(&t), 0, 0, 0);
    MTLTextureSwizzleChannels w = d.swizzle;
    if (!w.red && !w.green && !w.blue && !w.alpha) w = MTLTextureSwizzleChannelsMake(MTLTextureSwizzleRed, MTLTextureSwizzleGreen, MTLTextureSwizzleBlue, MTLTextureSwizzleAlpha);
    BOOL swz = h && (w.red != MTLTextureSwizzleRed || w.green != MTLTextureSwizzleGreen || w.blue != MTLTextureSwizzleBlue || w.alpha != MTLTextureSwizzleAlpha);
    if (swz) { /* a swizzled texture is a view of itself with that swizzle (the view keeps the image) */
        NSUInteger slices = t.texture_type == MTLTextureType3D ? 1 : MAX(1, t.array_length) * (t.texture_type == MTLTextureTypeCube || t.texture_type == MTLTextureTypeCubeArray ? 6 : 1);
        uint64_t v[7] = {t.pixel_format, t.texture_type, 0, MAX(1, t.mip_levels), 0, slices, (uint64_t)w.red | (uint64_t)w.green << 8 | (uint64_t)w.blue << 16 | (uint64_t)w.alpha << 24};
        uint64_t vh = (uint64_t)mw(MW_TEXTURE_VIEW, h, U(v), 0, 0, 0);
        if (vh) { mw(MW_RELEASE, h, 0, 0, 0, 0); h = vh; } else swz = NO;
    }
    _MWTexture *x = mw_wrap([_MWTexture class], h, self);
    if (x) { x->_d = t; if (swz) { x->_swz = w; x->_hasSwz = YES; } }
    return x;
}
- (id<MTLSamplerState>)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)d {
    MwSamplerDesc s = {d.minFilter, d.magFilter, d.mipFilter, d.maxAnisotropy, d.sAddressMode, d.tAddressMode, d.rAddressMode, d.borderColor,
                       d.normalizedCoordinates, d.compareFunction, d.lodMinClamp, d.lodMaxClamp};
    return mw_wrap([_MWSampler class], (uint64_t)mw(MW_NEW_SAMPLER, _h, U(&s), 0, 0, 0), self);
}
static void fill_stencil(MwStencilDesc *o, MTLStencilDescriptor *s) {
    if (!s) return;
    o->enabled = 1; o->compare = s.stencilCompareFunction; o->stencil_fail = s.stencilFailureOperation; o->depth_fail = s.depthFailureOperation;
    o->pass = s.depthStencilPassOperation; o->read_mask = s.readMask; o->write_mask = s.writeMask;
}
- (id<MTLDepthStencilState>)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)d {
    MwDepthStencilDesc s; memset(&s, 0, sizeof s);
    s.depth_compare = d.depthCompareFunction; s.depth_write = d.depthWriteEnabled;
    fill_stencil(&s.front, d.frontFaceStencil); fill_stencil(&s.back, d.backFaceStencil);
    return mw_wrap([_MWDepthStencil class], (uint64_t)mw(MW_NEW_DEPTH_STENCIL, _h, U(&s), 0, 0, 0), self);
}
- (id<MTLLibrary>)newLibraryWithNSData:(NSData *)data error:(NSError **)error {
    char err[256] = {0};
    if (!data) { if (error) *error = mw_error(1, "could not read the metallib"); return nil; }
    _MWLibrary *l = mw_wrap([_MWLibrary class], (uint64_t)mw(MW_NEW_LIBRARY, _h, U([data bytes]), [data length], U(err), 0), self);
    if (!l) { if (error) *error = mw_error(1, err); return nil; }
    l->_funcs = [metallib_functions(data) retain];
    return l;
}
- (id<MTLLibrary>)newLibraryWithFile:(NSString *)p error:(NSError **)e { return [self newLibraryWithNSData:[NSData dataWithContentsOfFile:p] error:e]; }
- (id<MTLLibrary>)newLibraryWithURL:(NSURL *)u error:(NSError **)e { return [self newLibraryWithFile:[u path] error:e]; }
- (id<MTLLibrary>)newLibraryWithData:(dispatch_data_t)d error:(NSError **)e {
    const void *p = NULL; size_t n = 0;
    (void)dispatch_data_create_map(d, &p, &n);
    return [self newLibraryWithNSData:p ? [NSData dataWithBytes:p length:n] : nil error:e];
}
- (id<MTLLibrary>)newDefaultLibraryWithBundle:(NSBundle *)b error:(NSError **)e {
    NSString *p = [b pathForResource:@"default" ofType:@"metallib"];
    if (!p) p = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"default.metallib"];
    return [self newLibraryWithFile:p error:e];
}
- (id<MTLLibrary>)newDefaultLibrary { return [self newDefaultLibraryWithBundle:[NSBundle mainBundle] error:nil]; }
- (id<MTLLibrary>)newLibraryWithSource:(NSString *)s options:(MTLCompileOptions *)o error:(NSError **)e {
    /* MSL -> metallib on the host (clang + metal_stdlib, cached on disk), then the usual metallib path */
    NSMutableString *macros = [NSMutableString string];
    for (NSString *k in o.preprocessorMacros) [macros appendFormat:@"#define %@ %@\n", k, [[o.preprocessorMacros objectForKey:k] description]];
    char *err = calloc(1, 8192);
    uint64_t len = 0;
    void *lib = (void *)mw(MW_COMPILE_SOURCE, U([s UTF8String]), U([macros UTF8String]), U(err), 8192, U(&len));
    if (!lib) {
        if (e) *e = mw_error(3, err[0] ? err : "scion: the MSL source did not compile");
        free(err);
        return nil;
    }
    free(err);
    NSData *d = [NSData dataWithBytes:lib length:len];
    mw(MW_HOST_FREE, U(lib), 0, 0, 0, 0);
    return [self newLibraryWithNSData:d error:e];
}
- (void)newLibraryWithSource:(NSString *)s options:(MTLCompileOptions *)o completionHandler:(void (^)(id<MTLLibrary>, NSError *))h {
    NSError *e = nil;
    id<MTLLibrary> l = [self newLibraryWithSource:s options:o error:&e];
    h(l, e);
    [l release];
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)f error:(NSError **)error {
    char err[256] = {0};
    id p = mw_wrap([_MWComputePSO class], (uint64_t)mw(MW_NEW_COMPUTE_PSO, _h, H_(f), U(err), 0, 0), self);
    if (!p && error) *error = mw_error(2, err);
    return p;
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)f options:(MTLPipelineOption)o reflection:(MTLAutoreleasedComputePipelineReflection *)r error:(NSError **)e {
    return [self newComputePipelineStateWithFunction:f error:e];
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)d options:(MTLPipelineOption)o reflection:(MTLAutoreleasedComputePipelineReflection *)r error:(NSError **)e {
    return [self newComputePipelineStateWithFunction:d.computeFunction error:e];
}
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d error:(NSError **)error {
    MwRenderPipelineDesc *p = malloc(sizeof *p); memset(p, 0, sizeof *p);
    p->vertex_function = H_(d.vertexFunction); p->fragment_function = H_(d.fragmentFunction);
    id colors = d.colorAttachments;
    for (NSUInteger i = 0; i < MW_MAX_COLOR; i++) {
        MTLRenderPipelineColorAttachmentDescriptor *c = [colors existingAtIndex:i];
        if (!c || c.pixelFormat == MTLPixelFormatInvalid) continue;
        MwColorAttachmentPipe *x = &p->color[i];
        x->pixel_format = c.pixelFormat; x->write_mask = c.writeMask; x->blending = c.blendingEnabled;
        x->src_rgb = c.sourceRGBBlendFactor; x->dst_rgb = c.destinationRGBBlendFactor; x->op_rgb = c.rgbBlendOperation;
        x->src_a = c.sourceAlphaBlendFactor; x->dst_a = c.destinationAlphaBlendFactor; x->op_a = c.alphaBlendOperation;
    }
    p->color_count = MW_MAX_COLOR; /* as many as a pass (fill_pass); empty slots write nothing */
    p->depth_format = d.depthAttachmentPixelFormat; p->stencil_format = d.stencilAttachmentPixelFormat;
    p->sample_count = d.rasterSampleCount > d.sampleCount ? d.rasterSampleCount : d.sampleCount;
    p->rasterization_enabled = d.rasterizationEnabled; p->topology_class = d.inputPrimitiveTopology; p->alpha_to_coverage = d.alphaToCoverageEnabled;
    MTLVertexDescriptor *vd = d.vertexDescriptor;
    if (vd) {
        p->has_vertex_desc = 1;
        id attrs = vd.attributes, layouts = vd.layouts;
        for (NSUInteger i = 0; i < MW_MAX_VERTEX_ATTR; i++) {
            MTLVertexAttributeDescriptor *a = [attrs existingAtIndex:i];
            if (a) { p->attr[i].format = a.format; p->attr[i].offset = a.offset; p->attr[i].buffer_index = a.bufferIndex; }
        }
        for (NSUInteger i = 0; i < MW_MAX_VERTEX_BUF; i++) {
            MTLVertexBufferLayoutDescriptor *l = [layouts existingAtIndex:i];
            if (l) { p->layout[i].stride = l.stride; p->layout[i].step_function = l.stepFunction; p->layout[i].step_rate = l.stepRate; }
        }
    }
    char err[256] = {0};
    id r = mw_wrap([_MWRenderPSO class], (uint64_t)mw(MW_NEW_RENDER_PSO, _h, U(p), U(err), 0, 0), self);
    free(p);
    if (!r && error) *error = mw_error(2, err);
    return r;
}
@end

/* ====================================================================== entry points */
static _MWDevice *g_dev;
id<MTLDevice> MTLCreateSystemDefaultDevice(void) {
    static int tried;
    if (!tried) { tried = 1; uint64_t h = (uint64_t)mw(MW_DEVICE_CREATE, 0, 0, 0, 0, 0); if (h) { g_dev = [[_MWDevice alloc] init]; g_dev->_h = h; } }
    return [g_dev retain];
}
NSArray *MTLCopyAllDevices(void) { id<MTLDevice> d = MTLCreateSystemDefaultDevice(); NSArray *a = d ? [[NSArray alloc] initWithObjects:d, nil] : [[NSArray alloc] init]; [d release]; return a; }
NSString *const MTLDeviceWasAddedNotification = @"MTLDeviceWasAddedNotification";
NSString *const MTLDeviceRemovalRequestedNotification = @"MTLDeviceRemovalRequestedNotification";
NSString *const MTLDeviceWasRemovedNotification = @"MTLDeviceWasRemovedNotification";

/* ====================================================================== QuartzCore (CALayer, CAMetalLayer) */
/* QuartzCore.framework maps to this dylib (dyld alias). Each CAMetalLayer owns a host window + swapchain, created on
 * the first -nextDrawable with drawableSize (or bounds * contentsScale). */
#import <QuartzCore/CAMetalLayer.h>

/* CALayer keeps the geometry and properties apps set; it composites nothing: a CAMetalLayer presents on its own, other
 * layers are only state (backgrounds, sublayers of overlays). */
@implementation CALayer { NSMutableArray *_subs; }
+ (instancetype)layer { return [[[self alloc] init] autorelease]; }
- (instancetype)init { if ((self = [super init])) { _contentsScale = 1; _opacity = 1; _anchorPoint = CGPointMake(0.5, 0.5); } return self; }
- (void)dealloc {
    for (CALayer *l in _subs) l->_superlayer = nil;
    [_subs release]; [_name release]; [_contents release]; [_actions release]; [_contentsGravity release];
    if (_backgroundColor) CFRelease(_backgroundColor);
    if (_borderColor) CFRelease(_borderColor);
    [super dealloc];
}
/* AppKit draws a view's layer (background, corners, border, contents): it hears about changes through the view */
- (void)_mwChanged { if ([_delegate respondsToSelector:@selector(_mwLayerChanged)]) [_delegate performSelector:@selector(_mwLayerChanged)]; }
- (void)setBackgroundColor:(CGColorRef)c { if (c) CFRetain(c); if (_backgroundColor) CFRelease(_backgroundColor); _backgroundColor = c; [self _mwChanged]; }
- (void)setBorderColor:(CGColorRef)c { if (c) CFRetain(c); if (_borderColor) CFRelease(_borderColor); _borderColor = c; [self _mwChanged]; }
- (void)setCornerRadius:(CGFloat)r { _cornerRadius = r; [self _mwChanged]; }
- (void)setBorderWidth:(CGFloat)w { _borderWidth = w; [self _mwChanged]; }
- (void)setOpacity:(float)o { _opacity = o; [self _mwChanged]; }
- (void)setHidden:(BOOL)h { _hidden = h; [self _mwChanged]; }
- (void)setMasksToBounds:(BOOL)m { _masksToBounds = m; [self _mwChanged]; }
- (void)setContents:(id)c { [c retain]; [_contents release]; _contents = c; [self _mwChanged]; }
- (void)setFrame:(CGRect)f {
    _frame = f; _bounds.size = f.size;
    _position = CGPointMake(f.origin.x + f.size.width * _anchorPoint.x, f.origin.y + f.size.height * _anchorPoint.y);
}
- (void)setBounds:(CGRect)b {
    _bounds = b;
    _frame = CGRectMake(_position.x - b.size.width * _anchorPoint.x, _position.y - b.size.height * _anchorPoint.y, b.size.width, b.size.height);
}
- (void)setPosition:(CGPoint)p { _position = p; _frame.origin = CGPointMake(p.x - _bounds.size.width * _anchorPoint.x, p.y - _bounds.size.height * _anchorPoint.y); }
- (NSArray *)sublayers { return _subs ? [[_subs copy] autorelease] : nil; }
- (void)setSublayers:(NSArray *)a {
    while ([_subs count]) [[_subs lastObject] removeFromSuperlayer];
    for (CALayer *l in a) [self addSublayer:l];
}
- (void)insertSublayer:(CALayer *)l atIndex:(unsigned)i {
    [l retain]; [l removeFromSuperlayer];
    if (!_subs) _subs = [[NSMutableArray alloc] init];
    [_subs insertObject:l atIndex:i > [_subs count] ? [_subs count] : i];
    l->_superlayer = self; [l release];
}
- (void)addSublayer:(CALayer *)l { [self insertSublayer:l atIndex:(unsigned)[_subs count]]; }
- (void)removeFromSuperlayer { CALayer *s = _superlayer; if (!s) return; _superlayer = nil; [s->_subs removeObjectIdenticalTo:self]; }
- (void)setNeedsDisplay { }
- (void)setNeedsLayout { }
- (void)layoutIfNeeded { }
- (void)displayIfNeeded { }
- (void)removeAllAnimations { }
@end
@implementation CATransaction
+ (void)begin { } + (void)commit { } + (void)flush { }
+ (void)setDisableActions:(BOOL)b { } + (void)setAnimationDuration:(CFTimeInterval)d { }
@end
NSString *const kCAGravityResize = @"resize", *const kCAGravityResizeAspect = @"resizeAspect", *const kCAGravityResizeAspectFill = @"resizeAspectFill", *const kCAGravityCenter = @"center";
uint64_t mach_absolute_time(void);
CFTimeInterval CACurrentMediaTime(void) { return mach_absolute_time() * 1e-9; } /* scion's mach time is in ns */

@interface _MWDrawable : _MWObject <CAMetalDrawable> { @public _MWTexture *_texture; CAMetalLayer *_layer; NSUInteger _id; BOOL _queued; } @end
@implementation _MWDrawable
- (void)dealloc { [_texture release]; [_layer release]; [super dealloc]; }
- (id<MTLTexture>)texture { return _texture; }
- (id)layer { return _layer; }
- (NSUInteger)drawableID { return _id; }
- (CFTimeInterval)presentedTime { return 0; }
- (void)present { if (!_queued) mw(MW_DRAWABLE_PRESENT, _h, 0, 0, 0, 0); } /* _queued: a Metal 4 queue already presents it (signalDrawable:) */
- (void)presentAtTime:(CFTimeInterval)t { [self present]; }
- (void)presentAfterMinimumDuration:(CFTimeInterval)t { [self present]; }
- (void)addPresentedHandler:(MTLDrawablePresentedHandler)b { } /* ponytail: not called; add when an app waits on it */
@end

@implementation CAMetalLayer {
    uint64_t _win, _host; NSUInteger _frames; CGSize _requested;
    /* AppKit views drawn over the Metal image (BGRA premultiplied, window pixels), blended in at each present */
    NSData *_ovPixels; NSUInteger _ovW, _ovH; BOOL _ovDirty; double _ovChanged, _lastPresent;
    id<MTLTexture> _ovTex; id<MTLRenderPipelineState> _ovPSO; MTLPixelFormat _ovFmt; id<MTLSamplerState> _ovSampler; id<MTLCommandQueue> _ovQueue;
    NSUInteger _ovDraws;
    id<MTLResidencySet> _residency;
}
- (NSUInteger)_mwOverlayDraws { return _ovDraws; } /* tests */
- (instancetype)init {
    if ((self = [super init])) { _pixelFormat = MTLPixelFormatBGRA8Unorm; _framebufferOnly = YES; _maximumDrawableCount = 3; _displaySyncEnabled = YES; _allowsNextDrawableTimeout = YES; }
    return self;
}
- (void)dealloc {
    if (_win) mw(MW_RELEASE, _win, 0, 0, 0, 0);
    [_ovPixels release]; [_ovTex release]; [_ovPSO release]; [_ovSampler release]; [_ovQueue release]; [_residency release];
    [_device release]; [super dealloc];
}
- (id<MTLResidencySet>)residencySet {
    @synchronized(self) {
        if (!_residency) _residency = [(_device ? _device : g_dev) newResidencySetWithDescriptor:[[MTLResidencySetDescriptor new] autorelease] error:NULL];
        return _residency;
    }
}
- (id<MTLDevice>)preferredDevice { return g_dev; }
- (void)_mwSetOverlay:(const void *)px width:(NSUInteger)w height:(NSUInteger)h {
    @synchronized(self) {
        if (!px && !_ovPixels) return;
        [_ovPixels release];
        _ovPixels = px ? [[NSData alloc] initWithBytes:px length:w * h * 4] : nil;
        _ovW = w; _ovH = h; _ovDirty = YES; _ovChanged = CACurrentMediaTime();
    }
    /* an app that is not drawing (a loading screen over a paused game) still shows its views, on black: from the main thread,
     * only when nothing acquired or presented a drawable for a while */
    [self retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self _mwPresentIdle]; [self release]; });
}
- (void)_mwPresentIdle {
    @synchronized(self) {
        double now = CACurrentMediaTime();
        if (!_host || _host == ~0ull || _lastPresent >= _ovChanged || now - _lastPresent < 0.25) return;
    }
    @autoreleasepool {
        id<CAMetalDrawable> d;
        @synchronized(self) { d = [self _mwNextDrawable]; }
        if (!d) return;
        if (!_ovQueue) _ovQueue = [d.texture.device newCommandQueue];
        id<MTLCommandBuffer> cb = [_ovQueue commandBuffer];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = d.texture; rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore; rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
        [cb presentDrawable:d];
        [cb commit];
    }
}
static NSString *const g_ov_msl = @"#include <metal_stdlib>\nusing namespace metal;\n"
    "struct V { float4 pos [[position]]; float2 uv; };\n"
    "vertex V mw_ov_vs(uint id [[vertex_id]]) { float2 p = float2((id << 1) & 2, id & 2); V o; o.pos = float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1); o.uv = p; return o; }\n"
    "fragment float4 mw_ov_fs(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) { return t.sample(s, in.uv); }\n";
/* blends the overlay over the drawable in cb, before it is presented (premultiplied alpha, stretched to the drawable) */
- (void)_mwComposite:(id<MTLCommandBuffer>)cb texture:(id<MTLTexture>)target {
    static int broken;
    NSData *px; NSUInteger w, h; BOOL dirty;
    @synchronized(self) {
        _lastPresent = CACurrentMediaTime();
        if (!_ovPixels || broken) return;
        px = [[_ovPixels retain] autorelease]; w = _ovW; h = _ovH; dirty = _ovDirty; _ovDirty = NO;
    }
    id<MTLDevice> dev = target.device;
    MTLPixelFormat tf = target.pixelFormat;
    BOOL srgb = tf == MTLPixelFormatBGRA8Unorm_sRGB || tf == MTLPixelFormatRGBA8Unorm_sRGB;
    MTLPixelFormat of = srgb ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm;
    if (!_ovTex || _ovTex.width != w || _ovTex.height != h || _ovTex.pixelFormat != of) {
        [_ovTex release];
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:of width:w height:h mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead;
        _ovTex = [dev newTextureWithDescriptor:td];
        dirty = YES;
    }
    if (dirty) [_ovTex replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:px.bytes bytesPerRow:w * 4];
    if (!_ovPSO || _ovFmt != tf) {
        static id<MTLLibrary> lib;
        NSError *err = nil;
        if (!lib) lib = [dev newLibraryWithSource:g_ov_msl options:nil error:&err];
        MTLRenderPipelineDescriptor *pd = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
        pd.vertexFunction = [[lib newFunctionWithName:@"mw_ov_vs"] autorelease]; pd.fragmentFunction = [[lib newFunctionWithName:@"mw_ov_fs"] autorelease];
        MTLRenderPipelineColorAttachmentDescriptor *ca = pd.colorAttachments[0];
        ca.pixelFormat = tf; ca.blendingEnabled = YES;
        ca.sourceRGBBlendFactor = ca.sourceAlphaBlendFactor = MTLBlendFactorOne;
        ca.destinationRGBBlendFactor = ca.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        [_ovPSO release];
        _ovPSO = lib ? [dev newRenderPipelineStateWithDescriptor:pd error:&err] : nil;
        _ovFmt = tf;
        if (!_ovPSO) { broken = 1; NSLog(@"scion: the AppKit overlay cannot be drawn over Metal (%@)", err); return; }
        MTLSamplerDescriptor *sd = [[[MTLSamplerDescriptor alloc] init] autorelease];
        sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
        sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
        [_ovSampler release]; _ovSampler = [dev newSamplerStateWithDescriptor:sd];
    }
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = target; rp.colorAttachments[0].loadAction = MTLLoadActionLoad; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
    [e setRenderPipelineState:_ovPSO];
    [e setFragmentTexture:_ovTex atIndex:0];
    [e setFragmentSamplerState:_ovSampler atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [e endEncoding];
    _ovDraws++;
}
/* AppKit: the layer belongs to a view in this host window (HWND); 0 = a window of its own; ~0 = detached (its window
 * is closing: no more drawables). The swapchain goes before the window does. */
- (void)_mwSetHostWindow:(uint64_t)hwnd {
    @synchronized(self) {
        if (hwnd == _host) return;
        _host = hwnd;
        if (_win) { mw(MW_RELEASE, _win, 0, 0, 0, 0); _win = 0; }
    }
}
- (void)setPixelFormat:(MTLPixelFormat)f {
    _pixelFormat = f;
    if (_win) mw(MW_LAYER_SET_FORMAT, _win, f, 0, 0, 0);
}
/* the window's size wins over a drawableSize the app keeps repeating: only a new request resizes the window */
- (void)setDrawableSize:(CGSize)s {
    if (s.width < 1 || s.height < 1) return;
    if (_win && (s.width != _requested.width || s.height != _requested.height)) mw(MW_LAYER_SET_SIZE, _win, (uint64_t)s.width, (uint64_t)s.height, 0, 0);
    _requested = s;
    if (!_win) _drawableSize = s;
}
- (id<CAMetalDrawable>)nextDrawable { @synchronized(self) { _lastPresent = CACurrentMediaTime(); return [self _mwNextDrawable]; } } /* the app is drawing */
- (id<CAMetalDrawable>)_mwNextDrawable {
    if (_host == ~0ull) return nil;
    if (!_device) _device = MTLCreateSystemDefaultDevice();
    if (!_win) {
        CGSize s = _drawableSize;
        if (s.width < 1 || s.height < 1) s = CGSizeMake(self.bounds.size.width * self.contentsScale, self.bounds.size.height * self.contentsScale);
        if (s.width < 1 || s.height < 1) s = CGSizeMake(800, 600);
        _win = (uint64_t)mw(MW_NEW_LAYER, (uint64_t)s.width, (uint64_t)s.height, U([[NSProcessInfo processInfo].processName UTF8String]), _pixelFormat, _host);
        if (!_win) return nil;
        _drawableSize = _requested = s;
    }
    if (!_host && mw(MW_LAYER_POLL, _win, 0, 0, 0, 0)) exit(0); /* window closed by the user: the app quits */
    uint64_t out[4] = {0}, h = (uint64_t)mw(MW_LAYER_NEXT_DRAWABLE, _win, U(out), 0, 0, 0);
    if (!h) return nil;
    _drawableSize = CGSizeMake(out[1], out[2]); /* follows the window, like a layer that autoresizes with its view */
    _pixelFormat = (MTLPixelFormat)out[3];
    _MWDrawable *d = mw_wrap([_MWDrawable class], h, _device);
    _MWTexture *t = mw_wrap([_MWTexture class], out[0], _device);
    MwTextureDesc td = {MTLTextureType2D, _pixelFormat, out[1], out[2], 1, 1, 1, 1, MTLResourceStorageModePrivate, MTLTextureUsageRenderTarget};
    t->_d = td; t->_framebufferOnly = _framebufferOnly;
    d->_texture = t; d->_layer = [self retain]; d->_id = _frames++;
    return [d autorelease];
}
@end

/* CAMetalDisplayLink: a timer on the run loop it is added to, at the preferred frame rate (60 Hz when unset), hands the
 * delegate the layer's next drawable. ponytail: not synchronised with the display's refresh */
#import <QuartzCore/CAMetalDisplayLink.h>
const CAFrameRateRange CAFrameRateRangeDefault = {0, 0, 0};
@interface CAMetalDisplayLinkUpdate () { @public id<CAMetalDrawable> _drawable; CFTimeInterval _t; } @end
@implementation CAMetalDisplayLinkUpdate
- (void)dealloc { [_drawable release]; [super dealloc]; }
- (id<CAMetalDrawable>)drawable { return _drawable; }
- (CFTimeInterval)targetTimestamp { return _t; }
- (CFTimeInterval)targetPresentationTimestamp { return _t; }
@end
@implementation CAMetalDisplayLink { CAMetalLayer *_layer; NSTimer *_timer; id _delegate; }
@synthesize preferredFrameRateRange = _range, preferredFrameLatency = _latency, paused = _paused;
- (instancetype)initWithMetalLayer:(CAMetalLayer *)layer { if ((self = [super init])) { _layer = [layer retain]; _latency = 2; } return self; }
- (void)dealloc { [_timer invalidate]; [_timer release]; [_layer release]; [super dealloc]; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; } /* weak */
- (void)_mwTick:(NSTimer *)t {
    if (_paused || !_delegate) return;
    id<CAMetalDrawable> d = [_layer nextDrawable];
    if (!d) return;
    CAMetalDisplayLinkUpdate *u = [[CAMetalDisplayLinkUpdate alloc] init];
    u->_drawable = [d retain]; u->_t = CACurrentMediaTime() + 1.0 / [self _mwRate];
    [_delegate metalDisplayLink:self needsUpdate:u];
    [u release];
}
- (double)_mwRate { float r = _range.preferred > 0 ? _range.preferred : _range.maximum > 0 ? _range.maximum : 60; return r < 1 ? 60 : r; }
- (void)addToRunLoop:(NSRunLoop *)rl forMode:(NSRunLoopMode)mode {
    if (_timer) return;
    _timer = [[NSTimer timerWithTimeInterval:1.0 / [self _mwRate] target:self selector:@selector(_mwTick:) userInfo:nil repeats:YES] retain];
    [rl addTimer:_timer forMode:mode];
}
- (void)removeFromRunLoop:(NSRunLoop *)rl forMode:(NSRunLoopMode)mode { [self invalidate]; }
- (void)invalidate { [_timer invalidate]; [_timer release]; _timer = nil; }
@end
static void mw_overlay_composite(id<MTLCommandBuffer> cb, id<MTLDrawable> d) {
    if (![(id)d isKindOfClass:[_MWDrawable class]]) return;
    _MWDrawable *x = (_MWDrawable *)d;
    [x->_layer _mwComposite:cb texture:x->_texture];
}

/* ====================================================================== Metal 3 extras that need no GPU work here */
/* residency: every allocation is always resident; the sets only keep their members */
@implementation MTLResidencySetDescriptor
- (id)copyWithZone:(NSZone *)z { MTLResidencySetDescriptor *d = [[MTLResidencySetDescriptor alloc] init]; d.label = self.label; d.initialCapacity = self.initialCapacity; return d; }
- (void)dealloc { [_label release]; [super dealloc]; }
@end
@interface _MWResidencySet : NSObject <MTLResidencySet> { @public id<MTLDevice> _dev; NSString *_name; NSMutableSet *_all; } @end
@implementation _MWResidencySet
- (void)dealloc { [_dev release]; [_name release]; [_all release]; [super dealloc]; }
- (id<MTLDevice>)device { return _dev; }
- (NSString *)label { return _name; }
- (uint64_t)allocatedSize { uint64_t n = 0; for (id<MTLAllocation> a in _all) n += a.allocatedSize; return n; }
- (NSUInteger)allocationCount { return [_all count]; }
- (NSArray *)allAllocations { return [_all allObjects]; }
- (void)requestResidency { } - (void)endResidency { } - (void)commit { }
- (void)addAllocation:(id<MTLAllocation>)a { if (a) [_all addObject:a]; }
- (void)addAllocations:(const id<MTLAllocation> *)a count:(NSUInteger)n { for (NSUInteger i = 0; i < n; i++) [self addAllocation:a[i]]; }
- (void)removeAllocation:(id<MTLAllocation>)a { if (a) [_all removeObject:a]; }
- (void)removeAllocations:(const id<MTLAllocation> *)a count:(NSUInteger)n { for (NSUInteger i = 0; i < n; i++) [self removeAllocation:a[i]]; }
- (void)removeAllAllocations { [_all removeAllObjects]; }
- (BOOL)containsAllocation:(id<MTLAllocation>)a { return [_all containsObject:a]; }
@end
@implementation _MWDevice (MWMetal3)
- (id<MTLResidencySet>)newResidencySetWithDescriptor:(MTLResidencySetDescriptor *)d error:(NSError **)e {
    _MWResidencySet *r = [[_MWResidencySet alloc] init];
    r->_dev = [self retain]; r->_name = [d.label copy]; r->_all = [[NSMutableSet alloc] init];
    return r;
}
@end
@implementation _MWCommandQueue (MWMetal3)
- (void)addResidencySet:(id<MTLResidencySet>)r { } - (void)removeResidencySet:(id<MTLResidencySet>)r { }
- (void)addResidencySets:(const id<MTLResidencySet> *)r count:(NSUInteger)n { } - (void)removeResidencySets:(const id<MTLResidencySet> *)r count:(NSUInteger)n { }
@end
@implementation _MWCommandBuffer (MWMetal3)
- (void)useResidencySet:(id<MTLResidencySet>)r { } - (void)useResidencySets:(const id<MTLResidencySet> *)r count:(NSUInteger)n { }
@end
/* resources are always usable from argument buffers and Vulkan orders the encoders: these are hints */
@implementation _MWComputeEncoder (MWMetal3)
- (void)useResource:(id<MTLResource>)r usage:(MTLResourceUsage)u { }
- (void)useResources:(const id<MTLResource> *)r count:(NSUInteger)n usage:(MTLResourceUsage)u { }
- (void)useHeap:(id)h { }
- (void)memoryBarrierWithScope:(MTLBarrierScope)s { }
- (void)memoryBarrierWithResources:(const id<MTLResource> *)r count:(NSUInteger)n { }
@end
@implementation _MWRenderEncoder (MWMetal3)
- (void)useResource:(id<MTLResource>)r usage:(MTLResourceUsage)u { }
- (void)useResource:(id<MTLResource>)r usage:(MTLResourceUsage)u stages:(MTLRenderStages)st { }
- (void)useResources:(const id<MTLResource> *)r count:(NSUInteger)n usage:(MTLResourceUsage)u stages:(MTLRenderStages)st { }
- (void)useHeap:(id)h stages:(MTLRenderStages)st { }
/* a barrier between draws splits the Vulkan render pass (Indium barrier()) */
- (void)memoryBarrierWithScope:(MTLBarrierScope)s afterStages:(MTLRenderStages)a beforeStages:(MTLRenderStages)b { mw(MW_RE_SET_STATE, _h, 8, 0, 0, 0); }
- (void)memoryBarrierWithResources:(const id<MTLResource> *)r count:(NSUInteger)n afterStages:(MTLRenderStages)a beforeStages:(MTLRenderStages)b { mw(MW_RE_SET_STATE, _h, 8, 0, 0, 0); }
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)m offset:(NSUInteger)o { mw(MW_RE_SET_STATE, _h, 7, m, o, 0); }
@end

/* ====================================================================== Metal 4 (recorded onto the Metal 3 objects above) */
#include "Metal4.m"
