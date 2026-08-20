<div align="center">

<img src="docs/images/ioquake3-icon-256.png" width="150" alt="ioquake3 old-Mac port icon">

# ioquake3: old-Mac port

**Quake III Arena running again on vintage Macs**, Panther on a G3, Tiger on a
G4, Lion on Intel, all from a single fat binary.

</div>

A port of [ioquake3](https://ioquake3.org/) built as one fat PowerPC + Intel
binary, tested on a range of old Macs. One Mach-O bundle (`ppc750` + `ppc7400` +
`x86_64`) drops onto every machine and `dyld` picks the right slice at runtime,
down to a 449 MHz iMac G3 with a 16 MB Rage 128, right at the minimum spec when
Q3 shipped in 1999.

> **About this project.** A personal project, I love Quake and I collect and
> tinker with old Macs. My part is the setup and testing: the build, deploy and
> benchmark scripts, and the per-machine settings. The engine and config changes
> were made mostly **with AI (Claude), which I directed and checked against real
> benchmarks on the machines**, most of the work here is tooling and config, not
> changes to the engine itself.

<div align="center">

| G3 · Panther · Rage 128 | G4 · Tiger · Radeon 9000 |
|:---:|:---:|
| ![Quake III on a G3](docs/images/screenshot-g3-yosemite.png) | ![Quake III on a G4](docs/images/screenshot-g4-quicksilver.png) |

| G5 · Leopard · Radeon 9600 | Intel mini · Lion · GMA 950 |
|:---:|:---:|
| ![Quake III on a G5](docs/screenshots/q3-imac-g5-03.jpg) | ![Quake III on an Intel Mac mini](docs/screenshots/q3-mini-intel-04.jpg) |

</div>

## Tested machines

| Machine | CPU | GPU | macOS | Slice |
|---|---|---|---|---|
| yosemite | G3 449 MHz | Rage 128 16 MB | Panther 10.3.9 | ppc750 |
| sawtooth | G4 500 MHz | GeForce2 MX 32 MB | Tiger 10.4.11 | ppc7400 |
| quicksilver | G4 733 MHz | Radeon 9000 Pro 64 MB | Tiger 10.4.11 | ppc7400 |
| mini-g4 | G4 1.25 GHz | Radeon 9200 32 MB | Tiger 10.4.11 | ppc7400 |
| imac-g5 | G5 2.0 GHz | Radeon 9600 128 MB | Leopard 10.5.8 | ppc7400 |
| mini-intel | Core 2 Duo 2.33 GHz | GMA 950 | Lion 10.7.5 | x86_64 |
| imac-2019 | i5-9600K | Radeon Pro 580X 8 GB | Sequoia 15.7 | x86_64 |

### Which OS each CPU needs

Three slices cover four CPU families, the G5 runs the same `ppc7400` slice as the G4s.
Each is built against the **oldest** OS its CPU family can run, not the OS the machines
here happen to run:

| CPU | Slice | OS needed | Tested on |
|---|---|---|---|
| G3 (750) | `ppc750` | 10.3.9 Panther or later | 10.3.9 |
| G4 (7400 / 7450 / 7447A) | `ppc7400` | 10.3.9 Panther or later | 10.4.11 |
| G5 (970) | `ppc7400` | 10.3.9 Panther or later | 10.5.8 |
| Intel, 64-bit | `x86_64` | 10.6 Snow Leopard or later | 10.7.5 and 15.7 |

`dyld` picks a slice by **CPU subtype alone**, the OS plays no part. A Mac running an
OS older than its slice was built for gets that slice anyway rather than falling back to
a lower one, and won't launch. That is why the `ppc7400` slice is built at 10.3 even
though no G4 or G5 here runs Panther: a G4 on Panther is a normal machine to own, and
building the slice any higher would leave it dead with no way to force a different one.
Doing it costs nothing on Tiger, see the before/after numbers below.

The right-hand column is the honest part: **a G4 on Panther, and a G5 on Panther or
Tiger, should work but have not been run on hardware**, there's no such machine here.
Same for an Intel Mac on Snow Leopard.

32-bit-only Intel Macs (Core Duo / Core Solo, 2006) have no slice at all: there is no
`i386` build, and no such machine here to make one on.

### What lowering the floor cost

Nothing measurable. Same source, same commit, `four` timedemo, three runs, median of
2 & 3, the old `ppc7400` slice (10.4u SDK) against the new one (10.3.9 SDK):

| Machine | Before | After |
|---|---:|---:|
| Quicksilver (G4 / Radeon 9000) 1680×1050 | 41.65 | 41.40 |
| Mac mini G4 (Radeon 9200) 1680×1050 | 27.55–30.00 † | 27.60 |
| Mac mini Intel (Lion / GMA 950) 1920×1080 | 41.20 | 42.00 |

† The mini G4's "before" is a range, not a figure: four passes at the same commit
recorded 27.55, 27.90, 27.90 and 30.00. The new result sits inside that spread, so
it's a weaker comparison than the other two rows, worth stating rather than quoting
whichever end flattered the result.

Run-to-run spread within a single pass is about ±0.3 fps, so quicksilver and the Intel
mini are ties. The G4 slice also disassembles to **exactly the same 165 AltiVec
instructions** before and after: AltiVec codegen follows `-arch`/`-mcpu`, not the SDK.

These are *bench-harness* numbers, the per-machine auto-config is switched off
(`+set com_archAutoexec 0`) so the engine runs defaults plus the resolution, which is
what makes them comparable across commits. They are **not** the framerates you get
playing, which are below.

## Framerate

Each machine runs a per-machine config at its native panel resolution. The
`four` timedemo runs from ~22 fps on the 449 MHz G3 (800×600) up to ~60 on the
G5 (1440×900); tuning is ongoing, and live numbers are in
[`benchmarks/results.csv`](benchmarks/results.csv).

**G3 performance is still being worked on, on both Panther and Tiger.** The
449 MHz G3 with a 16 MB Rage 128 is the machine this port has to fight hardest
for, and it is the one with the least settled configuration. It plays on both
10.3.9 and 10.4.11, that much is confirmed on hardware for v0.5.0, but the
`ppc750` profile is deliberately cautious (800×600, `r_picmip 1`, 16-bit colour
and depth, cheap sky) and has not been re-measured on either OS since. Two open
questions: whether that baseline is leaving framerate on the table, and whether
Panther and Tiger actually differ on this hardware. Treat the ~22 fps figure as
the last known good number rather than a current one.

## Features

- **One fat binary for every machine**, `ppc750` (G3), `ppc7400` (G4 AltiVec)
  and `x86_64` (Intel) slices in a single Mach-O.
- Runs on **Mac OS X 10.3.9 Panther through Lion** on PowerPC and early Intel, and
  on modern macOS via the Intel slice.
- **SDL 1.2**, the last SDL line that supports Panther and Tiger, with a
  monolithic OpenGL1 renderer.
- **Per-machine auto-config**, reads `hw.model` at boot and applies a tuned
  `autoexec` baked into the `.app` (resolution, FSAA, anisotropic + trilinear
  filtering, texture/colour depth).
- **Native game modules**, `cgame`/`qagame`/`ui` ship as fat native dylibs
  built from stock source, replacing the bundled bytecode; a small measured win,
  with automatic fallback to the bytecode.
- Self-contained **`ioquake3.app`** with a custom icon that renders correctly
  from Panther's Finder to modern macOS.
- Optional **Apple Watch "tactical computer" companion** (`watchlink`), off by
  default; enable with `seta watch_host "auto"`.

## Get the latest release

Download the latest disk image from
[**Releases**](https://github.com/matthewdeaves/old-mac-quake3/releases/latest)
(`ioquake3-OldMac-<version>.dmg`), one image runs on Panther, Tiger, Lion and
modern macOS.

Game data (`baseq3` `.pk3` files) is **not** included, you need your own copy
of Quake III Arena. Drop `ioquake3.app` and your `baseq3/` folder next to each
other and launch. On modern macOS, clear Gatekeeper with
`xattr -dr com.apple.quarantine ioquake3.app` (not needed on Panther/Tiger/Lion).

## Sister projects

Same machines, same tooling, older id engines:
[**old-mac-quakespasm**](https://github.com/matthewdeaves/old-mac-quakespasm)
(Quake) and [**old-mac-quake2**](https://github.com/matthewdeaves/old-mac-quake2)
(Quake II).

## Credits & licence

Built on [ioquake3](https://github.com/ioquake/ioq3) and id Software's Quake III
Arena engine. Released under the **GPLv2** (see [`COPYING.txt`](COPYING.txt)).
This port adds the old-Mac build/deploy tooling and the SDL 1.2 / Panther fixes;
the upstream engine readme is preserved in [`README`](README).
