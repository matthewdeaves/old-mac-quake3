#!/bin/sh
# Fix-and-Install.command - one-click install for the ioquake3 disk image.
#
# WHY THIS EXISTS: the bundle is unsigned (no paid Apple Developer ID yet --
# CLAUDE.md), so modern macOS quarantines it the moment a browser downloads
# this DMG. A quarantined app copied by hand (not dragged in Finder) can get
# "App Translocation": macOS runs it from a random, sandboxed copy instead of
# the real folder, so it can't find baseq3/ next to it. A README telling a
# person to run `xattr -dr` by hand is not a fix (CLAUDE.md: "Quarantine fix
# must be tooling, not a human step"). This script IS that tooling: it
# installs the app AND clears the flag, so every launch after this one is a
# plain double-click. Same fix quakespasm and alephone shipped for the same
# imac-2019 launch failure (2026-09-02).
#
# WORKS ON THE WHOLE FLEET (G3/G4/G5 PowerPC, Intel, Apple Silicon), not just
# modern macOS: on Panther/Tiger/Leopard/Lion there is no Gatekeeper/quarantine
# to clear at all, so clear-launch-quarantine.sh below finds nothing and says
# so -- that is a normal outcome there, not an error. This script is plain
# POSIX sh (no bashisms), the same dialect as clear-launch-quarantine.sh, so
# it runs under every /bin/sh on the fleet from Panther's forward.
#
# You still have to get THIS script running once via right-click > Open (or
# macOS says it "cannot be opened because it is from an unidentified
# developer") -- that one click is unavoidable without notarization. Nothing
# after it needs Terminal or a manual command.
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DEST="$HOME/Applications/quake3"

echo "ioquake3 - Fix and Install"
echo "==========================="
echo

if [ ! -d "$DIR/ioquake3.app" ]; then
	echo "ERROR: ioquake3.app not found next to this script (looked in $DIR)." >&2
	echo "Run this from the mounted disk image, not a copy of just this file." >&2
	printf 'Press Return to close this window...'; read -r _
	exit 1
fi

mkdir -p "$DEST"
echo "Installing to: $DEST"

# cp -a, NOT cp -R: -R follows symlinks and can flatten a framework into a
# second real copy; -a preserves the bundle's resource forks / xattrs as-is
# (make-dmg.sh's own reasoning for the same flag when it first stages the
# bundle onto the image).
rm -rf "$DEST/ioquake3.app"
cp -a "$DIR/ioquake3.app" "$DEST/"

# baseq3/ holds your Quake III game data (pak0.pk3 ... pak8.pk3). Never
# touched if it already exists, so re-running this after an update keeps your
# data -- same "preserve game data" contract as scripts/deploy-dmg.sh.
if [ ! -d "$DEST/baseq3" ]; then
	mkdir -p "$DEST/baseq3"
	echo "Created $DEST/baseq3 -- put your own pak0.pk3 ... pak8.pk3 there."
fi

# Finder bundle-bit (Panther/Tiger only need this; harmless, best-effort
# elsewhere -- same non-fatal pattern as deploy-dmg.sh's own call). Bundled
# under a hidden dir since this script runs standalone off the mounted image,
# with no repo checkout beside it.
mkdir -p "$DIR/.fix-support"
if [ -x "$DIR/.fix-support/set-bundle-bit" ]; then
	echo
	echo "Setting Finder bundle icon..."
	"$DIR/.fix-support/set-bundle-bit" "$DEST/ioquake3.app" >/dev/null 2>&1 || true
fi

echo
echo "Clearing quarantine..."
if [ -x "$DIR/.fix-support/clear-launch-quarantine.sh" ]; then
	"$DIR/.fix-support/clear-launch-quarantine.sh" "$DEST/ioquake3.app" || true
else
	echo "WARN: clear-launch-quarantine.sh missing from this image, falling back to plain xattr" >&2
	xattr -dr com.apple.quarantine "$DEST/ioquake3.app" >/dev/null 2>&1 || true
fi

echo
echo "Done. ioquake3.app is installed at:"
echo "  $DEST/ioquake3.app"
echo "Double-click it from there from now on -- no more prompts."
echo
open -R "$DEST/ioquake3.app" 2>/dev/null || true
printf 'Press Return to close this window...'
read -r _ignored
