# Profiling and measured results

Profiling method and lookup for per-machine measurements and negative results.
Hardware baselines and August/September experiments live in `docs/profiling/`.
Current benchmark rows are in `benchmarks/results.csv`; the headings below route to each account.

## Context

> **Summary.** Measured numbers and recorded negatives per machine class (yosemite G3, quicksilver/mini-g4 G4, imac-g5, mini-intel, Panther). Find a machine or a negative with `grep -n '^##' docs/PROFILING.md` or `grep -n NEGATIVE docs/PROFILING.md`.

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
# -> build/release-darwin-ppc/ioquake3.ppc: ~2460 ppc750 text symbols
```

For a ppc7400 profile, adapt to `-arch ppc7400 -faltivec`.

**Sample the RENDER phase, not the load.** The G3 map load (`CL_InitCGame`)
takes ~12 s and dwarfs everything; a naive warmup catches JPEG decode,
`inflate` and `R_CreateImage`, not the frame loop. Trigger on the load-complete
log line:

```
./ioquake3-prof ... +set logfile 2 +set timedemo 1 +demo four &
# poll qconsole.log for "CL_InitCGame:" (bot frag/obituary lines = playing): +3 s
/usr/bin/sample $PID 16 10 -file /tmp/prof.txt
```

Analyse by thread (`Thread_*` roots) and by "Sort by top of stack" leaf leaders.
The main render thread is the one under `SDL_main -> Com_Frame`. Exclude idle
`mach_msg_trap` and `semaphore_timedwait` threads - those are GPU-swap and
helper-thread waits.

Startup `qconsole.log` prints `GL_RENDERER` and the extension list. Read it
before enabling any code path for a GPU.

---

## yosemite (G3 449 MHz: Rage 128 16 MB) - CPU-bound at 640x480, fill-bound above

See `docs/profiling/hardware-baselines.md`.

## quicksilver (G4 733 MHz: Radeon 9000) - CPU/geometry-bound with fill headroom

See `docs/profiling/hardware-baselines.md`.

## mini-g4 (G4 1.25 GHz: Radeon 9200 32 MB) - fill-rate / overdraw bound

See `docs/profiling/hardware-baselines.md`.

## imac-g5 (PPC 970 2.0 GHz: Radeon 9600) - ~60 fps GPU-bound at native, not vsync-capped

See `docs/profiling/hardware-baselines.md`.

## mini-intel (Core 2 Duo: GMA 950, Lion) - fill-bound at 1080p

See `docs/profiling/hardware-baselines.md`.

## Native-resolution confirmations (2026-07-05: deployed `ee6ed80b` configs, vsync-off bench)

See `docs/profiling/hardware-baselines.md`.

## G3 on both OSes (2026-08-22, issue #8)

See `docs/profiling/hardware-baselines.md`.

## NEGATIVE - on Panther, r_primitives and compiled vertex arrays are both below the noise floor (2026-08-23, issue #15)

See `docs/profiling/august-experiments.md`.

## SUPERSEDED - r_primitives 3 on yosemite/Panther was a visual bug, not just an unresolvable fps question (2026-08-23, issue #26)

See `docs/profiling/august-experiments.md`.

## NEGATIVE - r_fastsky 2 does not buy mirrors back on yosemite (2026-08-20, issue #6/#8)

See `docs/profiling/august-experiments.md`.

## Fresh shipping-profile baseline, post-#26/#31 fixes (2026-08-28, issue #8)

See `docs/profiling/august-experiments.md`.

## NEGATIVE - r_simpleMipMaps is already the cheap default, nothing to gain (2026-08-28, issue #8)

See `docs/profiling/august-experiments.md`.

## NEGATIVE - com_hunkMegs/com_zoneMegs headroom is not a G3 risk (2026-08-28, issue #8)

See `docs/profiling/august-experiments.md`.

## Tiger-side re-baseline under the converged config (2026-08-28, issue #15)

See `docs/profiling/august-experiments.md`.

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

## Quality and renderer experiments, 2026-09-22

See `docs/profiling/september-experiments.md`.
