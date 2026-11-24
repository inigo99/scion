/* layout.m — Auto Layout: the active constraints of a view subtree, solved as weighted least squares.
 * Variables: the edges (left, right, top, bottom) of every view in the subtree that does not translate its autoresizing
 * mask into constraints (and is not placed by a stack or grid view), in the root view's coordinates with y growing
 * downwards whatever the views' flipping (as in Auto Layout: top + 20 is 20 points lower). Every other view or
 * layout guide a constraint mentions is a constant (its current frame).
 * Each constraint becomes a residual weighted by its priority (required ≫ high ≫ low); inequalities only count while they
 * are violated (an active set, grown until nothing is violated); intrinsic sizes add hugging (≤) and compression (≥)
 * terms with the view's priorities; a very weak term keeps each edge where it was, so an underconstrained view stays put.
 * Two passes: a wrapping label's height depends on the width the first pass gave it.
 * ponytail: dense normal equations (fine for a few hundred edges); no visual format language; positions times a
 * multiplier are taken in the root's coordinates (Auto Layout uses the nearest common ancestor's). */
#import "internal.h"
#include <stdlib.h>
#include <string.h>

typedef struct { double c[4]; int v[4]; int n; double k; } Expr; /* sum c[i] * var[v[i]] + k */
typedef struct { Expr e; int rel; double w; BOOL active; } Term;    /* e (rel) 0 */

typedef struct {
    NSView *root; BOOL flipped;
    NSMutableArray *views;   /* variable views; view i owns variables 4i..4i+3: left right top bottom (y down) */
    Term *t; size_t nt, cap;
} Sys;

static double weight(double priority) { return pow(10, priority / 125); } /* 1000 -> 1e8, 750 -> 1e6, 250 -> 1e2 */
static void term(Sys *s, Expr e, int rel, double priority) {
    if (s->nt == s->cap) { s->cap = s->cap ? s->cap * 2 : 64; s->t = realloc(s->t, s->cap * sizeof(Term)); }
    s->t[s->nt++] = (Term){e, rel, weight(priority), rel == NSLayoutRelationEqual};
}
static void add(Expr *e, int var, double c) {
    for (int i = 0; i < e->n; i++) if (e->v[i] == var) { e->c[i] += c; return; }
    e->v[e->n] = var; e->c[e->n] = c; e->n++;
}
static NSRect rect_in_root(Sys *s, id item) {
    if ([item isKindOfClass:[NSLayoutGuide class]]) { NSView *o = [item owningView]; return o ? [o convertRect:o.bounds toView:s->root] : NSZeroRect; }
    NSView *v = item;
    return v == s->root ? v.bounds : [v convertRect:v.bounds toView:s->root];
}
/* the vertical span of r (root coordinates) with y growing downwards */
static void down(Sys *s, NSRect r, double *top, double *bottom) {
    if (s->flipped) { *top = NSMinY(r); *bottom = NSMaxY(r); } else { *top = -NSMaxY(r); *bottom = -NSMinY(r); }
}
/* e += m * attribute(item) */
static void attr(Sys *s, Expr *e, id item, NSLayoutAttribute a, double m) {
    if (!item || a == NSLayoutAttributeNotAnAttribute) return;
    /* a guide of a variable view moves with it: its edges are the owner's, inset (the safe area) */
    double off_lo = 0, off_hi = 0;
    if ([item isKindOfClass:[NSLayoutGuide class]] && [item owningView] && [s->views indexOfObjectIdenticalTo:[item owningView]] != NSNotFound) {
        NSLayoutGuide *g = item; NSView *o = g.owningView;
        NSEdgeInsets in = g->_mwSafeArea ? o.safeAreaInsets : NSEdgeInsetsZero;
        BOOL axx = a == NSLayoutAttributeLeft || a == NSLayoutAttributeLeading || a == NSLayoutAttributeRight || a == NSLayoutAttributeTrailing ||
                   a == NSLayoutAttributeWidth || a == NSLayoutAttributeCenterX;
        off_lo = axx ? in.left : in.top; off_hi = axx ? -in.right : -in.bottom;
        item = o;
    }
    NSUInteger i = [s->views indexOfObjectIdenticalTo:item]; i = i == NSNotFound ? 0 : i + 1; /* 0: a constant */
    BOOL ax = a == NSLayoutAttributeLeft || a == NSLayoutAttributeLeading || a == NSLayoutAttributeRight || a == NSLayoutAttributeTrailing ||
              a == NSLayoutAttributeWidth || a == NSLayoutAttributeCenterX;
    /* the low and high edge on this axis, as coefficients on (lo, hi) */
    double lo = 0, hi = 0;
    switch (a) {
    case NSLayoutAttributeLeft: case NSLayoutAttributeLeading: case NSLayoutAttributeTop: case NSLayoutAttributeFirstBaseline: lo = 1; break;
    case NSLayoutAttributeRight: case NSLayoutAttributeTrailing: case NSLayoutAttributeBottom: case NSLayoutAttributeLastBaseline: hi = 1; break;
    case NSLayoutAttributeWidth: case NSLayoutAttributeHeight: lo = -1; hi = 1; break;
    case NSLayoutAttributeCenterX: case NSLayoutAttributeCenterY: lo = hi = 0.5; break;
    default: break;
    }
    if (i) {
        int base = (int)(i - 1) * 4 + (ax ? 0 : 2);
        if (lo) add(e, base, lo * m);
        if (hi) add(e, base + 1, hi * m);
        e->k += m * (lo * off_lo + hi * off_hi);
    } else {
        NSRect r = rect_in_root(s, item);
        double l = NSMinX(r), h = NSMaxX(r);
        if (!ax) down(s, r, &l, &h);
        e->k += m * (lo * l + hi * h);
    }
}
static BOOL placed_by_container(NSView *v) {
    return [v.superview isKindOfClass:[NSStackView class]] || [v.superview isKindOfClass:[NSGridView class]];
}
static void collect(Sys *s, NSView *v, NSMutableArray *cons, BOOL isRoot) {
    if (!isRoot && !v.translatesAutoresizingMaskIntoConstraints && !placed_by_container(v)) {
        [s->views addObject:v];
    }
    for (NSLayoutConstraint *c in v.constraints) if (c.isActive) [cons addObject:c];
    for (NSView *sub in v.subviews) collect(s, sub, cons, NO);
}
/* Gaussian elimination with partial pivoting: A x = b, n x n (A and b are destroyed) */
static void gauss(double *A, double *b, double *x, int n) {
    for (int c = 0; c < n; c++) {
        int p = c;
        for (int r = c + 1; r < n; r++) if (fabs(A[r * n + c]) > fabs(A[p * n + c])) p = r;
        if (p != c) { for (int k = 0; k < n; k++) { double t = A[c * n + k]; A[c * n + k] = A[p * n + k]; A[p * n + k] = t; } double t = b[c]; b[c] = b[p]; b[p] = t; }
        double d = A[c * n + c];
        if (fabs(d) < 1e-300) continue;
        for (int r = c + 1; r < n; r++) {
            double f = A[r * n + c] / d;
            if (f == 0) continue;
            for (int k = c; k < n; k++) A[r * n + k] -= f * A[c * n + k];
            b[r] -= f * b[c];
        }
    }
    for (int r = n - 1; r >= 0; r--) {
        double v = b[r];
        for (int k = r + 1; k < n; k++) v -= A[r * n + k] * x[k];
        x[r] = fabs(A[r * n + r]) < 1e-300 ? 0 : v / A[r * n + r];
    }
}
static double eval(const Expr *e, const double *x) { double v = e->k; for (int i = 0; i < e->n; i++) v += e->c[i] * x[e->v[i]]; return v; }
/* rootSize: the root's size is a variable too (a window's content view): it stays put at priority 500, as a window does
   (NSLayoutPriorityWindowSizeStayPut), so required and compression-resistance constraints can change it; out: the size */
static BOOL solve_once(NSView *root, BOOL *any, NSSize *rootSize) {
    Sys s = {root, root.isFlipped, [NSMutableArray array], NULL, 0, 0};
    NSMutableArray *cons = [NSMutableArray array];
    if (rootSize) [s.views addObject:root];
    collect(&s, root, cons, YES);
    if ([s.views count] <= (rootSize ? 1u : 0u) || ![cons count]) { *any = NO; return NO; }
    *any = YES;
    int n = (int)[s.views count] * 4;
    double *cur = calloc((size_t)n, sizeof(double)), *x = calloc((size_t)n, sizeof(double));
    for (NSUInteger i = 0; i < [s.views count]; i++) {
        NSRect r = rect_in_root(&s, s.views[i]);
        cur[i * 4] = NSMinX(r); cur[i * 4 + 1] = NSMaxX(r); down(&s, r, &cur[i * 4 + 2], &cur[i * 4 + 3]);
    }
    for (NSLayoutConstraint *c in cons) {
        Expr e = {{0}, {0}, 0, 0};
        attr(&s, &e, c.firstItem, c.firstAttribute, 1);
        if (c.secondItem) attr(&s, &e, c.secondItem, c.secondAttribute, -c.multiplier);
        e.k -= c.constant;
        if (!e.n) continue; /* only constants: nothing to solve */
        term(&s, e, (int)c.relation, c.priority);
    }
    for (NSUInteger i = 0; i < [s.views count]; i++) {
        NSView *v = s.views[i];
        NSSize in = [v intrinsicContentSize];
        for (int axis = 0; axis < 2; axis++) {
            double size = axis ? in.height : in.width;
            Expr w = {{-1, 1}, {(int)i * 4 + axis * 2, (int)i * 4 + axis * 2 + 1}, 2, 0};
            if (size >= 0) {
                w.k = -size;
                term(&s, w, NSLayoutRelationLessThanOrEqual, [v contentHuggingPriorityForOrientation:axis]);
                term(&s, w, NSLayoutRelationGreaterThanOrEqual, [v contentCompressionResistancePriorityForOrientation:axis]);
            }
            w.k = 0;
            term(&s, w, NSLayoutRelationGreaterThanOrEqual, NSLayoutPriorityRequired); /* no negative sizes */
        }
    }
    if (rootSize) {   /* the root's top-left corner is fixed; its size holds at 500 */
        for (int k = 0; k < 4; k++) {
            Expr e = {{1}, {k}, 1, -cur[k]};
            if (k == 0 || k == 2) term(&s, e, NSLayoutRelationEqual, NSLayoutPriorityRequired);
        }
        Expr w = {{-1, 1}, {0, 1}, 2, -(cur[1] - cur[0])}, h = {{-1, 1}, {2, 3}, 2, -(cur[3] - cur[2])};
        term(&s, w, NSLayoutRelationEqual, 500); term(&s, h, NSLayoutRelationEqual, 500);
    }
    double *A = malloc((size_t)n * n * sizeof(double)), *b = malloc((size_t)n * sizeof(double));
    for (int round = 0; round < 30; round++) {
        memset(A, 0, (size_t)n * n * sizeof(double)); memset(b, 0, (size_t)n * sizeof(double));
        for (int j = 0; j < n; j++) { A[j * n + j] = 1e-2; b[j] = 1e-2 * cur[j]; } /* stay where you are, weakly */
        for (size_t k = 0; k < s.nt; k++) {
            Term *t = &s.t[k];
            if (!t->active) continue;
            for (int p = 0; p < t->e.n; p++) {
                for (int q = 0; q < t->e.n; q++) A[t->e.v[p] * n + t->e.v[q]] += t->w * t->e.c[p] * t->e.c[q];
                b[t->e.v[p]] -= t->w * t->e.c[p] * t->e.k;
            }
        }
        gauss(A, b, x, n);
        /* an inequality joins while violated, and leaves when it holds the solution on the wrong side: as a penalty, a
         * binding >= stays slightly violated (it pulls up); one that is slightly exceeded is pushing down instead */
        BOOL moved = NO;
        for (size_t k = 0; k < s.nt; k++) {
            Term *t = &s.t[k];
            if (t->rel == NSLayoutRelationEqual) continue;
            double r = eval(&t->e, x) * (t->rel == NSLayoutRelationGreaterThanOrEqual ? 1 : -1); /* >= 0 when it holds */
            if (!t->active && r < -0.01) { t->active = YES; moved = YES; }
            else if (t->active && r > 1e-6) { t->active = NO; moved = YES; }
        }
        if (!moved) break;
    }
    /* frames, parents first (the views are in tree order), on whole device pixels */
    BOOL changed = NO;
    if (rootSize) {
        CGFloat sc = root.window ? root.window.backingScaleFactor : mw_scale0();
        *rootSize = NSMakeSize(round((x[1] - x[0]) * sc) / sc, round((x[3] - x[2]) * sc) / sc);
    }
    for (NSUInteger i = rootSize ? 1 : 0; i < [s.views count]; i++) {
        NSView *v = s.views[i];
        CGFloat sc = v.window ? v.window.backingScaleFactor : mw_scale0();
        #define PX(q) (round((q) * sc) / sc)
        double top = s.flipped ? x[i * 4 + 2] : -x[i * 4 + 3], bottom = s.flipped ? x[i * 4 + 3] : -x[i * 4 + 2]; /* back to the root's y */
        NSRect r = NSMakeRect(PX(x[i * 4]), PX(top), PX(x[i * 4 + 1]) - PX(x[i * 4]), PX(bottom) - PX(top));
        #undef PX
        r.size.width = fmax(0, r.size.width); r.size.height = fmax(0, r.size.height);
        NSRect f = v.superview == root ? r : [v.superview convertRect:r fromView:root];
        if (fabs(f.origin.x - v.frame.origin.x) > 1e-3 || fabs(f.origin.y - v.frame.origin.y) > 1e-3 ||
            fabs(f.size.width - v.frame.size.width) > 1e-3 || fabs(f.size.height - v.frame.size.height) > 1e-3) { v.frame = f; changed = YES; }
    }
    free(A); free(b); free(cur); free(x); free(s.t);
    return changed;
}
void mw_solve_layout(NSView *root) {
    BOOL any = NO;
    NSWindow *w = root.window;
    BOOL sizesWindow = w && [w _mwRootView] == root && !w.isZoomed && !(w.styleMask & NSWindowStyleMaskFullScreen);
    for (int pass = 0; pass < 3; pass++) {
        NSSize sz = root.frame.size;
        BOOL changed = solve_once(root, &any, sizesWindow ? &sz : NULL);
        if (!any) break;
        if (sizesWindow && (fabs(sz.width - root.frame.size.width) > 0.5 || fabs(sz.height - root.frame.size.height) > 0.5)) {
            /* the content needs another size: the window follows (top-left corner kept), then lay out again */
            NSRect f = w.frame, c = [w contentRectForFrameRect:f];
            c.origin.y += c.size.height - sz.height; c.size = sz;
            [w setFrame:[w frameRectForContentRect:c] display:NO];
            continue;
        }
        if (!changed) break;
    }
}
