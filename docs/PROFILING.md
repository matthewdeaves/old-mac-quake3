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
- **Sound, not graphics, is the biggest CPU cost on the G3.** Lower `s_khz`
  (22→11 kHz) ~halves the scalar mix work. See KNOBS / autoexec.
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
