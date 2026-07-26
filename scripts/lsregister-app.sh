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
# On Lion, running the bundle's executable that way makes LS re-register the
# bundle from the live process, and because the launch did not originate from LS
# it writes the record with an EMPTY `executable:` path — the inode is stored,
# the name is lost. Finder and the Dock then refuse to open a perfectly good app
# with "damaged or incomplete". Measured on mini-intel 2026-07-26:
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
      exe=\$(\"\$lsr\" -dump 2>/dev/null \
              | grep -A20 \"path: *\$app\\\$\" \
              | sed -n 's/^[[:space:]]*executable:[[:space:]]*//p' | head -1)
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
