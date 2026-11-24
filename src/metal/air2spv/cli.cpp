// air2spv-cli: metallib -> SPIR-V + binding summary (test tool)
#include <cstdint>
#include <iridium/iridium.hpp>
#include <cstdio>
#include <vector>
int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: air2spv in.metallib out.spv\n"); return 2; }
    FILE *f = fopen(argv[1], "rb"); if (!f) return 2;
    std::vector<char> d; char buf[65536]; size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) d.insert(d.end(), buf, buf + n);
    fclose(f);
    size_t outSize = 0; Iridium::OutputInfo info;
    void *out = Iridium::translate(d.data(), d.size(), outSize, info);
    if (!out) return 1;
    FILE *o = fopen(argv[2], "wb"); fwrite(out, 1, outSize, o); fclose(o);
    for (auto &[name, fi] : info.functionInfos) {
        printf("%s type=%d", name.c_str(), int(fi.type));
        for (auto &b : fi.bindings) printf(" [%d idx=%zu int=%zu acc=%d]", int(b.type), b.index, b.internalIndex, int(b.textureAccessType));
        printf("\n");
    }
    return 0;
}
