# MISTAKES

Append-only log of approaches that broke, or would have broken. **Read before
lighting up an idea that smells "easy", "modern is better", or "load-time, zero
risk".** Mechanisms are in `docs/adr/`; measured performance negatives are in
`docs/PROFILING.md`. What is here is the lesson and the facts that live nowhere
else.

---

## Modern ioquake3 (SDL2 / CMake) was ruled out for the PPC fleet - caught at planning

**The smell:** "just clone ioquake3 HEAD, it's the most maintained, newer is
better." HEAD was pinned before anyone checked the runtime envelope.

**The reasoning:** upstream switched to CMake + SDL2; SDL2 was believed never to
have supported 10.3 or 10.4; the PPC fleet is Panther and Tiger. So the baseline
was pinned to the last SDL 1.2 commit `4432a80a`. `docs/adr/0001`

**Caveat, added 2026-08-20:** that "SDL2 never supported 10.3/10.4" claim was
**reasoned, not tested**, and is the only unmeasured load-bearing claim in the
project. Two of its supporting facts are now known to be weak (the
`make-macosx.sh` quote is from *this* 2013 tree, and imac-g5 *does* run 10.5).
Read `docs/adr/0001` before repeating it.

**Lesson:** for this fleet, "best port" is decided by the OS + SDL + GPU envelope
of the *oldest* target, not by upstream activity. And label a claim measured or
reasoned when you write it down, or it hardens into a fact nobody rechecks.

---

## (Was an open risk) Q3A on the 449 MHz G3 may be below playable

Quake III is much heavier than Quake 1, and yosemite (G3 449 MHz, Rage 128
16 MB) is at the 1999 minimum-spec edge. The >= 20 fps G3 floor was
**aspirational**; the plan was to gate G3 out rather than drag the whole matrix
down if it could not clear the floor even at `r_picmip 3`.

**Disproven as a blocker, 2026-05-26.** A *windowed* `four` timedemo at 640x480
with default settings: **20.5 fps on the G3** (and that run was contended by
iMovie), **60.8 fps on quicksilver** (G4, Radeon 9000), **~288 fps on Lion**
(GMA 950). The v0 baseline then measured the G3 at **27 fps @1024x768 and
45 fps @640x480** with default settings and no tuning; quicksilver sat flat at
~60 (vsync-capped, hiding real headroom) and mini-intel at 105/238 fps.

**Lesson:** the floor was reachable, but only bench evidence said so. Don't
commit visual work to a slice on an assumption about it in either direction.

---

## The prebuilt `libSDLmain.a` / `libSDL-1.2.0.dylib` SIGSEGV on Panther

**The smell:** "ioquake3 ships a fat SDL dylib and a prebuilt `libSDLmain.a`,
just link them, they're already universal." It built fine, ran on Lion at
~288 fps, and on the G3 SIGSEGV'd before printing a single line.

**Cause and fix:** both blobs are 10.4+ builds that dispatch `objc_msgSend`
through the fixed absolute address `bla 0xfffeff00`, unmapped on 10.3.9.
`docs/adr/0006` has the two crash sites, the `otool` tell, and the fix.

**Lesson:** "universal" only means the *architectures* are present, not that
each slice targets the *OS* of the oldest machine. For this fleet, never trust a
prebuilt macOS library to run on Panther.

---

## Driving the bench Macs fullscreen over ssh wedges the old GPUs

**The smell:** "just `+set r_customwidth 1280 +set r_fullscreen 1`, run the
timedemo, `killall` it, repeat across the fleet." Three machines (mini-g4,
quicksilver, mini-intel) black-screened and a G5 threw a CrashReporter dialog
during one parallel quality sweep; each needed a manual reset.

Five stacked hazards - non-native mode switch, KILL during a mode set, a grabbed
display on the next launch, windowed-over-ssh exiting early, and the G5's R300
hard-hang - are all in `docs/adr/0009`, with the fixes.

**Also surfaced:** the red/green/blue HUD box with a blue line is the
**lagometer** net-graph (`cg_lagometer`), not a texture bug. Ugly on every GPU,
now `0` fleet-wide. Distinct from the Rage 128's garbled 3D HUD icons, which are
three real MD3 models drawn into HUD viewports by `CG_DrawStatusBar`
(`cg_draw.c`) and are fixed by `cg_draw3dIcons 0`, a 2D-icon fallback that is
also faster. Both verified by screenshot.

**Lesson:** "fullscreen at any resolution" is an x86/modern-GPU assumption. On
2000-era Mac GPUs only a same-mode (native-res) set is safe, and an unattended
ssh bench loop will eventually wedge a panel nobody is there to reset. The G3
(CRT, no widescreen modes) tolerated it fine; the wedging is specific to the
LCD-panel widescreen machines and their drivers.

---

## Benching over ssh: backgrounding kills the app, and KILL wedges the GPU - 2026-07-05

Three stacked mistakes chased through a "safebench never returns fps" bug,
wedging quicksilver and mini-intel (both needed reboots) before the right shape
appeared: backgrounding an ssh-launched app kills it; KILLing a fullscreen
engine wedges the GPU driver; a stale `ioq3.pid` pops a modal dialog that blocks
a headless launch forever. Mechanisms and fixes: `docs/adr/0009`.

**Lesson:** an ssh bench of a fullscreen GL app is three problems at once -
keeping the app's display session alive, ending it without a signal, and not
stranding state that blocks the next run. Solve all three or it wedges a machine
nobody is there to reset.

---

## The fleet "reboot recovery" was never actually set up - 2026-07-05

**The smell:** trusted `ssh <host> '~/bin/qsreboot.sh'` because the docs and the
scripts said it worked. It returned exit 0 every time and the machines never
rebooted; the user had to hard-reset them by hand. The NOPASSWD sudoers entry
had never been installed anywhere, so tier 1 failed silently and fell through to
a Finder AppleEvent restart that **returns success even when it does nothing**.
A false "reboot succeeded" is worse than a failure: it hid that recovery was
impossible while machines kept being wedged.

Fixes, and the tier marker that makes a false success visible: `docs/adr/0009`.
The host tooling was also version-controlled (`scripts/host-bin/` plus
`scripts/install-host-tools.sh`); it had only ever existed on the machines.

**Bonus mistake:** the first NOPASSWD "detection" probe ran
`sudo /sbin/reboot --help`. **BSD `reboot` ignores unknown flags and just
reboots** - the probe rebooted the G3. Never run `/sbin/reboot` with any
argument to test it.

**Lesson:** a recovery path you have never actually fired is not a recovery
path. Verify destructive tooling end to end, watching the host cycle, and never
trust an exit code from a fallback that can no-op silently.

---

## The `ppc7400` slice was min-10.4, so a G4 on Panther could never launch it - 2026-07-25

**The smell:** each slice built against "the SDK of the OS that machine runs".
That reads as careful matching and is backwards, because `dyld` grades by CPU
subtype alone. Full mechanism, the `otool -L` evidence, the A/B that showed the
fix cost nothing, and the 165-AltiVec-instruction check: `docs/adr/0002`.

**Lesson:** "built against the SDK matching the machine" is the wrong instinct
for fat binaries. Ask instead: what is the oldest OS a CPU that grades to this
slice could be running? And check the answer against `otool -L`, not against
intent - the sister ports had the identical bug and it was invisible until
someone read the dependency list.

---

## `-faltivec` silently un-stamps the cpusubtype - inherited: guarded here

**The smell:** `-arch ppc7400 -mcpu=7400` is on the command line, so the binary
must be stamped `ppc7400`. It is not, and a generic `ppc` member shadows every
other PowerPC slice. `docs/adr/0003`.

**Lesson:** never trust the compiler's stamp on a slice you cannot boot. Assert
it on every artifact, every build - with `lipo`, not `file`.

---

## Tiger's `ps` cannot be trusted for process detection - 2026-07-25

Two independent silent limitations, both of which produced wrong answers in this
project on the same day: `comm` is not a valid ps keyword on 10.4, and `ps ax`
truncates at 79 columns. Every guard built on `ps -axo comm,pid` was dead -
this port's bench teardown (which is why four Macs needed power-button resets)
and the "is a game already running?" checks in `smoke-dmg.sh` / `screenshot.sh`
here and in the Quake II port. What to use instead: `docs/adr/0009`.

**Lesson:** a process check that silently returns "nothing running" is far more
dangerous than one that errors, because the caller concludes it is safe to
launch another fullscreen engine. Test detection code by asserting it finds
something you KNOW is running, not by watching it find nothing.

---

## Every bench script said PASS while the .app wouldn't open at all - 2026-07-26/27

Double-clicking the app on Lion gave "damaged or incomplete" while every
automated check was green. The binary was byte-identical to the build, `lipo`
listed all three slices, the bundle was complete, the Finder bundle bit was set,
there was no quarantine xattr, and `smoke-dmg.sh` passed at 1260 frames /
40.3 fps @1920x1080. The fault was Lion's LaunchServices record, and **our own
bench tooling was causing it**. Full diagnosis, the single-variable measurement
that pinned the trigger to `dlopen` inside the bundle, and why the sister ports
are safe: `docs/adr/0010`.

**Lesson 1:** "the binary runs" and "the app opens" are different claims, and
this project's entire test suite only ever proved the first. When every
automated check is green and the user still cannot launch the thing, suspect the
layer the harness bypasses for convenience.

**Lesson 2:** a fix that makes the symptom go away is not evidence you found the
cause. Re-registering at deploy time produced a good record, verified green, and
was still worthless. The cheap test that would have caught it immediately, and
that was skipped in favour of a plausible story about rsync: break it, apply the
fix, then run the rest of the pipeline and look again.
