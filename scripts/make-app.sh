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
SDL2="$PROJ/code/libs/macosx/libSDL2-2.0.0.dylib"   # arm64 only; see below
ICNS="$PROJ/MacOSX/ioquake3.icns"
PLIST="$PROJ/scripts/bundle/Info.plist"
GAMEDYLIBS="$PROJ/build/gamedylibs"
APP="$PROJ/build/ioquake3.app"

for f in "$FAT" "$SDL" "$ICNS" "$PLIST"; do
  test -f "$f" || { echo "make-app: missing $f"; exit 1; }
done

# Stamp the bundle with the build identity. scripts/bundle/Info.plist carries a
# placeholder; without this the deployed .app on every machine claims the same
# version forever and a smoke test can't prove WHICH build it just ran. Override
# with Q3_PORT_VERSION when make-dmg.sh is cutting a tagged release.
Q3_PORT_VERSION="${Q3_PORT_VERSION:-$(git -C "$PROJ" describe --tags --always --dirty 2>/dev/null || echo unknown)}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PLIST" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString 1.36-oldmac-$Q3_PORT_VERSION" \
  -c "Set :CFBundleVersion $Q3_PORT_VERSION" \
  "$APP/Contents/Info.plist" >/dev/null
echo "==> stamped bundle version: 1.36-oldmac-$Q3_PORT_VERSION"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$FAT"  "$APP/Contents/MacOS/ioquake3"; chmod +x "$APP/Contents/MacOS/ioquake3"
cp "$SDL"  "$APP/Contents/MacOS/libSDL-1.2.0.dylib"   # binary refs @executable_path/libSDL-1.2.0.dylib
cp "$ICNS" "$APP/Contents/Resources/ioquake3.icns"

# The arm64 member of that fat SDL is sdl12-compat, which dlopen()s a real SDL2
# at runtime. Ship ours beside the binary so it is what gets found, rather than
# whatever SDL2 the machine happens to have. The other four slices link genuine
# SDL 1.2 and never open this file, so on PowerPC and Intel it is inert. It is
# optional for the same reason the arm64 engine slice is. docs/adr/0017.
if [ -f "$SDL2" ]; then
  cp "$SDL2" "$APP/Contents/MacOS/libSDL2-2.0.0.dylib"
  echo "==> bundled libSDL2-2.0.0.dylib ($(lipo -archs "$SDL2" 2>/dev/null || echo arm64)) for the arm64 slice"
else
  echo "==> no $SDL2: arm64 slice will find no SDL2 and fail to start"
fi

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
  # arm64 modules are OPTIONAL, exactly like the arm64 engine slice: a mini
  # cannot build them, and FS_FindVM falls back to the QVM per-module when one
  # is absent. Missing them costs Apple Silicon the interpreter, not the game.
  A64=0
  for dyl in "$GAMEDYLIBS"/{cgame,qagame,ui}arm64.dylib; do
    [ -f "$dyl" ] || continue
    cp "$dyl" "$APP/Contents/MacOS/baseq3/$(basename "$dyl")"
    DYN=$((DYN+1)); A64=$((A64+1))
  done
  echo "==> bundled $DYN native game dylib(s) into Contents/MacOS/baseq3/"
  if [ "$A64" -eq 3 ]; then
    echo "    including all three arm64 modules"
  else
    echo "    arm64 modules: $A64 of 3 (run scripts/build-gamedylibs-arm64.sh here for the rest)"
  fi
else
  echo "make-app: missing $GAMEDYLIBS — run scripts/build-gamedylibs.sh first"; exit 1
fi

echo "==> assembled $APP"
find "$APP" -type f | sed "s#$APP/##;s/^/    /"
