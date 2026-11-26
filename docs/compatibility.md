# Compatibility

Scion is young. It runs the programs below, and its libraries implement the APIs those programs (and the test suite)
use. Most other macOS apps will stop somewhere, usually at an Objective-C method or a C function Scion does not have yet.
That is expected, and it is the best way to contribute: each missing piece added makes the next app more likely to run.

## Known to work

Checked by the test suite (`tests/cases.txt`), on Windows and under Wine, for both architectures unless noted.

| Program | Kind | What is checked |
|---|---|---|
| [esbuild](https://esbuild.github.io/) 0.28.2 | Go, command line | `--version`, bundling a TypeScript project |
| [Biome](https://biomejs.dev/) 2.6.2 | Rust, command line | `--version`, formatting a file |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) 0.64.5 | Swift (built by Apple's toolchain), universal | linting clean and dirty files |
| [class-dump](https://github.com/nygard/class-dump) 3.5 | Objective-C + Foundation, arm64 | dumping an Objective-C binary |
| [Hex Fiend](https://hexfiend.com/) 2.18.1 | AppKit, document-based | opens a file in a document window |
| [Itsycal](https://www.mowglii.com/itsycal/) 0.15.15 | AppKit, menu bar | status icon, its calendar popover, images from `Assets.car` |
| [Reminders MenuBar](https://github.com/DamascenoRafael/reminders-menubar) 2.2.0 | SwiftUI, menu bar | status icon and its SwiftUI popover |

If you get another app running, please add it here (and, if it can be fetched from an official release, to
`tests/apps/fetch.sh` and `tests/cases.txt`).

## What is there

- **Binaries:** Mach-O x86_64 and arm64, thin or universal; classic binds and chained fixups; `@rpath` frameworks
  inside bundles; thread-local variables; Objective-C, Swift, C++, Go and Rust programs.
- **System:** files and directories, memory (`mmap`, `mprotect`, `mach_vm_*`, `vm_remap`), threads, locks, condition
  variables, Mach thread control, signals (with `sigaltstack`), GCD (queues, groups, semaphores, sources), clocks,
  `sysctl` basics.
- **Networking:** BSD sockets (TCP and UDP, IPv4 and IPv6, Unix-domain on Linux), name resolution (`getaddrinfo`),
  non-blocking I/O with `poll`, `select`, kqueue (read, write and user events) and GCD read and write sources. HTTP
  and HTTPS with `URLSession` (data, upload and download tasks, completion handlers or a delegate), `NSURLConnection`
  and `NSData`/`NSString` URL loading, on the host's HTTP stack (WinHTTP on Windows, libcurl on Linux): its proxies,
  certificates and compression. Cookies (`NSHTTPCookieStorage`, kept between runs), redirects with the redirect
  delegate, and HTTP Basic authentication answered by the task's delegate or `NSURLCredentialStorage`.
- **Child processes:** `posix_spawn` (file actions, working directory, environment), `waitpid`, `kill`, `system`,
  `popen` and `NSTask` / Swift's `Process` (pipes, termination handler, readability handlers). A macOS program runs in
  a new scion; anything else runs natively: on Linux any program, on Windows an `.exe`, where `/usr/bin/<name>` and
  the like find `<name>.exe` on the `PATH` and `/bin/sh -c` falls back to `cmd.exe` when there is no `sh.exe`.
  `exec*` run the new program as a child and end with its status.
- **Foundation:** most of the everyday API: strings (Unicode), collections, run loops and timers, notifications,
  operation queues, JSON, property lists, keyed archiving, regular expressions, dates and calendars (Gregorian; time
  zones with fixed offsets), URLs and file management, user defaults, bundles and localized strings, KVO,
  NSInvocation and forwarding, undo.
- **AppKit:** windows, views, controls (buttons, switches, sliders, segmented controls, text fields and an
  `NSTextView` with styled text, selection and clicking), menus and key equivalents, context menus, file dialogs, Auto Layout, stack views, view-based table views,
  status items and popovers, documents, compiled nibs, asset catalogs, images (PNG, JPEG, ICNS and more through WIC),
  CoreGraphics drawing, `MTKView`, `CVDisplayLink`.
- **Text:** attributed strings with runs of attributes (`NSAttributedString`, `CFAttributedString`), drawn and measured
  with their fonts, colors, underlines, backgrounds and paragraph styles (alignment, indents, spacing, line heights,
  wrapping and truncation). CoreText: fonts and descriptors, lines, runs, typesetters, framesetters and frames, and
  font files an app registers (`CTFontManagerRegisterFontsForURL`, `ATSApplicationFontsPath`). Fonts are the host's:
  a family the system has is used by its name, others get a look-alike.
- **Metal:** devices, queues, command buffers, compute and render pipelines, buffers, textures, samplers, depth/stencil,
  blits, argument buffers, function constants, indirect commands, heaps and fences, timestamps, visibility results,
  `CAMetalLayer`, parts of Metal 4 (`MTL4*`), MetalFX upscalers; shaders from `.metallib` files and from MSL source.
- **Swift:** the runtime and standard library (6.1), Concurrency, the Darwin/ObjectiveC/Dispatch/CoreFoundation/
  CoreGraphics/Foundation overlays, Combine, and a SwiftUI that covers common views, stacks, lists, state and
  bindings, presentations, `MenuBarExtra` and `Settings`. Scion answers availability checks as macOS 14.6.
- **Input and sound:** keyboard, mouse, XInput controllers with rumble (GameController, CoreHaptics), raw input
  (`GCKeyboard`, `GCMouse`), audio output (AudioUnit, AudioQueue).

## Not there yet

These are the big gaps. Each is a good project for a contributor (see [roadmap.md](roadmap.md)).

- **Networking above sockets:** no `CFNetwork` or `Network.framework`; `URLSession` has no URL cache, Digest/NTLM
  authentication or server-trust challenges, WebSocket or background sessions, and no Swift `async` methods;
  credentials are not kept in a keychain. On Windows, GCD read and write sources fire for sockets only (a pipe or a
  file counts as always ready).
- **Child processes:** no `fork`. On Windows a child gets descriptors 0-2 only, `kill` ends it without running its
  handlers, and processes cannot be stopped (`SIGSTOP`).
- **Text and fonts:** each run is drawn by the host's text renderer (GDI on Windows, FreeType on Linux), so there are no
  glyph outlines (`CTFontCreatePathForGlyph`), font features or vertical text, and lines are laid out left to right
  (no bidirectional reordering). A glyph is its character. No input methods, spell checking or undo in text views.
- **Graphics:** no OpenGL, no CoreAnimation beyond what Metal presentation needs, no CoreImage.
- **Media:** no AVFoundation, video or audio input.
- **Services:** no iCloud, Keychain (Security), StoreKit, notifications, XPC services or login items.
- **Metal:** no ray tracing, mesh shaders or tile shaders; desktop GPUs are not tile-based, so imageblocks and
  programmable blending need emulation that does not exist yet.
- **Performance:** arm64 code is translated as it runs, so the first run of an arm64 program is the slowest; later runs
  reuse the translations kept on disk. x86_64 programs run natively and are faster: prefer the x86_64 half of a
  universal binary.
- **Code signing, sandboxing and hardened runtime** are ignored.

## When an app does not start

1. **Run it from a console** with `scion.exe`, not `scionw.exe`, so you see its output. Unimplemented imports, unknown
   Objective-C messages and crashes are reported there, crashes with a backtrace.
2. **List what is missing** before running anything: `python3 tests/missing_symbols.py "Some App.app" arm64` (on
   Linux, with `llvm-nm-18`) prints the functions the app and its frameworks import that Scion's libraries do not
   export, grouped by library. Zero means dyld can bind everything.
3. **Trace:** `SCION_TRACE=1` logs loading, binding and every host call; `SCION_TRACE_MSG=1` logs the first send of
   each Objective-C selector to each class. `SCION_TOLERANT=1` turns unknown Objective-C messages into a log line and a
   zero result instead of an exception, to see how far the app gets.
4. **Metal:** `SCION_METAL_INFO=1` shows the GPU and shader compilation details; `SCION_METAL_VALIDATION=1` enables the
   Vulkan validation layer (if installed).
5. **Open an issue** with the app's name and version, where to get it, the architecture you ran, and the console output.
   The [app compatibility template](../.github/ISSUE_TEMPLATE/app_compatibility.yml) asks for exactly that.

All switches are listed in [environment.md](environment.md).
