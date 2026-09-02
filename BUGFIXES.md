# Bug-fix log

One line-or-three per real bug fixed: what it was, what the fix was. Newest
first. Not a changelog; routine work and refactors do not belong here.

- **2026-09-02** `Fix Launch Problems.command`'s local-disk-copy fix (below)
  was not actually sufficient for `set-bundle-bit`. Caught before shipping
  by re-testing the fix-in-place rework against a copy carrying real
  `com.apple.quarantine` xattrs end to end (not the DMG-volume scenario
  alone): after copying the helpers to `$STAGE` per the fix below,
  `set-bundle-bit` still got silently SIGKILLed running from there --
  `clear-launch-quarantine.sh` (a script, interpreted by the Apple-signed
  `/bin/sh`) did not. Different mechanism: the volume-level
  `AppleSystemPolicy` block documented below is specific to code executing
  off a translocated/quarantined DMG volume; this is the ordinary
  per-binary Gatekeeper code-signature check, which fires on any `execve`
  of quarantined unsigned Mach-O regardless of which volume it is on.
  Fix: `xattr -d com.apple.quarantine` on each file in `$STAGE` right after
  copying it, before running it -- confirmed this alone is enough, no
  ad-hoc signing needed. Only the throwaway `$STAGE` copies are touched,
  never the shipped originals, so a re-run always starts clean.
- **2026-09-02** `Fix and Install.command` copied `ioquake3.app` to
  `~/Applications/quake3` instead of fixing it wherever the user actually
  put it -- inconsistent with quakespasm and alephone, both reworked the
  same day to fix-in-place (user drags the game where they want; the
  command just clears quarantine/bundle-bit and re-registers there), and
  not what the user asked for: "the command should come in the dmg to be
  run in same folder as the fat binary etc." Renamed to
  `Fix Launch Problems.command` and reworked: no more copy step, it now
  operates on `ioquake3.app` next to itself (`$DIR`, not a hardcoded
  `~/Applications/quake3`), and refuses early with a clear message if `$DIR`
  is not writable (the app is still on the read-only mounted image and
  needs dragging out first -- quarantine can't be cleared on a read-only
  volume anyway, so this used to fail with a confusing `xattr` error
  instead). `fix-support/` (the sidecar copies of
  `clear-launch-quarantine.sh` and `set-bundle-bit`) is now shipped
  VISIBLE, no leading dot -- it has to travel along with a plain
  "drag everything out of this window" gesture, which a hidden dir would
  silently miss. The local-disk-copy-before-exec trick from the fix below
  is unchanged and still required regardless of copy-vs-in-place: the
  SIGKILL is about the volume code executes FROM, not about where the app
  ends up.
- **2026-09-02** `Fix and Install.command` (shipped in v0.6.12, same day)
  silently never cleared quarantine on a real browser-downloaded DMG. It ran
  its two helper executables (`set-bundle-bit`, `clear-launch-quarantine.sh`)
  straight off the mounted disk image. Found by actually reproducing the
  install with a real GitHub-downloaded DMG (not a synthetic local test): both
  helpers got silently SIGKILLed with zero output, confirmed via the unified
  log (`kernel: (AppleSystemPolicy) ASP: Security policy would not allow
  process: ..., /Volumes/.../.fix-support/clear-launch-quarantine.sh`). A real
  browser download's mounted DMG volume is itself quarantined and read-only;
  macOS silently kills any unsigned executable run directly from it, no
  dialog, nothing to approve. The installed app was left still quarantined and
  wouldn't launch, despite the script printing "Done." Fix: copy both helpers
  to local disk (`$DEST/.fix-support/`) before running them - a plain `cp` off
  that same quarantined volume is not subject to the block, only direct
  execution from it is. My earlier "verified" claim for v0.6.12 was a
  synthetic dry run (fake `.app`, no real quarantine xattr involved) and did
  not catch this - only a real downloaded DMG does.
- **2026-09-02** DMG install could App-Translocate on modern macOS. The
  README's only fix was "run `xattr -dr com.apple.quarantine` by hand" -- not
  a fix per CLAUDE.md ("Quarantine fix must be tooling, not a human step").
  `scripts/clear-launch-quarantine.sh` already existed in this repo (synced
  from old-mac-build-host) but was never called by `make-dmg.sh` or
  `deploy-dmg.sh` -- dead tooling. quakespasm and alephone hit and fixed the
  identical failure on `imac-2019` the same day. Shipped the actual fix:
  `scripts/bundle/Fix-and-Install.command`, now bundled on every DMG from
  `make-dmg.sh`, that a user right-click-Opens once -- it installs to
  `~/Applications/quake3`, sets the Finder bundle bit
  (`scripts/bundle/set-bundle-bit`, Panther/Tiger only need it, no-op
  elsewhere), and clears quarantine. All three steps are safe no-ops on
  Panther/Tiger/Leopard/Lion, which predate Gatekeeper/quarantine/App
  Translocation entirely, so the one script covers the whole fleet (G3/G4/G5
  PowerPC through Apple Silicon) rather than needing a PPC-only manual path.
  README.md and the in-DMG README.txt both lead with it now; the old manual
  `xattr` instruction is now the documented fallback for a device data
  drag-install, not the primary path.
- **2026-08-30** `code/rend2/tr_image_jpg.c`'s `R_JPGErrorExit` called
  `ri.Error(ERR_FATAL, ...)` unconditionally on any libjpeg decode error (#41)
  - no `setjmp`/`longjmp` recovery at all, unlike `code/renderer/tr_image_jpg.c`
  (fixed for the classic renderer back in `40e10ce3`, #17). A bad/non-JPEG
  levelshot would take the whole client down instead of failing that one
  image load, same class of bug upstream's `d8fd07b6`/`e2503567` already fixed
  for the classic renderer. Ported the identical setjmp-based recovery into
  rend2's copy. Not the cause of the live crash reported in #41 (this port
  never ships the rend2 binary - `USE_RENDERER_DLOPEN=0` statically links
  classic opengl1 only, confirmed in `scripts/build.sh`/the Makefile's
  `TARGETS` logic) - that crash traced to a stale client build plus one
  bit-rotted texture in the user's own `pak0.pk3` (not this repo's data, fixed
  by replacing the file from a known-good fleet copy). Logging this fix
  because it is real and rend2 remains a shipped source path even if not the
  active binary today.
- **2026-08-28** `smoke-dmg.sh`/`bench.sh`/`safebench.sh` deleted
  `baseq3/qconsole.log` as pre-launch "clean slate" setup, destroying the
  previous run's evidence right when a crash/hang needs it (cross-port
  finding from old-mac-half-life-1 ADR 0018, same bug there). Now rotates
  to `qconsole.log.prev` instead of `rm -f`. Verified live on quicksilver:
  two consecutive smoke runs left both files with distinct content/mtimes,
  not one overwritten copy.
- **2026-08-28** Filesystem crash cluster, six upstream fixes (#17,
  `750a15c8`): `FS_FOpenFileReadDir` left a stale non-zero handle on
  not-found; `FS_Seek` double-seeked a streamed file and discarded the
  correct result; `FS_CreatePath` incremented a NULL pointer on any path
  with no separator; `FS_CheckPak0` dereferenced `path->pack` one line
  before its own NULL guard; `FS_AddGameDirectory`'s `qsort` had no guard
  against a NULL file list; `RB_MDRSurfaceAnim`'s overflow check
  undercounted the index buffer by 3x.
- **2026-08-28** ppc750 build broken by `CFErrorRef` (#37, `b9f002a1`):
  `b7a99846`'s App Translocation fix used a Leopard-only CoreFoundation type
  in a file that builds once from shared source across every slice. Caught
  by triggering a real release-candidate build via `pipeline-quake3`, not by
  CI - green CI does not build this target. Fixed to `void *`/`void **`,
  which is ABI-identical and compiles on every SDK in the fleet.
- **2026-08-25** Net message, patch collision, and infostring security and bounds fixes (#17,
  `cc0b3e68`): MSG_ReadBits/MSG_WriteBits buffer overflow checks and exact
  limits (upstream d2b1d124/1e309787/3a702ded); Huffman compressor/decompressor
  maxoffset bounds; q3msgboom crash in MSG_ReadString (9f294ce5); MSG_ReadDeltaKey
  mask indexing fix (b4ad5a84); CM_AddFacetBevels bounds and CM_EdgePlaneNum
  null plane guard (ee2541ef/077ab4cb); Q_IsColorString signed-char UB guard
  (a6df505d); Info_RemoveKey memmove fix for overlapping buffers (c52e35bc);
  case-insensitive Info_Key handling (9c29b25a); stricter Info_Validate (a6f949c8).
- **2026-08-25** Float-precision loss in shader and wave time math (#17,
  `33e83a11`, upstream 30fdd88c/59b1262b/6f0736ce): shaderTime, floatTime,
  clampTime, and timeOffset widened to double; wave-value, turbulent, and
  rotate calculations use int64_t; animated-image index modulus replaced
  with wrap loop. Prevents animation and texture jitter after long uptime.
- **2026-08-23** Seventeen renderer fixes from upstream (#17, `40e10ce3`):
  one corrupt .jpg in a pk3 killed the whole engine (now non-fatal per
  texture), light-grid OOB reads, drawSurfs overflow clamped on the wrong
  variable with portals/mirrors, skybox cull-state order dependency,
  shift-by-32 UB at exactly 32 dlights, stencil shadows dying past
  500-vertex batches, font cache leak per RE_RegisterFont call, render
  command buffer running out of room for the swap command.
- **2026-08-23** Any ERR_DROP during Com_Init segfaulted instead of exiting
  with "Error during initialization" (#36, `c2fa4e50`): CL_ClearMemory
  dereferenced com_sv_running before that cvar is registered. NULL guard,
  matching upstream's current shape.
- **2026-08-23** Nine client/net fixes from upstream (#17, `4c29d38e`):
  snapshot delta against an overwritten parseEntities slot, VOIP sender
  index read before range check, connect-string and serverinfo buffer
  overflows, connectionless print/echo accepted from any address, console
  history OOB, bind case-sensitivity, Alt+Enter repeat.

- **2026-08-23** Ten filesystem/cvar security holes from upstream (#17,
  `4f1e8cb5`): VM/server could rewrite protected cvars, fs_game accepted
  `..` traversal from a malicious server, VM could write files with
  dylib/qvm/pk3 extensions, autoexec/q3config could load out of pk3s.
  Ported upstream's settled fixes (FS_InvalidGameDir, Sys_DllExtension,
  Cvar_Register flag scrubbing).
- **2026-08-23** Sound mixer OOB writes (#17, `eca6aa54`): resampler
  `samplefrac` accumulator overflowed on long sounds (upstream 2ef641b9),
  paint-buffer index went negative after ~4.5 h uptime (84daa282), NULL
  soundData mixed (a167110f), background-track restart called Q_strncpyz
  with src==dst (57eae5da).
- **2026-08-23** Shader parser accepted `name {garbage` and a missing
  closing brace silently ate the next shader file's first shader (#17,
  `9d94ce5b`, upstream eb73dcb7/3ec2b02d); tcMod args overflowed a 1024
  buffer via raw strcat (eeeaf3f1); rgbGen const read uninitialized stack
  (e5f54c58); flares died after vid_restart (d526eacd) and fogged with
  fogNum 0 (00c1831e); rail/lightning surfaces wrote past the tess buffer
  (cc9072d0).
- **2026-08-23** Map entity lump parsing stopped at the first empty
  key/value, silently dropping every later entity (#17, `d35fb252`,
  upstream c8c7bb1d); skin Hunk_Alloc took sizeof(pointer) not
  sizeof(struct) at two sites (a5fbc1bf); PNG tRNS length check could
  never fire, `(!x) == 2` (fda03ee4).
- **2026-08-29** Seven files' AltiVec include guards (`snd_mix.c`,
  `renderer/tr_shade.c`, `renderer/tr_shade_calc.c`, `renderer/tr_surface.c`,
  `rend2/` copies of the same three) skipped `<altivec.h>` on any `MACOS_X`
  build (#39), which only works because Apple's gcc-4.0.1 exposes `vec_*` as
  bare compiler built-ins under `-faltivec`. First attempt gated the skip on
  `__APPLE_ALTIVEC__` too (Apple-only macro) - measured wrong against a real
  build: the imac-2019 GCC14 cross-toolchain targets
  `powerpc-apple-darwin8` and defines `__APPLE_ALTIVEC__`/`__APPLE_CC__`
  itself for compatibility, so that guard still skipped the include and
  failed with "implicit declaration of vec_splat_u32" etc. Real
  discriminator is `__GNUC__`: Apple never shipped a PowerPC gcc past 4.x,
  so `__GNUC__ >= 5` on a `MACOS_X` build is always a non-Apple compiler.
  `q_platform.h`'s `VECCONST_UINT8` macro had the identical MACOS_X-assumes-
  Apple bug (Apple's parenthesized vector-literal syntax vs. the standard
  braced compound-literal one) and got the same fix.
  Also hit and fixed: `rend2/tr_bsp.c` passes a `uint32_t*` where
  `code/SDL12/include/SDL_opengl.h`'s own `typedef unsigned long GLuint`
  wants a `GLuint*` - same 4-byte type on this 32-bit target either way,
  but GCC14 makes this class of mismatch a hard error by default where
  Apple's gcc-4.0.1 only warned (`-Wno-error=incompatible-pointer-types`
  added to the GCC14 build path only, no source change).
  End result: `scripts/build.sh g3` and `g4` now build and link clean
  end-to-end via `imac-2019`'s GCC14 (opt-in, `BUILD_HOST=imac-2019`) -
  correct `ppc750`/`ppc7400` cpusubtype confirmed via `lipo` on both. Also
  regression-built g4 on the real production toolchain (`mini-intel`,
  Apple gcc-4.0.1) after these changes - clean, unaffected (`__GNUC__ >= 5`
  is false there, so every changed guard takes its original branch).
  Not yet done: a real hardware timedemo/launch proof of a GCC14-built
  binary, and a build-time comparison against `mini-intel` - see ADR 0020.
- **2026-08-29** `imac-2019` and `imac-g5` shipped `com_maxfps "0"`
  (uncapped) like every other machine tier, but unlike `arm64` and
  `quad-g5` never got the fix those two tiers already carry for the same
  bug: at high enough fps the client's `CMD_BACKUP` (64-slot) usercmd ring
  wraps faster than a real internet round trip, so `CG_DrawDisconnect`
  (`cg_draw.c`) declares a healthy connection dead - "Connection
  Interrupted" icon, `MAX_PACKET_USERCMDS` console spam, and broken
  movement, single player unaffected (loopback keeps pace fine). Reported
  live (#40) on `imac-2019` against a real internet server; user confirmed
  `/com_maxfps 125` in-console clears it immediately. Fixed at the source
  (`com_maxfps "125"`, matching the arm64/quad-g5 configs exactly) for
  `imac-2019`; applied the same fix to `imac-g5` as a preventive parity fix
  (same "no fps floor" class of machine, not independently reproduced
  there).
