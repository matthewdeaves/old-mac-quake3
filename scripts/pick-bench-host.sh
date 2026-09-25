#!/bin/sh
# pick-bench-host.sh - path-stable shim onto build-host#105's pinned scripts
# (this repo's shared-scripts.pin). Kept at THIS path: called by fixed local
# path from bench.sh, safebench.sh, deploy.sh, deploy-dmg.sh, smoke-dmg.sh,
# bench-evidence.sh and others, and by Jenkins per manager direction (#71).
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SELF_DIR/shared.sh" pick-bench-host.sh "$@"
