#!/usr/bin/env bash
#
# parallel-bench.sh [--quick] [--reset] [--no-<machine> ...] — run the Q3
# timedemo matrix across the fleet concurrently, append to results.csv.
# Adapted from ~/quakespasm/scripts.
#
# CSV append is atomic for our short rows (<PIPE_BUF); header init is noclobber
# (in bench.sh) — so six concurrent legs are safe. COMMIT is resolved ONCE here
# and exported so side commits during a long run can't drift the row tags.
#
set -uo pipefail

PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
CSV="$PROJ_LOCAL/benchmarks/results.csv"
COMMIT="$(git -C "$PROJ_LOCAL" rev-parse --short HEAD)"
export COMMIT

# yosemite-tiger is the same G3 as yosemite on its 10.4.11 partition, so it is
# SKIPPED by default — opt in with --yosemite-tiger (which drops yosemite).
ALL=(yosemite yosemite-tiger sawtooth quicksilver mini-g4 mini-intel imac-2019)
# shellcheck disable=SC2206
DEMOS=(${DEMOS:-four})
# shellcheck disable=SC2206
RESES=(${RESES:-1024x768 640x480})
RUNS="${RUNS:-3}"
QUICK=0; RESET=0
declare -A SKIP
SKIP[yosemite-tiger]=1          # same Mac as yosemite; opt in explicitly
for a in "$@"; do
  case "$a" in
    --quick) QUICK=1 ;;
    --reset) RESET=1 ;;
    --yosemite-tiger) SKIP[yosemite-tiger]=""; SKIP[yosemite]=1 ;;
    --no-*)  SKIP["${a#--no-}"]=1 ;;
    *) echo "parallel-bench: unknown arg '$a'"; exit 2 ;;
  esac
done
# shellcheck disable=SC2206
# DEMO_QUICK is a deliberate space-separated
# list meant to split into array elements, same as DEMOS/RESES above.
[ "$QUICK" = 1 ] && { DEMOS=(${DEMO_QUICK:-four}); RESES=(1024x768); }

# yosemite and yosemite-tiger are one Power Mac G3 with two boot partitions and
# one IP. Running both legs would bench the SAME booted OS twice and log it under
# two names — worse than useless, because the rows look like a comparison.
if [ -z "${SKIP[yosemite]:-}" ] && [ -z "${SKIP[yosemite-tiger]:-}" ]; then
  echo "parallel-bench: yosemite and yosemite-tiger are the same Mac (one IP, one" >&2
  echo "  OS booted at a time). Pick one: --yosemite-tiger, or --no-yosemite-tiger." >&2
  exit 2
fi

if [ "$RESET" = 1 ] && [ -f "$CSV" ]; then
  cp "$CSV" "$CSV.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  rm -f "$CSV" "$PROJ_LOCAL"/benchmarks/raw/* 2>/dev/null || true
  echo "reset: backed up + wiped results.csv"
fi

# Both names. The loose bench binary is ioquake3-bench, so its process is called
# ioquake3-bench, and macOS killall matches on the process name: `killall
# ioquake3` does not touch it. Naming only one of the two here left stale bench
# engines running fullscreen on the very machines this line exists to clear,
# which is how a fleet run ends in power-button resets. Same reasoning as the
# ALIVE_FN/KILL_FN pair in bench.sh.
# CLAIM EACH MACHINE BEFORE TOUCHING IT, AND NEVER -KILL.
#
# This loop used to ssh to every machine in the fleet in parallel and run
# `killall -KILL` on both engine names, with no claim taken first. Two separate
# faults, both fixed here (2026-08-22):
#
# 1. No claim. An engine running on a machine is not necessarily stale. If
#    another session holds that box for its own bench, this killed its run, and
#    it got back a short or missing fps line rather than an error. Taking the
#    claim first is what makes "stale" true: if we hold the lock, nothing else
#    is entitled to be running.
#
# 2. -KILL. docs/adr/0009 is explicit that KILLing a rendering fullscreen engine
#    sticks it in uninterruptible GPU-driver exit (ps state E) and hangs the
#    whole WindowServer until a reboot. This line was the one place in the repo
#    still doing exactly that, on every machine at once. TERM lets the signal
#    handler restore the display; KILL stays available only as a last resort
#    after TERM has been given time.
#
# A machine we cannot claim is SKIPPED, not forced. That is the point of the
# lock, and --run fails rather than waiting, so a busy box costs us nothing.
echo "==> pre-kill stale engines (claimed, TERM first)"
for m in "${ALL[@]}"; do [ -n "${SKIP[$m]:-}" ] && continue
  (
    "$HERE/pick-bench-host.sh" --run "$m" "parallel-bench pre-kill" -- \
      ssh -o ConnectTimeout=5 "$m" '
        killall -TERM ioquake3-bench 2>/dev/null
        killall -TERM ioquake3 2>/dev/null
        # Panther /bin/sleep is integer-only, so whole seconds.
        n=0; while [ $n -lt 8 ]; do
          killall -0 ioquake3-bench 2>/dev/null || killall -0 ioquake3 2>/dev/null || break
          sleep 1; n=$((n+1))
        done
        # Last resort only, and only for something that ignored TERM for 8s.
        killall -KILL ioquake3-bench 2>/dev/null
        killall -KILL ioquake3 2>/dev/null
        true' >/dev/null 2>&1 \
      || echo "    $m: busy or unreachable, pre-kill skipped"
  ) & done; wait

mkdir -p /tmp/q3-parallel-bench
echo "==> launching legs (commit $COMMIT, demos: ${DEMOS[*]}, res: ${RESES[*]}, runs: $RUNS)"
pids=()
for m in "${ALL[@]}"; do
  [ -n "${SKIP[$m]:-}" ] && continue
  (
    for res in "${RESES[@]}"; do for d in "${DEMOS[@]}"; do
      COMMIT="$COMMIT" "$HERE/bench.sh" "$m" "$d" "$res" "$RUNS"
    done; done
  ) >"/tmp/q3-parallel-bench/$m.log" 2>&1 &
  pids+=($!)
done

fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done

echo "=== results for $COMMIT ==="
grep ",$COMMIT," "$CSV" 2>/dev/null | sort || true
[ "$fail" = 0 ] || echo "⚠️ a leg reported NA — inspect /tmp/q3-parallel-bench/<machine>.log"
exit $fail
