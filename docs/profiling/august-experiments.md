# August renderer experiments

Rejected experiments, visual refutations and shipping-profile re-baselines.
Measurement method and other rounds remain in `docs/PROFILING.md`.
Sections preserve their issue numbers and dates for lookup.

## NEGATIVE - on Panther, r_primitives and compiled vertex arrays are both below the noise floor (2026-08-23, issue #15)

Issue #15 records Panther at 33.35 for `r_primitives 3` against 31.70 for `2`, a
5.2% gap, and Tiger reversing it. That measurement did not pin
`r_ext_compiled_vertex_array`, which is CVAR_ARCHIVE and read `0` on the Panther
partition and `1` on the Tiger one. So the two legs used different vertex
submission paths for a reason nothing controlled.

Re-measured as a 2x2 with both cvars pinned and read back from the engine on
every leg. `yosemite`, Panther 10.3.9, demo `four`, 800x600 fullscreen,
`v0.6.7-test1` (`68d683cc0bb6a98769d453851ea2789d`), one discarded warm-up then
three round-robin passes.

| leg | runs | median | spread |
|---|---|---:|---:|
| `r_primitives 3`, CVA off | 30.1 / 28.8 / 29.1 | 29.10 | 1.30 |
| `r_primitives 2`, CVA off | 30.5 / 26.3 / 29.1 | 29.10 | 4.20 |
| `r_primitives 3`, CVA on  | 28.4 / 30.2 / 30.5 | 30.20 | 2.10 |
| `r_primitives 2`, CVA on  | 27.8 / 27.2 / 28.5 | 27.80 | 1.30 |

All 12 legs span 26.3 to 30.5, a spread of 4.2 fps. **No leg is separable.** The
within-leg spread is as large as any difference between legs, and the two
CVA-off legs have identical medians while their means differ by 0.7 fps, which
is the summary-statistic instability that a spread this size produces.

Every leg was verified from the engine's own output rather than from the cvar we
set: `...using` or `...ignoring GL_EXT_compiled_vertex_array`, and `rendering
primitives: single glDrawElements` or `multiple glColor4ubv + glTexCoord2fv +
glVertex3fv`. All 12 read correctly.

### The instrument was calibrated, so the null means something

A null from an uncalibrated harness means "I cannot see this", not "there is
nothing there". Two known-positive controls, same config, same three-run shape:

| control | runs | median |
|---|---|---:|
| `r_picmip 0` | 23.5 / 24.6 / 23.4 | 23.50 |
| `r_vertexlight 1` | 39.9 / 39.9 / 35.2 | 39.90 |

Against the 2x2 cluster at 26.3 to 30.5, `picmip 0` is about -20% and
`vertexlight 1` about +37%, and neither overlaps the cluster at all. `picmip: 0`
and `picmip: 1` were read back from the engine, so the control did change.

**So the harness resolves a 20% effect cleanly and cannot resolve these two at
all.** The honest bound: on Panther at this configuration, `r_primitives` and
`r_ext_compiled_vertex_array` each cost less than roughly 14% of frame rate, and
three runs cannot say more than that. That does not make them zero, and it does
not refute the Tiger measurement, which is a different OS and driver.

**What it does flag:** `autoexec-yosemite-darwin8.cfg` ships `r_primitives 2`
for Tiger on a 2.9% difference, and `autoexec-yosemite.cfg` ships `3` for
Panther on 5.2%. Both are smaller than what three runs resolve on this machine
today. Neither value is wrong; the evidence under them is thinner than the
comments imply, and separating a 5% effect here needs many more runs than three.

### Two things that had to be fixed before any of this could be measured

**The partitions were not running the same binary.** Read on 2026-08-23 before
anything was touched: Panther `88ea73b3c79c1133a0e0cda73277b3e0`, Tiger
`2822bc046a311a150a05356fc811cc2e`, and every slice differed in size including
`ppc750`, 1691152 against 1691072. Both now hold the same
`v0.6.7-test1` binary, verified by md5 on each partition.

**The engine silently truncates a long command line.** `Com_ParseCommandLine`
(`code/qcommon/common.c:405,428`) keeps 31 `+` groups and discards the rest with
no message. The first attempt at this 2x2 pinned 26 cvars, which pushed
`+set nextdemo quit +set timedemo 1 +demo four` off the end. The engine started,
rendered the menu, and held the machine for six minutes producing no fps line.
`safebench.sh` now counts the groups and refuses.

## SUPERSEDED - r_primitives 3 on yosemite/Panther was a visual bug, not just an unresolvable fps question (2026-08-23, issue #26)

Every `r_primitives 3` fps figure above (the 33.35/33.3 rows, the 2x2 table) is
still accurate as an fps measurement, but shipping 3 was wrong regardless: it
renders world surfaces as flat lit gradients with no diffuse texture on this
Rage 128 (entities unaffected), confirmed by matched-frame screenshot A/B -
`docs/screenshots/q3-yosemite-issue26-before.jpg` / `-after.jpg`. `r_primitives
1` and `2` both render correctly. Root cause is presumably in
`R_ArrayElementDiscrete` (`tr_shade.c`, the `qglMultiTexCoord2fARB` immediate-
mode path that only `r_primitives 3` exercises) meeting a Rage 128 driver
quirk, not narrowed further since the fleet has no second Rage 128 to
discriminate driver-specific from card-specific.

Both `autoexec-ppc750.cfg` and `autoexec-yosemite.cfg` now ship `r_primitives
2`. The "below the noise floor" finding directly above still stands as the
reason giving up 3 cost nothing measurable in fps; it just wasn't yet known to
also be a correctness bug. Do not re-add `r_primitives 3` on this machine
without a second Rage 128 to test it on first.

## NEGATIVE - r_fastsky 2 does not buy mirrors back on yosemite (2026-08-20, issue #6/#8)

`r_fastsky 1` gates portal/mirror surfaces off entirely (`tr_main.c:969`,
`r_fastsky->integer == 1` exactly). `r_fastsky 2` was tried to dodge that exact
gate while keeping the fill saving, since both saving paths (`tr_backend.c:448`,
`tr_sky.c:799`) are truthy tests, not `== 1` tests. It does restore the portal,
but `tr_backend.c:448`'s same truthy test also clears the portal's colour
buffer to black, so the mirror renders as a black rectangle (seen on hardware,
q3dm0). And the fill saving does not exist: measured on yosemite, demo four,
800x600 -

    r_fastsky 2   13.7 fps, mirrors black
    r_fastsky 0   13.9 fps, mirrors correct

Real sky is if anything faster - the Rage 128 is not sky-fill-bound here, so
the cheap-sky path cost every reflection in the game for no measurable gain.
Shipped: `r_fastsky "0"` on both `autoexec-yosemite.cfg` and
`autoexec-ppc750.cfg`. **Do not re-propose `r_fastsky 2` on this machine** -
the mirrors-back argument for it was already tested and failed on the actual
mechanism (black portal, not a partial render).

## Fresh shipping-profile baseline, post-#26/#31 fixes (2026-08-28, issue #8)

3 runs, median of runs 2 and 3, current shipped config (`r_primitives 2`,
`cg_marks 1`, `r_ext_compiled_vertex_array 1`, `r_fastsky 0`, all converged -
see #26/#31):

    yosemite (Panther), demo four, 800x600: 26.2 / 26.3 / 25.9 -> 26.1 fps

Up from the ~22 fps single-run figure in issue #8's original text (that run
predates the r_primitives/cg_marks fixes). Well clear of the 20 fps floor.
Mirrors already correct and costing nothing (see NEGATIVE above) - issue #8's
"mirrors currently cost fps or are switched off" premise is stale. Remaining
open items on #8: `com_hunkmegs`/`com_zonemegs` headroom audit,
`r_simpleMipMaps`/`GL_SGIS_generate_mipmap`, and a Tiger-side re-baseline under
this same converged config (`yosemite-tiger` unreachable this session - see
#15).

## NEGATIVE - r_simpleMipMaps is already the cheap default, nothing to gain (2026-08-28, issue #8)

Checked rather than benched, because the code answers it directly.
`r_simpleMipMaps` (`code/renderer/tr_init.c:1045`) defaults to `"1"` and no
shipped config overrides it, on the G3 or anywhere else. `R_MipMap`
(`code/renderer/tr_image.c:394-400`) already takes the cheap box-filter path
whenever it is set, which is always, here. The expensive gamma-correct
`R_MipMap2` path is what `0` would select - we are not paying for it and
never have been. This is also load-time cost (texture upload), not per-frame
fill, so it could not have moved the steady-state fps number this ticket
cares about even if there were a change to make.

The ticket's other name for the same idea, `GL_SGIS_generate_mipmap`
(hardware-generated mipmaps), is a different, unrelated mechanism - a GL
extension, not an engine cvar - and does not appear in yosemite's
`GL_EXTENSIONS` line at all (checked live, full string). Rage 128 / GL 1.1
does not have it. Nothing here to implement.

## NEGATIVE - com_hunkMegs/com_zoneMegs headroom is not a G3 risk (2026-08-28, issue #8)

Engine defaults (`code/qcommon/common.c:50-51`, `DEF_COMHUNKMEGS 128`,
`DEF_COMZONEMEGS 24`) are unoverridden by both `autoexec-yosemite.cfg` and
`autoexec-ppc750.cfg` - shipped total ~152 MB. Measured on yosemite:
448 MB physical RAM (`system_profiler SPHardwareDataType`, `hw.memsize`),
leaving ~296 MB of headroom even before the OS's own footprint. No paging
risk on our bench unit.

For a hypothetical lower-RAM G3 (the `ppc750` baseline applies to any G3
slice, not just yosemite): `Com_InitHunkMemory` (`common.c:1543-1577`)
allocates via plain `calloc`, which on any Mac OS X version here is backed
by a dynamic swap file - a 128 MB request degrades to paging under memory
pressure, it does not `ERR_FATAL`. `calloc` only fails, and only then hits
`ERR_FATAL`, if the OS truly cannot back the allocation at all (virtual
address space or disk exhausted), not merely because physical RAM is
smaller than the hunk size. So the failure mode for a lower-spec G3 is
"runs slower," not "crashes at startup" - graceful, same shape as ADR
0007's per-arch baseline being a safe default for unknown hardware. Nothing
to change without a second, lower-RAM G3 to measure an actual regression
on, which this fleet does not have.

**Conclusion for #8 on Panther:** both named candidates are exhausted
without a code or config change. Combined with the already-recorded G3
findings above (fill-bound above 640x480, texture/picmip wall, r_fastsky,
r_primitives, flare interval, sound rate), yosemite/Panther is optimization-
exhausted at the current effects level. The only real remaining item on #8
is the Tiger-side re-baseline, which is #15's scope, not a separate #8
action.

## Tiger-side re-baseline under the converged config (2026-08-28, issue #15)

`yosemite-tiger` came reachable this session (another repo's OS-switch work,
not this session's), and it was free, so the re-baseline #15 had been
waiting on got taken while the window existed rather than requesting a
dedicated switch for it.

**MEASURED**, `scripts/safebench.sh yosemite-tiger 800x600`, demo `four`,
shipped production config (`autoexec-ppc750.cfg` + `autoexec-yosemite.cfg` +
`autoexec-yosemite-darwin8.cfg`, i.e. `r_primitives 2` and nothing else
OS-specific - Tiger carries no quality overlay), 3 runs, median of runs 2
and 3:

    run 1   29.5 fps
    run 2   28.9 fps
    run 3   30.8 fps
    median (2,3)   29.85 fps

Compare the standing Panther number (`088c47d8`, above): **26.1 fps**, but
that run is the FULL shipped Panther config, which includes
`autoexec-yosemite-darwin7.cfg` - Panther's deliberate quality overlay
(finer curve subdivision, full model LOD, trilinear filtering, detail
textures, blob shadows), not just the shared baseline. Tiger has no
equivalent overlay to compare against directly; the two "shipped" numbers
are not the same effects level.

**INFERRED**, not re-measured fresh: `autoexec-yosemite-darwin7.cfg`'s own
header records that overlay's cost as measured, at the time the file was
written: 33.35 -> 30.1 fps, about -9.7% (that measurement predates the
`r_primitives` 3->2 revert, issue #26, so the absolute numbers are stale,
but the overlay's own settings are unrelated to `r_primitives` and there is
no reason its *relative* cost would have changed). Applying that -9.7% in
reverse to today's Panther number: 26.1 / 0.903 ≈ **28.9 fps** for Panther
at the shared baseline, no quality overlay - within noise of Tiger's
measured 29.85.

**Conclusion.** The original ~55% gap this issue opened with does not
survive controlling the cvars that were drifting at the time (CVA,
`cg_marks`, `r_textureMode`, `r_lodCurveError`, plus the two partitions
running different binaries - see the "G3 on both OSes" section above).
Under today's converged, explicitly-pinned config, Panther and Tiger
perform within a few percent of each other at the same effects level; the
real, large, and entirely intentional difference visible in the two
*shipped* numbers is Panther spending its extra headroom on
`autoexec-yosemite-darwin7.cfg`'s visual quality trade, not an unexplained
OS or driver defect. That trade is deliberate (the file's own header: "the
project rule is that above the floor effects beat frame rate") and correct
to keep.

The darwin7/darwin8 overlay files' "Why is Tiger slower at all: issue #15,
not answered" lines are corrected in the same commit as this entry, to
point here instead of implying an open question.
