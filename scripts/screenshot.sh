#!/usr/bin/env bash
# Capture a bank of in-game ioquake3 screenshots from a deployed target.
#
# How it works:
#   1. Stage autoshot.cfg in baseq3/ that runs `wait`*N + screenshotJPEG, ×N,
#      then quit. Putting the chain in a cfg (not on the cmdline) avoids the
#      engine's +argv cap.
#   2. Launch with `+set timedemo 1 +demo four +exec autoshot.cfg`. Timedemo
#      removes the realtime gate, so the demo plays one frame per Com_Frame
#      iteration and each `wait` maps 1:1 to a demo frame.
#   3. scp the JPEGs back into docs/screenshots/q3-<machine>-NN.jpg.
#
# usage: scripts/screenshot.sh <machine> [demo] [count]
#   machine: yosemite|sawtooth|quicksilver|mini-g4|imac-g5|mini-intel|imac-2019|qemu-tiger3d
#   VM output: ~/oldmac/evidence/quake3/screenshots-<UTC>/ (host framebuffer PNGs)
#   demo:    four (default)
#   count:   number of shots (default 8)
# output: docs/screenshots/q3-<machine>-NN.jpg
#
# Capture is at 1024x768 fullscreen on most boxes, but the iMac G5 captures at
# its NATIVE 1440x900 (the only R300-safe fullscreen — a same-mode set). The cfg
# ends with a clean `quit` (not a hard kill), which is what makes fullscreen
# capture safe on the G5's Leopard/R300 driver.

set -euo pipefail
HOST="${1:?usage: $0 <machine> [demo] [count]}"

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
if [ "${RETRO_BENCH_LOCK:-}" != "$HOST" ] && [ "${BENCH_NO_LOCK:-0}" != 1 ] && [ -x "$_PICK" ]; then
	export RETRO_BENCH_LOCK="$HOST"
	exec "$_PICK" --run "$HOST" "screenshot" -- "$0" "$@"
fi
DEMO="${2:-four}"
COUNT="${3:-8}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2088
# tilde stays unexpanded on purpose: it must
# resolve on the REMOTE host's home, not this workstation's. See ci.yml.
REMOTE_DIR="/Applications/Quake3"

case "$HOST" in
  yosemite|yosemite-tiger|sawtooth|quicksilver|mini-g4|imac-g5|mini-intel|imac-2019|qemu-tiger3d) ;;
  *) echo "screenshot: unknown machine '$HOST'" >&2; exit 2 ;;
esac
case "$HOST" in
  yosemite|yosemite-tiger) TMO=300 ;; sawtooth|quicksilver|mini-g4) TMO=200 ;;
  imac-g5) TMO=120 ;; mini-intel) TMO=120 ;; imac-2019) TMO=90 ;;
  qemu-tiger3d) TMO=300 ;;  # QemuMac emulated G4 + Radeon 9700; fps/timing follows host load
esac

# Capture resolution. Default 1024x768 fullscreen for consistent dimensions.
# The iMac G5 captures at its NATIVE panel res (1440x900) — that is the only
# R300-safe fullscreen (a same-mode set, no mode switch) AND what the user wants
# the shots to show. Clean `quit` (in the cfg) exits without the hard kill that
# black-screens the R300, so native-res capture is safe.
SS_W=1024; SS_H=768
[ "$HOST" = imac-g5 ] && { SS_W=1440; SS_H=900; }

INITIAL=120          # boot + precache settle before the first shot
BETWEEN=120          # demo frames between shots

BUSY="$(ssh "$HOST" "ps ax 2>/dev/null | grep -iE 'ioquake3|quake3' | grep -v grep || true")"
if [ -n "$BUSY" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "[shot $HOST] ABORT — a game is already running (FORCE=1 to override)" >&2; exit 2
fi

# Guest glReadPixels is broken on the emulated R300 (qemu#7/#8).
# Keep the GUI's SSH session alive and let the demo exit through the engine.
if [ "$HOST" = qemu-tiger3d ]; then
  if ssh "$HOST" 'ps -axc -o ucomm | grep -E "^(xash3d|xash3d.bin|quakespasm|ioquake3|quake2|Aleph One) *$"'; then
    echo "A game is already running; quit it before capturing." >&2; exit 2
  fi
  case "$DEMO" in ''|*[!a-zA-Z0-9_]*) echo "invalid demo name" >&2; exit 2;; esac
  case "$COUNT" in ''|*[!0-9]*|0) echo "count must be positive" >&2; exit 2;; esac
  OUT="${SCREENSHOT_DIR:-$HOME/oldmac/evidence/quake3/screenshots-$(date -u +%Y%m%dT%H%M%SZ)}"
  mkdir -p "$OUT"
  RUN_HOME="/tmp/q3shot-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  ssh "$HOST" "mkdir -p '$RUN_HOME/baseq3'; cp '$REMOTE_DIR/baseq3/q3config.cfg' '$RUN_HOME/baseq3/'; : > '$RUN_HOME/game.log'"
  ssh "$HOST" "cd '$REMOTE_DIR' && exec ./ioquake3.app/Contents/MacOS/ioquake3 \
    +set fs_basepath '$REMOTE_DIR' +set fs_homepath '$RUN_HOME' \
    +set r_mode -1 +set r_customwidth 1024 +set r_customheight 768 +set r_fullscreen 1 \
    +set r_ext_compressed_textures 1 +set logfile 2 +set com_maxfps 60 +set timedemo 0 \
    +set nextdemo quit +demo '$DEMO' > '$RUN_HOME/game.log' 2>&1" &
  SESSION_PID=$!
  ready=0
  for ((i=0; i<TMO; i++)); do
    kill -0 "$SESSION_PID" 2>/dev/null || break
    if ssh "$HOST" "grep -q 'CL_InitCGame' '$RUN_HOME/baseq3/qconsole.log' 2>/dev/null"; then ready=1; break; fi
    sleep 1
  done
  n=0
  if [ "$ready" = 1 ]; then
    sleep 2
    while [ "$n" -lt "$COUNT" ] && kill -0 "$SESSION_PID" 2>/dev/null; do
      printf -v idx '%02d' "$n"
      "$REPO_ROOT/scripts/shared.sh" qemu-vm.sh screendump "$OUT/q3-$HOST-$idx.png"
      n=$((n+1))
      sleep 2
    done
  fi
  wait "$SESSION_PID"
  scp -q "$HOST:$RUN_HOME/baseq3/qconsole.log" "$OUT/qconsole.log"
  ssh "$HOST" "rm -rf '$RUN_HOME'"
  [ "$n" -gt 0 ] || { echo "No gameplay frames captured" >&2; exit 1; }
  echo "[shot $HOST] saved $n host framebuffer images -> $OUT; engine exited cleanly"
  exit 0
fi

# Build autoshot.cfg: wait, screenshotJPEG, repeated COUNT times, then quit.
CFG=$(mktemp)
{
  echo "set timedemo 1"
  echo "wait $INITIAL"
  for ((i=0; i<COUNT; i++)); do
    echo "screenshotJPEG"
    echo "wait $BETWEEN"
  done
  echo "quit"
} > "$CFG"

echo "[shot $HOST] staging autoshot.cfg ($COUNT shots, demo=$DEMO)"
ssh "$HOST" "mkdir -p $REMOTE_DIR/baseq3 && rm -rf $REMOTE_DIR/baseq3/screenshots && mkdir -p $REMOTE_DIR/baseq3/screenshots"
scp -q "$CFG" "$HOST:$REMOTE_DIR/baseq3/autoshot.cfg"
rm -f "$CFG"

echo "[shot $HOST] capturing (1024x768 fullscreen, timedemo)"
ssh "$HOST" "
  if killall -TERM ioquake3 2>/dev/null; then sleep 2; fi
  killall -KILL ioquake3 2>/dev/null || true
  sleep 1
  cd $REMOTE_DIR || exit 9
  ./ioquake3.app/Contents/MacOS/ioquake3 \\
    +set fs_basepath \"\$PWD\" +set fs_homepath \"\$PWD\" \\
    +set r_mode -1 +set r_customwidth $SS_W +set r_customheight $SS_H +set r_fullscreen 1 \\
    +set com_maxfps 0 +set timedemo 1 +demo $DEMO +exec autoshot.cfg > /dev/null 2>&1 &
  PID=\$!
  j=0
  while [ \$j -lt $TMO ]; do
    if ! kill -0 \$PID 2>/dev/null; then break; fi
    sleep 1; j=\$((j+1))
  done
  killall -TERM ioquake3 2>/dev/null; sleep 2; killall -KILL ioquake3 2>/dev/null || true
  rm -f baseq3/autoshot.cfg
  ls baseq3/screenshots/*.jpg 2>/dev/null | wc -l | tr -d ' '"

OUT="$REPO_ROOT/docs/screenshots"
mkdir -p "$OUT"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
scp -q "$HOST:$REMOTE_DIR/baseq3/screenshots/*.jpg" "$TMPD/" 2>/dev/null || { echo "[shot $HOST] FAIL: no screenshots produced" >&2; exit 1; }

n=0
for f in $(ls "$TMPD"/*.jpg 2>/dev/null | sort); do
  printf -v idx '%02d' "$n"
  cp "$f" "$OUT/q3-$HOST-$idx.jpg"
  n=$((n+1))
done
echo "[shot $HOST] saved $n screenshots -> $OUT/q3-$HOST-NN.jpg"

# Same direct-exec of the bundle binary as the bench scripts, same LaunchServices
# damage on Lion — repair it before we leave. See scripts/lsregister-app.sh.
"$(dirname "$0")/lsregister-app.sh" "$HOST" --quiet || true
