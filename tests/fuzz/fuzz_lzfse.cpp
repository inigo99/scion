// libFuzzer target: the LZFSE decoder of compiled asset catalogs (src/appkit/lzfse.m, plain C). tests/fuzz/run.sh
#include <cstdint>
#include <cstddef>
#include <vector>
extern "C" size_t mw_lzfse_decode(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size);
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *d, size_t n) {
    std::vector<uint8_t> out(1 << 20);
    mw_lzfse_decode(out.data(), out.size(), d, n);
    return 0;
}
