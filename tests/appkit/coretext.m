// CoreText and rich text: attributed strings with runs (NSAttributedString, CFAttributedString), lines, runs,
// typesetters, framesetters and frames (breaking, paragraph styles, truncation), drawing into bitmaps, fonts,
// descriptors and registering a font file (font.ttf next to the test, if tests/build.sh found one). Prints "CORETEXT OK".
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
#include <math.h>

static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static CGContextRef ctx(int w, int h) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    return c;
}
// pixels mostly of one color (r, g, b each 0 or 255) in rows y0..y1 from the top
static int count(CGContextRef c, int r, int g, int b, int y0, int y1) {
    int n = 0;
    for (int y = y0; y < y1 && y < (int)CGBitmapContextGetHeight(c); y++)
        for (int x = 0; x < (int)CGBitmapContextGetWidth(c); x++) {
            const uint8_t *p = (const uint8_t *)CGBitmapContextGetData(c) + y * CGBitmapContextGetBytesPerRow(c) + x * 4;
            if (p[3] > 160 && abs(p[2] - r) < 90 && abs(p[1] - g) < 90 && abs(p[0] - b) < 90) n++;
        }
    return n;
}

static void attributed(void) {
    NSFont *f12 = [NSFont fontWithName:@"Helvetica" size:12], *b12 = [NSFont fontWithName:@"Helvetica-Bold" size:12];
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:@"Hello brave world" attributes:@{NSFontAttributeName: f12}];
    [s addAttribute:NSFontAttributeName value:b12 range:NSMakeRange(6, 5)];
    [s addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(8, 9)];
    NSRange r;
    NSDictionary *a = [s attributesAtIndex:0 effectiveRange:&r];
    CHECK(NSEqualRanges(r, NSMakeRange(0, 6)) && a[NSFontAttributeName] == f12, "run 0: %lu+%lu", (unsigned long)r.location, (unsigned long)r.length);
    a = [s attributesAtIndex:7 effectiveRange:&r];
    CHECK(NSEqualRanges(r, NSMakeRange(6, 2)) && a[NSFontAttributeName] == b12 && !a[NSForegroundColorAttributeName], "run 1");
    a = [s attributesAtIndex:9 effectiveRange:&r];
    CHECK(NSEqualRanges(r, NSMakeRange(8, 3)) && a[NSForegroundColorAttributeName], "run 2");
    [s attribute:NSForegroundColorAttributeName atIndex:9 longestEffectiveRange:&r inRange:NSMakeRange(0, s.length)];
    CHECK(NSEqualRanges(r, NSMakeRange(8, 9)), "longest red range %lu+%lu", (unsigned long)r.location, (unsigned long)r.length);
    __block int runs = 0;
    [s enumerateAttributesInRange:NSMakeRange(0, s.length) options:0 usingBlock:^(NSDictionary *x, NSRange q, BOOL *stop) { runs++; }];
    CHECK(runs == 4, "runs %d", runs);
    // new characters take the attributes of the one they replace; removal and setting merge runs
    [s replaceCharactersInRange:NSMakeRange(6, 5) withString:@"BRAVE!"];
    CHECK([s.string isEqualToString:@"Hello BRAVE! world"] && [s attribute:NSFontAttributeName atIndex:11 effectiveRange:NULL] == b12, "replace");
    [s setAttributes:@{NSFontAttributeName: f12} range:NSMakeRange(0, s.length)];
    [s attributesAtIndex:3 effectiveRange:&r];
    CHECK(NSEqualRanges(r, NSMakeRange(0, s.length)), "one run after setAttributes");
    NSAttributedString *sub = [s attributedSubstringFromRange:NSMakeRange(6, 6)];
    CHECK([sub.string isEqualToString:@"BRAVE!"] && [sub attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] == f12, "substring");
    NSMutableAttributedString *t = [s mutableCopy];
    CHECK([t isEqualToAttributedString:s], "copy equal");
    [t addAttribute:NSKernAttributeName value:@1 range:NSMakeRange(0, 1)];
    CHECK(![t isEqual:s], "different attributes");
    // CFAttributedString is the same object
    CFMutableAttributedStringRef m = CFAttributedStringCreateMutable(NULL, 0);
    CFAttributedStringReplaceString(m, CFRangeMake(0, 0), CFSTR("abcdef"));
    CFAttributedStringSetAttribute(m, CFRangeMake(2, 2), kCTForegroundColorAttributeName, [NSColor blueColor].CGColor);
    CFRange e;
    CHECK(CFAttributedStringGetAttribute(m, 3, kCTForegroundColorAttributeName, &e) && e.location == 2 && e.length == 2 && CFAttributedStringGetLength(m) == 6, "CF");
    CFRelease(m);
    // CoreText's names are AppKit's
    CHECK([(__bridge NSString *)kCTFontAttributeName isEqualToString:NSFontAttributeName] && [(__bridge NSString *)kCTParagraphStyleAttributeName isEqualToString:NSParagraphStyleAttributeName], "names");
}

static NSAttributedString *text(NSString *s, CGFloat size) {
    return [[NSAttributedString alloc] initWithString:s attributes:@{NSFontAttributeName: [NSFont fontWithName:@"Helvetica" size:size]}];
}

static void lines(void) {
    NSMutableAttributedString *s = [text(@"Hello world", 20) mutableCopy];
    [s addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"Helvetica-Bold" size:30] range:NSMakeRange(6, 5)];
    CTLineRef l = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
    CGFloat asc, desc, lead;
    double w = CTLineGetTypographicBounds(l, &asc, &desc, &lead);
    CHECK(w > 60 && asc > 18 && desc > 2, "bounds %g %g %g", w, asc, desc);
    CFArrayRef runs = CTLineGetGlyphRuns(l);
    CHECK(CFArrayGetCount(runs) == 2 && CTLineGetGlyphCount(l) == 11, "runs %ld", (long)CFArrayGetCount(runs));
    CTRunRef r1 = (CTRunRef)CFArrayGetValueAtIndex(runs, 1);
    CHECK(CTRunGetStringRange(r1).location == 6 && CTRunGetGlyphCount(r1) == 5, "run range");
    CGPoint p[5]; CTRunGetPositions(r1, CFRangeMake(0, 0), p);
    CHECK(p[0].x > 30 && p[1].x > p[0].x && p[4].x < w, "positions %g %g", p[0].x, p[1].x);
    CGGlyph g[5]; CTRunGetGlyphs(r1, CFRangeMake(0, 0), g);
    CHECK(g[0] == 'w' && g[4] == 'd', "glyphs");
    // caret positions and back
    CGFloat x6 = CTLineGetOffsetForStringIndex(l, 6, NULL), x8 = CTLineGetOffsetForStringIndex(l, 8, NULL);
    CHECK(x6 > 0 && x8 > x6 && CTLineGetOffsetForStringIndex(l, 11, NULL) == (CGFloat)w, "offsets %g %g", x6, x8);
    CHECK(CTLineGetStringIndexForPosition(l, CGPointMake(x8 + 1, 0)) == 8 && CTLineGetStringIndexForPosition(l, CGPointMake(-5, 0)) == 0
          && CTLineGetStringIndexForPosition(l, CGPointMake(w + 10, 0)) == 11, "index for position");
    CHECK(fabs(CTLineGetPenOffsetForFlush(l, 0.5, w + 100) - 50) < 0.01, "flush");
    // truncation
    CTLineRef cut = CTLineCreateTruncatedLine(l, w / 2, kCTLineTruncationEnd, NULL);
    CHECK(cut && CTLineGetTypographicBounds(cut, NULL, NULL, NULL) <= w / 2 + 0.01, "truncated");
    if (cut) CFRelease(cut);
    CFRelease(l);
}

static void breaking(void) {
    NSAttributedString *s = text(@"alpha beta gamma\ndelta", 16);
    CTTypesetterRef ts = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)s);
    CTLineRef ab = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text(@"alpha beta", 16));
    double w = CTLineGetTypographicBounds(ab, NULL, NULL, NULL);
    CFRelease(ab);
    CHECK(CTTypesetterSuggestLineBreak(ts, 0, w + 2) == 11, "break after 'beta ': %ld", (long)CTTypesetterSuggestLineBreak(ts, 0, w + 2));
    CHECK(CTTypesetterSuggestLineBreak(ts, 11, 1000) == 6, "up to the newline: %ld", (long)CTTypesetterSuggestLineBreak(ts, 11, 1000));
    CFIndex c = CTTypesetterSuggestClusterBreak(ts, 0, w / 2);
    CHECK(c > 0 && c < 6, "cluster break %ld", (long)c);
    CHECK(CTTypesetterSuggestLineBreak(ts, 0, 1) == 1, "at least one character");
    CTLineRef l = CTTypesetterCreateLine(ts, CFRangeMake(17, 0));
    CHECK(CTLineGetStringRange(l).location == 17 && CTLineGetStringRange(l).length == 5, "line to the end");
    CFRelease(l); CFRelease(ts);
}

static void frames(void) {
    NSString *words = @"The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog.";
    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)text(words, 14));
    CGPathRef path = CGPathCreateWithRect(CGRectMake(10, 20, 150, 400), NULL);
    CTFrameRef f = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
    CFArrayRef ls = CTFrameGetLines(f);
    CFIndex n = CFArrayGetCount(ls);
    CHECK(n >= 3, "lines %ld", (long)n);
    CHECK(CTFrameGetVisibleStringRange(f).length == (CFIndex)words.length, "all visible");
    CGPoint o[32]; CTFrameGetLineOrigins(f, CFRangeMake(0, 0), o);
    CHECK(o[0].y < 400 && o[0].y > 380 && o[1].y < o[0].y && o[0].x == 0, "origins %g %g", o[0].y, o[1].y);
    for (CFIndex i = 0; i < n; i++) {
        double lw = CTLineGetTypographicBounds((CTLineRef)CFArrayGetValueAtIndex(ls, i), NULL, NULL, NULL) - CTLineGetTrailingWhitespaceWidth((CTLineRef)CFArrayGetValueAtIndex(ls, i));
        CHECK(lw <= 150.5, "line %ld too wide: %g", (long)i, lw);
    }
    CFRelease(f);
    // a short box shows only the lines that fit
    CGPathRelease(path); path = CGPathCreateWithRect(CGRectMake(0, 0, 150, 40), NULL);
    f = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
    CHECK(CFArrayGetCount(CTFrameGetLines(f)) < n && CTFrameGetVisibleStringRange(f).length < (CFIndex)words.length, "clipped frame");
    CFRelease(f); CGPathRelease(path);
    CFRange fit;
    CGSize narrow = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), NULL, CGSizeMake(100, CGFLOAT_MAX), &fit);
    CGSize wide = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
    CHECK(narrow.width <= 100 && narrow.height > wide.height && wide.width > 300 && fit.length == (CFIndex)words.length, "suggested %gx%g %gx%g", narrow.width, narrow.height, wide.width, wide.height);
    CFRelease(fs);

    // paragraph styles: centered, indented, spaced
    CTTextAlignment center = kCTTextAlignmentCenter; CGFloat indent = 20, spacing = 10;
    CTParagraphStyleSetting set[] = {{kCTParagraphStyleSpecifierAlignment, sizeof center, &center},
                                     {kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof indent, &indent},
                                     {kCTParagraphStyleSpecifierParagraphSpacing, sizeof spacing, &spacing}};
    CTParagraphStyleRef ps = CTParagraphStyleCreate(set, 3);
    CTTextAlignment back = 9; CGFloat ib = 0;
    CHECK(CTParagraphStyleGetValueForSpecifier(ps, kCTParagraphStyleSpecifierAlignment, sizeof back, &back) && back == kCTTextAlignmentCenter
          && CTParagraphStyleGetValueForSpecifier(ps, kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof ib, &ib) && ib == 20, "style values");
    CHECK([(__bridge id)ps isKindOfClass:[NSParagraphStyle class]] && ((__bridge NSParagraphStyle *)ps).alignment == NSTextAlignmentCenter, "an NSParagraphStyle");
    NSMutableAttributedString *p = [text(@"one\ntwo", 14) mutableCopy];
    [p addAttribute:NSParagraphStyleAttributeName value:(__bridge id)ps range:NSMakeRange(0, p.length)];
    fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)p);
    path = CGPathCreateWithRect(CGRectMake(0, 0, 200, 200), NULL);
    f = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
    CTFrameGetLineOrigins(f, CFRangeMake(0, 2), o);
    double w1 = CTLineGetTypographicBounds((CTLineRef)CFArrayGetValueAtIndex(CTFrameGetLines(f), 0), NULL, NULL, NULL);
    CHECK(o[0].x > 80 && o[0].x < 120 && o[0].x > (200 - 20 - w1) / 2, "centered and indented: %g", o[0].x);
    CHECK(o[0].y - o[1].y > 14 + 9, "paragraph spacing: %g", o[0].y - o[1].y);
    CFRelease(f); CFRelease(fs); CGPathRelease(path); CFRelease(ps);

    // tail truncation as a paragraph's line break mode
    CTLineBreakMode tail = kCTLineBreakByTruncatingTail;
    CTParagraphStyleSetting ts[] = {{kCTParagraphStyleSpecifierLineBreakMode, sizeof tail, &tail}};
    ps = CTParagraphStyleCreate(ts, 1);
    NSMutableAttributedString *t = [text(words, 14) mutableCopy];
    [t addAttribute:(__bridge NSString *)kCTParagraphStyleAttributeName value:(__bridge id)ps range:NSMakeRange(0, t.length)];
    fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)t);
    path = CGPathCreateWithRect(CGRectMake(0, 0, 120, 200), NULL);
    f = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
    CTLineRef only = (CTLineRef)CFArrayGetValueAtIndex(CTFrameGetLines(f), 0);
    CHECK(CFArrayGetCount(CTFrameGetLines(f)) == 1 && CTLineGetTypographicBounds(only, NULL, NULL, NULL) <= 120.5, "one truncated line");
    CFRelease(f); CFRelease(fs); CGPathRelease(path); CFRelease(ps);
}

static void drawing(void) {
    CGContextRef c = ctx(300, 100);
    NSMutableAttributedString *s = [text(@"RED BLUE", 40) mutableCopy];
    [s addAttribute:(__bridge NSString *)kCTForegroundColorAttributeName value:(__bridge id)[NSColor redColor].CGColor range:NSMakeRange(0, 3)];
    [s addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:NSMakeRange(4, 4)];
    CTLineRef l = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
    CGContextSetTextPosition(c, 10, 30);   // baseline 30 up from the bottom: rows ~30..70 from the top
    CTLineDraw(l, c);
    int red = count(c, 255, 0, 0, 0, 100), blue = count(c, 0, 0, 255, 0, 100);
    CHECK(red > 50 && blue > 50, "line colors: red %d blue %d", red, blue);
    CHECK(count(c, 255, 0, 0, 72, 100) == 0 && count(c, 0, 0, 255, 0, 10) == 0, "above the baseline");
    CFRelease(l);
    CGContextClearRect(c, CGRectMake(0, 0, 300, 100));
    // a frame in the top 80 pixels: nothing below them
    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)s);
    CGPathRef path = CGPathCreateWithRect(CGRectMake(0, 20, 300, 80), NULL);
    CTFrameRef f = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
    CTFrameDraw(f, c);
    CHECK(CFArrayGetCount(CTFrameGetLines(f)) == 1 && count(c, 255, 0, 0, 0, 80) > 50 && count(c, 255, 0, 0, 80, 100) + count(c, 0, 0, 255, 80, 100) == 0,
          "frame in its box: %d lines, red %d / %d", (int)CFArrayGetCount(CTFrameGetLines(f)), count(c, 255, 0, 0, 0, 80), count(c, 255, 0, 0, 80, 100));
    CFRelease(f); CGPathRelease(path); CFRelease(fs);
    CGContextClearRect(c, CGRectMake(0, 0, 300, 100));
    // NSAttributedString draws its runs, in a flipped context from the top
    [NSGraphicsContext saveGraphicsState];
    CGContextTranslateCTM(c, 0, 100); CGContextScaleCTM(c, 1, -1);
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:c flipped:YES]];
    NSMutableAttributedString *u = [text(@"RED BLUE", 30) mutableCopy];
    [u addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, 3)];
    [u addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:NSMakeRange(4, 4)];
    [u addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:NSMakeRange(4, 4)];
    NSSize z = u.size;
    CHECK(z.width > 80 && z.height > 25 && z.height < 45, "size %gx%g", z.width, z.height);
    [u drawInRect:NSMakeRect(5, 5, 290, 60)];
    [NSGraphicsContext restoreGraphicsState];
    CHECK(count(c, 255, 0, 0, 0, 50) > 30 && count(c, 0, 0, 255, 0, 50) > 30 && count(c, 255, 0, 0, 55, 100) == 0, "attributed drawing: red %d blue %d",
          count(c, 255, 0, 0, 0, 50), count(c, 0, 0, 255, 0, 50));
    CGContextRelease(c);
}

static void fonts(void) {
    CTFontRef f = CTFontCreateWithName(CFSTR("Helvetica-Bold"), 18, NULL);
    CHECK(CTFontGetSize(f) == 18 && (CTFontGetSymbolicTraits(f) & kCTFontTraitBold) && CTFontGetAscent(f) > 10, "font");
    CFStringRef ps = CTFontCopyPostScriptName(f);
    CHECK([(__bridge NSString *)ps isEqualToString:@"Helvetica-Bold"], "PostScript name");
    CFRelease(ps);
    CTFontRef it = CTFontCreateCopyWithSymbolicTraits(f, 0, NULL, kCTFontTraitItalic, kCTFontTraitItalic);
    CHECK(it && (CTFontGetSymbolicTraits(it) & kCTFontTraitItalic) && (CTFontGetSymbolicTraits(it) & kCTFontTraitBold), "bold italic copy");
    if (it) CFRelease(it);
    CTFontDescriptorRef d = CTFontDescriptorCreateWithNameAndSize(CFSTR("Georgia"), 11);
    CFTypeRef n = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute);
    CHECK(n && [(__bridge NSString *)n isEqualToString:@"Georgia"], "descriptor name");
    if (n) CFRelease(n);
    CTFontRef g = CTFontCreateWithFontDescriptor(d, 0, NULL);
    CHECK(CTFontGetSize(g) == 11 && [((__bridge NSFont *)g).fontName isEqualToString:@"Georgia"], "font from descriptor");
    CFRelease(g); CFRelease(d); CFRelease(f);
    CGGlyph gl[2]; UniChar ch[2] = {'A', 'B'}; CGSize adv[2];
    CTFontRef h = CTFontCreateWithName(CFSTR("Helvetica"), 20, NULL);
    CHECK(CTFontGetGlyphsForCharacters(h, ch, gl, 2) && CTFontGetAdvancesForGlyphs(h, kCTFontOrientationDefault, gl, adv, 2) > 15 && adv[0].width > 5, "advances");
    CFRelease(h);

    // registering a font file
    NSURL *bad = [NSURL fileURLWithPath:@"coretext_not_a_font.txt"];
    [@"not a font" writeToURL:bad atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    CFErrorRef err = NULL;
    CHECK(!CTFontManagerRegisterFontsForURL((__bridge CFURLRef)bad, kCTFontManagerScopeProcess, &err) && err, "a text file is not a font");
    if (err) CFRelease(err);
    [[NSFileManager defaultManager] removeItemAtURL:bad error:NULL];
    NSURL *u = [NSURL fileURLWithPath:@"font.ttf"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"font.ttf"]) { printf("(no font.ttf: registration not tested)\n"); return; }
    CFArrayRef ds = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)u);
    CHECK(ds && CFArrayGetCount(ds) >= 1, "descriptors from the file");
    if (!ds || !CFArrayGetCount(ds)) return;
    NSString *name = (__bridge_transfer NSString *)CTFontDescriptorCopyAttribute((CTFontDescriptorRef)CFArrayGetValueAtIndex(ds, 0), kCTFontNameAttribute);
    CFRelease(ds);
    CHECK(name.length > 0 && [(__bridge_transfer NSArray *)CTFontManagerCopyAvailablePostScriptNames() containsObject:name], "registered %s", name.UTF8String);
    CTFontRef r = CTFontCreateWithName((__bridge CFStringRef)name, 30, NULL);
    CTLineRef l = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)[[NSAttributedString alloc] initWithString:@"Registered" attributes:@{NSFontAttributeName: (__bridge id)r}]);
    CHECK(CTLineGetTypographicBounds(l, NULL, NULL, NULL) > 60, "measures in the registered font");
    CFRelease(l); CFRelease(r);
}

// a text view shows its runs; points map to characters and the arrows move between lines
static void textview(void) {
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 120)];
    tv.string = @"red blue\nsecond line";
    NSTextStorage *st = tv.textStorage;
    NSFont *big = [NSFont fontWithName:@"Helvetica" size:24];
    [st addAttribute:NSFontAttributeName value:big range:NSMakeRange(0, st.length)];
    [st addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, 3)];
    [st addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:NSMakeRange(4, 4)];
    NSBitmapImageRep *rep = [tv bitmapImageRepForCachingDisplayInRect:tv.bounds];
    [tv cacheDisplayInRect:tv.bounds toBitmapImageRep:rep];
    int red = 0, blue = 0;
    for (NSInteger y = 0; y < rep.pixelsHigh / 2; y++)
        for (NSInteger x = 0; x < rep.pixelsWide; x++) {
            NSColor *c = [rep colorAtX:x y:y];
            if (c.redComponent > 0.7 && c.greenComponent < 0.4 && c.blueComponent < 0.4) red++;
            if (c.blueComponent > 0.7 && c.greenComponent < 0.4 && c.redComponent < 0.4) blue++;
        }
    CHECK(red > 20 && blue > 20, "text view runs: red %d blue %d", red, blue);
    CHECK([tv characterIndexForInsertionAtPoint:NSMakePoint(2, 10)] == 0, "first character");
    NSUInteger second = [tv characterIndexForInsertionAtPoint:NSMakePoint(2, 45)];
    CHECK(second == 9, "second line starts at 9: %lu", (unsigned long)second);
    tv.selectedRange = NSMakeRange(1, 0);
    [tv doCommandBySelector:@selector(moveDown:)];
    CHECK(tv.selectedRange.location >= 9 && tv.selectedRange.location <= 11, "down: %lu", (unsigned long)tv.selectedRange.location);
    [tv doCommandBySelector:@selector(moveUp:)];
    CHECK(tv.selectedRange.location <= 2, "up: %lu", (unsigned long)tv.selectedRange.location);
}

int main(void) {
    @autoreleasepool {
        attributed();
        lines();
        breaking();
        frames();
        drawing();
        fonts();
        textview();
        printf(fails ? "CORETEXT FAILED (%d)\n" : "CORETEXT OK\n", fails);
    }
    return fails != 0;
}
