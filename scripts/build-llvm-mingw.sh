#!/bin/sh
# Cross-compiles the static LLVM and clang 20 libraries that scion-metal.dll and scion-msl.dll link (src/build_metal.sh)
# for Windows x64 with MinGW-w64: deps/llvm20/build-win. Needs scripts/fetch-deps.sh --all first.
# Two stages: native tblgen tools (deps/llvm20/build-host), then the libraries. Takes hours on a small machine.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
L=${LLVM20:-${DEPS:-$ROOT/deps}/llvm20}
COMMON="-G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang -DLLVM_TARGETS_TO_BUILD=X86 \
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF -DCLANG_INCLUDE_DOCS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_RTTI=OFF"
cmake -S "$L/llvm" -B "$L/build-host" $COMMON >/dev/null
cmake --build "$L/build-host" --target llvm-tblgen clang-tblgen
cmake -S "$L/llvm" -B "$L/build-win" $COMMON -DCMAKE_TOOLCHAIN_FILE="$ROOT/patches/mingw.cmake" \
  -DLLVM_HOST_TRIPLE=x86_64-w64-windows-gnu -DLLVM_BUILD_TOOLS=OFF -DCLANG_BUILD_TOOLS=OFF -DLLVM_BUILD_UTILS=OFF \
  -DLLVM_TABLEGEN="$L/build-host/bin/llvm-tblgen" -DCLANG_TABLEGEN="$L/build-host/bin/clang-tblgen" >/dev/null
cmake --build "$L/build-win"
echo "OK -> $L/build-win"
