# Mistakes

Search by date or ticket; newest records first.
Archive: `docs/archive/MISTAKES.md` contains the verbatim detailed accounts.
Dates added to undated accounts identify their recorded evidence or first Git record, not a newly inferred incident date.

## 2026-09-25 imac-g5 went unresponsive after a clean timedemo at native resolution (2026-09-25)
**What happened.** `bench-evidence.sh imac-g5 baseline-r1` at `BENCH_RES=1440x900` (imac-g5's confirmed native resolution, `docs/PROFILING.md`, no mode switch involved) ran a real timedemo to completion -- 1260 frames, 34.2 seconds, 36.8 fps printed by `CL_DemoCompleted()` -- and then the host went unresponsive.
Full cause, fix and evidence: `docs/archive/MISTAKES.md`, search the distinctive heading text.

## #71 follow-up: Gap 1 fixed (build-host#119/6b42c47, shared-v2), Gap 2 still open, plus a Jenkins caller found
Pin bumped to `shared-v2` tonight (2026-09-25), verified empirically: a real claim through `scripts/shared.sh pick-bench-host.sh --run mini-sl ...` now shows `OWNER` as `matt@Hayleys-Air:old-mac-quake3`, not `retro-shared`.
Full cause, fix and evidence: `docs/archive/MISTAKES.md`, search the distinctive heading text.

## 2026-08-28 A correct `-mmacosx-version-min` stamp does not mean the binary runs there (2026-08-28)
**The smell:** "the compiler accepts `-mmacosx-version-min=10.6`, the linker stamps `LC_VERSION_MIN_MACOSX version 10.6` on the output, so it targets 10.6." Issue #39 asked whether `imac-2019` (Sequoia 15.7.9, its own clang 17) could cross-...
Full cause, fix and evidence: `docs/archive/MISTAKES.md`, search the distinctive heading text.

## 2026-08-23 A one-liner that reports on six machines is itself a thing that has to be right (2026-08-23)
Verifying that a stale config had been removed from six bench machines, the check was: a=$(ls ~/Desktop/quake3/baseq3/autoexec.cfg 2>/dev/null && echo PRESENT || echo none) On success `ls` prints THE PATH as well as the word, so `$a` holds two lines.
Full cause, fix and evidence: `docs/archive/MISTAKES.md`, search the distinctive heading text.

## 2026-08-23 A timeout is not a crash, and the harness says "crash" (2026-08-23)
`smoke-dmg.sh` reported "no fps line; the production launch did not render a demo (crash or hang)" for mini-intel.
Full cause, fix and evidence: `docs/archive/MISTAKES.md`, search the distinctive heading text.

## 2026-08-22 The Makefile has two ARCH ladders that look alike, and only the second one is ours - 2026-08-22
Checking whether the `i386` slice JIT-compiles the QVM or interprets it, I read the ARCH cases at `Makefile:314-345`.
Full cause, fix and evidence: `docs/archive/MISTAKES.md`, search the distinctive heading text.

## 2026-08-22 A quoted heredoc protects the shell, not the GitHub gate (2026-08-22)
Three issues in this repo were closed without anyone deciding to close them.
Full cause, fix and evidence: `docs/archive/MISTAKES.md`, search the distinctive heading text.

## 2026-08-21 Modern ioquake3 (SDL2 / CMake) was ruled out for the PPC fleet - caught at planning
**The smell:** "just clone ioquake3 HEAD, it's the most maintained, newer is better." HEAD was pinned before anyone checked the runtime envelope.
Full cause, fix and evidence: `docs/archive/MISTAKES.md`, search the distinctive heading text.

## 2026-08-20 `-faltivec` silently un-stamps the cpusubtype - inherited: guarded here
**The smell:** `-arch ppc7400 -mcpu=7400` is on the command line, so the binary must be stamped `ppc7400`.
Full cause, fix and evidence: `docs/archive/MISTAKES.md`, search the distinctive heading text.
