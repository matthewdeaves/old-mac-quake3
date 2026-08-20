#!/usr/bin/env bash
#
# build-gamedylibs-arm64.sh - build the three game modules (cgame, qagame, ui)
# as native arm64 dylibs, the arm64 counterpart to build-gamedylibs.sh.
#
# RUNS HERE, on the orchestration Mac, for the same reason build-arm64.sh does.
#
# Why native and not the QVM, on this slice specifically
# ------------------------------------------------------
# On the other slices this is a real-compiler-over-JIT win: ppc and x86 both
# have a QVM backend (vm_powerpc.c, vm_x86.c) so the bytecode is already
# native by the time it runs. arm64 has no backend in this baseline, so a QVM
# here drops to the plain interpreter and the engine says so on stdout
# ("Architecture doesn't have a bytecode compiler, using interpreter").
#
# Measured on an M5, demo four, median of three: native 875 fps, interpreted
# QVM 830 fps. The gap is small only because that demo is renderer-bound at
# these rates.
#
# These dylibs did not work at all until the vmMain entry-point fix in
# qcommon.h. The engine called vmMain through a variadic pointer while every
# module defines it with named int parameters; that agrees on x86_64 and
# PowerPC and does not on Apple arm64, where a variadic call passes everything
# after the last NAMED argument on the stack while a non-variadic callee reads
# x1-x7. The module got its command and garbage for every argument, which
# surfaced as "CG_ConfigString: bad index: -274449096". docs/adr/0017.
#
# No lipo and no cpusubtype re-stamping here, unlike the ppc pair: arm64 has
# one subtype and this produces one slice per module.
#
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$PROJ/build/gamedylibs"
VMIN="${Q3_ARM64_MIN:-11.0}"

[ "$(uname -m)" = "arm64" ] || {
  echo "build-gamedylibs-arm64.sh: needs an Apple Silicon Mac (uname -m says $(uname -m))" >&2
  exit 1; }

mkdir -p "$OUT"

# BUILD_MISSIONPACK=0: we ship baseq3 only, and the missionpack build emits a
# second set of identically named dylibs into missionpack/ that would be easy
# to pick up by mistake.
#
# The two make ARGUMENT overrides are the same pair build-arm64.sh needs and for
# the same reason (the Makefile assigns both itself, so the environment loses).
# SHLIBLDFLAGS is overridden because the stock one takes its arch from $(LDFLAGS)
# which we are not setting; -Wl,-U,_com_altivec is kept from upstream, since the
# modules reference com_altivec and the engine supplies it.
echo "==> building cgame/qagame/ui (arm64, macOS $VMIN)"
( cd "$PROJ" && PLATFORM=darwin ARCH=arm64 make clean >/dev/null 2>&1 || true )
( cd "$PROJ" && PLATFORM=darwin ARCH=arm64 CC=/usr/bin/clang \
    CFLAGS="-arch arm64 -mmacosx-version-min=$VMIN -O3 -Qunused-arguments" \
    BUILD_CLIENT=0 BUILD_SERVER=0 BUILD_GAME_SO=1 BUILD_GAME_QVM=0 \
    BUILD_MISSIONPACK=0 USE_CURL=0 USE_OPENAL=0 USE_CODEC_VORBIS=0 \
    USE_LOCAL_HEADERS=1 \
    make -j"$(sysctl -n hw.ncpu)" HAVE_VM_COMPILED= NOTSHLIBCFLAGS= \
      SHLIBLDFLAGS="-dynamiclib -arch arm64 -mmacosx-version-min=$VMIN -Wl,-U,_com_altivec" )

SRC="$PROJ/build/release-darwin-arm64/baseq3"
for m in cgame qagame ui; do
  F="$SRC/${m}arm64.dylib"
  test -f "$F" || { echo "build-gamedylibs-arm64.sh: make produced no $F" >&2; exit 1; }
  cp "$F" "$OUT/${m}arm64.dylib"
  chmod u+w "$OUT/${m}arm64.dylib"
  strip -x "$OUT/${m}arm64.dylib"
  # Ad-hoc sign, for the same reason the engine slice is signed: an unsigned
  # arm64 Mach-O is SIGKILLed on load with no diagnostic. dlopen is no
  # exception, and a module that fails to load is silently replaced by the QVM,
  # so this would degrade quietly rather than fail loudly.
  codesign --force --sign - "$OUT/${m}arm64.dylib"
  codesign --verify --verbose=1 "$OUT/${m}arm64.dylib"
  GOT=$(lipo -info "$OUT/${m}arm64.dylib" | sed 's/.*: //' | tr -d ' ')
  [ "$GOT" = "arm64" ] || { echo "build-gamedylibs-arm64.sh: ${m} is '$GOT', want 'arm64'" >&2; exit 1; }
  echo "    ${m}arm64.dylib  $GOT  $(du -h "$OUT/${m}arm64.dylib" | cut -f1)"
done

# The engine dlopen()s these BY NAME, built from ARCH_STRING: "qagame" +
# "arm64" + ".dylib". That happens to line up here because ioquake3's Makefile
# also calls this arch "arm64". It does NOT line up on the i386 slice, where the
# Makefile says "x86" and ARCH_STRING says "i386", which is exactly why that
# slice ships no native modules at all. See scripts/bundle/autoexec-i386.cfg.
echo "==> done -> build/gamedylibs/{cgame,qagame,ui}arm64.dylib"
