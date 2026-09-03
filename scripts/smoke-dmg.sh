#!/usr/bin/env bash
# Smoke-test the DMG-installed copy of ioquake3 on a target Mac the way a human
# launches it: the per-machine production autoexec (baseq3/autoexec.cfg) drives
# the renderer — fullscreen, the machine's own resolution, full visual tune. We
# do NOT override vid/res (that's what bench.sh does for deterministic
# measurement). The only thing we add is a timedemo so the run AUTO-EXITS
# instead of sitting fullscreen forever — proof the world actually rendered (an
# fps line) on the real production path the corrupt-DMG class of bug slips past.
#
# LAUNCHED VIA LaunchServices (`open -n --args`) on 10.6+, the same path a
# Finder double-click takes — not a direct exec of the bundle's Mach-O, which
# every OTHER launcher script here still uses and which cannot see a quarantine
# flag, App Translocation, a bad signature, or a stale LS record (issue #37).
# Below 10.6 `open` has no `--args` at all (MEASURED: Panther/Tiger/Leopard's
# `open` usage lists no such flag), and Gatekeeper/quarantine doesn't exist yet
# either, so those OSes fall back to the direct-exec path — not a compromise,
# there is nothing for LaunchServices to catch there that direct exec misses.
#
# usage: scripts/smoke-dmg.sh <machine> [demo]
#   machine: yosemite | sawtooth | quicksilver | mini-g4 | imac-g5 | mini-intel | imac-2019
#   demo:    four (default — the classic Q3 timedemo)
#
# After this passes, start a NEW GAME by hand: the timedemo proves world render
# + correct res but NOT the live-server/entity spawn path.

set -euo pipefail
HOST="${1:?usage: $0 <machine> [demo]}"

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
	exec "$_PICK" --run "$HOST" "smoke-dmg" -- "$0" "$@"
fi
DEMO="${2:-four}"
# shellcheck disable=SC2088
# tilde stays unexpanded on purpose: it must
# resolve on the REMOTE host's home, not this workstation's. See ci.yml.
REMOTE_DIR="~/quake3"

case "$HOST" in
  yosemite|yosemite-tiger) TIMEOUT=300; COOLDOWN=5 ;;
  sawtooth)    TIMEOUT=240; COOLDOWN=3 ;;
  quicksilver) TIMEOUT=180; COOLDOWN=2 ;;
  mini-g4)     TIMEOUT=180; COOLDOWN=2 ;;
  imac-g5)     TIMEOUT=90;  COOLDOWN=2 ;;
  mini-intel)  TIMEOUT=300; COOLDOWN=1 ;;
  imac-2019)   TIMEOUT=60;  COOLDOWN=1 ;;
  g5-desktop|g5-tiger|g5-panther|quad-leopard|quad-tiger)
               TIMEOUT=120; COOLDOWN=2 ;;
  mini-intel2) TIMEOUT=300; COOLDOWN=1 ;;
  # 300, and the history matters because this line has been 90, then 180, then
  # 90 again.
  #
  # It went back to 90 on the reasoning that raising a timeout does not fix a
  # slow machine and only hides the fault. That was right about the FAULT and
  # wrong about what the timeout is FOR. mini-sl has no display attached, so its
  # GeForce 9400M gives no accelerated context and the engine binds the Apple
  # Software Renderer (#28). That is the fault, and no timeout fixes it.
  #
  # But the timeout's job is to tell a HUNG run from a SLOW one, and at 90 it
  # could not: measured today, mini-sl completes demo four in 170.9 seconds and
  # renders the world to the end. At 90 that machine reports a crash. It is
  # healthy and slow.
  #
  # This is the fault that put "mini-intel never completes a timedemo" into two
  # repos and a user-facing document. The allowance must sit above the machine's
  # real runtime, and a slow run stays visible because the result line carries
  # the seconds: 1260 frames 170.9 seconds 7.4 fps.
  mini-sl)     TIMEOUT=300; COOLDOWN=1 ;;
  *) echo "smoke-dmg: unknown machine: $HOST" >&2; exit 2 ;;
esac

# Both are overridable. The per-machine defaults are tuned for the demo each
# port uses at that machine's production settings, and a slower demo, a
# heavier config or a busy box can exceed them. When that happens the run is
# reported as a crash or hang, which is a much more alarming thing than the
# truth, and it leaves the engine still running for the NEXT run to trip over.
TIMEOUT="${SMOKE_TIMEOUT:-$TIMEOUT}"
COOLDOWN="${SMOKE_COOLDOWN:-$COOLDOWN}"

# HEADLESS CHECK. A Mac with no display attached cannot be smoke-tested
# meaningfully, and the way it fails is deeply misleading: this script reported
# "the production launch did not render a demo (crash or hang)" for two machines
# that were doing nothing of the kind.
#
# Measured 2026-08-23 (#28, #30). With no monitor:
#   mini-sl    GeForce 9400M present and driver loaded, but no accelerated
#              context, so the engine binds GL_RENDERER: Apple Software Renderer
#              and cannot finish a timedemo at any timeout.
#   mini-intel binds hardware GL but has no real display mode, so a 1920x1080
#              fullscreen request falls back to 640 x 480 and never completes.
# Two presentations, one cause, and neither is a crash.
#
# KEYED ON IODisplayConnect, NOT ON EDID, and that distinction is the whole
# check. The first version of this counted IODisplayEDID, which looked right
# because a real monitor supplies EDID. It is wrong on PowerPC: measured across
# the fleet on 2026-08-23,
#
#     machine      EDID  connect   renders?
#     yosemite       0      6      YES, benched and screenshotted all night
#     mini-g4        1      5      yes
#     g5-desktop     1      6      yes
#     mini-sl        0      1      no, software renderer
#     mini-intel     0      1      no, 640x480 fallback
#
# so EDID=0 would have warned "no display attached" on the G3 every single run,
# on the oldest and most awkward machine in the fleet, which is exactly where a
# spurious warning does most damage. Confirmed by running it: it did.
# INFERRED, not measured: the G3 probably drives an analog display, or its
# driver never publishes EDID.
#
# WHAT THIS TEST IS AND IS NOT. It is measured to separate two headless Intel
# minis from three working machines (one G3, one G4, one G5). connect<=1 has
# only ever been observed on those two, both the same class, so treat it as a
# useful signal rather than a law and do not apply it to untested hardware and
# believe the answer.
#
# WARN, do not refuse. mini-intel does bind hardware GL while headless, and a
# gate that refused a machine somebody had just plugged a monitor into would be
# worse than the confusion it prevents.
#
# `|| true` is load-bearing: grep -c EXITS 1 WHEN THE COUNT IS ZERO, which is
# precisely the headless case this check exists to catch. Without it, under
# set -euo pipefail, the assignment fails and the script dies silently with no
# output at all. The first version did exactly that, on the two machines it was
# written to diagnose.
# IODisplayConnect is confirmed present on 10.3.9: yosemite reports 6. That
# matters because the key this check ORIGINALLY used does not exist there at all
# -- Panther's ioreg has no IODisplayEDID key, so the count was 0 for a reason
# that had nothing to do with displays. Before reading a count as a measurement,
# prove the key exists on that OS version; this fleet spans 10.3 to 10.7 and a
# probe written against Lion returns confident zeros from Panther.
#
# An empty result means the probe could not run, which is NOT the same as zero,
# and must never be reported as "headless".
#
# BOUNDED, on the LOCAL side. Root-caused 2026-08-23 on mini-sl: this ioreg
# call went into uninterruptible kernel sleep on the remote end, unkillable by
# TERM/KILL there, and ssh has no built-in bound on a remote command that is
# already running - ConnectTimeout only covers connection setup, and
# ServerAlive keepalives are answered by sshd itself, not by the stuck child
# command. That hung this script (and the bench lock it holds) for over an
# hour with nothing to show for it; only a reboot of the target cleared it.
# Same run_deadline pattern as safebench.sh: killing the LOCAL ssh client is
# always safe, whatever is stuck on the far end is a separate problem this
# script cannot fix, and at least the caller and the lock are freed.
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
run_deadline() {
  _secs="$1"; shift
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$_secs" "$@"; return $?; fi
  "$@" &
  _p=$!; _t=0
  while [ "$_t" -lt "$_secs" ]; do
    kill -0 "$_p" 2>/dev/null || break
    sleep 1; _t=$((_t+1))
  done
  if kill -0 "$_p" 2>/dev/null; then
    kill -TERM "$_p" 2>/dev/null; sleep 2; kill -KILL "$_p" 2>/dev/null
  fi
  wait "$_p" 2>/dev/null
}
DCONNECT="$(run_deadline 15 ssh "$HOST" 'ioreg -lw0 2>/dev/null | grep -c IODisplayConnect || true' 2>/dev/null | tr -dc '0-9' || true)"
if [ -z "$DCONNECT" ]; then
  HEADLESS=0
  echo "[smoke $HOST] note: display probe did not answer; headless state NOT DETERMINED." >&2
elif [ "$DCONNECT" -le 1 ] 2>/dev/null; then
  HEADLESS=1
  echo "[smoke $HOST] WARNING: looks headless (IODisplayConnect=$DCONNECT)." >&2
  echo "  A Mac with no display cannot give a real fullscreen mode and may bind" >&2
  echo "  the software renderer. If this run fails, suspect that before the" >&2
  echo "  build. See issues #28 and #30." >&2
else
  HEADLESS=0
fi

# The bench fleet is SHARED. Launching a second fullscreen game on a box already
# running one wedges both. Bail if anything Quake-ish is live; FORCE=1 overrides.
# `ps ax`, NOT `ps -axo comm,pid`: the latter returns EMPTY on Tiger (unsupported
# option combination), so this guard silently never fired on the machines that
# needed it most — it would happily start a second fullscreen engine.
BUSY="$(ssh "$HOST" "ps ax 2>/dev/null | grep -iE 'ioquake3|quakespasm|quake2|/quake' | grep -v grep || true")"
if [ -n "$BUSY" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "[smoke $HOST] ABORT — $HOST is already running a game (shared bench):" >&2
  echo "$BUSY" | sed 's/^/    /' >&2
  echo "[smoke $HOST] wait for it to finish, or re-run with FORCE=1 if it is stale." >&2
  exit 2
fi

# `open --args` (pass command-line args through LaunchServices) does not exist
# before Snow Leopard: MEASURED across the fleet just now, `open` with no
# arguments prints its own usage line, and only 10.6+ lists `[--args
# arguments]` in it — Panther/Tiger/Leopard's `open` has no way to hand the
# engine +set overrides at all (Leopard has -n; Tiger/Panther do not even have
# that). Below 10.6, `open -n --args ...` doesn't fail loudly — Tiger's parser
# reads "-n" as a FILENAME and tries to open "quake3/-n", which is worse than
# a clean failure. So this is a real per-OS branch, not a nicety.
#
# Below 10.6 there is also no Gatekeeper/quarantine/App Translocation to catch
# in the first place (that machinery starts at 10.7.3/10.12), BUT direct exec
# still skips LaunchServices bundle resolution entirely on every OS — a bad
# Info.plist, a missing CFBundleExecutable, a stale LS record, or the bundle
# bit not being set (ADR 0014) would all break a real double-click while a
# direct exec of the Mach-O keeps working, on 10.3 exactly as on 10.15. That
# gap is closed below with a bare `open` pre-check on pre-10.6 hosts (issue
# #37, flagged by a peer review of the launch matrix): it proves LaunchServices
# can actually resolve and start the bundle, which direct exec can never prove
# regardless of OS era. `open --args` on 10.6+ already proves the same thing
# AND drives the timedemo in one launch, so it needs no separate pre-check.
OPEN_ARGS_OK=0
case "$(ssh -o ConnectTimeout=10 "$HOST" 'sw_vers -productVersion' 2>/dev/null)" in
  10.[0-5].*|10.[0-5]) OPEN_ARGS_OK=0 ;;
  10.*|11.*|12.*|13.*|14.*|15.*|16.*|26.*) OPEN_ARGS_OK=1 ;;
  *) OPEN_ARGS_OK=0 ;;   # unknown/empty answer: assume the conservative (older) path
esac

if [ "$OPEN_ARGS_OK" = 1 ]; then
  echo "[smoke $HOST] launching DMG-installed ioquake3.app via LaunchServices (open -n --args, the Finder double-click path), demo=$DEMO"
else
  echo "[smoke $HOST] launching DMG-installed ioquake3.app with PRODUCTION config (direct exec — this OS predates Gatekeeper/open --args), demo=$DEMO"
fi
# Finder-equivalent launch, not direct exec, ON 10.6+. Issue #37: every OTHER
# script here (bench.sh, safebench.sh, screenshot.sh, and this script until
# now) execs the bundle's Mach-O directly over ssh, which never goes through
# LaunchServices at all — so a build that CANNOT be double-clicked (quarantine,
# App Translocation, a bad code signature, a stale LS record) could still
# smoke-test PASS. That gap is exactly how a real user's "major problems
# reliably manually opening" report went uncaught: CLI/ssh exec passing while
# double-click fails is a bug, not a pass. `open -n` is what Finder itself
# does on a double-click.
#
# fs_basepath is DELIBERATELY NOT overridden on the open path (the direct-exec
# path still forces it to $PWD, same as always — there is no reason to change
# a mechanism that was never broken). Forcing it on the open path would mask
# exactly the class of bug this change exists to catch — the engine must find
# its own install directory from Sys_BinaryPath()/argv[0], the same as a real
# double-click, not be told where it lives. fs_homepath IS still set
# explicitly on both paths: that only controls where qconsole.log/q3config.cfg
# land, unrelated to basepath detection, and this script needs to know where
# to read the log back from.
#
# CRITICAL — make the engine QUIT ITSELF; never KILL a fullscreen app. We add
# +set nextdemo quit so CL_DemoCompleted runs 'quit' after the timedemo and the
# engine exits the NORMAL way (SDL restores the captured display, pid removed).
# A hard KILL on a still-fullscreen ioquake3 wedges the GPU driver / WindowServer
# until a reboot (this bit the fleet repeatedly — R300 G4 + GMA950 Lion). So the
# only backstop here is a gentle TERM if it somehow never self-quits; NEVER KILL.
# A stale pid file pops an "Abnormal Exit" modal that hangs headless — rm it first.
PIDF='$HOME/Library/Application Support/Quake3/ioq3.pid'

# PRE-CHECK, pre-10.6 hosts only: a bare `open` with NO ARGS AT ALL — the
# actual mechanism a Finder double-click uses, more literally than `open
# --args` even is (a real double-click never passes arguments either). This
# is the only way on these OSes to prove LaunchServices can resolve and start
# the bundle at all (Info.plist, CFBundleExecutable, the bundle bit, a stale
# LS record) — the thing direct exec can never test, on any OS, Gatekeeper or
# not. It launches into the production main menu (no demo — `open` has no way
# to pass one here), so it is quit with a plain TERM once confirmed running,
# same backstop pattern as everywhere else in this script, and the actual
# timedemo/fps measurement still comes from the direct-exec pass below.
PRECHECK_STATUS=""
if [ "$OPEN_ARGS_OK" = 0 ]; then
  echo "[smoke $HOST] pre-check: bare 'open' (no args — true double-click) proves LaunchServices can start this bundle"
  # NO `-n`: MEASURED on quicksilver (Tiger) — `-n` does not exist on Tiger's
  # `open` either, same trap as `--args` (the comment above this block already
  # documented `-n` for Leopard+, not for Tiger/Panther). Unrecognized, it is
  # read as a FILENAME ("No such file: .../-n") and the launch never happens,
  # exit 1, silently — exactly the failure mode already known from `--args`.
  # Plain `open ./ioquake3.app` launches correctly on both 10.3 and 10.4
  # (verified on quicksilver). `|| true` on the whole substitution: this must
  # not trip `set -e` and abort the script before the result is even read —
  # a real OPEN_FAILED/timeout needs to be reported and gated on below, not
  # crash the script into a bare non-zero exit with no explanation.
  PRECHECK_STATUS="$(ssh "$HOST" "
    cd $REMOTE_DIR || { echo NO_INSTALL; exit 9; }
    rm -f \"$PIDF\"
    open ./ioquake3.app || { echo OPEN_FAILED; exit 9; }
    k=0
    while [ \$k -lt 20 ]; do
      killall -0 ioquake3 2>/dev/null && break
      sleep 1; k=\$((k+1))
    done
    if killall -0 ioquake3 2>/dev/null; then
      echo OPEN_LAUNCH_OK
      killall -TERM ioquake3 2>/dev/null
      g=0; while [ \$g -lt 12 ]; do killall -0 ioquake3 2>/dev/null || break; sleep 1; g=\$((g+1)); done
    else
      echo OPEN_LAUNCH_TIMEOUT
    fi
    rm -f \"$PIDF\"" 2>/dev/null)" || true
  echo "[smoke $HOST] pre-check result: ${PRECHECK_STATUS:-<no output>}"
  # Same reboot backstop as the bottom of this script: if TERM didn't take,
  # the engine must not be left running for the direct-exec pass below to
  # collide with (two fullscreen instances wedges both, ADR 0009).
  if ssh "$HOST" 'killall -0 ioquake3 2>/dev/null'; then
    echo "[smoke $HOST] pre-check engine SURVIVED TERM and is still running; rebooting so it is" >&2
    echo "  not left on an unclaimed machine, and so the timedemo pass below has a clean start. See #29." >&2
    # shellcheck disable=SC2088
    ssh "$HOST" '~/bin/qsreboot.sh' 2>/dev/null || true
    t=0; while [ $t -lt 60 ]; do ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" true 2>/dev/null || break; sleep 5; t=$((t+5)); done
    if [ $t -ge 60 ]; then
      echo "[smoke $HOST] FAIL — pre-check engine did not die and reboot did not take (run 'sudo ~/bin/qsreboot-setup.sh')" >&2
      exit 1
    fi
    t=0; while [ $t -lt 240 ]; do ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" true 2>/dev/null && break; sleep 5; t=$((t+5)); done
    if [ $t -ge 240 ]; then
      echo "[smoke $HOST] FAIL — pre-check reboot did not come back within 240s" >&2
      exit 1
    fi
    echo "[smoke $HOST] back up after pre-check reboot, engine cleared"
  fi
fi

if [ "$OPEN_ARGS_OK" = 1 ]; then
LAUNCH_CMD='  open -n ./ioquake3.app --args \
    +set fs_homepath "$PWD" \
    +set logfile 2 +set nextdemo quit +set timedemo 1 +demo '"$DEMO"' \
    || { echo '"'"'OPEN_FAILED'"'"'; exit 9; }'
else
LAUNCH_CMD='  ./ioquake3.app/Contents/MacOS/ioquake3 \
    +set fs_basepath "$PWD" +set fs_homepath "$PWD" \
    +set logfile 2 +set nextdemo quit +set timedemo 1 +demo '"$DEMO"' > /dev/null 2>&1 &'
fi
ssh "$HOST" "
  killall -TERM ioquake3 2>/dev/null && sleep 2
  cd $REMOTE_DIR || { echo 'NO_INSTALL'; exit 9; }
  mv -f baseq3/qconsole.log baseq3/qconsole.log.prev 2>/dev/null; rm -f \"$PIDF\"
$LAUNCH_CMD
  # wait for the engine to self-quit (process gone) or error out; self-bounded
  j=0
  while [ \$j -lt $TIMEOUT ]; do
    killall -0 ioquake3 2>/dev/null || break            # self-quit = clean exit
    grep -qE 'ERROR:|Error:' baseq3/qconsole.log 2>/dev/null && break
    sleep 1; j=\$((j+1))
  done
  # backstop ONLY if it didn't self-quit: a gentle TERM (handler restores the
  # display). NEVER KILL a fullscreen ioquake3 — that wedges the GPU driver.
  if killall -0 ioquake3 2>/dev/null; then
    killall -TERM ioquake3 2>/dev/null
    g=0; while [ \$g -lt 12 ]; do killall -0 ioquake3 2>/dev/null || break; sleep 1; g=\$((g+1)); done
  fi
  rm -f \"$PIDF\"
  sleep $COOLDOWN
  true"

# REBOOT BACKSTOP. The remote block above sends TERM and waits 12s, and if the
# engine survives that it simply falls through: the script returns, the bench
# lock is released with it, and the engine keeps running on an unclaimed machine.
#
# Measured 2026-08-23 (#29): a smoke run on mini-sl left this exact state, and it
# was still there twenty minutes later, found only because another repo refused
# to take the machine. TERM did not take because that machine renders with the
# software renderer and never finishes the demo, so `nextdemo quit` never fires.
#
# safebench.sh has never produced this state, and the reason is that it REBOOTS
# when the engine will not die. The backstop is the design, not a nicety, and
# this script was missing it. Same pattern, deliberately: verify it went down and
# came back rather than trusting qsreboot.sh's exit code, whose Finder fallback
# can report a false success.
#
# NEVER KILL instead: a hard KILL on a fullscreen ioquake3 wedges the GPU driver
# and takes the WindowServer with it, which is the thing this whole script is
# careful about.
if ssh "$HOST" 'killall -0 ioquake3 2>/dev/null'; then
  echo "[smoke $HOST] engine SURVIVED TERM and is still running; rebooting so it is" >&2
  echo "  not left on an unclaimed machine. See #29." >&2
  # shellcheck disable=SC2088
  # tilde stays unexpanded on purpose: it must
  # resolve on the REMOTE host's home, not this workstation's. See ci.yml.
  ssh "$HOST" '~/bin/qsreboot.sh' 2>/dev/null || true
  t=0; while [ $t -lt 60 ]; do ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" true 2>/dev/null || break; sleep 5; t=$((t+5)); done
  if [ $t -ge 60 ]; then
    echo "[smoke $HOST] did NOT go down - reboot FAILED (run 'sudo ~/bin/qsreboot-setup.sh')" >&2
  else
    t=0; while [ $t -lt 240 ]; do ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" true 2>/dev/null && break; sleep 5; t=$((t+5)); done
    [ $t -ge 240 ] && echo "[smoke $HOST] did not come back within 240s" >&2 || echo "[smoke $HOST] back up, engine cleared" >&2
  fi
fi

# Pull the log and report.
TMP=$(mktemp)
scp -q "$HOST:quake3/baseq3/qconsole.log" "$TMP" 2>/dev/null || { echo "[smoke $HOST] FAIL: no qconsole.log (engine never wrote one)"; rm -f "$TMP"; exit 1; }

FPS_LINE=$(grep -E 'frames.*seconds.*fps' "$TMP" 2>/dev/null | tail -1 || true)
MODE_LINE=$(grep -iE 'GL_RENDERER|Initializing OpenGL|setting mode|MODE:' "$TMP" 2>/dev/null | tail -2 | tr '\n' ' ' || true)
rm -f "$TMP"

echo "[smoke $HOST] renderer : ${MODE_LINE:-<none>}"
echo "[smoke $HOST] result   : ${FPS_LINE:-<NO FPS LINE>}"

# Repair on the way out regardless of pass/fail — a smoke test must not leave
# the machine less launchable than it found it. Belt and braces: this script
# now launches via `open` (LaunchServices) rather than a direct exec, which is
# what used to corrupt the LS record here (MEASURED, one run on Lion flipped a
# good record to blank — that was direct-exec-specific and should no longer
# happen from this script, but lsregister-app.sh is cheap and idempotent, and
# other scripts here still direct-exec, so a stale record from one of THOSE
# runs is still worth clearing on the way out). See scripts/lsregister-app.sh.
"$(dirname "$0")/lsregister-app.sh" "$HOST" || true

# On pre-10.6 hosts, a PASS also needs the bare-open pre-check to have proven
# LaunchServices can actually start this bundle — an fps line from the
# direct-exec pass alone would not have caught a launch that only works via
# direct exec, which is exactly the class of bug issue #37 exists to catch.
if [ "$OPEN_ARGS_OK" = 0 ] && [ "$PRECHECK_STATUS" != "OPEN_LAUNCH_OK" ]; then
  echo "[smoke $HOST] FAIL — bare 'open' pre-check did not confirm a LaunchServices launch (${PRECHECK_STATUS:-<none>}), even though the direct-exec timedemo pass may have rendered fine." >&2
  echo "  That is a real double-click failure this script would otherwise have missed. See #37." >&2
  exit 1
fi

if [ -n "$FPS_LINE" ]; then
  echo "[smoke $HOST] PASS — world rendered to completion on the production path, via Finder-equivalent launch"
  exit 0
else
  if [ "${HEADLESS:-0}" = 1 ]; then
  echo "[smoke $HOST] FAIL — no fps line, and this machine has NO DISPLAY ATTACHED."
  echo "  That is the likely cause: see #28 and #30. Not necessarily a build fault."
else
  echo "[smoke $HOST] FAIL — no fps line; the LaunchServices launch did not render a demo." >&2
  echo "  Could be a crash/hang (see qconsole.log above), OR the app never actually" >&2
  echo "  started at all: Gatekeeper/AMFI can kill a quarantined, ad-hoc-signed launch" >&2
  echo "  outright on 10.12+ with NOTHING written to qconsole.log (issue #37, measured" >&2
  echo "  on imac-2019 — check 'log show --predicate eventMessage contains \"ioquake3\"'" >&2
  echo "  on the target for AMFI/ASP denial lines if this machine runs 10.12 or later." >&2
fi
  exit 1
fi
