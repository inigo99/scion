/* mslc — command-line MSL -> metallib (tests):
 *   mslc in.metal out.metallib
 *   mslc -b outdir files...   (batch: one line per file, "OK name" or "ERR name: first error line") */
#include "msl.h"
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
static std::string slurp(const char *p) { std::ifstream f(p, std::ios::binary); std::stringstream ss; ss << f.rdbuf(); return ss.str(); }
int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: mslc in.metal out.metallib | mslc -b outdir files...\n"); return 2; }
    if (std::string(argv[1]) == "-b") {
        std::vector<std::string> files;
        for (int i = 3; i < argc; i++) {
            if (argv[i][0] != '@') { files.push_back(argv[i]); continue; }
            std::istringstream ls(slurp(argv[i] + 1));
            for (std::string l; std::getline(ls, l);) if (!l.empty()) files.push_back(l);
        }
        for (auto &file : files) {
            std::string log, name = file;
            name = name.substr(name.find_last_of("/\\") + 1);
            auto lib = mslCompile(slurp(file.c_str()), "", log);
            if (lib.empty()) {
                std::string first;
                std::istringstream ls(log);
                for (std::string l; std::getline(ls, l);) if (l.find("error") != std::string::npos || first.empty()) { first = l; if (l.find("error") != std::string::npos) break; }
                printf("ERR %s: %s\n", name.c_str(), first.c_str());
            } else {
                std::ofstream o(std::string(argv[2]) + "/" + name + ".metallib", std::ios::binary);
                o.write((const char *)lib.data(), lib.size());
                printf("OK %s\n", name.c_str());
            }
            fflush(stdout);
        }
        return 0;
    }
    std::string log;
    auto lib = mslCompile(slurp(argv[1]), "", log);
    if (!log.empty()) fprintf(stderr, "%s\n", log.c_str());
    if (lib.empty()) return 1;
    std::ofstream o(argv[2], std::ios::binary);
    o.write((const char *)lib.data(), lib.size());
    return 0;
}
