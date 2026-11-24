/* ui.cpp — host half of AppKit, GameController and AudioToolbox (hostcall "ui", see uibridge.h).
 * Windows live on one host UI thread with its own message loop, so they stay responsive whatever the guest does;
 * their input becomes MwEvents in a queue the guest drains (NSApplication's event loop). Controllers: XInput.
 * Sound: WASAPI shared mode (float32, the system converts rate and channels), or a null sink without a device. */
#include "scion.h"
#include "uibridge.h"
#include <windowsx.h>
#include <dwmapi.h>
#include <xinput.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <wincodec.h>
#include <algorithm>
#include <atomic>
#include <deque>
#include <mutex>
#include <thread>

/* ======================================================================= event queue */
static std::mutex g_qmu;
static std::deque<MwEvent> g_queue;
static HANDLE g_qev; /* auto-reset: something was queued (or UI_WAKE) */
static uint64_t now_ns() { LARGE_INTEGER f, c; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&c); return (uint64_t)((double)c.QuadPart * 1e9 / (double)f.QuadPart); }
static void push(MwEvent e) {
    e.time_ns = now_ns();
    { std::lock_guard<std::mutex> l(g_qmu); g_queue.push_back(e); }
    SetEvent(g_qev);
}
static A next_event(MwEvent *out, int64_t timeout_ns) {
    uint64_t deadline = timeout_ns < 0 ? UINT64_MAX : now_ns() + (uint64_t)timeout_ns;
    for (;;) {
        {
            std::lock_guard<std::mutex> l(g_qmu);
            if (!g_queue.empty()) { *out = g_queue.front(); g_queue.pop_front(); return 1; }
        }
        uint64_t t = now_ns();
        if (t >= deadline) return 0;
        DWORD ms = deadline == UINT64_MAX ? INFINITE : (DWORD)((deadline - t + 999999) / 1000000);
        if (WaitForSingleObject(g_qev, ms) == WAIT_OBJECT_0) {
            std::lock_guard<std::mutex> l(g_qmu);
            if (g_queue.empty()) return 0; /* UI_WAKE */
        }
    }
}

/* ======================================================================= keyboard: scan code -> Mac key code */
static uint8_t mac_key(UINT scan, bool ext) {
    static const uint8_t base[0x59] = {
        0xFF, 0x35, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x1B, 0x18, 0x33, 0x30, /* 00 */
        0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23, 0x21, 0x1E, 0x24, 0x3B, 0x00, 0x01, /* 10 */
        0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25, 0x29, 0x27, 0x32, 0x38, 0x2A, 0x06, 0x07, 0x08, 0x09, /* 20 */
        0x0B, 0x2D, 0x2E, 0x2B, 0x2F, 0x2C, 0x3C, 0x43, 0x3A, 0x31, 0x39, 0x7A, 0x78, 0x63, 0x76, 0x60, /* 30 */
        0x61, 0x62, 0x64, 0x65, 0x6D, 0x47, 0xFF, 0x59, 0x5B, 0x5C, 0x4E, 0x56, 0x57, 0x58, 0x45, 0x53, /* 40 */
        0x54, 0x55, 0x52, 0x41, 0xFF, 0xFF, 0x0A, 0x67, 0x6F,                                             /* 50 */
    };
    if (ext) switch (scan) {
        case 0x1C: return 0x4C; case 0x1D: return 0x3E; case 0x35: return 0x4B; case 0x38: return 0x3D;
        case 0x47: return 0x73; case 0x48: return 0x7E; case 0x49: return 0x74; case 0x4B: return 0x7B;
        case 0x4D: return 0x7C; case 0x4F: return 0x77; case 0x50: return 0x7D; case 0x51: return 0x79;
        case 0x52: return 0x72; case 0x53: return 0x75; case 0x5B: return 0x37; case 0x5C: return 0x36;
        case 0x5D: return 0x6E; default: return 0xFF;
    }
    if (scan == 0x64) return 0x69; /* F13 */
    return scan < sizeof base ? base[scan] : 0xFF;
}
static uint32_t modifiers() {
    uint32_t m = 0;
    if (GetKeyState(VK_SHIFT) & 0x8000) m |= UI_MOD_SHIFT;
    if (GetKeyState(VK_CONTROL) & 0x8000) m |= UI_MOD_CONTROL;
    if (GetKeyState(VK_MENU) & 0x8000) m |= UI_MOD_OPTION;
    if ((GetKeyState(VK_LWIN) | GetKeyState(VK_RWIN)) & 0x8000) m |= UI_MOD_COMMAND;
    if (GetKeyState(VK_CAPITAL) & 1) m |= UI_MOD_CAPS;
    return m;
}
static void utf8(const wchar_t *w, int n, char *out, size_t cap) {
    int k = n > 0 ? WideCharToMultiByte(CP_UTF8, 0, w, n, out, (int)cap - 1, nullptr, nullptr) : 0;
    out[k < 0 ? 0 : k] = 0;
}
/* characters a key produces: with the current modifiers and with only Shift (charactersIgnoringModifiers) */
static void key_chars(UINT vk, UINT scan, char *chars, char *nomod) {
    BYTE st[256];
    GetKeyboardState(st);
    wchar_t w[8];
    int n;
    /* Mac function keys produce private-use characters; the common ones */
    static const struct { UINT vk; wchar_t c; } fn[] = {{VK_UP, 0xF700}, {VK_DOWN, 0xF701}, {VK_LEFT, 0xF702}, {VK_RIGHT, 0xF703},
        {VK_F1, 0xF704}, {VK_F2, 0xF705}, {VK_F3, 0xF706}, {VK_F4, 0xF707}, {VK_F5, 0xF708}, {VK_F6, 0xF709}, {VK_F7, 0xF70A},
        {VK_F8, 0xF70B}, {VK_F9, 0xF70C}, {VK_F10, 0xF70D}, {VK_F11, 0xF70E}, {VK_F12, 0xF70F}, {VK_INSERT, 0xF727},
        {VK_DELETE, 0xF728}, {VK_HOME, 0xF729}, {VK_END, 0xF72B}, {VK_PRIOR, 0xF72C}, {VK_NEXT, 0xF72D}};
    for (auto &f : fn) if (f.vk == vk) { utf8(&f.c, 1, chars, 16); utf8(&f.c, 1, nomod, 16); return; }
    if (vk == VK_BACK) { wchar_t c = 0x7F; utf8(&c, 1, chars, 16); utf8(&c, 1, nomod, 16); return; } /* Mac: Delete */
    if (vk == VK_RETURN) { wchar_t c = '\r'; utf8(&c, 1, chars, 16); utf8(&c, 1, nomod, 16); return; }
    n = ToUnicodeEx(vk, scan, st, w, 8, 4 /* no keyboard state change */, GetKeyboardLayout(0));
    utf8(w, n, chars, 16);
    BYTE st2[256] = {0};
    st2[VK_SHIFT] = st[VK_SHIFT]; st2[VK_CAPITAL] = st[VK_CAPITAL];
    n = ToUnicodeEx(vk, scan, st2, w, 8, 4, GetKeyboardLayout(0));
    utf8(w, n, nomod, 16);
}

/* ======================================================================= windows */
#define WM_LAYERED_UPDATE (WM_APP + 2)
struct Win {
    uint32_t id;
    HWND hwnd = nullptr;
    uint32_t style = 0;
    int minw = 0, minh = 0, maxw = 0, maxh = 0, aspw = 0, asph = 0;
    bool fullscreen = false, cursor_hidden = false, tracking = false;
    RECT saved{}; LONG saved_style = 0;
    int lastx = INT32_MIN, lasty = INT32_MIN;
    int clicks = 0; uint64_t last_click = 0; int click_btn = -1, clickx = 0, clicky = 0;
    std::mutex pmu; std::vector<uint32_t> px; int pw = 0, ph = 0; /* UI_PRESENT: what WM_PAINT shows */
    bool layered = false;     /* UI_W_TRANSPARENT: the pixels go to UpdateLayeredWindow instead */
};
static std::mutex g_wmu;
static std::vector<Win *> g_wins;
static HWND g_msgwnd;
static HMENU g_menubar;
static std::vector<std::pair<HMENU, int>> g_menu_items; /* (menu, id) for state updates */
static std::mutex g_menu_mu;
static std::vector<MwMenuItem> g_menu_pending;
static std::vector<std::string> g_menu_strings;
static HANDLE g_menu_ev;
static bool g_in_menu, g_menu_apply_later; /* a menu is open: a new menu bar waits until it closes */
static void menu_apply();
static std::atomic<bool> g_relative{false};
static Win *win_by_id(uint32_t id) { std::lock_guard<std::mutex> l(g_wmu); return id && id <= g_wins.size() ? g_wins[id - 1] : nullptr; }
static Win *win_by_hwnd(HWND h) { return (Win *)GetWindowLongPtrW(h, GWLP_USERDATA); }

static DWORD win_style(uint32_t s) {
    if (!(s & UI_STYLE_TITLED)) return WS_POPUP;
    DWORD st = WS_CAPTION | WS_SYSMENU;
    if (s & UI_STYLE_MINIATURIZABLE) st |= WS_MINIMIZEBOX;
    if (s & UI_STYLE_RESIZABLE) st |= WS_THICKFRAME | WS_MAXIMIZEBOX;
    return st;
}
static UINT win_dpi(HWND h) {
    static auto get = (UINT(WINAPI *)(HWND))GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow");
    UINT d = get ? get(h) : 96;
    return d ? d : 96;
}
/* AdjustWindowRect counts one menu row: a bar wrapped to more rows takes them from the content, so give them back
   (grows the window upwards, keeping the content where it was) */
static void keep_content_height(HWND h, int ch) {
    RECT cr; GetClientRect(h, &cr);
    if (!GetMenu(h) || cr.bottom == ch || IsZoomed(h) || IsIconic(h)) return;
    RECT wr; GetWindowRect(h, &wr);
    int d = ch - cr.bottom;
    SetWindowPos(h, nullptr, wr.left, wr.top - d, wr.right - wr.left, wr.bottom - wr.top + d, SWP_NOZORDER | SWP_NOACTIVATE);
}
static void adjust(RECT *r, DWORD st, bool menu, UINT dpi) {
    static auto adj = (BOOL(WINAPI *)(LPRECT, DWORD, BOOL, DWORD, UINT))GetProcAddress(GetModuleHandleW(L"user32.dll"), "AdjustWindowRectExForDpi");
    if (adj) adj(r, st, menu, 0, dpi);
    else AdjustWindowRect(r, st, menu);
}
static MwEvent ev(Win *w, uint32_t type) { MwEvent e{}; e.type = type; e.window = w ? w->id : 0; e.modifiers = modifiers(); return e; }

static void mouse_event(Win *w, uint32_t type, LPARAM l, int button, WPARAM wp) {
    MwEvent e = ev(w, type);
    e.x = GET_X_LPARAM(l); e.y = GET_Y_LPARAM(l); e.button = (uint32_t)button;
    if (w->lastx != INT32_MIN) { e.dx = (float)(e.x - w->lastx); e.dy = (float)(e.y - w->lasty); }
    if (type == UI_EV_MOUSE_DOWN) {
        uint64_t t = now_ns();
        bool close_ok = abs(e.x - w->clickx) <= GetSystemMetrics(SM_CXDOUBLECLK) && abs(e.y - w->clicky) <= GetSystemMetrics(SM_CYDOUBLECLK);
        w->clicks = (button == w->click_btn && close_ok && t - w->last_click < (uint64_t)GetDoubleClickTime() * 1000000) ? w->clicks + 1 : 1;
        w->last_click = t; w->click_btn = button; w->clickx = e.x; w->clicky = e.y;
    }
    e.clicks = type == UI_EV_MOUSE_MOVE ? 0 : (uint32_t)w->clicks;
    /* the buttons held when the message was sent (MK_*): dragging is a move with a button down */
    e.b = (wp & MK_LBUTTON ? 1u : 0u) | (wp & MK_RBUTTON ? 2u : 0u) | (wp & MK_MBUTTON ? 4u : 0u);
    if (type == UI_EV_MOUSE_MOVE && g_relative && GetForegroundWindow() == w->hwnd) {
        /* cursor detached from the mouse (games): report the motion and put the cursor back in the middle */
        RECT rc; GetClientRect(w->hwnd, &rc);
        POINT c{(rc.right) / 2, (rc.bottom) / 2};
        if (e.x == c.x && e.y == c.y) return; /* our own warp */
        e.dx = (float)(e.x - c.x); e.dy = (float)(e.y - c.y);
        w->lastx = c.x; w->lasty = c.y;
        ClientToScreen(w->hwnd, &c); SetCursorPos(c.x, c.y);
        push(e);
        return;
    }
    w->lastx = e.x; w->lasty = e.y;
    push(e);
}

static void key_event(Win *w, WPARAM vk, LPARAM l, bool down) {
    UINT scan = (l >> 16) & 0xFF;
    bool ext = (l >> 24) & 1;
    uint8_t code = mac_key(scan, ext);
    if (vk == VK_SHIFT || vk == VK_CONTROL || vk == VK_MENU || vk == VK_LWIN || vk == VK_RWIN || vk == VK_CAPITAL) {
        MwEvent e = ev(w, UI_EV_FLAGS);
        e.keycode = code; e.a = down;
        push(e);
        return;
    }
    if (code == 0xFF) return;
    MwEvent e = ev(w, down ? UI_EV_KEY_DOWN : UI_EV_KEY_UP);
    e.keycode = code;
    e.a = down && ((l >> 30) & 1); /* repeat */
    if (e.keycode >= 0x41 && e.keycode <= 0x5C && e.keycode != 0x48 && e.keycode != 0x49 && e.keycode != 0x4A) e.modifiers |= UI_MOD_NUMPAD;
    if ((e.keycode >= 0x60 && e.keycode <= 0x7E) || e.keycode == 0x72) e.modifiers |= UI_MOD_FUNCTION;
    key_chars((UINT)vk, scan, e.chars, e.chars_nomod);
    push(e);
}

static void set_fullscreen(Win *w, bool on) {
    if (on == w->fullscreen) return;
    if (on) {
        GetWindowRect(w->hwnd, &w->saved);
        w->saved_style = GetWindowLongW(w->hwnd, GWL_STYLE);
        MONITORINFO mi{sizeof mi};
        GetMonitorInfoW(MonitorFromWindow(w->hwnd, MONITOR_DEFAULTTONEAREST), &mi);
        SetWindowLongW(w->hwnd, GWL_STYLE, (w->saved_style & ~(WS_CAPTION | WS_THICKFRAME)) | WS_POPUP);
        SetMenu(w->hwnd, nullptr);
        SetWindowPos(w->hwnd, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right - mi.rcMonitor.left,
                     mi.rcMonitor.bottom - mi.rcMonitor.top, SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
    } else {
        SetWindowLongW(w->hwnd, GWL_STYLE, w->saved_style);
        if (g_menubar && !(w->style & UI_STYLE_NOMENU)) SetMenu(w->hwnd, g_menubar);
        SetWindowPos(w->hwnd, nullptr, w->saved.left, w->saved.top, w->saved.right - w->saved.left, w->saved.bottom - w->saved.top,
                     SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOOWNERZORDER);
    }
    w->fullscreen = on;
    MwEvent e = ev(w, UI_EV_FULLSCREEN);
    e.a = on;
    push(e);
}

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM wp, LPARAM l) {
    Win *w = win_by_hwnd(h);
    if (!w) return DefWindowProcW(h, m, wp, l);
    switch (m) {
    case WM_CLOSE: push(ev(w, UI_EV_CLOSE_REQUEST)); return 0; /* the guest decides (windowShouldClose:) */
    case WM_DESTROY: return 0;
    case WM_ACTIVATE: {
        MwEvent e = ev(w, UI_EV_FOCUS);
        e.a = LOWORD(wp) != WA_INACTIVE;
        push(e);
        if (!e.a && g_relative) ClipCursor(nullptr);
        break;
    }
    case WM_SIZE: {
        if (wp == SIZE_MINIMIZED) { MwEvent e = ev(w, UI_EV_MINIMIZE); e.a = 1; push(e); return 0; }
        MwEvent e = ev(w, UI_EV_RESIZE);
        e.x = LOWORD(l); e.y = HIWORD(l); e.a = win_dpi(h);
        push(e);
        return 0;
    }
    case WM_MOVE: push(ev(w, UI_EV_MOVE)); return 0;
    case WM_DPICHANGED: {
        RECT *r = (RECT *)l;
        SetWindowPos(h, nullptr, r->left, r->top, r->right - r->left, r->bottom - r->top, SWP_NOZORDER | SWP_NOACTIVATE);
        MwEvent e = ev(w, UI_EV_DPI);
        e.a = HIWORD(wp);
        push(e);
        return 0;
    }
    case WM_GETMINMAXINFO: {
        MINMAXINFO *mm = (MINMAXINFO *)l;
        DWORD st = GetWindowLongW(h, GWL_STYLE);
        if (w->minw || w->minh) {
            RECT r{0, 0, w->minw, w->minh};
            adjust(&r, st, GetMenu(h) != nullptr, win_dpi(h));
            mm->ptMinTrackSize.x = r.right - r.left; mm->ptMinTrackSize.y = r.bottom - r.top;
        }
        if (w->maxw || w->maxh) {
            RECT r{0, 0, w->maxw ? w->maxw : 100000, w->maxh ? w->maxh : 100000};
            adjust(&r, st, GetMenu(h) != nullptr, win_dpi(h));
            mm->ptMaxTrackSize.x = r.right - r.left; mm->ptMaxTrackSize.y = r.bottom - r.top;
        }
        return 0;
    }
    case WM_SIZING: {
        if (!w->aspw || !w->asph) break;
        RECT *r = (RECT *)l, fr{0, 0, 0, 0};
        adjust(&fr, GetWindowLongW(h, GWL_STYLE), GetMenu(h) != nullptr, win_dpi(h));
        int bw = fr.right - fr.left, bh = fr.bottom - fr.top;
        int cw = r->right - r->left - bw, ch = r->bottom - r->top - bh;
        if (wp == WMSZ_TOP || wp == WMSZ_BOTTOM) cw = ch * w->aspw / w->asph;
        else ch = cw * w->asph / w->aspw;
        if (wp == WMSZ_LEFT || wp == WMSZ_TOPLEFT || wp == WMSZ_BOTTOMLEFT) r->left = r->right - cw - bw; else r->right = r->left + cw + bw;
        if (wp == WMSZ_TOP || wp == WMSZ_TOPLEFT || wp == WMSZ_TOPRIGHT) r->top = r->bottom - ch - bh; else r->bottom = r->top + ch + bh;
        return TRUE;
    }
    case WM_KEYDOWN: case WM_SYSKEYDOWN:
        if (wp == VK_F4 && (GetKeyState(VK_MENU) & 0x8000)) { push(ev(w, UI_EV_CLOSE_REQUEST)); return 0; } /* Alt+F4 */
        key_event(w, wp, l, true);
        return 0; /* Alt is Option: it must not open the menu bar */
    case WM_KEYUP: case WM_SYSKEYUP: key_event(w, wp, l, false); return 0;
    case WM_CHAR: case WM_SYSCHAR: case WM_DEADCHAR: case WM_SYSDEADCHAR: return 0;
    case WM_MOUSEMOVE:
        if (!w->tracking) {
            TRACKMOUSEEVENT t{sizeof t, TME_LEAVE, h, 0};
            TrackMouseEvent(&t);
            w->tracking = true;
            push(ev(w, UI_EV_MOUSE_ENTER));
        }
        mouse_event(w, UI_EV_MOUSE_MOVE, l, -1, wp);
        return 0;
    case WM_MOUSELEAVE: w->tracking = false; w->lastx = INT32_MIN; push(ev(w, UI_EV_MOUSE_EXIT)); return 0;
    case WM_LBUTTONDOWN: SetCapture(h); mouse_event(w, UI_EV_MOUSE_DOWN, l, 0, wp); return 0;
    case WM_RBUTTONDOWN: SetCapture(h); mouse_event(w, UI_EV_MOUSE_DOWN, l, 1, wp); return 0;
    case WM_MBUTTONDOWN: SetCapture(h); mouse_event(w, UI_EV_MOUSE_DOWN, l, 2, wp); return 0;
    case WM_XBUTTONDOWN: SetCapture(h); mouse_event(w, UI_EV_MOUSE_DOWN, l, 2 + HIWORD(wp), wp); return TRUE;
    case WM_LBUTTONUP: ReleaseCapture(); mouse_event(w, UI_EV_MOUSE_UP, l, 0, wp); return 0;
    case WM_RBUTTONUP: ReleaseCapture(); mouse_event(w, UI_EV_MOUSE_UP, l, 1, wp); return 0;
    case WM_MBUTTONUP: ReleaseCapture(); mouse_event(w, UI_EV_MOUSE_UP, l, 2, wp); return 0;
    case WM_XBUTTONUP: ReleaseCapture(); mouse_event(w, UI_EV_MOUSE_UP, l, 2 + HIWORD(wp), wp); return TRUE;
    case WM_MOUSEWHEEL: case WM_MOUSEHWHEEL: {
        POINT p{GET_X_LPARAM(l), GET_Y_LPARAM(l)};
        ScreenToClient(h, &p);
        MwEvent e = ev(w, UI_EV_SCROLL);
        e.x = p.x; e.y = p.y;
        float d = (float)GET_WHEEL_DELTA_WPARAM(wp) / WHEEL_DELTA;
        if (m == WM_MOUSEWHEEL) e.dy = d; else e.dx = -d;
        push(e);
        return 0;
    }
    case WM_SETCURSOR:
        if (LOWORD(l) == HTCLIENT && (w->cursor_hidden || g_relative)) { SetCursor(nullptr); return TRUE; }
        if (LOWORD(l) == HTCLIENT) { SetCursor(LoadCursorW(nullptr, MAKEINTRESOURCEW(32512))); return TRUE; }
        break;
    case WM_COMMAND:
        if (HIWORD(wp) == 0 && !l) { MwEvent e = ev(w, UI_EV_MENU); e.a = LOWORD(wp); push(e); return 0; }
        break;
    case WM_INITMENUPOPUP: { /* the guest validates the items (validateMenuItem:): ask and wait a little */
        ResetEvent(g_menu_ev);
        push(ev(w, UI_EV_MENU_OPEN));
        if (WaitForSingleObject(g_menu_ev, 150) == WAIT_OBJECT_0) {
            std::lock_guard<std::mutex> lk(g_menu_mu);
            for (auto &it : g_menu_pending) {
                for (auto &[menu, id] : g_menu_items) {
                    if (id != it.id) continue;
                    EnableMenuItem(menu, (UINT)id, MF_BYCOMMAND | ((it.flags & UI_MI_DISABLED) ? MF_GRAYED : MF_ENABLED));
                    CheckMenuItem(menu, (UINT)id, MF_BYCOMMAND | ((it.flags & UI_MI_CHECKED) ? MF_CHECKED : MF_UNCHECKED));
                }
            }
        }
        return 0;
    }
    case WM_ERASEBKGND: return 1; /* Metal or UI_PRESENT draws everything */
    case WM_LAYERED_UPDATE: {   /* premultiplied BGRA, as UpdateLayeredWindow wants it */
        std::lock_guard<std::mutex> lk(w->pmu);
        if (!w->layered || !w->pw) return 0;
        BITMAPINFO bi{}; bi.bmiHeader = {sizeof bi.bmiHeader, w->pw, -w->ph, 1, 32, BI_RGB};
        void *bits = nullptr;
        HDC screen = GetDC(nullptr), mem = CreateCompatibleDC(screen);
        HBITMAP bm = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
        if (bm) {
            memcpy(bits, w->px.data(), w->px.size() * 4);
            HGDIOBJ old = SelectObject(mem, bm);
            SIZE sz{w->pw, w->ph}; POINT src{0, 0};
            BLENDFUNCTION bf{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
            UpdateLayeredWindow(h, screen, nullptr, &sz, mem, &src, 0, &bf, ULW_ALPHA);
            SelectObject(mem, old); DeleteObject(bm);
        }
        DeleteDC(mem); ReleaseDC(nullptr, screen);
        return 0;
    }
    case WM_PAINT: {
        std::lock_guard<std::mutex> lk(w->pmu);
        if (!w->pw) break;
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps);
        BITMAPINFO bi{}; bi.bmiHeader = {sizeof bi.bmiHeader, w->pw, -w->ph, 1, 32, BI_RGB};
        SetDIBitsToDevice(dc, 0, 0, w->pw, w->ph, 0, 0, 0, w->ph, w->px.data(), &bi, DIB_RGB_COLORS);
        EndPaint(h, &ps);
        return 0;
    }
    case WM_ENTERMENULOOP: g_in_menu = true; break;
    case WM_EXITMENULOOP:
        g_in_menu = false;
        if (g_menu_apply_later) { g_menu_apply_later = false; menu_apply(); }
        break;
    case WM_QUERYENDSESSION: push(ev(w, UI_EV_QUIT)); return TRUE;
    }
    return DefWindowProcW(h, m, wp, l);
}

/* ======================================================================= UI thread + synchronous requests */
struct Req { int op; A a, b, c, d, e; A r; };
/* ======================================================================= raw input (GCKeyboard / GCMouse) */
static std::mutex g_rmu;
static std::deque<MwRaw> g_raw;
static HANDLE g_rev;
static void raw_push(MwRaw r) {
    r.time_ns = now_ns();
    { std::lock_guard<std::mutex> l(g_rmu); if (g_raw.size() < 4096) g_raw.push_back(r); }
    SetEvent(g_rev);
}
/* PC set-1 scan code -> USB HID usage (page 7) */
static uint8_t hid_usage(UINT scan, bool ext) {
    static const uint8_t base[0x59] = {
        0, 0x29, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E, 0x2A, 0x2B,   /* 00 */
        0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13, 0x2F, 0x30, 0x28, 0xE0, 0x04, 0x16, /* 10 */
        0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F, 0x33, 0x34, 0x35, 0xE1, 0x31, 0x1D, 0x1B, 0x06, 0x19, /* 20 */
        0x05, 0x11, 0x10, 0x36, 0x37, 0x38, 0xE5, 0x55, 0xE2, 0x2C, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, /* 30 */
        0x3F, 0x40, 0x41, 0x42, 0x43, 0x53, 0x47, 0x5F, 0x60, 0x61, 0x56, 0x5C, 0x5D, 0x5E, 0x57, 0x59, /* 40 */
        0x5A, 0x5B, 0x62, 0x63, 0, 0, 0x64, 0x44, 0x45,                                                  /* 50 */
    };
    if (ext) switch (scan) {
        case 0x1C: return 0x58; case 0x1D: return 0xE4; case 0x35: return 0x54; case 0x37: return 0x46; case 0x38: return 0xE6;
        case 0x47: return 0x4A; case 0x48: return 0x52; case 0x49: return 0x4B; case 0x4B: return 0x50; case 0x4D: return 0x4F;
        case 0x4F: return 0x4D; case 0x50: return 0x51; case 0x51: return 0x4E; case 0x52: return 0x49; case 0x53: return 0x4C;
        case 0x5B: return 0xE3; case 0x5C: return 0xE7; case 0x5D: return 0x65; default: return 0;
    }
    if (scan == 0x45) return 0x53;
    return scan < sizeof base ? base[scan] : 0;
}
static void raw_input(HRAWINPUT h) {
    alignas(8) BYTE buf[256];
    UINT size = sizeof buf;
    if (GetRawInputData(h, RID_INPUT, buf, &size, sizeof(RAWINPUTHEADER)) == (UINT)-1) return;
    if (!win_by_hwnd(GetForegroundWindow())) return; /* like macOS: only while the app is in front */
    RAWINPUT *ri = (RAWINPUT *)buf;
    if (ri->header.dwType == RIM_TYPEKEYBOARD) {
        RAWKEYBOARD &k = ri->data.keyboard;
        if (k.MakeCode == 0 || k.VKey == 0xFF) return; /* fake keys (e.g. the half of Pause) */
        MwRaw r{}; r.type = UI_RAW_KEY; r.code = hid_usage(k.MakeCode, (k.Flags & RI_KEY_E0) != 0); r.down = !(k.Flags & RI_KEY_BREAK);
        if (r.code) raw_push(r);
    } else if (ri->header.dwType == RIM_TYPEMOUSE) {
        RAWMOUSE &m = ri->data.mouse;
        static LONG lastx = LONG_MIN, lasty;
        if (m.usFlags & MOUSE_MOVE_ABSOLUTE) { /* remote desktop, VMs, tablets: deltas from absolute positions */
            bool virt = m.usFlags & MOUSE_VIRTUAL_DESKTOP;
            int w = GetSystemMetrics(virt ? SM_CXVIRTUALSCREEN : SM_CXSCREEN), hh = GetSystemMetrics(virt ? SM_CYVIRTUALSCREEN : SM_CYSCREEN);
            LONG x = MulDiv(m.lLastX, w, 65535), y = MulDiv(m.lLastY, hh, 65535);
            if (lastx != LONG_MIN && (x != lastx || y != lasty)) { MwRaw r{}; r.type = UI_RAW_MOVE; r.dx = (float)(x - lastx); r.dy = (float)(y - lasty); raw_push(r); }
            lastx = x; lasty = y;
        } else if (m.lLastX || m.lLastY) { MwRaw r{}; r.type = UI_RAW_MOVE; r.dx = (float)m.lLastX; r.dy = (float)m.lLastY; raw_push(r); }
        static const USHORT down[5] = {RI_MOUSE_LEFT_BUTTON_DOWN, RI_MOUSE_RIGHT_BUTTON_DOWN, RI_MOUSE_MIDDLE_BUTTON_DOWN, RI_MOUSE_BUTTON_4_DOWN, RI_MOUSE_BUTTON_5_DOWN};
        static const USHORT up[5] = {RI_MOUSE_LEFT_BUTTON_UP, RI_MOUSE_RIGHT_BUTTON_UP, RI_MOUSE_MIDDLE_BUTTON_UP, RI_MOUSE_BUTTON_4_UP, RI_MOUSE_BUTTON_5_UP};
        for (int b = 0; b < 5; b++) {
            if (m.usButtonFlags & down[b]) { MwRaw r{}; r.type = UI_RAW_BUTTON; r.code = (uint32_t)b; r.down = 1; raw_push(r); }
            if (m.usButtonFlags & up[b]) { MwRaw r{}; r.type = UI_RAW_BUTTON; r.code = (uint32_t)b; r.down = 0; raw_push(r); }
        }
        if (m.usButtonFlags & (RI_MOUSE_WHEEL | RI_MOUSE_HWHEEL)) {
            MwRaw r{}; r.type = UI_RAW_SCROLL;
            float d = (float)(SHORT)m.usButtonData / WHEEL_DELTA;
            if (m.usButtonFlags & RI_MOUSE_WHEEL) r.dy = d; else r.dx = d;
            raw_push(r);
        }
    }
}
static void raw_start() { /* on the UI thread */
    RAWINPUTDEVICE d[2] = {{1, 6, RIDEV_INPUTSINK, g_msgwnd}, {1, 2, RIDEV_INPUTSINK, g_msgwnd}};
    RegisterRawInputDevices(d, 2, sizeof *d);
}

static std::wstring wide(const char *s);
/* ======================================================================= status items (notification area) */
#define WM_TRAY (WM_APP + 1)

struct Tray { HICON icon = nullptr; std::vector<uint32_t> px; uint32_t w = 0, h = 0; std::wstring tip; };
static std::map<int, Tray> g_trays;     /* UI thread only */
static HWND g_traywnd;                  /* hidden top-level window: owns the icons and their menus */
static void tray_click(int id, int button) {
    if (!g_trays.count(id)) return;
    NOTIFYICONIDENTIFIER ni{sizeof ni}; ni.hWnd = g_traywnd; ni.uID = (UINT)id;
    RECT r;
    if (FAILED(Shell_NotifyIconGetRect(&ni, &r))) { POINT p; GetCursorPos(&p); r = {p.x - 8, p.y - 8, p.x + 8, p.y + 8}; }
    MwEvent e = ev(nullptr, UI_EV_STATUS);
    e.a = (uint32_t)id; e.button = (uint32_t)button; e.clicks = 1;
    e.x = r.left; e.y = r.top; e.dx = (float)(r.right - r.left); e.dy = (float)(r.bottom - r.top);
    push(e);
}
static LRESULT CALLBACK trayproc(HWND h, UINT m, WPARAM wp, LPARAM l) {
    if (m == WM_TRAY) {
        if (l == WM_LBUTTONDOWN) tray_click((int)wp, 0);
        else if (l == WM_RBUTTONUP) tray_click((int)wp, 1);
        return 0;
    }
    return DefWindowProcW(h, m, wp, l);
}
static HICON make_icon(const MwImage *img) {   /* premultiplied BGRA -> 32-bit icon (straight alpha) */
    BITMAPV5HEADER bh{}; bh.bV5Size = sizeof bh; bh.bV5Width = (LONG)img->w; bh.bV5Height = -(LONG)img->h; bh.bV5Planes = 1;
    bh.bV5BitCount = 32; bh.bV5Compression = BI_BITFIELDS;
    bh.bV5RedMask = 0xFF0000; bh.bV5GreenMask = 0xFF00; bh.bV5BlueMask = 0xFF; bh.bV5AlphaMask = 0xFF000000;
    void *bits = nullptr;
    HDC dc = GetDC(nullptr);
    HBITMAP color = CreateDIBSection(dc, (BITMAPINFO *)&bh, DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, dc);
    if (!color) return nullptr;
    const uint8_t *s = (const uint8_t *)img->pixels; uint8_t *d = (uint8_t *)bits;
    for (size_t i = 0; i < (size_t)img->w * img->h; i++, s += 4, d += 4) {
        unsigned a = s[3];
        for (int k = 0; k < 3; k++) d[k] = (uint8_t)(a ? std::min(255u, s[k] * 255u / a) : 0);
        d[3] = (uint8_t)a;
    }
    HBITMAP mask = CreateBitmap((int)img->w, (int)img->h, 1, 1, nullptr);
    ICONINFO ii{TRUE, 0, 0, mask, color};
    HICON icon = CreateIconIndirect(&ii);
    DeleteObject(mask); DeleteObject(color);
    return icon;
}
static A status_item(int id, int op, const MwImage *img, const char *tip) {
    if (!g_traywnd) {
        WNDCLASSEXW tc{sizeof tc};
        tc.lpfnWndProc = trayproc; tc.hInstance = GetModuleHandleW(nullptr); tc.lpszClassName = L"scion-tray";
        RegisterClassExW(&tc);
        g_traywnd = CreateWindowExW(WS_EX_TOOLWINDOW, L"scion-tray", L"", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, tc.hInstance, nullptr);
    }
    NOTIFYICONDATAW nd{}; nd.cbSize = sizeof nd; nd.hWnd = g_traywnd; nd.uID = (UINT)id;
    if (!op) {
        auto it = g_trays.find(id);
        if (it == g_trays.end()) return 0;
        Shell_NotifyIconW(NIM_DELETE, &nd);
        if (it->second.icon) DestroyIcon(it->second.icon);
        g_trays.erase(it);
        return 1;
    }
    bool fresh = !g_trays.count(id);
    Tray &t = g_trays[id];
    if (img && img->w && img->h) {
        if (HICON n = make_icon(img)) { if (t.icon) DestroyIcon(t.icon); t.icon = n; }
        t.w = img->w; t.h = img->h; t.px.assign((const uint32_t *)img->pixels, (const uint32_t *)img->pixels + (size_t)img->w * img->h);
    }
    if (tip) t.tip = wide(tip);
    nd.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP; nd.uCallbackMessage = WM_TRAY;
    nd.hIcon = t.icon ? t.icon : LoadIconW(nullptr, MAKEINTRESOURCEW(32512));
    wcsncpy(nd.szTip, t.tip.c_str(), 127);
    Shell_NotifyIconW(fresh ? NIM_ADD : NIM_MODIFY, &nd);   /* without a notification area the item still exists */
    return 1;
}

static A ui_thread_op(Req *q);
static LRESULT CALLBACK msgproc(HWND h, UINT m, WPARAM wp, LPARAM l) {
    if (m == WM_APP) { Req *q = (Req *)l; q->r = ui_thread_op(q); return 0; }
    if (m == WM_INPUT) { raw_input((HRAWINPUT)l); return DefWindowProcW(h, m, wp, l); }
    return DefWindowProcW(h, m, wp, l);
}
static void ui_start() {
    static std::once_flag once;
    std::call_once(once, [] {
        g_qev = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        g_menu_ev = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        typedef UINT(WINAPI * tbp_t)(UINT);
        if (HMODULE wm = LoadLibraryW(L"winmm.dll")) if (auto tbp = (tbp_t)GetProcAddress(wm, "timeBeginPeriod")) tbp(1); /* precise timers for games */
        HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        std::thread([ready] {
            CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED); /* the file dialogs need an STA */
            HINSTANCE hi = GetModuleHandleW(nullptr);
            WNDCLASSEXW wc{sizeof wc};
            wc.lpfnWndProc = wndproc; wc.hInstance = hi; wc.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
            wc.hIcon = LoadIconW(hi, MAKEINTRESOURCEW(1)); wc.lpszClassName = L"scion-window"; wc.style = CS_OWNDC;
            extern std::wstring g_app_icon; /* an installed app's own icon (scion install) */
            if (!g_app_icon.empty()) {
                wc.hIcon = (HICON)LoadImageW(nullptr, g_app_icon.c_str(), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
                wc.hIconSm = (HICON)LoadImageW(nullptr, g_app_icon.c_str(), IMAGE_ICON, 16, 16, LR_LOADFROMFILE);
            }
            RegisterClassExW(&wc);
            WNDCLASSEXW mc{sizeof mc};
            mc.lpfnWndProc = msgproc; mc.hInstance = hi; mc.lpszClassName = L"scion-ui";
            RegisterClassExW(&mc);
            g_msgwnd = CreateWindowExW(0, L"scion-ui", L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, hi, nullptr);
            SetEvent(ready);
            MSG msg;
            while (GetMessageW(&msg, nullptr, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageW(&msg); }
        }).detach();
        WaitForSingleObject(ready, INFINITE);
        CloseHandle(ready);
    });
}
static A on_ui(int op, A a, A b = 0, A c = 0, A d = 0, A e = 0) {
    ui_start();
    Req q{op, a, b, c, d, e, 0};
    SendMessageW(g_msgwnd, WM_APP, 0, (LPARAM)&q);
    return q.r;
}

static std::wstring wide(const char *s) {
    if (!s) return L"";
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    std::wstring w(n ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s, -1, w.data(), n);
    return w;
}
static std::wstring key_label(const MwMenuItem &it) {
    if (!it.key || !*it.key) return L"";
    std::wstring s;
    if (it.key_modifiers & UI_MOD_COMMAND) s += L"Ctrl+";   /* Command shortcuts answer to Ctrl on Windows */
    if (it.key_modifiers & UI_MOD_CONTROL) s += L"Win+";
    if (it.key_modifiers & UI_MOD_OPTION) s += L"Alt+";
    if (it.key_modifiers & UI_MOD_SHIFT) s += L"Shift+";
    std::wstring k = wide(it.key);
    if (k == L",") s += L","; else if (k == L"\x1b") s += L"Esc"; else for (wchar_t c : k) s += (wchar_t)towupper(c);
    return s;
}

struct MenuRow { MwMenuItem it; std::string title, key; };
static std::vector<MenuRow> g_menu_next;
static void menu_apply() {
    HMENU bar = CreateMenu();
    std::vector<HMENU> stack{bar};
    g_menu_items.clear();
    for (MenuRow &row : g_menu_next) {
        MwMenuItem it = row.it;
        it.title = row.title.c_str(); it.key = row.key.c_str();
        int level = it.level < 0 ? 0 : it.level;
        while ((int)stack.size() > level + 1) stack.pop_back();
        if (stack.empty()) stack.push_back(bar);
        HMENU parent = stack.back();
        if (it.flags & UI_MI_SEPARATOR) { AppendMenuW(parent, MF_SEPARATOR, 0, nullptr); continue; }
        std::wstring title = wide(it.title);
        std::wstring keys = key_label(it);
        if (!keys.empty()) title += L"\t" + keys;
        UINT f = MF_STRING | ((it.flags & UI_MI_DISABLED) ? MF_GRAYED : 0) | ((it.flags & UI_MI_CHECKED) ? MF_CHECKED : 0);
        if (it.flags & UI_MI_SUBMENU) {
            HMENU sub = CreatePopupMenu();
            AppendMenuW(parent, f | MF_POPUP, (UINT_PTR)sub, title.c_str());
            stack.push_back(sub);
        } else {
            AppendMenuW(parent, f, (UINT_PTR)it.id, title.c_str());
            g_menu_items.push_back({parent, it.id});
        }
    }
    HMENU old = g_menubar;
    g_menubar = bar;
    std::lock_guard<std::mutex> l(g_wmu);
    for (Win *w : g_wins)
        if (w->hwnd && !w->fullscreen && (w->style & UI_STYLE_TITLED) && !(w->style & UI_STYLE_NOMENU)) {
            RECT cr; GetClientRect(w->hwnd, &cr);
            POINT o{0, 0}; ClientToScreen(w->hwnd, &o);
            SetMenu(w->hwnd, bar);
            /* keep the content where it is: the menu bar takes room from the frame (above), not from the content */
            RECT r{0, 0, cr.right, cr.bottom};
            adjust(&r, GetWindowLongW(w->hwnd, GWL_STYLE), TRUE, win_dpi(w->hwnd));
            SetWindowPos(w->hwnd, nullptr, o.x + r.left, o.y + r.top, r.right - r.left, r.bottom - r.top, SWP_NOZORDER | SWP_NOACTIVATE);
            keep_content_height(w->hwnd, cr.bottom);
        }
    if (old) DestroyMenu(old);
}

/* ---------------------------------------------------------------- file dialogs and context menus */
static std::mutex g_test_mu;
static std::string g_test_dialog; static bool g_test_dialog_set; /* UI_TEST: the next answers, without showing anything */
static int g_test_popup = -1;
static char *dup_str(const std::string &s) { char *p = (char *)malloc(s.size() + 1); memcpy(p, s.c_str(), s.size() + 1); return p; }
static std::string item_path(IShellItem *it) {
    std::string r;
    PWSTR p = nullptr;
    if (SUCCEEDED(it->GetDisplayName(SIGDN_FILESYSPATH, &p))) {
        int n = WideCharToMultiByte(CP_UTF8, 0, p, -1, nullptr, 0, nullptr, nullptr);
        std::string u(n > 0 ? n - 1 : 0, '\0');
        if (n > 1) WideCharToMultiByte(CP_UTF8, 0, p, -1, u.data(), n, nullptr, nullptr);
        r = win_to_darwin(u);
        CoTaskMemFree(p);
    }
    return r;
}
static A file_dialog(const MwFileDialog *d) {
    {
        std::lock_guard<std::mutex> l(g_test_mu);
        if (g_test_dialog_set) { g_test_dialog_set = false; return g_test_dialog.empty() ? 0 : (A)dup_str(g_test_dialog); }
    }
    bool save = d->flags & UI_FD_SAVE;
    IFileDialog *fd = nullptr;
    if (FAILED(CoCreateInstance(save ? CLSID_FileSaveDialog : CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                save ? IID_IFileSaveDialog : IID_IFileOpenDialog, (void **)&fd))) return 0;
    FILEOPENDIALOGOPTIONS o = 0;
    fd->GetOptions(&o);
    o |= FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR;
    if (!save && (d->flags & UI_FD_DIRS) && !(d->flags & UI_FD_FILES)) o |= FOS_PICKFOLDERS;
    if (!save && (d->flags & UI_FD_MULTIPLE)) o |= FOS_ALLOWMULTISELECT;
    if (d->flags & UI_FD_HIDDEN) o |= FOS_FORCESHOWHIDDEN;
    if (save) o |= FOS_OVERWRITEPROMPT; else o |= FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST;
    fd->SetOptions(o);
    if (d->title && *d->title) fd->SetTitle(wide(d->title).c_str());
    if (d->button && *d->button) fd->SetOkButtonLabel(wide(d->button).c_str());
    if (d->filename && *d->filename) fd->SetFileName(wide(d->filename).c_str());
    if (d->directory && *d->directory) {
        IShellItem *dir = nullptr;
        if (SUCCEEDED(SHCreateItemFromParsingName(darwin_to_win(d->directory, -1).c_str(), nullptr, IID_IShellItem, (void **)&dir))) { fd->SetFolder(dir); dir->Release(); }
    }
    std::wstring spec;
    if (d->types && *d->types) { /* "png;jpg" -> "*.png;*.jpg" */
        std::string t = d->types;
        size_t i = 0;
        while (i <= t.size()) {
            size_t j = t.find(';', i); if (j == std::string::npos) j = t.size();
            if (j > i) { if (!spec.empty()) spec += L";"; spec += L"*." + wide(t.substr(i, j - i).c_str()); }
            i = j + 1;
        }
        COMDLG_FILTERSPEC f[2] = {{spec.c_str(), spec.c_str()}, {L"*.*", L"*.*"}};
        fd->SetFileTypes(save ? 1 : 2, f);
        if (save) { std::string first = t.substr(0, t.find(';')); fd->SetDefaultExtension(wide(first.c_str()).c_str()); }
    }
    Win *owner = win_by_id(d->window);
    std::string out;
    if (SUCCEEDED(fd->Show(owner ? owner->hwnd : nullptr))) {
        if (!save && (o & FOS_ALLOWMULTISELECT)) {
            IShellItemArray *arr = nullptr;
            if (SUCCEEDED(((IFileOpenDialog *)fd)->GetResults(&arr))) {
                DWORD n = 0; arr->GetCount(&n);
                for (DWORD k = 0; k < n; k++) { IShellItem *it; if (SUCCEEDED(arr->GetItemAt(k, &it))) { out += item_path(it) + "\n"; it->Release(); } }
                arr->Release();
            }
        } else {
            IShellItem *it = nullptr;
            if (SUCCEEDED(fd->GetResult(&it))) { out = item_path(it) + "\n"; it->Release(); }
        }
    }
    fd->Release();
    return out.empty() ? 0 : (A)dup_str(out);
}
/* the items in the same flattened form as the menu bar; returns the chosen id */
static A popup_menu(Win *w, int x, int y, const MwMenuItem *items, int n) {
    {
        std::lock_guard<std::mutex> l(g_test_mu);
        if (g_test_popup >= 0) { A r = g_test_popup; g_test_popup = -1; return r; }
    }
    HMENU root = CreatePopupMenu();
    std::vector<HMENU> stack{root};
    for (int i = 0; i < n; i++) {
        const MwMenuItem &it = items[i];
        int level = it.level < 0 ? 0 : it.level;
        while ((int)stack.size() > level + 1) stack.pop_back();
        HMENU parent = stack.back();
        if (it.flags & UI_MI_SEPARATOR) { AppendMenuW(parent, MF_SEPARATOR, 0, nullptr); continue; }
        std::wstring title = wide(it.title), keys = key_label(it);
        if (!keys.empty()) title += L"\t" + keys;
        UINT f = MF_STRING | ((it.flags & UI_MI_DISABLED) ? MF_GRAYED : 0) | ((it.flags & UI_MI_CHECKED) ? MF_CHECKED : 0);
        if (it.flags & UI_MI_SUBMENU) { HMENU sub = CreatePopupMenu(); AppendMenuW(parent, f | MF_POPUP, (UINT_PTR)sub, title.c_str()); stack.push_back(sub); }
        else AppendMenuW(parent, f, (UINT_PTR)it.id, title.c_str());
    }
    POINT p{x, y};
    HWND h = w ? w->hwnd : g_msgwnd;
    if (w) ClientToScreen(w->hwnd, &p);
    if (w && !IsWindowVisible(w->hwnd) && g_traywnd) h = g_traywnd;   /* a status item's menu: owned by the tray window */
    if (h != g_msgwnd) SetForegroundWindow(h);
    A r = TrackPopupMenu(root, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, p.x, p.y, 0, h, nullptr);
    if (h == g_traywnd) PostMessageW(h, WM_NULL, 0, 0);   /* so the menu closes when clicking elsewhere (KB135788) */
    DestroyMenu(root);
    return r;
}

static A ui_thread_op(Req *q) {
    switch (q->op) {
    case UI_FILE_DIALOG: return file_dialog((const MwFileDialog *)q->a);
    case UI_RAW_NEXT: raw_start(); return 0;
    case UI_POPUP_MENU: return popup_menu(win_by_id((uint32_t)q->a), (int)q->b, (int)q->c, (const MwMenuItem *)q->d, (int)q->e);
    case UI_STATUS_ITEM: return status_item((int)q->a, (int)q->b, (const MwImage *)q->c, (const char *)q->d);
    case UI_TEST: {
        auto it = g_trays.find((int)q->b);
        if (it == g_trays.end()) return 0;
        if (q->a == 4) tray_click((int)q->b, (int)q->c);
        else { MwImage *o = (MwImage *)q->c; o->w = it->second.w; o->h = it->second.h; o->pixels = malloc(it->second.px.size() * 4 + 1);
               memcpy(o->pixels, it->second.px.data(), it->second.px.size() * 4); }
        return 1;
    }
    case UI_WINDOW_CREATE: {
        const MwWindowDesc *d = (const MwWindowDesc *)q->a;
        Win *w = new Win;
        { std::lock_guard<std::mutex> l(g_wmu); g_wins.push_back(w); w->id = (uint32_t)g_wins.size(); }
        w->style = d->style;
        DWORD st = win_style(d->style);
        UINT dpi = 96;
        if (auto gd = (UINT(WINAPI *)())GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForSystem")) dpi = gd();
        RECT r{0, 0, d->w, d->h};
        HMENU menu = (d->style & UI_STYLE_NOMENU) || !(d->style & UI_STYLE_TITLED) ? nullptr : g_menubar;
        adjust(&r, st, menu != nullptr, dpi);
        int x = d->x, y = d->y;
        if (x < -30000 || y < -30000) { /* center on the primary screen's work area */
            RECT wa; SystemParametersInfoW(SPI_GETWORKAREA, 0, &wa, 0);
            x = wa.left + (wa.right - wa.left - (r.right - r.left)) / 2; y = wa.top + (wa.bottom - wa.top - (r.bottom - r.top)) / 2;
        } else { x += r.left; y += r.top; }
        w->hwnd = CreateWindowExW(0, L"scion-window", wide(d->title).c_str(), st, x, y, r.right - r.left, r.bottom - r.top,
                                  nullptr, menu, GetModuleHandleW(nullptr), nullptr);
        if (!w->hwnd) return 0;
        SetWindowLongPtrW(w->hwnd, GWLP_USERDATA, (LONG_PTR)w);
        keep_content_height(w->hwnd, d->h);
        BOOL dark = TRUE;
        DwmSetWindowAttribute(w->hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &dark, sizeof dark);
        if (d->visible) ShowWindow(w->hwnd, SW_SHOW);
        return w->id;
    }
    case UI_WINDOW_SET: {
        Win *w = win_by_id((uint32_t)q->a);
        if (!w || !w->hwnd) return -1;
        A x = q->c, y = q->d, wh = q->e;
        switch (q->b) {
        case UI_W_TITLE: SetWindowTextW(w->hwnd, wide((const char *)q->c).c_str()); return 0;
        case UI_W_FRAME: {
            int cw = (int)(wh & 0xFFFFFFFF), ch = (int)(wh >> 32);
            RECT r{0, 0, cw, ch};
            adjust(&r, GetWindowLongW(w->hwnd, GWL_STYLE), GetMenu(w->hwnd) != nullptr, win_dpi(w->hwnd));
            SetWindowPos(w->hwnd, nullptr, (int)x + r.left, (int)y + r.top, r.right - r.left, r.bottom - r.top, SWP_NOZORDER | SWP_NOACTIVATE);
            keep_content_height(w->hwnd, ch);
            return 0;
        }
        case UI_W_SHOW:
            if (!q->c) ShowWindow(w->hwnd, SW_HIDE);
            else if (q->c == 1) ShowWindow(w->hwnd, IsWindowVisible(w->hwnd) ? SW_SHOWNOACTIVATE : SW_SHOWNA);
            else { ShowWindow(w->hwnd, SW_SHOW); SetForegroundWindow(w->hwnd); SetFocus(w->hwnd); }
            return 0;
        case UI_W_CLOSE: DestroyWindow(w->hwnd); w->hwnd = nullptr; return 0;
        case UI_W_MINIMIZE: ShowWindow(w->hwnd, q->c ? SW_MINIMIZE : SW_RESTORE); return 0;
        case UI_W_FULLSCREEN: set_fullscreen(w, q->c != 0); return 0;
        case UI_W_MIN_SIZE: w->minw = (int)q->c; w->minh = (int)q->d; return 0;
        case UI_W_MAX_SIZE: w->maxw = (int)q->c; w->maxh = (int)q->d; return 0;
        case UI_W_ASPECT: w->aspw = (int)q->c; w->asph = (int)q->d; return 0;
        case UI_W_STYLE: {
            w->style = (uint32_t)q->c;
            if (w->fullscreen) return 0;
            RECT cr; GetClientRect(w->hwnd, &cr);
            POINT o{0, 0}; ClientToScreen(w->hwnd, &o);
            DWORD st = win_style(w->style) | (GetWindowLongW(w->hwnd, GWL_STYLE) & WS_VISIBLE);
            SetWindowLongW(w->hwnd, GWL_STYLE, st);
            HMENU want = (w->style & UI_STYLE_NOMENU) || !(w->style & UI_STYLE_TITLED) ? nullptr : g_menubar;
            if (GetMenu(w->hwnd) != want) SetMenu(w->hwnd, want);
            RECT r{0, 0, cr.right, cr.bottom};
            adjust(&r, st, GetMenu(w->hwnd) != nullptr, win_dpi(w->hwnd));
            SetWindowPos(w->hwnd, nullptr, o.x + r.left, o.y + r.top, r.right - r.left, r.bottom - r.top, SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOACTIVATE);
            keep_content_height(w->hwnd, cr.bottom);
            return 0;
        }
        case UI_W_CURSOR_HIDDEN: w->cursor_hidden = q->c != 0; return 0;
        case UI_W_TRANSPARENT: {
            bool on = q->c != 0;
            if (on == w->layered) return 0;
            w->layered = on;
            LONG_PTR ex = GetWindowLongPtrW(w->hwnd, GWL_EXSTYLE);
            SetWindowLongPtrW(w->hwnd, GWL_EXSTYLE, on ? ex | WS_EX_LAYERED : ex & ~WS_EX_LAYERED);
            if (on) PostMessageW(w->hwnd, WM_LAYERED_UPDATE, 0, 0); else InvalidateRect(w->hwnd, nullptr, FALSE);
            return 0;
        }
        }
        return -1;
    }
    case UI_MENU: { /* copied now; applied at once, or when the open menu closes */
        const MwMenuItem *items = (const MwMenuItem *)q->a;
        g_menu_next.clear();
        for (A i = 0; i < q->b; i++) g_menu_next.push_back({items[i], items[i].title ? items[i].title : "", items[i].key ? items[i].key : ""});
        if (g_in_menu) g_menu_apply_later = true; else menu_apply();
        return 0;
    }
    case UI_CURSOR:
        if (q->a == 0) { while (ShowCursor(FALSE) >= 0) {} return 0; }
        if (q->a == 1) { while (ShowCursor(TRUE) < 0) {} return 0; }
        if (q->a == 2) { SetCursorPos((int)q->b, (int)q->c); return 0; }
        if (q->a == 3) {
            g_relative = q->b == 0;
            if (!g_relative) ClipCursor(nullptr);
            else if (HWND fg = GetForegroundWindow(); fg && win_by_hwnd(fg)) {
                RECT rc; GetClientRect(fg, &rc);
                POINT a{rc.left, rc.top}, b{rc.right, rc.bottom};
                ClientToScreen(fg, &a); ClientToScreen(fg, &b);
                RECT clip{a.x, a.y, b.x, b.y};
                ClipCursor(&clip);
            }
            return 0;
        }
        return -1;
    case UI_INJECT: {
        Win *w = win_by_id((uint32_t)q->a);
        if (!w || !w->hwnd) return -1;
        /* through the window procedure, as if the message came from the system (keyboard state included) */
        if (q->b == WM_KEYDOWN || q->b == WM_KEYUP || q->b == WM_SYSKEYDOWN || q->b == WM_SYSKEYUP) {
            BYTE st[256]; GetKeyboardState(st);
            bool down = q->b == WM_KEYDOWN || q->b == WM_SYSKEYDOWN;
            st[q->c & 0xFF] = down ? 0x80 : 0;
            if (q->c == VK_LSHIFT || q->c == VK_RSHIFT) st[VK_SHIFT] = st[q->c];
            if (q->c == VK_LCONTROL || q->c == VK_RCONTROL) st[VK_CONTROL] = st[q->c];
            if (q->c == VK_LMENU || q->c == VK_RMENU) st[VK_MENU] = st[q->c];
            SetKeyboardState(st);
            WPARAM vk = q->c;
            if (vk == VK_LSHIFT || vk == VK_RSHIFT) vk = VK_SHIFT;
            if (vk == VK_LCONTROL || vk == VK_RCONTROL) vk = VK_CONTROL;
            if (vk == VK_LMENU || vk == VK_RMENU) vk = VK_MENU;
            return wndproc(w->hwnd, (UINT)q->b, vk, (LPARAM)q->d);
        }
        return wndproc(w->hwnd, (UINT)q->b, (WPARAM)q->c, (LPARAM)q->d);
    }
    }
    return -1;
}

/* ======================================================================= controllers (XInput) */
typedef DWORD(WINAPI *xget_t)(DWORD, XINPUT_STATE *);
typedef DWORD(WINAPI *xset_t)(DWORD, XINPUT_VIBRATION *);
static xget_t g_xget;
static xset_t g_xset;
static MwPad g_virtual[4];
static bool g_virtual_on[4];
static void xinput_load() {
    static std::once_flag once;
    std::call_once(once, [] {
        for (const wchar_t *n : {L"xinput1_4.dll", L"xinput1_3.dll", L"xinput9_1_0.dll"})
            if (HMODULE m = LoadLibraryW(n)) {
                g_xget = (xget_t)GetProcAddress(m, "XInputGetState");
                g_xset = (xset_t)GetProcAddress(m, "XInputSetState");
                if (g_xget) break;
            }
    });
}
static float axis(SHORT v, SHORT dead) {
    if (v > -dead && v < dead) return 0;
    float f = v < 0 ? (v + dead) / (32768.0f - dead) : (v - dead) / (32767.0f - dead);
    return f < -1 ? -1 : f > 1 ? 1 : f;
}
static A pad_state(A index, MwPad *p) {
    if (index < 0 || index > 3) return 0;
    if (g_virtual_on[index]) { *p = g_virtual[index]; return 1; }
    xinput_load();
    XINPUT_STATE s{};
    if (!g_xget || g_xget((DWORD)index, &s) != ERROR_SUCCESS) return 0;
    memset(p, 0, sizeof *p);
    WORD b = s.Gamepad.wButtons;
    static const struct { WORD x; uint32_t m; } map[] = {
        {XINPUT_GAMEPAD_A, UI_PAD_A}, {XINPUT_GAMEPAD_B, UI_PAD_B}, {XINPUT_GAMEPAD_X, UI_PAD_X}, {XINPUT_GAMEPAD_Y, UI_PAD_Y},
        {XINPUT_GAMEPAD_LEFT_SHOULDER, UI_PAD_LB}, {XINPUT_GAMEPAD_RIGHT_SHOULDER, UI_PAD_RB}, {XINPUT_GAMEPAD_LEFT_THUMB, UI_PAD_LS},
        {XINPUT_GAMEPAD_RIGHT_THUMB, UI_PAD_RS}, {XINPUT_GAMEPAD_START, UI_PAD_MENU}, {XINPUT_GAMEPAD_BACK, UI_PAD_VIEW},
        {XINPUT_GAMEPAD_DPAD_UP, UI_PAD_UP}, {XINPUT_GAMEPAD_DPAD_DOWN, UI_PAD_DOWN}, {XINPUT_GAMEPAD_DPAD_LEFT, UI_PAD_LEFT},
        {XINPUT_GAMEPAD_DPAD_RIGHT, UI_PAD_RIGHT}};
    for (auto &mp : map) if (b & mp.x) p->buttons |= mp.m;
    p->lx = axis(s.Gamepad.sThumbLX, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);
    p->ly = axis(s.Gamepad.sThumbLY, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);
    p->rx = axis(s.Gamepad.sThumbRX, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE);
    p->ry = axis(s.Gamepad.sThumbRY, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE);
    p->lt = s.Gamepad.bLeftTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD ? s.Gamepad.bLeftTrigger / 255.0f : 0;
    p->rt = s.Gamepad.bRightTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD ? s.Gamepad.bRightTrigger / 255.0f : 0;
    strcpy(p->name, "Xbox Wireless Controller");
    p->has_rumble = 1;
    return 1;
}
static uint16_t g_rumble_seen[4][2];
static A pad_rumble(A index, A low, A high) {
    if (index < 0 || index > 3) return -1;
    g_rumble_seen[index][0] = (uint16_t)low; g_rumble_seen[index][1] = (uint16_t)high;
    if (g_virtual_on[index]) return 0;
    xinput_load();
    XINPUT_VIBRATION v{(WORD)low, (WORD)high};
    return g_xset && g_xset((DWORD)index, &v) == ERROR_SUCCESS ? 0 : -1;
}

/* ======================================================================= audio (WASAPI) */
struct Stream {
    IAudioClient *client = nullptr;
    IAudioRenderClient *render = nullptr;
    HANDLE ev = nullptr;
    UINT32 bufFrames = 0;
    int channels = 2, rate = 48000;
    bool null_sink = false, started = false;
    uint64_t null_t0 = 0, null_written = 0; /* null sink: consumes in real time */
    std::mutex mu;
};
static std::mutex g_amu;
static std::vector<Stream *> g_streams;
static A audio_open(A rate, A channels) {
    Stream *s = new Stream;
    s->rate = (int)rate; s->channels = (int)channels;
    bool ok = false;
    if (!getenv("SCION_AUDIO_NULL")) {
        CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        IMMDeviceEnumerator *en = nullptr;
        IMMDevice *dev = nullptr;
        if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator), (void **)&en)) &&
            SUCCEEDED(en->GetDefaultAudioEndpoint(eRender, eConsole, &dev)) &&
            SUCCEEDED(dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void **)&s->client))) {
            WAVEFORMATEXTENSIBLE wf{};
            wf.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
            wf.Format.nChannels = (WORD)channels;
            wf.Format.nSamplesPerSec = (DWORD)rate;
            wf.Format.wBitsPerSample = 32;
            wf.Format.nBlockAlign = (WORD)(4 * channels);
            wf.Format.nAvgBytesPerSec = (DWORD)(rate * 4 * channels);
            wf.Format.cbSize = 22;
            wf.Samples.wValidBitsPerSample = 32;
            wf.dwChannelMask = channels == 1 ? SPEAKER_FRONT_CENTER : channels == 2 ? (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT) : 0;
            static const GUID kFloat = {0x00000003, 0x0000, 0x0010, {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71}};
            wf.SubFormat = kFloat;
            DWORD flags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK | 0x80000000 /* AUTOCONVERTPCM */ | 0x08000000 /* SRC_DEFAULT_QUALITY */;
            if (SUCCEEDED(s->client->Initialize(AUDCLNT_SHAREMODE_SHARED, flags, 400000 /* 40 ms */, 0, &wf.Format, nullptr)) &&
                SUCCEEDED(s->client->GetBufferSize(&s->bufFrames)) &&
                SUCCEEDED(s->client->GetService(__uuidof(IAudioRenderClient), (void **)&s->render))) {
                s->ev = CreateEventW(nullptr, FALSE, FALSE, nullptr);
                s->client->SetEventHandle(s->ev);
                ok = true;
            }
        }
        if (dev) dev->Release();
        if (en) en->Release();
    }
    if (!ok) {
        if (s->render) s->render->Release();
        if (s->client) s->client->Release();
        s->render = nullptr; s->client = nullptr;
        s->null_sink = true;
        s->bufFrames = (UINT32)(rate / 25);
        TRACE("audio: no device, output discarded\n");
    }
    std::lock_guard<std::mutex> l(g_amu);
    g_streams.push_back(s);
    return (A)g_streams.size();
}
static Stream *stream(A id) { std::lock_guard<std::mutex> l(g_amu); return id > 0 && id <= (A)g_streams.size() ? g_streams[id - 1] : nullptr; }
static uint64_t null_queued(Stream *s) {
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
        if (s->null_sink) {
            uint64_t q = null_queued(s);
            if (q >= s->bufFrames) {
                if (!s->started) return done; /* nothing drains a stopped stream */
                l.unlock(); Sleep(2); continue;
            }
            if (s->started && !q) { s->null_t0 = now_ns(); s->null_written = 0; } /* underrun: restart the clock */
            A n = std::min<A>(frames - done, (A)(s->bufFrames - q));
            s->null_written += (uint64_t)n;
            done += n;
            continue;
        }
        UINT32 pad = 0;
        if (FAILED(s->client->GetCurrentPadding(&pad))) return done;
        UINT32 room = s->bufFrames - pad;
        if (!room) {
            if (!s->started) return done;
            l.unlock();
            WaitForSingleObject(s->ev, 50);
            continue;
        }
        UINT32 n = (UINT32)std::min<A>(frames - done, room);
        BYTE *buf;
        if (FAILED(s->render->GetBuffer(n, &buf))) return done;
        memcpy(buf, data + done * s->channels, (size_t)n * 4 * s->channels);
        s->render->ReleaseBuffer(n, 0);
        done += n;
    }
    return done;
}
static A audio_ctl(A id, A op) {
    Stream *s = stream(id);
    if (!s) return -1;
    std::lock_guard<std::mutex> l(s->mu);
    switch (op) {
    case 0:
        if (!s->started) {
            if (s->null_sink) s->null_t0 = now_ns() - (uint64_t)0, s->null_written = s->null_written; /* queued frames start playing now */
            else s->client->Start();
            s->started = true;
        }
        return 0;
    case 1:
        if (s->started) { if (!s->null_sink) s->client->Stop(); s->started = false; }
        if (s->null_sink) s->null_written = 0;
        else s->client->Reset();
        return 0;
    case 2:
        if (!s->null_sink) {
            if (s->started) s->client->Stop();
            s->render->Release(); s->client->Release(); CloseHandle(s->ev);
            s->render = nullptr; s->client = nullptr;
        }
        s->null_sink = true; s->started = false; s->null_written = 0; /* the slot stays (ids are never reused) */
        return 0;
    case 3: {
        if (s->null_sink) return (A)null_queued(s);
        UINT32 pad = 0;
        s->client->GetCurrentPadding(&pad);
        return pad;
    }
    case 4: return s->rate;
    case 5: return s->null_sink;
    }
    return -1;
}

/* ======================================================================= the hostcall */
static BOOL CALLBACK enum_mon(HMONITOR m, HDC, LPRECT, LPARAM p) { ((std::vector<HMONITOR> *)p)->push_back(m); return TRUE; }
static void raw_init() {
    static std::once_flag once;
    std::call_once(once, [] { g_rev = CreateEventW(nullptr, FALSE, FALSE, nullptr); on_ui(UI_RAW_NEXT, 0); });
}
/* ======================================================================= text (GDI), images (WIC) */
static std::mutex g_tmu;
static HFONT text_font(const char *name, int px, int weight, bool italic, bool mono) {
    static std::vector<std::pair<std::string, HFONT>> cache;
    std::string n = name ? name : "";
    auto has = [&](const char *k) { return n.find(k) != std::string::npos; };
    const wchar_t *family = mono || has("Mono") || has("Menlo") || has("Courier") || has("Monaco") || has("Consolas") ? L"Consolas"
                          : has("Times") || has("Georgia") || has("Serif") ? L"Times New Roman" : L"Segoe UI";
    if (has("Bold") && weight < 700) weight = 700;
    if (has("Semibold") && weight < 600) weight = 600;
    if (has("Italic") || has("Oblique")) italic = true;
    std::string key = std::to_string(px) + "/" + std::to_string(weight) + "/" + (italic ? "i" : "") + "/" + std::to_string((uintptr_t)family);
    for (auto &[k, f] : cache) if (k == key) return f;
    /* the pitch tells GDI what to fall back to when the family is missing (Consolas under Wine, say): a monospaced font */
    BYTE pitch = family[0] == L'C' ? FIXED_PITCH | FF_MODERN : family[0] == L'T' ? VARIABLE_PITCH | FF_ROMAN : VARIABLE_PITCH | FF_SWISS;
    HFONT f = CreateFontW(-px, 0, 0, 0, weight, italic, 0, 0, DEFAULT_CHARSET, OUT_TT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                          pitch, family);
    if (cache.size() > 64) { DeleteObject(cache.front().second); cache.erase(cache.begin()); }
    cache.push_back({key, f});
    return f;
}
static A text_op(MwText *t) {
    std::lock_guard<std::mutex> l(g_tmu);
    static HDC dc = CreateCompatibleDC(nullptr);
    int px = (int)(t->size + 0.5f);
    if (px < 1) px = 1;
    HFONT f = text_font(t->font, px, t->weight ? (int)t->weight : 400, t->flags & UI_TEXT_ITALIC, t->flags & UI_TEXT_MONO);
    HGDIOBJ old = SelectObject(dc, f);
    std::wstring s = wide(t->text);
    SIZE sz{}; GetTextExtentPoint32W(dc, s.c_str(), (int)s.size(), &sz);
    TEXTMETRICW tm{}; GetTextMetricsW(dc, &tm);
    t->width = (float)sz.cx; t->ascent = (float)tm.tmAscent; t->descent = (float)tm.tmDescent;
    t->pad = (uint32_t)(px / 4 + 2); /* overhang of italics and antialiasing */
    t->w = (uint32_t)sz.cx + 2 * t->pad; t->h = (uint32_t)(tm.tmAscent + tm.tmDescent);
    if (t->mask && t->w && t->h) {
        BITMAPINFO bi{}; bi.bmiHeader = {sizeof bi.bmiHeader, (LONG)t->w, -(LONG)t->h, 1, 32, BI_RGB};
        void *bits = nullptr;
        HBITMAP bm = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
        if (bm) {
            HGDIOBJ ob = SelectObject(dc, bm);
            memset(bits, 0, (size_t)t->w * t->h * 4);
            SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(255, 255, 255)); SetTextAlign(dc, TA_LEFT | TA_TOP);
            TextOutW(dc, (int)t->pad, 0, s.c_str(), (int)s.size());
            GdiFlush();
            const uint8_t *p = (const uint8_t *)bits;
            for (size_t i = 0, n = (size_t)t->w * t->h; i < n; i++) t->mask[i] = std::max(p[i * 4], std::max(p[i * 4 + 1], p[i * 4 + 2]));
            SelectObject(dc, ob); DeleteObject(bm);
        }
    }
    SelectObject(dc, old);
    return 1;
}
static IWICImagingFactory *wic() {
    static thread_local bool com;
    if (!com) { CoInitializeEx(nullptr, COINIT_MULTITHREADED); com = true; } /* fails harmlessly on an STA thread */
    static IWICImagingFactory *f;
    static std::once_flag once;
    std::call_once(once, [] { CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&f)); });
    return f;
}
static A image_decode(const void *data, A size, MwImage *out) {
    IWICImagingFactory *f = wic();
    if (!f || !data || !size) return 0;
    IWICStream *st = nullptr; IWICBitmapDecoder *dec = nullptr; IWICBitmapFrameDecode *fr = nullptr; IWICBitmapSource *cv = nullptr;
    A ok = 0;
    if (SUCCEEDED(f->CreateStream(&st)) && SUCCEEDED(st->InitializeFromMemory((BYTE *)data, (DWORD)size)) &&
        SUCCEEDED(f->CreateDecoderFromStream(st, nullptr, WICDecodeMetadataCacheOnDemand, &dec)) && SUCCEEDED(dec->GetFrame(0, &fr)) &&
        SUCCEEDED(WICConvertBitmapSource(GUID_WICPixelFormat32bppPBGRA, fr, &cv))) {
        UINT w = 0, h = 0; cv->GetSize(&w, &h);
        void *px = malloc((size_t)w * h * 4);
        if (px && SUCCEEDED(cv->CopyPixels(nullptr, w * 4, w * h * 4, (BYTE *)px))) { out->w = w; out->h = h; out->pixels = px; ok = 1; }
        else free(px);
    }
    for (IUnknown *u : {(IUnknown *)cv, (IUnknown *)fr, (IUnknown *)dec, (IUnknown *)st}) if (u) u->Release();
    return ok;
}
static A image_encode(const MwImage *img, A type, float quality, uint64_t *size) {
    IWICImagingFactory *f = wic();
    if (!f || !img || !img->w || !img->h) return 0;
    const GUID *fmt = type == UI_IMG_JPEG ? &GUID_ContainerFormatJpeg : type == UI_IMG_BMP ? &GUID_ContainerFormatBmp
                    : type == UI_IMG_TIFF ? &GUID_ContainerFormatTiff : type == UI_IMG_GIF ? &GUID_ContainerFormatGif : &GUID_ContainerFormatPng;
    IStream *st = nullptr; IWICBitmapEncoder *enc = nullptr; IWICBitmapFrameEncode *fr = nullptr; IPropertyBag2 *props = nullptr;
    IWICBitmap *src = nullptr;
    A r = 0;
    if (SUCCEEDED(CreateStreamOnHGlobal(nullptr, TRUE, &st)) && SUCCEEDED(f->CreateEncoder(*fmt, nullptr, &enc)) &&
        SUCCEEDED(enc->Initialize(st, WICBitmapEncoderNoCache)) && SUCCEEDED(enc->CreateNewFrame(&fr, &props))) {
        if (type == UI_IMG_JPEG && props) {
            PROPBAG2 opt{}; opt.pstrName = (LPOLESTR)L"ImageQuality";
            VARIANT v{}; v.vt = VT_R4; v.fltVal = quality > 0 && quality <= 1 ? quality : 0.9f;
            props->Write(1, &opt, &v);
        }
        WICPixelFormatGUID pf = GUID_WICPixelFormat32bppPBGRA;
        if (SUCCEEDED(fr->Initialize(props)) && SUCCEEDED(fr->SetSize(img->w, img->h)) && SUCCEEDED(fr->SetPixelFormat(&pf)) &&
            SUCCEEDED(f->CreateBitmapFromMemory(img->w, img->h, GUID_WICPixelFormat32bppPBGRA, img->w * 4, img->w * img->h * 4, (BYTE *)img->pixels, &src)) &&
            SUCCEEDED(fr->WriteSource(src, nullptr)) && SUCCEEDED(fr->Commit()) && SUCCEEDED(enc->Commit())) {
            HGLOBAL g = nullptr;
            if (SUCCEEDED(GetHGlobalFromStream(st, &g))) {
                STATSTG ss{}; st->Stat(&ss, STATFLAG_NONAME);
                size_t n = (size_t)ss.cbSize.QuadPart;
                void *out = malloc(n ? n : 1);
                memcpy(out, GlobalLock(g), n); GlobalUnlock(g);
                *size = n; r = (A)out;
            }
        }
    }
    for (IUnknown *u : {(IUnknown *)src, (IUnknown *)props, (IUnknown *)fr, (IUnknown *)enc, (IUnknown *)st}) if (u) u->Release();
    return r;
}
static A present(Win *w, const MwImage *img) {
    if (!w || !w->hwnd) return -1;
    {
        std::lock_guard<std::mutex> l(w->pmu);
        if (!img) { w->pw = w->ph = 0; w->px.clear(); return 0; }
        w->px.assign((const uint32_t *)img->pixels, (const uint32_t *)img->pixels + (size_t)img->w * img->h);
        w->pw = (int)img->w; w->ph = (int)img->h;
    }
    if (w->layered) PostMessageW(w->hwnd, WM_LAYERED_UPDATE, 0, 0); else InvalidateRect(w->hwnd, nullptr, FALSE);
    return 0;
}

A hc_ui(A op, A a, A b, A c, A d, A e) {
    switch (op) {
    case UI_NEXT_EVENT: ui_start(); return next_event((MwEvent *)a, (int64_t)b);
    case UI_WAKE: ui_start(); SetEvent(g_qev); return 0;
    case UI_WINDOW_CREATE: case UI_WINDOW_SET: case UI_MENU: case UI_CURSOR: case UI_INJECT: case UI_FILE_DIALOG: case UI_POPUP_MENU: case UI_STATUS_ITEM:
        return on_ui((int)op, a, b, c, d, e);
    case UI_RAW_NEXT: {
        raw_init();
        uint64_t deadline = (int64_t)b < 0 ? UINT64_MAX : now_ns() + (uint64_t)b;
        for (;;) {
            { std::lock_guard<std::mutex> l(g_rmu); if (!g_raw.empty()) { *(MwRaw *)a = g_raw.front(); g_raw.pop_front(); return 1; } }
            uint64_t t = now_ns();
            if (t >= deadline) return 0;
            WaitForSingleObject(g_rev, deadline == UINT64_MAX ? INFINITE : (DWORD)((deadline - t + 999999) / 1000000));
        }
    }
    case UI_RAW_INJECT:
        raw_init();
        raw_push(*(const MwRaw *)a);
        return 0;
    case UI_TEST: {
        if (a == 4 || a == 5) return on_ui(UI_TEST, a, b, c);   /* status items live on the UI thread */
        std::lock_guard<std::mutex> l(g_test_mu);
        if (a == 1) { g_test_dialog = b ? (const char *)b : ""; g_test_dialog_set = true; }
        else if (a == 2) g_test_popup = (int)b;
        else if (a == 3) { /* a copy of what window b shows (UI_PRESENT) -> MwImage *c, pixels malloc'd (UI_FREE) */
            Win *w = win_by_id((uint32_t)b);
            if (!w) return 0;
            std::lock_guard<std::mutex> lk(w->pmu);
            if (!w->pw) return 0;
            MwImage *o = (MwImage *)c;
            o->w = (uint32_t)w->pw; o->h = (uint32_t)w->ph; o->pixels = malloc(w->px.size() * 4);
            memcpy(o->pixels, w->px.data(), w->px.size() * 4);
            return 1;
        }
        return 0;
    }
    case UI_WINDOW_INFO: {
        Win *w = win_by_id((uint32_t)a);
        MwWindowInfo *o = (MwWindowInfo *)b;
        memset(o, 0, sizeof *o);
        if (!w || !w->hwnd) return -1;
        RECT cr; GetClientRect(w->hwnd, &cr);
        POINT p{0, 0}; ClientToScreen(w->hwnd, &p);
        o->x = p.x; o->y = p.y; o->w = cr.right; o->h = cr.bottom;
        RECT wr; GetWindowRect(w->hwnd, &wr);
        o->fx = wr.left; o->fy = wr.top; o->fw = wr.right - wr.left; o->fh = wr.bottom - wr.top;
        /* the menu bar is not part of a Mac window's frame: leaving it out keeps the frame - content height constant
           when the bar wraps to more rows (apps that save the frame height and restore it would grow each launch) */
        MENUBARINFO mb{}; mb.cbSize = sizeof mb;
        if (GetMenu(w->hwnd) && GetMenuBarInfo(w->hwnd, OBJID_MENU, 0, &mb)) { int mh = mb.rcBar.bottom - mb.rcBar.top; if (mh > 0 && mh < o->fh) { o->fy += mh; o->fh -= mh; } }
        o->dpi = win_dpi(w->hwnd);
        o->key = GetForegroundWindow() == w->hwnd;
        o->visible = IsWindowVisible(w->hwnd);
        o->minimized = IsIconic(w->hwnd);
        o->zoomed = IsZoomed(w->hwnd);
        o->fullscreen = w->fullscreen;
        return 0;
    }
    case UI_WINDOW_HWND: { Win *w = win_by_id((uint32_t)a); return w ? (A)w->hwnd : 0; }
    case UI_SCREEN: {
        std::vector<HMONITOR> mons;
        EnumDisplayMonitors(nullptr, nullptr, enum_mon, (LPARAM)&mons);
        /* the primary screen first, like NSScreen.screens */
        std::stable_partition(mons.begin(), mons.end(), [](HMONITOR m) { MONITORINFO mi{sizeof mi}; GetMonitorInfoW(m, &mi); return (mi.dwFlags & MONITORINFOF_PRIMARY) != 0; });
        if (a < 0 || a >= (A)mons.size()) return (A)mons.size();
        MwScreen *s = (MwScreen *)b;
        memset(s, 0, sizeof *s);
        MONITORINFOEXW mi{};
        mi.cbSize = sizeof mi;
        GetMonitorInfoW(mons[a], &mi);
        s->x = mi.rcMonitor.left; s->y = mi.rcMonitor.top; s->w = mi.rcMonitor.right - mi.rcMonitor.left; s->h = mi.rcMonitor.bottom - mi.rcMonitor.top;
        s->vx = mi.rcWork.left; s->vy = mi.rcWork.top; s->vw = mi.rcWork.right - mi.rcWork.left; s->vh = mi.rcWork.bottom - mi.rcWork.top;
        s->primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
        UINT dx = 96, dy = 96;
        typedef HRESULT(WINAPI * gdfm_t)(HMONITOR, int, UINT *, UINT *);
        static gdfm_t gdfm = [] { HMODULE m = LoadLibraryW(L"shcore.dll"); return m ? (gdfm_t)GetProcAddress(m, "GetDpiForMonitor") : nullptr; }();
        if (gdfm) gdfm(mons[a], 0, &dx, &dy);
        s->dpi = dx ? dx : 96;
        DEVMODEW dm{}; dm.dmSize = sizeof dm;
        s->refresh_mhz = EnumDisplaySettingsW(mi.szDevice, ENUM_CURRENT_SETTINGS, &dm) && dm.dmDisplayFrequency > 1 ? dm.dmDisplayFrequency * 1000 : 60000;
        WideCharToMultiByte(CP_UTF8, 0, mi.szDevice, -1, s->name, sizeof s->name, nullptr, nullptr);
        return (A)mons.size();
    }
    case UI_MENU_STATE: {
        std::lock_guard<std::mutex> l(g_menu_mu);
        g_menu_pending.assign((const MwMenuItem *)a, (const MwMenuItem *)a + b);
        SetEvent(g_menu_ev);
        return 0;
    }
    case UI_MOUSE_POS: {
        POINT p; GetCursorPos(&p);
        ((int32_t *)a)[0] = p.x; ((int32_t *)a)[1] = p.y;
        A btn = 0;
        if (GetAsyncKeyState(VK_LBUTTON) & 0x8000) btn |= 1;
        if (GetAsyncKeyState(VK_RBUTTON) & 0x8000) btn |= 2;
        if (GetAsyncKeyState(VK_MBUTTON) & 0x8000) btn |= 4;
        return btn;
    }
    case UI_PAD: return pad_state(a, (MwPad *)b);
    case UI_RUMBLE: return pad_rumble(a, b, c);
    case UI_PAD_INJECT:
        if (a < 0 || a > 3) return -1;
        if (b) { g_virtual[a] = *(const MwPad *)b; g_virtual_on[a] = true; }
        else g_virtual_on[a] = false;
        return ((A)g_rumble_seen[a][0] << 16) | g_rumble_seen[a][1]; /* tests read the last rumble back */
    case UI_AUDIO_OPEN: return audio_open(a, b);
    case UI_AUDIO_WRITE: return audio_write(a, (const float *)b, c);
    case UI_AUDIO_CTL: return audio_ctl(a, b);
    case UI_VSYNC_WAIT: {
        DEVMODEW dm{}; dm.dmSize = sizeof dm;
        A mhz = EnumDisplaySettingsW(nullptr, ENUM_CURRENT_SETTINGS, &dm) && dm.dmDisplayFrequency > 1 ? dm.dmDisplayFrequency * 1000 : 60000;
        uint64_t period = 1000000000000ull / (uint64_t)mhz;
        static thread_local uint64_t last;
        HRESULT hr = DwmFlush();
        uint64_t t = now_ns();
        /* no compositor (or one that does not wait, like Wine's): pace with the clock */
        if (FAILED(hr) || (last && t - last < period / 2)) {
            uint64_t next = last && t - last < period ? last + period : t;
            if (next > t) Sleep((DWORD)((next - t) / 1000000));
            while (now_ns() < next) {}
        }
        last = now_ns();
        return mhz;
    }
    case UI_ALERT: {
        UINT t = c == 2 ? MB_ICONERROR : c == 1 ? MB_ICONWARNING : MB_ICONINFORMATION;
        t |= d >= 3 ? MB_YESNOCANCEL : d == 2 ? MB_OKCANCEL : MB_OK;
        int r = MessageBoxW(nullptr, wide((const char *)b).c_str(), wide((const char *)a).c_str(), t | MB_TASKMODAL);
        return r == IDOK || r == IDYES ? 0 : r == IDNO ? 1 : r == IDCANCEL ? (d >= 3 ? 2 : 1) : 0;
    }
    case UI_CLIPBOARD: {
        if (!OpenClipboard(nullptr)) return 0;
        A r = 0;
        if (a == 0) {
            if (HANDLE h = GetClipboardData(CF_UNICODETEXT)) {
                const wchar_t *w = (const wchar_t *)GlobalLock(h);
                int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
                char *s = (char *)malloc(n > 0 ? n : 1);
                s[0] = 0;
                if (n > 0) WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, nullptr, nullptr);
                GlobalUnlock(h);
                r = (A)s;
            }
        } else {
            std::wstring w = wide((const char *)b);
            HGLOBAL g = GlobalAlloc(GMEM_MOVEABLE, (w.size() + 1) * 2);
            memcpy(GlobalLock(g), w.c_str(), (w.size() + 1) * 2);
            GlobalUnlock(g);
            EmptyClipboard();
            SetClipboardData(CF_UNICODETEXT, g);
        }
        CloseClipboard();
        return r;
    }
    case UI_FREE: free((void *)a); return 0;
    case UI_TEXT: return text_op((MwText *)a);
    case UI_IMAGE_DECODE: return image_decode((const void *)a, b, (MwImage *)c);
    case UI_IMAGE_ENCODE: { float q; memcpy(&q, &c, sizeof q); return image_encode((const MwImage *)a, b, q, (uint64_t *)d); }
    case UI_PRESENT: return present(win_by_id((uint32_t)a), (const MwImage *)b);
    }
    return -38;
}
