#!/bin/sh
# Cross-compiles dynarmic (fetched by scripts/fetch-deps.sh) for Windows x64 with MinGW-w64: deps/dynarmic/build-win
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
D=${DYNARMIC:-${DEPS:-$ROOT/deps}/dynarmic}
B=$D/build-win
# dynarmic only needs Boost's header-only parts; point CMake at a directory holding just the boost/ link so that
# the host's other headers do not leak into the MinGW build
mkdir -p "$B/boost-inc"; ln -sfn /usr/include/boost "$B/boost-inc/boost"
cmake -S "$D" -B "$B" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$ROOT/patches/mingw.cmake" -DCMAKE_BUILD_TYPE=Release \
  -DDYNARMIC_FRONTENDS=A64 -DDYNARMIC_TESTS=OFF -DDYNARMIC_USE_BUNDLED_EXTERNALS=ON -DBoost_INCLUDE_DIR="$B/boost-inc" >/dev/null
cmake --build "$B" --parallel
echo "OK -> $B"
