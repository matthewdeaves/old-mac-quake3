#!/usr/bin/env bash
#
# make-app.sh — assemble build/ioquake3.app from the fat binary + SDL 1.2 dylib
# + icon + Info.plist. ONE bundle with a fat Mach-O inside (ppc750 + ppc7400 +
# x86_64) runs on every fleet machine. Mirrors the QuakeSpasm / Quake II .app
# tooling. deploy.sh ships this and sets the Finder bundle bit (Panther/Tiger
# need kHasBundle to show the app icon instead of a plain folder — see
# scripts/bundle/set-bundle-bit.c).
#
# Data: ioquake3 on macOS derives fs_basepath via Sys_StripAppBundle(), i.e. the
# directory CONTAINING the .app. So ~/Desktop/quake3/ioquake3.app finds baseq3 at
# ~/Desktop/quake3/baseq3 — no data inside the bundle.
#
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
FAT="$PROJ/build/ioquake3-fat"
SDL="$PROJ/code/libs/macosx/libSDL-1.2.0.dylib"
ICNS="$PROJ/MacOSX/ioquake3.icns"
PLIST="$PROJ/scripts/bundle/Info.plist"
APP="$PROJ/build/ioquake3.app"

for f in "$FAT" "$SDL" "$ICNS" "$PLIST"; do
  test -f "$f" || { echo "make-app: missing $f"; exit 1; }
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PLIST" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$FAT"  "$APP/Contents/MacOS/ioquake3"; chmod +x "$APP/Contents/MacOS/ioquake3"
cp "$SDL"  "$APP/Contents/MacOS/libSDL-1.2.0.dylib"   # binary refs @executable_path/libSDL-1.2.0.dylib
cp "$ICNS" "$APP/Contents/Resources/ioquake3.icns"

echo "==> assembled $APP"
find "$APP" -type f | sed "s#$APP/##;s/^/    /"
