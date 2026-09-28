#!/bin/sh
# launch-game.sh - path-stable shim onto build-host#147's pinned launch guard
# (this repo's shared-scripts.pin), see scripts/pick-build-host.sh's header.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SELF_DIR/shared.sh" launch-game.sh "$@"
