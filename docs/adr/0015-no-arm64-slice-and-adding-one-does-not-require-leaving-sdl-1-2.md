# 15. No arm64 slice, and adding one would not require leaving SDL 1.2

Date: 2026-08-20
Status: accepted (no arm64 slice ships)

## Context

Recorded because the arm64 question and the "rebase onto modern ioquake3"
question (ADR 0001) keep being treated as one decision. They are not.

What blocks an arm64 slice is that **SDL 1.2 upstream never produced an arm64
build**, so there is no arm64 SDL to link. What that needs is an **arm64
implementation of the SDL 1.2 API**, which `sdl12-compat` (libsdl-org) is,
rather than a newer engine. Each slice of a fat Mach-O carries its own
`LC_LOAD_DYLIB`, so an arm64 slice could link the shim while the PowerPC and
Intel slices keep real SDL 1.2.

**What sdl12-compat can and cannot do** (researched 2026-08-20, scope corrected
after an earlier draft implied it was a general answer to SDL 1.2 on modern
systems):

- **It cannot help PowerPC.** It `dlopen`s SDL2 and enforces a minimum of
  **SDL2 2.0.7 on macOS** (`src/SDL12_compat.c:1293`, checked at `:1755`),
  while the PowerPC ceiling is **2.0.3**. It is a candidate for the arm64 slice
  only, never a way to modernise the PowerPC ones.
- **It does build for arm64 on macOS**, verified on the orchestration Mac.
- **It does not make an existing binary run**; the engine is still compiled for
  arm64 either way.
- **Risks that matter for a GL game:** its OpenGL scaling path redirects
  rendering through a fake backbuffer and is documented to break FBO-using
  applications, and its macOS quirks table is empty
  (`src/SDL12_compat.c:1490-1493`), so no per-game workaround auto-applies.

The trade stands, but it is a trade: the shim is the only route that leaves the
PowerPC and Intel slices untouched, and the alternative is an engine with a real
SDL2 path, which is the rebase this ADR keeps separate.

## Decision

**No arm64 slice ships.** Apple Silicon Macs run the `x86_64` slice under
Rosetta 2. The three-slice model of ADR 0002 stands.

## Two arm64 specifics for this engine

Both found by **reading the tree, not by building**, so treat as **INFERRED**
until a build confirms them.

- **The QVM has no arm64 backend and the `Makefile` will not warn you.**
  `Makefile:400` sets `HAVE_VM_COMPILED=true` unconditionally for
  `PLATFORM=darwin`, before any arch test. The backend selection at
  `Makefile:1766` onward is a chain of `ifeq` on `ARCH` - `i386`, `x86`,
  `x86_64`, `amd64`, `x64`, `ppc`, `ppc64`, `sparc` - **with no `else` and no
  arm64 case**. `-DNO_VM_COMPILED` is added only when `HAVE_VM_COMPILED` is not
  true (`Makefile:843-844`). So an arm64 darwin build claims a JIT, links no
  `vm_*.o`, and does not get `-DNO_VM_COMPILED`. It should fail loudly at link
  time. The fix is one line: gate darwin on arch the way the Linux block already
  does.
- **Apple Silicon enforces W^X**, so a QVM JIT would need `MAP_JIT` plus
  `pthread_jit_write_protect_np`. Largely moot in practice: every shipped
  `autoexec-*.cfg` sets `vm_game` / `vm_cgame` / `vm_ui` to `0`, meaning native
  dylibs, not the JIT (ADR 0008). An arm64 slice would want a fourth set of
  those dylibs, taking `build-gamedylibs.sh` from 9 builds and 3 lipos to 12
  and 4.

## Alternatives rejected

**Treat arm64 as a reason to rebase onto SDL2 upstream.** The blocker is an SDL
1.2 ABI for arm64, which `sdl12-compat` supplies without touching the engine
baseline. Conflating the two makes the rebase look mandatory when it is not.

## Consequences

**Gained**

- The arm64 question can be evaluated on its own cost, independent of ADR 0001.

**Lost**

- Apple Silicon runs translated, so no native-speed reference on modern
  hardware.

**Open**

- Nothing above has been compiled. The first arm64 build attempt is what
  promotes these from INFERRED to measured.
