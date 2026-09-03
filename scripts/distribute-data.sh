#!/usr/bin/env bash
#
# distribute-data.sh <machine> — copy the baseq3 game data (9 pk3s, ~482M) from
# mini-intel (the only machine with Quake III installed) to a bench machine's
# ~/quake3/baseq3/. Relays through a local cache because the PPC/old
# Macs are NOT in mini-intel's ssh config — only this orchestration host can
# reach the whole fleet. Idempotent: rsync only ships missing/changed pk3s.
#
# NEVER touches the read-only install at mini-intel:/Users/mini/Games/ioquake3.
# Source is the staged copy at mini-intel:~/quake3/baseq3/.
#
set -euo pipefail

MACHINE="${1:?usage: distribute-data.sh <yosemite|yosemite-tiger|sawtooth|quicksilver|mini-g4|imac-2019|imac-g5|g5-panther|g5-tiger|g5-desktop|quad-tiger|quad-leopard|workstation>}"

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
	exec "$_PICK" --run "$MACHINE" "distribute-data" -- "$0" "$@"
fi
SRC_HOST="${SRC_HOST:-mini-intel}"
# shellcheck disable=SC2088
# both tildes stay unexpanded on purpose: they
# must resolve on the REMOTE host's home, not this workstation's. See ci.yml.
SRC_DIR="~/quake3/baseq3"
PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$PROJ_LOCAL/build/baseq3-cache"        # gitignored (under build/)
# shellcheck disable=SC2088
# tilde stays unexpanded on purpose: it must resolve on the REMOTE host's
# home, not this workstation's. See ci.yml.
REMOTE_DIR="~/quake3/baseq3"
ONLY_PK3=(--include='*.pk3' --include='*.PK3' --exclude='*')

case "$MACHINE" in
  yosemite|yosemite-tiger|sawtooth|quicksilver|mini-g4|mini-intel|imac-2019|imac-g5|workstation) ;;
  # Multi-boot G5 aliases (ticketing-workflow.md): three OS partitions on the
  # G5 Dual 2.7 (g5-panther/g5-tiger/g5-desktop), two on the G5 Quad
  # (quad-tiger/quad-leopard). Missing from this list until a fresh boot
  # round made g5-panther reachable and this script refused it outright -
  # not a deliberate exclusion, just never added when these aliases came
  # online. Same rsync path as every other alias; nothing else changes.
  g5-panther|g5-tiger|g5-desktop|quad-tiger|quad-leopard) ;;
  *) echo "distribute-data.sh: unknown machine '$MACHINE'"; exit 2 ;;
esac
[ "$MACHINE" = "$SRC_HOST" ] && { echo "$MACHINE is the data source — nothing to do."; exit 0; }

RSYNC_EXTRA=""
[ "$MACHINE" = yosemite ] && RSYNC_EXTRA="--protocol=29"   # Panther rsync is 2.5.x

mkdir -p "$CACHE"
echo "==> cache baseq3 pk3s from $SRC_HOST -> $CACHE (first time pulls ~482M)"
rsync -av --partial "${ONLY_PK3[@]}" "$SRC_HOST:$SRC_DIR/" "$CACHE/"

# `workstation` is this machine itself (docs/adr/0019, pick-bench-host.sh's
# LOCAL_ALIASES) - no sshd, no hostkey, so ship via a local copy instead of
# ssh+rsync-over-network, into THIS host's own home, not a remote tilde.
if [ "$MACHINE" = workstation ]; then
	LOCAL_DIR="$HOME/Desktop/quake3/baseq3"
	echo "==> ship pk3s -> workstation:$LOCAL_DIR (local copy)"
	mkdir -p "$LOCAL_DIR"
	rsync -av --partial "${ONLY_PK3[@]}" "$CACHE/" "$LOCAL_DIR/"

	echo "==> verify on workstation"
	( cd "$LOCAL_DIR" && echo -n '  pk3 count: ' && ls ./*.[pP][kK]3 2>/dev/null | wc -l && du -ch ./*.[pP][kK]3 2>/dev/null | tail -1 | sed 's/^/  total: /' )
else
	echo "==> ship pk3s -> $MACHINE:$REMOTE_DIR"
	ssh "$MACHINE" "mkdir -p $REMOTE_DIR"
	rsync -av --partial $RSYNC_EXTRA "${ONLY_PK3[@]}" "$CACHE/" "$MACHINE:$REMOTE_DIR/"

	echo "==> verify on $MACHINE"
	ssh "$MACHINE" "cd $REMOTE_DIR && echo -n '  pk3 count: ' && ls *.[pP][kK]3 2>/dev/null | wc -l && du -ch *.[pP][kK]3 2>/dev/null | tail -1 | sed 's/^/  total: /'"
fi
echo "==> [$MACHINE] data distributed."
