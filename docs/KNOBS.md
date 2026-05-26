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

## Cmdline flags (bench / launch)

| flag | meaning |
|---|---|
| `+set timedemo 1 +demo <name>` | run a timedemo (benchmark) |
| `+set logfile 2` | line-flushed `qconsole.log` (poll target for bench.sh) |
| `+set fs_basepath` / `+set fs_homepath` | data + write dirs |

## To investigate (kickoff)

- Which `r_mode` presets are usable per GPU; whether GMA 950 / Rage 128 need
  `r_colorbits 16`.
- `com_maxfps` vs physics: Q3 jump heights depend on fps — keep consistent
  for bench, document for play.
- Whether the SDL 1.2-era renderer exposes any of the later `r_ext_*` knobs.
