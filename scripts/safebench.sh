#!/usr/bin/env bash
#
# safebench.sh <machine> <WxH> [demo] [extra +set cvars] — SAFE timedemo.
#
# Why this exists: hard-killing a fullscreen ioquake3 mid mode-switch wedges the
# old GPUs. (Windowed mode can't be used here — an ssh-launched app with no Aqua
# session fails to create a window and exits early.) So this:
#   * runs FULLSCREEN at the given res — pass the machine's NATIVE desktop res so
#     it's a same-mode set (no actual mode switch = the only safe fullscreen),
#   * exits via a self-quitting cfg (wait -> quit) = clean shutdown, NO hard kill,
#   * watchdogs the run and, if the game hangs, TERMs it and — if the machine is
#     unresponsive — reboots it via ~/bin/qsreboot.sh so we never leave a wedge.
#
# Prints: "[machine WxH] <N> frames <S> seconds <F> fps ...".
set -uo pipefail
M="${1:?usage: safebench.sh <machine> <WxH> [demo] [extra +set...]}"
RES="${2:?need WxH}"; W=${RES%x*}; H=${RES#*x}
DEMO="${3:-four}"
EXTRA="${4:-}"
RDIR='~/Desktop/quake3'
SSHO="-o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3"

reachable() { ssh $SSHO "$M" 'true' 2>/dev/null; }
alive()     { ssh $SSHO "$M" "ps ax 2>/dev/null | grep -c '[i]oquake3'" 2>/dev/null; }
reboot_m()  { echo "[$M] REBOOTING via qsreboot.sh"; ssh $SSHO "$M" '~/bin/qsreboot.sh' 2>/dev/null || echo "[$M] reboot cmd failed"; }

reachable || { echo "[$M] unreachable"; exit 3; }

# gentle pre-clean of any stray game
ssh $SSHO "$M" "killall -TERM ioquake3 2>/dev/null; sleep 3; killall -KILL ioquake3 2>/dev/null; true" 2>/dev/null

# Proven measurement path: fullscreen timedemo from the cmdline (NO +exec self-
# quit — that quits before the demo and logs nothing). Poll the log for the fps
# line, then stop with TERM-grace (lets SDL restore the display) and KILL only as
# a backstop. At NATIVE res this is a same-mode set, so no display corruption.
ssh $SSHO "$M" "cd $RDIR; : > baseq3/qconsole.log
  ./ioquake3.app/Contents/MacOS/ioquake3 +set com_archAutoexec 0 +set fs_basepath \"\$PWD\" +set fs_homepath \"\$PWD\" \
    +set logfile 2 +set r_swapInterval 0 +set r_mode -1 +set r_customwidth $W +set r_customheight $H +set r_fullscreen 1 \
    $EXTRA +set timedemo 1 +demo $DEMO >/dev/null 2>&1 &
  true" 2>/dev/null

# poll for the fps line (demo finished) or the process dying
DEADLINE=${SAFEBENCH_TIMEOUT:-260}
fps=""
for ((t=0; t<DEADLINE; t+=4)); do
  sleep 4
  fps=$(ssh $SSHO "$M" "awk '/seconds .* fps/{print}' $RDIR/baseq3/qconsole.log 2>/dev/null | tail -1" 2>/dev/null)
  [ -n "$fps" ] && break
  a=$(alive); [ "${a:-X}" = 0 ] && break   # died early
done

# stop cleanly: TERM, wait out the grace, KILL only if still alive
ssh $SSHO "$M" "killall -TERM ioquake3 2>/dev/null" 2>/dev/null
for ((g=0; g<10; g++)); do sleep 1; [ "$(alive)" = 0 ] && break; done
[ "$(alive)" != 0 ] && ssh $SSHO "$M" "killall -KILL ioquake3 2>/dev/null" 2>/dev/null
sleep 2

# health check; reboot if wedged
if ! reachable; then
  echo "[$M $RES] ${fps:-NO-FPS} — host UNRESPONSIVE after run"; reboot_m; exit 1
fi
ncrash=$(ssh $SSHO "$M" "ls ~/Library/Logs/CrashReporter/ioquake3* 2>/dev/null | wc -l | tr -d ' '" 2>/dev/null)
echo "[$M $RES] ${fps:-NO-FPS-LINE}${ncrash:+  (crashlogs=$ncrash)}"
[ -n "$fps" ] && exit 0 || exit 1
