# ioquake3 old-Mac port

Quake III Arena (ioquake3, last SDL 1.2 commit) as ONE fat binary for PowerPC, Intel and Apple Silicon Macs. Floors: G3 20 fps, every other class 25. A feature stays on while its class holds the floor; win fps by optimising code.

## Rules (each from a real mistake)
- old-mac-build-host owns builds and CI; never hardcode a mini. Release DMG only on a Tiger G4 (docs/adr/0005).
- Bench only with `scripts/safebench.sh`. Never KILL a fullscreen engine; native resolution only (docs/adr/0009, MISTAKES.md).
- Start games only through `scripts/launch-game.sh`, never a bare `nohup ... &` (#78).
- Check slices with `scripts/macho-archs.sh`, never `file` or workstation `lipo` (#57).
- rsync to `<host>:oldmac/quake3/src/`, never `oldmac/` itself (#50).
- Public repo: no addresses, keys, tunnel tokens or `.env` content from retro-server-infra.
- We ship code, not id assets. No em dashes. No Claude co-author line. Never rate or praise work.
- Record every negative result in docs/PROFILING.md.

## Where to look
- Build, deploy, bench commands: `.claude/rules/build-system.md`
- Slices, build facts and traps: `docs/BUILD-FACTS.md`
- Machines and hardware hazards: `.claude/rules/legacy-mac-hardware.md`
- Tickets, claims, cross-repo: `docs/TICKETING.md`, fleet POLICY
- Decisions and rejected options: `docs/adr/`
- Measured numbers: `docs/PROFILING.md`, `benchmarks/results.csv`
- Tuning knobs: `docs/KNOBS.md`; release steps: `docs/RELEASE.md`
- Past breakages: `MISTAKES.md`, `BUGFIXES.md`
- Every other doc: `docs/README.md`
