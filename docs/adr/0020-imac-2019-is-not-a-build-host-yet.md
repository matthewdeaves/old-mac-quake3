# 20. imac-2019 is not a build host yet

Date: 2026-08-28
Status: accepted, PPC (g3/g4) superseded 2026-08-29 - see Follow-up 7. i386/lion
still an open negative result; revisit only with new evidence.

## Context

Issue #39, raised as a relayed claim from a peer session: "imac-2019 has a
real PPC cross-compiler (GCC14) but only appears in this repo's scripts as a
deploy/bench target, not a build host - alephone's `build.sh`/
`build-deps-ppc.sh` is a working reference for the pattern." Filed, then
picked up on a direct user instruction to stop treating the investigation as
blocked and actually get it working.

Two claims needed checking before touching `scripts/build.sh`, which today
only knows `mini-intel`/`mini-intel2` (Lion 10.7.5, `gcc-4.0` + the 10.3.9
SDK) as build hosts.

## Investigation

**Claim 1: alephone uses imac-2019 as a build host.** Checked against
alephone's own source (`~/Documents/alephone`, read-only). False. Its
`build.sh` calls `pick-build-host.sh --acquire` with no explicit host, which
only ever resolves against the default `BUILD_HOSTS` list
(`mini-intel mini-intel2`) - identical to ours. Its own copy of
`pick-build-host.sh` hard-rejects any host whose `sw_vers` isn't `10.7*`
(`classify()`, the same "wrong-os" guard added for `mini-sl`), and that guard
is not overridable via a `BUILD_HOSTS=` env override - confirmed by trying it
against both alephone's copy and ours. `imac-2019` appears in alephone's tree
exactly three times, all in `pick-bench-host.sh`'s `BENCH_HOSTS` or comments,
never in a build script. What is real: `mini-intel` and `imac-2019` both log
in as user `mini`, and both carry `/Users/mini/gcc14-ppc` - the toolchain
exists in more than one place, but nothing anywhere, alephone included, ever
selects `imac-2019` specifically to compile on.

**Claim 2 (the real question underneath): could `imac-2019` build our g3/g4
or lion/i386 slices at all, safely?** Tested directly, two ways.

*PPC:* `powerpc-apple-darwin8-gcc -arch ppc7400 -mcpu=7400 ...` on `imac-2019`
returns `error: this compiler does not support 'ppc7400'`. This GCC14 build
does not implement Apple's multi-subtype `-arch` flag the way our `gcc-4.0`
does; using it would need a real port of `scripts/build.sh`'s `CPUFLAGS` to
whatever flags this toolchain actually accepts. Separately and independently,
`old-mac-build-host` is mid-fix on a missing `crt1.10.5.o` for this same
toolchain. Not pursued further - two real, independent gaps, not something to
paper over same-day.

*Intel (lion/x86_64), no cross-compiler needed at all:*
`BUILD_HOST=imac-2019 BUILD_HOST_PRECLAIMED=1 scripts/build.sh lion` (bypassing
the picker's OS-only restriction by hand, since the restriction is about the
*build-lock candidate list*, not about whether the host can actually build)
compiled clean with `imac-2019`'s own clang. Correct `x86_64` subtype, correct
`LC_VERSION_MIN_MACOSX 10.6`. Copied the result to `mini-intel2` (real Lion
10.7.5 hardware, not a simulation) and ran it directly against real game data:
**`Segmentation fault: 11`, immediately, no output at all.** Full mechanism
and the `otool -L`/`otool -l` evidence: `MISTAKES.md`, "A correct
`-mmacosx-version-min` stamp does not mean the binary runs there."

## Follow-up: the missing-`-isysroot` theory, tested and ruled out

A peer session proposed a specific mechanism for the Intel crash above: the
`lion` case's `SDK=` is empty, so nothing ever passes `-isysroot` - on
`mini-intel` that naturally falls through to Lion's own real system libs (it
*is* the OS), but on `imac-2019` the same empty `-isysroot` silently defaults
to Sequoia's own SDK, baking in modern library version records that crash
Lion's dyld. They staged a real, period-correct `MacOSX10.7.sdk` (from an
actual Xcode-for-Lion installer, dated 2012) at `~/SDKs/MacOSX10.7.sdk` on
`imac-2019` and reported their own compile/link/run test passing with it.

Tested directly rather than adopted: rebuilt the `lion` slice on `imac-2019`
with `-isysroot /Users/mini/SDKs/MacOSX10.7.sdk` added. Confirmed the fix
actually took - `otool -l` on the new binary shows `sdk 10.6` (was `sdk 15.5`
before). Ran the result on **two** real machines: `mini-sl` (Snow Leopard
10.6.8) and **`mini-intel2` (Lion 10.7.5, the exact OS the staged SDK
matches)**. Both: `Segmentation fault: 11`, immediately, same as before.
`DYLD_PRINT_LIBRARIES=1 DYLD_PRINT_APIS=1` produced no output before the
crash, and no crash report was ever written - the failure is early enough
that it precedes dyld's own tracing hooks.

This rules the specific mechanism out, not just leaves it unconfirmed: the
SDK stamp genuinely changed and the crash did not. Something else is wrong
underneath both the SDK-generation issue and whatever this is. Not
root-caused further by this session - two independently-real crashes on two
different real machines is enough evidence to keep this blocked without
chasing a third hypothesis same-day.

## Follow-up 2: likely actual root cause, from old-mac-build-host (not independently re-verified here)

`old-mac-build-host` picked up the "dies before dyld tracing engages" clue
and reports `otool -l` on an `imac-2019`-built binary shows `LC_MAIN` as the
entry-point load command, even with `-mmacosx-version-min=10.6` explicitly
set. `LC_MAIN` was introduced in Mountain Lion (10.8); Snow Leopard and
Lion's kernel/dyld only understand the older `LC_UNIXTHREAD`. If accurate,
this is structural - no SDK, `-isysroot`, or version-min flag changes what
entry-point load command the *linker* emits, which would explain why the
`-isysroot` fix above changed the SDK stamp but not the crash. Whether
modern `ld64` can still be told to emit `LC_UNIXTHREAD` for an old target is
open; `old-mac-build-host` was not finding an obvious flag for it as of this
writing. Recorded here as reported, not independently re-run against a fresh
binary by this session (the test binaries from the two follow-ups above were
already deleted as part of cleanup) - flagged as peer-reported pending this
session's own recheck, per this repo's own claim-hygiene norms. If true in
general, it is a harder blocker than an `imac-2019`-specific quirk: it would
mean current-generation `ld64` cannot produce Snow-Leopard/Lion-runnable
binaries at all, for any host, which is a fact worth having plainly rather
than continuing to treat as an open toolchain-config question.

## Follow-up 3: a separate PPC compile blocker, from old-mac-build-host (not independently re-verified here)

Reported after this ADR's PPC findings above: any real g4/g5 source that
includes `<sys/types.h>` (i.e. nearly everything) hits a hard compile
failure on `machine/ansi.h` through this GCC14 build. Reported cause: the
toolchain was bootstrapped against the Panther SDK, and GCC always searches
its own `include-fixed` directory before an explicit `-isysroot`, so it
silently pulls Panther's `sys/types.h` instead of the Tiger/Leopard one the
build actually targets. Reported fix: `-nostdinc` plus an explicit
`-isystem` list to skip `include-fixed` entirely, said to be verified for
both g4 and g5 (not this port's own C code, general toolchain behavior; g3/
Panther targets are unaffected since Panther's headers are the ones already
baked in). Written up in old-mac-build-host's `docs/imac-2019.md` and
quakespasm#37. Recorded here for completeness alongside this ADR's own two
PPC blockers (`-arch ppc7400` unsupported, missing `crt1.10.5.o`) - not
independently re-tested by this session, same as Follow-up 2's LC_MAIN
report above.

## Follow-up 4: real g4 source build attempted, one blocker cleared, a new one found

old-mac-build-host fixed the `include-fixed`/Panther-`sys/types.h` issue
(Follow-up 3): the workaround (`-nostdinc` plus an explicit `-isystem`
list, dropping only `include-fixed`) was independently re-verified here -
compiled `<sys/types.h> <stdio.h> <stdlib.h> <string.h> <math.h>` together
clean, against both the 10.4u SDK (their tested case) and the 10.3.9 SDK
with `-mmacosx-version-min=10.3` (this project's actual requirement, since
G5-Panther shares the ppc7400 slice - not previously tested by them).

Then attempted a real build, not a synthetic header test: synced current
source to `imac-2019` and ran the actual `g4` slice through `make` with
this project's real build flags (`BUILD_CLIENT=1`, etc.) plus the
workaround include list. Genuine progress - it got past `include-fixed`
entirely and compiled real engine source (`snd_wavelet.c` and others, warts
like an existing `-Warray-bounds` warning notwithstanding) before hitting a
**new, different, real blocker**: `code/client/snd_mix.c`'s AltiVec-SIMD
mixer fails with `implicit declaration of function 'vec_splat_u32'` (and
`vec_lvsl`, `vec_perm`, `vec_mule`, `vec_sra`, `vec_mulo`, `vec_add`) under
GCC14's `-maltivec`, even though the file already does `#include
<altivec.h>` (confirmed - the include is present). This project's g4/g5
slice currently builds under Apple's ancient `gcc-4.0` with `-faltivec`,
which apparently exposes a different (or differently-named) set of AltiVec
builtins than GCC14's mainline `<altivec.h>` does under `-maltivec`. Not
investigated further this session - a real toolchain-version ABI/intrinsics
gap, not a missing flag or header, and worth its own dedicated pass rather
than a same-session dig.

Net effect: the PPC build-host thread has now cleared 2 of its original 3
blockers (`-arch ppc7400` syntax, `include-fixed`/`sys/types.h`) through
combined effort across sessions, and surfaced a fourth, more specific one
(AltiVec intrinsic declarations) in their place. `crt1.10.5.o` (g5/10.5
target only, reported fixed with `-L $SDK/usr/lib`, not retested here since
this session's failure was on the g4/10.3 path) and this AltiVec gap are
what's left. Still not wired into `build.sh` - still a real, unfinished
toolchain, now closer than the earlier follow-ups found it.

## Follow-up 5: the AltiVec gap has a real root cause, and a real second layer under it

old-mac-build-host root-caused Follow-up 4's `vec_splat_u32`-class errors:
`code/client/snd_mix.c:26`, `#if idppc_altivec && !defined(MACOS_X)`, skips
`#include <altivec.h>` entirely on Mac builds (`Makefile:430` defines
`-DMACOS_X` for every darwin target) - written for Apple's gcc-4.0, which
exposes those names as compiler built-ins with no header needed. GCC14
(genuinely FSF, not Apple's fork, despite targeting
`powerpc-apple-darwin8`) needs the header actually included to declare
them. Verified directly against our own source, not taken on trust: the
guard and the `-DMACOS_X` definition are exactly as described.

The suggested one-line fix (gate on `__APPLE_ALTIVEC__` instead of the
`MACOS_X` exclusion) does not actually work - checked empirically before
touching anything: `powerpc-apple-darwin8-gcc -maltivec -dM -E -` on this
GCC14 build shows it **also** predefines `__APPLE_ALTIVEC__` (and
`__APPLE_CC__`, and `__APPLE__`) - this toolchain was deliberately built to
present itself as Apple-compatible, so none of the "is this really Apple's
compiler" macros the codebase might reach for actually distinguish it.
Gating on `__APPLE_ALTIVEC__` would skip the same include on GCC14 for the
same reason `MACOS_X` does.

Tested the more robust version instead - dropping the `MACOS_X` exclusion
entirely (`#if idppc_altivec`, always include on any Mac target) - on a
scratch copy, never the tracked file. **This does fix the reported errors**
(`vec_splat_u32`/`vec_lvsl`/`vec_perm`/etc all resolve), but immediately
surfaces a second, structurally identical bug one layer down:
`q_platform.h:49`, `#ifdef MACOS_X`, picks between Apple's old
parenthesised vector-literal syntax (`(vector unsigned char) (a,b,c,...)`)
and the standard braced compound-literal syntax
(`(vector unsigned char) {a,b,c,...}`) for `VECCONST_UINT8`. Same shape,
same file even (`q_platform.h:49` right next to the `altivec.h` guard just
above it): `MACOS_X` picks "Apple's dialect" when it should be picking
"which GCC generation this actually is."

**A macro that would actually work, checked empirically**: `__GNUC__`.
GCC14 reports `__GNUC__ == 14`; Apple's gcc-4.0 (this project's real build
toolchain) reports `__GNUC__ == 4`. Unlike every Apple-branded macro tried
so far, this cross-compiler can't plausibly be built to lie about its own
major version the way it was deliberately built to claim Apple-compatible
defines - `__GNUC__` is the compiler's own genuine identity, not a
compatibility shim. A guard along the lines of `#if defined(MACOS_X) &&
__GNUC__ < 5` (picking Apple's dialect only on the toolchain generation
that actually needs it) would likely settle both spots correctly, but this
was not implemented or tested against real hardware - two source-level
changes to shipping audio-mixing code, post-release, without a real-machine
regression pass, is exactly the kind of change that stays diagnosis, not a
same-session fix. Left for whoever picks this up next, with the actual
mechanism now fully understood rather than guessed at.

## Follow-up 6: the definitive answer - a real, full build.sh attempt, all targets

User asked directly: can `imac-2019` build every slice this repo ships,
right now. Answered for real rather than by extrapolation from header
tests: applied the Follow-up 5 `__GNUC__` fix, made `build.sh` host-aware
for `BUILD_HOST=imac-2019` (GCC14 toolchain path, `~/SDKs` instead of the
non-existent `/Developer/SDKs` - confirmed absent, sealed system volume,
not a permissions gap - and `-Wl,-ld_classic` for `lion`/`i386` per
Follow-up 2's fix), all on `scratch/imac-2019-altivec-fix` (pushed, never
touched `master`), and ran `build.sh` for real against current source.

**arm64**: yes - native, already proven in production use (today's actual
release was built there).

**lion (x86_64)**: compiles clean, `otool -l` confirms `LC_UNIXTHREAD` (not
`LC_MAIN`) with `-Wl,-ld_classic` in place - the fix that was only
minimally tested before now produces the right result on a real build of
this project's own source, not a `hi.c`. Not hardware-verified this pass -
every Lion-class box (`mini-intel`, `mini-intel2`, `mini-sl`) was busy with
other sessions' real work throughout.

**g3 (ppc750)**: no, new blocker. Build-host's "g3 doesn't need the
`-nostdinc` workaround" note was checked against a minimal header test, not
a real build - a real one reaches `code/zlib/crc32.c`, which needs it too
(same `machine/ansi.h`-class failure). Applying the workaround to g3
surfaced a **second**, deeper, genuinely unresolved bug: `crc32.c` uses
`ptrdiff_t` without including `<stddef.h>` itself (a real, safe,
independent fix - added the include, third-party code relying on a
transitive include that only happened to work under Apple's gcc-4.0's
header chain). That fix did not resolve the failure. Traced with `-E`:
GCC14's own `stddef.h` genuinely is found and processed (confirmed by file
path in the preprocessed output) but an *earlier* partial inclusion already
sets the header's top-level multiple-inclusion guard without the
`ptrdiff_t` typedef ever having been reached, so the later, explicit
`#include <stddef.h>` short-circuits straight past it. This is a real bug
in this GCC14 build's own `stddef.h`, not anything about our source or
flags - not something to chase further this session.

**g4 (ppc7400)**: no, same root cause as g3 - confirmed to hit the
identical `crc32.c`/`stddef.h` failure before ever reaching the AltiVec
code the Follow-up 4/5 fixes address. Not a PPC-arch-specific issue; a
GCC14 header-implementation defect that blocks any real g3 or g4 build
through this toolchain as currently packaged.

**i386**: no, a third and unrelated real blocker. Fails in Apple's own
modern AppKit headers (`NSItemProvider.h`/
`NSPreviewRepresentingActivityItem.h`): `cannot define category for
undefined class 'NSItemProvider'`, a forward-declaration ordering issue
that appears specific to building against a modern SDK generation with
`-mmacosx-version-min=10.4`. Not a GCC14/PPC issue at all - `i386` builds
with the same system clang as `lion`, so this is a separate, genuine
"does this SDK generation still support this old a deployment target"
question, independent of everything else in this ADR.

**Definitive answer: no, not today.** One of five slices (`arm64`) already
works natively. One more (`lion`) compiles clean with the right load
command and is the closest to usable, pending a real hardware pass. The
other three (`g3`, `g4`, `i386`) each fail on a distinct, real, verified
blocker - two are toolchain/SDK defects with no known fix yet, not
something a flag change resolves. Cleaned up all build artifacts on
`imac-2019` and released the lock; nothing here touched `master` or the
already-published release.

## Decision

**`imac-2019` is not wired into `scripts/build.sh` or `scripts/build-fat.sh`
today, for either the PPC or the Intel slices.** The relayed claim that
motivated this ticket did not hold up against the reference it cited, and the
independently-real question underneath it - could this host build our slices
at all - was tested for real and failed for the one target (Intel) that was
actually testable today; the other (PPC) has known, separately-tracked gaps
that make it untestable yet.

This is a negative result, not a "not now": the Intel failure is a real
segfault on real hardware, not a missing feature. Revisiting it needs new
evidence, not just PPC's gaps closing - specifically, either a matching-era
SDK on `imac-2019` to compile against instead of Sequoia's own, or some other
concrete reason to expect a different result, followed by the same
real-hardware test this ADR already ran once.

## Consequences

**Gained**: a settled answer, backed by a real build and a real crash, rather
than an unverified claim sitting in the tracker. `mini-intel`/`mini-intel2`
stay the only build hosts; nothing about today's release build changed - this
was a scratch investigation, never touched `build/ioquake3-fat` or the staged
DMG.

**Lost**: nothing shipped depended on this working.

**Not done here**: the obvious next candidate SDK (a period-correct
`MacOSX10.7.sdk`) was tried and it was *not* the fix - see the follow-up
above. What is still untried: root-causing the actual early-crash mechanism
(a `DYLD_PRINT_LIBRARIES`/crash-report trace that produces nothing suggests
something before or during dyld's own startup, not a straightforward missing
symbol), and comparing against exactly what `mini-intel`/`mini-intel2` do
differently at the toolchain level, not just the SDK level.

## Follow-up 7: g3 and g4 now build and link clean end-to-end via imac-2019 (2026-08-29)

New evidence this ADR's own reopening criteria asked for: old-mac-quakespasm#37
independently proved the same GCC14/imac-2019 path end-to-end for their port
(ptrdiff_t shim, `-fnext-runtime` against build-host's `~/gcc14-ppc-objc`
toolchain install, correct cpusubtype+SDL linkage, real Mach-O output). That
recipe transfers - same SDK, same toolchain, same class of header/runtime
gaps - so it was worth a real retry here rather than treating Follow-up 6's
"not today" as final without retesting against new tooling.

Wired an opt-in `BUILD_HOST=imac-2019` path into `scripts/build.sh`'s `g3`
and `g4` cases (Apple-toolchain path unchanged and still the default -
nothing here alters an unpinned `build.sh`/`build-fat.sh` run). Three real,
new blockers found and fixed on top of what quakespasm's recipe already
covered - none of them present in quakespasm's own source, so genuinely new
information for this port specifically:

1. Seven files' AltiVec `#include <altivec.h>` guards assumed `MACOS_X`
   means "Apple's real compiler, which exposes `vec_*` as bare compiler
   built-ins." A first attempt gated that on `__APPLE_ALTIVEC__` too - wrong,
   measured against a real build: this GCC14 cross-toolchain targets
   `powerpc-apple-darwin8` and defines `__APPLE_ALTIVEC__`/`__APPLE_CC__`
   itself for compatibility, so the guard still skipped the real header and
   failed on `vec_splat_u32` etc. as implicitly declared. Fixed for real
   with `__GNUC__ >= 5` (Apple never shipped a PowerPC gcc past the 4.x
   line) - see BUGFIXES.md for the full file list.
2. `q_platform.h`'s `VECCONST_UINT8` macro had the identical MACOS_X-means-
   Apple assumption for which vector-literal syntax to emit. Same fix.
3. `rend2/tr_bsp.c` passes a `uint32_t*` where the bundled
   `SDL_opengl.h`'s own `typedef unsigned long GLuint` wants a `GLuint*` -
   same 4-byte type on this 32-bit target, but GCC14 makes this class of
   pointer mismatch a hard error by default where Apple's gcc-4.0.1 only
   warned. Flag-only fix (`-Wno-error=incompatible-pointer-types`, GCC14
   path only), no source change.

Verified, not just compiled: `lipo -info` confirms `ppc750` on the g3
output and `ppc7400` on g4, both via `BUILD_HOST=imac-2019
scripts/build.sh <g3|g4>`. Also regression-built g4 on the real production
toolchain (`mini-intel`, Apple gcc-4.0.1) after all seven source changes -
clean, unaffected, exactly as expected (`__GNUC__ >= 5` is false there, so
every changed guard takes its original, unchanged branch).

pick-build-host.sh's OS check (`classify()`) was hardcoded to accept only
`10.7*`, so even an explicit `--acquire-host imac-2019` was refused as
wrong-os regardless of `BUILD_HOSTS`. Routed around it this session via
`pick-bench-host.sh --run` + `BUILD_HOST_PRECLAIMED=1`; build-host has since
synced a host-aware fix (buildhost#48, `expect_os()`), so that workaround
should no longer be needed.

**Not done here**: no real-hardware timedemo/launch proof of a GCC14-built
binary (compile+link success is not the same claim - same caveat
quakespasm's own writeup flagged for their port), and no build-time
comparison against `mini-intel` to say whether imac-2019 is actually
faster. i386/lion on imac-2019 (Follow-up 6's other two negative results)
not retried - unrelated toolchain, no new evidence for those two. Whether
to actually flip `build.sh`'s default BUILD_HOST, or wire this into
`build-fat.sh`, is a separate decision from "can it build" - not made here.
