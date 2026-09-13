#!/usr/bin/env bash
# Isolated regression tests for join-log.sh's classifier. No ssh, no hardware.
set -euo pipefail

source "$(dirname "$0")/join-log.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# No log at all (engine never wrote one, or died before opening it).
out="$(classify_join_log "$tmp/missing.log" "1.2.3.4:27960")" && exit 1
[[ "$out" == FAIL:* ]]

# A real successful join: CL_InitCGame only prints once the client has a
# gamestate and started the client game module.
cat > "$tmp/ok.log" <<'EOF'
132.145.70.106 resolved to 132.145.70.106:27960
CL_InitCGame:  9.03 seconds
EOF
out="$(classify_join_log "$tmp/ok.log" "132.145.70.106:27960")"
[[ "$out" == PASS:* ]]

# MEASURED 2026-09-13 (yosemite-tiger): a real successful join whose LAST
# "resolved to" line is the authorize server's own, from a resend that fired
# after the join already completed. Must still PASS on CL_InitCGame alone.
cat > "$tmp/ok-with-authorize-noise.log" <<'EOF'
132.145.70.106 resolved to 132.145.70.106:27960
CL_InitCGame:  9.03 seconds
authorize.quake3arena.com resolved to 192.246.40.56:27952
EOF
out="$(classify_join_log "$tmp/ok-with-authorize-noise.log" "132.145.70.106:27960")"
[[ "$out" == PASS:* ]]

# Timed out before a challenge response ever came back -- no CL_InitCGame.
cat > "$tmp/timeout.log" <<'EOF'
132.145.70.106 resolved to 132.145.70.106:27960

Server connection timed out.
EOF
out="$(classify_join_log "$tmp/timeout.log" "132.145.70.106:27960")" && exit 1
[[ "$out" == FAIL:* ]]

# Server dropped the client with its own reason (bad protocol, banned, full).
cat > "$tmp/dropped.log" <<'EOF'
132.145.70.106 resolved to 132.145.70.106:27960
Error: Server is full.
EOF
out="$(classify_join_log "$tmp/dropped.log" "132.145.70.106:27960")" && exit 1
[[ "$out" == FAIL:* ]]

# Resolved to a DIFFERENT address than the one asked for, and never reached
# CL_InitCGame -- a stale autoexec/cl_reconnectArgs firing instead of our
# +connect, not a real pass.
cat > "$tmp/wrongaddr.log" <<'EOF'
10.0.0.5 resolved to 10.0.0.5:27960
EOF
out="$(classify_join_log "$tmp/wrongaddr.log" "132.145.70.106:27960")" && exit 1
[[ "$out" == FAIL:* ]]

echo 'test-join-log: all cases pass'
