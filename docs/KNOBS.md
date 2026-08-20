# KNOBS - Quake III tuning inventory

Cvars and cmdline flags used for per-machine tuning. Every per-target knob must
be flippable at runtime (cvar) or at launch (cmdline) so a round-end review can
A/B contributions without a rebuild. Per-machine defaults live in
`scripts/bundle/autoexec-<machine>.cfg` (`docs/adr/0007`). Measured effects are
in `docs/PROFILING.md`.

## Resolution / framebuffer

| cvar | meaning |
|---|---|
| `r_mode` | video mode; `-1` = use custom w/h |
| `r_customwidth` / `r_customheight` | resolution when `r_mode -1` |
| `r_fullscreen` | 0 windowed / 1 fullscreen |
| `r_colorbits` / `r_depthbits` | framebuffer precision (16/32, 16/24) |
| `r_ext_multisample` | FSAA samples; `CVAR_LATCH`, read once at GL init, driven through `SDL_GL_MULTISAMPLE*` at context creation (`sdl_glimp.c:375`) |

## Texture quality / VRAM

| cvar | meaning |
|---|---|
| `r_picmip` | texture detail; 0 = sharpest, 3 = blurriest/fastest |
| `r_texturebits` | 16 or 32-bit textures |
| `r_ext_compressed_textures` | S3TC compression, a big VRAM saver where supported. **The Rage 128 has none.** |
| `r_ext_texture_filter_anisotropic` + `r_ext_max_anisotropy` | AF level |
| `r_textureMode` | `GL_LINEAR_MIPMAP_NEAREST` (default) or `GL_LINEAR_MIPMAP_LINEAR` (trilinear) |

## Lighting / geometry / effects

| cvar | meaning |
|---|---|
| `r_vertexlight` | 1 = vertex lighting (fast, but collapses every map shader to one flat stage), 0 = lightmaps plus full shaders |
| `r_dynamiclight` | dynamic lights on/off (rocket and plasma glow) |
| `r_subdivisions` | curved-surface tessellation; higher = coarser/faster |
| `r_lodbias` / `r_lodscale` | model LOD aggressiveness |
| `cg_shadows` | blob/stencil shadows |
| `r_flares` / `r_fastsky` | flare sprites / cheap sky |
| `r_detailtextures` | detail texture pass |

## Framerate / HUD / present

| cvar | meaning |
|---|---|
| `com_maxfps` | fps cap (0 = uncapped). Classic Q3 physics is tuned to 125, and jump heights depend on fps - keep it consistent for benching. |
| `r_swapInterval` | vsync. **Separate from `com_maxfps`** - `com_maxfps 0` does NOT defeat vsync. |
| `cg_drawfps` | on-screen fps counter |
| `cg_draw3dIcons` | **0 on the Rage 128.** The status bar draws three real MD3 models into HUD viewports (ammo/head/armor) and the Rage 128 renders them as garbage smudges. 0 gives a clean 2D-icon fallback, also faster. |
| `cg_lagometer` | 0 to remove the bottom-right net-graph. On the Rage 128 it showed as a corrupted red/green/blue block. Off fleet-wide. |

## Sound

| cvar | meaning |
|---|---|
| `s_sdlSpeed` | SDL backend mix rate. **This is the knob, not `s_khz`**, which is a no-op on this backend (`code/sdl/sdl_snd.c`). `11025` roughly halves the scalar mix work; the biggest single G3 CPU lever. |
| `com_altivec` | 1 on the ppc7400 slice, which selects `S_PaintChannelFrom16_altivec` in `snd_mix.c` |

## Game modules

| cvar | meaning |
|---|---|
| `vm_cgame` / `vm_game` / `vm_ui` | **`0` = native dylib** (loads `<mod><arch>.dylib` from a search dir), `1` = bytecode interpreter, `2` = bytecode JIT-compiled to native (stock default) |

The port ships `0`. See `docs/adr/0008` for what that buys and why it is safe.

## Cmdline flags (bench / launch)

| flag | meaning |
|---|---|
| `+set timedemo 1 +demo <name>` | run a timedemo |
| `+set nextdemo quit` | make the engine quit itself when the demo ends. **Load-bearing** - see `docs/adr/0009` |
| `+set logfile 2` | line-flushed `qconsole.log`, the poll target for the bench scripts |
| `+set com_archAutoexec 0` | disable both auto-config layers so cmdline `+set` owns the run |
| `+set fs_basepath` / `+set fs_homepath` | data and write directories |
| `+set cl_timedemoLog <file>` | per-frame durations, used to find frame-time spikes |

## Still open

- Which `r_mode` presets are usable per GPU (in practice everything ships at
  `r_mode -1` plus the machine's native custom resolution).
- Whether the SDL 1.2-era renderer exposes any of the later `r_ext_*` knobs.
- `r_smp` on the two-core Intel mini: historically flaky, gate and test.
