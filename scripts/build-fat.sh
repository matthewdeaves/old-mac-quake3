#!/usr/bin/env bash
#
# build-fat.sh — build all three ioquake3 slices and lipo them into one fat
# binary (ppc750 + ppc7400 + x86_64). Adapted from ~/quakespasm/scripts.
# This is the only binary we deploy. dyld picks the slice per CPU at runtime;
# multi-subtype ppc lipo (ppc750 + ppc7400) is proven to work by QuakeSpasm.
#
# ⚠️ v0 DRAFT — depends on build.sh, which is itself unvalidated. See
#    KICKOFF_PROMPT.md. Validate the g4 (10.4u) slice first; it is the most
#    likely to compile cleanly, then g3, then lion.
#
set -euo pipefail

BUILD_HOST="${BUILD_HOST:-mini-intel}"
PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$PROJ_LOCAL/build"

# Serialize the three slices (build.sh flocks anyway; this just sequences them).
for T in g3 g4 lion; do
  echo "############ building slice: $T ############"
  "$HERE/build.sh" "$T"
done

for T in g3 g4 lion; do
  test -f "$OUT/ioquake3-$T" || { echo "build-fat.sh: missing slice build/ioquake3-$T"; exit 1; }
done

echo "==> lipo on $BUILD_HOST (no lipo on Linux)"
scp -q "$OUT/ioquake3-g3" "$OUT/ioquake3-g4" "$OUT/ioquake3-lion" "$BUILD_HOST:/tmp/"
ssh "$BUILD_HOST" "cd /tmp
  lipo -create ioquake3-g3 ioquake3-g4 ioquake3-lion -output ioquake3-fat
  lipo -info ioquake3-fat"
scp -q "$BUILD_HOST:/tmp/ioquake3-fat" "$OUT/ioquake3-fat"
ssh "$BUILD_HOST" "rm -f /tmp/ioquake3-g3 /tmp/ioquake3-g4 /tmp/ioquake3-lion /tmp/ioquake3-fat"

echo "==> fat binary -> build/ioquake3-fat"
file "$OUT/ioquake3-fat" | sed 's/^/    /'
