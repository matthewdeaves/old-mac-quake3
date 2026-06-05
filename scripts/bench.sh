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
# "four" is the classic. See KICKOFF_PROMPT.md.
#
# ⚠️ v0 DRAFT. Determinism note: Q3 execs autoexec.cfg at startup, then our
#    cmdline +set overrides win for res/timedemo. If per-machine autoexec
#    cvars pollute comparisons, rename it aside during bench (kickoff item).
#
set -euo pipefail

MACHINE="${1:?usage: bench.sh <machine> <demo> <WxH> [runs]}"
DEMO="${2:?Q3 demo name, e.g. four}"
RES="${3:?resolution, e.g. 1024x768}"
RUNS="${4:-3}"
W="${RES%x*}"; H="${RES#*x}"

PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
CSV="$PROJ_LOCAL/benchmarks/results.csv"
RAWDIR="$PROJ_LOCAL/benchmarks/raw"
REMOTE_DIR="~/Desktop/quake3"
COMMIT="${COMMIT:-$(git -C "$PROJ_LOCAL" rev-parse --short HEAD)}"
mkdir -p "$RAWDIR"

case "$MACHINE" in
  yosemite) TMO=300 ;; sawtooth) TMO=240 ;; quicksilver|mini-g4) TMO=180 ;;
  imac-g5) TMO=90 ;;
  mini-intel) TMO=90 ;; imac-2019) TMO=60 ;;
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
restore_autoexec() {
  ssh "$MACHINE" "cd $REMOTE_DIR && [ -f baseq3/autoexec.cfg.bench-aside ] && mv -f baseq3/autoexec.cfg.bench-aside baseq3/autoexec.cfg || true" 2>/dev/null || true
}
trap restore_autoexec EXIT
ssh "$MACHINE" "cd $REMOTE_DIR && [ -f baseq3/autoexec.cfg ] && mv -f baseq3/autoexec.cfg baseq3/autoexec.cfg.bench-aside || true" 2>/dev/null || true

# CSV header — atomic create (noclobber) so concurrent legs don't double-write.
( set -C; echo "timestamp,commit,machine,demo,res,run1_fps,run2_fps,run3_fps,median_fps" > "$CSV" ) 2>/dev/null || true

declare -a FPS
for ((r=1; r<=RUNS; r++)); do
  echo "==> [$MACHINE] $DEMO ${W}x${H} run $r/$RUNS (timeout ${TMO}s)"
  LOG="$RAWDIR/${COMMIT}_${MACHINE}_${DEMO}_${RES}_run${r}.log"
  # cd/rm/launch carefully: only the engine goes to background (cd && X & would
  # background the whole chain). Integer sleeps only — Panther sleep is int-only.
  ssh "$MACHINE" "cd $REMOTE_DIR
    killall -TERM ioquake3 2>/dev/null; sleep 1; killall -KILL ioquake3 2>/dev/null; true
    rm -f baseq3/qconsole.log
    ./ioquake3 +set fs_basepath \"\$PWD\" +set fs_homepath \"\$PWD\" \\
      +set logfile 2 +set com_maxfps 0 +set r_fullscreen 1 \\
      +set r_mode -1 +set r_customwidth $W +set r_customheight $H \\
      +set timedemo 1 +demo $DEMO >/dev/null 2>&1 &
    t=0
    while [ \$t -lt $TMO ]; do
      grep -qE 'frames.*seconds.*fps' baseq3/qconsole.log 2>/dev/null && break
      sleep 1; t=\$((t+1))
    done
    killall -TERM ioquake3 2>/dev/null; sleep 2; killall -KILL ioquake3 2>/dev/null; true
    grep -E 'frames.*seconds.*fps' baseq3/qconsole.log 2>/dev/null | tail -1" \
    > "$LOG" 2>/dev/null || true

  f=$(grep -oE '[0-9]+(\.[0-9]+)? fps' "$LOG" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
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

[ "$MED" = NA ] && { echo "bench.sh: NA result (timeout/crash/no fps line)"; exit 1; }
exit 0
