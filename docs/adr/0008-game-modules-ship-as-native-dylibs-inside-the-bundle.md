# 8. Game modules ship as native dylibs inside the bundle: with QVM fallback

Date: 2026-08-20
Status: accepted

## Context

Quake III's game logic - `cgame`, `qagame`, `ui` - ships as QVM bytecode inside
id's own pak files. The long-standing idea was to replace it with native code to
kill "interpreter overhead".

**Profiling the build config refuted that premise first.** `vm_powerpc.c` and
`vm_powerpc_asm.c` are compiled into our fat binary (`Makefile:400` sets
`HAVE_VM_COMPILED=true` for `PLATFORM=darwin`; `Makefile:1806` adds the PowerPC
objects), and `vm_cgame` / `vm_game` / `vm_ui` default to `"2"` = `VMI_COMPILED`.
**The QVM is already JIT-compiled to native PowerPC at load** - there is no
interpreter running on the fleet. The unsymbolized `0x432*` leaves in the
quicksilver profile are the **JIT code buffer**, runtime-generated PowerPC with
no symbols, i.e. cgame already native.

So a native dylib buys only (a) a real compiler's codegen over the JIT's naive
per-opcode translation and (b) dropping the QVM's per-memory-access sandbox
bounds-masking.

**Measured**, on quicksilver, demo `four` at native 1680x1050, only `vm_cgame`
differing, three runs each. A timedemo is client-side playback, so only cgame
runs; there is no server, qagame is irrelevant, and ui is not active.

| cgame path | runs | median(2,3) | worst frame |
|---|---|---|---|
| native dylib (`vm_cgame 0`) | 41.5 / 41.4 / 41.9 | **41.65** | 81 ms |
| JIT (`vm_cgame 2`) | 41.0 / 41.0 / 41.2 | **41.10** | 81 ms |

**+0.55 fps, +1.3%, consistent** - every native run beat every JIT run, so real
rather than noise - at zero visual cost, worst frame unchanged. Recorded so it
is never re-hyped as a "~5% interpreter win": it is not, the JIT already
captured that.

The measurement was first taken as sub-threshold and **not shipped**, because
the fat model would need nine builds and three lipos and a deployment-model
change. That work was subsequently done, and the modules now ship.

## Decision

**`cgame`, `qagame` and `ui` ship as fat native dylibs inside the `.app`, and
the per-arch autoexec cfgs set `vm_cgame` / `vm_game` / `vm_ui` to `0`.**

- `scripts/build-gamedylibs.sh` produces six files in `build/gamedylibs/`:
  `cgameppc.dylib`, `qagameppc.dylib`, `uippc.dylib` (each fat
  `ppc750 + ppc7400`) and `cgamex86_64.dylib`, `qagamex86_64.dylib`,
  `uix86_64.dylib`. Nine builds, three lipos. Per-slice flags and OS floors
  match `build.sh` (ADR 0002), and the PowerPC cpusubtypes are re-stamped and
  asserted (ADR 0003).
- `make-app.sh` places them at `ioquake3.app/Contents/MacOS/baseq3/`. On macOS
  that path is `fs_apppath/baseq3` (`files.c`, `#ifdef MACOS_X`), a search
  directory `FS_FindVM` scans **before** the user's `pak8.pk3` QVM.
- `dyld` selects the arch slice from the fat dylib.
- **`FS_FindVM` falls back to the QVM automatically** if the dylib is absent,
  wrong-arch, or the client is on a pure server (`fs_numServerPaks > 0`), so
  `vm_* 0` is always safe.
- These are the **only** files this port puts inside the bundle's `baseq3`. The
  user's own game data stays outside it (ADR 0011).

## Alternatives rejected

**Keep the QVM everywhere.** Leaves the measured 1.3% on the table now that the
delivery mechanism exists.

**Ship the dylibs next to the app rather than inside it.** They would then be in
the user's data directory, which this port does not write to. The Quake II
sister port does exactly that, and as a side effect avoids the LaunchServices
fault in ADR 0010 - which is a real cost of this choice, accepted knowingly.

## Consequences

**Gained**

- +1.3% on quicksilver, at no visual cost and no worst-frame cost, with safe
  automatic degradation on any machine or server where the dylib cannot be used.

**Lost**

- Nine builds and three lipos on every release, and native game code as a wider
  attack surface than sandboxed bytecode.
- The `.app` now `dlopen`s a file inside itself, which breaks its own
  LaunchServices record on Lion. See ADR 0010.
