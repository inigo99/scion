// libFuzzer target: the Mach-O loader (src/dyld.cpp) on generated files: load commands, segments and sections, the export
// trie, rebase/bind opcodes and chained fixups, written into a heap copy of the image. tests/fuzz/run.sh
#include "../../src/scion.h"
#include <stdexcept>

bool g_trace = false;
struct Refused : std::runtime_error { using std::runtime_error::runtime_error; };
void die(const char *m) { throw Refused(m); }   // link_image stops a malformed program this way
static const uint8_t *g_data; static size_t g_size;
const uint8_t *host_map_file(const std::string &, size_t *size) { *size = g_size; return g_data; }
bool host_map_segment(void *, uint64_t, const std::string &, uint64_t) { return false; }
void *image_alloc(uint64_t, uint64_t len) { return len <= (64u << 20) ? calloc(1, len) : nullptr; }
uint64_t call_guest(uint64_t, const uint64_t *, int) { return 0; }

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *d, size_t n) {
    // the loader reads the header in place, as from a page-aligned mapping
    std::vector<uint64_t> buf((n + 7) / 8 + 1); memcpy(buf.data(), d, n);
    g_data = (const uint8_t *)buf.data(); g_size = n;
    for (uint32_t cpu : {0u, CPU_ARM64}) {
        Image *im = map_image("fuzz", cpu);
        if (!im) continue;
        try { link_image(*im); patch_gs_tsd(*im, 1); } catch (const Refused &) {}
        g_images.clear(); g_missing.clear();
        free(im->base); delete im;
    }
    return 0;
}
