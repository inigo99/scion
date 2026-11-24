// 2D drawing: CoreGraphics (fills, strokes, clipping, images) and AppKit (views, controls, text, PNG, windows composited
// by the host, controls driven by the mouse, and views over Metal). Prints "DRAWING OK".
#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>
#include <stdio.h>
#include <math.h>

static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

// pixel (x, y from the top) of a premultiplied BGRA context (32Little + PremultipliedFirst)
static uint32_t px(CGContextRef c, int x, int y) {
    const uint8_t *p = (const uint8_t *)CGBitmapContextGetData(c) + y * CGBitmapContextGetBytesPerRow(c) + x * 4;
    return (uint32_t)p[2] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[0] << 8 | p[3]; // RRGGBBAA
}
static int near(uint32_t a, uint32_t b, int tol) {
    for (int s = 0; s < 32; s += 8) if (abs((int)((a >> s) & 255) - (int)((b >> s) & 255)) > tol) return 0;
    return 1;
}
static double alpha_sum(CGContextRef c) {
    double t = 0;
    for (size_t y = 0; y < CGBitmapContextGetHeight(c); y++)
        for (size_t x = 0; x < CGBitmapContextGetWidth(c); x++) t += (px(c, (int)x, (int)y) & 255) / 255.0;
    return t;
}
static CGContextRef ctx(int w, int h) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    return c;
}

static void cg(void) {
    CGContextRef c = ctx(100, 100);
    CHECK(c != NULL, "CGBitmapContextCreate");
    // rectangle: origin at the bottom left (y up)
    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextFillRect(c, CGRectMake(10, 10, 20, 30));          // x 10..30, y 10..40 -> rows 60..89
    CHECK(px(c, 15, 70) == 0xFF0000FF, "rect inside %08x", px(c, 15, 70));
    CHECK(px(c, 15, 50) == 0, "rect outside (above) %08x", px(c, 15, 50));
    CHECK(px(c, 35, 70) == 0, "rect outside (right) %08x", px(c, 35, 70));
    // edge on a half pixel: 50 % coverage
    CGContextClearRect(c, CGRectMake(0, 0, 100, 100));
    CHECK(alpha_sum(c) == 0, "ClearRect");
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextFillRect(c, CGRectMake(10.5, 0, 10, 100));
    CHECK(near(px(c, 10, 50), 0x00007F7F, 2), "AA edge %08x", px(c, 10, 50));
    CHECK(px(c, 11, 50) == 0x0000FFFF, "interior %08x", px(c, 11, 50));
    // circle: area ~ pi r^2
    CGContextClearRect(c, CGRectMake(0, 0, 100, 100));
    CGContextSetGrayFillColor(c, 1, 1);
    CGContextFillEllipseInRect(c, CGRectMake(20, 20, 60, 60));
    double area = alpha_sum(c);
    CHECK(fabs(area - M_PI * 900) < 15, "circle area %.1f (expected %.1f)", area, M_PI * 900);
    CHECK(px(c, 50, 50) == 0xFFFFFFFF && px(c, 22, 22) == 0, "circle center/corner");
    // 4 px stroke: horizontal line
    CGContextClearRect(c, CGRectMake(0, 0, 100, 100));
    CGContextSetRGBStrokeColor(c, 0, 1, 0, 1);
    CGContextSetLineWidth(c, 4);
    CGContextMoveToPoint(c, 10, 50); CGContextAddLineToPoint(c, 90, 50); CGContextStrokePath(c);
    CHECK(px(c, 50, 48) == 0x00FF00FF && px(c, 50, 51) == 0x00FF00FF, "stroke inside");
    CHECK(px(c, 50, 46) == 0 && px(c, 50, 53) == 0, "stroke outside %08x %08x", px(c, 50, 46), px(c, 50, 53));
    CHECK(fabs(alpha_sum(c) - 320) < 2, "stroke area %.1f", alpha_sum(c));
    // stroked rectangle with mitered corners: the whole ring
    CGContextClearRect(c, CGRectMake(0, 0, 100, 100));
    CGContextSetLineWidth(c, 2);
    CGContextStrokeRect(c, CGRectMake(20, 20, 60, 60));
    CHECK(fabs(alpha_sum(c) - (62 * 62 - 58 * 58)) < 3, "ring %.1f", alpha_sum(c));
    CHECK(px(c, 19, 19) == 0x00FF00FF, "mitered corner %08x", px(c, 19, 19));
    // even-odd: two concentric rectangles leave a hole
    CGContextClearRect(c, CGRectMake(0, 0, 100, 100));
    CGContextAddRect(c, CGRectMake(10, 10, 80, 80)); CGContextAddRect(c, CGRectMake(30, 30, 40, 40));
    CGContextEOFillPath(c);
    CHECK(px(c, 50, 50) == 0 && px(c, 15, 50) == 0xFFFFFFFF, "even-odd");
    // rounded clip and transforms
    CGContextClearRect(c, CGRectMake(0, 0, 100, 100));
    CGContextSaveGState(c);
    CGPathRef rr = CGPathCreateWithRoundedRect(CGRectMake(0, 0, 100, 100), 30, 30, NULL);
    CGContextAddPath(c, rr); CGContextClip(c); CGPathRelease(rr);
    CGContextSetRGBFillColor(c, 1, 1, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 100, 100));
    CGContextRestoreGState(c);
    CHECK(px(c, 1, 1) == 0 && px(c, 50, 50) == 0xFFFF00FF && px(c, 50, 1) == 0xFFFF00FF, "rounded clip");
    CGContextClearRect(c, CGRectMake(0, 0, 100, 100));
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, 50, 50); CGContextRotateCTM(c, M_PI / 4); CGContextScaleCTM(c, 2, 2);
    CGContextSetRGBFillColor(c, 1, 0, 1, 0.5);
    CGContextFillRect(c, CGRectMake(-5, -5, 10, 10));            // centered 20x20 diamond
    CGContextRestoreGState(c);
    CHECK(near(px(c, 50, 50), 0x7F007F7F, 2), "CTM + alpha %08x", px(c, 50, 50));
    CHECK(px(c, 50, 37) != 0 && px(c, 39, 39) == 0, "diamond");
    CHECK(fabs(alpha_sum(c) - 200) < 3, "diamond area %.1f", alpha_sum(c));
    // images: a 2x2 square scaled without interpolation, and CGBitmapContextCreateImage
    uint8_t quad[16] = {0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255, 255, 255, 255, 255}; // BGRA: red green / blue white
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, quad, 16, NULL);
    CGImageRef img = CGImageCreate(2, 2, 8, 32, 8, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, dp, NULL, false, 0);
    CGContextClearRect(c, CGRectMake(0, 0, 100, 100));
    CGContextSetInterpolationQuality(c, kCGInterpolationNone);
    CGContextDrawImage(c, CGRectMake(0, 0, 100, 100), img);
    CHECK(px(c, 10, 10) == 0xFF0000FF && px(c, 90, 10) == 0x00FF00FF && px(c, 10, 90) == 0x0000FFFF && px(c, 90, 90) == 0xFFFFFFFF,
          "scaled image %08x %08x %08x %08x", px(c, 10, 10), px(c, 90, 10), px(c, 10, 90), px(c, 90, 90));
    CGImageRef copy = CGBitmapContextCreateImage(c);
    CHECK(CGImageGetWidth(copy) == 100 && CGImageGetHeight(copy) == 100, "CreateImage");
    CGContextRef c2 = ctx(50, 50);
    CGContextDrawImage(c2, CGRectMake(0, 0, 50, 50), copy);
    CHECK(near(px(c2, 5, 5), 0xFF0000FF, 1) && near(px(c2, 45, 45), 0xFFFFFFFF, 1), "downscaled image %08x %08x", px(c2, 5, 5), px(c2, 45, 45));
    // alpha mask with the fill color
    uint8_t m[4] = {255, 0, 0, 255};
    CGDataProviderRef mp = CGDataProviderCreateWithData(NULL, m, 4, NULL);
    CGImageRef mask = CGImageCreate(2, 2, 8, 8, 2, NULL, kCGImageAlphaOnly, mp, NULL, false, 0);
    CGContextClearRect(c2, CGRectMake(0, 0, 50, 50));
    CGContextSetInterpolationQuality(c2, kCGInterpolationNone);
    CGContextSetRGBFillColor(c2, 0, 0, 1, 1);
    CGContextDrawImage(c2, CGRectMake(0, 0, 50, 50), mask);
    CHECK(px(c2, 5, 5) == 0x0000FFFF && px(c2, 45, 5) == 0 && px(c2, 45, 45) == 0x0000FFFF, "mascara");
    CGImageRelease(mask); CGDataProviderRelease(mp);
    CGImageRelease(copy); CGImageRelease(img); CGDataProviderRelease(dp); CGColorSpaceRelease(cs);
    CGContextRelease(c2); CGContextRelease(c);
    printf("CoreGraphics: done\n");
}


/* ---------------------------------------------------------------- AppKit without a window: text, views to bitmaps, PNG */
@interface Fill : NSView
@property NSColor *color; @property NSRect area; @property BOOL flip; @property NSImage *image;
@end
@implementation Fill
- (BOOL)isFlipped { return _flip; }
- (void)drawRect:(NSRect)r {
    if (_image) { [_image drawInRect:self.bounds]; return; }
    [_color setFill]; NSRectFill(_area);
}
@end
static BOOL near_color(NSColor *c, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return c && fabs(c.redComponent - r) < 0.03 && fabs(c.greenComponent - g) < 0.03 && fabs(c.blueComponent - b) < 0.03 && fabs(c.alphaComponent - a) < 0.03;
}
static NSString *desc(NSColor *c) { return c ? [NSString stringWithFormat:@"%.2f %.2f %.2f %.2f", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent] : @"nil"; }

static void offscreen(void) {
    NSFont *f = [NSFont systemFontOfSize:13];
    NSSize s1 = [@"Hello" sizeWithAttributes:@{NSFontAttributeName: f}], s2 = [@"Hello, world" sizeWithAttributes:@{NSFontAttributeName: f}];
    CHECK(s1.width > 15 && s1.width < 60 && s1.height >= 13 && s1.height < 26, "text size %gx%g", s1.width, s1.height);
    CHECK(s2.width > s1.width * 1.8, "longer text, wider (%g)", s2.width);
    CHECK(f.ascender > 8 && f.descender < 0, "font metrics %g %g", f.ascender, f.descender);
    NSRect two = [@"one two three four five" boundingRectWithSize:NSMakeSize(60, 1000) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: f}];
    CHECK(two.size.height > s1.height * 1.5, "text wrapped into lines (%g)", two.size.height);

    // a view tree to a bitmap (cacheDisplayInRect)
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    root.wantsLayer = YES; root.layer.backgroundColor = NSColor.redColor.CGColor; root.layer.cornerRadius = 20; root.layer.masksToBounds = YES;
    Fill *fl = [[Fill alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    fl.flip = YES; fl.color = NSColor.blueColor; fl.area = NSMakeRect(30, 10, 20, 20);   // flipped view: at the top
    [root addSubview:fl];
    NSTextField *label = [NSTextField labelWithString:@"Hello"];
    label.font = [NSFont boldSystemFontOfSize:20]; label.textColor = NSColor.whiteColor;
    label.frame = NSMakeRect(10, 10, 80, 30);
    [root addSubview:label];
    Fill *img = [[Fill alloc] initWithFrame:NSMakeRect(60, 50, 20, 20)];
    img.image = [NSImage imageWithSize:NSMakeSize(10, 10) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [NSColor.greenColor setFill]; NSRectFill(NSMakeRect(0, 0, 10, 5)); return YES;   // bottom half
    }];
    [root addSubview:img];
    NSBitmapImageRep *rep = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
    [root cacheDisplayInRect:root.bounds toBitmapImageRep:rep];
    CGFloat k = rep.pixelsWide / 100.0;
    #define AT(px_, py_) [rep colorAtX:(NSInteger)((px_) * k) y:(NSInteger)((py_) * k)]   // y from the top, in points
    CHECK(near_color(AT(1, 1), 0, 0, 0, 0), "transparent rounded corner (%s)", [desc(AT(1, 1)) UTF8String]);
    CHECK(near_color(AT(50, 50), 1, 0, 0, 1), "red layer background (%s)", [desc(AT(50, 50)) UTF8String]);
    CHECK(near_color(AT(40, 20), 0, 0, 1, 1), "drawRect: of a flipped view, at the top (%s)", [desc(AT(40, 20)) UTF8String]);
    CHECK(near_color(AT(95, 80), 1, 0, 0, 1), "and not at the bottom (%s)", [desc(AT(95, 80)) UTF8String]);
    CHECK(near_color(AT(70, 45), 0, 1, 0, 1) && near_color(AT(70, 35), 1, 0, 0, 1), "NSImage with a drawingHandler (%s / %s)", [desc(AT(70, 45)) UTF8String], [desc(AT(70, 35)) UTF8String]);
    int white = 0;
    for (int y = 60; y < 90; y++) for (int x = 10; x < 90; x++) { NSColor *c = AT(x, y); if (c.greenComponent > 0.6 && c.redComponent > 0.6) white++; }
    CHECK(white > 20, "label text drawn (%d white points)", white);
    // PNG and JPEG (WIC) round trip
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    CHECK(png.length > 100, "PNG encoded (%lu bytes)", (unsigned long)png.length);
    NSBitmapImageRep *back = [NSBitmapImageRep imageRepWithData:png];
    CHECK(back.pixelsWide == rep.pixelsWide && near_color([back colorAtX:(NSInteger)(50 * k) y:(NSInteger)(50 * k)], 1, 0, 0, 1) &&
          near_color([back colorAtX:1 y:1], 0, 0, 0, 0), "PNG decodes to the same");
    NSImage *ni = [[NSImage alloc] initWithData:png];
    CHECK(ni && ni.size.width == rep.pixelsWide, "NSImage from PNG");
    CHECK([rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @0.8}].length > 100, "JPEG encoded");
    // NSBezierPath
    NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, 10, 10)];
    CHECK([o containsPoint:NSMakePoint(5, 5)] && ![o containsPoint:NSMakePoint(0.5, 0.5)], "NSBezierPath containsPoint");
    CHECK(o.elementCount == 6, "oval elements (%ld)", (long)o.elementCount);
    // controls draw
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
    NSSegmentedControl *seg = [NSSegmentedControl segmentedControlWithLabels:@[@"30", @"60", @"90"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
    seg.frame = NSMakeRect(0, 8, 120, 24); seg.selectedSegment = 1;
    NSSwitch *sw = [NSSwitch new]; sw.frame = NSMakeRect(140, 9, 38, 22); sw.state = NSControlStateValueOn;
    [panel addSubview:seg]; [panel addSubview:sw];
    NSBitmapImageRep *pr = [panel bitmapImageRepForCachingDisplayInRect:panel.bounds];
    [panel cacheDisplayInRect:panel.bounds toBitmapImageRep:pr];
    CGFloat pk = pr.pixelsWide / 200.0;
    NSColor *knob = [pr colorAtX:(NSInteger)(168 * pk) y:(NSInteger)(20 * pk)], *track = [pr colorAtX:(NSInteger)(146 * pk) y:(NSInteger)(20 * pk)];
    CHECK(knob.alphaComponent > 0.9 && knob.redComponent > 0.8, "NSSwitch: knob on the right (%s)", [desc(knob) UTF8String]);
    CHECK(track.blueComponent > 0.8 && track.redComponent < 0.3, "NSSwitch on, in blue (%s)", [desc(track) UTF8String]);
    NSColor *sel = [pr colorAtX:(NSInteger)(39 * pk) y:(NSInteger)(11 * pk)], *unsel = [pr colorAtX:(NSInteger)(4 * pk) y:(NSInteger)(11 * pk)];
    CHECK(sel.alphaComponent > unsel.alphaComponent + 0.1, "selected segment highlighted (%s / %s)", [desc(sel) UTF8String], [desc(unsel) UTF8String]);
    printf("AppKit without a window: done\n");
}

/* ---------------------------------------------------------------- windows: the host shows them; mouse on controls; views over Metal */
int64_t _scion_ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
enum { UI_INJECT = 20, UI_FREE = 22, UI_TEST = 25 };
enum { WM_MOUSEMOVE = 0x200, WM_LBUTTONDOWN = 0x201, WM_LBUTTONUP = 0x202, WM_CLOSE = 0x10 };
typedef struct { uint32_t w, h; void *pixels; } Img;
static void inject(NSWindow *w, unsigned msg, uint64_t wp, uint64_t lp) { _scion_ui(UI_INJECT, (uint64_t)w.windowNumber, msg, wp, lp, 0); }
static uint64_t xy(NSWindow *w, NSPoint p) { /* content points (bottom-left) -> client pixels (top-left) */
    CGFloat s = w.backingScaleFactor, h = w.contentView.frame.size.height;
    return (uint64_t)(uint16_t)lround(p.x * s) | (uint64_t)(uint16_t)lround((h - p.y) * s) << 16;
}
static void click(NSWindow *w, NSPoint p) { inject(w, WM_LBUTTONDOWN, 1, xy(w, p)); inject(w, WM_LBUTTONUP, 0, xy(w, p)); }
static uint32_t shown(NSWindow *w, NSPoint p) { /* BGRA of what the window shows at p -> 0xRRGGBB */
    Img img = {0};
    if (_scion_ui(UI_TEST, 3, (uint64_t)w.windowNumber, (uint64_t)(uintptr_t)&img, 0, 0) != 1) return 0xFFFFFFFF;
    CGFloat s = w.backingScaleFactor, h = w.contentView.frame.size.height;
    uint32_t x = (uint32_t)(p.x * s), y = (uint32_t)((h - p.y) * s), v = 0xFFFFFFFF;
    if (x < img.w && y < img.h) { const uint8_t *q = (const uint8_t *)img.pixels + (y * img.w + x) * 4; v = (uint32_t)q[2] << 16 | (uint32_t)q[1] << 8 | q[0]; }
    _scion_ui(UI_FREE, (uint64_t)(uintptr_t)img.pixels, 0, 0, 0, 0);
    return v;
}

@interface App : NSObject <NSApplicationDelegate, MTKViewDelegate>
@property NSWindow *win, *mwin; @property NSSegmentedControl *seg; @property NSSlider *slider; @property NSSwitch *sw; @property NSButton *check;
@property int step, actions, frames;
@end
@implementation App
- (void)act:(id)s { _actions++; }
- (void)mtkView:(MTKView *)v drawableSizeWillChange:(CGSize)s { }
- (void)drawInMTKView:(MTKView *)v {
    static id<MTLCommandQueue> q; if (!q) q = [v.device newCommandQueue];
    id<MTLCommandBuffer> cb = q.commandBuffer;
    MTLRenderPassDescriptor *rp = v.currentRenderPassDescriptor;
    if (!rp) return;
    [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
    [cb presentDrawable:v.currentDrawable];
    [cb commit];
    _frames++;
}
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    _win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    _win.title = @"Drawing"; _win.releasedWhenClosed = NO;
    NSView *c = _win.contentView;
    NSView *red = [[NSView alloc] initWithFrame:NSMakeRect(10, 150, 40, 40)];
    red.wantsLayer = YES; red.layer.backgroundColor = NSColor.redColor.CGColor;
    _seg = [NSSegmentedControl segmentedControlWithLabels:@[@"A", @"B", @"C"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(act:)];
    _seg.frame = NSMakeRect(10, 110, 150, 24); _seg.segmentDistribution = NSSegmentDistributionFillEqually; _seg.selectedSegment = 0;
    _slider = [NSSlider sliderWithValue:0 minValue:0 maxValue:100 target:self action:@selector(act:)];
    _slider.frame = NSMakeRect(10, 70, 200, 21);
    _sw = [NSSwitch new]; _sw.frame = NSMakeRect(10, 30, 38, 22); _sw.target = self; _sw.action = @selector(act:);
    _check = [NSButton checkboxWithTitle:@"Option" target:self action:@selector(act:)]; _check.frame = NSMakeRect(80, 30, 100, 18);
    for (NSView *v in @[red, _seg, _slider, _sw, _check]) [c addSubview:v];
    [_win makeKeyAndOrderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(next:) userInfo:nil repeats:YES];
}
- (void)next:(NSTimer *)t {
    switch (_step++) {
    case 1: {
        printf("step: composited window\n");
        uint32_t bg = shown(_win, NSMakePoint(250, 10)), r = shown(_win, NSMakePoint(30, 170));
        CHECK(bg != 0xFFFFFFFF && ((bg >> 16) & 255) > 30 && ((bg >> 16) & 255) < 70, "window background (%06x)", bg);
        CHECK(r == 0xFF0000, "red view in the window (%06x)", r);
        printf("step: mouse\n");
        click(_win, NSMakePoint(10 + 125, 122));                                 // third segment
        click(_win, NSMakePoint(29, 41));                                        // switch
        click(_win, NSMakePoint(88, 39));                                        // checkbox
        inject(_win, WM_LBUTTONDOWN, 1, xy(_win, NSMakePoint(20, 80)));          // drag the slider to 75 %
        inject(_win, WM_MOUSEMOVE, 1, xy(_win, NSMakePoint(110, 80)));
        inject(_win, WM_MOUSEMOVE, 1, xy(_win, NSMakePoint(10 + 8 + 0.75 * 184, 80)));
        inject(_win, WM_LBUTTONUP, 0, xy(_win, NSMakePoint(10 + 8 + 0.75 * 184, 80)));
        break;
    }
    case 3: {
        CHECK(_seg.selectedSegment == 2, "click on a segment (%ld)", (long)_seg.selectedSegment);
        CHECK(_sw.state == NSControlStateValueOn, "click on the switch");
        CHECK(_check.state == NSControlStateValueOn, "click on the checkbox");
        CHECK(fabs(_slider.doubleValue - 75) < 3, "drag the slider (%g)", _slider.doubleValue);
        CHECK(_actions >= 5, "actions sent (%d)", _actions);
        uint32_t on = shown(_win, NSMakePoint(16, 41));
        CHECK((on & 255) > 200 && (on >> 16) < 80, "the switch looks on (%06x)", on);
        printf("step: views over Metal\n");
        _mwin = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 150) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        _mwin.releasedWhenClosed = NO;
        MTKView *mv = [[MTKView alloc] initWithFrame:NSMakeRect(0, 0, 200, 150) device:MTLCreateSystemDefaultDevice()];
        mv.clearColor = MTLClearColorMake(0, 0, 1, 1); mv.delegate = self;
        _mwin.contentView = mv;
        NSButton *b = [NSButton buttonWithTitle:@"On top" target:nil action:nil];
        b.frame = NSMakeRect(10, 10, 90, 24);
        [mv addSubview:b];
        [_mwin makeKeyAndOrderFront:nil];
        break;
    }
    case 12: {
        CAMetalLayer *l = (CAMetalLayer *)_mwin.contentView.layer;
        NSUInteger draws = [l respondsToSelector:@selector(_mwOverlayDraws)] ? (NSUInteger)[l performSelector:@selector(_mwOverlayDraws)] : 0;
        CHECK(_frames > 5, "MTKView draws (%d)", _frames);
        CHECK(draws > 3, "views blend over the Metal image (%lu times)", (unsigned long)draws);
        [_mwin close]; [_win close];
        printf(fails ? "DRAWING FAIL (%d)\n" : "DRAWING OK\n", fails);
        exit(fails != 0);
    }
    case 40: printf("FAIL: timed out\n"); exit(1);
    }
}
@end

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        cg();
        offscreen();
        [NSApplication sharedApplication];
        App *a = [App new];
        NSApp.delegate = a;
        [NSApp run];
    }
    return 1;
}
