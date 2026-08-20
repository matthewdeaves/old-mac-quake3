# 6. Prebuilt Mac libraries are rebuilt from source for Panther

Date: 2026-08-20
Status: accepted

## Context

ioquake3 ships a fat `code/libs/macosx/libSDL-1.2.0.dylib` (ppc + x86_64 + i386)
and a prebuilt `code/libs/macosx/libSDLmain.a`. Linking them produced a fat
binary that built cleanly and ran on Lion at ~288 fps - and **SIGSEGV'd on the
G3 before printing a single line**. Crash logs were the only clue.

**Root cause.** Both prebuilt blobs were built for Mac OS X 10.4 and up. On
PowerPC they dispatch `objc_msgSend` through a **fixed absolute address,
`bla 0xfffeff00`** - an Objective-C fast-dispatch trampoline that exists on 10.4
and later and is **unmapped on 10.3.9**. So the Cocoa bootstrap faults instantly:

- prebuilt `SDLMain.o` faults in `main`, the Cocoa app bootstrap, at the first
  `objc_msgSend`;
- prebuilt `libSDL-1.2.0.dylib` faults in `SDL_VideoInit`, the Quartz video
  driver's Cocoa calls, reached from `GLimp_StartDriverAndSetMode` -> `SDL_Init`.

`lipo` and `file` both say "ppc", so it *looks* portable; nothing flags the
10.4-only dispatch until a real 10.3.9 CPU executes it. The tell is
`otool -tv | grep 'bla 0xfffeff00'` on the **executable's** SDLMain - the dylib
hides it behind stubs, but the crash backtrace names
`SDL_VideoInit + 0xNNN -> 0xfffeff00`.

## Decision

**Compile `SDLMain.m` from source per slice, and replace the bundled SDL dylib
with QuakeSpasm's Panther-proven build.**

1. Stock SDL 1.2.15 `SDLMain.m` (from QuakeSpasm's
   `SDL.framework/.../devel-lite`, with `SDL_USE_NIB_FILE 0` so it uses
   `CustomApplicationMain` and needs no NIB) lives at
   `code/libs/macosx/SDLMain.m`. The `Makefile` rule builds `libSDLmain.a` from
   it with the target SDK and `-mmacosx-version-min`, replacing upstream's
   `cp $< $@` of the prebuilt `.a`.
2. `code/libs/macosx/libSDL-1.2.0.dylib` is QuakeSpasm's Panther-safe SDL
   1.2.15, `install_name_tool -id`'d back to
   `@executable_path/libSDL-1.2.0.dylib`. It is bundled **inside** the `.app` at
   `Contents/MacOS/libSDL-1.2.0.dylib`, so no loose runtime libraries sit next
   to the app.

After both, the G3 and G4 reach `GL_RENDERER` and run the timedemo.

## Alternatives rejected

**Link the prebuilt blobs because they are already universal.** "Universal"
only means the *architectures* are present, not that each slice targets the
*OS* of the oldest machine.

**Ship an SDL framework alongside the app.** One dylib inside the bundle,
resolved by `@executable_path` at load time, is fewer things to find and grade
on the machines where the loader is most likely to go wrong. It is also what
keeps the QVM launch path clear of `dlopen` (ADR 0010).

## Consequences

**Gained**

- Every slice's Cocoa bootstrap uses the dispatch its own floor supports.

**Lost**

- The port carries a vendored SDL 1.2.15 binary it did not build itself, from
  the sister QuakeSpasm tree.

**Rule that follows**

- **Never trust a prebuilt macOS library to run on Panther.** Rebuild it from
  source against the 10.3.9 SDK, or take QuakeSpasm's, which is already proven
  on yosemite.
