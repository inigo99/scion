#!/bin/sh
# Builds Scion for Windows x64 from Linux: bin/scion.exe, bin/scionw.exe and the guest libraries in bin/lib
# (libSystem, libc++, libobjc, Foundation, Metal, AppKit, GameController, AudioToolbox).
# Needs: scripts/fetch-deps.sh and scripts/build-dynarmic.sh first (see docs/building.md).
set -e
cd "$(dirname "$0")"
DEPS=${DEPS:-../deps}
D=${DYNARMIC:-$DEPS/dynarmic}; B=$D/build-win
mkdir -p ../out
OUT=${OUT:-../bin}; mkdir -p $OUT/lib
T=$(mktemp -d)
sh build_rt.sh >/dev/null
RT=../out/rt
# Warnings that are noise for these libraries, which override methods in categories, call delegate methods on id
# and pass nil to their own nonnull parameters by design.
QUIET="-Wno-objc-protocol-method-implementation -Wno-nonnull -Wno-missing-noescape -Wno-unused-property-ivar \
  -Wno-objc-missing-super-calls -Wno-objc-designated-initializers -Wno-incomplete-implementation -Wno-objc-method-access \
  -Wno-atomic-property-with-user-defined-accessor -Wno-gnu-folding-constant -Wno-mismatched-parameter-types"
for a in x86_64 arm64; do
  for f in libsystem dispatch libc; do
    clang -target $a-apple-macos11 -O2 -ffreestanding -fno-stack-protector -std=c11 -Wall -Wno-unused-parameter \
      -Wno-deprecated-non-prototype -c $f.c -o $T/${f}_$a.o
  done
  clang -target $a-apple-macos11 -isysroot ../sdk/darwin -O2 -fno-stack-protector -std=c11 -Wall -Wno-unused-parameter \
    -c libc_ext.c -o $T/libc_ext_$a.o
  clang -target $a-apple-macos11 -isysroot ../sdk/darwin -O2 -fno-stack-protector -std=c11 -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
    -c stubs.c -o $T/stubs_$a.o
  ld64.lld-18 -dylib -arch $a -platform_version macos 11.0 11.0 -install_name /usr/lib/libSystem.B.dylib \
    -o $T/ls_$a.dylib $T/libsystem_$a.o $T/dispatch_$a.o $T/libc_$a.o $T/libc_ext_$a.o $T/stubs_$a.o $RT/$a/unwind/*.o
done
llvm-lipo-18 -create $T/ls_x86_64.dylib $T/ls_arm64.dylib -output $OUT/lib/libSystem.B.dylib
# libc++.1.dylib = LLVM libc++ + libc++abi (libc++abi.dylib is aliased onto it by the loader)
for a in x86_64 arm64; do
  ld64.lld-18 -dylib -arch $a -platform_version macos 11.0 11.0 -install_name /usr/lib/libc++.1.dylib \
    -o $T/cxx_$a.dylib $RT/$a/cxx/*.o $RT/$a/cxxabi/*.o $T/ls_$a.dylib
done
llvm-lipo-18 -create $T/cxx_x86_64.dylib $T/cxx_arm64.dylib -output $OUT/lib/libc++.1.dylib
# libobjc.A.dylib: runtime (C) + msgSend (asm) + root classes (ObjC, MRC)
for a in x86_64 arm64; do
  G="-target $a-apple-macos11 -O2 -ffreestanding -fno-stack-protector -funwind-tables -fexceptions -Wall -Wno-unused-parameter -Wno-deprecated-non-prototype"
  clang $G -std=c11 -c objc/objc.c -o $T/objc_$a.o
  clang $G -fobjc-runtime=macosx-11 -fno-objc-arc -fobjc-exceptions -Wno-objc-root-class -c objc/NSObject.m -o $T/nsobject_$a.o
  clang -target $a-apple-macos11 -c objc/msgsend_$a.s -o $T/msgsend_$a.o
  ld64.lld-18 -dylib -arch $a -platform_version macos 11.0 11.0 -install_name /usr/lib/libobjc.A.dylib \
    -o $T/objc_$a.dylib $T/objc_$a.o $T/nsobject_$a.o $T/msgsend_$a.o $T/cxx_$a.dylib $T/ls_$a.dylib
done
llvm-lipo-18 -create $T/objc_x86_64.dylib $T/objc_arm64.dylib -output $OUT/lib/libobjc.A.dylib
# Foundation.dylib (CoreFoundation/CoreServices alias onto it): NSString, collections, system classes, CF basics
for a in x86_64 arm64; do
  for f in NSString collections system regex json runloop extra swift calendar url plist coder cf more kvo eventkit xpc constlit; do
    clang -target $a-apple-macos11 -O2 -ffreestanding -fno-stack-protector -Wall -Wno-unused-parameter $QUIET -isystem ../sdk/include \
      -fobjc-runtime=macosx-11 -fno-objc-arc -fobjc-exceptions -funwind-tables -fexceptions -fconstant-cfstrings -c foundation/$f.m -o $T/f_${f}_$a.o
  done
  ld64.lld-18 -dylib -arch $a -platform_version macos 11.0 11.0 \
    -install_name /System/Library/Frameworks/Foundation.framework/Versions/A/Foundation \
    -o $T/fnd_$a.dylib $T/f_*_$a.o $T/objc_$a.dylib $T/ls_$a.dylib
done
llvm-lipo-18 -create $T/fnd_x86_64.dylib $T/fnd_arm64.dylib -output $OUT/lib/Foundation.dylib
# Metal.dylib (guest Objective-C half of Metal + QuartzCore + MetalFX; the host half is scion-metal.dll, see build_metal.sh)
for a in x86_64 arm64; do
  clang -target $a-apple-macos11 -isysroot ../sdk/darwin -isystem ../sdk/include -O2 -fno-stack-protector -Wall -Wno-unused-parameter $QUIET \
    -Wno-objc-property-no-attribute -Wno-objc-protocol-property-synthesis -Wno-protocol -fobjc-runtime=macosx-11 -fno-objc-arc -fobjc-exceptions -funwind-tables -fconstant-cfstrings \
    -c metal/Metal.m -o $T/metal_$a.o &&
  clang -target $a-apple-macos11 -isysroot ../sdk/darwin -isystem ../sdk/include -O2 -fno-stack-protector -Wall -Wno-unused-parameter $QUIET \
    -Wno-objc-property-no-attribute -Wno-objc-protocol-property-synthesis -Wno-protocol -fobjc-runtime=macosx-11 -fno-objc-arc -fobjc-exceptions -funwind-tables -fconstant-cfstrings \
    -c metal/MetalFX.m -o $T/metalfx_$a.o
  ld64.lld-18 -dylib -arch $a -platform_version macos 11.0 11.0 -install_name /System/Library/Frameworks/Metal.framework/Versions/A/Metal \
    -o $T/mtl_$a.dylib $T/metal_$a.o $T/metalfx_$a.o $T/fnd_$a.dylib $T/objc_$a.dylib $T/ls_$a.dylib
done
llvm-lipo-18 -create $T/mtl_x86_64.dylib $T/mtl_arm64.dylib -output $OUT/lib/Metal.dylib
# AppKit.dylib (Cocoa, CoreGraphics, CoreVideo and MetalKit alias onto it; the host half is ui.cpp in scion.exe)
for a in x86_64 arm64; do
  for f in app window menu widgets cg cgdraw draw layout nib document table misc statusbar lzfse assets; do
    clang -target $a-apple-macos11 -isysroot ../sdk/darwin -isystem ../sdk/include -O2 -fno-stack-protector -Wall -Wno-unused-parameter $QUIET \
      -Wno-objc-property-no-attribute -Wno-objc-protocol-property-synthesis -Wno-protocol -Wno-atomic-property-with-user-defined-accessor \
      -Wno-objc-missing-super-calls -Wno-deprecated-declarations \
      -fobjc-runtime=macosx-11 -fno-objc-arc -fobjc-exceptions -funwind-tables -fconstant-cfstrings -c appkit/$f.m -o $T/ak_${f}_$a.o
  done
  ld64.lld-18 -dylib -arch $a -platform_version macos 11.0 11.0 -install_name /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
    -o $T/ak_$a.dylib $T/ak_*_$a.o $T/mtl_$a.dylib $T/fnd_$a.dylib $T/objc_$a.dylib $T/ls_$a.dylib
done
llvm-lipo-18 -create $T/ak_x86_64.dylib $T/ak_arm64.dylib -output $OUT/lib/AppKit.dylib
# GameController.dylib (CoreHaptics aliases onto it): controllers from UI_PAD, haptics -> UI_RUMBLE
for a in x86_64 arm64; do
  clang -target $a-apple-macos11 -isysroot ../sdk/darwin -isystem ../sdk/include -O2 -fno-stack-protector -Wall -Wno-unused-parameter $QUIET \
    -Wno-objc-property-no-attribute -Wno-objc-protocol-property-synthesis -Wno-protocol -Wno-atomic-property-with-user-defined-accessor \
    -fobjc-runtime=macosx-11 -fno-objc-arc -fobjc-exceptions -funwind-tables -fconstant-cfstrings -c gamecontroller/gc.m -o $T/gc_$a.o
  ld64.lld-18 -dylib -arch $a -platform_version macos 11.0 11.0 -install_name /System/Library/Frameworks/GameController.framework/Versions/A/GameController \
    -o $T/gc_$a.dylib $T/gc_$a.o $T/fnd_$a.dylib $T/objc_$a.dylib $T/ls_$a.dylib
done
llvm-lipo-18 -create $T/gc_x86_64.dylib $T/gc_arm64.dylib -output $OUT/lib/GameController.dylib
# AudioToolbox.dylib (AudioUnit and CoreAudio alias onto it): sound through UI_AUDIO_* (WASAPI)
for a in x86_64 arm64; do
  clang -target $a-apple-macos11 -isysroot ../sdk/darwin -isystem ../sdk/include -O2 -fno-stack-protector -fblocks -Wall -Wno-unused-parameter \
    -Wno-four-char-constants -c audio/audiotoolbox.c -o $T/at_$a.o
  ld64.lld-18 -dylib -arch $a -platform_version macos 11.0 11.0 -install_name /System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox \
    -o $T/at_$a.dylib $T/at_$a.o $T/fnd_$a.dylib $T/ls_$a.dylib
done
llvm-lipo-18 -create $T/at_x86_64.dylib $T/at_arm64.dylib -output $OUT/lib/AudioToolbox.dylib
x86_64-w64-mingw32-g++-posix -std=c++20 -O2 -Wall -Wno-unused-parameter -municode host.cpp dyld.cpp arm64.cpp ui.cpp install.cpp -o $OUT/scion.exe \
  -I$D/src -I$D/externals/mcl/include -I$D/externals/fmt/include \
  $B/src/dynarmic/libdynarmic.a $(find $B/externals -name '*.a') -lbcrypt -lwinmm -lsynchronization -ldwmapi -lole32 -luuid -lgdi32 -lshell32 -lwindowscodecs -static -Wl,-Map=../out/scion.map
# scion: the native Linux host (#10), sharing lib/ with scion.exe. Needs dynarmic built for Linux
# (scripts/build-dynarmic.sh --linux) and SDL2, FreeType, fontconfig, libpng and libjpeg; without them, it is skipped.
L=$D/build-linux
if [ -f $L/src/dynarmic/libdynarmic.a ] && pkg-config --exists sdl2 freetype2 fontconfig libpng; then
  g++ -std=c++20 -O2 -Wall -Wno-unused-parameter host_linux.cpp ui_linux.cpp dyld.cpp arm64.cpp -o $OUT/scion \
    -I$D/src -I$D/externals/mcl/include -I$D/externals/fmt/include $(pkg-config --cflags sdl2 freetype2 fontconfig libpng) \
    $L/src/dynarmic/libdynarmic.a $(find $L/externals -name '*.a') $(pkg-config --libs sdl2 freetype2 fontconfig libpng) -ljpeg -lpthread -lrt
else echo "note: dynarmic for Linux (scripts/build-dynarmic.sh --linux) or SDL2/FreeType/fontconfig/libpng are missing: skipping bin/scion"; fi
# scionw.exe: scion.exe without a console window (Start menu shortcuts of installed apps)
x86_64-w64-mingw32-g++-posix -std=c++20 -O2 -Wall -municode -mwindows launcher.cpp -o $OUT/scionw.exe -lshell32 -lole32 -luuid -static
rm -rf $T
echo "OK -> $OUT"
