# Bug-fix log

One line-or-three per real bug fixed: what it was, what the fix was. Newest
first. Not a changelog; routine work and refactors do not belong here.

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
- **2026-08-29** `snd_mix.c`'s AltiVec include guard skipped
  `<altivec.h>` on any `MACOS_X` build (#39), which only works because
  Apple's gcc-4.0.1 exposes `vec_*` as bare compiler built-ins under
  `-faltivec`. A non-Apple GCC (e.g. GCC14 on `imac-2019`) defines none
  of those without the real header, so the guard now also checks
  `__APPLE_ALTIVEC__` (Apple-only macro) before skipping the include.
  Inert under the current build (Apple gcc-4.0.1 always defines
  `__APPLE_ALTIVEC__` under `-faltivec`, so the macro truth table is
  unchanged there); only matters if/when a non-Apple PPC toolchain is
  wired in.
