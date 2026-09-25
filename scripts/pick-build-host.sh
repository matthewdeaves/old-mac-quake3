#!/bin/sh
# pick-build-host.sh - path-stable shim onto build-host#105's pinned scripts
# (this repo's shared-scripts.pin). scripts/build.sh calls this by fixed
# local path, so the path stays even though the content is now fetched.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SELF_DIR/shared.sh" pick-build-host.sh "$@"
