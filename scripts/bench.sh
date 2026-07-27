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
set -euo pipefail

MACHINE="${1:?usage: bench.sh <machine> <demo> <WxH> [runs]}"
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

W="${RES%x*}"; H="${RES#*x}"

PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
CSV="$PROJ_LOCAL/benchmarks/results.csv"
RAWDIR="$PROJ_LOCAL/benchmarks/raw"
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
ALIVE_FN='alive() { killall -0 ioquake3 2>/dev/null || ps ax 2>/dev/null | grep -q "[i]oquake3"; }'

# Also stop any engine we left running. If this script dies (Ctrl-C, a parent
# shell going away, a killed background job) the REMOTE engine keeps rendering
# fullscreen with nobody polling it — that orphan is what hard-crashed mini-g4
# and the iMac G5 on 2026-07-25, needing power-button resets. TERM only: never
# KILL a fullscreen ioquake3. Also clear the pid file so the next launch doesn't
# come up on the "safe settings" modal.
bench_cleanup() {
  ssh -o ConnectTimeout=10 "$MACHINE" "$ALIVE_FN
    cd $REMOTE_DIR 2>/dev/null
    if alive; then
      killall -TERM ioquake3 2>/dev/null
      g=0; while [ \$g -lt 15 ]; do alive || break; sleep 1; g=\$((g+1)); done
      alive && killall -KILL ioquake3 2>/dev/null
    fi
    rm -f \"$PIDF\"
    [ -f baseq3/autoexec.cfg.bench-aside ] && mv -f baseq3/autoexec.cfg.bench-aside baseq3/autoexec.cfg
    true" 2>/dev/null || true
}
trap bench_cleanup EXIT INT TERM
ssh "$MACHINE" "cd $REMOTE_DIR && [ -f baseq3/autoexec.cfg ] && mv -f baseq3/autoexec.cfg baseq3/autoexec.cfg.bench-aside || true" 2>/dev/null || true

# CSV header — atomic create (noclobber) so concurrent legs don't double-write.
( set -C; echo "timestamp,commit,machine,demo,res,run1_fps,run2_fps,run3_fps,median_fps" > "$CSV" ) 2>/dev/null || true

declare -a FPS
for ((r=1; r<=RUNS; r++)); do
  echo "==> [$MACHINE] $DEMO ${W}x${H} run $r/$RUNS (timeout ${TMO}s)"
  LOG="$RAWDIR/${COMMIT}_${MACHINE}_${DEMO}_${RES}_run${r}.log"
  # cd/rm/launch carefully: only the engine goes to background (cd && X & would
  # background the whole chain). Integer sleeps only — Panther sleep is int-only.
  ssh "$MACHINE" "$ALIVE_FN
    cd $REMOTE_DIR
    killall -TERM ioquake3 2>/dev/null
    g=0; while [ \$g -lt 12 ]; do alive || break; sleep 1; g=\$((g+1)); done
    rm -f baseq3/qconsole.log \"$PIDF\"
    ./ioquake3 +set com_archAutoexec 0 +set fs_basepath \"\$PWD\" +set fs_homepath \"\$PWD\" \\
      +set logfile 2 +set com_maxfps 0 +set r_fullscreen 1 \\
      +set r_mode -1 +set r_customwidth $W +set r_customheight $H \\
      +set nextdemo quit +set timedemo 1 +demo $DEMO >/dev/null 2>&1 &
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
    # Teardown: TERM, a REAL grace period, then KILL only if it is still there.
    # KILL is kept deliberately — the sister ports document that SDL/CoreAudio
    # threads do not always answer SIGTERM, and an engine left running is worse
    # than a hard kill: the next run launches fullscreen on top of it, which is
    # what wedged four Macs on 2026-07-25. The fix is the GRACE, not removing
    # KILL: never KILL while it may still hold the fullscreen GL context.
    if alive; then
      killall -TERM ioquake3 2>/dev/null
      g=0; while [ \$g -lt 15 ]; do alive || break; sleep 1; g=\$((g+1)); done
      alive && killall -KILL ioquake3 2>/dev/null
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
echo "$TS,$COMMIT,$MACHINE,$DEMO,$RES,${FPS[1]:-NA},${FPS[2]:-NA},${FPS[3]:-NA},$MED" >> "$CSV"
echo "==> [$MACHINE] median ${MED} fps -> results.csv"

# Belt-and-braces. MEASURED 2026-07-27: the LaunchServices corruption needs a
# dlopen() from INSIDE the .app, and this script triggers neither half of that —
# it runs the loose ./ioquake3 (no enclosing bundle) AND passes com_archAutoexec 0,
# so the arch cfg that sets vm_* 0 never runs and no bundle module is loaded.
# Kept anyway: the call is idempotent and costs one ssh, and it keeps working if
# either of those two facts changes. See MISTAKES.md 2026-07-26/27.
"$(dirname "$0")/lsregister-app.sh" "$MACHINE" --quiet || true

[ "$MED" = NA ] && { echo "bench.sh: NA result (timeout/crash/no fps line)"; exit 1; }
exit 0
