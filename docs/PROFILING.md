# Profiling and measured results

Every measured number, per machine class, including the negatives. **Never
re-chase a recorded negative.** Method first, then findings.

Live bench rows are in `benchmarks/results.csv`; raw logs in `benchmarks/raw/`.
Bench discipline (3 runs, median of 2 and 3, `com_archAutoexec 0`, native res
only) is in `docs/adr/0009`.

## Method: `sample` on real hardware, no Xcode needed

`/usr/bin/sample` ships on Panther and Tiger and attaches to a running process.
It needs **symbols**, so profile a **non-stripped** build (`NO_STRIP=1`). The
normal `build.sh` output is stripped only on `make install`, but the DMG/app
path does strip, so build a dedicated binary:

```
ssh mini-intel 'cd quake3; SDK=/Developer/SDKs/MacOSX10.3.9.sdk
  PLATFORM=darwin ARCH=ppc CC=/usr/bin/gcc-4.0 \
  CFLAGS="-isysroot $SDK -arch ppc750 -mcpu=750 -mmacosx-version-min=10.3 -O3" \
  NO_STRIP=1 BUILD_CLIENT=1 BUILD_SERVER=0 BUILD_GAME_SO=0 BUILD_GAME_QVM=0 \
  USE_RENDERER_DLOPEN=0 USE_CURL=0 USE_OPENAL=0 USE_CODEC_VORBIS=0 USE_LOCAL_HEADERS=1 \
  make -j2'
# -> build/release-darwin-ppc/ioquake3.ppc, ~2460 ppc750 text symbols
```

For a ppc7400 profile, adapt to `-arch ppc7400 -faltivec`.

**Sample the RENDER phase, not the load.** The G3 map load (`CL_InitCGame`)
takes ~12 s and dwarfs everything; a naive warmup catches JPEG decode,
`inflate` and `R_CreateImage`, not the frame loop. Trigger on the load-complete
log line:

```
./ioquake3-prof ... +set logfile 2 +set timedemo 1 +demo four &
# poll qconsole.log for "CL_InitCGame:" (bot frag/obituary lines = playing), +3 s
/usr/bin/sample $PID 16 10 -file /tmp/prof.txt
```

Analyse by thread (`Thread_*` roots) and by "Sort by top of stack" leaf leaders.
The main render thread is the one under `SDL_main -> Com_Frame`. Exclude idle
`mach_msg_trap` and `semaphore_timedwait` threads - those are GPU-swap and
helper-thread waits.

Startup `qconsole.log` prints `GL_RENDERER` and the extension list. Read it
before enabling any code path for a GPU.

---

## yosemite (G3 449 MHz, Rage 128 16 MB) - CPU-bound at 640x480, fill-bound above

Steady state, demo `four` @640x480, main thread `Com_Frame 1402 -> CL_Frame 1376`:

| Subsystem | self-samples | share | notes |
|---|---|---|---|
| **Sound mix** (`S_Update_`, `S_PaintChannelFrom16_scalar`) | ~407 | **~29%** | scalar, no AltiVec on a 750; 8-bot FFA mixes many channels. **#1 lever.** |
| Render backend (`RB_Surface*`, `RB_StageIteratorGeneric`) | ~180 | ~13% | MD3 mesh + BSP face + patch-grid tessellation + GL submit |
| GL driver (`gldFreeVertexBuffer`, `gldUpdateDispatch`, memcpy) | ~130 | ~9% | ATI driver vertex-buffer churn |
| Render frontend (`R_AddWorldSurfaces`, `R_RecursiveWorldNode`, cull) | ~96 | ~7% | BSP walk + `BoxOnPlaneSide` |
| GPU swap wait (`CGLFlushDrawable`) | ~33 | ~2% | **small**, confirming CPU-bound at 640x480 |

**Sound, not graphics, is the biggest CPU cost on the G3.** The SDL backend's
mix rate is **`s_sdlSpeed`**, NOT `s_khz` - `s_khz` is a no-op on this backend
(`code/sdl/sdl_snd.c`). `s_sdlSpeed 11025` roughly halves the scalar mix work:
**640x480 went 47.7 -> 54.6 fps**, against a sound-off ceiling of 61.0.

`glgProcessColor` and texture-upload churn appear whenever the demo streams new
bot skins - a load cost, mitigated by picmip and, where supported, compression.

### Texture detail and the VRAM wall (clean A/B, 2026-06-29)

Rage 128, 16 MB, **no S3TC** so textures are uncompressed. Demo `four`
@1024x768, varying only `r_picmip` by cmdline `+set`:

| r_picmip | fps | notes |
|---|---|---|
| 3 (1/8 res) | 28.2 | the "very basic" look |
| **1 (1/2 res)** | **27.0** | nearly free vs picmip 3, so fill-bound between 3 and 1 |
| 0 (full res) | 20.8 | hits the 16 MB VRAM wall - **211 ms** frame spikes, texture thrash |

**picmip 1 is the sweet spot.** Between picmip 3 and 1 the G3 is fill-bound and
texture detail is nearly free; picmip 0 is gated by VRAM, not fill.

### Effects restored at 800x600

The survival setting `r_vertexlight 1` had collapsed every map shader to one
flat stage: no lit or animated walls, no portals, no glows. Shipped instead:
`r_vertexlight 0` (lightmaps plus full shaders) + `r_dynamiclight 1` +
`r_flares 1` at **800x600 = 22.1 fps**, clearing the 20 floor. Screenshots
confirm proper lighting and rocket glow.

### NEGATIVE - PPC compiler flags buy nothing (2026-06-29)

`-funroll-loops -fomit-frame-pointer` on top of the stock darwin-ppc
`-O3 -ffast-math -falign-loops=16`, A/B on yosemite, demo `four`:

- shipped 800x600 effects (fill-bound): 22.3 -> 22.2 fps (noise)
- 640x480 vertexlight 1 (CPU-bound): 55.5 -> 56.0 fps (noise, +1%)

The G3's bottleneck is GPU fill plus the ATI GL driver
(`gldFreeVertexBuffer`/`gldUpdateDispatch`), not PPC integer/FP compute, which
`-O3` already handles. **Do not re-chase.** The real G3 levers were all config:
picmip, `r_vertexlight`, resolution and `s_sdlSpeed`.

---

## quicksilver (G4 733 MHz, Radeon 9000) - CPU/geometry-bound with fill headroom

Inferred from bench numbers first: ~44 fps @1024x768 max quality against
**38.9 fps @1680x1050** shipped effects - **2.24x the pixels for ~12% fps**. A
fill-bound machine would have fallen to ~20 fps. So lowering fill (16-bit
textures or framebuffer, picmip, resolution) would buy almost nothing here while
hurting looks. **Don't chase fill levers on this machine.**

Config-level CPU levers are effectively exhausted:

- **CVA is already on.** `r_ext_compiled_vertex_array` defaults to 1 and the
  Radeon exposes `GL_EXT_compiled_vertex_array`.
- **Sound is already AltiVec-vectorized.** Unlike the G3's scalar path, the G4
  uses `S_PaintChannelFrom16_altivec` (`snd_mix.c`, gated by `com_altivec 1` on
  the ppc7400 build), so `s_sdlSpeed 11025` gives a smaller win than the G3's -
  still positive and at **zero visual cost**: **38.9 -> 41.1 fps (+2.2, +5.7%)**,
  worst frame 84 -> 81 ms. Shipped 2026-07-05. That was the last free-on-looks
  config CPU lever.

### Anisotropic filtering is FREE here - the "too costly" claim was wrong (2026-07-05)

Config-only, aniso the only variable, all other effect cvars held at shipped
values via `com_archAutoexec 0` + EXTRA, demo `four` @native 1680x1050, vsync
off:

| aniso | fps (3 runs) | worst ms | verdict |
|---|---|---|---|
| off | 41.1 / 41.1 / 41.1 | 80 | baseline |
| 8x | 41.1 / 41.1 / 41.1 | 81-83 | free |
| **16x** | **41.0 / 41.0 / 41.0** | 80-81 | **SHIPPED**, hardware max, free |

Exactly the CPU-bound-with-fill-headroom prediction: the extra per-fragment
texel fetches are fully absorbed. The renderer confirms it engaged -
`...using GL_EXT_texture_filter_anisotropic (max: 16)` prints in `qconsole.log`
only when aniso is actually enabled.

### Trilinear is also FREE, and shipped (2026-07-05)

Same method, `r_textureMode GL_LINEAR_MIPMAP_LINEAR` the only variable: baseline
41.1 / 41.1 -> trilinear 41.1 / 40.9 / 41.0 (median 41.0), worst frame 81 ms
unchanged. The 0.1 delta is noise. It removes the default
`GL_LINEAR_MIPMAP_NEAREST` mip-band seams and makes the 16x aniso actually
effective, since aniso samples across mips. **Config-level looks levers on
quicksilver are now exhausted.**

### NEGATIVE - ARB VBO is not worth it (2026-07-05, MEASURED)

Profiled with `sample` on a NO_STRIP ppc7400 slice, demo `four` @native
1680x1050, shipped config, 12 s / 1200 samples of steady state. CPU-active leaf
leaders:

| Bucket | leaf samples | share of active | key leaves |
|---|---|---|---|
| **GL driver / submission** | ~108 | ~27% | `gldUpdateDispatch` 53, `__memcpy` 17, unsym `0x432*` 22, `gleCompileTCLVertexArray` 5, `gleSetClientEnableFlag` 6, `gldDestroyQuery` 5 |
| **Backend tessellation** | ~103 | ~26% | `RB_SurfaceMesh` 27, `RB_StageIteratorGeneric` 21, `RB_SurfaceFace` 11, `RB_SurfaceGrid` 11, `RB_CalcDiffuseColor` 10, `RB_SurfacePolychain` 10 |
| **Frontend** | ~90 | ~23% | `R_AddWorldSurfaces` 15, `R_RecursiveWorldNode` 13, `R_MarkFragments` 10, `R_ChopPolyBehindPlane` 8, `R_RotateForEntity` 8, cull |
| **Sound** | ~58 | ~15% | `S_PaintChannelFrom16_altivec` 48, `Resampler2::ConvertAltivec` 10 |

Three measured reasons it fails the bar:

1. **No single dominant hotspot.** Work is spread nearly evenly across four
   buckets, so no one change jumps 41 fps past 45.
2. **The driver bucket is mostly irreducible.** It is dominated by
   `gldUpdateDispatch`, the ATI *hardware* command dispatch, which happens with
   client arrays or VBOs alike. The software-vertex path a VBO would actually
   eliminate (Apple's `gle*` engine) is only ~11 samples; hardware TCL is
   already doing the transform.
3. **Q3's opengl1 `tess` pipeline is dynamic by construction** - it rebuilds
   `tess.xyz`, texcoords and colors on the CPU every frame (deforms, dlights,
   MD3 lerp). Only lightmap-lit static world faces (`RB_SurfaceFace`, ~11
   samples) are truly VBO-cacheable.

The **"wider AltiVec" half of the old hypothesis is already done**: the MD3 mesh
lerp (`LerpMeshVertexes_altivec`, the biggest single backend leaf), marks, sky
and shade_calc are all AltiVec-vectorized in the stock baseline (gated by
`com_altivec 1`, which the ppc7400 build sets). There is no un-vectorized hot
loop left to convert.

**Conclusion, evidence-based NEGATIVE: do not re-chase.** A streaming/static VBO
retrofit offers a realistic ~+2 to +4 fps, within noise of the >= 45 target, for
a large high-risk change testable only on remote hardware. quicksilver is
well-balanced and near its efficient envelope at 41 fps @native 1680x1050 with a
maxed look (picmip 1, 32-bit, full shaders, dlights, flares, shadows, 16x aniso,
trilinear). Treat its optimization search space as **exhausted** barring a new
class of idea.

### Native game dylib vs the PPC QVM JIT - +1.3%, MEASURED

See `docs/adr/0008` for the numbers and why the win is small (the QVM is already
JIT-compiled to native PowerPC; there is no interpreter on the fleet). Recorded
here so it is never re-hyped as a "~5% interpreter win".

### NEGATIVE - bot-skin pre-caching has nothing to pre-cache (2026-07-05, MEASURED)

Hypothesis: the recurring frame-time spikes are bot skin/model textures uploaded
to VRAM on first sighting, fixable by pre-caching at map load. Per-frame
durations (`cl_timedemoLog`) confirmed the spikes are real and recurring, not a
one-time load: **5.6% of frames >= 50 ms**, in bursts throughout the demo
(frames 254-257, 332-342, 414-421, 683-693, 1069-1085 and more), each a visible
stutter against the 24 ms average.

Cold-vs-warm-VRAM test - play demo `four` twice in one engine session:

| pass | fps | worst | spikes >= 50 ms |
|---|---|---|---|
| 1 (cold VRAM) | 41.1 | 82 ms | 64 |
| 2 (warm VRAM) | 41.4 | 79 ms | 63 |

The two passes are **frame-for-frame identical** (spike-index Jaccard 0.81;
burst @330-344 = `[73,76,73,70,68...]` cold vs `[75,75,72,70,68...]` warm; mean
at spike frames 56.8 vs 55.0 ms). **Only frame 0 improved, 66 -> 38 ms**, the
single genuine load frame.

**Therefore the recurring spikes are NOT texture uploads.** They are per-frame
CPU/render cost on heavy demo scenes - dense geometry, explosions, many entities
- the heavy tail of the same frontend + tessellation + dispatch distribution
above. **Do not build a skin pre-cache.** Smoothing these bursts is the same
CPU-bound renderer problem whose only real lever (VBO) is already rejected.

---

## mini-g4 (G4 1.25 GHz, Radeon 9200 32 MB) - fill-rate / overdraw bound

**Bench-confirmed on hardware 2026-07-05: 27.5 fps @native 1680x1050, real GPU.**
`GL_RENDERER` = `ATI Radeon 9200 OpenGL Engine` (hardware; the old "mini-g4
headless = software GL" caveat is about a *headless* launch, and safebench's
real-display fullscreen path gets hardware acceleration). `hw.model`
`PowerMac10,1` maps to `autoexec-mini-g4` correctly.

**A distinct bottleneck from quicksilver.** The tell: a *faster* CPU (1.25 GHz
vs 733 MHz) yet *slower* (27.5 vs 41.1 fps), so GPU-limited. And it is
insensitive to texture bandwidth:

| change (only variable, vs shipped) | fps (3 runs) | worst ms | verdict |
|---|---|---|---|
| shipped (picmip 1, 32-bit, dlight 1, aniso 2x) | 27.5 / 27.5 / 27.6 | 138 | baseline |
| 16-bit color + depth + textures | 27.9 / 28.0 / 27.9 | 138 | **NEGATIVE**, noise, don't re-chase |
| picmip 1 -> 2 | 27.9 / 27.9 / 27.9 | 137 | **NEGATIVE**, noise, don't re-chase |
| `r_dynamiclight 0` | 30.0 / 30.0 / 30.0 | 138 | marginal (+2.5) but costs glow; NOT shipped |

- **Two texture-bandwidth levers, bit depth and picmip, both moved fps by 0.0**,
  so the frame cost is invariant to texel bytes and size: **fill-RATE / overdraw
  bound** (fragments per second), not memory-bandwidth bound. quicksilver's
  "aniso is free" finding therefore does **not** transfer - that was a CPU-bound
  machine with fill headroom; the mini has none, and aniso is **not** presumed
  free here.
- **The ~138 ms periodic worst-frame spikes are invariant across every config**
  tested, so not a steady-state fill lever.
- `r_dynamiclight 0` is the only lever that moved fps (+2.5, +9%) but removes
  rocket/plasma glow and does not fix the spikes - a poor effects-beat-fps trade,
  kept off the shipped config.

Raising mini-g4 fps meaningfully needs a code-level win (overdraw reduction) or a
resolution drop, which is blocked: native-only is the safe fullscreen on these
GPUs (`docs/adr/0009`). Untested candidates, all effect trades: `cg_shadows 0`,
coarser `r_subdivisions`, aniso 2 -> 0.

---

## imac-g5 (PPC 970 2.0 GHz, Radeon 9600) - ~60 fps GPU-bound at native, not vsync-capped

The shipped 1440x900 config (picmip 0, aniso 8, trilinear, shadows, flares,
dlights) benches **60.0 fps with vsync forced off** (`r_swapInterval 0`, two
clean samples 59.9 / 60.1). An earlier "128.9 fps @1600x1200, well above 100"
figure was stale bring-up spin from before aniso 8 + trilinear + flares + the
1440x900 move; it never reproduced. **The "reveal the hidden vsync headroom"
hypothesis is disproven by measurement** - 60 fps is the real GPU ceiling at this
quality.

The G5 has no fps floor and effects beat fps, so the frames it has were spent on
antialiasing, Q3's most dated look being jagged geometry and weapon edges. FSAA
cost curve, @1440x900 vsync off (`r_ext_multisample`, driven via
`SDL_GL_MULTISAMPLE*` at context creation, `sdl_glimp.c:375`; `CVAR_LATCH`, read
once at GL init):

| FSAA | fps | avg/worst ms | verdict |
|---|---|---|---|
| off | 60.0 | 16.6 / 52 | baseline |
| **2x** | **34.5** (34.5 / 34.4) | 29 / 84 | **SHIPPED**, big edge-quality win |
| 4x | 20.1 | 49.7 / **149** | **REJECTED**, 3x hit, choppy |

**NEGATIVE - 4x FSAA is too costly on the Radeon 9600.** 60 -> 20 fps, 149 ms
worst frame. MSAA on this R300-class part roughly triples frame cost at 4x; 2x is
the sweet spot, killing the worst jaggies for ~43% cost. **Don't re-try 4x.**

Remaining G5 levers are trades, not free, now that 2x FSAA spent the headroom:
4x if a cheaper effect is dropped; `r_subdivisions` 4 -> 2 (finer curves, small
cost); aniso 8 -> 16 (near-free but marginal perceptually at 1440x900).

**Op note:** the two June-29 crashlogs on the box are stale ssh-launch
`NSApplication` aborts, a WindowServer-session hazard of launching a Cocoa app
over ssh, unrelated to config. See `docs/adr/0009` for the ssh flakiness.

---

## mini-intel (Core 2 Duo, GMA 950, Lion) - fill-bound at 1080p

56.9 fps @native 1920x1080 on the shipped config (2026-07-05); 42.0 fps on the
bench harness config after the OS-floor change (`docs/adr/0002`).

**Tearing fix.** Horizontal tear lines drifted down every screen, menu and
in-game. The config set `com_maxfps 0` but never enabled vsync, so
`r_swapInterval` sat at the engine default 0. Set **`r_swapInterval 1`** in
`autoexec-mini-intel.cfg`; ~57 fps is below the 60 Hz refresh so it costs no
fps. Deployed and user-confirmed.

Untested candidate: `r_smp` on the two cores - historically flaky, gate and test
carefully.

---

## Native-resolution confirmations (2026-07-05, deployed `ee6ed80b` configs, vsync-off bench)

| Machine | Native res | Confirmed fps | Target |
|---|---|---|---|
| yosemite (G3) | 800x600 | **22.2** | >= 20, clears the floor |
| quicksilver (G4) | 1680x1050 | **39.4** | >= 60, 1.76M px with effects |
| mini-intel (Lion) | 1920x1080 | **56.9** | >= 60, just under |
| imac-g5 | 1440x900 | **59.5** | none, maxed config |

Still unconfirmed at native resolution on hardware: **sawtooth** (set up,
deployed, `autoexec-sawtooth.cfg` at 1024x768 with effects) and **imac-2019**.
Both were powered off during that round. **G3 performance is open on both
Panther and Tiger** - the `ppc750` profile is deliberately cautious (800x600,
`r_picmip 1`, 16-bit colour and depth, cheap sky) and has not been re-measured
on either OS since v0.5.0. Treat ~22 fps as the last known good number, not a
current one.

## Open questions

- **Fleet-wide vsync.** Only mini-intel sets `r_swapInterval`. The trade: kills
  tearing, adds judder when fps is below refresh. imac-g5 would cap 59 -> 60, no
  real loss.
- quicksilver and mini-intel sit just under the 60 target at native resolution.
  Either could clear it by dropping one resolution step or shedding an effect;
  the shipped configs currently favour resolution and effects.
- **G4/G5 AltiVec code work is not pursued** - the AltiVec paths in `tr_shade`
  and `snd_mix` are already active on the ppc7400 slice, and no un-vectorized
  hot loop remains (see the quicksilver profile).
