#!/usr/bin/env bash
#
# distribute-data.sh <machine> — copy the baseq3 game data (9 pk3s, ~482M) from
# mini-intel (the only machine with Quake III installed) to a bench machine's
# ~/Desktop/quake3/baseq3/. Relays through a local cache because the PPC/old
# Macs are NOT in mini-intel's ssh config — only this orchestration host can
# reach the whole fleet. Idempotent: rsync only ships missing/changed pk3s.
#
# NEVER touches the read-only install at mini-intel:/Users/mini/Games/ioquake3.
# Source is the staged copy at mini-intel:~/Desktop/quake3/baseq3/.
#
set -euo pipefail

MACHINE="${1:?usage: distribute-data.sh <yosemite|sawtooth|quicksilver|mini-g4|imac-2019|imac-g5>}"
SRC_HOST="${SRC_HOST:-mini-intel}"
SRC_DIR="~/Desktop/quake3/baseq3"
PROJ_LOCAL="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$PROJ_LOCAL/build/baseq3-cache"        # gitignored (under build/)
REMOTE_DIR="~/Desktop/quake3/baseq3"
ONLY_PK3=(--include='*.pk3' --include='*.PK3' --exclude='*')

case "$MACHINE" in
  yosemite|sawtooth|quicksilver|mini-g4|mini-intel|imac-2019|imac-g5) ;;
  *) echo "distribute-data.sh: unknown machine '$MACHINE'"; exit 2 ;;
esac
[ "$MACHINE" = "$SRC_HOST" ] && { echo "$MACHINE is the data source — nothing to do."; exit 0; }

RSYNC_EXTRA=""
[ "$MACHINE" = yosemite ] && RSYNC_EXTRA="--protocol=29"   # Panther rsync is 2.5.x

mkdir -p "$CACHE"
echo "==> cache baseq3 pk3s from $SRC_HOST -> $CACHE (first time pulls ~482M)"
rsync -av --partial "${ONLY_PK3[@]}" "$SRC_HOST:$SRC_DIR/" "$CACHE/"

echo "==> ship pk3s -> $MACHINE:$REMOTE_DIR"
ssh "$MACHINE" "mkdir -p $REMOTE_DIR"
rsync -av --partial $RSYNC_EXTRA "${ONLY_PK3[@]}" "$CACHE/" "$MACHINE:$REMOTE_DIR/"

echo "==> verify on $MACHINE"
ssh "$MACHINE" "cd $REMOTE_DIR && echo -n '  pk3 count: ' && ls *.[pP][kK]3 2>/dev/null | wc -l && du -ch *.[pP][kK]3 2>/dev/null | tail -1 | sed 's/^/  total: /'"
echo "==> [$MACHINE] data distributed."
