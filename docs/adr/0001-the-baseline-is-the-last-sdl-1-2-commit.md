# 1. The engine baseline is the last SDL 1.2 commit

Date: 2026-08-20
Status: accepted, with the premise re-opened (see "Re-examined" below)

## Context

The fleet runs Panther 10.3.9 (yosemite, a G3) and Tiger 10.4.11 (three G4s),
plus Leopard 10.5.8 (imac-g5), Lion 10.7.5 and modern macOS on Intel. Upstream
ioquake3 `HEAD` builds with CMake and SDL2. The reasoning at the time was that
SDL2 has never supported 10.3 or 10.4, so a modern ioquake3 binary would not
launch on the PowerPC machines.

## Decision

**The tree is pinned to `4432a80a` (2013-01-17, "Add vim stuff to .gitignore"),
the commit immediately before `f478761e` "Use SDL 2 instead of SDL 1.2".** That
commit is the root of branch `master` (originally `oldmac-base`, renamed once
the port became its own repository).

- That tree uses the top-level env-var-driven `Makefile` and `sdl-config`, and
  links `code/libs/macosx/libSDL-1.2.0.dylib`, which is the same SDL 1.2.x world
  the QuakeSpasm sister port lives in, so its cross-build recipe transfers.
- **Fallback, never needed:** the 1.36 release era, `b003422d` (2011-05) - older
  but the same SDL 1.2 line, and the version actually installed on the mini.
  `4432a80a` compiled clean against the 10.3.9 SDK with `gcc-4.0` with no source
  changes beyond the SDL fix in ADR 0006, so the fallback was never taken.

The engine diff against `4432a80a` is small and deliberate: `Makefile` (per-slice
arch flags, ADR 0003; `libSDLmain` from source, ADR 0006; `cl_watchlink.o`),
`code/qcommon/common.c` (auto-config, ADR 0007), `code/client/cl_watchlink.c`
plus its three call sites (ADR 0013), and the replaced `code/libs/macosx` SDL
blobs.

## Re-examined 2026-08-20: the premise is the one unmeasured claim in the project

Nearly every other constraint here is backed by evidence: the SDK floor A/B is a
bench table (ADR 0002), the dyld subtype grading is an `otool -L` diff, the
AltiVec claim is a disassembly count. **"SDL2 never supported macOS 10.3 or 10.4"
is backed by nothing in this tree.** `MISTAKES.md` labels it "caught at
planning", which is honest: it was reasoned, not tested.

Two supporting claims are weaker than they read:

- **"Upstream's PPC path targets the 10.5 SDK, G4 or better."** That text is
  `make-macosx.sh:76` ("For PPC macs, G4's or better are required to run
  ioquake3") and `:82-86` (the 10.5 SDK block) - a file that exists **in this
  pinned 2013 tree already**, and which our build bypasses entirely by driving
  the top-level `Makefile` with our own env vars. It says nothing about
  SDL2-era upstream.
- **"None of our PPC Macs run 10.5."** Out of date. `imac-g5` runs Leopard
  10.5.8 and is a benched fleet member.

Counter-evidence from the sister Half-Life port: it ships `panther-sdl2` 2.0.3,
targeting 10.3 and 10.4, statically linked into its PowerPC slices, and it runs
on a G3 on Panther. So "SDL2 never supported 10.3/10.4" is true of *upstream*
SDL and not of the forks that exist.

**None of that means the pin is wrong.** The migration cost is real and is
separately documented. It means the pin should be re-decided on measurement
rather than re-quoted. The original kickoff instruction "do not relitigate"
should be read as "do not relitigate casually", not "never look again".

## Alternatives rejected

**Build from upstream `HEAD` (CMake + SDL2).** Rejected on the reasoning above,
which is now flagged as unmeasured. A rebase would also discard the per-slice
`Makefile` control this port depends on (ADR 0003) and land in a build system
none of the tooling drives.

**Gate the G3 out and ship G4-and-up from a modern tree.** The blocker was
argued to be the OS/SDL pairing rather than the chip, so it would not have
helped: the G4s run Tiger, not Leopard.

## Consequences

**Gained**

- One 2013 tree that compiles with `gcc-4.0` against the 10.3.9 SDK and with
  `clang` on Lion, from one `Makefile`.
- The monolithic OpenGL1 renderer, which is what these GPUs can actually run.

**Lost**

- Nothing fixed in ioquake3 since 2013 is fixed here.
- `rend2` and the SDL2-era `r_ext_*` surface are not available.

**Risks accepted**

- The `upstream` remote (ioquake/ioq3, HEAD, reference only) **is not currently
  configured**: `git remote -v` shows only `origin`. Earlier documentation said
  it existed with its push URL disabled. Re-add it read-only if HEAD is ever
  wanted for comparison.
