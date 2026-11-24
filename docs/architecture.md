# Architecture

Scion runs a macOS program inside an ordinary Windows process. There is no virtual machine and no macOS kernel: the
program's Mach-O binary is loaded into memory, linked against Scion's own implementation of the macOS libraries, and
started. Those libraries talk to Windows through one narrow interface.

```
                         ┌──────────────────────── one Windows process (scion.exe) ────────────────────────┐
 Some App.app            │                                                                                │
 Contents/MacOS/SomeApp ─┼─► dyld (src/dyld.cpp) maps it, rebases, binds, runs initializers                │
                         │                                                                                │
                         │   guest side: Mach-O code, Darwin ABI                                          │
                         │   ┌──────────────────────────────────────────────────────────────────────┐    │
                         │   │ the app                                                              │    │
                         │   │ SwiftUI · Combine · Swift overlays · libswiftCore                    │    │
                         │   │ AppKit · Metal · GameController · AudioToolbox · Foundation · CF     │    │
                         │   │ libobjc · libc++ · libSystem (libc, pthreads, GCD, Mach, signals)    │    │
                         │   └───────────────────────────────┬──────────────────────────────────────┘    │
                         │                     host calls (src/hostcalls.h)                               │
                         │   host side: Windows code       ▼                                              │
                         │   files · memory · threads · locks · clocks · signals (src/host.cpp)           │
                         │   windows · input · audio (src/ui.cpp)     arm64 JIT (src/arm64.cpp, dynarmic) │
                         │   Metal: scion-metal.dll (Indium on Vulkan, AIR → SPIR-V)                      │
                         │          scion-msl.dll (Metal Shading Language → AIR, with Clang)              │
                         └────────────────────────────────────────────────────────────────────────────────┘
```

## Two worlds

**The guest side** is everything the app can see. It is Mach-O code built from this repository with clang for
`x86_64-apple-macos11` and `arm64-apple-macos11` (universal dylibs in `bin/lib`), and it follows Apple's ABI exactly:
object layouts, calling conventions, symbol names, Objective-C metadata, Swift's runtime ABI. An app compiled by Xcode
links against these libraries as if they were Apple's, because their exports have the same names and behavior.

**The host side** is `scion.exe` (and two DLLs it loads on demand), an ordinary Windows x64 program built with MinGW.
It owns everything that needs the operating system.

The two meet in **host calls** (`src/hostcalls.h`): a table of about a hundred functions, each taking up to six integer
or pointer arguments and returning an integer (negative values are Darwin `errno`s). No floats, no structs by value, no
varargs: that keeps one generic thunk enough for both architectures. Windows, input and audio go through one of them
(`ui`, with its own small protocol in `src/uibridge.h`); Metal goes through another (`metal`, `src/metal/mtlbridge.h`).

This split is the main design rule. The guest libraries never call Windows directly, and the host never needs to know
about Objective-C, Swift or Mach-O layouts beyond loading them. A future Linux or macOS host would only have to
implement the host-call table.

## Loading a program (`src/dyld.cpp`)

`scion.exe` is a small dyld:

- reads fat (universal) and thin Mach-O files, picks the slice (x86_64 by default, `SCION_ARCH=arm64` for Apple Silicon);
- maps segments at their preferred address (`0x100000000`) or anywhere else with a slide;
- applies rebases and binds from both formats: the classic opcodes and chained fixups (the default since macOS 12);
- resolves install names: Apple's paths (`/usr/lib/libSystem.B.dylib`, `/System/Library/Frameworks/AppKit.framework/...`)
  map to Scion's libraries in `bin/lib`; `@rpath`, `@executable_path` and `@loader_path` work for an app's own
  frameworks; a framework Scion does not ship resolves to libSystem, whose stubs and a flat symbol search
  take over;
- sets up thread-local variables (TLV), registers Objective-C classes image by image (like dyld's notifications to
  libobjc) and runs initializers in dependency order, then jumps to `LC_MAIN` or `LC_UNIXTHREAD`.

## Running code

**x86_64 programs run natively.** macOS and Windows disagree on the calling convention (System V vs. Microsoft x64), so
the guest libSystem crosses into the host with `ms_abi` thunks. Darwin keeps thread-specific data behind `%gs`, which on
Windows points to the TEB and cannot be moved; the few instructions that address `%gs` directly (Go does) are rewritten
at load time to use a reserved TEB TLS slot.

**arm64 programs are translated** (`src/arm64.cpp`). [dynarmic](https://github.com/azahar-emu/dynarmic) compiles arm64
code to x86_64 as it runs, one JIT per guest thread, sharing one exclusive monitor. Host calls arrive as `svc`
instructions. Scion's libraries have arm64 slices too, so an arm64 app runs entirely under the JIT down to the host-call
table; everything past it is native. Some details that matter for real programs:

- guest addresses are host addresses, and memory accesses go straight to it ("fastmem"); a fault falls back to a
  callback that can redirect the access (that is how `mach_vm_remap` aliases work);
- self-modifying and generated code (JITs inside the guest, like the Go runtime or JavaScript engines) is supported:
  `mprotect`, `munmap` and `sys_icache_invalidate` invalidate translated blocks in every thread;
- instructions dynarmic lacks are handled by Scion: LSE atomics, LRCPC2, half-precision compares, and the pointer
  authentication instructions (no-ops, since Scion's pointers are never signed);
- x86's memory model is stronger than ARM's, so translated code needs no extra barriers.

## The guest libraries

All of them are written for Scion (clean room, see [CONTRIBUTING.md](../CONTRIBUTING.md)), in C and Objective-C, with
these exceptions built from open-source code: libc++/libc++abi/libunwind (LLVM) and Swift's runtime and overlays
(Apple's open-source Swift).

| Library | Source | Notes |
|---|---|---|
| libSystem | `src/libsystem.c`, `src/libc.c`, `src/libc_ext.c`, `src/dispatch.c`, `src/stubs.c` | libc, pthreads, Mach (ports, `vm_*`, thread state), signals (Windows exceptions become Darwin signals with `sigaltstack` and `siglongjmp`), kqueue, GCD, Blocks runtime. Missing functions are added as real programs import them, Wine-style. |
| libobjc | `src/objc/` | Objective-C 2 runtime with Apple's metadata layout: classes, categories, protocols, ARC entry points, weak references, associated objects, `@synchronized`, message forwarding, exceptions on libunwind, the hooks Swift uses. `objc_msgSend` is hand-written assembly for both architectures. |
| Foundation, CoreFoundation | `src/foundation/` | Toll-free bridged: CF objects are the Foundation objects. Strings, collections, run loops, timers, notifications, operation queues, JSON, property lists (XML, binary, OpenStep), keyed archives, NSRegularExpression, dates and calendars, URLs, file management, KVO, NSInvocation, EventKit's reminders. |
| AppKit, CoreGraphics, CoreVideo, MetalKit, QuartzCore | `src/appkit/` | Windows are Win32 windows on one host UI thread; views are composited by Scion and drawn with its own CoreGraphics (or Metal). Menus, controls, text, Auto Layout, table views, nibs (compiled `.nib` archives), asset catalogs (`Assets.car`), documents, status items, file dialogs. |
| Metal, MetalFX | `src/metal/` | Objective-C objects that wrap host handles; buffers live in host-visible Vulkan memory mapped into the same address space, so `-contents` is a plain pointer. |
| GameController, CoreHaptics | `src/gamecontroller/` | XInput controllers (with rumble), raw keyboard and mouse. |
| AudioToolbox, CoreAudio | `src/audio/` | Output AudioUnits and AudioQueues on WASAPI. |
| Combine, SwiftUI | `src/swift/` | Written in Swift against the ABI of Apple's binaries, so apps built with Xcode link against them. SwiftUI resolves views into a node tree and lays it out with SwiftUI's propose/choose/place rule on AppKit views. |

## Metal

Metal apps ship their shaders precompiled as `.metallib` files: Apple's AIR, which is LLVM bitcode with `air.*`
intrinsics and metadata. Some also compile Metal Shading Language source at run time.

- **API** (`src/metal/Metal.m` on the guest, `src/metal/host_metal.cpp` on the host): Metal objects map onto
  [Indium](https://github.com/darlinghq/indium), a Metal-like layer on Vulkan, patched for Scion (`patches/indium-scion.patch`):
  bindless resources for argument buffers, imported host memory for `newBufferWithBytesNoCopy`, Metal 4 command
  allocators and argument tables, timestamps, visibility results, swapchains on Win32 windows, thread-safe queues.
- **AIR → SPIR-V** (`src/metal/air2spv/`): a translator written for Scion that reads modern AIR (opaque pointers, LLVM 17+
  bitcode from current Xcode) as well as older typed-pointer AIR, and emits SPIR-V for Vulkan 1.3: control-flow
  structurization, SIMD-group operations, `simdgroup_matrix`, function constants, threadgroup memory, atomics, textures
  and samplers.
- **MSL → AIR** (`src/metal/msl/`): `newLibraryWithSource:` compiles MSL with Clang 20 (patched lightly in
  `patches/clang-msl.patch`) plus a Metal standard library header written for Scion, and emits the same AIR a metallib
  holds, which then goes through the translator. Results are cached on disk.

`scion-metal.dll` and `scion-msl.dll` link LLVM statically, which is why they are large; they are loaded only when a
program first uses Metal or compiles MSL.

## Windows integration

- `scion install App.app` reads the bundle's `Info.plist`, converts its `.icns` icon, creates a Start menu shortcut that
  runs it with `scionw.exe` (no console window), registers its document types for "Open with", and adds an entry to
  Windows' installed apps whose uninstaller is `scion uninstall` (`src/install.cpp`). Under Wine, Wine turns these into
  `.desktop` files and MIME types, so Linux desktops get the same.
- Guest paths: `/c/Users/...` is `C:\Users\...`; other absolute paths live under `%LOCALAPPDATA%\scion\root`
  (so `/tmp`, `/Library/...` and friends exist); `HOME` is the Windows user profile.

## Repository layout

```
src/            Scion itself: host (*.cpp) and guest libraries (subfolders, libsystem.c, dispatch.c, ...)
  build*.sh     build scripts (docs/building.md)
sdk/            headers the guest code is compiled against (no Apple SDK needed)
  darwin/       a minimal Darwin sysroot from Apple's open-source releases (APSL and other open licenses)
  include/      Scion's own headers for the frameworks it implements
  libcxx-config/ libc++ configuration for an Apple-compatible ABI
compat/win/     small shims for building third-party code with MinGW
patches/        patches applied to dependencies by scripts/fetch-deps.sh
scripts/        dependency fetching and helper builds
tests/          the regression suite (docs/testing.md)
docs/           this documentation
```
