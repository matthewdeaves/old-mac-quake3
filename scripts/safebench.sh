#!/usr/bin/env bash
#
# safebench.sh <machine> <WxH> [demo] [extra +set cvars] — SAFE timedemo.
#
# Runs one fullscreen timedemo on a bench machine over ssh and prints its fps,
# launching AND cleanly shutting the engine down before it returns — you should
# never have to quit the game by hand.
#
# The hard-won shape of this (see docs/HANDOFF-2026-06-29.md "Session update"):
#
#   * ONE ssh session does everything. The engine is BACKGROUNDED (&) but the
#     same session then stays alive polling the log — this is load-bearing. An
#     app whose launching ssh RETURNS immediately loses its Mach bootstrap /
#     WindowServer session and dies with "CFMessagePortCreateLocal failed"
#     before it can even open the display. Keeping the session open (the poll
#     loop) is what lets it render. (This is exactly how the QuakeSpasm port
#     benches.)
#   * NATIVE res only. Pass the machine's native desktop res so fullscreen is a
#     same-mode set (no real mode switch) — the only safe fullscreen on the old
#     Rage 128 / GeForce2 GPUs, which corrupt their LUT on a hard-killed switch.
#   * Clean shutdown via the ENGINE quitting ITSELF: `+set nextdemo quit`. When a
#     timedemo finishes, CL_DemoCompleted() prints the fps line then runs the
#     `nextdemo` cvar as a command (cl_main.c) — so the engine executes `quit` and
#     exits the NORMAL way: SDL restores the display, the pid file is removed, no
#     signal is ever sent. This is the whole game — KILLing a fullscreen ioquake3
#     wedges it in uninterruptible GPU-driver exit (hangs the display until a hard
#     reset). We therefore only TERM/KILL as a LAST-RESORT backstop if self-quit
#     never happens, and NEVER `wait` on the pid.
#   * killall -0 (not `ps | grep`) for existence checks — killall matches the
#     process NAME (ioquake3), so it never false-matches our own shell's argv.
#   * Stale pid file cleanup. Any un-clean prior exit (SIGKILL/SIGPIPE/wedge)
#     leaves ~/Library/Application Support/Quake3/ioq3.pid; the next launch then
#     pops a modal "Abnormal Exit — safe video settings?" dialog (common.c) that
#     BLOCKS forever headless. We rm it before every launch.
#   * The remote block is SELF-BOUNDING (its own poll counter) so a stuck run
#     can't orphan a remote shell even if the host-side `timeout` backstop fires.
#
# Prints: "[machine WxH] <N> frames <S> seconds <F> fps ...".
set -uo pipefail
M="${1:?usage: safebench.sh <machine> <WxH> [demo] [extra +set...]}"
RES="${2:?need WxH}"; W=${RES%x*}; H=${RES#*x}
DEMO="${3:-four}"
EXTRA="${4:-}"
RDIR='~/Desktop/quake3'
PIDF='$HOME/Library/Application Support/Quake3/ioq3.pid'
SSHO="-o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
DEADLINE=${SAFEBENCH_TIMEOUT:-260}          # per-run wall-clock budget (seconds)

reachable() { ssh $SSHO "$M" 'true' 2>/dev/null; }
# Reboot and VERIFY it actually cycles — qsreboot.sh's Finder fallback can report
# a false success without the machine ever going down, so we confirm it drops off
# the network and returns rather than trusting the exit code.
reboot_m()  {
  echo "[$M] REBOOTING via qsreboot.sh (verifying it cycles)"
  ssh $SSHO "$M" '~/bin/qsreboot.sh' 2>/dev/null || true
  local t=0
  while [ $t -lt 60 ]; do ssh $SSHO "$M" true 2>/dev/null || break; sleep 5; t=$((t+5)); done
  if [ $t -ge 60 ]; then echo "[$M] did NOT go down — reboot FAILED (run 'sudo ~/bin/qsreboot-setup.sh')"; return 1; fi
  t=0; while [ $t -lt 240 ]; do ssh $SSHO "$M" true 2>/dev/null && { echo "[$M] back up"; return 0; }; sleep 5; t=$((t+5)); done
  echo "[$M] did not come back within 240s"; return 1
}

reachable || { echo "[$M] unreachable"; exit 3; }

# One ssh session does it all: pre-clean, launch backgrounded (the session stays
# alive via the poll loop, so the app keeps its WindowServer session and renders),
# let the engine SELF-QUIT via nextdemo=quit, then read the fps off the on-disk log
# (logfile 2 is line-flushed). Self-bounding: the poll is an integer counter
# (Panther's /bin/sleep is integer-only). Host-side `timeout` is a last backstop.
out=$(timeout "$DEADLINE" ssh $SSHO "$M" "
  cd $RDIR || exit 9
  # gentle pre-clean: TERM any stray + clear the stale pid/log. No KILL here — a
  # wedged fullscreen app won't die cleanly to KILL, and the health check reboots
  # if anything is still stuck.
  killall -TERM ioquake3 2>/dev/null; sleep 2
  rm -f \"$PIDF\" baseq3/qconsole.log

  # nextdemo=quit → when the timedemo finishes, CL_DemoCompleted prints the fps
  # line and runs 'quit', so the engine exits the NORMAL way (SDL restores the
  # display, pid removed). No signal is ever sent to a rendering fullscreen app.
  ./ioquake3.app/Contents/MacOS/ioquake3 +set com_archAutoexec 0 \
    +set fs_basepath \"\$PWD\" +set fs_homepath \"\$PWD\" +set logfile 2 \
    +set r_swapInterval 0 +set r_mode -1 +set r_customwidth $W +set r_customheight $H +set r_fullscreen 1 \
    $EXTRA +set nextdemo quit +set timedemo 1 +demo $DEMO >/dev/null 2>&1 &

  # wait for the engine to self-quit (process gone) or error out; self-bounded
  budget=\$(( $DEADLINE - 25 )); j=0
  while [ \$j -lt \$budget ]; do
    killall -0 ioquake3 2>/dev/null || break            # self-quit = clean exit
    if grep -qE 'ERROR:|Error:' baseq3/qconsole.log 2>/dev/null; then break; fi
    sleep 1; j=\$((j+1))
  done

  # backstop ONLY if it didn't self-quit: a gentle TERM (handler restores the
  # display). NEVER KILL a fullscreen ioquake3 — that wedges the GPU driver.
  if killall -0 ioquake3 2>/dev/null; then
    killall -TERM ioquake3 2>/dev/null
    g=0; while [ \$g -lt 12 ]; do killall -0 ioquake3 2>/dev/null || break; sleep 1; g=\$((g+1)); done
  fi
  rm -f \"$PIDF\"

  echo \"FPSLINE:\$(grep -E 'seconds .*fps' baseq3/qconsole.log 2>/dev/null | tail -1)\"
  killall -0 ioquake3 2>/dev/null && echo 'STUCK:1' || echo 'STUCK:0'
" 2>/dev/null)

fps=$(printf '%s\n' "$out" | sed -n 's/^FPSLINE://p' | tail -1)
stuck=$(printf '%s\n' "$out" | sed -n 's/^STUCK://p' | tail -1)
sleep 1

# health check; a machine that went unresponsive or left a stuck (driver-wedged)
# engine gets rebooted so we never leave the fleet in a bad state.
if ! reachable; then
  echo "[$M $RES] ${fps:-NO-FPS} — host UNRESPONSIVE after run"; reboot_m; exit 1
fi
if [ "${stuck:-0}" = 1 ]; then
  echo "[$M $RES] ${fps:-NO-FPS} — engine STUCK in exit (GPU-driver wedge); rebooting"; reboot_m; exit 1
fi
ncrash=$(ssh $SSHO "$M" "ls ~/Library/Logs/CrashReporter/ioquake3* 2>/dev/null | wc -l | tr -d ' '" 2>/dev/null)
echo "[$M $RES] ${fps:-NO-FPS-LINE}${ncrash:+  (crashlogs=$ncrash)}"
[ -n "$fps" ] && exit 0 || exit 1
