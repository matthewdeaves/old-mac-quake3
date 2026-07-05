#!/bin/bash
# Reboot this Mac reliably, even with a wedged Finder or a corrupt display LUT
# (the state a hard-killed fullscreen ioquake3 can leave the old GPUs in).
#
# Prints a `QSREBOOT:` marker naming the tier that fired, so the caller can tell
# a real kernel reboot from an UNVERIFIED Finder event. This matters: the Finder
# fallback returns success even when it silently does nothing (headless / wedged
# Finder), which once looked like a successful reboot when the machine never went
# down. NEVER trust this script's exit code alone — confirm the host actually
# drops off the network and comes back (install-host-tools.sh / safebench do this).
#
# Tier 1 (preferred): `sudo -S /sbin/reboot </dev/null`. Needs the NOPASSWD
#   sudoers entry installed once by qsreboot-setup.sh. We use -S (read pw from
#   stdin), NOT -n: Panther/Tiger/Leopard BSD sudo reject -n ("Illegal option").
#   </dev/null feeds an empty password so it FAILS FAST (falls to tier 2) instead
#   of hanging if the sudoers entry is missing.
# Tier 2 (fallback): Finder AppleEvent restart. Works only with a live Aqua
#   session and can no-op silently — hence flagged UNVERIFIED.

if sudo -S /sbin/reboot </dev/null >/dev/null 2>&1; then
    echo "QSREBOOT: tier1 kernel reboot initiated"
    exit 0
fi
if osascript -e 'tell application "Finder" to restart' >/dev/null 2>&1; then
    echo "QSREBOOT: tier2 finder restart requested (UNVERIFIED — confirm host went down)"
    exit 0
fi
echo "QSREBOOT: FAILED — no NOPASSWD sudoers entry and Finder unresponsive" >&2
exit 1
