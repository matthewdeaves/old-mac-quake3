#!/usr/bin/env bash
#
# lsregister-app.sh — repair the target's LaunchServices record for
# ~/Desktop/quake3/ioquake3.app, so the app can still be opened by DOUBLE-CLICK.
#
# usage: scripts/lsregister-app.sh <machine> [--quiet]
#
# WHY THIS EXISTS
#
# bench.sh, safebench.sh, screenshot.sh and smoke-dmg.sh all launch the engine by
# exec'ing the Mach-O directly over ssh — they never go through LaunchServices,
# because they need one ssh session that outlives the app (see scripts/CLAUDE.md).
#
# The precise trigger (measured 2026-07-27, narrower than "direct exec"): the
# engine `dlopen`s a game module from INSIDE the bundle —
# Contents/MacOS/baseq3/{cgame,qagame,ui}*.dylib, when the arch cfg sets vm_* 0.
# A dlopen inside an .app from a process LS did not launch makes LS register the
# bundle off the live process, and it writes the record with an EMPTY
# `executable:` path — the inode is stored, the name is lost. Finder and the Dock
# then refuse to open a perfectly good app with "damaged or incomplete".
# Load-time linkage is fine: libSDL-1.2.0.dylib sits in the same bundle and is
# resolved by dyld via @executable_path without provoking any of this.
# Measured on mini-intel 2026-07-26:
#
#     after deploy.sh          executable: Contents/MacOS/ioquake3
#     after ONE smoke-dmg run  executable:            <- blank
#
# So this is NOT a deploy-time problem, and re-registering only in deploy.sh is
# useless: deploy -> bench is the normal order, and the bench re-breaks it. Every
# script that direct-execs the engine has to repair the record on its way out.
#
# Panther and Tiger have not been observed doing this, but the call is harmless
# there and the fleet is easier to reason about if every target gets the same
# treatment.
#
# Non-fatal by contract: this is launch polish, never a reason to fail a bench or
# a deploy. It prints a warning and returns 0 even when it cannot fix anything.
#
set -uo pipefail

MACHINE="${1:?usage: $0 <machine> [--quiet]}"

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
if [ -z "${RETRO_BENCH_LOCK:-}" ] && [ "${BENCH_NO_LOCK:-0}" != 1 ] && [ -x "$_PICK" ]; then
	export RETRO_BENCH_LOCK="$MACHINE"
	exec "$_PICK" --run "$MACHINE" "lsregister-app" -- "$0" "$@"
fi
QUIET="${2:-}"
REMOTE_DIR="~/Desktop/quake3"

say() { [ "$QUIET" = "--quiet" ] || echo "$@"; }

# lsregister moved into CoreServices.framework at 10.5; Panther and Tiger keep it
# under ApplicationServices. Both paths are tried — confirmed present on yosemite
# (10.3.9) and quicksilver (10.4.11).
OUT="$(ssh -o ConnectTimeout=15 "$MACHINE" "
  for lsr in \
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    /System/Library/Frameworks/ApplicationServices.framework/Frameworks/LaunchServices.framework/Support/lsregister; do
    if [ -x \"\$lsr\" ]; then
      app=\$(cd $REMOTE_DIR 2>/dev/null && pwd)/ioquake3.app
      [ -d \"\$app\" ] || { echo 'NOAPP'; exit 0; }
      \"\$lsr\" -f \"\$app\" >/dev/null 2>&1
      # Assert the repair took. A blank \`executable:\` is precisely the broken
      # state this script exists to clear, so an unchecked -f proves nothing.
      #
      # TWO dump formats, and only one of them has labels. 10.4 and later print
      # key-value lines, \`path: ...\` and \`executable: ...\`. PANTHER prints a
      # compact columnar block with no field names at all:
      #
      #   B00002352  APPL/....  Fri Aug 21 18:51:00 2026  ioquake3.app
      #              -pad----hn----------!            v0  ioquake3
      #              Contents/Resources/ioquake3.icns     org.ioquake...
      #              Contents/MacOS/ioquake3              106610, 106626, Mach-O
      #              V00000008 /Users/mini/Desktop/quake3/ioquake3.app
      #
      # So the labelled parse finds nothing on 10.3 no matter how healthy the
      # record is, and this script called every Panther box BLANK. That is not
      # a cosmetic false alarm: release-check.sh matches on the warning text, so
      # a G3 in the machine list failed a release for a record that was fine.
      # Measured on yosemite 2026-08-21: labelled parse empty, block parse
      # returns Contents/MacOS/ioquake3.
      #
      # Try the labelled form, fall back to the block form. Paragraph mode finds
      # the block whose text contains the app path, then takes the first
      # Contents/MacOS/ field in it.
      exe=\$(\"\$lsr\" -dump 2>/dev/null \
              | grep -A20 \"path: *\$app\\\$\" \
              | sed -n 's/^[[:space:]]*executable:[[:space:]]*//p' | head -1)
      [ -n \"\$exe\" ] || exe=\$(\"\$lsr\" -dump 2>/dev/null \
              | awk -v app=\"\$app\" 'BEGIN{RS=\"\"} index(\$0, app){ for(i=1;i<=NF;i++) if(\$i ~ /^Contents\\/MacOS\\//){ print \$i; exit } }' \
              | head -1)
      [ -n \"\$exe\" ] && echo \"OK \$exe\" || echo 'BLANK'
      exit 0
    fi
  done
  echo 'NOTOOL'
" 2>/dev/null)"

case "$OUT" in
  OK\ *)  say "    [lsregister $MACHINE] OK — ${OUT#OK }" ;;
  BLANK)  echo "    [lsregister $MACHINE] WARNING — record still has no executable;" >&2
          echo "        double-clicking the app will say \"damaged\". Launch it once from Finder." >&2 ;;
  NOAPP)  say "    [lsregister $MACHINE] no ioquake3.app deployed — skipped" ;;
  NOTOOL) say "    [lsregister $MACHINE] lsregister not found — skipped" ;;
  *)      say "    [lsregister $MACHINE] unreachable or failed — skipped (non-fatal)" ;;
esac

exit 0
