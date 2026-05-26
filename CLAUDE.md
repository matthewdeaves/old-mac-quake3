# ioquake3 old-Mac port — guidance for Claude

Sister project to the **QuakeSpasm PPC port** (`~/quakespasm`) and the
**Quake II port** (`~/quake2`). Shares the same 6-machine bench fleet, the
`mini-intel` cross-build host, and the same tooling philosophy. The
QuakeSpasm project is the mature template — when a tooling question isn't
answered here, look at how `~/quakespasm` does it.

> **STATUS: build pipeline VALIDATED end-to-end (2026-05-26). The fat binary
> (ppc750 + ppc7400 + x86_64) builds and runs on real hardware — G3 (Panther),
> G4 (Tiger), and Lion — and a v0 baseline is in `benchmarks/results.csv`.
> Two SDL/Panther fixes were required to make the PPC slices run (see
> `MISTAKES.md`). Remaining: per-machine tuning (autoexec) from bench evidence,
> and an `.app` bundle + icon. The `scripts/` are no longer v0 drafts.**

## Goal in one line

Best-looking **ioquake3 (Quake III Arena)** for G3 Panther + G4 Tiger + Lion
Intel, staying playable on each. Framerate targets: **≥ 60 fps on G4 / Lion,
≥ 20 fps on G3**. The G3 floor was feared aspirational — **now PROVEN by the v0
baseline**: yosemite (G3 449 MHz, Rage 128) does `four` at **27 fps @ 1024×768
and 45 fps @ 640×480 with default settings** (no tuning), clearing the floor.
G4 (quicksilver, Radeon 9000) ~60 fps (vsync-capped — real headroom hidden),
Lion (GMA 950) 105/238 fps. imac-2019 (Sequoia / Radeon Pro 580X) is a modern
bench reference that separates CPU-bound from GPU-bound effects.

## THE load-bearing constraint: SDL 1.2, NOT SDL 2

Modern ioquake3 (upstream `HEAD`) uses **CMake + SDL2**, and its PPC build
path targets the **10.5 SDK** — `make-macosx.sh` says verbatim *"For PPC
macs, G4's or better are required to run ioquake3."* **SDL2 never supported
macOS 10.3 or 10.4.** Our PPC fleet runs **Panther 10.3.9** (yosemite) and
**Tiger 10.4.11** (the three G4s) — none run Leopard 10.5. So a modern
ioquake3 binary cannot run on a single one of our PPC Macs.

Therefore the code baseline is pinned to the **last SDL 1.2 commit**:

- branch **`oldmac-base`** @ **`4432a80a`** (2013-01-17 "Add vim stuff to
  .gitignore"), the commit immediately before `f478761e "Use SDL 2 instead
  of SDL 1.2"`. Its Makefile uses `sdl-config` and links
  `code/libs/macosx/libSDL-1.2.0.dylib` — the same SDL 1.2.x world
  QuakeSpasm lives in, so the QuakeSpasm cross-build recipe transfers.
- `main` tracks upstream HEAD (SDL2/CMake) **for reference only** — never
  build the PPC fleet from it.
- **Fallback** if `4432a80a` won't compile against the 10.3.9 SDK: the 1.36
  release era (`b003422d`, 2011-05) — older but the same SDL 1.2 line, and
  the version actually installed on the mini.

This is exactly the kind of "modern is better" assumption that breaks on old
hardware — see `MISTAKES.md`.

## Host matrix (shared with QuakeSpasm / Quake II)

| Machine | CPU | GPU | macOS | Build slice | ssh alias |
|---|---|---|---|---|---|
| yosemite | G3 449 MHz | Rage 128 16 MB | Panther 10.3.9 | g3 (ppc750) | yosemite |
| sawtooth | G4 500 MHz | GeForce2 MX 32 MB | Tiger 10.4.11 | g4 (ppc7400) | sawtooth |
| quicksilver | G4 733 MHz | Radeon 9000 Pro 64 MB | Tiger 10.4.11 | g4 (ppc7400) | quicksilver |
| mini-g4 | G4 1.25 GHz | Radeon 9200 32 MB | Tiger 10.4.11 | g4 (ppc7400) | mini-g4 |
| mini-intel | Core 2 Duo 2.33 GHz | GMA 950 | Lion 10.7.5 | lion (x86_64) | mini-intel |
| imac-2019 | i5-9600K | Radeon Pro 580X 8 GB | Sequoia 15.7.5 | lion (x86_64) | imac-2019 |

Build TARGET names (`g3`/`g4`/`lion`) = chip family + SDK, NOT machines. One
`g4` (ppc7400) binary serves sawtooth/quicksilver/mini-g4; one `lion`
(x86_64) binary serves mini-intel/imac-2019. The deployed artifact is a
single **fat binary** (`ppc750` + `ppc7400` + `x86_64`) — dyld picks the
slice at runtime. Multi-subtype ppc lipo (ppc750 + ppc7400 in one Mach-O)
is proven to work by QuakeSpasm.

## Build path (ioquake3 ≠ QuakeSpasm)

QuakeSpasm uses `Quake/Makefile.darwin`; **ioquake3 uses its own top-level
`Makefile`** driven by env vars. Per slice, on `mini-intel`, roughly:

```
PLATFORM=darwin ARCH=<ppc|x86_64> CC=<gcc-4.0|clang> \
  MACOSX_VERSION_MIN=<10.3|10.4|10.7> \
  CFLAGS="-isysroot <SDK> -arch <ppc|x86_64> <-mcpu/-maltivec/-O3>" \
  make
```

- **g3:** `ARCH=ppc CC=gcc-4.0`, SDK `MacOSX10.3.9.sdk`, `-arch ppc750 -mcpu=750 -mmacosx-version-min=10.3 -O3` (NO AltiVec — a 750 has no vector unit)
- **g4:** `ARCH=ppc CC=gcc-4.0`, SDK `MacOSX10.4u.sdk`, `-arch ppc7400 -mcpu=7400 -faltivec -mtune=7450 -mmacosx-version-min=10.4 -O3`
- **lion:** `ARCH=x86_64 CC=clang`, min 10.7, `-O3`
- All slices build `USE_RENDERER_DLOPEN=0` (monolithic, opengl1 linked in; no
  renderer dylib; skips rend2). The Makefile's hardcoded ppc `-arch ppc -faltivec`
  was removed — `scripts/build.sh` supplies arch/AltiVec/version-min per target.

Output lands in `build/release-darwin-<arch>/ioquake3.<arch>`. Both PPC slices
are `ARCH=ppc`, so they collide on the same filename — `build.sh` renames to
`ioquake3-g3` / `ioquake3-g4` and **re-stamps the Mach-O cpusubtype** (ppc750=9,
ppc7400=10) post-link, because the generic bundled `libSDLmain`/crt make Apple
ld stamp subtype 0; otherwise the two slices collide in lipo. `CLIENTBIN=ioquake3`,
`BASEGAME=baseq3`.

**Build items — ALL RESOLVED (2026-05-26):**
1. ✅ **SDL 1.2.** The bundled fat `libSDL-1.2.0.dylib` AND prebuilt `libSDLmain.a`
   were 10.4+ builds that SIGSEGV on Panther (objc_msgSend via `bla 0xfffeff00`,
   unmapped on 10.3.9). Fix: compile `code/libs/macosx/SDLMain.m` from source
   (Makefile rule), and swap in QuakeSpasm's Panther-safe SDL 1.2.15. See `MISTAKES.md`.
2. ✅ **Builds against 10.3.9 SDK / gcc-4.0** — no source tweaks needed beyond
   the SDL fix; g3/g4/lion all compile.
3. ✅ **Raw binary proven** on all three arches. `.app` bundle + icon is the
   remaining nicety (one fat-binary `.app` for all machines).
4. ✅ **Game logic** = QVMs inside `baseq3/pak8.pk3`; no game dylibs built.

## Game data + per-machine config

- **baseq3 is already staged** at `mini-intel:~/Desktop/quake3/baseq3/`
  (9 pk3s: `PAK0.PK3` + `pak1-8.pk3`, copied read-only from the installed
  ioquake3 1.36 at `/Users/mini/Games/ioquake3/`). **Never modify the
  install.** All stock maps + demos live inside the pk3s.
- Q3 config: cvars in `autoexec.cfg` (read from `fs_homepath`/`baseq3`).
  Per-machine defaults = per-machine `autoexec-<machine>.cfg` (analogous to
  QuakeSpasm's per-machine autoexec). Relevant Q3 visual/perf knobs:
  `r_picmip`, `r_mode`/`r_customwidth`/`r_customheight`, `r_texturebits`,
  `r_colorbits`, `r_vertexlight`, `r_subdivisions`, `r_lodbias`,
  `r_ext_texture_filter_anisotropic`, `r_ext_compressed_textures`,
  `cg_drawfps`, `com_maxfps`. Inventory them in `docs/KNOBS.md` as added.

## Benchmark discipline

Q3 uses `timedemo`, not Quake's: launch with `+set timedemo 1 +demo <name>`.
Demo names must be enumerated from the staged pk3s (point-release `.dm_68`
demos live in `pak8.pk3`) — the new session lists them and picks a canonical
2–3. Otherwise the QuakeSpasm rules carry over: **3 runs, median of 2 & 3**,
append to `benchmarks/results.csv` (rolling history, never wipe mid-round),
raw logs in `benchmarks/raw/`, two commits per phase (code, then bench),
tag rows with `(commit, machine, demo, res)`.

## Multi-tenancy on mini-intel (now THREE projects)

`mini-intel` cross-builds QuakeSpasm, Quake II, **and** this. Isolation:

| Resource | QuakeSpasm | Quake II | **Quake III** |
|---|---|---|---|
| rsync target | `mini-intel:quakespasm/` | `mini-intel:quake2/` | **`mini-intel:quake3/`** |
| local flock | `~/quakespasm/build/.build.lock` | `~/quake2/build/.build.lock` | **`~/quake3/build/.build.lock`** |
| local outputs | `~/quakespasm/build/quakespasm-*` | `~/quake2/build/q2-*` | **`~/quake3/build/ioquake3-*`** |

Shared read-only: `/Developer/SDKs/{MacOSX10.3.9.sdk,MacOSX10.4u.sdk}`,
`/usr/bin/{gcc-4.0,clang}`. **Never modify** — recovery is multi-hour. Never
let `build.sh` rsync to `mini-intel:~/` or another project's dir.

## Operational gotchas (inherited from the fleet — all still apply)

- **Don't run g3 + g4 builds in parallel** from one shell → `.o` races stamp
  the wrong CPU subtype. `build.sh` flocks; serialize if you bypass. After a
  build, sanity-check `file build/ioquake3-g3` says `ppc750`, `-g4` says
  `ppc7400`.
- **Panther `/bin/sleep` is integer-only** — `sleep 0.2` returns instantly.
  Poll loops on yosemite use `sleep 1`.
- **Killing the engine:** `killall -TERM` grace then `killall -KILL`. SIGTERM
  lets SDL restore the display (Rage 128 LUT corruption risk on hard kill).
  **Never `pkill`** (absent on Tiger/Panther).
- **Old-Mac SSH needs legacy crypto** — `~/.ssh/config` already has the
  `+ssh-rsa` / pre-2014 KEX entries and `id_rsa_tiger`.
- **`mini-intel` sleeps aggressively** — "No route to host" = asleep; wake
  and retry.
- **`ssh <host> '~/bin/qsreboot.sh'`** reboots a wedged Mac (one-time
  `qsreboot-setup.sh` per machine).

## Tooling

Adapted from QuakeSpasm; see `scripts/README.md` (host matrix, contracts) and
`scripts/CLAUDE.md` (gotchas). `build.sh <g3|g4|lion>` → `build-fat.sh` →
`deploy.sh <machine>` → `bench.sh` / `parallel-bench.sh` / `bench-and-commit.sh`.
**These are unvalidated drafts until the build pipeline is proven.**
