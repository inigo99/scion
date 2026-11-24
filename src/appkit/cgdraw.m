/* cgdraw.m — CoreGraphics 2D drawing into bitmaps: affine transforms, CGPath, CGDataProvider, CGImage and bitmap
 * CGContexts (fill, stroke, clip, images), in software.
 * Device space is y-up in pixels; memory row 0 is the top, as in CG. Paths are stored in device space (transformed by the
 * CTM when they are built, like CG). Filling: scanlines with 4 sub-rows and exact horizontal coverage (antialiased),
 * nonzero or even-odd. Strokes become consistently oriented polygons (segments, joins, caps) filled nonzero.
 * ponytail: no dashes, shadows, gradients or separable blend modes (Porter-Duff ones only, and only under the shape drawn); every edge is visited per sub-row
 * (fine for UI paths; an active-edge list if huge paths show up). */
#import "internal.h"
#include <stdlib.h>
#include <string.h>

/* ======================================================================= affine transforms */
CGAffineTransform CGAffineTransformConcat(CGAffineTransform a, CGAffineTransform b) {
    CGAffineTransform r = {a.a * b.a + a.b * b.c, a.a * b.b + a.b * b.d, a.c * b.a + a.d * b.c, a.c * b.b + a.d * b.d,
                           a.tx * b.a + a.ty * b.c + b.tx, a.tx * b.b + a.ty * b.d + b.ty};
    return r;
}
CGAffineTransform CGAffineTransformInvert(CGAffineTransform t) {
    CGFloat det = t.a * t.d - t.b * t.c;
    if (det == 0) return t;
    CGAffineTransform r = {t.d / det, -t.b / det, -t.c / det, t.a / det, (t.c * t.ty - t.d * t.tx) / det, (t.b * t.tx - t.a * t.ty) / det};
    return r;
}
CGAffineTransform CGAffineTransformMakeRotation(CGFloat a) { return CGAffineTransformMake(cos(a), sin(a), -sin(a), cos(a), 0, 0); }
CGAffineTransform CGAffineTransformTranslate(CGAffineTransform t, CGFloat x, CGFloat y) { return CGAffineTransformConcat(CGAffineTransformMakeTranslation(x, y), t); }
CGAffineTransform CGAffineTransformScale(CGAffineTransform t, CGFloat x, CGFloat y) { return CGAffineTransformConcat(CGAffineTransformMakeScale(x, y), t); }
CGAffineTransform CGAffineTransformRotate(CGAffineTransform t, CGFloat a) { return CGAffineTransformConcat(CGAffineTransformMakeRotation(a), t); }
bool CGAffineTransformIsIdentity(CGAffineTransform t) { return t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1 && t.tx == 0 && t.ty == 0; }
bool CGAffineTransformEqualToTransform(CGAffineTransform a, CGAffineTransform b) { return !memcmp(&a, &b, sizeof a); }
CGSize CGSizeApplyAffineTransform(CGSize s, CGAffineTransform t) { return CGSizeMake(t.a * s.width + t.c * s.height, t.b * s.width + t.d * s.height); }
CGRect CGRectApplyAffineTransform(CGRect r, CGAffineTransform t) {
    if (CGRectIsNull(r)) return r;
    r = CGRectStandardize(r);
    CGPoint p[4] = {r.origin, {r.origin.x + r.size.width, r.origin.y}, {r.origin.x, r.origin.y + r.size.height},
                    {r.origin.x + r.size.width, r.origin.y + r.size.height}};
    CGFloat x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
    for (int i = 0; i < 4; i++) {
        CGPoint q = CGPointApplyAffineTransform(p[i], t);
        x0 = fmin(x0, q.x); y0 = fmin(y0, q.y); x1 = fmax(x1, q.x); y1 = fmax(y1, q.y);
    }
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

/* ======================================================================= CGPath */
enum { E_MOVE, E_LINE, E_QUAD, E_CUBIC, E_CLOSE };
typedef struct { int type; CGPoint p[3]; } Elem;
@interface _MWCGPath : NSObject { @public Elem *_e; size_t _n, _cap; CGPoint _start, _cur; } @end
@implementation _MWCGPath
- (void)dealloc { free(_e); [super dealloc]; }
@end
static void pelem(_MWCGPath *p, int type, int np, const CGPoint *pts, const CGAffineTransform *t) {
    if (p->_n == p->_cap) { p->_cap = p->_cap ? p->_cap * 2 : 16; p->_e = realloc(p->_e, p->_cap * sizeof(Elem)); }
    Elem *e = &p->_e[p->_n++];
    e->type = type;
    for (int i = 0; i < np; i++) e->p[i] = t ? CGPointApplyAffineTransform(pts[i], *t) : pts[i];
    if (type == E_MOVE) p->_start = e->p[0];
    if (type == E_CLOSE) p->_cur = p->_start; else if (np) p->_cur = e->p[np - 1];
}
static BOOL popen_(_MWCGPath *p) { return p->_n && p->_e[p->_n - 1].type != E_CLOSE; } /* a current point exists */
static void pmove(_MWCGPath *p, const CGAffineTransform *t, CGFloat x, CGFloat y) {
    CGPoint q = {x, y};
    if (p->_n && p->_e[p->_n - 1].type == E_MOVE) p->_n--; /* consecutive moves: the last one wins */
    pelem(p, E_MOVE, 1, &q, t);
}
static void pline(_MWCGPath *p, const CGAffineTransform *t, CGFloat x, CGFloat y) {
    CGPoint q = {x, y};
    if (!p->_n) { pelem(p, E_MOVE, 1, &q, t); return; }
    if (p->_e[p->_n - 1].type == E_CLOSE) { CGPoint s = p->_start; pelem(p, E_MOVE, 1, &s, NULL); }
    pelem(p, E_LINE, 1, &q, t);
}
static void pcurve(_MWCGPath *p, const CGAffineTransform *t, CGPoint a, CGPoint b, CGPoint c) {
    if (!p->_n) pmove(p, t, a.x, a.y);
    else if (p->_e[p->_n - 1].type == E_CLOSE) { CGPoint s = p->_start; pelem(p, E_MOVE, 1, &s, NULL); }
    CGPoint q[3] = {a, b, c};
    pelem(p, E_CUBIC, 3, q, t);
}
static void pquad(_MWCGPath *p, const CGAffineTransform *t, CGPoint a, CGPoint b) {
    if (!p->_n) pmove(p, t, a.x, a.y);
    else if (p->_e[p->_n - 1].type == E_CLOSE) { CGPoint s = p->_start; pelem(p, E_MOVE, 1, &s, NULL); }
    CGPoint q[2] = {a, b};
    pelem(p, E_QUAD, 2, q, t);
}
static void pclosepath(_MWCGPath *p) { if (popen_(p)) pelem(p, E_CLOSE, 0, NULL, NULL); }
/* arc from angle a0 sweeping s radians (signed: + counterclockwise in y-up space); connect: line from the current point */
static void parc(_MWCGPath *p, const CGAffineTransform *t, CGFloat cx, CGFloat cy, CGFloat r, CGFloat a0, CGFloat s) {
    CGFloat x = cx + r * cos(a0), y = cy + r * sin(a0);
    if (popen_(p)) pline(p, t, x, y); else pmove(p, t, x, y);
    int n = (int)ceil(fabs(s) / (M_PI / 2) - 1e-9);
    if (n < 1) return;
    CGFloat step = s / n, k = 4.0 / 3 * tan(step / 4);
    for (int i = 0; i < n; i++) {
        CGFloat t1 = a0 + i * step, t2 = t1 + step;
        CGPoint c1 = {cx + r * (cos(t1) - k * sin(t1)), cy + r * (sin(t1) + k * cos(t1))};
        CGPoint c2 = {cx + r * (cos(t2) + k * sin(t2)), cy + r * (sin(t2) - k * cos(t2))};
        CGPoint e = {cx + r * cos(t2), cy + r * sin(t2)};
        pcurve(p, t, c1, c2, e);
    }
}
static CGFloat sweep(CGFloat a0, CGFloat a1, bool clockwise) {
    CGFloat d = a1 - a0, two = 2 * M_PI;
    if (!clockwise) { if (d >= two) return two; d = fmod(d, two); if (d < 0) d += two; }
    else { if (d <= -two) return -two; d = fmod(d, two); if (d > 0) d -= two; }
    return d;
}
static void parcto(_MWCGPath *p, const CGAffineTransform *t, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r) {
    if (!popen_(p)) { pmove(p, t, x1, y1); return; }
    /* the current point is stored transformed: bring it back to the caller's space */
    CGPoint p0 = t ? CGPointApplyAffineTransform(p->_cur, CGAffineTransformInvert(*t)) : p->_cur;
    CGFloat ux = p0.x - x1, uy = p0.y - y1, vx = x2 - x1, vy = y2 - y1;
    CGFloat lu = hypot(ux, uy), lv = hypot(vx, vy);
    if (lu < 1e-9 || lv < 1e-9 || r <= 0) { pline(p, t, x1, y1); return; }
    ux /= lu; uy /= lu; vx /= lv; vy /= lv;
    CGFloat cosang = ux * vx + uy * vy, ang = acos(fmax(-1, fmin(1, cosang)));
    if (ang < 1e-6 || fabs(ang - M_PI) < 1e-6) { pline(p, t, x1, y1); return; }
    CGFloat d = r / tan(ang / 2), bx = ux + vx, by = uy + vy, lb = hypot(bx, by), h = r / sin(ang / 2);
    CGFloat cx = x1 + bx / lb * h, cy = y1 + by / lb * h;
    CGFloat t1x = x1 + ux * d, t1y = y1 + uy * d, t2x = x1 + vx * d, t2y = y1 + vy * d;
    CGFloat a0 = atan2(t1y - cy, t1x - cx), a1 = atan2(t2y - cy, t2x - cx), s = a1 - a0;
    while (s > M_PI) s -= 2 * M_PI;
    while (s < -M_PI) s += 2 * M_PI;
    pline(p, t, t1x, t1y);
    parc(p, t, cx, cy, r, a0, s);
}
static const CGFloat KAPPA = 0.5522847498307936;
static void pcorner(_MWCGPath *p, const CGAffineTransform *t, CGPoint from, CGPoint corner, CGPoint to) {
    pcurve(p, t, CGPointMake(from.x + (corner.x - from.x) * KAPPA, from.y + (corner.y - from.y) * KAPPA),
           CGPointMake(to.x + (corner.x - to.x) * KAPPA, to.y + (corner.y - to.y) * KAPPA), to);
}
static void prect(_MWCGPath *p, const CGAffineTransform *t, CGRect r) {
    r = CGRectStandardize(r);
    CGFloat x0 = r.origin.x, y0 = r.origin.y, x1 = x0 + r.size.width, y1 = y0 + r.size.height;
    pmove(p, t, x0, y0); pline(p, t, x1, y0); pline(p, t, x1, y1); pline(p, t, x0, y1); pclosepath(p);
}
static void prounded(_MWCGPath *p, const CGAffineTransform *t, CGRect r, CGFloat rx, CGFloat ry) {
    r = CGRectStandardize(r);
    rx = fmin(fmax(rx, 0), r.size.width / 2); ry = fmin(fmax(ry, 0), r.size.height / 2);
    if (rx <= 0 || ry <= 0) { prect(p, t, r); return; }
    CGFloat x0 = r.origin.x, y0 = r.origin.y, x1 = x0 + r.size.width, y1 = y0 + r.size.height;
    pmove(p, t, x0 + rx, y0);
    pline(p, t, x1 - rx, y0); pcorner(p, t, CGPointMake(x1 - rx, y0), CGPointMake(x1, y0), CGPointMake(x1, y0 + ry));
    pline(p, t, x1, y1 - ry); pcorner(p, t, CGPointMake(x1, y1 - ry), CGPointMake(x1, y1), CGPointMake(x1 - rx, y1));
    pline(p, t, x0 + rx, y1); pcorner(p, t, CGPointMake(x0 + rx, y1), CGPointMake(x0, y1), CGPointMake(x0, y1 - ry));
    pline(p, t, x0, y0 + ry); pcorner(p, t, CGPointMake(x0, y0 + ry), CGPointMake(x0, y0), CGPointMake(x0 + rx, y0));
    pclosepath(p);
}
static void pellipse(_MWCGPath *p, const CGAffineTransform *t, CGRect r) {
    r = CGRectStandardize(r);
    CGFloat x0 = r.origin.x, y0 = r.origin.y, x1 = x0 + r.size.width, y1 = y0 + r.size.height, mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
    pmove(p, t, x1, my);
    pcorner(p, t, CGPointMake(x1, my), CGPointMake(x1, y1), CGPointMake(mx, y1));
    pcorner(p, t, CGPointMake(mx, y1), CGPointMake(x0, y1), CGPointMake(x0, my));
    pcorner(p, t, CGPointMake(x0, my), CGPointMake(x0, y0), CGPointMake(mx, y0));
    pcorner(p, t, CGPointMake(mx, y0), CGPointMake(x1, y0), CGPointMake(x1, my));
    pclosepath(p);
}
static void pappend(_MWCGPath *p, const CGAffineTransform *t, _MWCGPath *o) {
    for (size_t i = 0; i < o->_n; i++) {
        Elem *e = &o->_e[i];
        switch (e->type) {
        case E_MOVE: pmove(p, t, e->p[0].x, e->p[0].y); break;
        case E_LINE: pline(p, t, e->p[0].x, e->p[0].y); break;
        case E_QUAD: pquad(p, t, e->p[0], e->p[1]); break;
        case E_CUBIC: pcurve(p, t, e->p[0], e->p[1], e->p[2]); break;
        case E_CLOSE: pclosepath(p); break;
        }
    }
}
#define P(x) ((_MWCGPath *)(x))
CGMutablePathRef CGPathCreateMutable(void) { return (CGMutablePathRef)[[_MWCGPath alloc] init]; }
CGPathRef CGPathCreateWithRect(CGRect r, const CGAffineTransform *t) { CGMutablePathRef p = CGPathCreateMutable(); prect(P(p), t, r); return p; }
CGPathRef CGPathCreateWithEllipseInRect(CGRect r, const CGAffineTransform *t) { CGMutablePathRef p = CGPathCreateMutable(); pellipse(P(p), t, r); return p; }
CGPathRef CGPathCreateWithRoundedRect(CGRect r, CGFloat rx, CGFloat ry, const CGAffineTransform *t) { CGMutablePathRef p = CGPathCreateMutable(); prounded(P(p), t, r, rx, ry); return p; }
CGMutablePathRef CGPathCreateMutableCopy(CGPathRef o) { CGMutablePathRef p = CGPathCreateMutable(); if (o) pappend(P(p), NULL, P(o)); return p; }
CGPathRef CGPathCreateCopy(CGPathRef o) { return CGPathCreateMutableCopy(o); }
CGPathRef CGPathRetain(CGPathRef p) { if (p) [(id)p retain]; return p; }
void CGPathRelease(CGPathRef p) { if (p) [(id)p release]; }
void CGPathMoveToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x, CGFloat y) { pmove(P(p), t, x, y); }
void CGPathAddLineToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x, CGFloat y) { pline(P(p), t, x, y); }
void CGPathAddCurveToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat ax, CGFloat ay, CGFloat bx, CGFloat by, CGFloat x, CGFloat y) {
    pcurve(P(p), t, CGPointMake(ax, ay), CGPointMake(bx, by), CGPointMake(x, y));
}
void CGPathAddQuadCurveToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat cx, CGFloat cy, CGFloat x, CGFloat y) { pquad(P(p), t, CGPointMake(cx, cy), CGPointMake(x, y)); }
void CGPathAddArc(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat a1, bool cw) { parc(P(p), t, x, y, r, a0, sweep(a0, a1, cw)); }
void CGPathAddRelativeArc(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat d) { parc(P(p), t, x, y, r, a0, d); }
void CGPathAddArcToPoint(CGMutablePathRef p, const CGAffineTransform *t, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r) { parcto(P(p), t, x1, y1, x2, y2, r); }
void CGPathAddRect(CGMutablePathRef p, const CGAffineTransform *t, CGRect r) { prect(P(p), t, r); }
void CGPathAddRects(CGMutablePathRef p, const CGAffineTransform *t, const CGRect *r, size_t n) { for (size_t i = 0; i < n; i++) prect(P(p), t, r[i]); }
void CGPathAddRoundedRect(CGMutablePathRef p, const CGAffineTransform *t, CGRect r, CGFloat rx, CGFloat ry) { prounded(P(p), t, r, rx, ry); }
void CGPathAddEllipseInRect(CGMutablePathRef p, const CGAffineTransform *t, CGRect r) { pellipse(P(p), t, r); }
void CGPathAddLines(CGMutablePathRef p, const CGAffineTransform *t, const CGPoint *pts, size_t n) {
    for (size_t i = 0; i < n; i++) { if (i) pline(P(p), t, pts[i].x, pts[i].y); else pmove(P(p), t, pts[i].x, pts[i].y); }
}
void CGPathAddPath(CGMutablePathRef p, const CGAffineTransform *t, CGPathRef o) { if (o) pappend(P(p), t, P(o)); }
void CGPathCloseSubpath(CGMutablePathRef p) { pclosepath(P(p)); }
bool CGPathIsEmpty(CGPathRef p) { return !p || !P(p)->_n; }
CGPoint CGPathGetCurrentPoint(CGPathRef p) { return p && P(p)->_n ? P(p)->_cur : CGPointZero; }
static CGRect pbounds(_MWCGPath *p) { /* control-point box (CG's bounding box is tighter for curves: close enough) */
    if (!p->_n) return CGRectNull;
    CGFloat x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
    for (size_t i = 0; i < p->_n; i++) {
        Elem *e = &p->_e[i];
        int np = e->type == E_CUBIC ? 3 : e->type == E_QUAD ? 2 : e->type == E_CLOSE ? 0 : 1;
        for (int k = 0; k < np; k++) { x0 = fmin(x0, e->p[k].x); y0 = fmin(y0, e->p[k].y); x1 = fmax(x1, e->p[k].x); y1 = fmax(y1, e->p[k].y); }
    }
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}
CGRect CGPathGetBoundingBox(CGPathRef p) { return p ? pbounds(P(p)) : CGRectNull; }
CGRect CGPathGetPathBoundingBox(CGPathRef p) { return CGPathGetBoundingBox(p); }

/* ---------------------------------------------------------------- flattening into polylines */
typedef struct { CGPoint *p; size_t n, cap; } Poly;
typedef struct { Poly *v; size_t n, cap; char *closed; } Polys;
static void poly_pt(Poly *l, CGPoint q) {
    if (l->n && fabs(l->p[l->n - 1].x - q.x) < 1e-9 && fabs(l->p[l->n - 1].y - q.y) < 1e-9) return;
    if (l->n == l->cap) { l->cap = l->cap ? l->cap * 2 : 16; l->p = realloc(l->p, l->cap * sizeof(CGPoint)); }
    l->p[l->n++] = q;
}
static Poly *polys_new(Polys *s) {
    if (s->n == s->cap) { s->cap = s->cap ? s->cap * 2 : 8; s->v = realloc(s->v, s->cap * sizeof(Poly)); s->closed = realloc(s->closed, s->cap); }
    memset(&s->v[s->n], 0, sizeof(Poly)); s->closed[s->n] = 0;
    return &s->v[s->n++];
}
static void polys_free(Polys *s) { for (size_t i = 0; i < s->n; i++) free(s->v[i].p); free(s->v); free(s->closed); }
static int segs(CGFloat len) { int n = (int)ceil(sqrt(len)) + 1; return n > 256 ? 256 : n; }
/* tf: maps path points (device, y-up) into the rasterizer's space (pixels, y-down) */
static void flatten(_MWCGPath *p, CGAffineTransform tf, Polys *out) {
    Poly *cur = NULL;
    CGPoint last = {0, 0};
    for (size_t i = 0; i < p->_n; i++) {
        Elem *e = &p->_e[i];
        if (e->type == E_MOVE) { cur = polys_new(out); last = CGPointApplyAffineTransform(e->p[0], tf); poly_pt(cur, last); continue; }
        if (!cur) { cur = polys_new(out); poly_pt(cur, last); }
        if (e->type == E_CLOSE) { out->closed[cur - out->v] = 1; if (cur->n) last = cur->p[0]; cur = NULL; continue; }
        CGPoint a = last, b = CGPointApplyAffineTransform(e->p[0], tf);
        if (e->type == E_LINE) { poly_pt(cur, b); last = b; continue; }
        CGPoint c = CGPointApplyAffineTransform(e->p[1], tf);
        if (e->type == E_QUAD) {
            int n = segs(hypot(b.x - a.x, b.y - a.y) + hypot(c.x - b.x, c.y - b.y));
            for (int k = 1; k <= n; k++) {
                CGFloat t = (CGFloat)k / n, u = 1 - t;
                poly_pt(cur, CGPointMake(u * u * a.x + 2 * u * t * b.x + t * t * c.x, u * u * a.y + 2 * u * t * b.y + t * t * c.y));
            }
            last = c; continue;
        }
        CGPoint d = CGPointApplyAffineTransform(e->p[2], tf);
        int n = segs(hypot(b.x - a.x, b.y - a.y) + hypot(c.x - b.x, c.y - b.y) + hypot(d.x - c.x, d.y - c.y));
        for (int k = 1; k <= n; k++) {
            CGFloat t = (CGFloat)k / n, u = 1 - t;
            poly_pt(cur, CGPointMake(u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x,
                                     u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y));
        }
        last = d;
    }
}

/* ---------------------------------------------------------------- edges and coverage */
typedef struct { float x0, y0, x1, y1; int dir; } Edge;
typedef struct { Edge *e; size_t n, cap; float minx, miny, maxx, maxy; } Edges;
static void edge(Edges *E, CGFloat x0, CGFloat y0, CGFloat x1, CGFloat y1) {
    if (y0 == y1 || !isfinite(x0) || !isfinite(x1) || !isfinite(y0) || !isfinite(y1)) return;
    int dir = 1;
    if (y0 > y1) { CGFloat t = x0; x0 = x1; x1 = t; t = y0; y0 = y1; y1 = t; dir = -1; }
    if (E->n == E->cap) { E->cap = E->cap ? E->cap * 2 : 64; E->e = realloc(E->e, E->cap * sizeof(Edge)); }
    E->e[E->n++] = (Edge){(float)x0, (float)y0, (float)x1, (float)y1, dir};
    if (E->n == 1) { E->minx = fminf(x0, x1); E->maxx = fmaxf(x0, x1); E->miny = y0; E->maxy = y1; }
    else { E->minx = fminf(E->minx, fminf(x0, x1)); E->maxx = fmaxf(E->maxx, fmaxf(x0, x1)); E->miny = fminf(E->miny, y0); E->maxy = fmaxf(E->maxy, y1); }
}
static void edges_poly(Edges *E, const CGPoint *p, size_t n, BOOL reverse) { /* closed polygon */
    for (size_t i = 0; i < n; i++) {
        CGPoint a = p[i], b = p[(i + 1) % n];
        if (reverse) edge(E, b.x, b.y, a.x, a.y); else edge(E, a.x, a.y, b.x, b.y);
    }
}
/* every polygon of a stroke goes in with the same orientation, so overlaps add up under the nonzero rule */
static void edges_oriented(Edges *E, const CGPoint *p, size_t n) {
    CGFloat area = 0;
    for (size_t i = 0; i < n; i++) { CGPoint a = p[i], b = p[(i + 1) % n]; area += a.x * b.y - b.x * a.y; }
    if (fabs(area) < 1e-12) return;
    edges_poly(E, p, n, area < 0);
}

/* ======================================================================= CGColorSpace extras, CGDataProvider, CGImage */
@interface _MWCGDataProvider : NSObject {
@public void *_info; const uint8_t *_data; size_t _size; CGDataProviderReleaseDataCallback _rel; NSData *_obj;
} @end
@implementation _MWCGDataProvider
- (void)dealloc { if (_rel) _rel(_info, _data, _size); [_obj release]; [super dealloc]; }
@end
CGDataProviderRef CGDataProviderCreateWithData(void *info, const void *data, size_t size, CGDataProviderReleaseDataCallback rel) {
    _MWCGDataProvider *p = [[_MWCGDataProvider alloc] init];
    p->_info = info; p->_data = data; p->_size = size; p->_rel = rel;
    return (CGDataProviderRef)p;
}
CGDataProviderRef CGDataProviderCreateWithCFData(CFTypeRef d) {
    _MWCGDataProvider *p = [[_MWCGDataProvider alloc] init];
    p->_obj = [(NSData *)d copy]; p->_data = [p->_obj bytes]; p->_size = [p->_obj length];
    return (CGDataProviderRef)p;
}
CFTypeRef CGDataProviderCopyData(CGDataProviderRef p) { _MWCGDataProvider *x = (id)p; return x ? (CFTypeRef)[[NSData alloc] initWithBytes:x->_data length:x->_size] : NULL; }
CGDataProviderRef CGDataProviderRetain(CGDataProviderRef p) { if (p) [(id)p retain]; return p; }
void CGDataProviderRelease(CGDataProviderRef p) { if (p) [(id)p release]; }

/* pixel layout of a bitmap (context or image): bytes per pixel and the byte offset of r, g, b, a (-1: absent) */
typedef struct { int bpp, off[4]; BOOL gray, premul, ok; } Fmt;
static Fmt fmt_of(size_t bpc, size_t bitsPerPixel, uint32_t info, size_t comps) {
    Fmt f = {0, {-1, -1, -1, -1}, NO, YES, NO};
    uint32_t alpha = info & kCGBitmapAlphaInfoMask, order = info & kCGBitmapByteOrderMask;
    if (bpc != 8) return f;
    f.premul = alpha != kCGImageAlphaLast && alpha != kCGImageAlphaFirst;
    if (bitsPerPixel == 8) {
        f.bpp = 1; f.ok = YES;
        if (alpha == kCGImageAlphaOnly) f.off[3] = 0; else { f.gray = YES; f.off[0] = f.off[1] = f.off[2] = 0; }
        return f;
    }
    if (bitsPerPixel == 16 && comps == 1) { f.bpp = 2; f.ok = YES; f.gray = YES; f.off[0] = f.off[1] = f.off[2] = 0; f.off[3] = 1; return f; }
    if (bitsPerPixel == 24) { f.bpp = 3; f.ok = YES; f.off[0] = 0; f.off[1] = 1; f.off[2] = 2; return f; }
    if (bitsPerPixel != 32) return f;
    f.bpp = 4; f.ok = YES;
    /* big-endian order: First = A R G B, Last = R G B A; 32Little reverses the bytes */
    BOOL first = alpha == kCGImageAlphaPremultipliedFirst || alpha == kCGImageAlphaFirst || alpha == kCGImageAlphaNoneSkipFirst;
    BOOL has = alpha != kCGImageAlphaNone && alpha != kCGImageAlphaNoneSkipFirst && alpha != kCGImageAlphaNoneSkipLast;
    int pos[4]; /* r g b a in big-endian order */
    if (first) { pos[3] = 0; pos[0] = 1; pos[1] = 2; pos[2] = 3; } else { pos[0] = 0; pos[1] = 1; pos[2] = 2; pos[3] = 3; }
    for (int i = 0; i < 4; i++) f.off[i] = order == kCGBitmapByteOrder32Little ? 3 - pos[i] : pos[i];
    if (!has) f.off[3] = -1;
    return f;
}
static inline void px_load(const Fmt *f, const uint8_t *p, float c[4]) { /* -> premultiplied rgba 0..1 */
    float a = f->off[3] >= 0 ? p[f->off[3]] / 255.f : 1;
    if (f->off[0] < 0) { c[0] = c[1] = c[2] = 0; c[3] = a; return; }
    float k = f->premul ? 1 : a;
    c[0] = p[f->off[0]] / 255.f * k; c[1] = p[f->off[1]] / 255.f * k; c[2] = p[f->off[2]] / 255.f * k; c[3] = a;
}
static inline uint8_t u8(float v) { return v <= 0 ? 0 : v >= 1 ? 255 : (uint8_t)(v * 255 + 0.5f); }
static inline void px_store(const Fmt *f, uint8_t *p, const float c[4]) {
    if (f->off[3] >= 0) p[f->off[3]] = u8(c[3]);
    if (f->off[0] < 0) return;
    if (f->gray) { p[f->off[0]] = u8(0.299f * c[0] + 0.587f * c[1] + 0.114f * c[2]); return; }
    p[f->off[0]] = u8(c[0]); p[f->off[1]] = u8(c[1]); p[f->off[2]] = u8(c[2]);
}

@interface _MWCGImage : NSObject {
@public size_t _w, _h, _bpc, _bpp, _bpr; uint32_t _info; Fmt _f; BOOL _mask; _MWCGDataProvider *_prov; CGColorSpaceRef _cs; const uint8_t *_px;
} @end
@implementation _MWCGImage
- (void)dealloc { [_prov release]; if (_cs) [(id)_cs release]; [super dealloc]; }
@end
size_t CGColorSpaceGetNumberOfComponents(CGColorSpaceRef s);
CGImageRef CGImageCreate(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr, CGColorSpaceRef cs, CGBitmapInfo info,
                         CGDataProviderRef prov, const CGFloat *decode, bool interpolate, CGColorRenderingIntent intent) {
    if (!prov || !w || !h) return NULL;
    _MWCGImage *i = [[_MWCGImage alloc] init];
    i->_w = w; i->_h = h; i->_bpc = bpc; i->_bpp = bpp; i->_bpr = bpr; i->_info = info;
    i->_prov = [(id)prov retain]; i->_px = i->_prov->_data;
    i->_cs = cs ? (CGColorSpaceRef)[(id)cs retain] : NULL;
    i->_f = fmt_of(bpc, bpp, info, cs ? CGColorSpaceGetNumberOfComponents(cs) : 3);
    i->_mask = (info & kCGBitmapAlphaInfoMask) == kCGImageAlphaOnly;
    if (!i->_f.ok) NSLog(@"scion: CGImage format not supported (%zu bpc, %zu bpp, info 0x%x): drawn as nothing", bpc, bpp, info);
    return (CGImageRef)i;
}
static void free_data(void *info, const void *data, size_t size) { free((void *)data); }
CGImageRef CGImageMaskCreate(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr, CGDataProviderRef prov, const CGFloat *decode, bool interpolate) {
    _MWCGImage *i = (id)CGImageCreate(w, h, bpc, bpp, bpr, NULL, kCGImageAlphaOnly, prov, decode, interpolate, 0);
    /* an image mask paints where its samples are 0 (decode {0, 1}): store the inverse once */
    if (i && bpc == 8 && bpp == 8) {
        uint8_t *inv = malloc(w * h);
        for (size_t y = 0; y < h; y++) for (size_t x = 0; x < w; x++) inv[y * w + x] = 255 - i->_px[y * bpr + x];
        [i->_prov release];
        i->_prov = (id)CGDataProviderCreateWithData(NULL, inv, w * h, free_data);
        i->_px = inv; i->_bpr = w;
    }
    return (CGImageRef)i;
}
CGImageRef CGImageCreateWithImageInRect(CGImageRef src, CGRect r) {
    _MWCGImage *s = (id)src;
    if (!s) return NULL;
    r = CGRectIntegral(CGRectIntersection(CGRectStandardize(r), CGRectMake(0, 0, s->_w, s->_h)));
    if (CGRectIsEmpty(r) || !s->_f.ok) return NULL;
    _MWCGImage *i = (id)CGImageCreate((size_t)r.size.width, (size_t)r.size.height, s->_bpc, s->_bpp, s->_bpr, s->_cs, s->_info, (CGDataProviderRef)s->_prov, NULL, true, 0);
    i->_px = s->_px + (size_t)r.origin.y * s->_bpr + (size_t)r.origin.x * s->_f.bpp;
    i->_mask = s->_mask;
    return (CGImageRef)i;
}
CGImageRef CGImageCreateCopy(CGImageRef i) { return i ? (CGImageRef)[(id)i retain] : NULL; }
CGImageRef CGImageRetain(CGImageRef i) { if (i) [(id)i retain]; return i; }
void CGImageRelease(CGImageRef i) { if (i) [(id)i release]; }
#define I(x) ((_MWCGImage *)(x))
size_t CGImageGetWidth(CGImageRef i) { return i ? I(i)->_w : 0; }
size_t CGImageGetHeight(CGImageRef i) { return i ? I(i)->_h : 0; }
size_t CGImageGetBytesPerRow(CGImageRef i) { return i ? I(i)->_bpr : 0; }
size_t CGImageGetBitsPerPixel(CGImageRef i) { return i ? I(i)->_bpp : 0; }
size_t CGImageGetBitsPerComponent(CGImageRef i) { return i ? I(i)->_bpc : 0; }
CGBitmapInfo CGImageGetBitmapInfo(CGImageRef i) { return i ? I(i)->_info : 0; }
CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef i) { return i ? I(i)->_info & kCGBitmapAlphaInfoMask : 0; }
CGDataProviderRef CGImageGetDataProvider(CGImageRef i) { return i ? (CGDataProviderRef)I(i)->_prov : NULL; }
CGColorSpaceRef CGImageGetColorSpace(CGImageRef i) { return i ? I(i)->_cs : NULL; }
bool CGImageIsMask(CGImageRef i) { return i && I(i)->_mask; }

/* ======================================================================= CGContext */
typedef struct GState {
    CGAffineTransform ctm;
    float fill[4], stroke[4];          /* straight rgba */
    CGFloat alpha, lw, miter;
    int cap, join, blend, interp;
    BOOL aa;
    int cx0, cy0, cx1, cy1;            /* clip box, pixels (y down), half-open */
    uint8_t *mask;                     /* clip coverage (w * h), NULL = the box only */
    CGAffineTransform textm;           /* text matrix and position (glyphs: draw.m) */
    int textmode;
    void *font;                        /* NSFont (not retained: fonts are cached) */
    struct GState *prev;
} GState;
@interface _MWCGContext : NSObject {
@public uint8_t *_data; size_t _w, _h, _bpr, _bpc, _bitsPP; uint32_t _info; Fmt _f; BOOL _owns; GState *_gs; _MWCGPath *_path;
} @end
@implementation _MWCGContext
- (void)dealloc {
    while (_gs) { GState *p = _gs->prev; free(_gs->mask); free(_gs); _gs = p; }
    [_path release];
    if (_owns) free(_data);
    [super dealloc];
}
@end
#define C(x) ((_MWCGContext *)(x))

CGContextRef CGBitmapContextCreate(void *data, size_t w, size_t h, size_t bpc, size_t bpr, CGColorSpaceRef cs, uint32_t info) {
    size_t comps = cs ? CGColorSpaceGetNumberOfComponents(cs) : 0;
    uint32_t alpha = info & kCGBitmapAlphaInfoMask;
    size_t bitsPP = alpha == kCGImageAlphaOnly ? bpc : comps == 1 ? bpc * (alpha == kCGImageAlphaNone ? 1 : 2) : bpc * 4;
    Fmt f = fmt_of(bpc, bitsPP, info, comps ? comps : 1);
    if (!w || !h || !f.ok || (comps == 3 && f.bpp != 4)) { NSLog(@"scion: CGBitmapContextCreate: format not supported (%zu bpc, info 0x%x)", bpc, info); return NULL; }
    _MWCGContext *c = [[_MWCGContext alloc] init];
    c->_w = w; c->_h = h; c->_bpc = bpc; c->_bitsPP = bitsPP; c->_info = info; c->_f = f;
    c->_bpr = bpr ? bpr : w * f.bpp;
    if (data) c->_data = data; else { c->_data = calloc(c->_bpr, h); c->_owns = YES; }
    if (!c->_data) { /* out of memory: no context (drawing into it would write through NULL) */
        fprintf(stderr, "scion: CGBitmapContextCreate: out of memory for %zux%zu\n", w, h);
        [c release]; return NULL;
    }
    GState *g = calloc(1, sizeof *g);
    g->ctm = CGAffineTransformIdentity; g->fill[3] = g->stroke[3] = 1; g->alpha = 1; g->lw = 1; g->miter = 10; g->aa = YES;
    g->cx1 = (int)w; g->cy1 = (int)h; g->textm = CGAffineTransformIdentity;
    c->_gs = g;
    c->_path = [[_MWCGPath alloc] init];
    return (CGContextRef)c;
}
void *CGBitmapContextGetData(CGContextRef c) { return c ? C(c)->_data : NULL; }
size_t CGBitmapContextGetWidth(CGContextRef c) { return c ? C(c)->_w : 0; }
size_t CGBitmapContextGetHeight(CGContextRef c) { return c ? C(c)->_h : 0; }
size_t CGBitmapContextGetBytesPerRow(CGContextRef c) { return c ? C(c)->_bpr : 0; }
size_t CGBitmapContextGetBitsPerComponent(CGContextRef c) { return c ? C(c)->_bpc : 0; }
size_t CGBitmapContextGetBitsPerPixel(CGContextRef c) { return c ? C(c)->_bitsPP : 0; }
CGBitmapInfo CGBitmapContextGetBitmapInfo(CGContextRef c) { return c ? C(c)->_info : 0; }
CGImageRef CGBitmapContextCreateImage(CGContextRef c) {
    if (!c) return NULL;
    _MWCGContext *x = C(c);
    NSData *d = [[NSData alloc] initWithBytes:x->_data length:x->_bpr * x->_h];
    CGDataProviderRef p = CGDataProviderCreateWithCFData((CFTypeRef)d);
    [d release];
    CGColorSpaceRef cs = x->_f.gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB();
    CGImageRef i = CGImageCreate(x->_w, x->_h, x->_bpc, x->_bitsPP, x->_bpr, cs, x->_info, p, NULL, true, 0);
    CGColorSpaceRelease(cs); CGDataProviderRelease(p);
    return i;
}
CGContextRef CGContextRetain(CGContextRef c) { if (c) [(id)c retain]; return c; }
void CGContextRelease(CGContextRef c) { if (c) [(id)c release]; }
void CGContextFlush(CGContextRef c) { }
void CGContextSynchronize(CGContextRef c) { }

/* ---------------------------------------------------------------- graphics state */
void CGContextSaveGState(CGContextRef c) {
    if (!c) return;
    GState *g = malloc(sizeof *g);
    *g = *C(c)->_gs;
    if (g->mask) { size_t n = C(c)->_w * C(c)->_h; g->mask = malloc(n); memcpy(g->mask, C(c)->_gs->mask, n); }
    g->prev = C(c)->_gs; C(c)->_gs = g;
}
void CGContextRestoreGState(CGContextRef c) {
    if (!c || !C(c)->_gs->prev) return;
    GState *g = C(c)->_gs; C(c)->_gs = g->prev;
    free(g->mask); free(g);
}
#define G (C(c)->_gs)
/* text state (the glyphs are drawn by draw.m) */
void CGContextSetTextMatrix(CGContextRef c, CGAffineTransform t) { if (c) G->textm = t; }
CGAffineTransform CGContextGetTextMatrix(CGContextRef c) { return c ? G->textm : CGAffineTransformIdentity; }
/* the text position is the text matrix's translation, as in CG */
void CGContextSetTextPosition(CGContextRef c, CGFloat x, CGFloat y) { if (c) { G->textm.tx = x; G->textm.ty = y; } }
CGPoint CGContextGetTextPosition(CGContextRef c) { return c ? CGPointMake(G->textm.tx, G->textm.ty) : CGPointZero; }
void CGContextSetTextDrawingMode(CGContextRef c, CGTextDrawingMode m) { if (c) G->textmode = (int)m; }
void CGContextSetCharacterSpacing(CGContextRef c, CGFloat s) { }
void *_mwCGContextFont(CGContextRef c) { return c ? G->font : NULL; }
void _mwCGContextSetFont(CGContextRef c, void *f) { if (c) G->font = f; }
/* ponytail: transparency layers draw straight into the context (no group compositing) */
void CGContextBeginTransparencyLayer(CGContextRef c, CFDictionaryRef aux) { CGContextSaveGState(c); }
void CGContextBeginTransparencyLayerWithRect(CGContextRef c, CGRect r, CFDictionaryRef aux) { CGContextSaveGState(c); }
void CGContextEndTransparencyLayer(CGContextRef c) { CGContextRestoreGState(c); }
void CGContextConcatCTM(CGContextRef c, CGAffineTransform t) { if (c) G->ctm = CGAffineTransformConcat(t, G->ctm); }
void CGContextTranslateCTM(CGContextRef c, CGFloat x, CGFloat y) { CGContextConcatCTM(c, CGAffineTransformMakeTranslation(x, y)); }
void CGContextScaleCTM(CGContextRef c, CGFloat x, CGFloat y) { CGContextConcatCTM(c, CGAffineTransformMakeScale(x, y)); }
void CGContextRotateCTM(CGContextRef c, CGFloat a) { CGContextConcatCTM(c, CGAffineTransformMakeRotation(a)); }
CGAffineTransform CGContextGetCTM(CGContextRef c) { return c ? G->ctm : CGAffineTransformIdentity; }
void _mwCGContextSetCTM(CGContextRef c, CGAffineTransform t) { if (c) G->ctm = t; }
CGAffineTransform CGContextGetUserSpaceToDeviceSpaceTransform(CGContextRef c) { return CGContextGetCTM(c); }
CGPoint CGContextConvertPointToDeviceSpace(CGContextRef c, CGPoint p) { return CGPointApplyAffineTransform(p, CGContextGetCTM(c)); }
CGPoint CGContextConvertPointToUserSpace(CGContextRef c, CGPoint p) { return CGPointApplyAffineTransform(p, CGAffineTransformInvert(CGContextGetCTM(c))); }
CGRect CGContextConvertRectToDeviceSpace(CGContextRef c, CGRect r) { return CGRectApplyAffineTransform(r, CGContextGetCTM(c)); }
CGRect CGContextConvertRectToUserSpace(CGContextRef c, CGRect r) { return CGRectApplyAffineTransform(r, CGAffineTransformInvert(CGContextGetCTM(c))); }
static void setc(float *d, CGFloat r, CGFloat g, CGFloat b, CGFloat a) { d[0] = r; d[1] = g; d[2] = b; d[3] = a; }
static void setcg(float *d, CGColorRef col) {
    size_t n = CGColorGetNumberOfComponents(col);
    const CGFloat *k = CGColorGetComponents(col);
    if (n >= 4) setc(d, k[0], k[1], k[2], k[3]); else if (n == 2) setc(d, k[0], k[0], k[0], k[1]); else setc(d, 0, 0, 0, col ? 1 : 0);
}
void CGContextSetRGBFillColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a) { if (c) setc(G->fill, r, g, b, a); }
void CGContextSetRGBStrokeColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a) { if (c) setc(G->stroke, r, g, b, a); }
void CGContextSetGrayFillColor(CGContextRef c, CGFloat w, CGFloat a) { if (c) setc(G->fill, w, w, w, a); }
void CGContextSetGrayStrokeColor(CGContextRef c, CGFloat w, CGFloat a) { if (c) setc(G->stroke, w, w, w, a); }
void CGContextSetFillColorWithColor(CGContextRef c, CGColorRef k) { if (c) setcg(G->fill, k); }
void CGContextSetStrokeColorWithColor(CGContextRef c, CGColorRef k) { if (c) setcg(G->stroke, k); }
void CGContextSetFillColor(CGContextRef c, const CGFloat *k) { if (c && k) setc(G->fill, k[0], k[1], k[2], k[3]); }
void CGContextSetStrokeColor(CGContextRef c, const CGFloat *k) { if (c && k) setc(G->stroke, k[0], k[1], k[2], k[3]); }
void CGContextSetFillColorSpace(CGContextRef c, CGColorSpaceRef s) { }
void CGContextSetStrokeColorSpace(CGContextRef c, CGColorSpaceRef s) { }
void CGContextSetAlpha(CGContextRef c, CGFloat a) { if (c) G->alpha = fmax(0, fmin(1, a)); }
void CGContextSetLineWidth(CGContextRef c, CGFloat w) { if (c) G->lw = fmax(0, w); }
void CGContextSetLineCap(CGContextRef c, CGLineCap k) { if (c) G->cap = k; }
void CGContextSetLineJoin(CGContextRef c, CGLineJoin j) { if (c) G->join = j; }
void CGContextSetMiterLimit(CGContextRef c, CGFloat m) { if (c) G->miter = m; }
void CGContextSetLineDash(CGContextRef c, CGFloat phase, const CGFloat *l, size_t n) { } /* ponytail: solid lines; dash the polylines when an app needs it */
void CGContextSetShouldAntialias(CGContextRef c, bool f) { if (c) G->aa = f; }
void CGContextSetAllowsAntialiasing(CGContextRef c, bool f) { }
void CGContextSetShouldSmoothFonts(CGContextRef c, bool f) { }
void CGContextSetAllowsFontSmoothing(CGContextRef c, bool f) { }
void CGContextSetInterpolationQuality(CGContextRef c, CGInterpolationQuality q) { if (c) G->interp = q; }
CGInterpolationQuality CGContextGetInterpolationQuality(CGContextRef c) { return c ? G->interp : 0; }
void CGContextSetBlendMode(CGContextRef c, CGBlendMode m) { if (c) G->blend = m; }
void CGContextSetShadow(CGContextRef c, CGSize o, CGFloat b) { }
void CGContextSetShadowWithColor(CGContextRef c, CGSize o, CGFloat b, CGColorRef k) { }
void CGContextSetFlatness(CGContextRef c, CGFloat f) { }

/* ---------------------------------------------------------------- the current path (device space) */
void CGContextBeginPath(CGContextRef c) { if (c) C(c)->_path->_n = 0; }
void CGContextClosePath(CGContextRef c) { if (c) pclosepath(C(c)->_path); }
void CGContextMoveToPoint(CGContextRef c, CGFloat x, CGFloat y) { if (c) pmove(C(c)->_path, &G->ctm, x, y); }
void CGContextAddLineToPoint(CGContextRef c, CGFloat x, CGFloat y) { if (c) pline(C(c)->_path, &G->ctm, x, y); }
void CGContextAddCurveToPoint(CGContextRef c, CGFloat ax, CGFloat ay, CGFloat bx, CGFloat by, CGFloat x, CGFloat y) {
    if (c) pcurve(C(c)->_path, &G->ctm, CGPointMake(ax, ay), CGPointMake(bx, by), CGPointMake(x, y));
}
void CGContextAddQuadCurveToPoint(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat x, CGFloat y) { if (c) pquad(C(c)->_path, &G->ctm, CGPointMake(cx, cy), CGPointMake(x, y)); }
void CGContextAddArc(CGContextRef c, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat a1, int cw) { if (c) parc(C(c)->_path, &G->ctm, x, y, r, a0, sweep(a0, a1, cw)); }
void CGContextAddArcToPoint(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r) { if (c) parcto(C(c)->_path, &G->ctm, x1, y1, x2, y2, r); }
void CGContextAddRect(CGContextRef c, CGRect r) { if (c) prect(C(c)->_path, &G->ctm, r); }
void CGContextAddRects(CGContextRef c, const CGRect *r, size_t n) { for (size_t i = 0; i < n; i++) CGContextAddRect(c, r[i]); }
void CGContextAddEllipseInRect(CGContextRef c, CGRect r) { if (c) pellipse(C(c)->_path, &G->ctm, r); }
void CGContextAddPath(CGContextRef c, CGPathRef p) { if (c && p) pappend(C(c)->_path, &G->ctm, P(p)); }
void CGContextAddLines(CGContextRef c, const CGPoint *pts, size_t n) { if (c) CGPathAddLines((CGMutablePathRef)C(c)->_path, &G->ctm, pts, n); }
bool CGContextIsPathEmpty(CGContextRef c) { return !c || !C(c)->_path->_n; }
CGPoint CGContextGetPathCurrentPoint(CGContextRef c) { return c && C(c)->_path->_n ? CGContextConvertPointToUserSpace(c, C(c)->_path->_cur) : CGPointZero; }
CGRect CGContextGetPathBoundingBox(CGContextRef c) { return c && C(c)->_path->_n ? CGContextConvertRectToUserSpace(c, pbounds(C(c)->_path)) : CGRectNull; }
CGPathRef CGContextCopyPath(CGContextRef c) {
    if (!c) return NULL;
    CGAffineTransform inv = CGAffineTransformInvert(G->ctm);
    CGMutablePathRef p = CGPathCreateMutable(); pappend(P(p), &inv, C(c)->_path); return p;
}

/* ---------------------------------------------------------------- rasterizing */
static CGAffineTransform to_pixels(_MWCGContext *x) { return CGAffineTransformMake(1, 0, 0, -1, 0, (CGFloat)x->_h); } /* device y-up -> rows */
typedef struct Paint Paint;
struct Paint {
    void (*at)(const Paint *, int x, int y, float out[4]); /* premultiplied source at a pixel; NULL = solid */
    float solid[4];
    _MWCGImage *img; CGAffineTransform inv; BOOL nearest; float tint[4];
};
enum { S = 4 }; /* sub-rows per pixel row */
typedef void (*Sink)(_MWCGContext *, int y, int x0, int x1, const float *cov, void *ctx);
/* coverage of the shape (edges, pixel space) row by row, inside the clip box */
static void raster(_MWCGContext *x, Edges *E, BOOL eo, BOOL aa, Sink sink, void *ctx) {
    GState *g = x->_gs;
    if (!E->n) return;
    int y0 = (int)fmaxf(floorf(E->miny), g->cy0), y1 = (int)fminf(ceilf(E->maxy), g->cy1);
    int x0 = (int)fmaxf(floorf(E->minx), g->cx0), x1 = (int)fminf(ceilf(E->maxx) + 1, g->cx1);
    if (y0 >= y1 || x0 >= x1) return;
    float *cov = calloc((size_t)(x1 - x0 + 2), sizeof(float));
    size_t cap = 64; struct X { float x; int d; } *xs = malloc(cap * sizeof *xs);
    int subs = aa ? S : 1;
    Edge *a = &E->e[0], *b = &E->e[1];
    if (E->n == 2 && a->x0 == a->x1 && b->x0 == b->x1 && a->y0 == b->y0 && a->y1 == b->y1) {
        /* an axis-aligned rectangle (backgrounds, NSRectFill): exact coverage without scanning */
        float xa = fminf(a->x0, b->x0), xb = fmaxf(a->x0, b->x0), ya = a->y0, yb = a->y1;
        if (!aa) { xa = roundf(xa); xb = roundf(xb); ya = roundf(ya); yb = roundf(yb); }
        float *h = malloc((size_t)(x1 - x0) * sizeof(float));
        for (int i = x0; i < x1; i++) h[i - x0] = fmaxf(0, fminf(i + 1, xb) - fmaxf(i, xa));
        for (int y = y0; y < y1; y++) {
            float v = fmaxf(0, fminf(y + 1, yb) - fmaxf(y, ya));
            if (v <= 0) continue;
            for (int i = x0; i < x1; i++) cov[i - x0] = h[i - x0] * v;
            sink(x, y, x0, x1, cov, ctx);
        }
        free(h); free(xs); free(cov);
        return;
    }
    for (int y = y0; y < y1; y++) {
        int lo = x1, hi = x0;
        for (int s = 0; s < subs; s++) {
            float sy = y + (s + 0.5f) / subs;
            size_t n = 0;
            for (size_t i = 0; i < E->n; i++) {
                Edge *e = &E->e[i];
                if (sy < e->y0 || sy >= e->y1) continue;
                if (n == cap) { cap *= 2; xs = realloc(xs, cap * sizeof *xs); }
                xs[n].x = e->x0 + (sy - e->y0) * (e->x1 - e->x0) / (e->y1 - e->y0); xs[n].d = e->dir; n++;
            }
            for (size_t i = 1; i < n; i++) { struct X t = xs[i]; size_t j = i; while (j && xs[j - 1].x > t.x) { xs[j] = xs[j - 1]; j--; } xs[j] = t; }
            int wind = 0;
            for (size_t i = 0; i + 1 < n; i++) {
                wind += xs[i].d;
                BOOL in = eo ? (wind & 1) : wind != 0;
                if (!in) continue;
                float a = xs[i].x, b = xs[i + 1].x;
                if (!aa) { a = roundf(a); b = roundf(b); }
                a = fmaxf(a, x0); b = fminf(b, x1);
                if (a >= b) continue;
                int ia = (int)a, ib = (int)b;
                float w = 1.f / subs;
                if (ia == ib) cov[ia - x0] += (b - a) * w;
                else {
                    cov[ia - x0] += (ia + 1 - a) * w;
                    for (int k = ia + 1; k < ib; k++) cov[k - x0] += w;
                    if (ib < x1) cov[ib - x0] += (b - ib) * w;
                }
                if (ia < lo) lo = ia;
                if (ib + 1 > hi) hi = ib + 1 > x1 ? x1 : ib + 1;
            }
        }
        if (lo < hi) { sink(x, y, lo, hi, cov + (lo - x0), ctx); memset(cov + (lo - x0), 0, (size_t)(hi - lo) * sizeof(float)); }
    }
    free(xs); free(cov);
}
static void blend_sink(_MWCGContext *x, int y, int x0, int x1, const float *cov, void *ctx) {
    const Paint *p = ctx;
    GState *g = x->_gs;
    uint8_t *row = x->_data + (size_t)y * x->_bpr;
    const uint8_t *m = g->mask ? g->mask + (size_t)y * x->_w : NULL;
    for (int i = x0; i < x1; i++) {
        float c = cov[i - x0];
        if (c <= 0.002f) continue;
        if (c > 1) c = 1;
        if (m) { c *= m[i] / 255.f; if (c <= 0) continue; }
        float s[4], d[4];
        if (p->at) p->at(p, i, y, s); else memcpy(s, p->solid, sizeof s);
        uint8_t *px = row + (size_t)i * x->_f.bpp;
        px_load(&x->_f, px, d);
        if (g->blend == kCGBlendModeClear) for (int k = 0; k < 4; k++) d[k] *= 1 - c;
        else if (g->blend == kCGBlendModeCopy) { float a = c * g->alpha; for (int k = 0; k < 4; k++) d[k] = s[k] * a + d[k] * (1 - c); }
        else if (g->blend >= kCGBlendModeSourceIn && g->blend <= kCGBlendModePlusLighter && g->blend != kCGBlendModePlusDarker) {
            /* Porter-Duff on premultiplied S (source x alpha) and D, then the coverage lerps from D to the result */
            float S[4], sa, da = d[3];
            for (int k = 0; k < 4; k++) S[k] = s[k] * g->alpha;
            sa = S[3];
            for (int k = 0; k < 4; k++) {
                float r;
                switch (g->blend) {
                case kCGBlendModeSourceIn: r = S[k] * da; break;
                case kCGBlendModeSourceOut: r = S[k] * (1 - da); break;
                case kCGBlendModeSourceAtop: r = S[k] * da + d[k] * (1 - sa); break;
                case kCGBlendModeDestinationOver: r = S[k] * (1 - da) + d[k]; break;
                case kCGBlendModeDestinationIn: r = d[k] * sa; break;
                case kCGBlendModeDestinationOut: r = d[k] * (1 - sa); break;
                case kCGBlendModeDestinationAtop: r = S[k] * (1 - da) + d[k] * sa; break;
                case kCGBlendModeXOR: r = S[k] * (1 - da) + d[k] * (1 - sa); break;
                default: r = fminf(1, S[k] + d[k]); break;   /* plus lighter */
                }
                d[k] += c * (r - d[k]);
            }
        } else {
            float a = c * g->alpha, ia = 1 - s[3] * a;
            for (int k = 0; k < 4; k++) d[k] = s[k] * a + d[k] * ia;
        }
        px_store(&x->_f, px, d);
    }
}
static void solid(Paint *p, const float *col) {
    memset(p, 0, sizeof *p);
    p->solid[0] = col[0] * col[3]; p->solid[1] = col[1] * col[3]; p->solid[2] = col[2] * col[3]; p->solid[3] = col[3];
}
static void edges_of_path(_MWCGContext *x, _MWCGPath *path, Edges *E) {
    Polys ps = {0};
    flatten(path, to_pixels(x), &ps);
    for (size_t i = 0; i < ps.n; i++) if (ps.v[i].n > 2) edges_poly(E, ps.v[i].p, ps.v[i].n, NO);
    polys_free(&ps);
}
/* stroke outline of a path as polygons (pixel space), half width hw */
static void circle(Edges *E, CGPoint c, CGFloat r) {
    int n = (int)ceil(r * 2); if (n < 8) n = 8; if (n > 64) n = 64;
    CGPoint pts[64];
    for (int i = 0; i < n; i++) pts[i] = CGPointMake(c.x + r * cos(2 * M_PI * i / n), c.y + r * sin(2 * M_PI * i / n));
    edges_oriented(E, pts, (size_t)n);
}
static void stroke_edges(_MWCGContext *x, _MWCGPath *path, CGFloat hw, Edges *E) {
    GState *g = x->_gs;
    Polys ps = {0};
    flatten(path, to_pixels(x), &ps);
    for (size_t k = 0; k < ps.n; k++) {
        Poly *l = &ps.v[k];
        BOOL closed = ps.closed[k];
        if (closed && l->n > 2 && hypot(l->p[0].x - l->p[l->n - 1].x, l->p[0].y - l->p[l->n - 1].y) < 1e-9) l->n--;
        size_t n = l->n;
        if (n < 2) {
            if (n == 1 && g->cap == kCGLineCapRound) circle(E, l->p[0], hw);
            else if (n == 1 && g->cap == kCGLineCapSquare) {
                CGPoint q = l->p[0], r[4] = {{q.x - hw, q.y - hw}, {q.x + hw, q.y - hw}, {q.x + hw, q.y + hw}, {q.x - hw, q.y + hw}};
                edges_oriented(E, r, 4);
            }
            continue;
        }
        size_t nseg = closed ? n : n - 1;
        for (size_t i = 0; i < nseg; i++) {
            CGPoint a = l->p[i], b = l->p[(i + 1) % n];
            CGFloat dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy);
            if (len < 1e-9) continue;
            CGFloat ux = dx / len, uy = dy / len, nx = -uy * hw, ny = ux * hw;
            if (!closed && g->cap == kCGLineCapSquare) {
                if (i == 0) { a.x -= ux * hw; a.y -= uy * hw; }
                if (i == nseg - 1) { b.x += ux * hw; b.y += uy * hw; }
            }
            CGPoint q[4] = {{a.x + nx, a.y + ny}, {b.x + nx, b.y + ny}, {b.x - nx, b.y - ny}, {a.x - nx, a.y - ny}};
            edges_oriented(E, q, 4);
        }
        /* joins at the inner vertices (every vertex when closed) */
        for (size_t i = closed ? 0 : 1; i < (closed ? n : n - 1); i++) {
            CGPoint v = l->p[i], a = l->p[(i + n - 1) % n], b = l->p[(i + 1) % n];
            CGFloat d1x = v.x - a.x, d1y = v.y - a.y, d2x = b.x - v.x, d2y = b.y - v.y;
            CGFloat l1 = hypot(d1x, d1y), l2 = hypot(d2x, d2y);
            if (l1 < 1e-9 || l2 < 1e-9) continue;
            d1x /= l1; d1y /= l1; d2x /= l2; d2y /= l2;
            CGFloat cross = d1x * d2y - d1y * d2x;
            if (fabs(cross) < 1e-6 && d1x * d2x + d1y * d2y > 0) continue; /* straight on */
            if (g->join == kCGLineJoinRound) { circle(E, v, hw); continue; }
            CGFloat s = cross > 0 ? -1 : 1; /* the outer side */
            CGPoint p1 = {v.x - d1y * hw * s, v.y + d1x * hw * s}, p2 = {v.x - d2y * hw * s, v.y + d2x * hw * s};
            CGFloat cosang = -(d1x * d2x + d1y * d2y), half = acos(fmax(-1, fmin(1, cosang))) / 2;
            if (g->join == kCGLineJoinMiter && half > 1e-6 && 1 / sin(half) <= g->miter) {
                CGFloat mx = (p1.x - v.x) + (p2.x - v.x), my = (p1.y - v.y) + (p2.y - v.y), ml = hypot(mx, my);
                if (ml > 1e-9) {
                    CGFloat dist = hw / sin(half);
                    CGPoint m = {v.x + mx / ml * dist, v.y + my / ml * dist}, q[4] = {v, p1, m, p2};
                    edges_oriented(E, q, 4);
                    continue;
                }
            }
            CGPoint t[3] = {v, p1, p2};
            edges_oriented(E, t, 3);
        }
        if (!closed && g->cap == kCGLineCapRound) { circle(E, l->p[0], hw); circle(E, l->p[n - 1], hw); }
    }
    polys_free(&ps);
}
static CGFloat line_scale(GState *g) { return sqrt(fabs(g->ctm.a * g->ctm.d - g->ctm.b * g->ctm.c)); }
static void do_fill(_MWCGContext *x, _MWCGPath *path, BOOL eo, const float *col) {
    Edges E = {0};
    edges_of_path(x, path, &E);
    Paint p; solid(&p, col);
    raster(x, &E, eo, x->_gs->aa, blend_sink, &p);
    free(E.e);
}
static void do_stroke(_MWCGContext *x, _MWCGPath *path) {
    Edges E = {0};
    CGFloat hw = x->_gs->lw * line_scale(x->_gs) / 2;
    if (hw <= 0) hw = 0.5; /* lineWidth 0: the thinnest line the device can draw */
    stroke_edges(x, path, hw, &E);
    Paint p; solid(&p, x->_gs->stroke);
    raster(x, &E, NO, x->_gs->aa, blend_sink, &p);
    free(E.e);
}
void CGContextDrawPath(CGContextRef c, CGPathDrawingMode m) {
    if (!c) return;
    _MWCGContext *x = C(c);
    if (m == kCGPathFill || m == kCGPathFillStroke) do_fill(x, x->_path, NO, G->fill);
    if (m == kCGPathEOFill || m == kCGPathEOFillStroke) do_fill(x, x->_path, YES, G->fill);
    if (m == kCGPathStroke || m == kCGPathFillStroke || m == kCGPathEOFillStroke) do_stroke(x, x->_path);
    x->_path->_n = 0;
}
void CGContextFillPath(CGContextRef c) { CGContextDrawPath(c, kCGPathFill); }
void CGContextEOFillPath(CGContextRef c) { CGContextDrawPath(c, kCGPathEOFill); }
void CGContextStrokePath(CGContextRef c) { CGContextDrawPath(c, kCGPathStroke); }
/* the rect helpers keep the current path (CG builds them on the side) */
static void with_path(CGContextRef c, void (^build)(_MWCGPath *), CGPathDrawingMode m) {
    if (!c) return;
    _MWCGPath *saved = C(c)->_path;
    C(c)->_path = [[_MWCGPath alloc] init];
    build(C(c)->_path);
    CGContextDrawPath(c, m);
    [C(c)->_path release];
    C(c)->_path = saved;
}
void CGContextFillRect(CGContextRef c, CGRect r) { with_path(c, ^(_MWCGPath *p) { prect(p, &G->ctm, r); }, kCGPathFill); }
void CGContextFillRects(CGContextRef c, const CGRect *r, size_t n) { with_path(c, ^(_MWCGPath *p) { for (size_t i = 0; i < n; i++) prect(p, &G->ctm, r[i]); }, kCGPathFill); }
void CGContextStrokeRect(CGContextRef c, CGRect r) { with_path(c, ^(_MWCGPath *p) { prect(p, &G->ctm, r); }, kCGPathStroke); }
void CGContextStrokeRectWithWidth(CGContextRef c, CGRect r, CGFloat w) {
    if (!c) return;
    CGFloat old = G->lw; G->lw = w; CGContextStrokeRect(c, r); G->lw = old;
}
void CGContextFillEllipseInRect(CGContextRef c, CGRect r) { with_path(c, ^(_MWCGPath *p) { pellipse(p, &G->ctm, r); }, kCGPathFill); }
void CGContextStrokeEllipseInRect(CGContextRef c, CGRect r) { with_path(c, ^(_MWCGPath *p) { pellipse(p, &G->ctm, r); }, kCGPathStroke); }
void CGContextStrokeLineSegments(CGContextRef c, const CGPoint *pts, size_t n) {
    with_path(c, ^(_MWCGPath *p) { for (size_t i = 0; i + 1 < n; i += 2) { pmove(p, &G->ctm, pts[i].x, pts[i].y); pline(p, &G->ctm, pts[i + 1].x, pts[i + 1].y); } }, kCGPathStroke);
}
void CGContextClearRect(CGContextRef c, CGRect r) {
    if (!c) return;
    int old = G->blend; G->blend = kCGBlendModeClear;
    float k[4] = {0, 0, 0, 1};
    _MWCGPath *p = [[_MWCGPath alloc] init]; prect(p, &G->ctm, r);
    do_fill(C(c), p, NO, k);
    [p release];
    G->blend = old;
}

/* ---------------------------------------------------------------- clipping */
static void mask_sink(_MWCGContext *x, int y, int x0, int x1, const float *cov, void *ctx) {
    uint8_t *m = (uint8_t *)ctx + (size_t)y * x->_w;
    for (int i = x0; i < x1; i++) m[i] = u8(cov[i - x0]);
}
static void clip_path(_MWCGContext *x, _MWCGPath *path, BOOL eo) {
    GState *g = x->_gs;
    Edges E = {0};
    edges_of_path(x, path, &E);
    if (!E.n) { g->cx1 = g->cx0; g->cy1 = g->cy0; free(E.e); return; } /* empty path: nothing is drawable */
    /* an axis-aligned rectangle on whole pixels only shrinks the clip box */
    BOOL box = E.n == 2 && E.e[0].x0 == E.e[0].x1 && E.e[1].x0 == E.e[1].x1 && E.minx == floorf(E.minx) && E.maxx == floorf(E.maxx) &&
               E.miny == floorf(E.miny) && E.maxy == floorf(E.maxy);
    if (!box) {
        uint8_t *m = calloc(x->_w, x->_h);
        raster(x, &E, eo, g->aa, mask_sink, m);
        if (g->mask) for (size_t i = 0, n = x->_w * x->_h; i < n; i++) m[i] = (uint8_t)((m[i] * g->mask[i] + 127) / 255);
        free(g->mask); g->mask = m;
    }
    g->cx0 = (int)fmaxf(g->cx0, floorf(E.minx)); g->cy0 = (int)fmaxf(g->cy0, floorf(E.miny));
    g->cx1 = (int)fminf(g->cx1, ceilf(E.maxx)); g->cy1 = (int)fminf(g->cy1, ceilf(E.maxy));
    if (g->cx1 < g->cx0) g->cx1 = g->cx0;
    if (g->cy1 < g->cy0) g->cy1 = g->cy0;
    free(E.e);
}
void CGContextClip(CGContextRef c) { if (c) { clip_path(C(c), C(c)->_path, NO); C(c)->_path->_n = 0; } }
void CGContextEOClip(CGContextRef c) { if (c) { clip_path(C(c), C(c)->_path, YES); C(c)->_path->_n = 0; } }
void CGContextClipToRect(CGContextRef c, CGRect r) {
    if (!c) return;
    _MWCGPath *p = [[_MWCGPath alloc] init]; prect(p, &G->ctm, r); clip_path(C(c), p, NO); [p release];
}
void CGContextClipToRects(CGContextRef c, const CGRect *r, size_t n) {
    if (!c) return;
    _MWCGPath *p = [[_MWCGPath alloc] init];
    for (size_t i = 0; i < n; i++) prect(p, &G->ctm, r[i]);
    clip_path(C(c), p, NO); [p release];
}
CGRect CGContextGetClipBoundingBox(CGContextRef c) {
    if (!c) return CGRectNull;
    _MWCGContext *x = C(c);
    CGRect dev = CGRectMake(G->cx0, (CGFloat)x->_h - G->cy1, G->cx1 - G->cx0, G->cy1 - G->cy0);
    return CGContextConvertRectToUserSpace(c, dev);
}

/* ---------------------------------------------------------------- images */
static void texel(const _MWCGImage *i, int u, int v, float out[4]) {
    if (u < 0) u = 0; if (v < 0) v = 0;
    if (u >= (int)i->_w) u = (int)i->_w - 1; if (v >= (int)i->_h) v = (int)i->_h - 1;
    px_load(&i->_f, i->_px + (size_t)v * i->_bpr + (size_t)u * i->_f.bpp, out);
}
static void image_at(const Paint *p, int x, int y, float out[4]) {
    CGPoint q = CGPointApplyAffineTransform(CGPointMake(x + 0.5, y + 0.5), p->inv);
    const _MWCGImage *i = p->img;
    if (p->nearest) texel(i, (int)floor(q.x), (int)floor(q.y), out);
    else {
        CGFloat fx = q.x - 0.5, fy = q.y - 0.5;
        int u = (int)floor(fx), v = (int)floor(fy);
        float ax = (float)(fx - u), ay = (float)(fy - v), t[4][4];
        texel(i, u, v, t[0]); texel(i, u + 1, v, t[1]); texel(i, u, v + 1, t[2]); texel(i, u + 1, v + 1, t[3]);
        for (int k = 0; k < 4; k++) out[k] = (t[0][k] * (1 - ax) + t[1][k] * ax) * (1 - ay) + (t[2][k] * (1 - ax) + t[3][k] * ax) * ay;
    }
    if (i->_mask) { float a = out[3]; for (int k = 0; k < 4; k++) out[k] = p->tint[k] * a; } /* masks paint the fill color */
}
void CGContextDrawImage(CGContextRef c, CGRect r, CGImageRef img) {
    _MWCGImage *i = (id)img;
    if (!c || !i || !i->_f.ok || r.size.width == 0 || r.size.height == 0) return;
    _MWCGContext *x = C(c);
    /* image pixel (u, v from the top) -> user space -> device -> pixel rows */
    CGAffineTransform m = CGAffineTransformMake(r.size.width / i->_w, 0, 0, -r.size.height / i->_h, r.origin.x, r.origin.y + r.size.height);
    m = CGAffineTransformConcat(CGAffineTransformConcat(m, G->ctm), to_pixels(x));
    Paint p = {0};
    p.at = image_at; p.img = i; p.inv = CGAffineTransformInvert(m);
    p.nearest = G->interp == kCGInterpolationNone;
    /* a 1:1 axis-aligned blit on whole pixels samples exactly */
    if (fabs(fabs(m.a) - 1) < 1e-6 && fabs(fabs(m.d) - 1) < 1e-6 && m.b == 0 && m.c == 0 && m.tx == round(m.tx) && m.ty == round(m.ty)) p.nearest = YES;
    p.tint[0] = G->fill[0] * G->fill[3]; p.tint[1] = G->fill[1] * G->fill[3]; p.tint[2] = G->fill[2] * G->fill[3]; p.tint[3] = G->fill[3];
    Edges E = {0};
    CGPoint q[4] = {CGPointApplyAffineTransform(CGPointMake(0, 0), m), CGPointApplyAffineTransform(CGPointMake(i->_w, 0), m),
                    CGPointApplyAffineTransform(CGPointMake(i->_w, i->_h), m), CGPointApplyAffineTransform(CGPointMake(0, i->_h), m)};
    edges_poly(&E, q, 4, NO);
    raster(x, &E, NO, G->aa, blend_sink, &p);
    free(E.e);
}

/* ---------------------------------------------------------------- path queries */
bool CGPathContainsPoint(CGPathRef p, const CGAffineTransform *t, CGPoint pt, bool eo) {
    if (!p) return false;
    Polys ps = {0};
    flatten(P(p), t ? *t : CGAffineTransformIdentity, &ps);
    int wind = 0;
    for (size_t k = 0; k < ps.n; k++) {
        Poly *l = &ps.v[k];
        for (size_t i = 0; i < l->n && l->n > 2; i++) {
            CGPoint a = l->p[i], b = l->p[(i + 1) % l->n];
            if ((a.y <= pt.y) != (b.y <= pt.y)) {
                CGFloat x = a.x + (pt.y - a.y) * (b.x - a.x) / (b.y - a.y);
                if (x > pt.x) wind += b.y > a.y ? 1 : -1;
            }
        }
    }
    polys_free(&ps);
    return eo ? (wind & 1) : wind != 0;
}
void CGPathApply(CGPathRef p, void *info, CGPathApplierFunction f) {
    if (!p || !f) return;
    for (size_t i = 0; i < P(p)->_n; i++) {
        Elem *e = &P(p)->_e[i];
        CGPathElement el = {(CGPathElementType)e->type, e->p};
        f(info, &el);
    }
}
/* view clipping: the box only (no mask), on whole device pixels; rotated CTMs fall back to a path clip */
void _mwCGContextClipToRectAligned(CGContextRef c, CGRect r) {
    if (!c) return;
    GState *g = G;
    if (g->ctm.b != 0 || g->ctm.c != 0) { CGContextClipToRect(c, r); return; }
    CGRect d = CGRectApplyAffineTransform(r, g->ctm);
    int h = (int)C(c)->_h;
    int x0 = (int)lround(d.origin.x), x1 = (int)lround(d.origin.x + d.size.width);
    int y0 = h - (int)lround(d.origin.y + d.size.height), y1 = h - (int)lround(d.origin.y);
    if (x0 > g->cx0) g->cx0 = x0; if (y0 > g->cy0) g->cy0 = y0;
    if (x1 < g->cx1) g->cx1 = x1; if (y1 < g->cy1) g->cy1 = y1;
    if (g->cx1 < g->cx0) g->cx1 = g->cx0;
    if (g->cy1 < g->cy0) g->cy1 = g->cy0;
}
