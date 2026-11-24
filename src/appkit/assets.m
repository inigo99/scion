/* assets.m — compiled asset catalogs (Assets.car): named colors (+[NSColor colorNamed:]) and images (+[NSImage imageNamed:]).
 * An Assets.car is a BOM store (big-endian block table and named variables) holding B-trees: FACETKEYS (name ->
 * attributes, among them the identifier, attribute 17), APPEARANCEKEYS (appearance name -> id), KEYFORMAT (which attribute
 * each slot of a rendition key holds) and RENDITIONS (key -> a CSI rendition: header 'CTSI', then for a color, layout
 * 1009, a 'COLR' payload of doubles). scion draws in dark mode, so the dark variant wins when there is one.
 * An image, layout 1003, is usually a link (TLV 1010 'INLK': a rectangle, y up, and the key of a packed atlas, layout 1004);
 * the atlas payload is 'MLEC' (compression 11) around a 'dmp2' header and an LZFSE stream, decoded as deepmap2.
 * ponytail: deepmap2 Default (YCoCg, alpha) and Lossless gray+alpha only; palette and KCBC chunks (big app icons) not yet */
#import "internal.h"

enum { ATTR_APPEARANCE = 7, ATTR_IDENTIFIER = 17, ATTR_SCALE = 12, LAYOUT_IMAGE = 1003, LAYOUT_ATLAS = 1004, LAYOUT_COLOR = 1009 };

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }

typedef struct { const uint8_t *d; size_t n; uint32_t idx, nblocks; } Bom;
static const uint8_t *block(Bom *b, uint32_t i, uint32_t *len) {
    if (i >= b->nblocks) return NULL;
    uint32_t a = be32(b->d + b->idx + 4 + 8 * i), l = be32(b->d + b->idx + 8 + 8 * i);
    if ((size_t)a + l > b->n) return NULL;
    if (len) *len = l;
    return b->d + a;
}
static int32_t var(Bom *b, const char *name) {
    uint32_t vo = be32(b->d + 24);
    if (vo + 4 > b->n) return -1;
    uint32_t n = be32(b->d + vo), p = vo + 4;
    for (uint32_t i = 0; i < n && p + 5 <= b->n; i++) {
        uint32_t idx = be32(b->d + p); uint8_t l = b->d[p + 4];
        if (strlen(name) == l && !memcmp(b->d + p + 5, name, l)) return (int32_t)idx;
        p += 5 + l;
    }
    return -1;
}
/* every (key, value) of a tree */
static void walk(Bom *b, uint32_t path, int depth, void (^f)(const uint8_t *k, uint32_t kl, const uint8_t *v, uint32_t vl)) {
    for (int guard = 0; path && guard < 100000 && depth < 32; guard++) {
        uint32_t pl; const uint8_t *p = block(b, path, &pl);
        if (!p || pl < 12) return;
        uint16_t leaf = (uint16_t)(p[0] << 8 | p[1]), cnt = (uint16_t)(p[2] << 8 | p[3]);
        for (uint16_t i = 0; i < cnt && 12 + 8u * i + 8 <= pl; i++) {
            uint32_t vi = be32(p + 12 + 8 * i), ki = be32(p + 16 + 8 * i);
            if (!leaf) { walk(b, vi, depth + 1, f); continue; }
            uint32_t kl, vl; const uint8_t *k = block(b, ki, &kl), *v = block(b, vi, &vl);
            if (k && v) f(k, kl, v, vl);
        }
        if (!leaf) return;
        path = be32(p + 4);   /* the next leaf */
    }
}
static void tree(Bom *b, const char *name, void (^f)(const uint8_t *, uint32_t, const uint8_t *, uint32_t)) {
    int32_t t = var(b, name); uint32_t tl;
    const uint8_t *h = t < 0 ? NULL : block(b, (uint32_t)t, &tl);
    if (!h || tl < 21 || memcmp(h, "tree", 4)) return;
    walk(b, be32(h + 8), 0, f);
}

size_t mw_lzfse_decode(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size);

/* deepmap2 -> RGBA premultiplied (malloc'd, w*h*4) */
static int tdiv2(int v) { return v / 2; }   /* C division truncates toward zero */
static uint8_t clamp8(int v) { return (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v); }
static uint8_t *dmp2_decode(const uint8_t *p, size_t n, uint32_t *ow, uint32_t *oh) {
    if (n < 16 || memcmp(p, "dmp2", 4)) return NULL;
    uint8_t type = p[4], version = p[5], pf = p[7];
    uint32_t w = le16(p + 8), h = le16(p + 10), len = le32(p + 12);
    size_t px = (size_t)w * h;
    if (!px || 16 + (size_t)len > n) return NULL;
    size_t cap = px * 8 + h + 1024;
    uint8_t *raw = malloc(cap), *out = calloc(px, 4);
    size_t got = mw_lzfse_decode(raw, cap, p + 16, len);
    BOOL ok = NO;
    if (type == 3 && pf == 2 && got >= px * 2) {   /* lossless gray + alpha, interleaved */
        for (size_t i = 0; i < px; i++) { out[4 * i] = out[4 * i + 1] = out[4 * i + 2] = raw[2 * i]; out[4 * i + 3] = raw[2 * i + 1]; }
        ok = YES;
    } else if (type == 2 && (pf == 3 || pf == 4)) {   /* [alpha plane][a predictor per row][high bytes][low bytes] of zigzag YCoCg residuals */
        size_t an = pf == 4 ? px : 0, m = px * 3;
        if (got >= an + h + 2 * m) {
            const uint8_t *A = raw, *P = raw + an, *hi = P + h, *lo = hi + m;
            int *v = malloc(m * sizeof(int)), W = (int)w * 3, cs = version ? 1 : 0;
            for (uint32_t y = 0; y < h; y++)
                for (uint32_t x = 0; x < w; x++)
                    for (int k = 0; k < 3; k++) {
                        size_t i = (size_t)y * W + x * 3 + k, g = (size_t)y * W + x * 3;
                        int c = lo[i] | hi[i] << 8, r = c & 1 ? -(c >> 1) : c >> 1;
                        int left = x ? v[i - 3] : 0, up = y ? v[i - W] : 0, pred = 0;
                        switch (P[y]) {
                        case 1: {   /* Paeth, decided on the first component */
                            int ul = x && y ? v[g - W - 3] : 0, l0 = x ? v[g - 3] : 0, u0 = y ? v[g - W] : 0;
                            pred = abs(u0 - ul) <= abs(l0 - ul) ? left : up; break;
                        }
                        case 2: pred = left; break;
                        case 3: pred = up; break;
                        case 4: pred = (left + up + 1) >> 1; break;
                        }
                        v[i] = r + pred;
                    }
            for (size_t j = 0; j < px; j++) {
                int Y = v[3 * j], co = v[3 * j + 1] << cs, cg = v[3 * j + 2] << cs, t = Y - tdiv2(cg);
                out[4 * j] = clamp8(t + co - tdiv2(co)); out[4 * j + 1] = clamp8(t + cg); out[4 * j + 2] = clamp8(t - tdiv2(co));
                out[4 * j + 3] = an ? A[j] : 255;
            }
            free(v);
            ok = YES;
        }
    }
    free(raw);
    if (!ok) { free(out); return NULL; }
    *ow = w; *oh = h;
    return out;
}

/* one catalog: colors by name, image renditions by name and scale, atlases by key */
typedef struct { NSData *data; NSMutableDictionary *colors, *images, *atlases, *pixels; uint32_t kf[32], nk; } Catalog;

static NSString *keystr(const uint16_t *k, uint32_t n) {
    NSMutableString *s = [NSMutableString string];
    for (uint32_t i = 0; i < n; i++) [s appendFormat:@"%u,", k[i]];
    return s;
}

static Catalog *load_catalog(NSString *path) {
    Catalog *cat = calloc(1, sizeof *cat);
    cat->colors = [[NSMutableDictionary alloc] init]; cat->images = [[NSMutableDictionary alloc] init];
    cat->atlases = [[NSMutableDictionary alloc] init]; cat->pixels = [[NSMutableDictionary alloc] init];
    NSData *data = cat->data = [[NSData alloc] initWithContentsOfFile:path];
    NSMutableDictionary *out = cat->colors;
    if (data.length < 32 || memcmp(data.bytes, "BOMStore", 8)) return cat;
    Bom b = {data.bytes, data.length, be32((const uint8_t *)data.bytes + 16), 0};
    if (b.idx + 4 > b.n) return cat;
    b.nblocks = be32(b.d + b.idx);
    /* which key slot holds the identifier and the appearance */
    int32_t kf = var(&b, "KEYFORMAT"); uint32_t kfl;
    const uint8_t *k = kf < 0 ? NULL : block(&b, (uint32_t)kf, &kfl);
    if (!k || kfl < 12) return cat;
    __block int idSlot = -1, appSlot = -1, scaleSlot = -1;
    uint32_t nk = le32(k + 8);
    for (uint32_t i = 0; i < nk && i < 32 && 12 + 4 * i + 4 <= kfl; i++) {
        uint32_t a = cat->kf[cat->nk++] = le32(k + 12 + 4 * i);
        if (a == ATTR_IDENTIFIER) idSlot = (int)i;
        if (a == ATTR_APPEARANCE) appSlot = (int)i;
        if (a == ATTR_SCALE) scaleSlot = (int)i;
    }
    if (idSlot < 0) return cat;
    __block uint16_t dark = 0xffff;
    tree(&b, "APPEARANCEKEYS", ^(const uint8_t *kk, uint32_t kl, const uint8_t *v, uint32_t vl) {
        if (kl == 24 && !memcmp(kk, "NSAppearanceNameDarkAqua", 24) && vl >= 2) dark = le16(v);
    });
    NSMutableDictionary *names = [NSMutableDictionary dictionary];   /* identifier -> name */
    tree(&b, "FACETKEYS", ^(const uint8_t *kk, uint32_t kl, const uint8_t *v, uint32_t vl) {
        if (vl < 6) return;
        uint16_t n = le16(v + 4);
        for (uint16_t i = 0; i < n && 6 + 4u * i + 4 <= vl; i++)
            if (le16(v + 6 + 4 * i) == ATTR_IDENTIFIER)
                names[@(le16(v + 8 + 4 * i))] = [[[NSString alloc] initWithBytes:kk length:kl encoding:NSUTF8StringEncoding] autorelease];
    });
    NSMutableDictionary *isDark = [NSMutableDictionary dictionary];
    NSUInteger nslots = cat->nk;
    tree(&b, "RENDITIONS", ^(const uint8_t *kk, uint32_t kl, const uint8_t *v, uint32_t vl) {
        if (vl < 184 || memcmp(v, "ISTC", 4) || (uint32_t)idSlot * 2 + 2 > kl) return;
        uint16_t layout = le16(v + 36);
        NSData *rend = [NSData dataWithBytes:v length:vl];
        if (layout == LAYOUT_ATLAS) {
            uint16_t key[32] = {0};
            for (NSUInteger i = 0; i < nslots && 2 * i + 2 <= kl; i++) key[i] = le16(kk + 2 * i);
            cat->atlases[keystr(key, (uint32_t)nslots)] = rend;
            return;
        }
        NSString *name = names[@(le16(kk + 2 * idSlot))];
        uint16_t app = appSlot >= 0 && (uint32_t)appSlot * 2 + 2 <= kl ? le16(kk + 2 * appSlot) : 0;
        if (!name || (app && app != dark)) return;
        if (layout == LAYOUT_IMAGE) {   /* name -> scale -> rendition (the dark one wins) */
            uint16_t sc = scaleSlot >= 0 && (uint32_t)scaleSlot * 2 + 2 <= kl ? le16(kk + 2 * scaleSlot) : 1;
            NSMutableDictionary *byScale = cat->images[name] ?: (cat->images[name] = [NSMutableDictionary dictionary]);
            NSString *dk = [NSString stringWithFormat:@"dark%u", sc];
            if (!byScale[@(sc)] || app || ![byScale[dk] boolValue]) { byScale[@(sc)] = rend; byScale[dk] = @(app != 0); }
            return;
        }
        if (layout != LAYOUT_COLOR || (out[name] && [isDark[name] boolValue])) return;
        const uint8_t *c = v + 184 + le32(v + 168);
        if (c + 16 > v + vl || memcmp(c, "RLOC", 4)) return;
        uint32_t n = le32(c + 12);
        if (n < 3 || c + 16 + 8 * n > v + vl) return;
        double comp[4] = {0, 0, 0, 1};
        for (uint32_t i = 0; i < n && i < 4; i++) memcpy(&comp[i], c + 16 + 8 * i, 8);
        if (n == 2) { comp[3] = comp[1]; comp[1] = comp[2] = comp[0]; }   /* gray + alpha */
        out[name] = [NSColor colorWithSRGBRed:comp[0] green:comp[1] blue:comp[2] alpha:comp[3]];
        isDark[name] = @(app != 0);
    });
    return cat;
}

static Catalog *catalog(NSBundle *bundle) {
    static NSMutableDictionary *cache;   /* catalog path -> Catalog * */
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    NSString *path = [(bundle ?: [NSBundle mainBundle]) pathForResource:@"Assets" ofType:@"car"];
    if (!path) return NULL;
    NSValue *c = cache[path];
    if (!c) cache[path] = c = [NSValue valueWithPointer:load_catalog(path)];
    return [c pointerValue];
}

static NSColor *named_color(NSString *name, NSBundle *bundle) {
    Catalog *c = catalog(bundle);
    return c ? c->colors[name] : nil;
}

/* the decoded atlas (RGBA premultiplied, w, h) for a packed-asset key */
static NSData *atlas_pixels(Catalog *cat, NSString *key, uint32_t *w, uint32_t *h) {
    NSArray *hit = cat->pixels[key];
    if (!hit) {
        NSData *r = cat->atlases[key];
        const uint8_t *v = r.bytes, *c = v ? v + 184 + le32(v + 168) : NULL;
        uint32_t aw = 0, ah = 0; uint8_t *px = NULL;
        if (c && c + 48 <= v + r.length && !memcmp(c, "MLEC", 4) && le32(c + 8) == 11)
            px = dmp2_decode(c + 32, (size_t)(v + r.length - (c + 32)), &aw, &ah);
        hit = cat->pixels[key] = px ? @[[NSData dataWithBytesNoCopy:px length:(NSUInteger)aw * ah * 4], @(aw), @(ah)] : @[];
    }
    if (hit.count < 3) return nil;
    *w = [hit[1] unsignedIntValue]; *h = [hit[2] unsignedIntValue];
    return hit[0];
}

/* one image rendition -> a bitmap rep of `pts` points */
static NSBitmapImageRep *image_rep(Catalog *cat, NSData *rend) {
    const uint8_t *v = rend.bytes, *t = v + 184, *end = t + le32(v + 168);
    if (end > v + rend.length) return nil;
    uint32_t scale = le32(v + 20) / 100 ?: 1;
    for (; t + 8 <= end; t += 8 + le32(t + 4)) {
        uint32_t tag = le32(t), len = le32(t + 4);
        const uint8_t *d = t + 8;
        if (tag != 1010 || len < 30 || memcmp(d, "KLNI", 4)) continue;
        uint32_t x = le32(d + 8), y = le32(d + 12), w = le32(d + 16), h = le32(d + 20), kl = le32(d + 26);
        uint16_t key[32] = {0};
        for (uint32_t i = 0; 30 + 4 * i + 4 <= len && i < kl / 4; i++) {   /* (attribute, value) tokens */
            uint16_t a = le16(d + 30 + 4 * i);
            for (uint32_t s = 0; s < cat->nk; s++) if (cat->kf[s] == a) key[s] = le16(d + 32 + 4 * i);
        }
        uint32_t aw, ah;
        NSData *px = atlas_pixels(cat, keystr(key, cat->nk), &aw, &ah);
        if (!px || x + w > aw || y + h > ah || !w || !h) return nil;
        NSBitmapImageRep *r = [[[NSBitmapImageRep alloc] _mwInitWidth:w height:h] autorelease];
        const uint8_t *src = (const uint8_t *)px.bytes + ((size_t)(ah - y - h) * aw + x) * 4;   /* the rectangle's y is from the bottom */
        for (uint32_t row = 0; row < h; row++) memcpy(r.bitmapData + row * r.bytesPerRow, src + (size_t)row * aw * 4, w * 4);
        r.size = NSMakeSize((CGFloat)w / scale, (CGFloat)h / scale);
        return r;
    }
    return nil;
}

NSImage *mw_catalog_image(NSString *name, NSBundle *bundle) {
    Catalog *cat = catalog(bundle);
    NSDictionary *byScale = cat ? cat->images[name] : nil;
    NSImage *img = nil;
    for (NSNumber *s in @[@2, @1, @3]) {   /* the 2x first: it is the one drawn */
        NSBitmapImageRep *r = byScale[s] ? image_rep(cat, byScale[s]) : nil;
        if (!r) continue;
        if (!img) img = [[[NSImage alloc] initWithSize:r.size] autorelease];
        [img addRepresentation:r];
    }
    return img;
}

@implementation NSBundle (MWImages)
- (NSImage *)imageForResource:(NSString *)name {
    NSString *path = [self pathForImageResource:name];
    return path ? [[[NSImage alloc] initWithContentsOfFile:path] autorelease] : mw_catalog_image(name, self);
}
- (NSString *)pathForImageResource:(NSString *)name {
    NSString *ext = [name pathExtension], *path = ext.length ? [self pathForResource:[name stringByDeletingPathExtension] ofType:ext] : nil;
    for (NSString *e in @[@"png", @"tiff", @"jpg", @"jpeg", @"gif", @"bmp", @"icns"]) if (!path) path = [self pathForResource:name ofType:e];
    return path;
}
@end

@implementation NSColor (MWNamedColors)
+ (NSColor *)colorNamed:(NSString *)name bundle:(NSBundle *)bundle {
    if (!name) return nil;
    NSColor *c = named_color(name, bundle);
    if (c) return c;
    /* the system's names */
    SEL s = NSSelectorFromString([[[name substringToIndex:1] lowercaseString] stringByAppendingString:[name substringFromIndex:1]]);
    if ([name hasPrefix:@"system"] || [name hasSuffix:@"Color"]) {
        NSString *sel = [name hasSuffix:@"Color"] ? NSStringFromSelector(s) : [NSStringFromSelector(s) stringByAppendingString:@"Color"];
        SEL ss = NSSelectorFromString(sel);
        if ([NSColor respondsToSelector:ss] && ![sel hasPrefix:@"colorNamed"]) return ((NSColor *(*)(id, SEL))objc_msgSend)([NSColor class], ss);
    }
    return nil;
}
+ (NSColor *)colorNamed:(NSString *)name { return [self colorNamed:name bundle:nil]; }
@end
