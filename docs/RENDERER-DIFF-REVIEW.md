# Review: upstream ioquake3 diff since our pin, for cherry-pickable fixes

Reviewed 2026-08-23 against upstream `ioquake/ioq3` at `58839361`
(2026-07-19), diffed from our pin `4432a80a` (2013-01-17). 1817 commits
between the two. Closes the scoping half of issue #17.

Written so this is not re-litigated, and so the non-trivial candidate list
survives past this session. Originally triage only; application state is
tracked below as increments land.

## Applied so far

- Increment 1 (`d35fb252`): tr_bsp.c entity-parse early-stop (`c8c7bb1d`),
  cm_patch.c facets array size (`5e09f20c`), tr_image.c skin alloc both
  sites (`a5fbc1bf`), tr_image_png.c tRNS check (`fda03ee4`). Built fat,
  smoke-tested on yosemite, 26.1 fps, no regression.
- Increment 2 (`9d94ce5b`): shader-parser hardening (`eb73dcb7`,
  `3ec2b02d`, `eeeaf3f1`, `e5f54c58`), flare fixes (`00c1831e`,
  `d526eacd`), rail/lightning overflow check (`cc9072d0`). The
  `SkipBracedSection` signature change also touched dead-code
  `code/rend2/tr_shader.c` mechanically.
- Increment 3 (`eca6aa54`): base sound path (`a167110f`, `57eae5da`,
  `a836c2db` apply-clean; `2ef641b9`, `84daa282` hand-ported, our
  resamplers are mono and our transfer uses `out_mask` not `%`). OpenAL
  cluster dropped as dead code, see above.
- Increments 2+3 verified together: 5-slice fat rebuilt (lipo-asserted),
  deployed to yosemite, safebench 800x600 demo four: 26.2 fps, crashlogs=0,
  against the 26.1 pre-increment baseline. G4-class run via the Jenkins
  bench-quake3-mini-g4 job; result in the #17 comment trail.
- Increment 4 (`4f1e8cb5`): files.c/cvar.c security cluster, all ten
  commits (six apply-clean, four hand-ported; the fs_game trio taken as
  its settled combined state, not piecemeal). Verified: fat rebuilt,
  yosemite 26.1 fps crashlogs=0, mini-g4 75.0 via Jenkins, and the
  fs_game gate tested in the REFUSING direction on this workstation
  (arm64 + x86_64 slices): '../evil' is refused at FS_Startup. Known
  limitation: an init-time ERR_DROP exits via segfault, pre-existing
  error-path fragility, filed separately.

## Method

- Cloned upstream into a scratch dir, confirmed `4432a80a` is a real ancestor
  commit in its history (it is — our repo forked from exactly that commit).
- Diffed `code/renderer` (-> `code/renderergl1` + `code/renderercommon` after
  upstream's 2015 split, `f6fb9eb6`), `code/qcommon`, and `code/client`
  between the pin and upstream HEAD, with rename detection (`-M40%`) so the
  renderer split reads as moved files with small real diffs, not as
  wholesale deletes/adds.
- `code/renderergl2` (upstream's separate GLSL/shader-based backend, added
  after the split) is entirely out of scope — it is not a fix to the
  renderer we have, it is a different renderer we do not carry.
- Excluded throughout: Windows/Linux-only code, SDL2-only code (we are
  pinned to SDL 1.2, ADR 0001), anything requiring GL 2.0+/GLSL on the
  PowerPC/old-Intel fixed-function GPUs in the fleet, and pure
  reorg/rename/cleanup with no behavior change.
- Three parallel passes: `code/qcommon` core files, `code/client` (net +
  sound), `code/renderergl1`/`renderercommon`. Each file's real changes were
  read via `git log`/`git show` on the commits that looked substantive, not
  just the diffstat.
- A handful of the highest-confidence findings were spot-checked directly
  against our current tree (not just the upstream diff) below.

## What's NOT here

Everything upstream changed that assumes: SDL2, GL 2.0+/GLSL, Windows or
Linux syscalls, VoIP codec swap (Speex->Opus - we still vendor Speex), IQM
model rework (not deeply reviewed - stock baseq3 doesn't use IQM, low
priority for a follow-up), MDR/RTCW-style skeletal models (unused format),
PVR/PowerVR texture loading (no PowerVR hardware in the fleet), the VM JIT
files for x86_64/ARM/SPARC (`vm_x86_64*.c`, `vm_armv7l.c`, `vm_sparc*`,
`vm_powerpc*`) - irrelevant because every slice except i386 runs native
dylibs, not a QVM JIT (ADR 0008), and i386's own JIT is `vm_x86.c`, barely
touched upstream.

Also not applicable: every `-faltivec`-isolation commit (`5909b9a1` and its
`tr_altivec.c`/`snd_altivec.c` split). Upstream needed it to let one fat PPC
binary detect AltiVec at runtime; we already avoid that problem by compiling
`ppc750` and `ppc7400` as separate slices (ADR 0002/0003), so the failure
mode it fixes cannot occur here. And every `GL_CLAMP`/`haveClampToEdge`
fallback commit - those patch a runtime GL-version-gated code path our tree
never had; we hardcode `GL_CLAMP_TO_EDGE` unconditionally and it already
works on every GPU in the fleet.

## Candidates, by confidence

### Spot-checked against our current tree (confirmed present or confirmed absent)

- **tr_bsp.c `R_GetEntityToken`, `code/renderer/tr_bsp.c:1778`** - upstream
  `c8c7bb1d` fixed `||` that should be `&&`: our current code reads
  `if ( !s_worldData.entityParsePoint || !s[0] )`, which stops parsing a
  map's entity lump entirely the first time any key or value happens to be
  an empty string, silently dropping every entity after it. **Confirmed
  present, unfixed, in our tree right now.** Upstream's fix on a real map
  (`poq3dm5`) is cited as the trigger. Zero GPU dependency, one-character
  fix.
- **cm_patch.c facets array, `code/qcommon/cm_patch.c:421`** - our tree
  still has the exact line upstream's `5e09f20c` fixed:
  `static facet_t facets[MAX_PATCH_PLANES]; //maybe MAX_FACETS ??` - the
  comment questioning its own size is still there. `MAX_PATCH_PLANES` is
  2048, `MAX_FACETS` is 1024, so this array is arguably oversized rather
  than overflowing, but it means the two related bounds checks in the same
  file (`numFacets == MAX_FACETS`) are checked against a different constant
  than the array is declared with - fragile, and exactly what upstream
  flagged. **Confirmed present, unfixed.**
- **tr_image.c skin surfaces alloc size, `code/renderer/tr_image.c:1504`** -
  upstream `a5fbc1bf` fixed a `sizeof(pointer)` vs `sizeof(struct)` bug.
  Checked all three call sites in our tree:
  - line 1504 (`RE_RegisterSkin`, single-shader-name skin path):
    `ri.Hunk_Alloc( sizeof(skin->surfaces[0]), h_low )` - **bug, present**:
    `skin->surfaces[0]` is a pointer, so this under-allocates to
    `sizeof(pointer)` (4 or 8 bytes) instead of `sizeof(skinSurface_t)`, then
    the very next line writes a full `skinSurface_t` through it.
  - line 1538 (multi-surface `.skin` file path) already uses
    `sizeof( *skin->surfaces[0] )` - **already correct**.
  - line 1570 (`R_InitSkins`, the built-in default skin):
    `ri.Hunk_Alloc( sizeof( *skin->surfaces ), h_low )` - **bug, present, and
    NOT already-correct as an earlier pass of this review wrongly concluded**.
    `skin->surfaces` decays to `skinSurface_t **`, so `*skin->surfaces` is
    `skinSurface_t *` and `sizeof` of that is a pointer size again - same
    underlying bug as line 1504, spelled differently. Matches upstream's
    `a5fbc1bf` fix for `R_InitSkins` exactly (`sizeof( *skin->surfaces )` ->
    `sizeof( *skin->surfaces[0] )`).
  So both the single-shader-name path and the built-in default skin need the
  fix; only the `.skin`-file path was already right.
- **msg.c `MSG_ReadBits`/`MSG_WriteBits` bounds, `code/qcommon/msg.c:107-`**
  - our tree matches upstream's *pre*-`d2b1d124` state: no bounds check
  before the huffman-coded and raw bit read/write paths touch `msg->data`.
  **Confirmed present, unfixed.** This is the fix for the public
  `q3msgboom`-class crash. Four related commits form the real fix
  (`d2b1d124`, `3a702ded`, `9f294ce5`, `1e309787`) - take them together, not
  piecemeal, per the qcommon triage below.
- **tr_image_png.c tRNS chunk check, `code/renderer/tr_image_png.c:2278`** -
  our tree has `if(!ChunkHeaderLength == 2)`. This is `(!ChunkHeaderLength)
  == 2`, which is always false (a boolean can never equal 2), so the length
  check on the tRNS chunk **never fires**. **Confirmed present, unfixed.** A
  malformed PNG with a too-short tRNS chunk reads up to 5 bytes past the
  buffer. Fix is `ChunkHeaderLength != 2`.
- **tr_light.c grid interpolation** - our tree's `R_SetupEntityLightingGrid`
  (`code/renderer/tr_light.c:122`) matches the structure upstream's
  `1bb2bc37`+`9f57fea0` pair fixed (off-by-one grid clamp plus a missing
  bounds guard in the trilinear interpolation loop). Not fully hand-verified
  line-for-line against the exact upstream patch in this pass - flagged
  **needs one more read before writing the actual patch**, but the function
  is present and unchanged from the pre-fix shape.

### High-confidence, not yet spot-checked (from the diff review, worth checking before applying)

**code/qcommon** - all from the qcommon triage pass:
- `d2b1d124`+`3a702ded`+`9f294ce5`+`1e309787` - `MSG_ReadBits`/`MSG_WriteBits`
  bounds + signedness + overflow-flag off-by-one (see above, confirmed
  present).
- `b4ad5a84` - `MSG_ReadDeltaKey` wrong mask (`kbitmask[bits]` should be
  `kbitmask[bits-1]`), corrupts delta-decoded angle values.
- `ee2541ef` - `CM_AddFacetBevels` range check off-by-one plus a missing
  `continue`/`return`, real OOB write on complex patch geometry.
- `9d742275`+`077ab4cb` - `CM_GridPlane`/`CM_EdgePlaneNum` unresolvable-plane
  guard; take the *final* combined state (`077ab4cb`), the intermediate
  commit alone is a regression on real maps.
- `3a6af1bc` - VM could strip `CVAR_PROTECTED` via `Cvar_Register` and then
  rewrite protected cvars like `fs_homepath`. External security report.
- `0f62a565` - `CVAR_VM_CREATED` flag ordering bug, weakens the above fix's
  model.
- `63e59a45` - a cvar flagged both `CVAR_LATCH` and `CVAR_CHEAT` skipped the
  cheat-protection check.
- `ce2b8db2` - `Cvar_Unset` never set `cvar_modifiedFlags`.
- `3638f69d`+`738465d6`+`71a9a5ef` (files.c/cvar.c) - `fs_game ".."`
  directory traversal from a malicious server; final settled fix is
  `FS_InvalidGameDir()`, take that, not the abandoned latch-based attempt.
- `936db459`+`05858d30` (files.c) - block the VM from writing/loading files
  with dylib/qvm/pk3 extensions (or disguised variants) - directly relevant,
  this port loads native dylibs from the bundle (ADR 0008).
- `376267d5` - don't load `autoexec.cfg`/`q3config.cfg` out of untrusted pk3s.
- `67d9ecd0`, `90c98c90`+`2d45e570`, `c7500bb2`, `4ea0eebf`, `26780805` -
  smaller filesystem-layer crash/correctness fixes (stale file handle on
  failed pk3 lookup, broken zip-file seeking, NULL derefs, qsort(NULL)).
- `a6df505d` - `Q_IsColorString` calling `isalnum()` on a negative `char` is
  UB; **PowerPC-relevant asymmetry**: `char` is unsigned by default on
  classic PowerPC/Darwin but signed on x86, so this bug can only manifest on
  the Intel/arm64 slices of this fat binary, never the PowerPC ones.
- `5c1091b4`, `c52e35bc`, `a6f949c8`, `9c29b25a`, `3ec2b02d` - smaller
  string/info-string parsing fixes (one-byte overread, overlapping
  `strcpy`, info-string control-character injection, case-inconsistent key
  removal, unterminated-shader-block parser runaway).
- `b3223dcf` - `Q_rand` (`code/qcommon/q_math.c`) relies on signed-overflow
  UB; trivial `unsigned` fix, same output on every target here.
- `313064ba` - `+seta`/`+sets`/`+setu` command-line args and multi-token
  `+set` values were silently mishandled. **Check our own `scripts/*.sh`
  before taking this** - if any bench/deploy script relies on the current
  (broken) behavior it needs re-checking against the fix.
- Explicitly flagged *against* taking as-is: `7003c9de`+`170a0524` (raising
  `DEF_COMZONEMEGS`/`MIN_COMHUNKMEGS`) - justified upstream by their GL2
  renderer's memory growth, which we don't carry; blindly raising
  `MIN_COMHUNKMEGS` to 128MB could hurt the G3's tight RAM budget rather
  than help it.

**code/client** - from the client/sound triage pass:
- `63e6c82f` - `CL_CheckForResend` stack buffer overflow building the
  `connect "..."` string.
- `0853c85e` - `CL_ServerInfoPacket` `strncat` ignores current length,
  server-supplied info string can overflow near `MAX_INFO_STRING`.
- `e9436abf`+client.h - connectionless print/echo accepted from any host,
  not just the server/rcon address.
- `ebac005c` - `CL_ParseVoip` reads `clc.voipIncomingSequence[sender]`
  before range-checking `sender` (raw network `short`) - confirmed this
  ordering exists in our tree; live OOB read from untrusted network data if
  VOIP is compiled in.
- `91194bfc`+`ac621642` - snapshot staleness check inconsistent with
  `MAX_SNAPSHOT_ENTITIES`, can delta against an overwritten ring-buffer
  slot; take together with the `MAX_PARSE_ENTITIES` bump to 8192 (~1MB,
  trivial even on the G3).
- `3ad427c6` - `CL_LoadConsoleHistory` off-by-one plus missing
  NUL-termination, OOB read on mod switch.
- `a18ae32a` - `Key_StringToKeynum` doesn't lowercase single-char bind args,
  so some `bind` commands silently bind the wrong key.
- `8a50e2aa` - Alt+Enter re-toggles fullscreen on every OS key-repeat
  instead of once. Low priority but relevant given this project's own
  documented fullscreen-hazard sensitivity (ADR 0009).
- `84daa282` - `S_TransferPaintBuffer` signed-multiply overflow after
  enough uptime, OOB write into the DMA sound buffer.
- `a167110f` - `S_PaintChannels` mixes a one-shot channel with NULL sound
  data, dereferences NULL.
- `2ef641b9` - `ResampleSfx`/`ResampleSfxRaw` `samplefrac` accumulator
  overflows on long sounds; portable to our mono-only mixer path.
- `57eae5da` - `S_Base_StartBackgroundTrack` calls `Q_strncpyz` with
  aliased src==dst, aborts under some libc's (named as OS X 10.9 upstream;
  our modern reference machine, imac-2019, is worth checking).
- `a836c2db` - `S_FindName` doesn't reject `*`-prefixed names before
  allocating a slot, can return handle 0 for a valid-looking name.
- Most of `snd_openal.c`'s diff: `b8ee77ce`, `efe8437c`, `36a4075a`,
  `5795be68`, `3d69ae99`, `203ab7b9`, `b3bd74fc`, `4fb053b8`, `f61fe5f6`/
  `05858d30` - a cluster of explicitly OS X-labeled OpenAL crash/silence/
  buffer-lifecycle fixes. **NOT APPLICABLE as shipped: an earlier pass
  reasoned from the Makefile's `USE_OPENAL=1` default, but
  `scripts/build.sh:148` overrides it to `USE_OPENAL=0` for every slice, so
  `snd_openal.c` is never compiled.** Revisit only if OpenAL is ever
  enabled; the base sound path fixes (`84daa282`, `a167110f`, `2ef641b9`,
  `57eae5da`, `a836c2db`) are the live ones.

**code/renderergl1/renderercommon** - from the renderer triage pass, ranked
by that pass as highest-value:
1. `a5fbc1bf` - skin-surface Hunk alloc-size bug (confirmed above, single-
   shader-name path only in our tree).
2. `1bb2bc37`+`9f57fea0` - light-grid OOB read (flagged above for one more
   read before patching).
3. `27ddba9c` - no bounds check writing into `skin->surfaces[MD3_MAX_SURFACES]`
   from a `.skin` file with too many surfaces.
4. `d8fd07b6`+`e2503567` - libjpeg errors call `ERR_FATAL`, one corrupt
   `.jpg` in a pk3 kills the whole engine; fix makes it non-fatal
   per-texture.
5. `fda03ee4` - PNG tRNS length check (confirmed above).
6. `8531162b`+`81e2b6c0` - render command buffer can run out of room for
   the swap/end-of-frame command under load, screen stops updating or
   crashes; second part is x86_64-specific padding, relevant to that slice.
7. `e6209f3b` - `tr.refdef.drawSurfs` OOB read with portals/mirrors, wrong
   surface-count variable clamped.
8. `1ba9e7a4` - `RB_SetGL2D` bypasses the `GL_Cull()` state cache (also
   present in `tr_shadows.c`), desyncs cull state for later draws.
9. `c787cf3a` - stencil shadows (`r_shadows 2`) silently stop drawing once
   a batch crosses 500 vertices, shared-buffer aliasing bug.
10. `c8c7bb1d` - entity-parsing premature stop (confirmed above).
11. Shader-parser hardening cluster: `e5f54c58` (uninitialized `rgbGen`
    vector), `eeeaf3f1` (unbounded `strcat` in `tcMod` parsing - our tree's
    `code/renderer/tr_shader.c:986` still has the raw `strcat(buffer, token)`
    this fixes), `3ec2b02d` (unterminated shader block eats the next
    shader), `eb73dcb7` (inverted `&&`/`||` in brace validation).
12. `608e852a` - `tr_font.c` leaks the cached `.dat` font buffer on every
    `RE_RegisterFont` call for an already-registered size - relevant given
    the G3's tight memory budget, and this is the code path we actually
    run (`USE_FREETYPE` is unset).

Also flagged: `cc9072d0` (tr_surface.c, missing overflow check on rail/
lightning trails), `c755d75a` (tr_animation.c, MDR index overflow check
undercounts by 3x - MDR format unused by stock content, low priority),
`621a72e6`/`d38039f9` (tr_bsp.c, null guards in patch stitching),
`6d748965` (tr_curve.c, exact-float-equality tolerance fix for degenerate
patch edges), `d526eacd`+`00c1831e` (tr_flares.c, stale flare coefficient
after `vid_restart`, fog-with-no-fog crash), `2dcc5719` (tr_sky.c, skybox
never sets cull state, order-dependent invisible sky - confirmed relevant,
not yet spot-checked against our tree), `497a74f2` (tr_world.c, shift-by-32
UB on the dlight bitmask when exactly 32 lights are active), `cb2fa48d`
(tr_model.c, off-by-one vertex-count rejection).

**Needs a combined follow-up, not piecemeal**: `30fdd88c`+`59b1262b`+
`6f0736ce`, the float-precision-loss fix spanning `tr_scene.c`, `tr_noise.c`,
`tr_shade.c`, `tr_shade_calc.c`, `tr_local.h`, `tr_backend.c` - widens
`shaderTime`/wave-function time math from float to double/int64, fixes
animated-texture and water/scroll/rotate jitter after long uptime. Real,
CPU-only, applies to every slice, but only coherent as one patch across six
files.

### Not a bug - a legitimate feature-enable opportunity

- `0c3ec34d` - re-enables a `#if 0`'d `RB_DrawSun()` call in
  `tr_backend.c`/`tr_sky.c`, gated on `r_drawSun`. Plain fixed-function
  immediate-mode code, no GLSL/GL2 requirement. Worth a measured try per
  this project's "effects beat fps above the floor" goal - separate from
  this ticket's correctness scope, flag as its own item if pursued.

## What this pass did NOT do

- **Nothing was applied, built, or benched.** Every item above is a
  candidate, not a commit.
- `tr_model_iqm.c` was not deeply reviewed (not rename-matched by git, heavy
  rework, low priority given stock baseq3 doesn't use IQM).
- The `snd_openal.c` cluster and the float-precision cluster were identified
  but not individually verified line-for-line against our current tree.
- No commit here has been checked for whether it still applies cleanly on
  top of this port's own 154 commits of local changes (per-arch config
  system, native dylib loading, watchlink, etc).

## Next steps

Per the ticket's own scope warning, this is deliberately a triage, not an
implementation pass. Suggested order for whoever picks this up next:
1. The five spot-checked, confirmed-present bugs above (tr_bsp.c entity
   parsing, cm_patch.c array size, tr_image.c skin alloc, msg.c bit-reader
   bounds, tr_image_png.c tRNS check) are the safest first patch: all are
   isolated, zero GL/GPU dependency, and confirmed present by reading our
   actual source, not just inferred from the upstream diff.
2. The shader-parser hardening cluster and the OpenAL cluster are next:
   still isolated per-file, but not yet spot-checked here.
3. The float-precision cluster and the files.c/cvar.c security cluster are
   larger units that should be taken (or not) as wholes.
4. Anything taken gets built and smoke-tested at minimum; anything touching
   a hot path (tr_main.c, tr_shade.c, the command-buffer fix) gets benched
   per ADR 0009 before being called done, not assumed safe because the
   upstream commit message says so.
