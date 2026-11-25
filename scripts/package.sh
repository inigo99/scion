#!/bin/sh
# Packages bin/ as a release, with one top-level folder (as the CI expects):
#   scripts/package.sh 0.1.0           -> out/scion-0.1.0-windows-x64.zip
#   scripts/package.sh 0.1.0 --linux   -> out/scion-0.1.0-linux-x86_64.tar.gz (the native Linux host)
set -e
cd "$(dirname "$0")/.."
V=${1:?usage: scripts/package.sh VERSION [--linux]}
if [ "$2" = --linux ]; then N=scion-$V-linux-x86_64; FILES="scion scion-metal.so scion-msl.so"
else N=scion-$V-windows-x64; FILES="scion.exe scionw.exe scion-metal.dll scion-msl.dll"; fi
S=out/package/$N
for f in $FILES lib/libSystem.B.dylib lib/libswiftCore.dylib; do
  [ -f bin/$f ] || { echo "bin/$f is missing (docs/building.md)"; exit 1; }
done
rm -rf out/package; mkdir -p $S
for f in $FILES; do cp bin/$f $S/; done
cp -R bin/lib $S/
cp -R README.md LICENSE THIRD_PARTY_NOTICES.md CHANGELOG.md licenses $S/
if [ "$2" = --linux ]; then
  (cd out/package && rm -f ../$N.tar.gz && tar czf ../$N.tar.gz $N)
  echo "out/$N.tar.gz"
else
  (cd out/package && rm -f ../$N.zip && zip -qr9 ../$N.zip $N)
  echo "out/$N.zip"
fi
