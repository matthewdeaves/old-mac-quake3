#!/usr/bin/env bash
# Build the Linux dedicated-server release from the same ioquake3 tree the Mac
# fat binary is built from.
#
# This is a SEPARATE release from the fat Mac app. It ships one ELF binary for
# one Linux architecture, built in a container so the result does not depend on
# whatever happens to be installed on the machine that ran it.
#
# usage: scripts/build-server-linux.sh [--arch x86_64|aarch64] [--version V]
#        [--allow-dirty]   development build from an unclean tree, marked as such
# output: dist/server/quake3-server-<version>-linux-<arch>.tar.gz
#
# Requires Docker (or Colima). No local compiler is used.
#
# WHY ONLY ONE BINARY
#
# Unlike Quake II, nothing else has to be built. Quake III's game logic ships
# as QVM bytecode inside id's own pak files, and bytecode is CPU independent,
# so the server runs the same qagame.qvm the clients already have. There is no
# per-architecture game library to produce.
#
# scripts/build.sh sets BUILD_SERVER=0 for the Mac builds because the Mac
# release is a client. Here it is the only thing turned on.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ARCH="x86_64"
VERSION=""
VERSION_GIVEN=0
ALLOW_DIRTY=0

while [ $# -gt 0 ]; do
	case "$1" in
		--arch)    ARCH="${2:?--arch needs a value}"; shift 2 ;;
		--version) VERSION="${2:?--version needs a value}"; VERSION_GIVEN=1; shift 2 ;;
		--allow-dirty) ALLOW_DIRTY=1; shift ;;
		-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
		*) echo "$0: unknown argument: $1" >&2; exit 2 ;;
	esac
done

case "$ARCH" in
	x86_64)  DOCKER_PLATFORM="linux/amd64"; IOQ3_ARCH="x86_64" ;;
	aarch64) DOCKER_PLATFORM="linux/arm64"; IOQ3_ARCH="aarch64" ;;
	*) echo "$0: unsupported arch: $ARCH (expected x86_64 or aarch64)" >&2; exit 2 ;;
esac

# PROVENANCE
#
# A published tarball has to be rebuildable from the tag it was released under.
# v0.6.3 was not: it was built from a modified tree, and the version it was
# given named a tag that did not point at the commit being compiled. Both slips
# were visible in its own BUILD-INFO.txt and neither stopped the build. See
# issue #21.
#
# Note git diff --quiet compares the working tree against the INDEX, so a change
# that is staged but not committed reads as clean. Measured: with one staged
# edit, git diff --quiet exits 0 while git diff --quiet HEAD exits 1. That is
# why the check below is git status --porcelain, which sees staged, unstaged and
# untracked alike. build/ and dist/ are gitignored, so ordinary build output
# does not trip it.
if [ -z "$VERSION" ]; then
	VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo unknown)"
fi
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY=""

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
	if [ "$ALLOW_DIRTY" -eq 0 ]; then
		echo "$0: the working tree is not clean, refusing to build." >&2
		echo "$0: a release built from a dirty tree cannot be rebuilt from its tag." >&2
		echo "$0: commit or stash first, or pass --allow-dirty for a throwaway build." >&2
		git status --short >&2
		exit 1
	fi
	GIT_DIRTY=" (working tree modified - NOT REPRODUCIBLE)"
	case "$VERSION" in
		*-dirty|*+dirty) ;;
		*) VERSION="$VERSION+dirty" ;;
	esac
	echo "$0: WARNING building from a dirty tree, version is now $VERSION" >&2
fi

# An explicit --version that names an existing tag must name THIS commit.
if [ "$VERSION_GIVEN" -eq 1 ] && git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null 2>&1; then
	TAG_COMMIT="$(git rev-parse --short "refs/tags/$VERSION^{commit}")"
	HEAD_COMMIT="$(git rev-parse --short HEAD)"
	if [ "$TAG_COMMIT" != "$HEAD_COMMIT" ]; then
		echo "$0: --version $VERSION is a tag at $TAG_COMMIT but HEAD is $HEAD_COMMIT." >&2
		echo "$0: check out the tag, or pick a version that is not an existing tag." >&2
		exit 1
	fi
fi
BUILD_DATE="$(date -u '+%Y-%m-%d %H:%M UTC')"

IMAGE="oldmac-quake3-server-build:deb11"
OUT_DIR="$REPO_ROOT/dist/server"
WORK="$REPO_ROOT/build/server-linux-$ARCH"

echo "[server] quake3 dedicated server"
echo "[server]   arch     : $ARCH ($DOCKER_PLATFORM)"
echo "[server]   version  : $VERSION"
echo "[server]   commit   : $GIT_COMMIT$GIT_DIRTY"

command -v docker >/dev/null 2>&1 || {
	echo "$0: docker not found. Start Colima or Docker Desktop first." >&2; exit 1; }
docker info >/dev/null 2>&1 || {
	echo "$0: the Docker daemon is not responding. Try: colima start" >&2; exit 1; }

mkdir -p "$WORK" "$OUT_DIR"

echo "[server] building container image"
docker build --platform "$DOCKER_PLATFORM" \
	-t "$IMAGE" -f scripts/docker/server-build.Dockerfile scripts/docker >/dev/null

echo "[server] staging source"
rm -rf "$WORK/src"
mkdir -p "$WORK/src"
tar cf - code Makefile misc | tar xf - -C "$WORK/src"

# This heredoc is UNQUOTED on purpose: every '\$' below is escaped by hand so the
# container script gets it literally, and quoting the delimiter would ship those
# backslashes through as well.
#
# The cost is that '$', backticks and '\' are all live here, INCLUDING INSIDE
# COMMENTS. A comment that quoted a shell fragment in backticks was therefore
# executed at heredoc-write time, and the command inside it read stdin. When this
# script runs with a terminal or an open pipe on stdin, that read never returns:
# the build stops dead after "staging source" with no error, no container and no
# output, for as long as you leave it. Fifteen minutes were lost to it on
# 2026-08-22. Quote shell fragments in comments below with " ", never ` `.
cat > "$WORK/build-in-container.sh" <<CONTAINER_SCRIPT
#!/bin/sh
set -e
cd /work/src

# Hardening.
#
# This binary parses UDP datagrams from strangers, in C written in 1999, and is
# meant to sit on the internet permanently. Debian's gcc gives PIE and NX by
# default and nothing else, so a plain build ships with no stack canaries, no
# FORTIFY_SOURCE and only partial RELRO. These are the difference between a
# memory-safety bug being a crash and being a shell.
#
# ioquake3's release target passes CFLAGS through additively
# (CFLAGS="\$(CFLAGS) \$(BASE_CFLAGS) ..."), and never assigns LDFLAGS itself,
# so both reach the compiler without displacing anything.
#
# Only the dedicated executable is built here, no .so, so -pie is safe.
export CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE"
export LDFLAGS="-Wl,-z,relro,-z,now -Wl,-z,noexecstack -pie"

echo "[container] building ioq3ded"
# Server only. No client, no renderer, no game .so and no QVM compilation: the
# game bytecode comes from id's pak files and is CPU independent.
# The 'set -e' at the top of this script would abort the instant make returned
# non-zero, BEFORE the MAKE_RC check below could tail the log to stderr. That is
# not theoretical: it made two aarch64 builds fail in total silence, printing
# only "[container] building ioq3ded" and exiting 2 with no reason given, and
# the real error (an unsupported-architecture #error) was sitting in
# /work/build.log the whole time. '|| MAKE_RC=\$?' keeps make out of set -e's
# reach so the diagnostics below actually run.
MAKE_RC=0
make BUILD_CLIENT=0 BUILD_SERVER=1 \\
     BUILD_GAME_SO=0 BUILD_GAME_QVM=0 BUILD_MISSIONPACK=0 \\
     BUILD_RENDERER_OPENGL2=0 \\
     -j"\$(nproc)" > /work/build.log 2>&1 || MAKE_RC=\$?

if [ "\$MAKE_RC" -ne 0 ]; then
	echo "[container] make failed:" >&2
	tail -40 /work/build.log >&2
	exit 1
fi

BIN=\$(find build -type f -name "ioq3ded*" | head -1)
if [ -z "\$BIN" ] || [ ! -f "\$BIN" ]; then
	echo "[container] make reported success but produced no ioq3ded" >&2
	tail -40 /work/build.log >&2
	exit 1
fi

strip "\$BIN" 2>/dev/null || true
mkdir -p /work/out
cp "\$BIN" /work/out/ioq3ded

echo "[container] verifying"
file /work/out/ioq3ded

# Assert the hardening actually landed, rather than assuming a flag that a
# Makefile could quietly have displaced.
readelf -sW /work/out/ioq3ded | grep -q "__stack_chk_fail" || {
	echo "[container] no stack canaries in the binary" >&2; exit 1; }
readelf -dW /work/out/ioq3ded | grep -q "BIND_NOW" || {
	echo "[container] RELRO is not full (no BIND_NOW)" >&2; exit 1; }
readelf -lW /work/out/ioq3ded | grep -q "GNU_STACK.*RWE" && {
	echo "[container] stack is executable" >&2; exit 1; }
echo "[container] hardening: canaries yes, full RELRO, NX, PIE"

# Everything loaded must be part of glibc. Anything else is a package the
# operator would have to install, which is what this build exists to avoid.
# The previous form of this check could not pass on any architecture. It piped
# grep -o through "tr -d '[:space:]'", which strips NEWLINES as well as spaces,
# so every library name was welded into one string:
#   linux-vdso.so.1libdl.so.2libm.so.6libc.so.6
# That blob then matched none of the allowed names and the build was refused
# with "depends on libraries outside glibc", naming libc and libm as the
# offenders. It also never allowed linux-vdso, which the kernel always injects.
# awk keeps one name per line and sed strips the directory, because the loader
# appears as an absolute path (/lib/ld-linux-aarch64.so.1).
ldd /work/out/ioq3ded > /work/ldd.txt 2>&1 || true
BAD=\$(awk '{print \$1}' /work/ldd.txt \\
	| sed 's|.*/||' \\
	| grep -E '\\.so' \\
	| grep -vE '^(linux-vdso|libc|libm|libdl|libpthread|librt|libgcc_s|ld-linux.*)\\.so' || true)
if [ -n "\$BAD" ]; then
	echo "[container] binary depends on libraries outside glibc:" >&2
	echo "\$BAD" >&2
	cat /work/ldd.txt >&2
	exit 1
fi

# It has to start. With no pak files it stops at the missing-data error, and
# reaching that proves the engine initialised.
useradd -m -u 1501 q3probe 2>/dev/null || true
mkdir -p /work/probe
chown -R q3probe /work/probe /work/out
su q3probe -c 'cd /work/probe && timeout 8 stdbuf -oL -eL /work/out/ioq3ded +set dedicated 1 +set fs_homepath /work/probe > /work/probe.log 2>&1' || true
if ! grep -qE "ioq3|Q3 [0-9]|FS_Startup" /work/probe.log; then
	echo "[container] the server did not start:" >&2
	cat /work/probe.log >&2
	exit 1
fi
echo "[container] startup probe reached engine init"
CONTAINER_SCRIPT
chmod +x "$WORK/build-in-container.sh"

echo "[server] compiling in container"
rm -rf "$WORK/out"
docker run --rm --platform "$DOCKER_PLATFORM" \
	-v "$WORK:/work" -w /work \
	"$IMAGE" /work/build-in-container.sh

[ -f "$WORK/out/ioq3ded" ] || { echo "$0: no ioq3ded was produced" >&2; exit 1; }

# ---------------------------------------------------------------------- package
STAGE="$WORK/pkg/quake3-server-$VERSION-linux-$ARCH"
rm -rf "$WORK/pkg"
mkdir -p "$STAGE/systemd"

# server.cfg goes in baseq3/, NOT beside the binary.
#
# The launch line says `+exec server.cfg`, and Quake III's exec searches the
# GAME directory, never the directory ioq3ded sits in. A copy left at the
# install root is silently never read: the server starts, binds its port, looks
# healthy, logs "couldn't exec server.cfg" once, and then runs on defaults with
# the default hostname, no passwords and none of the privacy settings in the
# shipped config. This tarball used to ship it at the root, which is exactly the
# location the README says does not work. Issue #14.
mkdir -p "$STAGE/baseq3"
cp "$REPO_ROOT/server/server.cfg"       "$STAGE/baseq3/server.cfg"

# fs_homepath, shipped as an empty directory on purpose.
#
# The unit sets ProtectSystem=strict and names this path in ReadWritePaths=.
# systemd cannot mount a read-write path that does not exist, so a clean install
# without it fails at 226/NAMESPACE before the engine ever runs, and restart
# loops. The unit also creates it defensively; shipping it means a hand install
# that never reads the unit still works. Issue #13.
mkdir -p "$STAGE/home/baseq3"

cp "$WORK/out/ioq3ded"                  "$STAGE/ioq3ded"
cp "$REPO_ROOT/server/README.md"        "$STAGE/README.md"
cp "$REPO_ROOT/server/ioq3ded.service"  "$STAGE/systemd/"
cp "$REPO_ROOT/COPYING.txt"             "$STAGE/COPYING.txt" 2>/dev/null || true

cat > "$STAGE/BUILD-INFO.txt" <<EOF
Quake III Arena dedicated server (old-mac-quake3)
=================================================
Version      : $VERSION
Built from   : git $GIT_COMMIT$GIT_DIRTY
Built on     : $BUILD_DATE
Target       : linux-$ARCH ($IOQ3_ARCH)
Built against: Debian 11, glibc 2.31

Runs on any Linux with glibc 2.31 or newer (Ubuntu 20.04 and up). The only
shared libraries it loads are part of glibc, so nothing needs installing.

There is no separate game library here. Quake III's game logic is QVM
bytecode inside id's pak files and is CPU independent, so the server runs the
same qagame.qvm the clients do.

Same source tree as the Mac fat binary release. No renderer is built in, so
this cannot be used as a client.

Project: https://github.com/matthewdeaves/old-mac-quake3
EOF

TARBALL="$OUT_DIR/quake3-server-$VERSION-linux-$ARCH.tar.gz"
rm -f "$TARBALL"
tar czf "$TARBALL" -C "$WORK/pkg" "$(basename "$STAGE")"
tar tzf "$TARBALL" >/dev/null || { echo "$0: tarball is unreadable" >&2; exit 1; }

echo
echo "[server] done"
echo "[server]   $TARBALL"
echo "[server]   $(du -h "$TARBALL" | cut -f1)  sha256 $(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
echo
tar tzf "$TARBALL" | sed 's/^/[server]   /'
