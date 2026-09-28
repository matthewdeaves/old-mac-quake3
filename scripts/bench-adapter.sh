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
#
# build-host#135/old-mac-quake3#75: a peer running this port's bench through
# bench-evidence.sh must never leave uncommitted output in THIS repo's
# tree. bench_launch below already satisfies that unconditionally: its only
# writes are "$workdir"/log.txt and stats.{txt,unit} -- $workdir is
# bench-evidence.sh's own bundle dir (its $EVROOT), never this repo's
# benchmarks/. safebench.sh, which it wraps, writes nothing into this repo
# either (checked: no REPO_ROOT/PROJ_LOCAL/benchmarks/ reference in it). The
# only path in this port that writes into the tracked benchmarks/ tree is
# scripts/bench.sh, an owner-run script bench_launch never calls; it now
# honours BENCH_OUT_DIR too (see its own header) for the same reason, in
# case that ever changes.

# shellcheck disable=SC2034  # read by bench-evidence.sh after sourcing this file
PORT=quake3

# Shared evidence tooling supports absolute installed paths (build-host#107).
# shellcheck disable=SC2034  # read by bench-evidence.sh after sourcing this file
INSTALL_BIN='/Applications/Quake3/ioquake3.app/Contents/MacOS/ioquake3'

BENCH_DEMO="${BENCH_DEMO:-four}"

# Resolution is never guessed here. docs/adr/0009: a non-native fullscreen
# switch hard-hangs the G5's R300 driver and corrupts the other old GPUs'
# display, so safebench.sh itself takes WxH as a required argument rather
# than looking it up -- this adapter does not add a second, silently-guessed
# source of truth. Caller must pass the host's confirmed native resolution as
# BENCH_RES (see docs/PROFILING.md's native-resolution confirmations table).
bench_launch() {
	local host="$1" workdir="$3"  # $2 (round) is unused: the contract passes it, this adapter doesn't need it
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
