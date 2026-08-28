# 20. imac-2019 is not a build host yet

Date: 2026-08-28
Status: accepted (negative result; revisit only with new evidence)

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
root-caused further - two independently-real crashes on two different real
machines is enough evidence to keep this blocked without chasing a third
hypothesis same-day.

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
