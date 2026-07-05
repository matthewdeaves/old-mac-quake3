#!/usr/bin/env bash
#
# build-gamedylibs.sh — build the three game modules (cgame, qagame, ui) as
# NATIVE dylibs for all three arches and lipo the PPC pair, producing six files
# in build/gamedylibs/:
#
#   cgameppc.dylib  qagameppc.dylib  uippc.dylib       (fat ppc750 + ppc7400)
#   cgamex86_64.dylib  qagamex86_64.dylib  uix86_64.dylib
#
# WHY: the stock ppc build already JIT-compiles the QVM bytecode to native PPC
# (vm_powerpc.c, vm_cgame/game/ui default "2"=VMI_COMPILED), so this is NOT an
# "interpreter -> native" win — it's a real-compiler-over-JIT + dropped-QVM-
# sandbox-masking win, measured at +1.3% fps on quicksilver (see docs/PROFILING.md).
#
# make-app.sh drops these into ioquake3.app/Contents/MacOS/baseq3/. On macOS that
# path is fs_apppath/baseq3 (files.c #ifdef MACOS_X), a search dir that FS_FindVM
# scans BEFORE the user's pak8.pk3 QVM — so with vm_cgame/game/ui 0 (set in the
# arch autoexec cfgs) the engine loads these instead of JIT-compiling the QVM.
# dyld selects the arch slice from the fat dylib; FS_FindVM auto-falls-back to the
# QVM if a dylib is missing, wrong-arch, or the client is on a pure server
# (!fs_numServerPaks). So the single fat .app self-selects and degrades safely.
#
# Mirrors build-fat.sh: per-slice flags match build.sh; lipo runs on mini-intel
# (no lipo on Linux); ppc cpusubtypes are re-stamped (ppc750=9, ppc7400=10) before
# lipo so a G3 loads the no-AltiVec slice and a G4 the AltiVec one.
#
set -euo pipefail

BUILD_HOST="${BUILD_HOST:-mini-intel}"
PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
PROJ_REMOTE="quake3"
LOCK="$PROJ_LOCAL/build/.build.lock"
OUT="$PROJ_LOCAL/build/gamedylibs"
MODS="cgame qagame ui"

mkdir -p "$OUT"
exec 9>"$LOCK"
flock -w 900 9 || { echo "build-gamedylibs: lock timeout"; exit 1; }

rsync_tree() {
  rsync -az --delete --exclude='.git' --exclude='build/' --exclude='benchmarks/' \
    --exclude='.venv/' --exclude='*.o' --exclude='*.d' "$PROJ_LOCAL/" "$BUILD_HOST:$PROJ_REMOTE/"
}

# $1=target(g3|g4|lion) — build the three game dylibs for one slice on mini-intel,
# pull them to $OUT/<mod><tag>.dylib and (for ppc) re-stamp the cpusubtype.
build_slice() {
  local T="$1" ARCH CC SDK CPUFLAGS tag stamp
  case "$T" in
    g3)   ARCH=ppc;    CC=/usr/bin/gcc-4.0; SDK=/Developer/SDKs/MacOSX10.3.9.sdk
          CPUFLAGS="-isysroot $SDK -arch ppc750 -mcpu=750 -mmacosx-version-min=10.3 -O3"
          tag=g3; stamp='\x09' ;;
    g4)   ARCH=ppc;    CC=/usr/bin/gcc-4.0; SDK=/Developer/SDKs/MacOSX10.4u.sdk
          CPUFLAGS="-isysroot $SDK -arch ppc7400 -mcpu=7400 -faltivec -mtune=7450 -mmacosx-version-min=10.4 -O3"
          tag=g4; stamp='\x0a' ;;
    lion) ARCH=x86_64; CC=/usr/bin/clang
          CPUFLAGS="-arch x86_64 -mmacosx-version-min=10.7 -O3 -Qunused-arguments"
          tag=x86_64; stamp= ;;
    *) echo "build-gamedylibs: bad target '$T'"; exit 2 ;;
  esac
  echo "==> [$T] make game dylibs (ARCH=$ARCH)"
  ssh "$BUILD_HOST" "cd $PROJ_REMOTE
    PLATFORM=darwin ARCH=$ARCH make clean >/dev/null 2>&1 || true
    PLATFORM=darwin ARCH=$ARCH CC='$CC' CFLAGS='$CPUFLAGS' \\
      BUILD_CLIENT=0 BUILD_SERVER=0 BUILD_GAME_SO=1 BUILD_GAME_QVM=0 BUILD_MISSIONPACK=0 \\
      USE_RENDERER_DLOPEN=0 USE_CURL=0 USE_OPENAL=0 USE_CODEC_VORBIS=0 USE_LOCAL_HEADERS=1 \\
      make -j2 >/dev/null 2>&1"
  local m
  for m in $MODS; do
    scp -q "$BUILD_HOST:$PROJ_REMOTE/build/release-darwin-$ARCH/baseq3/${m}${ARCH}.dylib" "$OUT/${m}-${tag}.dylib"
    # Apple ld stamps the generic-crt game dylib as ppc subtype 0; re-stamp so the
    # two ppc slices are distinct (else they collide in lipo and dyld mis-routes).
    if [ -n "$stamp" ]; then
      printf "$stamp" | dd of="$OUT/${m}-${tag}.dylib" bs=1 seek=11 count=1 conv=notrunc 2>/dev/null
    fi
  done
}

echo "############ build-gamedylibs: rsync + three slices ############"
rsync_tree
build_slice g3
build_slice g4
build_slice lion

echo "==> lipo ppc pairs on $BUILD_HOST -> fat <mod>ppc.dylib"
for m in $MODS; do
  scp -q "$OUT/${m}-g3.dylib" "$BUILD_HOST:/tmp/${m}-g3.dylib"
  scp -q "$OUT/${m}-g4.dylib" "$BUILD_HOST:/tmp/${m}-g4.dylib"
done
ssh "$BUILD_HOST" "cd /tmp
  for m in $MODS; do
    lipo -create \${m}-g3.dylib \${m}-g4.dylib -output \${m}ppc.dylib
  done"
for m in $MODS; do
  scp -q "$BUILD_HOST:/tmp/${m}ppc.dylib" "$OUT/${m}ppc.dylib"
  cp "$OUT/${m}-x86_64.dylib" "$OUT/${m}x86_64.dylib"
done
ssh "$BUILD_HOST" "rm -f /tmp/cgame-*.dylib /tmp/qagame-*.dylib /tmp/ui-*.dylib /tmp/cgameppc.dylib /tmp/qagameppc.dylib /tmp/uippc.dylib"

# tidy the per-slice intermediates, keep only the six shipping dylibs
rm -f "$OUT"/*-g3.dylib "$OUT"/*-g4.dylib "$OUT"/*-x86_64.dylib

echo "==> build/gamedylibs/ (six shipping dylibs):"
for f in "$OUT"/*.dylib; do printf '    %s  ' "$(basename "$f")"; file -b "$f" | tr -d '\n' | sed 's/Mach-O //'; echo; done
