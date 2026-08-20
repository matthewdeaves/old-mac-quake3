# 12. The Linux dedicated server is one container-built ELF

Date: 2026-08-20
Status: accepted

## Context

The fleet plays over a LAN, but a dedicated server lets PowerPC Macs meet over
the internet. It is a separate release from the Mac app, built from the same
tree.

Unlike Quake II, nothing else has to be built. **Quake III's game logic ships as
QVM bytecode inside id's own pak files, and bytecode is CPU independent**, so the
server runs the same `qagame.qvm` the clients do. There is no per-architecture
game library to produce. `scripts/build.sh` sets `BUILD_SERVER=0` for the Mac
builds because the Mac release is a client; here the server is the only thing
turned on.

## Decision

**`scripts/build-server-linux.sh` builds one ELF in a Debian 11 container, so
the result depends on glibc 2.31 rather than on whatever the build machine
happens to have.**

- `--arch x86_64` (default) or `--arch aarch64` for an ARM VPS. Output:
  `dist/server/quake3-server-<version>-linux-<arch>.tar.gz`.
- Needs Docker or Colima and no local compiler.
- **Runtime requirement: any Linux with glibc 2.31 or newer** - Ubuntu 20.04 and
  up, Debian 11 and up. The only shared libraries loaded are part of glibc.
- The tarball carries `ioq3ded`, `server.cfg`, `systemd/ioq3ded.service` and
  `BUILD-INFO.txt`. **No game data** (ADR 0011).

**Network posture.** `dedicated 1`: a private internet server that accepts
connections from anywhere but sends no heartbeats, so it is listed in no public
browser. The five `sv_master` entries are blanked as well, so an accidental
`dedicated 2` still tells nobody. This is unlike Half-Life's `sv_lan 1`, which
actually refuses non-local addresses - `dedicated 1` restricts advertising only,
never who may connect. Default port is UDP 27960; the documented `ufw` rules are
**per source address**.

**Amplification, measured against this exact build:**

| Query | Sent | Received | Amplification |
|---|---|---|---|
| `getstatus` | 13 bytes | 418 bytes | **32x** |
| `getinfo` | 15 bytes | 184 bytes | 12x |

ioquake3 already carries a leaky bucket: `SVC_RateLimitAddress` allows 10
requests per second per address, and a global outbound bucket allows 10 per
100 ms. The upstream comment is blunt about the trade - "allow getstatus to be
DoSed relatively easily, but prevent excess outbound bandwidth usage when being
flooded inbound". So the factor is 32x but throughput is capped at roughly 100
replies a second, which makes it a poor reflector. For comparison the sister
servers measure 101x (Half-Life, no rate limit at all), 23x (Quake II, no rate
limit) and 3x (Quake 1).

**That is a mitigation, not a fix.** An address allowlist removes the problem
outright, because a spoofed packet claims to come from the victim rather than
from you and gets dropped.

**Hardening in the unit.** Seccomp `@system-service`, so anything outside the
allow-list returns EPERM rather than killing the process; memory and task limits
to bound a memory-exhaustion bug; downloads off (`sv_allowDownload 0`).
**`MemoryDenyWriteExecute` is deliberately NOT set**, unlike the other three
servers in this family: Quake III JITs its game bytecode (`vm_game` and
`vm_cgame` default to 2, `VMI_COMPILED`), so the engine writes memory and then
executes it, and denying W+X would make the server die the moment it loads
`qagame.qvm`. `+set vm_game 1` forces the slower interpreter and lets the flag
come back - a fine trade on a server with a handful of players.

**The console FIFO** is opened read-write on fd 3. A plain redirect would be no
good: the server sees EOF and stops reading the moment a writer closes, so
exactly one command would ever work.

## One diagnosed behaviour worth recording

**The first connection from an internet address may pause up to five seconds.**
Quake III sends non-LAN clients to id's authorize server to check their CD key,
and that server has been gone for years. The engine copes on its own - upstream
comment "we couldn't contact the auth server, let them in" - so the connection
completes once the lookup fails or `AUTHORIZE_TIMEOUT` (5000 ms,
`code/server/server.h:217`) expires. A pause on first connect, not a failure,
and it does not repeat. **There is no way to turn it off with official paks**:
`com_standalone` is `CVAR_ROM` and the engine sets it from the pak checksums, so
`+set com_standalone 1` on the command line does nothing.

## Tuned for the clients that will actually connect `sv_minPing` and
`sv_maxPing` are both 0, so nobody is refused for being on a slow link.
`sv_fps` stays at the default 20: raising it costs bandwidth and asks the client
for work, and these machines are fill-rate bound long before they are network
bound. `sv_pure 1` is safe here precisely because both ends install from the
same release and carry identical paks. Endianness needs nothing: the protocol
converts, and a little-endian server talking to big-endian PowerPC clients is
what the Mac builds already do on a LAN. There is no maplist cvar, so rotation
chains `vstr` configs, the standard Quake III idiom.

## Alternatives rejected

**Build on the host machine.** The binary's glibc floor would then depend on
whoever built it.

**Build a per-arch game library, as the Quake II port does.** Unnecessary: the
QVM is CPU independent.

**Rely on the built-in rate limit instead of an allowlist.** It caps throughput
but does not stop the server being used as a 32x reflector.

## Consequences

**Gained**

- One file to copy to a VPS, x86_64 or aarch64, with a documented systemd unit.

**Lost**

- `MemoryDenyWriteExecute` is off by default, so the JIT's W+X allocation stands
  unless the operator opts into the interpreter.

See `server/README.md` for the install, rcon, bots and connection instructions.
