#!/usr/bin/env bash
#
# build-arm64.sh - build the ioquake3 arm64 (Apple Silicon) slice.
#
# RUNS HERE, on the orchestration Mac, NOT on a build mini. This is the one
# slice a mini cannot produce: their Xcode 4.6 toolchain predates arm64 by
# seven years. Everything else in this port cross-compiles on Lion; see
# scripts/build.sh for those four targets.
#
# The SDL problem, and how this slice solves it
# ---------------------------------------------
# This engine is the last SDL 1.2 baseline of ioquake3, and SDL 1.2 has no
# arm64 build. So the arm64 slice links sdl12-compat, which reimplements the
# 1.2 API on top of SDL2, and we supply the SDL2 as well.
#
# That is a two-layer stack we own end to end, not the four-layer one you get
# from a package manager. sdl12-compat has NO link-time dependency on SDL2 at
# all: it dlopen()s one at runtime, trying "@loader_path/libSDL2-2.0.0.dylib"
# FIRST (SDL12_compat.c, the dylib_locations table). Because we ship our own
# real SDL2 next to the binary, that is the one it finds, and a system SDL2
# never enters the picture. Verified with otool: the built shim links only
# AppKit, Foundation, CoreFoundation, ApplicationServices, libobjc, libSystem.
#
# PowerPC and Intel are untouched by any of this. dyld grades a fat by CPU
# subtype alone, so those four slices keep the genuine SDL 1.2 that is already
# committed in code/libs/macosx/libSDL-1.2.0.dylib; only the arm64 member of
# that same fat is the shim. docs/adr/0017.
#
# What this script does NOT do: fuse. build-fat.sh does that, and it treats
# arm64 as OPTIONAL, so a tree where this script has never run still produces a
# valid four-slice release rather than failing.
#
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$PROJ/build"
VMIN="${Q3_ARM64_MIN:-11.0}"
PREFIX="${Q3_ARM64_PREFIX:-$HOME/.cache/oldmac-q3-arm64}"

# Pinned, because "whatever the machine happens to have" is how a port stops
# being reproducible. Bump deliberately, then re-bench.
SDL2_VER="${Q3_ARM64_SDL2_VER:-2.32.4}"
SDL12_URL="https://github.com/libsdl-org/sdl12-compat.git"
SDL12_TAG="${Q3_ARM64_SDL12_TAG:-release-1.2.76}"

command -v cmake >/dev/null 2>&1 || { echo "build-arm64.sh: needs cmake" >&2; exit 1; }
[ "$(uname -m)" = "arm64" ] || {
  echo "build-arm64.sh: this must run on an Apple Silicon Mac (uname -m says $(uname -m))" >&2
  exit 1; }

mkdir -p "$OUT" "$PREFIX"

# --- 0) a real SDL2, from source ---------------------------------------------
# The prefix records what built it, so a bumped version or floor rebuilds rather
# than silently reusing the previous one.
SDL2_WANT="SDL2 $SDL2_VER arm64 $VMIN"
if [ "$(cat "$PREFIX/.sdl2-built-from" 2>/dev/null)" != "$SDL2_WANT" ]; then
  echo "==> [0/3] building SDL $SDL2_VER (arm64, macOS $VMIN)"
  rm -rf "$PREFIX/sdl2"
  SRC="$PREFIX/src/SDL2-$SDL2_VER"
  if [ ! -d "$SRC" ]; then
    mkdir -p "$PREFIX/src"
    curl -fsSL "https://www.libsdl.org/release/SDL2-$SDL2_VER.tar.gz" | tar xz -C "$PREFIX/src"
  fi
  # Shared, not static: the shim dlopen()s it by name at runtime, so a static
  # archive would simply be unreachable. Built out of tree so a re-run with a
  # different floor cannot pick up the previous configure's cache.
  rm -rf "$SRC/build-arm64" && mkdir -p "$SRC/build-arm64"
  ( cd "$SRC/build-arm64" && CFLAGS="-arch arm64 -mmacosx-version-min=$VMIN -O2" \
      LDFLAGS="-arch arm64 -mmacosx-version-min=$VMIN" \
      ../configure --prefix="$PREFIX/sdl2" --build=arm64-apple-darwin \
        --enable-shared --disable-static >/dev/null )
  ( cd "$SRC/build-arm64" && make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null )
  printf '%s\n' "$SDL2_WANT" > "$PREFIX/.sdl2-built-from"
fi
SDL2_DYLIB="$PREFIX/sdl2/lib/libSDL2-2.0.0.dylib"
test -f "$SDL2_DYLIB" || { echo "build-arm64.sh: no $SDL2_DYLIB after build" >&2; exit 1; }

# --- 1) sdl12-compat, from source --------------------------------------------
SDL12_WANT="sdl12-compat $SDL12_TAG arm64 $VMIN"
if [ "$(cat "$PREFIX/.sdl12-built-from" 2>/dev/null)" != "$SDL12_WANT" ]; then
  echo "==> [1/3] building sdl12-compat $SDL12_TAG (arm64, macOS $VMIN)"
  SRC12="$PREFIX/src/sdl12-compat"
  [ -d "$SRC12/.git" ] || git clone -q "$SDL12_URL" "$SRC12"
  ( cd "$SRC12" && git fetch -q --tags && git checkout -q "$SDL12_TAG" )
  rm -rf "$SRC12/build-arm64"
  cmake -S "$SRC12" -B "$SRC12/build-arm64" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$VMIN" \
    -DCMAKE_BUILD_TYPE=Release -DSDL12TESTS=OFF -DSDL12DEVEL=OFF >/dev/null
  cmake --build "$SRC12/build-arm64" -j"$(sysctl -n hw.ncpu)" >/dev/null
  rm -rf "$PREFIX/sdl12" && mkdir -p "$PREFIX/sdl12"
  cp "$SRC12/build-arm64/libSDL-1.2.0.dylib" "$SRC12/build-arm64/libSDLmain.a" "$PREFIX/sdl12/"
  printf '%s\n' "$SDL12_WANT" > "$PREFIX/.sdl12-built-from"
fi

# The shim must not have picked up a link-time SDL2. If it ever does, the whole
# "we control both layers" argument above collapses, so assert it rather than
# trusting the build.
if otool -L "$PREFIX/sdl12/libSDL-1.2.0.dylib" | tail -n +2 | grep -qi 'SDL2'; then
  echo "build-arm64.sh: the shim link-depends on SDL2; it must dlopen it instead" >&2
  otool -L "$PREFIX/sdl12/libSDL-1.2.0.dylib" | sed 's/^/    /' >&2
  exit 1
fi

# --- 2) the engine ------------------------------------------------------------
# Two make-level overrides are needed, and they must be make ARGUMENTS, not
# environment variables: the Makefile ASSIGNS both of these itself inside its
# darwin block, and a makefile assignment beats the environment. (build.sh can
# pass its settings in the environment because those are all ifndef-guarded.)
#
#   HAVE_VM_COMPILED=  there is no arm64 QVM JIT in this baseline. Left set,
#                      vm.c references VM_Compile/VM_CallCompiled and the link
#                      fails. Cleared, it gets -DNO_VM_COMPILED and interprets.
#   NOTSHLIBCFLAGS=    clears -mdynamic-no-pic, which arm64 clang does not take.
#
# A clean is mandatory, not hygiene: neither override is a file dependency, so
# make will happily relink stale objects built without them.
echo "==> [2/3] building ioquake3 (arm64, macOS $VMIN)"
( cd "$PROJ" && PLATFORM=darwin ARCH=arm64 make clean >/dev/null 2>&1 || true )
( cd "$PROJ" && PLATFORM=darwin ARCH=arm64 CC=/usr/bin/clang \
    CFLAGS="-arch arm64 -mmacosx-version-min=$VMIN -O3 -Qunused-arguments" \
    BUILD_CLIENT=1 BUILD_SERVER=0 BUILD_GAME_SO=0 BUILD_GAME_QVM=0 \
    USE_RENDERER_DLOPEN=0 USE_CURL=0 USE_OPENAL=0 USE_CODEC_VORBIS=0 \
    USE_LOCAL_HEADERS=1 \
    make -j"$(sysctl -n hw.ncpu)" HAVE_VM_COMPILED= NOTSHLIBCFLAGS= )

BIN="$PROJ/build/release-darwin-arm64/ioquake3.arm64"
test -f "$BIN" || { echo "build-arm64.sh: make produced no $BIN" >&2; exit 1; }

rm -f "$OUT/ioquake3-arm64"
cp "$BIN" "$OUT/ioquake3-arm64"

# --- 3) stage the SDL pair, sign, verify --------------------------------------
# Sign BEFORE the fuse, never after: build-fat.sh lipos on a Lion mini, which
# cannot codesign arm64, and an unsigned arm64 Mach-O is SIGKILLed by the kernel
# with no diagnostic at all. lipo preserves each slice's bytes, signature
# included, so signing the single-arch member here survives the fuse.
cp "$PREFIX/sdl12/libSDL-1.2.0.dylib" "$OUT/libSDL-1.2.0-arm64.dylib"
cp "$SDL2_DYLIB"                      "$OUT/libSDL2-2.0.0.dylib"
chmod u+w "$OUT/libSDL-1.2.0-arm64.dylib" "$OUT/libSDL2-2.0.0.dylib"
install_name_tool -id "@executable_path/libSDL-1.2.0.dylib" "$OUT/libSDL-1.2.0-arm64.dylib"
install_name_tool -id "@executable_path/libSDL2-2.0.0.dylib" "$OUT/libSDL2-2.0.0.dylib"
strip -x "$OUT/libSDL-1.2.0-arm64.dylib" "$OUT/libSDL2-2.0.0.dylib"
for f in "$OUT/ioquake3-arm64" "$OUT/libSDL-1.2.0-arm64.dylib" "$OUT/libSDL2-2.0.0.dylib"; do
  codesign --force --sign - "$f"
  codesign --verify --verbose=1 "$f"
done

echo "==> [3/3] verify"
GOT=$(lipo -info "$OUT/ioquake3-arm64" | sed 's/.*: //' | tr -d ' ')
echo "    cpusubtype: $GOT (want arm64)"
[ "$GOT" = "arm64" ] || { echo "build-arm64.sh: slice is '$GOT', want 'arm64'" >&2; exit 1; }

# The engine must reference the shim by the same install name the other four
# slices use, or dyld looks for a file that is not there.
otool -L "$OUT/ioquake3-arm64" | grep -q '@executable_path/libSDL-1.2.0.dylib' || {
  echo "build-arm64.sh: engine does not reference @executable_path/libSDL-1.2.0.dylib" >&2
  otool -L "$OUT/ioquake3-arm64" | sed 's/^/    /' >&2; exit 1; }

echo "==> done"
echo "    build/ioquake3-arm64          engine slice (fuse with build-fat.sh)"
echo "    build/libSDL-1.2.0-arm64.dylib  sdl12-compat (fuse into code/libs/macosx/)"
echo "    build/libSDL2-2.0.0.dylib     real SDL $SDL2_VER, shipped beside the binary"
