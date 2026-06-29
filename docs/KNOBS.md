# KNOBS — Quake III tuning inventory

Cvars and cmdline flags used for per-machine tuning. Every per-target knob
must be flippable at runtime (cvar) or launch (cmdline) so end-of-round review
can A/B contributions without a rebuild. Per-machine defaults live in
`scripts/bundle/autoexec-<machine>.cfg`.

## Resolution / framebuffer

| cvar | meaning |
|---|---|
| `r_mode` | video mode; `-1` = use custom w/h |
| `r_customwidth` / `r_customheight` | resolution when `r_mode -1` |
| `r_fullscreen` | 0 windowed / 1 fullscreen |
| `r_colorbits` / `r_depthbits` | framebuffer precision (16/32, 16/24) |

## Texture quality / VRAM

| cvar | meaning |
|---|---|
| `r_picmip` | texture detail; 0 = sharpest, 3 = blurriest/fastest |
| `r_texturebits` | 16 or 32-bit textures |
| `r_ext_compressed_textures` | S3TC compression — big VRAM saver (Rage 128!) |
| `r_ext_texture_filter_anisotropic` + `r_ext_max_anisotropy` | AF level |

## Lighting / geometry / effects

| cvar | meaning |
|---|---|
| `r_vertexlight` | 1 = vertex lighting (fast), 0 = lightmaps (pretty) |
| `r_dynamiclight` | dynamic lights on/off |
| `r_subdivisions` | curved-surface tessellation; higher = coarser/faster |
| `r_lodbias` | model LOD aggressiveness; higher = lower detail sooner |
| `cg_shadows` | blob/stencil shadows |
| `r_flares` / `r_fastsky` | flare sprites / cheap sky |

## Framerate / HUD

| cvar | meaning |
|---|---|
| `com_maxfps` | fps cap (0 = uncapped) — note: classic Q3 physics is tuned to 125 |
| `cg_drawfps` | on-screen fps counter |
| `cg_draw3dIcons` | **0 on Rage 128.** Status bar draws 3 real MD3 models into HUD viewports (ammo/head/armor); the Rage 128's GL renders them as garbage smudges. 0 = clean 2D-icon fallback, also faster. |
| `cg_lagometer` | 0 to remove the bottom-right net-graph; on the Rage 128 it showed as a corrupted red/blue/green block. |

### Finding: G3 picmip / VRAM wall at 1024×768 (clean A/B, 2026-06-29)

On yosemite (Rage 128, 16 MB, **no S3TC** so textures are uncompressed) the `four`
timedemo @ 1024×768, varying ONLY r_picmip via cmdline `+set`:

| r_picmip | fps | notes |
|---|---|---|
| 3 (1/8 res) | 28.2 | "very basic" textures |
| **1 (1/2 res)** | **27.0** | nearly free vs picmip 3 → fill-bound between 3 and 1 |
| 0 (full res) | 20.8 | hits the 16 MB VRAM wall — 211 ms frame spikes (texture thrash) |

So picmip **1 is the sweet spot**: much sharper than 3 at ~1 fps cost, while picmip
0 collapses to the 20 fps floor with VRAM thrashing. Takeaway: between picmip 3↔1
the G3 is fill-bound (texture detail ~free); picmip 0 is gated by VRAM, not fill.
At 640×480 the G3 is CPU-bound (sound mixing dominates — see PROFILING.md), so CPU
wins (e.g. s_sdlSpeed 11025) lift that regime and the worst-case combat frames.

## Cmdline flags (bench / launch)

| flag | meaning |
|---|---|
| `+set timedemo 1 +demo <name>` | run a timedemo (benchmark) |
| `+set logfile 2` | line-flushed `qconsole.log` (poll target for bench.sh) |
| `+set fs_basepath` / `+set fs_homepath` | data + write dirs |

## To investigate (kickoff)

- **`r_swapInterval` / vsync — confirmed relevant.** The v0 baseline showed
  quicksilver (G4) pinned at ~60 fps at BOTH 1024×768 and 640×480, while
  mini-intel (Lion) hit 105/238 fps. That flat ~60 on the G4 is vsync at the
  60 Hz display refresh hiding real headroom. For benchmarking true GPU/CPU
  cost, set `r_swapInterval 0` (vsync off); for play, vsync-on avoids tearing.
  Bench `com_maxfps 0` does NOT defeat vsync — `r_swapInterval` is separate.
- Which `r_mode` presets are usable per GPU; whether GMA 950 / Rage 128 need
  `r_colorbits 16`.
- `com_maxfps` vs physics: Q3 jump heights depend on fps — keep consistent
  for bench, document for play.
- Whether the SDL 1.2-era renderer exposes any of the later `r_ext_*` knobs.
