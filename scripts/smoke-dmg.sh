#!/usr/bin/env bash
# Smoke-test the DMG-installed copy of ioquake3 on a target Mac the way a human
# launches it: the per-machine production autoexec (baseq3/autoexec.cfg) drives
# the renderer — fullscreen, the machine's own resolution, full visual tune. We
# do NOT override vid/res (that's what bench.sh does for deterministic
# measurement). The only thing we add is a timedemo so the run AUTO-EXITS
# instead of sitting fullscreen forever — proof the world actually rendered (an
# fps line) on the real production path the corrupt-DMG class of bug slips past.
#
# usage: scripts/smoke-dmg.sh <machine> [demo]
#   machine: yosemite | sawtooth | quicksilver | mini-g4 | imac-g5 | mini-intel | imac-2019
#   demo:    four (default — the classic Q3 timedemo)
#
# After this passes, start a NEW GAME by hand: the timedemo proves world render
# + correct res but NOT the live-server/entity spawn path.

set -euo pipefail
HOST="${1:?usage: $0 <machine> [demo]}"
DEMO="${2:-four}"
REMOTE_DIR="~/Desktop/quake3"

case "$HOST" in
  yosemite)    TIMEOUT=300; COOLDOWN=5 ;;
  sawtooth)    TIMEOUT=240; COOLDOWN=3 ;;
  quicksilver) TIMEOUT=180; COOLDOWN=2 ;;
  mini-g4)     TIMEOUT=180; COOLDOWN=2 ;;
  imac-g5)     TIMEOUT=90;  COOLDOWN=2 ;;
  mini-intel)  TIMEOUT=90;  COOLDOWN=1 ;;
  imac-2019)   TIMEOUT=60;  COOLDOWN=1 ;;
  *) echo "smoke-dmg: unknown machine: $HOST" >&2; exit 2 ;;
esac

# The bench fleet is SHARED. Launching a second fullscreen game on a box already
# running one wedges both. Bail if anything Quake-ish is live; FORCE=1 overrides.
BUSY="$(ssh "$HOST" "ps -axo comm,pid 2>/dev/null | grep -iE 'ioquake3|quake3|quakespasm|quake2|/quake' | grep -v grep || true")"
if [ -n "$BUSY" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "[smoke $HOST] ABORT — $HOST is already running a game (shared bench):" >&2
  echo "$BUSY" | sed 's/^/    /' >&2
  echo "[smoke $HOST] wait for it to finish, or re-run with FORCE=1 if it is stale." >&2
  exit 2
fi

echo "[smoke $HOST] launching DMG-installed ioquake3.app with PRODUCTION config (as a human would), demo=$DEMO"
# Production launch — no vid/res override, so baseq3/autoexec.cfg drives the
# renderer. We force fs_homepath to the install dir so qconsole.log + q3config
# match the on-disk layout the player uses (and so the log is where we read it).
# +set timedemo is an early command; +demo runs after CL_Init, so the demo plays
# in the machine's production fullscreen mode.
#
# CRITICAL — make the engine QUIT ITSELF; never KILL a fullscreen app. We add
# +set nextdemo quit so CL_DemoCompleted runs 'quit' after the timedemo and the
# engine exits the NORMAL way (SDL restores the captured display, pid removed).
# A hard KILL on a still-fullscreen ioquake3 wedges the GPU driver / WindowServer
# until a reboot (this bit the fleet repeatedly — R300 G4 + GMA950 Lion). So the
# only backstop here is a gentle TERM if it somehow never self-quits; NEVER KILL.
# A stale pid file pops an "Abnormal Exit" modal that hangs headless — rm it first.
PIDF='$HOME/Library/Application Support/Quake3/ioq3.pid'
ssh "$HOST" "
  killall -TERM ioquake3 2>/dev/null && sleep 2
  cd $REMOTE_DIR || { echo 'NO_INSTALL'; exit 9; }
  rm -f baseq3/qconsole.log \"$PIDF\"
  ./ioquake3.app/Contents/MacOS/ioquake3 \\
    +set fs_basepath \"\$PWD\" +set fs_homepath \"\$PWD\" \\
    +set logfile 2 +set nextdemo quit +set timedemo 1 +demo $DEMO > /dev/null 2>&1 &
  # wait for the engine to self-quit (process gone) or error out; self-bounded
  j=0
  while [ \$j -lt $TIMEOUT ]; do
    killall -0 ioquake3 2>/dev/null || break            # self-quit = clean exit
    grep -qE 'ERROR:|Error:' baseq3/qconsole.log 2>/dev/null && break
    sleep 1; j=\$((j+1))
  done
  # backstop ONLY if it didn't self-quit: a gentle TERM (handler restores the
  # display). NEVER KILL a fullscreen ioquake3 — that wedges the GPU driver.
  if killall -0 ioquake3 2>/dev/null; then
    killall -TERM ioquake3 2>/dev/null
    g=0; while [ \$g -lt 12 ]; do killall -0 ioquake3 2>/dev/null || break; sleep 1; g=\$((g+1)); done
  fi
  rm -f \"$PIDF\"
  sleep $COOLDOWN
  true"

# Pull the log and report.
TMP=$(mktemp)
scp -q "$HOST:Desktop/quake3/baseq3/qconsole.log" "$TMP" 2>/dev/null || { echo "[smoke $HOST] FAIL: no qconsole.log (engine never wrote one)"; rm -f "$TMP"; exit 1; }

FPS_LINE=$(grep -E 'frames.*seconds.*fps' "$TMP" 2>/dev/null | tail -1 || true)
MODE_LINE=$(grep -iE 'GL_RENDERER|Initializing OpenGL|setting mode|MODE:' "$TMP" 2>/dev/null | tail -2 | tr '\n' ' ' || true)
rm -f "$TMP"

echo "[smoke $HOST] renderer : ${MODE_LINE:-<none>}"
echo "[smoke $HOST] result   : ${FPS_LINE:-<NO FPS LINE>}"

if [ -n "$FPS_LINE" ]; then
  echo "[smoke $HOST] PASS — world rendered to completion on the production path"
  exit 0
else
  echo "[smoke $HOST] FAIL — no fps line; the production launch did not render a demo (crash or hang)" >&2
  exit 1
fi
