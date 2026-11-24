# Roadmap

Scion's goal is simple to state: a macOS app should run on Windows the way a Windows app runs on Linux with Wine.
Getting there is a long road, walked one app at a time. This page says where the project stands and what would move it
furthest.

## How it got here

| Milestone | What it proved |
|---|---|
| Mach-O on Windows | A macOS binary (x86_64 natively, arm64 through dynarmic) loads, links and runs inside a Windows process. |
| Command-line programs | Real Go (esbuild) and Rust (Biome) tools run, for both architectures. |
| Runtime | Signals, Mach memory and threads, multi-image dyld, Blocks and GCD, an Objective-C runtime and Foundation of Scion's own. |
| Full arm64 | C++ with exceptions, Objective-C exceptions, guest JITs, `vm_remap`; class-dump runs as an arm64-only app. |
| Metal | Compute and rendering on Vulkan; a translator for modern AIR; MSL compiled at run time; windows with `CAMetalLayer`. |
| GUI | AppKit windows, drawing, controls, menus, keyboard and mouse, controllers with rumble, audio. |
| Metal 4 | Enough of the `MTL4*` API, bindless argument buffers and imported memory for a real game engine's graphics tests. |
| Swift | The Swift runtime and overlays; SwiftFormat (built by Apple) runs; Hex Fiend and Itsycal run. |
| Concurrency and SwiftUI | Swift Concurrency; Scion's own Combine and SwiftUI with the ABI of Apple's, enough for Reminders MenuBar. |
| Open source | Renamed Scion, MIT-licensed, English documentation, a reproducible build and test suite. |

## Next

These are the areas where work has the most effect. Each is self-contained enough for one contributor to own.

**Make it easy to work on**
- CI that builds every layer (core, Metal host, Swift) and runs the suite on each pull request, and publishes releases.
- A cache for translated arm64 code, so arm64 apps start fast on the second run.

**Linux**
- A native Linux host (no Wine): the host-call table on POSIX, windows and input on Wayland/X11 (SDL), audio on
  PipeWire, `scion-metal` as a shared library, `.desktop` integration. Command-line programs first.

**Run more apps**
- Networking: BSD sockets on Winsock, then `URLSession` (most apps need it, even if only for update checks).
- Child processes: `posix_spawn` and `NSTask` on `CreateProcess`.
- Text: CoreText on DirectWrite, rich text in `NSTextView`, input methods.
- CoreAnimation layers beyond Metal presentation; CoreImage basics.
- AVFoundation playback; audio input.
- More of SwiftUI (navigation, grids, animations, more modifiers).

**Graphics**
- Metal ray tracing (`VK_KHR_ray_tracing_pipeline`), mesh shaders (`VK_EXT_mesh_shader`), `simdgroup_matrix` on
  cooperative matrices.
- Tile shaders and programmable blending emulated on desktop GPUs.
- A Direct3D 12 back end, for machines whose Vulkan drivers are poor.

**Developers**
- `xcodebuild`-compatible builds with Apple's open-source Swift Build, so Xcode projects build on Windows.

## Proposing something

Open an issue describing the app or the API, what you plan to do, and how you will test it. Larger changes (a new
framework, a new host back end) are best discussed before the code is written.
