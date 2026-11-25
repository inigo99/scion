/* bundle.h — what the host reads from an app bundle before any guest code runs: Info.plist (XML and binary) and the
 * PNG images of an .icns. Shared by install.cpp (Windows) and install_linux.cpp. */
#pragma once
#include <string>
#include <vector>
#include <cstring>
#include <cstdint>
#include <algorithm>
#include <cstdlib>

static std::string cp_utf8(uint32_t c) {
    std::string o;
    if (c < 0x80) o += (char)c;
    else if (c < 0x800) { o += (char)(0xC0 | c >> 6); o += (char)(0x80 | (c & 0x3F)); }
    else if (c < 0x10000) { o += (char)(0xE0 | c >> 12); o += (char)(0x80 | ((c >> 6) & 0x3F)); o += (char)(0x80 | (c & 0x3F)); }
    else { o += (char)(0xF0 | c >> 18); o += (char)(0x80 | ((c >> 12) & 0x3F)); o += (char)(0x80 | ((c >> 6) & 0x3F)); o += (char)(0x80 | (c & 0x3F)); }
    return o;
}

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
            out += cp_utf8((uint32_t)c);
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
        if (hi == 5) { for (uint64_t i = 0; i < cnt; i++) v.s += cp_utf8(r.b[pos + i]); }
        else if (hi == 6)   /* UTF-16 BE */
            for (uint64_t i = 0; i < cnt; i++) {
                uint32_t c = (uint32_t)be(r.b + pos + i * 2, 2);
                if (c >= 0xD800 && c < 0xDC00 && i + 1 < cnt) { uint32_t d = (uint32_t)be(r.b + pos + (i + 1) * 2, 2); if (d >= 0xDC00 && d < 0xE000) { c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00); i++; } }
                v.s += cp_utf8(c);
            }
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
static bool parse_plist(const std::string &f, PVal &out) {
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

/* the PNG images an .icns carries (modern ones do, 16 to 1024 px), one per width */
struct IcnsPng { unsigned w; std::string png; };
static std::vector<IcnsPng> icns_pngs(const std::string &icns) {
    std::vector<IcnsPng> imgs;
    if (icns.size() < 8 || memcmp(icns.data(), "icns", 4)) return imgs;
    size_t pos = 8, end = std::min<size_t>(icns.size(), be((const uint8_t *)icns.data() + 4, 4));
    while (pos + 8 <= end) {
        uint32_t len = (uint32_t)be((const uint8_t *)icns.data() + pos + 4, 4);
        if (len < 8 || pos + len > end) break;
        std::string data = icns.substr(pos + 8, len - 8);
        if (data.size() > 24 && !memcmp(data.data(), "\x89PNG", 4)) {
            unsigned w = (unsigned)be((const uint8_t *)data.data() + 16, 4);
            bool have = false; for (auto &i : imgs) have |= i.w == w;
            if (w >= 16 && !have) imgs.push_back({w, data});
        }
        pos += len;
    }
    return imgs;
}
