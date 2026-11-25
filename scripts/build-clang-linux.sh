#!/bin/sh
# Builds the patched Clang 20.1.2 libraries (patches/clang-msl.patch) that scion-msl.so (the MSL compiler of the native
# Linux host) links, against the system's LLVM 20 (llvm-20-dev, 20.1.2): deps/llvm20/build-linux. Needs
# scripts/fetch-deps.sh --metal first, and libzstd-dev. An hour or more on a small machine.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
L=${LLVM20:-${DEPS:-$ROOT/deps}/llvm20}
cmake -S "$L/clang" -B "$L/build-linux" -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_DIR=/usr/lib/llvm-20/lib/cmake/llvm \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_CXX_FLAGS=-w -DCLANG_INCLUDE_TESTS=OFF -DCLANG_INCLUDE_DOCS=OFF -DCLANG_BUILD_TOOLS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF -DCLANG_ENABLE_ARCMT=OFF -DCLANG_ENABLE_STATIC_ANALYZER=OFF >/dev/null
cmake --build "$L/build-linux" --target clangCodeGen clangFrontend
echo "OK -> $L/build-linux"
