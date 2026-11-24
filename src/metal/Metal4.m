/* Metal4.m — Metal 4 (macOS 26) on top of the Metal 3 objects of Metal.m (#included at its end: one translation unit, MRC).
 * - A Metal 4 command buffer records onto a Metal 3 command buffer begun from a hidden device queue; committing it to a
 *   Metal 4 queue commits that one (the host submits in commit order).
 * - Argument tables hold GPU addresses and resource IDs; before each draw or dispatch the encoder binds what changed
 *   (an address maps back to its buffer with mw_buffer_at, a resource ID is the texture or sampler object).
 * - A Metal 4 compute encoder also does blits: it switches between a Metal 3 compute and blit encoder.
 * - Barriers and fences are no-ops, except between the draws of a render pass: the host orders every encoder and dispatch
 *   after the previous one (Indium fullBarrier).
 * - Residency sets: everything is always resident.
 * - Queue events: a signal is an empty command buffer whose completion sets the value; a wait holds back the next
 *   commits (on the queue's serial dispatch queue) until the value is reached, so the CPU never blocks in commit.
 * - Timestamps: written when the command buffer completes (mach_absolute_time, ns), in encoding order.
 * ponytail: heaps and buffer-backed textures make separate allocations (no aliasing); no indirect draws or dispatches;
 * no attribute strides; no occlusion queries. */

#include <mach/mach_time.h>
#include <math.h>

/* ---------------------------------------------------------------------- descriptors */
@implementation MTL4CompilerDescriptor
- (void)dealloc { [_label release]; [_pipelineDataSetSerializer release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { MTL4CompilerDescriptor *d = [[MTL4CompilerDescriptor alloc] init]; d.label = _label; d.pipelineDataSetSerializer = _pipelineDataSetSerializer; return d; }
@end
@interface _MW4Compiler : NSObject <MTL4Compiler> { @public id<MTLDevice> _dev; NSString *_label; } @end
@implementation _MW4Compiler
- (void)dealloc { [_dev release]; [_label release]; [super dealloc]; }
- (id<MTLDevice>)device { return _dev; }
- (NSString *)label { return _label; }
@end
@implementation MTL4ArgumentTableDescriptor
- (void)dealloc { [_label release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
    MTL4ArgumentTableDescriptor *d = [[MTL4ArgumentTableDescriptor alloc] init];
    d.maxBufferBindCount = _maxBufferBindCount; d.maxTextureBindCount = _maxTextureBindCount; d.maxSamplerStateBindCount = _maxSamplerStateBindCount;
    d.initializeBindings = _initializeBindings; d.supportAttributeStrides = _supportAttributeStrides; d.label = _label;
    return d;
}
@end
@implementation MTL4CommandAllocatorDescriptor
- (void)dealloc { [_label release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { MTL4CommandAllocatorDescriptor *d = [[MTL4CommandAllocatorDescriptor alloc] init]; d.label = _label; return d; }
@end
@implementation MTL4CommandQueueDescriptor
- (void)dealloc { [_label release]; if (_feedbackQueue) dispatch_release(_feedbackQueue); [super dealloc]; }
- (void)setFeedbackQueue:(dispatch_queue_t)q { if (q) dispatch_retain(q); if (_feedbackQueue) dispatch_release(_feedbackQueue); _feedbackQueue = q; }
- (id)copyWithZone:(NSZone *)z { MTL4CommandQueueDescriptor *d = [[MTL4CommandQueueDescriptor alloc] init]; d.label = _label; d.feedbackQueue = _feedbackQueue; return d; }
@end
@implementation MTL4CommandBufferOptions
- (void)dealloc { [_logState release]; [super dealloc]; }
@end
@implementation MTL4CounterHeapDescriptor
- (id)copyWithZone:(NSZone *)z { MTL4CounterHeapDescriptor *d = [[MTL4CounterHeapDescriptor alloc] init]; d.type = _type; d.count = _count; return d; }
@end
@implementation MTL4RenderPassDescriptor
- (id)copyWithZone:(NSZone *)z {
    MTL4RenderPassDescriptor *d = [super copyWithZone:z]; /* MTLRenderPassDescriptor copies into [self class] */
    d.visibilityResultType = self.visibilityResultType; d.defaultRasterSampleCount = self.defaultRasterSampleCount;
    d.tileWidth = self.tileWidth; d.tileHeight = self.tileHeight; d.supportColorAttachmentMapping = self.supportColorAttachmentMapping;
    return d;
}
@end
@interface MTL4CommitOptions () { @public NSMutableArray *_handlers; } @end
@implementation MTL4CommitOptions
- (void)dealloc { [_handlers release]; [super dealloc]; }
- (void)addFeedbackHandler:(MTL4CommitFeedbackHandler)b {
    if (!_handlers) _handlers = [[NSMutableArray alloc] init];
    [_handlers addObject:[[b copy] autorelease]];
}
@end
@implementation MTLHeapDescriptor
- (id)copyWithZone:(NSZone *)z {
    MTLHeapDescriptor *d = [[MTLHeapDescriptor alloc] init];
    d.size = _size; d.storageMode = _storageMode; d.cpuCacheMode = _cpuCacheMode; d.hazardTrackingMode = _hazardTrackingMode; d.type = _type;
    return d;
}
- (MTLResourceOptions)resourceOptions { return (MTLResourceOptions)(_cpuCacheMode | _storageMode << 4 | _hazardTrackingMode << 8); }
- (void)setResourceOptions:(MTLResourceOptions)o { _cpuCacheMode = (MTLCPUCacheMode)(o & 0xF); _storageMode = (MTLStorageMode)((o >> 4) & 0xF); _hazardTrackingMode = (MTLHazardTrackingMode)((o >> 8) & 3); }
@end

/* ---------------------------------------------------------------------- simple objects */
@interface _MW4Allocator : NSObject <MTL4CommandAllocator> { @public id<MTLDevice> _dev; NSString *_name; } @end
@implementation _MW4Allocator
- (void)dealloc { [_dev release]; [_name release]; [super dealloc]; }
- (id<MTLDevice>)device { return _dev; }
- (NSString *)label { return _name; }
- (uint64_t)allocatedSize { return 0; }
- (void)reset { }
@end

@interface _MW4Fence : NSObject <MTLFence> { @public id<MTLDevice> _dev; NSString *_label; } @end
@implementation _MW4Fence
@synthesize label = _label;
- (void)dealloc { [_dev release]; [_label release]; [super dealloc]; }
- (id<MTLDevice>)device { return _dev; }
@end

/* a shared event: the value, and the blocks waiting for it */
@interface _MW4Event : NSObject <MTLSharedEvent> { @public id<MTLDevice> _dev; NSString *_label; NSCondition *_cv; uint64_t _value; NSMutableArray *_notify; } @end
@interface _MWSharedEventListenerPending : NSObject { @public uint64_t at; MTLSharedEventNotificationBlock block; dispatch_queue_t q; } @end
@implementation _MWSharedEventListenerPending @end
@implementation _MW4Event
@synthesize label = _label;
- (instancetype)init { if ((self = [super init])) { _cv = [[NSCondition alloc] init]; _notify = [[NSMutableArray alloc] init]; } return self; }
- (void)dealloc { [_dev release]; [_label release]; [_cv release]; [_notify release]; [super dealloc]; }
- (id<MTLDevice>)device { return _dev; }
- (uint64_t)signaledValue { [_cv lock]; uint64_t v = _value; [_cv unlock]; return v; }
- (void)setSignaledValue:(uint64_t)v {
    NSMutableArray *due = [NSMutableArray array];
    [_cv lock];
    _value = v; [_cv broadcast];
    for (NSUInteger i = 0; i < [_notify count];) {
        _MWSharedEventListenerPending *p = _notify[i];
        if (p->at <= v) { [due addObject:p]; [_notify removeObjectAtIndex:i]; } else i++;
    }
    [_cv unlock];
    for (_MWSharedEventListenerPending *p in due) {
        MTLSharedEventNotificationBlock b = p->block; [self retain];
        dispatch_async(p->q, ^{ b(self, v); [b release]; [self release]; });
    }
}
- (BOOL)waitUntilSignaledValue:(uint64_t)v timeoutMS:(uint64_t)ms {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:ms / 1000.0];
    [_cv lock];
    while (_value < v) if (![_cv waitUntilDate:limit]) break;
    BOOL ok = _value >= v;
    [_cv unlock];
    return ok;
}
- (void)notifyListener:(MTLSharedEventListener *)l atValue:(uint64_t)v block:(MTLSharedEventNotificationBlock)b {
    _MWSharedEventListenerPending *p = [[[_MWSharedEventListenerPending alloc] init] autorelease];
    p->at = v; p->block = [b copy]; p->q = l ? l.dispatchQueue : dispatch_get_global_queue(0, 0);
    [_cv lock]; [_notify addObject:p]; [_cv unlock];
    [self setSignaledValue:[self signaledValue]]; /* already reached: run it now */
}
@end
@implementation MTLSharedEventListener { dispatch_queue_t _q; }
+ (MTLSharedEventListener *)sharedListener { static MTLSharedEventListener *l; if (!l) l = [[MTLSharedEventListener alloc] init]; return l; }
- (instancetype)init { return [self initWithDispatchQueue:dispatch_get_global_queue(0, 0)]; }
- (instancetype)initWithDispatchQueue:(dispatch_queue_t)q { if ((self = [super init])) { _q = q; dispatch_retain(q); } return self; }
- (void)dealloc { dispatch_release(_q); [super dealloc]; }
- (dispatch_queue_t)dispatchQueue { return _q; }
@end

/* ---------------------------------------------------------------------- heaps (separate allocations) */
@interface _MW4Heap : NSObject <MTLHeap> { @public _MWDevice *_dev; MTLHeapDescriptor *_d; NSString *_label; NSUInteger _used; } @end
@implementation _MW4Heap
@synthesize label = _label;
- (void)dealloc { [_dev release]; [_d release]; [_label release]; [super dealloc]; }
- (id<MTLDevice>)device { return _dev; }
- (MTLStorageMode)storageMode { return _d.storageMode; }
- (MTLCPUCacheMode)cpuCacheMode { return _d.cpuCacheMode; }
- (MTLHazardTrackingMode)hazardTrackingMode { return _d.hazardTrackingMode; }
- (MTLResourceOptions)resourceOptions { return _d.resourceOptions; }
- (NSUInteger)size { return _d.size; }
- (NSUInteger)usedSize { return _used; }
- (NSUInteger)currentAllocatedSize { return _d.size; }
- (MTLHeapType)type { return _d.type; }
- (NSUInteger)maxAvailableSizeWithAlignment:(NSUInteger)a { return _used < _d.size ? _d.size - _used : 0; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)s { return MTLPurgeableStateNonVolatile; }
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)n options:(MTLResourceOptions)o offset:(NSUInteger)off {
    _used += n;
    return [_dev newBufferWithLength:n options:o];
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)n options:(MTLResourceOptions)o { return [self newBufferWithLength:n options:o offset:_used]; }
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d offset:(NSUInteger)off {
    _MWTexture *t = (_MWTexture *)[_dev newTextureWithDescriptor:d];
    if (t) { t->_heap = [self retain]; t->_heapOffset = off; _used += t.allocatedSize; }
    return t;
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d { return [self newTextureWithDescriptor:d offset:_used]; }
@end
@implementation _MWBuffer (MW4)
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d offset:(NSUInteger)off bytesPerRow:(NSUInteger)bpr {
    _MWTexture *t = (_MWTexture *)[_device newTextureWithDescriptor:d];
    if (!t) return nil;
    t->_buffer = [self retain]; t->_bufOffset = off; t->_bufBpr = bpr;
    /* a snapshot of the buffer's current texels (ponytail: later writes to either are not seen by the other) */
    if (d.textureType == MTLTextureType2D && off + bpr * d.height <= _len)
        [t replaceRegion:MTLRegionMake2D(0, 0, d.width, d.height) mipmapLevel:0 withBytes:(char *)[self contents] + off bytesPerRow:bpr];
    return t;
}
- (id<MTLHeap>)heap { return nil; }
- (NSUInteger)heapOffset { return 0; }
- (BOOL)isAliasable { return NO; }
- (void)makeAliasable { }
@end

/* ---------------------------------------------------------------------- counter heaps */
@interface _MW4CounterHeap : NSObject <MTL4CounterHeap> { @public NSMutableData *_data; NSUInteger _count; NSString *_label; } @end
@implementation _MW4CounterHeap
@synthesize label = _label;
- (void)dealloc { [_data release]; [_label release]; [super dealloc]; }
- (NSUInteger)count { return _count; }
- (MTL4CounterHeapType)type { return MTL4CounterHeapTypeTimestamp; }
- (NSData *)resolveCounterRange:(NSRange)r {
    if (r.location + r.length > _count) return nil;
    @synchronized(self) { return [_data subdataWithRange:NSMakeRange(r.location * 8, r.length * 8)]; }
}
- (void)invalidateCounterRange:(NSRange)r {
    if (r.location + r.length > _count) return;
    @synchronized(self) { memset((char *)[_data mutableBytes] + r.location * 8, 0, r.length * 8); }
}
- (void)_mwWrite:(NSUInteger)i time:(uint64_t)t { if (i < _count) @synchronized(self) { ((uint64_t *)[_data mutableBytes])[i] = t; } }
@end

/* ---------------------------------------------------------------------- argument tables */
enum { MW4_MAX_BUF = 31, MW4_MAX_TEX = 128, MW4_MAX_SAMP = 16 };
@interface _MW4ArgumentTable : NSObject <MTL4ArgumentTable> {
@public id<MTLDevice> _dev; NSString *_label; uint64_t _version;
    MTLGPUAddress _addr[MW4_MAX_BUF]; uint64_t _tex[MW4_MAX_TEX], _samp[MW4_MAX_SAMP];
    NSUInteger _nbuf, _ntex, _nsamp; /* bound slots: highest index + 1 */
} @end
@implementation _MW4ArgumentTable
- (void)dealloc { [_dev release]; [_label release]; [super dealloc]; }
- (id<MTLDevice>)device { return _dev; }
- (NSString *)label { return _label; }
- (void)setAddress:(MTLGPUAddress)a atIndex:(NSUInteger)i { if (i < MW4_MAX_BUF) { _addr[i] = a; if (i >= _nbuf) _nbuf = i + 1; _version++; } }
- (void)setAddress:(MTLGPUAddress)a attributeStride:(NSUInteger)s atIndex:(NSUInteger)i { [self setAddress:a atIndex:i]; } /* ponytail: stride from the pipeline */
- (void)setResource:(MTLResourceID)r atBufferIndex:(NSUInteger)i { }
- (void)setTexture:(MTLResourceID)r atIndex:(NSUInteger)i { if (i < MW4_MAX_TEX) { _tex[i] = r._impl; if (i >= _ntex) _ntex = i + 1; _version++; } }
- (void)setSamplerState:(MTLResourceID)r atIndex:(NSUInteger)i { if (i < MW4_MAX_SAMP) { _samp[i] = r._impl; if (i >= _nsamp) _nsamp = i + 1; _version++; } }
@end
/* what an encoder last bound from a table, per stage, so unchanged slots are not bound again */
typedef struct { _MW4ArgumentTable *table; uint64_t version; MTLGPUAddress addr[MW4_MAX_BUF]; uint64_t tex[MW4_MAX_TEX], samp[MW4_MAX_SAMP]; } MW4Bound;
/* stage: 0 vertex, 1 fragment (render) or 0 (compute); set: the Metal 3 encoder */
static void mw4_bind(MW4Bound *b, _MW4ArgumentTable *t, id enc, int render, int stage) {
    if (!t || (b->table == t && b->version == t->_version)) return;
    b->table = t; b->version = t->_version;
    for (NSUInteger i = 0; i < t->_nbuf; i++) {
        if (!t->_addr[i] || t->_addr[i] == b->addr[i]) continue;
        NSUInteger off = 0; id<MTLBuffer> buf = mw_buffer_at(t->_addr[i], &off);
        if (!buf) continue;
        b->addr[i] = t->_addr[i];
        if (!render) [enc setBuffer:buf offset:off atIndex:i];
        else if (stage) [enc setFragmentBuffer:buf offset:off atIndex:i];
        else [enc setVertexBuffer:buf offset:off atIndex:i];
    }
    for (NSUInteger i = 0; i < t->_ntex; i++) {
        if (!t->_tex[i] || t->_tex[i] == b->tex[i]) continue;
        id<MTLTexture> x = mw_resource_for_id(t->_tex[i], NO); b->tex[i] = t->_tex[i];
        if (!render) [(id<MTLComputeCommandEncoder>)enc setTexture:x atIndex:i]; else if (stage) [enc setFragmentTexture:x atIndex:i]; else [enc setVertexTexture:x atIndex:i];
    }
    for (NSUInteger i = 0; i < t->_nsamp; i++) {
        if (!t->_samp[i] || t->_samp[i] == b->samp[i]) continue;
        id<MTLSamplerState> x = mw_resource_for_id(t->_samp[i], YES); b->samp[i] = t->_samp[i];
        if (!render) [(id<MTLComputeCommandEncoder>)enc setSamplerState:x atIndex:i]; else if (stage) [enc setFragmentSamplerState:x atIndex:i]; else [enc setVertexSamplerState:x atIndex:i];
    }
}

/* ---------------------------------------------------------------------- command buffers */
@interface _MW4CommandBuffer : NSObject <MTL4CommandBuffer> {
@public _MWDevice *_dev; NSString *_label; id<MTLCommandBuffer> _cb; id _enc; /* the open Metal 4 encoder */
    NSMutableArray *_stamps; /* {heap, index, GPU timestamp index} in encoding order, written on completion */
    int64_t _ts0; /* GPU timestamp at the start */
    NSMutableArray *_resolves; /* {heap, location, length, address} copied into a buffer on completion */
} @end
@interface _MW4Encoder : NSObject { @public _MW4CommandBuffer *_cb4; NSString *_label; }
@property(copy, atomic) NSString *label;
@end
@implementation _MW4Encoder
@synthesize label = _label;
- (void)dealloc { [_cb4 release]; [_label release]; [super dealloc]; }
- (id<MTL4CommandBuffer>)commandBuffer { return _cb4; }
- (void)barrierAfterQueueStages:(MTLStages)a beforeStages:(MTLStages)b visibilityOptions:(MTL4VisibilityOptions)o { }
- (void)barrierAfterStages:(MTLStages)a beforeQueueStages:(MTLStages)b visibilityOptions:(MTL4VisibilityOptions)o { }
- (void)barrierAfterEncoderStages:(MTLStages)a beforeEncoderStages:(MTLStages)b visibilityOptions:(MTL4VisibilityOptions)o { }
- (void)updateFence:(id<MTLFence>)f afterEncoderStages:(MTLStages)s { }
- (void)waitForFence:(id<MTLFence>)f beforeEncoderStages:(MTLStages)s { }
- (void)insertDebugSignpost:(NSString *)s { }
- (void)pushDebugGroup:(NSString *)s { }
- (void)popDebugGroup { }
- (void)_mwClose { }
- (void)endEncoding { [self _mwClose]; if (_cb4 && _cb4->_enc == self) _cb4->_enc = nil; }
- (void)_mwStamp:(id<MTL4CounterHeap>)h index:(NSUInteger)i { [_cb4 writeTimestampIntoHeap:h atIndex:i]; }
@end

@interface _MW4Compute : _MW4Encoder <MTL4ComputeCommandEncoder> {
@public id<MTLComputeCommandEncoder> _ce; id<MTLBlitCommandEncoder> _be; id<MTLComputePipelineState> _pso; _MW4ArgumentTable *_table; MW4Bound _bound;
} @end
@implementation _MW4Compute
- (void)dealloc { [_ce release]; [_be release]; [_pso release]; [_table release]; [super dealloc]; }
- (MTLStages)stages { return MTLStageDispatch | MTLStageBlit; }
- (void)_mwClose { [_ce endEncoding]; [_ce release]; _ce = nil; [_be endEncoding]; [_be release]; _be = nil; }
- (id<MTLComputeCommandEncoder>)ce {
    if (!_ce) {
        [_be endEncoding]; [_be release]; _be = nil;
        _ce = [[_cb4->_cb computeCommandEncoder] retain]; memset(&_bound, 0, sizeof _bound);
        if (_pso) [_ce setComputePipelineState:_pso];
    }
    mw4_bind(&_bound, _table, _ce, 0, 0);
    return _ce;
}
- (id<MTLBlitCommandEncoder>)be {
    if (!_be) { [_ce endEncoding]; [_ce release]; _ce = nil; _be = [[_cb4->_cb blitCommandEncoder] retain]; }
    return _be;
}
- (void)setComputePipelineState:(id<MTLComputePipelineState>)s { [s retain]; [_pso release]; _pso = s; [_ce setComputePipelineState:s]; }
- (void)setArgumentTable:(id<MTL4ArgumentTable>)t { [t retain]; [_table release]; _table = (_MW4ArgumentTable *)t; }
- (void)setThreadgroupMemoryLength:(NSUInteger)n atIndex:(NSUInteger)i { }
- (void)setImageblockWidth:(NSUInteger)w height:(NSUInteger)h { }
- (void)dispatchThreads:(MTLSize)g threadsPerThreadgroup:(MTLSize)t { [[self ce] dispatchThreads:g threadsPerThreadgroup:t]; }
- (void)dispatchThreadgroups:(MTLSize)g threadsPerThreadgroup:(MTLSize)t { [[self ce] dispatchThreadgroups:g threadsPerThreadgroup:t]; }
- (void)dispatchThreadgroupsWithIndirectBuffer:(MTLGPUAddress)a threadsPerThreadgroup:(MTLSize)t {
    NSUInteger off = 0; id<MTLBuffer> b = mw_buffer_at(a, &off);
    if (b) [(_MWComputeEncoder *)[self ce] dispatchThreadgroupsWithIndirectBuffer:b indirectBufferOffset:off threadsPerThreadgroup:t];
    else fprintf(stderr, "scion: Metal 4 indirect buffer address %llx is not a buffer\n", (unsigned long long)a);
}
- (void)dispatchThreadsWithIndirectBuffer:(MTLGPUAddress)a { fprintf(stderr, "scion: Metal 4 dispatchThreadsWithIndirectBuffer not supported\n"); } /* ponytail: needs the grid turned into threadgroups on the GPU */
- (void)copyFromBuffer:(id<MTLBuffer>)s sourceOffset:(NSUInteger)so toBuffer:(id<MTLBuffer>)d destinationOffset:(NSUInteger)doff size:(NSUInteger)n {
    [[self be] copyFromBuffer:s sourceOffset:so toBuffer:d destinationOffset:doff size:n];
}
- (void)copyFromBuffer:(id<MTLBuffer>)s sourceOffset:(NSUInteger)so sourceBytesPerRow:(NSUInteger)bpr sourceBytesPerImage:(NSUInteger)bpi sourceSize:(MTLSize)z
             toTexture:(id<MTLTexture>)d destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)o {
    [[self be] copyFromBuffer:s sourceOffset:so sourceBytesPerRow:bpr sourceBytesPerImage:bpi sourceSize:z toTexture:d destinationSlice:ds destinationLevel:dl destinationOrigin:o];
}
- (void)copyFromBuffer:(id<MTLBuffer>)s sourceOffset:(NSUInteger)so sourceBytesPerRow:(NSUInteger)bpr sourceBytesPerImage:(NSUInteger)bpi sourceSize:(MTLSize)z
             toTexture:(id<MTLTexture>)d destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)o options:(MTLBlitOption)opt {
    [[self be] copyFromBuffer:s sourceOffset:so sourceBytesPerRow:bpr sourceBytesPerImage:bpi sourceSize:z toTexture:d destinationSlice:ds destinationLevel:dl destinationOrigin:o options:opt];
}
- (void)copyFromTexture:(id<MTLTexture>)s sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)z
               toBuffer:(id<MTLBuffer>)d destinationOffset:(NSUInteger)doff destinationBytesPerRow:(NSUInteger)bpr destinationBytesPerImage:(NSUInteger)bpi {
    [[self be] copyFromTexture:s sourceSlice:ss sourceLevel:sl sourceOrigin:so sourceSize:z toBuffer:d destinationOffset:doff destinationBytesPerRow:bpr destinationBytesPerImage:bpi];
}
- (void)copyFromTexture:(id<MTLTexture>)s sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)z
               toBuffer:(id<MTLBuffer>)d destinationOffset:(NSUInteger)doff destinationBytesPerRow:(NSUInteger)bpr destinationBytesPerImage:(NSUInteger)bpi options:(MTLBlitOption)o {
    [[self be] copyFromTexture:s sourceSlice:ss sourceLevel:sl sourceOrigin:so sourceSize:z toBuffer:d destinationOffset:doff destinationBytesPerRow:bpr destinationBytesPerImage:bpi options:o];
}
- (void)copyFromTexture:(id<MTLTexture>)s sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)z
              toTexture:(id<MTLTexture>)d destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)o {
    [[self be] copyFromTexture:s sourceSlice:ss sourceLevel:sl sourceOrigin:so sourceSize:z toTexture:d destinationSlice:ds destinationLevel:dl destinationOrigin:o];
}
- (void)copyFromTexture:(id<MTLTexture>)s sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl toTexture:(id<MTLTexture>)d
       destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl sliceCount:(NSUInteger)sc levelCount:(NSUInteger)lc {
    for (NSUInteger l = 0; l < lc; l++) for (NSUInteger k = 0; k < sc; k++) {
        MTLSize z = MTLSizeMake(MAX(1, s.width >> (sl + l)), MAX(1, s.height >> (sl + l)), s.textureType == MTLTextureType3D ? MAX(1, s.depth >> (sl + l)) : 1);
        [[self be] copyFromTexture:s sourceSlice:ss + k sourceLevel:sl + l sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:z
                         toTexture:d destinationSlice:ds + k destinationLevel:dl + l destinationOrigin:MTLOriginMake(0, 0, 0)];
    }
}
- (void)copyFromTexture:(id<MTLTexture>)s toTexture:(id<MTLTexture>)d { [[self be] copyFromTexture:s toTexture:d]; }
- (void)fillBuffer:(id<MTLBuffer>)b range:(NSRange)r value:(uint8_t)v { [[self be] fillBuffer:b range:r value:v]; }
- (void)generateMipmapsForTexture:(id<MTLTexture>)t { [[self be] generateMipmapsForTexture:t]; }
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)t { }
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)t { }
- (void)writeTimestampWithGranularity:(MTL4TimestampGranularity)g intoHeap:(id<MTL4CounterHeap>)h atIndex:(NSUInteger)i { [self _mwStamp:h index:i]; }
@end

@interface _MW4Render : _MW4Encoder <MTL4RenderCommandEncoder> {
@public id<MTLRenderCommandEncoder> _re; _MW4ArgumentTable *_tables[2]; MW4Bound _bound[2]; NSUInteger _tw, _th;
} @end
@implementation _MW4Render
- (void)dealloc { [_re release]; [_tables[0] release]; [_tables[1] release]; [super dealloc]; }
- (void)_mwClose { [_re endEncoding]; [_re release]; _re = nil; }
- (NSUInteger)tileWidth { return _tw; }
- (NSUInteger)tileHeight { return _th; }
- (id<MTLRenderCommandEncoder>)re { mw4_bind(&_bound[0], _tables[0], _re, 1, 0); mw4_bind(&_bound[1], _tables[1], _re, 1, 1); return _re; }
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)s { [_re setRenderPipelineState:s]; }
- (void)setArgumentTable:(id<MTL4ArgumentTable>)t atStages:(MTLRenderStages)st {
    for (int k = 0; k < 2; k++) if (st & (k ? MTLRenderStageFragment : MTLRenderStageVertex)) { [t retain]; [_tables[k] release]; _tables[k] = (_MW4ArgumentTable *)t; }
}
- (void)setViewport:(MTLViewport)v { [_re setViewport:v]; }
- (void)setViewports:(const MTLViewport *)v count:(NSUInteger)n { [_re setViewports:v count:n]; }
- (void)setScissorRect:(MTLScissorRect)r { [_re setScissorRect:r]; }
- (void)setScissorRects:(const MTLScissorRect *)r count:(NSUInteger)n { [_re setScissorRects:r count:n]; }
- (void)setCullMode:(MTLCullMode)c { [_re setCullMode:c]; }
- (void)setFrontFacingWinding:(MTLWinding)w { [_re setFrontFacingWinding:w]; }
- (void)setTriangleFillMode:(MTLTriangleFillMode)m { [_re setTriangleFillMode:m]; }
- (void)setDepthClipMode:(MTLDepthClipMode)m { [_re setDepthClipMode:m]; }
- (void)setDepthBias:(float)b slopeScale:(float)s clamp:(float)c { [_re setDepthBias:b slopeScale:s clamp:c]; }
- (void)setDepthTestMinBound:(float)a maxBound:(float)b { }
- (void)setDepthStencilState:(id<MTLDepthStencilState>)s { [_re setDepthStencilState:s]; }
- (void)setStencilReferenceValue:(uint32_t)v { [_re setStencilReferenceValue:v]; }
- (void)setStencilFrontReferenceValue:(uint32_t)f backReferenceValue:(uint32_t)b { [_re setStencilFrontReferenceValue:f backReferenceValue:b]; }
- (void)setBlendColorRed:(float)r green:(float)g blue:(float)b alpha:(float)a { [_re setBlendColorRed:r green:g blue:b alpha:a]; }
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)m offset:(NSUInteger)o { [_re setVisibilityResultMode:m offset:o]; }
/* between draws of this pass (the host orders encoders already); ponytail: every one splits the Vulkan pass, even with no draw before it */
- (void)barrierAfterEncoderStages:(MTLStages)a beforeEncoderStages:(MTLStages)b visibilityOptions:(MTL4VisibilityOptions)o {
    [_re memoryBarrierWithScope:MTLBarrierScopeBuffers afterStages:MTLRenderStageVertex beforeStages:MTLRenderStageVertex];
}
- (void)setColorStoreAction:(MTLStoreAction)a atIndex:(NSUInteger)i { }
- (void)setDepthStoreAction:(MTLStoreAction)a { }
- (void)setStencilStoreAction:(MTLStoreAction)a { }
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n { [[self re] drawPrimitives:t vertexStart:s vertexCount:n instanceCount:1 baseInstance:0]; }
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n instanceCount:(NSUInteger)ic {
    [[self re] drawPrimitives:t vertexStart:s vertexCount:n instanceCount:ic baseInstance:0];
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n instanceCount:(NSUInteger)ic baseInstance:(NSUInteger)bi {
    [[self re] drawPrimitives:t vertexStart:s vertexCount:n instanceCount:ic baseInstance:bi];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(MTLGPUAddress)ib indexBufferLength:(NSUInteger)len
                instanceCount:(NSUInteger)ic baseVertex:(NSInteger)bv baseInstance:(NSUInteger)bi {
    NSUInteger off = 0; id<MTLBuffer> b = mw_buffer_at(ib, &off);
    if (!b) { fprintf(stderr, "scion: Metal 4 index buffer address %llx is not a buffer\n", (unsigned long long)ib); return; }
    [[self re] drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:b indexBufferOffset:off instanceCount:ic baseVertex:bv baseInstance:bi];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(MTLGPUAddress)ib indexBufferLength:(NSUInteger)len {
    [self drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferLength:len instanceCount:1 baseVertex:0 baseInstance:0];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(MTLGPUAddress)ib indexBufferLength:(NSUInteger)len instanceCount:(NSUInteger)ic {
    [self drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferLength:len instanceCount:ic baseVertex:0 baseInstance:0];
}
- (void)drawPrimitives:(MTLPrimitiveType)t indirectBuffer:(MTLGPUAddress)a {
    NSUInteger off = 0; id<MTLBuffer> b = mw_buffer_at(a, &off);
    if (b) [(_MWRenderEncoder *)[self re] drawPrimitives:t indirectBuffer:b indirectBufferOffset:off];
    else fprintf(stderr, "scion: Metal 4 indirect buffer address %llx is not a buffer\n", (unsigned long long)a);
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexType:(MTLIndexType)it indexBuffer:(MTLGPUAddress)ib indexBufferLength:(NSUInteger)len indirectBuffer:(MTLGPUAddress)a {
    NSUInteger ioff = 0, off = 0; id<MTLBuffer> ibuf = mw_buffer_at(ib, &ioff), b = mw_buffer_at(a, &off);
    if (b && ibuf) [(_MWRenderEncoder *)[self re] drawIndexedPrimitives:t indexType:it indexBuffer:ibuf indexBufferOffset:ioff indirectBuffer:b indirectBufferOffset:off];
    else fprintf(stderr, "scion: Metal 4 indirect draw with addresses that are not buffers\n");
}
- (void)writeTimestampWithGranularity:(MTL4TimestampGranularity)g afterStage:(MTLRenderStages)s intoHeap:(id<MTL4CounterHeap>)h atIndex:(NSUInteger)i { [self _mwStamp:h index:i]; }
@end

static id<MTLCommandQueue> mw4_hidden_queue(_MWDevice *d) {
    static id<MTLCommandQueue> q;
    @synchronized([_MW4CommandBuffer class]) { if (!q) q = [d newCommandQueue]; }
    return q;
}
@implementation _MW4CommandBuffer
@synthesize label = _label;
- (void)dealloc { [_dev release]; [_label release]; [_cb release]; [_stamps release]; [_resolves release]; [super dealloc]; }
- (id<MTLDevice>)device { return _dev; }
- (void)beginCommandBufferWithAllocator:(id<MTL4CommandAllocator>)a {
    [_cb release]; _cb = [[mw4_hidden_queue(_dev) commandBuffer] retain];
    _ts0 = mw(MW_CB_TIMESTAMP, ((_MWObject *)_cb)->_h, 0, 0, 0, 0);
    [_stamps release]; _stamps = [[NSMutableArray alloc] init];
    [_resolves release]; _resolves = [[NSMutableArray alloc] init];
}
- (void)beginCommandBufferWithAllocator:(id<MTL4CommandAllocator>)a options:(MTL4CommandBufferOptions *)o { [self beginCommandBufferWithAllocator:a]; }
- (void)_mwCloseEncoder { if (_enc) { [_enc endEncoding]; _enc = nil; } }
/* the Metal 3 command buffer this one records onto, with no encoder open (MetalFX's Metal 4 scalers encode there) */
- (id<MTLCommandBuffer>)_mwLegacyCommandBuffer { [self _mwCloseEncoder]; return _cb; }
- (void)endCommandBuffer { [self _mwCloseEncoder]; }
- (id<MTL4RenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTL4RenderPassDescriptor *)d options:(MTL4RenderEncoderOptions)opt {
    [self _mwCloseEncoder];
    MTLRenderPassDescriptor *p = d;
    if (opt & (MTL4RenderEncoderOptionResuming | MTL4RenderEncoderOptionSuspending)) {
        /* a pass split over encoders: the resumed part loads what the suspended part stored */
        p = [[d copy] autorelease];
        NSMutableArray *atts = [NSMutableArray arrayWithObjects:p.depthAttachment, p.stencilAttachment, nil];
        for (NSUInteger i = 0; i < 8; i++) { MTLRenderPassColorAttachmentDescriptor *c = p.colorAttachments[i]; if (c.texture) [atts addObject:c]; }
        for (MTLRenderPassAttachmentDescriptor *a in atts) {
            if (!a.texture) continue;
            if (opt & MTL4RenderEncoderOptionResuming) a.loadAction = MTLLoadActionLoad;
            if (opt & MTL4RenderEncoderOptionSuspending) a.storeAction = MTLStoreActionStore;
        }
    }
    _MW4Render *e = [[[_MW4Render alloc] init] autorelease];
    e->_cb4 = [self retain]; e->_re = [[_cb renderCommandEncoderWithDescriptor:p] retain];
    e->_tw = d.tileWidth ? d.tileWidth : 32; e->_th = d.tileHeight ? d.tileHeight : 32;
    if (!e->_re) return nil;
    _enc = e;
    return e;
}
- (id<MTL4RenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTL4RenderPassDescriptor *)d { return [self renderCommandEncoderWithDescriptor:d options:0]; }
- (id<MTL4ComputeCommandEncoder>)computeCommandEncoder {
    [self _mwCloseEncoder];
    _MW4Compute *e = [[[_MW4Compute alloc] init] autorelease];
    e->_cb4 = [self retain];
    _enc = e;
    return e;
}
- (void)useResidencySet:(id<MTLResidencySet>)r { }
- (void)useResidencySets:(const id<MTLResidencySet> *)r count:(NSUInteger)n { }
- (void)pushDebugGroup:(NSString *)s { }
- (void)popDebugGroup { }
- (void)writeTimestampIntoHeap:(id<MTL4CounterHeap>)h atIndex:(NSUInteger)i {
    [_stamps addObject:@[h, @(i), @(mw(MW_CB_TIMESTAMP, ((_MWObject *)_cb)->_h, 0, 0, 0, 0))]];
}
- (void)resolveCounterHeap:(id<MTL4CounterHeap>)h withRange:(NSRange)r intoBuffer:(MTL4BufferRange)b waitFence:(id<MTLFence>)w updateFence:(id<MTLFence>)u {
    [_resolves addObject:@[h, @(r.location), @(r.length), @(b.bufferAddress)]];
}
/* the Metal 3 command buffer to commit, with the timestamp and resolve work hung on its completion */
- (id<MTLCommandBuffer>)_mwTake {
    [self _mwCloseEncoder];
    id<MTLCommandBuffer> cb = [_cb autorelease]; _cb = nil;
    if (!cb) return nil;
    NSArray *stamps = [_stamps autorelease], *resolves = [_resolves autorelease]; _stamps = _resolves = nil;
    int64_t ts0 = _ts0, ts1 = mw(MW_CB_TIMESTAMP, ((_MWObject *)cb)->_h, 0, 0, 0, 0);
    /* GPU timestamps, moved onto mach time so that the last one is now */
    [cb addCompletedHandler:^(id<MTLCommandBuffer> done) {
            uint64_t ns[512], now = mach_absolute_time();
            int64_t n = mw(MW_CB_TIMESTAMPS, ((_MWObject *)done)->_h, U(ns), 512, 0, 0);
            int64_t off = ts1 >= 0 && ts1 < n ? (int64_t)now - (int64_t)ns[ts1] : 0;
            if (ts0 >= 0 && ts0 < n && ts1 >= 0 && ts1 < n) {
                ((_MWCommandBuffer *)done)->_gpu0 = (double)((int64_t)ns[ts0] + off) * 1e-9;
                ((_MWCommandBuffer *)done)->_gpu1 = (double)((int64_t)ns[ts1] + off) * 1e-9;
            }
            for (NSArray *s in stamps) {
                int64_t k = [s[2] longLongValue];
                [(_MW4CounterHeap *)s[0] _mwWrite:[s[1] unsignedIntegerValue] time:k >= 0 && k < n ? (uint64_t)((int64_t)ns[k] + off) : now];
            }
            for (NSArray *r in resolves) {
                NSUInteger off = 0; id<MTLBuffer> buf = mw_buffer_at([r[3] unsignedLongLongValue], &off);
                NSData *d = [(id<MTL4CounterHeap>)r[0] resolveCounterRange:NSMakeRange([r[1] unsignedIntegerValue], [r[2] unsignedIntegerValue])];
                if (buf && d && off + [d length] <= buf.length) memcpy((char *)buf.contents + off, [d bytes], [d length]);
            }
        }];
    return cb;
}
@end

/* ---------------------------------------------------------------------- queues */
@interface _MW4Feedback : NSObject <MTL4CommitFeedback> { @public CFTimeInterval _t0, _t1; NSError *_err; } @end
@implementation _MW4Feedback
- (void)dealloc { [_err release]; [super dealloc]; }
- (NSError *)error { return _err; }
- (CFTimeInterval)GPUStartTime { return _t0; }
- (CFTimeInterval)GPUEndTime { return _t1; }
@end
static CFTimeInterval mw4_now(void) { return mach_absolute_time() / 1e9; }

@interface _MW4Queue : NSObject <MTL4CommandQueue> {
@public _MWDevice *_dev; NSString *_label; dispatch_queue_t _feedback, _serial; NSMutableArray *_waits; /* {event, value} for the next commit */
    long _deferred; /* commits still queued on _serial */
} @end
@implementation _MW4Queue
- (void)dealloc { [_dev release]; [_label release]; if (_feedback) dispatch_release(_feedback); dispatch_release(_serial); [_waits release]; [super dealloc]; }
- (id<MTLDevice>)device { return _dev; }
- (NSString *)label { return _label; }
/* run `work` in queue order: now, or after the commits that wait for events */
- (void)_mwOrdered:(void (^)(void))work {
    NSArray *waits = nil;
    @synchronized(self) { if ([_waits count]) { waits = [[_waits copy] autorelease]; [_waits removeAllObjects]; } }
    if (!waits && !__atomic_load_n(&_deferred, __ATOMIC_ACQUIRE)) { work(); return; }
    __atomic_add_fetch(&_deferred, 1, __ATOMIC_ACQ_REL);
    [waits retain]; work = [work copy];
    dispatch_async(_serial, ^{
        for (NSArray *w in waits) [(id<MTLSharedEvent>)w[0] waitUntilSignaledValue:[w[1] unsignedLongLongValue] timeoutMS:UINT32_MAX];
        work(); [work release]; [waits release];
        __atomic_sub_fetch(&_deferred, 1, __ATOMIC_ACQ_REL);
    });
}
- (void)commit:(const id<MTL4CommandBuffer> *)cbs count:(NSUInteger)n options:(MTL4CommitOptions *)o {
    NSMutableArray *legacy = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++) { id<MTLCommandBuffer> cb = [(_MW4CommandBuffer *)cbs[i] _mwTake]; if (cb) [legacy addObject:cb]; }
    NSArray *handlers = o ? [[o->_handlers copy] autorelease] : nil;
    if ([handlers count]) {
        if (![legacy count]) [legacy addObject:[mw4_hidden_queue(_dev) commandBuffer]];
        __block CFTimeInterval t0 = mw4_now();
        dispatch_queue_t fq = _feedback ? _feedback : dispatch_get_global_queue(0, 0);
        dispatch_retain(fq);
        [[legacy lastObject] addCompletedHandler:^(id<MTLCommandBuffer> done) {
            _MW4Feedback *f = [[_MW4Feedback alloc] init]; f->_t0 = t0; f->_t1 = mw4_now();
            _MWCommandBuffer *d = (_MWCommandBuffer *)done;
            if (d->_gpu1 > 0) { f->_t0 = d->_gpu0; f->_t1 = d->_gpu1; } /* measured on the GPU */
            dispatch_async(fq, ^{ for (MTL4CommitFeedbackHandler h in handlers) h(f); [f release]; dispatch_release(fq); });
        }];
    }
    [self _mwOrdered:^{ for (id<MTLCommandBuffer> cb in legacy) [cb commit]; }];
}
- (void)commit:(const id<MTL4CommandBuffer> *)cbs count:(NSUInteger)n { [self commit:cbs count:n options:nil]; }
- (void)signalEvent:(id<MTLEvent>)e value:(uint64_t)v {
    id<MTLCommandBuffer> cb = [mw4_hidden_queue(_dev) commandBuffer];
    [e retain];
    [cb addCompletedHandler:^(id<MTLCommandBuffer> done) {
        if ([(id)e respondsToSelector:@selector(setSignaledValue:)]) [(id<MTLSharedEvent>)e setSignaledValue:v];
        [e release];
    }];
    [self _mwOrdered:^{ [cb commit]; }];
}
- (void)waitForEvent:(id<MTLEvent>)e value:(uint64_t)v {
    if (![(id)e respondsToSelector:@selector(waitUntilSignaledValue:timeoutMS:)] || [(id<MTLSharedEvent>)e signaledValue] >= v) return;
    @synchronized(self) { [_waits addObject:@[e, @(v)]]; }
}
- (void)signalDrawable:(id<MTLDrawable>)d {
    if ([(id)d isKindOfClass:[_MWDrawable class]]) ((_MWDrawable *)d)->_queued = YES;
    id<MTLCommandBuffer> cb = [mw4_hidden_queue(_dev) commandBuffer];
    [cb presentDrawable:d];
    [self _mwOrdered:^{ [cb commit]; }];
}
- (void)waitForDrawable:(id<MTLDrawable>)d { }
- (void)addResidencySet:(id<MTLResidencySet>)r { }
- (void)addResidencySets:(const id<MTLResidencySet> *)r count:(NSUInteger)n { }
- (void)removeResidencySet:(id<MTLResidencySet>)r { }
- (void)removeResidencySets:(const id<MTLResidencySet> *)r count:(NSUInteger)n { }
@end

/* ---------------------------------------------------------------------- device */
@implementation _MWDevice (MW4)
- (BOOL)supportsBCTextureCompression { return YES; }
- (NSUInteger)argumentBuffersSupport { return 1; } /* tier 2 */
- (id<MTL4CommandQueue>)newMTL4CommandQueueWithDescriptor:(MTL4CommandQueueDescriptor *)d error:(NSError **)e {
    _MW4Queue *q = [[_MW4Queue alloc] init];
    q->_dev = [self retain]; q->_label = [d.label copy]; q->_waits = [[NSMutableArray alloc] init];
    q->_serial = dispatch_queue_create("scion.mtl4queue", NULL);
    if (d.feedbackQueue) { q->_feedback = d.feedbackQueue; dispatch_retain(q->_feedback); }
    return q;
}
- (id<MTL4CommandQueue>)newMTL4CommandQueue { return [self newMTL4CommandQueueWithDescriptor:nil error:NULL]; }
- (id<MTL4CommandBuffer>)newCommandBuffer { _MW4CommandBuffer *c = [[_MW4CommandBuffer alloc] init]; c->_dev = [self retain]; return c; }
- (id<MTL4CommandAllocator>)newCommandAllocatorWithDescriptor:(MTL4CommandAllocatorDescriptor *)d error:(NSError **)e {
    _MW4Allocator *a = [[_MW4Allocator alloc] init]; a->_dev = [self retain]; a->_name = [d.label copy]; return a;
}
- (id<MTL4CommandAllocator>)newCommandAllocator { return [self newCommandAllocatorWithDescriptor:nil error:NULL]; }
- (id<MTL4ArgumentTable>)newArgumentTableWithDescriptor:(MTL4ArgumentTableDescriptor *)d error:(NSError **)e {
    if (d.maxBufferBindCount > MW4_MAX_BUF || d.maxTextureBindCount > MW4_MAX_TEX || d.maxSamplerStateBindCount > MW4_MAX_SAMP) {
        if (e) *e = mw_error(1, "argument table too large");
        return nil;
    }
    _MW4ArgumentTable *t = [[_MW4ArgumentTable alloc] init]; t->_dev = [self retain]; t->_label = [d.label copy];
    return t;
}
- (id<MTL4CounterHeap>)newCounterHeapWithDescriptor:(MTL4CounterHeapDescriptor *)d error:(NSError **)e {
    if (d.type != MTL4CounterHeapTypeTimestamp || !d.count) { if (e) *e = mw_error(1, "only timestamp counter heaps"); return nil; }
    _MW4CounterHeap *h = [[_MW4CounterHeap alloc] init]; h->_count = d.count; h->_data = [[NSMutableData alloc] initWithLength:d.count * 8];
    return h;
}
- (NSUInteger)sizeOfCounterHeapEntry:(MTL4CounterHeapType)t { return t == MTL4CounterHeapTypeTimestamp ? sizeof(MTL4TimestampHeapEntry) : 0; }
- (uint64_t)queryTimestampFrequency { return 1000000000ull; } /* mach_absolute_time: ns */
- (id<MTL4Compiler>)newCompilerWithDescriptor:(MTL4CompilerDescriptor *)d error:(NSError **)e {
    _MW4Compiler *c = [[_MW4Compiler alloc] init]; c->_dev = [self retain]; c->_label = [d.label copy]; return c;
}
/* buffer-backed textures copy the texels (newTextureWithDescriptor:offset:bytesPerRow:): any alignment of a texel works */
- (NSUInteger)minimumLinearTextureAlignmentForPixelFormat:(MTLPixelFormat)f { return 16; }
- (NSUInteger)minimumTextureBufferAlignmentForPixelFormat:(MTLPixelFormat)f { return 16; }
- (id<MTLHeap>)newHeapWithDescriptor:(MTLHeapDescriptor *)d {
    _MW4Heap *h = [[_MW4Heap alloc] init]; h->_dev = [self retain]; h->_d = [d copy];
    return h;
}
/* bytes per texel of a pixel format (block formats: per 4x4 block / 16); ponytail: the common formats, else 4 */
static double mw_format_bpp(MTLPixelFormat f) {
    if (f == 1 || (f >= 10 && f <= 14) || f == 253) return 1;
    if ((f >= 20 && f <= 25) || (f >= 30 && f <= 34) || (f >= 40 && f <= 43) || f == 250) return 2;
    if ((f >= 103 && f <= 105) || (f >= 110 && f <= 115) || f == 260) return 8;
    if (f >= 123 && f <= 125) return 16;
    if (f == 130 || f == 131 || f == 140 || f == 141) return 0.5;
    if (f >= 132 && f <= 153) return 1;
    return 4;
}
- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)d {
    double n = 0;
    for (NSUInteger l = 0; l < MAX(1, d.mipmapLevelCount); l++) n += (double)MAX(1, d.width >> l) * MAX(1, d.height >> l) * MAX(1, d.depth >> l);
    n *= mw_format_bpp(d.pixelFormat) * MAX(1, d.arrayLength) * MAX(1, d.sampleCount) * (d.textureType == MTLTextureTypeCube || d.textureType == MTLTextureTypeCubeArray ? 6 : 1);
    MTLSizeAndAlign r = {((NSUInteger)ceil(n) + 0xFFFF) & ~(NSUInteger)0xFFFF, 0x10000}; return r;
}
- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)n options:(MTLResourceOptions)o { MTLSizeAndAlign r = {(n + 255) & ~(NSUInteger)255, 256}; return r; }
- (id<MTLFence>)newFence { _MW4Fence *f = [[_MW4Fence alloc] init]; f->_dev = [self retain]; return f; }
- (id<MTLSharedEvent>)newSharedEvent { _MW4Event *e = [[_MW4Event alloc] init]; e->_dev = [self retain]; return e; }
- (id<MTLEvent>)newEvent { return [self newSharedEvent]; }
@end
