/* menu.m — NSMenu / NSMenuItem. The main menu becomes the menu bar of every window (a native Win32 menu, ui.cpp):
 * it is flattened and sent again whenever something changes; the host reports clicks (UI_EV_MENU) and asks for the items'
 * state before a menu opens (UI_EV_MENU_OPEN), answered with the usual validation (validateMenuItem:). Key equivalents
 * are matched here, in -[NSApplication sendEvent:]; on Windows Ctrl+key also triggers a Command+key item. */
#import "internal.h"
#include <string.h>

static BOOL g_dirty;
static void flatten(NSMenu *m, int level, NSMutableArray *out);
static uint32_t item_flags(NSMenuItem *i, NSMenu *m, BOOL validate);
static BOOL mw_popup(NSMenu *m, NSWindow *w, NSPoint p);
static NSMutableArray *g_flat;   /* items sent to the host; id = index + 1 */
void mw_menu_mark_dirty(void) { g_dirty = YES; }

/* ======================================================================= NSMenuItem */
@interface NSMenuItem () { @public NSMenu *_owner; BOOL _sep; } @end
@interface NSMenu () - (void)_mwSetSuper:(NSMenu *)m; @end
@implementation NSMenuItem
+ (NSMenuItem *)separatorItem { NSMenuItem *i = [[[self alloc] initWithTitle:@"" action:NULL keyEquivalent:@""] autorelease]; i->_sep = YES; i.enabled = NO; return i; }
+ (NSMenuItem *)sectionHeaderWithTitle:(NSString *)t { NSMenuItem *i = [[[self alloc] initWithTitle:t action:NULL keyEquivalent:@""] autorelease]; i.enabled = NO; return i; }
- (instancetype)init { return [self initWithTitle:@"" action:NULL keyEquivalent:@""]; }
- (instancetype)initWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k {
    if ((self = [super init])) {
        _title = [t ? t : @"" copy]; _action = a; _keyEquivalent = [k ? k : @"" copy];
        _keyEquivalentModifierMask = NSEventModifierFlagCommand; _enabled = YES;
    }
    return self;
}
- (void)dealloc {
    [_title release]; [_keyEquivalent release]; [_toolTip release]; [_attributedTitle release]; [_submenu release];
    [_representedObject release]; [_image release]; [_onStateImage release]; [_offStateImage release]; [_view release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)z {
    NSMenuItem *c = [[NSMenuItem alloc] initWithTitle:_title action:_action keyEquivalent:_keyEquivalent];
    c.target = _target; c.tag = _tag; c.state = _state; c.enabled = _enabled; c.keyEquivalentModifierMask = _keyEquivalentModifierMask;
    c.representedObject = _representedObject; c->_sep = _sep;
    return c;
}
- (void)_changed { [_owner _mwChanged]; }
- (void)setTitle:(NSString *)t { if ([t isEqualToString:_title]) return; [_title release]; _title = [t ? t : @"" copy]; [self _changed]; }
- (void)setAttributedTitle:(NSAttributedString *)t { [_attributedTitle release]; _attributedTitle = [t copy]; if (t) self.title = t.string; }
- (void)setKeyEquivalent:(NSString *)k { [_keyEquivalent release]; _keyEquivalent = [k ? k : @"" copy]; [self _changed]; }
- (void)setKeyEquivalentModifierMask:(NSEventModifierFlags)m { _keyEquivalentModifierMask = m; [self _changed]; }
/* state and enabled reach the host when a menu opens (UI_MENU_STATE): no resend */
- (void)setHidden:(BOOL)h { if (h == _hidden) return; _hidden = h; [self _changed]; }
- (void)setSubmenu:(NSMenu *)m {
    if (m == _submenu) return;
    [m retain];
    [_submenu _mwSetSuper:nil];
    [_submenu release]; _submenu = m;
    [m _mwSetSuper:_owner];
    [self _changed];
}
- (BOOL)isSeparatorItem { return _sep; }
- (BOOL)hasSubmenu { return _submenu != nil; }
- (BOOL)isHighlighted { return NO; }
- (BOOL)isHiddenOrHasHiddenAncestor { return _hidden; }
- (NSMenu *)menu { return _owner; }
- (NSMenuItem *)parentItem { return nil; }
- (NSString *)description { return [NSString stringWithFormat:@"<NSMenuItem %@>", _title]; }
@end

/* ======================================================================= NSMenu */
@interface NSMenu () { NSMutableArray *_items; NSMenu *_sup; } @end
@implementation NSMenu
+ (void)setMenuBarVisible:(BOOL)f { }
+ (BOOL)menuBarVisible { return YES; }
+ (void)popUpContextMenu:(NSMenu *)m withEvent:(NSEvent *)e forView:(NSView *)v { mw_popup(m, v.window ? v.window : e.window, e.locationInWindow); }
- (instancetype)init { return [self initWithTitle:@""]; }
- (instancetype)initWithTitle:(NSString *)t {
    if ((self = [super init])) { _title = [t ? t : @"" copy]; _items = [[NSMutableArray alloc] init]; _autoenablesItems = YES; _showsStateColumn = YES; }
    return self;
}
- (void)dealloc {
    for (NSMenuItem *i in _items) i->_owner = nil;
    [_items release]; [_title release]; [_font release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)z {
    NSMenu *m = [[NSMenu alloc] initWithTitle:_title];
    for (NSMenuItem *i in _items) { NSMenuItem *c = [i copy]; [m addItem:c]; [c release]; }
    return m;
}
- (void)_mwSetSuper:(NSMenu *)m { _sup = m; }
- (NSMenu *)supermenu { return _sup; }
- (void)_mwChanged {
    /* only the main menu (and what hangs from it) is on screen */
    NSMenu *root = self;
    while (root->_sup) root = root->_sup;
    if (root == [NSApp mainMenu]) g_dirty = YES;
}
- (void)setTitle:(NSString *)t { [_title release]; _title = [t ? t : @"" copy]; [self _mwChanged]; }
- (NSArray *)itemArray { return [[_items copy] autorelease]; }
- (void)setItemArray:(NSArray *)a { [self removeAllItems]; for (NSMenuItem *i in a) [self addItem:i]; }
- (NSInteger)numberOfItems { return (NSInteger)[_items count]; }
- (NSMenuItem *)highlightedItem { return nil; }
- (void)insertItem:(NSMenuItem *)i atIndex:(NSInteger)n {
    if (!i) return;
    if (i->_owner) [i->_owner removeItem:i];
    [_items insertObject:i atIndex:(NSUInteger)(n < 0 ? 0 : n > (NSInteger)[_items count] ? (NSInteger)[_items count] : n)];
    i->_owner = self;
    [i.submenu _mwSetSuper:self];
    [self _mwChanged];
}
- (void)addItem:(NSMenuItem *)i { [self insertItem:i atIndex:(NSInteger)[_items count]]; }
- (NSMenuItem *)insertItemWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k atIndex:(NSInteger)n {
    NSMenuItem *i = [[[NSMenuItem alloc] initWithTitle:t action:a keyEquivalent:k] autorelease];
    [self insertItem:i atIndex:n];
    return i;
}
- (NSMenuItem *)addItemWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k {
    return [self insertItemWithTitle:t action:a keyEquivalent:k atIndex:(NSInteger)[_items count]];
}
- (void)removeItem:(NSMenuItem *)i {
    if (![_items containsObject:i]) return;
    i->_owner = nil;
    [i.submenu _mwSetSuper:nil];
    [_items removeObjectIdenticalTo:i];
    [self _mwChanged];
}
- (void)removeItemAtIndex:(NSInteger)n { if (n >= 0 && n < (NSInteger)[_items count]) [self removeItem:[_items objectAtIndex:(NSUInteger)n]]; }
- (void)removeAllItems { while ([_items count]) [self removeItem:[_items lastObject]]; }
- (NSMenuItem *)itemAtIndex:(NSInteger)n { return n >= 0 && n < (NSInteger)[_items count] ? [_items objectAtIndex:(NSUInteger)n] : nil; }
- (NSMenuItem *)itemWithTitle:(NSString *)t { for (NSMenuItem *i in _items) if ([i.title isEqualToString:t]) return i; return nil; }
- (NSMenuItem *)itemWithTag:(NSInteger)t { for (NSMenuItem *i in _items) if (i.tag == t) return i; return nil; }
- (NSInteger)indexOfItem:(NSMenuItem *)i { NSUInteger n = [_items indexOfObjectIdenticalTo:i]; return n == NSNotFound ? -1 : (NSInteger)n; }
- (NSInteger)indexOfItemWithTitle:(NSString *)t { return [self indexOfItem:[self itemWithTitle:t]]; }
- (NSInteger)indexOfItemWithTag:(NSInteger)t { return [self indexOfItem:[self itemWithTag:t]]; }
- (NSInteger)indexOfItemWithSubmenu:(NSMenu *)m { for (NSMenuItem *i in _items) if (i.submenu == m) return [self indexOfItem:i]; return -1; }
- (NSInteger)indexOfItemWithTarget:(id)t andAction:(SEL)a { for (NSMenuItem *i in _items) if (i.target == t && i.action == a) return [self indexOfItem:i]; return -1; }
- (void)setSubmenu:(NSMenu *)m forItem:(NSMenuItem *)i { i.submenu = m; }
- (void)itemChanged:(NSMenuItem *)i { [self _mwChanged]; }
- (void)cancelTracking { }
- (BOOL)popUpMenuPositioningItem:(NSMenuItem *)i atLocation:(NSPoint)p inView:(NSView *)v {
    NSWindow *w = v ? v.window : [NSApp keyWindow];
    NSPoint q = v ? [v convertPoint:p toView:nil] : [w convertPointFromScreen:p];
    return mw_popup(self, w, q);
}

/* validation, as AppKit does it before showing a menu or running a key equivalent */
static BOOL item_valid(NSMenuItem *i, NSMenu *m) {
    if (!m.autoenablesItems) return i.enabled;
    if (!i.action) return i.submenu != nil || (i.enabled && !i.isSeparatorItem && i.view);
    id t = [NSApp targetForAction:i.action to:i.target from:i];
    if (!t) return NO;
    if ([t respondsToSelector:@selector(validateMenuItem:)]) return [t validateMenuItem:i];
    if ([t respondsToSelector:@selector(validateUserInterfaceItem:)]) return [t validateUserInterfaceItem:i];
    return YES;
}
- (void)update {
    if ([(id)_delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [_delegate menuNeedsUpdate:self];
    for (NSMenuItem *i in [[_items copy] autorelease]) {
        BOOL v = item_valid(i, self);
        if (_autoenablesItems && v != i.enabled) i.enabled = v; /* AppKit stores the result */
        [i.submenu update];
    }
}
- (void)performActionForItemAtIndex:(NSInteger)n {
    NSMenuItem *i = [self itemAtIndex:n];
    if (!i || !i.action) return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSDictionary *info = @{@"MenuItem": i};
    [nc postNotificationName:NSMenuWillSendActionNotification object:self userInfo:info];
    [NSApp sendAction:i.action to:i.target from:i];
    [nc postNotificationName:NSMenuDidSendActionNotification object:self userInfo:info];
}

static BOOL is_letter(unichar c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static BOOL key_matches(NSMenuItem *i, NSString *key, NSEventModifierFlags mods) {
    NSString *k = i.keyEquivalent;
    if (![k length] || ![key length]) return NO;
    unichar kc = [k characterAtIndex:0];
    NSEventModifierFlags want = i.keyEquivalentModifierMask & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
    NSEventModifierFlags have = mods & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
    if (is_letter(kc)) {
        if (kc >= 'A' && kc <= 'Z') want |= NSEventModifierFlagShift;
        if ([k caseInsensitiveCompare:key] != NSOrderedSame) return NO;
    } else {
        want &= ~(NSEventModifierFlags)NSEventModifierFlagShift; have &= ~(NSEventModifierFlags)NSEventModifierFlagShift; /* the Shift is part of the character */
        if (![k isEqualToString:key]) return NO;
    }
    return want == have;
}
static NSMenuItem *find_key(NSMenu *m, NSString *key, NSEventModifierFlags mods) {
    for (NSMenuItem *i in m.itemArray) {
        if (i.hidden && !i.allowsKeyEquivalentWhenHidden) continue;
        if (i.submenu) { NSMenuItem *r = find_key(i.submenu, key, mods); if (r) return r; }
        else if (key_matches(i, key, mods)) return i;
    }
    return nil;
}
- (BOOL)performKeyEquivalent:(NSEvent *)e {
    if (e.type != NSEventTypeKeyDown) return NO;
    NSMenuItem *i = find_key(self, e.charactersIgnoringModifiers, e.modifierFlags);
    if (!i) return NO;
    [i.menu update];
    if (!i.enabled) return NO;
    [i.menu performActionForItemAtIndex:[i.menu indexOfItem:i]];
    return YES;
}
@end

/* a context menu at a point of a window (window coordinates); runs the chosen item's action */
static BOOL mw_popup(NSMenu *m, NSWindow *w, NSPoint p) {
    NSMenuItem *i = mw_popup_choose(m, w, p);
    if (!i) return NO;
    if (i.enabled) [i.menu performActionForItemAtIndex:[i.menu indexOfItem:i]];
    return YES;
}
NSMenuItem *mw_popup_choose(NSMenu *m, NSWindow *w, NSPoint p) {
    if (!m) return nil;
    [m update];
    if ([(id)m.delegate respondsToSelector:@selector(menuWillOpen:)]) [m.delegate menuWillOpen:m];
    NSMutableArray *rows = [NSMutableArray array];
    flatten(m, 0, rows);
    MwMenuItem *items = calloc([rows count] ? [rows count] : 1, sizeof *items);
    NSUInteger n = 0;
    for (NSArray *r in rows) {
        NSMenuItem *i = r[0];
        MwMenuItem *o = &items[n++];
        o->id = (int32_t)n; o->level = [r[1] intValue]; o->flags = item_flags(i, i.menu, NO);
        o->title = [i.title UTF8String]; o->key = [i.keyEquivalent UTF8String]; o->key_modifiers = (uint32_t)i.keyEquivalentModifierMask;
    }
    CGFloat sc = w ? w.backingScaleFactor : 1, h = w ? [w contentRectForFrameRect:w.frame].size.height : 0;
    int64_t chosen = ui(UI_POPUP_MENU, [w _mwId], (uint64_t)(int64_t)lround(p.x * sc), (uint64_t)(int64_t)lround((h - p.y) * sc), U(items), n);
    free(items);
    if ([(id)m.delegate respondsToSelector:@selector(menuDidClose:)]) [m.delegate menuDidClose:m];
    if (chosen < 1 || chosen > (int64_t)[rows count]) return nil;
    return rows[(NSUInteger)chosen - 1][0];
}

BOOL mw_menu_has_key_equivalent(NSString *key, NSEventModifierFlags mods) { return [NSApp mainMenu] && find_key([NSApp mainMenu], key, mods) != nil; }

/* ======================================================================= host menu bar */
static void flatten(NSMenu *m, int level, NSMutableArray *out) {
    for (NSMenuItem *i in m.itemArray) {
        if (i.hidden) continue;
        [out addObject:@[i, @(level)]];
        if (i.submenu) flatten(i.submenu, level + 1, out);
    }
}
static uint32_t item_flags(NSMenuItem *i, NSMenu *m, BOOL validate) {
    uint32_t f = 0;
    if (i.isSeparatorItem) return UI_MI_SEPARATOR;
    if (i.submenu) f |= UI_MI_SUBMENU;
    if (!(validate ? item_valid(i, m) : i.enabled) && !i.submenu) f |= UI_MI_DISABLED;
    if (i.state == NSControlStateValueOn) f |= UI_MI_CHECKED;
    return f;
}
void mw_menu_sync(void) {
    if (!g_dirty) return;
    g_dirty = NO;
    NSMenu *bar = [NSApp mainMenu];
    NSMutableArray *rows = [NSMutableArray array];
    if (bar) flatten(bar, 0, rows);
    [g_flat release];
    g_flat = [[NSMutableArray alloc] init];
    MwMenuItem *items = calloc([rows count] ? [rows count] : 1, sizeof *items);
    NSUInteger n = 0;
    for (NSArray *r in rows) {
        NSMenuItem *i = r[0];
        int level = [r[1] intValue];
        [g_flat addObject:i];
        MwMenuItem *o = &items[n++];
        o->id = (int32_t)[g_flat count];
        o->level = level;
        o->flags = item_flags(i, i.menu, NO);
        NSString *t = i.title;
        if (level == 0 && [bar indexOfItem:i] == 0) /* the application menu: titled after the app */
            t = [i.submenu.title length] && ![i.submenu.title isEqualToString:@"Apple"] ? i.submenu.title : [NSProcessInfo processInfo].processName;
        else if (level == 0 && i.submenu && [i.submenu.title length]) t = i.submenu.title;
        o->title = [t UTF8String];
        o->key = [i.keyEquivalent UTF8String];
        o->key_modifiers = (uint32_t)i.keyEquivalentModifierMask;
        if ([i.keyEquivalent length] == 1 && [i.keyEquivalent characterAtIndex:0] >= 'A' && [i.keyEquivalent characterAtIndex:0] <= 'Z')
            o->key_modifiers |= NSEventModifierFlagShift;
    }
    ui(UI_MENU, U(items), n, 0, 0, 0);
    free(items);
}
void mw_menu_event(const MwEvent *e) {
    if (e->type == UI_EV_MENU) {
        NSUInteger k = e->a;
        if (k < 1 || k > [g_flat count]) return;
        NSMenuItem *i = [g_flat objectAtIndex:k - 1];
        if (!i.menu) return;
        [i.menu update];
        if (i.enabled) [i.menu performActionForItemAtIndex:[i.menu indexOfItem:i]];
        return;
    }
    /* UI_EV_MENU_OPEN: validate everything and answer with the states */
    NSMenu *bar = [NSApp mainMenu];
    [bar update];
    NSUInteger n = [g_flat count];
    MwMenuItem *items = calloc(n ? n : 1, sizeof *items);
    for (NSUInteger k = 0; k < n; k++) {
        NSMenuItem *i = [g_flat objectAtIndex:k];
        items[k].id = (int32_t)k + 1;
        items[k].flags = item_flags(i, i.menu, NO);
    }
    ui(UI_MENU_STATE, U(items), n, 0, 0, 0);
    free(items);
    /* titles changed by the validation (e.g. "Enter/Exit Full Screen") show from the next opening */
}
