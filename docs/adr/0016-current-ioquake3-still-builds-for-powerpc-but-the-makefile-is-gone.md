# 16. Current ioquake3 still builds for PowerPC, but the Makefile is gone

Date: 2026-08-20
Status: accepted (measured); no engine bump is proposed yet

## Context

ADR 0001 pins this port to the last SDL 1.2 commit (`4432a80a`, 2013) and
records the SDL 1.2 premise as the one unmeasured claim in the repo. The
question left open was whether a current engine could be built for PowerPC at
all. It was tested on 2026-08-20.

## What upstream did

**Upstream deleted the Makefile.** `76043c78 "Delete Makefile"` landed
2025-11-05; the tree is CMake-only after it and `CMakeLists.txt:1` requires
`cmake_minimum_required(VERSION 3.25)`, which will not run on a Lion mini.
The last Makefile-era commit is its parent, **`7ac92951`**, same day. The
Makefile there still builds but prints a deprecation notice and refuses to
run without `I_ACKNOWLEDGE_THE_MAKEFILE_IS_DEPRECATED=1` in `Makefile.local`.

## What was measured

**`7ac92951` builds for `ppc750` against the 10.3.9 SDK with gcc-4.0**, both
the GL1 client and `ioquake3_opengl2`, verified by `lipo -info`. Five changes
were needed:

1. **`-std=gnu99`.** The tree uses C99 declarations in `for` statements.
2. **`MACOSX_VERSION_MIN=10.3`.** The Makefile defaults to `11.0`
   (`Makefile:464`), which gcc-4.0 rejects outright as an unknown value.
3. **An AppKit alias.** `sys_osx.m` uses `NSAlertStyleCritical` /
   `NSAlertStyleWarning`, the 10.12 spellings. The 10.3.9 and 10.4u SDKs have
   only `NSCriticalAlertStyle` / `NSWarningAlertStyle`. Same values, so a
   two-line `#ifndef` alias keeps one source building on both.
4. **`USE_RENDERER_DLOPEN=0`.** With the renderer as a separate dylib, both it
   and the client link SDL2. Against a static Panther `libSDL2.a` that
   registers SDL's Objective-C classes twice in one process and the 10.3 ObjC
   runtime aborts in `class_initialize`. Measured on the sister Quake II tree
   the same day. Folding the renderer in leaves one SDL instance.
5. **Drop `HAVE_VM_COMPILED` for `__ppc__`.** See below.

**SDL 2.0.3 is enough.** `MINSDL_PATCH` is set conditionally
(`sys_local.h:36-40`): built against 2.0.3, `SDL_VERSION_ATLEAST(2,0,5)` is
false, so the floor becomes 2.0.0 and the check cannot fire. The Panther SDL2
ceiling is not a blocker for a current ioquake3.

## The PowerPC JIT is broken upstream

`q_platform.h:147` defines `HAVE_VM_COMPILED` for macOS `__ppc__`, and
`vm.c` uses that define to select the compiled VM. But `Makefile:2367` lists
`$(B)/client/vm_powerpc_asm.o` in the PowerPC object list and **the source
file for it no longer exists in the tree**. `vm_powerpc.c` compiles; the link
then dies on `VM_Compile` and `VM_CallCompiled`.

So the header promises a compiled VM the Makefile cannot link. Dropping the
define for `__ppc__` fixes it, and matches what `__aarch64__` in the same
block already does.

That last point also settles an open item in **ADR 0015**, which recorded
"the QVM has no arm64 backend" as INFERRED from the Makefile. It can be read
directly from the tree: `q_platform.h:158-160` gives `__aarch64__` an
`ARCH_STRING` and deliberately no `HAVE_VM_COMPILED`. Promote that claim from
INFERRED to read-from-source. It costs us nothing either way, because every
shipped `autoexec-*.cfg` sets `vm_game` / `vm_cgame` / `vm_ui` to 0 and runs
native dylibs (ADR 0008).

## Decision

**Record the result. Do not bump the engine yet.** ADR 0001 stands. What has
changed is that the bump is now a known quantity rather than an unknown: five
small patches, a pinned commit that upstream has already moved past, and a
build system upstream no longer maintains.

The pin would have to be `7ac92951`, which is a dead end by construction:
upstream develops on CMake after it. Taking it means either carrying the
Makefile ourselves or moving the whole port to a CMake that no build mini can
run.

## Consequences

**Gained**

- "Can a current ioquake3 target PowerPC?" is answered yes, with the exact
  patch list.
- ADR 0015's arm64 QVM claim is no longer an inference.

**Lost**

- Nothing. Nothing shipped changed.

**Open**

- The `ppc750` binary was built but **never run**. No hardware test.
- The SDL 1.2 to SDL 2.0.3 move this implies is untested for this engine on
  any PowerPC machine.
- Nothing was built for `ppc7400`, `ppc970`, `i386`, `x86_64` or `arm64`.
