#!/usr/bin/env bash
#
# safebench.sh <machine> <WxH> [demo] [extra +set cvars] — SAFE timedemo.
#
# Runs one fullscreen timedemo on a bench machine over ssh and prints its fps,
# launching AND cleanly shutting the engine down before it returns — you should
# never have to quit the game by hand.
#
# The hard-won shape of this (see docs/adr/0009 and MISTAKES.md):
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

# Claim this machine for the whole run, exactly as bench.sh:42-46 does.
#
# This was missing, and safebench is the script CLAUDE.md points at as THE safe
# timedemo, so it was the most-used way to drive a bench machine without
# claiming it. Caught on 2026-08-22 when the picker showed yosemite busy with
# two processes, no lock and no owner, during a run of this script.
#
# Re-exec under the picker rather than acquire-here-and-trap: this script sets
# its own EXIT-adjacent handling, and bash traps REPLACE rather than compose, so
# a release trap installed here could be silently discarded and leave the
# machine claimed until the stale reclaim. `--run` makes the lock a property of
# the INVOCATION, so it is released however this exits.
#
# RETRO_BENCH_LOCK guards against the re-exec recursing. BENCH_NO_LOCK=1 skips
# the lock, for debugging the picker itself. It is not a way to get past a
# machine someone else is using.
_PICK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pick-bench-host.sh"
# Compare RETRO_BENCH_LOCK to THIS script's target rather than merely testing
# that it is set. pick-bench-host.sh --run now exports it naming the claimed
# host, so a bare -z test would make this script skip its own claim whenever it
# runs inside any other claim, including one on a DIFFERENT machine. Same-host
# still skips, which is the reentrancy this guard is for.
if [ "${RETRO_BENCH_LOCK:-}" != "$M" ] && [ "${BENCH_NO_LOCK:-0}" != 1 ] && [ -x "$_PICK" ]; then
	export RETRO_BENCH_LOCK="$M"
	exec "$_PICK" --run "$M" "safebench" -- "$0" "$@"
fi

RES="${2:?need WxH}"; W=${RES%x*}; H=${RES#*x}
DEMO="${3:-four}"
EXTRA="${4:-}"
# shellcheck disable=SC2088
# tilde stays unexpanded on purpose: it must
# resolve on the REMOTE host's home, not this workstation's. See ci.yml.
RDIR='~/Desktop/quake3'
PIDF='$HOME/Library/Application Support/Quake3/ioq3.pid'
SSHO="-o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
DEADLINE=${SAFEBENCH_TIMEOUT:-260}          # per-run wall-clock budget (seconds)

# REFUSE A COMMAND LINE THE ENGINE WILL SILENTLY TRUNCATE.
#
# Com_ParseCommandLine (code/qcommon/common.c:405,428) splits the command line
# on '+' into at most MAX_CONSOLE_LINES = 32 entries, and when it reaches 32 it
# `return`s. Everything after the 32nd is DISCARDED with no message of any kind.
#
# Entry 0 is the text before the first '+' (the binary path), so 31 '+' groups
# survive. The launch line below contributes 12 of them, which leaves 19 for
# $EXTRA.
#
# Why this needs a check and not a comment. The groups that get dropped are the
# ones at the END, and the end of this line is `+set nextdemo quit +set timedemo
# 1 +demo <demo>` — the three that actually run the benchmark and make the engine
# quit. So an over-long EXTRA does not fail. The engine launches, initialises,
# renders the main menu, and sits there fullscreen until the deadline kills it.
# safebench then reports NO-FPS-LINE, which is indistinguishable from a crash.
#
# Measured 2026-08-23 on yosemite: a 26-group EXTRA pinning the G3 profile for
# issue #15 produced exactly that. The log stopped after "--- Common
# Initialization Complete ---", the engine held the machine for six minutes
# doing nothing, and the run had to be TERMed by hand. Nothing in the output
# said the command line had been truncated.
#
# The count is of literal '+' characters, so a cvar VALUE containing '+' counts
# against the budget. That errs toward refusing, which is the safe direction.
_EXTRA_PLUS=$(printf '%s' "$EXTRA" | tr -cd '+' | wc -c | tr -d ' ')
_FIXED_PLUS=12
_TOTAL_PLUS=$(( _FIXED_PLUS + _EXTRA_PLUS ))
if [ "$_TOTAL_PLUS" -gt 31 ]; then
  echo "[$M] REFUSING: command line has $_TOTAL_PLUS '+' groups ($_FIXED_PLUS fixed + $_EXTRA_PLUS in EXTRA)." >&2
  echo "     The engine keeps 31 (MAX_CONSOLE_LINES 32, code/qcommon/common.c:405)." >&2
  echo "     Past that it drops the REST OF THE LINE silently, including +demo," >&2
  echo "     so the engine would launch and never run the timedemo." >&2
  echo "     Pass at most 19 '+' groups in EXTRA, or set the rest in the machine's" >&2
  echo "     baseq3/q3config.cfg before the run." >&2
  exit 4
fi

reachable() { ssh $SSHO "$M" 'true' 2>/dev/null; }
# Reboot and VERIFY it actually cycles — qsreboot.sh's Finder fallback can report
# a false success without the machine ever going down, so we confirm it drops off
# the network and returns rather than trusting the exit code.
reboot_m()  {
  echo "[$M] REBOOTING via qsreboot.sh (verifying it cycles)"
  # shellcheck disable=SC2088
  # tilde stays unexpanded on purpose: it must
  # resolve on the REMOTE host's home, not this workstation's. See ci.yml.
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
# (Panther's /bin/sleep is integer-only). Host-side deadline is a last backstop.
#
# NOT `timeout`. GNU coreutils' timeout is not on stock macOS, and this
# workstation has neither it nor gtimeout (measured 2026-08-22). This script
# runs `set -uo pipefail` with no `-e`, so a missing binary failed SILENTLY:
# $out came back empty, every run printed NO-FPS-LINE, and the bench machine was
# never contacted at all. A green-looking failure that never reached the
# hardware is the worst shape this script can have, so the deadline is portable
# now and only falls back when a real timeout exists.
#
# Killing the LOCAL ssh client is safe. The remote block is self-bounding on its
# own poll counter, so the engine still self-quits via nextdemo and restores the
# display even if we stop listening. Nothing is ever signalled to the fullscreen
# app, which is the rule that matters (docs/adr/0009).
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
run_deadline() {
  _secs="$1"; shift
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$_secs" "$@"; return $?; fi
  "$@" &
  _p=$!; _t=0
  while [ "$_t" -lt "$_secs" ]; do
    kill -0 "$_p" 2>/dev/null || break
    sleep 1; _t=$((_t+1))
  done
  if kill -0 "$_p" 2>/dev/null; then
    kill -TERM "$_p" 2>/dev/null; sleep 2; kill -KILL "$_p" 2>/dev/null
  fi
  wait "$_p" 2>/dev/null
}
out=$(run_deadline "$DEADLINE" ssh $SSHO "$M" "
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
# We launched the bundle's binary directly (line ~81), which on Lion blanks the
# LaunchServices `executable:` path and makes Finder call the app "damaged".
# Repair it — but only here, past the unresponsive/stuck checks above, so we
# never poke a machine that is mid-reboot. See scripts/lsregister-app.sh.
"$(dirname "$0")/lsregister-app.sh" "$M" --quiet || true

ncrash=$(ssh $SSHO "$M" "ls ~/Library/Logs/CrashReporter/ioquake3* 2>/dev/null | wc -l | tr -d ' '" 2>/dev/null)
echo "[$M $RES] ${fps:-NO-FPS-LINE}${ncrash:+  (crashlogs=$ncrash)}"
[ -n "$fps" ] && exit 0 || exit 1
