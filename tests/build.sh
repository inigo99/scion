#!/bin/sh
# Builds the macOS test programs (x86_64 and arm64) into out/tests, against Scion's own libraries in bin/lib and the
# headers in sdk/ (no Apple SDK). Needs clang and ld64.lld (LLVM 18 or newer) and bin/lib (src/build.sh).
# Optional parts are built when their tools are there: Go (go), Swift (SWIFT_TC, see docs/building.md) and class-dump
# (git + network). Then run tests/run.sh (Linux + Wine) or tests/run.ps1 (Windows).
set -e
cd "$(dirname "$0")/.."
T=tests O=out/tests L=bin/lib DEPS=${DEPS:-deps}
LD=${LD64:-$(command -v ld64.lld-18 || command -v ld64.lld)}
W=$O/obj; mkdir -p $W $O/dylib
[ -f $L/libSystem.B.dylib ] || { echo "bin/lib is missing: build Scion first (src/build.sh)"; exit 1; }
C="-isysroot sdk/darwin -isystem sdk/include -O2 -fblocks"
OBJC="-fobjc-runtime=macosx-11 -fobjc-exceptions -fconstant-cfstrings -Wno-objc-property-no-attribute -Wno-protocol"
FW="$L/AppKit.dylib $L/Metal.dylib $L/GameController.dylib $L/AudioToolbox.dylib $L/Foundation.dylib $L/libobjc.A.dylib"

# background jobs, JOBS (default: the number of CPUs) at a time; `finish` waits for them and fails if any did
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}; rm -f $W/FAILED $W/slots
mkfifo $W/slots; exec 3<>$W/slots; rm $W/slots; i=0; while [ $i -lt $JOBS ]; do echo >&3; i=$((i+1)); done   # one token per free slot
job() { read -r _ <&3; ("$@" 3>&- || { echo "failed: $*" >&2; touch $W/FAILED; }; echo >&3) & }
finish() { wait; [ ! -f $W/FAILED ] || exit 1; }
# prog NAME SOURCE "COMPILE FLAGS" "LINK INPUTS" -> $O/NAME_{x86_64,arm64}, built in the background
prog1() {
  case $3 in *.cpp) cc=clang++;; *) cc=clang;; esac
  $cc -target $1-apple-macos11 $C $4 -c $T/$3 -o $W/$2_$1.o &&
  $LD -arch $1 -platform_version macos 11.0 11.0 -o $O/$2_$1 $W/$2_$1.o $5 $L/libSystem.B.dylib
}
prog() { for a in x86_64 arm64; do job prog1 $a "$@"; done; }

# the smallest guest, with classic binds and with chained fixups
for a in x86_64 arm64; do
  clang -target $a-apple-macos11 $C -c $T/c/hello.c -o $W/hello_$a.o
  $LD -arch $a -platform_version macos 11.0 11.0 -no_fixup_chains -o $O/hello_$a $W/hello_$a.o $L/libSystem.B.dylib
  $LD -arch $a -platform_version macos 11.0 11.0 -fixup_chains -o $O/hello_chained_$a $W/hello_$a.o $L/libSystem.B.dylib
done
# C: signals, Mach, GCD, run-time code, vm_remap, sockets, dispatch sources, audio
prog mach_signals c/mach_signals.c
prog gcd c/gcd.c
prog jit c/jit.c
prog remap c/remap.c
prog net c/net.c
prog spawn c/spawn.c
prog sources gcd/sources.c
prog audio audio/audio.c "-Wno-four-char-constants" "$L/AudioToolbox.dylib"
# a dylib found through @rpath, with a thread-local variable in the executable
for a in x86_64 arm64; do
  clang -target $a-apple-macos11 $C -c $T/c/dylib/mylib.c -o $W/mylib_$a.o
  $LD -arch $a -platform_version macos 11.0 11.0 -dylib -install_name @rpath/libmylib_$a.dylib -o $O/dylib/libmylib_$a.dylib $W/mylib_$a.o $L/libSystem.B.dylib
  clang -target $a-apple-macos11 $C -c $T/c/dylib/main.c -o $W/dylibapp_$a.o
  $LD -arch $a -platform_version macos 11.0 11.0 -rpath @executable_path -o $O/dylib/app_$a $W/dylibapp_$a.o $O/dylib/libmylib_$a.dylib $L/libSystem.B.dylib
done
# C++ (libc++, libc++abi, libunwind)
CXX="-std=c++20 -nostdinc++ -isystem sdk/libcxx-config -isystem $DEPS/llvm-runtimes/libcxx/include"   # libc++ headers: scripts/fetch-deps.sh
prog cxx cpp/cxx.cpp "$CXX" "$L/libc++.1.dylib"
prog threads cpp/threads.cpp "$CXX" "$L/libc++.1.dylib"
# Objective-C: the runtime without Foundation, Foundation, exceptions, regex, AppKit pieces
prog runtime objc/runtime.m "$OBJC -fobjc-arc" "$L/libobjc.A.dylib"
for t in foundation foundation2 exceptions regex invocations urlsession task; do prog $t objc/$t.m "$OBJC -fobjc-arc" "$L/Foundation.dylib $L/libobjc.A.dylib"; done
for t in autolayout asset_catalog; do prog ${t}2 objc/$t.m "$OBJC -fobjc-arc" "$FW"; done
for t in status_item table_views; do prog $t objc/$t.m "$OBJC -fno-objc-arc" "$FW"; done
# AppKit, GameController (ARC, like real apps)
for t in appkit dialogs drawing autolayout coretext; do prog $t appkit/$t.m "$OBJC -fobjc-arc" "$FW"; done
# a font file for the CoreText test to register (any TrueType/OpenType font fontconfig knows; skipped without one)
f=$(fc-match -f '%{file}' 'DejaVu Sans:bold' 2>/dev/null) && case $f in *.ttf|*.otf) cp "$f" $O/font.ttf;; esac
for t in gamepad keyboard; do prog $t gamepad/$t.m "$OBJC -fobjc-arc" "$FW"; done
# Metal: Apple-compiled sample metallibs from Indium's tests (deps/indium, scripts/fetch-deps.sh), a modern-AIR metallib
# generated here, and MSL sources compiled at run time
I=$DEPS/indium/test
if [ -d $I ]; then
  cp $I/basic-compute/add.metallib $O/add.metallib; cp $I/cube/shaders.metallib $O/cube.metallib
  cp $I/sampler/AAPLShaders.metallib $O/texture.metallib; cp $I/triangle/AAPLShaders.metallib $O/AAPLShaders.metallib
else echo "note: $I is missing (scripts/fetch-deps.sh): the compute, triangle, cube, window and texture tests will fail"; fi
python3 $T/metal/air/mkmetallib.py $O/ng.metallib $T/metal/air/kernels.c $T/metal/air/kernels.spec $T/metal/air/matrix.ll $T/metal/air/matrix.spec
cp $T/metal/msl/compute.metal $O/msl_compute.metal; cp $T/metal/msl/render.metal $O/msl_render.metal
for t in compute triangle cube window ng texture msl metalfx; do prog $t metal/$t.m "$OBJC -fno-objc-arc" "$FW"; done
# a sample app bundle (Swift fills in its executable below) and a file for the third-party app tests
rm -rf $O/Sample.app; cp -R $T/swift/Sample.app $O/Sample.app; chmod -R u+w $O/Sample.app
# Hello.app: the smallest app bundle (hello as a universal binary), for running bundles and for scion install
rm -rf $O/Hello.app; mkdir -p $O/Hello.app/Contents/MacOS $O/Hello.app/Contents/Resources
${LIPO:-llvm-lipo-18} -create $O/hello_x86_64 $O/hello_arm64 -output $O/Hello.app/Contents/MacOS/Hello
cp $T/swift/Sample.app/Contents/Resources/Sample.icns $O/Hello.app/Contents/Resources/Hello.icns
sed -e 's/>Sample</>Hello</g' -e 's/dev\.scion\.sample/dev.scion.hello/' $T/swift/Sample.app/Contents/Info.plist > $O/Hello.app/Contents/Info.plist
printf 'Scion test file\n0123456789abcdef\n' > $O/sample.bin

# optional: Go (signals and asynchronous preemption)
if command -v go >/dev/null; then
  for a in x86_64:amd64 arm64:arm64; do
    (cd $T/go/signals && CGO_ENABLED=0 GOOS=darwin GOARCH=${a#*:} go build -o "$OLDPWD/$O/signals_${a%%:*}" .)
  done
else echo "note: no Go toolchain: skipping the Go test"; fi
finish
# optional: Swift (needs SWIFT_TC and Scion's Swift runtime, out/swift: src/build_swift*.sh)
if [ -n "$SWIFT_TC" ] && [ -d out/swift ]; then
  for a in x86_64 arm64; do
    for t in language combine system foundation; do sh $T/swift/swiftc.sh $a $O/swift_${t}_$a $T/swift/$t.swift; done
    for t in concurrency swiftui; do sh $T/swift/swiftc.sh $a $O/swift_${t}_$a $T/swift/$t.swift -parse-as-library; done   # @main
    sh $T/swift/swiftc.sh $a $W/Sample_$a $T/swift/plist.swift
  done
  mkdir -p $O/Sample.app/Contents/MacOS   # a universal binary: the runner picks the architecture with SCION_ARCH
  ${LIPO:-llvm-lipo-18} -create $W/Sample_x86_64 $W/Sample_arm64 -output $O/Sample.app/Contents/MacOS/Sample
else echo "note: SWIFT_TC is not set (or out/swift is missing): skipping the Swift tests"; fi
# optional: class-dump 3.5 (a real Objective-C app, arm64 only), built from its GitHub source
sh $T/apps/class-dump.sh || echo "note: could not build class-dump (needs git and network): skipping it"
echo "tests built in $O"
