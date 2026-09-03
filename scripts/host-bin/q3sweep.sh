#!/bin/sh
#
# q3sweep.sh - run one ioquake3 timedemo ON THIS MACHINE and print the fps line.
#
# Lives on the bench box, not on the orchestrator. Everything here is
# Panther-safe /bin/sh: no bash, no `ps -A` (10.3 has only `ps ax`), no
# `grep -o`, no `seq`, no `timeout`.
#
# usage:  q3sweep.sh [cvar args...]
#   e.g.  q3sweep.sh +set r_picmip 2 +set r_subdivisions 20
#
# Prints one line, either the engine's timedemo result or NORESULT plus the
# last thing the log said, so a failed sweep row is still diagnosable.
#
# env:
#   Q3DIR   game dir            (default $HOME/quake3-play)
#   Q3DEMO  demo name           (default four)
#   Q3W/Q3H resolution          (default 800x600)
#   Q3FS    1 = fullscreen      (default 0, windowed: a mode switch is the one
#                                thing that can wedge a machine's display, and a
#                                sweep runs dozens of times unattended)
#   Q3WAIT  seconds to wait     (default 600; the G3 needs ~90s per run and a
#                                heavy setting can take several times that)
#
# The engine is stopped by killing it, which leaves a stale PID file. Upstream
# reacts to that with a modal "did not exit properly" dialog on the NEXT launch,
# which blocks forever with nobody to click it and makes every subsequent row
# read NORESULT. This port prints a warning instead (see qcommon/common.c), and
# this script removes the file anyway so an older build still sweeps cleanly.
#
set -u

Q3DIR="${Q3DIR:-$HOME/quake3-play}"
Q3DEMO="${Q3DEMO:-four}"
Q3W="${Q3W:-800}"
Q3H="${Q3H:-600}"
Q3FS="${Q3FS:-0}"
Q3WAIT="${Q3WAIT:-600}"

cd "$Q3DIR" || { echo "NORESULT no such dir: $Q3DIR"; exit 1; }

APP="./ioquake3.app/Contents/MacOS/ioquake3"
[ -x "$APP" ] || { echo "NORESULT no engine at $APP"; exit 1; }

LOG="$Q3DIR/baseq3/qconsole.log"

# Clear anything left by a previous row before launching, not after: a stale
# PID file or an old log is exactly what makes a good run look like a bad one.
rm -f "$LOG" "$Q3DIR"/*.pid "$HOME/Library/Application Support/Quake3"/*.pid 2>/dev/null
for p in `ps ax | grep ioquake3 | grep -v grep | awk '{print $1}'`; do
  kill -9 "$p" 2>/dev/null
done

# com_archAutoexec 0: the per-machine autoexec would overwrite the very cvars a
# sweep exists to vary, and it does it AFTER the command line is applied.
$APP +set fs_basepath "$Q3DIR" +set fs_homepath "$Q3DIR" \
     +set logfile 2 +set com_archAutoexec 0 \
     +set r_fullscreen "$Q3FS" +set r_mode -1 \
     +set r_customwidth "$Q3W" +set r_customheight "$Q3H" \
     +set com_maxfps 0 \
     "$@" \
     +set nextdemo quit +set timedemo 1 +demo "$Q3DEMO" >/dev/null 2>&1 &
ENGINE=$!

elapsed=0
while [ "$elapsed" -lt "$Q3WAIT" ]; do
  if grep fps "$LOG" >/dev/null 2>&1; then break; fi
  # Stop early if the engine died rather than waiting out the full budget.
  kill -0 "$ENGINE" 2>/dev/null || break
  sleep 5
  elapsed=`expr $elapsed + 5`
done
sleep 2

for p in `ps ax | grep ioquake3 | grep -v grep | awk '{print $1}'`; do
  kill -9 "$p" 2>/dev/null
done

RESULT=`grep fps "$LOG" 2>/dev/null | tail -1`
if [ -n "$RESULT" ]; then
  echo "$RESULT"
else
  echo "NORESULT after ${elapsed}s | last: `tail -1 \"$LOG\" 2>/dev/null`"
fi
