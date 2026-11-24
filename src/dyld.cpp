/* dyld.cpp — dyld-lite: maps Mach-O images, rebases, binds, exports, TLV, initializers. */
#include "scion.h"

/* ======================================================================= Mach-O */
#define MH_MAGIC_64 0xfeedfacfu
#define FAT_CIGAM 0xbebafecau
enum { LC_SEGMENT_64 = 0x19, LC_UNIXTHREAD = 0x5, LC_DYLD_INFO_ONLY = 0x80000022, LC_MAIN = 0x80000028,
       LC_DYLD_EXPORTS_TRIE = 0x80000033, LC_DYLD_CHAINED_FIXUPS = 0x80000034,
       LC_LOAD_DYLIB = 0xc, LC_ID_DYLIB = 0xd, LC_LOAD_WEAK_DYLIB = 0x80000018, LC_REEXPORT_DYLIB = 0x8000001f,
       LC_LAZY_LOAD_DYLIB = 0x20, LC_LOAD_UPWARD_DYLIB = 0x80000023, LC_RPATH = 0x8000001c };
struct mh64 { uint32_t magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved; };

static uint64_t uleb(const uint8_t *&p) { uint64_t r = 0; int s = 0; uint8_t b; do { b = *p++; r |= (uint64_t)(b & 0x7f) << s; s += 7; } while (b & 0x80); return r; }
static int64_t sleb(const uint8_t *&p) { int64_t r = 0; int s = 0; uint8_t b; do { b = *p++; r |= (int64_t)(b & 0x7f) << s; s += 7; } while (b & 0x80); if (s < 64 && (b & 0x40)) r |= -((int64_t)1 << s); return r; }
static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }


static bool load_file(const std::string &path, std::vector<uint8_t> &out) {
    FILE *f = fopen(path.c_str(), "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    out.resize(n);
    bool ok = fread(out.data(), 1, n, f) == (size_t)n;
    fclose(f);
    return ok;
}

/* want: 0 = prefer x86_64 (native), else the cputype to require */
static uint8_t *pick_slice(std::vector<uint8_t> &f, uint32_t want) {
    if (f.size() < 8) return nullptr;
    if (*(uint32_t *)f.data() == FAT_CIGAM) {
        uint32_t n = be32(&f[4]); uint8_t *fallback = nullptr;
        for (uint32_t i = 0; i < n; i++) {
            uint32_t cpu = be32(&f[8 + i * 20]); uint8_t *p = f.data() + be32(&f[8 + i * 20 + 8]);
            if (want ? cpu == want : cpu == CPU_X86_64) return p;
            if (!want && cpu == CPU_ARM64) fallback = p;
        }
        return fallback;
    }
    mh64 *h = (mh64 *)f.data();
    if (h->magic != MH_MAGIC_64) return nullptr;
    return (!want || h->cputype == want) ? f.data() : nullptr;
}

static void parse_exports(Image &im, const uint8_t *trie, uint64_t mh_rt) {
    struct Node { uint32_t off; std::string prefix; };
    std::vector<Node> st{{0, ""}};
    while (!st.empty()) {
        Node n = st.back(); st.pop_back();
        const uint8_t *p = trie + n.off;
        uint64_t term = uleb(p);
        const uint8_t *children = p + term;
        if (term) {
            uint64_t flags = uleb(p);
            if (flags & 0x08) { /* EXPORT_SYMBOL_FLAGS_REEXPORT: ordinal + optional import name */
                int ord = (int)uleb(p); std::string imp((const char *)p);
                im.reexported[n.prefix] = {ord, imp.empty() ? n.prefix : imp};
            } else {
                uint64_t off = uleb(p); /* ponytail: STUB_AND_RESOLVER exports use the stub address */
                im.syms[n.prefix] = (flags & 3) == 2 ? off /* absolute */ : mh_rt + off;
            }
        }
        p = children;
        uint8_t nc = *p++;
        for (uint8_t i = 0; i < nc; i++) {
            std::string edge((const char *)p); p += edge.size() + 1;
            st.push_back({(uint32_t)uleb(p), n.prefix + edge});
        }
    }
}

Image *map_image(const std::string &path, uint32_t want) {
    Image *im = new Image;
    im->path = path;
    if (!load_file(path, im->file)) { delete im; return nullptr; }
    im->mh = pick_slice(im->file, want);
    if (!im->mh) { delete im; return nullptr; }
    mh64 *h = (mh64 *)im->mh;
    im->arm = h->cputype == CPU_ARM64;
    uint64_t lo = UINT64_MAX, hi = 0;
    uint8_t *lc = im->mh + sizeof *h;
    for (uint32_t i = 0; i < h->ncmds; i++, lc += ((uint32_t *)lc)[1]) {
        uint32_t cmd = *(uint32_t *)lc;
        if (cmd == LC_SEGMENT_64) {
            seg64 *s = (seg64 *)lc; im->segs.push_back(s);
            if (!s->maxprot && !s->initprot && !strncmp(s->segname, "__PAGEZERO", 16)) continue;
            lo = std::min(lo, s->vmaddr); hi = std::max(hi, s->vmaddr + s->vmsize);
        } else if (cmd == LC_DYLD_INFO_ONLY) im->di = (dyldinfo *)lc;
        else if (cmd == LC_DYLD_CHAINED_FIXUPS) im->chained = (linkedit *)lc;
        else if (cmd == LC_DYLD_EXPORTS_TRIE) im->exports = (linkedit *)lc;
        else if (cmd == LC_MAIN) im->entry = *(uint64_t *)(lc + 8);
        else if (cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB || cmd == LC_REEXPORT_DYLIB || cmd == LC_LAZY_LOAD_DYLIB || cmd == LC_LOAD_UPWARD_DYLIB) {
            im->dep_names.push_back((const char *)lc + ((uint32_t *)lc)[2]);
            im->dep_weak.push_back(cmd == LC_LOAD_WEAK_DYLIB);
            im->dep_reexport.push_back(cmd == LC_REEXPORT_DYLIB);
        } else if (cmd == LC_ID_DYLIB) im->install_name = (const char *)lc + ((uint32_t *)lc)[2];
        else if (cmd == LC_RPATH) im->rpaths.push_back((const char *)lc + ((uint32_t *)lc)[2]);
        else if (cmd == LC_UNIXTHREAD) {
            uint32_t *t = (uint32_t *)(lc + 8); /* flavor, count, state */
            uint64_t *regs = (uint64_t *)(t + 2);
            im->entry = im->arm ? regs[32] /* pc */ : regs[16] /* rip */;
            im->unixthread = true;
        }
    }
    /* ponytail: one RWX mapping per image; per-segment VirtualProtect when W^X matters */
    uint64_t len = hi - lo;
    im->base = (uint8_t *)image_alloc(lo, len);
    if (!im->base) die("could not map the image");
    im->slide = (int64_t)((uint64_t)im->base - lo);
    im->size = len;
    g_images.push_back(im);
    for (seg64 *s : im->segs)
        if (s->filesize && s->maxprot) memcpy((void *)im->vm(s->vmaddr), im->mh + s->fileoff, s->filesize);
    if (!im->unixthread && im->entry) {
        for (seg64 *s : im->segs) if (!strncmp(s->segname, "__TEXT", 16)) im->entry += s->vmaddr; /* LC_MAIN is an offset */
    }
    im->entry = im->entry ? im->vm(im->entry) : 0;
    if (im->exports) parse_exports(*im, im->mh + im->exports->off, im->mh_rt());
    else if (im->di && im->di->export_size) parse_exports(*im, im->mh + im->di->export_off, im->mh_rt());
    TRACE("%s: %s at %p, %zu exports\n", path.c_str(), im->arm ? "arm64" : "x86_64", im->base, im->syms.size());
    return im;
}

/* ---------------- images and symbol resolution ---------------- */
Image *g_libsys;
std::vector<Image *> g_images;
std::string g_lib_dir;
Image *g_main;
bool guest_pc(uint64_t pc) {
    for (Image *i : g_images) if (pc >= (uint64_t)i->base && pc < (uint64_t)i->base + i->size) return true;
    return false;
}
uint64_t g_missing_stub; /* address that reports an unimplemented import if called */
std::vector<std::string> g_missing;

static uint64_t find_export(Image *im, const std::string &name, int depth = 0) {
    if (!im || depth > 8) return 0;
    auto it = im->syms.find(name);
    if (it != im->syms.end()) return it->second;
    auto re = im->reexported.find(name);
    if (re != im->reexported.end() && re->second.first >= 1 && re->second.first <= (int)im->deps.size())
        return find_export(im->deps[re->second.first - 1], re->second.second, depth + 1);
    for (size_t i = 0; i < im->deps.size(); i++)
        if (im->dep_reexport[i]) if (uint64_t v = find_export(im->deps[i], name, depth + 1)) return v;
    return 0;
}
/* two-level lookup by library ordinal; scion falls back to a flat search because its libraries
 * do not always place a symbol in the same dylib Apple does */
static uint64_t resolve(Image &im, int ord, const char *name, bool weak = false) {
    Image *target = ord > 0 && ord <= (int)im.deps.size() ? im.deps[ord - 1] : ord == 0 ? &im : ord == -1 ? g_main : nullptr;
    if (uint64_t v = find_export(target, name)) return v;
    for (Image *i : g_images) if (i != target) if (uint64_t v = find_export(i, name)) return v;
    if (weak) return 0; /* weak import not provided: NULL, like dyld */
    g_missing.push_back(name);
    return g_missing_stub;
}

static std::string dir_of(const std::string &p) { size_t k = p.find_last_of("\\/"); return k == std::string::npos ? "." : p.substr(0, k); }
#ifdef _WIN32
static bool file_exists(const std::string &p) { DWORD a = GetFileAttributesA(p.c_str()); return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY); }
#else
static bool file_exists(const std::string &p) { struct stat st; return !stat(p.c_str(), &st) && S_ISREG(st.st_mode); }
#endif
static std::string expand(const std::string &p, Image *loader) {
    if (!p.rfind("@executable_path", 0)) return dir_of(g_main->path) + p.substr(16);
    if (!p.rfind("@loader_path", 0)) return dir_of(loader->path) + p.substr(12);
    return p;
}
/* install name -> file on disk. Apple system libraries map to scion's lib directory; anything we do not ship
 * resolves to libSystem, whose stubs (and the flat fallback) take over. */
static std::string locate(const std::string &name, Image *loader) {
    static const std::map<std::string, std::string> alias = {
        {"CoreFoundation", "Foundation"}, {"QuartzCore", "Metal"}, {"MetalFX", "Metal"}, {"Cocoa", "AppKit"}, {"CoreGraphics", "AppKit"}, {"ApplicationServices", "AppKit"},
        {"CoreVideo", "AppKit"}, {"MetalKit", "AppKit"}, {"CoreHaptics", "GameController"}, {"AudioUnit", "AudioToolbox"}, {"CoreAudio", "AudioToolbox"}, {"CoreServices", "Foundation"}, {"EventKit", "Foundation"}, {"ScriptingBridge", "Foundation"}, {"libSystem.B", "libSystem.B"},
        {"libc++abi", "libc++.1"}, {"libc++", "libc++.1"},
    };
    if (!name.rfind("@rpath/", 0)) {
        std::vector<std::string> rp = loader->rpaths;
        rp.insert(rp.end(), g_main->rpaths.begin(), g_main->rpaths.end());
        for (auto &r : rp) { std::string c = expand(r, loader) + "/" + name.substr(7); if (file_exists(c)) return c; }
        /* rpaths into Apple's system (/usr/lib/swift, Xcode toolchains) mean scion's own copy of the library */
        std::string leaf = name.substr(name.find_last_of('/') + 1), c = g_lib_dir + "/" + leaf;
        return leaf.find(".dylib") != std::string::npos && file_exists(c) ? c : "";
    }
    if (name[0] == '@') { std::string c = expand(name, loader); return file_exists(c) ? c : ""; }
    std::string base = name.substr(name.find_last_of('/') + 1);
    size_t dot = base.find(".dylib"); if (dot != std::string::npos) base = base.substr(0, dot);
    auto a = alias.find(base); if (a != alias.end()) base = a->second;
    std::string c = g_lib_dir + "/" + base + ".dylib";
    if (file_exists(c)) return c;
    if (name.size() > 2 && name[0] == '/' && isalpha((unsigned char)name[1]) && name[2] == '/') { /* /c/... */
        std::string w = std::string(1, (char)toupper(name[1])) + ":" + name.substr(2);
        if (file_exists(w)) return w;
    }
    return "";
}
Image *find_image(const char *suffix) {
    for (Image *i : g_images) if (i->path.size() >= strlen(suffix) && !_stricmp(i->path.c_str() + i->path.size() - strlen(suffix), suffix)) return i;
    return nullptr;
}
static Image *load_rec(const std::string &path, uint32_t cpu) {
    for (Image *i : g_images) if (!_stricmp(i->path.c_str(), path.c_str())) return i;
    Image *im = map_image(path, cpu);
    if (!im) die(("no " + std::string(cpu == CPU_ARM64 ? "arm64" : "x86_64") + " slice in " + path).c_str());
    for (size_t k = 0; k < im->dep_names.size(); k++) {
        std::string f = locate(im->dep_names[k], im);
        Image *d = f.empty() ? nullptr : load_rec(f, cpu);
        if (!d && !im->dep_weak[k]) {
            TRACE("%s -> %s (not shipped: resolved in libSystem)\n", im->dep_names[k].c_str(), f.c_str());
            d = g_libsys ? g_libsys : load_rec(g_lib_dir + "/libSystem.B.dylib", cpu);
        }
        im->deps.push_back(d);
    }
    return im;
}
Image *load_all(const std::string &main_path) {
    std::vector<uint8_t> probe;
    /* SCION_ARCH=arm64 (or x86_64) picks that slice of a universal program instead of the native x86_64 one */
    const char *arch = getenv("SCION_ARCH");
    Image *main = map_image(main_path, arch && !strcmp(arch, "arm64") ? CPU_ARM64 : arch && !strcmp(arch, "x86_64") ? CPU_X86_64 : 0);
    if (!main) return nullptr;
    g_main = main;
    uint32_t cpu = main->arm ? CPU_ARM64 : CPU_X86_64;
    g_libsys = load_rec(g_lib_dir + "/libSystem.B.dylib", cpu);
    if (!g_libsys) die("lib/libSystem.B.dylib is missing next to scion");
    for (size_t k = 0; k < main->dep_names.size(); k++) {
        std::string f = locate(main->dep_names[k], main);
        Image *d = f.empty() ? nullptr : load_rec(f, cpu);
        if (!d && !main->dep_weak[k]) d = g_libsys;
        main->deps.push_back(d);
    }
    return main;
}

static void do_rebase(Image &im, const uint8_t *p, const uint8_t *end) {
    uint64_t addr = 0;
    auto fix = [&](uint64_t a) { *(uint64_t *)im.vm(a) += im.slide; };
    while (p < end) {
        uint8_t op = *p & 0xf0, imm = *p & 0x0f; p++;
        uint64_t n, skip;
        switch (op) {
        case 0x00: return;
        case 0x10: break;
        case 0x20: addr = im.segs[imm]->vmaddr + uleb(p); break;
        case 0x30: addr += uleb(p); break;
        case 0x40: addr += imm * 8; break;
        case 0x50: for (n = imm; n--; addr += 8) fix(addr); break;
        case 0x60: for (n = uleb(p); n--; addr += 8) fix(addr); break;
        case 0x70: fix(addr); addr += 8 + uleb(p); break;
        case 0x80: n = uleb(p); skip = uleb(p); for (; n--; addr += 8 + skip) fix(addr); break;
        default: die("unknown rebase opcode");
        }
    }
}

static void do_bind(Image &im, const uint8_t *p, const uint8_t *end, bool lazy) {
    uint64_t addr = 0; int64_t addend = 0; const char *sym = ""; bool weak = false; int ord = 0;
    auto bind = [&]() { uint64_t v = resolve(im, ord, sym, weak); *(uint64_t *)im.vm(addr) = v ? v + addend : 0; };
    while (p < end) {
        uint8_t op = *p & 0xf0, imm = *p & 0x0f; p++;
        uint64_t n, skip;
        switch (op) {
        case 0x00: if (!lazy) return; break;
        case 0x10: ord = imm; break;
        case 0x20: ord = (int)uleb(p); break;
        case 0x30: ord = imm ? (int)(int8_t)(0xF0 | imm) : 0; break;
        case 0x50: break;
        case 0x40: weak = imm & 1; sym = (const char *)p; p += strlen(sym) + 1; break;
        case 0x60: addend = sleb(p); break;
        case 0x70: addr = im.segs[imm]->vmaddr + uleb(p); break;
        case 0x80: addr += uleb(p); break;
        case 0x90: bind(); addr += 8; break;
        case 0xA0: bind(); addr += 8 + uleb(p); break;
        case 0xB0: bind(); addr += 8 + imm * 8; break;
        case 0xC0: n = uleb(p); skip = uleb(p); for (; n--; addr += 8 + skip) bind(); break;
        default: die("unknown bind opcode");
        }
    }
}

/* LC_DYLD_CHAINED_FIXUPS: pointer formats DYLD_CHAINED_PTR_64 (2) and _64_OFFSET (6) */
static void do_chained(Image &im) {
    const uint8_t *hdr = im.mh + im.chained->off;
    uint32_t starts_off = *(uint32_t *)(hdr + 4), imports_off = *(uint32_t *)(hdr + 8), symbols_off = *(uint32_t *)(hdr + 12);
    uint32_t nimports = *(uint32_t *)(hdr + 16), ifmt = *(uint32_t *)(hdr + 20);
    std::vector<uint64_t> targets(nimports);
    std::vector<int64_t> addends(nimports);
    for (uint32_t i = 0; i < nimports; i++) {
        uint32_t name_off; int64_t add = 0; bool weak; int ord;
        if (ifmt == 1) { uint32_t e = ((uint32_t *)(hdr + imports_off))[i]; name_off = e >> 9; weak = (e >> 8) & 1; ord = (int8_t)(e & 0xFF); }
        else if (ifmt == 2) { const uint32_t *e = (uint32_t *)(hdr + imports_off) + i * 2; name_off = e[0] >> 9; weak = (e[0] >> 8) & 1; ord = (int8_t)(e[0] & 0xFF); add = (int32_t)e[1]; }
        else { const uint64_t *e = (uint64_t *)(hdr + imports_off) + i * 2; name_off = (uint32_t)(e[0] >> 32); weak = (e[0] >> 16) & 1; ord = (int16_t)(e[0] & 0xFFFF); add = (int64_t)e[1]; }
        if (ifmt != 3) { uint32_t v = (uint8_t)ord; ord = v >= 0xF0 ? (int8_t)v : (int)v; } /* 0xFD..0xFF are the special ordinals */
        else { uint32_t v = (uint16_t)ord; ord = v >= 0xFFF0 ? (int16_t)v : (int)v; }
        targets[i] = resolve(im, ord, (const char *)hdr + symbols_off + name_off, weak);
        addends[i] = add;
    }
    const uint8_t *starts = hdr + starts_off;
    uint32_t nseg = *(uint32_t *)starts;
    for (uint32_t s = 0; s < nseg; s++) {
        uint32_t off = ((uint32_t *)(starts + 4))[s];
        if (!off) continue;
        const uint8_t *si = starts + off;
        uint16_t page_size = *(uint16_t *)(si + 4), fmt = *(uint16_t *)(si + 6);
        uint64_t seg_off = *(uint64_t *)(si + 8);
        uint16_t npages = *(uint16_t *)(si + 20);
        const uint16_t *pstart = (const uint16_t *)(si + 22);
        if (fmt != 2 && fmt != 6) die("unsupported chained fixups format (arm64e?)");
        uint64_t mh_rt = im.mh_rt(), seg_base = mh_rt + seg_off; /* segment_offset is relative to the mach header */
        for (uint16_t pg = 0; pg < npages; pg++) {
            if (pstart[pg] == 0xFFFF) continue;
            uint64_t *loc = (uint64_t *)(seg_base + (uint64_t)pg * page_size + pstart[pg]);
            for (;;) {
                uint64_t v = *loc, next = (v >> 51) & 0xFFF;
                if (v >> 63) { /* bind */
                    uint32_t ord = v & 0xFFFFFF; int64_t add = (int64_t)((v >> 24) & 0xFF);
                    *loc = targets[ord] ? targets[ord] + addends[ord] + add : 0;
                } else {       /* rebase */
                    uint64_t target = v & 0xFFFFFFFFFull, high8 = (v >> 36) & 0xFF;
                    *loc = (fmt == 6 ? mh_rt + target : target + im.slide) | high8 << 56;
                }
                if (!next) break;
                loc = (uint64_t *)((uint8_t *)loc + next * 4);
            }
        }
    }
}

void link_image(Image &im) {
    if (im.chained) do_chained(im);
    else if (im.di) {
        if (im.slide) do_rebase(im, im.mh + im.di->rebase_off, im.mh + im.di->rebase_off + im.di->rebase_size);
        do_bind(im, im.mh + im.di->bind_off, im.mh + im.di->bind_off + im.di->bind_size, false);
        do_bind(im, im.mh + im.di->lazy_off, im.mh + im.di->lazy_off + im.di->lazy_size, true);
        /* weak-definition table: only rebind when libSystem provides a stronger definition */
    }
}

/* Darwin x86_64 code may address TSD slots directly through %gs (Go: gs:0x30 holds g).
 * On Windows %gs is the TEB, so rewrite those displacements into TEB.TlsSlots[idx].
 * Pattern: 65 REX.W (8B|89|C7) modrm(mod=00,rm=100) SIB=25 disp32
 * ponytail: byte-pattern scan of __text; switch to a real decoder (Zydis is already linked) if false hits appear */
int patch_gs_tsd(Image &im, DWORD tls_idx) {
    if (im.arm) return 0;
    uint32_t newdisp = 0x1480 + 8 * tls_idx;
    int n = 0;
    for (seg64 *s : im.segs) {
        sect64 *sc = (sect64 *)(s + 1);
        for (uint32_t i = 0; i < s->nsects; i++) {
            if (strncmp(sc[i].sectname, "__text", 16)) continue;
            uint8_t *p = (uint8_t *)im.vm(sc[i].addr), *e = p + sc[i].size - 9;
            for (; p < e; p++)
                if (p[0] == 0x65 && (p[1] & 0xF8) == 0x48 && (p[2] == 0x8B || p[2] == 0x89 || p[2] == 0xC7) &&
                    (p[3] & 0xC7) == 0x04 && p[4] == 0x25 && *(uint32_t *)(p + 5) == 0x30) {
                    *(uint32_t *)(p + 5) = newdisp; n++; p += 8;
                }
        }
    }
    return n;
}


/* Mach-O thread-local variables: point every descriptor at libSystem's scion_tlv_get_addr with a per-image key */
static int g_tlv_images;
void setup_tlv(Image &im) {
    uint64_t lo = UINT64_MAX, hi = 0; std::vector<sect64 *> descs;
    for (seg64 *s : im.segs) {
        sect64 *sc = (sect64 *)(s + 1);
        for (uint32_t i = 0; i < s->nsects; i++) {
            uint8_t type = sc[i].flags & 0xFF;
            if (type == 0x13) descs.push_back(&sc[i]);
            if (type == 0x11 || type == 0x12) { lo = std::min(lo, sc[i].addr); hi = std::max(hi, sc[i].addr + sc[i].size); }
        }
    }
    if (descs.empty()) return;
    if (g_tlv_images >= 32) die("too many images with thread-local variables");
    int key = 480 + g_tlv_images;
    uint64_t *tmpl = (uint64_t *)g_libsys->syms["_scion_tlv_tmpl"] + 2 * g_tlv_images++;
    tmpl[0] = lo == UINT64_MAX ? 0 : im.vm(lo); tmpl[1] = lo == UINT64_MAX ? 0 : hi - lo;
    uint64_t thunk = g_libsys->syms["_scion_tlv_get_addr"];
    for (sect64 *d : descs)
        for (uint64_t *p = (uint64_t *)im.vm(d->addr), *e = p + d->size / 8; p + 2 < e + 1; p += 3) p[0] = thunk, p[1] = key;
    TRACE("TLV: %zu sections, template %llu bytes, key %d\n", descs.size(), (unsigned long long)tmpl[1], key);
}


/* dependencies first; libobjc registers each image's classes before its initializers run (like dyld's objc notify) */
static void init_rec(Image *im, uint64_t *args4, uint64_t objc_hook) {
    if (im->inited) return;
    im->inited = true;
    for (Image *d : im->deps) if (d) init_rec(d, args4, objc_hook);
    bool has_objc = false;
    for (seg64 *s : im->segs) {
        sect64 *sc = (sect64 *)(s + 1);
        for (uint32_t i = 0; i < s->nsects; i++) if (!strncmp(sc[i].sectname, "__objc_imageinfo", 16)) has_objc = true;
    }
    if (has_objc) TRACE("objc: registrando %s (hook=%llx)\n", im->path.c_str(), (unsigned long long)objc_hook);
    if (has_objc && objc_hook) { uint64_t a[2] = {im->mh_rt(), (uint64_t)im->slide}; call_guest(objc_hook, a, 2); }
    for (seg64 *s : im->segs) {
        sect64 *sc = (sect64 *)(s + 1);
        for (uint32_t i = 0; i < s->nsects; i++) {
            uint8_t type = sc[i].flags & 0xFF;
            if (type == 0x9) /* S_MOD_INIT_FUNC_POINTERS */
                for (uint64_t *f = (uint64_t *)im->vm(sc[i].addr), *e = f + sc[i].size / 8; f < e; f++) call_guest(*f, args4, 4);
            else if (type == 0x16) /* S_INIT_FUNC_OFFSETS */
                for (uint32_t *f = (uint32_t *)im->vm(sc[i].addr), *e = f + sc[i].size / 4; f < e; f++) call_guest(im->mh_rt() + *f, args4, 4);
        }
    }
}
static uint64_t g_args4[4], g_objc_hook;
void init_all(Image *main, uint64_t *args4) {
    Image *objc = find_image("libobjc.A.dylib");
    g_objc_hook = objc ? find_export(objc, "__scion_objc_image") : 0;
    memcpy(g_args4, args4, sizeof g_args4);
    init_rec(main, g_args4, g_objc_hook);
}
void init_image(Image *im) {
    if (!g_objc_hook) if (Image *objc = find_image("libobjc.A.dylib")) g_objc_hook = find_export(objc, "__scion_objc_image");
    init_rec(im, g_args4, g_objc_hook);
}
std::string locate_dl(const std::string &name) { return locate(name, g_main); }
Image *load_dl(const std::string &file) { return load_rec(file, g_main->arm ? CPU_ARM64 : CPU_X86_64); }
uint64_t dl_sym(Image *im, const std::string &name) { return find_export(im, name); }
