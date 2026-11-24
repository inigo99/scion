#!/usr/bin/env python3
"""missing_symbols.py APP_OR_BINARY [ARCH] [-v]: the symbols a macOS binary (and the frameworks inside its .app) imports that scion's
libraries (bin/lib) do not export, grouped by the library the binary expects them from and demangled.
The measure of how far an app is from loading: 0 missing means dyld can bind everything."""
import os, subprocess, sys, collections

MW = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEMANGLE = os.environ.get('SWIFT_DEMANGLE', 'swift-demangle')   # from a Swift toolchain; without it, names stay mangled

def nm(path, arch, undefined):
    flags = ['-m', '--undefined-only'] if undefined else ['-g', '--defined-only', '-j']
    r = subprocess.run(['llvm-nm-18', *flags, f'--arch={arch}', path], capture_output=True, text=True)
    return r.stdout.splitlines()

def binaries(app):
    if os.path.isfile(app):
        return [app]
    out = []
    for root, _, files in os.walk(app):
        for f in files:
            p = os.path.join(root, f)
            if os.path.islink(p) or not os.access(p, os.X_OK):
                continue
            with open(p, 'rb') as fh:
                if fh.read(4) in (b'\xca\xfe\xba\xbe', b'\xcf\xfa\xed\xfe'):
                    out.append(p)
    return out

def main():
    app, arch = sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else 'arm64'
    bins = binaries(app)
    have = set()
    libdir = os.path.join(MW, 'bin', 'lib')
    for f in os.listdir(libdir):
        if f.endswith('.dylib'):
            have.update(nm(os.path.join(libdir, f), arch, False))
    for b in bins:   # the app's own frameworks
        have.update(nm(b, arch, False))
    missing = collections.defaultdict(set)
    for b in bins:
        for line in nm(b, arch, True):
            parts = line.split()
            if len(parts) < 3 or '(from' not in line:
                continue
            sym, lib = line.split('(from ')[0].split()[-1], line.rsplit('(from ', 1)[1].rstrip(')')
            if sym not in have and '_swift_FORCE_LOAD_' not in sym:   # weak imports resolve to NULL: the app may still use them (e.g. Swift #available)
                missing[lib + (' (weak)' if line.lstrip().startswith('(undefined) weak') else '')].add(sym)
    total = sum(len(v) for v in missing.values())
    for lib in sorted(missing, key=lambda l: -len(missing[l])):
        syms = sorted(missing[lib])
        try:
            dem = subprocess.run([DEMANGLE, '--simplified'], input='\n'.join(s[1:] if s.startswith('_$') else s for s in syms),
                                 capture_output=True, text=True).stdout.splitlines()
        except FileNotFoundError:
            dem = syms
        print(f'== {lib}: {len(syms)}')
        if '-v' in sys.argv:
            for s, d in zip(syms, dem):
                print('  ', d if d != s[1:] else s)
    print(f'MISSING {total} symbols ({arch})')

main()
