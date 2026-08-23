#!/usr/bin/env bash
#
# deploy.sh <machine> — ship the fat binary + per-machine config to a bench
# Mac. Quake III runs from ~/Desktop/quake3/ with baseq3/ alongside the
# binary (no .app needed for benching). Adapted from ~/quakespasm/scripts.
#
# Game data (baseq3/*.pk3) is NOT shipped by this script — it originates on
# mini-intel (the machine with Q3 installed) and is copied to a bench machine by
# scripts/distribute-data.sh. This script checks how many pk3s are present and
# warns if there are none (see the presence check below), rather than deploying
# them itself. The .app bundle (icon, Info.plist, fat binary) is built by
# make-app.sh and IS deployed here alongside the raw binary that bench.sh uses.
#
set -euo pipefail

# `yosemite-tiger` is the SAME Power Mac G3 as `yosemite`, booted from its second
# partition (10.4.11 instead of 10.3.9) — one IP, one OS at a time. It exists so a
# G3-on-Tiger run can be deployed and benched without editing host lists.
MACHINE="${1:?usage: deploy.sh <yosemite|yosemite-tiger|sawtooth|quicksilver|mini-g4|mini-intel|imac-2019|imac-g5>}"

# Claim this machine for the whole run. See scripts/pick-bench-host.sh.
#
# Re-exec under the picker rather than acquire-here-and-trap: bash traps REPLACE
# rather than compose, so a release trap installed at the top of a script that
# later sets its own trap is silently discarded, and the machine stays claimed
# until the stale reclaim. `--run` makes the lock a property of the INVOCATION,
# so it is released however this exits, and no caller has to remember to do it.
#
# The lock lives on the target, so it serialises across repos, agents and
# workstations, not just this checkout. It also refuses a host booted into an OS
# its alias does not name, which the multi-boot machines otherwise allow.
#
# RETRO_BENCH_LOCK guards against the re-exec recursing.
# BENCH_NO_LOCK=1 skips the lock, for when the picker itself is what you are
# debugging. It is not a way to get past a machine someone else is using.
_PICK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pick-bench-host.sh"
# Compare RETRO_BENCH_LOCK to THIS script's target rather than merely testing
# that it is set. pick-bench-host.sh --run now exports it naming the claimed
# host, so a bare -z test would make this script skip its own claim whenever it
# runs inside any other claim, including one on a DIFFERENT machine. Same-host
# still skips, which is the reentrancy this guard is for.
if [ "${RETRO_BENCH_LOCK:-}" != "$MACHINE" ] && [ "${BENCH_NO_LOCK:-0}" != 1 ] && [ -x "$_PICK" ]; then
	export RETRO_BENCH_LOCK="$MACHINE"
	exec "$_PICK" --run "$MACHINE" "deploy" -- "$0" "$@"
fi
PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
FAT="$PROJ_LOCAL/build/ioquake3-fat"
SDL_DYLIB="$PROJ_LOCAL/code/libs/macosx/libSDL-1.2.0.dylib"
SDL2_DYLIB="$PROJ_LOCAL/code/libs/macosx/libSDL2-2.0.0.dylib"   # arm64 slice only
BUNDLE="$PROJ_LOCAL/scripts/bundle"
APP="$PROJ_LOCAL/build/ioquake3.app"
SBB="$BUNDLE/set-bundle-bit"     # fat (ppc+x86_64) Finder bundle-bit setter
# shellcheck disable=SC2088
# tilde stays unexpanded on purpose: it must
# resolve on the REMOTE host's home, not this workstation's. See ci.yml.
REMOTE_DIR="~/Desktop/quake3"

case "$MACHINE" in
  yosemite|yosemite-tiger|sawtooth|quicksilver|mini-g4|mini-intel|imac-2019|imac-g5) ;;
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

# NOT "ioquake3". Finder hides the .app extension, so a loose Mach-O called
# ioquake3 sitting beside ioquake3.app shows up as a SECOND thing called
# "ioquake3", with a generic Unix-executable icon. Only the bundle can be
# opened; double-clicking the loose one cannot work, and on 2026-07-26 that
# duplicate cost real time to rule out while chasing an unrelated launch bug.
# bench.sh wants a bare Mach-O it can exec over ssh, so the file still ships,
# under a name nobody will mistake for the game. Issue #10.
echo "==> [$MACHINE] ship fat binary -> $REMOTE_DIR/ioquake3-bench"
# --checksum: size+mtime can miss a stale binary on these machines.
rsync -av --partial --checksum $RSYNC_EXTRA "$FAT" "$MACHINE:$REMOTE_DIR/ioquake3-bench"
ssh "$MACHINE" "chmod +x $REMOTE_DIR/ioquake3-bench"
# Clear the old name if this machine was deployed to before the rename.
ssh "$MACHINE" "rm -f $REMOTE_DIR/ioquake3"

echo "==> [$MACHINE] ship SDL 1.2 dylib -> $REMOTE_DIR/libSDL-1.2.0.dylib"
# The binary links @executable_path/libSDL-1.2.0.dylib; the fat dylib (ppc +
# i386 + x86_64 + arm64) must sit next to it. dyld picks the matching slice at
# runtime. The first three members are genuine SDL 1.2; the arm64 one is
# sdl12-compat, because SDL 1.2 has no arm64 build. docs/adr/0017.
rsync -av --partial --checksum $RSYNC_EXTRA "$SDL_DYLIB" "$MACHINE:$REMOTE_DIR/libSDL-1.2.0.dylib"

# The shim dlopen()s a real SDL2 at runtime, "@loader_path/libSDL2-2.0.0.dylib"
# first, so ship ours beside the binary rather than leave it to find whatever is
# installed. Inert on PowerPC and Intel, which never open it.
if [ -f "$SDL2_DYLIB" ]; then
  echo "==> [$MACHINE] ship SDL2 dylib (for the arm64 slice) -> $REMOTE_DIR/libSDL2-2.0.0.dylib"
  rsync -av --partial --checksum $RSYNC_EXTRA "$SDL2_DYLIB" "$MACHINE:$REMOTE_DIR/libSDL2-2.0.0.dylib"
fi

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
# finding the baseq3/ alongside. The raw ./ioquake3-bench above is kept for bench.sh.
"$HERE/make-app.sh" >/dev/null
echo "==> [$MACHINE] ship ioquake3.app -> $REMOTE_DIR/ioquake3.app"
rsync -a --delete --partial --checksum $RSYNC_EXTRA "$APP/" "$MACHINE:$REMOTE_DIR/ioquake3.app/"
ssh "$MACHINE" "chmod +x $REMOTE_DIR/ioquake3.app/Contents/MacOS/ioquake3"

if [ -f "$SBB" ]; then
  echo "==> [$MACHINE] set Finder bundle bit (so the .app shows the icon, not a folder)"
  rsync -a --partial $RSYNC_EXTRA "$SBB" "$MACHINE:$REMOTE_DIR/.set-bundle-bit"
  ssh "$MACHINE" "chmod +x $REMOTE_DIR/.set-bundle-bit && $REMOTE_DIR/.set-bundle-bit $REMOTE_DIR/ioquake3.app 2>&1 | sed 's/^/    /' || echo '    (bundle-bit set failed — non-fatal)'"
fi

# --- re-register the bundle with LaunchServices -------------------------------
# Repair the target's LS record so the app still opens by DOUBLE-CLICK. Deploying
# is not what breaks it — direct-exec benching is (see lsregister-app.sh) — but a
# fresh bundle should still leave the machine in a launchable state, and this is
# the last point before someone might go and click it.
"$HERE/lsregister-app.sh" "$MACHINE" || true

echo "==> [$MACHINE] verify"
ssh "$MACHINE" "cd $REMOTE_DIR && file ioquake3-bench | sed 's/^/    /' && echo '    app binary:' && file ioquake3.app/Contents/MacOS/ioquake3 | sed 's/^/    /' && ls -la baseq3/autoexec.cfg 2>/dev/null"
echo "==> [$MACHINE] deployed."
