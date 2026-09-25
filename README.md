<div align="center">

<img src="docs/images/ioquake3-icon-256.png" width="150" alt="ioquake3 old-Mac port icon">

# ioquake3: old-Mac port

Quake III Arena (ioquake3) for Mac OS X 10.3.9 through current macOS: one fat
binary for PowerPC G3/G4/G5, Intel and Apple Silicon.

</div>

A port of [ioquake3](https://ioquake3.org/). One Mach-O carries five slices
(`ppc750`, `ppc7400`, `i386`, `x86_64`, `arm64`) and `dyld` picks one at launch,
from a 449 MHz Power Mac G3 with a 16 MB Rage 128 to Apple Silicon (native, not
Rosetta).

<div align="center">

| G3 · Panther · Rage 128 | G4 · Tiger · Radeon 9000 |
|:---:|:---:|
| ![Quake III on a G3](docs/images/screenshot-g3-yosemite.png) | ![Quake III on a G4](docs/images/screenshot-g4-quicksilver.png) |

| G5 · Leopard · Radeon 9600 | Intel mini · Lion · GMA 950 |
|:---:|:---:|
| ![Quake III on a G5](docs/screenshots/q3-imac-g5-03.jpg) | ![Quake III on an Intel Mac mini](docs/screenshots/q3-mini-intel-04.jpg) |

</div>

## Tested machines

| Machine | CPU | GPU | Mac OS X / macOS | Slice |
|---|---|---|---|---|
| yosemite | G3 449 MHz | Rage 128 16 MB | 10.3.9 and 10.4.11 | ppc750 |
| sawtooth | G4 500 MHz | GeForce2 MX 32 MB | 10.4.11 | ppc7400 |
| quicksilver | G4 733 MHz | Radeon 9000 Pro 64 MB | 10.4.11 | ppc7400 |
| mini-g4 | G4 1.25 GHz | Radeon 9200 32 MB | 10.4.11 | ppc7400 |
| imac-g5 | G5 2.0 GHz | Radeon 9600 128 MB | 10.5.8 | ppc7400 |
| g5 tower | G5 Dual 2.7 GHz | Radeon 9600 | 10.3.9, 10.4.11 and 10.5.8 | ppc7400 |
| mini-intel | Core 2 Duo 2.33 GHz | GMA 950 | 10.7.5 | x86_64 |
| mini-sl | Core 2 Duo 2.26 GHz | GeForce 9400 | 10.6.8 | x86_64 |
| imac-2019 | i5-9600K | Radeon Pro 580X 8 GB | 15.7 | x86_64 |
| (desk Mac) | Apple M5 | - | 26 (dev build) | arm64 |

### Which OS each CPU needs

Five slices cover six CPU families; the G5 runs the same `ppc7400` slice as the G4s.
Each is built against the **oldest** OS its CPU can run:

| CPU | Slice | OS needed | Tested on |
|---|---|---|---|
| G3 (750) | `ppc750` | 10.3.9 Panther or later | 10.3.9, 10.4.11 |
| G4 (7400 / 7450 / 7447A) | `ppc7400` | 10.3.9 Panther or later | 10.4.11 |
| G5 (970) | `ppc7400` | 10.3.9 Panther or later | 10.3.9, 10.4.11, 10.5.8 |
| Intel, 32-bit only | `i386` | 10.4 Tiger through 10.6.8 | **not run on hardware** |
| Intel, 64-bit | `x86_64` | 10.6 Snow Leopard or later | 10.6.8, 10.7.5, 15.7 |
| Apple Silicon | `arm64` | 11.0 Big Sur or later | 26 (dev build) |

`dyld` picks a slice by **CPU subtype alone**, never by OS, and does not fall back to a
lower slice. So the `ppc7400` slice is built for 10.3 even though no G4 here runs
Panther: a G4 on Panther is a normal machine to own. Targeting 10.3 cost nothing
measurable on Tiger. **A G4 on Panther has not been run on hardware.**

The `i386` slice exists for the 2006 Core Solo and Core Duo Macs (Mac mini 1,1, iMac 4,1,
MacBook 1,1, MacBook Pro 1,1), the only Intel Macs with no 64-bit mode. There is no such
machine here, so its settings come from documented capability, not measurement.

The `arm64` slice links `sdl12-compat` over an SDL 2.32.4 this project builds and ships
(sha256-pinned), because no real SDL 1.2 exists for it. PowerPC and Intel keep the
genuine SDL 1.2. See `docs/adr/0017`.

## Framerate

Each Mac gets the settings its class can carry, at its own desktop resolution. These
are the shipped defaults on a fresh install, `four` timedemo, median of three warm
runs (2026-09-23; v0.6.17, except the G5 row (v0.6.18), the imac-2019 row
(v0.6.19 settings, pinned bench legs), the G4 row (v0.6.20, 2x FSAA + 16x
aniso) and the Intel GMA 950 row (v0.6.21, 16x aniso)):

| Class | Machine, resolution | fps |
|---|---|---:|
| G3, Panther | yosemite, 800×600 | 25.8 |
| G3, Tiger | yosemite, 800×600 | 32.9 |
| G4 | mini-g4, 1024×768, 2x FSAA, 16x aniso | 38.1 |
| G5 Dual 2.7 | g5 tower, 1680×1050, 2x FSAA, full textures | 47.2 |
| Intel GMA 950 | mini-intel, 1920×1080, vsync on, 16x aniso | 40.6 |
| modern Intel | imac-2019, 2560×1440, 4x FSAA, trilinear | 537.5 |

Floors: G3 20 fps; G4, Lion, G5 and newer 25 fps. A feature that keeps its class
at or above the floor stays on; extra frame rate above the floor comes from
optimising code, not from switching features off. Measurement history is in
[`docs/PROFILING.md`](docs/PROFILING.md) and [`benchmarks/results.csv`](benchmarks/results.csv).

## Known issues

- **GMA 950 Macs at 1920×1080** run ~41 fps, above the 25 fps floor, by choice: the
  driver paces frames to about 60 Hz on its own (55-59 fps with vsync off, whatever
  the settings), and vsync on was kept over the risk of tearing (#63).
- **Tiger** can ask you to confirm the first launch of a newly installed app; the game
  does not start until you answer that dialog.
- **The `i386` slice** has not been run on a Core Solo/Duo Mac.

## Features

- **One fat binary for every machine**, `ppc750` (G3), `ppc7400` (G4/G5 AltiVec),
  `i386` (2006 Core Solo/Duo), `x86_64` (Intel) and `arm64` (Apple Silicon) slices in
  a single Mach-O.
- Runs on **Mac OS X 10.3.9 Panther through current macOS**, natively on every one,
  including Apple Silicon rather than under Rosetta.
- **SDL 1.2** (the last SDL line that supports Panther and Tiger) and the GL1
  renderer on the four PowerPC/Intel slices; arm64 runs rend2 over
  sdl12-compat/SDL2 (ADR 0017).
- **Per-machine auto-config**: at launch it picks a tuned `autoexec` baked into
  the `.app` for the CPU slice, the GPU it finds, the Mac model and the OS
  (resolution, FSAA, anisotropic + trilinear filtering, texture/colour depth).
- **Native game modules**, `cgame`/`qagame`/`ui` ship as fat native dylibs
  built from stock source, replacing the bundled bytecode; a small measured win,
  with automatic fallback to the bytecode.
- Self-contained **`ioquake3.app`** with a custom icon that renders correctly
  from Panther's Finder to modern macOS.
- Optional **Apple Watch "tactical computer" companion** (`watchlink`), off by
  default; turn it on with `seta watch_enable 1` in `baseq3/autoexec.cfg` and off
  again with `seta watch_enable 0`.

## The Linux dedicated server

There is also a headless Linux server, so a game does not have to be hosted on
one of the old Macs. It builds from the same tree and ships as its own release
(`server-v*`), for x86_64 and aarch64. It needs glibc 2.31 or newer, so Ubuntu
20.04 or Debian 11 upward, and it ships no content.

Read [`server/README.md`](server/README.md) before putting one on the internet.
The firewall rules there are not optional: the engine answers unauthenticated
status queries with about 32 times what it was asked for, so an open server can
be used to reflect traffic at someone else.
The engine rate-limits these replies itself.

Hosting and running a dedicated server long-term (deployment, firewall setup,
webadmin) is covered in a separate repo,
[**retro-server-infra**](https://github.com/matthewdeaves/retro-server-infra), not here.

## Get the latest release

Download the latest disk image from
[**Releases**](https://github.com/matthewdeaves/old-mac-quake3/releases/latest)
(`ioquake3-OldMac-<version>.dmg`), one image runs on Panther, Tiger, Lion and
modern macOS.

Open the `.dmg`, then drag everything out of that window -- `ioquake3.app`,
`Fix Launch Problems.command`, and the `fix-support` folder -- together to
wherever you want the game to live (an empty folder is easiest, e.g.
`/Applications/Quake3`). On modern macOS, right-click
**`Fix Launch Problems.command`** there and choose Open (once -- this app
isn't Developer ID signed, so an unsigned script needs one right-click-Open
bypass the first time instead of a plain double-click). It clears the
quarantine flag that otherwise breaks the first launch, right where you put
it -- it does not move or copy anything for you -- see "Where to put it"
below for why that flag matters. Game data (`baseq3` `.pk3` files) is **not**
included, you need your own copy of Quake III Arena -- add your `pak0.pk3`
… `pak8.pk3` into that same folder's `baseq3/`, then double-click
`ioquake3.app` from there like any other app.

OS X 10.5-10.7 (Leopard, Snow Leopard, Lion) predate Gatekeeper being on by
default (the quarantine flag itself is older, since Leopard, but nothing
enforces it there) -- just drag `ioquake3.app` into a folder (e.g. `/Applications/Quake3`)
next to your own `baseq3/`, no script needed
(`Fix Launch Problems.command` checks the OS version itself and says so if
you run it anyway). Panther/Tiger (10.3/10.4) can skip it too, but running
it there still sets the Finder bundle icon -- a separate old-Finder fix,
unrelated to quarantine.

## Sister projects

Same machines, same tooling, older id engines:
[**old-mac-quakespasm**](https://github.com/matthewdeaves/old-mac-quakespasm)
(Quake) and [**old-mac-quake2**](https://github.com/matthewdeaves/old-mac-quake2)
(Quake II).

### Where to put it on Apple Silicon and modern macOS

Put the game folder in **`/Applications`** (or `~/Applications`, no admin
password needed -- wherever you drag it to when you run
`Fix Launch Problems.command`, see above), not on the Desktop.

macOS asks an app for permission before it may read files in Desktop, Documents
or Downloads, and it asks **every launch** for an app it cannot identify
consistently. A game that lives in `/Applications` is outside those protected
locations, so it never triggers the prompt and can read its own `baseq3/`
folder without being interrupted.

A quarantined app also gets **App Translocation** wherever it lives: macOS
runs it from a random, sandboxed copy instead of its real folder, so it can't
see `baseq3/` next to it at all. `Fix Launch Problems.command` clears the
quarantine flag for you, in place, wherever you dragged the app; doing it by
hand is:

```sh
xattr -dr com.apple.quarantine /Applications/<folder>
```

PowerPC and Intel Macs running 10.3 through 10.7 have none of this and can keep
the folder wherever you like.

## Credits & licence

Built on [ioquake3](https://github.com/ioquake/ioq3) and id Software's Quake III
Arena engine. Released under the **GPLv2** (see [`COPYING.txt`](COPYING.txt)).
This port adds the old-Mac build/deploy tooling and the SDL 1.2 / Panther fixes;
the upstream engine readme is preserved in [`README`](README).
