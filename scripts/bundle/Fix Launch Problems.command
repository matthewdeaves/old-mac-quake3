#!/bin/sh
# Fix Launch Problems.command - clears quarantine (and the App Translocation
# it causes) and re-registers ioquake3.app with LaunchServices, IN PLACE,
# wherever you have put it. Does NOT install, copy, or move anything.
#
# WORKFLOW: drag everything out of this disk image window (ioquake3.app,
# this file, and the fix-support folder) together to wherever you want the
# game to live -- ~/Applications, /Applications, Desktop, an external drive,
# your call. THEN right-click this file there and choose Open. It fixes
# whatever's sitting next to it; it never decides where your game lives.
# Same fix-in-place convention as quakespasm and alephone ship, per the
# user's own direction 2026-09-02: "the command should come in the dmg to
# be run in same folder as the fat binary etc."
#
# WHY THIS EXISTS: the bundle is unsigned (no paid Apple Developer ID yet --
# CLAUDE.md), so modern macOS quarantines it the moment a browser downloads
# this DMG. A quarantined app copied by hand (not dragged in Finder) can get
# "App Translocation": macOS runs it from a random, sandboxed copy instead of
# the real folder, so it can't find baseq3/ next to it. A README telling a
# person to run `xattr -dr` by hand is not a fix (CLAUDE.md: "Quarantine fix
# must be tooling, not a human step"). This script IS that tooling.
#
# WORKS ON THE WHOLE FLEET (G3/G4/G5 PowerPC, Intel, Apple Silicon), not just
# modern macOS: on Panther/Tiger/Leopard/Lion there is no Gatekeeper/quarantine
# to clear at all, so clear-launch-quarantine.sh below finds nothing and says
# so -- that is a normal outcome there, not an error. This script is plain
# POSIX sh (no bashisms), the same dialect as clear-launch-quarantine.sh, so
# it runs under every /bin/sh on the fleet from Panther forward.
#
# You still have to get THIS script running once via right-click > Open (or
# macOS says it "cannot be opened because it is from an unidentified
# developer") -- that one click is unavoidable without notarization. Nothing
# after it needs Terminal or a manual command.
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
APP="$DIR/ioquake3.app"

echo "ioquake3 - Fix Launch Problems"
echo "==============================="
echo

if [ ! -d "$APP" ]; then
	echo "ERROR: ioquake3.app not found next to this script (looked in $DIR)." >&2
	echo "Drag ioquake3.app out of the disk image together with this file" >&2
	echo "(and the fix-support folder) before running it -- this script fixes" >&2
	echo "the app beside it, it does not install or copy anything for you." >&2
	printf 'Press Return to close this window...'; read -r _
	exit 1
fi

# If $DIR is not writable, ioquake3.app is still sitting on the mounted disk
# image (read-only once it's a real released .dmg -- make-dmg.sh's hard rule
# is -format UDZO). Clearing an xattr or creating baseq3/ there will just
# fail with a confusing error, so catch it here with a clear one instead.
# Detected by testing the actual directory, not guessed from where a DMG
# usually mounts.
if [ ! -w "$DIR" ]; then
	echo "ERROR: $DIR is not writable -- ioquake3.app is still on the mounted" >&2
	echo "disk image. Drag everything in this window out to wherever you want" >&2
	echo "the game to live first, then run this from there." >&2
	printf 'Press Return to close this window...'; read -r _
	exit 1
fi

# baseq3/ holds your Quake III game data (pak0.pk3 ... pak8.pk3). Created
# next to the app if missing; never touched if it already exists, so
# re-running this after a future update keeps your data in place.
if [ ! -d "$DIR/baseq3" ]; then
	mkdir -p "$DIR/baseq3"
	echo "Created $DIR/baseq3 -- put your own pak0.pk3 ... pak8.pk3 there."
fi

# COPY the helpers to local disk before running them -- do NOT exec them
# straight off the mounted image, even now that ioquake3.app itself is fixed
# in place rather than copied. MEASURED 2026-09-02: a real browser-downloaded
# DMG's mounted volume is itself quarantined (and read-only, per above), and
# macOS's AppleSystemPolicy silently SIGKILLs any unsigned executable run
# directly from it -- no dialog, nothing to approve, `killall -0` shows
# nothing wrong, the parent script just sees "Killed: 9" with zero output
# from the child. Confirmed via the unified log:
#   kernel: (AppleSystemPolicy) ASP: Security policy would not allow
#   process: ..., /Volumes/.../fix-support/clear-launch-quarantine.sh
# A plain `cp` off that volume onto local disk moves the SCRIPT out from
# under that specific volume-level block (clear-launch-quarantine.sh, a
# shell script interpreted by the Apple-signed /bin/sh, runs fine right
# after the copy, quarantine xattr and all). It does NOT do the same for a
# raw unsigned Mach-O binary: MEASURED AGAIN the same day, set-bundle-bit
# still got silently SIGKILLed after being copied to plain local disk, xattr
# intact -- that one is the ordinary per-binary Gatekeeper code-signature
# check, which fires on any execve of quarantined unsigned code regardless
# of which volume it lives on, not the DMG-volume-specific block above.
# Fix: strip the xattr off EACH STAGED COPY, individually, right after
# copying it and before running it -- confirmed this alone (no code-signing
# needed) is enough to let set-bundle-bit run. Deliberately not stripped on
# the ORIGINALS under $DIR/fix-support: only the throwaway copy in $STAGE is
# touched, so a re-run always starts from the pristine shipped files again.
STAGE="$DIR/.fix-support-run"
rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT
cp "$DIR/fix-support/set-bundle-bit"              "$STAGE/" 2>/dev/null || true
cp "$DIR/fix-support/clear-launch-quarantine.sh"  "$STAGE/" 2>/dev/null || true
chmod +x "$STAGE/set-bundle-bit" "$STAGE/clear-launch-quarantine.sh" 2>/dev/null || true
xattr -d com.apple.quarantine "$STAGE/set-bundle-bit" "$STAGE/clear-launch-quarantine.sh" 2>/dev/null || true

# Finder bundle-bit (Panther/Tiger only need this; harmless, best-effort
# elsewhere -- same non-fatal pattern as deploy-dmg.sh's own call).
if [ -x "$STAGE/set-bundle-bit" ]; then
	echo
	echo "Setting Finder bundle icon..."
	"$STAGE/set-bundle-bit" "$APP" >/dev/null 2>&1 || true
fi

echo
echo "Clearing quarantine and re-registering with LaunchServices..."
if [ -x "$STAGE/clear-launch-quarantine.sh" ]; then
	"$STAGE/clear-launch-quarantine.sh" "$APP" || true
else
	echo "WARN: fix-support/clear-launch-quarantine.sh missing (did you drag" >&2
	echo "the fix-support folder out too?) -- falling back to plain xattr," >&2
	echo "no LaunchServices re-registration this time." >&2
	xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
fi

echo
echo "Done. ioquake3.app is ready to use, right where it is:"
echo "  $APP"
echo "Double-click it from now on -- no more prompts."
echo
open -R "$APP" 2>/dev/null || true
printf 'Press Return to close this window...'
read -r _ignored
