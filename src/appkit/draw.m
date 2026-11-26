/* draw.m — AppKit drawing on top of cgdraw.m: NSGraphicsContext, NSBezierPath, NSRectFill & co, text (rendered by the
 * host with GDI, drawn as alpha masks), NSImage / NSBitmapImageRep (decoded and encoded by the host with WIC), SF Symbol
 * stand-ins, and the window compositor: every view of a window is drawn into one bitmap (drawRect:, layer background,
 * corners and border), which the host shows, or which is blended over the window's CAMetalLayer when it has one. */
#import "internal.h"
#import <QuartzCore/CAMetalLayer.h>
#include <stdlib.h>
#include <string.h>

/* ======================================================================= NSGraphicsContext */
/* NSCompositingOperation -> CGBlendMode (Clear..XOR are 0..10, the separable ones start at 14) */
CGBlendMode mw_blend_mode(NSCompositingOperation o) {
    return o == NSCompositingOperationClear ? kCGBlendModeClear : o == NSCompositingOperationCopy ? kCGBlendModeCopy
         : o >= NSCompositingOperationSourceIn && o <= NSCompositingOperationXOR ? (CGBlendMode)(kCGBlendModeSourceIn + o - NSCompositingOperationSourceIn)
         : o == NSCompositingOperationPlusDarker ? kCGBlendModePlusDarker : o == NSCompositingOperationPlusLighter ? kCGBlendModePlusLighter
         : o >= NSCompositingOperationMultiply && o <= NSCompositingOperationLuminosity ? (CGBlendMode)(kCGBlendModeMultiply + o - NSCompositingOperationMultiply)
         : kCGBlendModeNormal;
}
@implementation NSGraphicsContext { CGContextRef _cg; BOOL _flipped; id _keep; NSImageInterpolation _interp; NSCompositingOperation _op; }
static NSGraphicsContext *g_ctx;
static NSMutableArray *g_ctx_stack;
+ (NSGraphicsContext *)currentContext { return g_ctx; }
+ (void)setCurrentContext:(NSGraphicsContext *)c { [c retain]; [g_ctx release]; g_ctx = c; }
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)c flipped:(BOOL)f {
    if (!c) return nil;
    NSGraphicsContext *g = [[[self alloc] init] autorelease];
    g->_cg = CGContextRetain(c); g->_flipped = f; g->_op = NSCompositingOperationSourceOver;
    return g;
}
+ (NSGraphicsContext *)graphicsContextWithBitmapImageRep:(NSBitmapImageRep *)b {
    CGContextRef c = [b _mwNewCGContext];
    NSGraphicsContext *g = [self graphicsContextWithCGContext:c flipped:NO];
    CGContextRelease(c);
    if (g) g->_keep = [b retain];
    return g;
}
+ (void)saveGraphicsState {
    if (!g_ctx_stack) g_ctx_stack = [[NSMutableArray alloc] init];
    [g_ctx_stack addObject:g_ctx ? (id)g_ctx : (id)[NSNull null]];
    [g_ctx saveGraphicsState];
}
+ (void)restoreGraphicsState {
    if (![g_ctx_stack count]) return;
    id c = [[g_ctx_stack lastObject] retain];
    [g_ctx_stack removeLastObject];
    [self setCurrentContext:c == [NSNull null] ? nil : c];
    [g_ctx restoreGraphicsState];
    [c release];
}
- (void)dealloc { CGContextRelease(_cg); [_keep release]; [super dealloc]; }
- (CGContextRef)CGContext { return _cg; }
- (void *)graphicsPort { return _cg; }
- (BOOL)isFlipped { return _flipped; }
- (BOOL)isDrawingToScreen { return _keep == nil; }
- (BOOL)shouldAntialias { return YES; }
- (void)setShouldAntialias:(BOOL)f { CGContextSetShouldAntialias(_cg, f); }
- (NSImageInterpolation)imageInterpolation { return _interp; }
- (void)setImageInterpolation:(NSImageInterpolation)i { _interp = i; CGContextSetInterpolationQuality(_cg, (CGInterpolationQuality)i); }
- (NSCompositingOperation)compositingOperation { return _op; }
- (void)setCompositingOperation:(NSCompositingOperation)o {
    _op = o;
    CGContextSetBlendMode(_cg, mw_blend_mode(o));
}
- (void)saveGraphicsState { CGContextSaveGState(_cg); }
- (void)restoreGraphicsState { CGContextRestoreGState(_cg); }
- (void)flushGraphics { }
@end
CGContextRef mw_cg(void) { return [g_ctx CGContext]; }

/* ======================================================================= NSBezierPath (a CGPath in user space) */
@implementation NSBezierPath { CGMutablePathRef _p; NSWindingRule _rule; }
static CGFloat g_default_width = 1;
+ (NSBezierPath *)bezierPath { return [[[self alloc] init] autorelease]; }
+ (NSBezierPath *)bezierPathWithRect:(NSRect)r { NSBezierPath *p = [self bezierPath]; [p appendBezierPathWithRect:r]; return p; }
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)r { NSBezierPath *p = [self bezierPath]; [p appendBezierPathWithOvalInRect:r]; return p; }
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)x yRadius:(CGFloat)y { NSBezierPath *p = [self bezierPath]; [p appendBezierPathWithRoundedRect:r xRadius:x yRadius:y]; return p; }
+ (void)fillRect:(NSRect)r { CGContextFillRect(mw_cg(), r); }
+ (void)strokeRect:(NSRect)r { [[self bezierPathWithRect:r] stroke]; }
+ (void)strokeLineFromPoint:(NSPoint)a toPoint:(NSPoint)b { NSBezierPath *p = [self bezierPath]; [p moveToPoint:a]; [p lineToPoint:b]; [p stroke]; }
+ (void)clipRect:(NSRect)r { CGContextClipToRect(mw_cg(), r); }
+ (void)setDefaultLineWidth:(CGFloat)w { g_default_width = w; }
+ (CGFloat)defaultLineWidth { return g_default_width; }
- (instancetype)init { if ((self = [super init])) { _p = CGPathCreateMutable(); _lineWidth = g_default_width; _miterLimit = 10; _flatness = 0.6; } return self; }
- (void)dealloc { CGPathRelease(_p); [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
    NSBezierPath *c = [[NSBezierPath alloc] init];
    CGPathAddPath(c->_p, NULL, _p);
    c.lineWidth = _lineWidth; c.miterLimit = _miterLimit; c.lineJoinStyle = _lineJoinStyle; c.lineCapStyle = _lineCapStyle; c->_rule = _rule;
    return c;
}
- (CGPathRef)CGPath { return _p; }
- (NSWindingRule)windingRule { return _rule; }
- (void)setWindingRule:(NSWindingRule)r { _rule = r; }
- (NSRect)bounds { return CGPathIsEmpty(_p) ? NSZeroRect : CGPathGetBoundingBox(_p); }
- (NSRect)controlPointBounds { return [self bounds]; }
- (BOOL)isEmpty { return CGPathIsEmpty(_p); }
static void count_el(void *info, const CGPathElement *e) { (*(NSInteger *)info)++; }
- (NSInteger)elementCount { NSInteger n = 0; CGPathApply(_p, &n, count_el); return n; }
- (NSPoint)currentPoint { return CGPathGetCurrentPoint(_p); }
- (void)moveToPoint:(NSPoint)p { CGPathMoveToPoint(_p, NULL, p.x, p.y); }
- (void)lineToPoint:(NSPoint)p { CGPathAddLineToPoint(_p, NULL, p.x, p.y); }
- (void)curveToPoint:(NSPoint)p controlPoint1:(NSPoint)a controlPoint2:(NSPoint)b { CGPathAddCurveToPoint(_p, NULL, a.x, a.y, b.x, b.y, p.x, p.y); }
- (void)relativeMoveToPoint:(NSPoint)p { NSPoint c = self.currentPoint; [self moveToPoint:NSMakePoint(c.x + p.x, c.y + p.y)]; }
- (void)relativeLineToPoint:(NSPoint)p { NSPoint c = self.currentPoint; [self lineToPoint:NSMakePoint(c.x + p.x, c.y + p.y)]; }
- (void)closePath { CGPathCloseSubpath(_p); }
- (void)removeAllPoints { CGPathRelease(_p); _p = CGPathCreateMutable(); }
- (void)appendBezierPath:(NSBezierPath *)o { CGPathAddPath(_p, NULL, o->_p); }
- (void)appendBezierPathWithRect:(NSRect)r { CGPathAddRect(_p, NULL, r); }
- (void)appendBezierPathWithOvalInRect:(NSRect)r { CGPathAddEllipseInRect(_p, NULL, r); }
- (void)appendBezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)x yRadius:(CGFloat)y { CGPathAddRoundedRect(_p, NULL, r, x, y); }
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a endAngle:(CGFloat)b clockwise:(BOOL)cw {
    CGPathAddArc(_p, NULL, c.x, c.y, r, a * M_PI / 180, b * M_PI / 180, cw);
}
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a endAngle:(CGFloat)b {
    [self appendBezierPathWithArcWithCenter:c radius:r startAngle:a endAngle:b clockwise:NO];
}
- (void)appendBezierPathWithArcFromPoint:(NSPoint)a toPoint:(NSPoint)b radius:(CGFloat)r { CGPathAddArcToPoint(_p, NULL, a.x, a.y, b.x, b.y, r); }
- (void)appendBezierPathWithPoints:(NSPointArray)pts count:(NSInteger)n { for (NSInteger i = 0; i < n; i++) { if (i || CGPathIsEmpty(_p)) [self lineToPoint:pts[i]]; else [self moveToPoint:pts[i]]; } }
- (void)setLineDash:(const CGFloat *)d count:(NSInteger)n phase:(CGFloat)p { } /* ponytail: solid, like CGContextSetLineDash */
- (void)fill {
    CGContextRef c = mw_cg();
    CGContextBeginPath(c); CGContextAddPath(c, _p);
    if (_rule == NSWindingRuleEvenOdd) CGContextEOFillPath(c); else CGContextFillPath(c);
}
- (void)stroke {
    CGContextRef c = mw_cg();
    CGContextSaveGState(c);
    CGContextSetLineWidth(c, _lineWidth); CGContextSetLineCap(c, (CGLineCap)_lineCapStyle);
    CGContextSetLineJoin(c, (CGLineJoin)_lineJoinStyle); CGContextSetMiterLimit(c, _miterLimit);
    CGContextBeginPath(c); CGContextAddPath(c, _p); CGContextStrokePath(c);
    CGContextRestoreGState(c);
}
- (void)addClip {
    CGContextRef c = mw_cg();
    CGContextBeginPath(c); CGContextAddPath(c, _p);
    if (_rule == NSWindingRuleEvenOdd) CGContextEOClip(c); else CGContextClip(c);
}
- (void)setClip { [self addClip]; } /* ponytail: intersects instead of replacing the clip */
- (BOOL)containsPoint:(NSPoint)p { return CGPathContainsPoint(_p, NULL, p, _rule == NSWindingRuleEvenOdd); }
- (void)transformUsingAffineTransform:(id)t { }
@end

void NSRectFill(NSRect r) { CGContextFillRect(mw_cg(), r); }
void NSRectFillList(const NSRect *r, NSInteger n) { CGContextFillRects(mw_cg(), r, (size_t)n); }
void NSRectFillUsingOperation(NSRect r, NSCompositingOperation op) {
    CGContextRef c = mw_cg();
    if (op == NSCompositingOperationClear) { CGContextClearRect(c, r); return; }
    CGContextSaveGState(c);
    CGContextSetBlendMode(c, op == NSCompositingOperationCopy ? kCGBlendModeCopy : kCGBlendModeNormal);
    CGContextFillRect(c, r);
    CGContextRestoreGState(c);
}
void NSFrameRectWithWidth(NSRect r, CGFloat w) {
    if (r.size.width <= 0 || r.size.height <= 0) return;
    NSRect s[4] = {{r.origin, {r.size.width, w}}, {{r.origin.x, NSMaxY(r) - w}, {r.size.width, w}},
                   {{r.origin.x, r.origin.y + w}, {w, r.size.height - 2 * w}}, {{NSMaxX(r) - w, r.origin.y + w}, {w, r.size.height - 2 * w}}};
    CGContextFillRects(mw_cg(), s, 4);
}
void NSFrameRect(NSRect r) { NSFrameRectWithWidth(r, 1); }
void NSRectClip(NSRect r) { CGContextClipToRect(mw_cg(), r); }
void NSRectClipList(const NSRect *r, NSInteger n) { CGContextClipToRects(mw_cg(), r, (size_t)n); }
void NSEraseRect(NSRect r) { CGContextRef c = mw_cg(); CGContextSaveGState(c); CGContextSetGrayFillColor(c, 1, 1); CGContextFillRect(c, r); CGContextRestoreGState(c); }
void mw_fill_round(NSRect r, CGFloat radius, NSColor *col) {
    CGContextRef c = mw_cg();
    if (!c || !col) return;
    CGContextSaveGState(c);
    CGContextSetFillColorWithColor(c, col.CGColor);
    CGPathRef p = CGPathCreateWithRoundedRect(r, radius, radius, NULL);
    CGContextBeginPath(c); CGContextAddPath(c, p); CGContextFillPath(c);
    CGPathRelease(p);
    CGContextRestoreGState(c);
}
void mw_stroke_round(NSRect r, CGFloat radius, CGFloat width, NSColor *col) {
    CGContextRef c = mw_cg();
    if (!c || !col || width <= 0) return;
    CGContextSaveGState(c);
    CGContextSetStrokeColorWithColor(c, col.CGColor); CGContextSetLineWidth(c, width);
    CGPathRef p = CGPathCreateWithRoundedRect(NSInsetRect(r, width / 2, width / 2), fmax(0, radius - width / 2), fmax(0, radius - width / 2), NULL);
    CGContextBeginPath(c); CGContextAddPath(c, p); CGContextStrokePath(c);
    CGPathRelease(p);
    CGContextRestoreGState(c);
}

/* ======================================================================= text */
static uint32_t css_weight(NSFont *f) {
    CGFloat w = f.weight;
    return w <= -0.6 ? 200 : w <= -0.3 ? 300 : w < 0.2 ? 400 : w < 0.28 ? 500 : w < 0.35 ? 600 : w < 0.5 ? 700 : 800;
}
static NSFont *font_or_default(NSFont *f) { return f ? f : [NSFont systemFontOfSize:[NSFont systemFontSize]]; }
static MwText text_desc(NSFont *f, const char *utf8, CGFloat scale) {
    MwText t = {0};
    t.font = [f.fontName UTF8String]; t.text = utf8; t.size = (float)(f.pointSize * scale); t.weight = css_weight(f);
    t.flags = f.isFixedPitch ? UI_TEXT_MONO : 0;
    return t;
}
/* width, ascent, descent in points at the primary screen's scale (cached: layout asks for the same strings often) */
static void measure(NSString *s, NSFont *f, CGFloat out[3]) {
    static NSMutableDictionary *cache;
    f = font_or_default(f);
    NSString *k = [NSString stringWithFormat:@"%@\x1f%g\x1f%u\x1f%@", f.fontName, f.pointSize, css_weight(f), s];
    NSArray *hit = cache[k];
    if (hit) { for (int i = 0; i < 3; i++) out[i] = [hit[i] doubleValue]; return; }
    CGFloat sc = mw_scale0();
    MwText t = text_desc(f, [s UTF8String], sc);
    if (ui(UI_TEXT, U(&t), 0, 0, 0, 0) != 1) { out[0] = [s length] * f.pointSize * 0.55; out[1] = f.pointSize * 0.95; out[2] = f.pointSize * 0.25; }
    else { out[0] = t.width / sc; out[1] = t.ascent / sc; out[2] = t.descent / sc; }
    if (!cache || [cache count] > 4000) { [cache release]; cache = [[NSMutableDictionary alloc] init]; }
    cache[k] = @[@(out[0]), @(out[1]), @(out[2])];
}
static CGFloat width_of(NSString *s, NSFont *f) { CGFloat m[3]; measure(s, f, m); return m[0]; }
void mw_font_metrics(NSFont *f, CGFloat *ascent, CGFloat *descent) {
    CGFloat m[3]; measure(@"", f, m);
    if (ascent) *ascent = m[1];
    if (descent) *descent = m[2];
}
static CGFloat line_height(NSFont *f) { CGFloat a, d; mw_font_metrics(font_or_default(f), &a, &d); return a + d; }
static NSString *truncated(NSString *s, NSFont *f, CGFloat maxw) {
    if (width_of(s, f) <= maxw) return s;
    NSUInteger lo = 0, hi = [s length];
    while (lo < hi) { /* the longest prefix that fits with the ellipsis */
        NSUInteger mid = (lo + hi + 1) / 2;
        if (width_of([[s substringToIndex:mid] stringByAppendingString:@"…"], f) <= maxw) lo = mid; else hi = mid - 1;
    }
    return [[s substringToIndex:lo] stringByAppendingString:@"…"];
}
/* the lines a string breaks into: paragraphs at '\n', words wrapped greedily at maxw (> 0) */
static NSArray *text_lines(NSString *s, NSFont *f, CGFloat maxw, BOOL wrap, NSLineBreakMode lb) {
    NSMutableArray *out = [NSMutableArray array];
    BOOL trunc = lb == NSLineBreakByTruncatingTail || lb == NSLineBreakByTruncatingHead || lb == NSLineBreakByTruncatingMiddle;
    for (NSString *para in [s componentsSeparatedByString:@"\n"]) {
        if (!wrap || maxw <= 0 || trunc || lb == NSLineBreakByClipping) {
            [out addObject:trunc && maxw > 0 ? truncated(para, f, maxw) : para];
            continue;
        }
        NSString *line = nil;
        for (NSString *word in [para componentsSeparatedByString:@" "]) {
            NSString *cand = line ? [NSString stringWithFormat:@"%@ %@", line, word] : word;
            if (line && width_of(cand, f) > maxw) { [out addObject:line]; line = word; }
            else line = cand;
        }
        [out addObject:line ? line : @""];
    }
    return out;
}
NSSize mw_text_size_wrapped(NSString *s, NSFont *f, CGFloat maxw) {
    f = font_or_default(f);
    NSArray *lines = text_lines(s ? s : @"", f, maxw, maxw > 0, NSLineBreakByWordWrapping);
    CGFloat w = 0;
    for (NSString *l in lines) w = fmax(w, width_of(l, f));
    return NSMakeSize(ceil(w), ceil(line_height(f) * [lines count]));
}
NSSize mw_text_size(NSString *s, NSFont *f) { return mw_text_size_wrapped(s, f, 0); }
static void free_data(void *info, const void *data, size_t size) { free((void *)data); }
/* one line with its baseline's left end at p (user space), upright and on whole device pixels, in col (NULL: the
 * context's fill color) */
void mw_draw_text_line(CGContextRef c, NSString *s, NSFont *f, CGColorRef col, CGPoint p) {
    if (!c || ![s length]) return;
    CGAffineTransform m = CGContextGetCTM(c);
    CGFloat sc = sqrt(fabs(m.a * m.d - m.b * m.c));
    if (sc <= 0) return;
    MwText t = text_desc(f, [s UTF8String], sc);
    if (ui(UI_TEXT, U(&t), 0, 0, 0, 0) != 1 || !t.w || !t.h) return;
    t.mask = malloc((size_t)t.w * t.h);
    ui(UI_TEXT, U(&t), 0, 0, 0, 0);
    CGPoint d = CGPointApplyAffineTransform(p, m);
    CGRect r = CGRectMake(round(d.x) - t.pad, round(d.y) - t.descent, t.w, t.h);
    CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, t.mask, (size_t)t.w * t.h, free_data);
    CGImageRef img = CGImageCreate(t.w, t.h, 8, 8, t.w, NULL, kCGImageAlphaOnly, dp, NULL, false, 0);
    CGContextSaveGState(c);
    _mwCGContextSetCTM(c, CGAffineTransformIdentity);
    if (col) CGContextSetFillColorWithColor(c, col);
    CGContextDrawImage(c, r, img);
    CGContextRestoreGState(c);
    CGImageRelease(img); CGDataProviderRelease(dp);
}
static void draw_line(CGContextRef c, NSString *s, NSFont *f, NSColor *col, CGPoint p) { mw_draw_text_line(c, s, f, (col ? col : [NSColor blackColor]).CGColor, p); }
CGFloat mw_text_width(NSString *s, NSFont *f) { return width_of(s, font_or_default(f)); }
/* ---------------------------------------------------------------- glyphs (CoreText / CGContextShowGlyphs)
 * A glyph here is its UTF-16 character: fonts map characters to themselves. Each glyph's coverage mask is rendered once per
 * font, size and scale and drawn upright with the context's fill color at the text-space position (text matrix, then CTM). */
void *_mwCGContextFont(CGContextRef c); void _mwCGContextSetFont(CGContextRef c, void *f);
@interface _MWGlyph : NSObject { @public CGImageRef img; uint32_t w, h, pad; float descent; } @end
@implementation _MWGlyph - (void)dealloc { CGImageRelease(img); [super dealloc]; } @end
static _MWGlyph *glyph_mask(NSFont *f, unichar g, CGFloat sc) {
    static NSMutableDictionary *cache;
    NSString *k = [NSString stringWithFormat:@"%@\x1f%g\x1f%u", f.fontName, f.pointSize * sc, (unsigned)g];
    _MWGlyph *m = cache[k];
    if (m) return m;
    m = [[[_MWGlyph alloc] init] autorelease];
    char u8[8] = {0}; NSString *ch = [NSString stringWithCharacters:&g length:1];
    strncpy(u8, [ch UTF8String] ?: "", 7);
    MwText t = text_desc(f, u8, sc);
    if (g > ' ' && ui(UI_TEXT, U(&t), 0, 0, 0, 0) == 1 && t.w && t.h) {
        t.mask = malloc((size_t)t.w * t.h);
        ui(UI_TEXT, U(&t), 0, 0, 0, 0);
        CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, t.mask, (size_t)t.w * t.h, free_data);
        m->img = CGImageCreate(t.w, t.h, 8, 8, t.w, NULL, kCGImageAlphaOnly, dp, NULL, false, 0);
        CGDataProviderRelease(dp);
        m->w = t.w; m->h = t.h; m->pad = t.pad; m->descent = t.descent;
    }
    if (!cache || [cache count] > 8000) { [cache release]; cache = [[NSMutableDictionary alloc] init]; }
    cache[k] = m;
    return m;
}
static void draw_glyphs(CGContextRef c, NSFont *f, const CGGlyph *gl, const CGPoint *pos, size_t n) {
    if (!c || !n) return;
    f = font_or_default(f);
    CGAffineTransform tm = CGContextGetTextMatrix(c), m = CGAffineTransformConcat(tm, CGContextGetCTM(c));
    CGFloat sc = sqrt(fabs(m.a * m.d - m.b * m.c));
    if (sc <= 0) return;
    CGContextSaveGState(c);
    CGAffineTransform ctm = CGContextGetCTM(c);
    _mwCGContextSetCTM(c, CGAffineTransformIdentity);
    for (size_t i = 0; i < n; i++) {
        _MWGlyph *g = glyph_mask(f, gl[i], sc);
        if (!g->img) continue;
        CGPoint d = CGPointApplyAffineTransform(CGPointApplyAffineTransform(pos[i], tm), ctm);
        CGContextDrawImage(c, CGRectMake(round(d.x) - g->pad, round(d.y) - g->descent, g->w, g->h), g->img);
    }
    CGContextRestoreGState(c);
}
static CGFloat glyph_advance(NSFont *f, CGGlyph g) { return width_of([NSString stringWithCharacters:&g length:1], font_or_default(f)); }
@implementation NSFont (MWGlyphs)
- (void)getAdvancements:(NSSizeArray)adv forGlyphs:(const NSGlyph *)g count:(NSUInteger)n { for (NSUInteger i = 0; i < n; i++) adv[i] = NSMakeSize(glyph_advance(self, (CGGlyph)g[i]), 0); }
- (void)getAdvancements:(NSSizeArray)adv forCGGlyphs:(const CGGlyph *)g count:(NSUInteger)n { for (NSUInteger i = 0; i < n; i++) adv[i] = NSMakeSize(glyph_advance(self, g[i]), 0); }
- (NSSize)advancementForGlyph:(NSGlyph)g { return NSMakeSize(glyph_advance(self, (CGGlyph)g), 0); }
- (NSSize)advancementForCGGlyph:(CGGlyph)g { return NSMakeSize(glyph_advance(self, g), 0); }
- (NSRect)boundingRectForGlyph:(NSGlyph)g { CGFloat a, d; mw_font_metrics(self, &a, &d); return NSMakeRect(0, -d, glyph_advance(self, (CGGlyph)g), a + d); }
- (NSRect)boundingRectForCGGlyph:(CGGlyph)g { return [self boundingRectForGlyph:g]; }
- (NSGlyph)glyphWithName:(NSString *)n { return [n length] == 1 ? [n characterAtIndex:0] : 0; }
- (void)set { _mwCGContextSetFont(mw_cg(), self); }
- (void)setInContext:(NSGraphicsContext *)c { _mwCGContextSetFont((CGContextRef)[c CGContext], self); }
@end
/* CoreText on NSFont (CTFontRef is toll-free bridged with NSFont, as on macOS); layout is in coretext.m */
CTFontRef CTFontCreateWithName(CFStringRef n, CGFloat size, const CGAffineTransform *m) {
    if (size <= 0) size = 12;
    NSFont *f = n ? [NSFont fontWithName:(NSString *)n size:size] : nil;
    if (!f) f = [(NSString *)n rangeOfString:@"Mono"].location != NSNotFound || [(NSString *)n rangeOfString:@"Menlo"].location != NSNotFound || [(NSString *)n rangeOfString:@"Courier"].location != NSNotFound
        ? [NSFont userFixedPitchFontOfSize:size] : [NSFont systemFontOfSize:size];
    return (CTFontRef)[f retain];
}
CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef d, CGFloat size, const CGAffineTransform *m) { return (CTFontRef)[[NSFont fontWithDescriptor:(NSFontDescriptor *)d size:size] ?: [NSFont systemFontOfSize:size] retain]; }
CTFontRef CTFontCreateCopyWithAttributes(CTFontRef f, CGFloat size, const CGAffineTransform *m, CTFontDescriptorRef d) {
    NSFontDescriptor *fd = d ? [[(NSFont *)f fontDescriptor] fontDescriptorByAddingAttributes:[(NSFontDescriptor *)d fontAttributes]] : [(NSFont *)f fontDescriptor];
    return (CTFontRef)[[NSFont fontWithDescriptor:fd size:size > 0 ? size : [(NSFont *)f pointSize]] ?: (NSFont *)f retain];
}
CTFontRef CTFontCreateForString(CTFontRef f, CFStringRef s, CFRange r) { return (CTFontRef)[(NSFont *)f retain]; } /* every character is "in" every font */
CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType type, CGFloat size, CFStringRef lang) {
    CGFloat s = size > 0 ? size : type == kCTFontUIFontSmallSystem || type == kCTFontUIFontSmallEmphasizedSystem || type == kCTFontUIFontToolTip ? 11
              : type == kCTFontUIFontMiniSystem || type == kCTFontUIFontMiniEmphasizedSystem ? 9 : 13;
    NSFont *f = type == kCTFontUIFontUserFixedPitch ? [NSFont userFixedPitchFontOfSize:s]
              : type == kCTFontUIFontEmphasizedSystem || type == kCTFontUIFontSmallEmphasizedSystem || type == kCTFontUIFontMiniEmphasizedSystem
                || type == kCTFontUIFontEmphasizedSystemDetail || type == kCTFontUIFontAlertHeader ? [NSFont boldSystemFontOfSize:s]
              : type == kCTFontUIFontUser ? [NSFont userFontOfSize:s] : [NSFont systemFontOfSize:s];
    return (CTFontRef)[f retain];
}
CFCharacterSetRef CTFontCopyCharacterSet(CTFontRef f) {
    NSMutableCharacterSet *cs = [[NSMutableCharacterSet alloc] init];
    [cs addCharactersInRange:NSMakeRange(0x20, 0xD800 - 0x20)]; [cs addCharactersInRange:NSMakeRange(0xE000, 0x10000 - 0xE000)];
    return (CFCharacterSetRef)cs;
}
bool CTFontGetGlyphsForCharacters(CTFontRef f, const UniChar ch[], CGGlyph g[], CFIndex n) { for (CFIndex i = 0; i < n; i++) g[i] = ch[i]; return true; }
double CTFontGetAdvancesForGlyphs(CTFontRef f, CTFontOrientation orientation, const CGGlyph g[], CGSize *adv, CFIndex n) {
    double total = 0;
    for (CFIndex i = 0; i < n; i++) { CGFloat a = glyph_advance((NSFont *)f, g[i]); if (adv) adv[i] = CGSizeMake(a, 0); total += a; }
    return total;
}
CGRect CTFontGetBoundingRectsForGlyphs(CTFontRef f, CTFontOrientation o, const CGGlyph g[], CGRect *rects, CFIndex n) {
    CGRect all = CGRectNull;
    for (CFIndex i = 0; i < n; i++) { CGRect r = [(NSFont *)f boundingRectForGlyph:g[i]]; if (rects) rects[i] = r; all = CGRectUnion(all, r); }
    return all;
}
CGFloat CTFontGetAscent(CTFontRef f) { CGFloat a, d; mw_font_metrics((NSFont *)f, &a, &d); return a; }
CGFloat CTFontGetDescent(CTFontRef f) { CGFloat a, d; mw_font_metrics((NSFont *)f, &a, &d); return d; }
CGFloat CTFontGetLeading(CTFontRef f) { return 0; }
CGFloat CTFontGetSize(CTFontRef f) { return [(NSFont *)f pointSize]; }
CGFloat CTFontGetCapHeight(CTFontRef f) { return [(NSFont *)f capHeight]; }
CGFloat CTFontGetXHeight(CTFontRef f) { return [(NSFont *)f xHeight]; }
CGFloat CTFontGetUnderlinePosition(CTFontRef f) { return -CTFontGetDescent(f) / 2; }
CGFloat CTFontGetUnderlineThickness(CTFontRef f) { return 1; }
CFStringRef CTFontCopyPostScriptName(CTFontRef f) { return (CFStringRef)[[(NSFont *)f fontName] copy]; }
CFStringRef CTFontCopyFamilyName(CTFontRef f) { return (CFStringRef)[[(NSFont *)f familyName] copy]; }
CFStringRef CTFontCopyFullName(CTFontRef f) { return (CFStringRef)[[(NSFont *)f displayName] copy]; }
CFStringRef CTFontCopyDisplayName(CTFontRef f) { return (CFStringRef)[[(NSFont *)f displayName] copy]; }
void CTFontDrawGlyphs(CTFontRef f, const CGGlyph g[], const CGPoint pos[], size_t n, CGContextRef c) { draw_glyphs(c, (NSFont *)f, g, pos, n); }
void CGContextShowGlyphsAtPositions(CGContextRef c, const CGGlyph *g, const CGPoint *pos, size_t n) { draw_glyphs(c, _mwCGContextFont(c), g, pos, n); }
void CGContextShowGlyphsWithAdvances(CGContextRef c, const CGGlyph *g, const CGSize *adv, size_t n) {
    if (!c || !n) return;
    CGPoint *pos = malloc(n * sizeof *pos), p = CGPointZero;  /* text space, from the text position (the matrix's translation) */
    for (size_t i = 0; i < n; i++) { pos[i] = p; p.x += adv[i].width; p.y += adv[i].height; }
    draw_glyphs(c, _mwCGContextFont(c), g, pos, n);
    CGPoint end = CGPointApplyAffineTransform(p, CGContextGetTextMatrix(c));
    CGContextSetTextPosition(c, end.x, end.y);
    free(pos);
}
void CGContextShowGlyphs(CGContextRef c, const CGGlyph *g, size_t n) {
    CGSize *adv = malloc((n ? n : 1) * sizeof *adv);
    for (size_t i = 0; i < n; i++) adv[i] = CGSizeMake(glyph_advance(_mwCGContextFont(c), g[i]), 0);
    CGContextShowGlyphsWithAdvances(c, g, adv, n);
    free(adv);
}

void mw_draw_text_in(NSString *s, NSRect r, NSFont *f, NSColor *col, NSTextAlignment a, NSLineBreakMode lb, BOOL wrap, BOOL vcenter) {
    CGContextRef c = mw_cg();
    if (!c || ![s length]) return;
    f = font_or_default(f);
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    NSArray *lines = text_lines(s, f, r.size.width, wrap, lb);
    CGFloat asc, desc; mw_font_metrics(f, &asc, &desc);
    CGFloat lh = asc + desc, block = lh * [lines count], top = vcenter ? (r.size.height - block) / 2 : 0;
    for (NSUInteger i = 0; i < [lines count]; i++) {
        NSString *l = lines[i];
        CGFloat w = width_of(l, f), x = r.origin.x;
        if (a == NSTextAlignmentCenter) x += (r.size.width - w) / 2;
        else if (a == NSTextAlignmentRight) x += r.size.width - w;
        CGFloat down = top + asc + lh * i; /* from the top of the rect to this baseline */
        draw_line(c, l, f, col, CGPointMake(x, flipped ? r.origin.y + down : NSMaxY(r) - down));
    }
}
typedef struct { NSFont *font; NSColor *color; NSParagraphStyle *style; } Attrs;
static Attrs attrs(NSDictionary *a) {
    Attrs t = {a[NSFontAttributeName], a[NSForegroundColorAttributeName], a[NSParagraphStyleAttributeName]};
    if (!t.font) t.font = [NSFont fontWithName:@"Helvetica" size:12];
    if (!t.color) t.color = [NSColor blackColor];
    return t;
}
static void draw_at(NSString *s, NSPoint p, NSDictionary *a) {
    Attrs t = attrs(a);
    NSSize sz = mw_text_size(s, t.font);
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    NSRect r = NSMakeRect(p.x, flipped ? p.y : p.y, sz.width + 1, sz.height); /* the origin is the top-left (flipped) or bottom-left */
    mw_draw_text_in(s, r, t.font, t.color, t.style ? t.style.alignment : NSTextAlignmentLeft, NSLineBreakByClipping, NO, NO);
}
static void draw_in(NSString *s, NSRect r, NSDictionary *a) {
    Attrs t = attrs(a);
    NSLineBreakMode lb = t.style ? t.style.lineBreakMode : NSLineBreakByWordWrapping;
    mw_draw_text_in(s, r, t.font, t.color, t.style ? t.style.alignment : NSTextAlignmentLeft, lb, YES, NO);
}
static NSRect bounding(NSString *s, NSSize size, NSStringDrawingOptions o, NSDictionary *a) {
    Attrs t = attrs(a);
    NSSize z = (o & NSStringDrawingUsesLineFragmentOrigin) ? mw_text_size_wrapped(s, t.font, size.width) : mw_text_size(s, t.font);
    return NSMakeRect(0, 0, z.width, z.height);
}
@implementation NSString (AppKitDrawing)
- (NSSize)sizeWithAttributes:(NSDictionary *)a { return mw_text_size(self, attrs(a).font); }
- (void)drawAtPoint:(NSPoint)p withAttributes:(NSDictionary *)a { draw_at(self, p, a); }
- (void)drawInRect:(NSRect)r withAttributes:(NSDictionary *)a { draw_in(self, r, a); }
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSStringDrawingOptions)o attributes:(NSDictionary *)a { return bounding(self, s, o, a); }
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSStringDrawingOptions)o attributes:(NSDictionary *)a context:(id)c { return bounding(self, s, o, a); }
- (void)drawWithRect:(NSRect)r options:(NSStringDrawingOptions)o attributes:(NSDictionary *)a { draw_in(self, r, a); }
- (void)drawWithRect:(NSRect)r options:(NSStringDrawingOptions)o attributes:(NSDictionary *)a context:(id)c { draw_in(self, r, a); }
@end
/* attributed strings keep their runs: laid out by coretext.m */
@implementation NSAttributedString (AppKitDrawing)
- (NSSize)size { return mw_attr_size(self, 0); }
- (void)drawAtPoint:(NSPoint)p { NSSize z = mw_attr_size(self, 0); mw_attr_draw(self, NSMakeRect(p.x, p.y, z.width + 1, z.height), NO); }
- (void)drawInRect:(NSRect)r { mw_attr_draw(self, r, YES); }
static NSRect attr_bounding(NSAttributedString *s, NSSize size, NSStringDrawingOptions o) {
    NSSize z = mw_attr_size(s, (o & NSStringDrawingUsesLineFragmentOrigin) ? size.width : 0);
    return NSMakeRect(0, 0, z.width, z.height);
}
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSStringDrawingOptions)o { return attr_bounding(self, s, o); }
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSStringDrawingOptions)o context:(id)c { return attr_bounding(self, s, o); }
- (void)drawWithRect:(NSRect)r options:(NSStringDrawingOptions)o { mw_attr_draw(self, r, (o & NSStringDrawingUsesLineFragmentOrigin) != 0); }
- (void)drawWithRect:(NSRect)r options:(NSStringDrawingOptions)o context:(id)c { mw_attr_draw(self, r, (o & NSStringDrawingUsesLineFragmentOrigin) != 0); }
@end
/* ======================================================================= images */
@implementation NSImageRep
- (BOOL)draw { return NO; }
- (BOOL)drawInRect:(NSRect)r { return NO; }
- (BOOL)drawAtPoint:(NSPoint)p { return [self drawInRect:NSMakeRect(p.x, p.y, self.size.width, self.size.height)]; }
- (BOOL)hasAlpha { return YES; }
- (NSInteger)bitsPerSample { return 8; }
@end
/* pixels: 8 bits per sample, RGBA (or RGB / gray), alpha premultiplied and last, like AppKit's default */
@implementation NSBitmapImageRep { unsigned char *_data; NSInteger _bpr, _bpp, _spp, _bps; BOOL _owns, _alpha; CGImageRef _cg; }
- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:(NSInteger)bps
    samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)a isPlanar:(BOOL)p colorSpaceName:(NSString *)cs bytesPerRow:(NSInteger)bpr bitsPerPixel:(NSInteger)bpp {
    if (!(self = [super init])) return nil;
    if (w <= 0 || h <= 0 || p) { [self release]; return nil; }
    self.pixelsWide = w; self.pixelsHigh = h; self.size = NSMakeSize(w, h);
    _spp = spp; _bps = bps ? bps : 8; _alpha = a; _bpp = bpp ? bpp : _bps * spp; _bpr = bpr ? bpr : (w * _bpp + 7) / 8;
    if (planes && planes[0]) _data = planes[0];
    else { _data = calloc((size_t)(_bpr * h), 1); _owns = YES; }
    return self;
}
- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:(NSInteger)bps
    samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)a isPlanar:(BOOL)p colorSpaceName:(NSString *)cs bitmapFormat:(NSBitmapFormat)f
    bytesPerRow:(NSInteger)bpr bitsPerPixel:(NSInteger)bpp {
    return [self initWithBitmapDataPlanes:planes pixelsWide:w pixelsHigh:h bitsPerSample:bps samplesPerPixel:spp hasAlpha:a isPlanar:p colorSpaceName:cs bytesPerRow:bpr bitsPerPixel:bpp];
}
- (instancetype)_mwInitWidth:(size_t)w height:(size_t)h {
    return [self initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                 isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:32];
}
/* host pixels (BGRA premultiplied) -> RGBA premultiplied */
- (instancetype)_mwInitBGRA:(const uint8_t *)px width:(size_t)w height:(size_t)h {
    if (!(self = [self _mwInitWidth:w height:h])) return nil;
    for (size_t i = 0, n = w * h; i < n; i++) { _data[i * 4] = px[i * 4 + 2]; _data[i * 4 + 1] = px[i * 4 + 1]; _data[i * 4 + 2] = px[i * 4]; _data[i * 4 + 3] = px[i * 4 + 3]; }
    return self;
}
- (instancetype)initWithCGImage:(CGImageRef)i {
    if (!i || !(self = [self _mwInitWidth:CGImageGetWidth(i) height:CGImageGetHeight(i)])) { [self release]; return nil; }
    CGContextRef c = [self _mwNewCGContext];
    CGContextSetBlendMode(c, kCGBlendModeCopy);
    CGContextDrawImage(c, CGRectMake(0, 0, CGImageGetWidth(i), CGImageGetHeight(i)), i);
    CGContextRelease(c);
    return self;
}
- (instancetype)initWithData:(NSData *)d {
    MwImage img = {0};
    if (!d || ui(UI_IMAGE_DECODE, U([d bytes]), [d length], U(&img), 0, 0) != 1) { [self release]; return nil; }
    self = [self _mwInitBGRA:img.pixels width:img.w height:img.h];
    ui(UI_FREE, U(img.pixels), 0, 0, 0, 0);
    return self;
}
+ (instancetype)imageRepWithData:(NSData *)d { return [[[self alloc] initWithData:d] autorelease]; }
+ (NSArray *)imageRepsWithData:(NSData *)d { id r = [self imageRepWithData:d]; return r ? @[r] : @[]; }
+ (instancetype)imageRepWithContentsOfFile:(NSString *)f { return [self imageRepWithData:[NSData dataWithContentsOfFile:f]]; }
- (instancetype)initForIncrementalLoad { return [self _mwInitWidth:1 height:1]; }
- (void)dealloc { if (_owns) free(_data); CGImageRelease(_cg); [super dealloc]; }
- (unsigned char *)bitmapData { return _data; }
- (NSInteger)bytesPerRow { return _bpr; }
- (NSInteger)bitsPerPixel { return _bpp; }
- (NSInteger)samplesPerPixel { return _spp; }
- (NSInteger)bitsPerSample { return _bps; }
- (BOOL)hasAlpha { return _alpha; }
- (BOOL)isPlanar { return NO; }
- (NSBitmapFormat)bitmapFormat { return 0; }
- (uint32_t)_mwInfo { return _spp == 1 ? kCGImageAlphaNone : _alpha ? kCGImageAlphaPremultipliedLast : _bpp == 32 ? kCGImageAlphaNoneSkipLast : kCGImageAlphaNone; }
- (CGContextRef)_mwNewCGContext {
    CGColorSpaceRef cs = _spp == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(_data, (size_t)self.pixelsWide, (size_t)self.pixelsHigh, (size_t)_bps, (size_t)_bpr, cs, [self _mwInfo]);
    CGColorSpaceRelease(cs);
    if (c && (self.size.width != self.pixelsWide || self.size.height != self.pixelsHigh)) /* points -> pixels */
        CGContextScaleCTM(c, self.pixelsWide / self.size.width, self.pixelsHigh / self.size.height);
    return c;
}
- (CGImageRef)CGImage { /* a snapshot of the pixels as they are now */
    CGImageRelease(_cg);
    NSData *d = [[NSData alloc] initWithBytes:_data length:(NSUInteger)(_bpr * self.pixelsHigh)];
    CGDataProviderRef p = CGDataProviderCreateWithCFData((CFTypeRef)d);
    CGColorSpaceRef cs = _spp == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB();
    _cg = CGImageCreate((size_t)self.pixelsWide, (size_t)self.pixelsHigh, (size_t)_bps, (size_t)_bpp, (size_t)_bpr, cs, [self _mwInfo], p, NULL, true, 0);
    CGColorSpaceRelease(cs); CGDataProviderRelease(p); [d release];
    return _cg;
}
- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y {
    if (x < 0 || y < 0 || x >= self.pixelsWide || y >= self.pixelsHigh || _bps != 8) return nil;
    const uint8_t *p = _data + y * _bpr + x * (_bpp / 8);
    if (_spp < 3) return [NSColor colorWithWhite:p[0] / 255.0 alpha:_alpha ? p[1] / 255.0 : 1];
    CGFloat a = _alpha ? p[3] / 255.0 : 1, k = a > 0 ? 1 / a : 0;
    return [NSColor colorWithRed:p[0] / 255.0 * k green:p[1] / 255.0 * k blue:p[2] / 255.0 * k alpha:a];
}
- (void)setColor:(NSColor *)c atX:(NSInteger)x y:(NSInteger)y {
    if (x < 0 || y < 0 || x >= self.pixelsWide || y >= self.pixelsHigh || _bps != 8 || _spp < 3) return;
    uint8_t *p = _data + y * _bpr + x * (_bpp / 8);
    CGFloat r, g, b, a; [c getRed:&r green:&g blue:&b alpha:&a];
    if (!_alpha) a = 1;
    p[0] = (uint8_t)lround(r * a * 255); p[1] = (uint8_t)lround(g * a * 255); p[2] = (uint8_t)lround(b * a * 255);
    if (_alpha) p[3] = (uint8_t)lround(a * 255);
}
/* encoded by the host (WIC) from BGRA premultiplied */
- (NSData *)representationUsingType:(NSBitmapImageFileType)t properties:(NSDictionary *)props {
    size_t w = (size_t)self.pixelsWide, h = (size_t)self.pixelsHigh;
    uint8_t *px = malloc(w * h * 4);
    for (size_t y = 0; y < h; y++) for (size_t x = 0; x < w; x++) {
        const uint8_t *s = _data + y * _bpr + x * (_bpp / 8);
        uint8_t *d = px + (y * w + x) * 4;
        if (_spp < 3) { d[0] = d[1] = d[2] = s[0]; d[3] = _alpha ? s[1] : 255; }
        else { d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; d[3] = _alpha ? s[3] : 255; }
    }
    MwImage img = {(uint32_t)w, (uint32_t)h, px};
    int type = t == NSBitmapImageFileTypeJPEG || t == NSBitmapImageFileTypeJPEG2000 ? UI_IMG_JPEG : t == NSBitmapImageFileTypeBMP ? UI_IMG_BMP
             : t == NSBitmapImageFileTypeTIFF ? UI_IMG_TIFF : t == NSBitmapImageFileTypeGIF ? UI_IMG_GIF : UI_IMG_PNG;
    float q = props[NSImageCompressionFactor] ? [props[NSImageCompressionFactor] floatValue] : 0.9f;
    uint64_t qbits = 0; memcpy(&qbits, &q, sizeof q);
    uint64_t size = 0;
    void *out = (void *)(uintptr_t)ui(UI_IMAGE_ENCODE, U(&img), (uint64_t)type, qbits, U(&size), 0);
    free(px);
    if (!out) return nil;
    NSData *d = [NSData dataWithBytes:out length:size];
    ui(UI_FREE, U(out), 0, 0, 0, 0);
    return d;
}
+ (NSData *)representationOfImageRepsInArray:(NSArray *)reps usingType:(NSBitmapImageFileType)t properties:(NSDictionary *)p {
    return [[reps firstObject] representationUsingType:t properties:p];
}
- (NSData *)TIFFRepresentation { return [self representationUsingType:NSBitmapImageFileTypeTIFF properties:@{}]; }
- (BOOL)drawInRect:(NSRect)r {
    CGContextRef c = mw_cg();
    if (!c) return NO;
    CGContextDrawImage(c, r, [self CGImage]);
    return YES;
}
- (BOOL)draw { return [self drawInRect:NSMakeRect(0, 0, self.size.width, self.size.height)]; }
@end

/* SF Symbols stand-ins: simple line drawings of the common ones, in a unit square (y up) */
static void sym_line(CGContextRef c, const CGFloat *p, int n) {
    CGContextBeginPath(c); CGContextMoveToPoint(c, p[0], p[1]);
    for (int i = 1; i < n; i++) CGContextAddLineToPoint(c, p[2 * i], p[2 * i + 1]);
    CGContextStrokePath(c);
}
static void sym_fill(CGContextRef c, const CGFloat *p, int n) {
    CGContextBeginPath(c); CGContextMoveToPoint(c, p[0], p[1]);
    for (int i = 1; i < n; i++) CGContextAddLineToPoint(c, p[2 * i], p[2 * i + 1]);
    CGContextClosePath(c); CGContextFillPath(c);
}
static void draw_symbol(CGContextRef c, NSString *name, CGRect r, NSColor *col) {
    CGFloat side = fmin(r.size.width, r.size.height);
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, r.origin.x + (r.size.width - side) / 2, r.origin.y + (r.size.height - side) / 2);
    CGContextScaleCTM(c, side, side);
    CGContextSetFillColorWithColor(c, col.CGColor); CGContextSetStrokeColorWithColor(c, col.CGColor);
    CGContextSetLineWidth(c, 0.1); CGContextSetLineCap(c, kCGLineCapRound); CGContextSetLineJoin(c, kCGLineJoinRound);
    BOOL fill = [name hasSuffix:@".fill"];
    NSString *base = fill ? [name substringToIndex:[name length] - 5] : name;
    if ([base hasPrefix:@"slider.horizontal"]) {
        CGFloat ys[3] = {0.78, 0.5, 0.22}, ks[3] = {0.62, 0.32, 0.55};
        for (int i = 0; i < 3; i++) {
            CGFloat l[4] = {0.1, ys[i], 0.9, ys[i]}; sym_line(c, l, 2);
            CGContextFillEllipseInRect(c, CGRectMake(ks[i] - 0.1, ys[i] - 0.1, 0.2, 0.2));
        }
    } else if ([base isEqualToString:@"chevron.down"]) { CGFloat l[6] = {0.2, 0.64, 0.5, 0.34, 0.8, 0.64}; sym_line(c, l, 3); }
    else if ([base isEqualToString:@"chevron.up"]) { CGFloat l[6] = {0.2, 0.36, 0.5, 0.66, 0.8, 0.36}; sym_line(c, l, 3); }
    else if ([base isEqualToString:@"chevron.left"]) { CGFloat l[6] = {0.64, 0.2, 0.34, 0.5, 0.64, 0.8}; sym_line(c, l, 3); }
    else if ([base isEqualToString:@"chevron.right"]) { CGFloat l[6] = {0.36, 0.2, 0.66, 0.5, 0.36, 0.8}; sym_line(c, l, 3); }
    else if ([base isEqualToString:@"chevron.up.chevron.down"]) {
        CGFloat a[6] = {0.32, 0.6, 0.5, 0.8, 0.68, 0.6}, b[6] = {0.32, 0.4, 0.5, 0.2, 0.68, 0.4}; sym_line(c, a, 3); sym_line(c, b, 3);
    } else if ([base hasPrefix:@"xmark"]) { CGFloat a[4] = {0.25, 0.25, 0.75, 0.75}, b[4] = {0.25, 0.75, 0.75, 0.25}; sym_line(c, a, 2); sym_line(c, b, 2); }
    else if ([base isEqualToString:@"plus"]) { CGFloat a[4] = {0.5, 0.2, 0.5, 0.8}, b[4] = {0.2, 0.5, 0.8, 0.5}; sym_line(c, a, 2); sym_line(c, b, 2); }
    else if ([base isEqualToString:@"minus"]) { CGFloat a[4] = {0.2, 0.5, 0.8, 0.5}; sym_line(c, a, 2); }
    else if ([base hasPrefix:@"checkmark"]) {
        if ([base hasSuffix:@".circle"]) {
            if (fill) { CGContextFillEllipseInRect(c, CGRectMake(0.08, 0.08, 0.84, 0.84)); CGContextSetStrokeColorWithColor(c, [NSColor whiteColor].CGColor); }
            else CGContextStrokeEllipseInRect(c, CGRectMake(0.1, 0.1, 0.8, 0.8));
            CGFloat a[6] = {0.3, 0.5, 0.45, 0.34, 0.72, 0.66}; sym_line(c, a, 3);
        } else { CGFloat a[6] = {0.2, 0.5, 0.42, 0.26, 0.82, 0.74}; sym_line(c, a, 3); }
    }
    else if ([base hasPrefix:@"play"]) { CGFloat a[6] = {0.28, 0.18, 0.28, 0.82, 0.82, 0.5}; sym_fill(c, a, 3); }
    else if ([base hasPrefix:@"pause"]) { CGContextFillRect(c, CGRectMake(0.26, 0.2, 0.16, 0.6)); CGContextFillRect(c, CGRectMake(0.58, 0.2, 0.16, 0.6)); }
    else if ([base hasPrefix:@"stop"]) { CGContextFillRect(c, CGRectMake(0.24, 0.24, 0.52, 0.52)); }
    else if ([base hasPrefix:@"gear"]) {
        CGContextSetLineWidth(c, 0.14); CGContextStrokeEllipseInRect(c, CGRectMake(0.27, 0.27, 0.46, 0.46));
        for (int i = 0; i < 8; i++) { CGFloat a = i * M_PI / 4, l[4] = {0.5 + 0.3 * cos(a), 0.5 + 0.3 * sin(a), 0.5 + 0.42 * cos(a), 0.5 + 0.42 * sin(a)}; sym_line(c, l, 2); }
    } else if ([base hasPrefix:@"speaker"]) {
        CGFloat a[12] = {0.12, 0.38, 0.3, 0.38, 0.52, 0.18, 0.52, 0.82, 0.3, 0.62, 0.12, 0.62}; sym_fill(c, a, 6);
        if ([base rangeOfString:@"slash"].location != NSNotFound) { CGFloat l[4] = {0.62, 0.36, 0.88, 0.64}; sym_line(c, l, 2); }
        else { CGContextBeginPath(c); CGContextAddArc(c, 0.52, 0.5, 0.24, -0.8, 0.8, 0); CGContextStrokePath(c); }
    } else if ([base hasPrefix:@"gamecontroller"]) {
        CGContextSetLineWidth(c, 0.09);
        CGPathRef p = CGPathCreateWithRoundedRect(CGRectMake(0.1, 0.28, 0.8, 0.44), 0.2, 0.2, NULL);
        CGContextAddPath(c, p); if (fill) CGContextFillPath(c); else CGContextStrokePath(c); CGPathRelease(p);
    } else if ([base hasPrefix:@"magnifyingglass"]) {
        CGContextStrokeEllipseInRect(c, CGRectMake(0.16, 0.36, 0.46, 0.46)); CGFloat l[4] = {0.56, 0.42, 0.84, 0.14}; sym_line(c, l, 2);
    } else if ([base hasPrefix:@"clock"]) {
        CGContextStrokeEllipseInRect(c, CGRectMake(0.12, 0.12, 0.76, 0.76)); CGFloat l[6] = {0.5, 0.72, 0.5, 0.5, 0.66, 0.4}; sym_line(c, l, 3);
    } else if ([base hasPrefix:@"ellipsis"]) {
        for (int i = 0; i < 3; i++) CGContextFillEllipseInRect(c, CGRectMake(0.14 + i * 0.28, 0.43, 0.14, 0.14));
    } else if ([base hasPrefix:@"calendar"]) {
        CGContextSetLineWidth(c, 0.08); CGContextStrokeRect(c, CGRectMake(0.14, 0.14, 0.72, 0.66)); CGContextFillRect(c, CGRectMake(0.14, 0.62, 0.72, 0.18));
        if ([base rangeOfString:@"exclamationmark"].location != NSNotFound) { CGFloat l[4] = {0.5, 0.5, 0.5, 0.32}; sym_line(c, l, 2); CGContextFillEllipseInRect(c, CGRectMake(0.46, 0.18, 0.08, 0.08)); }
    } else if ([base hasPrefix:@"flag"]) {
        CGFloat pole[4] = {0.24, 0.1, 0.24, 0.88}, f[8] = {0.24, 0.88, 0.8, 0.76, 0.24, 0.52, 0.24, 0.88};
        sym_line(c, pole, 2); if (fill) sym_fill(c, f, 3); else sym_line(c, f, 4);
    } else if ([base hasPrefix:@"trash"]) {
        CGContextSetLineWidth(c, 0.08); CGFloat b[8] = {0.24, 0.72, 0.3, 0.12, 0.7, 0.12, 0.76, 0.72}, t[4] = {0.14, 0.76, 0.86, 0.76}, h[8] = {0.38, 0.76, 0.4, 0.88, 0.6, 0.88, 0.62, 0.76};
        sym_line(c, b, 4); sym_line(c, t, 2); sym_line(c, h, 4);
    } else if ([base hasPrefix:@"pencil"]) {
        CGFloat l[4] = {0.2, 0.2, 0.78, 0.78}; CGContextSetLineWidth(c, 0.16); sym_line(c, l, 2);
    } else if ([base hasPrefix:@"link"]) {
        CGContextSetLineWidth(c, 0.08);
        CGContextTranslateCTM(c, 0.5, 0.5); CGContextRotateCTM(c, M_PI / 4); CGContextTranslateCTM(c, -0.5, -0.5);
        CGPathRef a = CGPathCreateWithRoundedRect(CGRectMake(0.1, 0.38, 0.46, 0.24), 0.12, 0.12, NULL), b = CGPathCreateWithRoundedRect(CGRectMake(0.44, 0.38, 0.46, 0.24), 0.12, 0.12, NULL);
        CGContextAddPath(c, a); CGContextAddPath(c, b); CGContextStrokePath(c); CGPathRelease(a); CGPathRelease(b);
    } else if ([base hasPrefix:@"list"] || [base hasPrefix:@"checklist"] || [base hasPrefix:@"line.horizontal.3"] || [base hasPrefix:@"text.alignleft"]) {
        BOOL bullets = [base hasPrefix:@"list"] || [base hasPrefix:@"checklist"], decr = [base rangeOfString:@"decrease"].location != NSNotFound;
        for (int i = 0; i < 3; i++) {
            CGFloat y = 0.74 - i * 0.24, x0 = bullets ? 0.36 : 0.14 + (decr ? i * 0.12 : 0), x1 = bullets ? 0.86 : 0.86 - (decr ? i * 0.12 : 0);
            CGFloat l[4] = {x0, y, x1, y}; sym_line(c, l, 2);
            if (bullets) CGContextFillEllipseInRect(c, CGRectMake(0.1, y - 0.06, 0.12, 0.12));
        }
    } else if ([base hasPrefix:@"tray"] || [base hasPrefix:@"folder"] || [base hasPrefix:@"text.below.folder"]) {
        CGContextSetLineWidth(c, 0.08);
        CGFloat t[12] = {0.1, 0.2, 0.1, 0.7, 0.36, 0.7, 0.44, 0.6, 0.9, 0.6, 0.9, 0.2};
        if ([base hasPrefix:@"tray"]) { CGFloat u[12] = {0.1, 0.5, 0.1, 0.2, 0.9, 0.2, 0.9, 0.5, 0.64, 0.5, 0.36, 0.5}; sym_line(c, u, 6); }
        else { sym_line(c, t, 6); CGFloat cl[4] = {0.9, 0.2, 0.1, 0.2}; sym_line(c, cl, 2); }
    } else if ([base hasPrefix:@"keyboard"] || [base hasPrefix:@"dock"]) {
        CGContextSetLineWidth(c, 0.08); CGContextStrokeRect(c, CGRectMake(0.1, 0.26, 0.8, 0.48));
        CGFloat l[4] = {0.3, 0.38, 0.7, 0.38}; sym_line(c, l, 2);
    } else if ([base hasPrefix:@"exclamationmark"]) {
        int n = [base hasSuffix:@".3"] ? 3 : [base hasSuffix:@".2"] ? 2 : 1;
        for (int i = 0; i < n; i++) { CGFloat x = 0.5 + (i - (n - 1) / 2.0) * 0.26, l[4] = {x, 0.84, x, 0.38}; sym_line(c, l, 2); CGContextFillEllipseInRect(c, CGRectMake(x - 0.06, 0.1, 0.12, 0.12)); }
    } else if ([base hasPrefix:@"number"] || [base hasPrefix:@"hashtag"] || [base hasPrefix:@"tag"]) {
        CGFloat a[4] = {0.4, 0.14, 0.46, 0.86}, b[4] = {0.6, 0.14, 0.66, 0.86}, h1[4] = {0.18, 0.36, 0.84, 0.36}, h2[4] = {0.18, 0.64, 0.84, 0.64};
        sym_line(c, a, 2); sym_line(c, b, 2); sym_line(c, h1, 2); sym_line(c, h2, 2);
    } else if ([base hasPrefix:@"largecircle.fill.circle"] || [base hasPrefix:@"circle.inset.filled"] || [base hasPrefix:@"record.circle"]) {
        CGContextStrokeEllipseInRect(c, CGRectMake(0.12, 0.12, 0.76, 0.76)); CGContextFillEllipseInRect(c, CGRectMake(0.3, 0.3, 0.4, 0.4));
    } else if ([base hasPrefix:@"circle"]) {
        if (fill) CGContextFillEllipseInRect(c, CGRectMake(0.12, 0.12, 0.76, 0.76)); else CGContextStrokeEllipseInRect(c, CGRectMake(0.15, 0.15, 0.7, 0.7));
    } else if ([base hasPrefix:@"square"]) {
        if (fill) CGContextFillRect(c, CGRectMake(0.15, 0.15, 0.7, 0.7)); else CGContextStrokeRect(c, CGRectMake(0.18, 0.18, 0.64, 0.64));
    } else if ([base hasPrefix:@"arrow"]) {
        CGFloat a[4] = {0.5, 0.2, 0.5, 0.8}, h[6] = {0.28, 0.58, 0.5, 0.8, 0.72, 0.58};
        CGFloat ang = [base hasPrefix:@"arrow.down"] ? M_PI : [base hasPrefix:@"arrow.left"] ? M_PI / 2 : [base hasPrefix:@"arrow.right"] ? -M_PI / 2 : 0;
        CGContextTranslateCTM(c, 0.5, 0.5); CGContextRotateCTM(c, ang); CGContextTranslateCTM(c, -0.5, -0.5);
        sym_line(c, a, 2); sym_line(c, h, 3);
    } else CGContextFillEllipseInRect(c, CGRectMake(0.35, 0.35, 0.3, 0.3)); /* anything else: a dot */
    CGContextRestoreGState(c);
}

@implementation NSImage { NSMutableArray *_reps; BOOL (^_handler)(NSRect); BOOL _hflipped; NSString *_symbol; }
static NSMutableDictionary *g_named;
+ (NSImage *)imageNamed:(NSString *)n {
    if (!n) return nil;
    NSImage *i = g_named[n];
    if (i) return i;
    NSBundle *b = [NSBundle mainBundle];
    NSString *path = [n pathExtension].length ? [b pathForResource:[n stringByDeletingPathExtension] ofType:[n pathExtension]] : nil;
    for (NSString *ext in @[@"png", @"jpg", @"jpeg", @"tiff", @"gif", @"bmp"]) if (!path) path = [b pathForResource:n ofType:ext];
    i = path ? [[[NSImage alloc] initWithContentsOfFile:path] autorelease] : mw_catalog_image(n, nil);
    if (i) { if (!g_named) g_named = [[NSMutableDictionary alloc] init]; g_named[n] = i; }
    return i;
}
+ (NSImage *)imageWithSystemSymbolName:(NSString *)n accessibilityDescription:(NSString *)d {
    NSImage *i = [[[self alloc] initWithSize:NSMakeSize(16, 16)] autorelease];
    i->_symbol = [n copy]; i.template = YES; i.accessibilityDescription = d;
    return i;
}
+ (NSImage *)imageWithSize:(NSSize)s flipped:(BOOL)f drawingHandler:(BOOL (^)(NSRect))h {
    NSImage *i = [[[self alloc] initWithSize:s] autorelease];
    i->_handler = [h copy]; i->_hflipped = f;
    return i;
}
- (instancetype)init { return [self initWithSize:NSZeroSize]; }
- (instancetype)initWithSize:(NSSize)s { if ((self = [super init])) { _size = s; _reps = [[NSMutableArray alloc] init]; } return self; }
- (instancetype)initWithData:(NSData *)d {
    NSBitmapImageRep *r = [NSBitmapImageRep imageRepWithData:d];
    if (!r) { [self release]; return nil; }
    if ((self = [self initWithSize:r.size])) [_reps addObject:r];
    return self;
}
- (instancetype)initWithContentsOfFile:(NSString *)f { return [self initWithData:[NSData dataWithContentsOfFile:f]]; }
- (instancetype)initWithContentsOfURL:(NSURL *)u { return [self initWithData:[NSData dataWithContentsOfURL:u]]; }
- (instancetype)initByReferencingFile:(NSString *)f { return [self initWithContentsOfFile:f]; }
- (instancetype)initWithCGImage:(CGImageRef)i size:(NSSize)s {
    NSBitmapImageRep *r = [[[NSBitmapImageRep alloc] initWithCGImage:i] autorelease];
    if (!r) { [self release]; return nil; }
    if (s.width <= 0 || s.height <= 0) s = r.size;
    r.size = s;
    if ((self = [self initWithSize:s])) [_reps addObject:r];
    return self;
}
- (void)dealloc { [_reps release]; [_accessibilityDescription release]; [_handler release]; [_symbol release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)_mwSymbol { return _symbol; }
- (NSArray *)representations { return [[_reps copy] autorelease]; }
- (BOOL)isValid { return [_reps count] || _handler || _symbol; }
- (void)addRepresentation:(NSImageRep *)r { if (r) [_reps addObject:r]; if (_size.width <= 0 && r) _size = r.size; }
- (void)removeRepresentation:(NSImageRep *)r { [_reps removeObjectIdenticalTo:r]; }
- (NSBitmapImageRep *)_mwBitmap {
    for (id r in _reps) if ([r isKindOfClass:[NSBitmapImageRep class]]) return r;
    return nil;
}
/* drawn now into a bitmap of the given pixel size (symbols, drawing handlers, lockFocus contents) */
- (NSBitmapImageRep *)_mwRenderWidth:(size_t)w height:(size_t)h {
    NSBitmapImageRep *r = [[[NSBitmapImageRep alloc] _mwInitWidth:w ? w : 1 height:h ? h : 1] autorelease];
    r.size = _size;
    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithBitmapImageRep:r];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:g];
    mw_draw_image(self, NSMakeRect(0, 0, _size.width, _size.height), nil, 1);
    [NSGraphicsContext restoreGraphicsState];
    return r;
}
- (CGImageRef)CGImageForProposedRect:(NSRect *)r context:(NSGraphicsContext *)c hints:(NSDictionary *)h {
    NSBitmapImageRep *b = [self _mwBitmap];
    if (!b) {
        CGFloat s = mw_scale0();
        b = [self _mwRenderWidth:(size_t)ceil(_size.width * s) height:(size_t)ceil(_size.height * s)];
    }
    return [b CGImage];
}
- (NSData *)TIFFRepresentation {
    NSBitmapImageRep *b = [self _mwBitmap];
    if (!b) b = [self _mwRenderWidth:(size_t)ceil(_size.width) height:(size_t)ceil(_size.height)];
    return [b TIFFRepresentation];
}
- (void)lockFocus {
    CGFloat s = mw_scale0();
    NSBitmapImageRep *b = [self _mwBitmap];
    if (!b) { b = [[[NSBitmapImageRep alloc] _mwInitWidth:(size_t)ceil(_size.width * s) height:(size_t)ceil(_size.height * s)] autorelease]; b.size = _size; [_reps addObject:b]; }
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:b]];
}
- (void)unlockFocus { [NSGraphicsContext restoreGraphicsState]; }
- (BOOL)_mwDrawHandlerIn:(NSRect)r {
    CGContextRef c = mw_cg();
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, r.origin.x, r.origin.y);
    if (_size.width > 0 && _size.height > 0) CGContextScaleCTM(c, r.size.width / _size.width, r.size.height / _size.height);
    if (flipped != _hflipped) { CGContextTranslateCTM(c, 0, _size.height); CGContextScaleCTM(c, 1, -1); }
    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithCGContext:c flipped:_hflipped];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:g];
    BOOL ok = _handler(NSMakeRect(0, 0, _size.width, _size.height));
    [NSGraphicsContext restoreGraphicsState];
    CGContextRestoreGState(c);
    return ok;
}
- (void)drawInRect:(NSRect)r { mw_draw_image(self, r, nil, 1); }
- (void)drawInRect:(NSRect)r fromRect:(NSRect)f operation:(NSCompositingOperation)o fraction:(CGFloat)a {
    CGContextRef c = mw_cg();
    if (c) { CGContextSaveGState(c); CGContextSetBlendMode(c, mw_blend_mode(o)); }
    mw_draw_image(self, r, nil, a);
    if (c) CGContextRestoreGState(c);
}
- (void)drawAtPoint:(NSPoint)p fromRect:(NSRect)f operation:(NSCompositingOperation)o fraction:(CGFloat)a {
    [self drawInRect:NSMakeRect(p.x, p.y, _size.width, _size.height) fromRect:f operation:o fraction:a];
}
- (void)drawInRect:(NSRect)r fromRect:(NSRect)f operation:(NSCompositingOperation)o fraction:(CGFloat)a respectFlipped:(BOOL)rf hints:(NSDictionary *)h {
    [self drawInRect:r fromRect:f operation:o fraction:a];
}
@end
/* ponytail: the source rect (fromRect:) is ignored: the whole image fills r */
void mw_draw_image(NSImage *i, NSRect r, NSColor *tint, CGFloat alpha) {
    CGContextRef c = mw_cg();
    if (!c || !i || r.size.width <= 0 || r.size.height <= 0) return;
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    NSColor *t = tint ? tint : [NSColor labelColor];
    CGContextSaveGState(c);
    CGContextSetAlpha(c, alpha);
    NSString *sym = [i _mwSymbol];
    if (sym) draw_symbol(c, sym, flipped ? CGRectMake(r.origin.x, r.origin.y + r.size.height, r.size.width, -r.size.height) : r, t);
    else if ([i _mwBitmap]) {
        CGImageRef img = [[i _mwBitmap] CGImage];
        if (flipped) { CGContextTranslateCTM(c, r.origin.x, NSMaxY(r)); CGContextScaleCTM(c, 1, -1); r.origin = NSZeroPoint; } /* upright */
        if (i.isTemplate) { /* the image's alpha, painted with the tint */
            size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
            uint8_t *m = malloc(w * h);
            const uint8_t *px = [[i _mwBitmap] bitmapData];
            NSInteger bpr = [[i _mwBitmap] bytesPerRow], bpp = [[i _mwBitmap] bitsPerPixel] / 8;
            for (size_t y = 0; y < h; y++) for (size_t x = 0; x < w; x++) m[y * w + x] = bpp == 4 ? px[y * bpr + x * 4 + 3] : 255;
            CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, m, w * h, free_data);
            CGImageRef mask = CGImageCreate(w, h, 8, 8, w, NULL, kCGImageAlphaOnly, dp, NULL, true, 0);
            CGContextSetFillColorWithColor(c, t.CGColor);
            CGContextDrawImage(c, r, mask);
            CGImageRelease(mask); CGDataProviderRelease(dp);
        } else CGContextDrawImage(c, r, img);
    } else if ([i respondsToSelector:@selector(_mwDrawHandlerIn:)] && i.isValid) [i _mwDrawHandlerIn:r];
    CGContextRestoreGState(c);
}

/* ======================================================================= the window compositor */
static void render_body(NSView *v, CGContextRef c, CGFloat alpha, CAMetalLayer **metal);
/* c's CTM: the superview's coordinates */
/* the cell's class comes from outside AppKit and draws something itself (the control's own -drawRect: is AppKit's) */
static BOOL mw_cell_is_custom(NSCell *cell, NSView *v) {
    static const char *appkit;
    if (!appkit) appkit = class_getImageName([NSCell class]);
    const char *im = class_getImageName(object_getClass(cell));
    if (!im || !appkit || !strcmp(im, appkit)) return NO;
    Class vc = object_getClass(v);   /* a control subclass that draws itself wins */
    return class_getMethodImplementation(vc, @selector(drawRect:)) == class_getMethodImplementation([NSControl class], @selector(drawRect:))
        || !strcmp(class_getImageName(vc) ?: "", appkit);
}
static void render_view(NSView *v, CGContextRef c, CGFloat alpha, CAMetalLayer **metal) {
    if (v.isHidden || v.alphaValue <= 0) return;
    CALayer *L = v.layer;
    if (L && (L.isHidden || L.opacity <= 0)) return;
    NSRect f = v.frame, b = v.bounds;
    CGContextSaveGState(c);
    if (v.superview && v.superview.isFlipped) { CGContextTranslateCTM(c, f.origin.x, f.origin.y + f.size.height); CGContextScaleCTM(c, 1, -1); }
    else CGContextTranslateCTM(c, f.origin.x, f.origin.y);
    if (v.isFlipped) { CGContextTranslateCTM(c, 0, f.size.height); CGContextScaleCTM(c, 1, -1); }
    if (b.size.width > 0 && b.size.height > 0 && (b.size.width != f.size.width || b.size.height != f.size.height))
        CGContextScaleCTM(c, f.size.width / b.size.width, f.size.height / b.size.height);
    CGContextTranslateCTM(c, -b.origin.x, -b.origin.y);
    render_body(v, c, alpha, metal);
    CGContextRestoreGState(c);
}
/* c's CTM: the view's own (bounds) coordinates */
static void render_body(NSView *v, CGContextRef c, CGFloat alpha, CAMetalLayer **metal) {
    CALayer *L = v.layer;
    NSRect b = v.bounds;
    CGContextSaveGState(c);
    alpha *= v.alphaValue * (L ? L.opacity : 1);
    CGContextSetAlpha(c, alpha);
    CGFloat radius = L ? fmin(L.cornerRadius, fmin(b.size.width, b.size.height) / 2) : 0;
    if (radius > 0 && L.masksToBounds) {
        CGPathRef p = CGPathCreateWithRoundedRect(b, radius, radius, NULL);
        CGContextBeginPath(c); CGContextAddPath(c, p); CGContextClip(c); CGPathRelease(p);
    } else _mwCGContextClipToRectAligned(c, b);
    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithCGContext:c flipped:v.isFlipped];
    [NSGraphicsContext setCurrentContext:g];
    if ([L isKindOfClass:[CAMetalLayer class]]) { if (!*metal) *metal = (CAMetalLayer *)L; }
    else {
        if (L && v.wantsUpdateLayer) [v updateLayer];
        if (L.backgroundColor) mw_fill_round(b, radius, [NSColor colorWithCGColor:L.backgroundColor]);
        id contents = L.contents;
        if ([contents isKindOfClass:[NSImage class]]) mw_draw_image(contents, b, nil, 1);
        else if ([contents isKindOfClass:NSClassFromString(@"_MWCGImage")]) {
            CGContextSaveGState(c);
            if (v.isFlipped) { CGContextTranslateCTM(c, 0, 2 * b.origin.y + b.size.height); CGContextScaleCTM(c, 1, -1); }
            CGContextDrawImage(c, b, (CGImageRef)contents);
            CGContextRestoreGState(c);
        }
        NSCell *cell = [v isKindOfClass:[NSControl class]] ? [(NSControl *)v cell] : nil;
        if (cell && mw_cell_is_custom(cell, v)) {   /* a cell subclass of the app's draws its control */
            CGContextSaveGState(c);
            [cell drawWithFrame:b inView:v];
            CGContextRestoreGState(c);
            [NSGraphicsContext setCurrentContext:g];
        } else if (!(L && v.wantsUpdateLayer) && [v methodForSelector:@selector(drawRect:)] != method_getImplementation(class_getInstanceMethod([NSView class], @selector(drawRect:)))) {
            CGContextSaveGState(c);
            [v drawRect:b];
            CGContextRestoreGState(c);
            [NSGraphicsContext setCurrentContext:g];
        }
        if (L.borderWidth > 0 && L.borderColor) mw_stroke_round(b, radius, L.borderWidth, [NSColor colorWithCGColor:L.borderColor]);
    }
    for (NSView *s in v.subviews) render_view(s, c, alpha, metal);
    CGContextRestoreGState(c);
}
/* -[NSView cacheDisplayInRect:toBitmapImageRep:]: the view and its subviews, without the window behind them */
void mw_cache_display(NSView *v, NSRect r, NSBitmapImageRep *rep) {
    CGContextRef c = [rep _mwNewCGContext];
    if (!c || r.size.width <= 0 || r.size.height <= 0) { CGContextRelease(c); return; }
    CGContextSaveGState(c); CGContextSetBlendMode(c, kCGBlendModeClear); CGContextFillRect(c, CGRectMake(0, 0, rep.size.width, rep.size.height)); CGContextRestoreGState(c);
    CGContextScaleCTM(c, rep.size.width / r.size.width, rep.size.height / r.size.height);
    if (v.isFlipped) { CGContextTranslateCTM(c, 0, r.size.height); CGContextScaleCTM(c, 1, -1); }
    CGContextTranslateCTM(c, -r.origin.x, -r.origin.y);
    NSGraphicsContext *saved = [[NSGraphicsContext currentContext] retain];
    CAMetalLayer *m = nil;
    render_body(v, c, 1, &m);
    [NSGraphicsContext setCurrentContext:saved];
    [saved release];
    CGContextRelease(c);
}
/* draws a view tree into c (CTM: the view's superview coordinates); used by the compositor and cacheDisplayInRect: */
void mw_render_view_into(NSView *v, CGContextRef c, CAMetalLayer **metal) {
    NSGraphicsContext *saved = [[NSGraphicsContext currentContext] retain];
    CAMetalLayer *m = nil;
    render_view(v, c, 1, metal ? metal : &m);
    [NSGraphicsContext setCurrentContext:saved];
    [saved release];
}
static CAMetalLayer *find_metal(NSView *v) {
    if (v.isHidden) return nil;
    if ([v.layer isKindOfClass:[CAMetalLayer class]]) return (CAMetalLayer *)v.layer;
    for (NSView *s in v.subviews) { CAMetalLayer *m = find_metal(s); if (m) return m; }
    return nil;
}
void mw_render_window(NSWindow *w) {
    NSView *root = [w _mwRootView];
    if (!root || !w.isVisible) return;
    CGFloat s = w.backingScaleFactor;
    NSSize sz = root.frame.size;
    size_t pw = (size_t)lround(sz.width * s), ph = (size_t)lround(sz.height * s);
    if (!pw || !ph) return;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, pw, ph, 8, pw * 4, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!c) return;
    CGContextScaleCTM(c, s, s);
    /* the content view sits at the origin of the window's content */
    CGContextTranslateCTM(c, -root.frame.origin.x, -root.frame.origin.y);
    CAMetalLayer *metal = nil;
    /* with a Metal view the other views go over its image (transparent background); otherwise the window's background */
    if (!find_metal(root)) {
        NSColor *bg = w.backgroundColor ? w.backgroundColor : [NSColor windowBackgroundColor];
        CGContextSetFillColorWithColor(c, bg.CGColor);
        CGContextFillRect(c, root.frame);
    }
    mw_render_view_into(root, c, &metal);
    const uint8_t *px = CGBitmapContextGetData(c);
    if (metal) {
        BOOL any = NO;
        for (size_t i = 3, n = pw * ph * 4; i < n && !any; i += 4) any = px[i] != 0;
        [metal _mwSetOverlay:any ? px : NULL width:pw height:ph];
    } else {
        MwImage img = {(uint32_t)pw, (uint32_t)ph, (void *)px};
        /* a borderless window that is not opaque and has a see-through background: per-pixel alpha on the host */
        BOOL clear = !w.isOpaque && !(w.styleMask & NSWindowStyleMaskTitled) && (!w.backgroundColor || w.backgroundColor.alphaComponent < 1);
        if (clear != [w _mwTransparent]) { [w _mwSetTransparent:clear]; ui(UI_WINDOW_SET, [w _mwId], UI_W_TRANSPARENT, clear, 0, 0); }
        ui(UI_PRESENT, [w _mwId], U(&img), 0, 0, 0);
    }
    CGContextRelease(c);
}
NSString *const NSImageCompressionFactor = @"NSImageCompressionFactor";

/* ======================================================================= UniformTypeIdentifiers (image types), ImageIO (writing) */
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
UTType *UTTypePNG, *UTTypeJPEG, *UTTypeTIFF, *UTTypeGIF, *UTTypeBMP, *UTTypeImage, *UTTypeData;
static NSDictionary *mw_ut_ext(void) {
    return @{@"public.png": @"png", @"public.jpeg": @"jpeg", @"public.tiff": @"tiff", @"com.compuserve.gif": @"gif", @"com.microsoft.bmp": @"bmp",
             @"public.image": @"", @"public.data": @""};
}
@implementation UTType { NSString *_id; }
+ (void)load {
    UTTypePNG = [[UTType typeWithIdentifier:@"public.png"] retain]; UTTypeJPEG = [[UTType typeWithIdentifier:@"public.jpeg"] retain];
    UTTypeTIFF = [[UTType typeWithIdentifier:@"public.tiff"] retain]; UTTypeGIF = [[UTType typeWithIdentifier:@"com.compuserve.gif"] retain];
    UTTypeBMP = [[UTType typeWithIdentifier:@"com.microsoft.bmp"] retain]; UTTypeImage = [[UTType typeWithIdentifier:@"public.image"] retain];
    UTTypeData = [[UTType typeWithIdentifier:@"public.data"] retain];
}
+ (instancetype)typeWithIdentifier:(NSString *)i { UTType *t = [[self new] autorelease]; t->_id = [i copy]; return t; }
+ (instancetype)typeWithFilenameExtension:(NSString *)e {
    e = e.lowercaseString; if ([e isEqual:@"jpg"]) e = @"jpeg"; if ([e isEqual:@"tif"]) e = @"tiff";
    for (NSString *i in mw_ut_ext()) if ([mw_ut_ext()[i] isEqual:e]) return [self typeWithIdentifier:i];
    return nil;
}
- (void)dealloc { [_id release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)identifier { return _id; }
- (NSString *)preferredFilenameExtension { NSString *e = mw_ut_ext()[_id]; return e.length ? e : nil; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[UTType class]] && [_id isEqual:((UTType *)o)->_id]; }
- (NSUInteger)hash { return _id.hash; }
- (NSString *)description { return _id; }
@end

/* a CGImageDestinationRef is this object (CFRelease releases it); the image is encoded when finalized */
@interface _MWImageDestination : NSObject { @public NSString *_path; NSBitmapImageFileType _type; NSBitmapImageRep *_rep; } @end
@implementation _MWImageDestination
- (void)dealloc { [_path release]; [_rep release]; [super dealloc]; }
@end
CGImageDestinationRef CGImageDestinationCreateWithURL(CFURLRef url, CFStringRef type, size_t count, CFDictionaryRef options) {
    NSString *t = (NSString *)type, *path = [(NSURL *)url path];
    if (!path || !t) return NULL;
    _MWImageDestination *d = [_MWImageDestination new];
    d->_path = [path copy];
    d->_type = [t isEqual:@"public.jpeg"] ? NSBitmapImageFileTypeJPEG : [t isEqual:@"public.tiff"] ? NSBitmapImageFileTypeTIFF
             : [t isEqual:@"com.compuserve.gif"] ? NSBitmapImageFileTypeGIF : [t isEqual:@"com.microsoft.bmp"] ? NSBitmapImageFileTypeBMP : NSBitmapImageFileTypePNG;
    return (CGImageDestinationRef)d;
}
void CGImageDestinationAddImage(CGImageDestinationRef d, CGImageRef image, CFDictionaryRef properties) {
    _MWImageDestination *x = (_MWImageDestination *)d;
    if (!x || !image) return;
    [x->_rep release]; x->_rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
}
bool CGImageDestinationFinalize(CGImageDestinationRef d) {
    _MWImageDestination *x = (_MWImageDestination *)d;
    NSData *data = x && x->_rep ? [x->_rep representationUsingType:x->_type properties:@{}] : nil;
    return data && [data writeToFile:x->_path atomically:YES];
}
