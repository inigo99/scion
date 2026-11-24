# Third-party notices

Scion's own code is under the [MIT License](LICENSE). It includes, links or downloads the third-party components below,
each under its own license. Full license texts are in [`licenses/`](licenses/).

## In this repository

| Path | Component | License |
|---|---|---|
| `sdk/darwin/` | Headers from Apple's open-source releases (Libc, xnu, libpthread, libdispatch, libmalloc, cctools, CommonCrypto, CarbonHeaders and others), plus a few small headers written for Scion (marked "scion SDK") | Apple Public Source License 2.0 ([`licenses/APSL-2.0.txt`](licenses/APSL-2.0.txt)); some files are BSD-licensed or public domain as stated in their headers; `ptrauth.h` is from LLVM (Apache-2.0 WITH LLVM-exception) |
| `sdk/include/Metal/` (files with an `SPDX-License-Identifier: MPL-2.0` header) | darling-metal, from the [Darling](https://github.com/darlinghq/darling-metal) project | Mozilla Public License 2.0 ([`licenses/MPL-2.0.txt`](licenses/MPL-2.0.txt)). These files stay under the MPL; changes to them are published here as source. |
| `sdk/libcxx-config/` | libc++ configuration files, adapted from [LLVM](https://llvm.org/) | Apache-2.0 WITH LLVM-exception ([`licenses/llvm.txt`](licenses/llvm.txt)) |
| `src/metal/air2spv/spirv.hpp11`, `src/metal/air2spv/GLSL.std.450.h` | SPIR-V headers from [Khronos](https://github.com/KhronosGroup/SPIRV-Headers) | MIT-style Khronos license (in each file) |
| `patches/` | Patches to the dependencies below | Each patch is under the license of the project it patches |

## Fetched when building (`scripts/fetch-deps.sh`)

Nothing below is stored in this repository; the build downloads it from upstream at a pinned version.

| Component | Used for | License |
|---|---|---|
| [dynarmic](https://github.com/azahar-emu/dynarmic) | arm64 → x86_64 JIT, linked into `scion.exe` | 0BSD ([`licenses/dynarmic.txt`](licenses/dynarmic.txt)) |
| [fmt](https://github.com/fmtlib/fmt), [mcl](https://github.com/azahar-emu/mcl), [robin-map](https://github.com/Tessil/robin-map), [Zycore](https://github.com/zyantific/zycore-c), [Zydis](https://github.com/zyantific/zydis) | dynarmic's dependencies, linked into `scion.exe` | MIT ([`licenses/`](licenses/)) |
| [Xbyak](https://github.com/herumi/xbyak) | dynarmic's x86 assembler, linked into `scion.exe` | BSD-3-Clause ([`licenses/xbyak.txt`](licenses/xbyak.txt)) |
| [LLVM libc++, libc++abi, libunwind](https://github.com/llvm/llvm-project) 18.1.8 | the guest C++ runtime (`lib/libc++.1.dylib`, and libunwind inside `lib/libSystem.B.dylib`) | Apache-2.0 WITH LLVM-exception ([`licenses/llvm.txt`](licenses/llvm.txt)) |
| [Indium](https://github.com/darlinghq/indium) | Metal on Vulkan, linked into `scion-metal.dll` | 0BSD ([`licenses/indium.txt`](licenses/indium.txt)) |
| [LLVM and Clang](https://github.com/llvm/llvm-project) 20.1.2 | shader translation and the MSL compiler, linked into `scion-metal.dll` and `scion-msl.dll` | Apache-2.0 WITH LLVM-exception ([`licenses/llvm.txt`](licenses/llvm.txt)) |
| [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) 1.3.296 | building `scion-metal.dll` | Apache-2.0 OR MIT |
| [Swift](https://github.com/swiftlang/swift) 6.1.3 and 5.4.3 (SDK overlays) | the Swift runtime, standard library, Concurrency and overlays in `lib/libswift*.dylib` | Apache-2.0 with the Runtime Library Exception ([`licenses/swift.txt`](licenses/swift.txt)) |

## Linked from the toolchain

| Component | Where | License |
|---|---|---|
| MinGW-w64 runtime, libstdc++ and libgcc | linked statically into `scion.exe`, `scionw.exe` and the DLLs | GPL-3.0 with the GCC Runtime Library Exception ([`licenses/gcc-runtime-exception.txt`](licenses/gcc-runtime-exception.txt)), which allows distributing the result under any license; winpthreads under MIT ([`licenses/winpthreads.txt`](licenses/winpthreads.txt)); the MinGW-w64 CRT is public domain or permissively licensed |

## Downloaded only to run the tests

These are never part of Scion or its releases; the test scripts fetch them from their official sources.

| Component | License |
|---|---|
| Sample `.metallib` shaders from Indium's `test/` folder (Apple sample code) | MIT (Apple Inc.) |
| [class-dump](https://github.com/nygard/class-dump) 3.5 | GPL-2.0 |
| esbuild, Biome, SwiftFormat, Itsycal, Reminders MenuBar, Hex Fiend (`tests/apps/fetch.sh`) | MIT; MIT or Apache-2.0; MIT; MIT; GPL-3.0; BSD-2-Clause |

## Trademarks

Apple, macOS, Metal, Swift, SwiftUI, AppKit, Xcode and Apple Silicon are trademarks of Apple Inc. Vulkan and SPIR-V are
trademarks of the Khronos Group Inc. Windows is a trademark of Microsoft Corporation. Scion is not affiliated with or
endorsed by any of them.
