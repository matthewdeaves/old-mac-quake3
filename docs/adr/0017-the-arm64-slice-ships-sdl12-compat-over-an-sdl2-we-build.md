# 0017. The arm64 slice ships sdl12-compat over an SDL2 we build

Date: 2026-08-20

Status: accepted. Supersedes the conclusion of
[0015](0015-no-arm64-slice-and-adding-one-does-not-require-leaving-sdl-1-2.md),
whose reasoning about how the shim would have to be sourced was wrong.

## Context

0015 established that the engine itself is arm64-clean, and that the only thing
standing between this port and an arm64 slice is the absence of an arm64
implementation of the SDL 1.2 API. That much held up.

What did not hold up was the reason given for not doing it. The recorded
objection was that `sdl12-compat` drags in a three-deep shim stack: engine ->
sdl12-compat -> sdl2-compat -> SDL3, on the grounds that Homebrew's arm64
`sdl12-compat` loads Homebrew's `libSDL2-2.0.0.dylib`, which on that system is
`sdl2-compat`, itself a shim over SDL3.

That description of Homebrew is accurate and was checked again here
(`/opt/homebrew/lib/libSDL2-2.0.0.dylib` resolves into
`Cellar/sdl2-compat/2.32.70`). It is simply not a description of what we would
ship, because it assumes we would use the system's SDL2. We do not have to.

`sdl12-compat` has **no link-time dependency on SDL2 at all**. It `dlopen`s one
at runtime, and the first location it tries is `@loader_path/libSDL2-2.0.0.dylib`
(`src/SDL12_compat.c`, the `dylib_locations` table). Verified on the shim we
built: `otool -L` lists AppKit, Foundation, CoreFoundation, ApplicationServices,
libobjc and libSystem, and nothing else.

So the stack is whatever SDL2 we put next to the binary. Shipping our own makes
it two layers, both ours:

    ioquake3 (arm64) -> sdl12-compat 1.2.76 -> SDL 2.32.4

Both are built from pinned upstream sources by `scripts/build-arm64.sh`. The
SDL 2.32.4 is the same version and the same provenance as the one the Half-Life
port already ships in its own arm64 slice.

## Decision

Ship an arm64 slice. It is the fifth member of the same fat binary, selected by
dyld on CPU subtype alone exactly as the other four are.

The arm64 member of `code/libs/macosx/libSDL-1.2.0.dylib` is `sdl12-compat`.
The `ppc`, `i386` and `x86_64` members of that same file remain genuine
SDL 1.2 and are untouched, byte for byte. No PowerPC or Intel machine ever
loads the shim, and no engine source is conditional on which one it got.

`code/libs/macosx/libSDL2-2.0.0.dylib` is new, arm64-only, and ships beside the
binary so the shim finds ours rather than the machine's.

arm64 is **optional at fuse time**, like the Half-Life port's. `build-fat.sh`
and `make-dmg.sh` both say out loud whether the slice is present; its absence
is a Rosetta 2 downgrade, not a failure. This is not a nicety: a mini cannot
build arm64, so a hard requirement would make a release impossible from the
normal build path.

## The engine fix this needed

Native arm64 game modules did not work at first. `cgamearm64.dylib` loaded and
then died on `CG_ConfigString: bad index: -274449096`.

The cause is an argument-passing mismatch that is invisible on every other
architecture this port targets. The engine declared the module entry point as
variadic:

    intptr_t (QDECL *entryPoint)( int callNum, ... );

while every module *defines* `vmMain` with thirteen named `int` parameters and
no ellipsis (`cg_main.c`, `g_main.c`, `ui_main.c`). `VM_Call` already passed
exactly those thirteen, so on x86_64 and PowerPC the two spellings compile to
the same call sequence and nothing is wrong. On Apple arm64 they do not: a
variadic call places every argument after the last **named** one on the stack,
while a non-variadic callee reads them from `x1`-`x7`. The module therefore got
its first argument and garbage for all twelve others.

Reduced to a standalone test across a real `dlopen` boundary, with an x86_64
control:

    arm64:  engine sent 11 22 33 44  ->  module saw 11 -2089563526 73896 53714815
    x86_64: engine sent 11 22 33 44  ->  module saw 11 22 33 44

The fix is a shared `vmMainEntry_t` typedef in `qcommon.h` spelling the
prototype the way the modules actually define it, used at all three
declaration sites (`qcommon.h`, `vm_local.h`, `sys_main.c`). It is correct on
every architecture and changes generated code on none of them but arm64.

Two earlier explanations for the same symptom were tested and **refuted**, and
must not be republished:

- "Apple arm64 does not promote variadic `int` to 8 bytes, so the engine's
  `va_arg(ap, intptr_t)` reads a mis-sized slot." Tested directly: passing
  `int`s and reading `intptr_t` gives the correct values, and passing explicit
  `intptr_t`s gives byte-identical output.
- "The mismatch is in the module-to-engine direction (`VM_DllSyscall`)." That
  direction is variadic on both sides and is fine.

## Consequences

- Apple Silicon runs this port natively. Measured on an M5, demo `four`, median
  of three: 875 fps with native modules, 830 fps interpreted, and 485 fps at
  2560x1440 with 16x anisotropic and 4x multisample.
- The arm64 slice is the only one with no bytecode JIT. `vm_powerpc.c` and
  `vm_x86.c` cover the others; this baseline has no arm64 backend, so a QVM
  here runs on the plain interpreter. `scripts/bundle/autoexec-arm64.cfg`
  therefore sets `vm_cgame`/`vm_game`/`vm_ui` to 0 and the port ships native
  arm64 modules, which is only possible because of the fix above.
- `r_mode -2` (desktop resolution) is used on this slice and no other. Apple
  Silicon Macs ship many different panels, so a hardcoded resolution would be
  letterboxed or scaled on most of them. Verified live: it selected 1710x1107.
- Everything arm64 is built on the orchestration Mac. That is now true of two
  scripts, `build-arm64.sh` and `build-gamedylibs-arm64.sh`.
- Signing happens **before** the fuse, never after. `build-fat.sh` lipos on a
  Lion mini, which cannot codesign arm64, and an unsigned arm64 Mach-O is
  SIGKILLed on load with no diagnostic. `lipo` preserves each member's bytes,
  signature included.

## What is still open

The risks 0015 raised against the shim are reduced, not eliminated. Its
OpenGL scaling path is documented upstream to misbehave with FBO users, and its
macOS quirks table is empty. Neither has been observed here: a full demo
renders correctly, and mouse look and WASD both drive the player in a live map.
They are worth re-checking on any engine or shim bump.
