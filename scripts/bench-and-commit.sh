#!/usr/bin/env bash
#
# bench-and-commit.sh "<phase>" [parallel-bench args...] — clean-tree bench,
# then commit the rows tagged to HEAD. Refuses a dirty tree (bench data must
# attribute to a real commit). Two commits per phase: code first, then this.
# Adapted from ~/quakespasm/scripts. v0 DRAFT.
#
set -uo pipefail

PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
CSV="$PROJ_LOCAL/benchmarks/results.csv"
DESC="${1:?usage: bench-and-commit.sh \"<phase>\" [--quick|--reset|--no-<machine> ...]}"
shift || true

[ -z "$(git -C "$PROJ_LOCAL" status --porcelain)" ] || {
  echo "bench-and-commit: working tree is dirty — commit the code change first."; exit 2; }

export COMMIT="$(git -C "$PROJ_LOCAL" rev-parse --short HEAD)"
before=$(grep -c ",$COMMIT," "$CSV" 2>/dev/null || echo 0)

"$HERE/parallel-bench.sh" "$@" || { echo "bench-and-commit: bench leg failed."; exit 3; }

after=$(grep -c ",$COMMIT," "$CSV" 2>/dev/null || echo 0)
[ "$after" -gt "$before" ] || { echo "bench-and-commit: no new rows landed for $COMMIT."; exit 1; }

summary=$(grep ",$COMMIT," "$CSV" | awk -F, '{printf "  %-12s %-8s %-9s %s fps\n",$3,$4,$5,$9}' | sort)
shopt -s nullglob
git -C "$PROJ_LOCAL" add benchmarks/results.csv benchmarks/raw/"${COMMIT}"_*.log
git -C "$PROJ_LOCAL" commit -q -F - <<EOF
bench: $DESC (HEAD $COMMIT)

$summary
EOF
echo "==> committed bench rows for $COMMIT"
