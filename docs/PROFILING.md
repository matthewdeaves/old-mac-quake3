# Profiling the PPC fleet

How we find CPU hotspots on the old Macs, and what we've found.

## Method: `sample` on real hardware (no Xcode needed)

Apple's lightweight statistical profiler `/usr/bin/sample` ships on Panther and
Tiger and attaches to a running process — no Xcode, no instrumentation rebuild.
It needs **symbols**, so profile a **non-stripped** build:

```
# cross-build a non-stripped g3 slice on mini-intel (adds NO_STRIP=1)
ssh mini-intel 'cd quake3; SDK=/Developer/SDKs/MacOSX10.3.9.sdk
  PLATFORM=darwin ARCH=ppc CC=/usr/bin/gcc-4.0 \
  CFLAGS="-isysroot $SDK -arch ppc750 -mcpu=750 -mmacosx-version-min=10.3 -O3" \
  NO_STRIP=1 BUILD_CLIENT=1 BUILD_SERVER=0 BUILD_GAME_SO=0 BUILD_GAME_QVM=0 \
  USE_RENDERER_DLOPEN=0 USE_CURL=0 USE_OPENAL=0 USE_CODEC_VORBIS=0 USE_LOCAL_HEADERS=1 \
  make -j2'
# -> build/release-darwin-ppc/ioquake3.ppc has ~2460 ppc750 text symbols
```

(The normal `build.sh` output is stripped only on `make install`; but the DMG/app
path does strip, so build a dedicated NO_STRIP binary for profiling.)

**Sample the RENDER phase, not the load.** The G3 map load (`CL_InitCGame`) takes
~12 s and dwarfs everything; a naive warmup catches JPEG decode / `inflate` /
`R_CreateImage`, not the frame loop. Trigger on the load-complete log line:

```
# launch timedemo, wait for "CL_InitCGame:" in qconsole.log, +3 s, then sample
./ioquake3-prof ... +set logfile 2 +set timedemo 1 +demo four &
# poll qconsole.log for "CL_InitCGame:"  (the bot frag/obituary lines = playing)
/usr/bin/sample $PID 16 10 -file /tmp/prof.txt
```

Analyse the call graph by thread (`Thread_*` roots) and the "Sort by top of
stack" leaf-leaders. The main render thread is the one under `SDL_main →
Com_Frame`.

## Findings — yosemite (G3 449 MHz, Rage 128), demo four @ 640×480

Steady-state, main thread `Com_Frame 1402 → CL_Frame 1376`:

| Subsystem | self-samples | share | notes |
|---|---|---|---|
| **Sound mix** (`S_Update_`/`S_PaintChannelFrom16_scalar`) | ~407 | **~29%** | scalar (no AltiVec on G3); 8-bot FFA mixes many channels. **#1 lever.** |
| Render backend (`RB_Surface*`, `RB_StageIteratorGeneric`) | ~180 | ~13% | MD3 mesh + BSP face + patch-grid tessellation + GL submit |
| GL driver (`gldFreeVertexBuffer`, `gldUpdateDispatch`, memcpy) | ~130 | ~9% | ATI driver vertex-buffer churn |
| Render frontend (`R_AddWorldSurfaces`, `R_RecursiveWorldNode`, cull) | ~96 | ~7% | BSP walk + `BoxOnPlaneSide` |
| GPU swap wait (`CGLFlushDrawable`) | ~33 | ~2% | **small** → confirms CPU-bound at 640×480 |

Key takeaways:
- **Sound, not graphics, is the biggest CPU cost on the G3.** Lower the SDL mix
  rate via **`s_sdlSpeed 11025`** (NOT `s_khz` — that's a no-op on this backend,
  code/sdl/sdl_snd.c) to ~halve the scalar mix work. See KNOBS / autoexec.
- At 640×480 the GPU swap-wait is tiny → genuinely CPU-bound, so CPU wins move
  fps here. At 1024×768 the G3 is fill-bound (see [[KNOBS]]) and CPU wins instead
  protect the floor during heavy combat.
- `glgProcessColor` / texture upload churn appears whenever the demo streams new
  bot skins — a load cost, mitigated by picmip and (where supported) compression.

## Negative result: PPC compiler flags don't help (2026-06-29)

Tested `-funroll-loops -fomit-frame-pointer` on top of the stock darwin-ppc
`-O3 -ffast-math -falign-loops=16`, A/B on yosemite (demo four):
- shipped 800×600 effects (fill-bound): 22.3 → 22.2 fps (noise)
- 640×480 vertexlight1 (CPU-bound):     55.5 → 56.0 fps (noise, +1%)

So compiler flags buy nothing on the G3 — its bottleneck is GPU fill + the ATI
GL driver (gldFreeVertexBuffer/gldUpdateDispatch), not PPC integer/FP compute
(which `-O3` already handles). Don't re-chase this. The real G3 levers were all
config: picmip, r_vertexlight, resolution, and s_sdlSpeed (sound rate).

## Findings — quicksilver (G4 733 MHz, Radeon 9000), demo four @ native 1680×1050

**The G4 is CPU/geometry-bound at native res, with fill headroom to spare.**
Inferred from real bench numbers, not a profile: quicksilver did ~44 fps @1024×768
max-quality and **38.9 fps @1680×1050** shipped-effects — i.e. **2.24× the pixels
cost only ~12% fps**. A fill-bound machine would have fallen to ~20 fps (fps ∝
1/pixels). So at native res the Radeon 9000 has plenty of fill left; **fps wins
come from CPU levers, and lowering fill (16-bit textures/framebuffer, picmip,
resolution) would buy almost nothing while hurting looks** — don't chase them here.

**Config-level CPU levers are nearly exhausted on the G4:**
- **CVA is already on.** `r_ext_compiled_vertex_array` defaults to 1 and the
  Radeon exposes `GL_EXT_compiled_vertex_array`, so vertex submission already uses
  locked arrays — no free win there.
- **Sound is already AltiVec-vectorized.** Unlike the scalar G3, the G4 uses
  `S_PaintChannelFrom16_altivec` (snd_mix.c, gated by `com_altivec 1` on the
  ppc-altivec build), so `s_sdlSpeed 11025` gives a *smaller* win than the G3's.
  Still positive and **zero visual cost** (audio only): **38.9 → 41.1 fps (+2.2,
  +5.7%)**, worst-frame 84→81 ms. Shipped on quicksilver (2026-07-05). This is
  the last free-on-looks config CPU lever.

**Reaching the ≥45 fps target while keeping the best-looking config now requires
CODE-level CPU wins, or a small geometry trade:**
- Untested-but-promising: **ARB VBO** vertex submission (beyond CVA) and **wider
  AltiVec** in the mesh-transform / shading hot loops (the render backend +
  `gldUpdateDispatch` churn that dominated the G3 frame after sound). Gate behind
  a cvar so the one fat binary self-tunes.
- Config trade with a looks cost (measure before shipping): `r_subdivisions`
  8→12 coarsens curve tessellation (a per-frame CPU + submission cut) — only take
  it if the blockier curves are acceptable at 1680×1050 and the fps is needed.
- Since the G4 has fill to spare, once fps clears 45 the spare fill can be spent
  on a looks feature (anisotropic filtering — the code path is GPU-gated and the
  Radeon supports it up to 16×; currently off on quicksilver as "too costly," a
  claim the fill-headroom data suggests is worth re-testing).

**Anisotropic filtering is FREE on quicksilver — the "too costly" claim was wrong
(2026-07-05).** Tested exactly this, config-only, aniso the ONLY variable (all
other effect cvars held at the shipped values, via `com_archAutoexec 0` + EXTRA,
demo four @ native 1680×1050, vsync off):
| aniso | fps (3 runs) | worst ms | verdict |
|---|---|---|---|
| off | 41.1 / 41.1 / 41.1 | 80 | baseline |
| 8× | 41.1 / 41.1 / 41.1 | 81–83 | free |
| **16×** | **41.0 / 41.0 / 41.0** | 80–81 | **SHIPPED** — hardware max, free |
Zero fps cost at any level — exactly the CPU/geometry-bound-with-fill-headroom
prediction: the extra per-fragment texel fetches are fully absorbed because the
GPU isn't the bottleneck at native res. The renderer confirms it engaged
(`...using GL_EXT_texture_filter_anisotropic (max: 16)` in qconsole.log — that
line prints only when aniso is actually enabled). Shipped 16× on quicksilver.
**Trilinear is also FREE on quicksilver — and now SHIPPED (2026-07-05).** Same
method (config-only, `r_textureMode GL_LINEAR_MIPMAP_LINEAR` the only variable,
all shipped cvars held, demo four @ native 1680×1050 vsync off): baseline 41.1 /
41.1 → trilinear 41.1 / 40.9 / 41.0 (median 41.0), worst-frame 81 ms unchanged.
The 0.1 delta is noise — the extra per-fragment mip blend is absorbed by the same
fill headroom that made aniso free. Removes the default `GL_LINEAR_MIPMAP_NEAREST`
mip-band seams and makes the 16× aniso actually effective (aniso samples across
mips). Shipped in `autoexec-quicksilver.cfg`. Config-level looks levers on
quicksilver are now **exhausted** (aniso 16× + trilinear both banked, both free).

### Profiled the quicksilver render thread — VBO is NOT worth it (2026-07-05, MEASURED)

Before committing an iteration to the long-hypothesized code-level **ARB VBO**
submission rework, we finally *profiled* quicksilver (not just inferred it) with
`/usr/bin/sample` on a NO_STRIP ppc7400 slice (recipe above, adapted to the 10.4u
SDK / `-arch ppc7400 -faltivec`), demo four @ native 1680×1050, shipped config,
12 s / 1200 samples of the steady-state render. **The result refuted the VBO
hypothesis.** CPU-active leaf leaders (idle `mach_msg_trap` 1509 / `semaphore_
timedwait` 1026 threads excluded — those are the GPU-swap + helper-thread waits):

| Bucket | leaf samples | share of active | key leaves |
|---|---|---|---|
| **GL driver / submission** | ~108 | ~27% | `gldUpdateDispatch` 53, `__memcpy` 17, unsym `0x432*` 22, `gleCompileTCLVertexArray` 5, `gleSetClientEnableFlag` 6, `gldDestroyQuery` 5 |
| **Backend tessellation** | ~103 | ~26% | `RB_SurfaceMesh` 27, `RB_StageIteratorGeneric` 21, `RB_SurfaceFace` 11, `RB_SurfaceGrid` 11, `RB_CalcDiffuseColor` 10, `RB_SurfacePolychain` 10 |
| **Frontend** | ~90 | ~23% | `R_AddWorldSurfaces` 15, `R_RecursiveWorldNode` 13, `R_MarkFragments` 10, `R_ChopPolyBehindPlane` 8, `R_RotateForEntity` 8, cull |
| **Sound** | ~58 | ~15% | `S_PaintChannelFrom16_altivec` 48, `Resampler2::ConvertAltivec` 10 |

**Why VBO fails the cost/benefit bar here — three measured reasons:**
1. **No single dominant hotspot.** Work is spread ~evenly across four buckets, so
   no one change jumps 41→comfortably-past-45. The whole premise of a big code win
   (one fat hotspot to crush) is absent on this machine.
2. **The driver bucket is mostly irreducible.** It's dominated by `gldUpdateDispatch`
   = the ATI *hardware* command dispatch, which happens with client arrays OR VBOs.
   The software-vertex path a VBO would actually eliminate (Apple's `gle*` engine)
   is only ~11 samples — hardware TCL is already doing the transform. VBO can't
   touch the 53-sample `gldUpdateDispatch`.
3. **Q3's opengl1 `tess` pipeline is dynamic by construction** — it rebuilds
   `tess.xyz`/texcoords/colors on the CPU every frame (deforms, dlights, MD3 lerp).
   Only lightmap-lit static world faces (`RB_SurfaceFace`, ~11 samples) are truly
   VBO-cacheable; everything else would still `glBufferData(STREAM)` fresh data
   each frame. A large, risky retrofit for a ~11-sample addressable slice.

And the **"wider AltiVec" half of the old hypothesis is already done**: the MD3
mesh lerp (`LerpMeshVertexes_altivec`, the biggest single backend leaf), marks,
sky, and shade_calc are all AltiVec-vectorized in the stock baseline (gated by
`com_altivec 1`, which the ppc7400 build sets). There is no un-vectorized hot loop
left to convert.

**Conclusion (evidence-based NEGATIVE — do not re-chase):** a streaming/static
VBO retrofit of the opengl1 renderer offers a realistic ~+2–4 fps (within noise of
the ≥45 target) for a large, high-risk change testable only on remote hardware.
It does not clear the bar. quicksilver is **well-balanced and near its efficient
envelope at 41 fps @ native 1680×1050 with a maxed look** (picmip 1, 32-bit, full
shaders, dlights, flares, shadows, 16× aniso, trilinear). Per *effects > fps* and
the fill-headroom finding, the right spend was the free looks features (aniso +
trilinear, both now shipped), not chasing an arbitrary fps number through risky
renderer surgery. The ≥45 target is not worth a VBO rework; treat quicksilver's
optimization search space as **exhausted** barring a new class of idea.

## Findings — mini-g4 (G4 1.25 GHz, Radeon 9200 32 MB), demo four @ native 1680×1050

**Now BENCH-CONFIRMED on hardware (2026-07-05) — 27.5 fps, real GPU.** The machine
was previously "unconfirmed." `GL_RENDERER` = `ATI Radeon 9200 OpenGL Engine`
(HARDWARE — the old "mini-g4 headless = software GL" caveat is about a *headless*
launch; safebench's real-display fullscreen path gets hardware accel, so 27.5 is
a true hw number). hw.model `PowerMac10,1` → `autoexec-mini-g4` auto-config is
correctly wired; all 9 baseq3 pk3s staged.

**This is a DISTINCT bottleneck from quicksilver — fill-rate / overdraw bound, NOT
CPU-bound and NOT bandwidth-bound.** The tell: mini-g4 has a *faster* CPU (1.25
GHz vs quicksilver's 733) yet is *slower* (27.5 vs 41.1 fps) → GPU-limited. And it
is insensitive to texture bandwidth:
| change (only variable, vs shipped) | fps (3 runs) | worst ms | verdict |
|---|---|---|---|
| shipped (picmip 1, 32-bit, dlight 1, aniso 2×) | 27.5 / 27.5 / 27.6 | 138 | baseline |
| 16-bit color+depth+textures | 27.9 / 28.0 / 27.9 | 138 | **NEGATIVE** — noise, don't re-chase |
| picmip 1→2 | 27.9 / 27.9 / 27.9 | 137 | **NEGATIVE** — noise, don't re-chase |
| r_dynamiclight 0 | 30.0 / 30.0 / 30.0 | 138 | marginal (+2.5) but costs glow; NOT shipped |

- **Two texture-bandwidth levers (bit depth AND picmip) both moved fps 0.0** → the
  frame cost is invariant to texel bytes/size, so mini-g4 is **fill-RATE / overdraw
  bound** (fragments/sec), not memory-bandwidth bound. quicksilver's "aniso is
  free" finding therefore does NOT transfer — that was a CPU-bound machine with
  fill headroom; the mini has none.
- **The ~138 ms periodic worst-frame spikes are invariant across EVERY config**
  (bit depth, picmip, dynamic lights) → not a steady-state fill lever. Most likely
  **bot-skin texture-upload stalls** (the 8-bot "four" demo streams new skins as
  bots spawn) — a load cost bleeding into the frame loop, not fixable by these
  cvars.
- **r_dynamiclight 0 is the only lever that moved fps (+2.5, +9%)** but it removes
  the rocket/plasma glow and does NOT fix the spikes → poor effects>fps trade,
  kept OFF the shipped config. Raising mini-g4 fps meaningfully needs a code-level
  win (VBO / overdraw reduction) or a resolution drop (blocked — native-only for
  safe fullscreen on old GPUs). Untested next candidates (all effect trades):
  `cg_shadows 0`, `r_subdivisions` coarser, aniso 2→0 (its fill cost here is
  unmeasured — unlike quicksilver, aniso is NOT presumed free on this fill-bound
  card).

## Findings — imac-g5 (PPC 970 2.0 GHz, Radeon 9600), demo four @ native 1440×900

**The G5 is genuinely ~60 fps GPU-bound at native res when fully maxed — NOT
vsync-capped.** The shipped 1440×900 config (picmip 0, aniso 8, trilinear,
shadows, flares, dlights) benches **60.0 fps with vsync forced OFF**
(`r_swapInterval 0`, 2 clean samples 59.9/60.1). The prior header's "128.9 fps
@1600×1200, well above 100" was stale bring-up spin from before aniso 8 +
trilinear + flares + the 1440×900 move; it never reproduced. So the "reveal the
hidden vsync headroom" hypothesis was **disproven by measurement** — 60 fps is
the real GPU ceiling at this quality, there are no free frames behind vsync.

**But the G5 has no fps floor and effects>fps, so spend the frames it has on
antialiasing — the biggest remaining visual upgrade** (Q3's jagged geometry /
weapon edges are its most dated look). FSAA cost curve, measured @1440×900
vsync-off (`r_ext_multisample`, driven via `SDL_GL_MULTISAMPLE*` at context
creation, sdl_glimp.c:375; CVAR_LATCH → read once at GL init):
| FSAA | fps | avg/worst ms | verdict |
|---|---|---|---|
| off | 60.0 | 16.6 / 52 | baseline |
| **2×** | **34.5** (34.5/34.4) | 29 / 84 | **SHIPPED** — smooth, big edge-quality win |
| 4× | 20.1 | 49.7 / **149** | **REJECTED** — 3× hit, choppy; don't re-chase |

- **Negative — 4× FSAA is too costly on the Radeon 9600.** 60→20 fps (149 ms
  worst frame). MSAA on this R300-class part roughly triples frame cost at 4×;
  2× is the sweet spot (kills the worst jaggies for ~43% cost). Don't re-try 4×.
- **Op note — imac-g5 ssh is flaky under back-to-back benching** (intermittent
  "unreachable" / a launch that writes no fps line, ~1 in 3). It always recovers
  on a short re-poll; not a wedge, no reboot needed. Run samples one at a time and
  re-poll reachability between them. The two June-29 crashlogs on the box are
  stale ssh-launch `NSApplication` aborts (a WindowServer-session hazard of
  launching a Cocoa app over ssh), unrelated to config.
- **Next G5 levers** (headroom is now spent by 2× FSAA, so these are trades, not
  free): 4×-if-a-cheaper-effect-is-dropped; `r_subdivisions 4→2` (finer curves,
  small cost); aniso 8→16 (near-free but marginal perceptually at 1440×900).
