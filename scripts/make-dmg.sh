#!/usr/bin/env bash
# Build a distributable .dmg containing the self-contained ioquake3.app (fat
# ppc750 + ppc7400 + x86_64 binary + the SDL 1.2 dylib inside it) + a
# user-facing README — the easy way to hand the build to the old Macs.
#
# Unlike the Quake II port, ioquake3 ships NO loose runtime libraries: the game
# logic is the cgame/qagame/ui QVMs that live inside the user's own baseq3
# (pak8.pk3), and the SDL 1.2 dylib is bundled INSIDE the .app
# (Contents/MacOS/libSDL-1.2.0.dylib, referenced via @executable_path). So the
# DMG is just the engine .app + README; the player drops it next to their own
# baseq3/ (we ship no copyrighted game data).
#
# usage: scripts/make-dmg.sh [version-label]
#   version-label: e.g. v0.1.0 (default: short HEAD hash)
#
# env: DMG_HOST  Mac to run hdiutil on. DEFAULT: mini-g4 (Tiger 10.4).
#               WHY TIGER, NOT LION OR THE G3 (same finding as the Q1/Q2 ports):
#                 * Lion's hdiutil writes a UDIF container Panther's 2003-vintage
#                   DiskImageMounter can't parse ("no mountable file systems" on
#                   10.3.9). A TIGER-built UDZO mounts on Panther AND everything
#                   newer (old->new compat holds; new->old doesn't). Tiger is the
#                   oldest OS we need for the hdiutil step.
#                 * We avoid the 1999 Panther G3 (flakiest hardware in the fleet
#                   — non-ECC RAM / 25-yr-old disk). The end-to-end content
#                   verification below catches any byte-flip on ANY host, but
#                   there's no reason to build on the worst hardware when a
#                   healthy Tiger box (mini-g4) does the job.
#               The BINARY is always built on Lion (mini-intel) by build-fat.sh;
#               DMG_HOST only runs the hdiutil packaging step on the staged tree.
#               Override DMG_HOST=quicksilver (also Tiger) if mini-g4 is offline.
#
# pre:   build/ioquake3-fat present (scripts/build-fat.sh; built here if missing)
# post:  dist/ioquake3-OldMac-<version>.dmg
#
# One .dmg installs on every supported Mac — the fat binary's three slices
# (ppc750 / ppc7400 / x86_64) + the per-machine autoexec layer mean one disk
# image serves G3 Panther through modern Intel (the G5 runs the ppc7400 slice).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${1:-$(git rev-parse --short HEAD)}"
# Tiger host -> image mounts on Panther->modern (see header). If DMG_HOST is not
# set explicitly, auto-pick the first REACHABLE Tiger box so a powered-off
# mini-g4 doesn't break the default — both write Panther-mountable images.
if [ -z "${DMG_HOST:-}" ]; then
  for cand in mini-g4 quicksilver; do
    if ssh -o ConnectTimeout=6 -o BatchMode=yes "$cand" true 2>/dev/null; then DMG_HOST="$cand"; break; fi
  done
  DMG_HOST="${DMG_HOST:-mini-g4}"
  echo "[make-dmg] DMG_HOST not set — using reachable Tiger host: $DMG_HOST"
fi
VOLNAME="ioquake3 OldMac $VERSION"
OUT="$REPO_ROOT/dist/ioquake3-OldMac-$VERSION.dmg"

FAT="$REPO_ROOT/build/ioquake3-fat"
if [ ! -f "$FAT" ]; then
  echo "[make-dmg] build/ioquake3-fat missing — building it"
  scripts/build-fat.sh
fi
# Sanity: must be the 3-slice fat, not a stray single-arch binary. lipo reads
# the Mach header directly; file(1)'s ppc subtype names vary by host (an
# Apple-silicon box renders ppc750 as "ppc_650"), so lipo -archs is authoritative.
ARCHS=$(lipo -archs "$FAT" 2>/dev/null || echo)
for a in ppc750 ppc7400 x86_64; do
  case " $ARCHS " in
    *" $a "*) ;;
    *) echo "[make-dmg] $FAT is not the 3-arch fat binary (missing $a; got: ${ARCHS:-none}) — run scripts/build-fat.sh" >&2; exit 1;;
  esac
done

# ---- assemble the .app (make-app.sh) + stage the disk-image contents -----
echo "[make-dmg] assemble ioquake3.app"
scripts/make-app.sh >/dev/null
APP_SRC="$REPO_ROOT/build/ioquake3.app"
test -d "$APP_SRC" || { echo "[make-dmg] make-app.sh did not produce $APP_SRC" >&2; exit 1; }

STAGE=$(mktemp -d -t ioq3-dmg.XXXXXX)
trap "rm -rf '$STAGE'" EXIT
IMG="$STAGE/img"                       # becomes the .dmg root
mkdir -p "$IMG"
cp -a "$APP_SRC" "$IMG/ioquake3.app"

cat > "$IMG/README.txt" <<EOF
ioquake3 — OldMac fat build ($VERSION)
======================================

A single universal build of ioquake3 (SDL 1.2 baseline) for vintage Macs:
  • PowerPC G3  (ppc750)   — Mac OS X 10.3 Panther
  • PowerPC G4  (ppc7400)  — Mac OS X 10.4 Tiger  (also runs on the G5 / 10.5)
  • Intel        (x86_64)   — Mac OS X 10.7 Lion and newer
dyld picks the right slice per machine automatically.

INSTALL
-------
1. Drag ioquake3.app to a folder that already contains your Quake III "baseq3"
   directory (your own pak0.pk3 … pak8.pk3 — this image ships NO game data).
   e.g.  ~/Desktop/quake3/ioquake3.app   alongside   ~/Desktop/quake3/baseq3/
2. Double-click ioquake3.app.

The app finds baseq3 in the folder that CONTAINS the .app (it strips its own
bundle path), so keep the .app next to baseq3/.

APPLE WATCH "TACTICAL COMPUTER" COMPANION (optional)
----------------------------------------------------
This build includes watchlink: with the companion iPhone/Apple Watch app on the
same Wi-Fi, your live health / armor / ammo / weapon / score / powerups stream
to your wrist (auto-discovered over Bonjour, UDP 27999). It's enabled per machine
via  seta watch_host "auto"  in baseq3/autoexec.cfg and is otherwise inert.

Project: https://github.com/matthewdeaves/old-mac-quake3
License: GPL-2.0-or-later (see the project repo). Quake III game data is NOT
included and remains under its own commercial license.
EOF

# ---- build the .dmg on a Mac, with END-TO-END content verification -------
# `hdiutil verify` only checks the UDIF container's INTERNAL checksum (that the
# compressed blocks decompress to whatever was stored). It does NOT verify that
# what was stored matches our source — a single byte flipped in the
# rsync->hdiutil chain (bad sector / RAM glitch) passes hdiutil verify and ships
# a corrupt binary (this exact class of bug bit the Q2 port — a flipped opcode
# crashed every G4). So after building, mount the finished image and md5 the
# actual binaries inside it against the source. Retry on mismatch; fail loud.
REMOTE="/tmp/ioq3-dmg-$VERSION"
RSYNC_EXTRA=""
[ "$DMG_HOST" = "yosemite" ] && RSYNC_EXTRA="--protocol=29"   # Panther rsync is 2.5.x

# The corruptible binaries whose fidelity we assert end-to-end. The staged $IMG
# copies are a plain cp -a of build/ioquake3.app, so $IMG md5s ARE the true
# source md5s.
VERIFY_FILES="ioquake3.app/Contents/MacOS/ioquake3 ioquake3.app/Contents/MacOS/libSDL-1.2.0.dylib"
SRC_SUMS=$(cd "$IMG" && for f in $VERIFY_FILES; do \
             printf '%s  %s\n' "$(md5sum "$f" | cut -d' ' -f1)" "$f"; done)

mkdir -p "$REPO_ROOT/dist"

attempt=0; verified=no
while [ "$attempt" -lt 3 ]; do
  attempt=$((attempt + 1))
  echo "[make-dmg] attempt $attempt/3: ship staged image to $DMG_HOST and run hdiutil"
  ssh "$DMG_HOST" "rm -rf '$REMOTE' && mkdir -p '$REMOTE'"
  rsync -a $RSYNC_EXTRA -e 'ssh -o ServerAliveInterval=15' "$IMG/" "$DMG_HOST:$REMOTE/img/"
  # UDZO = zlib-compressed read-only image; widest compatibility incl. Panther.
  ssh "$DMG_HOST" "rm -f '$REMOTE/out.dmg' && \
    hdiutil create -volname '$VOLNAME' -srcfolder '$REMOTE/img' \
      -ov -format UDZO '$REMOTE/out.dmg' && \
    hdiutil verify '$REMOTE/out.dmg' >/dev/null"

  # md5 the binaries INSIDE the finished image (mount -> hash -> detach). Mount
  # at a private mountpoint (not /Volumes) to dodge a stale same-name mount.
  # NB: the file list is hardcoded in the remote script (NOT passed as args) —
  # ssh word-splits a multi-path "$VERIFY_FILES" arg to its first path only.
  # Keep this list in sync with $VERIFY_FILES above.
  DMG_SUMS=$(ssh "$DMG_HOST" bash -s "$REMOTE" <<'REMOTE_EOF' || true
REM="$1"; MP="$REM/mnt"
mkdir -p "$MP"
hdiutil detach "$MP" >/dev/null 2>&1 || true
hdiutil attach -nobrowse -readonly -mountpoint "$MP" "$REM/out.dmg" >/dev/null 2>&1 || exit 7
for f in ioquake3.app/Contents/MacOS/ioquake3 ioquake3.app/Contents/MacOS/libSDL-1.2.0.dylib; do
  printf '%s  %s\n' "$(md5 "$MP/$f" 2>/dev/null | awk '{print $NF}')" "$f"
done
hdiutil detach "$MP" >/dev/null 2>&1 || hdiutil detach -force "$MP" >/dev/null 2>&1 || true
REMOTE_EOF
)
  if [ "$DMG_SUMS" = "$SRC_SUMS" ]; then verified=yes; break; fi
  echo "[make-dmg] WARNING: DMG contents differ from source (attempt $attempt) — retrying" >&2
  echo "--- source ---"; echo "$SRC_SUMS"
  echo "--- in dmg ---"; echo "$DMG_SUMS"
done

[ "$verified" = yes ] || {
  echo "[make-dmg] FATAL: could not produce an uncorrupted DMG after $attempt attempts on $DMG_HOST." >&2
  echo "           The build host may have a failing disk/RAM. Try a different DMG_HOST." >&2
  exit 1
}
echo "[make-dmg] verified: ioquake3 + libSDL-1.2.0.dylib inside the DMG match source byte-for-byte"

# Fetch, then verify scp didn't corrupt the container either.
scp -q "$DMG_HOST:$REMOTE/out.dmg" "$OUT"
RMT_DMG_MD5=$(ssh "$DMG_HOST" "md5 '$REMOTE/out.dmg' | awk '{print \$NF}'")
LCL_DMG_MD5=$(md5sum "$OUT" | cut -d' ' -f1)
[ "$RMT_DMG_MD5" = "$LCL_DMG_MD5" ] || {
  echo "[make-dmg] FATAL: scp corrupted $OUT ($RMT_DMG_MD5 != $LCL_DMG_MD5)" >&2; exit 1; }
ssh "$DMG_HOST" "rm -rf '$REMOTE'" 2>/dev/null || true

echo "[make-dmg] OK — $OUT (contents verified byte-identical to source)"
ls -lh "$OUT"
