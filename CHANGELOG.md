# Changelog

## Unreleased

- Fixed: NSTableView column rectangles read `-width` through the wrong method signature (garbage column widths).
- Fixed: `-tableView:isGroupRow:` delegate answers could be misread; `+[NSString pathWithComponents:]` was missing
  (`+[NSURL fileURLWithPathComponents:]` raised).
- The core build is free of compiler warnings; `src/foundation/swift.m` is split into `calendar.m` and `url.m`.
- CI: a Windows test job, a manual heavy build (Metal host and Swift) and a release workflow on `v*` tags.

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
