# 2. Three slices in one fat binary: floored at the oldest OS each CPU can run

Date: 2026-08-20
Status: accepted

## Context

The fleet spans a 449 MHz G3 on Panther through a 2019 iMac on Sequoia. Shipping
one artefact to all of them means one fat Mach-O and letting `dyld` choose.

`dyld` grades a fat binary by **CPU subtype alone**. The OS plays no part, and
there is no fallback to a lower slice. A G4 running Panther is handed the
`ppc7400` slice because it is a 7400, whatever OS floor that slice was built at.

The port originally built each slice against "the SDK of the OS that machine
runs": g3 against 10.3.9 because yosemite runs Panther, g4 against 10.4u because
all three G4s run Tiger, Intel at min 10.7 because the build host is a Lion mini.
That reads as careful matching and is backwards - it made the `ppc7400` slice
unlaunchable on any G4 or G5 running Panther, and the same bug was present in the
three fat game dylibs. Verified on the binaries, not on intent: the old `ppc7400`
slice linked libSystem 88.3.11 / AppKit 824.48 (Tiger) against the `ppc750`
slice's libSystem 71.1.3 (Panther).

## Decision

**Three slices - `ppc750`, `ppc7400`, `x86_64` - in one Mach-O, each built
against the oldest OS its CPU family can run.** Fixed in commit `069b36d0`.

| Slice | Built against | Floor | Serves |
|---|---|---|---|
| `ppc750` | 10.3.9 SDK, `-mmacosx-version-min=10.3` | 10.3.9 Panther | G3 (750) |
| `ppc7400` | 10.3.9 SDK, `-mmacosx-version-min=10.3` | 10.3.9 Panther | G4 (7400/7450/7447A) and G5 (970) |
| `x86_64` | Lion toolchain, `-mmacosx-version-min=10.6` | 10.6 Snow Leopard | 64-bit Intel |

Per-slice flags, from `scripts/build.sh`:

- **g3:** `ARCH=ppc CC=gcc-4.0`, `-arch ppc750 -mcpu=750
  -mmacosx-version-min=10.3 -O3`. **No AltiVec** - a 750 has no vector unit, and
  an AltiVec instruction is an illegal instruction there.
- **g4:** `ARCH=ppc CC=gcc-4.0`, `-arch ppc7400 -mcpu=7400 -faltivec
  -mtune=7450 -mmacosx-version-min=10.3 -O3 -isystem
  /usr/lib/gcc/powerpc-apple-darwin10/4.0.1/include`. The `-isystem` is
  mandatory: `-faltivec` makes the compiler want `<altivec.h>`, a **compiler**
  header that `-isysroot` hides. `-faltivec` itself is required against the
  10.3.9 SDK, for Apple's context-sensitive `vector` keyword.
- **lion:** `ARCH=x86_64 CC=clang`, min 10.6, `-O3`.

All slices build `USE_RENDERER_DLOPEN=0` (monolithic, opengl1 linked in, no
renderer dylib, rend2 skipped), `CLIENTBIN=ioquake3`, `BASEGAME=baseq3`. Output
lands in `build/release-darwin-<arch>/ioquake3.<arch>`; both PowerPC slices are
`ARCH=ppc` and collide on that filename, so `build.sh` renames to
`ioquake3-g3` / `ioquake3-g4`. `build-fat.sh` lipos the three into
`build/ioquake3-fat`, the only binary deployed.

Multi-subtype ppc lipo (`ppc750` + `ppc7400` in one Mach-O) is proven to work by
the QuakeSpasm sister port.

## Evidence: lowering the floors cost nothing

Same source, same commit, `four` timedemo, three runs, median of 2 and 3, bench
harness with the per-machine auto-config off (`+set com_archAutoexec 0`). Old
`ppc7400` (10.4u SDK) against new (10.3.9 SDK):

| Machine | Before | After |
|---|---:|---:|
| quicksilver (G4 / Radeon 9000) 1680x1050 | 41.65 | 41.40 |
| mini-g4 (Radeon 9200) 1680x1050 | 27.55-30.00 † | 27.60 |
| mini-intel (Lion / GMA 950) 1920x1080 | 41.20 | 42.00 |

† Four passes at the same commit recorded 27.55, 27.90, 27.90 and 30.00, so the
mini-g4 row is a range rather than a figure and is a weaker comparison than the
other two. Run-to-run spread within one pass is about +/-0.3 fps, so quicksilver
and the Intel mini are ties.

**AltiVec survives the SDK change.** The g4 slice disassembles to *exactly* 165
AltiVec instructions before and after: codegen follows `-arch`/`-mcpu`, not the
SDK. After the change every ppc member links libSystem 71.1.3 / Cocoa 9.0.0.
Manually confirmed playing on the G3 (10.3.9) and the iMac G5 (10.5.8).

## Alternatives rejected

**One generic `ppc` slice for all PowerPC.** A generic `ppc` member (subtype 0)
matches *every* PowerPC host, so it shadows the correct slice and a G3 would
load the AltiVec build. See ADR 0003.

**A separate `ppc970` slice for the G5.** The G5 runs the `ppc7400` slice; no
measured need for a fourth.

**Matching each slice's SDK to the OS the machine in the rack boots.** The bug
this ADR fixes. Ask instead: what is the oldest OS a CPU that grades to this
slice could be running? Check the answer with `otool -L`, not against intent.

## Consequences

**Gained**

- One `.app` and one DMG for 10.3.9 Panther through modern macOS.
- A G4 or G5 on Panther, and an Intel Mac on Snow Leopard, can launch it.

**Lost**

- **No `i386` slice**, so 32-bit-only Intel Macs (Core Solo / Core Duo, 2006)
  are not covered. There is no such machine here to build or test one on.
- **No `arm64` slice** - see ADR 0015.

**Not verified on hardware** (stated rather than implied): a G4 on Panther, a G5
on Panther or Tiger, and an Intel Mac on Snow Leopard should all work; no such
machine exists here to run them.
