# September quality and renderer experiments

The 2026-09-22 experiment results and their measured tradeoffs.
Other rounds and profiling method remain in `docs/PROFILING.md`.
Read the requested and effective settings with each result.

## Quality and renderer experiments, 2026-09-22

Native desktop resolutions were read from the machines before testing. These
results supersede the old 1680x1050 mini-g4 assumptions for its current display.
Each row below uses three alternating runs, with the median of runs 2 and 3.
Raw logs and matched-frame screenshots are under `benchmarks/raw/20260922-*`.
Screenshots run separately from timing and are not FPS samples.

| Machine / resolution | Change | Runs | Median 2,3 |
|---|---|---|---:|
| mini-g4 / 1024x768 | bilinear mip filtering | 44.8 / 74.4 / 73.9 | 74.15 |
| mini-g4 / 1024x768 | trilinear mip filtering | 74.8 / 74.6 / 75.1 | 74.85 |
| mini-g4 / 1024x768 | post-flare finish, existing behavior | 74.1 / 75.4 / 75.3 | 75.35 |
| mini-g4 / 1024x768 | suppress post-flare finish | 74.5 / 74.5 / 74.9 | 74.70 |
| mini-sl / 1920x1080 | existing moderate texture/light settings | 121.3 / 121.1 / 121.5 | 121.30 |
| mini-sl / 1920x1080 | full textures, dynamic lights, 8x AF, trilinear, 2x AA; flare interval 1 | 20.6 / 20.2 / 20.3 | 20.25 |
| mini-sl / 1920x1080 | same quality, no AA; flare interval 8 | 123.8 / 116.8 / 121.6 | 119.20 |
| mini-sl / 1920x1080 | same quality, 2x AA; flare interval 8 | 50.7 / 50.1 / 50.5 | 50.30 |
| Apple M5 / 2560x1080 | copied texture coordinates | 230.0 / 237.5 / 221.2 | 229.35 |
| Apple M5 / 2560x1080 | direct texture coordinates | 240.1 / 237.3 / 226.2 | 231.75 |

## Keep: G4 filtering and GeForce 9400 quality

The mini-g4's trilinear change has no measurable FPS cost. Matched screenshots
show the same geometry and lighting with smoother texture filtering. Keep it
in `autoexec-mini-g4.cfg`. The anomalous first baseline run is retained in the
raw data and excluded by the normal warm-up rule.

The Macmini3,1 reports a GeForce 9400 with 256 MB VRAM. Its old generic Intel
settings left full-resolution textures, dynamic lights and anisotropic filtering
disabled. The new `autoexec-mini-sl.cfg` uses full-resolution textures, dynamic
lights, 8x AF and trilinear, retaining S3TC and leaving multisampling off. Its
119.2 FPS result is above the Intel 60 FPS floor. Flare visibility checks use
interval 8, already used on PowerPC: this keeps the sprites and their fades,
but can delay an occlusion update by up to seven frames. This is a deliberate
latency trade, not identical per-frame flare visibility.

**NEGATIVE:** 2x AA remains below the Intel floor even with interval 8, and its
worst frames are 384-429 ms. Do not ship that combination on this GeForce 9400.
The 20.3 FPS final AA sample was recovered from the completed engine log after
a local harness error; it rendered all 1260 frames and shut down normally.

## Code candidates, disabled unless hardware measurements justify them

The tested `r_flareNoFinish` candidate preserved `r_finish 0`'s suppression of the swap-time finish
after flare depth readback. The readback and fade remain intact. The mini-g4
comparison was negative: no separable improvement. The code was reverted after
the G3 comparison also showed no clear benefit. Its historical unit harness
exercised visibility, fades, readback and all finish modes.

The subsequently reverted `r_directTexCoords` candidate submitted unmodified mesh texture/lightmap coordinates with
their original stride, avoiding per-stage copies. Texture modifiers, generated
coordinates and the discrete primitive path keep the original arrays. This
changes neither shader selection nor lighting calculations. Pointer/stride
and fallback tests pass. On the M5 the measured difference is smaller than run
variation; **no demonstrated speedup there**, so the Apple Silicon default stays
off. Matched demo frames show intact world textures; moving particles and HUD
portraits differ between launches, so these captures are not pixel-equality proof.

The old specialized stage iterators are not enabled: source review found that
their selection does not exclude texture modifiers, while their draw paths use
unmodified mesh coordinates. The direct-coordinate experiment instead retains
the general shader path and explicitly checks for modifiers.

## Coverage and operational findings

The iMac G5's initial single run was 38.6 FPS at 1440x900 with its existing
2x AA. Subsequent benchmark connection attempts timed out even though separate
SSH health checks answered. A persistent SSH connection subsequently allowed
the complete quality comparison below. No candidate code speedup is claimed
on that machine.
Its reported extension list lacks `GL_EXT_framebuffer_multisample` and
`GL_EXT_framebuffer_blit`, required by Quake2's resolve-once experiment. That
code cannot simply be copied to the Radeon 9600 path.

Quake3 already combines depth and stencil clears in `RB_BeginDrawingView`, so
Quake2's combined-clear change has no equivalent saving here.

The G3's `/Applications/Quake3/baseq3` initially lacked game data. Deployment
warned, but a benchmark was attempted before that warning was handled. Restored
the patch archives from its older `quake3-play` folder and the main archive from
the existing local installation. The repaired G3 completed all 1260 demo frames
at **26.1 FPS**, with shipped configuration and normal shutdown. This was an
installation repair, not a rendering regression or an optimization gain.

The build workflow remains owned by `old-mac-build-host`. Modern Apple `lipo`
failed to identify thin PowerPC files; the numeric Mach-O header verifier from
Quake2 now checks them through `otool`. Its fixture tests reject missing,
unknown and malformed members. A local experiment replacing the arm64 member
with modern `lipo` also dropped both PPC members; that artifact was **not
deployed**. Continue assembling release fat binaries on the claimed Lion build
host and verifying every expected member.

## Further quality budget, same day

These are paired experiments, not before/after comparisons between unrelated
runs. Each result is the median of runs 2 and 3; all timing runs completed 1260
frames. Expanded weapon effects mean `cg_oldRail 0`, `cg_oldRocket 0` and
`cg_oldPlasma 0`, enabling existing spiral rails, rocket explosion effects and
plasma particles. These are configuration changes, not newly written effects.

| Machine | Paired change | Baseline FPS | Candidate FPS | Decision |
|---|---|---:|---:|---|
| yosemite | expanded weapon effects | 26.05 | 25.95 | within 20 FPS budget |
| mini-g4 | expanded weapon effects | 77.85 | 77.25 | keep |
| mini-g4 | curves 8/250 to 4/1000, expanded effects on | 77.15 | 76.90 | keep |
| mini-sl | expanded weapon effects | 118.45 | 122.80 | keep effects, do not claim speedup |
| mini-sl | curves 4/250 to 1/10000, expanded effects on | 120.45 | 120.40 | keep |
| Apple M5 | expanded weapon effects | 380.95 | 378.05 | keep |
| imac-g5 | expanded effects, curves 1/10000, AF16, retaining 2x AA | 38.25 | 36.95 | within quality budget |

Curve pairs are `r_subdivisions/r_lodCurveError`. The G3, G4, G5 and GeForce 9400
final-quality captures retain textured world geometry and lighting. Weapon
particles vary between demo launches, so captures are visual checks rather than
pixel-equality tests. The M5 weapon experiment and earlier direct-coordinate
experiment ran in different performance bands; their absolute FPS must not be
used as evidence of a code speedup.

G3 flare finish suppression also failed to show a separable benefit: 25.75 FPS
off versus 25.95 on. The G5 single-sample comparison was 38.6 off versus 38.3 on,
insufficient for a speedup conclusion. Both renderer experiments were subsequently reverted after measurement.
The direct-coordinate candidate compiled and ran on arm64 and PPC; the
subsequent comparison below did not justify keeping it. The first five-slice build contains
the flare experiment only. The other G4 GPUs, GMA950 and modern Intel were not
remeasured in this round; these machine-specific results do not establish their
performance. This round has demonstrated quality gains within the measured
budgets, not a reliable new CPU-code FPS gain or a global maximum.

## Current G3 profile and scalar mixer candidate

A fresh Panther profile was captured after a bot obituary and a further three
seconds of gameplay. The earlier capture caught load-time pixel conversion and
was discarded as frame-time evidence. The usable call tree contains 559 samples
under `Com_Frame`: 71 leaf samples in `gldAllocVertexBuffer`, 20 in
`gldFreeVertexBuffer`, and 31 in `S_PaintChannelFrom16_scalar`. These are sampled
attributions, not precise subsystem timings; unresolved driver frames limit
interpretation. The larger lead is driver geometry submission, while scalar
sound is a smaller opportunity. The profiled timedemo's 22.2 FPS is instrumented
and must not be compared against ordinary benchmark results.

`s_mixScalarChunks` adds an opt-in scalar PCM loop that processes contiguous
runs between sound-chunk boundaries. Arithmetic and sample rate stay identical;
the Doppler and AltiVec paths are unchanged. The extracted actual functions pass
600 exact-output comparisons with address/undefined-behavior sanitizers,
including boundary crossings, signed sample extremes, channel volumes, destination
offsets and Doppler fallback. The arm64 engine compiles. The cvar defaults to 0;
this is a candidate, not a measured G3 speedup. The subsequent PPC build and measurement are recorded below.

The scalar mixer M5 comparison completed three alternating runs: off
201.0/195.8/191.0, on 169.2/191.7/191.6. Medians 193.40 versus 191.65 FPS show
no useful gain on this machine, so it remains disabled. The G3-specific result and removal decision are recorded below; no G3 benefit
is inferred from a native arm64 compile or test.

## Completed legacy code comparisons and shader-renderer work

The final five-slice candidate build completed through `old-mac-build-host`'s
claimed Lion mini and verified ppc750, ppc7400, x86_64, i386 and arm64. The G3
and G4 were deployed from that candidate, source `e478d815`.

Direct texture coordinates on the G4 gave 76.80 FPS off and 76.90 on, with
runs 76.6/76.7/76.9 versus 77.3/76.8/77.0. On G3, off gave
26.0/25.9/20.3 and on 24.4/25.4/19.0. Both final legs slowed markedly, so the
23.10 versus 22.20 medians must not be treated as a precise regression estimate.
None of the individual G3 pairs favored the candidate. Reverted the code rather
than shipping an unproven optimization. Later idle G3 inspection showed heavy
SSH activity; that is a measurement concern, not a proven explanation for the
prior slow samples. Avoid repeated fleet-wide status polling during timing.

Source review found that the Makefile already builds separate `ioquake3_rend2`
executables, despite an old build-script comment saying otherwise. This renderer
was not shipped. A separate M5 test app completed demo four with its GLSL 1.20
path, HDR and tone mapping. Generated normal maps, enhanced dynamic lighting and
SSAO were requested for the following experiments. Later log review found the
SSAO target incomplete; see the correction below. These tests are separate
from the shipping GL1 renderer and must not be compared as equal-quality FPS.

| M5 shader-renderer experiment | Baseline runs | Candidate runs | Medians 2,3 |
|---|---|---|---|
| flares off versus on | 82.9/86.1/84.0 | 84.7/86.3/82.0 | 85.05 / 84.15 |
| fresh dynamic storage, mode 0 versus 1 | 106.7/103.0/88.1 | 123.2/107.9/102.2 | 95.55 / 105.05 |
| gathered uploads, mode 0 versus 2 | 74.7/79.2/77.3 | 135.7/144.8/149.4 | 78.25 / 147.10 |

The single-upload change improves that paired comparison by 88.0%, with all
three pairs favoring it. Identical settings requested HDR, generated normal maps,
enhanced dynamic lighting and SSAO; both SDL and FBO multisampling were off for
this comparison. This is an optimization of the experimental shader renderer,
not an 88% gain over the shipping GL1 renderer. Absolute performance varied
between separate rounds; use only within-round pairs.

A local profile captured driver resource flushes under `glBufferSubData`.
The user interrupted that run before the timedemo completed, so its incomplete
FPS is excluded; sampled stacks motivated the upload experiment but are not
used as a quantitative whole-demo breakdown. Mode 1 replaces the dynamic
scratch-buffer storage before its partial uploads. Mode 2 gathers active vertex
ranges at their existing offsets and submits one complete vertex-buffer upload,
plus one index-buffer upload, instead. Static world/model VBOs are unchanged.
The actual upload functions pass byte-oracle tests across attribute masks,
vertex counts, mode switches and tangent-space build variants with address and
undefined-behavior sanitizers. Matched streaming screenshots were subsequently viewed; the incomplete AA results
and the user-requested validation stop are recorded below.

The first fresh-storage prototype was built from `e478d815` plus the small
orphaning patch; its CSV tag is `e478d815-orphan-v1`. The full two-mode source
and tests are retained in `553ba9f4`.

## Follow-through and background-workload caveat

The G3 scalar mixer completed: off 26.1/24.7/26.0, on 24.4/26.0/26.0.
The final pair ties; the earlier pairs disagree. Removed the candidate rather
than enabling a CPU optimization without a repeatable gain.

The user reported Dungeon Keeper running alongside Quake3 on the workstation.
Coordination notes place KeeperFX at 19:14-19:16:05 during shader quality
validation. The AA round completed only 2x 106.7/130.0 and 4x 89.9 FPS before
interruption; there is no three-run AA comparison. Keep the earlier streaming
comparison as measured, with the background-workload caveat. The user explicitly
requested no additional M5 validation round. Matched streaming screenshots were
viewed and showed intact world geometry, textures and lighting; portal-specific
validation remains unperformed.

Apple Silicon now selects the built-in rend2 executable in build-arm64.sh.
Its profile enables gathered uploads, HDR/tone mapping, generated normal maps,
dynamic-light mode 1, SSAO and 4x scene-FBO AA. SDL-window AA is disabled because
it does not antialias the offscreen HDR scene. The other four CPU slices retain
GL1. M1 through M4 performance is not established by the M5 measurements.

Next G3 hypothesis: omit the redundant vertex-color stream on single-pass,
unfogged identity-color stages. The driver allocation profile motivates reducing
submitted attributes; no FPS gain is assumed. `r_constantColor` defaults to 0.
Color computation remains intact, and other shader stages retain their arrays.

## Constant-color submission: removed after hardware comparison

Source 0dbbc761 built through the shared Lion host and verified all five slices.
The experimental GL1 path omitted the color array only on single-pass, white,
unfogged indexed stages. Its recorded-state test passed 192 combinations, and
both PowerPC slices compiled. Hardware results did not justify keeping it:

| Machine | Off runs | On runs | Medians 2,3 |
|---|---|---|---|
| G3 yosemite | 24.5/21.6/20.8 | 22.8/21.6/20.8 | 21.20 / 21.20 |
| G4 mini | 76.8/74.0/69.2 | 72.1/73.2/72.8 | 71.60 / 73.00 |

The G3's later pairs tie. On G4, the first two pairs favor the old path and the
last baseline slows sharply. Do not interpret that median difference as a
repeatable improvement. Removed the experiment and its test in 5b488953.
No candidate screenshots were needed for retention because the code was dropped.

The fat app from 0dbbc761 was installed on workstation, yosemite and mini-g4.
The installed arm64 member was extracted, compared byte-for-byte to the signed
native build, and passed signature verification. Whole-app verification is a
different check and fails on the unsigned legacy components. An obsolete
CodeResources manifest from the prior local installation was removed, and the
production app was registered with LaunchServices. No new M5 game/timing round
was run, as requested by the user.

The other G4 hosts were off, modern Intel was unreachable, and the GMA950 host
was claimed for other projects. These classes were not rebenchmarked.

## SSAO correction: requested does not mean rendering correctly

Saved M5 logs, including the streaming and AA experiments, report
`R_CheckFBO: (_hdrDepth) Unsupported framebuffer format`. The shader renderer
created an INTENSITY32F color target and ignored its failed completeness check.
Therefore SSAO was requested, but those results do not demonstrate working SSAO.
The streaming FPS comparison remains a comparison of the same settings and code
paths, not a measurement of performance with this framebuffer bug fixed.

A small offscreen CGL probe on Apple M5 reproduced the rejection: INTENSITY32F
returned 0x8cdd, while RGBA32F and RGBA16F returned complete, 0x8cd5, with no GL
errors. A second probe redefined the same attached texture, obtained a complete
framebuffer, and round-tripped red 0.123456791 unchanged with no GL error.
These probes do not render a game or measure FPS. The fix retries the
existing attached texture as RGBA32F, preserving the red channel's 32-bit float
precision; SSAO and depth-blur shaders read that red channel. If retry or the
SSAO output target remains incomplete, initialization disables SSAO instead of
using an invalid framebuffer. Failure-injection tests cover those outcomes.
The updated native renderer compiles. No post-fix whole-game FPS is claimed.
