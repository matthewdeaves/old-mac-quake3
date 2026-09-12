#!/usr/bin/env bash
# Shared verified staged-install promotion used by deploy-dmg.sh and tests.
promote_staged_install() {
  local root="$1" dest="$2" stage="$3" rollback="$4"
  local promote="$root/promote.$$" rollback_ready=no rollback_moved=no
  mkdir -p "$(dirname "$dest")"
  if [ -d "$dest" ]; then
    if mv "$dest" "$rollback" 2>/dev/null; then rollback_ready=yes; rollback_moved=yes
    else
      rm -rf "$rollback"
      if ditto "$dest" "$rollback" && [ -f "$rollback/ioquake3.app/Contents/MacOS/ioquake3" ]; then rollback_ready=yes; fi
    fi
  fi
  if [ -d "$dest" ] && [ "$rollback_ready" != yes ]; then return 8; fi
  if ! mv "$stage" "$promote"; then
    [ "$rollback_moved" = yes ] && mv "$rollback" "$dest" || true
    return 8
  fi
  if [ -d "$dest" ] && ! rm -rf "$dest"; then
    rm -rf "$promote"; [ "$rollback_moved" = yes ] && mv "$rollback" "$dest" || ditto "$rollback" "$dest" || true
    return 8
  fi
  if [ "${FORCE_PROMOTION_FAIL:-0}" = 1 ]; then
    rm -rf "$promote"
    if [ "$rollback_moved" = yes ]; then mv "$rollback" "$dest" || true
    elif [ "$rollback_ready" = yes ]; then ditto "$rollback" "$dest" || true
    fi
    return 8
  fi
  if ! mv "$promote" "$dest"; then
    rm -rf "$promote" "$dest"
    if [ "$rollback_moved" = yes ]; then mv "$rollback" "$dest" || true
    elif [ "$rollback_ready" = yes ]; then ditto "$rollback" "$dest" || true
    fi
    return 8
  fi
}
