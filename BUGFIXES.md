# Bug-fix log

One line-or-three per real bug fixed: what it was, what the fix was. Newest
first. Not a changelog; routine work and refactors do not belong here.

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
