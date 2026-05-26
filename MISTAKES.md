# MISTAKES — ioquake3 old-Mac port

Append-only log of approaches that broke or would have broken. **Read before
lighting up an idea that smells "easy", "modern is better", or "load-time /
zero risk".** Mirrors `~/quakespasm/MISTAKES.md`.

---

## Modern ioquake3 (SDL2 / CMake) cannot run on the PPC fleet — caught at planning

**The smell:** "Just clone ioquake3 HEAD, it's the most maintained — newer is
better." Pinned HEAD (and then the last-Makefile commit) before checking the
runtime envelope.

**Why it breaks:** upstream ioquake3 switched to **CMake + SDL2**, and its PPC
build targets the **10.5 SDK** (`make-macosx.sh`: *"For PPC macs, G4's or
better are required"*). **SDL2 has never supported macOS 10.3 / 10.4.** The
PPC fleet runs Panther 10.3.9 (yosemite) and Tiger 10.4.11 (the G4s) — **none
run 10.5** — so a modern binary won't launch on any PPC bench machine. The G4
machines being on Tiger (not Leopard) means even "G4-only" modern builds are
out; the blocker is the OS/SDL pairing, not just the chip.

**The fix (this one):** baseline pinned to the **last SDL 1.2 commit** `4432a80a`
(2013-01-17), branch `oldmac-base`, right before `f478761e "Use SDL 2 instead
of SDL 1.2"`. SDL 1.2 supports Panther/Tiger and is the same family
QuakeSpasm uses. `main` keeps HEAD for reference only. See `CLAUDE.md`
"THE load-bearing constraint".

**Lesson:** for this fleet, "best port" is decided by the **OS + SDL + GPU**
envelope of the *oldest* target, not by upstream activity. Check what will
actually launch on Panther before picking a baseline.

---

## (Open risk, not yet a mistake) Q3A on the 449 MHz G3 may be below playable

Quake III is much heavier than Quake 1, and yosemite (G3 449 MHz, Rage 128
16 MB) is at the 1999 minimum-spec edge. The ≥ 20 fps G3 floor is
**aspirational** — prove it by bench before committing visual work to that
slice. If it can't clear the floor even at `r_picmip 3` / low detail, gate G3
out (compile-time or per-machine) rather than dragging the matrix down.

**Update 2026-05-26:** disproven-as-blocker — a *windowed* `four` timedemo at
640×480 with default settings hit **20.5 fps on the G3** (and that run was
contended by iMovie), **60.8 fps on the G4** (quicksilver, Radeon 9000),
**~288 fps on Lion** (GMA 950). The floor looks reachable; still bench clean
before trusting it.

---

## The prebuilt `libSDLmain.a` / `libSDL-1.2.0.dylib` SIGSEGV on Panther — caught at first G3 run

**The smell:** "ioquake3 ships a fat `libSDL-1.2.0.dylib` (ppc+x86_64+i386) and
a prebuilt `libSDLmain.a` — just link them, they're already universal." The fat
binary built fine, ran on Lion (~288 fps), and on the G3 it... **SIGSEGV'd
before printing a single line.** Crash logs were the only clue.

**Why it breaks:** both prebuilt blobs were built for **Mac OS X 10.4+**. On PPC
they dispatch `objc_msgSend` via a **fixed absolute address — `bla 0xfffeff00`**
(an ObjC fast-dispatch trampoline that exists on 10.4+ but is **unmapped on
10.3.9**). So the Cocoa bootstrap faults instantly:
- prebuilt `SDLMain.o` → crash in `main` (the Cocoa app bootstrap) at the first
  `objc_msgSend`.
- prebuilt `libSDL-1.2.0.dylib` → crash in `SDL_VideoInit` (the Quartz video
  driver's Cocoa calls), reached via `GLimp_StartDriverAndSetMode` → `SDL_Init`.

The trap: `lipo`/`file` say "ppc" so it *looks* portable; nothing flags the
10.4-only dispatch until a real 10.3.9 CPU executes it. `otool -tv | grep 'bla
0xfffeff00'` on the **executable's** SDLMain is the tell (the dylib hides it
behind stubs, but the crash backtrace names `SDL_VideoInit + 0xNNN → 0xfffeff00`).

**The fix:**
1. **Compile `SDLMain.m` from source** against the target SDK / `-mmacosx-version-min`
   instead of copying the prebuilt `.a`. Stock SDL 1.2.15 `SDLMain.m` (from
   QuakeSpasm's `SDL.framework/.../devel-lite`, with `SDL_USE_NIB_FILE 0` so it
   uses `CustomApplicationMain`, no NIB) now lives at `code/libs/macosx/SDLMain.m`;
   the Makefile builds `libSDLmain.a` from it.
2. **Replace the bundled `libSDL-1.2.0.dylib`** with QuakeSpasm's proven
   Panther-safe SDL 1.2.15 (it runs on yosemite), `install_name_tool -id`'d back
   to `@executable_path/libSDL-1.2.0.dylib`.

After both, the G3/G4 reach `GL_RENDERER` and run the timedemo.

**Lesson:** "universal" only means the *architectures* are present — not that
each slice targets the *OS* of the oldest machine. A prebuilt PPC blob can still
be 10.4-only. For this fleet, never trust a prebuilt macOS lib to run on Panther;
rebuild it from source against the 10.3.9 SDK, or steal QuakeSpasm's (which is
already proven on yosemite).
