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
| CI and releases | Every pull request is built and tested on Wine, the Linux host and Windows, with the file readers fuzzed; `v*` tags publish releases. |
| Linux | A native Linux host (no Wine): command-line programs, AppKit and SwiftUI apps and Metal, x86_64 and arm64. |
| Fast arm64 | dynarmic compiles twice as fast; threads share translated code, and it is kept on disk, so an arm64 app starts about twice as fast from its second run. |

## Next

These are the areas where work has the most effect. Each is self-contained enough for one contributor to own.

**Linux** (`src/host_linux.cpp`, `src/ui_linux.cpp`)
- A menu bar, status items in the tray (StatusNotifierItem), HiDPI, a Flatpak or AppImage.

**Run more apps**
- Networking: WebSockets and a URL cache in `URLSession`; `Network.framework`; GCD sources on Windows pipes. Sockets,
  HTTP(S) `URLSession` with cookies and authentication, and GCD sources are there.
- Child processes: `fork` where it can be had (Linux); signals delivered to children's handlers on Windows.
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
