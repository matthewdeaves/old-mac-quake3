#!/usr/bin/env bash
# Isolated regression tests for join-log.sh's classifier. No ssh, no hardware.
set -euo pipefail

source "$(dirname "$0")/join-log.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# No log at all (engine never wrote one, or died before opening it).
out="$(classify_join_log "$tmp/missing.log" "1.2.3.4:27960")" && exit 1
[[ "$out" == FAIL:* ]]

# A real successful connect: cl_main.c's own "resolved to" line for the
# requested address, nothing that looks like a failure before it.
cat > "$tmp/ok.log" <<'EOF'
Waiting for handshake...
132.145.70.106 resolved to 132.145.70.106:27960
EOF
out="$(classify_join_log "$tmp/ok.log" "132.145.70.106:27960")"
[[ "$out" == PASS:* ]]

# Timed out before a challenge response ever came back.
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

# Resolved to a DIFFERENT address than the one asked for -- a stale
# autoexec/cl_reconnectArgs firing instead of our +connect, not a real pass.
cat > "$tmp/wrongaddr.log" <<'EOF'
10.0.0.5 resolved to 10.0.0.5:27960
EOF
out="$(classify_join_log "$tmp/wrongaddr.log" "132.145.70.106:27960")" && exit 1
[[ "$out" == FAIL:* ]]

echo 'test-join-log: all cases pass'
