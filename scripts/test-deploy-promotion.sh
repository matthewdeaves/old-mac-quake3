#!/usr/bin/env bash
# Isolated regression tests for deploy-dmg.sh's staged promotion contract.
set -euo pipefail

source "$(dirname "$0")/deploy-promotion.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Desktop"; printf keep > "$tmp/Desktop/ioquake3-OldMac-prior.dmg"
! grep -q 'rm -f "\$HOME"/Desktop/ioquake3-OldMac' scripts/deploy-dmg.sh
grep -qx keep "$tmp/Desktop/ioquake3-OldMac-prior.dmg"
new_app="$tmp/new/ioquake3.app/Contents/MacOS"
mkdir -p "$new_app"; printf new > "$new_app/ioquake3"

# Existing install: new app promoted, sentinel and user data retained in rollback.
old="$tmp/existing"; mkdir -p "$old/ioquake3.app/Contents/MacOS" "$old/baseq3"
printf sentinel > "$old/ioquake3.app/Contents/MacOS/ioquake3"; printf user > "$old/baseq3/q3config.cfg"
promote_staged_install "$tmp/existing-run" "$old" "$tmp/new" "$tmp/existing-run/rollback"; grep -qx new "$old/ioquake3.app/Contents/MacOS/ioquake3"
grep -qx user "$tmp/existing-run/rollback/baseq3/q3config.cfg"; grep -qx sentinel "$tmp/existing-run/rollback/ioquake3.app/Contents/MacOS/ioquake3"

# First install.
mkdir -p "$tmp/first/new/ioquake3.app/Contents/MacOS"; printf first > "$tmp/first/new/ioquake3.app/Contents/MacOS/ioquake3"
promote_staged_install "$tmp/first" "$tmp/first/Applications/Quake3" "$tmp/first/new" "$tmp/first/rollback"; grep -qx first "$tmp/first/Applications/Quake3/ioquake3.app/Contents/MacOS/ioquake3"

# Forced promotion failure restores the exact prior install.
mkdir -p "$tmp/fail/new/ioquake3.app/Contents/MacOS" "$tmp/fail/Applications/Quake3/ioquake3.app/Contents/MacOS"
printf replacement > "$tmp/fail/new/ioquake3.app/Contents/MacOS/ioquake3"; printf sentinel > "$tmp/fail/Applications/Quake3/ioquake3.app/Contents/MacOS/ioquake3"
mv "$tmp/fail/Applications/Quake3" "$tmp/fail-old"
if ! FORCE_PROMOTION_FAIL=1 promote_staged_install "$tmp/fail" "$tmp/fail-old" "$tmp/fail/new" "$tmp/fail/rollback"; then :; else exit 1; fi
grep -qx sentinel "$tmp/fail-old/ioquake3.app/Contents/MacOS/ioquake3"
echo 'test-deploy-promotion: all cases pass'
