# Review: upstream ioquake3 diff since our pin, for cherry-pickable fixes

Review of 1,817 upstream commits since the 2013 ioquake3 pin, tracked by #17.
The 2026-08-28 reconciliation says nine increments landed; read that status before the original candidates.
Candidate details moved to `docs/RENDERER-CANDIDATES.md`; methods and applied changes remain here.

## Context

> **Summary.** Triage of 1817 upstream ioq3 commits since our pin (2013-01-17) for fixes worth cherry-picking. As of the 2026-08-28 status note, nine increments have landed and all but two of ~55 named candidates are applied or rejected. Read "Status" first; the triage sections keep their 2026-08-23 "not yet" wording as history.
> Sections: Applied so far, Method, What's NOT here, Candidates by confidence, Status, historical notes. Find one with `grep -n '^## ' docs/RENDERER-DIFF-REVIEW.md`.

Reviewed 2026-08-23 against upstream `ioquake/ioq3` at `58839361`
(2026-07-19), diffed from our pin `4432a80a` (2013-01-17). 1817 commits
between the two. Closes the scoping half of issue #17.

Written so this is not re-litigated, and so the non-trivial candidate list
survives past this session. Originally triage only; application state is
tracked below as increments land.

## Applied so far

- Increment 1 (`d35fb252`): tr_bsp.c entity-parse early-stop (`c8c7bb1d`),
  cm_patch.c facets array size (`5e09f20c`), tr_image.c skin alloc both
  sites (`a5fbc1bf`), tr_image_png.c tRNS check (`fda03ee4`). Built fat,
  smoke-tested on yosemite, 26.1 fps, no regression.
- Increment 2 (`9d94ce5b`): shader-parser hardening (`eb73dcb7`,
  `3ec2b02d`, `eeeaf3f1`, `e5f54c58`), flare fixes (`00c1831e`,
  `d526eacd`), rail/lightning overflow check (`cc9072d0`). The
  `SkipBracedSection` signature change also touched dead-code
  `code/rend2/tr_shader.c` mechanically.
- Increment 3 (`eca6aa54`): base sound path (`a167110f`, `57eae5da`,
  `a836c2db` apply-clean; `2ef641b9`, `84daa282` hand-ported, our
  resamplers are mono and our transfer uses `out_mask` not `%`). OpenAL
  cluster dropped as dead code, see above.
- Increments 2+3 verified together: 5-slice fat rebuilt (lipo-asserted),
  deployed to yosemite, safebench 800x600 demo four: 26.2 fps, crashlogs=0,
  against the 26.1 pre-increment baseline. G4-class run via the Jenkins
  bench-quake3-mini-g4 job; result in the #17 comment trail.
- Increment 4 (`4f1e8cb5`): files.c/cvar.c security cluster, all ten
  commits (six apply-clean, four hand-ported; the fs_game trio taken as
  its settled combined state, not piecemeal). Verified: fat rebuilt,
  yosemite 26.1 fps crashlogs=0, mini-g4 75.0 via Jenkins, and the
  fs_game gate tested in the REFUSING direction on this workstation
  (arm64 + x86_64 slices): '../evil' is refused at FS_Startup. Known
  limitation: an init-time ERR_DROP exited via segfault, pre-existing
  error-path fragility, filed as #36 and fixed the same day (`c2fa4e50`,
  CL_ClearMemory NULL guard).
- Increment 6 (`40e10ce3`): seventeen ranked renderer fixes, 12 apply-clean
  and 5 hand-ported (command buffer keeps our SMP shape, libjpeg setjmp
  recovery, MD3/MDR bounds, grid2 guard, texCoords init; IQM hunks skipped,
  our IQM predates them). Verified: yosemite 26.1 fps crashlogs=0, mini-g4
  77.6/78.2/77.7 (within the increment-5 band), screenshots vs baseline
  identical apart from random gib scatter.
- Increment 5 (`4c29d38e`): nine client/net fixes (91194bfc+ac621642
  snapshot/parse-entities unification including the server side, a18ae32a,
  ebac005c, 0853c85e, 63e6c82f, 8a50e2aa, e9436abf, 3ad427c6). Upstream
  91194bfc carried a stray "gedit" at cl_parse.c:1, dropped. Verified with
  the #36 fix in one build: yosemite 26.1 fps crashlogs=0, mini-g4 via
  Jenkins, refusal path on the bundled app reaches the error dialog.
- Increment 7 (`33e83a11`): float-precision time-math cluster (`30fdd88c`,
  `59b1262b`, `6f0736ce`). shaderTime, floatTime, clampTime, timeOffset
  widened to double; WAVEVALUE, turbulent, and rotate use int64_t;
  animated-image index wrap loop. Verified: yosemite 26.0 fps (runs 1&2
  26.0 vs baseline 26.1), mini-g4 77.7 fps (median of 2&3 77.7 vs baseline
  77.6-78.2), 6 in-demo screenshots matching baseline. Zero performance or
  visual regression.
- Increment 9 (`750a15c8`): filesystem crash cluster, six commits
  (`67d9ecd0`, `90c98c90`, `c7500bb2`, `4ea0eebf`, `26780805`, `c755d75a`).
  Verified: 5-slice fat rebuilt, lipo-asserted, yosemite-tiger (G3, Tiger)
  30.5 fps crashlogs=0 (band 29.85-30.6), mini-g4 79.7 fps crashlogs=0
  (band 77.6-80.0) - no regression, as expected from six error-path fixes.
- Increment 8 (`cc0b3e68`): msg/huffman/patch/info cluster (`d2b1d124`,
  `1e309787`, `3a702ded`, `9f294ce5`, `b4ad5a84`, `7e2aa2c6`, `ee2541ef`,
  `077ab4cb`, `a6df505d`, `5c1091b4`, `c52e35bc`, `a6f949c8`, `9c29b25a`,
  `b3223dcf`). MSG_ReadBits/MSG_WriteBits buffer overflow checks, maxoffset
  bounds in Huffman receiver/transmitter, q3msgboom fix in string reading,
  MSG_ReadDeltaKey mask fix, CM_AddFacetBevels / CM_EdgePlaneNum guards,
  Q_IsColorString signedness guard, Info_ key handling, Q_rand unsigned
  wrapping math. Verified: yosemite 26.0-26.2 fps (runs 1&2 25.8/26.2),
  mini-g4 78.3 fps (median of 2&3 78.0/78.6), screenshots match baseline.

## Method

- Cloned upstream into a scratch dir, confirmed `4432a80a` is a real ancestor
  commit in its history (it is — our repo forked from exactly that commit).
- Diffed `code/renderer` (-> `code/renderergl1` + `code/renderercommon` after
  upstream's 2015 split, `f6fb9eb6`), `code/qcommon`, and `code/client`
  between the pin and upstream HEAD, with rename detection (`-M40%`) so the
  renderer split reads as moved files with small real diffs, not as
  wholesale deletes/adds.
- `code/renderergl2` (upstream's separate GLSL/shader-based backend, added
  after the split) is entirely out of scope — it is not a fix to the
  renderer we have, it is a different renderer we do not carry.
- Excluded throughout: Windows/Linux-only code, SDL2-only code (we are
  pinned to SDL 1.2, ADR 0001), anything requiring GL 2.0+/GLSL on the
  PowerPC/old-Intel fixed-function GPUs in the fleet, and pure
  reorg/rename/cleanup with no behavior change.
- Three parallel passes: `code/qcommon` core files, `code/client` (net +
  sound), `code/renderergl1`/`renderercommon`. Each file's real changes were
  read via `git log`/`git show` on the commits that looked substantive, not
  just the diffstat.
- A handful of the highest-confidence findings were spot-checked directly
  against our current tree (not just the upstream diff) below.

## What's NOT here

Everything upstream changed that assumes: SDL2, GL 2.0+/GLSL, Windows or
Linux syscalls, VoIP codec swap (Speex->Opus - we still vendor Speex), IQM
model rework (not deeply reviewed - stock baseq3 doesn't use IQM, low
priority for a follow-up), MDR/RTCW-style skeletal models (unused format),
PVR/PowerVR texture loading (no PowerVR hardware in the fleet), the VM JIT
files for x86_64/ARM/SPARC (`vm_x86_64*.c`, `vm_armv7l.c`, `vm_sparc*`,
`vm_powerpc*`) - irrelevant because every slice except i386 runs native
dylibs, not a QVM JIT (ADR 0008), and i386's own JIT is `vm_x86.c`, barely
touched upstream.

Also not applicable: every `-faltivec`-isolation commit (`5909b9a1` and its
`tr_altivec.c`/`snd_altivec.c` split). Upstream needed it to let one fat PPC
binary detect AltiVec at runtime; we already avoid that problem by compiling
`ppc750` and `ppc7400` as separate slices (ADR 0002/0003), so the failure
mode it fixes cannot occur here. And every `GL_CLAMP`/`haveClampToEdge`
fallback commit - those patch a runtime GL-version-gated code path our tree
never had; we hardcode `GL_CLAMP_TO_EDGE` unconditionally and it already
works on every GPU in the fleet.

## Candidates, by confidence

See `docs/RENDERER-CANDIDATES.md`.

## Status (2026-08-28): reconciled against increments 1-9, most of this is done

The two sections below are the original triage from 2026-08-23, before any
increment existed. They read as if nothing had been applied yet, which is
now false - nine increments have landed since (see "Applied so far" above
and `BUGFIXES.md`). Kept for the historical record rather than rewritten,
but do not trust their "not yet"/"suggested order" framing; read this
status note first.

An agent-assisted reconciliation (2026-08-28) cross-checked every named
candidate in the "Candidates, by confidence" section above against
`BUGFIXES.md` and a fresh read of current source. Result: of ~55 named
upstream hashes, all but eight had already landed across increments 1-8.
Increment 9 (`750a15c8`) took six of the remaining eight (see `BUGFIXES.md`).

**Genuinely still open, after increment 9:**
1. `2d45e570` - `FS_Seek` `ERR_FATAL`s on negative offset / `FS_SEEK_END`
   for pk3-contained files rather than supporting it. Loud and safe (not a
   silent-corruption bug), but a real fix means re-implementing backward
   seeks over a zip stream - its own session-sized unit, not taken blind.
2. `313064ba` - `+seta`/`+sets`/`+setu`/multi-token `+set` on the command
   line are still mishandled (`Com_StartupVariable`/`Com_AddStartupCommands`,
   `code/qcommon/common.c`). Needs checking against every shipped script's
   own `+set` usage first, per this doc's original flag - not done blind,
   this port's tooling leans heavily on `+set overrides` and a behavior
   change here is exactly the kind of thing that silently breaks a bench
   script rather than the game.

**Not applicable, confirmed still correct to skip:** the entire
`snd_openal.c` cluster (`USE_OPENAL=0` on every slice, dead code),
`RB_DrawSun()` (`0c3ec34d`, a feature-enable, not a correctness bug -
worth its own try per "effects beat fps above the floor" if pursued, not
this ticket's scope), the `DEF_COMZONEMEGS`/`MIN_COMHUNKMEGS` raise
(rejected for the G3 RAM budget, still rejected), `tr_model_iqm.c` (still
not deeply reviewed - no increment has touched it, stock baseq3 ships no
IQM content, still low priority).

## What this pass did NOT do (2026-08-23, historical)

- **Nothing was applied, built, or benched.** Every item above is a
  candidate, not a commit.
- `tr_model_iqm.c` was not deeply reviewed (not rename-matched by git, heavy
  rework, low priority given stock baseq3 doesn't use IQM).
- The `snd_openal.c` cluster and the float-precision cluster were identified
  but not individually verified line-for-line against our current tree.
- No commit here has been checked for whether it still applies cleanly on
  top of this port's own 154 commits of local changes (per-arch config
  system, native dylib loading, watchlink, etc).

## Next steps (2026-08-23, historical - superseded by the status note above)

Per the ticket's own scope warning, this is deliberately a triage, not an
implementation pass. Suggested order for whoever picks this up next:
1. The five spot-checked, confirmed-present bugs above (tr_bsp.c entity
   parsing, cm_patch.c array size, tr_image.c skin alloc, msg.c bit-reader
   bounds, tr_image_png.c tRNS check) are the safest first patch: all are
   isolated, zero GL/GPU dependency, and confirmed present by reading our
   actual source, not just inferred from the upstream diff.
2. The shader-parser hardening cluster and the OpenAL cluster are next:
   still isolated per-file, but not yet spot-checked here.
3. The float-precision cluster and the files.c/cvar.c security cluster are
   larger units that should be taken (or not) as wholes.
4. Anything taken gets built and smoke-tested at minimum; anything touching
   a hot path (tr_main.c, tr_shade.c, the command-buffer fix) gets benched
   per ADR 0009 before being called done, not assumed safe because the
   upstream commit message says so.
