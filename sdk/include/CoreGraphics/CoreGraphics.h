/* scion SDK — CoreGraphics subset: geometry, CGColor, displays and the mouse cursor, and 2D drawing into bitmaps
 * (CGContext, CGPath, CGImage), implemented in AppKit.dylib (dyld maps CoreGraphics.framework to it). */
#pragma once
#include <CoreFoundation/CoreFoundation.h>
#ifndef MW_CG_GEOMETRY
#define MW_CG_GEOMETRY
typedef double CGFloat;
#define CGFLOAT_MAX 1.7976931348623157e+308
#define CGFLOAT_MIN 2.2250738585072014e-308
#define CGFLOAT_IS_DOUBLE 1
typedef struct CGPoint { CGFloat x, y; } CGPoint;
typedef struct CGSize { CGFloat width, height; } CGSize;
typedef struct CGRect { CGPoint origin; CGSize size; } CGRect;
static inline CGPoint CGPointMake(CGFloat x, CGFloat y) { CGPoint p = {x, y}; return p; }
static inline CGSize CGSizeMake(CGFloat w, CGFloat h) { CGSize s = {w, h}; return s; }
static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { CGRect r = {{x, y}, {w, h}}; return r; }
#endif
#include <stdbool.h>
#ifndef CF_EXTERN_C_BEGIN
#ifdef __cplusplus
#define CF_EXTERN_C_BEGIN extern "C" {
#define CF_EXTERN_C_END }
#else
#define CF_EXTERN_C_BEGIN
#define CF_EXTERN_C_END
#endif
#endif

#ifndef MW_CG_ENUM
#define MW_CG_ENUM(T, N) enum __attribute__((enum_extensibility(open))) N : T N; enum N : T
#endif
CF_EXTERN_C_BEGIN
#pragma clang arc_cf_code_audited begin
typedef struct __attribute__((objc_bridge(id))) CGColor *CGColorRef;
typedef struct __attribute__((objc_bridge(id))) CGColorSpace *CGColorSpaceRef;
typedef struct __attribute__((objc_bridge(id))) CGImage *CGImageRef;
typedef struct __attribute__((objc_bridge(id))) CGContext *CGContextRef;
typedef uint32_t CGDirectDisplayID;
typedef int32_t CGError;
enum { kCGErrorSuccess = 0, kCGErrorFailure = 1000 };
typedef struct CGVector { CGFloat dx, dy; } CGVector;
typedef struct CGAffineTransform { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;
typedef MW_CG_ENUM(int32_t, CGRectEdge) { CGRectMinXEdge, CGRectMinYEdge, CGRectMaxXEdge, CGRectMaxYEdge };

extern const CGRect CGRectZero, CGRectNull, CGRectInfinite;
extern const CGPoint CGPointZero;
extern const CGSize CGSizeZero;
extern const CGAffineTransform CGAffineTransformIdentity;
extern const CFStringRef kCGColorSpaceSRGB, kCGColorSpaceGenericRGB, kCGColorSpaceDisplayP3, kCGColorSpaceExtendedLinearSRGB;

CGFloat CGRectGetMinX(CGRect r); CGFloat CGRectGetMidX(CGRect r); CGFloat CGRectGetMaxX(CGRect r);
CGFloat CGRectGetMinY(CGRect r); CGFloat CGRectGetMidY(CGRect r); CGFloat CGRectGetMaxY(CGRect r);
CGFloat CGRectGetWidth(CGRect r); CGFloat CGRectGetHeight(CGRect r);
bool CGRectEqualToRect(CGRect a, CGRect b); bool CGSizeEqualToSize(CGSize a, CGSize b); bool CGPointEqualToPoint(CGPoint a, CGPoint b);
bool CGRectIsEmpty(CGRect r); bool CGRectIsNull(CGRect r); bool CGRectContainsPoint(CGRect r, CGPoint p); bool CGRectContainsRect(CGRect a, CGRect b);
bool CGRectIntersectsRect(CGRect a, CGRect b);
CGRect CGRectStandardize(CGRect r); CGRect CGRectInset(CGRect r, CGFloat dx, CGFloat dy); CGRect CGRectOffset(CGRect r, CGFloat dx, CGFloat dy);
CGRect CGRectIntersection(CGRect a, CGRect b); CGRect CGRectUnion(CGRect a, CGRect b); CGRect CGRectIntegral(CGRect r);
CGAffineTransform CGAffineTransformMake(CGFloat a, CGFloat b, CGFloat c, CGFloat d, CGFloat tx, CGFloat ty);
CGAffineTransform CGAffineTransformMakeScale(CGFloat sx, CGFloat sy);
CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty);
CGPoint CGPointApplyAffineTransform(CGPoint p, CGAffineTransform t);

/* colors (reference counted like CF objects: CFRetain / CFRelease work too) */
CGColorRef CGColorCreateGenericRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a);
CGColorRef CGColorCreateSRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a);
CGColorRef CGColorCreateGenericGray(CGFloat gray, CGFloat a);
CGColorRef CGColorCreate(CGColorSpaceRef space, const CGFloat *components);
CGColorRef CGColorGetConstantColor(CFStringRef name);
CGColorRef CGColorRetain(CGColorRef c); void CGColorRelease(CGColorRef c);
size_t CGColorGetNumberOfComponents(CGColorRef c); const CGFloat *CGColorGetComponents(CGColorRef c); CGFloat CGColorGetAlpha(CGColorRef c);
CGColorRef CGColorCreateCopyWithAlpha(CGColorRef c, CGFloat a);
CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void); CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef name);
void CGColorSpaceRelease(CGColorSpaceRef s); CGColorSpaceRef CGColorSpaceRetain(CGColorSpaceRef s);
CGColorSpaceRef CGColorSpaceCreateDeviceGray(void); size_t CGColorSpaceGetNumberOfComponents(CGColorSpaceRef s);
extern const CFStringRef kCGColorSpaceGenericGray, kCGColorSpaceLinearGray;
extern const CFStringRef kCGColorBlack, kCGColorWhite, kCGColorClear;

/* displays */
CGDirectDisplayID CGMainDisplayID(void);
CGError CGGetActiveDisplayList(uint32_t max, CGDirectDisplayID *displays, uint32_t *count);
CGError CGGetOnlineDisplayList(uint32_t max, CGDirectDisplayID *displays, uint32_t *count);
CGRect CGDisplayBounds(CGDirectDisplayID d);
size_t CGDisplayPixelsWide(CGDirectDisplayID d); size_t CGDisplayPixelsHigh(CGDirectDisplayID d);
CGError CGDisplayHideCursor(CGDirectDisplayID d); CGError CGDisplayShowCursor(CGDirectDisplayID d);
CGError CGWarpMouseCursorPosition(CGPoint p);
CGError CGAssociateMouseAndMouseCursorPosition(int connected);
void CGGetLastMouseDelta(int32_t *dx, int32_t *dy);
typedef struct CGDisplayMode *CGDisplayModeRef;
CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID d);
double CGDisplayModeGetRefreshRate(CGDisplayModeRef m);
size_t CGDisplayModeGetWidth(CGDisplayModeRef m); size_t CGDisplayModeGetHeight(CGDisplayModeRef m);
void CGDisplayModeRelease(CGDisplayModeRef m);
/* ---------------------------------------------------------------- 2D drawing */
typedef struct __attribute__((objc_bridge_mutable(id))) CGPath *CGMutablePathRef;
typedef const struct __attribute__((objc_bridge(id))) CGPath *CGPathRef;
typedef struct __attribute__((objc_bridge(id))) CGDataProvider *CGDataProviderRef;
typedef void (*CGDataProviderReleaseDataCallback)(void *info, const void *data, size_t size);
typedef MW_CG_ENUM(int32_t, CGPathDrawingMode) { kCGPathFill, kCGPathEOFill, kCGPathStroke, kCGPathFillStroke, kCGPathEOFillStroke };
typedef MW_CG_ENUM(int32_t, CGLineCap) { kCGLineCapButt, kCGLineCapRound, kCGLineCapSquare };
typedef MW_CG_ENUM(int32_t, CGLineJoin) { kCGLineJoinMiter, kCGLineJoinRound, kCGLineJoinBevel };
typedef MW_CG_ENUM(int32_t, CGInterpolationQuality) { kCGInterpolationDefault = 0, kCGInterpolationNone = 1, kCGInterpolationLow = 2, kCGInterpolationMedium = 4, kCGInterpolationHigh = 3 };
typedef MW_CG_ENUM(int32_t, CGBlendMode) { kCGBlendModeNormal = 0, kCGBlendModeMultiply, kCGBlendModeScreen, kCGBlendModeOverlay, kCGBlendModeDarken, kCGBlendModeLighten,
               kCGBlendModeColorDodge, kCGBlendModeColorBurn, kCGBlendModeSoftLight, kCGBlendModeHardLight, kCGBlendModeDifference, kCGBlendModeExclusion,
               kCGBlendModeHue, kCGBlendModeSaturation, kCGBlendModeColor, kCGBlendModeLuminosity, kCGBlendModeClear = 16, kCGBlendModeCopy = 17,
               kCGBlendModeSourceIn, kCGBlendModeSourceOut, kCGBlendModeSourceAtop, kCGBlendModeDestinationOver, kCGBlendModeDestinationIn,
               kCGBlendModeDestinationOut, kCGBlendModeDestinationAtop, kCGBlendModeXOR, kCGBlendModePlusDarker, kCGBlendModePlusLighter };
typedef enum { kCGRenderingIntentDefault = 0 } CGColorRenderingIntent;
typedef uint32_t CGBitmapInfo;
enum {
    kCGImageAlphaNone = 0, kCGImageAlphaPremultipliedLast = 1, kCGImageAlphaPremultipliedFirst = 2, kCGImageAlphaLast = 3, kCGImageAlphaFirst = 4,
    kCGImageAlphaNoneSkipLast = 5, kCGImageAlphaNoneSkipFirst = 6, kCGImageAlphaOnly = 7,
    kCGBitmapAlphaInfoMask = 0x1F, kCGBitmapFloatComponents = 1 << 8, kCGBitmapByteOrderMask = 0x7000,
    kCGBitmapByteOrderDefault = 0, kCGBitmapByteOrder16Little = 1 << 12, kCGBitmapByteOrder32Little = 2 << 12,
    kCGBitmapByteOrder16Big = 3 << 12, kCGBitmapByteOrder32Big = 4 << 12,
};
typedef enum { kCGTextFill, kCGTextStroke, kCGTextFillStroke, kCGTextInvisible, kCGTextFillClip, kCGTextStrokeClip, kCGTextFillStrokeClip, kCGTextClip } CGTextDrawingMode;
typedef unsigned short CGGlyph;
typedef uint32_t CGImageAlphaInfo;

CGAffineTransform CGAffineTransformConcat(CGAffineTransform a, CGAffineTransform b);
CGAffineTransform CGAffineTransformInvert(CGAffineTransform t);
CGAffineTransform CGAffineTransformTranslate(CGAffineTransform t, CGFloat tx, CGFloat ty);
CGAffineTransform CGAffineTransformScale(CGAffineTransform t, CGFloat sx, CGFloat sy);
CGAffineTransform CGAffineTransformRotate(CGAffineTransform t, CGFloat angle);
CGAffineTransform CGAffineTransformMakeRotation(CGFloat angle);
bool CGAffineTransformIsIdentity(CGAffineTransform t);
bool CGAffineTransformEqualToTransform(CGAffineTransform a, CGAffineTransform b);
CGSize CGSizeApplyAffineTransform(CGSize s, CGAffineTransform t);
void CGRectDivide(CGRect r, CGRect *slice, CGRect *remainder, CGFloat amount, CGRectEdge edge);
CGRect CGRectApplyAffineTransform(CGRect r, CGAffineTransform t);

CGMutablePathRef CGPathCreateMutable(void);
CGPathRef CGPathCreateWithRect(CGRect r, const CGAffineTransform *t);
CGPathRef CGPathCreateWithEllipseInRect(CGRect r, const CGAffineTransform *t);
CGPathRef CGPathCreateWithRoundedRect(CGRect r, CGFloat rx, CGFloat ry, const CGAffineTransform *t);
CGPathRef CGPathCreateCopy(CGPathRef p);
CGMutablePathRef CGPathCreateMutableCopy(CGPathRef p);
CGPathRef CGPathRetain(CGPathRef p); void CGPathRelease(CGPathRef p);
void CGPathMoveToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x, CGFloat y);
void CGPathAddLineToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x, CGFloat y);
void CGPathAddCurveToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat c1x, CGFloat c1y, CGFloat c2x, CGFloat c2y, CGFloat x, CGFloat y);
void CGPathAddQuadCurveToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat cx, CGFloat cy, CGFloat x, CGFloat y);
void CGPathAddArc(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat a1, bool clockwise);
void CGPathAddRelativeArc(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat delta);
void CGPathAddArcToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r);
void CGPathAddRect(CGMutablePathRef p, const CGAffineTransform *t, CGRect r);
void CGPathAddRects(CGMutablePathRef p, const CGAffineTransform *t, const CGRect *r, size_t n);
void CGPathAddRoundedRect(CGMutablePathRef p, const CGAffineTransform *t, CGRect r, CGFloat rx, CGFloat ry);
void CGPathAddEllipseInRect(CGMutablePathRef p, const CGAffineTransform *t, CGRect r);
void CGPathAddLines(CGMutablePathRef p, const CGAffineTransform *t, const CGPoint *pts, size_t n);
void CGPathAddPath(CGMutablePathRef p, const CGAffineTransform *t, CGPathRef other);
void CGPathCloseSubpath(CGMutablePathRef p);
bool CGPathIsEmpty(CGPathRef p);
CGRect CGPathGetBoundingBox(CGPathRef p); CGRect CGPathGetPathBoundingBox(CGPathRef p);
CGPoint CGPathGetCurrentPoint(CGPathRef p);
bool CGPathContainsPoint(CGPathRef p, const CGAffineTransform *t, CGPoint pt, bool eoFill);
typedef enum { kCGPathElementMoveToPoint, kCGPathElementAddLineToPoint, kCGPathElementAddQuadCurveToPoint, kCGPathElementAddCurveToPoint,
               kCGPathElementCloseSubpath } CGPathElementType;
typedef struct CGPathElement { CGPathElementType type; CGPoint *points; } CGPathElement;
typedef void (*CGPathApplierFunction)(void *info, const CGPathElement *element);
void CGPathApply(CGPathRef p, void *info, CGPathApplierFunction function);

CGDataProviderRef CGDataProviderCreateWithData(void *info, const void *data, size_t size, CGDataProviderReleaseDataCallback release);
CGDataProviderRef CGDataProviderCreateWithCFData(CFTypeRef data);
CFTypeRef CGDataProviderCopyData(CGDataProviderRef p);
void CGDataProviderRelease(CGDataProviderRef p); CGDataProviderRef CGDataProviderRetain(CGDataProviderRef p);
CGImageRef CGImageMaskCreate(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr, CGDataProviderRef provider, const CGFloat *decode, bool interpolate);
bool CGImageIsMask(CGImageRef i);
CGImageRef CGImageCreate(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr, CGColorSpaceRef space, CGBitmapInfo info,
                         CGDataProviderRef provider, const CGFloat *decode, bool interpolate, CGColorRenderingIntent intent);
CGImageRef CGImageCreateWithImageInRect(CGImageRef i, CGRect r);
CGImageRef CGImageCreateCopy(CGImageRef i);
CGImageRef CGImageRetain(CGImageRef i); void CGImageRelease(CGImageRef i);
size_t CGImageGetWidth(CGImageRef i); size_t CGImageGetHeight(CGImageRef i); size_t CGImageGetBytesPerRow(CGImageRef i);
size_t CGImageGetBitsPerPixel(CGImageRef i); size_t CGImageGetBitsPerComponent(CGImageRef i);
CGBitmapInfo CGImageGetBitmapInfo(CGImageRef i); CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef i);
CGDataProviderRef CGImageGetDataProvider(CGImageRef i); CGColorSpaceRef CGImageGetColorSpace(CGImageRef i);

CGContextRef CGBitmapContextCreate(void *data, size_t w, size_t h, size_t bpc, size_t bpr, CGColorSpaceRef space, uint32_t info);
void *CGBitmapContextGetData(CGContextRef c);
size_t CGBitmapContextGetWidth(CGContextRef c); size_t CGBitmapContextGetHeight(CGContextRef c); size_t CGBitmapContextGetBytesPerRow(CGContextRef c);
CGBitmapInfo CGBitmapContextGetBitmapInfo(CGContextRef c);
size_t CGBitmapContextGetBitsPerComponent(CGContextRef c); size_t CGBitmapContextGetBitsPerPixel(CGContextRef c);
CGImageRef CGBitmapContextCreateImage(CGContextRef c);
CGContextRef CGContextRetain(CGContextRef c); void CGContextRelease(CGContextRef c);
void CGContextSaveGState(CGContextRef c); void CGContextRestoreGState(CGContextRef c);
void CGContextTranslateCTM(CGContextRef c, CGFloat tx, CGFloat ty); void CGContextScaleCTM(CGContextRef c, CGFloat sx, CGFloat sy);
void CGContextRotateCTM(CGContextRef c, CGFloat angle); void CGContextConcatCTM(CGContextRef c, CGAffineTransform t);
CGAffineTransform CGContextGetCTM(CGContextRef c);
void CGContextSetRGBFillColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a);
void CGContextSetRGBStrokeColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a);
void CGContextSetGrayFillColor(CGContextRef c, CGFloat g, CGFloat a); void CGContextSetGrayStrokeColor(CGContextRef c, CGFloat g, CGFloat a);
void CGContextSetFillColorWithColor(CGContextRef c, CGColorRef col); void CGContextSetStrokeColorWithColor(CGContextRef c, CGColorRef col);
void CGContextSetFillColor(CGContextRef c, const CGFloat *components); void CGContextSetStrokeColor(CGContextRef c, const CGFloat *components);
void CGContextSetFillColorSpace(CGContextRef c, CGColorSpaceRef s); void CGContextSetStrokeColorSpace(CGContextRef c, CGColorSpaceRef s);
void CGContextSetAlpha(CGContextRef c, CGFloat a);
void CGContextSetLineWidth(CGContextRef c, CGFloat w); void CGContextSetLineCap(CGContextRef c, CGLineCap cap);
void CGContextSetLineJoin(CGContextRef c, CGLineJoin j); void CGContextSetMiterLimit(CGContextRef c, CGFloat m);
void CGContextSetLineDash(CGContextRef c, CGFloat phase, const CGFloat *lengths, size_t n);
void CGContextSetShouldAntialias(CGContextRef c, bool f); void CGContextSetAllowsAntialiasing(CGContextRef c, bool f);
void CGContextSetInterpolationQuality(CGContextRef c, CGInterpolationQuality q); CGInterpolationQuality CGContextGetInterpolationQuality(CGContextRef c);
void CGContextSetShouldSmoothFonts(CGContextRef c, bool f); void CGContextSetAllowsFontSmoothing(CGContextRef c, bool f); void CGContextSetFlatness(CGContextRef c, CGFloat f);
void CGContextSetBlendMode(CGContextRef c, CGBlendMode m);
void CGContextSetShadow(CGContextRef c, CGSize offset, CGFloat blur);
void CGContextSetShadowWithColor(CGContextRef c, CGSize offset, CGFloat blur, CGColorRef color);
void CGContextBeginPath(CGContextRef c); void CGContextClosePath(CGContextRef c);
void CGContextMoveToPoint(CGContextRef c, CGFloat x, CGFloat y); void CGContextAddLineToPoint(CGContextRef c, CGFloat x, CGFloat y);
void CGContextAddCurveToPoint(CGContextRef c, CGFloat c1x, CGFloat c1y, CGFloat c2x, CGFloat c2y, CGFloat x, CGFloat y);
void CGContextAddQuadCurveToPoint(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat x, CGFloat y);
void CGContextAddArc(CGContextRef c, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat a1, int clockwise);
void CGContextAddArcToPoint(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r);
void CGContextAddRect(CGContextRef c, CGRect r); void CGContextAddRects(CGContextRef c, const CGRect *r, size_t n);
void CGContextAddEllipseInRect(CGContextRef c, CGRect r); void CGContextAddPath(CGContextRef c, CGPathRef p);
void CGContextAddLines(CGContextRef c, const CGPoint *pts, size_t n);
bool CGContextIsPathEmpty(CGContextRef c); CGPoint CGContextGetPathCurrentPoint(CGContextRef c); CGPathRef CGContextCopyPath(CGContextRef c); CGRect CGContextGetPathBoundingBox(CGContextRef c);
void CGContextFillPath(CGContextRef c); void CGContextEOFillPath(CGContextRef c); void CGContextStrokePath(CGContextRef c);
void CGContextDrawPath(CGContextRef c, CGPathDrawingMode m);
void CGContextFillRect(CGContextRef c, CGRect r); void CGContextFillRects(CGContextRef c, const CGRect *r, size_t n);
void CGContextStrokeRect(CGContextRef c, CGRect r); void CGContextStrokeRectWithWidth(CGContextRef c, CGRect r, CGFloat w);
void CGContextClearRect(CGContextRef c, CGRect r);
void CGContextFillEllipseInRect(CGContextRef c, CGRect r); void CGContextStrokeEllipseInRect(CGContextRef c, CGRect r);
void CGContextStrokeLineSegments(CGContextRef c, const CGPoint *pts, size_t n);
void CGContextClip(CGContextRef c); void CGContextEOClip(CGContextRef c);
void CGContextClipToRect(CGContextRef c, CGRect r); void CGContextClipToRects(CGContextRef c, const CGRect *r, size_t n);
CGRect CGContextGetClipBoundingBox(CGContextRef c);
void CGContextDrawImage(CGContextRef c, CGRect r, CGImageRef i);
void CGContextFlush(CGContextRef c); void CGContextSynchronize(CGContextRef c);
CGAffineTransform CGContextGetUserSpaceToDeviceSpaceTransform(CGContextRef c);
CGPoint CGContextConvertPointToUserSpace(CGContextRef c, CGPoint p); CGRect CGContextConvertRectToUserSpace(CGContextRef c, CGRect r);
CGPoint CGContextConvertPointToDeviceSpace(CGContextRef c, CGPoint p);
CGRect CGContextConvertRectToDeviceSpace(CGContextRef c, CGRect r);
void CGContextSetTextMatrix(CGContextRef c, CGAffineTransform t); CGAffineTransform CGContextGetTextMatrix(CGContextRef c);
void CGContextSetTextPosition(CGContextRef c, CGFloat x, CGFloat y); CGPoint CGContextGetTextPosition(CGContextRef c);
void CGContextSetTextDrawingMode(CGContextRef c, CGTextDrawingMode m); void CGContextSetCharacterSpacing(CGContextRef c, CGFloat s);
void CGContextShowGlyphsAtPositions(CGContextRef c, const CGGlyph *g, const CGPoint *p, size_t n);
void CGContextShowGlyphsWithAdvances(CGContextRef c, const CGGlyph *g, const CGSize *a, size_t n);
void CGContextShowGlyphs(CGContextRef c, const CGGlyph *g, size_t n);
void CGContextBeginTransparencyLayer(CGContextRef c, CFDictionaryRef aux);
void CGContextBeginTransparencyLayerWithRect(CGContextRef c, CGRect r, CFDictionaryRef aux); void CGContextEndTransparencyLayer(CGContextRef c);
#pragma clang arc_cf_code_audited end
CF_EXTERN_C_END
