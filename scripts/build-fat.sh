#!/usr/bin/env bash
#
# build-fat.sh — build all three ioquake3 slices and lipo them into one fat
# binary (ppc750 + ppc7400 + x86_64). Adapted from ~/quakespasm/scripts.
# This is the only binary we deploy. dyld picks the slice per CPU at runtime;
# multi-subtype ppc lipo (ppc750 + ppc7400) is proven to work by QuakeSpasm.
#
# Validated — produces the shipping fat binary for the whole fleet (g3 and g4
# both against the 10.3.9 SDK at min 10.3, lion x86_64 at min 10.6, lipo'd with
# re-stamped and asserted ppc cpusubtypes).
#
set -euo pipefail

PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$PROJ_LOCAL/build"

# Pin ONE Intel build host for the whole fat build and claim it up front, so all
# three slices and the final lipo use the same mini and no sister project
# (Q1/Q2/Half-Life) takes the box between slices. Explicit BUILD_HOST always wins.
if [ -z "${BUILD_HOST:-}" ]; then
  BUILD_HOST="$(BUILD_LOCK_WAIT="${BUILD_LOCK_WAIT:-900}" \
    "$HERE/pick-build-host.sh" --acquire "quake3 build-fat")" || {
    echo "build-fat.sh: no free Intel build host; see scripts/pick-build-host.sh --status" >&2
    exit 1
  }
  export BUILD_HOST
  # Absolute path: the trap must still resolve if anything ever cd's away.
  trap '"$HERE/pick-build-host.sh" --release "$BUILD_HOST" >/dev/null 2>&1; true' EXIT
  echo "==> claimed build host: $BUILD_HOST (held for all three slices + lipo)"
else
  export BUILD_HOST
  echo "==> using caller-supplied build host: $BUILD_HOST"
fi

# Clear last run's slices first: if a build.sh invocation fails we must not lipo
# a stale ioquake3-<target> from an earlier commit into the shipping fat.
#
# NOT build/ioquake3-arm64: this script cannot build it (no mini can), so it is
# produced separately by scripts/build-arm64.sh and would be destroyed here for
# no reason. It is picked up below if it exists.
rm -f "$OUT"/ioquake3-g3 "$OUT"/ioquake3-g4 "$OUT"/ioquake3-lion "$OUT"/ioquake3-i386 "$OUT"/ioquake3-fat

# Serialize the four cross-built slices (build.sh flocks anyway; this just
# sequences them).
for T in g3 g4 lion i386; do
  echo "############ building slice: $T ############"
  "$HERE/build.sh" "$T"
done

for T in g3 g4 lion i386; do
  test -f "$OUT/ioquake3-$T" || { echo "build-fat.sh: missing slice build/ioquake3-$T"; exit 1; }
done

# arm64 is OPTIONAL, and its absence is a Rosetta 2 downgrade rather than a
# fault: a fat with no arm64 member still runs on Apple Silicon, via the x86_64
# slice. Say which of the two happened either way, so a release is never
# silently short a slice. scripts/build-arm64.sh produces it.
SLICES="ioquake3-g3 ioquake3-g4 ioquake3-lion ioquake3-i386"
WANT="ppc750 ppc7400 i386 x86_64"
if [ -f "$OUT/ioquake3-arm64" ]; then
  SLICES="$SLICES ioquake3-arm64"
  WANT="$WANT arm64"
  echo "==> arm64 slice present, fusing five"
else
  echo "==> NO arm64 slice (build/ioquake3-arm64 absent), fusing four"
  echo "    Apple Silicon will run the x86_64 slice under Rosetta 2."
  echo "    Run scripts/build-arm64.sh on the orchestration Mac to include it."
fi

echo "==> lipo on $BUILD_HOST"
# shellcheck disable=SC2086  # SLICES is a deliberate word-split list
( cd "$OUT" && scp -q $SLICES "$BUILD_HOST:/tmp/" )
ssh "$BUILD_HOST" "cd /tmp
  lipo -create $SLICES -output ioquake3-fat
  lipo -info ioquake3-fat"
scp -q "$BUILD_HOST:/tmp/ioquake3-fat" "$OUT/ioquake3-fat"
ssh "$BUILD_HOST" "cd /tmp && rm -f $SLICES ioquake3-fat"

# Lion's lipo WRITES an arm64 member correctly but cannot NAME it, so the
# remote lipo -info above prints "cputype (16777228)" for that slice. That is
# cosmetic. The gate below runs HERE, where lipo knows the name.
#
# Compared as a SET, not as a string. lipo lists members in the order they were
# fused, not in any canonical order, so an ordered compare asserts the argument
# order of the lipo call rather than the contents of the file. That is exactly
# how this gate broke when the i386 slice was added: the slice was fused
# correctly and the build still failed, on 'ppc750 ppc7400 x86_64 i386' not
# matching a hardcoded 'ppc750 ppc7400 x86_64'.
GOT=$(lipo -info "$OUT/ioquake3-fat" | sed 's/.*: //' | tr -s ' ' | sed 's/ *$//')
GOT_SET=$(printf '%s\n' $GOT | LC_ALL=C sort | tr '\n' ' ')
WANT_SET=$(printf '%s\n' $WANT | LC_ALL=C sort | tr '\n' ' ')
[ "$GOT_SET" = "$WANT_SET" ] || {
  echo "build-fat.sh: fat is '$GOT', want the set '$WANT'"; exit 1; }

# A generic `ppc` member would be graded onto EVERY PowerPC host and shadow the
# right slice, so assert its absence explicitly rather than relying on the
# string compare above to have caught it.
case " $GOT " in
  *" ppc "*) echo "build-fat.sh: fat contains a generic ppc member"; exit 1;;
esac

echo "==> fat binary -> build/ioquake3-fat"
echo "    architectures: $GOT"
file "$OUT/ioquake3-fat" | sed 's/^/    /'
