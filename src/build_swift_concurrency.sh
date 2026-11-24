#!/bin/sh
# Builds Swift's _Concurrency (async/await, Task, actors) from the Swift sources (stdlib/public/Concurrency) for x86_64 and
# arm64 against scion's SDK and Swift runtime (src/build_swift.sh first: it also leaves the Threading objects) ->
# bin/lib/libswift_Concurrency.dylib (install name /usr/lib/swift/libswift_Concurrency.dylib) and
# out/swift/<arch>/_Concurrency.swiftmodule. The global executor is Dispatch's, as on macOS (scion's libdispatch).
set -e
MW=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${DEPS:-$MW/deps}
SWIFT_SRC=${SWIFT_SRC:-$DEPS/swift}
SWIFT_TC=${SWIFT_TC:?set SWIFT_TC to the usr/ directory of a Swift 6.1.3 toolchain for Linux (see docs/building.md)}
SB=${SWIFT_BUILD:-$MW/out/swift-build}; B=$SB/concurrency; mkdir -p $B
C=$SWIFT_SRC/stdlib/public/Concurrency
AV=$(grep -v '^#' $SWIFT_SRC/utils/availability-macros.def | grep -v '^$' | sed 's/.*/-Xfrontend -define-availability -Xfrontend "&"/' | tr '\n' ' ')
CSRC="../CompatibilityOverride/CompatibilityOverride.cpp Actor.cpp AsyncLet.cpp Clock.cpp GlobalExecutor.cpp ConcurrencyHooks.cpp
  EmbeddedSupport.cpp Error.cpp ExecutorChecks.cpp Setup.cpp Task.cpp TaskAlloc.cpp TaskStatus.cpp TaskGroup.cpp TaskLocal.cpp
  ThreadingError.cpp TracingSignpost.cpp AsyncStream.cpp DispatchGlobalExecutor.cpp"
# scion's libdispatch has no dispatch_async_swift_job (jobs as dispatch objects): the executor's fallback,
# dispatch_async_f, is taken (its weak check sees a null function)
cat > $B/nojob.h <<'EOH'
#include <dispatch/dispatch.h>
static void (*const mw_no_swift_job)(dispatch_queue_t, void *, dispatch_qos_class_t) = 0;
#define dispatch_async_swift_job (*mw_no_swift_job)
EOH
SSRC=$(sed -n '/^set(SWIFT_RUNTIME_CONCURRENCY_SWIFT_SOURCES/,/^)/p' $C/CMakeLists.txt | sed '1d;$d' | tr -d ' ')
for a in x86_64 arm64; do
  O=$MW/out/swift/$a; mkdir -p $B/$a
  objs=
  for f in $CSRC; do
    o=$B/$a/$(basename $f .cpp).o; inc=; [ $f = DispatchGlobalExecutor.cpp ] && inc="-include $B/nojob.h"
    clang++-20 -target $a-apple-macos14 -isysroot $MW/sdk/darwin -O2 -std=c++17 -fvisibility=hidden -fno-rtti -fno-exceptions -funwind-tables \
      -DSWIFT_STDLIB_HAS_TYPE_PRINTING -isystem $MW/sdk/libcxx-config -isystem $DEPS/llvm-runtimes/libcxx/include \
      -isystem $DEPS/llvm-runtimes/libcxxabi/include -isystem $MW/sdk/include \
      -DSWIFT_ENABLE_REFLECTION -DSWIFT_LIBRARY_EVOLUTION -DSWIFT_OBJC_INTEROP -DSWIFT_RUNTIME_OS_VERSIONING -DSWIFT_STDLIB_HAS_ENVIRON \
      -DSWIFT_TARGET_LIBRARY_NAME=swift_Concurrency -Dswift_Concurrency_EXPORTS -D__STDC_WANT_LIB_EXT1__=1 -fswift-async-fp=always \
      -DSWIFT_CONCURRENCY_USES_DISPATCH=1 -DSWIFT_THREADING_DARWIN $inc -I$SB/build-$a/include -I$SWIFT_SRC/Runtimes/Core/include -I$SWIFT_SRC/stdlib/include -I$SWIFT_SRC/include \
      -I$SWIFT_SRC/Runtimes/Core/SwiftShims -I$SWIFT_SRC/Runtimes/Core/runtime -c $C/$f -o $o > $B/$a/$(basename $f .cpp).log 2>&1 \
      || { echo "compilation failed ($f, $a): $B/$a/$(basename $f .cpp).log"; grep -m5 "error" $B/$a/$(basename $f .cpp).log; exit 1; }
    objs="$objs $o"
  done
  objs="$objs $(find $SB/build-$a/Threading/CMakeFiles/swiftThreading.dir -name "*.o")"
  eval $SWIFT_TC/libexec/swift/bin/swiftc -target $a-apple-macosx14.0 -sdk $MW/sdk/darwin -I $O -L $O -L $SB/sdklib \
    -resource-dir $SB/overlays/res -module-cache-path $B/mcache -Xcc -isystem -Xcc $MW/sdk/include \
    -Xcc -fmodule-map-file=$SWIFT_SRC/Runtimes/Core/SwiftShims/swift/shims/module.modulemap \
    -use-ld=lld -ld-path=/usr/bin/ld64.lld-18 -O -wmo $AV -enable-library-evolution -parse-stdlib -parse-as-library \
    -D SWIFT_CONCURRENCY_USES_DISPATCH -D SWIFT_RUNTIME_OS_VERSIONING -D SWIFT_STDLIB_HAS_ENVIRON -D SWIFT_THREADING_DARWIN \
    -I $C/InternalShims -enable-experimental-feature IsolatedAny -Xfrontend -swift-async-frame-pointer=always \
    -enable-experimental-feature NoncopyableGenerics2 -enable-experimental-feature SuppressedAssociatedTypes \
    -enable-experimental-feature SE427NoInferenceOnExtension -enable-experimental-feature AllowUnsafeAttribute \
    -enable-experimental-feature TypedThrows -enable-experimental-feature BitwiseCopyable -enable-experimental-feature Extern \
    -enable-experimental-feature Macros -enable-experimental-feature FreestandingMacros \
    -no-link-objc-runtime -library-level api -runtime-compatibility-version none \
    -Xfrontend -disable-implicit-concurrency-module-import -Xfrontend -disable-implicit-string-processing-module-import \
    -Xfrontend -disable-implicit-backtracing-module-import -Xfrontend -disable-objc-attr-requires-foundation-module \
    -Xfrontend -enforce-exclusivity=unchecked -Xfrontend -enable-ossa-modules -Xfrontend -target-min-inlining-version -Xfrontend min \
    -Xfrontend -disable-autolinking-runtime-compatibility-concurrency \
    -module-name _Concurrency -module-link-name swift_Concurrency -emit-library -emit-module -emit-module-path $O/_Concurrency.swiftmodule \
    -o $O/libswift_Concurrency.dylib -Xlinker -install_name -Xlinker /usr/lib/swift/libswift_Concurrency.dylib -Xlinker --error-limit=0 \
    $(for f in $SSRC; do echo $C/$f; done) $objs $MW/bin/lib/libc++.1.dylib $MW/bin/lib/libobjc.A.dylib > $B/swift-$a.log 2>&1 \
    || { echo "compilation failed (_Concurrency, $a): $B/swift-$a.log"; grep -m8 "error" $B/swift-$a.log; exit 1; }
done
llvm-lipo-18 -create $MW/out/swift/arm64/libswift_Concurrency.dylib $MW/out/swift/x86_64/libswift_Concurrency.dylib -output $MW/bin/lib/libswift_Concurrency.dylib
echo "OK -> $MW/bin/lib/libswift_Concurrency.dylib"
