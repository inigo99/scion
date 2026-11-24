/* install.cpp — macOS apps as apps of the host system.
 *   scion install App.app       Start menu shortcut with the app's icon, "Open with" for its document types, and an entry in
 *                                Windows' installed apps (its uninstaller is `scion uninstall`). Under Wine, Wine turns the
 *                                shortcut and the types into a .desktop file and MIME entries, so Linux desktops get the same.
 *   scion uninstall App.app    (or its bundle identifier) undoes it.
 *   scion App.app [args]       runs the bundle's executable.
 * A small reader for Info.plist (XML and binary) lives here: the host needs it before any guest code runs. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <objbase.h>
#include <propkey.h>
#include <string>
#include <vector>
#include <map>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include "scion.h"

std::string g_bundle_id;      /* the bundle being run, if any */
std::wstring g_app_icon;      /* its installed icon (.ico), for windows and the taskbar */

static std::wstring widen(const std::string &s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0); std::wstring w(n ? n - 1 : 0, 0);
    if (n) MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, w.data(), n);
    return w;
}
static std::string utf8(const std::wstring &w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr); std::string s(n ? n - 1 : 0, 0);
    if (n) WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, s.data(), n, nullptr, nullptr);
    return s;
}
static bool read_file(const std::wstring &p, std::string &out) {
    HANDLE h = CreateFileW(p.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER sz; GetFileSizeEx(h, &sz);
    if (sz.QuadPart > (64 << 20)) { CloseHandle(h); return false; }
    out.resize((size_t)sz.QuadPart); DWORD got = 0;
    bool ok = ReadFile(h, out.data(), (DWORD)out.size(), &got, nullptr) && got == out.size();
    CloseHandle(h);
    return ok;
}
static bool write_file(const std::wstring &p, const std::string &data) {
    HANDLE h = CreateFileW(p.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    DWORD put = 0; bool ok = WriteFile(h, data.data(), (DWORD)data.size(), &put, nullptr) && put == data.size();
    CloseHandle(h);
    return ok;
}
static bool is_dir(const std::wstring &p) { DWORD a = GetFileAttributesW(p.c_str()); return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY); }

/* ======================================================================= Info.plist: strings, arrays and dictionaries */
struct PVal {
    enum { NONE, STR, ARR, DICT } t = NONE;
    std::string s; std::vector<PVal> a; std::vector<std::pair<std::string, PVal>> d;
    const PVal *get(const char *k) const { for (auto &kv : d) if (kv.first == k) return &kv.second; return nullptr; }
    std::string str(const char *k) const { const PVal *v = get(k); return v && v->t == STR ? v->s : ""; }
};
/* XML: only what Info.plist needs; numbers, dates and data are kept as their text */
struct XmlIn { const char *p, *e; };
static void x_skip(XmlIn &x) {
    for (;;) {
        while (x.p < x.e && strchr(" \t\r\n", *x.p)) x.p++;
        if (x.e - x.p >= 4 && !memcmp(x.p, "<!--", 4)) { const char *c = strstr(x.p, "-->"); x.p = c && c < x.e ? c + 3 : x.e; continue; }
        if (x.e - x.p >= 2 && x.p[0] == '<' && (x.p[1] == '?' || x.p[1] == '!')) { while (x.p < x.e && *x.p != '>') x.p++; if (x.p < x.e) x.p++; continue; }
        return;
    }
}
static bool x_lit(XmlIn &x, const char *s) { size_t n = strlen(s); if ((size_t)(x.e - x.p) < n || memcmp(x.p, s, n)) return false; x.p += n; return true; }
static std::string x_text(XmlIn &x) {
    std::string out;
    while (x.p < x.e && *x.p != '<') {
        if (*x.p != '&') { out += *x.p++; continue; }
        const char *semi = (const char *)memchr(x.p, ';', (size_t)(x.e - x.p));
        if (!semi || semi - x.p > 10) { out += *x.p++; continue; }
        std::string ent(x.p + 1, semi);
        if (ent == "amp") out += '&'; else if (ent == "lt") out += '<'; else if (ent == "gt") out += '>'; else if (ent == "quot") out += '"'; else if (ent == "apos") out += '\'';
        else if (!ent.empty() && ent[0] == '#') {
            unsigned long c = ent[1] == 'x' ? strtoul(ent.c_str() + 2, 0, 16) : strtoul(ent.c_str() + 1, 0, 10);
            out += utf8(std::wstring(1, (wchar_t)c));
        }
        x.p = semi + 1;
    }
    return out;
}
static bool x_value(XmlIn &x, PVal &v, int depth) {
    if (depth > 64) return false;
    x_skip(x);
    if (x_lit(x, "<dict/>")) { v.t = PVal::DICT; return true; }
    if (x_lit(x, "<array/>")) { v.t = PVal::ARR; return true; }
    if (x_lit(x, "<true/>")) { v.t = PVal::STR; v.s = "true"; return true; }
    if (x_lit(x, "<false/>")) { v.t = PVal::STR; v.s = "false"; return true; }
    if (x_lit(x, "<dict>")) {
        v.t = PVal::DICT;
        for (;;) {
            x_skip(x);
            if (x_lit(x, "</dict>")) return true;
            if (!x_lit(x, "<key>")) return false;
            std::string k = x_text(x); if (!x_lit(x, "</key>")) return false;
            PVal c; if (!x_value(x, c, depth + 1)) return false;
            v.d.emplace_back(k, std::move(c));
        }
    }
    if (x_lit(x, "<array>")) {
        v.t = PVal::ARR;
        for (;;) { x_skip(x); if (x_lit(x, "</array>")) return true; PVal c; if (!x_value(x, c, depth + 1)) return false; v.a.push_back(std::move(c)); }
    }
    /* <string>, <integer>, <real>, <date>, <data> (or their empty forms) */
    if (x.p >= x.e || *x.p != '<') return false;
    const char *close = (const char *)memchr(x.p, '>', (size_t)(x.e - x.p)); if (!close) return false;
    std::string tag(x.p + 1, close);
    v.t = PVal::STR;
    if (!tag.empty() && tag.back() == '/') { x.p = close + 1; return true; }
    x.p = close + 1; v.s = x_text(x);
    return x_lit(x, ("</" + tag + ">").c_str());
}
/* binary bplist00 */
struct BinIn { const uint8_t *b; size_t n; std::vector<uint64_t> offs; unsigned refsz; };
static uint64_t be(const uint8_t *p, unsigned n) { uint64_t v = 0; for (unsigned i = 0; i < n; i++) v = v << 8 | p[i]; return v; }
static bool b_value(BinIn &r, uint64_t idx, PVal &v, int depth) {
    if (idx >= r.offs.size() || depth > 64) return false;
    size_t pos = (size_t)r.offs[idx]; if (pos >= r.n) return false;
    uint8_t m = r.b[pos++]; unsigned hi = m >> 4, lo = m & 15;
    uint64_t cnt = lo;
    auto count = [&]() -> bool {
        if (lo != 15) return true;
        if (pos >= r.n || (r.b[pos] >> 4) != 1) return false;
        unsigned sz = 1u << (r.b[pos] & 15); if (sz > 8 || pos + 1 + sz > r.n) return false;
        cnt = be(r.b + pos + 1, sz); pos += 1 + sz; return true;
    };
    switch (hi) {
    case 0x0: v.t = PVal::STR; v.s = m == 9 ? "true" : "false"; return true;
    case 0x1: { unsigned sz = 1u << lo; if (sz > 8 || pos + sz > r.n) return false; v.t = PVal::STR; v.s = std::to_string((long long)be(r.b + pos, sz)); return true; }
    case 0x2: case 0x3: v.t = PVal::STR; return true;
    case 0x4: case 0x5: case 0x6: {
        if (!count()) return false;
        uint64_t bytes = hi == 6 ? cnt * 2 : cnt; if (cnt > r.n || pos + bytes > r.n) return false;
        v.t = PVal::STR;
        if (hi == 5) { for (uint64_t i = 0; i < cnt; i++) v.s += utf8(std::wstring(1, (wchar_t)r.b[pos + i])); }
        else if (hi == 6) { std::wstring w; for (uint64_t i = 0; i < cnt; i++) w += (wchar_t)be(r.b + pos + i * 2, 2); v.s = utf8(w); }
        return true;
    }
    case 0xa: case 0xd: {
        if (!count()) return false;
        uint64_t refs = hi == 0xd ? cnt * 2 : cnt; if (cnt > r.offs.size() || pos + refs * r.refsz > r.n) return false;
        if (hi == 0xa) {
            v.t = PVal::ARR;
            for (uint64_t i = 0; i < cnt; i++) { PVal c; if (!b_value(r, be(r.b + pos + i * r.refsz, r.refsz), c, depth + 1)) return false; v.a.push_back(std::move(c)); }
        } else {
            v.t = PVal::DICT;
            for (uint64_t i = 0; i < cnt; i++) {
                PVal k, c;
                if (!b_value(r, be(r.b + pos + i * r.refsz, r.refsz), k, depth + 1) || k.t != PVal::STR) return false;
                if (!b_value(r, be(r.b + pos + (cnt + i) * r.refsz, r.refsz), c, depth + 1)) return false;
                v.d.emplace_back(k.s, std::move(c));
            }
        }
        return true;
    }
    }
    return false;
}
static bool read_plist(const std::wstring &path, PVal &out) {
    std::string f; if (!read_file(path, f)) return false;
    if (f.size() > 40 && !memcmp(f.data(), "bplist00", 8)) {
        const uint8_t *b = (const uint8_t *)f.data(), *t = b + f.size() - 32;
        BinIn r{b, f.size(), {}, t[7]}; unsigned offsz = t[6]; uint64_t count = be(t + 8, 8), top = be(t + 16, 8), table = be(t + 24, 8);
        if (offsz < 1 || offsz > 8 || r.refsz < 1 || r.refsz > 8 || count > f.size() || top >= count || table + count * offsz > f.size() - 32) return false;
        for (uint64_t i = 0; i < count; i++) r.offs.push_back(be(b + table + i * offsz, offsz));
        return b_value(r, top, out, 0);
    }
    XmlIn x{f.data(), f.data() + f.size()};
    x_skip(x);
    if (x_lit(x, "<plist")) { while (x.p < x.e && *x.p != '>') x.p++; if (x.p < x.e) x.p++; }
    return x_value(x, out, 0);
}

/* ======================================================================= the bundle */
struct App {
    std::wstring path;   /* ...\X.app */
    PVal info;
    std::string id, name, exe, version;
};
static bool load_app(const std::wstring &arg, App &a) {
    wchar_t full[MAX_PATH * 2];
    if (!GetFullPathNameW(arg.c_str(), MAX_PATH * 2, full, nullptr)) return false;
    a.path = full;
    while (!a.path.empty() && (a.path.back() == L'\\' || a.path.back() == L'/')) a.path.pop_back();
    if (!is_dir(a.path) || !read_plist(a.path + L"\\Contents\\Info.plist", a.info) || a.info.t != PVal::DICT) return false;
    std::wstring leaf = a.path.substr(a.path.find_last_of(L"\\/") + 1);
    if (leaf.size() > 4 && !_wcsicmp(leaf.c_str() + leaf.size() - 4, L".app")) leaf.resize(leaf.size() - 4);
    a.id = a.info.str("CFBundleIdentifier"); if (a.id.empty()) a.id = utf8(leaf);
    a.name = a.info.str("CFBundleDisplayName"); if (a.name.empty()) a.name = a.info.str("CFBundleName"); if (a.name.empty()) a.name = utf8(leaf);
    a.exe = a.info.str("CFBundleExecutable"); if (a.exe.empty()) a.exe = utf8(leaf);
    a.version = a.info.str("CFBundleShortVersionString");
    return true;
}
static std::wstring data_dir(const wchar_t *sub) { /* %LOCALAPPDATA%\scion\<sub> */
    wchar_t *la = nullptr; std::wstring d;
    if (SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &la) == S_OK) d = la;
    CoTaskMemFree(la);
    d += L"\\scion"; CreateDirectoryW(d.c_str(), nullptr);
    d += L"\\"; d += sub; CreateDirectoryW(d.c_str(), nullptr);
    return d;
}
static std::wstring safe_name(std::string s) { for (char &c : s) if (strchr("<>:\"/\\|?*", c)) c = '_'; return widen(s); }

/* scion App.app: the executable to run, and what the run needs from the bundle */
std::string mw_bundle_executable(const std::string &arg) {
    App a;
    if (!load_app(widen(arg), a)) return "";
    std::wstring exe = a.path + L"\\Contents\\MacOS\\" + widen(a.exe);
    if (GetFileAttributesW(exe.c_str()) == INVALID_FILE_ATTRIBUTES) return "";
    g_bundle_id = a.id;
    std::wstring ico = data_dir(L"icons") + L"\\" + safe_name(a.id) + L".ico";
    if (GetFileAttributesW(ico.c_str()) != INVALID_FILE_ATTRIBUTES) g_app_icon = ico;
    /* one taskbar button and the pinned shortcut's icon for this app, not for scion */
    SetCurrentProcessExplicitAppUserModelID(widen("scion." + a.id).c_str());
    return utf8(exe);
}

/* ======================================================================= icon: .icns -> .ico (the PNG images it carries) */
static std::string icns_to_ico(const std::string &icns) {
    struct Img { unsigned w; std::string png; };
    std::vector<Img> imgs;
    if (icns.size() < 8 || memcmp(icns.data(), "icns", 4)) return "";
    size_t pos = 8, end = std::min<size_t>(icns.size(), be((const uint8_t *)icns.data() + 4, 4));
    while (pos + 8 <= end) {
        uint32_t len = (uint32_t)be((const uint8_t *)icns.data() + pos + 4, 4);
        if (len < 8 || pos + len > end) break;
        std::string data = icns.substr(pos + 8, len - 8);
        if (data.size() > 24 && !memcmp(data.data(), "\x89PNG", 4)) {
            unsigned w = (unsigned)be((const uint8_t *)data.data() + 16, 4);
            bool have = false; for (auto &i : imgs) have |= i.w == w;
            if (w >= 16 && w <= 256 && !have) imgs.push_back({w, data});
        }
        pos += len;
    }
    if (imgs.empty()) return "";
    std::string ico(6, 0); ico[2] = 1; ico[4] = (char)imgs.size();
    size_t off = 6 + 16 * imgs.size();
    for (auto &i : imgs) {
        uint8_t e[16] = {(uint8_t)(i.w >= 256 ? 0 : i.w), (uint8_t)(i.w >= 256 ? 0 : i.w), 0, 0, 1, 0, 32, 0};
        uint32_t sz = (uint32_t)i.png.size(), o = (uint32_t)off;
        memcpy(e + 8, &sz, 4); memcpy(e + 12, &o, 4);
        ico.append((const char *)e, 16); off += sz;
    }
    for (auto &i : imgs) ico += i.png;
    return ico;
}
static std::wstring install_icon(const App &a) {
    std::string name = a.info.str("CFBundleIconFile");
    if (name.empty()) name = a.info.str("CFBundleIconName");
    if (name.empty()) return L"";
    if (name.size() < 5 || _stricmp(name.c_str() + name.size() - 5, ".icns")) name += ".icns";
    std::string icns; if (!read_file(a.path + L"\\Contents\\Resources\\" + widen(name), icns)) return L"";
    std::string ico = icns_to_ico(icns); if (ico.empty()) return L"";
    std::wstring out = data_dir(L"icons") + L"\\" + safe_name(a.id) + L".ico";
    return write_file(out, ico) ? out : L"";
}

/* ======================================================================= registry (current user only) */
static void reg_set(HKEY root, const std::wstring &key, const wchar_t *name, const std::wstring &val) {
    HKEY h; if (RegCreateKeyExW(root, key.c_str(), 0, nullptr, 0, KEY_WRITE, nullptr, &h, nullptr)) return;
    RegSetValueExW(h, name, 0, REG_SZ, (const BYTE *)val.c_str(), (DWORD)((val.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(h);
}
static void reg_dword(HKEY root, const std::wstring &key, const wchar_t *name, DWORD v) {
    HKEY h; if (RegCreateKeyExW(root, key.c_str(), 0, nullptr, 0, KEY_WRITE, nullptr, &h, nullptr)) return;
    RegSetValueExW(h, name, 0, REG_DWORD, (const BYTE *)&v, sizeof v); RegCloseKey(h);
}
static std::wstring reg_get(HKEY root, const std::wstring &key, const wchar_t *name) {
    wchar_t buf[4096]; DWORD sz = sizeof buf;
    if (RegGetValueW(root, key.c_str(), name, RRF_RT_REG_SZ, nullptr, buf, &sz)) return L"";
    return buf;
}
static std::wstring exe_path() { wchar_t b[MAX_PATH * 2]; GetModuleFileNameW(nullptr, b, MAX_PATH * 2); return b; }
static std::wstring launcher() { /* scionw.exe (no console window) next to scion.exe */
    std::wstring e = exe_path(), w = e.substr(0, e.find_last_of(L'\\')) + L"\\scionw.exe";
    return GetFileAttributesW(w.c_str()) != INVALID_FILE_ATTRIBUTES ? w : e;
}
static std::vector<std::string> document_extensions(const App &a) {
    std::vector<std::string> out;
    const PVal *types = a.info.get("CFBundleDocumentTypes");
    if (!types || types->t != PVal::ARR) return out;
    for (auto &t : types->a) {
        const PVal *exts = t.get("CFBundleTypeExtensions");
        if (!exts || exts->t != PVal::ARR) continue;
        for (auto &e : exts->a) if (e.t == PVal::STR && !e.s.empty() && e.s != "*" && e.s.find_first_of("\\/.") == std::string::npos) {
            bool have = false; for (auto &o : out) have |= !_stricmp(o.c_str(), e.s.c_str());
            if (!have) out.push_back(e.s);
        }
    }
    return out;
}
static std::wstring shortcut_path(const std::string &name) {
    wchar_t *pr = nullptr; std::wstring d;
    if (SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &pr) == S_OK) d = pr;
    CoTaskMemFree(pr);
    return d + L"\\" + safe_name(name) + L".lnk";
}
static bool make_shortcut(const std::wstring &lnk, const App &a, const std::wstring &icon) {
    IShellLinkW *sl = nullptr;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW, (void **)&sl))) return false;
    sl->SetPath(launcher().c_str());
    sl->SetArguments((L"\"" + a.path + L"\"").c_str());
    sl->SetWorkingDirectory(a.path.substr(0, a.path.find_last_of(L'\\')).c_str());
    sl->SetDescription(widen(a.name).c_str());
    if (!icon.empty()) sl->SetIconLocation(icon.c_str(), 0);
    IPropertyStore *ps = nullptr; /* AppUserModelID: the running app's taskbar button belongs to this shortcut */
    if (SUCCEEDED(sl->QueryInterface(IID_IPropertyStore, (void **)&ps))) {
        std::wstring aumid = widen("scion." + a.id);
        PROPVARIANT pv{}; pv.vt = VT_LPWSTR; pv.pwszVal = aumid.data();
        ps->SetValue(PKEY_AppUserModel_ID, pv); ps->Commit(); ps->Release();
    }
    IPersistFile *pf = nullptr; bool ok = false;
    if (SUCCEEDED(sl->QueryInterface(IID_IPersistFile, (void **)&pf))) { ok = SUCCEEDED(pf->Save(lnk.c_str(), TRUE)); pf->Release(); }
    sl->Release();
    return ok;
}

static int install(const std::wstring &arg) {
    App a;
    if (!load_app(arg, a)) { fprintf(stderr, "scion: %s is not a macOS app (Contents/Info.plist is missing)\n", utf8(arg).c_str()); return 1; }
    if (GetFileAttributesW((a.path + L"\\Contents\\MacOS\\" + widen(a.exe)).c_str()) == INVALID_FILE_ATTRIBUTES) {
        fprintf(stderr, "scion: the executable Contents/MacOS/%s is missing\n", a.exe.c_str()); return 1;
    }
    std::wstring icon = install_icon(a), lnk = shortcut_path(a.name), progid = widen("scion." + a.id);
    std::wstring run = L"\"" + launcher() + L"\" \"" + a.path + L"\"";
    if (!make_shortcut(lnk, a, icon)) { fprintf(stderr, "scion: could not create the shortcut\n"); return 1; }
    /* document types: offered in "Open with", the user's defaults are left alone */
    std::vector<std::string> exts = document_extensions(a);
    std::wstring cls = L"Software\\Classes\\" + progid, list;
    if (!exts.empty()) {
        reg_set(HKEY_CURRENT_USER, cls, nullptr, widen(a.name));
        reg_set(HKEY_CURRENT_USER, cls + L"\\shell\\open\\command", nullptr, run + L" \"%1\"");
        if (!icon.empty()) reg_set(HKEY_CURRENT_USER, cls + L"\\DefaultIcon", nullptr, icon);
        for (auto &e : exts) {
            reg_set(HKEY_CURRENT_USER, L"Software\\Classes\\." + widen(e) + L"\\OpenWithProgids", progid.c_str(), L"");
            list += widen(e) + L";";
        }
    }
    /* Windows' installed apps */
    std::wstring un = L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" + progid;
    reg_set(HKEY_CURRENT_USER, un, L"DisplayName", widen(a.name));
    reg_set(HKEY_CURRENT_USER, un, L"DisplayVersion", widen(a.version));
    reg_set(HKEY_CURRENT_USER, un, L"Publisher", L"scion");
    reg_set(HKEY_CURRENT_USER, un, L"InstallLocation", a.path);
    reg_set(HKEY_CURRENT_USER, un, L"UninstallString", L"\"" + exe_path() + L"\" uninstall " + widen(a.id));
    if (!icon.empty()) reg_set(HKEY_CURRENT_USER, un, L"DisplayIcon", icon);
    reg_dword(HKEY_CURRENT_USER, un, L"NoModify", 1); reg_dword(HKEY_CURRENT_USER, un, L"NoRepair", 1);
    /* what uninstall needs */
    std::wstring rec = L"Software\\scion\\Apps\\" + widen(a.id);
    reg_set(HKEY_CURRENT_USER, rec, L"Path", a.path); reg_set(HKEY_CURRENT_USER, rec, L"Shortcut", lnk);
    reg_set(HKEY_CURRENT_USER, rec, L"Icon", icon); reg_set(HKEY_CURRENT_USER, rec, L"Extensions", list);
    reg_set(HKEY_CURRENT_USER, rec, L"Name", safe_name(a.name));
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
    printf("%s installed (%s)\n  shortcut: %s\n  icon: %s\n", a.name.c_str(), a.id.c_str(), utf8(lnk).c_str(), icon.empty() ? "(no .icns with PNG images)" : utf8(icon).c_str());
    if (!exts.empty()) { printf("  opens: "); for (auto &e : exts) printf(".%s ", e.c_str()); printf("\n"); }
    return 0;
}
static int uninstall(const std::wstring &arg) {
    std::wstring id = arg;
    App a; if (load_app(arg, a)) id = widen(a.id);
    std::wstring rec = L"Software\\scion\\Apps\\" + id, progid = L"scion." + id;
    std::wstring lnk = reg_get(HKEY_CURRENT_USER, rec, L"Shortcut");
    if (lnk.empty()) { fprintf(stderr, "scion: %s is not installed\n", utf8(id).c_str()); return 1; }
    DeleteFileW(lnk.c_str());
    /* under Wine the shortcut became a .desktop file (winemenubuilder), which Wine leaves behind: remove it too */
    if (GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "wine_get_version")) {
        std::wstring base; /* Wine hides HOME but gives it as WINEHOMEDIR (\??\Z:\home\user) */
        if (const wchar_t *x = _wgetenv(L"XDG_DATA_HOME")) { base = std::wstring(L"Z:") + x; for (auto &c : base) if (c == L'/') c = L'\\'; }
        else if (const wchar_t *h = _wgetenv(L"WINEHOMEDIR")) { base = h; if (base.rfind(L"\\??\\", 0) == 0) base = base.substr(4); base += L"\\.local\\share"; }
        if (!base.empty()) DeleteFileW((base + L"\\applications\\wine\\Programs\\" + reg_get(HKEY_CURRENT_USER, rec, L"Name") + L".desktop").c_str());
    }
    std::wstring icon = reg_get(HKEY_CURRENT_USER, rec, L"Icon"); if (!icon.empty()) DeleteFileW(icon.c_str());
    std::wstring list = reg_get(HKEY_CURRENT_USER, rec, L"Extensions");
    for (size_t p = 0, q; (q = list.find(L';', p)) != std::wstring::npos; p = q + 1) {
        HKEY h;
        if (!RegOpenKeyExW(HKEY_CURRENT_USER, (L"Software\\Classes\\." + list.substr(p, q - p) + L"\\OpenWithProgids").c_str(), 0, KEY_SET_VALUE, &h)) {
            RegDeleteValueW(h, progid.c_str()); RegCloseKey(h);
        }
    }
    RegDeleteTreeW(HKEY_CURRENT_USER, (L"Software\\Classes\\" + progid).c_str());
    RegDeleteTreeW(HKEY_CURRENT_USER, (L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" + progid).c_str());
    RegDeleteTreeW(HKEY_CURRENT_USER, rec.c_str());
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
    printf("%s uninstalled (the app itself stays in its folder)\n", utf8(id).c_str());
    return 0;
}

/* scion install|uninstall ...: handled here, before any guest is loaded */
bool mw_subcommand(int argc, wchar_t **argv, int *rc) {
    bool ins = !wcscmp(argv[1], L"install");
    bool des = !wcscmp(argv[1], L"uninstall");
    if (!ins && !des) return false;
    if (argc < 3) { fprintf(stderr, "usage: scion %s <App.app>%s\n", ins ? "install" : "uninstall", ins ? "" : " | <bundle id>"); *rc = 2; return true; }
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    *rc = ins ? install(argv[2]) : uninstall(argv[2]);
    CoUninitialize();
    return true;
}
