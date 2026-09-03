#!/usr/bin/env bash
# Build a distributable .dmg containing the self-contained ioquake3.app (fat
# ppc750 + ppc7400 + x86_64 binary + the SDL 1.2 dylib inside it) + a
# user-facing README — the easy way to hand the build to the old Macs.
#
# ioquake3 ships NO loose runtime libraries next to the app: the SDL 1.2 dylib is
# bundled INSIDE the .app (Contents/MacOS/libSDL-1.2.0.dylib, via @executable_path),
# and so are our native game modules (Contents/MacOS/baseq3/{cgame,qagame,ui}{ppc,
# x86_64}.dylib — fat ppc750+ppc7400 + x86_64, loaded in place of the user's pak8
# QVM; see make-app.sh / build-gamedylibs.sh). So the DMG is just the engine .app +
# README; the player drops it next to their own baseq3/ (we ship no game data).
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
# One .dmg installs on every supported Mac — the fat binary's five slices
# (ppc750 / ppc7400 / x86_64 / i386 / arm64) + the per-machine autoexec layer
# mean one disk image serves G3 Panther through Apple Silicon (the G5 runs the
# ppc7400 slice; there is no ppc970). Verify with `lipo -archs`, not this line.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${1:-$(git rev-parse --short HEAD)}"
# Tiger host -> image mounts on Panther->modern (see header).
#
# PICK A HOST WE CAN CLAIM, NOT ONE THAT MERELY ANSWERS. This used to select the
# first REACHABLE Tiger box and then, at line ~247, run `rm -rf` on it. Reachable
# is not free: a box another session is benching or building on answers ssh
# perfectly well. Fixed 2026-08-22, same class as the parallel-bench pre-kill and
# the missing safebench claim.
#
# We re-exec under the picker rather than acquiring here and trapping, because
# this script installs its own EXIT trap for $STAGE below and bash traps REPLACE
# rather than compose, so a release trap set here would be silently discarded and
# the machine would stay claimed until the stale reclaim.
#
# The acquire below is a probe to choose between candidates, released at once so
# the --run can take it properly. That leaves a small window where another
# session could take the box between the probe and the run; --run then fails and
# says so, which is the correct outcome and is still far better than the previous
# behaviour of taking no lock at all.
_PICK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pick-bench-host.sh"
if [ -z "${RETRO_BENCH_LOCK:-}" ] && [ "${BENCH_NO_LOCK:-0}" != 1 ] && [ -x "$_PICK" ]; then
  # Export a claim nonce before the probe acquire below. Without it the probe
  # writes an owner file with no claim= and releases by matching user@host:repo,
  # which is identical for every session in this repo. Two scripts in the whole
  # fleet were still doing that and this was one of them; it is also why the
  # picker cannot yet drop its old-format fallback, because a claim-less writer
  # still has to be able to release itself. old-mac-build-host#7, #24.
  #
  # The exec below inherits this, so the --run acquire and its release use the
  # same nonce too.
  export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-$$.$(date +%s).${RANDOM:-0}}"
  _cands="${DMG_HOST:-mini-g4 quicksilver}"
  for cand in $_cands; do
    if "$_PICK" --acquire "$cand" "quake3 make-dmg probe" >/dev/null 2>&1; then
      "$_PICK" --release "$cand" >/dev/null 2>&1
      echo "[make-dmg] claiming Tiger host: $cand"
      export RETRO_BENCH_LOCK="$cand" DMG_HOST="$cand"
      exec "$_PICK" --run "$cand" "quake3 make-dmg" -- "$0" "$@"
    fi
    echo "[make-dmg] $cand is busy or unreachable, trying next"
  done
  echo "make-dmg: no free Tiger G4 (tried: $_cands). See pick-bench-host.sh --status" >&2
  exit 1
fi
DMG_HOST="${DMG_HOST:?DMG_HOST must be set by the claim above}"
VOLNAME="ioquake3 OldMac $VERSION"
OUT="$REPO_ROOT/dist/ioquake3-OldMac-$VERSION.dmg"

FAT="$REPO_ROOT/build/ioquake3-fat"
if [ ! -f "$FAT" ]; then
  echo "[make-dmg] build/ioquake3-fat missing — building it"
  scripts/build-fat.sh
fi
# Sanity: must be the 3-slice fat, not a stray single-arch binary. Prefer lipo
# (reads the Mach header directly) but this orchestration host is Linux with NO
# lipo — build-fat.sh lipo's remotely on mini-intel. So fall back to file(1),
# normalising its host-varying ppc subtype spelling (ppc_750 / ppc750 / ppc_650).
if command -v lipo >/dev/null 2>&1; then
  ARCHS=$(lipo -archs "$FAT" 2>/dev/null || echo)
else
  ARCHS=$(file "$FAT" 2>/dev/null | tr 'A-Z' 'a-z' | sed 's/ppc_/ppc/g')  # ppc_750->ppc750, keep x86_64
fi
for a in ppc750 ppc7400 i386 x86_64; do
  case " $ARCHS " in
    *"$a"*) ;;
    *) echo "[make-dmg] $FAT is missing the $a slice (got: ${ARCHS:-none}), run scripts/build-fat.sh" >&2; exit 1;;
  esac
done
# arm64 is REPORTED, not asserted. It cannot be cross-built on a mini, so
# requiring it would make a release impossible from the normal build path; and
# its absence is a Rosetta 2 downgrade rather than a fault. Saying which of the
# two happened is the point: a release must never be silently short a slice.
case " $ARCHS " in
  *arm64*)
    echo "[make-dmg] arm64 slice present: native on Apple Silicon"
    ARM64_LINE="  • Apple Silicon (arm64)  - macOS 11 Big Sur or later" ;;
  *)
    echo "[make-dmg] NO arm64 slice: Apple Silicon will use Rosetta 2"
    ARM64_LINE="  (no Apple Silicon slice in this build: it runs under Rosetta 2)" ;;
esac

# ---- assemble the .app (make-app.sh) + stage the disk-image contents -----
# Pass the release label down so the bundle inside the image self-identifies as
# this exact build. Otherwise the DMG filename says v0.5.0 and the .app on the
# machine says something else, and a smoke test proves nothing.
echo "[make-dmg] assemble ioquake3.app (version $VERSION)"
Q3_PORT_VERSION="$VERSION" scripts/make-app.sh >/dev/null
APP_SRC="$REPO_ROOT/build/ioquake3.app"
test -d "$APP_SRC" || { echo "[make-dmg] make-app.sh did not produce $APP_SRC" >&2; exit 1; }

STAMPED=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_SRC/Contents/Info.plist" 2>/dev/null || echo '')
[ "$STAMPED" = "$VERSION" ] || {
  echo "[make-dmg] .app CFBundleVersion is '$STAMPED', expected '$VERSION'" >&2; exit 1; }
echo "[make-dmg] bundle version verified: $STAMPED"

STAGE=$(mktemp -d -t ioq3-dmg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
IMG="$STAGE/img"                       # becomes the .dmg root
mkdir -p "$IMG"
cp -a "$APP_SRC" "$IMG/ioquake3.app"

# One-click quarantine/App-Translocation fix (issue: imac-2019 DMG launch,
# 2026-09-02). Fixes ioquake3.app IN PLACE wherever the user has dragged it
# -- does not copy or install anything itself (reworked 2026-09-02 to match
# quakespasm/alephone's convention, per the user's own direction: "the
# command should come in the dmg to be run in same folder as the fat binary
# etc."). fix-support/ ships VISIBLE (no leading dot) so a plain "drag
# everything out of this window" gesture carries it along with the app and
# the command file -- a hidden dir would silently get left behind on the
# image by that gesture and break the fix on next run.
mkdir -p "$IMG/fix-support"
cp "$REPO_ROOT/scripts/clear-launch-quarantine.sh" "$IMG/fix-support/clear-launch-quarantine.sh"
cp "$REPO_ROOT/scripts/bundle/set-bundle-bit"       "$IMG/fix-support/set-bundle-bit"
cp "$REPO_ROOT/scripts/bundle/Fix Launch Problems.command" "$IMG/Fix Launch Problems.command"
chmod +x "$IMG/fix-support/clear-launch-quarantine.sh" "$IMG/fix-support/set-bundle-bit" "$IMG/Fix Launch Problems.command"

cat > "$IMG/README.txt" <<EOF
ioquake3 - OldMac fat build ($VERSION)
======================================

A single universal build of ioquake3 (SDL 1.2 baseline) for vintage Macs:
  • PowerPC G3  (ppc750)   - Mac OS X 10.3.9 Panther or later
  • PowerPC G4  (ppc7400)  - Mac OS X 10.3.9 Panther or later
  • PowerPC G5  (ppc7400)  - Mac OS X 10.3.9 Panther or later (shares the G4 slice)
  • Intel 32    (i386)     - Mac OS X 10.4 Tiger through 10.6.8 Snow Leopard
  • Intel 64    (x86_64)   - Mac OS X 10.6 Snow Leopard or later
$ARM64_LINE
dyld picks the slice by CPU alone - the OS plays no part, and there is no
fallback - so every slice is built against the oldest OS its CPU can run.
The i386 slice exists for the 2006 Core Solo / Core Duo machines, the only
Intel Macs with no 64-bit mode; without it they are handed nothing at all.
Tested here on 10.3.9 (G3), 10.4.11 (G4), 10.5.8 (G5), 10.7.5 and 15.7 (Intel)
and on Apple Silicon; older combinations should work but have not been run on
hardware. The i386 slice has NOT been run on hardware: no 32-bit-only Intel Mac
exists in this fleet.
The game modules
(cgame/qagame/ui) ship as native dylibs inside the app too, loaded in place of
the bytecode for a small speed-up (falls back to the bytecode automatically).

INSTALL (recommended, works on every Mac in this image)
---------------------------------------------------------
1. Drag everything out of this window - ioquake3.app, "Fix Launch
   Problems.command", and the fix-support folder - to wherever you want the
   game to live (an empty folder is easiest, e.g. ~/Applications/quake3).
2. Right-click "Fix Launch Problems.command" there and choose Open (a plain
   double-click is blocked the first time on modern macOS - it is not
   Developer ID signed. Click Open again if macOS asks to confirm).

   On OS X 10.5-10.7 (Leopard, Snow Leopard, Lion) you do NOT need to run
   this at all - Gatekeeper isn't on by default there yet (that starts in
   OS X 10.8 Mountain Lion). The script checks your OS version itself and
   just tells you so if you run it anyway; either way, skip straight to
   step 4 there and just double-click ioquake3.app once you've dragged it
   out.
3. It clears the quarantine flag that otherwise breaks the first launch on
   modern macOS, right where you put it - it does not move or copy anything
   for you. (On Panther/Tiger it still sets the Finder bundle icon, a
   separate old-Finder fix, unrelated to quarantine.) A Terminal window
   shows what it did, then waits for Return.
4. Add your Quake III game data - your own pak0.pk3 … pak8.pk3 (this image
   ships NO game data) - into the baseq3/ folder next to ioquake3.app.
5. From then on, double-click ioquake3.app in that folder like any other app.

Re-running "Fix Launch Problems.command" after a future update is safe: it
never touches an existing baseq3/ folder, so your game data stays put.

MANUAL INSTALL (if you'd rather not run a script)
--------------------------------------------------
1. Drag ioquake3.app OUT of this window, to a folder that already contains
   your Quake III "baseq3" directory.
   e.g.  ~/Applications/quake3/ioquake3.app   alongside   ~/Applications/quake3/baseq3/
2. Double-click ioquake3.app from THAT folder - not from this disk image.
On Panther/Tiger/Leopard/Lion this just works. On modern macOS, right-click
ioquake3.app and choose Open the first time instead of double-clicking, or
use the installer above.

The app finds baseq3 in the folder that CONTAINS the .app (it strips its own
bundle path), so keep the .app next to baseq3/.

PER-MACHINE AUTO-TUNING
-----------------------
On launch the app reads the Mac's model (hw.model) and applies a tuned config
for that machine automatically - resolution, texture/effect detail and vsync are
picked to look their best while staying playable on that GPU. Measured on the
bench fleet at each machine's native resolution:
  • G3 449 MHz / Rage 128    800x600    ~22 fps  (lightmaps + shaders + effects)
  • G4 733 MHz / Radeon 9000  1680x1050 ~42 fps  (16x aniso + trilinear)
  • Core 2 Duo / GMA 950      1920x1080 ~57 fps  (vsync on - no tearing)
  • G5 2.0 GHz / Radeon 9600  1440x900  ~60 fps  (maxed: aniso 8x, trilinear)
To override, edit baseq3/autoexec.cfg; to disable auto-tuning, launch with
+set com_archAutoexec 0.

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
#
# DERIVED from what is actually staged, not hardcoded. Several of these are
# optional (the arm64 engine slice brings libSDL2 and three arm64 modules with
# it, and none of them can be built on a mini), and a hardcoded list would
# either fail on a four-slice build or silently skip the arm64 files on a
# five-slice one. Deriving it also removes the second copy of the list that
# used to live in the remote heredoc below, which was a standing drift hazard.
# ---- ad-hoc code-sign the staged bundle ----------------------------------
# macOS on arm64 refuses to map a page whose code signature does not validate
# and kills the process with CODESIGNING / Invalid Page. Signing also gives the
# bundle a stable identity, so macOS stops re-asking for Desktop/Documents
# access on every launch, which it does for an app it cannot identify.
#
# Order is not optional: codesign validates a bundle's nested code when it signs
# the bundle, so anything inside must already be signed. Plain dylibs first,
# then each framework as a DIRECTORY (never by its inner binary path), then the
# .app last. Signed here rather than on DMG_HOST, which is a Tiger G4 with no
# codesign, and before the checksums so the byte verification hashes what ships.
if command -v codesign >/dev/null 2>&1; then
	echo "[make-dmg] ad-hoc code-signing the staged bundle"
	SAPP="$IMG/ioquake3.app"
	find "$SAPP" -type f \( -name '*.dylib' -o -name '*.so' \) -not -path '*.framework/*' -print0 2>/dev/null \
	  | while IFS= read -r -d '' f; do codesign --force --sign - "$f" >/dev/null 2>&1 || true; done
	for fw in "$SAPP"/Contents/MacOS/*.framework "$SAPP"/Contents/Frameworks/*.framework; do
		[ -d "$fw" ] || continue
		for stray in "$fw"/*; do
			[ -L "$stray" ] && continue
			[ "$(basename "$stray")" = "Versions" ] && continue
			mkdir -p "$fw/Versions/A/Resources"
			mv "$stray" "$fw/Versions/A/Resources/" 2>/dev/null || true
		done
		codesign --force --sign - "$fw" >/dev/null 2>&1 || true
	done
	codesign --force --sign - "$SAPP" >/dev/null 2>&1 || true
	codesign -v "$SAPP" >/dev/null 2>&1 || {
		echo "[make-dmg] FATAL: the .app bundle signature does not validate" >&2; exit 1; }
	echo "[make-dmg] signatures verified on the bundle"
else
	echo "[make-dmg] WARN: no codesign here; the bundle will NOT run on Apple Silicon" >&2
fi

VERIFY_FILES=$( cd "$IMG" && find ioquake3.app/Contents/MacOS \
                  -type f \( -name 'ioquake3' -o -name '*.dylib' \) | LC_ALL=C sort )
SRC_SUMS=$(cd "$IMG" && printf '%s\n' "$VERIFY_FILES" | while read -r f; do \
             [ -n "$f" ] || continue; \
             printf '%s  %s\n' "$(md5sum "$f" | cut -d' ' -f1)" "$f"; done)
echo "[make-dmg] end-to-end md5 verify covers $(printf '%s\n' "$VERIFY_FILES" | grep -c .) binaries"
# Colon-separated so the whole list crosses ssh as ONE token with no whitespace
# and no newlines in it. Passing it as a plain multi-path argument does not
# work: ssh joins its arguments into a single remote command string, so the
# spaces word-split and only the first path survives, and embedded newlines
# would be read as command separators. NOT base64: the DMG host is a Tiger G4
# and 10.4 ships no base64(1) at all (verified: "no base64 in /usr/bin /bin
# /usr/sbin /sbin"). Bundle paths never contain a colon.
VERIFY_LIST=$(printf '%s\n' "$VERIFY_FILES" | grep . | tr '\n' ':')

mkdir -p "$REPO_ROOT/dist"

attempt=0; verified=no
while [ "$attempt" -lt 3 ]; do
  attempt=$((attempt + 1))
  echo "[make-dmg] attempt $attempt/3: ship staged image to $DMG_HOST and run hdiutil"
  ssh "$DMG_HOST" "rm -rf '$REMOTE' && mkdir -p '$REMOTE'"
  rsync -a $RSYNC_EXTRA -e 'ssh -o ServerAliveInterval=15' "$IMG/" "$DMG_HOST:$REMOTE/img/"

  # Set the Finder bundle-bit HERE, on $DMG_HOST, AFTER the rsync above, not
  # locally before it. VERIFIED on real hardware 2026-09-03 that hdiutil
  # create -srcfolder preserves HFS+ Finder-info metadata end to end, but
  # measured the same day that plain `rsync -a` (this line, no -E/xattr
  # support) does NOT -- setting the bit locally and rsyncing it over lost
  # it before hdiutil ever saw it (confirmed: the shipped DMG's app came out
  # with the bit unset despite the local build log saying "kHasBundle SET").
  # Same root cause as why deploy-dmg.sh/deploy.sh already need their own
  # post-transfer set-bundle-bit call. Running it here, remotely, right
  # before hdiutil packages $REMOTE/img, is what actually survives into the
  # shipped image -- uses the fix-support/set-bundle-bit copy that rsync
  # just carried over as part of img/, no separate transfer needed. Not
  # fatal: Fix Launch Problems.command's own runtime step is still the
  # fallback if this ever silently does nothing.
  ssh "$DMG_HOST" "'$REMOTE/img/fix-support/set-bundle-bit' '$REMOTE/img/ioquake3.app'" || true

  # UDZO = zlib-compressed read-only image; widest compatibility incl. Panther.
  ssh "$DMG_HOST" "rm -f '$REMOTE/out.dmg' && \
    hdiutil create -volname '$VOLNAME' -srcfolder '$REMOTE/img' \
      -ov -format UDZO '$REMOTE/out.dmg' && \
    hdiutil verify '$REMOTE/out.dmg' >/dev/null"

  # md5 the binaries INSIDE the finished image (mount -> hash -> detach). Mount
  # at a private mountpoint (not /Volumes) to dodge a stale same-name mount.
  # The file list arrives colon-separated as $2, so there is exactly ONE copy of
  # it (built above from what was actually staged) rather than a second
  # hardcoded copy here to drift out of sync.
  DMG_SUMS=$(ssh "$DMG_HOST" bash -s "$REMOTE" "$VERIFY_LIST" <<'REMOTE_EOF' || true
REM="$1"; LIST="$2"; MP="$REM/mnt"
mkdir -p "$MP"
hdiutil detach "$MP" >/dev/null 2>&1 || true
hdiutil attach -nobrowse -readonly -mountpoint "$MP" "$REM/out.dmg" >/dev/null 2>&1 || exit 7
OIFS=$IFS; IFS=:
for f in $LIST; do
  IFS=$OIFS
  [ -n "$f" ] || continue
  printf '%s  %s\n' "$(md5 "$MP/$f" 2>/dev/null | awk '{print $NF}')" "$f"
  IFS=:
done
IFS=$OIFS
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
