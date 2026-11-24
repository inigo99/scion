#!/bin/sh
# swiftc.sh ARCH OUT FILES... [swiftc options]: compiles Swift for macOS 14 against Scion's Swift runtime and overlays
# (out/swift/<arch>: src/build_swift.sh, src/build_swift_overlays.sh) and SDK. Uses the overlays' build resource dir
# (the Linux toolchain's own has Linux module maps). SWIFT_TC: the Swift 6.1.3 toolchain's usr folder (docs/building.md).
# ponytail: no _StringProcessing module yet.
MW=$(cd "$(dirname "$0")/../.." && pwd)
: "${SWIFT_TC:?set SWIFT_TC to a Swift 6.1.3 toolchain's usr folder (docs/building.md)}"
B=${SWIFT_BUILD:-$MW/out/swift-build}
a=$1; o=$2; shift 2
exec $SWIFT_TC/libexec/swift/bin/swiftc -target $a-apple-macosx14.0 -O -resource-dir $B/overlays/res -module-cache-path $B/overlays/mcache \
  -sdk $MW/sdk/darwin -Xcc -isystem -Xcc $MW/sdk/include -I $MW/out/swift/$a -L $MW/out/swift/$a -L $B/sdklib \
  -use-ld=lld -ld-path=${LD64:-/usr/bin/ld64.lld-18} \
  -Xfrontend -disable-implicit-string-processing-module-import "$@" -o $o
