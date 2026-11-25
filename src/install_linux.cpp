/* install_linux.cpp — macOS apps as apps of a Linux desktop, for the native Linux host (install.cpp does Windows).
 *   scion install App.app      a .desktop entry (application menus, launchers) with the app's icon, and its document
 *                              types offered for the file types they name (freedesktop.org MIME), for the current user
 *   scion uninstall App.app    (or its bundle identifier) undoes it
 *   scion App.app [args]       runs the bundle's executable
 * Files: $XDG_DATA_HOME/applications/scion-<id>.desktop, $XDG_DATA_HOME/icons/hicolor/<n>x<n>/apps/scion-<id>.png and,
 * for extensions no installed MIME type knows, $XDG_DATA_HOME/mime/packages/scion-<id>.xml. */
#include "scion.h"
#include "bundle.h"
#include <limits.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <map>

std::string g_bundle_id;   /* the bundle being run, if any */

static bool read_file(const std::string &p, std::string &out) {
    FILE *f = fopen(p.c_str(), "rb"); if (!f) return false;
    char b[65536]; size_t n; out.clear();
    while ((n = fread(b, 1, sizeof b, f)) > 0 && out.size() < (64u << 20)) out.append(b, n);
    fclose(f);
    return true;
}
static bool write_file(const std::string &p, const std::string &data) {
    FILE *f = fopen(p.c_str(), "wb"); if (!f) return false;
    bool ok = fwrite(data.data(), 1, data.size(), f) == data.size();
    return fclose(f) == 0 && ok;
}
static void mkdirs(const std::string &d) { for (size_t i = 1; i <= d.size(); i++) if (i == d.size() || d[i] == '/') mkdir(d.substr(0, i).c_str(), 0755); }
static bool exists(const std::string &p) { struct stat st; return !stat(p.c_str(), &st); }

/* ======================================================================= the bundle */
struct App { std::string path; PVal info; std::string id, name, exe, version; };
static bool load_app(const std::string &arg, App &a) {
    char full[PATH_MAX];
    if (!realpath(arg.c_str(), full)) return false;
    a.path = full;
    std::string f;
    if (!read_file(a.path + "/Contents/Info.plist", f) || !parse_plist(f, a.info) || a.info.t != PVal::DICT) return false;
    std::string leaf = a.path.substr(a.path.find_last_of('/') + 1);
    if (leaf.size() > 4 && !strcasecmp(leaf.c_str() + leaf.size() - 4, ".app")) leaf.resize(leaf.size() - 4);
    a.id = a.info.str("CFBundleIdentifier"); if (a.id.empty()) a.id = leaf;
    a.name = a.info.str("CFBundleDisplayName"); if (a.name.empty()) a.name = a.info.str("CFBundleName"); if (a.name.empty()) a.name = leaf;
    a.exe = a.info.str("CFBundleExecutable"); if (a.exe.empty()) a.exe = leaf;
    a.version = a.info.str("CFBundleShortVersionString");
    return true;
}
/* scion App.app: the executable to run */
std::string mw_bundle_executable(const std::string &arg) {
    std::string a0 = arg; while (a0.size() > 1 && a0.back() == '/') a0.pop_back();
    if (a0.size() < 4 || strcasecmp(a0.c_str() + a0.size() - 4, ".app")) return "";
    App a;
    if (!load_app(a0, a)) return "";
    std::string exe = a.path + "/Contents/MacOS/" + a.exe;
    if (!exists(exe)) return "";
    g_bundle_id = a.id;
    return exe;
}

/* ======================================================================= freedesktop.org */
static std::string data_home() {
    if (const char *x = getenv("XDG_DATA_HOME"); x && *x) return x;
    const char *h = getenv("HOME");
    return std::string(h ? h : "/tmp") + "/.local/share";
}
static std::string safe_id(std::string s) { for (char &c : s) if (!isalnum((unsigned char)c) && c != '.' && c != '-' && c != '_') c = '_'; return s; }
static std::string desktop_path(const std::string &id) { return data_home() + "/applications/scion-" + safe_id(id) + ".desktop"; }
static std::string exe_path() { char b[PATH_MAX]; ssize_t n = readlink("/proc/self/exe", b, sizeof b - 1); return n > 0 ? std::string(b, (size_t)n) : "scion"; }
/* a value in a .desktop Exec line: quoted, with ", `, $ and \ escaped */
static std::string exec_arg(const std::string &s) {
    std::string r = "\"";
    for (char c : s) { if (c == '"' || c == '`' || c == '$' || c == '\\') r += '\\'; if (c == '%') r += '%'; r += c; }
    return r + "\"";
}
static void run_quiet(const std::string &cmd) { if (system((cmd + " >/dev/null 2>&1").c_str())) {} }

/* extension -> MIME type, from the shared MIME database's globs (system and user) */
static std::map<std::string, std::string> known_globs() {
    std::map<std::string, std::string> m;
    for (std::string f : {std::string("/usr/share/mime/globs2"), std::string("/usr/local/share/mime/globs2"), data_home() + "/mime/globs2"}) {
        std::string s; if (!read_file(f, s)) continue;
        size_t p = 0;
        while (p < s.size()) {   /* weight:type:glob */
            size_t e = s.find('\n', p); if (e == std::string::npos) e = s.size();
            std::string line = s.substr(p, e - p); p = e + 1;
            size_t a = line.find(':'), b = a == std::string::npos ? a : line.find(':', a + 1);
            if (line.empty() || line[0] == '#' || b == std::string::npos) continue;
            std::string type = line.substr(a + 1, b - a - 1), glob = line.substr(b + 1);
            if (size_t c = glob.find(':'); c != std::string::npos) glob.resize(c);
            if (glob.rfind("*.", 0) == 0 && glob.find_first_of("*?[", 2) == std::string::npos) {
                std::string ext = glob.substr(2); for (char &c : ext) c = (char)tolower((unsigned char)c);
                m.emplace(ext, type);
            }
        }
    }
    return m;
}
static std::vector<std::string> document_extensions(const App &a) {
    std::vector<std::string> out;
    const PVal *types = a.info.get("CFBundleDocumentTypes");
    if (!types || types->t != PVal::ARR) return out;
    for (auto &t : types->a) {
        const PVal *exts = t.get("CFBundleTypeExtensions");
        if (!exts || exts->t != PVal::ARR) continue;
        for (auto &e : exts->a) if (e.t == PVal::STR && !e.s.empty() && e.s != "*" && e.s.find_first_of("\\/.<>&\"'") == std::string::npos) {
            std::string x = e.s; for (char &c : x) c = (char)tolower((unsigned char)c);
            if (std::find(out.begin(), out.end(), x) == out.end()) out.push_back(x);
        }
    }
    return out;
}
static std::string desktop_value(const std::string &file, const char *key) {
    std::string s; if (!read_file(file, s)) return "";
    std::string k = std::string("\n") + key + "=";
    size_t p = s.find(k); if (p == std::string::npos) return "";
    p += k.size(); return s.substr(p, s.find('\n', p) - p);
}

static int install(const std::string &arg) {
    App a;
    if (!load_app(arg, a)) { fprintf(stderr, "scion: %s is not a macOS app (Contents/Info.plist is missing)\n", arg.c_str()); return 1; }
    if (!exists(a.path + "/Contents/MacOS/" + a.exe)) { fprintf(stderr, "scion: the executable Contents/MacOS/%s is missing\n", a.exe.c_str()); return 1; }
    std::string id = safe_id(a.id), home = data_home();
    /* icon: every PNG of the .icns, into the hicolor theme */
    std::vector<std::string> icons;
    std::string iname = a.info.str("CFBundleIconFile"); if (iname.empty()) iname = a.info.str("CFBundleIconName");
    if (!iname.empty()) {
        if (iname.size() < 5 || strcasecmp(iname.c_str() + iname.size() - 5, ".icns")) iname += ".icns";
        std::string icns;
        if (read_file(a.path + "/Contents/Resources/" + iname, icns))
            for (auto &i : icns_pngs(icns)) {
                std::string dir = home + "/icons/hicolor/" + std::to_string(i.w) + "x" + std::to_string(i.w) + "/apps";
                mkdirs(dir);
                if (write_file(dir + "/scion-" + id + ".png", i.png)) icons.push_back(dir + "/scion-" + id + ".png");
            }
    }
    /* document types: known MIME types for their extensions, new ones (in a package of the app's) for the rest */
    std::vector<std::string> exts = document_extensions(a), mimes;
    std::map<std::string, std::string> known = known_globs();
    std::string pkg;
    for (auto &e : exts) {
        auto it = known.find(e);
        std::string m = it != known.end() ? it->second : "application/x-scion-" + id + "-" + e;
        if (it == known.end())
            pkg += "  <mime-type type=\"" + m + "\">\n    <comment>" + a.name + " document (." + e + ")</comment>\n    <glob pattern=\"*." + e + "\"/>\n  </mime-type>\n";
        if (std::find(mimes.begin(), mimes.end(), m) == mimes.end()) mimes.push_back(m);
    }
    std::string pkgfile = home + "/mime/packages/scion-" + id + ".xml";
    if (!pkg.empty()) {
        mkdirs(home + "/mime/packages");
        write_file(pkgfile, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<mime-info xmlns=\"http://www.freedesktop.org/standards/shared-mime-info\">\n" + pkg + "</mime-info>\n");
        run_quiet("update-mime-database '" + home + "/mime'");
    }
    /* the .desktop entry */
    std::string desk = "[Desktop Entry]\nType=Application\nName=" + a.name + "\nComment=macOS app, run by Scion\n"
                       "Exec=" + exec_arg(exe_path()) + " " + exec_arg(a.path) + " %F\n"
                       "Path=" + a.path.substr(0, a.path.find_last_of('/')) + "\nTerminal=false\nCategories=Utility;\n";
    if (!icons.empty()) desk += "Icon=scion-" + id + "\n";
    if (!mimes.empty()) { desk += "MimeType="; for (auto &m : mimes) desk += m + ";"; desk += "\n"; }
    desk += "X-Scion-Bundle=" + a.id + "\nX-Scion-Path=" + a.path + "\n";
    if (!a.version.empty()) desk += "X-Scion-Version=" + a.version + "\n";
    mkdirs(home + "/applications");
    std::string df = desktop_path(a.id);
    if (!write_file(df, desk)) { fprintf(stderr, "scion: could not write %s\n", df.c_str()); return 1; }
    chmod(df.c_str(), 0755);
    run_quiet("update-desktop-database '" + home + "/applications'");
    run_quiet("gtk-update-icon-cache -q -t '" + home + "/icons/hicolor'");
    printf("%s installed (%s)\n  menu entry: %s\n  icon: %s\n", a.name.c_str(), a.id.c_str(), df.c_str(),
           icons.empty() ? "(no .icns with PNG images)" : ("scion-" + id + " (" + std::to_string(icons.size()) + " sizes)").c_str());
    if (!exts.empty()) { printf("  opens: "); for (auto &e : exts) printf(".%s ", e.c_str()); printf("\n"); }
    return 0;
}
static int uninstall(const std::string &arg) {
    std::string id = arg;
    App a; if (load_app(arg, a)) id = a.id;
    std::string df = desktop_path(id), home = data_home(), sid = safe_id(id);
    if (!exists(df) || desktop_value(df, "X-Scion-Bundle").empty()) { fprintf(stderr, "scion: %s is not installed\n", id.c_str()); return 1; }
    unlink(df.c_str());
    for (int s : {16, 24, 32, 48, 64, 128, 256, 512, 1024}) {
        std::string p = home + "/icons/hicolor/" + std::to_string(s) + "x" + std::to_string(s) + "/apps/scion-" + sid + ".png";
        unlink(p.c_str());
    }
    std::string pkg = home + "/mime/packages/scion-" + sid + ".xml";
    if (exists(pkg)) { unlink(pkg.c_str()); run_quiet("update-mime-database '" + home + "/mime'"); }
    run_quiet("update-desktop-database '" + home + "/applications'");
    run_quiet("gtk-update-icon-cache -q -t '" + home + "/icons/hicolor'");
    printf("%s uninstalled (the app itself stays in its folder)\n", id.c_str());
    return 0;
}

/* scion install|uninstall ...: handled before any guest is loaded */
bool mw_subcommand_linux(int argc, char **argv, int *rc) {
    bool ins = !strcmp(argv[1], "install"), des = !strcmp(argv[1], "uninstall");
    if (!ins && !des) return false;
    if (argc < 3) { fprintf(stderr, "usage: scion %s <App.app>%s\n", ins ? "install" : "uninstall", ins ? "" : " | <bundle id>"); *rc = 2; return true; }
    *rc = ins ? install(argv[2]) : uninstall(argv[2]);
    return true;
}
