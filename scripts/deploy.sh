#!/usr/bin/env bash
#
# deploy.sh <machine> — ship the fat binary + per-machine config to a bench
# Mac. Quake III runs from ~/Desktop/quake3/ with baseq3/ alongside the
# binary (no .app needed for benching). Adapted from ~/quakespasm/scripts.
#
# ⚠️ v0 DRAFT. Game data (baseq3/*.pk3) currently lives ONLY on mini-intel
#    (the machine with Q3 installed). Other machines need baseq3 copied to
#    them before benching — see scripts/distribute-data.sh / KICKOFF_PROMPT.md.
#    An .app bundle (icon, Info.plist, SDL framework) is a later nicety.
#
set -euo pipefail

MACHINE="${1:?usage: deploy.sh <yosemite|sawtooth|quicksilver|mini-g4|mini-intel|imac-2019|imac-g5>}"
PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
FAT="$PROJ_LOCAL/build/ioquake3-fat"
SDL_DYLIB="$PROJ_LOCAL/code/libs/macosx/libSDL-1.2.0.dylib"
BUNDLE="$PROJ_LOCAL/scripts/bundle"
APP="$PROJ_LOCAL/build/ioquake3.app"
SBB="$BUNDLE/set-bundle-bit"     # fat (ppc+x86_64) Finder bundle-bit setter
REMOTE_DIR="~/Desktop/quake3"

case "$MACHINE" in
  yosemite|sawtooth|quicksilver|mini-g4|mini-intel|imac-2019|imac-g5) ;;
  *) echo "deploy.sh: unknown machine '$MACHINE'"; exit 2 ;;
esac
test -f "$FAT" || { echo "deploy.sh: build/ioquake3-fat missing — run build-fat.sh first"; exit 1; }
test -f "$SDL_DYLIB" || { echo "deploy.sh: $SDL_DYLIB missing"; exit 1; }

RSYNC_EXTRA=""
[ "$MACHINE" = yosemite ] && RSYNC_EXTRA="--protocol=29"   # Panther rsync is 2.5.x

echo "==> [$MACHINE] ensure remote dir + check for game data"
ssh "$MACHINE" "mkdir -p $REMOTE_DIR/baseq3
  n=\$(ls $REMOTE_DIR/baseq3/*.[pP][kK]3 2>/dev/null | wc -l | tr -d ' ')
  echo \"    baseq3 pk3s present: \$n\"
  [ \"\$n\" -ge 1 ] || echo '    ⚠️  no game data here yet — copy baseq3 pk3s before benching'"

echo "==> [$MACHINE] ship fat binary -> $REMOTE_DIR/ioquake3"
# --checksum: size+mtime can miss a stale binary on these machines.
rsync -av --partial --checksum $RSYNC_EXTRA "$FAT" "$MACHINE:$REMOTE_DIR/ioquake3"
ssh "$MACHINE" "chmod +x $REMOTE_DIR/ioquake3"

echo "==> [$MACHINE] ship SDL 1.2 dylib -> $REMOTE_DIR/libSDL-1.2.0.dylib"
# The binary links @executable_path/libSDL-1.2.0.dylib; the fat dylib (ppc +
# x86_64 + i386) must sit next to it. dyld picks the matching slice at runtime.
rsync -av --partial --checksum $RSYNC_EXTRA "$SDL_DYLIB" "$MACHINE:$REMOTE_DIR/libSDL-1.2.0.dylib"

if [ -f "$BUNDLE/autoexec-$MACHINE.cfg" ]; then
  echo "==> [$MACHINE] stage per-machine autoexec.cfg"
  rsync -av --checksum $RSYNC_EXTRA "$BUNDLE/autoexec-$MACHINE.cfg" \
    "$MACHINE:$REMOTE_DIR/baseq3/autoexec.cfg"
else
  echo "    (no scripts/bundle/autoexec-$MACHINE.cfg — skipping config)"
fi

# --- ioquake3.app bundle (icon + double-click play) ---------------------------
# One fat-binary .app per machine. Sits at ~/Desktop/quake3/ioquake3.app; ioquake3
# strips the bundle path (Sys_StripAppBundle) so fs_basepath = ~/Desktop/quake3,
# finding the baseq3/ alongside. The raw ./ioquake3 above is kept for bench.sh.
"$HERE/make-app.sh" >/dev/null
echo "==> [$MACHINE] ship ioquake3.app -> $REMOTE_DIR/ioquake3.app"
rsync -a --delete --partial --checksum $RSYNC_EXTRA "$APP/" "$MACHINE:$REMOTE_DIR/ioquake3.app/"
ssh "$MACHINE" "chmod +x $REMOTE_DIR/ioquake3.app/Contents/MacOS/ioquake3"

if [ -f "$SBB" ]; then
  echo "==> [$MACHINE] set Finder bundle bit (so the .app shows the icon, not a folder)"
  rsync -a --partial $RSYNC_EXTRA "$SBB" "$MACHINE:$REMOTE_DIR/.set-bundle-bit"
  ssh "$MACHINE" "chmod +x $REMOTE_DIR/.set-bundle-bit && $REMOTE_DIR/.set-bundle-bit $REMOTE_DIR/ioquake3.app 2>&1 | sed 's/^/    /' || echo '    (bundle-bit set failed — non-fatal)'"
fi

echo "==> [$MACHINE] verify"
ssh "$MACHINE" "cd $REMOTE_DIR && file ioquake3 | sed 's/^/    /' && echo '    app binary:' && file ioquake3.app/Contents/MacOS/ioquake3 | sed 's/^/    /' && ls -la baseq3/autoexec.cfg 2>/dev/null"
echo "==> [$MACHINE] deployed."
