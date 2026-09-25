#!/usr/bin/env bash
# scripts/bench-adapter.sh -- quake3's port adapter for the shared bench-evidence
# contract (build-host#104). Port-owned, like dmg-port.conf/dmg-hooks.sh: never
# synced from old-mac-build-host, never edited there. Contract:
# old-mac-build-host/docs/bench-evidence.md. Sourced by scripts/bench-evidence.sh.
#
# Wraps safebench.sh, which already encodes the only safe launch/shutdown
# sequence for a fullscreen ioquake3 (docs/adr/0009) and blocks until the
# engine self-quits -- so bench_launch here is synchronous and always leaves
# PID empty. bench-evidence.sh then records liveness as "not checked", which
# is correct: safebench.sh's own reboot backstop already catches a stuck
# engine (scripts/CLAUDE.md), a live two-sample poll would add nothing.

PORT=quake3

# bench-evidence.sh always does "$HOME/$INSTALL_BIN" (old-mac-build-host#107 --
# filed: the contract doc says INSTALL_BIN may be absolute, but the script
# does not special-case a leading '/'). quake3's install is root-level
# (/Applications/Quake3, deploy.sh:57), not under any user's $HOME, so this is
# a path-traversal value that resolves correctly rather than a real absolute
# path. Verified $HOME is /Users/<name> (2 components) on every active bench
# host (mini-g4, imac-g5, mini-sl, mini-intel, mini-intel2, imac-2019); if a
# future host's $HOME sits at a different depth, this breaks and the hash
# check drops to "not checked" (sh_host's shasum finds nothing), never a
# false pass. Switch back to the plain absolute path once #107 is fixed.
INSTALL_BIN='../../Applications/Quake3/ioquake3.app/Contents/MacOS/ioquake3'

BENCH_DEMO="${BENCH_DEMO:-four}"

# Resolution is never guessed here. docs/adr/0009: a non-native fullscreen
# switch hard-hangs the G5's R300 driver and corrupts the other old GPUs'
# display, so safebench.sh itself takes WxH as a required argument rather
# than looking it up -- this adapter does not add a second, silently-guessed
# source of truth. Caller must pass the host's confirmed native resolution as
# BENCH_RES (see docs/PROFILING.md's native-resolution confirmations table).
bench_launch() {
	local host="$1" round="$2" workdir="$3"
	local self_dir out rc fps
	self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

	if [ -z "${BENCH_RES:-}" ]; then
		{
			echo "bench-adapter: BENCH_RES=<WxH> required -- the host's confirmed"
			echo "  native resolution (docs/PROFILING.md), never guessed here."
			echo "  docs/adr/0009: a non-native fullscreen switch hard-hangs the G5's"
			echo "  R300 driver and corrupts the other old GPUs' display."
		} > "$workdir/log.txt"
		echo fps > "$workdir/stats.unit"
		echo "EXIT=2"
		echo "PID="
		return
	fi

	# +cvarlist alongside the normal pinned launch so bench_effective_config has
	# real read-back data even outside AUTOCONFIG mode (safebench.sh only adds
	# +cvarlist itself when AUTOCONFIG=1). Placed in the same EXTRA slot, so it
	# runs after all the fixed +set cvars and before +demo, same as the
	# AUTOCONFIG branch's own +cvarlist.
	out="$("$self_dir/safebench.sh" "$host" "$BENCH_RES" "$BENCH_DEMO" "${BENCH_EXTRA:-} +cvarlist" 2>&1)"
	rc=$?
	printf '%s\n' "$out" > "$workdir/log.txt"

	# safebench.sh's summary line: "[host WxH] <N> frames <S> seconds <F> fps ...".
	fps="$(printf '%s\n' "$out" | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1 | awk '{print $1}')"
	[ -n "$fps" ] && printf '%s\n' "$fps" > "$workdir/stats.txt"
	echo fps > "$workdir/stats.unit"

	echo "EXIT=$rc"
	echo "PID="
}

# safebench.sh always blocks until the engine has self-quit or the deadline
# backstop fires (docs/adr/0009), so bench_launch never leaves PID non-empty
# and this is never called live -- kept only to satisfy the adapter contract.
bench_liveness() {
	:
}

# Read back from the qconsole.log this host's install just wrote (the same
# lines CLAUDE.md already greps for r_swapInterval/GL_RENDERER), rather than
# trust the requested flags. host=workstation is never a quake3 bench target,
# so this is always ssh.
bench_effective_config() {
	local host="$1"
	ssh -o BatchMode=yes -o ConnectTimeout=15 "$host" \
		"grep -F -e 'GL_RENDERER' -e ' r_swapInterval \"' -e ' r_mode \"' -e ' r_fullscreen \"' \
		 -e ' r_customwidth \"' -e ' r_customheight \"' \
		 /Applications/Quake3/baseq3/qconsole.log 2>/dev/null" 2>/dev/null \
	| sed -n \
		-e 's/.*GL_RENDERER: */renderer=/p' \
		-e 's/.* r_swapInterval "\([^"]*\)".*/r_swapInterval=\1/p' \
		-e 's/.* r_mode "\([^"]*\)".*/r_mode=\1/p' \
		-e 's/.* r_fullscreen "\([^"]*\)".*/r_fullscreen=\1/p' \
		-e 's/.* r_customwidth "\([^"]*\)".*/r_customwidth=\1/p' \
		-e 's/.* r_customheight "\([^"]*\)".*/r_customheight=\1/p'
}
