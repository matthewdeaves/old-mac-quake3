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
	exec "$_PICK" --run "$HOST" "smoke-dmg" -- "$0" "$@"
fi
DEMO="${2:-four}"
REMOTE_DIR="~/Desktop/quake3"

case "$HOST" in
  yosemite|yosemite-tiger) TIMEOUT=300; COOLDOWN=5 ;;
  sawtooth)    TIMEOUT=240; COOLDOWN=3 ;;
  quicksilver) TIMEOUT=180; COOLDOWN=2 ;;
  mini-g4)     TIMEOUT=180; COOLDOWN=2 ;;
  imac-g5)     TIMEOUT=90;  COOLDOWN=2 ;;
  mini-intel)  TIMEOUT=90;  COOLDOWN=1 ;;
  imac-2019)   TIMEOUT=60;  COOLDOWN=1 ;;
  g5-desktop|g5-tiger|g5-panther|quad-leopard|quad-tiger)
               TIMEOUT=120; COOLDOWN=2 ;;
  mini-intel2) TIMEOUT=90;  COOLDOWN=1 ;;
  # Back to 90. This was briefly raised to 180 as a workaround for mini-sl
  # timing out, before the cause was known: that machine has NO DISPLAY
  # ATTACHED, so its GeForce 9400M gives no accelerated context and the engine
  # binds the Apple Software Renderer. No timeout fixes that, and carrying a
  # workaround that does not work only hides the real fault. See #28, and the
  # headless pre-flight check below which now names it. Issue #28.
  mini-sl)     TIMEOUT=90;  COOLDOWN=1 ;;
  *) echo "smoke-dmg: unknown machine: $HOST" >&2; exit 2 ;;
esac

# Both are overridable. The per-machine defaults are tuned for the demo each
# port uses at that machine's production settings, and a slower demo, a
# heavier config or a busy box can exceed them. When that happens the run is
# reported as a crash or hang, which is a much more alarming thing than the
# truth, and it leaves the engine still running for the NEXT run to trip over.
TIMEOUT="${SMOKE_TIMEOUT:-$TIMEOUT}"
COOLDOWN="${SMOKE_COOLDOWN:-$COOLDOWN}"

# HEADLESS CHECK. A Mac with no display attached cannot be smoke-tested
# meaningfully, and the way it fails is deeply misleading: this script reported
# "the production launch did not render a demo (crash or hang)" for two machines
# that were doing nothing of the kind.
#
# Measured 2026-08-23 (#28, #30). With no monitor:
#   mini-sl    GeForce 9400M present and driver loaded, but no accelerated
#              context, so the engine binds GL_RENDERER: Apple Software Renderer
#              and cannot finish a timedemo at any timeout.
#   mini-intel binds hardware GL but has no real display mode, so a 1920x1080
#              fullscreen request falls back to 640 x 480 and never completes.
# Two presentations, one cause, and neither is a crash.
#
# KEYED ON IODisplayConnect, NOT ON EDID, and that distinction is the whole
# check. The first version of this counted IODisplayEDID, which looked right
# because a real monitor supplies EDID. It is wrong on PowerPC: measured across
# the fleet on 2026-08-23,
#
#     machine      EDID  connect   renders?
#     yosemite       0      6      YES, benched and screenshotted all night
#     mini-g4        1      5      yes
#     g5-desktop     1      6      yes
#     mini-sl        0      1      no, software renderer
#     mini-intel     0      1      no, 640x480 fallback
#
# so EDID=0 would have warned "no display attached" on the G3 every single run,
# on the oldest and most awkward machine in the fleet, which is exactly where a
# spurious warning does most damage. Confirmed by running it: it did.
# INFERRED, not measured: the G3 probably drives an analog display, or its
# driver never publishes EDID.
#
# WHAT THIS TEST IS AND IS NOT. It is measured to separate two headless Intel
# minis from three working machines (one G3, one G4, one G5). connect<=1 has
# only ever been observed on those two, both the same class, so treat it as a
# useful signal rather than a law and do not apply it to untested hardware and
# believe the answer.
#
# WARN, do not refuse. mini-intel does bind hardware GL while headless, and a
# gate that refused a machine somebody had just plugged a monitor into would be
# worse than the confusion it prevents.
#
# `|| true` is load-bearing: grep -c EXITS 1 WHEN THE COUNT IS ZERO, which is
# precisely the headless case this check exists to catch. Without it, under
# set -euo pipefail, the assignment fails and the script dies silently with no
# output at all. The first version did exactly that, on the two machines it was
# written to diagnose.
# IODisplayConnect is confirmed present on 10.3.9: yosemite reports 6. That
# matters because the key this check ORIGINALLY used does not exist there at all
# -- Panther's ioreg has no IODisplayEDID key, so the count was 0 for a reason
# that had nothing to do with displays. Before reading a count as a measurement,
# prove the key exists on that OS version; this fleet spans 10.3 to 10.7 and a
# probe written against Lion returns confident zeros from Panther.
#
# An empty result means the probe could not run, which is NOT the same as zero,
# and must never be reported as "headless".
DCONNECT="$(ssh "$HOST" 'ioreg -lw0 2>/dev/null | grep -c IODisplayConnect || true' 2>/dev/null | tr -dc '0-9' || true)"
if [ -z "$DCONNECT" ]; then
  HEADLESS=0
  echo "[smoke $HOST] note: display probe did not answer; headless state NOT DETERMINED." >&2
elif [ "$DCONNECT" -le 1 ] 2>/dev/null; then
  HEADLESS=1
  echo "[smoke $HOST] WARNING: looks headless (IODisplayConnect=$DCONNECT)." >&2
  echo "  A Mac with no display cannot give a real fullscreen mode and may bind" >&2
  echo "  the software renderer. If this run fails, suspect that before the" >&2
  echo "  build. See issues #28 and #30." >&2
else
  HEADLESS=0
fi

# The bench fleet is SHARED. Launching a second fullscreen game on a box already
# running one wedges both. Bail if anything Quake-ish is live; FORCE=1 overrides.
# `ps ax`, NOT `ps -axo comm,pid`: the latter returns EMPTY on Tiger (unsupported
# option combination), so this guard silently never fired on the machines that
# needed it most — it would happily start a second fullscreen engine.
BUSY="$(ssh "$HOST" "ps ax 2>/dev/null | grep -iE 'ioquake3|quakespasm|quake2|/quake' | grep -v grep || true")"
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

# This script just exec'd the bundle's binary directly, which on Lion leaves the
# LaunchServices record with a blank executable path and breaks double-click.
# MEASURED here: one smoke run flipped a good record to blank. Repair on the way
# out, on both the pass and fail paths — a smoke test must not leave the machine
# less launchable than it found it. See scripts/lsregister-app.sh.
"$(dirname "$0")/lsregister-app.sh" "$HOST" || true

if [ -n "$FPS_LINE" ]; then
  echo "[smoke $HOST] PASS — world rendered to completion on the production path"
  exit 0
else
  if [ "${HEADLESS:-0}" = 1 ]; then
  echo "[smoke $HOST] FAIL — no fps line, and this machine has NO DISPLAY ATTACHED."
  echo "  That is the likely cause: see #28 and #30. Not necessarily a build fault."
else
  echo "[smoke $HOST] FAIL — no fps line; the production launch did not render a demo (crash or hang)"
fi >&2
  exit 1
fi
