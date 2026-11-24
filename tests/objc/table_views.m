/* table_views.m: view-based NSTableView (cell views from the delegate, row views, group rows, reuse, selection) */
#import <AppKit/AppKit.h>
static int fails;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s (line %d)\n", #c, __LINE__); fails++; } } while (0)
@interface Row : NSTableRowView @end
@implementation Row @end
@interface Dat : NSObject <NSTableViewDataSource, NSTableViewDelegate> { @public NSArray *items; int made, rows; } @end
@implementation Dat
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)items.count; }
- (BOOL)tableView:(NSTableView *)t isGroupRow:(NSInteger)r { return [items[(NSUInteger)r] hasPrefix:@"#"]; }
- (CGFloat)tableView:(NSTableView *)t heightOfRow:(NSInteger)r { return [self tableView:t isGroupRow:r] ? 18 : 24; }
- (NSTableRowView *)tableView:(NSTableView *)t rowViewForRow:(NSInteger)r {
    Row *f = [t makeViewWithIdentifier:@"row" owner:self];
    if (!f) { f = [[[Row alloc] initWithFrame:NSZeroRect] autorelease]; f.identifier = @"row"; rows++; }
    return f;
}
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    NSTableCellView *v = [t makeViewWithIdentifier:@"cell" owner:self];
    if (!v) {
        v = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)] autorelease];
        v.identifier = @"cell";
        NSTextField *f = [NSTextField labelWithString:@""];
        [v addSubview:f]; v.textField = f;
        made++;
    }
    v.textField.stringValue = items[(NSUInteger)r];
    return v;
}
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        NSTableView *t = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"c"]; col.width = 280;
        [t addTableColumn:col];
        Dat *d = [[Dat alloc] init];
        d->items = @[@"# Today", @"Dinner", @"Movie", @"# Tomorrow", @"Gym"];
        t.dataSource = d; t.delegate = d;
        sv.documentView = t;
        [w.contentView addSubview:sv];
        [t reloadData];
        CHECK(d->made == 5 && d->rows == 5);
        NSTableCellView *c2 = [t viewAtColumn:0 row:2 makeIfNecessary:NO];
        CHECK([c2.textField.stringValue isEqualToString:@"Movie"]);
        CHECK([t rowForView:c2.textField] == 2);
        CHECK([t columnForView:c2] == 0);
        CHECK([[t rowViewAtRow:0 makeIfNecessary:NO] isGroupRowStyle] && ![[t rowViewAtRow:1 makeIfNecessary:NO] isGroupRowStyle]);
        CHECK(((NSView *)[t rowViewAtRow:3 makeIfNecessary:NO]).frame.origin.y == 18 + 24 + 24 + 3 * t.intercellSpacing.height);
        [t selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
        CHECK([[t rowViewAtRow:2 makeIfNecessary:NO] isSelected] && ![[t rowViewAtRow:1 makeIfNecessary:NO] isSelected]);
        CHECK([[t rowViewAtRow:1 makeIfNecessary:NO] isNextRowSelected]);
        d->items = @[@"One", @"Two"];
        [t reloadData];
        CHECK(d->made == 5 && d->rows == 5);   /* reused */
        CHECK([[[t viewAtColumn:0 row:1 makeIfNecessary:NO] textField].stringValue isEqualToString:@"Two"]);
        __block int n = 0; [t enumerateAvailableRowViewsUsingBlock:^(id rv, NSInteger r) { n++; }];
        CHECK(n == 2 && [t rowViewAtRow:2 makeIfNecessary:NO] == nil);
        printf(fails ? "TABLES FAIL\n" : "TABLES OK\n");
    }
    return fails;
}
