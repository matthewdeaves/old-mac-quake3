# scripts/ — ioquake3 old-Mac toolchain

Adapted from `~/quakespasm/scripts`. **Validated and in daily use** — the
build → deploy → bench → release pipeline produces running fat binaries on the
whole fleet and a verified DMG. `install-host-tools.sh` sets up remote reboot
recovery; `safebench.sh` is the safe ssh timedemo (single-session, self-quit).

## Host matrix (shared fleet)

| Machine | CPU | GPU | macOS | Slice | ssh alias |
|---|---|---|---|---|---|
| yosemite | G3 449 MHz | Rage 128 16 MB | Panther 10.3.9 | g3 (ppc750) | yosemite |
| sawtooth | G4 500 MHz | GeForce2 MX 32 MB | Tiger 10.4.11 | g4 (ppc7400) | sawtooth |
| quicksilver | G4 733 MHz | Radeon 9000 Pro 64 MB | Tiger 10.4.11 | g4 (ppc7400) | quicksilver |
| mini-g4 | G4 1.25 GHz | Radeon 9200 32 MB | Tiger 10.4.11 | g4 (ppc7400) | mini-g4 |
| mini-intel | Core 2 Duo 2.33 GHz | GMA 950 | Lion 10.7.5 | lion (x86_64) | mini-intel |
| imac-2019 | i5-9600K | Radeon Pro 580X 8 GB | Sequoia 15.7.5 | lion (x86_64) | imac-2019 |

`mini-intel` is also the cross-build host (rsync target `mini-intel:quake3/`).

## Pipeline

```
build.sh <g3|g4|lion>                    # one slice on mini-intel -> build/ioquake3-<t>
build-fat.sh                             # lipo all three -> build/ioquake3-fat
deploy.sh <machine>                      # ship fat binary + autoexec -> ~/Desktop/quake3/
bench.sh <machine> <demo> <WxH> [runs]   # one timedemo -> benchmarks/results.csv
parallel-bench.sh [--quick|--reset|--no-<machine> ...]   # concurrent matrix
bench-and-commit.sh "<phase>" [args...]  # clean-tree bench + commit
```

## bundle/

`autoexec-<machine>.cfg` — per-machine Quake III cvar defaults (resolution,
`r_picmip`, lighting, anisotropy …). `deploy.sh` ships the matching one to
`~/Desktop/quake3/baseq3/autoexec.cfg`. Tune these from bench evidence.

## Open items (resolve during kickoff)

1. **Game data distribution** — `baseq3/*.pk3` currently lives only on
   `mini-intel`. Copy it to each bench machine before benching there.
2. **Fat SDL 1.2 dylib** — adapt QuakeSpasm's `MacOSX/SDL.framework` /
   `lion:~/sdl-archive/`.
3. **Building 2013 ioquake3 vs the 10.3.9 SDK** — may need source tweaks; do
   the g4 (10.4u) slice first.
4. **.app bundle** (icon/Info.plist) — a later nicety; raw binary first.
