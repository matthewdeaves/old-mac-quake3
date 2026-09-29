# Bugfixes

Search by date or ticket; newest records first.
Archive: `docs/archive/BUGFIXES.md` contains the verbatim detailed accounts.
Dates added to undated accounts identify their recorded evidence or first Git record, not a newly inferred incident date.

## 2026-09-29 `safebench.sh` never launched the game when `baseq3/qconsole.log` was absent
`safebench.sh` never launched the game when `baseq3/qconsole.log` was absent: the pre-clean ssh ended on `mv -f qconsole.log qconsole.log.prev`, which returns 1 with no old log, so `pre_rc=1` skipped the launch and the run read NO-FPS-LINE with empty output.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-09-28 `safebench.sh` ran a full `qsreboot.sh` cycle the instant a single post-run `reachable()` check failed, even though (per the 2026-09-27 fix below) we already knew…
`safebench.sh` ran a full `qsreboot.sh` cycle the instant a single post-run `reachable()` check failed, even though (per the 2026-09-27 fix below) we already knew this box can go briefly unreachable and self-recover with no reboot at all.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-09-27 `safebench.sh`'s reboot backstop (`reboot_m()`) reported "REBOOTING via qsreboot.sh..
`safebench.sh`'s reboot backstop (`reboot_m()`) reported "REBOOTING via qsreboot.sh...
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-09-23 `deploy-dmg.sh` never detached the DMG on Panther
`deploy-dmg.sh` never detached the DMG on Panther: it detached by mountpoint, and Panther's `hdiutil detach` takes only a device name, so it failed silently (`-force` too).
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-09-23 `smoke-dmg.sh`'s bare-`open` pre-check could hang forever on Tiger's first-launch consent dialog (`open` blocked in `LSConsentToLaunch`), holding the bench claim
`smoke-dmg.sh`'s bare-`open` pre-check could hang forever on Tiger's first-launch consent dialog (`open` blocked in `LSConsentToLaunch`), holding the bench claim.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-09-02 `Fix Launch Problems.command`'s local-disk-copy fix (below) was not actually sufficient for `set-bundle-bit`
`Fix Launch Problems.command`'s local-disk-copy fix (below) was not actually sufficient for `set-bundle-bit`.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-09-02 `Fix and Install.command` copied `ioquake3.app` to `~/Applications/quake3` instead of fixing it wherever the user actually put it -- inconsistent with quakespasm and…
`Fix and Install.command` copied `ioquake3.app` to `~/Applications/quake3` instead of fixing it wherever the user actually put it -- inconsistent with quakespasm and alephone, both reworked the same day to fix-in-place (user drags the game where they want; the command just clears quarantine/bundle-bit and re-registers there), and not what the user asked for: "the command…
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-09-02 `Fix and Install.command` (shipped in v0.6.12, same day) silently never cleared quarantine on a real browser-downloaded DMG
`Fix and Install.command` (shipped in v0.6.12, same day) silently never cleared quarantine on a real browser-downloaded DMG.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-09-02 DMG install could App-Translocate on modern macOS
DMG install could App-Translocate on modern macOS.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-30 `code/rend2/tr_image_jpg.c`'s `R_JPGErrorExit` called `ri.Error(ERR_FATAL, ...)` unconditionally on any libjpeg decode error (#41) - no `setjmp`/`longjmp` recovery at…
`code/rend2/tr_image_jpg.c`'s `R_JPGErrorExit` called `ri.Error(ERR_FATAL, ...)` unconditionally on any libjpeg decode error (#41) - no `setjmp`/`longjmp` recovery at all, unlike `code/renderer/tr_image_jpg.c` (fixed for the classic renderer back in `40e10ce3`, #17).
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-29 Seven files' AltiVec include guards (`snd_mix.c`, `renderer/tr_shade.c`, `renderer/tr_shade_calc.c`, `renderer/tr_surface.c`, `rend2/` copies of the same three)…
Seven files' AltiVec include guards (`snd_mix.c`, `renderer/tr_shade.c`, `renderer/tr_shade_calc.c`, `renderer/tr_surface.c`, `rend2/` copies of the same three) skipped `<altivec.h>` on any `MACOS_X` build (#39), which only works because Apple's gcc-4.0.1 exposes `vec_*` as bare compiler built-ins under `-faltivec`.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-29 `imac-2019` and `imac-g5` shipped `com_maxfps "0"` (uncapped) like every other machine tier, but unlike `arm64` and `quad-g5` never got the fix those two tiers…
`imac-2019` and `imac-g5` shipped `com_maxfps "0"` (uncapped) like every other machine tier, but unlike `arm64` and `quad-g5` never got the fix those two tiers already carry for the same bug: at high enough fps the client's `CMD_BACKUP` (64-slot) usercmd ring wraps faster than a real internet round trip, so `CG_DrawDisconnect` (`cg_draw.c`) declares a healthy connection…
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-28 `smoke-dmg.sh`/`bench.sh`/`safebench.sh` deleted `baseq3/qconsole.log` as pre-launch "clean slate" setup, destroying the previous run's evidence right when a…
`smoke-dmg.sh`/`bench.sh`/`safebench.sh` deleted `baseq3/qconsole.log` as pre-launch "clean slate" setup, destroying the previous run's evidence right when a crash/hang needs it (cross-port finding from old-mac-half-life-1 ADR 0018, same bug there).
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-28 Filesystem crash cluster, six upstream fixes (#17, `750a15c8`)
Filesystem crash cluster, six upstream fixes (#17, `750a15c8`): `FS_FOpenFileReadDir` left a stale non-zero handle on not-found; `FS_Seek` double-seeked a streamed file and discarded the correct result; `FS_CreatePath` incremented a NULL pointer on any path with no separator; `FS_CheckPak0` dereferenced `path->pack` one line before its own NULL guard;…
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-28 ppc750 build broken by `CFErrorRef` (#37, `b9f002a1`)
ppc750 build broken by `CFErrorRef` (#37, `b9f002a1`): `b7a99846`'s App Translocation fix used a Leopard-only CoreFoundation type in a file that builds once from shared source across every slice.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-25 Net message, patch collision, and infostring security and bounds fixes (#17, `cc0b3e68`)
Net message, patch collision, and infostring security and bounds fixes (#17, `cc0b3e68`): MSG_ReadBits/MSG_WriteBits buffer overflow checks and exact limits (upstream d2b1d124/1e309787/3a702ded); Huffman compressor/decompressor maxoffset bounds; q3msgboom crash in MSG_ReadString (9f294ce5); MSG_ReadDeltaKey mask indexing fix (b4ad5a84); CM_AddFacetBevels bounds and…
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-25 Float-precision loss in shader and wave time math (#17, `33e83a11`, upstream 30fdd88c/59b1262b/6f0736ce)
Float-precision loss in shader and wave time math (#17, `33e83a11`, upstream 30fdd88c/59b1262b/6f0736ce): shaderTime, floatTime, clampTime, and timeOffset widened to double; wave-value, turbulent, and rotate calculations use int64_t; animated-image index modulus replaced with wrap loop.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-23 Seventeen renderer fixes from upstream (#17, `40e10ce3`)
Seventeen renderer fixes from upstream (#17, `40e10ce3`): one corrupt .jpg in a pk3 killed the whole engine (now non-fatal per texture), light-grid OOB reads, drawSurfs overflow clamped on the wrong variable with portals/mirrors, skybox cull-state order dependency, shift-by-32 UB at exactly 32 dlights, stencil shadows dying past 500-vertex batches, font cache leak per…
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-23 Any ERR_DROP during Com_Init segfaulted instead of exiting with "Error during initialization" (#36, `c2fa4e50`)
Any ERR_DROP during Com_Init segfaulted instead of exiting with "Error during initialization" (#36, `c2fa4e50`): CL_ClearMemory dereferenced com_sv_running before that cvar is registered.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-23 Nine client/net fixes from upstream (#17, `4c29d38e`)
Nine client/net fixes from upstream (#17, `4c29d38e`): snapshot delta against an overwritten parseEntities slot, VOIP sender index read before range check, connect-string and serverinfo buffer overflows, connectionless print/echo accepted from any address, console history OOB, bind case-sensitivity, Alt+Enter repeat.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-23 Ten filesystem/cvar security holes from upstream (#17, `4f1e8cb5`)
Ten filesystem/cvar security holes from upstream (#17, `4f1e8cb5`): VM/server could rewrite protected cvars, fs_game accepted `..` traversal from a malicious server, VM could write files with dylib/qvm/pk3 extensions, autoexec/q3config could load out of pk3s.
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-23 Sound mixer OOB writes (#17, `eca6aa54`)
Sound mixer OOB writes (#17, `eca6aa54`): resampler `samplefrac` accumulator overflowed on long sounds (upstream 2ef641b9), paint-buffer index went negative after ~4.5 h uptime (84daa282), NULL soundData mixed (a167110f), background-track restart called Q_strncpyz with src==dst (57eae5da).
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-23 Shader parser accepted `name {garbage` and a missing closing brace silently ate the next shader file's first shader (#17, `9d94ce5b`, upstream eb73dcb7/3ec2b02d);…
Shader parser accepted `name {garbage` and a missing closing brace silently ate the next shader file's first shader (#17, `9d94ce5b`, upstream eb73dcb7/3ec2b02d); tcMod args overflowed a 1024 buffer via raw strcat (eeeaf3f1); rgbGen const read uninitialized stack (e5f54c58); flares died after vid_restart (d526eacd) and fogged with fogNum 0 (00c1831e); rail/lightning…
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.

## 2026-08-23 Map entity lump parsing stopped at the first empty key/value, silently dropping every later entity (#17, `d35fb252`, upstream c8c7bb1d); skin Hunk_Alloc took…
Map entity lump parsing stopped at the first empty key/value, silently dropping every later entity (#17, `d35fb252`, upstream c8c7bb1d); skin Hunk_Alloc took sizeof(pointer) not sizeof(struct) at two sites (a5fbc1bf); PNG tRNS length check could never fire, `(!x) == 2` (fda03ee4).
Full cause, fix and evidence: `docs/archive/BUGFIXES.md`, search the distinctive heading text.
