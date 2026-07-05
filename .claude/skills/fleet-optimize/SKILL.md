---
name: fleet-optimize
description: Find and apply the next fps or graphics-quality win for the old-Mac ioquake3 port across the shared bench fleet (G3/Rage128, G4/GeForce2·Radeon9000·9200, Intel-Lion/GMA950, G5/Radeon9600). Re-runnable — each run profiles one target machine class, forms ONE bottleneck-matched hypothesis, implements it cvar-first (then code, gated behind a cvar so one fat binary auto-tunes per machine), benches it safely, keeps or reverts, records it, and says whether more wins remain. Use whenever the user wants more fps, more graphical features, or asks to "optimise/tune" any old Mac.
---

# fleet-optimize — one optimization iteration for the old-Mac fleet

Goal: the best-looking build that stays **playable** on each machine class,
controlled entirely by **cvars from one fat binary** (auto-config by `hw.model`).
This skill runs **one disciplined iteration** — invoke it again to run the next.
It is the optimization *loop*; it uses the build/deploy/bench mechanics, it does
not reinvent them.

## Before you touch anything — read these (they encode hard-won limits)
- `MISTAKES.md` — what already broke. **Never re-chase a recorded negative.**
- `docs/PROFILING.md` — how to profile on real hardware + known hotspots.
- `docs/KNOBS.md` — the exact cvar names and what they do.
- `benchmarks/results.csv` — current per-machine fps (your baseline).
- `scripts/bundle/autoexec-*.cfg` — each machine's shipped config.

## Non-negotiable rules
1. **cvar-first, one fat binary.** Every machine-specific knob is a cvar set in
   `scripts/bundle/autoexec-<arch|machine>.cfg`, never hardcoded. Drop to code
   only when config is exhausted or the win needs it — and then **gate the new
   behaviour behind a cvar / GL-extension check** so the single fat binary still
   serves every machine and self-tunes. This is the whole deployment model.
2. **Bench safely — never wedge a machine.** Use `scripts/safebench.sh <machine>
   <nativeWxH>` only. It runs one ssh session, lets the engine **self-quit**
   (`+set nextdemo quit`), and never KILLs a fullscreen app (that hangs the GPU
   driver until a reboot). Recover a wedged Mac with `ssh <m> '~/bin/qsreboot.sh'`
   and confirm it actually cycles. Don't build g3 + g4 in parallel.
3. **Respect the envelope.** Floors/targets: **G3 ≥ 20 fps, G4/Lion ≥ 60 fps**,
   G5/modern uncapped. Above the floor, **effects > fps** (user preference): prefer
   adding a graphical feature to chasing fps nobody needs.
4. **Measure, don't guess.** A change without a known bottleneck is a guess.
   Profile the target class first; know if it's CPU-bound or fill-bound.
5. **Discipline.** 3 runs, median of 2 & 3; two commits (code, then bench data);
   tag CSV rows `(commit, machine, demo, res)`; **revert any regression**; and
   **record negative results** in `docs/PROFILING.md` so they're never re-tried.

## The loop (one iteration)
1. **ORIENT** — read the baseline (csv) + the machine configs. Pick ONE target
   machine class and a goal: raise fps toward its target, or add a graphical
   feature within its budget.
2. **PROFILE** — where does the frame go on that class? CPU-bound → CPU levers;
   fill-bound → pixel/fill levers. Use the toolbox below; see PROFILING.md.
3. **HYPOTHESIZE** — pick ONE change from the search space, matched to the
   bottleneck AND to what that GPU actually supports (see the class table).
4. **IMPLEMENT** — edit the machine's autoexec cvar (preferred) or the code
   (renderer/sound), gated behind a cvar.
5. **BUILD + DEPLOY** — config only: `scripts/distribute-data.sh` / re-deploy the
   cfg. Code: `scripts/build-fat.sh` (serialized), `scripts/deploy.sh <machine>`,
   sanity-check the slice cpusubtype (`file build/ioquake3-g3` → ppc750, etc).
6. **BENCH** — `scripts/safebench.sh <machine> <nativeWxH>`, 3 runs vs baseline.
   For a graphics change, also grab a screenshot (`scripts/screenshot.sh`) and eyeball it.
7. **EVALUATE** — keep if fps improved, or a feature was added without dropping
   below the floor and it looks right. Otherwise **revert**.
8. **RECORD** — append to `benchmarks/results.csv`; commit (code then bench);
   update KNOBS/PROFILING with what you learned, negatives included.
9. **REPORT** — state the win/loss and whether this class's search space is now
   exhausted. If **every** class has only recorded negatives left → declare done.

## Machine classes — what each supports & where the wins are
| Class (machine) | GPU envelope | Bound by | Best levers |
|---|---|---|---|
| **G3** (yosemite) | Rage 128, 16 MB, **no S3TC, no AltiVec, no multitexture combiners**, GL 1.2, fixed-function | GPU fill + ATI driver (proven) | 16-bit textures/framebuffer, resolution, `r_subdivisions`, **sound mix rate** (`s_sdlSpeed`). Config only — compiler flags proven useless. Buy fill budget (16-bit color) *then* spend it on effects. |
| **G4** (sawtooth GeForce2 MX / quicksilver Radeon 9000 / mini-g4 Radeon 9200) | AltiVec CPU, S3TC, 32–64 MB, register-combiner / fixed-function, no GLSL | mixed | **S3TC compressed textures** (free detail), **CVA/VBO** to cut CPU vertex submission, **AltiVec** in profiled hot loops (mesh xform, sound mix), aniso where fill headroom. |
| **Intel-Lion** (mini-intel GMA 950) | GL 1.4, no GLSL, weak fill, **strong 2-core CPU** | fill at native 1080p | 16-bit framebuffer, S3TC, **vsync** (tearing — done), possibly `r_smp` (2 cores, test carefully). |
| **G5** (imac-g5 Radeon 9600) | DX9-class, S3TC, aniso, AltiVec, fast | most headroom | push aniso, higher internal quality, more effects — least constrained; MAX it. |
| **Modern** (imac-2019 Sequoia) | huge | never the target | reference only — separates CPU-bound from GPU-bound effects. |

Startup `qconsole.log` prints `GL_RENDERER` + the extension list — **read it to
know exactly what a GPU supports** before enabling a code path for it.

## Optimization search space (cheapest → deepest)
**Config / cvar (no rebuild — always try first):**
texture detail (`r_picmip`), **texture bit depth** (`r_texturebits 16` = fill/bandwidth
win), **S3TC** (`r_ext_compressed_textures`, where supported), anisotropy;
framebuffer depth (`r_colorbits`/`r_depthbits 16` — fill win on Rage128/GMA);
lighting (`r_vertexlight`, `r_dynamiclight`, `r_flares`, `r_detailtextures`);
geometry (`r_subdivisions`, `r_lodbias`/`r_lodscale`, `r_fastsky`);
present (`r_swapInterval`/vsync, `com_maxfps`); sound mix rate (`s_sdlSpeed` on
the SDL backend — big G3 CPU win); submission mode (`r_primitives`); threading
(`r_smp` on 2-core machines — historically flaky, gate + test).

**Code (rebuild — when config is exhausted or the win needs it):**
- **Vertex submission architecture** — prefer ARB VBO / compiled vertex arrays
  where the GPU supports it; cuts the per-frame CPU submission churn
  (`gldFreeVertexBuffer`/`gldUpdateDispatch`) seen in profiling. Gate by GPU.
- **AltiVec** the profiled hot loops on ppc7400/G5 (mesh transform, lighting,
  `snd_mix`); verify codegen with `otool -tV`.
- Cut overdraw / tighten culling; remove per-frame allocations in the frame loop.
- Texture upload: 16-bit internal formats; avoid re-upload churn.
- Memory sizing (`com_hunkmegs`) to avoid paging on 128–256 MB machines.
Expose every new behaviour as a cvar → the one fat binary enables it per class.

## Toolbox
**This host (Linux):** read/grep the source (`code/renderer/`, `code/client/`,
`code/qcommon/`, `code/sdl/`); `git log` for prior attempts; cross-build via
`build-fat.sh` (mini-intel).
**On the Macs (analysis):**
- `/usr/bin/sample` (Panther→Lion, no Xcode) — statistical profiler; build a
  `NO_STRIP=1` slice, trigger on the load-complete log line, sample the render
  thread (full recipe in `docs/PROFILING.md`).
- **mini-intel + Xcode (Lion):** Instruments (Time Profiler, System Trace),
  **OpenGL Driver Monitor / OpenGL Profiler** (GL call counts, driver stalls,
  VRAM), `otool -tV` (disasm — verify AltiVec/codegen), `atos` (symbolicate),
  `gcc -pg`/gprof.
- CHUD/Shark on Tiger/Leopard (G4/G5) for deeper PPC profiling if present.

## Stop condition
Declare "no more optimizations" only when, for **every** machine class, the
remaining candidates are all tried-and-recorded negatives (or below the fps noise
floor). Log each negative in `docs/PROFILING.md`/`MISTAKES.md` so future runs of
this skill converge instead of looping.
