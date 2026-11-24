#!/bin/sh
# Downloads Scion's third-party dependencies at pinned versions into deps/ (or $DEPS) and applies Scion's patches.
#
#   scripts/fetch-deps.sh            dynarmic + LLVM runtimes + Indium: enough for scion.exe and the C/Objective-C libraries
#   scripts/fetch-deps.sh --all      also LLVM/clang 20 (Metal shader translation and compiler) and Swift 6.1.3 sources
#
# Nothing here is redistributed by Scion: every dependency is fetched from its upstream repository.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${DEPS:-$ROOT/deps}
mkdir -p "$DEPS"
P=$ROOT/patches

clone() { # dir url commit-or-tag [extra git clone args]
  name=$1; dir=$DEPS/$1; url=$2; rev=$3; shift 3
  if [ -d "$dir/.git" ]; then echo "= $name (already fetched)"; return 1; fi
  echo "+ $name @ $rev"
  git clone --quiet "$@" "$url" "$dir"
  git -C "$dir" -c advice.detachedHead=false checkout --quiet "$rev"
}

# dynarmic: the ARM64 JIT (0BSD)
if clone dynarmic https://github.com/azahar-emu/dynarmic.git a46601580d5512d324104f985b5f0209dc980ddc; then
  git -C "$DEPS/dynarmic" submodule --quiet update --init --depth 1 externals/fmt externals/mcl externals/robin-map \
    externals/xbyak externals/zycore externals/zydis
  git -C "$DEPS/dynarmic" apply "$P/dynarmic-gse-precise.patch" "$P/dynarmic-fp16-fcmp.patch"
  git -C "$DEPS/dynarmic/externals/xbyak" apply "$P/xbyak-mingw-headers.patch"
fi

# LLVM runtimes for the guest (libc++, libc++abi, libunwind; Apache-2.0 WITH LLVM-exception)
if clone llvm-runtimes https://github.com/llvm/llvm-project.git llvmorg-18.1.8 --depth 1 --branch llvmorg-18.1.8 \
     --filter=blob:none --sparse; then
  git -C "$DEPS/llvm-runtimes" sparse-checkout set libcxx libcxxabi libunwind
fi

# Indium: Metal on Vulkan (0BSD)
if clone indium https://github.com/darlinghq/indium.git 43d793077e4ec9a74ab6f70b0fc77b9397f239a0; then
  git -C "$DEPS/indium" apply "$P/indium-scion.patch"
fi

[ "$1" = --all ] || { echo "OK -> $DEPS"; exit 0; }

# LLVM/clang 20.1.2 for the Metal host library (AIR -> SPIR-V) and the MSL compiler (Apache-2.0 WITH LLVM-exception)
if clone llvm20 https://github.com/llvm/llvm-project.git llvmorg-20.1.2 --depth 1 --branch llvmorg-20.1.2 \
     --filter=blob:none --sparse; then
  git -C "$DEPS/llvm20" sparse-checkout set llvm clang cmake third-party
  (cd "$DEPS/llvm20" && patch -p0 --quiet < "$P/clang-msl.patch")
fi

# Vulkan headers for Indium (Apache-2.0 / MIT)
clone vulkan-headers https://github.com/KhronosGroup/Vulkan-Headers.git v1.3.296 --depth 1 --branch v1.3.296 || true

# Swift 6.1.3 sources: runtime, standard library and _Concurrency for the guest (Apache-2.0 with runtime exception)
if clone swift https://github.com/swiftlang/swift.git swift-6.1.3-RELEASE --depth 1 --branch swift-6.1.3-RELEASE; then
  cmake -P "$DEPS/swift/Runtimes/Resync.cmake" >/dev/null
fi

# Swift 5.4.3: the last release with the macOS SDK overlays in the open (Foundation, CoreGraphics, ... over their stable ABI)
if clone swift-overlays https://github.com/swiftlang/swift.git swift-5.4.3-RELEASE --depth 1 --branch swift-5.4.3-RELEASE \
     --filter=blob:none --sparse; then
  git -C "$DEPS/swift-overlays" sparse-checkout set stdlib/public/Darwin stdlib/public/SwiftShims
  patch -p1 --quiet -d "$DEPS/swift-overlays/stdlib/public/Darwin/Foundation" < "$P/swift-foundation-overlay.patch"
fi
echo "OK -> $DEPS"
