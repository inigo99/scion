#!/bin/sh
# Builds the host half of Metal:
#   bin/scion-metal.dll: Indium (Metal on Vulkan) + air2spv (Iridium-NG: AIR -> SPIR-V) + LLVM 20 (static)
#   bin/scion-msl.dll:   the MSL compiler for newLibraryWithSource: (metal/msl: clang 20 "C++ for OpenCL" with
#                          patches/clang-msl.patch + metal_stdlib.h), loaded by scion-metal.dll on first use
# Inputs (scripts/fetch-deps.sh --all, then scripts/build-llvm-mingw.sh): INDIUM (Indium, patched), LLVM20 (llvm-project
# 20.1.2 with clang/, patched, and build-win/ with its static libraries for MinGW), VKINC (Vulkan headers).
set -e
cd "$(dirname "$0")"
DEPS=${DEPS:-../deps}
INDIUM=${INDIUM:-$DEPS/indium}
LLVM20=${LLVM20:-$DEPS/llvm20}
LLVM_SRC=$LLVM20/llvm
L=$LLVM20/build-win/lib
OUT=${OUT:-../bin}; O=../out/metal; mkdir -p $O $OUT
GXX="x86_64-w64-mingw32-g++-posix -std=c++17 -O2 -w -I../compat/win -I$INDIUM/include -I$INDIUM/private-include"
VKINC=${VKINC:-$DEPS/vulkan-headers/include} # Vulkan headers (vulkan/, vk_video/)
CXX="$GXX -I$VKINC -include cstdint -include stdexcept -include string"
CXX_NG="$GXX -I$LLVM_SRC/include -I$LLVM20/build-win/include -fno-rtti" # LLVM is built without RTTI
CXX_MSL="$CXX_NG -I$O -I$LLVM_SRC/../clang/include -I$LLVM20/build-win/tools/clang/include"
{ echo 'R"__mw('; cat metal/msl/metal_stdlib.h; echo ')__mw"'; } > $O/metal_stdlib.inc.new
cmp -s $O/metal_stdlib.inc.new $O/metal_stdlib.inc || mv $O/metal_stdlib.inc.new $O/metal_stdlib.inc
rm -f $O/air.o $O/dynamic-llvm.o $O/iridium.o $O/spirv.o # old Iridium (LLVM 14) objects
HDR=$(ls -t $INDIUM/include/*/*.hpp $INDIUM/private-include/*/*.hpp metal/mtlbridge.h metal/air2spv/spv.h metal/msl/msl.h $O/metal_stdlib.inc ../compat/win/dlfcn.h | head -1) # newest header
for f in $INDIUM/src/indium/*.cpp $INDIUM/src/indium-kit/*.cpp metal/host_metal.cpp metal/air2spv/air2spv.cpp metal/msl/msl.cpp; do
  o=$O/$(basename $f .cpp).o
  [ -f $o ] && [ $o -nt $f ] && [ $o -nt $HDR ] && continue
  case $f in *air2spv.cpp) C=$CXX_NG;; *msl.cpp) C=$CXX_MSL;; *) C=$CXX;; esac
  ($C -c $f -o $o || { rm -f $o; touch $O/FAILED; }) &
done; wait; [ ! -f $O/FAILED ] || { rm $O/FAILED; echo "compilation failed"; exit 1; }
LIBS="-Wl,--start-group $L/*.a -Wl,--end-group -static -luser32 -lole32 -luuid -lpsapi -lshell32 -ladvapi32 -lntdll -lversion"
x86_64-w64-mingw32-g++-posix -shared -s -o $OUT/scion-metal.dll $(ls $O/*.o | grep -v '/msl.o$') $LIBS
[ $OUT/scion-msl.dll -nt $O/msl.o ] || x86_64-w64-mingw32-g++-posix -shared -s -o $OUT/scion-msl.dll $O/msl.o $LIBS
echo "OK -> $OUT/scion-metal.dll $OUT/scion-msl.dll"
