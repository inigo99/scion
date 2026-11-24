/* AppKit.dylib internals shared by its source files (guest, Objective-C MRC). */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreVideo/CoreVideo.h>
#include "../uibridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <math.h>
#include <float.h>
#include <dispatch/dispatch.h>
void *objc_autoreleasePoolPush(void); void objc_autoreleasePoolPop(void *);

int64_t _scion_ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
#define U(x) ((uint64_t)(uintptr_t)(x))
static inline int64_t ui(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e) { return _scion_ui(op, a, b, c, d, e); }

/* Coordinates: host pixels (top-left of the primary screen) <-> Cocoa points (bottom-left of the primary screen).
 * ponytail: global positions use the primary screen's scale; sizes use each window's own. Fine on one monitor or same-DPI
 * monitors; exact mixed-DPI placement would need per-monitor origins. */
CGFloat mw_scale0(void);      /* primary screen: points -> pixels */
CGFloat mw_height0(void);     /* primary screen height in points */
void mw_screens_changed(void);

void mw_app_activate(void);   /* starts the event pump (first window / NSApplication) */
NSWindow *mw_window_by_id(uint32_t id);
void mw_render_view_into(NSView *v, CGContextRef c, CAMetalLayer **metal);
void mw_window_event(NSWindow *w, const MwEvent *e);     /* resize, move, focus, close... */
void mw_menu_mark_dirty(void);
void mw_menu_sync(void);                                 /* sends the menu bar to the host if it changed */
void mw_menu_event(const MwEvent *e);
void mw_status_event(const MwEvent *e);
NSString *mw_status_report(void);                        /* statusbar.m: SCION_TEST_GUI */
void mw_status_test_click(int button);                   /* statusbar.m: SCION_TEST_CLICK */
NSRect mw_status_place(NSRect contentRect);              /* statusbar.m: a window opened from an icon stays on screen */
NSEvent *mw_run_event_monitors(NSEvent *e);              /* app.m: the local monitors (nil: swallowed); sets currentEvent */
BOOL mw_menu_has_key_equivalent(NSString *key, NSEventModifierFlags mods);
NSEvent *mw_event_from_host(const MwEvent *e, NSWindow *w);
void mw_tracking_update(NSWindow *w, NSEvent *e, BOOL exited);
void mw_event_set_area(NSEvent *e, NSTrackingArea *a);
void mw_windows_update(void);
NSMutableArray *g_windows_list(void);
void mw_get_last_mouse_delta(int32_t *dx, int32_t *dy);

/* drawing (draw.m, cgdraw.m) */
CGContextRef mw_cg(void);                                /* the current NSGraphicsContext's CGContext */
void _mwCGContextSetCTM(CGContextRef c, CGAffineTransform t);
void _mwCGContextClipToRectAligned(CGContextRef c, CGRect r); /* clip box rounded to device pixels (cheap) */
NSSize mw_text_size(NSString *s, NSFont *f);             /* points; one line per '\n' */
NSSize mw_text_size_wrapped(NSString *s, NSFont *f, CGFloat maxWidth);
void mw_font_metrics(NSFont *f, CGFloat *ascent, CGFloat *descent);
/* text in a rect of the current context: wraps unless lb truncates or clips; vcenter centers the block vertically */
void mw_draw_text_in(NSString *s, NSRect r, NSFont *f, NSColor *c, NSTextAlignment a, NSLineBreakMode lb, BOOL wrap, BOOL vcenter);
NSImage *mw_catalog_image(NSString *name, NSBundle *bundle);   /* assets.m: an image of a bundle's Assets.car (nil: main) */
void mw_draw_image(NSImage *i, NSRect r, NSColor *tint, CGFloat alpha); /* upright; tint: template images (nil: labelColor) */
void mw_render_window(NSWindow *w);                      /* composites the views, presents (or overlays a CAMetalLayer) */
void mw_fill_round(NSRect r, CGFloat radius, NSColor *c);
void mw_stroke_round(NSRect r, CGFloat radius, CGFloat width, NSColor *c);
void mw_solve_layout(NSView *root);                     /* layout.m: Auto Layout for the subtree */
void mw_cache_display(NSView *v, NSRect r, NSBitmapImageRep *rep);
NSMenuItem *mw_popup_choose(NSMenu *m, NSWindow *w, NSPoint p); /* menu.m: the chosen item (its action not performed) */

@interface NSBitmapImageRep (MWInternal)
- (instancetype)_mwInitWidth:(size_t)w height:(size_t)h;   /* RGBA premultiplied, zeroed */
- (CGContextRef)_mwNewCGContext;                          /* draws into the pixels; CTM in points */
@end
@interface NSImage (MWInternal)
- (NSString *)_mwSymbol;
@end
@interface NSWindow (MWInternal)
- (uint32_t)_mwId;
- (uint64_t)_mwHwnd;
- (void)_mwHandleMouse:(NSEvent *)e;
- (NSMutableSet *)_mwInside;
- (void)_mwSetNeedsRender;
@end
@interface NSView (MWInternal)
- (void)_mwSetWindow:(NSWindow *)w;
- (void)_mwBackingChanged;
- (void)_mwDetachLayers;
- (void)_mwClearNeedsDisplay;
@end
@interface NSMenu (MWInternal)
- (void)_mwChanged;
@end
@interface CALayer (MWHost)
- (void)_mwSetHostWindow:(uint64_t)hwnd;
- (void)_mwSetOverlay:(const void *)bgra width:(NSUInteger)w height:(NSUInteger)h; /* CAMetalLayer: views drawn over the Metal image */
@end
@interface NSRunLoop (MWRunLoop)
- (int)_pass; - (int)_passInMode:(NSString *)m;
- (NSTimeInterval)_nextTimer;
@end

/* nib.m */
NSView *mw_nib_init_view(NSView *self, NSCoder *c);
void mw_load_main_nib(void);
/* document.m */
id mw_document_controller_if_any(void);
void mw_open_launch_documents(void);
@interface NSWindow (MWRoot) - (NSView *)_mwRootView; - (BOOL)_mwTransparent; - (void)_mwSetTransparent:(BOOL)t; @end
@interface NSWindow (MWNoMenu) - (void)_mwSetNoMenu:(BOOL)f; @end
