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
