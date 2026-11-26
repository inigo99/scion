#!/bin/sh
# Builds the Swift overlays of the macOS SDK (Darwin, ObjectiveC, ...) for x86_64 and arm64 against scion's SDK and
# Swift runtime (src/build_swift.sh first) -> bin/lib/libswift<Name>.dylib (install name /usr/lib/swift/...) and
# out/swift/<arch>/<Name>.swiftmodule.
# Sources: Darwin from the Swift sources (SWIFT_SRC, stdlib/public/Platform); the Apple SDK overlays from the last Swift
# release that had them in the open (SWIFT_OVERLAYS: swiftlang/swift at swift-5.4.3-RELEASE, stdlib/public/Darwin and
# stdlib/public/SwiftShims). Their ABI is the stable one Apple's binaries link against.
set -e
MW=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${DEPS:-$MW/deps}
SWIFT_SRC=${SWIFT_SRC:-$DEPS/swift}
SWIFT_OVERLAYS=${SWIFT_OVERLAYS:-$DEPS/swift-overlays}
SWIFT_TC=${SWIFT_TC:?set SWIFT_TC to the usr/ directory of a Swift 6.1.3 toolchain for Linux (see docs/building.md)}
B=${SWIFT_BUILD:-$MW/out/swift-build}/overlays; rm -rf $B/mcache; mkdir -p $B/shims  # mcache: Clang modules, rebuilt every time (API notes and SDK headers change)
# a resource dir with only the stdlib shims and Clang's headers: the Linux toolchain's own also has Linux module maps
# (Dispatch, CoreFoundation, os) that would clash with the macOS ones. The shims are copied: a symlink would make
# Clang see their module map twice.
R=$SWIFT_TC/libexec/swift/lib/swift; rm -rf $B/res; mkdir -p $B/res; cp -r $R/shims $B/res/; ln -s $(readlink -f $R/clang) $B/res/clang
G=$SWIFT_SRC/utils/gyb; P=$SWIFT_SRC/stdlib/public/Platform; D=$SWIFT_OVERLAYS/stdlib/public/Darwin
# the overlays' private C shims (module names as in the 5.4 SwiftShims module map)
# (copied: their own directory's module map defines SwiftShims again)
for h in ObjectiveCOverlayShims DispatchOverlayShims CoreFoundationOverlayShims CFCharacterSetShims CFHashingShims \
         FoundationOverlayShims FoundationShimSupport NSCalendarShims NSCharacterSetShims NSCoderShims NSDataShims \
         NSDictionaryShims NSErrorShims NSFileManagerShims NSIndexPathShims NSIndexSetShims NSKeyedArchiverShims \
         NSLocaleShims NSTimeZoneShims NSUndoManagerShims; do cp $SWIFT_OVERLAYS/stdlib/public/SwiftShims/$h.h $B/shims/; done
# the Foundation overlay's shims, without those of the overlay files not built (NSCoder, NSKeyedArchiver, IndexPath,
# FileManager)
sed -i '/NSCoderShims\|NSKeyedArchiverShims\|NSFileManagerShims/d' $B/shims/FoundationOverlayShims.h
cat > $B/shims/module.modulemap <<EOM
module _SwiftObjectiveCOverlayShims [system] { header "ObjectiveCOverlayShims.h" }
module _SwiftDispatchOverlayShims [system] { header "DispatchOverlayShims.h" }
module _SwiftCoreFoundationOverlayShims [system] { header "CoreFoundationOverlayShims.h" }
module _SwiftFoundationOverlayShims [system] { header "FoundationOverlayShims.h" }
EOM
# Swift names for libdispatch and os (DispatchQueue for OS_dispatch_queue, ...): the SDK's usr/lib/swift/apinotes
mkdir -p $MW/sdk/darwin/usr/lib/swift/apinotes
cp $SWIFT_SRC/apinotes/Dispatch.apinotes $SWIFT_SRC/apinotes/os.apinotes $MW/sdk/darwin/usr/lib/swift/apinotes/
python3 $G -DCMAKE_SIZEOF_VOID_P=8 --line-directive '' -o $B/Darwin.swift $P/Darwin.swift.gyb
python3 $G -DCMAKE_SIZEOF_VOID_P=8 --line-directive '' -o $B/tgmath.swift $P/tgmath.swift.gyb
python3 $G -DCMAKE_SIZEOF_VOID_P=8 --line-directive '' -o $B/CGFloat.swift $D/CoreGraphics/CGFloat.swift.gyb
AV=$(grep -v '^#' $SWIFT_SRC/utils/availability-macros.def | grep -v '^$' | sed 's/.*/-Xfrontend -define-availability -Xfrontend "&"/' | tr '\n' ' ')
# ov ARCH NAME SOURCES...: one overlay -> out/swift/ARCH/NAME.swiftmodule + libswiftNAME.dylib
ov() {
  a=$1; n=$2; shift 2; O=$MW/out/swift/$a
  eval $SWIFT_TC/libexec/swift/bin/swiftc -target $a-apple-macosx14.0 -resource-dir $B/res -module-cache-path $B/mcache -sdk $MW/sdk/darwin -I $O -L $O -L ${SWIFT_BUILD:-$MW/out/swift-build}/sdklib \
    -Xcc -isystem -Xcc $MW/sdk/include -I $B/shims -use-ld=lld -ld-path=/usr/bin/ld64.lld-18 \
    -Xfrontend -disable-implicit-concurrency-module-import -Xfrontend -disable-implicit-string-processing-module-import \
    -Xfrontend -disable-objc-attr-requires-foundation-module $AV -O -parse-as-library -enable-library-evolution -import-underlying-module \
    -module-name $n -module-link-name swift$n -emit-library -emit-module -emit-module-path $O/$n.swiftmodule -o $O/libswift$n.dylib \
    -Xlinker -install_name -Xlinker /usr/lib/swift/libswift$n.dylib -Xlinker --error-limit=0 '"$@"' > $B/$n-$a.log 2>&1 \
    || { echo "compilation failed ($n, $a): $B/$n-$a.log"; grep -m5 "error" $B/$n-$a.log; exit 1; }
}
# FOUNDATION_ONLY=1: rebuild only the Foundation overlay (FOUNDATION_ARCHS: its architectures)
for a in $([ -z "${FOUNDATION_ONLY:-}" ] && echo x86_64 arm64); do
  ov $a Darwin $P/Platform.swift $P/TiocConstants.swift $P/POSIXError.swift $P/MachError.swift $B/Darwin.swift $B/tgmath.swift
  ov $a ObjectiveC $D/ObjectiveC/ObjectiveC.swift
  ov $a CoreFoundation $D/CoreFoundation/CoreFoundation.swift $MW/bin/lib/Foundation.dylib  # CF lives in Foundation.dylib
  # CoreGraphics: CGFloat (the C CGFloat type is imported as it) and the geometry helpers (src/swift/CGGeometry.swift);
  # scion's CoreGraphics has few of the other APIs that CoreGraphics.swift extends
  ov $a CoreGraphics $B/CGFloat.swift $MW/src/swift/CGGeometry.swift $MW/bin/lib/AppKit.dylib  # CG lives in AppKit.dylib
  # Combine (scion's, src/swift/Combine): the Dispatch and Foundation overlays' schedulers and publishers use it
  ONLY=Combine ARCHS=$a sh $MW/src/build_swiftui.sh > /dev/null
  # Dispatch: Dispatch.mm -> dispatch_overlay.c
  clang-20 -target $a-apple-macos14 -isysroot $MW/sdk/darwin -O2 -c $MW/src/swift/dispatch_overlay.c -o $B/dispatch_overlay_$a.o
  # Block.swift + the designated init(flags:block:) of newer overlays (apps call its initializing entry point)
  sed '/^\tpublic init(qos: DispatchQoS = .unspecified/i\
\tpublic init(flags: DispatchWorkItemFlags, block: @escaping @convention(block) () -> Void) {\
\t\t_block = _swift_dispatch_block_create_with_qos_class(__dispatch_block_flags_t(rawValue: flags.rawValue), DispatchQoS.unspecified.qosClass.rawValue, 0, block)\
\t}\
' $D/Dispatch/Block.swift > $B/Block.swift
  ov $a Dispatch $D/Dispatch/Dispatch.swift $B/Block.swift $D/Dispatch/Data.swift $D/Dispatch/IO.swift \
    $D/Dispatch/Private.swift $D/Dispatch/Queue.swift $D/Dispatch/Source.swift $D/Dispatch/Time.swift \
    $D/Dispatch/Schedulers+DispatchQueue.swift $B/dispatch_overlay_$a.o $O/Combine.dylib
  ov $a os $MW/src/swift/os.swift $MW/bin/lib/libobjc.A.dylib
done
# Foundation: a copy of the 5.4 overlay with scion's changes (patches/swift-foundation-overlay.patch), and only the
# files for the APIs scion's Foundation has (ponytail: no Combine, KVO publishers, URLSession, NSItemProvider, ...)
F=$B/foundation; rm -rf $F; cp -r $D/Foundation $F
# (scripts/fetch-deps.sh has usually applied the patch to the sources already)
if [ -s $MW/patches/swift-foundation-overlay.patch ] && ! (cd $F && patch -s -f -p1 -R --dry-run < $MW/patches/swift-foundation-overlay.patch >/dev/null 2>&1); then
  (cd $F && patch -s -p1 < $MW/patches/swift-foundation-overlay.patch)
fi
FOUNDATION_SOURCES="Foundation.swift Boxing.swift ReferenceConvertible.swift CheckClass.swift NSError.swift Data.swift
  DataProtocol.swift ContiguousBytes.swift Collections+DataProtocol.swift Pointers+DataProtocol.swift NSData+DataProtocol.swift
  DispatchData+DataProtocol.swift NSString.swift String.swift NSStringAPI.swift NSStringEncodings.swift NSRange.swift
  NSArray.swift NSDictionary.swift NSSet.swift NSNumber.swift NSFastEnumeration.swift PersonNameComponents.swift
  Date.swift NSDate.swift DateInterval.swift Locale.swift TimeZone.swift Calendar.swift DateComponents.swift
  CharacterSet.swift URL.swift NSURL.swift URLComponents.swift Codable.swift JSONEncoder.swift PlistEncoder.swift IndexPath.swift UUID.swift IndexSet.swift NSIndexSet.swift
  Decimal.swift Notification.swift NSPredicate.swift NSUndoManager.swift
  Publishers+Locking.swift Publishers+NotificationCenter.swift Publishers+Timer.swift
  Schedulers+Date.swift Schedulers+RunLoop.swift $MW/src/swift/AttributedString.swift $MW/src/swift/LocalizedStringResource.swift"
for a in ${FOUNDATION_ARCHS:-x86_64 arm64}; do
  ov $a Foundation $(for f in $FOUNDATION_SOURCES; do case $f in /*) echo $f;; *) echo $F/$f;; esac; done) $MW/bin/lib/Foundation.dylib $MW/out/swift/$a/Combine.dylib
  # AppKit after Foundation: its methods that return String bridge through Foundation's overlay (without it, Swift
  # 6.1's IRGen crashes lowering them)
  [ -n "${FOUNDATION_ONLY:-}" ] || ov $a AppKit $MW/src/swift/AppKitOverlay.swift $MW/bin/lib/AppKit.dylib
done
N="Darwin ObjectiveC CoreFoundation CoreGraphics Dispatch os AppKit Foundation"; [ -n "${FOUNDATION_ONLY:-}" ] && N=Foundation
for n in $N; do
  llvm-lipo-18 -create $MW/out/swift/arm64/libswift$n.dylib $MW/out/swift/x86_64/libswift$n.dylib -output $MW/bin/lib/libswift$n.dylib
done
echo "OK -> $MW/bin/lib/libswift{Darwin,ObjectiveC,CoreFoundation,CoreGraphics,Dispatch,os,AppKit,Foundation}.dylib"
