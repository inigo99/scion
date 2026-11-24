// Auto Layout: solved constraints (edges, centers, multipliers, inequalities, priorities, intrinsic sizes, wrapping
// labels, flipped views, and a manually placed panel whose stack view is pinned to its edges). Prints "AUTOLAYOUT OK".
#import <AppKit/AppKit.h>
#include <stdio.h>

static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)
static BOOL eq(CGFloat a, CGFloat b) { return fabs(a - b) < 1.01; }
static NSString *R(NSRect r) { return NSStringFromRect(r); }
#define RS(r) [R(r) UTF8String]
@interface Flip : NSView @end
@implementation Flip
- (BOOL)isFlipped { return YES; }
@end
static NSView *box(NSView *parent) { NSView *v = [NSView new]; v.translatesAutoresizingMaskIntoConstraints = NO; [parent addSubview:v]; return v; }

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        // 1. edges and a fixed height
        NSView *a = box(root);
        [NSLayoutConstraint activateConstraints:@[[a.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:10],
            [a.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-10], [a.topAnchor constraintEqualToAnchor:root.topAnchor constant:5],
            [a.heightAnchor constraintEqualToConstant:30]]];
        // 2. centered with a multiplier, chained above and below (a typical progress screen)
        NSProgressIndicator *bar = [NSProgressIndicator new]; bar.indeterminate = NO; bar.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:bar];
        NSTextField *title = [NSTextField labelWithString:@"Preparing shaders"]; title.font = [NSFont systemFontOfSize:22];
        title.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:title];
        NSStackView *row = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"one"], [NSTextField labelWithString:@"two"]]];
        row.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:row];
        NSTextField *notice = [NSTextField wrappingLabelWithString:@"First-time shader compilation can take a long time. Please keep the app open. Later launches are usually faster."];
        notice.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:notice];
        [NSLayoutConstraint activateConstraints:@[
            [bar.centerXAnchor constraintEqualToAnchor:root.centerXAnchor], [bar.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
            [bar.widthAnchor constraintEqualToAnchor:root.widthAnchor multiplier:.6],
            [title.centerXAnchor constraintEqualToAnchor:root.centerXAnchor], [title.bottomAnchor constraintEqualToAnchor:bar.topAnchor constant:-24],
            [row.centerXAnchor constraintEqualToAnchor:root.centerXAnchor], [row.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:16],
            [notice.widthAnchor constraintEqualToAnchor:root.widthAnchor multiplier:.5],
            [notice.centerXAnchor constraintEqualToAnchor:root.centerXAnchor], [notice.topAnchor constraintEqualToAnchor:row.bottomAnchor constant:20]]];
        // 3. inequalities and priorities: wants a width of 1000 (low priority) but no more than the parent - 20
        NSView *c = box(root);
        NSLayoutConstraint *want = [c.widthAnchor constraintEqualToConstant:1000]; want.priority = NSLayoutPriorityDefaultLow;
        [NSLayoutConstraint activateConstraints:@[want, [c.widthAnchor constraintLessThanOrEqualToAnchor:root.widthAnchor constant:-20],
            [c.leftAnchor constraintEqualToAnchor:root.leftAnchor constant:10], [c.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
            [c.heightAnchor constraintGreaterThanOrEqualToConstant:12]]];
        // 4. chained siblings with an intrinsic size
        NSTextField *l = [NSTextField labelWithString:@"Label"]; l.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:l];
        NSView *d = box(root);
        [NSLayoutConstraint activateConstraints:@[[l.leftAnchor constraintEqualToAnchor:root.leftAnchor constant:20], [l.topAnchor constraintEqualToAnchor:a.bottomAnchor constant:8],
            [d.leadingAnchor constraintEqualToAnchor:l.trailingAnchor constant:8], [d.centerYAnchor constraintEqualToAnchor:l.centerYAnchor],
            [d.widthAnchor constraintEqualToConstant:40], [d.heightAnchor constraintEqualToAnchor:d.widthAnchor multiplier:0.5]]];

        [root layoutSubtreeIfNeeded];
        CHECK(eq(a.frame.origin.x, 10) && eq(a.frame.size.width, 380) && eq(a.frame.size.height, 30) && eq(NSMaxY(a.frame), 295), "edges %s", RS(a.frame));
        CHECK(eq(bar.frame.size.width, 240) && eq(NSMidX(bar.frame), 200) && eq(NSMidY(bar.frame), 150) && eq(bar.frame.size.height, 20), "center and multiplier %s", RS(bar.frame));
        NSSize ts = title.intrinsicContentSize;
        CHECK(eq(title.frame.origin.y, NSMaxY(bar.frame) + 24) && eq(title.frame.size.width, ts.width) && eq(title.frame.size.height, ts.height) &&
              eq(NSMidX(title.frame), 200), "title above the bar at its own size %s", RS(title.frame));
        CHECK(eq(NSMaxY(row.frame), bar.frame.origin.y - 16) && row.frame.size.width > 40 && eq(row.frame.size.height, row.fittingSize.height), "row (stack) below %s", RS(row.frame));
        CHECK(row.arrangedSubviews[1].frame.origin.x > row.arrangedSubviews[0].frame.size.width, "the stack places its views");
        CHECK(eq(notice.frame.size.width, 200) && notice.frame.size.height > 2 * ts.height * 0.5 && eq(NSMaxY(notice.frame), row.frame.origin.y - 20),
              "label wrapped to the given width %s", RS(notice.frame));
        CHECK(eq(c.frame.size.width, 380) && eq(c.frame.origin.y, 0) && c.frame.size.height >= 11.5, "inequality beats low priority %s", RS(c.frame));
        CHECK(eq(l.frame.origin.x, 20) && eq(NSMaxY(l.frame), a.frame.origin.y - 8) && eq(d.frame.origin.x, NSMaxX(l.frame) + 8) &&
              eq(d.frame.size.height, 20) && eq(NSMidY(d.frame), NSMidY(l.frame)), "chained siblings and ratio %s %s", RS(l.frame), RS(d.frame));
        // 5. resizing the parent solves again
        [root setFrameSize:NSMakeSize(600, 300)];
        [root layoutSubtreeIfNeeded];
        CHECK(eq(a.frame.size.width, 580) && eq(bar.frame.size.width, 360) && eq(NSMidX(bar.frame), 300), "after resizing %s %s", RS(a.frame), RS(bar.frame));

        // 6. flipped view: top is the origin
        NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSView *e = box(host);
        [NSLayoutConstraint activateConstraints:@[[e.topAnchor constraintEqualToAnchor:host.topAnchor constant:10], [e.leftAnchor constraintEqualToAnchor:host.leftAnchor],
            [e.widthAnchor constraintEqualToConstant:50], [e.heightAnchor constraintEqualToConstant:20]]];
        [host layoutSubtreeIfNeeded];
        CHECK(eq(e.frame.origin.y, 70) && eq(e.frame.size.height, 20), "top in a normal view %s", RS(e.frame));
        NSView *fl = [[Flip alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSView *e2 = box(fl);
        [NSLayoutConstraint activateConstraints:@[[e2.topAnchor constraintEqualToAnchor:fl.topAnchor constant:10], [e2.leftAnchor constraintEqualToAnchor:fl.leftAnchor],
            [e2.widthAnchor constraintEqualToConstant:50], [e2.heightAnchor constraintEqualToConstant:20]]];
        [fl layoutSubtreeIfNeeded];
        CHECK(eq(e2.frame.origin.y, 10) && eq(e2.frame.size.height, 20), "top in a flipped view %s", RS(e2.frame));

        // 7. a controls panel: the panel is placed by hand, its stack is pinned to its edges and top
        NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960, 540)];
        NSView *panel = [NSView new];
        NSTextField *t1 = [NSTextField labelWithString:@"Controls"], *t2 = [NSTextField labelWithString:@"Frame rate"];
        NSStackView *stack = [NSStackView stackViewWithViews:@[t1, t2]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 10; stack.edgeInsets = NSEdgeInsetsMake(10, 12, 10, 12);
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [panel addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:panel.topAnchor], [stack.widthAnchor constraintEqualToConstant:308]]];
        panel.frame = NSMakeRect(10, 10, 308, 400);
        [content addSubview:panel];
        [panel layoutSubtreeIfNeeded];
        CGFloat want_h = stack.fittingSize.height;
        CHECK(eq(stack.frame.size.width, 308) && eq(stack.frame.size.height, want_h) && eq(NSMaxY(stack.frame), 400) && want_h > 40, "panel stack %s (%g)", RS(stack.frame), want_h);
        panel.frame = NSMakeRect(10, 10, 308, NSHeight(stack.frame));
        [panel layoutSubtreeIfNeeded];
        CHECK(eq(stack.frame.origin.y, 0) && eq(stack.frame.size.height, want_h), "panel fitted to its stack %s", RS(stack.frame));
        CHECK(eq(t1.frame.origin.x, 12) && t2.frame.origin.y > t1.frame.origin.y, "the vertical stack places its labels %s %s", RS(t1.frame), RS(t2.frame));
    }
    printf(fails ? "AUTOLAYOUT FAIL (%d)\n" : "AUTOLAYOUT OK\n", fails);
    return fails != 0;
}
