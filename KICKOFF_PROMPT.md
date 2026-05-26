# Kickoff prompt — ioquake3 old-Mac port

Start a new Claude Code session **from `~/quake3`** and paste the block below.
(Everything it needs is already in this repo: read `CLAUDE.md` first.)

---

You are picking up a brand-new sibling project to my QuakeSpasm PPC port
(`~/quakespasm`) and Quake II port (`~/quake2`): an **ioquake3 (Quake III
Arena) build tuned for old Macs**, sharing the same 6-machine bench fleet and
the `mini-intel` cross-build host. The project scaffold already exists — read
`CLAUDE.md`, `scripts/README.md`, `scripts/CLAUDE.md`, and `MISTAKES.md`
before doing anything. **All scripts in `scripts/` are v0 drafts and nothing
has compiled yet** — your job is to make the pipeline real, then establish a
baseline.

**The load-bearing constraint (already decided, do not relitigate):** the code
is pinned to branch **`master` (rooted at `4432a80a`)**, the last SDL 1.2 commit.
Modern ioquake3 (HEAD) is CMake + SDL2, and SDL2 can't run on Panther 10.3.9
or Tiger 10.4.11 — which is the entire PPC fleet. SDL 1.2 is mandatory. See
`MISTAKES.md`. Fallback if 4432a80a won't build for Panther: the 1.36 era
(`b003422d`).

**Hard rules:** the game is installed on `mini-intel` at
`/Users/mini/Games/ioquake3/` — **never modify it** (read-only source of
assets). The baseq3 data (9 pk3s) is already staged at
`mini-intel:~/Desktop/quake3/baseq3/`. rsync builds ONLY to `mini-intel:quake3/`
— never `quakespasm/` or `quake2/`. Inherit every fleet gotcha in
`scripts/CLAUDE.md` (integer sleep on Panther, TERM-then-KILL, never pkill,
yosemite `--protocol=29`, `mini-intel` sleeps).

**Validation sequence — do these in order, committing as you go:**

1. **Prove the build for ONE slice first — `g4` (ppc7400, 10.4u SDK).** It's
   the likeliest to compile. Run `scripts/build.sh g4` and fix what breaks.
   The two known unknowns to resolve here:
   - **Fat SDL 1.2 dylib.** ioquake3 links `libSDL-1.2.0.dylib`. Source a
     fat (ppc750+ppc7400+x86_64) SDL 1.2.x — adapt QuakeSpasm's
     `~/quakespasm/MacOSX/SDL.framework` and `lion:~/sdl-archive/`.
   - **The make invocation** in `build.sh` (env vars, disabled deps,
     renderer/QVM flags) — tune it against what the 2013 Makefile actually
     wants.
2. **Then `g3` (10.3.9 SDK)** — the riskiest compile. If it won't build
   against 10.3.9, note it in `MISTAKES.md` and decide: fallback to 1.36, or
   gate G3 out (compile-time) and ship G4+.
3. **Then `lion` (x86_64, clang)** — should be the easiest.
4. **`scripts/build-fat.sh`** → `build/ioquake3-fat`; verify
   `file` shows ppc750 + ppc7400 + x86_64.
5. **Run it for real on one machine** before benching. Distribute baseq3 to a
   target (start with a G4, e.g. quicksilver — copy the pk3s from
   `mini-intel:~/Desktop/quake3/baseq3/` to `<machine>:~/Desktop/quake3/baseq3/`),
   `scripts/deploy.sh quicksilver`, then launch interactively and confirm it
   renders and plays. THEN automate.
6. **Wire benchmarking.** Enumerate the demos in the pk3s (point-release
   `.dm_68` demos live in `pak8.pk3`; `four` is the classic). Pick a canonical
   1–2 demos, confirm `scripts/bench.sh <machine> <demo> 1024x768` parses the
   Q3 fps line from `qconsole.log`, then run `scripts/parallel-bench.sh
   --quick` and finally a full baseline grid via
   `scripts/bench-and-commit.sh "v0 baseline"`.
7. **Tune `scripts/bundle/autoexec-<machine>.cfg`** from the bench evidence —
   the per-machine defaults there are educated guesses, not measured.

**Honesty checks:** Q3A is much heavier than Q1; the **≥20 fps G3 floor is
aspirational** — prove or disprove it by bench, don't assume (`MISTAKES.md`).
Keep `benchmarks/results.csv` as rolling history (never wipe mid-round). Two
commits per phase (code, then `bench:`). Update `CLAUDE.md`/`docs/KNOBS.md` as
facts solidify, and save a project memory once the first binary runs.

Ask me before any plan-level pivot (dropping G3, switching baseline to 1.36,
abandoning the fat binary). Decide-and-ship on implementation details.

---

## Quick status snapshot (as of scaffold creation, 2026-05-26)

- **Source:** `~/quake3`, branch `master` (rooted at `4432a80a`) (last SDL 1.2).
  `main` = upstream HEAD (SDL2/CMake), reference only.
- **Done:** project layout, `CLAUDE.md`, `MISTAKES.md`, all `scripts/` (v0),
  per-machine `autoexec-*.cfg`, `docs/`. baseq3 staged on mini-intel.
- **Not started:** any compile, SDL 1.2 fat dylib, data distribution to other
  machines, demo enumeration, first bench row, `.app` bundle.
