#!/usr/bin/env bash
#
# sweep.sh <machine> [sweep-file] - measure a list of cvar settings on one bench
# box and print a ranked table.
#
# This is the tool for the question "which knob actually costs us anything on
# THIS hardware", which is not answerable by reading the config: several
# settings in this port's own machine configs turned out to cost nothing (the
# G3's cheap sky) or to do nothing at all (r_ext_compressed_textures on a Rage
# 128, whose driver reports no S3TC extension). bench.sh answers "how fast is
# this build"; this answers "what should the config say".
#
# usage:
#   scripts/sweep.sh yosemite                    # the built-in default sweep
#   scripts/sweep.sh yosemite my-sweep.txt       # a file of rows
#
# A sweep file is one row per line:  <label> <TAB or 2+ spaces> <cvar args>
# Lines starting with # are comments. A row with no cvar args is the baseline.
#
# Every row is measured against the SAME baseline command line (see
# host-bin/q3sweep.sh), with the per-machine autoexec disabled, so the only
# difference between rows is the row.
#
set -euo pipefail

HOST="${1:?usage: sweep.sh <machine> [sweep-file]}"

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
	exec "$_PICK" --run "$HOST" "sweep" -- "$0" "$@"
fi
SWEEPFILE="${2:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"

RUNNER="$HERE/host-bin/q3sweep.sh"
test -f "$RUNNER" || { echo "sweep.sh: missing $RUNNER" >&2; exit 1; }

# Ship the runner every time. It is small, and a sweep measured with a stale
# runner is worse than no sweep: the rows look fine and mean something else.
echo "==> installing host-bin/q3sweep.sh on $HOST"
scp -q "$RUNNER" "$HOST:~/q3sweep.sh"
ssh -n "$HOST" "chmod +x ~/q3sweep.sh"

# The default sweep. Chosen for a fill-limited GL 1.1 part; reorder freely.
DEFAULT_SWEEP=$(cat <<'ROWS'
baseline
res-640x480          Q3W=640 Q3H=480
res-1024x768         Q3W=1024 Q3H=768
picmip-2             +set r_picmip 2
picmip-3             +set r_picmip 3
vertexlight          +set r_vertexlight 1
no-dynamiclight      +set r_dynamiclight 0
no-flares            +set r_flares 0
no-detailtextures    +set r_detailtextures 0
subdivisions-40      +set r_subdivisions 40
lodbias-3            +set r_lodbias 3
simplemipmaps        +set r_simpleMipMaps 1
prim-arrayelement    +set r_primitives 2
prim-glvertex        +set r_primitives 3
no-cva               +set r_ext_compiled_vertex_array 0
fastsky-2            +set r_fastsky 2
ROWS
)

if [ -n "$SWEEPFILE" ]; then
  test -f "$SWEEPFILE" || { echo "sweep.sh: no such sweep file: $SWEEPFILE" >&2; exit 1; }
  ROWS_IN=$(cat "$SWEEPFILE")
else
  ROWS_IN="$DEFAULT_SWEEP"
fi

OUTDIR="$REPO_ROOT/benchmarks"
mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d-%H%M%S)
CSV="$OUTDIR/sweep-$HOST-$STAMP.csv"
echo "label,fps,raw" > "$CSV"

echo "==> sweeping $HOST ($(printf '%s\n' "$ROWS_IN" | grep -cv '^[[:space:]]*\(#\|$\)') rows)"
printf '%-22s %8s\n' "SETTING" "FPS"
printf '%-22s %8s\n' "----------------------" "--------"

while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  label=$(printf '%s' "$line" | awk '{print $1}')
  args=$(printf '%s' "$line" | sed "s/^$label[[:space:]]*//")

  # Rows may set env (Q3W=640) as well as pass cvars. Split them apart so the
  # env reaches the runner as env and the rest as arguments.
  env_part=""; cvar_part=""
  for tok in $args; do
    case "$tok" in
      [A-Z0-9_]*=*) env_part="$env_part $tok" ;;
      *)            cvar_part="$cvar_part $tok" ;;
    esac
  done

  # ssh -n is not optional here. Without it ssh inherits this loop's stdin and
  # swallows the remaining sweep rows, so the run measures the first row and
  # then silently reports a one-row sweep as if that were the whole thing.
  raw=$(ssh -n "$HOST" "$env_part ~/q3sweep.sh $cvar_part" 2>/dev/null || echo "NORESULT ssh failed")
  fps=$(printf '%s' "$raw" | sed -n 's/.*seconds \([0-9.]*\) fps.*/\1/p')
  [ -n "$fps" ] || fps="NA"
  printf '%-22s %8s\n' "$label" "$fps"
  printf '%s,%s,"%s"\n' "$label" "$fps" "$raw" >> "$CSV"
done <<< "$ROWS_IN"

echo
echo "==> $CSV"
echo "==> ranked (best first), baseline for reference:"
awk -F, 'NR>1 && $2!="NA" {printf "  %-22s %8.1f\n", $1, $2}' "$CSV" | sort -k2 -rn
BASE=$(awk -F, '$1=="baseline" && $2!="NA" {print $2}' "$CSV" | head -1)
if [ -n "${BASE:-}" ]; then
  echo
  echo "==> change vs baseline ($BASE fps):"
  awk -F, -v b="$BASE" 'NR>1 && $2!="NA" && $1!="baseline" {
      d=($2-b)/b*100; printf "  %-22s %+7.1f%%\n", $1, d }' "$CSV" | sort -k2 -rn
fi
