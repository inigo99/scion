#!/usr/bin/env python3
"""mkmetallib.py out.metallib kernels.c kernels.spec [more.ll more.spec ...]
Builds a test metallib without Apple's tools: clang-20 compiles the C kernels (Metal address spaces via attributes,
air.* intrinsics via __asm names), each function gets its own module with the !air.* metadata Apple's compiler
emits, and everything is packed into an MTLB container. The bitcode uses opaque pointers (modern AIR)."""
import os, re, struct, subprocess, sys, tempfile

AIR_DL = ('e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-'
          'v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32')
TYPES = {'vertex': 0, 'fragment': 1, 'kernel': 2}


def run(*cmd):
    subprocess.run(cmd, check=True)


def param_md(spec, mdid):
    idx, kind, *rest = spec.split(':')
    if kind == 'buffer':
        loc = rest[0] if rest else idx
        return (f'!{{i32 {idx}, !"air.buffer", !"air.location_index", i32 {loc}, i32 1, !"air.read_write", '
                f'!"air.arg_type_size", i32 4, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"uint", !"air.arg_name", !"b{idx}"}}')
    return f'!{{i32 {idx}, !"{kind}", !"air.arg_type_name", !"uint", !"air.arg_name", !"p{idx}"}}'


def build_function(ll_all, name, kind, params, work, fcs=()):
    ll = os.path.join(work, name + '.ll')
    run('llvm-extract-20', '-S', '--keep-const-init', f'--func={name}', ll_all, '-o', ll)
    text = open(ll).read()
    text = re.sub(r'target datalayout = "[^"]*"', f'target datalayout = "{AIR_DL}"', text)
    text = re.sub(r'target triple = "[^"]*"', 'target triple = "air64-apple-macosx14.0.0"', text)
    base = 90000
    lines = [f'!air.{kind} = !{{!{base}}}',
             f'!{base} = !{{ptr @{name}, !{base + 1}, !{base + 2}}}',
             f'!{base + 1} = !{{}}',
             f'!{base + 2} = !{{' + ', '.join(f'!{base + 3 + i}' for i in range(len(params))) + '}']
    for i, p in enumerate(params):
        lines.append(f'!{base + 3 + i} = {param_md(p, base + 3 + i)}')
    present = [fc for fc in fcs if re.search(rf'^@{fc[0]} ', text, re.M)]
    if present:  # function constants used by this function: {value global, type, name, index, required}
        lines.append('!air.function_constants = !{' + ', '.join(f'!{base + 200 + i}' for i in range(len(present))) + '}')
        for i, (g, t, n, idx) in enumerate(present):
            lines.append(f'!{base + 200 + i} = !{{ptr addrspace(2) @{g}, !"{t}", !"{n}", i32 {idx}, i1 true}}')
    lines.append(f'!air.version = !{{!{base + 100}}}')
    lines.append(f'!{base + 100} = !{{i32 2, i32 6, i32 0}}')
    text += '\n' + '\n'.join(lines) + '\n'
    open(ll, 'w').write(text)
    bc = os.path.join(work, name + '.bc')
    run('llvm-as-20', ll, '-o', bc)
    return open(bc, 'rb').read()


def pack(funcs):
    """funcs: list of (name, type, bitcode) -> MTLB bytes"""
    entries, bcs, off = [], b'', 0
    for name, ftype, bc in funcs:
        tags = b'NAME' + struct.pack('<H', len(name) + 1) + name.encode() + b'\0'
        tags += b'TYPE' + struct.pack('<HB', 1, ftype)
        tags += b'MDSZ' + struct.pack('<HQ', 8, len(bc))
        tags += b'OFFT' + struct.pack('<HQQQ', 24, 0, 0, off)
        tags += b'ENDT'
        entries.append(struct.pack('<I', len(tags) + 4) + tags)
        bcs += bc
        off += len(bc)
    flist = struct.pack('<I', len(entries)) + b''.join(entries)
    hdr_size = 88
    fl_off = hdr_size
    bc_off = fl_off + len(flist)
    total = bc_off + len(bcs)
    hdr = b'MTLB' + struct.pack('<HHHBBHH', 0x8001, 1, 2, 0, 1, 14, 0)
    hdr += struct.pack('<QQQQQQQQQ', total, fl_off, len(flist), bc_off, 0, bc_off, 0, bc_off, len(bcs))
    assert len(hdr) == hdr_size
    return hdr + flist + bcs


def main():
    """mkmetallib.py out.metallib (source.c|source.ll spec)..."""
    out, pairs = sys.argv[1], sys.argv[2:]
    funcs = []
    with tempfile.TemporaryDirectory() as work:
        for n, (src, spec) in enumerate(zip(pairs[::2], pairs[1::2])):
            ll_all = os.path.join(work, f'all{n}.ll')
            if src.endswith('.ll'):
                open(ll_all, 'w').write(open(src).read())
            else:
                run('clang-20', '-target', 'x86_64-unknown-linux', '-O2', '-ffreestanding', '-fno-builtin', '-fno-vectorize', '-fno-slp-vectorize',
                    '-fno-unroll-loops', '-emit-llvm', '-S', '-I', os.path.dirname(os.path.abspath(src)), src, '-o', ll_all)
            fcs, entries = [], []
            for line in open(spec):
                line = line.split('#')[0].split()
                if not line:
                    continue
                if line[0] == 'fc':  # fc <global> <type> <name> <index>: a Metal function constant
                    fcs.append((line[1], line[2], line[3], line[4]))
                else:
                    entries.append(line)
            for line in entries:
                name, kind, params = line[0], line[1], line[2:]
                funcs.append((name, TYPES[kind], build_function(ll_all, name, kind, params, work, fcs)))
    open(out, 'wb').write(pack(funcs))


main()
