/* table.m — scrolling (NSClipView / NSScrollView), NSScroller, and cell-based tables: NSTableView with its columns and
 * header, NSOutlineView (expandable rows of items) — drawn here, fed by the data source, with selection, clicks,
 * double-clicks and arrow keys. ponytail: view-based tables (rows of NSViews from -tableView:viewForTableColumn:row:) are
 * drawn from the views' text only; no column resizing or dragging, no in-place editing. */
#import "internal.h"
@interface NSView (MWNibDecode) - (void)_mwDecodeNib:(NSCoder *)c; @end

/* ======================================================================= scrolling */
@implementation NSClipView (MWScrolling)
- (NSRect)documentRect { NSView *d = self.documentView; return d ? NSUnionRect(d.frame, self.bounds) : self.bounds; }
- (NSRect)documentVisibleRect { NSView *d = self.documentView; return d ? [d convertRect:self.bounds fromView:self] : NSZeroRect; }
- (NSRect)constrainBoundsRect:(NSRect)r {
    NSRect d = self.documentView ? self.documentView.frame : NSZeroRect;
    r.origin.x = fmax(d.origin.x, fmin(r.origin.x, NSMaxX(d) - r.size.width));
    r.origin.y = fmax(d.origin.y, fmin(r.origin.y, NSMaxY(d) - r.size.height));
    if (d.size.width <= r.size.width) r.origin.x = d.origin.x;
    if (d.size.height <= r.size.height) r.origin.y = d.origin.y;
    return r;
}
- (void)scrollToPoint:(NSPoint)p {
    NSRect r = [self constrainBoundsRect:NSMakeRect(p.x, p.y, self.bounds.size.width, self.bounds.size.height)];
    if (NSEqualPoints(r.origin, self.bounds.origin)) return;
    [self setBoundsOrigin:r.origin];
    self.needsDisplay = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSViewBoundsDidChangeNotification object:self];
    NSScrollView *s = (NSScrollView *)self.superview;
    if ([s isKindOfClass:[NSScrollView class]]) [s reflectScrolledClipView:self];
}
- (void)scrollWheel:(NSEvent *)e {
    CGFloat dx = e.hasPreciseScrollingDeltas ? e.scrollingDeltaX : e.scrollingDeltaX * 16;
    CGFloat dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 16;
    NSRect d = self.documentView.frame, b = self.bounds;
    if (d.size.height <= b.size.height && d.size.width <= b.size.width) { [super scrollWheel:e]; return; }
    [self scrollToPoint:NSMakePoint(b.origin.x - dx, b.origin.y - dy)];
}
- (void)viewFrameChanged:(NSNotification *)n { [self scrollToPoint:self.bounds.origin]; }
@end
@implementation NSScrollView (MWScrolling)
- (void)reflectScrolledClipView:(NSClipView *)c {
    for (NSView *v in self.subviews) /* the table header follows the horizontal scroll */
        if (v != c && [v isKindOfClass:[NSClipView class]]) { NSRect b = v.bounds; b.origin.x = c.bounds.origin.x; [v setBoundsOrigin:b.origin]; v.needsDisplay = YES; }
}
- (NSRect)documentVisibleRect { return [self.contentView documentVisibleRect]; }
- (void)scrollWheel:(NSEvent *)e { [self.contentView scrollWheel:e]; }
- (void)tile {}
- (void)flashScrollers {}
- (NSScroller *)verticalScroller { return nil; } - (void)setVerticalScroller:(NSScroller *)s {}
- (NSScroller *)horizontalScroller { return nil; } - (void)setHorizontalScroller:(NSScroller *)s {}
@end
@implementation NSView (MWScrolling)
- (NSScrollView *)enclosingScrollView { for (NSView *v = self.superview; v; v = v.superview) if ([v isKindOfClass:[NSScrollView class]]) return (NSScrollView *)v; return nil; }
- (NSClipView *)_mwEnclosingClip { for (NSView *v = self.superview; v; v = v.superview) if ([v isKindOfClass:[NSClipView class]]) return (NSClipView *)v; return nil; }
- (void)scrollPoint:(NSPoint)p {
    NSClipView *c = [self _mwEnclosingClip];
    if (c) [c scrollToPoint:[self convertPoint:p toView:c.documentView ? c.documentView : c]];
}
- (BOOL)scrollRectToVisible:(NSRect)r {
    NSClipView *c = [self _mwEnclosingClip];
    if (!c || !c.documentView) return NO;
    NSRect t = [self convertRect:r toView:c.documentView], b = c.bounds;
    NSPoint o = b.origin;
    if (NSMinX(t) < NSMinX(b)) o.x = NSMinX(t); else if (NSMaxX(t) > NSMaxX(b)) o.x = NSMaxX(t) - b.size.width;
    if (NSMinY(t) < NSMinY(b)) o.y = NSMinY(t); else if (NSMaxY(t) > NSMaxY(b)) o.y = NSMaxY(t) - b.size.height;
    if (NSEqualPoints(o, b.origin)) return NO;
    [c scrollToPoint:o];
    return YES;
}
- (NSRect)_mwVisible {   /* the part of the view a clip view shows */
    NSClipView *c = [self _mwEnclosingClip];
    return c ? NSIntersectionRect(self.bounds, [self convertRect:c.bounds fromView:c]) : self.bounds;
}
@end

/* ======================================================================= NSScroller */
@implementation NSScroller { NSScrollerPart _hit; CGFloat _grab; }
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)s scrollerStyle:(NSScrollerStyle)st { return st == NSScrollerStyleOverlay ? 11 : 15; }
+ (CGFloat)scrollerWidth { return 15; }
+ (NSScrollerStyle)preferredScrollerStyle { return NSScrollerStyleLegacy; }
+ (BOOL)isCompatibleWithOverlayScrollers { return self == [NSScroller class]; }
- (NSRect)rectForPart:(NSScrollerPart)p {
    NSRect b = self.bounds; BOOL v = b.size.height >= b.size.width;
    if (p == NSScrollerKnobSlot || p == NSScrollerNoPart) return b;
    if (p != NSScrollerKnob) return NSZeroRect;
    CGFloat len = v ? b.size.height : b.size.width, k = fmax(16, len * fmin(1, fmax(0, _knobProportion))), pos = (len - k) * fmax(0, fmin(1, self.doubleValue));
    return v ? NSMakeRect(b.origin.x + 2, b.origin.y + pos, b.size.width - 4, k) : NSMakeRect(b.origin.x + pos, b.origin.y + 2, k, b.size.height - 4);
}
- (BOOL)isFlipped { return YES; }
- (NSScrollerPart)testPart:(NSPoint)p {
    NSPoint q = [self convertPoint:p fromView:nil];
    if (NSPointInRect(q, [self rectForPart:NSScrollerKnob])) return NSScrollerKnob;
    if (!NSPointInRect(q, self.bounds)) return NSScrollerNoPart;
    NSRect k = [self rectForPart:NSScrollerKnob]; BOOL v = self.bounds.size.height >= self.bounds.size.width;
    return (v ? q.y < NSMinY(k) : q.x < NSMinX(k)) ? NSScrollerDecrementPage : NSScrollerIncrementPage;
}
- (void)drawKnobSlotInRect:(NSRect)r highlight:(BOOL)h { [[NSColor colorWithWhite:0.5 alpha:0.12] set]; NSRectFill(r); }
- (void)drawKnob { mw_fill_round([self rectForPart:NSScrollerKnob], 4, [NSColor colorWithWhite:0.5 alpha:0.6]); }
- (void)drawRect:(NSRect)r { [self drawKnobSlotInRect:[self rectForPart:NSScrollerKnobSlot] highlight:NO]; if (_knobProportion < 1 && self.isEnabled) [self drawKnob]; }
- (void)_mwTrack:(NSEvent *)e {
    NSPoint q = [self convertPoint:e.locationInWindow fromView:nil];
    NSRect b = self.bounds, k = [self rectForPart:NSScrollerKnob]; BOOL v = b.size.height >= b.size.width;
    CGFloat len = v ? b.size.height : b.size.width, kl = v ? k.size.height : k.size.width;
    if (len - kl <= 0) return;
    CGFloat t = ((v ? q.y : q.x) - _grab) / (len - kl);
    self.doubleValue = fmax(0, fmin(1, t));
    _hit = NSScrollerKnob;
    self.needsDisplay = YES;
    [self sendAction:self.action to:self.target];
}
- (void)mouseDown:(NSEvent *)e {
    _hit = [self testPart:e.locationInWindow];
    NSPoint q = [self convertPoint:e.locationInWindow fromView:nil];
    NSRect k = [self rectForPart:NSScrollerKnob]; BOOL v = self.bounds.size.height >= self.bounds.size.width;
    if (_hit == NSScrollerKnob) { _grab = v ? q.y - k.origin.y : q.x - k.origin.x; return; }
    _grab = v ? k.size.height / 2 : k.size.width / 2;   /* a click in the track jumps there */
    [self sendAction:self.action to:self.target];
    [self _mwTrack:e];
}
- (void)mouseDragged:(NSEvent *)e { [self _mwTrack:e]; }
- (NSScrollerPart)hitPart { return _hit; }
- (void)setKnobProportion:(CGFloat)k { _knobProportion = k; self.needsDisplay = YES; }
- (void)setDoubleValue:(double)d { [super setDoubleValue:d]; self.needsDisplay = YES; }
- (NSScrollerKnobStyle)knobStyle { return 0; } - (void)setKnobStyle:(NSScrollerKnobStyle)s {}
- (NSScrollerStyle)scrollerStyle { return NSScrollerStyleLegacy; } - (void)setScrollerStyle:(NSScrollerStyle)s {}
- (NSUsableScrollerParts)usableParts { return NSAllScrollerParts; }
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    if ([c containsValueForKey:@"NSPercent"]) _knobProportion = [c decodeDoubleForKey:@"NSPercent"];
    if ([c containsValueForKey:@"NSCurValue"]) [super setDoubleValue:[c decodeDoubleForKey:@"NSCurValue"]];
}
@end

/* ======================================================================= NSTableColumn, header */
@implementation NSTableColumn
- (instancetype)initWithIdentifier:(NSUserInterfaceItemIdentifier)i {
    if ((self = [super init])) {
        _identifier = [i copy]; _width = 100; _minWidth = 10; _maxWidth = 100000; _editable = YES; _resizingMask = NSTableColumnAutoresizingMask;
        _headerCell = [[NSTableHeaderCell alloc] init];
        _dataCell = [[NSTextFieldCell alloc] init];
    }
    return self;
}
- (instancetype)init { return [self initWithIdentifier:@""]; }
- (instancetype)initWithCoder:(NSCoder *)c {
    if (!(self = [self initWithIdentifier:[c decodeObjectForKey:@"NSIdentifier"] ?: @""])) return nil;
    if ([c containsValueForKey:@"NSWidth"]) _width = [c decodeDoubleForKey:@"NSWidth"];
    if ([c containsValueForKey:@"NSMinWidth"]) _minWidth = [c decodeDoubleForKey:@"NSMinWidth"];
    if ([c containsValueForKey:@"NSMaxWidth"]) _maxWidth = [c decodeDoubleForKey:@"NSMaxWidth"];
    NSCell *h = [c decodeObjectForKey:@"NSHeaderCell"]; if (h) { [_headerCell release]; _headerCell = [h retain]; }
    NSCell *d = [c decodeObjectForKey:@"NSDataCell"]; if (d) { [_dataCell release]; _dataCell = [d retain]; }
    if ([c containsValueForKey:@"NSIsEditable"]) _editable = [c decodeBoolForKey:@"NSIsEditable"];
    _hidden = [c decodeBoolForKey:@"NSHidden"];
    _resizingMask = (NSTableColumnResizingOptions)[c decodeIntegerForKey:@"NSResizingMask"];
    _tableView = [c decodeObjectForKey:@"NSTableView"];
    return self;
}
- (void)dealloc { [_identifier release]; [_headerCell release]; [_dataCell release]; [_headerToolTip release]; [_sortDescriptorPrototype release]; [super dealloc]; }
- (NSString *)title { return [(NSCell *)_headerCell stringValue]; }
- (void)setTitle:(NSString *)t { [(NSCell *)_headerCell setStringValue:t ?: @""]; [_tableView.headerView setNeedsDisplay:YES]; }
- (void)setWidth:(CGFloat)w { _width = fmax(_minWidth, fmin(_maxWidth, w)); [_tableView tile]; }
- (void)_mwSetWidthRaw:(CGFloat)w { _width = w; }
- (void)setHidden:(BOOL)h { _hidden = h; [_tableView tile]; }
- (void)sizeToFit { [self setWidth:fmax(_minWidth, mw_text_size(self.title, nil).width + 12)]; }
- (id)dataCellForRow:(NSInteger)r { return _dataCell; }
@end
@implementation NSTableHeaderView
- (instancetype)initWithCoder:(NSCoder *)c {
    self = (NSTableHeaderView *)mw_nib_init_view(self, c);
    _tableView = [c decodeObjectForKey:@"NSTableView"];
    return self;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    NSTableView *t = _tableView;
    NSRect b = self.bounds;
    [[NSColor controlBackgroundColor] set]; NSRectFill(b);
    [[NSColor separatorColor] set]; NSRectFill(NSMakeRect(b.origin.x, NSMaxY(b) - 1, b.size.width, 1));
    NSInteger n = (NSInteger)[t.tableColumns count];
    for (NSInteger i = 0; i < n; i++) {
        NSTableColumn *col = t.tableColumns[(NSUInteger)i];
        if (col.isHidden) continue;
        NSRect cr = [self headerRectOfColumn:i];
        mw_draw_text_in(col.title, NSInsetRect(cr, 5, 0), [NSFont systemFontOfSize:11], [NSColor headerTextColor], [(NSCell *)col.headerCell alignment], NSLineBreakByTruncatingTail, NO, YES);
        [[NSColor separatorColor] set]; NSRectFill(NSMakeRect(NSMaxX(cr) - 1, cr.origin.y + 3, 1, cr.size.height - 6));
    }
}
- (NSRect)headerRectOfColumn:(NSInteger)c { NSRect r = [_tableView rectOfColumn:c]; return NSMakeRect(r.origin.x, 0, r.size.width, self.bounds.size.height); }
- (NSInteger)columnAtPoint:(NSPoint)p { return [_tableView columnAtPoint:NSMakePoint(p.x, 0)]; }
- (void)mouseDown:(NSEvent *)e {
    NSInteger c = [self columnAtPoint:[self convertPoint:e.locationInWindow fromView:nil]];
    if (c < 0) return;
    id d = _tableView.delegate;
    if ([d respondsToSelector:@selector(tableView:mouseDownInHeaderOfTableColumn:)]) [d tableView:_tableView mouseDownInHeaderOfTableColumn:_tableView.tableColumns[(NSUInteger)c]];
    if ([d respondsToSelector:@selector(tableView:didClickTableColumn:)]) [d tableView:_tableView didClickTableColumn:_tableView.tableColumns[(NSUInteger)c]];
}
@end
@interface NSTableColumn (MW) - (void)_mwSetWidthRaw:(CGFloat)w; @end
@interface _NSCornerView : NSView @end
@implementation _NSCornerView - (void)drawRect:(NSRect)r { [[NSColor controlBackgroundColor] set]; NSRectFill(self.bounds); } @end

/* ======================================================================= NSTableView */
@implementation NSTableRowView {
    NSColor *_backgroundColor;
}
- (instancetype)initWithFrame:(NSRect)r { if ((self = [super initWithFrame:r])) _selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular; return self; }
- (void)dealloc { [_backgroundColor release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (NSColor *)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(NSColor *)c { [c retain]; [_backgroundColor release]; _backgroundColor = c; self.needsDisplay = YES; }
- (void)setSelected:(BOOL)s {
    if (_selected == s) return;
    _selected = s;
    self.needsDisplay = YES;
    for (NSView *v in self.subviews) if ([v respondsToSelector:@selector(setBackgroundStyle:)]) [(id)v setBackgroundStyle:self.interiorBackgroundStyle];
}
- (NSBackgroundStyle)interiorBackgroundStyle { return _selected && _emphasized && _selectionHighlightStyle != NSTableViewSelectionHighlightStyleNone ? NSBackgroundStyleEmphasized : NSBackgroundStyleNormal; }
- (BOOL)isEmphasized { return _emphasized; }
- (NSInteger)numberOfColumns { return (NSInteger)[self.subviews count]; }
- (id)viewAtColumn:(NSInteger)c { NSTableView *t = (NSTableView *)self.superview; return [t isKindOfClass:[NSTableView class]] ? [t viewAtColumn:c row:[t rowForView:self] makeIfNecessary:NO] : nil; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; _emphasized = YES; }
- (void)drawBackgroundInRect:(NSRect)r {
    NSColor *c = _backgroundColor;
    if (!c && _groupRowStyle) c = [NSColor controlBackgroundColor];
    if (c) { [c set]; NSRectFill(r); }
}
- (void)drawSelectionInRect:(NSRect)r {
    if (_selectionHighlightStyle == NSTableViewSelectionHighlightStyleNone) return;
    mw_fill_round(NSInsetRect(self.bounds, 5, 0), 5, _emphasized ? [NSColor selectedContentBackgroundColor] : [NSColor unemphasizedSelectedContentBackgroundColor]);
}
- (void)drawSeparatorInRect:(NSRect)r { }
- (void)drawDraggingDestinationFeedbackInRect:(NSRect)r { }
- (void)drawRect:(NSRect)r {
    [self drawBackgroundInRect:self.bounds];
    if (_selected) [self drawSelectionInRect:self.bounds];
    [self drawSeparatorInRect:self.bounds];
}
@end

@implementation NSTableCellView {
    id _objectValue;
}
- (void)dealloc { [_objectValue release]; [_draggingImageComponents release]; [super dealloc]; }
- (id)objectValue { return _objectValue; }
- (void)setObjectValue:(id)v {
    [v retain]; [_objectValue release]; _objectValue = v;
    if (_textField && v && ![_textField infoForBinding:NSValueBinding]) _textField.objectValue = [v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSAttributedString class]] ? v : [v description];
}
- (void)setBackgroundStyle:(NSBackgroundStyle)b {
    _backgroundStyle = b;
    for (NSView *v in self.subviews) if ([v respondsToSelector:@selector(cell)] && [[(id)v cell] respondsToSelector:@selector(setBackgroundStyle:)]) [[(id)v cell] setBackgroundStyle:b];
}
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    _textField = [c decodeObjectForKey:@"NSTableCellViewTextField"] ?: [c decodeObjectForKey:@"textField"];
    _imageView = [c decodeObjectForKey:@"NSTableCellViewImageView"] ?: [c decodeObjectForKey:@"imageView"];
}
@end

@implementation NSTableView {
    NSMutableArray *_cols; NSMutableIndexSet *_sel; NSInteger _rows, _clickedRow, _clickedCol, _anchor; BOOL _rowsValid;
    NSMutableArray *_rowViews;                 /* view-based: one NSTableRowView per row (index = row) */
    NSMutableDictionary *_reuse, *_nibs;       /* identifier -> unused views / registered nib */
    BOOL _viewsDirty, _laying;
}
- (instancetype)initWithFrame:(NSRect)r {
    if ((self = [super initWithFrame:r])) {
        _cols = [[NSMutableArray alloc] init]; _sel = [[NSMutableIndexSet alloc] init];
        _rowHeight = 17; _intercellSpacing = NSMakeSize(3, 2); _allowsEmptySelection = YES; _allowsColumnSelection = NO;
        _clickedRow = _clickedCol = -1; _anchor = -1;
        _headerView = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, 23)]; _headerView.tableView = self;
    }
    return self;
}
- (void)_mwDecodeNib:(NSCoder *)c {
    [super _mwDecodeNib:c];
    for (NSTableColumn *col in [c decodeObjectForKey:@"NSTableColumns"]) if ([col isKindOfClass:[NSTableColumn class]]) [self addTableColumn:col];
    if ([c containsValueForKey:@"NSRowHeight"]) _rowHeight = [c decodeDoubleForKey:@"NSRowHeight"];
    if ([c containsValueForKey:@"NSIntercellSpacingWidth"]) _intercellSpacing = NSMakeSize([c decodeDoubleForKey:@"NSIntercellSpacingWidth"], [c decodeDoubleForKey:@"NSIntercellSpacingHeight"]);
    id hv = [c decodeObjectForKey:@"NSHeaderView"];
    if ([c containsValueForKey:@"NSHeaderView"]) { [_headerView release]; _headerView = [hv retain]; _headerView.tableView = self; }
    uint32_t f = (uint32_t)[c decodeInt64ForKey:@"NSTvFlags"];
    _allowsMultipleSelection = (f & 0x08000000u) != 0; _allowsEmptySelection = (f & 0x10000000u) != 0;
    _usesAlternatingRowBackgroundColors = (f & 0x00800000u) != 0;
    if ([c decodeObjectForKey:@"NSBackgroundColor"]) self.backgroundColor = [c decodeObjectForKey:@"NSBackgroundColor"];
    _gridStyleMask = (NSTableViewGridLineStyle)[c decodeIntegerForKey:@"NSGridStyleMask"];
    _columnAutoresizingStyle = (NSTableViewColumnAutoresizingStyle)[c decodeIntegerForKey:@"NSColumnAutoresizingStyle"];
}
- (void)dealloc { [_rowViews release]; [_reuse release]; [_nibs release]; [_cols release]; [_sel release]; [_headerView release]; [_cornerView release]; [_backgroundColor release]; [_gridColor release]; [_autosaveName release]; [_sortDescriptors release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (NSArray *)tableColumns { return [[_cols copy] autorelease]; }
- (NSInteger)numberOfColumns { return (NSInteger)[_cols count]; }
- (void)addTableColumn:(NSTableColumn *)c { if (!c || [_cols containsObject:c]) return; [_cols addObject:c]; c.tableView = self; [self tile]; }
- (void)removeTableColumn:(NSTableColumn *)c { [_cols removeObjectIdenticalTo:c]; [self tile]; }
- (void)moveColumn:(NSInteger)from toColumn:(NSInteger)to { id c = [[_cols[(NSUInteger)from] retain] autorelease]; [_cols removeObjectAtIndex:(NSUInteger)from]; [_cols insertObject:c atIndex:(NSUInteger)to]; [self tile]; }
- (NSInteger)columnWithIdentifier:(NSString *)i { for (NSUInteger k = 0; k < [_cols count]; k++) if ([[_cols[k] identifier] isEqualToString:i]) return (NSInteger)k; return -1; }
- (NSTableColumn *)tableColumnWithIdentifier:(NSString *)i { NSInteger k = [self columnWithIdentifier:i]; return k < 0 ? nil : _cols[(NSUInteger)k]; }
- (void)setDataSource:(id)d { _dataSource = d; _rowsValid = NO; [self tile]; }
- (void)setDelegate:(id)d {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_delegate) [nc removeObserver:_delegate name:NSTableViewSelectionDidChangeNotification object:self];
    _delegate = d;
    if ([d respondsToSelector:@selector(tableViewSelectionDidChange:)]) [nc addObserver:d selector:@selector(tableViewSelectionDidChange:) name:NSTableViewSelectionDidChangeNotification object:self];
}
- (NSInteger)_mwCountRows { return [_dataSource respondsToSelector:@selector(numberOfRowsInTableView:)] ? [_dataSource numberOfRowsInTableView:self] : 0; }
- (NSInteger)numberOfRows { if (!_rowsValid) { _rows = [self _mwCountRows]; _rowsValid = YES; } return _rows; }
- (CGFloat)_mwHeightOfRow:(NSInteger)r { return [_delegate respondsToSelector:@selector(tableView:heightOfRow:)] ? [_delegate tableView:self heightOfRow:r] : _rowHeight; }
- (BOOL)_mwVariableHeights { return [_delegate respondsToSelector:@selector(tableView:heightOfRow:)]; }
- (NSRect)rectOfRow:(NSInteger)r {
    CGFloat y = 0, sp = _intercellSpacing.height;
    if ([self _mwVariableHeights]) for (NSInteger i = 0; i < r; i++) y += [self _mwHeightOfRow:i] + sp;
    else y = r * (_rowHeight + sp);
    return NSMakeRect(0, y, self.bounds.size.width, [self _mwHeightOfRow:r] + sp);
}
- (NSRect)rectOfColumn:(NSInteger)c {
    CGFloat x = 0;
    for (NSInteger i = 0; i < c && i < (NSInteger)[_cols count]; i++) if (![_cols[(NSUInteger)i] isHidden]) x += [(NSTableColumn *)_cols[(NSUInteger)i] width] + _intercellSpacing.width;
    CGFloat w = c < (NSInteger)[_cols count] && ![_cols[(NSUInteger)c] isHidden] ? [(NSTableColumn *)_cols[(NSUInteger)c] width] + _intercellSpacing.width : 0;
    return NSMakeRect(x, 0, w, self.bounds.size.height);
}
- (NSRect)frameOfCellAtColumn:(NSInteger)c row:(NSInteger)r {
    NSRect cr = [self rectOfColumn:c], rr = [self rectOfRow:r];
    return NSMakeRect(cr.origin.x + _intercellSpacing.width / 2, rr.origin.y + _intercellSpacing.height / 2, cr.size.width - _intercellSpacing.width, rr.size.height - _intercellSpacing.height);
}
- (NSInteger)rowAtPoint:(NSPoint)p {
    NSInteger n = [self numberOfRows];
    if (p.y < 0) return -1;
    if (![self _mwVariableHeights]) { NSInteger r = (NSInteger)(p.y / (_rowHeight + _intercellSpacing.height)); return r < n ? r : -1; }
    CGFloat y = 0;
    for (NSInteger i = 0; i < n; i++) { y += [self _mwHeightOfRow:i] + _intercellSpacing.height; if (p.y < y) return i; }
    return -1;
}
- (NSInteger)columnAtPoint:(NSPoint)p {
    for (NSInteger i = 0; i < (NSInteger)[_cols count]; i++) { NSRect r = [self rectOfColumn:i]; if (r.size.width > 0 && p.x >= r.origin.x && p.x < NSMaxX(r)) return i; }
    return -1;
}
- (NSRange)rowsInRect:(NSRect)r {
    NSInteger a = [self rowAtPoint:NSMakePoint(0, fmax(0, r.origin.y))], b = [self rowAtPoint:NSMakePoint(0, NSMaxY(r) - 0.01)];
    if (a < 0) return NSMakeRange(0, 0);
    if (b < 0) b = [self numberOfRows] - 1;
    return NSMakeRange((NSUInteger)a, (NSUInteger)(b - a + 1));
}
- (NSIndexSet *)columnIndexesInRect:(NSRect)r {
    NSMutableIndexSet *s = [NSMutableIndexSet indexSet];
    for (NSInteger i = 0; i < (NSInteger)[_cols count]; i++) if (NSIntersectsRect([self rectOfColumn:i], r)) [s addIndex:(NSUInteger)i];
    return s;
}
/* size to the rows and columns (at least the clip view) */
- (void)tile {
    CGFloat w = 0, h = 0, sp = _intercellSpacing.height;
    for (NSTableColumn *c in _cols) if (!c.isHidden) w += c.width + _intercellSpacing.width;
    NSInteger n = [self numberOfRows];
    if ([self _mwVariableHeights]) for (NSInteger i = 0; i < n; i++) h += [self _mwHeightOfRow:i] + sp; else h = n * (_rowHeight + sp);
    NSClipView *clip = [self.superview isKindOfClass:[NSClipView class]] ? (NSClipView *)self.superview : nil;
    if (clip) { w = fmax(w, clip.bounds.size.width); h = fmax(h, clip.bounds.size.height); }
    else { w = fmax(w, self.frame.size.width); h = fmax(h, self.frame.size.height); }
    if ([_cols count] && clip && (_columnAutoresizingStyle == NSTableViewLastColumnOnlyAutoresizingStyle || _columnAutoresizingStyle == NSTableViewUniformColumnAutoresizingStyle)) {
        NSTableColumn *last = nil; for (NSTableColumn *c in _cols) if (!c.isHidden) last = c;
        CGFloat used = 0; for (NSTableColumn *c in _cols) if (!c.isHidden && c != last) used += c.width + _intercellSpacing.width;
        if (last) [last _mwSetWidthRaw:fmax(last.minWidth, fmin(last.maxWidth, clip.bounds.size.width - used - _intercellSpacing.width))];
    }
    if (!NSEqualSizes(self.frame.size, NSMakeSize(w, h))) [self setFrameSize:NSMakeSize(w, h)];
    NSRect hf = _headerView.frame; if (hf.size.width != w) [_headerView setFrameSize:NSMakeSize(w, hf.size.height ?: 23)];
    self.needsDisplay = YES; _headerView.needsDisplay = YES;
    [self _mwLayoutViews];
}
- (void)viewDidMoveToSuperview { [super viewDidMoveToSuperview]; [self tile]; }
- (void)resizeWithOldSuperviewSize:(NSSize)s { [super resizeWithOldSuperviewSize:s]; [self tile]; }
- (void)sizeLastColumnToFit { [self tile]; }
- (void)sizeToFit { [self tile]; }
- (void)reloadData {
    _rowsValid = NO; _viewsDirty = YES;
    NSInteger n = [self numberOfRows];
    [_sel removeIndexesInRange:NSMakeRange((NSUInteger)MAX(n, 0), NSNotFound - (NSUInteger)MAX(n, 0))];
    [self tile];
}
- (void)reloadDataForRowIndexes:(NSIndexSet *)r columnIndexes:(NSIndexSet *)c { if ([self _mwViewBased]) { _viewsDirty = YES; [self _mwLayoutViews]; } self.needsDisplay = YES; }
- (void)noteNumberOfRowsChanged { [self reloadData]; }
- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)r { [self tile]; }
- (void)beginUpdates {} - (void)endUpdates { [self reloadData]; }
- (void)insertRowsAtIndexes:(NSIndexSet *)i withAnimation:(NSTableViewAnimationOptions)a { [self reloadData]; }
- (void)removeRowsAtIndexes:(NSIndexSet *)i withAnimation:(NSTableViewAnimationOptions)a { [self reloadData]; }
- (void)moveRowAtIndex:(NSInteger)a toIndex:(NSInteger)b { [self reloadData]; }
/* selection */
- (NSIndexSet *)selectedRowIndexes { return [[_sel copy] autorelease]; }
- (NSInteger)selectedRow { return [_sel count] ? (NSInteger)[_sel lastIndex] : -1; }
- (NSInteger)numberOfSelectedRows { return (NSInteger)[_sel count]; }
- (BOOL)isRowSelected:(NSInteger)r { return r >= 0 && [_sel containsIndex:(NSUInteger)r]; }
- (NSIndexSet *)selectedColumnIndexes { return [NSIndexSet indexSet]; }
- (NSInteger)selectedColumn { return -1; }
- (void)selectRowIndexes:(NSIndexSet *)i byExtendingSelection:(BOOL)ext {
    NSMutableIndexSet *n = ext ? [[_sel mutableCopy] autorelease] : [NSMutableIndexSet indexSet];
    [n addIndexes:i];
    NSInteger rows = [self numberOfRows];
    [n removeIndexesInRange:NSMakeRange((NSUInteger)MAX(rows, 0), NSNotFound - (NSUInteger)MAX(rows, 0))];
    if ([n isEqualToIndexSet:_sel]) return;
    [_sel removeAllIndexes]; [_sel addIndexes:n];
    if ([n count]) _anchor = (NSInteger)[n lastIndex];
    self.needsDisplay = YES;
    [self _mwUpdateSelectedRowViews];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTableViewSelectionDidChangeNotification object:self];
}
- (void)selectRow:(NSInteger)r byExtendingSelection:(BOOL)e { [self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)r] byExtendingSelection:e]; }
- (void)deselectRow:(NSInteger)r { if (![self isRowSelected:r]) return; NSMutableIndexSet *n = [[_sel mutableCopy] autorelease]; [n removeIndex:(NSUInteger)r]; [self selectRowIndexes:n byExtendingSelection:NO]; }
- (void)deselectAll:(id)s { if ([_sel count]) [self selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO]; }
- (void)selectAll:(id)s { if (_allowsMultipleSelection) [self selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)[self numberOfRows])] byExtendingSelection:NO]; }
- (void)selectColumnIndexes:(NSIndexSet *)i byExtendingSelection:(BOOL)e {}
- (void)deselectColumn:(NSInteger)c {}
- (BOOL)_mwShouldSelect:(NSInteger)r { return ![_delegate respondsToSelector:@selector(tableView:shouldSelectRow:)] || [_delegate tableView:self shouldSelectRow:r]; }
- (NSInteger)clickedRow { return _clickedRow; }
- (NSInteger)clickedColumn { return _clickedCol; }
- (NSInteger)editedRow { return -1; } - (NSInteger)editedColumn { return -1; }
- (void)editColumn:(NSInteger)c row:(NSInteger)r withEvent:(NSEvent *)e select:(BOOL)s {}
- (void)scrollRowToVisible:(NSInteger)r { if (r >= 0 && r < [self numberOfRows]) [self scrollRectToVisible:[self rectOfRow:r]]; }
- (void)scrollColumnToVisible:(NSInteger)c { [self scrollRectToVisible:[self rectOfColumn:c]]; }
/* cell values */
- (id)_mwValueAtColumn:(NSTableColumn *)col row:(NSInteger)r {
    if ([_dataSource respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)]) return [_dataSource tableView:self objectValueForTableColumn:col row:r];
    if ([_delegate respondsToSelector:@selector(tableView:viewForTableColumn:row:)]) {
        NSView *v = [_delegate tableView:self viewForTableColumn:col row:r];
        if ([v respondsToSelector:@selector(textField)]) return [(NSControl *)[(id)v textField] stringValue];
        if ([v isKindOfClass:[NSControl class]]) return [(NSControl *)v stringValue];
    }
    return nil;
}
- (NSCell *)preparedCellAtColumn:(NSInteger)c row:(NSInteger)r {
    NSTableColumn *col = _cols[(NSUInteger)c];
    static NSTextFieldCell *plain;
    NSCell *cell = [col dataCellForRow:r];   /* one cell per column, refilled per row, as AppKit does */
    if (!cell) cell = plain ?: (plain = [[NSTextFieldCell alloc] init]);
    cell.objectValue = [self _mwValueAtColumn:col row:r];
    if ([_delegate respondsToSelector:@selector(tableView:willDisplayCell:forTableColumn:row:)]) [_delegate tableView:self willDisplayCell:cell forTableColumn:col row:r];
    return cell;
}
- (NSString *)_mwText:(id)v cell:(NSCell *)cell {
    if (!v) return nil;
    id f = [cell respondsToSelector:@selector(formatter)] ? [(id)cell formatter] : nil;
    if (f && [f respondsToSelector:@selector(stringForObjectValue:)]) return [f stringForObjectValue:v];
    if ([v isKindOfClass:[NSAttributedString class]]) return [v string];
    return [v isKindOfClass:[NSString class]] ? v : [v description];
}
- (void)drawBackgroundInClipRect:(NSRect)clip {
    NSColor *bg = _backgroundColor ?: [NSColor controlBackgroundColor];
    [bg set]; NSRectFill(clip);
    if (!_usesAlternatingRowBackgroundColors) return;
    NSRange rows = [self rowsInRect:clip];
    for (NSUInteger r = rows.location; r < NSMaxRange(rows); r++)
        if (r % 2) { [[NSColor colorWithWhite:0.5 alpha:0.06] set]; NSRectFill([self rectOfRow:(NSInteger)r]); }
}
- (void)highlightSelectionInClipRect:(NSRect)clip {
    BOOL key = self.window.isKeyWindow && self.window.firstResponder == self;
    NSColor *c = key ? [NSColor selectedContentBackgroundColor] : [NSColor unemphasizedSelectedContentBackgroundColor];
    [_sel enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) { NSRect rr = [self rectOfRow:(NSInteger)r]; if (NSIntersectsRect(rr, clip)) { [c set]; NSRectFill(rr); } }];
}
- (void)drawGridInClipRect:(NSRect)clip {
    if (!_gridStyleMask) return;
    [_gridColor ?: [NSColor gridColor] set];
    if (_gridStyleMask & NSTableViewSolidVerticalGridLineMask)
        for (NSInteger i = 0; i < (NSInteger)[_cols count]; i++) { NSRect r = [self rectOfColumn:i]; NSRectFill(NSMakeRect(NSMaxX(r) - 1, clip.origin.y, 1, clip.size.height)); }
    if (_gridStyleMask & NSTableViewSolidHorizontalGridLineMask) {
        NSRange rows = [self rowsInRect:clip];
        for (NSUInteger r = rows.location; r < NSMaxRange(rows); r++) { NSRect rr = [self rectOfRow:(NSInteger)r]; NSRectFill(NSMakeRect(clip.origin.x, NSMaxY(rr) - 1, clip.size.width, 1)); }
    }
}
- (CGFloat)_mwIndentForRow:(NSInteger)r column:(NSInteger)c { return 0; }
- (void)drawRow:(NSInteger)r clipRect:(NSRect)clip {
    BOOL sel = [self isRowSelected:r] && self.window.isKeyWindow;
    for (NSInteger c = 0; c < (NSInteger)[_cols count]; c++) {
        NSTableColumn *col = _cols[(NSUInteger)c];
        if (col.isHidden) continue;
        NSRect fr = [self frameOfCellAtColumn:c row:r];
        if (!NSIntersectsRect(fr, clip)) continue;
        CGFloat ind = [self _mwIndentForRow:r column:c];
        fr.origin.x += ind; fr.size.width -= ind;
        NSCell *cell = [self preparedCellAtColumn:c row:r];
        id v = cell.objectValue;
        if ([v isKindOfClass:[NSImage class]]) { mw_draw_image(v, NSInsetRect(fr, 1, 1), nil, 1); continue; }
        if ([cell isKindOfClass:NSClassFromString(@"NSButtonCell")]) { /* checkboxes */
            NSRect box = NSMakeRect(fr.origin.x + 2, NSMidY(fr) - 6, 12, 12);
            mw_stroke_round(box, 3, 1, [NSColor secondaryLabelColor]);
            if ([v boolValue]) mw_fill_round(NSInsetRect(box, 3, 3), 1.5, [NSColor controlAccentColor]);
            continue;
        }
        NSString *s = [self _mwText:v cell:cell];
        NSColor *tc = sel ? [NSColor alternateSelectedControlTextColor] : ([cell respondsToSelector:@selector(textColor)] && [(id)cell textColor] ? [(id)cell textColor] : [NSColor controlTextColor]);
        mw_draw_text_in(s, NSInsetRect(fr, 2, 0), cell.font ?: [NSFont systemFontOfSize:13], tc, cell.alignment, NSLineBreakByTruncatingTail, NO, YES);
    }
}
- (void)drawRect:(NSRect)dirty {
    NSRect clip = [self _mwVisible];
    [self drawBackgroundInClipRect:clip];
    if ([self _mwViewBased]) { [self drawGridInClipRect:clip]; return; }   /* the row and cell views draw the rest */
    [self highlightSelectionInClipRect:clip];
    [self drawGridInClipRect:clip];
    NSRange rows = [self rowsInRect:clip];
    for (NSUInteger r = rows.location; r < NSMaxRange(rows); r++) [self drawRow:(NSInteger)r clipRect:clip];
}
/* mouse and keys */
- (BOOL)_mwClickExtra:(NSPoint)p row:(NSInteger)r { return NO; }   /* outline: the disclosure triangle */
- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    NSInteger r = [self rowAtPoint:p];
    _clickedRow = r; _clickedCol = [self columnAtPoint:p];
    [self.window makeFirstResponder:self];
    if ([self _mwClickExtra:p row:r]) return;
    if (r < 0) { if (_allowsEmptySelection) [self deselectAll:nil]; }
    else if ([self _mwShouldSelect:r]) {
        NSEventModifierFlags m = e.modifierFlags;
        if (_allowsMultipleSelection && (m & NSEventModifierFlagCommand)) { if ([self isRowSelected:r]) { if ([_sel count] > 1 || _allowsEmptySelection) [self deselectRow:r]; } else [self selectRow:r byExtendingSelection:YES]; }
        else if (_allowsMultipleSelection && (m & NSEventModifierFlagShift) && _anchor >= 0) {
            NSInteger a = MIN(_anchor, r), b = MAX(_anchor, r), keep = _anchor;
            [self selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a + 1))] byExtendingSelection:NO];
            _anchor = keep;
        } else [self selectRow:r byExtendingSelection:NO];
    }
    if (e.clickCount >= 2 && _doubleAction) { if (r >= 0 || YES) [self sendAction:_doubleAction to:self.target]; }
    else if (self.action) [self sendAction:self.action to:self.target];
    _clickedRow = _clickedCol = -1;
}
- (void)_mwMoveSelection:(NSInteger)d extend:(BOOL)ext {
    NSInteger n = [self numberOfRows]; if (!n) return;
    NSInteger r = [self selectedRow];
    r = r < 0 ? (d > 0 ? 0 : n - 1) : MAX(0, MIN(n - 1, r + d));
    while (r >= 0 && r < n && ![self _mwShouldSelect:r]) r += d > 0 ? 1 : -1;
    if (r < 0 || r >= n) return;
    [self selectRow:r byExtendingSelection:ext && _allowsMultipleSelection];
    [self scrollRowToVisible:r];
}
- (void)moveUp:(id)s { [self _mwMoveSelection:-1 extend:NO]; }
- (void)moveDown:(id)s { [self _mwMoveSelection:1 extend:NO]; }
- (void)moveUpAndModifySelection:(id)s { [self _mwMoveSelection:-1 extend:YES]; }
- (void)moveDownAndModifySelection:(id)s { [self _mwMoveSelection:1 extend:YES]; }
- (void)scrollToBeginningOfDocument:(id)s { [self scrollRowToVisible:0]; }
- (void)scrollToEndOfDocument:(id)s { [self scrollRowToVisible:[self numberOfRows] - 1]; }
- (void)keyDown:(NSEvent *)e {
    unichar k = [e.charactersIgnoringModifiers length] ? [e.charactersIgnoringModifiers characterAtIndex:0] : 0;
    BOOL shift = (e.modifierFlags & NSEventModifierFlagShift) != 0;
    if (k == NSUpArrowFunctionKey) [self _mwMoveSelection:-1 extend:shift];
    else if (k == NSDownArrowFunctionKey) [self _mwMoveSelection:1 extend:shift];
    else if ((k == '\r' || k == 3) && _doubleAction) [self sendAction:_doubleAction to:self.target];
    else [super keyDown:e];
}
- (BOOL)becomeFirstResponder { self.needsDisplay = YES; return YES; }
- (BOOL)resignFirstResponder { self.needsDisplay = YES; return YES; }
/* ---- view-based tables: the delegate gives a view per cell (and maybe the row views); they are subviews of the table.
   ponytail: every row gets its views at once (no recycling while scrolling); fine for hundreds of rows, not for 100k. */
static char kColumn;
- (BOOL)_mwViewBased { return [_delegate respondsToSelector:@selector(tableView:viewForTableColumn:row:)] || [_delegate respondsToSelector:@selector(tableView:rowViewForRow:)]; }
- (NSView *)_mwViewForColumn:(NSTableColumn *)c row:(NSInteger)r {
    return [_delegate respondsToSelector:@selector(tableView:viewForTableColumn:row:)] ? [_delegate tableView:self viewForTableColumn:c row:r] : nil;
}
- (NSTableRowView *)_mwRowViewForRow:(NSInteger)r { return [_delegate respondsToSelector:@selector(tableView:rowViewForRow:)] ? [_delegate tableView:self rowViewForRow:r] : nil; }
- (BOOL)_mwIsGroupRow:(NSInteger)r { return [_delegate respondsToSelector:@selector(tableView:isGroupRow:)] && [_delegate tableView:self isGroupRow:r]; }
- (void)_mwRecycle:(NSView *)v {
    [[v retain] autorelease];
    [v removeFromSuperview];
    if (!v.identifier) return;
    if (!_reuse) _reuse = [[NSMutableDictionary alloc] init];
    NSMutableArray *pool = _reuse[v.identifier];
    if (!pool) _reuse[v.identifier] = pool = [NSMutableArray array];
    [pool addObject:v];
}
- (void)_mwLayoutViews {
    if (_laying || ![self _mwViewBased]) return;
    _laying = YES;
    if (!_rowViews) _rowViews = [[NSMutableArray alloc] init];
    NSInteger n = [self numberOfRows];
    if (_viewsDirty || (NSInteger)[_rowViews count] > n) {
        for (NSInteger r = (NSInteger)[_rowViews count] - 1; r >= 0; r--) {
            NSTableRowView *rv = _rowViews[(NSUInteger)r];
            if ([_delegate respondsToSelector:@selector(tableView:didRemoveRowView:forRow:)]) [_delegate tableView:self didRemoveRowView:rv forRow:r];
            for (NSView *v in [[rv.subviews copy] autorelease]) [self _mwRecycle:v];
            [self _mwRecycle:rv];
        }
        [_rowViews removeAllObjects];
        _viewsDirty = NO;
    }
    CGFloat sp = _intercellSpacing.height;
    for (NSInteger r = 0; r < n; r++) {
        NSTableRowView *rv;
        BOOL group = [self _mwIsGroupRow:r];
        if (r < (NSInteger)[_rowViews count]) rv = _rowViews[(NSUInteger)r];
        else {
            rv = [self _mwRowViewForRow:r];
            if (!rv) rv = [[[NSTableRowView alloc] initWithFrame:NSZeroRect] autorelease];
            rv.groupRowStyle = group;
            [_rowViews addObject:rv];
            [rv setFrame:[self rectOfRow:r]];
            [self addSubview:rv];
            for (NSInteger c = group ? -1 : 0; c < (group ? 0 : (NSInteger)[_cols count]); c++) {
                NSTableColumn *col = c < 0 ? nil : _cols[(NSUInteger)c];
                if (col.isHidden) continue;
                NSView *v = [self _mwViewForColumn:col row:r];
                if (!v) continue;
                objc_setAssociatedObject(v, &kColumn, @(c), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if ([v isKindOfClass:[NSTableCellView class]] && [_dataSource respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)])
                    [(NSTableCellView *)v setObjectValue:[_dataSource tableView:self objectValueForTableColumn:col row:r]];
                [rv addSubview:v];
            }
            if ([_delegate respondsToSelector:@selector(tableView:didAddRowView:forRow:)]) [_delegate tableView:self didAddRowView:rv forRow:r];
        }
        NSRect rr = [self rectOfRow:r];
        if (!NSEqualRects(rv.frame, rr)) [rv setFrame:rr];
        for (NSView *v in rv.subviews) {
            NSNumber *c = objc_getAssociatedObject(v, &kColumn);
            if (!c) continue;
            NSRect cr = [c integerValue] < 0 ? NSMakeRect(0, 0, rr.size.width, rr.size.height) : [self rectOfColumn:[c integerValue]];
            CGFloat ind = [c integerValue] < 0 ? 0 : [self _mwIndentForRow:r column:[c integerValue]];
            NSRect f = NSMakeRect(cr.origin.x + ind + _intercellSpacing.width / 2, sp / 2, cr.size.width - ind - _intercellSpacing.width, rr.size.height - sp);
            if ([c integerValue] < 0) f = NSMakeRect(0, 0, rr.size.width, rr.size.height);
            if (!NSEqualRects(v.frame, f)) [v setFrame:f];
        }
    }
    [self _mwUpdateSelectedRowViews];
    _laying = NO;
}
- (void)_mwUpdateSelectedRowViews {
    for (NSUInteger r = 0; r < [_rowViews count]; r++) {
        NSTableRowView *rv = _rowViews[r];
        BOOL s = [_sel containsIndex:r];
        if (rv.isSelected != s) rv.selected = s;
        rv.previousRowSelected = r > 0 && [_sel containsIndex:r - 1];
        rv.nextRowSelected = [_sel containsIndex:r + 1];
    }
}
- (id)makeViewWithIdentifier:(NSString *)i owner:(id)o {
    if (!i) return nil;
    NSMutableArray *pool = _reuse[i];
    if ([pool count]) { id v = [[[pool lastObject] retain] autorelease]; [pool removeLastObject]; return v; }
    NSNib *nib = _nibs[i];
    NSArray *top = nil;
    if (nib && [nib instantiateWithOwner:o topLevelObjects:&top])
        for (id v in top) if ([v isKindOfClass:[NSView class]]) { if (![v identifier]) [v setIdentifier:i]; return v; }
    return nil;
}
- (void)registerNib:(NSNib *)n forIdentifier:(NSString *)i {
    if (!i) return;
    if (!_nibs) _nibs = [[NSMutableDictionary alloc] init];
    if (n) _nibs[i] = n; else [_nibs removeObjectForKey:i];
}
- (NSDictionary *)registeredNibsByIdentifier { return [[_nibs copy] autorelease]; }
- (id)rowViewAtRow:(NSInteger)r makeIfNecessary:(BOOL)m {
    if (m && ![_rowViews count]) [self _mwLayoutViews];
    return r >= 0 && r < (NSInteger)[_rowViews count] ? _rowViews[(NSUInteger)r] : nil;
}
- (id)viewAtColumn:(NSInteger)c row:(NSInteger)r makeIfNecessary:(BOOL)m {
    NSTableRowView *rv = [self rowViewAtRow:r makeIfNecessary:m];
    for (NSView *v in rv.subviews) { NSNumber *k = objc_getAssociatedObject(v, &kColumn); if (k && ([k integerValue] == c || [k integerValue] < 0)) return v; }
    return nil;
}
- (NSInteger)rowForView:(NSView *)v {
    for (; v && v != self; v = v.superview) { NSUInteger i = [_rowViews indexOfObjectIdenticalTo:v]; if (i != NSNotFound) return (NSInteger)i; }
    return -1;
}
- (NSInteger)columnForView:(NSView *)v {
    for (; v && v != self; v = v.superview) { NSNumber *k = objc_getAssociatedObject(v, &kColumn); if (k) return [k integerValue]; }
    return -1;
}
- (void)enumerateAvailableRowViewsUsingBlock:(void (^)(id, NSInteger))b {
    NSArray *a = [[_rowViews copy] autorelease];
    for (NSUInteger r = 0; r < [a count]; r++) b(a[r], (NSInteger)r);
}
- (void)hideRowsAtIndexes:(NSIndexSet *)i withAnimation:(NSTableViewAnimationOptions)a {}
- (void)unhideRowsAtIndexes:(NSIndexSet *)i withAnimation:(NSTableViewAnimationOptions)a {}
- (void)setIndicatorImage:(NSImage *)i inTableColumn:(NSTableColumn *)c {}
- (NSImage *)indicatorImageInTableColumn:(NSTableColumn *)c { return nil; }
- (void)setDraggingSourceOperationMask:(NSDragOperation)m forLocal:(BOOL)l {}
- (void)setDropRow:(NSInteger)r dropOperation:(NSTableViewDropOperation)o {}
- (void)setHeaderView:(NSTableHeaderView *)h { [h retain]; [_headerView release]; _headerView = h; h.tableView = self; }
@end

/* ======================================================================= NSOutlineView */
@implementation NSOutlineView { NSMutableArray *_items, *_levels; NSMutableSet *_expanded; NSMapTable *_parents; }
- (instancetype)initWithFrame:(NSRect)r {
    if ((self = [super initWithFrame:r])) { _indentationPerLevel = 16; _autoresizesOutlineColumn = YES; [self _mwInit]; }
    return self;
}
- (void)_mwInit {
    if (_items) return;
    _items = [[NSMutableArray alloc] init]; _levels = [[NSMutableArray alloc] init];
    _expanded = [[NSMutableSet alloc] init];
    _parents = [[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsObjectPointerPersonality] retain];
}
- (void)_mwDecodeNib:(NSCoder *)c {
    [self _mwInit];
    [super _mwDecodeNib:c];
    if ([c containsValueForKey:@"NSOutlineViewIndentationPerLevelKey"]) _indentationPerLevel = [c decodeDoubleForKey:@"NSOutlineViewIndentationPerLevelKey"];
    _outlineTableColumn = [c decodeObjectForKey:@"NSOutlineViewOutlineTableColumnKey"];
}
- (void)dealloc { [_items release]; [_levels release]; [_expanded release]; [_parents release]; [super dealloc]; }
static id key_of(id item) { return item ? [NSValue valueWithPointer:item] : [NSNull null]; }
- (NSInteger)_mwChildren:(id)item {
    id ds = self.dataSource;
    return [ds respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)] ? [ds outlineView:self numberOfChildrenOfItem:item] : 0;
}
- (void)_mwFlatten:(id)item level:(NSInteger)l {
    NSInteger n = [self _mwChildren:item];
    for (NSInteger i = 0; i < n; i++) {
        id c = [self.dataSource outlineView:self child:i ofItem:item];
        if (!c) continue;
        [_items addObject:c]; [_levels addObject:@(l)];
        [_parents setObject:item forKey:c];
        if ([_expanded containsObject:key_of(c)] && [self isExpandable:c]) [self _mwFlatten:c level:l + 1];
    }
}
- (void)_mwRebuild { [self _mwInit]; [_items removeAllObjects]; [_levels removeAllObjects]; [_parents removeAllObjects]; [self _mwFlatten:nil level:0]; }
- (NSInteger)_mwCountRows { [self _mwRebuild]; return (NSInteger)[_items count]; }
- (id)itemAtRow:(NSInteger)r { [self numberOfRows]; return r >= 0 && r < (NSInteger)[_items count] ? _items[(NSUInteger)r] : nil; }
- (NSInteger)rowForItem:(id)item { [self numberOfRows]; NSUInteger i = [_items indexOfObjectIdenticalTo:item]; return i == NSNotFound ? -1 : (NSInteger)i; }
- (NSInteger)levelForRow:(NSInteger)r { [self numberOfRows]; return r >= 0 && r < (NSInteger)[_levels count] ? [_levels[(NSUInteger)r] integerValue] : -1; }
- (NSInteger)levelForItem:(id)item { return [self levelForRow:[self rowForItem:item]]; }
- (id)parentForItem:(id)item { [self numberOfRows]; return [_parents objectForKey:item]; }
- (NSInteger)childIndexForItem:(id)item {
    id p = [self parentForItem:item]; NSInteger n = [self _mwChildren:p];
    for (NSInteger i = 0; i < n; i++) if ([self.dataSource outlineView:self child:i ofItem:p] == item) return i;
    return -1;
}
- (NSInteger)numberOfChildrenOfItem:(id)item { return [self _mwChildren:item]; }
- (id)child:(NSInteger)i ofItem:(id)item { return [self.dataSource outlineView:self child:i ofItem:item]; }
- (BOOL)isExpandable:(id)item { id ds = self.dataSource; return [ds respondsToSelector:@selector(outlineView:isItemExpandable:)] && [ds outlineView:self isItemExpandable:item]; }
- (BOOL)isItemExpanded:(id)item { return item == nil || [_expanded containsObject:key_of(item)]; }
- (void)expandItem:(id)item expandChildren:(BOOL)all {
    if (!item || ![self isExpandable:item]) return;
    id d = self.delegate;
    if ([d respondsToSelector:@selector(outlineView:shouldExpandItem:)] && ![d outlineView:self shouldExpandItem:item]) return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:NSOutlineViewItemWillExpandNotification object:self userInfo:@{@"NSObject": item}];
    [_expanded addObject:key_of(item)];
    if (all) for (NSInteger i = 0, n = [self _mwChildren:item]; i < n; i++) [self expandItem:[self.dataSource outlineView:self child:i ofItem:item] expandChildren:YES];
    [self reloadData];
    [nc postNotificationName:NSOutlineViewItemDidExpandNotification object:self userInfo:@{@"NSObject": item}];
}
- (void)expandItem:(id)item { [self expandItem:item expandChildren:NO]; }
- (void)collapseItem:(id)item collapseChildren:(BOOL)all {
    if (!item || ![_expanded containsObject:key_of(item)]) return;
    id d = self.delegate;
    if ([d respondsToSelector:@selector(outlineView:shouldCollapseItem:)] && ![d outlineView:self shouldCollapseItem:item]) return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:NSOutlineViewItemWillCollapseNotification object:self userInfo:@{@"NSObject": item}];
    [_expanded removeObject:key_of(item)];
    [self reloadData];
    [nc postNotificationName:NSOutlineViewItemDidCollapseNotification object:self userInfo:@{@"NSObject": item}];
}
- (void)collapseItem:(id)item { [self collapseItem:item collapseChildren:NO]; }
- (void)reloadItem:(id)item { [self reloadData]; }
- (void)reloadItem:(id)item reloadChildren:(BOOL)c { [self reloadData]; }
- (void)insertItemsAtIndexes:(NSIndexSet *)i inParent:(id)p withAnimation:(NSTableViewAnimationOptions)a { [self reloadData]; }
- (void)removeItemsAtIndexes:(NSIndexSet *)i inParent:(id)p withAnimation:(NSTableViewAnimationOptions)a { [self reloadData]; }
- (NSRect)frameOfOutlineCellAtRow:(NSInteger)r {
    NSInteger oc = _outlineTableColumn ? [[self tableColumns] indexOfObjectIdenticalTo:_outlineTableColumn] : 0;
    NSRect f = [self frameOfCellAtColumn:oc row:r];
    return NSMakeRect(f.origin.x + _indentationPerLevel * [self levelForRow:r], f.origin.y, 14, f.size.height);
}
- (CGFloat)_mwIndentForRow:(NSInteger)r column:(NSInteger)c {
    NSInteger oc = _outlineTableColumn ? (NSInteger)[[self tableColumns] indexOfObjectIdenticalTo:_outlineTableColumn] : 0;
    return c == oc ? _indentationPerLevel * [self levelForRow:r] + 16 : 0;
}
- (id)_mwValueAtColumn:(NSTableColumn *)col row:(NSInteger)r {
    id ds = self.dataSource;
    return [ds respondsToSelector:@selector(outlineView:objectValueForTableColumn:byItem:)] ? [ds outlineView:self objectValueForTableColumn:col byItem:[self itemAtRow:r]] : nil;
}
- (NSCell *)preparedCellAtColumn:(NSInteger)c row:(NSInteger)r {
    NSCell *cell = [super preparedCellAtColumn:c row:r];
    id d = self.delegate;
    if ([d respondsToSelector:@selector(outlineView:willDisplayCell:forTableColumn:item:)]) [d outlineView:self willDisplayCell:cell forTableColumn:self.tableColumns[(NSUInteger)c] item:[self itemAtRow:r]];
    return cell;
}
- (BOOL)_mwShouldSelect:(NSInteger)r { id d = self.delegate; return ![d respondsToSelector:@selector(outlineView:shouldSelectItem:)] || [d outlineView:self shouldSelectItem:[self itemAtRow:r]]; }
- (void)drawRow:(NSInteger)r clipRect:(NSRect)clip {
    [super drawRow:r clipRect:clip];
    id item = [self itemAtRow:r];
    if (![self isExpandable:item]) return;
    NSRect t = [self frameOfOutlineCellAtRow:r];
    CGFloat cx = NSMidX(t), cy = NSMidY(t);
    NSBezierPath *p = [NSBezierPath bezierPath];
    if ([self isItemExpanded:item]) { [p moveToPoint:NSMakePoint(cx - 4, cy - 2)]; [p lineToPoint:NSMakePoint(cx + 4, cy - 2)]; [p lineToPoint:NSMakePoint(cx, cy + 3)]; }
    else { [p moveToPoint:NSMakePoint(cx - 2, cy - 4)]; [p lineToPoint:NSMakePoint(cx + 3, cy)]; [p lineToPoint:NSMakePoint(cx - 2, cy + 4)]; }
    [p closePath];
    [[NSColor secondaryLabelColor] set]; [p fill];
}
- (BOOL)_mwClickExtra:(NSPoint)p row:(NSInteger)r {
    id item = [self itemAtRow:r];
    if (!item || ![self isExpandable:item] || !NSPointInRect(p, NSInsetRect([self frameOfOutlineCellAtRow:r], -2, 0))) return NO;
    if ([self isItemExpanded:item]) [self collapseItem:item]; else [self expandItem:item];
    return YES;
}
- (void)moveRight:(id)s { id i = [self itemAtRow:[self selectedRow]]; if (i) [self expandItem:i]; }
- (void)moveLeft:(id)s { id i = [self itemAtRow:[self selectedRow]]; if (i) [self collapseItem:i]; }
- (void)keyDown:(NSEvent *)e {
    unichar k = [e.charactersIgnoringModifiers length] ? [e.charactersIgnoringModifiers characterAtIndex:0] : 0;
    if (k == NSRightArrowFunctionKey) [self moveRight:nil]; else if (k == NSLeftArrowFunctionKey) [self moveLeft:nil]; else [super keyDown:e];
}
- (void)setDropItem:(id)i dropChildIndex:(NSInteger)c {}
@end

NSNotificationName const NSTableViewSelectionDidChangeNotification = @"NSTableViewSelectionDidChangeNotification",
    NSTableViewSelectionIsChangingNotification = @"NSTableViewSelectionIsChangingNotification",
    NSTableViewColumnDidMoveNotification = @"NSTableViewColumnDidMoveNotification", NSTableViewColumnDidResizeNotification = @"NSTableViewColumnDidResizeNotification",
    NSOutlineViewItemWillExpandNotification = @"NSOutlineViewItemWillExpandNotification", NSOutlineViewItemDidExpandNotification = @"NSOutlineViewItemDidExpandNotification",
    NSOutlineViewItemWillCollapseNotification = @"NSOutlineViewItemWillCollapseNotification", NSOutlineViewItemDidCollapseNotification = @"NSOutlineViewItemDidCollapseNotification",
    NSOutlineViewSelectionDidChangeNotification = @"NSOutlineViewSelectionDidChangeNotification";
