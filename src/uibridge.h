/* uibridge.h — the boundary between the guest's AppKit / GameController / AudioToolbox and the host (scion.exe):
 *     int64_t ui(op, a, b, c, d, e)        (hostcall HC_ui)
 * Plain C structs, identical on both sides. Screen coordinates are host pixels, top-left origin; the guest converts to
 * Cocoa points (bottom-left origin) with the screen's scale. Windows live on a host UI thread with its own message
 * loop; their events are queued and the guest takes them with UI_NEXT_EVENT. */
#pragma once
#include <stdint.h>

enum {
    UI_NEXT_EVENT = 1,   /* MwEvent *out, timeout_ns (-1 forever, 0 poll) -> 1 event, 0 none */
    UI_WAKE,             /* wakes a waiting UI_NEXT_EVENT (returns 0 to it) */
    UI_WINDOW_CREATE,    /* const MwWindowDesc* -> window id (> 0) */
    UI_WINDOW_SET,       /* id, what (UI_W_*), a, b, c */
    UI_WINDOW_INFO,      /* id, MwWindowInfo* out */
    UI_WINDOW_HWND,      /* id -> HWND */
    UI_SCREEN,           /* index, MwScreen* out -> number of screens */
    UI_MENU,             /* const MwMenuItem *items, count: the menu bar of every window */
    UI_MENU_STATE,       /* const MwMenuItem *items, count: checks / enabled / titles (answer to UI_EV_MENU_OPEN) */
    UI_CURSOR,           /* op (0 hide, 1 show, 2 warp x y, 3 associate (b = 0 detaches: relative deltas only)), x, y */
    UI_MOUSE_POS,        /* int32_t out[2] (screen pixels) -> buttons bitmask */
    UI_PAD,              /* index 0..3, MwPad* out -> 1 connected */
    UI_RUMBLE,           /* index, low motor 0..65535, high motor 0..65535 */
    UI_PAD_INJECT,       /* index, const MwPad* (0: unplug): a virtual controller, for tests */
    UI_AUDIO_OPEN,       /* sample rate, channels -> stream id (float32 interleaved; always succeeds: no device = null sink) */
    UI_AUDIO_WRITE,      /* id, const float*, frames -> frames queued (blocks until there is room) */
    UI_AUDIO_CTL,        /* id, op (0 start, 1 stop, 2 close, 3 queued frames, 4 device rate, 5 is null sink) */
    UI_VSYNC_WAIT,       /* -> waits for the next display refresh (DwmFlush), returns the refresh rate in mHz */
    UI_ALERT,            /* const char *title, const char *text, style (0 info, 1 warning, 2 critical), buttons (1-3) -> 0.. */
    UI_INJECT,           /* id, msg, wparam, lparam: posts a raw Win32 message to the window (tests) */
    UI_CLIPBOARD,        /* op (0 get -> char* malloc'd by host, freed with UI_FREE; 1 set text) , text */
    UI_FREE,             /* pointer returned by the host */
    UI_FILE_DIALOG,      /* const MwFileDialog* -> char* (malloc'd, UI_FREE): chosen Darwin paths, one per line; 0 = cancelled */
    UI_POPUP_MENU,       /* window id, x, y (client pixels), const MwMenuItem *items, count -> chosen item id, 0 = none */
    UI_TEST,             /* tests: what (1 next file dialog answer: paths or "" = cancel, 2 next popup answer: item id,
                            3 read back window b's pixels into MwImage *c -> 1, 4 click status item b with button c -> 1 if it
                            exists, 5 status item b's icon into MwImage *c -> 1), value */
    UI_RAW_NEXT,         /* MwRaw *out, timeout_ns: raw keyboard/mouse input (GCKeyboard, GCMouse) while the app is in front */
    UI_RAW_INJECT,       /* const MwRaw*: a synthetic raw event (tests) */
    UI_TEXT,             /* MwText*: measures the text (mask == 0) or renders it into mask (w * h coverage bytes) -> 1 ok */
    UI_IMAGE_DECODE,     /* const void *data, size, MwImage *out (pixels malloc'd by the host, UI_FREE) -> 1 ok */
    UI_IMAGE_ENCODE,     /* const MwImage*, type (UI_IMG_*), float quality, uint64_t *size out -> data (malloc'd, UI_FREE) | 0 */
    UI_PRESENT,          /* window id, const MwImage* (0: none): the window's client area shows these pixels (non-Metal windows) */
    UI_STATUS_ITEM,      /* id (> 0), op (1 set, 0 remove), const MwImage *icon (0: keep), const char *tooltip (0: keep):
                            an icon in the notification area (NSStatusItem); clicks come back as UI_EV_STATUS */
    UI_OP_COUNT
};

/* window style (NSWindowStyleMask values) */
enum { UI_STYLE_TITLED = 1, UI_STYLE_CLOSABLE = 2, UI_STYLE_MINIATURIZABLE = 4, UI_STYLE_RESIZABLE = 8, UI_STYLE_NOMENU = 16 /* panels and modal windows: no menu bar */ };

typedef struct {
    int32_t x, y, w, h;      /* content rect, screen pixels (x/y < -30000: center) */
    uint32_t style;
    uint32_t visible;
    const char *title;
} MwWindowDesc;

enum {
    UI_W_TITLE = 1,     /* const char* */
    UI_W_FRAME,         /* x, y, w|h<<32: content rect in screen pixels */
    UI_W_SHOW,          /* 0 hide, 1 show, 2 show + activate (key) */
    UI_W_CLOSE,         /* destroys the window */
    UI_W_MINIMIZE,      /* 1 minimize, 0 restore */
    UI_W_FULLSCREEN,    /* 1 enter, 0 exit */
    UI_W_MIN_SIZE,      /* w, h content pixels */
    UI_W_MAX_SIZE,      /* w, h */
    UI_W_ASPECT,        /* w, h (0, 0 = free) */
    UI_W_STYLE,         /* style mask */
    UI_W_CURSOR_HIDDEN, /* 1 hides the cursor over this window's content */
    UI_W_TRANSPARENT,   /* 1: per-pixel alpha (what UI_PRESENT shows is blended over the desktop; clear pixels let clicks through) */
};

typedef struct {
    int32_t x, y, w, h;          /* content rect, screen pixels */
    int32_t fx, fy, fw, fh;      /* whole window (frame) */
    uint32_t dpi;                /* 96 = scale 1 */
    uint32_t key, visible, minimized, fullscreen, zoomed;
} MwWindowInfo;

typedef struct {
    int32_t x, y, w, h;          /* monitor, screen pixels */
    int32_t vx, vy, vw, vh;      /* work area (without the taskbar) */
    uint32_t dpi, primary;
    uint32_t refresh_mhz;
    char name[64];
} MwScreen;

enum {
    UI_EV_KEY_DOWN = 1, UI_EV_KEY_UP, UI_EV_FLAGS,              /* keyboard */
    UI_EV_MOUSE_DOWN, UI_EV_MOUSE_UP, UI_EV_MOUSE_MOVE,         /* button: 0 left, 1 right, 2 other (+ number) */
    UI_EV_SCROLL, UI_EV_MOUSE_ENTER, UI_EV_MOUSE_EXIT,
    UI_EV_RESIZE,           /* x, y = client size pixels, a = dpi */
    UI_EV_MOVE,
    UI_EV_FOCUS,            /* a = 1 became key, 0 resigned */
    UI_EV_CLOSE_REQUEST,    /* the user asked to close the window */
    UI_EV_MINIMIZE,         /* a = 1 minimized, 0 restored */
    UI_EV_FULLSCREEN,       /* a = 1 entered, 0 left */
    UI_EV_MENU,             /* a = menu item id */
    UI_EV_MENU_OPEN,        /* a menu is about to show: answer with UI_MENU_STATE */
    UI_EV_DPI,              /* a = new dpi */
    UI_EV_QUIT,             /* system shutdown / logoff */
    UI_EV_STATUS,           /* a = status item id, button (0 left, 1 right); x, y, dx, dy = the icon's rect, screen pixels */
};

/* NSEventModifierFlags */
enum { UI_MOD_CAPS = 1 << 16, UI_MOD_SHIFT = 1 << 17, UI_MOD_CONTROL = 1 << 18, UI_MOD_OPTION = 1 << 19, UI_MOD_COMMAND = 1 << 20,
       UI_MOD_NUMPAD = 1 << 21, UI_MOD_FUNCTION = 1 << 23 };

typedef struct {
    uint32_t type, window;
    uint64_t time_ns;           /* monotonic */
    int32_t x, y;               /* mouse: client pixels, top-left origin */
    float dx, dy;               /* mouse move: delta (pixels); scroll: lines (precise when b = 1) */
    uint32_t keycode;           /* Mac virtual key code (kVK_*) */
    uint32_t modifiers;         /* NSEventModifierFlags */
    uint32_t button, clicks;
    uint32_t a, b;              /* per type (see above); key: a = repeat */
    char chars[16];             /* UTF-8, key events */
    char chars_nomod[16];       /* characters ignoring modifiers except Shift */
} MwEvent;

typedef struct {
    int32_t id;                 /* > 0: sent back in UI_EV_MENU */
    int32_t level;              /* 0 top-level (menu bar entry), 1 inside it, 2 ... */
    uint32_t flags;             /* UI_MI_* */
    uint32_t key_modifiers;     /* key equivalent modifiers (NSEventModifierFlags) */
    const char *title;          /* UTF-8 */
    const char *key;            /* key equivalent ("q", "," ...), "" none */
} MwMenuItem;
enum { UI_MI_SEPARATOR = 1, UI_MI_DISABLED = 2, UI_MI_CHECKED = 4, UI_MI_SUBMENU = 8 };

enum { UI_FD_SAVE = 1, UI_FD_FILES = 2, UI_FD_DIRS = 4, UI_FD_MULTIPLE = 8, UI_FD_CREATE_DIRS = 16, UI_FD_HIDDEN = 32 };
typedef struct {
    uint32_t flags, window;          /* UI_FD_*; owner window id (0: none) */
    const char *title, *button;      /* UTF-8, may be 0 */
    const char *directory, *filename;/* initial folder (Darwin path), proposed name */
    const char *types;               /* allowed extensions separated by ';' ("png;jpg"), 0 = any */
} MwFileDialog;

enum { UI_RAW_KEY = 1, UI_RAW_MOVE, UI_RAW_BUTTON, UI_RAW_SCROLL };
typedef struct {
    uint32_t type;              /* UI_RAW_* */
    uint32_t code;              /* key: HID usage (page 7); button: 0 left, 1 right, 2 middle, 3.. extra */
    int32_t down;
    float dx, dy;               /* move: counts, y down; scroll: notches, y up */
    uint64_t time_ns;
} MwRaw;

/* text: one line, UTF-8; sizes in pixels. The mask's origin is the left end of the baseline at (pad, ascent). */
enum { UI_TEXT_ITALIC = 1, UI_TEXT_MONO = 2 };
typedef struct {
    const char *font;           /* PostScript or family name (".AppleSystemUIFont", "Menlo-Regular", "Helvetica-Bold"...) */
    const char *text;
    float size;                 /* em size, pixels */
    uint32_t weight;            /* 100..900 (400 regular, 700 bold) */
    uint32_t flags;             /* UI_TEXT_* */
    float width, ascent, descent;   /* out: advance width, line metrics */
    uint32_t w, h, pad;         /* out: mask size (pad pixels on each side) */
    uint8_t *mask;              /* in (rendering): w * h bytes, row 0 = top */
} MwText;

/* images: 32-bit BGRA, premultiplied alpha, row 0 = top, rows of w * 4 bytes */
enum { UI_IMG_PNG, UI_IMG_JPEG, UI_IMG_BMP, UI_IMG_TIFF, UI_IMG_GIF };
typedef struct { uint32_t w, h; void *pixels; } MwImage;

typedef struct {
    uint32_t buttons;           /* UI_PAD_* */
    float lx, ly, rx, ry;       /* -1..1, y up */
    float lt, rt;               /* 0..1 */
    char name[48];
    uint32_t has_rumble;
} MwPad;
enum {
    UI_PAD_A = 1, UI_PAD_B = 2, UI_PAD_X = 4, UI_PAD_Y = 8, UI_PAD_LB = 16, UI_PAD_RB = 32, UI_PAD_LS = 64, UI_PAD_RS = 128,
    UI_PAD_MENU = 256, UI_PAD_VIEW = 512, UI_PAD_UP = 1024, UI_PAD_DOWN = 2048, UI_PAD_LEFT = 4096, UI_PAD_RIGHT = 8192,
    UI_PAD_HOME = 16384,
};
