<div align="center">

<img src="docs/images/ioquake3-icon-256.png" width="160" alt="ioquake3 old-Mac port icon">

# ioquake3 — old-Mac port

**Quake III Arena that actually runs on PowerPC Macs again** — Panther on a
G3, Tiger on a G4, and Lion on Intel — all from a *single fat binary*.

</div>

---

> ⚠️ **Status: early work in progress.** This repo so far is about *getting a
> working build going* — a fat binary that compiles, launches and renders across
> the fleet, plus a first benchmark baseline. **Per-machine optimisation and
> visual tuning have not started yet.** The numbers below are stock-settings
> baselines (not tuned), and only three of the six machines have been benched.
> Expect this to change a lot.

This is a port of [ioquake3](https://ioquake3.org/) tuned for vintage Apple
hardware. One Mach-O bundle (`ppc750` + `ppc7400` + `x86_64`) drops onto every
machine in the fleet and `dyld` picks the right slice at runtime. The headline:
**Quake III rendering on a 449 MHz iMac G3 with a 16 MB Rage 128**, the machine
that was at the *minimum spec* edge when Q3 shipped in 1999.

<div align="center">

| G3 · Panther · Rage 128 | G4 · Tiger · Radeon 9000 |
|:---:|:---:|
| ![Quake III on a G3](docs/images/screenshot-g3-yosemite.png) | ![Quake III on a G4](docs/images/screenshot-g4-quicksilver.png) |

| G5 · Leopard · Radeon 9600 — native 1440×900 | Intel mini · Lion · GMA 950 — 1024×768 |
|:---:|:---:|
| ![Quake III on a G5](docs/screenshots/q3-imac-g5-03.jpg) | ![Quake III on an Intel Mac mini](docs/screenshots/q3-mini-intel-04.jpg) |

</div>

## Framerate (v0 baseline)

`four` timedemo, fullscreen, **default settings** (no per-machine tuning),
median of runs 2 & 3:

| Machine | CPU | GPU | OS | 640×480 | 1024×768 |
|---|---|---|---|--:|--:|
| yosemite | G3 449 MHz | Rage 128 16 MB | Panther 10.3.9 | **45** | **27** |
| quicksilver | G4 733 MHz | Radeon 9000 64 MB | Tiger 10.4.11 | 61 | 60 |
| imac-g5 | G5 2.0 GHz | Radeon 9600 128 MB | Leopard 10.5.8 | — | 133 |
| mini-intel | Core 2 Duo 2.33 GHz | GMA 950 | Lion 10.7.5 | 238 | 105 |

The **≥ 20 fps G3 floor and ≥ 60 fps G4 target are both met at stock settings.**
The G4's flat ~60 in the table is the display's vsync cap, not a ceiling.

Each machine now ships a per-machine config at its **native panel resolution**
(favouring resolution + effects over raw fps). Confirmed native-res `four`
timedemo fps (2026-07-05):

| Machine | Native res | fps | Config |
|---|---|--:|---|
| yosemite (G3) | 800×600 | **22** | lightmaps + shaders + dlights + flares |
| quicksilver (G4) | 1680×1050 | **42** | picmip 1, effects, 16× aniso + trilinear, native modules |
| mini-intel (Lion) | 1920×1080 | **57** | picmip 1, vsync on (no tearing) |
| imac-g5 | 1440×900 | **60** | MAXED — picmip 0, aniso 8×, trilinear, 2× FSAA |

(sawtooth, mini-g4 and imac-2019 not yet benched at native res.)

## Features

- **One fat binary, whole fleet.** `ppc750` (G3, no AltiVec), `ppc7400`
  (G4, AltiVec) and `x86_64` (Intel) slices in a single Mach-O.
- **Native game modules.** The `cgame`/`qagame`/`ui` game code ships as fat
  native dylibs bundled in the `.app` (also `ppc750`+`ppc7400`+`x86_64`), loaded
  in place of the stock `pak8.pk3` bytecode. Stock ioquake3 already JIT-compiles
  that bytecode to native PowerPC, so this is a modest, free win (a real
  compiler's codegen + no VM sandbox-masking) — **bench-measured +1.3% on the
  Radeon-9000 G4**, zero visual cost. It self-selects per machine and falls back
  to the bytecode automatically if a dylib is missing or on a pure server.
- **Runs on Mac OS X 10.3.9 → 10.7** (and modern macOS via the x86_64 slice).
- **SDL 1.2**, the last SDL line that supports Panther and Tiger.
- **Monolithic OpenGL1 renderer** — no `dlopen`, no GL2/GLSL renderer (useless
  on a Rage 128 / GeForce 2 anyway).
- **`ioquake3.app` bundle with a custom icon** that renders correctly all the
  way from Panther's Finder to modern macOS (legacy-only `.icns`).
- **Cross-build toolchain** producing all three slices from one Lion host.
- **Apple Watch "tactical computer" companion** (`watchlink`) — your live
  health / armor / ammo / weapon / score / powerups stream to an iPhone + Apple
  Watch app over Bonjour (UDP 27999), the same companion that drives the Quake 1
  and Quake 2 ports. Off by default; enable with `seta watch_host "auto"`.

## Why a special port? (the load-bearing constraint)

Modern ioquake3 is **CMake + SDL2**, and SDL2 has *never* supported macOS 10.3
or 10.4. The PowerPC fleet here runs **Panther 10.3.9** and **Tiger 10.4.11** —
so a current ioquake3 binary won't launch on a single one of them. This port is
therefore pinned to the **last SDL 1.2 commit** of ioquake3 (this repo's
`master` branch is rooted there), the same SDL 1.2 world that still talks to a
Rage 128 under Panther.

Two booby-traps had to be defused to get the PPC slices running (both in
[`MISTAKES.md`](MISTAKES.md)): the bundled `libSDLmain.a` and `libSDL-1.2.0.dylib`
were 10.4+ builds that dispatch `objc_msgSend` through a fixed address unmapped
on 10.3.9 (instant SIGSEGV in the Cocoa bootstrap) — fixed by compiling SDLMain
from source and swapping in a Panther-safe SDL 1.2.

## What this port actually changes in the engine

In the interest of honesty about scope: **most of this port is tooling, config
and packaging, not engine surgery.** All the per-machine graphics/fps tuning
(FSAA, anisotropic + trilinear filtering, texture/colour depth, sound mix rate,
resolution, and the native-game-module switch above) is driven entirely by
**cvars in the bundled `autoexec-*.cfg` files** — no renderer or game-logic
algorithm was rewritten to get those wins. The measured C changes vs the pinned
SDL 1.2 baseline are:

- **`code/qcommon/common.c`** — the per-machine auto-config mechanism
  (`Com_AutoConfigForMachine` / `Com_ExecConfigFromBundle`): read `hw.model` at
  startup and exec the matching arch + machine config baked into the `.app`.
- **`code/libs/macosx/SDLMain.m`** (compiled from source) — the Panther
  `objc_msgSend` SIGSEGV fix described above.
- **`code/client/cl_watchlink.c`** plus small hooks in `cl_main.c` / `cl_parse.c`
  / `client.h` — the optional Apple Watch companion (`watchlink`), off by default.
- **`Makefile`** — per-slice arch / AltiVec / version-min plumbing for the
  cross-build.

The native game modules are built from the **stock, unmodified** `cgame`/`game`/
`ui` source — the win is from compiling them natively, not from changing the game.

## Build & deploy

The toolchain (`scripts/`) cross-builds on a Lion host and deploys to the fleet:

```sh
scripts/build-fat.sh                 # build all 3 slices -> build/ioquake3-fat
scripts/build-gamedylibs.sh          # native cgame/qagame/ui dylibs -> build/gamedylibs
scripts/make-app.sh                  # wrap it in build/ioquake3.app (+ icon + dylibs)
scripts/deploy.sh <machine>          # ship the .app + raw binary + config
scripts/bench.sh <machine> four 1024x768   # one timedemo -> benchmarks/results.csv

# release packaging (mirrors the Quake 1/2 ports)
scripts/make-dmg.sh [version]        # verified .dmg (built on a Tiger host) -> dist/
scripts/deploy-dmg.sh <machine>      # install from the .dmg, byte-for-byte verified
scripts/smoke-dmg.sh <machine>       # launch the install (production config) + timedemo
scripts/screenshot.sh <machine>      # capture in-game shots -> docs/screenshots/
```

Per-slice flags, the cpusubtype re-stamp, and the SDL story are documented in
[`CLAUDE.md`](CLAUDE.md) and [`scripts/README.md`](scripts/README.md). The icon
pipeline (`scripts/make-icon.py`) turns a source PNG into a Panther→Sequoia
`.icns`.

## Host matrix

| Machine | CPU | GPU | macOS | Slice |
|---|---|---|---|---|
| yosemite | G3 449 MHz | Rage 128 16 MB | Panther 10.3.9 | ppc750 |
| sawtooth | G4 500 MHz | GeForce2 MX 32 MB | Tiger 10.4.11 | ppc7400 |
| quicksilver | G4 733 MHz | Radeon 9000 Pro 64 MB | Tiger 10.4.11 | ppc7400 |
| mini-g4 | G4 1.25 GHz | Radeon 9200 32 MB | Tiger 10.4.11 | ppc7400 |
| imac-g5 | G5 2.0 GHz | Radeon 9600 128 MB | Leopard 10.5.8 | ppc7400 |
| mini-intel | Core 2 Duo 2.33 GHz | GMA 950 | Lion 10.7.5 | x86_64 |
| imac-2019 | i5-9600K | Radeon Pro 580X 8 GB | Sequoia 15.7 | x86_64 |

(The G5 has no dedicated `ppc970` slice — it runs the `ppc7400` slice. It's
benched at its **native** 1440×900 panel resolution.)

## Sister projects

Same six-machine fleet, same cross-build-on-Lion tooling philosophy, older
id engines:

- **[old-mac-quakespasm](https://github.com/matthewdeaves/old-mac-quakespasm)** — Quake (QuakeSpasm) for PowerPC Macs. The mature template this port borrows from.
- **[old-mac-quake2](https://github.com/matthewdeaves/old-mac-quake2)** — Quake II for PowerPC Macs.

## Credits & licence

Built on [ioquake3](https://github.com/ioquake/ioq3) and id Software's Quake III
Arena engine. Released under the **GPLv2** (see [`COPYING.txt`](COPYING.txt)).
Game data (`baseq3` pk3s) is **not** included — you need a copy of Quake III
Arena. This port adds the old-Mac build/deploy tooling and the SDL 1.2 / Panther
fixes; the upstream engine readme is preserved in [`README`](README).
