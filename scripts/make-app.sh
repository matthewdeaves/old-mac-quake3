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
# directory CONTAINING the .app. So ~/Desktop/quake3/ioquake3.app finds the user's
# baseq3 at ~/Desktop/quake3/baseq3 — that game data stays OUTSIDE the bundle.
#
# The ONLY files we put inside the bundle's baseq3 are our own native game dylibs
# (Contents/MacOS/baseq3/{cgame,qagame,ui}{ppc,x86_64}.dylib). On macOS that path
# is fs_apppath/baseq3 (files.c #ifdef MACOS_X), a search dir FS_FindVM scans
# before the user's pak8.pk3 QVM, so with vm_cgame/game/ui 0 (arch autoexec cfgs)
# the engine loads these native modules instead of JIT-compiling the QVM. dyld
# picks the arch slice; it falls back to the QVM if a dylib is absent/wrong-arch or
# on a pure server. Built by scripts/build-gamedylibs.sh. We never touch the user's
# baseq3.
#
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
FAT="$PROJ/build/ioquake3-fat"
SDL="$PROJ/code/libs/macosx/libSDL-1.2.0.dylib"
ICNS="$PROJ/MacOSX/ioquake3.icns"
PLIST="$PROJ/scripts/bundle/Info.plist"
GAMEDYLIBS="$PROJ/build/gamedylibs"
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

# Per-arch + per-machine auto-config: the engine (Com_AutoConfigForMachine in
# code/qcommon/common.c) reads these from the bundle Resources at startup via
# CFBundle, keyed on hw.model, so ONE universal .app self-tunes on every fleet
# machine. Mirrors the QuakeSpasm / Quake II ports.
CFGN=0
for cfg in "$PROJ"/scripts/bundle/autoexec-*.cfg; do
  [ -f "$cfg" ] || continue
  cp "$cfg" "$APP/Contents/Resources/$(basename "$cfg")"
  CFGN=$((CFGN+1))
done
echo "==> bundled $CFGN auto-config cfg(s) into Resources/"

# Native game dylibs (fat ppc750+ppc7400 + x86_64), loaded from fs_apppath/baseq3
# when the arch autoexec sets vm_cgame/game/ui 0 (see header + build-gamedylibs.sh).
# Required for the shipping build; run scripts/build-gamedylibs.sh if missing.
DYN=0
if [ -d "$GAMEDYLIBS" ]; then
  mkdir -p "$APP/Contents/MacOS/baseq3"
  for dyl in "$GAMEDYLIBS"/{cgame,qagame,ui}{ppc,x86_64}.dylib; do
    test -f "$dyl" || { echo "make-app: missing $dyl — run scripts/build-gamedylibs.sh"; exit 1; }
    cp "$dyl" "$APP/Contents/MacOS/baseq3/$(basename "$dyl")"
    DYN=$((DYN+1))
  done
  echo "==> bundled $DYN native game dylib(s) into Contents/MacOS/baseq3/"
else
  echo "make-app: missing $GAMEDYLIBS — run scripts/build-gamedylibs.sh first"; exit 1
fi

echo "==> assembled $APP"
find "$APP" -type f | sed "s#$APP/##;s/^/    /"
