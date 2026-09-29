# ioquake3 old-Mac port

Quake III Arena on ioquake3's last SDL 1.2 commit, as one fat binary for PowerPC, Intel and Apple Silicon Macs.

## Traps
- Package release DMGs on a Tiger G4 (see docs/BUILD-FACTS.md).
- Bench through `scripts/safebench.sh`, at native resolution; never KILL a fullscreen engine (see docs/HARDWARE.md).
- Launch through `scripts/launch-game.sh`; see docs/BUILD-FACTS.md, #78.
- Inspect slices with `scripts/macho-archs.sh`, never `file` or workstation `lipo` (see docs/BUILD-FACTS.md, #57).
- rsync to `<host>:oldmac/quake3/src/`, never `oldmac/` (see docs/SCRIPT-CONTRACTS.md, #50).
- old-mac-build-host owns builds and CI; never hardcode a mini.
- Public repo: no addresses, keys, tunnel tokens or `.env` content from retro-server-infra.
- We ship code, not id assets. No em dashes. No Claude co-author line. Never rate or praise work.
- Record negative performance results in `docs/PROFILING.md` so failed experiments stay findable.

## Where to look
- Docs → `docs/README.md`
- Build → `docs/BUILD-COMMANDS.md`
- Deploy → `docs/BUILD-COMMANDS.md`
- Smoke → `docs/BUILD-COMMANDS.md`
- Bench → `docs/BENCH-COMMANDS.md`
- Tests → `docs/TESTS.md`
- Release → `docs/RELEASE.md`
- Tickets → `docs/TICKETING.md`
- History → `BUGFIXES.md`, `MISTAKES.md`, `docs/archive/`
- VM → `docs/VM-TIGER.md`
