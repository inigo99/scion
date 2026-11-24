/* asset_catalog.m: images of a compiled asset catalog (Assets.car), here Itsycal's: btnPrev (gray + alpha, lossless atlas)
   and PrefsAboutVC (color, deepmap2 atlas), each at 1x and 2x. argv[1]: the .app; argv[2] (optional): a folder for PNGs. */
#import <AppKit/AppKit.h>

static int fails;
static void ok(BOOL c, const char *what) { if (!c) { printf("FAIL: %s\n", what); fails++; } }

static NSBitmapImageRep *rep(NSImage *i, NSInteger w) {
    for (id r in i.representations) if ([r isKindOfClass:[NSBitmapImageRep class]] && [r pixelsWide] == w) return r;
    return nil;
}
static CGFloat alpha(NSBitmapImageRep *r, NSInteger x, NSInteger y) { return [r colorAtX:x y:y].alphaComponent; }

int main(int argc, char **argv) {
    @autoreleasepool {
        NSBundle *b = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argc > 1 ? argv[1] : "Itsycal.app"]];
        NSImage *prev = [b imageForResource:@"btnPrev"], *about = [b imageForResource:@"PrefsAboutVC"];
        ok(prev && NSEqualSizes(prev.size, NSMakeSize(18, 18)), "btnPrev 18x18");
        NSBitmapImageRep *p1 = rep(prev, 18), *p2 = rep(prev, 36), *a2 = rep(about, 64);
        ok(p1 && p2, "btnPrev at 1x and 2x");
        /* a left-pointing triangle: transparent corners, opaque in the middle, more ink on the right (its base) */
        ok(alpha(p1, 0, 0) == 0 && alpha(p1, 17, 17) == 0, "btnPrev transparent corners");
        ok(alpha(p1, 9, 9) > 0.5, "btnPrev opaque center");
        int left = 0, right = 0;
        for (int y = 0; y < 36; y++) for (int x = 0; x < 36; x++) if (alpha(p2, x, y) > 0.5) { if (x < 18) left++; else right++; }
        ok(right > left, "btnPrev points left");
        ok(about && NSEqualSizes(about.size, NSMakeSize(32, 32)) && a2, "PrefsAboutVC 32x32 with 2x");
        NSColor *c = [a2 colorAtX:32 y:32];
        ok(c.alphaComponent > 0.9, "PrefsAboutVC opaque center");
        ok([NSColor colorNamed:@"TodayCellColor" bundle:b] != nil, "named color");
        if (argc > 2) for (NSBitmapImageRep *r in @[p2 ?: [NSNull null], a2 ?: [NSNull null]])
            if ([r isKindOfClass:[NSBitmapImageRep class]])
                [[r representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"%s/cat%ld.png", argv[2], (long)r.pixelsWide] atomically:YES];
        printf(fails ? "CATALOG: %d FAILURES\n" : "CATALOG OK\n", fails);
    }
    return fails != 0;
}
