#!/usr/bin/env bash
# Pure classifier for join-smoke.sh's captured qconsole.log, split out so it
# can be unit-tested (scripts/test-join-log.sh) without ssh or real hardware,
# same split as deploy-promotion.sh/test-deploy-promotion.sh.
#
# This proves the CLIENT issued a connect and saw no immediate failure. It is
# not proof of a live join by itself -- retro-server-infra#27's pass
# criterion is a client that appears in the server's own player list/connect
# log, which is infra's side to confirm. "resolved to" is the one line
# CL_Connect_f (code/client/cl_main.c) always prints once it has actually
# sent the connect packet to the right address, so it is the cheapest real
# evidence that this is not a no-op.
classify_join_log() {
  local log="$1" want_addr="$2" line
  if [ ! -f "$log" ]; then
    echo "FAIL: no qconsole.log written"
    return 1
  fi
  # Failure signals the client itself prints: an out-of-band timeout/refusal,
  # a bad address, or the server dropping us with a reason string (CL_ParseGamestate's
  # ERR_DROP path in code/client/cl_parse.c prints the server's own reason).
  line="$(grep -iE 'connection timed out|bad server address|could not resolve|^Error: ' "$log" | tail -1)"
  if [ -n "$line" ]; then
    echo "FAIL: $line"
    return 1
  fi
  line="$(grep -iE 'resolved to' "$log" | tail -1)"
  if [ -z "$line" ]; then
    echo "FAIL: no connect attempt seen (\"resolved to\" line missing)"
    return 1
  fi
  case "$line" in
    *"$want_addr"*) echo "PASS: $line"; return 0 ;;
    *) echo "FAIL: connected to the wrong address ($line, wanted $want_addr)"; return 1 ;;
  esac
}
