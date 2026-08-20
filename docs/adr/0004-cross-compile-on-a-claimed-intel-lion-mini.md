# 4. Cross-compile every slice on a claimed Intel Lion mini

Date: 2026-08-20
Status: accepted

## Context

The 10.3.9 and 10.4u SDKs and the `gcc-4.0` that goes with them live on the
Intel Lion minis under `/Developer/SDKs`. No modern Mac has them, and the
PowerPC machines are the hardware under test.

There are **two interchangeable Intel cross-build minis**, `mini-intel` and
`mini-intel2` - the same Macmini2,1 on 10.7.5 with the same toolchain, so either
builds any slice. Four projects share them: this port, QuakeSpasm, Quake II and
Half-Life.

## Decision

**All three slices cross-compile on an Intel Lion mini, chosen at runtime rather
than hardcoded. The PowerPC machines are bench and test targets only.**

- `build.sh`, `build-fat.sh` and `build-gamedylibs.sh` - the three scripts that
  compile - call `scripts/pick-build-host.sh --acquire` for a host that is
  reachable and idle and release it on exit. `BUILD_HOST=<alias>` pins one;
  `--status` shows both.
- `build-fat.sh` and `build-gamedylibs.sh` claim **one** host up front and hold
  it for the whole run, three slices plus the `lipo`, rather than re-picking per
  slice: the slices must be lipo'd together on the same box, and a sister
  project must not take it midway.
- **The rsync target directory is always `<host>:quake3/`** - never
  `quakespasm/`, never `quake2/`, never `<host>:~/`. The scripts hardcode the
  directory (`PROJ_REMOTE=quake3`), not the host.
- The claim is a lock directory **on the mini**, `/tmp/.retro-build-lock`, and
  the picker also counts running compiler processes as busy, so it detects
  builds started outside it.
- `pick-build-host.sh` is a distributed copy; the canonical one lives in the
  separate `old-mac-build-host` repository that owns the minis, and is synced
  out. Edit it there.

Isolation between the four projects on one host:

| Resource | QuakeSpasm | Quake II | **Quake III** |
|---|---|---|---|
| rsync target | `<host>:quakespasm/` | `<host>:quake2/` | **`<host>:quake3/`** |
| local flock | `~/quakespasm/build/.build.lock` | `~/quake2/build/.build.lock` | **`~/quake3/build/.build.lock`** |
| local outputs | `~/quakespasm/build/quakespasm-*` | `~/quake2/build/q2-*` | **`~/quake3/build/ioquake3-*`** |

Shared read-only on the minis: `/Developer/SDKs/{MacOSX10.3.9.sdk,
MacOSX10.4u.sdk}` and `/usr/bin/{gcc-4.0,clang}`. **Never modify them** -
recovery is multi-hour.

Other scripts that name `mini-intel` are not build-host references and are
correct as they stand: it is also a bench target (`bench.sh`,
`parallel-bench.sh`, `smoke-dmg.sh`, `screenshot.sh`, `deploy*.sh`) and the
game-data source (`distribute-data.sh`).

## Alternatives rejected

**Build natively on the PowerPC machines.** They are the slowest hardware and
the machines under measurement.

**Build on the orchestration box.** It has none of the SDKs or compilers these
targets need.

**A per-checkout `flock` alone.** It serialises only builds from the same
checkout and cannot see a build another repository, agent or workstation started
on the same mini. Both are kept: `flock` still guards same-repo races
(ADR 0003), the host lock guards cross-repo ones.

**Hardcoding one mini.** Two identical hosts exist so two builds can run at
once; hardcoding wastes half the capacity.

## Consequences

**Gained**

- One toolchain and one set of SDKs to keep provisioned, on either mini.
- Four projects build concurrently without colliding.

**Lost**

- Nothing can be tested where it is built; every PowerPC verification is a
  deploy-and-observe cycle on other hardware.

**Risks accepted**

- The distributed `pick-build-host.sh` can drift from the canonical copy.
