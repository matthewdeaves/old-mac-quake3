#!/usr/bin/env bash
#
# build.sh <g3|g4|lion|i386>: cross-compile ONE ioquake3 slice on the mini-intel
# cross-build host. Adapted from ~/quakespasm/scripts/build.sh.
#
# IMPORTANT: ioquake3 uses its own top-level `Makefile` (env-var driven),
# NOT Quake/Makefile.darwin like QuakeSpasm. Baseline is the last SDL 1.2
# commit (branch master, rooted at 4432a80a); see ../CLAUDE.md.
#
# VALIDATED — this builds each of the four cross-buildable slices and they run
# on real hardware (arm64 is built by scripts/build-arm64.sh, not here). The
# two items that were open at kickoff are both resolved (2026-05-26): the fat
# SDL 1.2 dylib is QuakeSpasm's Panther-safe 1.2.15 with SDLMain.m compiled
# from source (the bundled 10.4+ libSDLmain.a SIGSEGVs on Panther), and 2013
# ioquake3 compiles clean against the 10.3.9 SDK with gcc-4.0. See ../CLAUDE.md
# for the resolved-items list and ../MISTAKES.md for the SDL detail.
#
set -euo pipefail

TARGET="${1:?usage: build.sh <g3|g4|lion|i386>}"
PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
PROJ_REMOTE="quake3"   # <build host>:quake3/  — NEVER quakespasm/ or quake2/

# The cross-build host is an Intel Mac mini — there are now TWO interchangeable
# ones (mini-intel, mini-intel2: same Macmini2,1 / 10.7.5 / identical toolchain).
# When the caller has not pinned one, ask pick-build-host.sh for a host that is
# reachable and idle, and CLAIM it for the duration so nothing takes it mid-build.
# The claim is a lock ON the mini, so it is visible to the Q1/Q2/Half-Life sister
# projects too — the flock below only serialises builds from THIS checkout.
# build-fat.sh pins BUILD_HOST for all four slices, so this only fires for a
# standalone build.sh run.
BUILD_HOST_CLAIMED=0
if [ -z "${BUILD_HOST:-}" ]; then
  # Export a claim nonce BEFORE the acquire so the EXIT trap below releases with
  # the same one. Without it the picker falls back to matching user@host:repo,
  # which is identical for two sessions in this repo, and either could drop the
  # other's lock. old-mac-build-host#7.
  #
  # It must be exported, not just set: the release runs from a trap, and if the
  # nonce did not reach it the picker would meet a claim= it cannot match and
  # strand the lock until the 90 minute reclaim. That round trip is the test.
  export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-$$.$(date +%s).${RANDOM:-0}}"
  BUILD_HOST="$(BUILD_LOCK_WAIT="${BUILD_LOCK_WAIT:-900}" \
    "$PROJ_LOCAL/scripts/pick-build-host.sh" --acquire "quake3 build.sh $TARGET")" || {
    echo "build.sh: no free Intel build host; see scripts/pick-build-host.sh --status" >&2
    exit 1
  }
  BUILD_HOST_CLAIMED=1
  echo "[build] claimed build host: $BUILD_HOST"
elif [ "${BUILD_HOST_PRECLAIMED:-0}" != 1 ]; then
  # BUILD_HOST is set but not by build-fat.sh (it exports BUILD_HOST_PRECLAIMED
  # when it already holds the claim for the whole run) - a session pinned this
  # host directly for a standalone build.sh run. Claim it for real: this used
  # to run completely unclaimed. Issue #34.
  export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-$$.$(date +%s).${RANDOM:-0}}"
  "$PROJ_LOCAL/scripts/pick-build-host.sh" --acquire-host "$BUILD_HOST" "quake3 build.sh $TARGET" >/dev/null || {
    echo "build.sh: $BUILD_HOST is not available; see scripts/pick-build-host.sh --status $BUILD_HOST" >&2
    exit 1
  }
  BUILD_HOST_CLAIMED=1
  echo "[build] claimed caller-pinned build host: $BUILD_HOST"
fi
trap '[ "$BUILD_HOST_CLAIMED" = 1 ] && "$PROJ_LOCAL/scripts/pick-build-host.sh" --release "$BUILD_HOST" >/dev/null 2>&1; true' EXIT

LOCK="$PROJ_LOCAL/build/.build.lock"

mkdir -p "$PROJ_LOCAL/build"

# Serialize g3+g4: both are ARCH=ppc, rsync to the same remote tree and make
# in the same dir; concurrent runs race .o files and stamp the wrong CPU
# subtype (a g3 binary that reports ppc7400 crashes in AppKit on Panther).
exec 9>"$LOCK"
flock -w 600 9 || { echo "build.sh: timed out waiting for $LOCK"; exit 1; }

case "$TARGET" in
  g3)
    ARCH=ppc;    SDK=/Developer/SDKs/MacOSX10.3.9.sdk; VMIN=10.3; SUBTYPE=ppc750
    if [ "$BUILD_HOST" = "imac-2019" ]; then
      # scratch/imac-2019-altivec-fix: /Developer/SDKs never exists here
      # (sealed system volume, not a permissions gap) - real SDKs live at
      # ~/SDKs/*.sdk. GCC14 doesn't accept Apple's multi-subtype -arch
      # syntax at all ("this compiler does not support 'ppc7400'", checked
      # directly) so g3 (no AltiVec, no include-fixed issue per build-host)
      # needs no other change. docs/adr/0020.
      CC=/Users/mini/gcc14-ppc/bin/powerpc-apple-darwin8-gcc
      SDK=/Users/mini/SDKs/MacOSX10.3.9.sdk
      GCCBASE=/Users/mini/gcc14-ppc/lib/gcc/powerpc-apple-darwin8/14.2.0
      # scratch/imac-2019-altivec-fix: MEASURED, contradicts the earlier
      # "g3 doesn't need this" note - that was checked against a minimal
      # header test, not a real build. A real g3 build hits it too, just
      # differently (stddef.h/ptrdiff_t undeclared reaching code/zlib/,
      # not machine/ansi.h) - same include-fixed-shadows-isysroot cause.
      # docs/adr/0020.
      # -include the ptrdiff_t shim (docs/adr/0020 Follow-up 7): Panther's
      # ansi.h defines _BSD_PTRDIFF_T_ as a value-alias macro, GCC14's
      # stddef.h misreads that as "already typedef'd" and skips its own -
      # force the real typedef in ahead of anything else that could pull
      # stddef.h in first.
      CPUFLAGS="-include scripts/imac-2019-ptrdiff-shim.h -nostdinc -isystem $GCCBASE/include -isystem $GCCBASE/../../../../powerpc-apple-darwin8/include -isystem $SDK/usr/include -iframework $SDK/System/Library/Frameworks -isysroot $SDK -arch ppc -mcpu=750 -mmacosx-version-min=$VMIN -O3"
    else
      CC=/usr/bin/gcc-4.0
      # -arch ppc750 stamps cpusubtype 9 AND leaves __ALTIVEC__ undefined, so no
      # AltiVec instructions reach the 449 MHz G3 (which has no vector unit).
      CPUFLAGS="-isysroot $SDK -arch ppc750 -mcpu=750 -mmacosx-version-min=$VMIN -O3"
    fi ;;
  g4)
    ARCH=ppc;    SDK=/Developer/SDKs/MacOSX10.3.9.sdk; VMIN=10.3; SUBTYPE=ppc7400
    if [ "$BUILD_HOST" = "imac-2019" ]; then
      # scratch/imac-2019-altivec-fix: same SDK-path and -arch-syntax notes
      # as g3 above, PLUS GCC14's include-fixed search order pulls a
      # Panther-bootstrap sys/types.h ahead of -isysroot's for ANY g4/g5
      # compile (machine/ansi.h: No such file or directory) - workaround is
      # -nostdinc plus an explicit -isystem list, verified against this
      # project's real -mmacosx-version-min=10.3 (not just build-host's
      # tested 10.4 case). docs/adr/0020, old-mac-build-host docs/imac-2019.md.
      CC=/Users/mini/gcc14-ppc/bin/powerpc-apple-darwin8-gcc
      SDK=/Users/mini/SDKs/MacOSX10.3.9.sdk
      GCCBASE=/Users/mini/gcc14-ppc/lib/gcc/powerpc-apple-darwin8/14.2.0
      # -include the ptrdiff_t shim, same reasoning as g3 above. docs/adr/0020
      # Follow-up 7.
      CPUFLAGS="-include scripts/imac-2019-ptrdiff-shim.h -nostdinc -isystem $GCCBASE/include -isystem $GCCBASE/../../../../powerpc-apple-darwin8/include -isystem $SDK/usr/include -iframework $SDK/System/Library/Frameworks -isysroot $SDK -arch ppc -mcpu=7400 -maltivec -mabi=altivec -mmacosx-version-min=$VMIN -O3"
    else
      CC=/usr/bin/gcc-4.0
      # -arch ppc7400 stamps cpusubtype 10 AND defines __ALTIVEC__; -faltivec
      # enables the AltiVec ABI/codegen, -mtune=7450 schedules for the G4 line.
      #
      # 10.3.9 SDK at min 10.3, NOT 10.4u/min-10.4: dyld grades slices by CPU
      # subtype alone, so a G4 on Panther is handed this slice with no fallback
      # to the min-10.3 ppc750 one. A 10.4-built slice is simply dead there.
      # AltiVec codegen is independent of the SDK, so this costs nothing on
      # Tiger. -isystem is required because <altivec.h> is a *compiler* header
      # and -isysroot hides it.
      CPUFLAGS="-isysroot $SDK -arch ppc7400 -mcpu=7400 -faltivec -mtune=7450 -mmacosx-version-min=$VMIN -O3 -isystem /usr/lib/gcc/powerpc-apple-darwin10/4.0.1/include"
    fi ;;
  lion)
    ARCH=x86_64; CC=/usr/bin/clang
    SDK=;        VMIN=10.6; SUBTYPE=x86_64
    # min 10.6, not 10.7: a 64-bit Intel Mac on Snow Leopard grades to this
    # slice too. The shipped libSDL-1.2.0.dylib is already built at 10.6.
    CPUFLAGS="-arch x86_64 -mmacosx-version-min=$VMIN -O3 -Qunused-arguments"
    if [ "$BUILD_HOST" = "imac-2019" ]; then
      # scratch/imac-2019-altivec-fix: MEASURED SEGFAULT without this.
      # imac-2019's own (Xcode 16) clang/ld64 emits LC_MAIN regardless of
      # -mmacosx-version-min, which pre-10.8 dyld cannot parse - real
      # hardware test (mini-intel2, Lion 10.7.5) confirmed exit 139,
      # immediately, zero output. -Wl,-ld_classic makes the linker emit
      # LC_UNIXTHREAD instead (build-host's finding, cross-checked). Not
      # needed on mini-intel/mini-intel2's own (much older) clang. docs/adr/0020.
      CPUFLAGS="$CPUFLAGS -Wl,-ld_classic"
    fi ;;
  i386)
    # 32-bit-only Intel: the 2006 Core Solo / Core Duo machines (Mac mini 1,1,
    # iMac 4,1, MacBook 1,1, MacBook Pro 1,1). The only Intel Macs with no
    # 64-bit mode, and they stop at 10.6.8.
    #
    # dyld grades by CPU subtype alone and never falls back, so without this
    # slice those machines are handed nothing at all and the app does not
    # launch. The shipped code/libs/macosx/libSDL-1.2.0.dylib already carries
    # an i386 slice, so nothing else has to move.
    #
    # min 10.4, lower than the x86_64 slice's 10.6: an i386-only Mac may still
    # be on Tiger or Leopard and there is nothing below this slice.
    #
    # ARCH=x86 rather than i386: that is what ioquake3's Makefile calls it,
    # and q_platform.h keys ARCH_STRING "i386" off __i386__ regardless.
    #
    # NOT TESTED ON HARDWARE: no 32-bit-only Intel Mac exists in the fleet.
    ARCH=x86;    CC=/usr/bin/clang
    SDK=;        VMIN=10.4; SUBTYPE=i386
    CPUFLAGS="-arch i386 -mmacosx-version-min=$VMIN -O3 -Qunused-arguments"
    if [ "$BUILD_HOST" = "imac-2019" ]; then
      # scratch/imac-2019-altivec-fix: MEASURED, real error without this -
      # Sequoia's own system AppKit headers (SDK="" defaults to the host's
      # own frameworks) fail to compile at all for i386/-mmacosx-version-
      # min=10.4: "cannot define category for undefined class
      # 'NSItemProvider'" (NSPreviewRepresentingActivityItem.h forward-
      # declaration ordering) - a modern-SDK-generation/old-deployment-
      # target incompatibility, unrelated to GCC14/PPC entirely (i386 uses
      # system clang, same as lion). A period-correct staged SDK sidesteps
      # it clean - compiles with zero errors. docs/adr/0020.
      CPUFLAGS="$CPUFLAGS -isysroot /Users/mini/SDKs/MacOSX10.4u.sdk -Wl,-ld_classic"
    fi
    true ;;
  arm64)
    echo "build.sh: arm64 cannot be built on a Lion mini (its Xcode 4.6" >&2
    echo "build.sh: toolchain predates arm64), and the SDL 1.2 this engine" >&2
    echo "build.sh: links has no arm64 build. See docs/adr/0015." >&2
    exit 2 ;;
  *) echo "build.sh: unknown target '$TARGET' (want g3|g4|lion|i386)"; exit 2 ;;
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
# Drop any previous artifact first: if the scp below fails, the verify step must
# not pass on a stale binary left from an earlier run.
rm -f "$LOCAL_BIN"
scp -q "$BUILD_HOST:$REMOTE_BIN" "$LOCAL_BIN"
[ -f "$LOCAL_BIN" ] || { echo "build.sh: retrieve produced no $LOCAL_BIN"; exit 1; }

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
# Assert on the decoded subtype, not just the byte we wrote: -faltivec is known
# to defeat -mcpu='s stamping outright, and a generic `ppc` member is fatal (it
# matches every PowerPC host, so a G3 can be handed the AltiVec slice). Trust
# lipo here — `file` misreports subtype 9 as "ppc_650" on a modern host.
if command -v lipo >/dev/null 2>&1; then
  got=$(lipo -info "$LOCAL_BIN" | sed 's/.*: //' | tr -d ' ')
else
  got=$(python3 -c "
import struct, sys
data = open('$LOCAL_BIN', 'rb').read(12)
if len(data) >= 12:
    magic = struct.unpack('>I', data[:4])[0]
    if magic == 0xfeedface:
        t, s = struct.unpack('>II', data[4:12])
        print({(18, 9): 'ppc750', (18, 10): 'ppc7400', (18, 100): 'ppc970', (18, 0): 'ppc'}.get((t, s & 0xffffff), f'cputype({t}) cpusubtype({s})'))
    elif magic == 0xcefaedfe:
        t, s = struct.unpack('<II', data[4:12])
        print({(7, 3): 'i386'}.get((t, s & 0xffffff), f'cputype({t}) cpusubtype({s})'))
    elif magic == 0xcffaedfe:
        t, s = struct.unpack('<II', data[4:12])
        print({(0x01000007, 3): 'x86_64', (0x0100000c, 0): 'arm64'}.get((t, s & 0xffffff), f'cputype({t}) cpusubtype({s})'))
" 2>/dev/null || echo "")
fi
echo "    cpusubtype: $got (want $SUBTYPE)"
[ "$got" = "$SUBTYPE" ] || { echo "build.sh: cpusubtype is '$got', want '$SUBTYPE' - re-stamp failed"; exit 1; }
file "$LOCAL_BIN" | sed 's/^/    /'

# SDL linkage: the binary references @executable_path/libSDL-1.2.0.dylib, so the
# fat dylib (code/libs/macosx/) just needs to sit next to it — deploy.sh ships it.
echo "==> [$TARGET] done -> build/ioquake3-$TARGET"
