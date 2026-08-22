#!/usr/bin/env bash
# Install the host-side recovery tooling (qsreboot.sh + qsreboot-setup.sh) to
# ~/bin on the bench Macs. Idempotent — re-run after adding a machine or editing
# the source scripts in scripts/host-bin/.
#
# Two steps, per machine:
#   1) this script            — copies the scripts to ~/bin and chmod +x
#   2) sudo ~/bin/qsreboot-setup.sh  — installs the NOPASSWD sudoers entry ONCE
#      (needs the machine's admin password; without it qsreboot.sh cannot do a
#      real kernel reboot and silently falls back to an unverified Finder event)
#
# After both, `ssh <host> '~/bin/qsreboot.sh'` reboots cleanly through the kernel
# even if Finder / the display LUT is wedged. This script VERIFIES a real reboot
# by watching the host drop off the network and come back — it does not trust
# qsreboot.sh's exit code (the Finder fallback can report a false success).
#
# usage: scripts/install-host-tools.sh [host [host...]]
#   default hosts: yosemite sawtooth quicksilver mini-g4 mini-intel imac-2019 imac-g5
# env:
#   HOSTS_ENV=...   override the default host list
#   VERIFY_REBOOT=1 after install, actually reboot each host and confirm it cycles

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/scripts/host-bin"

HOSTS=("$@")
[ ${#HOSTS[@]} -eq 0 ] && HOSTS=(${HOSTS_ENV:-yosemite sawtooth quicksilver mini-g4 mini-intel imac-2019 imac-g5})

# Claim each machine before touching it, and release it again before moving on.
#
# This script drove the whole fleet over ssh without ever taking the lock, so it
# could walk into another repo's running bench. It claims PER HOST rather than
# for the whole run, because it loops over many machines and holding all of them
# for the duration would block the fleet for no reason. Issue #24.
#
# A nonce is exported so the release is strict: without one the picker falls back
# to matching user@host:repo, which every session in this repo shares.
# old-mac-build-host#7.
_PICK="$REPO_ROOT/scripts/pick-bench-host.sh"
export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-$$.$(date +%s).${RANDOM:-0}}"
_HELD=""
_release_held() { if [ -n "$_HELD" ]; then "$_PICK" --release "$_HELD" >/dev/null 2>&1 || true; _HELD=""; unset RETRO_BENCH_LOCK; fi; }
# EXIT as well as the explicit release below, so a failure mid-host does not
# leave the machine claimed until the stale reclaim.
trap _release_held EXIT INT TERM
_claim_host() { # <host> -> 0 claimed / 1 skip
    [ "${BENCH_NO_LOCK:-0}" = 1 ] && return 0
    [ -x "$_PICK" ] || return 0
    if "$_PICK" --acquire "$1" "quake3 $(basename "$0")" >/dev/null 2>&1; then
        _HELD="$1"
        # Tell nested scripts the machine is already claimed. lsregister-app.sh
        # and friends re-exec themselves under pick-bench-host.sh --run unless
        # RETRO_BENCH_LOCK is set, and that nested acquire cannot succeed while
        # we hold the same host: it would fail and the caller would report an
        # inconclusive result on a machine that is perfectly fine. Caught by
        # running this against a real host rather than by reading it.
        export RETRO_BENCH_LOCK="$1"
        return 0
    fi
    return 1
}

# Poll a host until it stops responding (down) or starts responding (up).
wait_state() { # <host> <up|down> <timeout_s>
    local host="$1" want="$2" deadline="$3" t=0
    while [ "$t" -lt "$deadline" ]; do
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" true 2>/dev/null; then
            [ "$want" = up ] && return 0
        else
            [ "$want" = down ] && return 0
        fi
        sleep 5; t=$((t+5))
    done
    return 1
}

for host in "${HOSTS[@]}"; do
    echo "=== $host ==="
    _claim_host "$host" || { echo "[$host] busy (another session holds it), skipping"; continue; }
    ssh -o ConnectTimeout=10 "$host" 'mkdir -p ~/bin' || { echo "[$host] ssh failed (asleep/off?)"; _release_held; continue; }
    for script in qsreboot.sh qsreboot-setup.sh; do
        scp -q "$SRC/$script" "$host:bin/$script"
        ssh "$host" "chmod +x ~/bin/$script"
    done
    echo "[$host] installed ~/bin/qsreboot.sh ~/bin/qsreboot-setup.sh"

    # NOTE: do NOT probe by running /sbin/reboot with any flag — BSD reboot
    # ignores unknown flags (e.g. --help) and just REBOOTS. The only safe way to
    # confirm the NOPASSWD entry is to inspect sudoers (needs the admin password,
    # so we don't do it here) or to VERIFY_REBOOT=1 for a real down/up cycle.
    echo "[$host] if not done yet, enable reboots ONCE:  ssh $host 'sudo ~/bin/qsreboot-setup.sh'"

    if [ "${VERIFY_REBOOT:-0}" = 1 ]; then
        echo "[$host] VERIFY_REBOOT: rebooting and confirming it cycles..."
        ssh "$host" '~/bin/qsreboot.sh' || true
        if wait_state "$host" down 60 && wait_state "$host" up 240; then
            echo "[$host] reboot VERIFIED (went down and came back)"
        else
            echo "[$host] reboot NOT verified — host did not cycle (check qsreboot-setup)"
        fi
    fi
    _release_held
done

echo
echo "Per machine, once:  ssh <host> 'sudo ~/bin/qsreboot-setup.sh'   (admin password)"
echo "Then to reboot:     ssh <host> '~/bin/qsreboot.sh'"
echo "Verify for real:    VERIFY_REBOOT=1 scripts/install-host-tools.sh <host>"
