/* fontnames.h — the names in a TrueType/OpenType font file (or collection), and turning the names apps ask for
 * ("Inter-SemiBold", "ArialMT", "HelveticaNeue-Bold") into a family, a weight and a slant. For ui.cpp and ui_linux.cpp. */
#pragma once
#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <vector>

struct FontFace { std::string family, style, full, postscript; int weight = 400; bool italic = false; };

static inline uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static inline uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }

static inline bool style_has(const std::string &s, const char *w) {
    std::string a, b(w);
    for (char c : s) if (c != ' ' && c != '-' && c != '_') a += (char)tolower((unsigned char)c);
    for (char &c : b) c = (char)tolower((unsigned char)c);
    return a.find(b) != std::string::npos;
}
/* the weight (100..900) and slant a style name says ("Bold Italic", "SemiBold", "Light") */
static inline void style_traits(const std::string &style, int &weight, bool &italic) {
    if (style_has(style, "italic") || style_has(style, "oblique")) italic = true;
    if (style_has(style, "thin") || style_has(style, "hairline")) weight = 100;
    else if (style_has(style, "extralight") || style_has(style, "ultralight")) weight = 200;
    else if (style_has(style, "light")) weight = 300;
    else if (style_has(style, "medium")) weight = 500;
    else if (style_has(style, "semibold") || style_has(style, "demibold")) weight = 600;
    else if (style_has(style, "extrabold") || style_has(style, "ultrabold")) weight = 800;
    else if (style_has(style, "black") || style_has(style, "heavy")) weight = 900;
    else if (style_has(style, "bold")) weight = 700;
}

/* the faces of a font file in memory; empty if it is not one */
static inline std::vector<FontFace> sfnt_faces(const uint8_t *d, size_t n) {
    std::vector<FontFace> out;
    std::vector<uint32_t> offs;
    if (n >= 12 && !memcmp(d, "ttcf", 4)) {
        uint32_t k = be32(d + 8);
        for (uint32_t i = 0; i < k && 12 + 4 * i + 4 <= n; i++) offs.push_back(be32(d + 12 + 4 * i));
    } else offs.push_back(0);
    for (uint32_t o : offs) {
        if (o + 12 > n) continue;
        uint32_t ver = be32(d + o);
        if (ver != 0x00010000 && ver != 0x4F54544F /* OTTO */ && ver != 0x74727565 /* true */) continue;
        uint16_t tables = be16(d + o + 4);
        const uint8_t *name = nullptr; uint32_t name_len = 0;
        for (uint16_t t = 0; t < tables && o + 12 + 16 * (t + 1) <= n; t++) {
            const uint8_t *r = d + o + 12 + 16 * t;
            if (!memcmp(r, "name", 4) && be32(r + 8) + be32(r + 12) <= n) { name = d + be32(r + 8); name_len = be32(r + 12); }
        }
        if (!name || name_len < 6) continue;
        uint16_t count = be16(name + 2), soff = be16(name + 4);
        std::string ids[17]; int prio[17] = {0};
        for (uint32_t i = 0; i < count && 6 + 12 * (i + 1) <= name_len; i++) {
            const uint8_t *r = name + 6 + 12 * i;
            uint16_t plat = be16(r), enc = be16(r + 2), lang = be16(r + 4), id = be16(r + 6), len = be16(r + 8), at = be16(r + 10);
            if (id > 16 || (size_t)soff + at + len > name_len) continue;
            const uint8_t *s = name + soff + at;
            std::string v; int p;
            if (plat == 3 || plat == 0) {   /* UTF-16BE; English first */
                p = plat == 3 && lang == 0x409 ? 3 : 2;
                for (uint16_t k = 0; k + 1 < len; k += 2) {
                    uint32_t c = be16(s + k);
                    if (c < 0x80) v += (char)c;
                    else if (c < 0x800) { v += (char)(0xC0 | c >> 6); v += (char)(0x80 | (c & 63)); }
                    else { v += (char)(0xE0 | c >> 12); v += (char)(0x80 | (c >> 6 & 63)); v += (char)(0x80 | (c & 63)); }
                }
                (void)enc;
            } else if (plat == 1 && enc == 0) { p = 1; v.assign((const char *)s, len); }   /* Mac Roman: ASCII names */
            else continue;
            if (p > prio[id]) { prio[id] = p; ids[id] = v; }
        }
        FontFace f;
        f.family = ids[1]; f.style = ids[2].empty() ? "Regular" : ids[2]; f.full = ids[4]; f.postscript = ids[6];
        if (f.family.empty()) continue;
        if (f.postscript.empty()) { f.postscript = f.family + "-" + f.style; f.postscript.erase(std::remove(f.postscript.begin(), f.postscript.end(), ' '), f.postscript.end()); }
        style_traits(f.style, f.weight, f.italic);
        out.push_back(f);
    }
    return out;
}

/* fonts registered by the app (CTFontManagerRegisterFontsForURL, ATSApplicationFontsPath): their names, lower case */
struct FontRegistry {
    std::mutex m;
    std::map<std::string, FontFace> by_name;
    void add(const FontFace &f) {
        std::lock_guard<std::mutex> l(m);
        for (const std::string *k : {&f.postscript, &f.full}) if (!k->empty()) by_name[lower(*k)] = f;
    }
    bool find(const std::string &name, FontFace &out) {
        std::lock_guard<std::mutex> l(m);
        auto it = by_name.find(lower(name));
        if (it == by_name.end()) return false;
        out = it->second;
        return true;
    }
    static std::string lower(std::string s) { for (char &c : s) c = (char)tolower((unsigned char)c); return s; }
};

/* the families a name may stand for, most likely first: "Inter-SemiBold" -> Inter; "ArialMT" -> Arial;
 * "HelveticaNeue-Bold" -> HelveticaNeue, Helvetica Neue; and the weight and slant its style part says */
static inline std::vector<std::string> font_candidates(const std::string &name, int &weight, bool &italic) {
    std::vector<std::string> out;
    std::string base = name, style;
    size_t dash = name.find('-');
    if (dash != std::string::npos) { base = name.substr(0, dash); style = name.substr(dash + 1); }
    if (!style.empty()) { int w = weight; style_traits(style, w, italic); if (w != 400) weight = w; }
    for (const char *suf : {"PSMT", "MT", "PS"})
        if (base.size() > strlen(suf) + 1 && base.compare(base.size() - strlen(suf), strlen(suf), suf) == 0) { base.erase(base.size() - strlen(suf)); break; }
    if (base.empty() || base[0] == '.') return out;
    out.push_back(base);
    std::string spaced;   /* CamelCase -> Camel Case */
    for (size_t i = 0; i < base.size(); i++) {
        if (i && isupper((unsigned char)base[i]) && islower((unsigned char)base[i - 1])) spaced += ' ';
        spaced += base[i];
    }
    if (spaced != base) out.push_back(spaced);
    return out;
}
