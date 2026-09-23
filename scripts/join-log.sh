#!/usr/bin/env bash
# Pure classifier for join-smoke.sh's captured qconsole.log, split out so it
# can be unit-tested (scripts/test-join-log.sh) without ssh or real hardware.
#
# This proves the CLIENT actually joined a live game, not just that it sent a
# connect packet. retro-server-infra#27's pass criterion is a client that
# appears in the server's own player list/connect log, which is infra's side
# to confirm -- this is the client-side half.
#
# MEASURED 2026-09-13 on yosemite-tiger against a real server: a plain
# "resolved to" grep is a false negative. Whenever the target server does not
# answer the FIRST getchallenge fast enough, CL_CheckForResend's periodic
# resend also calls CL_RequestAuthorization() (code/client/cl_main.c), which
# prints its OWN "authorize.quake3arena.com resolved to ..." line using the
# exact same wording -- and it keeps re-printing on every resend, so it is
# often the LAST "resolved to" line in the log even on a run that joined fine
# seconds earlier. "CL_InitCGame" (cl_cgame.c) is the real signal: it is only
# printed after the client has received a gamestate from the server and
# started the client game module, i.e. an actual join, not just a connect
# attempt. That is what this now checks first.
classify_join_log() {
  local log="$1" want_addr="$2" line
  if [ ! -f "$log" ]; then
    echo "FAIL: no qconsole.log written"
    return 1
  fi
  line="$(grep -iE 'CL_InitCGame' "$log" | tail -1)"
  if [ -n "$line" ]; then
    echo "PASS: $line"
    return 0
  fi
  # Didn't reach CL_InitCGame -- check for the client's own failure signals:
  # an out-of-band timeout/refusal, a bad address, or the server dropping us
  # with a reason string (CL_ParseGamestate's ERR_DROP path in
  # code/client/cl_parse.c prints the server's own reason).
  line="$(grep -iE 'connection timed out|bad server address|could not resolve|^Error: ' "$log" | tail -1)"
  if [ -n "$line" ]; then
    echo "FAIL: $line"
    return 1
  fi
  # Weakest signal, kept as a fallback for a log with neither CL_InitCGame nor
  # an explicit failure line: did the client even attempt to reach $want_addr.
  line="$(grep -iE 'resolved to' "$log" | grep -F "$want_addr" | tail -1)"
  if [ -n "$line" ]; then
    echo "FAIL: connect attempted but never reached CL_InitCGame ($line)"
    return 1
  fi
  echo "FAIL: no connect attempt to $want_addr seen, and no CL_InitCGame"
  return 1
}
