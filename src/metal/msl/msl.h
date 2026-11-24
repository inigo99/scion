/* msl.h — Metal Shading Language source -> metallib (see msl.cpp) */
#pragma once
#include <cstdint>
#include <string>
#include <vector>
/* macros: "#define NAME VALUE\n" lines. Returns the metallib, or empty with the compiler messages in log. */
std::vector<uint8_t> mslCompile(const std::string &src, const std::string &macros, std::string &log);
/* changes with every build of the compiler or metal_stdlib: key for caches of compiled sources */
extern const char kMslVersion[];
