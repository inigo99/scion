#!/bin/sh
# Builds Scion: bin/scion.exe and bin/scionw.exe (Windows x64, cross-compiled), bin/scion (the native Linux host, when
# its dependencies are there) and the guest libraries in bin/lib (libSystem, libc++, libobjc, Foundation, Metal, AppKit,
# GameController, AudioToolbox).
# Needs: scripts/fetch-deps.sh and scripts/build-dynarmic.sh first (see docs/building.md). JOBS: parallel compilers
# (default: the number of CPUs). Every object is compiled first, in parallel; then the libraries are linked in order.
set -e
cd "$(dirname "$0")"
DEPS=${DEPS:-../deps}
D=${DYNARMIC:-$DEPS/dynarmic}; B=$D/build-win; L=$D/build-linux
mkdir -p ../out
OUT=${OUT:-../bin}; mkdir -p $OUT/lib
T=$(mktemp -d); trap 'rm -rf $T' EXIT
sh build_rt.sh >/dev/null
RT=../out/rt
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}

# compile jobs run in the background, JOBS at a time (a FIFO holds one token per free slot); `finish` waits for them
# and fails if any did
mkfifo $T/slots; exec 3<>$T/slots; i=0; while [ $i -lt $JOBS ]; do echo >&3; i=$((i+1)); done
job() {  # command...
  read -r _ <&3
  ("$@" 3>&- || { echo "failed: $*" >&2; touch $T/FAILED; }; echo >&3) &
}
finish() { wait; [ ! -f $T/FAILED ] || exit 1; }

W="-Wall -Wno-unused-parameter"
# Warnings that are noise for these libraries, which override methods in categories, call delegate methods on id
# and pass nil to their own nonnull parameters by design.
QUIET="-Wno-objc-protocol-method-implementation -Wno-nonnull -Wno-missing-noescape -Wno-unused-property-ivar \
  -Wno-objc-missing-super-calls -Wno-objc-designated-initializers -Wno-incomplete-implementation -Wno-objc-method-access \
  -Wno-atomic-property-with-user-defined-accessor -Wno-gnu-folding-constant -Wno-mismatched-parameter-types"
OBJC="-fobjc-runtime=macosx-11 -fno-objc-arc -fobjc-exceptions -funwind-tables -fconstant-cfstrings"
KIT="-isysroot ../sdk/darwin -isystem ../sdk/include $W $QUIET -Wno-objc-property-no-attribute -Wno-objc-protocol-property-synthesis -Wno-protocol"
FOUNDATION="NSString collections system regex json runloop extra swift calendar url plist coder cf more kvo eventkit xpc constlit"
APPKIT="app window menu widgets cg cgdraw draw layout nib document table misc statusbar lzfse assets"

# ---- 1. objects
for a in x86_64 arm64; do
  G="-target $a-apple-macos11 -O2 -fno-stack-protector"
  for f in libsystem dispatch libc; do job clang $G -ffreestanding -std=c11 $W -Wno-deprecated-non-prototype -c $f.c -o $T/${f}_$a.o; done
  job clang $G -isysroot ../sdk/darwin -std=c11 $W -c libc_ext.c -o $T/libc_ext_$a.o
  job clang $G -isysroot ../sdk/darwin -std=c11 $W -Wno-deprecated-declarations -c stubs.c -o $T/stubs_$a.o
  # libobjc: runtime (C) + msgSend (asm) + root classes (ObjC, MRC)
  O="$G -ffreestanding -funwind-tables -fexceptions $W -Wno-deprecated-non-prototype"
  job clang $O -std=c11 -c objc/objc.c -o $T/objc_$a.o
  job clang $O -fobjc-runtime=macosx-11 -fno-objc-arc -fobjc-exceptions -Wno-objc-root-class -c objc/NSObject.m -o $T/nsobject_$a.o
  job clang -target $a-apple-macos11 -c objc/msgsend_$a.s -o $T/msgsend_$a.o
  for f in $FOUNDATION; do
    job clang $G -ffreestanding $W $QUIET -isystem ../sdk/include $OBJC -fexceptions -c foundation/$f.m -o $T/f_${f}_$a.o
  done
  for f in Metal MetalFX; do job clang $G $KIT $OBJC -c metal/$f.m -o $T/mtl_${f}_$a.o; done
  for f in $APPKIT; do
    job clang $G $KIT -Wno-atomic-property-with-user-defined-accessor -Wno-objc-missing-super-calls -Wno-deprecated-declarations \
      $OBJC -c appkit/$f.m -o $T/ak_${f}_$a.o
  done
  job clang $G $KIT -Wno-atomic-property-with-user-defined-accessor $OBJC -c gamecontroller/gc.m -o $T/gc_$a.o
  job clang $G -isysroot ../sdk/darwin -isystem ../sdk/include -fblocks $W -Wno-four-char-constants -c audio/audiotoolbox.c -o $T/at_$a.o
done
# the hosts: scion.exe (MinGW), scionw.exe and, with dynarmic for Linux and SDL2/FreeType/fontconfig/libpng/libjpeg, scion
DI="-I$D/src -I$D/externals/mcl/include -I$D/externals/fmt/include"
for f in host dyld arm64 ui install; do job x86_64-w64-mingw32-g++-posix -std=c++20 -O2 $W -municode $DI -c $f.cpp -o $T/win_$f.o; done
LINUX=
if [ -f $L/src/dynarmic/libdynarmic.a ] && pkg-config --exists sdl2 freetype2 fontconfig libpng; then
  LINUX=1
  for f in host_linux ui_linux install_linux dyld arm64; do
    job g++ -std=c++20 -O2 $W $DI $(pkg-config --cflags sdl2 freetype2 fontconfig libpng) -c $f.cpp -o $T/lin_$f.o
  done
else echo "note: dynarmic for Linux (scripts/build-dynarmic.sh --linux) or SDL2/FreeType/fontconfig/libpng are missing: skipping bin/scion"; fi
job x86_64-w64-mingw32-g++-posix -std=c++20 -O2 -Wall -municode -mwindows launcher.cpp -o $OUT/scionw.exe -lshell32 -lole32 -luuid -static
finish

# ---- 2. links, each library after those it links against
dylib() {  # arch install-name output objects...
  a=$1; n=$2; o=$3; shift 3
  ld64.lld-18 -dylib -arch $a -platform_version macos 11.0 11.0 -install_name $n -o $o "$@"
}
F=/System/Library/Frameworks
for a in x86_64 arm64; do
  dylib $a /usr/lib/libSystem.B.dylib $T/ls_$a.dylib $T/libsystem_$a.o $T/dispatch_$a.o $T/libc_$a.o $T/libc_ext_$a.o $T/stubs_$a.o $RT/$a/unwind/*.o
  # libc++.1.dylib = LLVM libc++ + libc++abi (libc++abi.dylib is aliased onto it by the loader)
  dylib $a /usr/lib/libc++.1.dylib $T/cxx_$a.dylib $RT/$a/cxx/*.o $RT/$a/cxxabi/*.o $T/ls_$a.dylib
  dylib $a /usr/lib/libobjc.A.dylib $T/objc_$a.dylib $T/objc_$a.o $T/nsobject_$a.o $T/msgsend_$a.o $T/cxx_$a.dylib $T/ls_$a.dylib
  # Foundation (CoreFoundation/CoreServices alias onto it): NSString, collections, system classes, CF basics
  dylib $a $F/Foundation.framework/Versions/A/Foundation $T/fnd_$a.dylib $T/f_*_$a.o $T/objc_$a.dylib $T/ls_$a.dylib
  # Metal (guest Objective-C half of Metal + QuartzCore + MetalFX; the host half is scion-metal.dll, see build_metal.sh)
  dylib $a $F/Metal.framework/Versions/A/Metal $T/mtl_$a.dylib $T/mtl_*_$a.o $T/fnd_$a.dylib $T/objc_$a.dylib $T/ls_$a.dylib
  # AppKit (Cocoa, CoreGraphics, CoreVideo and MetalKit alias onto it; the host half is ui.cpp / ui_linux.cpp)
  dylib $a $F/AppKit.framework/Versions/C/AppKit $T/ak_$a.dylib $T/ak_*_$a.o $T/mtl_$a.dylib $T/fnd_$a.dylib $T/objc_$a.dylib $T/ls_$a.dylib
  # GameController (CoreHaptics aliases onto it): controllers from UI_PAD, haptics -> UI_RUMBLE
  dylib $a $F/GameController.framework/Versions/A/GameController $T/gc_$a.dylib $T/gc_$a.o $T/fnd_$a.dylib $T/objc_$a.dylib $T/ls_$a.dylib
  # AudioToolbox (AudioUnit and CoreAudio alias onto it): sound through UI_AUDIO_*
  dylib $a $F/AudioToolbox.framework/Versions/A/AudioToolbox $T/at_$a.dylib $T/at_$a.o $T/fnd_$a.dylib $T/ls_$a.dylib
done
for l in ls:libSystem.B cxx:libc++.1 objc:libobjc.A fnd:Foundation mtl:Metal ak:AppKit gc:GameController at:AudioToolbox; do
  llvm-lipo-18 -create $T/${l%%:*}_x86_64.dylib $T/${l%%:*}_arm64.dylib -output $OUT/lib/${l#*:}.dylib
done
x86_64-w64-mingw32-g++-posix -municode $T/win_*.o -o $OUT/scion.exe \
  $B/src/dynarmic/libdynarmic.a $(find $B/externals -name '*.a') -lbcrypt -lwinmm -lsynchronization -ldwmapi -lole32 -luuid -lgdi32 \
  -lshell32 -lwindowscodecs -static -Wl,-Map=../out/scion.map
# scion: the native Linux host (#10), sharing lib/ with scion.exe
[ -z "$LINUX" ] || g++ $T/lin_*.o -o $OUT/scion $L/src/dynarmic/libdynarmic.a $(find $L/externals -name '*.a') \
  $(pkg-config --libs sdl2 freetype2 fontconfig libpng) -ljpeg -lX11 -lpthread -lrt
echo "OK -> $OUT"
