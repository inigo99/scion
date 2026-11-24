#!/bin/sh
# Downloads the third-party macOS programs the optional tests run (tests/cases.txt) into out/tests/apps, from their
# official releases. None of them is part of Scion or redistributed with it: each keeps its own license.
# Needs curl, tar and unzip (on Windows, Git Bash has them); Hex Fiend ships as a .dmg, which needs 7z.
set -e
cd "$(dirname "$0")/../.."
A=out/tests/apps; mkdir -p $A; cd $A
get() { [ -f "$2" ] || curl -fL --retry 3 -o "$2" "$1"; }
npm_bin() {  # npm_bin PACKAGE VERSION FILE-IN-PACKAGE OUT
  get "https://registry.npmjs.org/$1/-/$(basename $1)-$2.tgz" pkg.tgz
  tar xzf pkg.tgz "package/$3" && mv "package/$3" "$4" && rm -rf package pkg.tgz && chmod +x "$4"
}
[ -f esbuild_x64 ] || npm_bin @esbuild/darwin-x64 0.28.2 bin/esbuild esbuild_x64        # MIT
[ -f esbuild_arm64 ] || npm_bin @esbuild/darwin-arm64 0.28.2 bin/esbuild esbuild_arm64  # MIT
[ -f biome_x64 ] || npm_bin @biomejs/cli-darwin-x64 2.6.2 biome biome_x64               # MIT or Apache-2.0
[ -f biome_arm64 ] || npm_bin @biomejs/cli-darwin-arm64 2.6.2 biome biome_arm64         # MIT or Apache-2.0
# SwiftFormat 0.64.5 (MIT): a universal binary built by Apple's toolchain
[ -f swiftformat ] || { get https://github.com/nicklockwood/SwiftFormat/releases/download/0.64.5/swiftformat.zip sf.zip && unzip -oq sf.zip swiftformat && rm sf.zip; }
# Itsycal 0.15.15 (MIT): menu bar calendar, Objective-C
[ -d Itsycal.app ] || { get https://itsycal.s3.amazonaws.com/Itsycal-0.15.15.zip itsycal.zip && unzip -oq itsycal.zip && rm -rf itsycal.zip __MACOSX; }
# Reminders MenuBar 2.2.0 (GPL-3.0): SwiftUI menu bar app
[ -d "Reminders MenuBar.app" ] || { get https://github.com/DamascenoRafael/reminders-menubar/releases/download/v2.2.0/reminders-menubar.zip rm.zip && unzip -oq rm.zip && rm -rf rm.zip __MACOSX; }
# Hex Fiend 2.18.1 (BSD-2-Clause): document-based AppKit app
if [ ! -d "Hex Fiend.app" ]; then
  get https://github.com/HexFiend/HexFiend/releases/download/v2.18.1/Hex_Fiend_2.18.1.dmg hexfiend.dmg
  if command -v 7z >/dev/null; then 7z x -y -ohf hexfiend.dmg >/dev/null && mv "$(find hf -maxdepth 3 -name 'Hex Fiend.app' -type d | head -1)" . && rm -rf hf hexfiend.dmg
  else echo "note: 7z is missing: open hexfiend.dmg and copy 'Hex Fiend.app' into $A by hand"; fi
fi
echo "third-party test apps in $A"
