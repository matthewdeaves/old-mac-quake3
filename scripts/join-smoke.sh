#!/usr/bin/env bash
# Real-client join smoke test for retro-server-infra#27's join matrix: launch
# the installed /Applications/Quake3 build on HOST, +connect it to ADDR,
# capture qconsole.log, and report PASS/FAIL with the connect line.
#
# This is CLIENT-side evidence only. retro-server-infra#27's pass criterion
# is a client that appears in the server's own player list/connect log —
# infra confirms that side separately; this script cannot and does not
# claim it. See scripts/join-log.sh for what PASS/FAIL is based on.
#
# usage: scripts/join-smoke.sh <host> <ip:port>
#   host: yosemite[-tiger] | sawtooth | quicksilver | mini-g4 | imac-g5 |
#         g5-{panther,tiger,desktop} | quad-{tiger,leopard} | mini-sl |
#         mini-intel[2] | imac-2019 | workstation
#
# NEVER killall -KILL a fullscreen ioquake3 — wedges the GPU driver and hangs
# the WindowServer until reboot (docs/adr/0009). TERM only, same pattern as
# smoke-dmg.sh, including its reboot backstop when TERM doesn't take (#29) —
# except on `workstation`, which is never rebooted: it's the interactive Mac
# a session itself may be running on, not an idle bench box.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/join-log.sh"

HOST="${1:?usage: $0 <host> <ip:port>}"
ADDR="${2:?usage: $0 <host> <ip:port>}"
REMOTE_DIR="/Applications/Quake3"

# Claim this machine for the whole run — see pick-bench-host.sh. `workstation`
# needs no claim: it is this machine itself (docs/adr/0019), and --run treats
# it as a local, no-ssh alias already.
_PICK="$HERE/pick-bench-host.sh"
if [ "${RETRO_BENCH_LOCK:-}" != "$HOST" ] && [ "${BENCH_NO_LOCK:-0}" != 1 ] && [ -x "$_PICK" ]; then
  export RETRO_BENCH_LOCK="$HOST"
  exec "$_PICK" --run "$HOST" "join-smoke" -- "$0" "$HOST" "$ADDR"
fi

case "$HOST" in
  yosemite|yosemite-tiger|sawtooth|quicksilver|mini-g4|imac-g5|g5-panther|g5-tiger|g5-desktop|quad-tiger|quad-leopard|mini-sl|mini-intel|mini-intel2|imac-2019|workstation) ;;
  *) echo "join-smoke: unknown machine '$HOST'" >&2; exit 2 ;;
esac

WAIT_SECS="${JOIN_WAIT:-25}"
LOCAL_LOG="$(mktemp)"
trap 'rm -f "$LOCAL_LOG"' EXIT

if [ "$HOST" = workstation ]; then
  BUSY="$(ps ax 2>/dev/null | grep -i ioquake3 | grep -v grep || true)"
  if [ -n "$BUSY" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "join-smoke workstation: ABORT — already running a game:" >&2
    echo "$BUSY" | sed 's/^/    /' >&2
    exit 2
  fi
  ( cd "$REMOTE_DIR" && mv -f baseq3/qconsole.log baseq3/qconsole.log.prev 2>/dev/null
    open -n ./ioquake3.app --args +set fs_homepath "$REMOTE_DIR" +set logfile 2 +connect "$ADDR" >/dev/null 2>&1 & )
  sleep "$WAIT_SECS"
  cp "$REMOTE_DIR/baseq3/qconsole.log" "$LOCAL_LOG" 2>/dev/null || true
  killall -TERM ioquake3 2>/dev/null || true
  g=0; while [ "$g" -lt 10 ]; do pgrep -x ioquake3 >/dev/null 2>&1 || break; sleep 1; g=$((g+1)); done
else
  BUSY="$(ssh "$HOST" "ps ax 2>/dev/null | grep -i ioquake3 | grep -v grep || true")"
  if [ -n "$BUSY" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "join-smoke $HOST: ABORT — already running a game (shared bench):" >&2
    echo "$BUSY" | sed 's/^/    /' >&2
    exit 2
  fi

  # Same open-vs-direct-exec split as smoke-dmg.sh: `open --args` does not
  # exist before Snow Leopard.
  OPEN_ARGS_OK=0
  case "$(ssh -o ConnectTimeout=10 "$HOST" 'sw_vers -productVersion' 2>/dev/null)" in
    10.[0-5].*|10.[0-5]) OPEN_ARGS_OK=0 ;;
    10.*|11.*|12.*|13.*|14.*|15.*|16.*|26.*) OPEN_ARGS_OK=1 ;;
    *) OPEN_ARGS_OK=0 ;;
  esac

  if [ "$OPEN_ARGS_OK" = 1 ]; then
    LAUNCH='open -n ./ioquake3.app --args +set fs_homepath "$PWD" +set logfile 2 +connect '"$ADDR"' >/dev/null 2>&1 &'
  else
    LAUNCH='./ioquake3.app/Contents/MacOS/ioquake3 +set fs_basepath "$PWD" +set fs_homepath "$PWD" +set logfile 2 +connect '"$ADDR"' >/dev/null 2>&1 &'
  fi

  ssh "$HOST" "
    cd $REMOTE_DIR || { echo NO_INSTALL; exit 9; }
    mv -f baseq3/qconsole.log baseq3/qconsole.log.prev 2>/dev/null || true
    $LAUNCH
    sleep $WAIT_SECS
    killall -TERM ioquake3 2>/dev/null || true
    g=0; while [ \$g -lt 10 ]; do killall -0 ioquake3 2>/dev/null || break; sleep 1; g=\$((g+1)); done
    true"

  # Reboot backstop, same as smoke-dmg.sh (#29): TERM sometimes doesn't take,
  # and a fullscreen ioquake3 must never be left running unclaimed or KILLed.
  if ssh "$HOST" 'killall -0 ioquake3 2>/dev/null'; then
    echo "join-smoke $HOST: engine SURVIVED TERM and is still running; rebooting (#29 pattern)" >&2
    # shellcheck disable=SC2088
    # tilde stays unexpanded on purpose: it must resolve on the REMOTE host's
    # home, not this workstation's. See ci.yml / smoke-dmg.sh.
    ssh "$HOST" '~/bin/qsreboot.sh' 2>/dev/null || true
    t=0; while [ "$t" -lt 60 ]; do ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" true 2>/dev/null || break; sleep 5; t=$((t+5)); done
    if [ "$t" -ge 60 ]; then
      echo "join-smoke $HOST: FAIL — did not go down, reboot failed (run sudo ~/bin/qsreboot-setup.sh)" >&2
      exit 1
    fi
    t=0; while [ "$t" -lt 240 ]; do ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" true 2>/dev/null && break; sleep 5; t=$((t+5)); done
    [ "$t" -ge 240 ] && echo "join-smoke $HOST: did not come back within 240s" >&2 || echo "join-smoke $HOST: back up, engine cleared" >&2
  fi

  scp -q "$HOST:$REMOTE_DIR/baseq3/qconsole.log" "$LOCAL_LOG" 2>/dev/null || true
  "$HERE/lsregister-app.sh" "$HOST" >/dev/null 2>&1 || true
fi

set +e
RESULT="$(classify_join_log "$LOCAL_LOG" "$ADDR")"
RC=$?
set -e
echo "join-smoke $HOST: $RESULT"
exit "$RC"
