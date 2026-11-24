/* autolayout.m: visual format language, a window that takes the size its content needs, guides of the safe area, and
   constraints that leave with a removed view */
#import <AppKit/AppKit.h>
static int fails;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s (line %d)\n", #c, __LINE__); fails++; } } while (0)
@interface Grid : NSView @end @implementation Grid - (NSSize)intrinsicContentSize { return NSMakeSize(173, 150); } @end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        NSView *root = w.contentView;
        root.additionalSafeAreaInsets = NSEdgeInsetsMake(10, 0, 0, 0);
        NSView *old = [[NSView alloc] init]; old.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:old];
        [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(300)-[o(50)]" options:0 metrics:nil views:@{@"o": old}]];
        [old removeFromSuperview];   /* its constraints go with it */
        NSView *child = [[NSView alloc] init]; child.translatesAutoresizingMaskIntoConstraints = NO;
        [root addSubview:child];
        [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[c]|" options:0 metrics:nil views:@{@"c": child}]];
        [NSLayoutConstraint activateConstraints:@[[child.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor],
                                                  [child.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
        Grid *g = [[Grid alloc] init]; g.translatesAutoresizingMaskIntoConstraints = NO; [child addSubview:g];
        NSTextField *l = [NSTextField labelWithString:@"Nov"]; l.translatesAutoresizingMaskIntoConstraints = NO; [child addSubview:l];
        NSDictionary *v = NSDictionaryOfVariableBindings(g, l);
        [child addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-pad-[g]-pad-|" options:0 metrics:@{@"pad": @2} views:v]];
        [child addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[l]-(>=4@750)-[g]-5-|" options:NSLayoutFormatAlignAllLeft metrics:nil views:v]];
        [root layoutSubtreeIfNeeded];
        NSSize c = [w contentRectForFrameRect:w.frame].size;
        CHECK(fabs(c.width - 177) < 1.5);
        CHECK(c.height >= 150 + 5 + 4 + 10 + 8 && c.height < 230);
        CHECK(fabs(g.frame.origin.x - 2) < 1 && fabs(g.frame.size.width - 173) < 1.5);
        CHECK(fabs(l.frame.origin.x - g.frame.origin.x) < 1);   /* aligned left */
        CHECK(fabs(NSMaxY(child.frame) - (c.height - 10)) < 1); /* under the safe area's top inset */
        for (NSLayoutConstraint *k in root.constraints) CHECK(k.firstItem != old && k.secondItem != old);
        printf(fails ? "AUTOLAYOUT FAIL\n" : "AUTOLAYOUT OK\n");
    }
    return fails;
}
