#!/usr/bin/env bash
# Isolated regression tests for deploy-dmg.sh's staged promotion contract.
set -euo pipefail

promote() {
  local root="$1" dest="$2" stage="$3" rollback="$1/rollback"
  local promote="$root/promote" rollback_ready=no rollback_moved=no
  mkdir -p "$root"
  mkdir -p "$(dirname "$dest")"
  if [ -d "$dest" ]; then
    if mv "$dest" "$rollback" 2>/dev/null; then rollback_ready=yes; rollback_moved=yes
    else
      rm -rf "$rollback"
      if ditto "$dest" "$rollback" && [ -f "$rollback/ioquake3.app/Contents/MacOS/ioquake3" ]; then rollback_ready=yes; fi
    fi
  fi
  [ ! -d "$dest" ] || [ "$rollback_ready" = yes ]
  mv "$stage" "$promote"
  if [ "${FORCE_PROMOTION_FAIL:-0}" = 1 ]; then
    rm -rf "$promote"
    if [ "$rollback_moved" = yes ]; then mv "$rollback" "$dest"; else ditto "$rollback" "$dest"; fi
    return 8
  fi
  if [ -d "$dest" ]; then rm -rf "$dest"; fi
  mv "$promote" "$dest"
}

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
promote "$tmp/existing-run" "$old" "$tmp/new"; grep -qx new "$old/ioquake3.app/Contents/MacOS/ioquake3"
grep -qx user "$tmp/existing-run/rollback/baseq3/q3config.cfg"; grep -qx sentinel "$tmp/existing-run/rollback/ioquake3.app/Contents/MacOS/ioquake3"

# First install.
mkdir -p "$tmp/first/new/ioquake3.app/Contents/MacOS"; printf first > "$tmp/first/new/ioquake3.app/Contents/MacOS/ioquake3"
promote "$tmp/first" "$tmp/first/Applications/Quake3" "$tmp/first/new"; grep -qx first "$tmp/first/Applications/Quake3/ioquake3.app/Contents/MacOS/ioquake3"

# Forced promotion failure restores the exact prior install.
mkdir -p "$tmp/fail/new/ioquake3.app/Contents/MacOS" "$tmp/fail/Applications/Quake3/ioquake3.app/Contents/MacOS"
printf replacement > "$tmp/fail/new/ioquake3.app/Contents/MacOS/ioquake3"; printf sentinel > "$tmp/fail/Applications/Quake3/ioquake3.app/Contents/MacOS/ioquake3"
if FORCE_PROMOTION_FAIL=1 promote "$tmp/fail" "$tmp/fail/Applications/Quake3" "$tmp/fail/new"; then exit 1; fi
grep -qx sentinel "$tmp/fail/Applications/Quake3/ioquake3.app/Contents/MacOS/ioquake3"
echo 'test-deploy-promotion: all cases pass'
