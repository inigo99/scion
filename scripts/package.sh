#!/bin/sh
# Packages bin/ as a release: out/scion-<version>-windows-x64.zip (one top-level folder, as the CI expects).
# Usage: scripts/package.sh 0.1.0
set -e
cd "$(dirname "$0")/.."
V=${1:?usage: scripts/package.sh VERSION}; N=scion-$V-windows-x64; S=out/package/$N
for f in scion.exe scionw.exe scion-metal.dll scion-msl.dll lib/libSystem.B.dylib lib/libswiftCore.dylib; do
  [ -f bin/$f ] || { echo "bin/$f is missing (docs/building.md)"; exit 1; }
done
rm -rf out/package; mkdir -p $S
cp -R bin/scion.exe bin/scionw.exe bin/scion-metal.dll bin/scion-msl.dll bin/lib $S/
cp -R README.md LICENSE THIRD_PARTY_NOTICES.md CHANGELOG.md licenses $S/
(cd out/package && rm -f ../$N.zip && zip -qr9 ../$N.zip $N)
echo "out/$N.zip"
