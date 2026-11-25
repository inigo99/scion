#!/bin/sh
# Fuzzes the readers of files that come with an app (libFuzzer with ASan and UBSan, clang 18): the Mach-O loader
# (src/dyld.cpp), Info.plist and .icns (src/bundle.h, read by `scion install`) and the LZFSE decoder of asset catalogs
# (src/appkit/lzfse.m).
# Usage: tests/fuzz/run.sh [SECONDS per target, default 60]
# Needs clang-18 and libclang-rt-18-dev; seeds come from out/tests (tests/build.sh, and tests/apps/fetch.sh for asset
# catalogs). Findings stay in out/fuzz/<target>/ (crash-*, timeout-*, oom-*): replay one with out/fuzz/<target>/fuzz FILE.
set -e
cd "$(dirname "$0")/../.."
T=${1:-60}; O=out/fuzz; CXX=${CXX:-clang++-18}; CC=${CC:-clang-18}
F="-g -O1 -fsanitize=fuzzer,address,undefined -fno-sanitize-recover=undefined"
for t in macho bundle lzfse; do mkdir -p $O/$t/seeds $O/$t/corpus; done
$CXX $F -std=c++20 -Isrc tests/fuzz/fuzz_macho.cpp src/dyld.cpp -o $O/macho/fuzz
$CXX $F -std=c++17 tests/fuzz/fuzz_bundle.cpp -o $O/bundle/fuzz
$CC $F -x c -c src/appkit/lzfse.m -o $O/lzfse/lzfse.o
$CXX $F tests/fuzz/fuzz_lzfse.cpp $O/lzfse/lzfse.o -o $O/lzfse/fuzz

# seeds: small Mach-O files (thin, chained fixups, a dylib, Go, universal), the bundles' plists (also as binary plists)
# and icons, LZFSE blocks cut out of asset catalogs
for f in hello_x86_64 hello_arm64 hello_chained_x86_64 hello_chained_arm64 dylib/app_x86_64 dylib/libmylib_arm64.dylib \
         runtime_x86_64 exceptions_arm64 signals_arm64; do
  [ -f out/tests/$f ] && cp out/tests/$f $O/macho/seeds/$(echo $f | tr / _)
done
[ -f out/tests/hello_x86_64 ] && [ -f out/tests/hello_arm64 ] && command -v llvm-lipo-18 >/dev/null &&
  llvm-lipo-18 -create out/tests/hello_x86_64 out/tests/hello_arm64 -output $O/macho/seeds/universal
python3 - "$O" <<'EOF'
import glob, hashlib, plistlib, sys
o = sys.argv[1]
for f in glob.glob('out/tests/**/Info.plist', recursive=True) + glob.glob('out/tests/**/*.icns', recursive=True) \
         + glob.glob('out/tests/**/*.strings', recursive=True):
    b = open(f, 'rb').read()
    if len(b) > 200000: continue
    h = hashlib.md5(f.encode()).hexdigest()[:10]
    open(f'{o}/bundle/seeds/{h}', 'wb').write(b)
    if f.endswith('.plist'):
        try: open(f'{o}/bundle/seeds/{h}.bin', 'wb').write(plistlib.dumps(plistlib.loads(b), fmt=plistlib.FMT_BINARY))
        except Exception: pass
n = 0
for car in glob.glob('out/tests/**/Assets.car', recursive=True):
    b = open(car, 'rb').read(); i = b.find(b'bvx2')
    while i >= 0 and n < 200:
        j = b.find(b'bvx$', i)
        if 0 < j - i < 200000: open(f'{o}/lzfse/seeds/s{n}', 'wb').write(b[i:j + 4]); n += 1
        i = b.find(b'bvx2', i + 4)
open(f'{o}/lzfse/seeds/raw', 'wb').write(b'bvx-\x05\x00\x00\x00hellobvx$')   # an uncompressed block
EOF

fail=0
for t in macho:3000000 bundle:65536 lzfse:262144; do
  name=${t%%:*}; echo "== $name ($T s)"
  (cd $O/$name && ./fuzz -max_total_time=$T -timeout=10 -rss_limit_mb=2560 -max_len=${t#*:} corpus seeds > log 2>&1) || fail=1
  grep -E "^Done|ERROR|SUMMARY|runtime error|Test unit written" $O/$name/log || true
done
[ $fail = 0 ] && echo "fuzz: no findings" || { echo "fuzz: findings in $O/*/ (crash-*, timeout-*, oom-*)"; exit 1; }
