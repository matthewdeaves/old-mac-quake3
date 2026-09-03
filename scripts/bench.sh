#!/usr/bin/env bash
#
# bench.sh <machine> <demo> <WxH> [runs] — run one Quake III timedemo and
# append a row to benchmarks/results.csv. Adapted from ~/quakespasm/scripts.
#
# Q3 timedemo prints a line like:
#   1234 frames 12.3 seconds 100.3 fps 5.0/10.0/30.0/2.0 ms
# We set `logfile 2` (line-flushed) and poll baseq3/qconsole.log for it, then
# stop the engine — the same poll-then-kill pattern QuakeSpasm uses, so we
# don't depend on Q3 auto-quitting after a demo.
#
# <demo> is a real Q3 demo name (NOT Quake's demo1/2/3). Enumerate the demos
# in the staged pk3s first (point-release demos are .dm_68 inside pak8.pk3);
# "four" is the classic.
#
# Determinism: Q3 execs autoexec.cfg at startup and the in-engine auto-config
# execs the bundled per-arch + per-machine cfgs, either of which would pollute
# a comparison. Both are suppressed for the duration of a bench — the deployed
# autoexec.cfg is moved aside and restored on exit (see restore_autoexec below),
# and the engine is launched with `+set com_archAutoexec 0`. Our cmdline +set
# then owns res/timedemo outright.
#
# env: EXTRA_CVARS  optional cmdline cvar overrides spliced into the launch,
#                    for an A/B leg against the same commit/machine/demo/res, e.g.
#                      EXTRA_CVARS="+set r_ext_multisample 0" scripts/bench.sh ...
#                    Recorded in results.csv's extra_cvars column and folded into
#                    the raw log filename (see CVAR_TAG below) — old-mac-quake3#48,
#                    same overwrite bug quakespasm's bench.sh already fixed:
#                    without a tag, two same-day legs that differ only in
#                    EXTRA_CVARS share one raw log filename and the second leg
#                    silently clobbers the first leg's evidence while
#                    results.csv still (mis)records both rows as correct.
#
set -euo pipefail

MACHINE="${1:?usage: bench.sh <machine> <demo> <WxH> [runs]}"

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
	exec "$_PICK" --run "$MACHINE" "bench" -- "$0" "$@"
fi
DEMO="${2:?Q3 demo name, e.g. four}"
RES="${3:?resolution, e.g. 1024x768}"
RUNS="${4:-3}"

# Reject a malformed resolution rather than benching nonsense. `bench.sh <m>
# four 3` (meaning "3 runs") would otherwise split to W=3 H=3 and time a 3x3
# render — the Quake II port shipped nine such rows at 1x1 and they became the
# quoted evidence for a config decision. runs is the FOURTH argument.
case "$RES" in
  [0-9]*x[0-9]*) ;;
  *) echo "bench.sh: resolution must be WxH (e.g. 1024x768), got '$RES'" >&2
     echo "  usage: $0 <machine> <demo> <WxH> [runs]  — runs is the FOURTH arg" >&2
     exit 2 ;;
esac

# REFUSE A COMMAND LINE THE ENGINE WILL SILENTLY TRUNCATE — same guard as
# safebench.sh (see its comment for the full citation). Com_ParseCommandLine
# (code/qcommon/common.c) splits on '+' into at most MAX_CONSOLE_LINES = 32
# entries and silently drops the rest once it hits 32, with no message. Entry 0
# is the binary path, so 31 '+' groups survive; the launch line below
# contributes 12 fixed ones, leaving 19 for EXTRA_CVARS. Past that, the dropped
# groups are the ones at the END — nextdemo/timedemo/demo — so the engine
# launches, sits at the main menu, and this script just times out per run
# looking like a hang, not an error.
_EXTRA_PLUS=$(printf '%s' "${EXTRA_CVARS:-}" | tr -cd '+' | wc -c | tr -d ' ')
_FIXED_PLUS=12
_TOTAL_PLUS=$(( _FIXED_PLUS + _EXTRA_PLUS ))
if [ "$_TOTAL_PLUS" -gt 31 ]; then
  echo "bench.sh: REFUSING: command line has $_TOTAL_PLUS '+' groups ($_FIXED_PLUS fixed + $_EXTRA_PLUS in EXTRA_CVARS)." >&2
  echo "  The engine keeps 31 (MAX_CONSOLE_LINES 32, code/qcommon/common.c) and drops" >&2
  echo "  the rest of the line silently, including +demo, so timedemo never runs." >&2
  echo "  Pass at most 19 '+' groups in EXTRA_CVARS, or set the rest in the machine's" >&2
  echo "  baseq3/q3config.cfg before the run." >&2
  exit 2
fi

W="${RES%x*}"; H="${RES#*x}"

PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
# BENCH_CSV/BENCH_RAW_DIR override the output paths. Both default to the
# git-tracked locations, where every row is meant to be committed with the
# narrated decision it supports; an automated caller with nobody curating a
# commit per row (old-mac-build-host#15) should point both at a gitignored
# path instead. Redirect both together — BENCH_CSV alone would still leave
# raw qconsole.log copies landing in the tracked benchmarks/raw/.
CSV="${BENCH_CSV:-$PROJ_LOCAL/benchmarks/results.csv}"
RAWDIR="${BENCH_RAW_DIR:-$PROJ_LOCAL/benchmarks/raw}"
# shellcheck disable=SC2088
# tilde stays unexpanded on purpose: it must
# resolve on the REMOTE host's home, not this workstation's. See ci.yml.
REMOTE_DIR="~/Desktop/quake3"
COMMIT="${COMMIT:-$(git -C "$PROJ_LOCAL" rev-parse --short HEAD)}"
mkdir -p "$RAWDIR"

# TMO = timedemo wall-clock budget. COOLDOWN = settle time AFTER each run before
# the next one launches, and it is not optional: the Rage 128 and R300 drivers
# leave the display in a fragile state for a few seconds after a fullscreen exit,
# and going straight into the next fullscreen launch can hang the machine. The
# Quake II port has carried these exact values for months; this script had NO
# cooldown at all, which is a large part of why four Macs needed power-button
# resets on 2026-07-25. Values copied from ~/Documents/old-mac-quake2/scripts.
case "$MACHINE" in
  yosemite|yosemite-tiger) TMO=300; COOLDOWN=5 ;;
  sawtooth)                TMO=240; COOLDOWN=3 ;;
  quicksilver|mini-g4)     TMO=180; COOLDOWN=2 ;;
  imac-g5)                 TMO=90;  COOLDOWN=2 ;;
  mini-intel)              TMO=90;  COOLDOWN=1 ;;
  imac-2019)               TMO=60;  COOLDOWN=1 ;;
  *) echo "bench.sh: unknown machine '$MACHINE'"; exit 2 ;;
esac

# imac-g5 R300 (Radeon 9600 / Leopard) safety: that driver HARD-HANGS the whole
# OS on a non-native fullscreen mode SWITCH (power-button recovery only — NOT
# SSH-recoverable). Requesting the panel's NATIVE resolution is a same-mode set
# the driver survives cleanly. So on the G5 refuse any non-native res under
# fullscreen. (Ref: the Q1 QuakeSpasm + Q2 port notes — same hardware.)
if [ "$MACHINE" = imac-g5 ]; then
  G5_NATIVE_RES="1440x900"        # built-in panel; same-mode capture only
  if [ "$RES" != "$G5_NATIVE_RES" ]; then
    echo "bench.sh: imac-g5 must bench at native $G5_NATIVE_RES — the R300 driver" >&2
    echo "  hard-hangs the OS on a non-native fullscreen mode switch (power button)." >&2
    echo "  Re-run: scripts/bench.sh imac-g5 $DEMO $G5_NATIVE_RES" >&2
    exit 3
  fi
fi

# Determinism: move the per-machine autoexec.cfg aside for the duration of the
# bench so results reflect engine defaults + our cmdline cvars only (resolution,
# timedemo). Per-machine tuning is a separate experiment; mixing it in would make
# fps non-comparable across machines and non-attributable to code commits.
# Restore on ANY exit so a crash/Ctrl-C can't leave the deployed config missing.
# A stale ioq3.pid pops an "Abnormal Exit / start with safe settings?" modal on
# the next launch, which hangs forever headless — the engine never renders, the
# poll times out, and the orphaned process then wedges the machine. Clear it
# before every run and on exit. (Single-quoted: $HOME expands on the REMOTE box.)
# Defined BEFORE the trap that uses it: set -u would abort on an early exit.
PIDF='$HOME/Library/Application Support/Quake3/ioq3.pid'

# "Is the engine still running?" — shipped to the remote box as a function.
# BOTH forms are needed. `ps -axo comm` returns EMPTY on Tiger (that option
# combination is unsupported there), so the check this script used to make
# never matched: its wait loops fell straight through and it launched the next
# run while the previous engine was still tearing down fullscreen. That is how
# machines got wedged. `killall -0` works on Tiger but is unverified on
# Panther, so OR the two — alive if either says so, which fails safe.
#
# BOTH NAMES, in the check and in the kill, and they must never disagree.
#
# The loose bench binary is called `ioquake3-bench`, so the process it starts is
# called `ioquake3-bench` too, and macOS `killall` matches on the process name.
# Measured on this box: with a process running as `ioquake3-bench`,
# `killall -0 ioquake3` reports NO MATCH while `ps ax | grep "[i]oquake3"`
# reports MATCH.
#
# So a check that ORs those two and a kill that names only `ioquake3` disagree
# by construction: alive() says yes forever, every killall hits nothing, the
# grace loops spin their full 15 seconds, and the next run launches fullscreen
# on top of an engine that is still holding the display. That is the exact
# failure MISTAKES.md records for 2026-07-25, and it needed power-button resets
# on four Macs.
#
# Both names, both places. The app's own binary is still called `ioquake3`, and
# killing that too before a bench is intended: an engine somebody left running
# from a double-click has to go before the next fullscreen launch either way.
#
# KNOWN, and deliberately not fixed here: the `ps ax` branch also matches the
# enclosing shell. sshd runs this whole snippet as `sh -c '<snippet>'`, and the
# snippet contains the literal string `ioquake3-bench` in the two lines above,
# so the shell's own argv matches its own grep. The `[i]` bracket trick only
# stops grep matching grep. So alive() over-reports.
#
# That over-report is in the SAFE direction: it makes the script wait and kill
# rather than launch on top of a live engine, and the cost is up to 15 seconds
# of grace per run. It only became dangerous in combination with the killall
# name mismatch above, where alive() said yes forever and the kill hit nothing,
# so the grace expired and the next run launched anyway.
#
# The real fix is to stop matching on names at all: record the engine's pid at
# launch and have alive() use `kill -0` on it. That rewrites the wedge-critical
# teardown path, so it wants a real fullscreen run on a PowerPC box to verify,
# not a grep.
ALIVE_FN='alive() { killall -0 ioquake3-bench 2>/dev/null || killall -0 ioquake3 2>/dev/null || ps ax 2>/dev/null | grep -q "[i]oquake3"; }'
KILL_FN='engine_kill() { killall -$1 ioquake3-bench 2>/dev/null; killall -$1 ioquake3 2>/dev/null; true; }'

# Also stop any engine we left running. If this script dies (Ctrl-C, a parent
# shell going away, a killed background job) the REMOTE engine keeps rendering
# fullscreen with nobody polling it — that orphan is what hard-crashed mini-g4
# and the iMac G5 on 2026-07-25, needing power-button resets. TERM only: never
# KILL a fullscreen ioquake3. Also clear the pid file so the next launch doesn't
# come up on the "safe settings" modal.
bench_cleanup() {
  ssh -o ConnectTimeout=10 "$MACHINE" "$ALIVE_FN
    $KILL_FN
    cd $REMOTE_DIR 2>/dev/null
    if alive; then
      engine_kill TERM
      g=0; while [ \$g -lt 15 ]; do alive || break; sleep 1; g=\$((g+1)); done
      alive && engine_kill KILL
    fi
    rm -f \"$PIDF\"
    [ -f baseq3/autoexec.cfg.bench-aside ] && mv -f baseq3/autoexec.cfg.bench-aside baseq3/autoexec.cfg
    true" 2>/dev/null || true
}
trap bench_cleanup EXIT INT TERM
ssh "$MACHINE" "cd $REMOTE_DIR && [ -f baseq3/autoexec.cfg ] && mv -f baseq3/autoexec.cfg baseq3/autoexec.cfg.bench-aside || true" 2>/dev/null || true

# CSV header — atomic create (noclobber) so concurrent legs don't double-write.
( set -C; echo "timestamp,commit,machine,demo,res,run1_fps,run2_fps,run3_fps,median_fps,extra_cvars" > "$CSV" ) 2>/dev/null || true

# Tag the raw log with the cvars when this is an A/B leg — same pattern as
# quakespasm/scripts/bench.sh (old-mac-quake3#48). Without it two legs that
# differ only in EXTRA_CVARS share one filename and the second overwrites the
# first leg's raw evidence, even though both rows land correctly in the CSV.
# Cap the readable slug and append a hash of the FULL cvar string for
# uniqueness — a long sweep can blow past the filesystem's 255-byte name limit.
CVAR_TAG=""
if [ -n "${EXTRA_CVARS:-}" ]; then
  CVAR_SLUG="$(printf '%s' "$EXTRA_CVARS" | tr -cs 'A-Za-z0-9' '_' | sed 's/^_//; s/_$//')"
  if [ "${#CVAR_SLUG}" -gt 60 ]; then
    CVAR_HASH="$(printf '%s' "$EXTRA_CVARS" | shasum -a 256 | cut -c1-8)"
    CVAR_SLUG="$(printf '%s' "$CVAR_SLUG" | cut -c1-60)_$CVAR_HASH"
  fi
  CVAR_TAG="_$CVAR_SLUG"
fi

declare -a FPS
for ((r=1; r<=RUNS; r++)); do
  echo "==> [$MACHINE] $DEMO ${W}x${H} run $r/$RUNS (timeout ${TMO}s)"
  LOG="$RAWDIR/${COMMIT}_${MACHINE}_${DEMO}_${RES}${CVAR_TAG}_run${r}.log"
  # cd/rm/launch carefully: only the engine goes to background (cd && X & would
  # background the whole chain). Integer sleeps only — Panther sleep is int-only.
  ssh "$MACHINE" "$ALIVE_FN
    $KILL_FN
    cd $REMOTE_DIR
    engine_kill TERM
    g=0; while [ \$g -lt 12 ]; do alive || break; sleep 1; g=\$((g+1)); done
    mv -f baseq3/qconsole.log baseq3/qconsole.log.prev 2>/dev/null; rm -f \"$PIDF\"
    ./ioquake3-bench +set com_archAutoexec 0 +set fs_basepath \"\$PWD\" +set fs_homepath \"\$PWD\" \\
      +set logfile 2 +set com_maxfps 0 +set r_fullscreen 1 \\
      +set r_mode -1 +set r_customwidth $W +set r_customheight $H \\
      ${EXTRA_CVARS:+$EXTRA_CVARS }+set nextdemo quit +set timedemo 1 +demo $DEMO >/dev/null 2>&1 &
    # FIRST wait for the engine to actually come up. Polling 'has it exited yet?'
    # straight after backgrounding is a race: on a slower Mac the process has not
    # exec'd yet, the check finds nothing, and we would 'break' immediately and
    # bench nothing at all. Give it up to 30s to appear.
    s=0
    while [ \$s -lt 30 ]; do alive && break; sleep 1; s=\$((s+1)); done
    # THEN wait for the run to finish. Two independent signals, whichever comes
    # first — the QuakeSpasm/Quake II scripts poll the LOG and that is the robust
    # one (it does not depend on process detection working), while process-exit
    # confirms the engine self-quit via 'nextdemo quit'. Waiting on the log alone
    # would move on while the engine still held the display; waiting on the
    # process alone silently benches nothing if detection is broken.
    t=0
    while [ \$t -lt $TMO ]; do
      alive || break
      grep -q 'frames.*seconds.*fps\\|ERROR:' baseq3/qconsole.log 2>/dev/null && break
      sleep 1; t=\$((t+1))
    done
    # The fps line appears BEFORE the engine has finished quitting, so give it
    # room to finish on its own before signalling it. This is not politeness,
    # it is a crash.
    #
    # The engine is launched with 'nextdemo quit', so when the demo ends it
    # walks Com_Quit_f -> CL_Shutdown -> RE_Shutdown -> GLimp_Shutdown ->
    # SDL_VideoQuit -> QZ_UnsetVideoMode -> CGReleaseAllDisplays. A TERM
    # delivered inside that window runs Sys_SigHandler -> Sys_Exit ->
    # SDL_Quit, which re-enters the SAME SDL video teardown already in
    # progress and releases an Objective-C object twice:
    #
    #   0 libobjc.A.dylib  objc_msgSend
    #   1 libSDL-1.2.0     QZ_TearDownOpenGL
    #   ...
    #   9 libSystem.B      _sigtramp          <- signal landed here
    #  12 CoreGraphics     _CGSSetDisplayOption
    #
    # Measured on yosemite 2026-08-21: 12 EXC_BAD_ACCESS crashes in one bench
    # round, one CrashReporter dialog each, all of them caused by this script
    # signalling an engine that was already exiting cleanly. Sys_SigHandler
    # guards against a SECOND signal but not against a signal arriving during
    # a normal shutdown.
    #
    # So: wait for the self-quit first. Only the engine that overruns gets
    # signalled, which is what the teardown below was always for.
    q=0; while [ \$q -lt 20 ]; do alive || break; sleep 1; q=\$((q+1)); done
    # Teardown: TERM, a REAL grace period, then KILL only if it is still there.
    # KILL is kept deliberately — the sister ports document that SDL/CoreAudio
    # threads do not always answer SIGTERM, and an engine left running is worse
    # than a hard kill: the next run launches fullscreen on top of it, which is
    # what wedged four Macs on 2026-07-25. The fix is the GRACE, not removing
    # KILL: never KILL while it may still hold the fullscreen GL context.
    if alive; then
      engine_kill TERM
      g=0; while [ \$g -lt 15 ]; do alive || break; sleep 1; g=\$((g+1)); done
      alive && engine_kill KILL
    fi
    rm -f \"$PIDF\"
    # Settle before the next run — see COOLDOWN above. Skipping this is what lets
    # a fragile post-fullscreen display state carry into the next launch.
    sleep $COOLDOWN
    grep -E 'frames.*seconds.*fps' baseq3/qconsole.log 2>/dev/null | tail -1" \
    > "$LOG" 2>/dev/null || true

  # `|| true`: a run that produced no fps line must record NA and let the other
  # runs proceed. Without it, grep's exit 1 trips `set -e`/pipefail and the whole
  # script dies silently mid-matrix, writing no CSV row at all.
  f=$(grep -oE '[0-9]+(\.[0-9]+)? fps' "$LOG" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?' | head -1) || true
  FPS[$r]="${f:-NA}"
  echo "    run $r: ${FPS[$r]} fps"
done

# Median: drop the cold run 1 when we have >=3 (mean of 2&3); else mean/single.
median() {
  awk -v a="${FPS[2]:-NA}" -v b="${FPS[3]:-NA}" -v c="${FPS[1]:-NA}" -v n="$RUNS" 'BEGIN{
    if (n>=3 && a!="NA" && b!="NA") printf "%.2f",(a+b)/2;
    else if (n==2 && c!="NA" && a!="NA") printf "%.2f",(c+a)/2;
    else if (c!="NA") printf "%.2f",c; else printf "NA";
  }'
}
MED="$(median)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EXTRA_CSV=$(printf '%s' "${EXTRA_CVARS:-}" | tr -d '"')
echo "$TS,$COMMIT,$MACHINE,$DEMO,$RES,${FPS[1]:-NA},${FPS[2]:-NA},${FPS[3]:-NA},$MED,\"$EXTRA_CSV\"" >> "$CSV"
echo "==> [$MACHINE] median ${MED} fps -> results.csv"

# Belt-and-braces. MEASURED 2026-07-27: the LaunchServices corruption needs a
# dlopen() from INSIDE the .app, and this script triggers neither half of that —
# it runs the loose ./ioquake3-bench (no enclosing bundle) AND passes com_archAutoexec 0,
# so the arch cfg that sets vm_* 0 never runs and no bundle module is loaded.
# Kept anyway: the call is idempotent and costs one ssh, and it keeps working if
# either of those two facts changes. See MISTAKES.md 2026-07-26/27.
"$(dirname "$0")/lsregister-app.sh" "$MACHINE" --quiet || true

[ "$MED" = NA ] && { echo "bench.sh: NA result (timeout/crash/no fps line)"; exit 1; }
exit 0
