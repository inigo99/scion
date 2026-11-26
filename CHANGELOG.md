# Changelog

## Unreleased

- Networking: BSD sockets (TCP, UDP, IPv4 and IPv6), `getaddrinfo` and `getnameinfo`, `poll`, `select`, and kqueue
  read and write filters on both hosts (`src/net.cpp`: Winsock on Windows, the kernel's sockets on Linux), with a test.
  `fcntl(F_SETFL, O_NONBLOCK)` and `FIONBIO` work.
- Networking: `URLSession` over HTTP and HTTPS (data, upload and download tasks; completion handlers or a delegate;
  cancel and timeouts), `NSURLConnection`, and `NSData`/`NSString` loading from http(s) URLs. Requests go through the
  host's HTTP stack (`src/http.cpp`: WinHTTP on Windows, libcurl on Linux, which the Linux host now needs), so system
  proxies and certificates apply. With a test against a local server.
- The LZFSE decoder (asset catalogs) no longer reads out of bounds on damaged data: initial FSE states are checked
  and the bit reader reads only the bytes it uses (found by the fuzzer, which made CI on main fail).
- arm64 guests start and warm up about twice as fast: dynarmic compiles guest code with half the CPU time
  (`patches/dynarmic-compile-speed.patch`). A small program starts in 10 ms instead of 80; Biome, esbuild and
  SwiftFormat use 40-55 % less CPU; each guest thread also needs 16 MB less memory.
- arm64 threads share translated code: a block one thread has compiled is copied and relocated by the others instead
  of compiled again (`patches/dynarmic-code-cache.patch`; `SCION_JIT_CACHE=0` turns it off). SwiftFormat runs 17 %
  faster and esbuild uses 11 % less CPU; single-threaded programs spend a few percent more to record their blocks.
- arm64 translated code is kept on disk for the next run of the same program (`%LOCALAPPDATA%\scion\jit`,
  `~/.cache/scion/jit`, 512 MB at most, safe to delete): from the second run Biome, esbuild and SwiftFormat start
  45-55 % faster with 50-60 % less CPU, and small programs use 40 % less; the first run spends a little more to save
  it. `SCION_JIT_CACHE=nodisk` keeps it in memory only. The files are mapped rather than read, and processes of the
  same program that run at the same time add up what they save instead of overwriting it.
- Windows: dylibs linked at address 0 load at the same address on every run instead of a random one.

## 0.2.0 (2026-11-25)

- **Native Linux host (preview)**, no Wine: `scion` for Linux runs command-line programs, AppKit and SwiftUI apps and
  Metal, x86_64 and arm64, with windows, input, controllers and audio through SDL2 and Metal on Vulkan
  (`scion-metal.so`, `scion-msl.so`); `scion install` adds freedesktop.org menu entries, icons and file types. Releases
  include `scion-<version>-linux-x86_64.tar.xz`. Under Wine, Linux paths given to `scion.exe` now work.
- Fixed: NSTableView column rectangles read `-width` through the wrong method signature (garbage column widths).
- Fixed: `-tableView:isGroupRow:` delegate answers could be misread; `+[NSString pathWithComponents:]` was missing
  (`+[NSURL fileURLWithPathComponents:]` raised).
- The core build is free of compiler warnings; `src/foundation/swift.m` is split into `calendar.m` and `url.m`.
- CI: a Windows test job, a manual heavy build (Metal host and Swift) and a release workflow on `v*` tags.
- CI: actions on Node 24; test and LLVM builds without warnings.
- Faster and lighter:
  - Mach-O images are mapped from their files instead of read and copied (native Linux host): large programs start
    several times faster (Biome: 120 → 15 ms) with half the memory.
  - arm64 guests no longer copy their registers on every host call (many threads: up to 2.5× faster), and the native
    Linux host re-reads its memory map only for the regions that changed.
  - Idle apps stay idle: `CFRunLoopRun` with nothing to run sleeps instead of spinning (Hex Fiend kept a core busy), a
    modal session no longer spins on a due timer of another mode, and `dispatch_main()`, the main run loop without
    AppKit and the Linux signal pump wait instead of polling every millisecond.
- Hardened readers: the loader checks every offset and size of a Mach-O file and names what it refuses; binary property
  lists can no longer expand exponentially or read past their end (Foundation and `scion install`). New libFuzzer
  targets in `tests/fuzz`, run by CI.
- Smaller releases: stripped host binaries and `scion-msl.so` without Clang's exported symbols; the Linux archive is a
  `.tar.xz` (19 MB).
- Build and CI: `src/build.sh`, `tests/build.sh` and `tests/run.sh` work in parallel (`JOBS`; the local suite takes
  6 → 3.5 minutes on two cores), and the input tests wait for their events instead of fixed delays. CI builds once,
  then runs the Wine, native, Windows and fuzzing jobs side by side.

## 0.1.0 (2026-11-24)

First public release.

- Runs macOS programs (Mach-O, x86_64 natively and arm64 through dynarmic) on Windows 10/11 x64, and under Wine on Linux.
- Scion's own libSystem, Objective-C runtime, Foundation, AppKit, Metal (on Vulkan, with AIR → SPIR-V translation and
  run-time MSL compilation), GameController, AudioToolbox, Swift runtime and overlays, Combine and SwiftUI.
- `scion install` / `scion uninstall` integrate app bundles with the Start menu, file types and installed apps.
- Third-party apps checked by the test suite: esbuild, Biome, SwiftFormat, class-dump, Hex Fiend, Itsycal and
  Reminders MenuBar.
- Regression suite runnable under Wine (`tests/run.sh`) and on Windows (`tests/run.ps1`).

Known issues in this release:

- `scion-metal.dll`, `scion-msl.dll` and the Swift libraries (`lib/libswift*.dylib`, `Combine.dylib`, `SwiftUI.dylib`)
  were built before the project took its current name and were renamed in place, not rebuilt. A few of their internal
  diagnostic messages may still appear in Spanish, and `SCION_SWIFTUI_DUMP=1` does not work (`=2` does). Building them
  from source ([docs/building.md](docs/building.md)) fixes both.
