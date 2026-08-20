---
name: fleet-optimize
description: Find and apply the next fps or graphics-quality win for the old-Mac ioquake3 port across the shared bench fleet (G3/Rage128, G4/GeForce2·Radeon9000·9200, Intel-Lion/GMA950, G5/Radeon9600). Re-runnable - each run profiles one target machine class, forms ONE bottleneck-matched hypothesis, implements it cvar-first (then code, gated behind a cvar so one fat binary auto-tunes per machine), benches it safely, keeps or reverts, records it, and says whether more wins remain. Use whenever the user wants more fps, more graphical features, or asks to "optimise/tune" any old Mac.
---

# fleet-optimize - one optimization iteration for the old-Mac fleet

Goal: the best-looking build that stays **playable** on each machine class,
controlled entirely by **cvars from one fat binary**. This skill runs **one
disciplined iteration**; invoke it again for the next. It uses the existing
build/deploy/bench mechanics, it does not reinvent them.

## Read first

- `docs/PROFILING.md` - the profiling method, every measured hotspot, and every
  recorded negative. **Never re-chase a recorded negative.**
- `MISTAKES.md` - what already broke.
- `docs/adr/0009` - safe benching, and the hardware that can be wedged.
- `docs/KNOBS.md` - the exact cvar names.
- `benchmarks/results.csv` - your baseline.
- `scripts/bundle/autoexec-*.cfg` - each machine's shipped config.

## Non-negotiable rules

1. **cvar-first, one fat binary.** Every machine-specific knob is a cvar in
   `scripts/bundle/autoexec-<arch|machine>.cfg`, never hardcoded. Drop to code
   only when config is exhausted, and then **gate the new behaviour behind a
   cvar or a GL-extension check** so the one binary still self-tunes.
2. **Bench safely.** `scripts/safebench.sh <machine> <nativeWxH>` only, at
   native resolution. Never KILL a fullscreen app; never build g3 and g4 in
   parallel. See `docs/adr/0009` before touching a bench machine.
3. **Respect the envelope.** Floors: **G3 >= 20 fps, G4/Lion >= 60 fps**, G5 and
   modern uncapped. Above the floor, **effects beat fps**.
4. **Measure, don't guess.** A change without a known bottleneck is a guess.
   Profile the class first; know whether it is CPU-bound or fill-bound.
5. **Discipline.** 3 runs, median of 2 and 3; two commits (code, then bench
   data); tag CSV rows `(commit, machine, demo, res)`; **revert any
   regression**; and **record negative results in `docs/PROFILING.md`**.

## The loop

1. **ORIENT** - read the CSV and the machine configs. Pick ONE machine class and
   one goal: raise fps toward its target, or add a feature within its budget.
2. **PROFILE** - where does the frame go on that class?
3. **HYPOTHESIZE** - ONE change, matched to the bottleneck AND to what that GPU
   actually supports.
4. **IMPLEMENT** - the machine's autoexec cvar by preference, else code behind a
   cvar.
5. **BUILD + DEPLOY** - config only: re-deploy the cfg. Code: `build-fat.sh`
   then `deploy.sh <machine>`.
6. **BENCH** - `safebench.sh`, 3 runs against the baseline. For a graphics
   change also take a `screenshot.sh` and look at it.
7. **EVALUATE** - keep if fps improved, or a feature landed without dropping
   below the floor and it looks right. Otherwise **revert**.
8. **RECORD** - append to `benchmarks/results.csv`; commit code then bench;
   update KNOBS/PROFILING, negatives included.
9. **REPORT** - the win or loss, and whether this class is exhausted.

## Machine classes - what each supports and where the wins are

| Class | GPU envelope | Bound by | Best levers |
|---|---|---|---|
| **G3** (yosemite) | Rage 128, 16 MB, **no S3TC, no AltiVec, no multitexture combiners**, GL 1.2, fixed-function | GPU fill plus the ATI driver (proven) | 16-bit textures/framebuffer, resolution, `r_subdivisions`, **`s_sdlSpeed`**. Config only - compiler flags proven useless. |
| **G4** (sawtooth GeForce2 MX / quicksilver Radeon 9000 / mini-g4 Radeon 9200) | AltiVec CPU, S3TC, 32-64 MB, register combiners, no GLSL | **differs per machine**: quicksilver is CPU/geometry-bound with fill headroom; mini-g4 is fill-rate bound with none | quicksilver: aniso and trilinear are free (both shipped, class exhausted). mini-g4: bandwidth levers measured zero; only overdraw or code wins remain. |
| **Intel-Lion** (mini-intel GMA 950) | GL 1.4, no GLSL, weak fill, **strong 2-core CPU** | fill at native 1080p | 16-bit framebuffer, S3TC, vsync (done), possibly `r_smp` (gate and test). |
| **G5** (imac-g5 Radeon 9600) | DX9-class, S3TC, aniso, AltiVec | GPU at native res, ~60 fps ceiling when maxed | 2x FSAA shipped; the headroom is now spent, so everything left is a trade. |
| **Modern** (imac-2019 Sequoia) | huge | never the target | reference only - separates CPU-bound from GPU-bound effects. |

Startup `qconsole.log` prints `GL_RENDERER` and the extension list. **Read it
before enabling a code path for a GPU.**

## Search space (cheapest to deepest)

**Config / cvar, always try first:** texture detail (`r_picmip`), bit depth
(`r_texturebits 16`), S3TC (`r_ext_compressed_textures`), anisotropy;
framebuffer depth (`r_colorbits`/`r_depthbits 16`); lighting (`r_vertexlight`,
`r_dynamiclight`, `r_flares`, `r_detailtextures`); geometry (`r_subdivisions`,
`r_lodbias`/`r_lodscale`, `r_fastsky`); present (`r_swapInterval`,
`com_maxfps`); sound mix rate (`s_sdlSpeed`); submission mode (`r_primitives`);
threading (`r_smp`, historically flaky).

**Code, when config is exhausted:** cut overdraw and tighten culling; remove
per-frame allocations in the frame loop; 16-bit internal texture formats and
less upload churn; `com_hunkmegs` sizing to avoid paging on 128-256 MB machines.
Expose every new behaviour as a cvar.

**Already rejected on measurement - do not propose these again:** ARB VBO
submission, wider AltiVec, bot-skin pre-caching, PPC compiler flags, 4x FSAA on
the Radeon 9600, texture-bandwidth levers on mini-g4. All are in
`docs/PROFILING.md` with numbers.

## Toolbox

**This host (Linux):** read and grep the source (`code/renderer/`,
`code/client/`, `code/qcommon/`, `code/sdl/`); `git log` for prior attempts;
cross-build with `build-fat.sh`. There is no `lipo` here - it runs on the mini.

**On the Macs:** `/usr/bin/sample` (Panther through Lion, no Xcode) - build a
`NO_STRIP=1` slice, trigger on the load-complete log line, sample the render
thread; full recipe in `docs/PROFILING.md`. On mini-intel with Lion's Xcode:
Instruments (Time Profiler, System Trace), OpenGL Driver Monitor / OpenGL
Profiler, `otool -tV` to verify codegen, `atos`, `gcc -pg`/gprof. CHUD/Shark on
Tiger and Leopard if present.

## Stop condition

Declare "no more optimizations" only when, for **every** machine class, the
remaining candidates are tried-and-recorded negatives or below the fps noise
floor. Log each negative so future runs converge instead of looping.
