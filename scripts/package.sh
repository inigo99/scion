#!/bin/sh
# Packages bin/ as a release, with one top-level folder (as the CI expects):
#   scripts/package.sh 0.1.0           -> out/scion-0.1.0-windows-x64.zip
#   scripts/package.sh 0.1.0 --linux   -> out/scion-0.1.0-linux-x86_64.tar.xz (the native Linux host)
# The host binaries are stripped in the package (bin/ keeps its symbols for debugging and profiling).
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
if [ "$2" = --linux ]; then (cd $S && strip $FILES); else (cd $S && x86_64-w64-mingw32-strip $FILES); fi
cp -R bin/lib $S/
cp -R README.md LICENSE THIRD_PARTY_NOTICES.md CHANGELOG.md licenses $S/
if [ "$2" = --linux ]; then
  (cd out/package && rm -f ../$N.tar.xz && tar cf - $N | xz -9 -T0 > ../$N.tar.xz)
  echo "out/$N.tar.xz"
else
  (cd out/package && rm -f ../$N.zip && zip -qr9 ../$N.zip $N)
  echo "out/$N.zip"
fi
