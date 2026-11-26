# Testing

Scion's regression suite is a set of small macOS programs, each checking one area and printing a known line when
everything passed (`CXX OK`, `METAL CUBE OK`, `APPKIT OK`...). They are compiled on Linux, without Apple's tools, and run
through `scion.exe`, either under Wine on Linux or on Windows.

```sh
tests/build.sh        # build the test programs -> out/tests
tests/run.sh          # run them under Wine          (Linux)
tests/run.ps1         # run them natively            (Windows: powershell -ExecutionPolicy Bypass -File tests\run.ps1)
tests/run.sh Metal    # only the tests whose name contains "Metal"
SCION=$PWD/bin/scion tests/run.sh   # the native Linux host, no Wine (#10; see the skip list in .github/workflows/ci.yml)
tests/fuzz/run.sh 60  # fuzz the readers of files that come with an app, 60 s each (see below)
```

`tests/build.sh` and `tests/run.sh` work in parallel, `JOBS` at a time (the number of CPUs by default); `run.sh` reports
in the order of the list, and runs `scion install` / `scion uninstall` last, one after the other.

Both runners read the same list, [`tests/cases.txt`](../tests/cases.txt): one test per line with its name, the output it
must contain, optional environment variables, and the program with its arguments. `{arch}` runs a line for x86_64 and
for arm64. A test whose program is missing is reported as skipped, so the optional parts below never fail the run.

## What the suite covers

| Area | Tests (in `tests/`) |
|---|---|
| Loader and libSystem | `c/hello.c` (classic binds and chained fixups), `c/dylib` (`@rpath`, a TLV), `c/mach_signals.c`, `c/gcd.c`, `gcd/sources.c`, `c/jit.c` (generated code), `c/remap.c` (`mach_vm_remap`), `go/signals` (Go's signals and asynchronous preemption) |
| C++ | `cpp/cxx.cpp` (exceptions, STL, iostream, threads, regex, filesystem), `cpp/threads.cpp` |
| Objective-C and Foundation | `objc/runtime.m` (no Foundation), `objc/exceptions.m`, `objc/foundation.m`, `objc/foundation2.m`, `objc/regex.m` (cases checked against Python's `re`), `objc/invocations.m` |
| Metal | `metal/compute.m`, `triangle.m`, `cube.m`, `texture.m` (Apple-compiled sample shaders from Indium's test folder), `ng.m` (modern AIR made by `metal/air/mkmetallib.py`), `msl.m` (MSL compiled at run time), `window.m` (`CAMetalLayer`), `metalfx.m` |
| AppKit and input | `appkit/appkit.m`, `dialogs.m`, `drawing.m`, `autolayout.m`, `objc/autolayout.m`, `objc/table_views.m`, `objc/status_item.m`, `gamepad/gamepad.m`, `gamepad/keyboard.m`, `audio/audio.c` |
| Swift | `swift/*.swift`: the language, Concurrency, Combine, SwiftUI (`swiftui.swift`; `navigation.swift`: navigation, grids; `animation.swift`: animations and transitions on a stopped clock), the Darwin/Dispatch/Foundation overlays, property lists and bundles (`Sample.app`). `swift/abi.sh` checks that SwiftUI exports Apple's mangled names for the APIs listed in `swift/swiftui-abi.txt`. |
| Desktop integration | `scion install` / `scion uninstall` of a small app bundle (Start menu on Windows, freedesktop.org on Linux) |
| Real programs | class-dump (built from source), and the third-party apps below |

Windows have no user to click them: tests inject input through host hooks (`UI_INJECT`, `UI_PAD_INJECT`,
`UI_RAW_INJECT`), and `SCION_TEST_GUI` / `SCION_TEST_CLICK` make any GUI app report its windows, documents and status
icons after a few seconds and quit. That is how the third-party apps are checked.

## Optional parts

| Part | Needs | Notes |
|---|---|---|
| Go test | `go` | cross-compiled for `GOOS=darwin` |
| Swift tests | `SWIFT_TC` and Scion's Swift build (`out/swift`) | see [building.md](building.md). On GitHub, `.github/workflows/swift.yml` builds Combine and SwiftUI and runs these tests (native host and Wine) whenever Swift code changes, with the Swift runtime and overlays cached between runs. |
| class-dump | `git` and network | GPLv2, cloned and built in a temporary folder by `tests/apps/class-dump.sh`; not part of Scion |
| Metal sample shaders | `deps/indium` (`scripts/fetch-deps.sh`) | Apple's sample `.metallib` files from Indium's tests, copied at build time |
| Third-party apps | `tests/apps/fetch.sh` (curl, tar, unzip; 7z for Hex Fiend's `.dmg`) | esbuild 0.28.2, Biome 2.6.2, SwiftFormat 0.64.5, Itsycal 0.15.15, Reminders MenuBar 2.2.0, Hex Fiend 2.18.1, downloaded from their official releases into `out/tests/apps`. None of them is redistributed by Scion. |

## Running under Wine

`tests/run.sh` needs Wine (64-bit), a display and Vulkan:

- With no `DISPLAY`, it starts `Xvfb :88`. Wine's null display driver gives windows no size, so the window tests need a
  real (or virtual) X server.
- Mesa's **lavapipe** (`mesa-vulkan-drivers`) provides Vulkan on the CPU, so the Metal tests run without a GPU, slowly.
- The runner restarts `wineserver` first: one started without a display hides the GPU from Vulkan.
- If Wine aborts with `free(): invalid pointer` in a container, create its runtime directory (`mkdir -p /run/user/$(id -u)`).

## Fuzzing

`tests/fuzz/run.sh [SECONDS]` builds libFuzzer targets (clang 18 with `libclang-rt-18-dev`; ASan and UBSan) for the code
that reads files an app brings with it, and runs each for the given time (60 s by default), seeded from `out/tests`:

| Target | Reads |
|---|---|
| `fuzz_macho.cpp` | the Mach-O loader (`src/dyld.cpp`): universal files, load commands, segments and sections, the export trie, rebase and bind opcodes, chained fixups |
| `fuzz_bundle.cpp` | `Info.plist` (XML and binary) and `.icns`, read by `scion install` (`src/bundle.h`) |
| `fuzz_lzfse.cpp` | the LZFSE decoder of compiled asset catalogs (`src/appkit/lzfse.m`) |

Findings stay in `out/fuzz/<target>/` (`crash-*`, `timeout-*`, `oom-*`); `out/fuzz/<target>/fuzz FILE` replays one. CI
fuzzes for 1 minute per target. The Foundation readers (property lists, JSON, keyed archives) run inside the guest and
are not fuzzed this way.

## Writing a test

1. Add a small program under `tests/<area>/` that checks what you implemented and prints `<NAME> OK` when every check
   passes (and the failing checks otherwise). Look at an existing test of the same area for the `CHECK` macro.
2. Build it in `tests/build.sh` (usually one `prog` line) and add a line to `tests/cases.txt`.
3. Run it for both architectures before sending the change.

Tests should not depend on timing more than necessary, on the network, or on files outside `out/tests`.
