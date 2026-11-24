/* cg.m — CoreGraphics (geometry, CGColor, displays, cursor), CoreVideo (CVDisplayLink) and MetalKit (MTKView), all in
 * AppKit.dylib (dyld maps those frameworks onto it). */
#import "internal.h"
#import <MetalKit/MetalKit.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
uint64_t mach_absolute_time(void);

/* ======================================================================= geometry */
const CGRect CGRectZero = {{0, 0}, {0, 0}};
const CGRect CGRectNull = {{INFINITY, INFINITY}, {0, 0}};
const CGRect CGRectInfinite = {{-DBL_MAX / 2, -DBL_MAX / 2}, {DBL_MAX, DBL_MAX}};
const CGPoint CGPointZero = {0, 0};
const CGSize CGSizeZero = {0, 0};
const CGAffineTransform CGAffineTransformIdentity = {1, 0, 0, 1, 0, 0};
CGFloat CGRectGetMinX(CGRect r) { return CGRectStandardize(r).origin.x; }
CGFloat CGRectGetMinY(CGRect r) { return CGRectStandardize(r).origin.y; }
CGFloat CGRectGetMaxX(CGRect r) { r = CGRectStandardize(r); return r.origin.x + r.size.width; }
CGFloat CGRectGetMaxY(CGRect r) { r = CGRectStandardize(r); return r.origin.y + r.size.height; }
CGFloat CGRectGetMidX(CGRect r) { r = CGRectStandardize(r); return r.origin.x + r.size.width / 2; }
CGFloat CGRectGetMidY(CGRect r) { r = CGRectStandardize(r); return r.origin.y + r.size.height / 2; }
CGFloat CGRectGetWidth(CGRect r) { return fabs(r.size.width); }
CGFloat CGRectGetHeight(CGRect r) { return fabs(r.size.height); }
bool CGRectIsNull(CGRect r) { return isinf(r.origin.x) || isinf(r.origin.y); }
bool CGRectIsEmpty(CGRect r) { return CGRectIsNull(r) || r.size.width == 0 || r.size.height == 0; }
bool CGRectEqualToRect(CGRect a, CGRect b) {
    if (CGRectIsNull(a) || CGRectIsNull(b)) return CGRectIsNull(a) && CGRectIsNull(b);
    a = CGRectStandardize(a); b = CGRectStandardize(b);
    return a.origin.x == b.origin.x && a.origin.y == b.origin.y && a.size.width == b.size.width && a.size.height == b.size.height;
}
bool CGSizeEqualToSize(CGSize a, CGSize b) { return a.width == b.width && a.height == b.height; }
bool CGPointEqualToPoint(CGPoint a, CGPoint b) { return a.x == b.x && a.y == b.y; }
CGRect CGRectStandardize(CGRect r) {
    if (CGRectIsNull(r)) return r;
    if (r.size.width < 0) { r.origin.x += r.size.width; r.size.width = -r.size.width; }
    if (r.size.height < 0) { r.origin.y += r.size.height; r.size.height = -r.size.height; }
    return r;
}
bool CGRectContainsPoint(CGRect r, CGPoint p) {
    r = CGRectStandardize(r);
    return !CGRectIsNull(r) && p.x >= r.origin.x && p.y >= r.origin.y && p.x < r.origin.x + r.size.width && p.y < r.origin.y + r.size.height;
}
CGRect CGRectIntersection(CGRect a, CGRect b) {
    if (CGRectIsNull(a) || CGRectIsNull(b)) return CGRectNull;
    a = CGRectStandardize(a); b = CGRectStandardize(b);
    CGFloat x0 = fmax(a.origin.x, b.origin.x), y0 = fmax(a.origin.y, b.origin.y);
    CGFloat x1 = fmin(a.origin.x + a.size.width, b.origin.x + b.size.width), y1 = fmin(a.origin.y + a.size.height, b.origin.y + b.size.height);
    return x1 < x0 || y1 < y0 ? CGRectNull : CGRectMake(x0, y0, x1 - x0, y1 - y0);
}
bool CGRectIntersectsRect(CGRect a, CGRect b) { CGRect i = CGRectIntersection(a, b); return !CGRectIsNull(i) && i.size.width > 0 && i.size.height > 0; }
bool CGRectContainsRect(CGRect a, CGRect b) { return CGRectEqualToRect(CGRectUnion(a, b), CGRectStandardize(a)); }
CGRect CGRectUnion(CGRect a, CGRect b) {
    if (CGRectIsNull(a)) return CGRectStandardize(b);
    if (CGRectIsNull(b)) return CGRectStandardize(a);
    a = CGRectStandardize(a); b = CGRectStandardize(b);
    CGFloat x0 = fmin(a.origin.x, b.origin.x), y0 = fmin(a.origin.y, b.origin.y);
    return CGRectMake(x0, y0, fmax(a.origin.x + a.size.width, b.origin.x + b.size.width) - x0, fmax(a.origin.y + a.size.height, b.origin.y + b.size.height) - y0);
}
CGRect CGRectInset(CGRect r, CGFloat dx, CGFloat dy) {
    r = CGRectStandardize(r);
    r.origin.x += dx; r.origin.y += dy; r.size.width -= 2 * dx; r.size.height -= 2 * dy;
    return r.size.width < 0 || r.size.height < 0 ? CGRectNull : r;
}
CGRect CGRectOffset(CGRect r, CGFloat dx, CGFloat dy) { if (CGRectIsNull(r)) return r; r.origin.x += dx; r.origin.y += dy; return r; }
CGRect CGRectIntegral(CGRect r) {
    if (CGRectIsNull(r)) return r;
    r = CGRectStandardize(r);
    CGFloat x0 = floor(r.origin.x), y0 = floor(r.origin.y);
    return CGRectMake(x0, y0, ceil(r.origin.x + r.size.width) - x0, ceil(r.origin.y + r.size.height) - y0);
}
CGAffineTransform CGAffineTransformMake(CGFloat a, CGFloat b, CGFloat c, CGFloat d, CGFloat tx, CGFloat ty) { CGAffineTransform t = {a, b, c, d, tx, ty}; return t; }
CGAffineTransform CGAffineTransformMakeScale(CGFloat sx, CGFloat sy) { return CGAffineTransformMake(sx, 0, 0, sy, 0, 0); }
CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty) { return CGAffineTransformMake(1, 0, 0, 1, tx, ty); }
CGPoint CGPointApplyAffineTransform(CGPoint p, CGAffineTransform t) { return CGPointMake(t.a * p.x + t.c * p.y + t.tx, t.b * p.x + t.d * p.y + t.ty); }

/* ======================================================================= CGColor, CGColorSpace (Objective-C objects: CFRetain/CFRelease work) */
@interface _MWCGColor : NSObject { @public CGFloat _c[4]; size_t _n; } @end
@implementation _MWCGColor @end
@interface _MWCGColorSpace : NSObject { @public size_t _n; } @end
@implementation _MWCGColorSpace @end
static CGColorRef color(size_t n, CGFloat a, CGFloat b, CGFloat c, CGFloat d) {
    _MWCGColor *x = [[_MWCGColor alloc] init];
    x->_n = n; x->_c[0] = a; x->_c[1] = b; x->_c[2] = c; x->_c[3] = d;
    return (CGColorRef)x;
}
CGColorRef CGColorCreateGenericRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return color(4, r, g, b, a); }
CGColorRef CGColorCreateSRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return color(4, r, g, b, a); }
CGColorRef CGColorCreateGenericGray(CGFloat w, CGFloat a) { return color(2, w, a, 0, 0); }
CGColorRef CGColorCreate(CGColorSpaceRef s, const CGFloat *c) { return c ? color(4, c[0], c[1], c[2], c[3]) : NULL; }
const CFStringRef kCGColorBlack = (CFStringRef)@"kCGColorBlack", kCGColorWhite = (CFStringRef)@"kCGColorWhite", kCGColorClear = (CFStringRef)@"kCGColorClear";
const CFStringRef kCGColorSpaceGenericGray = (CFStringRef)@"kCGColorSpaceGenericGray", kCGColorSpaceLinearGray = (CFStringRef)@"kCGColorSpaceLinearGray";
const CFStringRef kCGColorSpaceSRGB = (CFStringRef)@"kCGColorSpaceSRGB", kCGColorSpaceGenericRGB = (CFStringRef)@"kCGColorSpaceGenericRGB",
    kCGColorSpaceDisplayP3 = (CFStringRef)@"kCGColorSpaceDisplayP3", kCGColorSpaceExtendedLinearSRGB = (CFStringRef)@"kCGColorSpaceExtendedLinearSRGB";
CGColorRef CGColorGetConstantColor(CFStringRef name) {
    static CGColorRef black, white, clear;
    if (!black) { black = color(2, 0, 1, 0, 0); white = color(2, 1, 1, 0, 0); clear = color(2, 0, 0, 0, 0); }
    NSString *n = (NSString *)name;
    return [n isEqualToString:@"kCGColorWhite"] ? white : [n isEqualToString:@"kCGColorClear"] ? clear : black;
}
CGColorRef CGColorRetain(CGColorRef c) { if (c) [(id)c retain]; return c; }
void CGColorRelease(CGColorRef c) { if (c) [(id)c release]; }
size_t CGColorGetNumberOfComponents(CGColorRef c) { return c ? ((_MWCGColor *)c)->_n : 0; }
const CGFloat *CGColorGetComponents(CGColorRef c) { return c ? ((_MWCGColor *)c)->_c : NULL; }
CGFloat CGColorGetAlpha(CGColorRef c) { if (!c) return 0; _MWCGColor *x = (_MWCGColor *)c; return x->_c[x->_n - 1]; }
CGColorRef CGColorCreateCopyWithAlpha(CGColorRef c, CGFloat a) {
    _MWCGColor *x = (_MWCGColor *)c;
    return x->_n == 2 ? color(2, x->_c[0], a, 0, 0) : color(4, x->_c[0], x->_c[1], x->_c[2], a);
}
static CGColorSpaceRef space(size_t n) { _MWCGColorSpace *s = [[_MWCGColorSpace alloc] init]; s->_n = n; return (CGColorSpaceRef)s; }
CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void) { return space(3); }
CGColorSpaceRef CGColorSpaceCreateDeviceGray(void) { return space(1); }
CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef n) { return space([(NSString *)n rangeOfString:@"Gray"].location != NSNotFound ? 1 : 3); }
size_t CGColorSpaceGetNumberOfComponents(CGColorSpaceRef s) { return s ? ((_MWCGColorSpace *)s)->_n : 0; }
CGColorSpaceRef CGColorSpaceRetain(CGColorSpaceRef s) { if (s) [(id)s retain]; return s; }
void CGColorSpaceRelease(CGColorSpaceRef s) { if (s) [(id)s release]; }

/* ======================================================================= displays, cursor */
CGDirectDisplayID CGMainDisplayID(void) { return 1; }
static CGError list_displays(uint32_t max, CGDirectDisplayID *d, uint32_t *count) {
    uint32_t n = (uint32_t)[[NSScreen screens] count];
    if (count) *count = d ? (n < max ? n : max) : n;
    for (uint32_t i = 0; d && i < n && i < max; i++) d[i] = i + 1;
    return kCGErrorSuccess;
}
CGError CGGetActiveDisplayList(uint32_t max, CGDirectDisplayID *d, uint32_t *count) { return list_displays(max, d, count); }
CGError CGGetOnlineDisplayList(uint32_t max, CGDirectDisplayID *d, uint32_t *count) { return list_displays(max, d, count); }
static NSScreen *screen(CGDirectDisplayID d) { NSArray *s = [NSScreen screens]; return d >= 1 && d <= [s count] ? s[d - 1] : [s firstObject]; }
CGRect CGDisplayBounds(CGDirectDisplayID d) { /* CoreGraphics: top-left origin */
    NSRect f = screen(d).frame;
    return CGRectMake(f.origin.x, mw_height0() - f.origin.y - f.size.height, f.size.width, f.size.height);
}
size_t CGDisplayPixelsWide(CGDirectDisplayID d) { NSScreen *s = screen(d); return (size_t)lround(s.frame.size.width * s.backingScaleFactor); }
size_t CGDisplayPixelsHigh(CGDirectDisplayID d) { NSScreen *s = screen(d); return (size_t)lround(s.frame.size.height * s.backingScaleFactor); }
CGError CGDisplayHideCursor(CGDirectDisplayID d) { [NSCursor hide]; return kCGErrorSuccess; }
CGError CGDisplayShowCursor(CGDirectDisplayID d) { [NSCursor unhide]; return kCGErrorSuccess; }
CGError CGWarpMouseCursorPosition(CGPoint p) {
    CGFloat s0 = mw_scale0();
    ui(UI_CURSOR, 2, (uint64_t)lround(p.x * s0), (uint64_t)lround(p.y * s0), 0, 0);
    return kCGErrorSuccess;
}
CGError CGAssociateMouseAndMouseCursorPosition(int connected) { ui(UI_CURSOR, 3, connected ? 1 : 0, 0, 0, 0); return kCGErrorSuccess; }
void CGGetLastMouseDelta(int32_t *dx, int32_t *dy) { mw_get_last_mouse_delta(dx, dy); }
@interface _MWDisplayMode : NSObject { @public double _hz; size_t _w, _h; } @end
@implementation _MWDisplayMode @end
CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID d) {
    NSScreen *s = screen(d);
    _MWDisplayMode *m = [[_MWDisplayMode alloc] init];
    m->_hz = (double)s.maximumFramesPerSecond; m->_w = (size_t)s.frame.size.width; m->_h = (size_t)s.frame.size.height;
    return (CGDisplayModeRef)m;
}
double CGDisplayModeGetRefreshRate(CGDisplayModeRef m) { return m ? ((_MWDisplayMode *)m)->_hz : 60; }
size_t CGDisplayModeGetWidth(CGDisplayModeRef m) { return m ? ((_MWDisplayMode *)m)->_w : 0; }
size_t CGDisplayModeGetHeight(CGDisplayModeRef m) { return m ? ((_MWDisplayMode *)m)->_h : 0; }
void CGDisplayModeRelease(CGDisplayModeRef m) { if (m) [(id)m release]; }

/* ======================================================================= CVDisplayLink: a thread that waits for each refresh */
struct __CVDisplayLink {
    int refs;
    volatile int running;
    pthread_t thread;
    CVDisplayLinkOutputCallback cb; void *ctx;
    CVDisplayLinkOutputHandler handler;
    uint64_t period_ns;
    int64_t frames;
};
uint64_t CVGetCurrentHostTime(void) { return mach_absolute_time(); }
double CVGetHostClockFrequency(void) { return 1e9; }
uint32_t CVGetHostClockMinimumTimeDelta(void) { return 1; }
static void stamp(CVDisplayLinkRef l, CVTimeStamp *t, uint64_t host, int64_t frame) {
    memset(t, 0, sizeof *t);
    t->videoTimeScale = 1000000000; t->videoRefreshPeriod = (int64_t)l->period_ns; t->videoTime = frame * (int64_t)l->period_ns;
    t->hostTime = host; t->rateScalar = 1;
    t->flags = kCVTimeStampVideoTimeValid | kCVTimeStampHostTimeValid | kCVTimeStampVideoRefreshPeriodValid | kCVTimeStampRateScalarValid;
}
static void *link_thread(void *p) {
    CVDisplayLinkRef l = p;
    while (l->running) {
        int64_t mhz = ui(UI_VSYNC_WAIT, 0, 0, 0, 0, 0);
        if (!l->running) break;
        l->period_ns = (uint64_t)(1e12 / (mhz > 0 ? mhz : 60000));
        CVTimeStamp now, out;
        uint64_t t = mach_absolute_time();
        stamp(l, &now, t, l->frames); stamp(l, &out, t + l->period_ns, l->frames + 1);
        l->frames++;
        CVOptionFlags fo = 0;
        void *pool = objc_autoreleasePoolPush();
        if (l->handler) l->handler(l, &now, &out, 0, &fo);
        else if (l->cb) l->cb(l, &now, &out, 0, &fo, l->ctx);
        objc_autoreleasePoolPop(pool);
    }
    return NULL;
}
CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef *out) {
    if (!out) return kCVReturnInvalidArgument;
    CVDisplayLinkRef l = calloc(1, sizeof *l);
    l->refs = 1;
    l->period_ns = (uint64_t)(1e9 / fmax(1, [[NSScreen screens].firstObject maximumFramesPerSecond]));
    *out = l;
    return kCVReturnSuccess;
}
CVReturn CVDisplayLinkCreateWithCGDisplay(CGDirectDisplayID d, CVDisplayLinkRef *out) { return CVDisplayLinkCreateWithActiveCGDisplays(out); }
CVReturn CVDisplayLinkCreateWithCGDisplays(CGDirectDisplayID *d, long n, CVDisplayLinkRef *out) { return CVDisplayLinkCreateWithActiveCGDisplays(out); }
CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef l, CVDisplayLinkOutputCallback cb, void *ctx) { l->cb = cb; l->ctx = ctx; return kCVReturnSuccess; }
CVReturn CVDisplayLinkSetOutputHandler(CVDisplayLinkRef l, CVDisplayLinkOutputHandler h) {
    if (l->handler) [(id)l->handler release];
    l->handler = [h copy];
    return kCVReturnSuccess;
}
CVReturn CVDisplayLinkSetCurrentCGDisplay(CVDisplayLinkRef l, CGDirectDisplayID d) { return kCVReturnSuccess; }
CGDirectDisplayID CVDisplayLinkGetCurrentCGDisplay(CVDisplayLinkRef l) { return 1; }
CVReturn CVDisplayLinkStart(CVDisplayLinkRef l) {
    if (!l) return kCVReturnInvalidArgument;
    if (!l->cb && !l->handler) return kCVReturnDisplayLinkCallbacksNotSet;
    if (l->running) return kCVReturnDisplayLinkAlreadyRunning;
    l->running = 1;
    if (pthread_create(&l->thread, NULL, link_thread, l)) { l->running = 0; return kCVReturnError; }
    return kCVReturnSuccess;
}
CVReturn CVDisplayLinkStop(CVDisplayLinkRef l) {
    if (!l || !l->running) return kCVReturnDisplayLinkNotRunning;
    l->running = 0;
    if (!pthread_equal(pthread_self(), l->thread)) pthread_join(l->thread, NULL);
    else pthread_detach(l->thread);
    return kCVReturnSuccess;
}
int CVDisplayLinkIsRunning(CVDisplayLinkRef l) { return l && l->running; }
CVDisplayLinkRef CVDisplayLinkRetain(CVDisplayLinkRef l) { if (l) __atomic_add_fetch(&l->refs, 1, __ATOMIC_SEQ_CST); return l; }
void CVDisplayLinkRelease(CVDisplayLinkRef l) {
    if (!l || __atomic_sub_fetch(&l->refs, 1, __ATOMIC_SEQ_CST)) return;
    CVDisplayLinkStop(l);
    if (l->handler) [(id)l->handler release];
    free(l);
}
CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod(CVDisplayLinkRef l) { CVTime t = {(int64_t)l->period_ns, 1000000000, 0}; return t; }
double CVDisplayLinkGetActualOutputVideoRefreshPeriod(CVDisplayLinkRef l) { return l->period_ns / 1e9; }
CVReturn CVDisplayLinkGetCurrentTime(CVDisplayLinkRef l, CVTimeStamp *out) { stamp(l, out, mach_absolute_time(), l->frames); return kCVReturnSuccess; }

/* ======================================================================= MTKView */
/* the timer keeps a weak (assign) reference, so the view can go away */
@interface _MWViewTicker : NSObject { @public MTKView *_view; } @end
@implementation _MWViewTicker
- (void)tick:(NSTimer *)t { [_view performSelector:@selector(_mwTick)]; }
@end
@implementation MTKView {
    _MWViewTicker *_ticker; NSTimer *_timer; id<CAMetalDrawable> _drawable; MTLRenderPassDescriptor *_rpd;
    id<MTLTexture> _depth, _msaa; CGSize _lastSize; BOOL _pending;
}
@synthesize depthStencilTexture = _depth, multisampleColorTexture = _msaa;
- (instancetype)initWithFrame:(CGRect)r device:(id<MTLDevice>)d {
    if (!(self = [super initWithFrame:r])) return nil;
    _colorPixelFormat = MTLPixelFormatBGRA8Unorm; _depthStencilPixelFormat = MTLPixelFormatInvalid; _sampleCount = 1;
    _clearColor = MTLClearColorMake(0, 0, 0, 1); _clearDepth = 1; _preferredFramesPerSecond = 60; _autoResizeDrawable = YES; _framebufferOnly = YES;
    _depthStencilAttachmentTextureUsage = MTLTextureUsageRenderTarget; _depthStencilStorageMode = MTLStorageModePrivate;
    self.wantsLayer = YES;
    self.device = d;
    _ticker = [[_MWViewTicker alloc] init]; _ticker->_view = self;
    [self _mwSchedule];
    return self;
}
- (instancetype)initWithFrame:(NSRect)r { return [self initWithFrame:r device:nil]; }
- (instancetype)initWithCoder:(NSCoder *)c { return (id)mw_nib_init_view(self, c); }
- (void)dealloc {
    [_timer invalidate]; _ticker->_view = nil; [_ticker release];
    [_device release]; [_drawable release]; [_rpd release]; [_depth release]; [_msaa release];
    [super dealloc];
}
- (CAMetalLayer *)_ml { return (CAMetalLayer *)self.layer; }
- (CALayer *)makeBackingLayer {
    CAMetalLayer *l = [CAMetalLayer layer];
    l.device = _device; l.pixelFormat = _colorPixelFormat; l.framebufferOnly = _framebufferOnly;
    return l;
}
- (id<MTLDevice>)preferredDevice { return [[self _ml] preferredDevice]; }
- (void)setDevice:(id<MTLDevice>)d { [d retain]; [_device release]; _device = d; [self _ml].device = d; }
- (void)setColorPixelFormat:(MTLPixelFormat)f { _colorPixelFormat = f; [self _ml].pixelFormat = f; [_msaa release]; _msaa = nil; }
- (void)setDepthStencilPixelFormat:(MTLPixelFormat)f { _depthStencilPixelFormat = f; [_depth release]; _depth = nil; }
- (void)setSampleCount:(NSUInteger)n { _sampleCount = n ? n : 1; [_depth release]; _depth = nil; [_msaa release]; _msaa = nil; }
- (void)setFramebufferOnly:(BOOL)f { _framebufferOnly = f; [self _ml].framebufferOnly = f; }
- (void)setPresentsWithTransaction:(BOOL)f { _presentsWithTransaction = f; [self _ml].presentsWithTransaction = f; }
- (CGSize)drawableSize { return [self _ml].drawableSize; }
- (void)setDrawableSize:(CGSize)s { [self _ml].drawableSize = s; }
- (CGSize)preferredDrawableSize { NSRect b = [self convertRectToBacking:self.bounds]; return CGSizeMake(b.size.width, b.size.height); }
- (void)_mwSizeChanged:(CGSize)s {
    if (CGSizeEqualToSize(s, _lastSize) || s.width < 1 || s.height < 1) return;
    _lastSize = s;
    [_depth release]; _depth = nil; [_msaa release]; _msaa = nil;
    if ([(id)_delegate respondsToSelector:@selector(mtkView:drawableSizeWillChange:)]) [_delegate mtkView:self drawableSizeWillChange:s];
}
- (void)_mwFit {
    if (!_autoResizeDrawable || !self.window) return;
    CGSize s = [self preferredDrawableSize];
    if (s.width < 1 || s.height < 1) return;
    [self _ml].contentsScale = self.window.backingScaleFactor;
    if (!CGSizeEqualToSize([self _ml].drawableSize, s)) [self _ml].drawableSize = s;
    [self _mwSizeChanged:s];
}
- (void)setFrame:(NSRect)r { [super setFrame:r]; [self _mwFit]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self _mwFit]; }
- (void)viewDidChangeBackingProperties { [super viewDidChangeBackingProperties]; [self _mwFit]; }
- (void)_mwSchedule {
    [_timer invalidate]; _timer = nil;
    if (_paused || _enableSetNeedsDisplay || _preferredFramesPerSecond <= 0) return;
    _timer = [NSTimer timerWithTimeInterval:1.0 / _preferredFramesPerSecond target:_ticker selector:@selector(tick:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)setPaused:(BOOL)p { _paused = p; [self _mwSchedule]; }
- (void)setEnableSetNeedsDisplay:(BOOL)e { _enableSetNeedsDisplay = e; [self _mwSchedule]; }
- (void)setPreferredFramesPerSecond:(NSInteger)f { _preferredFramesPerSecond = f; [self _mwSchedule]; }
- (void)_mwTick { if (self.window.isVisible && !self.isHiddenOrHasHiddenAncestor && !self.window.isMiniaturized) [self draw]; }
- (void)setNeedsDisplay:(BOOL)f {
    [super setNeedsDisplay:f];
    if (!f || !_enableSetNeedsDisplay || _pending) return;
    _pending = YES;
    [self retain];
    dispatch_async(dispatch_get_main_queue(), ^{ _pending = NO; [self draw]; [self release]; });
}
- (void)displayIfNeeded { [super displayIfNeeded]; } /* drawing happens in -draw */
- (void)drawRect:(NSRect)r { }
- (void)draw {
    void *pool = objc_autoreleasePoolPush();
    if ([(id)_delegate respondsToSelector:@selector(drawInMTKView:)]) [_delegate drawInMTKView:self];
    else [self drawRect:self.bounds];
    [_drawable release]; _drawable = nil;
    [_rpd release]; _rpd = nil;
    objc_autoreleasePoolPop(pool);
}
- (id<CAMetalDrawable>)currentDrawable {
    if (!_drawable) {
        if (![self _ml].device) [self _ml].device = _device ? _device : [[self _ml] preferredDevice];
        _drawable = [[[self _ml] nextDrawable] retain];
        id<MTLTexture> t = _drawable.texture;
        if (t) [self _mwSizeChanged:CGSizeMake(t.width, t.height)]; /* the window decides the real size */
    }
    return _drawable;
}
static BOOL has_stencil(MTLPixelFormat f) {
    return f == MTLPixelFormatStencil8 || f == MTLPixelFormatDepth24Unorm_Stencil8 || f == MTLPixelFormatDepth32Float_Stencil8 || f == MTLPixelFormatX32_Stencil8;
}
- (id<MTLTexture>)_mwTexture:(MTLPixelFormat)f w:(NSUInteger)w h:(NSUInteger)h {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:f width:w height:h mipmapped:NO];
    d.usage = MTLTextureUsageRenderTarget; d.storageMode = MTLStorageModePrivate;
    if (_sampleCount > 1) { d.textureType = MTLTextureType2DMultisample; d.sampleCount = _sampleCount; }
    return [_device newTextureWithDescriptor:d];
}
- (MTLRenderPassDescriptor *)currentRenderPassDescriptor {
    if (_rpd) return _rpd;
    id<CAMetalDrawable> dr = [self currentDrawable];
    if (!dr) return nil;
    id<MTLTexture> t = dr.texture;
    _rpd = [[MTLRenderPassDescriptor renderPassDescriptor] retain];
    MTLRenderPassColorAttachmentDescriptor *c = _rpd.colorAttachments[0];
    c.clearColor = _clearColor; c.loadAction = MTLLoadActionClear;
    if (_sampleCount > 1) {
        if (!_msaa || _msaa.width != t.width || _msaa.height != t.height) { [_msaa release]; _msaa = [self _mwTexture:_colorPixelFormat w:t.width h:t.height]; }
        c.texture = _msaa; c.resolveTexture = t; c.storeAction = MTLStoreActionMultisampleResolve;
    } else { c.texture = t; c.storeAction = MTLStoreActionStore; }
    if (_depthStencilPixelFormat != MTLPixelFormatInvalid) {
        if (!_depth || _depth.width != t.width || _depth.height != t.height) { [_depth release]; _depth = [self _mwTexture:_depthStencilPixelFormat w:t.width h:t.height]; }
        if (_depthStencilPixelFormat != MTLPixelFormatStencil8 && _depthStencilPixelFormat != MTLPixelFormatX32_Stencil8) {
            _rpd.depthAttachment.texture = _depth; _rpd.depthAttachment.clearDepth = _clearDepth;
            _rpd.depthAttachment.loadAction = MTLLoadActionClear; _rpd.depthAttachment.storeAction = MTLStoreActionDontCare;
        }
        if (has_stencil(_depthStencilPixelFormat)) {
            _rpd.stencilAttachment.texture = _depth; _rpd.stencilAttachment.clearStencil = _clearStencil;
            _rpd.stencilAttachment.loadAction = MTLLoadActionClear; _rpd.stencilAttachment.storeAction = MTLStoreActionDontCare;
        }
    }
    return _rpd;
}
- (void)releaseDrawables { [_drawable release]; _drawable = nil; [_depth release]; _depth = nil; [_msaa release]; _msaa = nil; }
@end
void CGRectDivide(CGRect r, CGRect *slice, CGRect *rem, CGFloat amount, CGRectEdge edge) {
    r = CGRectStandardize(r);
    CGFloat w = r.size.width, h = r.size.height, a = fmax(0, amount);
    CGRect s = r, m = r;
    switch (edge) {
    case CGRectMinXEdge: a = fmin(a, w); s.size.width = a; m.origin.x += a; m.size.width = w - a; break;
    case CGRectMaxXEdge: a = fmin(a, w); s.origin.x += w - a; s.size.width = a; m.size.width = w - a; break;
    case CGRectMinYEdge: a = fmin(a, h); s.size.height = a; m.origin.y += a; m.size.height = h - a; break;
    case CGRectMaxYEdge: a = fmin(a, h); s.origin.y += h - a; s.size.height = a; m.size.height = h - a; break;
    }
    if (slice) *slice = s;
    if (rem) *rem = m;
}
