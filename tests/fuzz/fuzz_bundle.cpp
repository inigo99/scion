// libFuzzer target: what the host reads from an app bundle before running it (Info.plist, .icns). tests/fuzz/run.sh
#include "../../src/bundle.h"
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *d, size_t n) {
    std::string f((const char *)d, n);
    PVal v; parse_plist(f, v);
    icns_pngs(f);
    return 0;
}
