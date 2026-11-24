#!/bin/sh
# Builds class-dump 3.5 (Steve Nygard, GPLv2; Objective-C + Foundation) for arm64 only, against Scion's SDK: a real
# Objective-C program for the tests. Not part of Scion: it is cloned from GitHub into a temporary folder.
# Usage: sh tests/apps/class-dump.sh   ->   out/tests/class-dump_arm64
set -e
cd "$(dirname "$0")/../.."
M=$(pwd); W=${TMPDIR:-/tmp}/scion-class-dump; mkdir -p $W/obj out/tests
[ -d $W/src ] || git clone -q --depth 1 https://github.com/nygard/class-dump $W/src
cd $W/src
F="-target arm64-apple-macos11 -isysroot $M/sdk/darwin -O1 -w"
for f in Source/*.m class-dump.m; do
  clang $F -isystem $M/sdk/include -fobjc-arc -fobjc-runtime=macosx-11 -fobjc-exceptions -include MachObjC-Prefix.pch \
    -ISource -IThirdParty -c $f -o $W/obj/$(basename $f .m).o &
done; wait
clang $F -c ThirdParty/blowfish.c -o $W/obj/blowfish.o
L=$M/bin/lib
${LD64:-ld64.lld-18} -arch arm64 -platform_version macos 11.0 11.0 -o $M/out/tests/class-dump_arm64 $W/obj/*.o \
  $L/Foundation.dylib $L/libobjc.A.dylib $L/libSystem.B.dylib
echo "class-dump -> out/tests/class-dump_arm64"
