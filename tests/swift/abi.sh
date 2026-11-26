#!/bin/sh
# abi.sh [DYLIB]: checks that Scion's SwiftUI exports the symbols of Apple's SwiftUI listed in tests/swift/swiftui-abi.txt
# (the APIs Scion declares, with Apple's mangled names, so apps compiled against Apple's SwiftUI bind to them). A missing
# function, initializer, getter or type fails; other missing symbols (property descriptors, conformance records...)
# are listed. Default: bin/lib/SwiftUI.dylib.
MW=$(cd "$(dirname "$0")/../.." && pwd)
L=${1:-$MW/bin/lib/SwiftUI.dylib}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for a in x86_64 arm64; do
  ${NM:-llvm-nm-18} -gU --arch=$a "$L" | awk '{print $3}' | sed 's/^_//' | sort -u > $T/ours
  sort -u "$MW/tests/swift/swiftui-abi.txt" | comm -23 - $T/ours > $T/missing
  grep -E '(fC|F|Mn|Ma|vg)$' $T/missing > $T/fatal
  echo "$a: $(wc -l < $T/missing) of $(wc -l < "$MW/tests/swift/swiftui-abi.txt") listed symbols missing, $(wc -l < $T/fatal) of them entry points"
  sed 's/^/  missing: /' $T/missing
  [ -s $T/fatal ] && fail=1
done
exit ${fail:-0}
