#!/usr/bin/env bash
#
# release-check.sh <version> [machine ...] - the gate a release has to pass.
#
# Why this exists (issue #9). Nothing else in this repo opens the app the way a
# person does. bench.sh runs the loose Mach-O; safebench.sh, screenshot.sh and
# smoke-dmg.sh all exec ioquake3.app/Contents/MacOS/ioquake3 directly over ssh.
# All of them bypass LaunchServices, so the whole verification pipeline is
# structurally blind to "the app will not open". On 2026-07-26 it was worse than
# blind: smoke-dmg.sh reported PASS at 40.3 fps on a build that could not be
# double-clicked at all, because direct-exec benching is itself what corrupts the
# LaunchServices record.
#
# So this script does the part that CAN be automated, and then refuses to pass
# until a human has confirmed the part that cannot.
#
# usage:
#   scripts/release-check.sh v0.6.0 mini-g4 yosemite
#   RELEASE_CHECK_ASSUME_CLICKED=1 scripts/release-check.sh v0.6.0 mini-g4
#
# The env override exists for re-runs within one session after the click test
# has genuinely been done. It is deliberately ugly to type. Do not put it in a
# script: the entire point of the gate is that somebody looked.
#
set -uo pipefail

VERSION="${1:?usage: release-check.sh <version> [machine ...]}"
shift || true
MACHINES=("$@")
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
DMG="$REPO_ROOT/dist/ioquake3-OldMac-$VERSION.dmg"

FAILED=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAILED=1; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; }

echo "== release-check $VERSION =="

# ---- 1. the image exists and carries every slice --------------------------
if [ -f "$DMG" ]; then
  pass "disk image present: $(basename "$DMG") ($(du -h "$DMG" | cut -f1))"
else
  fail "no $DMG - run scripts/make-dmg.sh $VERSION on a Tiger G4"
fi

# ---- 2. slices ------------------------------------------------------------
FAT="$REPO_ROOT/build/ioquake3-fat"
if [ -f "$FAT" ]; then
  ARCHS=$(lipo -archs "$FAT" 2>/dev/null || echo)
  for a in ppc750 ppc7400 i386 x86_64; do
    case " $ARCHS " in *" $a "*) ;; *) fail "fat is missing the $a slice (got: $ARCHS)";; esac
  done
  case " $ARCHS " in
    *" arm64 "*) pass "slices: $ARCHS" ;;
    *) warn "no arm64 slice: Apple Silicon will run under Rosetta 2 ($ARCHS)" ;;
  esac
  case " $ARCHS " in
    *" ppc "*) fail "fat contains a GENERIC ppc member; it would be graded onto every PowerPC host" ;;
  esac
else
  fail "no build/ioquake3-fat"
fi

# ---- 3. no debug readouts left on in the shipped configs ------------------
# A release should not open with a frame counter in the corner. This is a
# grep rather than a runtime check because the configs ARE the shipped state.
DBG=$(grep -rlniE 'seta (cg_drawfps|r_speeds|com_speeds|r_showtris|developer) "[1-9]' \
        "$REPO_ROOT"/scripts/bundle/autoexec-*.cfg 2>/dev/null || true)
if [ -n "$DBG" ]; then
  fail "debug readouts enabled in: $(echo "$DBG" | xargs -n1 basename | tr '\n' ' ')"
else
  pass "no debug readouts enabled in any shipped config"
fi

# ---- 4. per-machine checks ------------------------------------------------
for m in "${MACHINES[@]}"; do
  echo "-- $m --"
  if ! ssh -n -o ConnectTimeout=8 "$m" true 2>/dev/null; then
    warn "$m unreachable - skipped"
    continue
  fi

  # 4a. the installed bundle is the version we think it is
  GOT=$(ssh -n -o ConnectTimeout=8 "$m" \
    'f=~/Desktop/quake3/ioquake3.app/Contents/Info.plist; [ -f "$f" ] && grep -A1 CFBundleVersion "$f" | tail -1 | sed "s/.*<string>//;s|</string>.*||"' 2>/dev/null)
  if [ "$GOT" = "$VERSION" ]; then
    pass "$m has $VERSION installed"
  else
    fail "$m has '${GOT:-nothing}', expected $VERSION"
  fi

  # 4b. no loose Mach-O called "ioquake3" beside the bundle (issue #10)
  if ssh -n -o ConnectTimeout=8 "$m" 'test -f ~/Desktop/quake3/ioquake3' 2>/dev/null; then
    fail "$m still has a loose ./ioquake3 beside the .app (double-click footgun, issue #10)"
  else
    pass "$m install dir has no duplicate 'ioquake3'"
  fi

  # 4c. THE ONE THAT MATTERS: does LaunchServices have a usable record?
  # This is the automatable half of "will it open by double-click", and it is
  # exactly what was silently broken while smoke-dmg reported PASS.
  LS=$("$HERE/lsregister-app.sh" "$m" 2>&1 || true)
  case "$LS" in
    *"no executable"*) fail "$m LaunchServices record has NO EXECUTABLE - double-click would say 'damaged'" ;;
    *OK*)              pass "$m LaunchServices record resolves to an executable" ;;
    *)                 warn "$m lsregister inconclusive: $(echo "$LS" | tail -1)" ;;
  esac
done

# ---- 5. the manual gate ---------------------------------------------------
echo "-- manual gate --"
if [ "${RELEASE_CHECK_ASSUME_CLICKED:-0}" = "1" ]; then
  warn "double-click test ASSUMED (RELEASE_CHECK_ASSUME_CLICKED=1)"
elif [ -t 0 ]; then
  echo "    On a real machine, mount the DMG, drag ioquake3.app next to a baseq3,"
  echo "    and DOUBLE-CLICK it in Finder. It must reach the main menu."
  printf "    Did the app open by double-click? [y/N] "
  read -r ans
  case "$ans" in
    [yY]*) pass "double-click confirmed by operator" ;;
    *)     fail "double-click NOT confirmed" ;;
  esac
else
  fail "not a terminal, so the double-click gate cannot be answered - re-run interactively, or set RELEASE_CHECK_ASSUME_CLICKED=1 if it has genuinely been done"
fi

echo
if [ "$FAILED" = 0 ]; then
  echo "release-check: PASS - $VERSION is fit to tag"
else
  echo "release-check: FAIL - do not tag $VERSION" >&2
fi
exit "$FAILED"
