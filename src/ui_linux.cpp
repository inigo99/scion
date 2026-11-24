/* ui_linux.cpp — host half of AppKit, GameController and AudioToolbox on the native Linux host (hostcall "ui",
 * uibridge.h), the counterpart of ui.cpp. SDL2 does windows, input, controllers, audio and the clipboard; FreeType and
 * fontconfig the text; libpng and libjpeg the images. Windows live on one host UI thread, as on Windows: their input
 * becomes MwEvents in a queue the guest drains.
 * ponytail, not yet: the menu bar (menus are kept, nothing shows them), status items in a real tray (they exist for
 * the guest and the tests), per-pixel transparent windows, BMP/TIFF/GIF images, HiDPI (everything is 96 dpi). */
#include "scion.h"
#include "uibridge.h"
#include "metal/mtlbridge.h"
#include <SDL2/SDL.h>
#include <SDL2/SDL_syswm.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <fontconfig/fontconfig.h>
#include <png.h>
#include <jpeglib.h>
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <map>
#include <mutex>
#include <thread>

static uint64_t now_ns() { return (uint64_t)hc_clock(1, 0, 0, 0, 0, 0); }
static char *dup_str(const std::string &s) { char *p = (char *)malloc(s.size() + 1); memcpy(p, s.c_str(), s.size() + 1); return p; }

/* ======================================================================= event queue */
static std::mutex g_qmu;
static std::condition_variable g_qcv;
static std::deque<MwEvent> g_queue;
static bool g_woken;
static void push(MwEvent e) {
    e.time_ns = now_ns();
    { std::lock_guard<std::mutex> l(g_qmu); g_queue.push_back(e); }
    g_qcv.notify_all();
}
static A next_event(MwEvent *out, int64_t timeout_ns) {
    std::unique_lock<std::mutex> l(g_qmu);
    auto ready = [] { return !g_queue.empty() || g_woken; };
    if (timeout_ns < 0) g_qcv.wait(l, ready);
    else g_qcv.wait_for(l, std::chrono::nanoseconds(timeout_ns), ready);
    g_woken = false;
    if (g_queue.empty()) return 0;
    *out = g_queue.front(); g_queue.pop_front();
    return 1;
}

/* ======================================================================= keyboard */
/* SDL scan codes are USB HID usages -> Mac virtual key codes (kVK_*) */
static uint8_t mac_key_hid(int u) {
    static const uint8_t t[104] = {
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25,   /* 00: a.. */
        0x2E, 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06, 0x12, 0x13,   /* 10 */
        0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x24, 0x35, 0x33, 0x30, 0x31, 0x1B, 0x18, 0x21,   /* 20 */
        0x1E, 0x2A, 0x2A, 0x29, 0x27, 0x32, 0x2B, 0x2F, 0x2C, 0x39, 0x7A, 0x78, 0x63, 0x76, 0x60, 0x61,   /* 30 */
        0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x72, 0x73, 0x74, 0x75, 0x77, 0x79, 0x7C,   /* 40 */
        0x7B, 0x7D, 0x7E, 0x47, 0x4B, 0x43, 0x4E, 0x45, 0x4C, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,   /* 50 */
        0x5B, 0x5C, 0x52, 0x41, 0x0A, 0x6E, 0xFF, 0x51,                                                   /* 60 */
    };
    switch (u) { case 224: return 0x3B; case 225: return 0x38; case 226: return 0x3A; case 227: return 0x37;
                 case 228: return 0x3E; case 229: return 0x3C; case 230: return 0x3D; case 231: return 0x36; }
    return u >= 0 && u < 104 ? t[u] : 0xFF;
}
/* PC set-1 scan codes (UI_INJECT carries Win32 key messages) -> Mac key codes; the same table as ui.cpp */
static uint8_t mac_key_scan(unsigned scan, bool ext) {
    static const uint8_t base[0x59] = {
        0xFF, 0x35, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x1B, 0x18, 0x33, 0x30,
        0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23, 0x21, 0x1E, 0x24, 0x3B, 0x00, 0x01,
        0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25, 0x29, 0x27, 0x32, 0x38, 0x2A, 0x06, 0x07, 0x08, 0x09,
        0x0B, 0x2D, 0x2E, 0x2B, 0x2F, 0x2C, 0x3C, 0x43, 0x3A, 0x31, 0x39, 0x7A, 0x78, 0x63, 0x76, 0x60,
        0x61, 0x62, 0x64, 0x65, 0x6D, 0x47, 0xFF, 0x59, 0x5B, 0x5C, 0x4E, 0x56, 0x57, 0x58, 0x45, 0x53,
        0x54, 0x55, 0x52, 0x41, 0xFF, 0xFF, 0x0A, 0x67, 0x6F,
    };
    if (ext) switch (scan) {
        case 0x1C: return 0x4C; case 0x1D: return 0x3E; case 0x35: return 0x4B; case 0x38: return 0x3D;
        case 0x47: return 0x73; case 0x48: return 0x7E; case 0x49: return 0x74; case 0x4B: return 0x7B;
        case 0x4D: return 0x7C; case 0x4F: return 0x77; case 0x50: return 0x7D; case 0x51: return 0x79;
        case 0x52: return 0x72; case 0x53: return 0x75; case 0x5B: return 0x37; case 0x5C: return 0x36;
        case 0x5D: return 0x6E; default: return 0xFF;
    }
    return scan < sizeof base ? base[scan] : 0xFF;
}
static bool is_modifier_key(uint8_t k) { return k >= 0x36 && k <= 0x3E; }   /* Command .. right Control, Caps Lock */
static uint32_t g_inject_mods;   /* modifiers held by injected key messages */
static uint32_t modifiers() {
    SDL_Keymod m = SDL_GetModState();
    uint32_t r = g_inject_mods;
    if (m & KMOD_SHIFT) r |= UI_MOD_SHIFT;
    if (m & KMOD_CTRL) r |= UI_MOD_CONTROL;
    if (m & KMOD_ALT) r |= UI_MOD_OPTION;
    if (m & KMOD_GUI) r |= UI_MOD_COMMAND;
    if (m & KMOD_CAPS) r |= UI_MOD_CAPS;
    return r;
}
static void put_utf8(uint32_t c, char *out) {
    if (c < 0x80) { out[0] = (char)c; out[1] = 0; }
    else if (c < 0x800) { out[0] = (char)(0xC0 | c >> 6); out[1] = (char)(0x80 | (c & 0x3F)); out[2] = 0; }
    else { out[0] = (char)(0xE0 | c >> 12); out[1] = (char)(0x80 | ((c >> 6) & 0x3F)); out[2] = (char)(0x80 | (c & 0x3F)); out[3] = 0; }
}
/* the characters of a key: Mac function-key characters, else the layout's character (shifted for letters and the US
 * symbols). ponytail: input methods and dead keys need SDL_TEXTINPUT */
static void key_chars(uint8_t mac, uint32_t base, uint32_t mods, char *chars, char *nomod) {
    static const struct { uint8_t k; uint16_t c; } fn[] = {{0x7E, 0xF700}, {0x7D, 0xF701}, {0x7B, 0xF702}, {0x7C, 0xF703},
        {0x7A, 0xF704}, {0x78, 0xF705}, {0x63, 0xF706}, {0x76, 0xF707}, {0x60, 0xF708}, {0x61, 0xF709}, {0x62, 0xF70A},
        {0x64, 0xF70B}, {0x65, 0xF70C}, {0x6D, 0xF70D}, {0x67, 0xF70E}, {0x6F, 0xF70F}, {0x72, 0xF727}, {0x75, 0xF728},
        {0x73, 0xF729}, {0x77, 0xF72B}, {0x74, 0xF72C}, {0x79, 0xF72D}, {0x33, 0x7F}, {0x24, '\r'}, {0x4C, 0x03}, {0x30, '\t'}, {0x35, 0x1B}};
    for (auto &f : fn) if (f.k == mac) { put_utf8(f.c, chars); put_utf8(f.c, nomod); return; }
    chars[0] = nomod[0] = 0;
    if (!base || base >= 0x110000) return;
    bool shift = mods & UI_MOD_SHIFT;
    uint32_t c = base;
    if (c >= 'a' && c <= 'z') { if (shift != !!(mods & UI_MOD_CAPS)) c -= 32; }
    else if (shift && c < 128) { static const char *from = "1234567890-=[]\\;',./`", *to = "!@#$%^&*()_+{}|:\"<>?~"; if (const char *p = strchr(from, (int)c)) c = (uint32_t)to[p - from]; }
    put_utf8(c, nomod);
    if (mods & UI_MOD_CONTROL && c >= '@' && c <= '_') c -= 64;
    else if (mods & UI_MOD_CONTROL && c >= 'a' && c <= 'z') c -= 96;
    put_utf8(c, chars);
}

/* ======================================================================= windows */
struct Win {
    uint32_t id;
    SDL_Window *sw = nullptr;
    uint32_t style = 0;
    bool fullscreen = false, cursor_hidden = false, inside = false;
    int lastx = INT32_MIN, lasty = INT32_MIN, buttons = 0;
    int clicks = 0; uint64_t last_click = 0; int click_btn = -1, clickx = 0, clicky = 0;
    std::mutex pmu; std::vector<uint32_t> px; int pw = 0, ph = 0;   /* UI_PRESENT */
};
static std::mutex g_wmu;
static std::vector<Win *> g_wins;
static std::atomic<bool> g_relative{false};
static Win *win_by_id(uint32_t id) { std::lock_guard<std::mutex> l(g_wmu); return id && id <= g_wins.size() ? g_wins[id - 1] : nullptr; }
static Win *win_by_sdl(uint32_t sdl_id) {
    SDL_Window *s = SDL_GetWindowFromID(sdl_id);
    std::lock_guard<std::mutex> l(g_wmu);
    for (Win *w : g_wins) if (w->sw && w->sw == s) return w;
    return nullptr;
}
static MwEvent ev(Win *w, uint32_t type) { MwEvent e{}; e.type = type; e.window = w ? w->id : 0; e.modifiers = modifiers(); return e; }
static void mouse(Win *w, uint32_t type, int x, int y, int button, float dx = 0, float dy = 0, bool rel = false) {
    MwEvent e = ev(w, type);
    e.x = x; e.y = y; e.button = (uint32_t)button;
    if (rel) { e.dx = dx; e.dy = dy; }
    else if (w->lastx != INT32_MIN) { e.dx = (float)(x - w->lastx); e.dy = (float)(y - w->lasty); }
    if (type == UI_EV_MOUSE_DOWN) {
        uint64_t t = now_ns();
        bool near = abs(x - w->clickx) <= 4 && abs(y - w->clicky) <= 4;
        w->clicks = button == w->click_btn && near && t - w->last_click < 500000000ull ? w->clicks + 1 : 1;
        w->last_click = t; w->click_btn = button; w->clickx = x; w->clicky = y;
        w->buttons |= 1 << (button < 2 ? button : 2);
    }
    if (type == UI_EV_MOUSE_UP) w->buttons &= ~(1 << (button < 2 ? button : 2));
    e.clicks = type == UI_EV_MOUSE_MOVE ? 0 : (uint32_t)w->clicks;
    e.b = (uint32_t)w->buttons;
    w->lastx = x; w->lasty = y;
    push(e);
}
static void key(Win *w, uint8_t mac, uint32_t base, bool down, bool repeat) {
    if (mac == 0xFF) return;
    if (is_modifier_key(mac)) { MwEvent e = ev(w, UI_EV_FLAGS); e.keycode = mac; e.a = down; push(e); return; }
    MwEvent e = ev(w, down ? UI_EV_KEY_DOWN : UI_EV_KEY_UP);
    e.keycode = mac; e.a = down && repeat;
    if (mac >= 0x41 && mac <= 0x5C && mac != 0x48 && mac != 0x49 && mac != 0x4A) e.modifiers |= UI_MOD_NUMPAD;
    if ((mac >= 0x60 && mac <= 0x7E) || mac == 0x72) e.modifiers |= UI_MOD_FUNCTION;
    key_chars(mac, base, e.modifiers, e.chars, e.chars_nomod);
    push(e);
}
static void redraw(Win *w) {   /* UI thread: the presented pixels into the window */
    SDL_Surface *s = SDL_GetWindowSurface(w->sw);
    if (!s) return;
    std::lock_guard<std::mutex> l(w->pmu);
    if (!w->pw) return;
    SDL_Surface *src = SDL_CreateRGBSurfaceWithFormatFrom(w->px.data(), w->pw, w->ph, 32, w->pw * 4, SDL_PIXELFORMAT_ARGB8888);
    if (src) { SDL_SetSurfaceBlendMode(src, SDL_BLENDMODE_NONE); SDL_BlitSurface(src, nullptr, s, nullptr); SDL_FreeSurface(src); }
    SDL_UpdateWindowSurface(w->sw);
}

/* ======================================================================= raw input (GCKeyboard / GCMouse) */
static std::mutex g_rmu;
static std::condition_variable g_rcv;
static std::deque<MwRaw> g_raw;
static std::atomic<bool> g_raw_on{false};
static void raw_push(MwRaw r) {
    r.time_ns = now_ns();
    { std::lock_guard<std::mutex> l(g_rmu); if (g_raw.size() < 4096) g_raw.push_back(r); }
    g_rcv.notify_all();
}

/* ======================================================================= controllers */
static SDL_GameController *g_pads[4];
static MwPad g_virtual[4];
static bool g_virtual_on[4];
static uint16_t g_rumble_seen[4][2];

/* ======================================================================= status items, tests */
struct Tray { std::vector<uint32_t> px; uint32_t w = 0, h = 0; std::string tip; };
static std::map<int, Tray> g_trays;   /* UI thread */
static std::mutex g_test_mu;
static std::string g_test_dialog; static bool g_test_dialog_set;
static int g_test_popup = -1;
static std::vector<MwMenuItem> g_menu; static std::vector<std::string> g_menu_strings;   /* kept, not shown yet */

/* ======================================================================= UI thread */
struct Req { int op; A a, b, c, d, e; A r; bool done; };
static Uint32 g_req_event;
static std::thread::id g_ui_thread;
static std::mutex g_reqmu;
static std::condition_variable g_reqcv;
static A ui_thread_op(Req *q);
static void handle(const SDL_Event &e) {
    if (e.type == g_req_event) {
        Req *q = (Req *)e.user.data1;
        q->r = ui_thread_op(q);
        { std::lock_guard<std::mutex> l(g_reqmu); q->done = true; }
        g_reqcv.notify_all();
        return;
    }
    switch (e.type) {
    case SDL_WINDOWEVENT: {
        Win *w = win_by_sdl(e.window.windowID); if (!w) return;
        switch (e.window.event) {
        case SDL_WINDOWEVENT_CLOSE: push(ev(w, UI_EV_CLOSE_REQUEST)); break;   /* the guest decides (windowShouldClose:) */
        case SDL_WINDOWEVENT_FOCUS_GAINED: case SDL_WINDOWEVENT_FOCUS_LOST: { MwEvent m = ev(w, UI_EV_FOCUS); m.a = e.window.event == SDL_WINDOWEVENT_FOCUS_GAINED; push(m); break; }
        case SDL_WINDOWEVENT_SIZE_CHANGED: { MwEvent m = ev(w, UI_EV_RESIZE); m.x = e.window.data1; m.y = e.window.data2; m.a = 96; push(m); redraw(w); break; }
        case SDL_WINDOWEVENT_MOVED: push(ev(w, UI_EV_MOVE)); break;
        case SDL_WINDOWEVENT_MINIMIZED: { MwEvent m = ev(w, UI_EV_MINIMIZE); m.a = 1; push(m); break; }
        case SDL_WINDOWEVENT_RESTORED: { MwEvent m = ev(w, UI_EV_MINIMIZE); m.a = 0; push(m); break; }
        case SDL_WINDOWEVENT_ENTER: w->inside = true; push(ev(w, UI_EV_MOUSE_ENTER)); break;
        case SDL_WINDOWEVENT_LEAVE: w->inside = false; w->lastx = INT32_MIN; push(ev(w, UI_EV_MOUSE_EXIT)); break;
        case SDL_WINDOWEVENT_EXPOSED: redraw(w); break;
        }
        break;
    }
    case SDL_KEYDOWN: case SDL_KEYUP: {
        if (g_raw_on) { MwRaw r{}; r.type = UI_RAW_KEY; r.code = (uint32_t)e.key.keysym.scancode; r.down = e.type == SDL_KEYDOWN; if (!e.key.repeat) raw_push(r); }
        Win *w = win_by_sdl(e.key.windowID); if (!w) return;
        if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_F4 && (e.key.keysym.mod & KMOD_ALT)) { push(ev(w, UI_EV_CLOSE_REQUEST)); return; }
        uint32_t base = e.key.keysym.sym & SDLK_SCANCODE_MASK ? 0 : (uint32_t)e.key.keysym.sym;
        key(w, mac_key_hid(e.key.keysym.scancode), base, e.type == SDL_KEYDOWN, e.key.repeat);
        break;
    }
    case SDL_MOUSEMOTION: {
        if (g_raw_on) { MwRaw r{}; r.type = UI_RAW_MOVE; r.dx = (float)e.motion.xrel; r.dy = (float)e.motion.yrel; raw_push(r); }
        Win *w = win_by_sdl(e.motion.windowID); if (!w) return;
        mouse(w, UI_EV_MOUSE_MOVE, e.motion.x, e.motion.y, -1, (float)e.motion.xrel, (float)e.motion.yrel, g_relative);
        break;
    }
    case SDL_MOUSEBUTTONDOWN: case SDL_MOUSEBUTTONUP: {
        int b = e.button.button == SDL_BUTTON_LEFT ? 0 : e.button.button == SDL_BUTTON_RIGHT ? 1 : 2 + (e.button.button > SDL_BUTTON_MIDDLE ? e.button.button - SDL_BUTTON_MIDDLE : 0);
        if (g_raw_on) { MwRaw r{}; r.type = UI_RAW_BUTTON; r.code = (uint32_t)(b < 2 ? b : b == 2 ? 2 : b + 1 - 2); r.down = e.type == SDL_MOUSEBUTTONDOWN; raw_push(r); }
        Win *w = win_by_sdl(e.button.windowID); if (!w) return;
        mouse(w, e.type == SDL_MOUSEBUTTONDOWN ? UI_EV_MOUSE_DOWN : UI_EV_MOUSE_UP, e.button.x, e.button.y, b);
        break;
    }
    case SDL_MOUSEWHEEL: {
        if (g_raw_on) { MwRaw r{}; r.type = UI_RAW_SCROLL; r.dx = e.wheel.preciseX; r.dy = e.wheel.preciseY; raw_push(r); }
        Win *w = win_by_sdl(e.wheel.windowID); if (!w) return;
        MwEvent m = ev(w, UI_EV_SCROLL);
        SDL_GetMouseState(&m.x, &m.y);
        m.dx = -e.wheel.preciseX; m.dy = e.wheel.preciseY;
        push(m);
        break;
    }
    case SDL_CONTROLLERDEVICEADDED:
        for (int i = 0; i < 4; i++) if (!g_pads[i]) { g_pads[i] = SDL_GameControllerOpen(e.cdevice.which); break; }
        break;
    case SDL_CONTROLLERDEVICEREMOVED:
        for (int i = 0; i < 4; i++)
            if (g_pads[i] && SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(g_pads[i])) == e.cdevice.which) { SDL_GameControllerClose(g_pads[i]); g_pads[i] = nullptr; }
        break;
    case SDL_QUIT: { MwEvent m{}; m.type = UI_EV_QUIT; push(m); break; }
    }
}
static void ui_start() {
    static std::once_flag once;
    std::call_once(once, [] {
        std::mutex m; std::condition_variable cv; bool ready = false;
        std::thread([&] {
            SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1");          /* signals belong to the guest */
            SDL_SetHint(SDL_HINT_VIDEODRIVER, "x11");               /* Metal layers draw into X11 windows (XWayland on Wayland) */
            XInitThreads();                                          /* Vulkan presents from other threads */
            /* window surfaces on X11 itself: a GL-backed one would re-create the X window, under a Metal layer's swapchain */
            SDL_SetHint(SDL_HINT_FRAMEBUFFER_ACCELERATION, "0");
            SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
            SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
            if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_EVENTS)) fprintf(stderr, "scion: SDL: %s\n", SDL_GetError());
            g_req_event = SDL_RegisterEvents(1);
            g_ui_thread = std::this_thread::get_id();
            { std::lock_guard<std::mutex> l(m); ready = true; cv.notify_all(); }
            SDL_Event e;
            for (;;) if (SDL_WaitEvent(&e)) handle(e);
        }).detach();
        std::unique_lock<std::mutex> l(m); cv.wait(l, [&] { return ready; });
    });
}
static A on_ui(int op, A a = 0, A b = 0, A c = 0, A d = 0, A e = 0) {
    ui_start();
    Req q{op, a, b, c, d, e, 0, false};
    if (std::this_thread::get_id() == g_ui_thread) return ui_thread_op(&q);
    SDL_Event ev{}; ev.type = g_req_event; ev.user.data1 = &q;
    SDL_PushEvent(&ev);
    std::unique_lock<std::mutex> l(g_reqmu);
    g_reqcv.wait(l, [&] { return q.done; });
    return q.r;
}

/* ---------------------------------------------------------------- file dialogs (zenity), Win32 messages for tests */
static A file_dialog(const MwFileDialog *d) {
    {
        std::lock_guard<std::mutex> l(g_test_mu);
        if (g_test_dialog_set) { g_test_dialog_set = false; return g_test_dialog.empty() ? 0 : (A)dup_str(g_test_dialog); }
    }
    auto q = [](const char *s) { std::string r = "'"; for (const char *c = s; *c; c++) { if (*c == '\'') r += "'\\''"; else r += *c; } return r + "'"; };
    std::string cmd = "zenity --file-selection";
    if (d->flags & UI_FD_SAVE) cmd += " --save --confirm-overwrite";
    if (!(d->flags & UI_FD_SAVE) && (d->flags & UI_FD_DIRS) && !(d->flags & UI_FD_FILES)) cmd += " --directory";
    if (!(d->flags & UI_FD_SAVE) && (d->flags & UI_FD_MULTIPLE)) cmd += " --multiple --separator='\n'";
    if (d->title && *d->title) cmd += " --title=" + q(d->title);
    std::string start = d->directory && *d->directory ? std::string(d->directory) + "/" : "";
    if (d->filename && *d->filename) start += d->filename;
    if (!start.empty()) cmd += " --filename=" + q(start.c_str());
    if (d->types && *d->types) {
        std::string t = d->types, f;
        for (size_t i = 0; i <= t.size();) { size_t j = t.find(';', i); if (j == std::string::npos) j = t.size(); if (j > i) f += " *." + t.substr(i, j - i); i = j + 1; }
        cmd += " --file-filter=" + q(f.c_str() + 1);
    }
    std::string out;
    if (FILE *p = popen((cmd + " 2>/dev/null").c_str(), "r")) { char b[4096]; size_t n; while ((n = fread(b, 1, sizeof b, p)) > 0) out.append(b, n); pclose(p); }
    if (!out.empty() && out.back() != '\n') out += '\n';
    return out.empty() ? 0 : (A)dup_str(out);
}
/* tests drive windows with Win32 messages (UI_INJECT): the ones they use, as ui.cpp's window procedure sees them */
static A inject(Win *w, unsigned msg, uint64_t wp, uint64_t lp) {
    int x = (int16_t)(lp & 0xFFFF), y = (int16_t)(lp >> 16 & 0xFFFF);
    switch (msg) {
    case 0x10: push(ev(w, UI_EV_CLOSE_REQUEST)); return 0;                                  /* WM_CLOSE */
    case 0x100: case 0x101: case 0x104: case 0x105: {                                         /* WM_(SYS)KEYDOWN/UP */
        bool down = msg == 0x100 || msg == 0x104;
        uint32_t m = wp == 0x10 || wp == 0xA0 || wp == 0xA1 ? UI_MOD_SHIFT : wp == 0x11 || wp == 0xA2 || wp == 0xA3 ? UI_MOD_CONTROL
                   : wp == 0x12 || wp == 0xA4 || wp == 0xA5 ? UI_MOD_OPTION : wp == 0x5B || wp == 0x5C ? UI_MOD_COMMAND : 0;
        if (m) g_inject_mods = down ? g_inject_mods | m : g_inject_mods & ~m;
        uint32_t base = wp >= 'A' && wp <= 'Z' ? (uint32_t)(wp + 32) : wp >= '0' && wp <= '9' ? (uint32_t)wp : wp == 0x20 ? ' ' : 0;
        key(w, mac_key_scan((unsigned)(lp >> 16 & 0xFF), lp >> 24 & 1), base, down, down && (lp >> 30 & 1));
        return 0;
    }
    case 0x200: mouse(w, UI_EV_MOUSE_MOVE, x, y, -1); return 0;                               /* WM_MOUSEMOVE */
    case 0x201: case 0x204: case 0x207: mouse(w, UI_EV_MOUSE_DOWN, x, y, msg == 0x201 ? 0 : msg == 0x204 ? 1 : 2); return 0;
    case 0x202: case 0x205: case 0x208: mouse(w, UI_EV_MOUSE_UP, x, y, msg == 0x202 ? 0 : msg == 0x205 ? 1 : 2); return 0;
    case 0x20A: case 0x20E: {                                                                 /* WM_MOUSE(H)WHEEL: screen coordinates */
        int wx = 0, wy = 0; SDL_GetWindowPosition(w->sw, &wx, &wy);
        MwEvent e = ev(w, UI_EV_SCROLL); e.x = x - wx; e.y = y - wy;
        float d = (float)(int16_t)(wp >> 16) / 120;
        if (msg == 0x20A) e.dy = d; else e.dx = -d;
        push(e);
        return 0;
    }
    }
    return -1;
}

static A ui_thread_op(Req *q) {
    switch (q->op) {
    case UI_WINDOW_CREATE: {
        const MwWindowDesc *d = (const MwWindowDesc *)q->a;
        Uint32 fl = SDL_WINDOW_HIDDEN | (d->style & UI_STYLE_RESIZABLE ? SDL_WINDOW_RESIZABLE : 0) | (d->style & UI_STYLE_TITLED ? 0 : SDL_WINDOW_BORDERLESS);
        int x = d->x < -30000 || d->y < -30000 ? (int)SDL_WINDOWPOS_CENTERED : d->x, y = d->x < -30000 || d->y < -30000 ? (int)SDL_WINDOWPOS_CENTERED : d->y;
        SDL_Window *sw = SDL_CreateWindow(d->title ? d->title : "", x, y, d->w > 0 ? d->w : 1, d->h > 0 ? d->h : 1, fl);
        if (!sw) { TRACE("SDL_CreateWindow: %s\n", SDL_GetError()); return 0; }
        Win *w = new Win; w->sw = sw; w->style = d->style;
        { std::lock_guard<std::mutex> l(g_wmu); g_wins.push_back(w); w->id = (uint32_t)g_wins.size(); }
        if (d->visible) SDL_ShowWindow(sw);
        /* the window must exist on the X server before another connection (Vulkan's) names it */
        SDL_SysWMinfo i; SDL_VERSION(&i.version);
        if (SDL_GetWindowWMInfo(sw, &i) && i.subsystem == SDL_SYSWM_X11) { XSync(i.info.x11.display, False);
        }
        return w->id;
    }
    case UI_WINDOW_SET: {
        Win *w = win_by_id((uint32_t)q->a);
        if (!w || !w->sw) return -1;
        switch (q->b) {
        case UI_W_TITLE: SDL_SetWindowTitle(w->sw, q->c ? (const char *)q->c : ""); return 0;
        case UI_W_FRAME: SDL_SetWindowPosition(w->sw, (int)q->c, (int)q->d); SDL_SetWindowSize(w->sw, (int)(q->e & 0xFFFFFFFF), (int)(q->e >> 32)); return 0;
        case UI_W_SHOW:
            if (!q->c) SDL_HideWindow(w->sw);
            else { SDL_ShowWindow(w->sw); if (q->c == 2) SDL_RaiseWindow(w->sw); }
            redraw(w);
            return 0;
        case UI_W_CLOSE: SDL_DestroyWindow(w->sw); w->sw = nullptr; return 0;
        case UI_W_MINIMIZE: if (q->c) SDL_MinimizeWindow(w->sw); else SDL_RestoreWindow(w->sw); return 0;
        case UI_W_FULLSCREEN:
            if ((q->c != 0) != w->fullscreen) {
                w->fullscreen = q->c != 0;
                SDL_SetWindowFullscreen(w->sw, w->fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);
                MwEvent e = ev(w, UI_EV_FULLSCREEN); e.a = w->fullscreen; push(e);
            }
            return 0;
        case UI_W_MIN_SIZE: SDL_SetWindowMinimumSize(w->sw, (int)q->c, (int)q->d); return 0;
        case UI_W_MAX_SIZE: SDL_SetWindowMaximumSize(w->sw, q->c ? (int)q->c : 16384, q->d ? (int)q->d : 16384); return 0;
        case UI_W_ASPECT: return 0;   /* ponytail: SDL2 has no aspect constraint */
        case UI_W_STYLE:
            w->style = (uint32_t)q->c;
            SDL_SetWindowBordered(w->sw, w->style & UI_STYLE_TITLED ? SDL_TRUE : SDL_FALSE);
            SDL_SetWindowResizable(w->sw, w->style & UI_STYLE_RESIZABLE ? SDL_TRUE : SDL_FALSE);
            return 0;
        case UI_W_CURSOR_HIDDEN: w->cursor_hidden = q->c != 0; return 0;
        case UI_W_TRANSPARENT: return 0;   /* ponytail: opaque */
        }
        return -1;
    }
    case UI_WINDOW_INFO: {
        Win *w = win_by_id((uint32_t)q->a);
        MwWindowInfo *o = (MwWindowInfo *)q->b;
        memset(o, 0, sizeof *o);
        if (!w || !w->sw) return -1;
        SDL_GetWindowPosition(w->sw, &o->x, &o->y); SDL_GetWindowSize(w->sw, &o->w, &o->h);
        int t = 0, l = 0, b = 0, r = 0; SDL_GetWindowBordersSize(w->sw, &t, &l, &b, &r);
        o->fx = o->x - l; o->fy = o->y - t; o->fw = o->w + l + r; o->fh = o->h + t + b;
        Uint32 f = SDL_GetWindowFlags(w->sw);
        o->dpi = 96; o->key = (f & SDL_WINDOW_INPUT_FOCUS) != 0; o->visible = (f & SDL_WINDOW_SHOWN) && !(f & SDL_WINDOW_HIDDEN);
        o->minimized = (f & SDL_WINDOW_MINIMIZED) != 0; o->zoomed = (f & SDL_WINDOW_MAXIMIZED) != 0; o->fullscreen = w->fullscreen;
        return 0;
    }
    case UI_SCREEN: {
        int n = SDL_GetNumVideoDisplays(); if (n < 1) n = 0;
        if (q->a < 0 || q->a >= n) return n;
        MwScreen *s = (MwScreen *)q->b; memset(s, 0, sizeof *s);
        SDL_Rect r, u; SDL_GetDisplayBounds((int)q->a, &r); if (SDL_GetDisplayUsableBounds((int)q->a, &u)) u = r;
        s->x = r.x; s->y = r.y; s->w = r.w; s->h = r.h; s->vx = u.x; s->vy = u.y; s->vw = u.w; s->vh = u.h;
        s->dpi = 96; s->primary = q->a == 0;
        SDL_DisplayMode m; s->refresh_mhz = !SDL_GetCurrentDisplayMode((int)q->a, &m) && m.refresh_rate > 1 ? (uint32_t)m.refresh_rate * 1000 : 60000;
        const char *nm = SDL_GetDisplayName((int)q->a); snprintf(s->name, sizeof s->name, "%s", nm ? nm : "screen");
        return n;
    }
    case UI_MENU: {   /* kept for a menu bar to come */
        const MwMenuItem *it = (const MwMenuItem *)q->a;
        g_menu.assign(it, it + q->b); g_menu_strings.clear();
        return 0;
    }
    case UI_CURSOR:
        if (q->a == 0) { SDL_ShowCursor(SDL_DISABLE); return 0; }
        if (q->a == 1) { SDL_ShowCursor(SDL_ENABLE); return 0; }
        if (q->a == 2) { SDL_WarpMouseGlobal((int)q->b, (int)q->c); return 0; }
        if (q->a == 3) { g_relative = q->b == 0; SDL_SetRelativeMouseMode(g_relative ? SDL_TRUE : SDL_FALSE); return 0; }
        return -1;
    case UI_MOUSE_POS: { int x, y; Uint32 b = SDL_GetGlobalMouseState(&x, &y); ((int32_t *)q->a)[0] = x; ((int32_t *)q->a)[1] = y;
                         return (b & SDL_BUTTON_LMASK ? 1 : 0) | (b & SDL_BUTTON_RMASK ? 2 : 0) | (b & SDL_BUTTON_MMASK ? 4 : 0); }
    case UI_INJECT: { Win *w = win_by_id((uint32_t)q->a); return w && w->sw ? inject(w, (unsigned)q->b, (uint64_t)q->c, (uint64_t)q->d) : -1; }
    case UI_FILE_DIALOG: return file_dialog((const MwFileDialog *)q->a);
    case UI_POPUP_MENU: { std::lock_guard<std::mutex> l(g_test_mu); A r = g_test_popup >= 0 ? g_test_popup : 0; g_test_popup = -1; return r; }   /* ponytail: no menu UI yet */
    case UI_STATUS_ITEM: {
        int id = (int)q->a;
        if (!q->b) return g_trays.erase(id) ? 1 : 0;
        Tray &t = g_trays[id];
        const MwImage *img = (const MwImage *)q->c;
        if (img && img->w && img->h) { t.w = img->w; t.h = img->h; t.px.assign((const uint32_t *)img->pixels, (const uint32_t *)img->pixels + (size_t)img->w * img->h); }
        if (q->d) t.tip = (const char *)q->d;
        return 1;
    }
    case UI_TEST: {   /* 4: click status item b with button c, 5: its icon into MwImage *c */
        auto it = g_trays.find((int)q->b);
        if (it == g_trays.end()) return 0;
        if (q->a == 4) { MwEvent e{}; e.type = UI_EV_STATUS; e.a = (uint32_t)q->b; e.button = (uint32_t)q->c; e.x = 0; e.y = 0; e.dx = 24; e.dy = 24; push(e); }
        else { MwImage *o = (MwImage *)q->c; o->w = it->second.w; o->h = it->second.h; o->pixels = malloc(it->second.px.size() * 4 + 1);
               memcpy(o->pixels, it->second.px.data(), it->second.px.size() * 4); }
        return 1;
    }
    case UI_PAD: {
        MwPad *p = (MwPad *)q->b; SDL_GameController *c = g_pads[q->a];
        if (!c) return 0;
        memset(p, 0, sizeof *p);
        static const struct { SDL_GameControllerButton b; uint32_t m; } map[] = {
            {SDL_CONTROLLER_BUTTON_A, UI_PAD_A}, {SDL_CONTROLLER_BUTTON_B, UI_PAD_B}, {SDL_CONTROLLER_BUTTON_X, UI_PAD_X}, {SDL_CONTROLLER_BUTTON_Y, UI_PAD_Y},
            {SDL_CONTROLLER_BUTTON_LEFTSHOULDER, UI_PAD_LB}, {SDL_CONTROLLER_BUTTON_RIGHTSHOULDER, UI_PAD_RB}, {SDL_CONTROLLER_BUTTON_LEFTSTICK, UI_PAD_LS},
            {SDL_CONTROLLER_BUTTON_RIGHTSTICK, UI_PAD_RS}, {SDL_CONTROLLER_BUTTON_START, UI_PAD_MENU}, {SDL_CONTROLLER_BUTTON_BACK, UI_PAD_VIEW},
            {SDL_CONTROLLER_BUTTON_DPAD_UP, UI_PAD_UP}, {SDL_CONTROLLER_BUTTON_DPAD_DOWN, UI_PAD_DOWN}, {SDL_CONTROLLER_BUTTON_DPAD_LEFT, UI_PAD_LEFT},
            {SDL_CONTROLLER_BUTTON_DPAD_RIGHT, UI_PAD_RIGHT}, {SDL_CONTROLLER_BUTTON_GUIDE, UI_PAD_HOME}};
        for (auto &m : map) if (SDL_GameControllerGetButton(c, m.b)) p->buttons |= m.m;
        auto ax = [&](SDL_GameControllerAxis a, bool flip) { float v = SDL_GameControllerGetAxis(c, a) / 32767.0f; if (v > -0.24f && v < 0.24f) v = 0; v = v < -1 ? -1 : v > 1 ? 1 : v; return flip ? -v : v; };
        p->lx = ax(SDL_CONTROLLER_AXIS_LEFTX, false); p->ly = ax(SDL_CONTROLLER_AXIS_LEFTY, true);
        p->rx = ax(SDL_CONTROLLER_AXIS_RIGHTX, false); p->ry = ax(SDL_CONTROLLER_AXIS_RIGHTY, true);
        p->lt = ax(SDL_CONTROLLER_AXIS_TRIGGERLEFT, false); p->rt = ax(SDL_CONTROLLER_AXIS_TRIGGERRIGHT, false);
        snprintf(p->name, sizeof p->name, "%s", SDL_GameControllerName(c) ? SDL_GameControllerName(c) : "Controller");
        p->has_rumble = SDL_GameControllerHasRumble(c);
        return 1;
    }
    case UI_RUMBLE: return g_pads[q->a] ? SDL_GameControllerRumble(g_pads[q->a], (Uint16)q->b, (Uint16)q->c, 1000) : -1;
    case UI_CLIPBOARD:
        if (q->a == 0) { char *t = SDL_GetClipboardText(); A r = t ? (A)dup_str(t) : 0; SDL_free(t); return r; }
        SDL_SetClipboardText(q->b ? (const char *)q->b : "");
        return 0;
    case UI_PRESENT: {
        Win *w = win_by_id((uint32_t)q->a);
        if (!w || !w->sw) return -1;
        redraw(w);
        return 0;
    }
    }
    return -1;
}

/* ======================================================================= audio (SDL), a null sink without a device */
struct Stream {
    SDL_AudioDeviceID dev = 0;
    int channels = 2, rate = 48000; uint32_t buf_frames = 0;
    bool null_sink = true, started = false;
    uint64_t null_t0 = 0, null_written = 0;
    std::mutex mu;
};
static std::mutex g_amu;
static std::vector<Stream *> g_streams;
static A audio_open(A rate, A channels) {
    Stream *s = new Stream; s->rate = (int)rate; s->channels = (int)channels; s->buf_frames = (uint32_t)(rate / 25);   /* 40 ms */
    if (!getenv("SCION_AUDIO_NULL")) {
        static std::once_flag once; static bool ok;
        std::call_once(once, [] { ok = SDL_InitSubSystem(SDL_INIT_AUDIO) == 0; });
        SDL_AudioSpec want{}, got{};
        want.freq = (int)rate; want.format = AUDIO_F32SYS; want.channels = (Uint8)channels; want.samples = 512;
        if (ok && (s->dev = SDL_OpenAudioDevice(nullptr, 0, &want, &got, 0))) s->null_sink = false;
    }
    if (s->null_sink) TRACE("audio: no device, output discarded\n");
    std::lock_guard<std::mutex> l(g_amu);
    g_streams.push_back(s);
    return (A)g_streams.size();
}
static Stream *stream(A id) { std::lock_guard<std::mutex> l(g_amu); return id > 0 && id <= (A)g_streams.size() ? g_streams[id - 1] : nullptr; }
static uint64_t queued(Stream *s) {
    if (!s->null_sink) return SDL_GetQueuedAudioSize(s->dev) / (4 * (uint32_t)s->channels);
    if (!s->started) return s->null_written;
    uint64_t played = (now_ns() - s->null_t0) * (uint64_t)s->rate / 1000000000ull;
    return s->null_written > played ? s->null_written - played : 0;
}
static A audio_write(A id, const float *data, A frames) {
    Stream *s = stream(id);
    if (!s) return -1;
    A done = 0;
    while (done < frames) {
        std::unique_lock<std::mutex> l(s->mu);
        uint64_t q = queued(s);
        if (q >= s->buf_frames) {
            if (!s->started) return done;   /* nothing drains a stopped stream */
            l.unlock(); struct timespec t = {0, 2000000}; nanosleep(&t, nullptr); continue;
        }
        A n = std::min<A>(frames - done, (A)(s->buf_frames - q));
        if (s->null_sink) { if (s->started && !q) { s->null_t0 = now_ns(); s->null_written = 0; } s->null_written += (uint64_t)n; }
        else SDL_QueueAudio(s->dev, data + done * s->channels, (Uint32)(n * 4 * s->channels));
        done += n;
    }
    return done;
}
static A audio_ctl(A id, A op) {
    Stream *s = stream(id);
    if (!s) return -1;
    std::lock_guard<std::mutex> l(s->mu);
    switch (op) {
    case 0: if (!s->started) { if (s->null_sink) s->null_t0 = now_ns(); else SDL_PauseAudioDevice(s->dev, 0); s->started = true; } return 0;
    case 1: if (s->started && !s->null_sink) SDL_PauseAudioDevice(s->dev, 1); s->started = false;
            if (s->null_sink) s->null_written = 0; else SDL_ClearQueuedAudio(s->dev);
            return 0;
    case 2: if (!s->null_sink) SDL_CloseAudioDevice(s->dev); s->dev = 0; s->null_sink = true; s->started = false; s->null_written = 0; return 0;
    case 3: return (A)queued(s);
    case 4: return s->rate;
    case 5: return s->null_sink;
    }
    return -1;
}

/* ======================================================================= text (FreeType + fontconfig) */
static std::mutex g_tmu;
static FT_Library g_ft;
static FT_Face text_face(const char *name, int px, int weight, bool italic, bool mono) {
    static std::map<std::string, FT_Face> cache;
    std::string n = name ? name : "";
    auto has = [&](const char *k) { return n.find(k) != std::string::npos; };
    const char *family = mono || has("Mono") || has("Menlo") || has("Courier") || has("Monaco") ? "monospace"
                       : has("Times") || has("Georgia") || has("Serif") ? "serif" : "sans-serif";
    if (has("Bold") && weight < 700) weight = 700;
    if (has("Semibold") && weight < 600) weight = 600;
    if (has("Italic") || has("Oblique")) italic = true;
    std::string key = std::string(family) + "/" + std::to_string(weight) + (italic ? "/i" : "");
    FT_Face f = cache.count(key) ? cache[key] : nullptr;
    if (!f) {
        if (!g_ft && FT_Init_FreeType(&g_ft)) return nullptr;
        FcPattern *p = FcNameParse((const FcChar8 *)family);
        FcPatternAddInteger(p, FC_WEIGHT, FcWeightFromOpenType(weight));
        FcPatternAddInteger(p, FC_SLANT, italic ? FC_SLANT_ITALIC : FC_SLANT_ROMAN);
        FcConfigSubstitute(nullptr, p, FcMatchPattern); FcDefaultSubstitute(p);
        FcResult r; FcPattern *m = FcFontMatch(nullptr, p, &r);
        FcChar8 *file = nullptr; int index = 0;
        if (m && FcPatternGetString(m, FC_FILE, 0, &file) == FcResultMatch) {
            FcPatternGetInteger(m, FC_INDEX, 0, &index);
            if (FT_New_Face(g_ft, (const char *)file, index, &f)) f = nullptr;
        }
        if (m) FcPatternDestroy(m);
        FcPatternDestroy(p);
        if (!f) return nullptr;
        cache[key] = f;
    }
    FT_Set_Pixel_Sizes(f, 0, (FT_UInt)px);
    return f;
}
static uint32_t next_cp(const unsigned char *&s) {
    uint32_t c = *s++;
    if (c < 0x80) return c;
    int n = c >= 0xF0 ? 3 : c >= 0xE0 ? 2 : 1; c &= 0x3F >> n;
    while (n-- && (*s & 0xC0) == 0x80) c = c << 6 | (*s++ & 0x3F);
    return c;
}
static A text_op(MwText *t) {
    std::lock_guard<std::mutex> l(g_tmu);
    int px = std::max(1, (int)(t->size + 0.5f));
    FT_Face f = text_face(t->font, px, t->weight ? (int)t->weight : 400, t->flags & UI_TEXT_ITALIC, t->flags & UI_TEXT_MONO);
    if (!f) return 0;
    int asc = (int)(f->size->metrics.ascender >> 6), desc = (int)(-f->size->metrics.descender >> 6);
    long width = 0;   /* 26.6 */
    for (const unsigned char *s = (const unsigned char *)t->text; s && *s;) {
        if (!FT_Load_Char(f, next_cp(s), FT_LOAD_DEFAULT)) width += f->glyph->advance.x;
    }
    t->width = (float)width / 64; t->ascent = (float)asc; t->descent = (float)desc;
    t->pad = (uint32_t)(px / 4 + 2);
    t->w = (uint32_t)((width + 63) >> 6) + 2 * t->pad; t->h = (uint32_t)(asc + desc);
    if (t->mask && t->w && t->h) {
        memset(t->mask, 0, (size_t)t->w * t->h);
        long pen = (long)t->pad << 6;
        for (const unsigned char *s = (const unsigned char *)t->text; *s;) {
            if (FT_Load_Char(f, next_cp(s), FT_LOAD_RENDER)) continue;
            FT_Bitmap &b = f->glyph->bitmap;
            int x0 = (int)(pen >> 6) + f->glyph->bitmap_left, y0 = asc - f->glyph->bitmap_top;
            for (unsigned r = 0; r < b.rows; r++) for (unsigned c = 0; c < b.width; c++) {
                int x = x0 + (int)c, y = y0 + (int)r;
                if (x < 0 || y < 0 || x >= (int)t->w || y >= (int)t->h) continue;
                uint8_t v = b.buffer[r * b.pitch + c], &d = t->mask[(size_t)y * t->w + x];
                if (v > d) d = v;
            }
            pen += f->glyph->advance.x;
        }
    }
    return 1;
}

/* ======================================================================= images: PNG (libpng), JPEG (libjpeg) */
static void to_premul_bgra(uint8_t *p, size_t n) {   /* straight RGBA -> premultiplied BGRA */
    for (size_t i = 0; i < n; i++, p += 4) { uint8_t r = p[0], g = p[1], b = p[2], a = p[3]; p[0] = (uint8_t)(b * a / 255); p[1] = (uint8_t)(g * a / 255); p[2] = (uint8_t)(r * a / 255); }
}
static A image_decode(const void *data, A size, MwImage *out) {
    if (!data || size < 8) return 0;
    const uint8_t *d = (const uint8_t *)data;
    if (!memcmp(d, "\x89PNG", 4)) {
        png_image im{}; im.version = PNG_IMAGE_VERSION;
        if (!png_image_begin_read_from_memory(&im, data, (size_t)size)) return 0;
        im.format = PNG_FORMAT_RGBA;
        uint8_t *px = (uint8_t *)malloc(PNG_IMAGE_SIZE(im));
        if (!px || !png_image_finish_read(&im, nullptr, px, 0, nullptr)) { free(px); png_image_free(&im); return 0; }
        to_premul_bgra(px, (size_t)im.width * im.height);
        out->w = im.width; out->h = im.height; out->pixels = px;
        return 1;
    }
    if (d[0] == 0xFF && d[1] == 0xD8) {
        jpeg_decompress_struct c; jpeg_error_mgr e; c.err = jpeg_std_error(&e);
        e.error_exit = [](j_common_ptr) { throw 1; };
        uint8_t *px = nullptr;
        try {
            jpeg_create_decompress(&c);
            jpeg_mem_src(&c, (const unsigned char *)data, (unsigned long)size);
            jpeg_read_header(&c, TRUE);
            c.out_color_space = JCS_EXT_BGRA;
            jpeg_start_decompress(&c);
            px = (uint8_t *)malloc((size_t)c.output_width * c.output_height * 4);
            while (c.output_scanline < c.output_height) { uint8_t *row = px + (size_t)c.output_scanline * c.output_width * 4; jpeg_read_scanlines(&c, &row, 1); }
            jpeg_finish_decompress(&c);
            out->w = c.output_width; out->h = c.output_height; out->pixels = px;
            jpeg_destroy_decompress(&c);
            return 1;
        } catch (int) { free(px); jpeg_destroy_decompress(&c); return 0; }
    }
    return 0;   /* ponytail: BMP, TIFF and GIF */
}
static A image_encode(const MwImage *img, A type, float quality, uint64_t *size) {
    if (!img || !img->w || !img->h) return 0;
    size_t n = (size_t)img->w * img->h;
    std::vector<uint8_t> rgba(n * 4);
    const uint8_t *s = (const uint8_t *)img->pixels;
    for (size_t i = 0; i < n; i++) {   /* premultiplied BGRA -> straight RGBA */
        uint8_t a = s[i * 4 + 3];
        for (int k = 0; k < 3; k++) rgba[i * 4 + k] = a ? (uint8_t)std::min(255, s[i * 4 + 2 - k] * 255 / a) : 0;
        rgba[i * 4 + 3] = a;
    }
    if (type == UI_IMG_JPEG) {
        jpeg_compress_struct c; jpeg_error_mgr e; c.err = jpeg_std_error(&e);
        unsigned char *buf = nullptr; unsigned long len = 0;
        jpeg_create_compress(&c); jpeg_mem_dest(&c, &buf, &len);
        c.image_width = img->w; c.image_height = img->h; c.input_components = 4; c.in_color_space = JCS_EXT_RGBA;
        jpeg_set_defaults(&c); jpeg_set_quality(&c, (int)((quality > 0 && quality <= 1 ? quality : 0.9f) * 100), TRUE);
        jpeg_start_compress(&c, TRUE);
        while (c.next_scanline < c.image_height) { uint8_t *row = &rgba[(size_t)c.next_scanline * img->w * 4]; jpeg_write_scanlines(&c, &row, 1); }
        jpeg_finish_compress(&c); jpeg_destroy_compress(&c);
        void *out = malloc(len); memcpy(out, buf, len); free(buf);
        *size = len; return (A)out;
    }
    png_image im{}; im.version = PNG_IMAGE_VERSION; im.width = img->w; im.height = img->h; im.format = PNG_FORMAT_RGBA;   /* PNG for the other types too */
    png_alloc_size_t len = 0;
    if (!png_image_write_to_memory(&im, nullptr, &len, 0, rgba.data(), 0, nullptr)) return 0;
    void *out = malloc(len);
    if (!png_image_write_to_memory(&im, out, &len, 0, rgba.data(), 0, nullptr)) { free(out); return 0; }
    *size = len; return (A)out;
}

/* ======================================================================= Metal layers: the X11 window behind an SDL window */
static void nw_size(void *ctx, uint32_t *w, uint32_t *h) { int a = 0, b = 0; if (((Win *)ctx)->sw) SDL_GetWindowSizeInPixels(((Win *)ctx)->sw, &a, &b); *w = (uint32_t)a; *h = (uint32_t)b; }
static void nw_set_size(void *ctx, uint32_t w, uint32_t h) {
    Win *win = (Win *)ctx; int x = 0, y = 0;
    if (win->sw) SDL_GetWindowPosition(win->sw, &x, &y);
    on_ui(UI_WINDOW_SET, win->id, UI_W_FRAME, x, y, (A)w | (A)h << 32);
}
bool ui_native_window(uint64_t sdl_window, uint32_t w, uint32_t h, const char *title, MwNativeWindow *out) {
    Win *win = nullptr;
    bool own = !sdl_window;
    if (own) {   /* a CAMetalLayer without an AppKit window: one of its own */
        MwWindowDesc d{-32001, -32001, (int32_t)(w ? w : 640), (int32_t)(h ? h : 480), UI_STYLE_TITLED | UI_STYLE_CLOSABLE | UI_STYLE_RESIZABLE | UI_STYLE_NOMENU, 1, title};
        win = win_by_id((uint32_t)on_ui(UI_WINDOW_CREATE, (A)&d));
    } else { std::lock_guard<std::mutex> l(g_wmu); for (Win *x : g_wins) if (x->sw == (SDL_Window *)sdl_window) win = x; }
    SDL_Window *s = win ? win->sw : nullptr;
    if (!s) return false;
    SDL_SysWMinfo i; SDL_VERSION(&i.version);
    if (!SDL_GetWindowWMInfo(s, &i) || i.subsystem != SDL_SYSWM_X11) { fprintf(stderr, "scion: Metal needs an X11 window\n"); return false; }
    /* Vulkan gets a connection of its own: SDL's belongs to the UI thread */
    static Display *dpy = XOpenDisplay(nullptr);
    if (!dpy) return false;
    *out = MwNativeWindow{dpy, (uint64_t)i.info.x11.window, nw_size, nullptr, own ? nw_set_size : nullptr, win};
    return true;
}

/* ======================================================================= the hostcall */
HCABI A hc_ui(A op, A a, A b, A c, A d, A e) {
    switch (op) {
    case UI_NEXT_EVENT: ui_start(); return next_event((MwEvent *)a, (int64_t)b);
    case UI_WAKE: { std::lock_guard<std::mutex> l(g_qmu); g_woken = true; } g_qcv.notify_all(); return 0;
    case UI_WINDOW_CREATE: case UI_WINDOW_SET: case UI_WINDOW_INFO: case UI_SCREEN: case UI_MENU: case UI_CURSOR: case UI_MOUSE_POS:
    case UI_INJECT: case UI_FILE_DIALOG: case UI_POPUP_MENU: case UI_STATUS_ITEM: case UI_CLIPBOARD:
        return on_ui((int)op, a, b, c, d, e);
    case UI_WINDOW_HWND: { Win *w = win_by_id((uint32_t)a); return w ? (A)w->sw : 0; }   /* the SDL_Window, for a Linux Metal host */
    case UI_MENU_STATE: return 0;
    case UI_PAD:
        if (a < 0 || a > 3) return 0;
        if (g_virtual_on[a]) { *(MwPad *)b = g_virtual[a]; return 1; }
        return on_ui(UI_PAD, a, b);
    case UI_RUMBLE:
        if (a < 0 || a > 3) return -1;
        g_rumble_seen[a][0] = (uint16_t)b; g_rumble_seen[a][1] = (uint16_t)c;
        return g_virtual_on[a] ? 0 : on_ui(UI_RUMBLE, a, b, c);
    case UI_PAD_INJECT:
        if (a < 0 || a > 3) return -1;
        if (b) { g_virtual[a] = *(const MwPad *)b; g_virtual_on[a] = true; } else g_virtual_on[a] = false;
        return ((A)g_rumble_seen[a][0] << 16) | g_rumble_seen[a][1];   /* tests read the last rumble back */
    case UI_RAW_NEXT: {
        ui_start(); g_raw_on = true;
        std::unique_lock<std::mutex> l(g_rmu);
        auto ready = [] { return !g_raw.empty(); };
        if ((int64_t)b < 0) g_rcv.wait(l, ready); else g_rcv.wait_for(l, std::chrono::nanoseconds(b), ready);
        if (g_raw.empty()) return 0;
        *(MwRaw *)a = g_raw.front(); g_raw.pop_front();
        return 1;
    }
    case UI_RAW_INJECT: g_raw_on = true; raw_push(*(const MwRaw *)a); return 0;
    case UI_AUDIO_OPEN: return audio_open(a, b);
    case UI_AUDIO_WRITE: return audio_write(a, (const float *)b, c);
    case UI_AUDIO_CTL: return audio_ctl(a, b);
    case UI_VSYNC_WAIT: {   /* ponytail: paced by the clock at the screen's refresh rate */
        MwScreen s; A mhz = on_ui(UI_SCREEN, 0, (A)&s) > 0 ? s.refresh_mhz : 60000;
        uint64_t period = 1000000000000ull / (uint64_t)mhz, t = now_ns();
        static thread_local uint64_t last;
        uint64_t next = last && t - last < period ? last + period : t;
        if (next > t) { struct timespec ts = {0, (long)(next - t)}; nanosleep(&ts, nullptr); }
        last = now_ns();
        return mhz;
    }
    case UI_ALERT: {
        ui_start();
        SDL_MessageBoxButtonData bt[3] = {{SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT, 0, d >= 3 ? "Yes" : "OK"}, {0, 1, d >= 3 ? "No" : "Cancel"}, {SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT, 2, "Cancel"}};
        Uint32 fl = c == 2 ? SDL_MESSAGEBOX_ERROR : c == 1 ? SDL_MESSAGEBOX_WARNING : SDL_MESSAGEBOX_INFORMATION;
        SDL_MessageBoxData md{fl, nullptr, a ? (const char *)a : "", b ? (const char *)b : "", d < 1 ? 1 : d > 3 ? 3 : (int)d, bt, nullptr};
        int r = 0; SDL_ShowMessageBox(&md, &r);
        return r < 0 ? (d >= 3 ? 2 : d == 2 ? 1 : 0) : r;
    }
    case UI_FREE: free((void *)a); return 0;
    case UI_TEXT: return text_op((MwText *)a);
    case UI_IMAGE_DECODE: return image_decode((const void *)a, b, (MwImage *)c);
    case UI_IMAGE_ENCODE: { float q; memcpy(&q, &c, sizeof q); return image_encode((const MwImage *)a, b, q, (uint64_t *)d); }
    case UI_PRESENT: {
        Win *w = win_by_id((uint32_t)a);
        if (!w) return -1;
        { std::lock_guard<std::mutex> l(w->pmu);
          const MwImage *img = (const MwImage *)b;
          if (!img) { w->pw = w->ph = 0; w->px.clear(); return 0; }
          w->px.assign((const uint32_t *)img->pixels, (const uint32_t *)img->pixels + (size_t)img->w * img->h);
          w->pw = (int)img->w; w->ph = (int)img->h; }
        return on_ui(UI_PRESENT, a);
    }
    case UI_TEST: {
        if (a == 4 || a == 5) return on_ui(UI_TEST, a, b, c);
        std::lock_guard<std::mutex> l(g_test_mu);
        if (a == 1) { g_test_dialog = b ? (const char *)b : ""; g_test_dialog_set = true; }
        else if (a == 2) g_test_popup = (int)b;
        else if (a == 3) {   /* what window b shows (UI_PRESENT) -> MwImage *c, pixels malloc'd (UI_FREE) */
            Win *w = win_by_id((uint32_t)b);
            if (!w) return 0;
            std::lock_guard<std::mutex> lk(w->pmu);
            if (!w->pw) return 0;
            MwImage *o = (MwImage *)c; o->w = (uint32_t)w->pw; o->h = (uint32_t)w->ph; o->pixels = malloc(w->px.size() * 4);
            memcpy(o->pixels, w->px.data(), w->px.size() * 4);
            return 1;
        }
        return 0;
    }
    }
    return -38;
}
