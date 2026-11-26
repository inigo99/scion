/* coretext.m — CoreText layout on attributed strings: typesetters break text into lines, lines hold runs (a range with
 * one set of attributes), framesetters stack lines in a rectangle with their paragraph styles. Also the CoreText font
 * calls draw.m does not have, descriptors, font registration and NSAttributedString drawing (which lays out here).
 *
 * A glyph is its UTF-16 character, its advance the width the host measures for it. A run is drawn as one string, so the
 * host's own shaping (kerning, ligatures, joined scripts) applies; its glyph positions are spread to match its width.
 * Lines are left to right (ponytail: no bidirectional reordering). */
#import "internal.h"

/* ======================================================================= attribute names */
#define K(n, v) const CFStringRef n = (CFStringRef)@v;
K(kCTFontAttributeName, "NSFont") K(kCTForegroundColorAttributeName, "CTForegroundColor")
K(kCTForegroundColorFromContextAttributeName, "CTForegroundColorFromContext") K(kCTBackgroundColorAttributeName, "CTBackgroundColor")
K(kCTParagraphStyleAttributeName, "NSParagraphStyle") K(kCTKernAttributeName, "NSKern") K(kCTTrackingAttributeName, "CTTracking")
K(kCTUnderlineStyleAttributeName, "NSUnderline") K(kCTUnderlineColorAttributeName, "CTUnderlineColor") K(kCTStrokeWidthAttributeName, "NSStrokeWidth")
K(kCTStrokeColorAttributeName, "CTStrokeColor") K(kCTLigatureAttributeName, "NSLigature") K(kCTSuperscriptAttributeName, "NSSuperScript")
K(kCTBaselineOffsetAttributeName, "CTBaselineOffset") K(kCTVerticalFormsAttributeName, "CTVerticalForms") K(kCTGlyphInfoAttributeName, "NSGlyphInfo")
K(kCTLanguageAttributeName, "NSLanguage") K(kCTWritingDirectionAttributeName, "NSWritingDirection")
K(kCTFontNameAttribute, "NSFontNameAttribute") K(kCTFontDisplayNameAttribute, "NSFontVisibleNameAttribute") K(kCTFontFamilyNameAttribute, "NSFontFamilyAttribute")
K(kCTFontStyleNameAttribute, "NSFontFaceAttribute") K(kCTFontTraitsAttribute, "NSCTFontTraitsAttribute") K(kCTFontSizeAttribute, "NSFontSizeAttribute")
K(kCTFontMatrixAttribute, "NSFontMatrixAttribute") K(kCTFontURLAttribute, "NSCTFontFileURLAttribute") K(kCTFontFeatureSettingsAttribute, "NSCTFontFeatureSettingsAttribute")
K(kCTFontSymbolicTrait, "NSCTFontSymbolicTrait") K(kCTFontWeightTrait, "NSCTFontWeightTrait") K(kCTFontWidthTrait, "NSCTFontProportionTrait")
K(kCTFontSlantTrait, "NSCTFontSlantTrait")
K(kCTFontCopyrightNameKey, "CTFontCopyrightName") K(kCTFontFamilyNameKey, "CTFontFamilyName") K(kCTFontSubFamilyNameKey, "CTFontSubFamilyName")
K(kCTFontStyleNameKey, "CTFontStyleName") K(kCTFontUniqueNameKey, "CTFontUniqueName") K(kCTFontFullNameKey, "CTFontFullName")
K(kCTFontVersionNameKey, "CTFontVersionName") K(kCTFontPostScriptNameKey, "CTFontPostScriptName")
K(kCTFrameProgressionAttributeName, "CTFrameProgression") K(kCTFramePathFillRuleAttributeName, "CTFramePathFillRule")
K(kCTFramePathWidthAttributeName, "CTFramePathWidth")
#undef K
/* the AppKit names: the same strings, as on macOS (CoreText and AppKit attributes mix) */
NSString *const NSFontAttributeName = @"NSFont", *const NSForegroundColorAttributeName = @"NSColor", *const NSBackgroundColorAttributeName = @"NSBackgroundColor",
    *const NSParagraphStyleAttributeName = @"NSParagraphStyle", *const NSKernAttributeName = @"NSKern", *const NSUnderlineStyleAttributeName = @"NSUnderline",
    *const NSUnderlineColorAttributeName = @"NSUnderlineColor", *const NSStrikethroughStyleAttributeName = @"NSStrikethrough",
    *const NSStrikethroughColorAttributeName = @"NSStrikethroughColor", *const NSStrokeWidthAttributeName = @"NSStrokeWidth",
    *const NSStrokeColorAttributeName = @"NSStrokeColor", *const NSShadowAttributeName = @"NSShadow", *const NSLigatureAttributeName = @"NSLigature",
    *const NSSuperscriptAttributeName = @"NSSuperScript", *const NSObliquenessAttributeName = @"NSObliqueness", *const NSExpansionAttributeName = @"NSExpansion",
    *const NSToolTipAttributeName = @"NSToolTip", *const NSAttachmentAttributeName = @"NSAttachment", *const NSCursorAttributeName = @"NSCursor",
    *const NSWritingDirectionAttributeName = @"NSWritingDirection";
#define kUnderlineColorNS NSUnderlineColorAttributeName
#define kBackgroundNS NSBackgroundColorAttributeName
#define kStrikeNS NSStrikethroughStyleAttributeName
#define kBaselineNS NSBaselineOffsetAttributeName
static inline BOOL CFStringIsSurrogateHighCharacter(unichar c) { return c >= 0xD800 && c <= 0xDBFF; }
static inline BOOL CFStringIsSurrogateLowCharacter(unichar c) { return c >= 0xDC00 && c <= 0xDFFF; }

/* ======================================================================= runs and lines */
@interface _MWCTRun : NSObject { @public
    NSDictionary *attrs; NSFont *font; NSString *text;   /* text: what is drawn (line breaks and tabs left out) */
    CGColorRef color;                                    /* NULL: the context's fill color */
    CFRange range; CFIndex n;
    CGGlyph *glyphs; CGPoint *pos; CGSize *adv; CFIndex *idx;
    CGFloat x, width, ascent, descent, baseline;
}
@end
@implementation _MWCTRun
- (void)dealloc { [attrs release]; [font release]; [text release]; CGColorRelease(color); free(glyphs); free(pos); free(adv); free(idx); [super dealloc]; }
@end
@interface _MWCTLine : NSObject { @public NSArray *runs; CFRange range; CGFloat width, ascent, descent, leading, trailing; }
@end
@implementation _MWCTLine
- (void)dealloc { [runs release]; [super dealloc]; }
@end
#define RUN(r) ((_MWCTRun *)(r))
#define LINE(l) ((_MWCTLine *)(l))

static NSFont *attr_font(NSDictionary *a) { NSFont *f = a[NSFontAttributeName]; return f ? f : [NSFont fontWithName:@"Helvetica" size:12]; }   /* CoreText's default */
static CGColorRef attr_color(NSDictionary *a) {
    if ([a[(id)kCTForegroundColorFromContextAttributeName] boolValue]) return NULL;
    id c = a[(id)kCTForegroundColorAttributeName];
    if (c) return CGColorRetain((CGColorRef)c);
    NSColor *ns = a[NSForegroundColorAttributeName];
    return CGColorRetain((ns ? ns : [NSColor blackColor]).CGColor);
}
static CGColorRef any_color(NSDictionary *a, NSString *cg, NSString *ns) {
    id c = a[cg];
    if (c) return (CGColorRef)c;
    NSColor *n = a[ns];
    return n ? n.CGColor : NULL;
}
static BOOL is_newline(unichar c) { return c == '\n' || c == '\r' || c == 0x2028 || c == 0x2029 || c == 0x85; }
static NSParagraphStyle *para_at(NSAttributedString *s, NSUInteger i) {
    NSParagraphStyle *p = [s length] ? [s attribute:NSParagraphStyleAttributeName atIndex:MIN(i, [s length] - 1) effectiveRange:NULL] : nil;
    return p ? p : [NSParagraphStyle defaultParagraphStyle];
}
static CGFloat tab_interval(NSParagraphStyle *p) { return p.defaultTabInterval > 0 ? p.defaultTabInterval : 28; }

/* the advance of each character: one host measurement per character and font, kept in a table per font (BMP), plus
 * kerning */
static float *advance_table(NSFont *f) {
    static NSMutableDictionary *tables;
    static NSLock *lock;
    if (!lock) lock = [[NSLock alloc] init];
    NSString *k = [NSString stringWithFormat:@"%@\x1f%g\x1f%g", f.fontName, f.pointSize, f.weight];
    [lock lock];
    if (!tables) tables = [[NSMutableDictionary alloc] init];
    NSMutableData *d = tables[k];
    if (!d) {
        d = [NSMutableData dataWithLength:65536 * sizeof(float)];
        float *t = [d mutableBytes];
        for (int i = 0; i < 65536; i++) t[i] = -1;
        if ([tables count] > 64) [tables removeAllObjects];
        tables[k] = d;
    }
    [lock unlock];
    return [d mutableBytes];
}
static CGFloat char_advance(NSString *s, NSUInteger i, NSFont *f, CGFloat kern, CGFloat pen, NSParagraphStyle *p, float *table) {
    unichar c = [s characterAtIndex:i];
    if (is_newline(c)) return 0;
    if (c == '\t') { CGFloat t = tab_interval(p); return (floor(pen / t) + 1) * t - pen; }
    if (CFStringIsSurrogateLowCharacter(c) && i > 0 && CFStringIsSurrogateHighCharacter([s characterAtIndex:i - 1])) return 0;
    if (CFStringIsSurrogateHighCharacter(c) && i + 1 < [s length]) return mw_text_width([s substringWithRange:NSMakeRange(i, 2)], f) + kern;
    if (table && table[c] >= 0) return table[c] + kern;
    CGFloat w = mw_text_width([NSString stringWithCharacters:&c length:1], f);
    if (table) table[c] = (float)w;
    return w + kern;
}

/* a run of characters [r] with attributes a, starting at pen x within its line */
static _MWCTRun *make_run(NSAttributedString *as, NSRange r, NSDictionary *a, CGFloat x) {
    _MWCTRun *run = [[[_MWCTRun alloc] init] autorelease];
    NSString *s = as.string;
    run->attrs = [a retain]; run->font = [attr_font(a) retain]; run->color = attr_color(a);
    run->range = CFRangeMake((CFIndex)r.location, (CFIndex)r.length); run->n = (CFIndex)r.length; run->x = x;
    run->glyphs = malloc(r.length * sizeof *run->glyphs + 1); run->pos = malloc(r.length * sizeof *run->pos + 1);
    run->adv = malloc(r.length * sizeof *run->adv + 1); run->idx = malloc(r.length * sizeof *run->idx + 1);
    CGFloat kern = [a[NSKernAttributeName] doubleValue], pen = 0, ascent, descent;
    NSParagraphStyle *p = para_at(as, r.location);
    NSMutableString *text = [NSMutableString string];
    BOOL tabs = NO;
    float *table = advance_table(run->font);
    for (NSUInteger k = 0; k < r.length; k++) {
        NSUInteger i = r.location + k;
        unichar c = [s characterAtIndex:i];
        CGFloat w = char_advance(s, i, run->font, kern, x + pen, p, table);
        run->glyphs[k] = is_newline(c) || c == '\t' ? 0xFFFF : c;
        run->idx[k] = (CFIndex)i; run->adv[k] = CGSizeMake(w, 0); run->pos[k] = CGPointMake(pen, 0);
        pen += w;
        if (c == '\t') tabs = YES;
        if (!is_newline(c)) [text appendFormat:@"%C", (unichar)(c == '\t' ? ' ' : c)];
    }
    /* drawn as a whole, the text may be narrower or wider than its characters' sum: spread them to its width */
    CGFloat whole = tabs ? pen : mw_text_width(text, run->font) + kern * [text length];
    if (!tabs && pen > 0 && whole > 0 && fabs(whole - pen) > 0.01) {
        CGFloat k = whole / pen;
        for (CFIndex j = 0; j < run->n; j++) { run->pos[j].x *= k; run->adv[j].width *= k; }
        pen = whole;
    }
    run->width = pen;
    run->text = [(tabs ? nil : text) copy];
    mw_font_metrics(run->font, &ascent, &descent);
    run->baseline = [a[(id)kCTBaselineOffsetAttributeName] doubleValue] + [a[kBaselineNS] doubleValue]
                  + [a[(id)kCTSuperscriptAttributeName] intValue] * run->font.pointSize * 0.33;
    run->ascent = ascent; run->descent = descent;
    return run;
}

/* a line of the characters in r: one run per attribute run */
static _MWCTLine *make_line(NSAttributedString *as, NSRange r) {
    _MWCTLine *line = [[[_MWCTLine alloc] init] autorelease];
    NSMutableArray *runs = [NSMutableArray array];
    __block CGFloat x = 0;
    [as enumerateAttributesInRange:r options:0 usingBlock:^(NSDictionary *a, NSRange q, BOOL *stop) {
        _MWCTRun *run = make_run(as, q, a, x);
        x += run->width;
        [runs addObject:run];
    }];
    line->runs = [runs retain]; line->range = CFRangeMake((CFIndex)r.location, (CFIndex)r.length); line->width = x;
    for (_MWCTRun *run in runs) {
        line->ascent = fmax(line->ascent, run->ascent + run->baseline);
        line->descent = fmax(line->descent, run->descent - run->baseline);
    }
    if (![runs count] || line->ascent + line->descent <= 0) {   /* an empty line has the height of its font */
        CGFloat a, d; mw_font_metrics(attr_font([as length] ? [as attributesAtIndex:MIN(r.location, [as length] - 1) effectiveRange:NULL] : @{}), &a, &d);
        line->ascent = a; line->descent = d;
    }
    /* trailing white space (and the line break) */
    NSString *s = as.string;
    for (NSUInteger i = NSMaxRange(r); i > r.location; i--) {
        unichar c = [s characterAtIndex:i - 1];
        if (c != ' ' && c != '\t' && !is_newline(c) && c != 0x3000) break;
        for (_MWCTRun *run in runs) if (NSLocationInRange(i - 1, NSMakeRange((NSUInteger)run->range.location, (NSUInteger)run->range.length)))
            line->trailing += run->adv[(CFIndex)(i - 1) - run->range.location].width;
    }
    return line;
}

/* ======================================================================= breaking lines */
static BOOL break_after(unichar c) { return c == ' ' || c == '\t' || c == '-' || c == 0x2010 || c == 0x2013 || c == 0x200B || c == 0x3000; }
static BOOL cjk(unichar c) { return (c >= 0x2E80 && c <= 0x9FFF) || (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFF00 && c <= 0xFFEF); }
/* how many characters from start fit in width: up to a line break, else to the last place a line may break (cluster:
 * any character) that fits; at least one character. White space at the end of a line does not count. */
static CFIndex suggest_break(NSAttributedString *as, CFIndex start, double width, BOOL cluster) {
    NSString *s = as.string;
    CFIndex n = (CFIndex)[s length], last = -1;
    CGFloat pen = 0;
    NSRange ar = NSMakeRange(0, 0); NSDictionary *a = nil; NSFont *f = nil; CGFloat kern = 0; float *table = NULL;
    NSParagraphStyle *p = para_at(as, (NSUInteger)start);
    for (CFIndex i = start; i < n; i++) {
        unichar c = [s characterAtIndex:(NSUInteger)i];
        if (is_newline(c)) return i + 1 - start + (c == '\r' && i + 1 < n && [s characterAtIndex:(NSUInteger)i + 1] == '\n');
        if (!NSLocationInRange((NSUInteger)i, ar)) { a = [as attributesAtIndex:(NSUInteger)i effectiveRange:&ar]; f = attr_font(a); kern = [a[NSKernAttributeName] doubleValue]; table = advance_table(f); }
        CGFloat w = char_advance(s, (NSUInteger)i, f, kern, pen, p, table);
        BOOL space = c == ' ' || c == '\t' || c == 0x3000;
        if (!space && pen + w > width + 0.001 && i > start) {
            if (!cluster && last > start) return last - start;
            if (CFStringIsSurrogateLowCharacter(c) && i - 1 > start) i--;
            return i - start;
        }
        pen += w;
        if (break_after(c) || cjk(c) || (i + 1 < n && cjk([s characterAtIndex:(NSUInteger)i + 1]))) last = i + 1;
    }
    return n - start;
}

/* ======================================================================= typesetters, framesetters, frames */
@interface _MWCTTypesetter : NSObject { @public NSAttributedString *s; } @end
@implementation _MWCTTypesetter - (void)dealloc { [s release]; [super dealloc]; } @end
@interface _MWCTFramesetter : NSObject { @public _MWCTTypesetter *ts; } @end
@implementation _MWCTFramesetter - (void)dealloc { [ts release]; [super dealloc]; } @end
@interface _MWCTFrame : NSObject { @public NSArray *lines; CGPoint *origins; CFRange range, visible; CGPathRef path; NSDictionary *attrs; } @end
@implementation _MWCTFrame - (void)dealloc { [lines release]; free(origins); CGPathRelease(path); [attrs release]; [super dealloc]; } @end
#define TS(t) ((_MWCTTypesetter *)(t))

static NSRange full(CFRange r, NSUInteger len) {
    NSUInteger loc = MIN((NSUInteger)MAX(r.location, 0), len);
    return NSMakeRange(loc, r.length > 0 ? MIN((NSUInteger)r.length, len - loc) : len - loc);
}
static double flush_offset(_MWCTLine *l, CGFloat factor, double width) { return fmax(0, (width - (l->width - l->trailing)) * fmax(0, fmin(1, factor))); }
static CGFloat flush_factor(NSTextAlignment a) { return a == NSTextAlignmentRight ? 1 : a == NSTextAlignmentCenter ? 0.5 : 0; }

static _MWCTLine *truncated_line(_MWCTLine *l, double width, CTLineTruncationType type, _MWCTLine *token, NSAttributedString *src);
/* lines of s[r] in a box width wide and (height > 0) that high, top first; origins: baselines from the box's bottom */
static NSArray *lay_out(NSAttributedString *s, NSRange r, CGFloat width, CGFloat height, CGPoint **origins_out, NSUInteger *end_out) {
    NSMutableArray *lines = [NSMutableArray array];
    NSMutableData *origins = [NSMutableData data];
    NSString *str = s.string;
    CGFloat top = height > 0 ? height : 0, y = top;
    NSUInteger i = r.location, end = NSMaxRange(r);
    BOOL first = YES;
    while (i < end || (first && !r.length)) {
        NSParagraphStyle *p = para_at(s, i);
        BOOL starts = i == 0 || is_newline([str characterAtIndex:i - 1]);
        CGFloat indent = starts ? p.firstLineHeadIndent : p.headIndent;
        CGFloat right = p.tailIndent > 0 ? p.tailIndent : width + p.tailIndent, avail = fmax(1, right - indent);
        NSLineBreakMode mode = p.lineBreakMode;
        BOOL one_line = mode == NSLineBreakByClipping || mode == NSLineBreakByTruncatingHead || mode == NSLineBreakByTruncatingTail || mode == NSLineBreakByTruncatingMiddle;
        CFIndex n = r.length ? suggest_break(s, (CFIndex)i, one_line ? 1e18 : avail, mode == NSLineBreakByCharWrapping) : 0;
        if (i + (NSUInteger)n > end) n = (CFIndex)(end - i);
        _MWCTLine *line = make_line(s, NSMakeRange(i, (NSUInteger)n));
        if (one_line && mode != NSLineBreakByClipping && line->width - line->trailing > avail) {
            CTLineTruncationType t = mode == NSLineBreakByTruncatingHead ? kCTLineTruncationStart : mode == NSLineBreakByTruncatingMiddle ? kCTLineTruncationMiddle : kCTLineTruncationEnd;
            _MWCTLine *cut = truncated_line(line, avail, t, nil, s);
            if (cut) line = cut;
        }
        CGFloat asc = line->ascent, desc = line->descent, h = asc + desc + line->leading;
        if (p.lineHeightMultiple > 0) { CGFloat nh = h * p.lineHeightMultiple; asc += nh - h; h = nh; }
        if (p.minimumLineHeight > 0 && h < p.minimumLineHeight) { asc += p.minimumLineHeight - h; h = p.minimumLineHeight; }
        if (p.maximumLineHeight > 0 && h > p.maximumLineHeight) { asc -= h - p.maximumLineHeight; h = p.maximumLineHeight; }
        CGFloat before = first ? 0 : (starts ? p.paragraphSpacingBefore : 0);
        CGFloat base = y - before - asc;
        if (height > 0 && base - desc < -0.5 && !first) break;   /* the box is full */
        if (height > 0 && base - desc < -0.5 && first && h > height + 0.5) break;
        [lines addObject:line];
        CGPoint o = CGPointMake(indent + flush_offset(line, flush_factor(p.alignment), avail), base);
        [origins appendBytes:&o length:sizeof o];
        i += (NSUInteger)n;
        BOOL ends = n > 0 && is_newline([str characterAtIndex:i - 1]);
        y = base - desc - line->leading - p.lineSpacing - (ends ? p.paragraphSpacing : 0);
        first = NO;
        if (!n) break;
    }
    if (height <= 0 && lines.count) {   /* unbounded: baselines were placed down from 0; the box's bottom is the last line's */
        CGPoint *o = (CGPoint *)[origins mutableBytes];
        _MWCTLine *last = [lines lastObject];
        CGFloat shift = -(o[lines.count - 1].y - last->descent - last->leading);
        for (NSUInteger k = 0; k < lines.count; k++) o[k].y += shift;
    }
    if (origins_out) { *origins_out = malloc([origins length] + 1); memcpy(*origins_out, [origins bytes], [origins length]); }
    if (end_out) *end_out = i;
    return lines;
}

/* ======================================================================= drawing */
/* a line with its baseline's left end at the origin of `place` (text space -> user space) */
static void draw_line_runs(CGContextRef c, _MWCTLine *l, CGAffineTransform place, CFRange only) {
    for (_MWCTRun *run in l->runs) {
        if (only.length && (run->range.location + run->n <= only.location || run->range.location >= only.location + only.length)) continue;
        CGColorRef bg = any_color(run->attrs, (id)kCTBackgroundColorAttributeName, kBackgroundNS);
        if (bg) {
            CGRect r = CGRectApplyAffineTransform(CGRectMake(run->x, -run->descent + run->baseline, run->width, run->ascent + run->descent), place);
            CGContextSaveGState(c); CGContextSetFillColorWithColor(c, bg); CGContextFillRect(c, r); CGContextRestoreGState(c);
        }
        CGPoint p = CGPointApplyAffineTransform(CGPointMake(run->x, run->baseline), place);
        if (run->text) mw_draw_text_line(c, run->text, run->font, run->color, p);
        else {   /* tabs: piece by piece */
            for (CFIndex k = 0, from = 0; k <= run->n; k++) {
                if (k < run->n && run->glyphs[k] != 0xFFFF) continue;
                if (k > from) {
                    unichar *u = malloc((size_t)(k - from) * sizeof *u);
                    for (CFIndex j = from; j < k; j++) u[j - from] = run->glyphs[j];
                    NSString *piece = [NSString stringWithCharacters:u length:(NSUInteger)(k - from)];
                    free(u);
                    mw_draw_text_line(c, piece, run->font, run->color, CGPointApplyAffineTransform(CGPointMake(run->x + run->pos[from].x, run->baseline), place));
                }
                from = k + 1;
            }
        }
        int ul = [run->attrs[NSUnderlineStyleAttributeName] intValue], st = [run->attrs[kStrikeNS] intValue];
        CGFloat trail = 0;
        if (run == [l->runs lastObject]) trail = fmin(l->trailing, run->width);
        for (int k = 0; k < 2; k++) {
            int style = k ? st : ul;
            if (!(style & 0xff)) continue;
            CGFloat th = (style & 0xff) == kCTUnderlineStyleThick ? 2 : 1, y = k ? run->ascent * 0.3 : -fmax(1, run->descent * 0.4);
            CGColorRef uc = k ? NULL : any_color(run->attrs, (id)kCTUnderlineColorAttributeName, kUnderlineColorNS);
            CGRect r = CGRectApplyAffineTransform(CGRectMake(run->x, run->baseline + y - th / 2, run->width - trail, th), place);
            CGContextSaveGState(c);
            if (uc || run->color) CGContextSetFillColorWithColor(c, uc ? uc : run->color);
            CGContextFillRect(c, r);
            if ((style & 0xff) == kCTUnderlineStyleDouble) CGContextFillRect(c, CGRectApplyAffineTransform(CGRectMake(run->x, run->baseline + y - th / 2 - 2, run->width - trail, th), place));
            CGContextRestoreGState(c);
        }
    }
}
static CGAffineTransform text_place(CGContextRef c, CGFloat dx, CGFloat dy) {
    CGAffineTransform tm = CGContextGetTextMatrix(c);
    return CGAffineTransformTranslate(tm, dx, dy);
}

/* ======================================================================= CTLine */
static CFIndex line_glyphs(_MWCTLine *l) { CFIndex n = 0; for (_MWCTRun *r in l->runs) n += r->n; return n; }
CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef s) {
    NSAttributedString *as = [[(NSAttributedString *)s copy] autorelease];
    return (CTLineRef)[make_line(as, NSMakeRange(0, [as length])) retain];
}
CFIndex CTLineGetGlyphCount(CTLineRef l) { return line_glyphs(LINE(l)); }
CFArrayRef CTLineGetGlyphRuns(CTLineRef l) { return (CFArrayRef)LINE(l)->runs; }
CFRange CTLineGetStringRange(CTLineRef l) { return LINE(l)->range; }
double CTLineGetPenOffsetForFlush(CTLineRef l, CGFloat f, double w) { return flush_offset(LINE(l), f, w); }
double CTLineGetTypographicBounds(CTLineRef l, CGFloat *a, CGFloat *d, CGFloat *lead) {
    if (a) *a = LINE(l)->ascent;
    if (d) *d = LINE(l)->descent;
    if (lead) *lead = LINE(l)->leading;
    return LINE(l)->width;
}
double CTLineGetTrailingWhitespaceWidth(CTLineRef l) { return LINE(l)->trailing; }
CGRect CTLineGetBoundsWithOptions(CTLineRef l, CTLineBoundsOptions o) {
    _MWCTLine *x = LINE(l);
    return CGRectMake(0, -x->descent, x->width, x->ascent + x->descent + ((o & kCTLineBoundsExcludeTypographicLeading) ? 0 : x->leading));
}
CGRect CTLineGetImageBounds(CTLineRef l, CGContextRef c) {
    _MWCTLine *x = LINE(l);
    CGPoint p = c ? CGContextGetTextPosition(c) : CGPointZero;
    return x->width - x->trailing > 0 ? CGRectMake(p.x, p.y - x->descent, x->width - x->trailing, x->ascent + x->descent) : CGRectNull;
}
CGFloat CTLineGetOffsetForStringIndex(CTLineRef l, CFIndex i, CGFloat *secondary) {
    CGFloat off = LINE(l)->width;
    for (_MWCTRun *r in LINE(l)->runs) {
        if (i >= r->range.location && i < r->range.location + r->n) { off = r->x + r->pos[i - r->range.location].x; break; }
        if (i < r->range.location) { off = r->x; break; }
    }
    if (secondary) *secondary = off;
    return off;
}
/* the caret position nearest x: before or after the character it falls on */
CFIndex CTLineGetStringIndexForPosition(CTLineRef l, CGPoint p) {
    _MWCTLine *x = LINE(l);
    if (![x->runs count]) return x->range.location;
    for (_MWCTRun *r in x->runs)
        for (CFIndex k = 0; k < r->n; k++) {
            CGFloat a = r->x + r->pos[k].x, w = r->adv[k].width;
            if (p.x < a + w / 2) return r->idx[k];
        }
    return x->range.location + x->range.length;
}
void CTLineEnumerateCaretOffsets(CTLineRef l, void (^b)(double, CFIndex, bool, bool *)) {
    bool stop = false;
    for (_MWCTRun *r in LINE(l)->runs)
        for (CFIndex k = 0; k < r->n && !stop; k++) {
            b(r->x + r->pos[k].x, r->idx[k], true, &stop);
            if (!stop) b(r->x + r->pos[k].x + r->adv[k].width, r->idx[k], false, &stop);
        }
}
void CTLineDraw(CTLineRef l, CGContextRef c) { if (c && l) draw_line_runs(c, LINE(l), text_place(c, 0, 0), CFRangeMake(0, 0)); }
CTLineRef CTLineCreateJustifiedLine(CTLineRef l, CGFloat factor, double width) { return (CTLineRef)[(id)l retain]; }   /* ponytail: not stretched */

/* the characters of the line that fit with the token ("…" in the line's last attributes) at the end, start or middle */
static NSAttributedString *line_string(_MWCTLine *l, NSAttributedString *src) {
    NSMutableAttributedString *m = [[[NSMutableAttributedString alloc] init] autorelease];
    for (_MWCTRun *r in l->runs) {
        NSMutableString *t = [NSMutableString string];
        for (CFIndex k = 0; k < r->n; k++) [t appendFormat:@"%C", (unichar)(r->glyphs[k] == 0xFFFF ? (src ? [src.string characterAtIndex:(NSUInteger)r->idx[k]] : ' ') : r->glyphs[k])];
        [m appendAttributedString:[[[NSAttributedString alloc] initWithString:t attributes:r->attrs] autorelease]];
    }
    return m;
}
static _MWCTLine *truncated_line(_MWCTLine *l, double width, CTLineTruncationType type, _MWCTLine *token, NSAttributedString *src) {
    if (l->width - l->trailing <= width) return l;
    NSAttributedString *s = line_string(l, src);
    NSAttributedString *tok = token ? line_string(token, nil)
        : [[[NSAttributedString alloc] initWithString:@"…" attributes:[l->runs count] ? ((_MWCTRun *)(type == kCTLineTruncationStart ? l->runs[0] : [l->runs lastObject]))->attrs : @{}] autorelease];
    CGFloat tw = make_line(tok, NSMakeRange(0, [tok length]))->width;
    if (tw > width) return nil;
    NSUInteger n = [s length], lo = 0, hi = n;
    NSAttributedString *best = tok;
    while (lo < hi) {   /* the most characters kept that fit */
        NSUInteger mid = (lo + hi + 1) / 2;
        NSMutableAttributedString *m = [[[NSMutableAttributedString alloc] init] autorelease];
        if (type == kCTLineTruncationEnd) { [m appendAttributedString:[s attributedSubstringFromRange:NSMakeRange(0, mid)]]; [m appendAttributedString:tok]; }
        else if (type == kCTLineTruncationStart) { [m appendAttributedString:tok]; [m appendAttributedString:[s attributedSubstringFromRange:NSMakeRange(n - mid, mid)]]; }
        else { NSUInteger a = (mid + 1) / 2, b = mid / 2;
               [m appendAttributedString:[s attributedSubstringFromRange:NSMakeRange(0, a)]]; [m appendAttributedString:tok];
               [m appendAttributedString:[s attributedSubstringFromRange:NSMakeRange(n - b, b)]]; }
        _MWCTLine *x = make_line(m, NSMakeRange(0, [m length]));
        if (x->width - x->trailing <= width) { lo = mid; best = m; } else hi = mid - 1;
    }
    _MWCTLine *out = make_line(best, NSMakeRange(0, [best length]));
    out->range = l->range;
    return out;
}
CTLineRef CTLineCreateTruncatedLine(CTLineRef l, double width, CTLineTruncationType type, CTLineRef token) {
    _MWCTLine *t = truncated_line(LINE(l), width, type, LINE(token), nil);
    return (CTLineRef)[t retain];
}

/* ======================================================================= CTRun */
CFIndex CTRunGetGlyphCount(CTRunRef r) { return RUN(r)->n; }
CFDictionaryRef CTRunGetAttributes(CTRunRef r) { return (CFDictionaryRef)RUN(r)->attrs; }
CTRunStatus CTRunGetStatus(CTRunRef r) { return kCTRunStatusNoStatus; }
CFRange CTRunGetStringRange(CTRunRef r) { return RUN(r)->range; }
CGAffineTransform CTRunGetTextMatrix(CTRunRef r) { return CGAffineTransformIdentity; }
static CFRange sub_range(_MWCTRun *r, CFRange q) { return q.length ? q : CFRangeMake(q.location, r->n - q.location); }
const CGGlyph *CTRunGetGlyphsPtr(CTRunRef r) { return RUN(r)->glyphs; }
const CGPoint *CTRunGetPositionsPtr(CTRunRef r) { return RUN(r)->pos; }
const CGSize *CTRunGetAdvancesPtr(CTRunRef r) { return RUN(r)->adv; }
const CFIndex *CTRunGetStringIndicesPtr(CTRunRef r) { return RUN(r)->idx; }
void CTRunGetGlyphs(CTRunRef r, CFRange q, CGGlyph b[]) { q = sub_range(RUN(r), q); memcpy(b, RUN(r)->glyphs + q.location, (size_t)q.length * sizeof *b); }
/* positions are in line space (from the line's start), as CoreText gives them */
void CTRunGetPositions(CTRunRef r, CFRange q, CGPoint b[]) {
    q = sub_range(RUN(r), q);
    for (CFIndex k = 0; k < q.length; k++) b[k] = CGPointMake(RUN(r)->x + RUN(r)->pos[q.location + k].x, RUN(r)->baseline);
}
void CTRunGetAdvances(CTRunRef r, CFRange q, CGSize b[]) { q = sub_range(RUN(r), q); memcpy(b, RUN(r)->adv + q.location, (size_t)q.length * sizeof *b); }
void CTRunGetStringIndices(CTRunRef r, CFRange q, CFIndex b[]) { q = sub_range(RUN(r), q); memcpy(b, RUN(r)->idx + q.location, (size_t)q.length * sizeof *b); }
double CTRunGetTypographicBounds(CTRunRef r, CFRange q, CGFloat *a, CGFloat *d, CGFloat *lead) {
    _MWCTRun *x = RUN(r); q = sub_range(x, q);
    if (a) *a = x->ascent;
    if (d) *d = x->descent;
    if (lead) *lead = 0;
    double w = 0; for (CFIndex k = 0; k < q.length; k++) w += x->adv[q.location + k].width;
    return w;
}
CGRect CTRunGetImageBounds(CTRunRef r, CGContextRef c, CFRange q) {
    _MWCTRun *x = RUN(r); q = sub_range(x, q);
    CGFloat w = 0; for (CFIndex k = 0; k < q.length; k++) w += x->adv[q.location + k].width;
    CGPoint p = c ? CGContextGetTextPosition(c) : CGPointZero;
    return CGRectMake(p.x + x->x + (q.length ? x->pos[q.location].x : 0), p.y + x->baseline - x->descent, w, x->ascent + x->descent);
}
void CTRunDraw(CTRunRef r, CGContextRef c, CFRange q) {
    if (!c) return;
    _MWCTLine *l = [[[_MWCTLine alloc] init] autorelease];
    l->runs = [@[(id)r] retain]; l->width = RUN(r)->x + RUN(r)->width;
    draw_line_runs(c, l, text_place(c, 0, 0), CFRangeMake(0, 0));   /* ponytail: the whole run */
}

/* ======================================================================= CTTypesetter */
CTTypesetterRef CTTypesetterCreateWithAttributedString(CFAttributedStringRef s) {
    _MWCTTypesetter *t = [[_MWCTTypesetter alloc] init];
    t->s = [(NSAttributedString *)s copy];
    return (CTTypesetterRef)t;
}
CTTypesetterRef CTTypesetterCreateWithAttributedStringAndOptions(CFAttributedStringRef s, CFDictionaryRef o) { return CTTypesetterCreateWithAttributedString(s); }
CTLineRef CTTypesetterCreateLine(CTTypesetterRef t, CFRange r) { return (CTLineRef)[make_line(TS(t)->s, full(r, [TS(t)->s length])) retain]; }
CTLineRef CTTypesetterCreateLineWithOffset(CTTypesetterRef t, CFRange r, double off) { return CTTypesetterCreateLine(t, r); }
CFIndex CTTypesetterSuggestLineBreak(CTTypesetterRef t, CFIndex start, double w) { return start < (CFIndex)[TS(t)->s length] ? suggest_break(TS(t)->s, start, w, NO) : 0; }
CFIndex CTTypesetterSuggestLineBreakWithOffset(CTTypesetterRef t, CFIndex start, double w, double off) { return CTTypesetterSuggestLineBreak(t, start, w - off); }
CFIndex CTTypesetterSuggestClusterBreak(CTTypesetterRef t, CFIndex start, double w) { return start < (CFIndex)[TS(t)->s length] ? suggest_break(TS(t)->s, start, w, YES) : 0; }
CFIndex CTTypesetterSuggestClusterBreakWithOffset(CTTypesetterRef t, CFIndex start, double w, double off) { return CTTypesetterSuggestClusterBreak(t, start, w - off); }

/* ======================================================================= CTFramesetter, CTFrame */
CTFramesetterRef CTFramesetterCreateWithTypesetter(CTTypesetterRef t) {
    _MWCTFramesetter *f = [[_MWCTFramesetter alloc] init];
    f->ts = [(id)t retain];
    return (CTFramesetterRef)f;
}
CTFramesetterRef CTFramesetterCreateWithAttributedString(CFAttributedStringRef s) {
    CTTypesetterRef t = CTTypesetterCreateWithAttributedString(s);
    CTFramesetterRef f = CTFramesetterCreateWithTypesetter(t);
    CFRelease(t);
    return f;
}
CTTypesetterRef CTFramesetterGetTypesetter(CTFramesetterRef f) { return (CTTypesetterRef)((_MWCTFramesetter *)f)->ts; }
/* ponytail: the path's bounding box, not its shape */
CTFrameRef CTFramesetterCreateFrame(CTFramesetterRef fs, CFRange r, CGPathRef path, CFDictionaryRef attrs) {
    NSAttributedString *s = ((_MWCTFramesetter *)fs)->ts->s;
    CGRect box = path ? CGPathGetBoundingBox(path) : CGRectZero;
    _MWCTFrame *f = [[_MWCTFrame alloc] init];
    NSRange nr = full(r, [s length]);
    NSUInteger end = nr.location;
    f->lines = [lay_out(s, nr, box.size.width, box.size.height > 0 ? box.size.height : 0.001, &f->origins, &end) retain];
    f->range = CFRangeMake((CFIndex)nr.location, (CFIndex)nr.length);
    f->visible = CFRangeMake((CFIndex)nr.location, (CFIndex)(end - nr.location));
    f->path = CGPathRetain(path); f->attrs = [(NSDictionary *)attrs copy];
    return (CTFrameRef)f;
}
CGSize CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterRef fs, CFRange r, CFDictionaryRef attrs, CGSize cons, CFRange *fit) {
    NSAttributedString *s = ((_MWCTFramesetter *)fs)->ts->s;
    NSRange nr = full(r, [s length]);
    CGFloat w = cons.width > 0 && cons.width < 1e7 ? cons.width : 1e7, h = cons.height > 0 && cons.height < 1e7 ? cons.height : 0;
    CGPoint *o = NULL; NSUInteger end = nr.location;
    NSArray *lines = lay_out(s, nr, w, h, &o, &end);
    CGFloat maxw = 0, top = 0, bottom = 0;
    for (NSUInteger k = 0; k < lines.count; k++) {
        _MWCTLine *l = lines[k];
        maxw = fmax(maxw, o[k].x + l->width - l->trailing);
        if (!k) top = o[k].y + l->ascent;
        bottom = o[k].y - l->descent - l->leading;
    }
    if (h > 0) top = h;
    free(o);
    if (fit) *fit = CFRangeMake((CFIndex)nr.location, (CFIndex)(end - nr.location));
    return CGSizeMake(ceil(maxw), ceil(lines.count ? top - bottom : 0));
}
#define FRAME(f) ((_MWCTFrame *)(f))
CFRange CTFrameGetStringRange(CTFrameRef f) { return FRAME(f)->range; }
CFRange CTFrameGetVisibleStringRange(CTFrameRef f) { return FRAME(f)->visible; }
CGPathRef CTFrameGetPath(CTFrameRef f) { return FRAME(f)->path; }
CFDictionaryRef CTFrameGetFrameAttributes(CTFrameRef f) { return (CFDictionaryRef)FRAME(f)->attrs; }
CFArrayRef CTFrameGetLines(CTFrameRef f) { return (CFArrayRef)FRAME(f)->lines; }
void CTFrameGetLineOrigins(CTFrameRef f, CFRange r, CGPoint o[]) {
    NSRange q = full(r, [FRAME(f)->lines count]);
    memcpy(o, FRAME(f)->origins + q.location, q.length * sizeof *o);
}
void CTFrameDraw(CTFrameRef f, CGContextRef c) {
    if (!c) return;
    CGRect box = FRAME(f)->path ? CGPathGetBoundingBox(FRAME(f)->path) : CGRectZero;
    CGAffineTransform tm = CGContextGetTextMatrix(c);
    for (NSUInteger k = 0; k < [FRAME(f)->lines count]; k++) {
        CGPoint o = FRAME(f)->origins[k];
        CGAffineTransform place = tm; place.tx = box.origin.x + o.x; place.ty = box.origin.y + o.y;
        draw_line_runs(c, FRAME(f)->lines[k], place, CFRangeMake(0, 0));
    }
}

/* ======================================================================= text in views: NSAttributedString drawing, NSTextView
 * A layout is the lines of a string wrapped at a width, with their baselines measured down from the top. */
@implementation _MWTextLayout
- (void)dealloc { [lines release]; free(base); free(x); [super dealloc]; }
@end
_MWTextLayout *mw_text_layout(NSAttributedString *s, CGFloat width) {
    _MWTextLayout *t = [[[_MWTextLayout alloc] init] autorelease];
    CGPoint *o = NULL;
    NSArray *lines = lay_out(s, NSMakeRange(0, [s length]), width > 0 ? width : 1e7, 0, &o, NULL);
    t->lines = [lines retain]; t->length = [s length];
    t->base = malloc((lines.count + 1) * sizeof *t->base); t->x = malloc((lines.count + 1) * sizeof *t->x);
    CGFloat top = lines.count ? o[0].y + ((_MWCTLine *)lines[0])->ascent : 0;
    for (NSUInteger k = 0; k < lines.count; k++) { t->base[k] = top - o[k].y; t->x[k] = o[k].x; }
    t->height = top;
    t->trailing_newline = [s length] && is_newline([s.string characterAtIndex:[s length] - 1]);
    if (t->trailing_newline && lines.count) {   /* the empty line after a final line break */
        _MWCTLine *last = [lines lastObject];
        t->height += last->ascent + last->descent;
    }
    free(o);
    return t;
}
static void layout_draw(_MWTextLayout *t, CGContextRef c, NSPoint at, BOOL flipped, CGFloat clip_h) {
    for (NSUInteger k = 0; k < t->lines.count; k++) {
        _MWCTLine *l = t->lines[k];
        if (clip_h > 0 && t->base[k] - l->ascent > clip_h + 0.5) break;
        CGAffineTransform place = flipped ? CGAffineTransformMake(1, 0, 0, -1, at.x + t->x[k], at.y + t->base[k])
                                          : CGAffineTransformMake(1, 0, 0, 1, at.x + t->x[k], at.y - t->base[k]);
        draw_line_runs(c, l, place, CFRangeMake(0, 0));
    }
}
/* at: the top-left of the text (flipped views) or its top-left in y-up coordinates */
void mw_text_layout_draw(_MWTextLayout *t, NSPoint at) {
    CGContextRef c = mw_cg();
    if (c) layout_draw(t, c, at, [[NSGraphicsContext currentContext] isFlipped], 0);
}
static NSUInteger line_of(_MWTextLayout *t, NSUInteger i) {
    for (NSUInteger k = 0; k < t->lines.count; k++) {
        CFRange r = ((_MWCTLine *)t->lines[k])->range;
        if ((CFIndex)i < r.location + r.length || k + 1 == t->lines.count) return k;
    }
    return 0;
}
/* the caret before character i: x, the top of its line and the line's height, from the top-left of the text */
NSRect mw_text_caret(_MWTextLayout *t, NSUInteger i, NSFont *empty) {
    if (!t->lines.count || (i >= t->length && t->trailing_newline)) {
        CGFloat a, d; mw_font_metrics(empty ? empty : [NSFont systemFontOfSize:12], &a, &d);
        _MWCTLine *last = [t->lines lastObject];
        CGFloat y = last ? t->base[t->lines.count - 1] + last->descent : 0;
        if (last) { a = last->ascent; d = last->descent; }
        return NSMakeRect(0, y, 1, a + d);
    }
    NSUInteger k = line_of(t, i);
    _MWCTLine *l = t->lines[k];
    CGFloat x = t->x[k] + CTLineGetOffsetForStringIndex((CTLineRef)l, (CFIndex)i, NULL);
    /* at a soft line break the caret goes to the start of the next line */
    return NSMakeRect(x, t->base[k] - l->ascent, 1, l->ascent + l->descent);
}
/* the character index nearest p (from the top-left of the text) */
NSUInteger mw_text_index(_MWTextLayout *t, NSPoint p) {
    if (!t->lines.count) return 0;
    NSUInteger k = 0;
    while (k + 1 < t->lines.count && p.y > t->base[k] + ((_MWCTLine *)t->lines[k])->descent) k++;
    if (t->trailing_newline && k + 1 == t->lines.count && p.y > t->base[k] + ((_MWCTLine *)t->lines[k])->descent) return t->length;
    _MWCTLine *l = t->lines[k];
    CFIndex i = CTLineGetStringIndexForPosition((CTLineRef)l, CGPointMake(p.x - t->x[k], 0));
    CFIndex end = l->range.location + l->range.length;   /* not past the line's own break */
    if (i >= end && end > l->range.location && k + 1 < t->lines.count) i = end - 1;
    return (NSUInteger)i;
}
/* the index on the line above (dir -1) or below (+1) nearest the same x; NSNotFound past the first or last */
NSUInteger mw_text_vertical(_MWTextLayout *t, NSUInteger i, int dir, NSFont *f) {
    NSRect c = mw_text_caret(t, i, f);
    CGFloat y = dir < 0 ? c.origin.y - 1 : NSMaxY(c) + 1;
    if (y < 0) return NSNotFound;
    if (y > t->height) return NSNotFound;
    return mw_text_index(t, NSMakePoint(c.origin.x, y));
}
/* rectangles covering the characters of r, line by line, from the top-left of the text */
NSArray *mw_text_rects(_MWTextLayout *t, NSRange r) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger k = 0; k < t->lines.count; k++) {
        _MWCTLine *l = t->lines[k];
        NSRange lr = NSMakeRange((NSUInteger)l->range.location, (NSUInteger)l->range.length), q = NSIntersectionRange(lr, r);
        if (!q.length) continue;
        CGFloat a = CTLineGetOffsetForStringIndex((CTLineRef)l, (CFIndex)q.location, NULL), b = CTLineGetOffsetForStringIndex((CTLineRef)l, (CFIndex)NSMaxRange(q), NULL);
        [out addObject:[NSValue valueWithRect:NSMakeRect(t->x[k] + a, t->base[k] - l->ascent, fmax(b - a, 4), l->ascent + l->descent)]];
    }
    return out;
}
NSSize mw_attr_size(NSAttributedString *s, CGFloat maxw) {
    _MWTextLayout *t = mw_text_layout(s, maxw);
    CGFloat w = 0;
    for (NSUInteger k = 0; k < t->lines.count; k++) { _MWCTLine *l = t->lines[k]; w = fmax(w, t->x[k] + l->width - l->trailing); }
    _MWCTLine *last = [t->lines lastObject];
    return NSMakeSize(ceil(w), ceil(last ? t->base[t->lines.count - 1] + last->descent + last->leading : 0));
}
/* lines from the top of r down (in flipped views from its top-left, in others from its top too) */
void mw_attr_draw(NSAttributedString *s, NSRect r, BOOL wrap) {
    CGContextRef c = mw_cg();
    if (!c || ![s length]) return;
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    _MWTextLayout *t = mw_text_layout(s, wrap && r.size.width > 0 ? r.size.width : 0);
    layout_draw(t, c, NSMakePoint(r.origin.x, flipped ? r.origin.y : NSMaxY(r)), flipped, r.size.height);
}

/* ======================================================================= more of CTFont, descriptors, collections */
CTFontRef CTFontCreateWithNameAndOptions(CFStringRef n, CGFloat size, const CGAffineTransform *m, CFOptionFlags o) { return CTFontCreateWithName(n, size, m); }
CTFontRef CTFontCreateCopyWithSymbolicTraits(CTFontRef f, CGFloat size, const CGAffineTransform *m, CTFontSymbolicTraits v, CTFontSymbolicTraits mask) {
    NSFont *nf = (NSFont *)f;
    uint32_t t = (CTFontGetSymbolicTraits(f) & ~mask) | (v & mask);
    NSString *family = [nf.fontName hasPrefix:@"."] ? nil : [[nf.fontName componentsSeparatedByString:@"-"] firstObject];
    NSDictionary *a = family ? @{NSFontFamilyAttribute: family} : @{};
    NSFontDescriptor *d = [[NSFontDescriptor fontDescriptorWithFontAttributes:a] fontDescriptorWithSymbolicTraits:t];
    CGFloat s = size > 0 ? size : nf.pointSize;
    NSFont *out = family ? [NSFont fontWithDescriptor:d size:s] : (t & kCTFontTraitBold) ? [NSFont boldSystemFontOfSize:s] : [NSFont systemFontOfSize:s];
    return (CTFontRef)[out retain];
}
CTFontRef CTFontCreateCopyWithFamily(CTFontRef f, CGFloat size, const CGAffineTransform *m, CFStringRef family) {
    NSFontDescriptor *d = [[NSFontDescriptor fontDescriptorWithFontAttributes:@{NSFontFamilyAttribute: (NSString *)family}] fontDescriptorWithSymbolicTraits:CTFontGetSymbolicTraits(f)];
    return (CTFontRef)[[NSFont fontWithDescriptor:d size:size > 0 ? size : ((NSFont *)f).pointSize] retain];
}
CTFontDescriptorRef CTFontCopyFontDescriptor(CTFontRef f) { return (CTFontDescriptorRef)[[(NSFont *)f fontDescriptor] retain]; }
CGAffineTransform CTFontGetMatrix(CTFontRef f) { return CGAffineTransformIdentity; }
CTFontSymbolicTraits CTFontGetSymbolicTraits(CTFontRef f) {
    NSFont *nf = (NSFont *)f; NSString *n = nf.fontName;
    CTFontSymbolicTraits t = nf.isFixedPitch ? kCTFontTraitMonoSpace : 0;
    if (nf.weight >= 0.3 || [n rangeOfString:@"Bold"].location != NSNotFound || [n rangeOfString:@"Black"].location != NSNotFound || [n rangeOfString:@"Heavy"].location != NSNotFound) t |= kCTFontTraitBold;
    if ([n rangeOfString:@"Italic"].location != NSNotFound || [n rangeOfString:@"Oblique"].location != NSNotFound) t |= kCTFontTraitItalic;
    if ([n hasPrefix:@".AppleSystemUIFont"]) t |= kCTFontTraitUIOptimized;
    return t;
}
CFDictionaryRef CTFontCopyTraits(CTFontRef f) {
    CTFontSymbolicTraits t = CTFontGetSymbolicTraits(f);
    return (CFDictionaryRef)[@{(id)kCTFontSymbolicTrait: @(t), (id)kCTFontWeightTrait: @((t & kCTFontTraitBold) ? 0.4 : ((NSFont *)f).weight),
                               (id)kCTFontWidthTrait: @0, (id)kCTFontSlantTrait: @((t & kCTFontTraitItalic) ? 0.07 : 0)} copy];
}
CFTypeRef CTFontCopyAttribute(CTFontRef f, CFStringRef k) {
    NSFont *nf = (NSFont *)f; NSString *key = (NSString *)k;
    id v = [key isEqualToString:(id)kCTFontNameAttribute] ? nf.fontName : [key isEqualToString:(id)kCTFontFamilyNameAttribute] ? nf.familyName
         : [key isEqualToString:(id)kCTFontDisplayNameAttribute] ? nf.displayName : [key isEqualToString:(id)kCTFontSizeAttribute] ? @(nf.pointSize)
         : [key isEqualToString:(id)kCTFontTraitsAttribute] ? [(id)CTFontCopyTraits(f) autorelease] : nil;
    return [v retain];
}
CFStringRef CTFontCopyName(CTFontRef f, CFStringRef k) {
    NSFont *nf = (NSFont *)f; NSString *key = (NSString *)k;
    NSArray *parts = [nf.fontName componentsSeparatedByString:@"-"];
    id v = [key isEqualToString:(id)kCTFontPostScriptNameKey] || [key isEqualToString:(id)kCTFontUniqueNameKey] ? nf.fontName
         : [key isEqualToString:(id)kCTFontFamilyNameKey] ? nf.familyName : [key isEqualToString:(id)kCTFontFullNameKey] ? nf.displayName
         : [key isEqualToString:(id)kCTFontStyleNameKey] || [key isEqualToString:(id)kCTFontSubFamilyNameKey] ? (parts.count > 1 ? parts.lastObject : @"Regular") : nil;
    return (CFStringRef)[v copy];
}
unsigned CTFontGetUnitsPerEm(CTFontRef f) { return 2048; }
CFIndex CTFontGetGlyphCount(CTFontRef f) { return 65535; }
CGRect CTFontGetBoundingBox(CTFontRef f) { NSFont *nf = (NSFont *)f; return CGRectMake(-nf.pointSize * 0.2, -CTFontGetDescent(f), nf.pointSize * 1.4, CTFontGetAscent(f) + CTFontGetDescent(f)); }
CGFloat CTFontGetSlantAngle(CTFontRef f) { return (CTFontGetSymbolicTraits(f) & kCTFontTraitItalic) ? -12 : 0; }
CGGlyph CTFontGetGlyphWithName(CTFontRef f, CFStringRef n) { NSString *s = (NSString *)n; return [s length] == 1 ? [s characterAtIndex:0] : [s isEqualToString:@"space"] ? ' ' : 0; }
CGPathRef CTFontCreatePathForGlyph(CTFontRef f, CGGlyph g, const CGAffineTransform *m) { return NULL; }   /* ponytail: no outlines */

CTFontDescriptorRef CTFontDescriptorCreateWithNameAndSize(CFStringRef n, CGFloat s) { return (CTFontDescriptorRef)[[NSFontDescriptor fontDescriptorWithName:(NSString *)n size:s] retain]; }
CTFontDescriptorRef CTFontDescriptorCreateWithAttributes(CFDictionaryRef a) { return (CTFontDescriptorRef)[[NSFontDescriptor fontDescriptorWithFontAttributes:(NSDictionary *)a] retain]; }
CTFontDescriptorRef CTFontDescriptorCreateCopyWithAttributes(CTFontDescriptorRef d, CFDictionaryRef a) { return (CTFontDescriptorRef)[[(NSFontDescriptor *)d fontDescriptorByAddingAttributes:(NSDictionary *)a] retain]; }
CTFontDescriptorRef CTFontDescriptorCreateCopyWithFamily(CTFontDescriptorRef d, CFStringRef f) { return (CTFontDescriptorRef)[[(NSFontDescriptor *)d fontDescriptorWithFamily:(NSString *)f] retain]; }
CTFontDescriptorRef CTFontDescriptorCreateCopyWithSymbolicTraits(CTFontDescriptorRef d, CTFontSymbolicTraits v, CTFontSymbolicTraits m) {
    NSFontDescriptor *fd = (NSFontDescriptor *)d;
    return (CTFontDescriptorRef)[[fd fontDescriptorWithSymbolicTraits:(fd.symbolicTraits & ~m) | (v & m)] retain];
}
CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef d, CFStringRef k) { return [[(NSFontDescriptor *)d objectForKey:(NSString *)k] retain]; }
CFDictionaryRef CTFontDescriptorCopyAttributes(CTFontDescriptorRef d) { return (CFDictionaryRef)[[(NSFontDescriptor *)d fontAttributes] copy]; }
CFArrayRef CTFontDescriptorCreateMatchingFontDescriptors(CTFontDescriptorRef d, CFSetRef m) { return (CFArrayRef)[@[(id)d] retain]; }
CTFontDescriptorRef CTFontDescriptorCreateMatchingFontDescriptor(CTFontDescriptorRef d, CFSetRef m) { return (CTFontDescriptorRef)[(id)d retain]; }

/* the fonts NSFontManager knows of, and those registered here */
static NSMutableArray *g_registered;   /* PostScript names */
CFArrayRef CTFontManagerCopyAvailablePostScriptNames(void) {
    NSMutableArray *a = [[[NSFontManager sharedFontManager] availableFonts] mutableCopy];
    @synchronized([NSFontManager class]) { for (NSString *n in g_registered) if (![a containsObject:n]) [a addObject:n]; }
    return (CFArrayRef)a;
}
CFArrayRef CTFontManagerCopyAvailableFontFamilyNames(void) {
    NSMutableArray *a = [[[NSFontManager sharedFontManager] availableFontFamilies] mutableCopy];
    @synchronized([NSFontManager class]) {
        for (NSString *n in g_registered) { NSString *fam = [[n componentsSeparatedByString:@"-"] firstObject]; if (![a containsObject:fam]) [a addObject:fam]; }
    }
    return (CFArrayRef)a;
}
CTFontCollectionRef CTFontCollectionCreateFromAvailableFonts(CFDictionaryRef o) { return (CTFontCollectionRef)CTFontManagerCopyAvailablePostScriptNames(); }
CFArrayRef CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionRef c) {
    NSMutableArray *a = [[NSMutableArray alloc] init];
    for (NSString *n in (NSArray *)c) [a addObject:[NSFontDescriptor fontDescriptorWithName:n size:0]];
    return (CFArrayRef)a;
}

/* font files: the host takes them (UI_FONT_ADD) and tells their PostScript names */
static NSArray *register_file(NSURL *u, NSError **e) {
    char names[4096] = {0};
    int64_t n = [u isFileURL] ? ui(UI_FONT_ADD, U([[u path] fileSystemRepresentation]), U(names), sizeof names, 0, 0) : -1;
    if (n <= 0) {
        if (e) *e = [NSError errorWithDomain:@"com.apple.CoreText.CTFontManagerErrorDomain" code:n == 0 ? 104 : 101 /* not registered / invalid file */
                                    userInfo:@{NSURLErrorKey: u ?: [NSNull null], NSLocalizedDescriptionKey: @"The file could not be registered."}];
        return nil;
    }
    NSArray *ps = [[NSString stringWithUTF8String:names] componentsSeparatedByString:@"\n"];
    @synchronized([NSFontManager class]) {
        if (!g_registered) g_registered = [[NSMutableArray alloc] init];
        for (NSString *p in ps) if ([p length] && ![g_registered containsObject:p]) [g_registered addObject:p];
    }
    return ps;
}
bool CTFontManagerRegisterFontsForURL(CFURLRef u, CTFontManagerScope scope, CFErrorRef *err) {
    NSError *e = nil;
    BOOL ok = register_file((NSURL *)u, &e) != nil;
    if (!ok && err) *err = (CFErrorRef)[e retain];
    return ok;
}
bool CTFontManagerUnregisterFontsForURL(CFURLRef u, CTFontManagerScope scope, CFErrorRef *err) { return true; }   /* ponytail: they stay */
bool CTFontManagerRegisterFontsForURLs(CFArrayRef urls, CTFontManagerScope scope, CFArrayRef *errs) {
    NSMutableArray *bad = [NSMutableArray array];
    for (NSURL *u in (NSArray *)urls) { NSError *e = nil; if (!register_file(u, &e) && e) [bad addObject:e]; }
    if (errs) *errs = [bad count] ? (CFArrayRef)[bad retain] : NULL;
    return ![bad count];
}
void CTFontManagerRegisterFontURLs(CFArrayRef urls, CTFontManagerScope scope, bool enabled, bool (^handler)(CFArrayRef, bool)) {
    CFArrayRef errs = NULL;
    CTFontManagerRegisterFontsForURLs(urls, scope, &errs);
    if (handler) handler(errs ? errs : (CFArrayRef)@[], true);
    if (errs) CFRelease(errs);
}
CFArrayRef CTFontManagerCreateFontDescriptorsFromURL(CFURLRef u) {
    NSArray *ps = register_file((NSURL *)u, NULL);
    if (!ps) return NULL;
    NSMutableArray *a = [[NSMutableArray alloc] init];
    for (NSString *n in ps) if ([n length]) [a addObject:[NSFontDescriptor fontDescriptorWithFontAttributes:@{NSFontNameAttribute: n, (id)kCTFontURLAttribute: (NSURL *)u}]];
    return (CFArrayRef)a;
}
/* an app's own fonts (Info.plist ATSApplicationFontsPath, a folder inside its Resources) are there when it starts */
__attribute__((constructor)) static void app_fonts(void) {
    NSString *rel = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ATSApplicationFontsPath"];
    if (![rel isKindOfClass:[NSString class]]) return;
    NSString *dir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:rel];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        NSString *ext = [[f pathExtension] lowercaseString];
        if ([@[@"ttf", @"otf", @"ttc", @"otc"] containsObject:ext]) register_file([NSURL fileURLWithPath:[dir stringByAppendingPathComponent:f]], NULL);
    }
}

/* ======================================================================= paragraph styles: an NSParagraphStyle */
CTParagraphStyleRef CTParagraphStyleCreate(const CTParagraphStyleSetting *s, size_t n) {
    NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
    for (size_t i = 0; s && i < n; i++) {
        const void *v = s[i].value;
        if (!v) continue;
        CGFloat f = s[i].valueSize == sizeof(CGFloat) ? *(const CGFloat *)v : 0;
        switch (s[i].spec) {
        case kCTParagraphStyleSpecifierAlignment: p.alignment = mw_alignment(*(const uint8_t *)v); break;
        case kCTParagraphStyleSpecifierLineBreakMode: p.lineBreakMode = (NSLineBreakMode)*(const uint8_t *)v; break;
        case kCTParagraphStyleSpecifierBaseWritingDirection: p.baseWritingDirection = *(const int8_t *)v; break;
        case kCTParagraphStyleSpecifierFirstLineHeadIndent: p.firstLineHeadIndent = f; break;
        case kCTParagraphStyleSpecifierHeadIndent: p.headIndent = f; break;
        case kCTParagraphStyleSpecifierTailIndent: p.tailIndent = f; break;
        case kCTParagraphStyleSpecifierDefaultTabInterval: p.defaultTabInterval = f; break;
        case kCTParagraphStyleSpecifierLineHeightMultiple: p.lineHeightMultiple = f; break;
        case kCTParagraphStyleSpecifierMaximumLineHeight: p.maximumLineHeight = f; break;
        case kCTParagraphStyleSpecifierMinimumLineHeight: p.minimumLineHeight = f; break;
        case kCTParagraphStyleSpecifierLineSpacing: case kCTParagraphStyleSpecifierMinimumLineSpacing:
        case kCTParagraphStyleSpecifierLineSpacingAdjustment: p.lineSpacing = f; break;
        case kCTParagraphStyleSpecifierParagraphSpacing: p.paragraphSpacing = f; break;
        case kCTParagraphStyleSpecifierParagraphSpacingBefore: p.paragraphSpacingBefore = f; break;
        default: break;   /* tab stops, maximum line spacing, line bounds options */
        }
    }
    return (CTParagraphStyleRef)p;
}
CTParagraphStyleRef CTParagraphStyleCreateCopy(CTParagraphStyleRef p) { return (CTParagraphStyleRef)[(id)p mutableCopy]; }
bool CTParagraphStyleGetValueForSpecifier(CTParagraphStyleRef ps, CTParagraphStyleSpecifier spec, size_t size, void *buf) {
    NSParagraphStyle *p = (NSParagraphStyle *)ps;
    CGFloat f = 0; uint8_t b = 0; BOOL isf = YES;
    switch (spec) {
    case kCTParagraphStyleSpecifierAlignment: b = mw_ct_alignment(p.alignment); isf = NO; break;
    case kCTParagraphStyleSpecifierLineBreakMode: b = (uint8_t)p.lineBreakMode; isf = NO; break;
    case kCTParagraphStyleSpecifierBaseWritingDirection: b = (uint8_t)(int8_t)p.baseWritingDirection; isf = NO; break;
    case kCTParagraphStyleSpecifierFirstLineHeadIndent: f = p.firstLineHeadIndent; break;
    case kCTParagraphStyleSpecifierHeadIndent: f = p.headIndent; break;
    case kCTParagraphStyleSpecifierTailIndent: f = p.tailIndent; break;
    case kCTParagraphStyleSpecifierDefaultTabInterval: f = p.defaultTabInterval; break;
    case kCTParagraphStyleSpecifierLineHeightMultiple: f = p.lineHeightMultiple; break;
    case kCTParagraphStyleSpecifierMaximumLineHeight: f = p.maximumLineHeight; break;
    case kCTParagraphStyleSpecifierMinimumLineHeight: f = p.minimumLineHeight; break;
    case kCTParagraphStyleSpecifierLineSpacing: case kCTParagraphStyleSpecifierMinimumLineSpacing:
    case kCTParagraphStyleSpecifierLineSpacingAdjustment: f = p.lineSpacing; break;
    case kCTParagraphStyleSpecifierParagraphSpacing: f = p.paragraphSpacing; break;
    case kCTParagraphStyleSpecifierParagraphSpacingBefore: f = p.paragraphSpacingBefore; break;
    default: return false;
    }
    if (!buf) return false;
    if (isf) { if (size < sizeof f) return false; memcpy(buf, &f, sizeof f); }
    else { if (size < 1) return false; memcpy(buf, &b, 1); }
    return true;
}
