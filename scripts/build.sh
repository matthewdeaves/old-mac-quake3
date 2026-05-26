#!/usr/bin/env bash
#
# build.sh <g3|g4|lion> — cross-compile ONE ioquake3 slice on the mini-intel
# cross-build host. Adapted from ~/quakespasm/scripts/build.sh.
#
# IMPORTANT: ioquake3 uses its own top-level `Makefile` (env-var driven),
# NOT Quake/Makefile.darwin like QuakeSpasm. Baseline is the last SDL 1.2
# commit (branch oldmac-base); see ../CLAUDE.md.
#
# ⚠️ v0 DRAFT — the build pipeline has NOT been validated end-to-end. The
#    two known-unresolved items are (1) a fat SDL 1.2 dylib for ppc750+
#    ppc7400+x86_64, and (2) compiling 2013 ioquake3 against the 10.3.9 SDK.
#    See KICKOFF_PROMPT.md. Expect to iterate on the make invocation below.
#
set -euo pipefail

TARGET="${1:?usage: build.sh <g3|g4|lion>}"
BUILD_HOST="${BUILD_HOST:-mini-intel}"
PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
PROJ_REMOTE="quake3"   # mini-intel:quake3/  — NEVER quakespasm/ or quake2/
LOCK="$PROJ_LOCAL/build/.build.lock"

mkdir -p "$PROJ_LOCAL/build"

# Serialize g3+g4: both are ARCH=ppc, rsync to the same remote tree and make
# in the same dir; concurrent runs race .o files and stamp the wrong CPU
# subtype (a g3 binary that reports ppc7400 crashes in AppKit on Panther).
exec 9>"$LOCK"
flock -w 600 9 || { echo "build.sh: timed out waiting for $LOCK"; exit 1; }

case "$TARGET" in
  g3)
    ARCH=ppc;    CC=/usr/bin/gcc-4.0
    SDK=/Developer/SDKs/MacOSX10.3.9.sdk; VMIN=10.3; SUBTYPE=ppc750
    # -arch ppc750 stamps cpusubtype 9 AND leaves __ALTIVEC__ undefined, so no
    # AltiVec instructions reach the 449 MHz G3 (which has no vector unit).
    CPUFLAGS="-isysroot $SDK -arch ppc750 -mcpu=750 -mmacosx-version-min=$VMIN -O3" ;;
  g4)
    ARCH=ppc;    CC=/usr/bin/gcc-4.0
    SDK=/Developer/SDKs/MacOSX10.4u.sdk;  VMIN=10.4; SUBTYPE=ppc7400
    # -arch ppc7400 stamps cpusubtype 10 AND defines __ALTIVEC__; -faltivec
    # enables the AltiVec ABI/codegen, -mtune=7450 schedules for the G4 line.
    CPUFLAGS="-isysroot $SDK -arch ppc7400 -mcpu=7400 -faltivec -mtune=7450 -mmacosx-version-min=$VMIN -O3" ;;
  lion)
    ARCH=x86_64; CC=/usr/bin/clang
    SDK=;        VMIN=10.7; SUBTYPE=x86_64
    CPUFLAGS="-arch x86_64 -mmacosx-version-min=10.7 -O3 -Qunused-arguments" ;;
  *) echo "build.sh: unknown target '$TARGET' (want g3|g4|lion)"; exit 2 ;;
esac

echo "==> [$TARGET] rsync $PROJ_LOCAL/ -> $BUILD_HOST:$PROJ_REMOTE/"
rsync -az --delete \
  --exclude='.git' --exclude='build/' --exclude='benchmarks/' \
  --exclude='.venv/' --exclude='*.o' --exclude='*.d' \
  "$PROJ_LOCAL/" "$BUILD_HOST:$PROJ_REMOTE/"

echo "==> [$TARGET] make on $BUILD_HOST (ARCH=$ARCH CC=$CC min=$VMIN)"
# Lean first-build config: client only (no dedicated server), no game libs
# (QVMs already ship inside baseq3/pak8.pk3), optional deps off to shrink the
# dependency surface against the old SDKs. USE_RENDERER_DLOPEN=0 links the
# opengl1 renderer straight into the binary -> a single Mach-O to deploy (no
# separate renderer_*.dylib), and skips rend2 (GL2/GLSL — useless on Rage 128 /
# GeForce2). Re-enable bits as the build stabilises.
ssh "$BUILD_HOST" "cd $PROJ_REMOTE
  PLATFORM=darwin ARCH=$ARCH make clean >/dev/null 2>&1 || true
  PLATFORM=darwin ARCH=$ARCH CC='$CC' \\
    CFLAGS='$CPUFLAGS' \\
    BUILD_CLIENT=1 BUILD_SERVER=0 BUILD_GAME_SO=0 BUILD_GAME_QVM=0 \\
    USE_RENDERER_DLOPEN=0 \\
    USE_CURL=0 USE_OPENAL=0 USE_CODEC_VORBIS=0 USE_LOCAL_HEADERS=1 \\
    make -j2"

# ioquake3 emits build/release-darwin-<arch>/ioquake3.<arch>. Both ppc slices
# share that name, so rename by TARGET as we pull back.
REMOTE_BIN="$PROJ_REMOTE/build/release-darwin-$ARCH/ioquake3.$ARCH"
LOCAL_BIN="$PROJ_LOCAL/build/ioquake3-$TARGET"
echo "==> [$TARGET] retrieve $REMOTE_BIN"
ssh "$BUILD_HOST" "test -f $REMOTE_BIN || { echo 'MISSING $REMOTE_BIN — build output dir:'; ls -la $PROJ_REMOTE/build/release-darwin-$ARCH/ 2>/dev/null; exit 1; }"
scp -q "$BUILD_HOST:$REMOTE_BIN" "$LOCAL_BIN"

# Re-stamp the Mach-O cpusubtype for the ppc slices. Apple's ld stamps the link
# as generic ppc (subtype 0) because the bundled libSDLmain.a / crt objects are
# generic — even though our codegen is target-specific (g3: no AltiVec, built
# -arch ppc750; g4: AltiVec, built -arch ppc7400). Two subtype-0 slices would
# COLLIDE in lipo and dyld couldn't route G3 vs G4. Patch the 4-byte big-endian
# cpusubtype field (offset 8; only the low byte at 11 is non-zero) so the slices
# are distinct: ppc750=9, ppc7400=10. lion (x86_64) needs no fixup. See MISTAKES.md.
case "$TARGET" in
  g3) printf '\x09' | dd of="$LOCAL_BIN" bs=1 seek=11 count=1 conv=notrunc 2>/dev/null ;;
  g4) printf '\x0a' | dd of="$LOCAL_BIN" bs=1 seek=11 count=1 conv=notrunc 2>/dev/null ;;
esac

echo "==> [$TARGET] verify (expect CPU subtype: $SUBTYPE)"
if [ "$ARCH" = ppc ]; then
  want=$([ "$TARGET" = g3 ] && echo "09" || echo "0a")
  got=$(xxd -p -s 11 -l 1 "$LOCAL_BIN")
  echo "    cpusubtype byte: 0x$got (want 0x$want for $SUBTYPE)"
  [ "$got" = "$want" ] || { echo "build.sh: cpusubtype re-stamp failed"; exit 1; }
fi
file "$LOCAL_BIN" | sed 's/^/    /'

# SDL linkage: the binary references @executable_path/libSDL-1.2.0.dylib, so the
# fat dylib (code/libs/macosx/) just needs to sit next to it — deploy.sh ships it.
echo "==> [$TARGET] done -> build/ioquake3-$TARGET"
