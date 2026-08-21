#!/usr/bin/env bash
# Build the Linux dedicated-server release from the same ioquake3 tree the Mac
# fat binary is built from.
#
# This is a SEPARATE release from the fat Mac app. It ships one ELF binary for
# one Linux architecture, built in a container so the result does not depend on
# whatever happens to be installed on the machine that ran it.
#
# usage: scripts/build-server-linux.sh [--arch x86_64|aarch64] [--version V]
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

while [ $# -gt 0 ]; do
	case "$1" in
		--arch)    ARCH="${2:?--arch needs a value}"; shift 2 ;;
		--version) VERSION="${2:?--version needs a value}"; shift 2 ;;
		-h|--help) sed -n '2,15p' "$0"; exit 0 ;;
		*) echo "$0: unknown argument: $1" >&2; exit 2 ;;
	esac
done

case "$ARCH" in
	x86_64)  DOCKER_PLATFORM="linux/amd64"; IOQ3_ARCH="x86_64" ;;
	aarch64) DOCKER_PLATFORM="linux/arm64"; IOQ3_ARCH="aarch64" ;;
	*) echo "$0: unsupported arch: $ARCH (expected x86_64 or aarch64)" >&2; exit 2 ;;
esac

if [ -z "$VERSION" ]; then
	VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo unknown)"
fi
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY=""
git diff --quiet 2>/dev/null || GIT_DIRTY=" (working tree modified)"
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
# grep -o through `tr -d '[:space:]'`, which strips NEWLINES as well as spaces,
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

cp "$WORK/out/ioq3ded"                  "$STAGE/ioq3ded"
cp "$REPO_ROOT/server/server.cfg"       "$STAGE/server.cfg"
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
