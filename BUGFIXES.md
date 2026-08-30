# Bug-fix log

One line-or-three per real bug fixed: what it was, what the fix was. Newest
first. Not a changelog; routine work and refactors do not belong here.

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
