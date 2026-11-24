#!/bin/sh
# Cross-compiles dynarmic (fetched by scripts/fetch-deps.sh) for Windows x64 with MinGW-w64: deps/dynarmic/build-win.
# scripts/build-dynarmic.sh --linux: for the native Linux host instead -> deps/dynarmic/build-linux
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
D=${DYNARMIC:-${DEPS:-$ROOT/deps}/dynarmic}
if [ "$1" = --linux ]; then
  cmake -S "$D" -B "$D/build-linux" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DDYNARMIC_FRONTENDS=A64 -DDYNARMIC_TESTS=OFF -DDYNARMIC_USE_BUNDLED_EXTERNALS=ON >/dev/null
  cmake --build "$D/build-linux" --parallel
  echo "OK -> $D/build-linux"; exit 0
fi
B=$D/build-win
# dynarmic only needs Boost's header-only parts; point CMake at a directory holding just the boost/ link so that
# the host's other headers do not leak into the MinGW build
mkdir -p "$B/boost-inc"; ln -sfn /usr/include/boost "$B/boost-inc/boost"
cmake -S "$D" -B "$B" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$ROOT/patches/mingw.cmake" -DCMAKE_BUILD_TYPE=Release \
  -DDYNARMIC_FRONTENDS=A64 -DDYNARMIC_TESTS=OFF -DDYNARMIC_USE_BUNDLED_EXTERNALS=ON -DBoost_INCLUDE_DIR="$B/boost-inc" >/dev/null
cmake --build "$B" --parallel
echo "OK -> $B"
