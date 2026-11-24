# Building Scion

Scion is cross-compiled on **Linux** (Ubuntu 24.04 is what the scripts are written for; other distributions work with
the same packages). Windows-only developers can use WSL2. The build never needs a Mac, Xcode or an Apple SDK: the guest
libraries are compiled with clang against the headers in `sdk/`.

There are three layers, from quick to slow:

| Layer | What it produces | Time | Needs |
|---|---|---|---|
| **Core** | `scion.exe`, `scionw.exe`, the C/Objective-C libraries in `bin/lib` | minutes | clang, lld, MinGW-w64, dynarmic |
| **Metal host** | `scion-metal.dll`, `scion-msl.dll` | hours (once) | LLVM/Clang 20 built for MinGW |
| **Swift** | `libswiftCore` and friends, Combine, SwiftUI in `bin/lib` | an hour or more | a Swift 6.1.3 toolchain for Linux |

Most changes only touch the core. If you work on the core, you can take `scion-metal.dll`, `scion-msl.dll` and the
Swift libraries from a release and drop them into `bin/`.

## 1. Packages

```sh
sudo apt install clang-18 lld-18 llvm-18 clang-20 llvm-20 mingw-w64 cmake ninja-build git python3 libboost-dev
# to run the tests (docs/testing.md); golang is optional
sudo apt install wine64 xvfb mesa-vulkan-drivers golang
```

`clang` and `clang++` must be clang 18 or newer. The scripts call versioned LLVM tools (`ld64.lld-18`, `llvm-lipo-18`,
`llvm-ar-18`, and `clang-20` for the Swift and test-shader parts), which is why both LLVM versions are listed.

## 2. Dependencies

```sh
scripts/fetch-deps.sh          # dynarmic, LLVM's libc++/libc++abi/libunwind, Indium -> deps/
scripts/build-dynarmic.sh      # dynarmic for Windows x64 -> deps/dynarmic/build-win
```

Every dependency is cloned from its upstream repository at a pinned revision, and Scion's patches (`patches/`) are
applied. Set `DEPS` to keep them somewhere else (all scripts honor it).

## 3. Core

```sh
src/build.sh                   # -> bin/scion.exe, bin/scionw.exe, bin/lib/*.dylib
```

This compiles the host with MinGW-w64 (static, no runtime DLLs to ship) and each guest library twice, for
`x86_64-apple-macos11` and `arm64-apple-macos11`, then links them into universal dylibs with `ld64.lld`.

## 4. Metal host (optional)

```sh
scripts/fetch-deps.sh --all    # also LLVM 20.1.2, Vulkan headers, Swift sources
scripts/build-llvm-mingw.sh    # static LLVM + Clang 20 for MinGW -> deps/llvm20/build-win (slow)
src/build_metal.sh             # -> bin/scion-metal.dll, bin/scion-msl.dll
```

## 5. Swift (optional)

The Swift runtime is built from Apple's open-source Swift 6.1.3 with Swift's own compiler, targeting macOS 14 and
linking against Scion's libraries.

1. Download the Swift 6.1.3 toolchain for your Linux distribution from [swift.org](https://www.swift.org/install/linux/)
   and unpack it. Set `SWIFT_TC` to its `usr` folder, e.g. `export SWIFT_TC=$HOME/swift-6.1.3-RELEASE-ubuntu24.04/usr`.
2. `scripts/fetch-deps.sh --all` (the Swift sources).
3. Build, in this order:

```sh
src/build_swift.sh             # libswiftCore -> out/swift/<arch>, bin/lib
src/build_swift_overlays.sh    # Darwin, ObjectiveC, Dispatch, CoreFoundation, CoreGraphics, Foundation overlays
src/build_swift_concurrency.sh # _Concurrency
src/build_swiftui.sh           # Scion's Combine and SwiftUI
```

Intermediate files go to `out/swift-build`.

> **Note.** The Metal-host and Swift scripts were moved to this layout when the project was published and have not yet
> been run end to end on a clean machine with it. If a step fails, please open an issue with the log; a CI job that
> builds every layer is one of the most useful contributions right now.

## Release layout

A release zip is just `bin/`:

```
scion.exe  scionw.exe  scion-metal.dll  scion-msl.dll
lib/       AppKit.dylib  Foundation.dylib  libSystem.B.dylib  ...  libswiftCore.dylib  SwiftUI.dylib  ...
```

plus `README.md`, `CHANGELOG.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md` and `licenses/`. `scion.exe` finds `lib/` next to
itself. `scripts/package.sh 0.1.0` builds `out/scion-0.1.0-windows-x64.zip` from `bin/`.
