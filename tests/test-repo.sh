#!/usr/bin/env bash
#
# Repo invariants. Needs no fleet hardware, no toolchain and no network, so it
# runs on a GitHub runner or by hand: tests/test-repo.sh
#
# These are not style checks. Each one encodes a bug THIS repo actually shipped,
# so a failure means the bug is back, not that someone wrote something oddly.
#
# EVERY DETECTOR SELF-TESTS BEFORE IT IS TRUSTED, against a known-BAD fixture
# where it must fire and a known-GOOD one where it must not. A grep over a
# directory it cannot read returns "no matches" and reads exactly like success;
# that happened repeatedly on 2026-08-22, once producing a confident "0 one-arg
# call sites" against an unreadable tree. A detector that cannot catch the bug it
# exists for must fail this script before it says anything about the repo.
#
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

FAIL=0
note() { printf '  %s\n' "$*"; }
ok()   { printf '\033[32mPASS\033[0m  %s\n' "$*"; }
bad()  { printf '\033[31mFAIL\033[0m  %s\n' "$*"; FAIL=1; }

# --- detectors -------------------------------------------------------------
# Each takes a directory, prints offenders, and exits 0 when it FINDS a problem.

# Tonight's bug, 1c8f2365. The bench-lock re-exec guard tested whether
# RETRO_BENCH_LOCK was SET rather than whether it named the machine being
# targeted. Once pick-bench-host.sh --run began exporting it, a script running
# under a claim on one machine silently skipped claiming a DIFFERENT one, which
# is the unclaimed-host fault arriving through the back door.
# make-dmg.sh is exempt: it loops candidate hosts and has not chosen one yet.
det_bare_lock_guard() {
	grep -ln 'z "${RETRO_BENCH_LOCK' "$1"/*.sh 2>/dev/null | grep -v 'make-dmg\.sh$'
}

# Tonight's bug, dacaa020 and 6a7fd1e2. A caller that acquires the lock without
# exporting a claim nonce writes an owner file with no claim=, so the release
# falls back to matching user@host:repo, which every session in this repo shares
# and which therefore cannot tell two of them apart.
det_acquire_without_nonce() {
	local f
	for f in "$1"/*.sh; do
		[ -e "$f" ] || continue
		case "$(basename "$f")" in pick-*) continue ;; esac
		if grep -q -- '--acquire' "$f" 2>/dev/null && ! grep -q 'BENCH_LOCK_CLAIM' "$f" 2>/dev/null; then
			echo "$f"
		fi
	done
}

# Issue #20, fixed in fd1cc396. build-fat.sh decided whether to fuse the arm64
# slice with a bare existence test, so it would fuse a slice built from source
# that had since moved and print a success line doing it. arm64 is the only
# slice not rebuilt in place, so it is the only one that can go stale.
det_arm64_existence_only() {
	local f="$1/build-fat.sh"
	[ -f "$f" ] || return 1
	if grep -q 'ioquake3-arm64' "$f" && ! grep -q 'source_stamp_verify' "$f"; then
		echo "$f"
	fi
}

# CLAUDE.md hard rule: no em dashes anywhere, prose or shipped strings. Checked
# on the bundled configs and docs because those are what a player or a reader
# actually sees.
det_em_dash() {
	grep -rl $'—' "$1" 2>/dev/null
}

# --- self-test: prove each detector fires on bad and stays quiet on good -----
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/bad" "$FIX/good"

printf 'if [ -z "${RETRO_BENCH_LOCK:-}" ]; then\nfi\n'          > "$FIX/bad/a.sh"
printf 'if [ "${RETRO_BENCH_LOCK:-}" != "$M" ]; then\nfi\n'      > "$FIX/good/a.sh"
printf 'x=$(pick.sh --acquire "job")\n'                          > "$FIX/bad/b.sh"
printf 'export BENCH_LOCK_CLAIM=n\nx=$(pick.sh --acquire "j")\n'  > "$FIX/good/b.sh"
printf 'if [ -f "$OUT/ioquake3-arm64" ]; then\nfi\n'             > "$FIX/bad/build-fat.sh"
printf 'source_stamp_verify d h\nioquake3-arm64\n'               > "$FIX/good/build-fat.sh"
printf 'a \xe2\x80\x94 b\n'                                      > "$FIX/bad/c.cfg"
printf 'a - b\n'                                                 > "$FIX/good/c.cfg"

selftest() { # <name> <detector>
	local name="$1" det="$2"
	if ! $det "$FIX/bad" >/dev/null 2>&1; then
		bad "detector $name did NOT fire on its bad fixture; it cannot be trusted"
		return
	fi
	if $det "$FIX/good" 2>/dev/null | grep -q .; then
		bad "detector $name fired on its GOOD fixture; it would refuse correct code"
		return
	fi
	ok "detector $name catches bad and passes good"
}

echo "== detector self-test =="
selftest bare-lock-guard      det_bare_lock_guard
selftest acquire-without-nonce det_acquire_without_nonce
selftest arm64-existence-only  det_arm64_existence_only
selftest em-dash               det_em_dash

# --- the input has to actually be there ------------------------------------
# A check over a missing directory reports "clean". Refuse to report anything
# unless the things being checked are present and readable.
echo
echo "== input present =="
for d in scripts scripts/bundle docs; do
	if [ -d "$d" ] && [ -r "$d" ]; then ok "$d readable"; else bad "$d missing or unreadable"; fi
done
n=$(ls -1 scripts/*.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "${n:-0}" -ge 10 ]; then ok "scripts/ has $n shell scripts"; else bad "scripts/ has only ${n:-0} shell scripts; input looks wrong"; fi

# --- the invariants --------------------------------------------------------
echo
echo "== invariants =="

out=$(det_bare_lock_guard scripts)
if [ -n "$out" ]; then bad "bench-lock guard tests only that RETRO_BENCH_LOCK is set:"; note "$out"
else ok "every bench-lock guard compares against its target host"; fi

out=$(det_acquire_without_nonce scripts)
if [ -n "$out" ]; then bad "acquires the host lock without exporting a claim nonce:"; note "$out"
else ok "every --acquire caller exports BENCH_LOCK_CLAIM"; fi

out=$(det_arm64_existence_only scripts)
if [ -n "$out" ]; then bad "build-fat.sh decides on the arm64 slice by existence alone:"; note "$out"
else ok "build-fat.sh verifies the arm64 slice against a source stamp"; fi

out=$(det_em_dash scripts/bundle docs README.md CLAUDE.md MISTAKES.md 2>/dev/null)
if [ -n "$out" ]; then bad "em dashes present (CLAUDE.md forbids them):"; note "$out"
else ok "no em dashes in configs or docs"; fi

# Every per-machine config named in the engine's map must exist in the bundle.
# Com_ExecConfigFromBundle returns qfalse SILENTLY when a file is absent, so a
# typo or a rename here is not an error at runtime; the machine just quietly
# gets the arch baseline and nobody is told.
missing=""
while IFS= read -r cfg; do
	[ -n "$cfg" ] || continue
	[ -f "scripts/bundle/$cfg.cfg" ] || missing="$missing $cfg"
done < <(sed -n 's/.*{ *"[^"]*", *"\(autoexec-[a-z0-9-]*\)".*/\1/p' code/qcommon/common.c 2>/dev/null | sort -u)
if [ -n "$missing" ]; then bad "com_machineMap names configs with no file in scripts/bundle/:"; note "$missing"
else ok "every config in com_machineMap exists in scripts/bundle/"; fi

echo
if [ "$FAIL" = 0 ]; then echo "test-repo: all invariants hold"; else echo "test-repo: FAILURES above"; fi
exit $FAIL
