#!/bin/sh
# Builds Swift's runtime and standard library (Runtimes/Core of the Swift sources) for macOS x86_64 and arm64 against
# the scion SDK -> bin/lib/libswiftCore.dylib (install name /usr/lib/swift/libswiftCore.dylib, as on macOS) and
# out/swift/<arch>/ (Swift.swiftmodule + the dylib, to compile Swift programs: tests/swift/swiftc.sh).
# Inputs: SWIFT_SRC (swiftlang/swift at the toolchain's tag, after `cmake -P Runtimes/Resync.cmake`),
#         SWIFT_TC (a Swift toolchain's usr/, e.g. Ubuntu's swiftlang 6.1.3 package unpacked).
# The build uses the Apple configuration (ObjC interop, library evolution, Unicode data, SIMD, CommandLine, type names:
# SWIFT_STDLIB_HAS_TYPE_PRINTING by hand, the new Runtimes build only passes it to Demangling).
set -e
MW=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${DEPS:-$MW/deps}
SWIFT_SRC=${SWIFT_SRC:-$DEPS/swift}
SWIFT_TC=${SWIFT_TC:?set SWIFT_TC to the usr/ directory of a Swift 6.1.3 toolchain for Linux (see docs/building.md)}
B=${SWIFT_BUILD:-$MW/out/swift-build}; mkdir -p $B/bin $B/sdklib
# the Swift driver archives with Darwin's libtool; llvm-ar does the same
cat > $B/bin/libtool <<'EOF'
#!/bin/sh
out=; files=
while [ $# -gt 0 ]; do case "$1" in -static|-no_warning_for_no_symbols) ;; -o) out=$2; shift ;; -*) ;; *) files="$files $1" ;; esac; shift; done
rm -f "$out"; exec llvm-ar-18 crs "$out" $files
EOF
chmod +x $B/bin/libtool; export PATH=$B/bin:$PATH
# -lSystem, -lobjc, -lc++ find scion's libraries
for l in libSystem:libSystem.B libobjc:libobjc.A libc++:libc++.1 libFoundation:Foundation libAppKit:AppKit; do ln -sf $MW/bin/lib/${l#*:}.dylib $B/sdklib/${l%%:*}.dylib; done
for a in arm64 x86_64; do
  cat > $B/tc-$a.cmake <<EOF
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR $a)
set(CMAKE_OSX_ARCHITECTURES $a)
set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0)
set(CMAKE_OSX_SYSROOT $MW/sdk/darwin)
set(CMAKE_C_COMPILER clang-20)
set(CMAKE_CXX_COMPILER clang++-20)
set(CMAKE_C_COMPILER_TARGET $a-apple-macos14)
set(CMAKE_CXX_COMPILER_TARGET $a-apple-macos14)
set(CMAKE_Swift_COMPILER $SWIFT_TC/libexec/swift/bin/swiftc)
set(CMAKE_Swift_COMPILER_TARGET $a-apple-macosx14.0)
set(CMAKE_AR llvm-ar-18)
set(CMAKE_RANLIB llvm-ranlib-18)
set(CMAKE_INSTALL_NAME_TOOL /bin/true)
set(CMAKE_C_FLAGS_INIT "-isystem $MW/sdk/include -DSWIFT_STDLIB_HAS_TYPE_PRINTING")
set(CMAKE_CXX_FLAGS_INIT "-DSWIFT_STDLIB_HAS_TYPE_PRINTING -isystem $MW/sdk/libcxx-config -isystem $DEPS/llvm-runtimes/libcxx/include -isystem $DEPS/llvm-runtimes/libcxxabi/include -isystem $MW/sdk/include")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld --ld-path=/usr/bin/ld64.lld-18 -nostdlib $MW/bin/lib/libSystem.B.dylib $MW/bin/lib/libc++.1.dylib $MW/bin/lib/libobjc.A.dylib")
set(CMAKE_Swift_FLAGS_INIT "-use-ld=lld -ld-path=/usr/bin/ld64.lld-18 -L$B/sdklib")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_Swift_COMPILER_WORKS TRUE)
set(CMAKE_C_COMPILER_WORKS TRUE)
set(CMAKE_CXX_COMPILER_WORKS TRUE)
EOF
  mkdir -p $B/build-$a
  (cd $B/build-$a && cmake -G Ninja $SWIFT_SRC/Runtimes/Core -DCMAKE_TOOLCHAIN_FILE=$B/tc-$a.cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=YES \
     -DSwiftCore_ENABLE_UNICODE_DATA=ON -DSwiftCore_ENABLE_VECTOR_TYPES=ON -DSwiftCore_ENABLE_COMMANDLINE_SUPPORT=ON \
     -DSwiftCore_ENABLE_ENVIRONMENT=ON -DSwiftCore_ENABLE_STDIN=ON > $B/cmake-$a.log 2>&1 && ninja > $B/ninja-$a.log 2>&1) \
    || { echo "compilation failed ($a): $B/ninja-$a.log"; grep -m5 "error" $B/ninja-$a.log; exit 1; }
  O=$MW/out/swift/$a; mkdir -p $O
  cp $B/build-$a/core/libswiftCore.dylib $O/libswiftCore.dylib
  llvm-install-name-tool-18 -id /usr/lib/swift/libswiftCore.dylib $O/libswiftCore.dylib
  rm -rf $O/Swift.swiftmodule; cp -r $B/build-$a/core/Swift.swiftmodule $O/
done
llvm-lipo-18 -create $MW/out/swift/arm64/libswiftCore.dylib $MW/out/swift/x86_64/libswiftCore.dylib -output $MW/bin/lib/libswiftCore.dylib
echo "OK -> $MW/bin/lib/libswiftCore.dylib, $MW/out/swift"
