# Review: what the ioQuake3-Wii port has that we can use

Reviewed 2026-08-22 against [Mayo1970/ioQuake3-wii](https://github.com/Mayo1970/ioQuake3-wii)
at `fd92c04`. Closes issue #7.

Written so this is not re-litigated. Where the answer is "nothing to take", the
reasoning is here rather than left implicit.

## Why this port was worth reading at all

Broadway is a **PPC750CL at 729 MHz**: the same chip family as `yosemite`
(G3, 449 MHz), big-endian, no AltiVec. A fixed-function, fill-limited GPU with a
tiny texture budget, which is the Rage 128's situation too. And GPLv2, so
anything worth taking is licence-compatible.

Out of scope throughout: the GX/OpenGX backend, libogc/devkitPPC, MEM1/MEM2
layout, Wii controllers, 240p/264p video modes, and the Dreamcast protocol-43
flavour.

The most useful file is not code. It is their `AGENTS.MD`, a list of things they
broke and then fixed, which is worth more than any diff.

## Taken

### `r_primitives` is a per-GPU answer, not a per-platform one

They pin `r_primitives 2`. We shipped the `0` default everywhere and had never
confirmed what it resolved to. Measured, 3 runs each, median of runs 2 and 3,
every run verified against the engine's own `rendering primitives:` line:

| machine | GPU | 3 immediate | 2 `glDrawElements` | 1 `glArrayElement` |
|---|---|---:|---:|---:|
| yosemite | Rage 128, 10.3.9 | **33.3** | 31.7 | 31.3 |
| mini-g4 | Radeon 9200, 10.4.11 | 57.3 | **74.6** | |

**Opposite answers, and the G4 gap is 30%.** Their pinned `2` would be the wrong
value on our G3 and the right one on our G4. Auto-select can never reach 3: it
picks 2 whenever `GL_EXT_compiled_vertex_array` is present and both drivers
report it.

Shipped as `r_primitives 3` in `autoexec-yosemite.cfg` and `autoexec-ppc750.cfg`
only. The preference **reverses again** on the same G3 under Tiger (20.8 for 3,
21.4 for 2), which is part of the much larger Panther/Tiger gap in #15.

### The JIT's value is memory, not framerate

They measured no fps gain from their QVM JIT and concluded the render backend is
the bottleneck. That independently matches our own +1.3% (`docs/PROFILING.md`,
ADR 0008), from a different port on the same CPU family.

The part we had never written down is what the JIT **is** good for: lower hunk
use, because compiled code lives off-hunk, so large maps that would exhaust
memory under the interpreter still load. A memory lever, not a speed one. Now
recorded in `PROFILING.md`.

## Rejected, with reasons

### Sound, ADPCM 4:1 storage

Their reasoning: it "keeps the working set inside the smaller pool while freeing
sbrk for QVM/JIT and map loads". So it is a **memory-pressure** fix, sized
against the Wii's ~88 MB and its hard MEM1/MEM2 split.

Our G3 has no equivalent squeeze, and we already cut `s_sdlSpeed` to 11025 for
the reason that actually applies here, which is mixing CPU (sound was ~29% of
the G3 frame). ADPCM would add decode cost to fix a problem we do not have.

**Not applicable. No bench needed.**

### Backend seam / batch submission

Their `tr_backend.c`, `tr_shade.c` and `tr_image.c` are restructured behind
`#if defined(WII_NATIVE_GX)` to host a second, batch-submitting backend.

The Rage 128 driver reports **`GL_VERSION: 1.1`**. No VBOs, no GL 1.5, nothing
to batch into. This is a hardware ceiling, not a question of effort, and we have
no GX analogue to host.

**Low value here.** Recorded so it is not revisited without new hardware.

### Hardware mipmap generation

`GL_SGIS_generate_mipmap` **is** present on the Rage 128, so the idea is
available in principle. What it saves is unmeasured, and it would show up in
level load time rather than a timedemo average, so it needs a different
measurement from the rest of this list. Folded into the memory/load work in #8
rather than kept here.

## Corroboration, which is worth as much as anything taken

Their critical-rules list says:

> **`r_fastsky 1`:** never use on Wii, it silently kills all portal/mirror
> rendering via an early-out in `R_MirrorViewBySurface`.

Same gate, same line, in both trees:

```
theirs  code/renderergl1/tr_main.c:968
ours    code/renderer/tr_main.c:969
        if ( r_noportals->integer || (r_fastsky->integer == 1) ) {
```

Two ports on entirely different hardware independently lost their mirrors to
this and independently tracked it to the same line. Our #6 conclusion was not a
local quirk.

We went one step further than their rule does. `r_fastsky 2` dodges that gate
but still blacks the portal view, because the fill-saving tests are truthy while
only the portal gate is an exact `== 1`. Their rule stops at "never use 1". Ours
has to stay **"use 0"**.

## Two traps checked against our tree

Both from their rules, both checked here rather than assumed:

| Trap | Our state |
|---|---|
| `Sys_Milliseconds` overflow: they capture a base and subtract it, and warn that removing it gives a negative return and a permanent black screen | **Safe.** `code/sys/sys_unix.c:96` already keeps `sys_timeBase` and subtracts it |
| `MAX_CONSOLE_LINES` is 32; command-line `+set` slots past it are dropped **silently** | Same value, `code/qcommon/common.c:404`. Our scripts are well under, but a bench harness pinning a whole profile could approach it, and the failure looks exactly like a cvar that did not take |

## One claim they debunk

> Older docs claimed a non-power-of-2 `dataAlloc` change in `vm.c` saves memory.
> That change is **NOT in the tree** (verified absent).

If that reaches us from any source, it is false in this port. Recorded so it is
not implemented on the strength of a stale document.

## What the diff is not good for

The original issue proposed diffing their `code/qcommon/`, `code/client/` and
`code/renderergl1/` against ours to surface post-2013 upstream fixes.

Their base **is** much newer: they have `renderergl1/` and `renderercommon/`,
the post-2013 renderer split, where we still have the flat `renderer/`.

But the comparison is noisy. On `tr_main.c`, ours 1403 lines against theirs
1421:

```
total added lines in theirs   49
of which GX-specific           5
```

and most of the remainder is **their own mirror instrumentation**, `wii_diag(...)`
calls, not upstream changes at all.

Diffing against this port measures three things at once: upstream's changes,
their GX work, and their debugging. **The right comparison is our tree against
upstream ioquake3 directly**, which removes two of the three. Tracked separately;
the Wii port is not the tool for it.
