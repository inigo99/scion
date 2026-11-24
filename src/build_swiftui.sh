#!/bin/sh
# Builds scion's own Swift frameworks for x86_64 and arm64: Combine (src/swift/Combine) and SwiftUI (src/swift/SwiftUI),
# with the module names and install names of Apple's (/System/Library/Frameworks/X.framework/Versions/A/X), so apps
# compiled by Apple bind to them -> bin/lib/X.dylib and out/swift/<arch>/X.swiftmodule.
# Needs src/build_swift.sh, src/build_swift_concurrency.sh and src/build_swift_overlays.sh first.
# ONLY=Combine or ONLY=SwiftUI rebuilds one of them; ARCHS=x86_64 one architecture (build_swift_overlays.sh builds
# Combine between the Darwin and the Dispatch overlays, which use it).
set -e
MW=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${DEPS:-$MW/deps}
SWIFT_SRC=${SWIFT_SRC:-$DEPS/swift}
SWIFT_TC=${SWIFT_TC:?set SWIFT_TC to the usr/ directory of a Swift 6.1.3 toolchain for Linux (see docs/building.md)}
SB=${SWIFT_BUILD:-$MW/out/swift-build}; B=$SB/frameworks; mkdir -p $B
AV=$(grep -v '^#' $SWIFT_SRC/utils/availability-macros.def | grep -v '^$' | sed 's/.*/-Xfrontend -define-availability -Xfrontend "&"/' | tr '\n' ' ')
# fw ARCH NAME [extra inputs...]: src/swift/NAME/*.swift -> NAME.dylib + NAME.swiftmodule
fw() {
  a=$1; n=$2; shift 2; O=$MW/out/swift/$a
  eval $SWIFT_TC/libexec/swift/bin/swiftc -target $a-apple-macosx14.0 -resource-dir $SB/overlays/res -module-cache-path $SB/overlays/mcache \
    -sdk $MW/sdk/darwin -I $O -L $O -L $SB/sdklib -L $MW/bin/lib -Xcc -isystem -Xcc $MW/sdk/include -use-ld=lld -ld-path=/usr/bin/ld64.lld-18 \
    -Xfrontend -disable-implicit-string-processing-module-import $AV -O -parse-as-library -enable-library-evolution \
    -module-name $n -module-link-name $n -emit-library -emit-module -emit-module-path $O/$n.swiftmodule -o $O/$n.dylib \
    -Xlinker -install_name -Xlinker /System/Library/Frameworks/$n.framework/Versions/A/$n -Xlinker --error-limit=0 \
    $MW/src/swift/$n/*.swift '"$@"' > $B/$n-$a.log 2>&1 \
    || { echo "compilation failed ($n, $a): $B/$n-$a.log"; grep -m8 "error" $B/$n-$a.log; exit 1; }
}
for n in ${ONLY:-Combine}; do
  # lib$n.dylib: the module's autolink entry is -l$n (Apple's is -framework $n)
  # scion's ObjC frameworks: their module maps autolink -lAppKit, -lFoundation (scion names them AppKit.dylib, ...)
  deps=""; [ $n = SwiftUI ] && deps="$MW/bin/lib/AppKit.dylib $MW/bin/lib/Foundation.dylib"
  for a in ${ARCHS:-x86_64 arm64}; do fw $a $n $deps; ln -sf $n.dylib $MW/out/swift/$a/lib$n.dylib; done
  [ -f $MW/out/swift/arm64/$n.dylib ] && [ -f $MW/out/swift/x86_64/$n.dylib ] || continue
  llvm-lipo-18 -create $MW/out/swift/arm64/$n.dylib $MW/out/swift/x86_64/$n.dylib -output $MW/bin/lib/$n.dylib
  echo "OK -> $MW/bin/lib/$n.dylib"
done
