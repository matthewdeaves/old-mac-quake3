#!/bin/sh
# bench-evidence.sh - path-stable shim, see scripts/pick-build-host.sh's
# header for why this is a shim. Needs BENCH_ADAPTER set explicitly: the
# pinned bench-evidence.sh looks for bench-adapter.sh next to ITSELF once it
# runs from the pin cache, not next to this shim (same class of gap as
# deploy-dmg.sh/smoke-dmg.sh's DMG_PORT_CONF, build-host#105 pilot finding).
# bench-adapter.sh itself is port-owned and never synced (see its own header).
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec env BENCH_ADAPTER="$SELF_DIR/bench-adapter.sh" "$SELF_DIR/shared.sh" bench-evidence.sh "$@"
