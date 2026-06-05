#!/usr/bin/env bash
# Install the release DMG onto a target Mac *exactly the way an end user would*:
# copy the .dmg to the Desktop, mount it, copy ioquake3.app into
# ~/Desktop/quake3/, then unmount. This is deliberately the DMG path (not
# deploy.sh's direct rsync) so the test loop exercises the same artifact and the
# same install steps a human performs (where the Q2 port's corrupt-DMG bug hid).
#
# usage: scripts/deploy-dmg.sh <machine> [version]
#   machine: yosemite | sawtooth | quicksilver | mini-g4 | imac-g5 | mini-intel | imac-2019 (ssh alias)
#   version: e.g. v0.1.0  (default: newest dist/ioquake3-OldMac-*.dmg)
#
# Preserves the user's game data: baseq3/*.pk3 and any q3config.cfg/autoexec.cfg
# are left untouched; only ioquake3.app is (re)installed.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HOST="${1:?usage: $0 <machine> [version]}"
VERSION="${2:-}"
case "$HOST" in
  yosemite|sawtooth|quicksilver|mini-g4|imac-g5|mini-intel|imac-2019) ;;
  *) echo "deploy-dmg: unknown machine '$HOST'" >&2; exit 2 ;;
esac
if [ -z "$VERSION" ]; then
  DMG=$(ls -t "$REPO_ROOT"/dist/ioquake3-OldMac-*.dmg 2>/dev/null | head -1)
  [ -n "$DMG" ] || { echo "no dist/ioquake3-OldMac-*.dmg found — run scripts/make-dmg.sh" >&2; exit 1; }
else
  DMG="$REPO_ROOT/dist/ioquake3-OldMac-$VERSION.dmg"
  [ -f "$DMG" ] || { echo "missing $DMG" >&2; exit 1; }
fi
DMG_BASE=$(basename "$DMG")

echo "[deploy-dmg $HOST] copy $DMG_BASE to ~/Desktop/"
ssh "$HOST" 'mkdir -p ~/Desktop'
scp -q "$DMG" "$HOST:Desktop/$DMG_BASE"

# Verify the .dmg arrived intact (md5 local vs remote) — defence in depth on top
# of make-dmg.sh's own end-to-end content check.
LCL_MD5=$(md5sum "$DMG" | cut -d' ' -f1)
RMT_MD5=$(ssh "$HOST" "md5 'Desktop/$DMG_BASE' | awk '{print \$NF}'")
[ "$LCL_MD5" = "$RMT_MD5" ] || { echo "[deploy-dmg $HOST] FATAL: scp corrupted the DMG ($LCL_MD5 != $RMT_MD5)" >&2; exit 1; }
echo "[deploy-dmg $HOST] DMG on Desktop verified intact ($RMT_MD5)"

echo "[deploy-dmg $HOST] mount + install ioquake3.app into ~/Desktop/quake3/ (preserving game data)"
ssh "$HOST" bash -s "$DMG_BASE" <<'REMOTE_EOF'
set -e
DMG_BASE="$1"
MNT="$HOME/ioq3install-mnt"
DEST="$HOME/Desktop/quake3"

# fresh mountpoint — detach any stale attach, then rmdir (NEVER rm -rf a path
# that might still be a mounted read-only volume).
hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach -force "$MNT" >/dev/null 2>&1 || true
rmdir "$MNT" 2>/dev/null || true
mkdir -p "$MNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$HOME/Desktop/$DMG_BASE" >/dev/null

mkdir -p "$DEST/baseq3"

# md5 helper (portable Panther->Lion: `md5` prints "MD5 (f) = HASH").
_md5() { md5 "$1" 2>/dev/null | awk '{print $NF}'; }

# Replace the app wholesale so no stale bundle files survive. ditto keeps the
# bundle bit, perms (+x on the binary) and resource forks. Verify the binary
# inside the installed bundle byte-for-byte (with a ditto retry) since that is
# the executable that actually runs — the old Macs' aging disks/RAM can flip a
# byte in a copy that loads but misbehaves.
APP_BIN="ioquake3.app/Contents/MacOS/ioquake3"
appok=no
for k in 1 2 3 4; do
  rm -rf "$DEST/ioquake3.app"; ditto "$MNT/ioquake3.app" "$DEST/ioquake3.app"; sync
  if [ "$(_md5 "$DEST/$APP_BIN")" = "$(_md5 "$MNT/$APP_BIN")" ]; then appok=yes; break; fi
  echo "  [verify] app binary mismatch (try $k) — re-dittoing" >&2; sleep 1
done
[ "$appok" = yes ] || { echo "  FATAL: app binary still corrupt after retries" >&2; exit 7; }
echo "  [verify] installed ioquake3 binary matches the image byte-for-byte"

# Also keep the loose ./ioquake3 + libSDL the rsync deploy.sh uses in sync, so
# bench.sh (which runs ./ioquake3) and the DMG path agree. Pull both out of the
# bundle we just verified.
cp -p "$DEST/ioquake3.app/Contents/MacOS/ioquake3"            "$DEST/ioquake3"            && chmod +x "$DEST/ioquake3" || true
cp -p "$DEST/ioquake3.app/Contents/MacOS/libSDL-1.2.0.dylib"  "$DEST/libSDL-1.2.0.dylib"  || true

# Set the Finder bundle bit so Panther/Tiger show the app icon, not a folder.
if [ -x "$DEST/.set-bundle-bit" ]; then
  "$DEST/.set-bundle-bit" "$DEST/ioquake3.app" >/dev/null 2>&1 || true
fi

# detach — retry until the slow-disk flush completes; only THEN rmdir the now-
# empty mountpoint.
detached=no
for k in 1 2 3 4 5; do
  if hdiutil detach "$MNT" >/dev/null 2>&1; then detached=yes; break; fi
  sleep 2
done
[ "$detached" = yes ] || hdiutil detach -force "$MNT" >/dev/null 2>&1 || true
rmdir "$MNT" 2>/dev/null || true

# Tidy: drop any OTHER ioquake3-OldMac-*.dmg left on the Desktop from previous
# rounds — keep only the one we just installed from (small disks).
for old in "$HOME"/Desktop/ioquake3-OldMac-*.dmg; do
  [ -e "$old" ] || continue
  if [ "$(basename "$old")" != "$DMG_BASE" ]; then
    rm -f "$old" && echo "removed old image $(basename "$old")"
  fi
done

echo "app binary archs:"
file "$DEST/ioquake3.app/Contents/MacOS/ioquake3" 2>/dev/null | sed 's/^/  /' || true
REMOTE_EOF

echo "[deploy-dmg $HOST] done — installed from $DMG_BASE"
