#!/usr/bin/env bash
# Install the release DMG onto a target Mac, exercising the same artifact and
# the same install steps a human performs (where the Q2 port's corrupt-DMG bug
# hid): stage the .dmg, mount it, copy ioquake3.app into /Applications/Quake3/,
# then unmount. This is deliberately the DMG path, not deploy.sh's direct
# rsync.
#
# INSTALL DIR IS NOT ~/Desktop/quake3 (old-mac-quake3#49, measured 2026-09-04):
# ~/Desktop is one of macOS's TCC-protected special folders (Desktop/Documents/
# Downloads, since Mojave). A headless/ssh-driven launch has nobody to answer
# the one-time consent dialog, so TCC silently denies the ad-hoc-signed engine
# read access to its own baseq3/ with NOTHING written to qconsole.log — this
# bit imac-2019 outright. /Applications/Quake3 is the canonical install, so this is a
# real fix, not a workaround: it removes the wall entirely rather than routing
# around a permission that would still trip up an unattended real install.
# NOT plain ~/quake3 — that name is already reserved on the two Lion build
# hosts (mini-intel/mini-intel2) as the build-tree rsync target (build-system.md's
# "rsync target is always <host>:quake3/" hard rule); colliding the deployed
# game with the source checkout on those same "build, bench, data source"
# machines would be worse than the bug this fixes. Caught 2026-09-04 by
# checking mini-intel's actual filesystem before assuming, not by inspection.
#
# The .dmg file itself stages under ~/oldmac/quake3/, NOT ~/Desktop (user rule,
# retro-agents 5cbbb3d, 2026-09-13): nothing this tooling deploys is left on
# any Mac's Desktop, fleet-wide. Earlier revisions staged it on Desktop to
# approximate a real user's download location; that is superseded.
#
# usage: scripts/deploy-dmg.sh <machine> [version]
#   machine: any bench-box ssh alias: yosemite[-tiger] | sawtooth | quicksilver | mini-g4 |
#            imac-g5 | g5-{panther,tiger,desktop} | quad-{tiger,leopard} | mini-intel[2] | imac-2019
#   version: e.g. v0.1.0  (default: newest dist/ioquake3-OldMac-*.dmg)
#
# Preserves the user's game data: baseq3/*.pk3 and any q3config.cfg/autoexec.cfg
# are left untouched; only ioquake3.app is (re)installed.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HOST="${1:?usage: $0 <machine> [version]}"

# Claim this machine for the whole run. See scripts/pick-bench-host.sh.
#
# Re-exec under the picker rather than acquire-here-and-trap: bash traps REPLACE
# rather than compose, so a release trap installed at the top of a script that
# later sets its own trap is silently discarded, and the machine stays claimed
# until the stale reclaim. `--run` makes the lock a property of the INVOCATION,
# so it is released however this exits, and no caller has to remember to do it.
#
# The lock lives on the target, so it serialises across repos, agents and
# workstations, not just this checkout. It also refuses a host booted into an OS
# its alias does not name, which the multi-boot machines otherwise allow.
#
# RETRO_BENCH_LOCK guards against the re-exec recursing.
# BENCH_NO_LOCK=1 skips the lock, for when the picker itself is what you are
# debugging. It is not a way to get past a machine someone else is using.
_PICK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pick-bench-host.sh"
# Compare RETRO_BENCH_LOCK to THIS script's target rather than merely testing
# that it is set. pick-bench-host.sh --run now exports it naming the claimed
# host, so a bare -z test would make this script skip its own claim whenever it
# runs inside any other claim, including one on a DIFFERENT machine. Same-host
# still skips, which is the reentrancy this guard is for.
if [ "${RETRO_BENCH_LOCK:-}" != "$HOST" ] && [ "${BENCH_NO_LOCK:-0}" != 1 ] && [ -x "$_PICK" ]; then
	export RETRO_BENCH_LOCK="$HOST"
	exec "$_PICK" --run "$HOST" "deploy-dmg" -- "$0" "$@"
fi
VERSION="${2:-}"
case "$HOST" in
  yosemite|yosemite-tiger|sawtooth|quicksilver|mini-g4|imac-g5|mini-intel|mini-intel2|mini-sl|g5-panther|g5-tiger|g5-desktop|quad-tiger|quad-leopard|imac-2019) ;;
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

echo "[deploy-dmg $HOST] copy $DMG_BASE to ~/oldmac/quake3/"
ssh "$HOST" 'mkdir -p ~/oldmac/quake3'
scp -q "$DMG" "$HOST:oldmac/quake3/$DMG_BASE"

# Verify the .dmg arrived intact (md5 local vs remote) — defence in depth on top
# of make-dmg.sh's own end-to-end content check.
LCL_MD5=$(md5sum "$DMG" | cut -d' ' -f1)
RMT_MD5=$(ssh "$HOST" "md5 'oldmac/quake3/$DMG_BASE' | awk '{print \$NF}'")
[ "$LCL_MD5" = "$RMT_MD5" ] || { echo "[deploy-dmg $HOST] FATAL: scp corrupted the DMG ($LCL_MD5 != $RMT_MD5)" >&2; exit 1; }
echo "[deploy-dmg $HOST] DMG verified intact ($RMT_MD5)"
scp -q "$REPO_ROOT/scripts/deploy-promotion.sh" "$HOST:oldmac/quake3/deploy-promotion.sh"

echo "[deploy-dmg $HOST] mount + install ioquake3.app into /Applications/Quake3 (preserving game data)"
ssh "$HOST" bash -s "$DMG_BASE" <<'REMOTE_EOF'
set -e
DMG_BASE="$1"
source "$HOME/oldmac/quake3/deploy-promotion.sh"
ROOT="$HOME/oldmac/quake3"
MNT="$ROOT/mount.$$"
DEST="/Applications/Quake3"
STAGE="$ROOT/install.stage.$$"
ROLLBACK="$ROOT/rollback-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$ROOT"

# fresh mountpoint — detach any stale attach, then rmdir (NEVER rm -rf a path
# that might still be a mounted read-only volume).
hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach -force "$MNT" >/dev/null 2>&1 || true
rmdir "$MNT" 2>/dev/null || true
mkdir -p "$MNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$ROOT/$DMG_BASE" >/dev/null

rm -rf "$STAGE"
mkdir -p "$STAGE/baseq3"
if [ -d "$DEST/baseq3" ]; then ditto "$DEST/baseq3" "$STAGE/baseq3"; fi

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
  rm -rf "$STAGE/ioquake3.app"; ditto "$MNT/ioquake3.app" "$STAGE/ioquake3.app"; sync
  if [ "$(_md5 "$STAGE/$APP_BIN")" = "$(_md5 "$MNT/$APP_BIN")" ]; then appok=yes; break; fi
  echo "  [verify] app binary mismatch (try $k) — re-dittoing" >&2; sleep 1
done
[ "$appok" = yes ] || { echo "  FATAL: app binary still corrupt after retries" >&2; exit 7; }
echo "  [verify] installed ioquake3 binary matches the image byte-for-byte"

# Also keep the loose bench binary + libSDL that deploy.sh ships in sync, so
# bench.sh and the DMG path agree. Pull both out of the bundle we just verified.
#
# ioquake3-bench, NOT ioquake3. Finder hides the .app extension, so a loose
# Mach-O called ioquake3 appears in the install dir as a SECOND "ioquake3" with
# a generic executable icon, and double-clicking it cannot work because it is
# not a bundle. This line was the source of that duplicate: it recreated the
# file on every DMG install, so renaming it in deploy.sh alone did not remove
# it. Issue #10.
cp -p "$STAGE/ioquake3.app/Contents/MacOS/ioquake3"            "$STAGE/ioquake3-bench"      && chmod +x "$STAGE/ioquake3-bench" || true
rm -f "$STAGE/ioquake3"
cp -p "$STAGE/ioquake3.app/Contents/MacOS/libSDL-1.2.0.dylib"  "$STAGE/libSDL-1.2.0.dylib"  || true

# Set the Finder bundle bit so Panther/Tiger show the app icon, not a folder.
if [ -x "$STAGE/.set-bundle-bit" ]; then
  "$STAGE/.set-bundle-bit" "$STAGE/ioquake3.app" >/dev/null 2>&1 || true
fi

# Re-register with LaunchServices. The rm -rf + ditto above gives the bundle new
# inodes, and LS can be left holding the old ones (or, on Lion, a record with a
# blank `executable:` path) — Finder then says "damaged or incomplete" for a
# perfectly good app. Every script here execs the binary directly and so never
# exercises this path. See MISTAKES.md 2026-07-26. Non-fatal.
#
# NOTE the `if` rather than `[ -x ... ] && { ...; }`: this block runs under
# `set -e`, and the && form returns non-zero on the Macs where the first path is
# absent (it moved to CoreServices at 10.5; Panther/Tiger keep it under
# ApplicationServices). That would abort the remote script here — BEFORE the
# hdiutil detach below — and leave the DMG mounted on the target.
for lsr in \
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  /System/Library/Frameworks/ApplicationServices.framework/Frameworks/LaunchServices.framework/Support/lsregister; do
  if [ -x "$lsr" ]; then
    "$lsr" -f "$STAGE/ioquake3.app" >/dev/null 2>&1 || true
    break
  fi
done

# detach — retry until the slow-disk flush completes; only THEN rmdir the now-
# empty mountpoint.
detached=no
for k in 1 2 3 4 5; do
  if hdiutil detach "$MNT" >/dev/null 2>&1; then detached=yes; break; fi
  sleep 2
done
[ "$detached" = yes ] || hdiutil detach -force "$MNT" >/dev/null 2>&1 || true
rmdir "$MNT" 2>/dev/null || true

if ! promote_staged_install "$ROOT" "$DEST" "$STAGE" "$ROLLBACK"; then
  echo "FATAL: promotion failed; restored rollback" >&2
  exit 8
fi

# Tidy ~/oldmac/quake3 once the new install is in place (#50, user rule via
# old-mac-build-host#73): no rollback copies or staged DMGs left behind. A
# rollback is removed only when every file in its baseq3 is also in the new
# install, so the player's data is never the copy that goes. Older rollbacks
# from before this rule are held to the same test.
for rb in "$ROOT"/rollback-*; do
  [ -d "$rb" ] || continue
  kept=no
  for f in "$rb"/baseq3/*; do
    [ -e "$f" ] || continue
    [ -e "$DEST/baseq3/${f##*/}" ] || { kept=yes; break; }
  done
  if [ "$kept" = yes ]; then
    echo "  [tidy] keeping ${rb##*/}: its baseq3 has files the new install lacks" >&2
  else
    rm -rf "$rb" && echo "  [tidy] removed ${rb##*/}"
  fi
done
rm -f "$ROOT"/ioquake3-OldMac-*.dmg && echo "  [tidy] removed staged DMG(s)"

# Clear stale ioquake3-OldMac-*.dmg files this same tooling left on ~/Desktop
# in earlier revisions (user rule, retro-agents 5cbbb3d): safe on every host in
# this script's own machine list above, none of which is the user's workstation
# (deploy-dmg.sh never targets it), so no genuinely user-placed file can match
# this exact name pattern here. Report what, if anything, gets removed.
shopt -s nullglob 2>/dev/null || true
old_desktop_dmgs=("$HOME"/Desktop/ioquake3-OldMac-*.dmg)
if [ "${#old_desktop_dmgs[@]}" -gt 0 ]; then
  echo "removing stale Desktop DMG(s): ${old_desktop_dmgs[*]##*/}"
  rm -f "${old_desktop_dmgs[@]}"
fi

echo "app binary archs:"
file "$DEST/ioquake3.app/Contents/MacOS/ioquake3" 2>/dev/null | sed 's/^/  /' || true
REMOTE_EOF

echo "[deploy-dmg $HOST] done — installed from $DMG_BASE"
