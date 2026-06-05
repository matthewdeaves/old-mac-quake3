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
#   machine: yosemite|sawtooth|quicksilver|mini-g4|imac-g5|mini-intel|imac-2019
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
DEMO="${2:-four}"
COUNT="${3:-8}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_DIR="~/Desktop/quake3"

case "$HOST" in
  yosemite|sawtooth|quicksilver|mini-g4|imac-g5|mini-intel|imac-2019) ;;
  *) echo "screenshot: unknown machine '$HOST'" >&2; exit 2 ;;
esac
case "$HOST" in
  yosemite) TMO=300 ;; sawtooth|quicksilver|mini-g4) TMO=200 ;;
  imac-g5) TMO=120 ;; mini-intel) TMO=120 ;; imac-2019) TMO=90 ;;
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

BUSY="$(ssh "$HOST" "ps -axo comm 2>/dev/null | grep -iE 'ioquake3|quake3' | grep -v grep || true")"
if [ -n "$BUSY" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "[shot $HOST] ABORT — a game is already running (FORCE=1 to override)" >&2; exit 2
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
scp -q "$CFG" "$HOST:Desktop/quake3/baseq3/autoshot.cfg"
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
TMPD=$(mktemp -d); trap "rm -rf '$TMPD'" EXIT
scp -q "$HOST:Desktop/quake3/baseq3/screenshots/*.jpg" "$TMPD/" 2>/dev/null || { echo "[shot $HOST] FAIL: no screenshots produced" >&2; exit 1; }

n=0
for f in $(ls "$TMPD"/*.jpg 2>/dev/null | sort); do
  printf -v idx '%02d' "$n"
  cp "$f" "$OUT/q3-$HOST-$idx.jpg"
  n=$((n+1))
done
echo "[shot $HOST] saved $n screenshots -> $OUT/q3-$HOST-NN.jpg"
