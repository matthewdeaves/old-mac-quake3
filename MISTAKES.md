# MISTAKES — ioquake3 old-Mac port

Append-only log of approaches that broke or would have broken. **Read before
lighting up an idea that smells "easy", "modern is better", or "load-time /
zero risk".** Mirrors `~/quakespasm/MISTAKES.md`.

---

## Modern ioquake3 (SDL2 / CMake) cannot run on the PPC fleet — caught at planning

**The smell:** "Just clone ioquake3 HEAD, it's the most maintained — newer is
better." Pinned HEAD (and then the last-Makefile commit) before checking the
runtime envelope.

**Why it breaks:** upstream ioquake3 switched to **CMake + SDL2**, and its PPC
build targets the **10.5 SDK** (`make-macosx.sh`: *"For PPC macs, G4's or
better are required"*). **SDL2 has never supported macOS 10.3 / 10.4.** The
PPC fleet runs Panther 10.3.9 (yosemite) and Tiger 10.4.11 (the G4s) — **none
run 10.5** — so a modern binary won't launch on any PPC bench machine. The G4
machines being on Tiger (not Leopard) means even "G4-only" modern builds are
out; the blocker is the OS/SDL pairing, not just the chip.

**The fix (this one):** baseline pinned to the **last SDL 1.2 commit** `4432a80a`
(2013-01-17), the root of branch `master`, right before `f478761e "Use SDL 2
instead of SDL 1.2"`. SDL 1.2 supports Panther/Tiger and is the same family
QuakeSpasm uses. The `upstream` remote keeps HEAD for reference only. See `CLAUDE.md`
"THE load-bearing constraint".

**Lesson:** for this fleet, "best port" is decided by the **OS + SDL + GPU**
envelope of the *oldest* target, not by upstream activity. Check what will
actually launch on Panther before picking a baseline.

---

## (Open risk, not yet a mistake) Q3A on the 449 MHz G3 may be below playable

Quake III is much heavier than Quake 1, and yosemite (G3 449 MHz, Rage 128
16 MB) is at the 1999 minimum-spec edge. The ≥ 20 fps G3 floor is
**aspirational** — prove it by bench before committing visual work to that
slice. If it can't clear the floor even at `r_picmip 3` / low detail, gate G3
out (compile-time or per-machine) rather than dragging the matrix down.

**Update 2026-05-26:** disproven-as-blocker — a *windowed* `four` timedemo at
640×480 with default settings hit **20.5 fps on the G3** (and that run was
contended by iMovie), **60.8 fps on the G4** (quicksilver, Radeon 9000),
**~288 fps on Lion** (GMA 950). The floor looks reachable; still bench clean
before trusting it.

---

## The prebuilt `libSDLmain.a` / `libSDL-1.2.0.dylib` SIGSEGV on Panther — caught at first G3 run

**The smell:** "ioquake3 ships a fat `libSDL-1.2.0.dylib` (ppc+x86_64+i386) and
a prebuilt `libSDLmain.a` — just link them, they're already universal." The fat
binary built fine, ran on Lion (~288 fps), and on the G3 it... **SIGSEGV'd
before printing a single line.** Crash logs were the only clue.

**Why it breaks:** both prebuilt blobs were built for **Mac OS X 10.4+**. On PPC
they dispatch `objc_msgSend` via a **fixed absolute address — `bla 0xfffeff00`**
(an ObjC fast-dispatch trampoline that exists on 10.4+ but is **unmapped on
10.3.9**). So the Cocoa bootstrap faults instantly:
- prebuilt `SDLMain.o` → crash in `main` (the Cocoa app bootstrap) at the first
  `objc_msgSend`.
- prebuilt `libSDL-1.2.0.dylib` → crash in `SDL_VideoInit` (the Quartz video
  driver's Cocoa calls), reached via `GLimp_StartDriverAndSetMode` → `SDL_Init`.

The trap: `lipo`/`file` say "ppc" so it *looks* portable; nothing flags the
10.4-only dispatch until a real 10.3.9 CPU executes it. `otool -tv | grep 'bla
0xfffeff00'` on the **executable's** SDLMain is the tell (the dylib hides it
behind stubs, but the crash backtrace names `SDL_VideoInit + 0xNNN → 0xfffeff00`).

**The fix:**
1. **Compile `SDLMain.m` from source** against the target SDK / `-mmacosx-version-min`
   instead of copying the prebuilt `.a`. Stock SDL 1.2.15 `SDLMain.m` (from
   QuakeSpasm's `SDL.framework/.../devel-lite`, with `SDL_USE_NIB_FILE 0` so it
   uses `CustomApplicationMain`, no NIB) now lives at `code/libs/macosx/SDLMain.m`;
   the Makefile builds `libSDLmain.a` from it.
2. **Replace the bundled `libSDL-1.2.0.dylib`** with QuakeSpasm's proven
   Panther-safe SDL 1.2.15 (it runs on yosemite), `install_name_tool -id`'d back
   to `@executable_path/libSDL-1.2.0.dylib`.

After both, the G3/G4 reach `GL_RENDERER` and run the timedemo.

**Lesson:** "universal" only means the *architectures* are present — not that
each slice targets the *OS* of the oldest machine. A prebuilt PPC blob can still
be 10.4-only. For this fleet, never trust a prebuilt macOS lib to run on Panther;
rebuild it from source against the 10.3.9 SDK, or steal QuakeSpasm's (which is
already proven on yosemite).

---

## Driving the bench Macs fullscreen over ssh wedges the old GPUs

**The smell:** "Just `+set r_customwidth 1280 +set r_fullscreen 1`, run the
timedemo, `killall` it, repeat across the fleet." Three machines (mini-g4,
quicksilver, mini-intel) black-screened and one G5 threw a CrashReporter dialog
during a parallel quality sweep — each needed a manual reset.

**What actually breaks:**
1. **Non-native fullscreen = a real mode switch**, and a hard `killall -KILL`
   mid mode-set leaves the Rage 128 / R200 / R300 / GMA display corrupted
   (black screen). Worse, the user reported the game came up **windowed** on the
   G5 and **pillarboxed** ("not full width") on quicksilver — the GPUs reject /
   letterbox a non-native mode.
2. **Repeated ssh-launched fullscreen runs** can leave the display grabbed, so
   the *next* launch hangs in early init (stops before `Initializing OpenGL`).
3. **Windowed mode is NOT a safe fallback over ssh** — an ssh-launched app with
   no foreground Aqua focus fails to create a window and exits early (empty log,
   no fps). So you can't sidestep the mode switch by going windowed.

**The fixes:**
- **Always drive each machine at its NATIVE desktop resolution** (quicksilver/
  mini-g4 1680x1050, imac-g5 1440x900, mini-intel 1920x1080). At native res the
  fullscreen set is a *same-mode set* — no mode switch — which is the only
  fullscreen these GPUs survive cleanly, and it fills the panel (fixes the
  windowed / not-full-width reports). Per-machine cfgs now ship native res.
- **Don't remote-bench the fragile fleet in a tight loop.** One careful run with
  a health-check + `~/bin/qsreboot.sh` on hang is the most you should attempt;
  prefer on-site (Finder-launch) validation. `scripts/safebench.sh` encodes the
  health-check + auto-reboot but still can't fully de-risk ssh fullscreen.
- The G3 (yosemite, CRT, no widescreen modes) tolerated benching fine — the
  wedging is specific to the LCD-panel widescreen machines + their drivers.

**Also surfaced:** the red/green/blue HUD box with a blue line is the **lagometer**
net-graph (`cg_lagometer`), not a texture bug — ugly on every GPU, now `0`
fleet-wide. (Distinct from the Rage 128's garbled 3D HUD icons = `cg_draw3dIcons 0`.)

**Lesson:** "fullscreen at any resolution" is an x86/modern-GPU assumption. On
2000-era Mac GPUs, only a same-mode (native-res) set is safe, and an unattended
ssh bench loop will eventually wedge a panel nobody is there to reset.

---

## Benching over ssh: backgrounding kills the app, and KILL wedges the GPU — 2026-07-05

Chased a "safebench never returns fps" bug into three stacked mistakes, wedging
quicksilver and mini-intel (both needed reboots) before finding the right shape.

**Mistake 1 — backgrounding an ssh-launched app kills it.** safebench launched
the engine with `&` and let the ssh session RETURN, then polled the log from
separate ssh calls. The instant the launching session closed, the detached
process lost its Mach bootstrap / WindowServer session and died with
`CFMessagePortCreateLocal failed` before it could open the display — an empty
log, no fps. **Fix:** do everything in ONE ssh session that stays open (launch
backgrounded, then poll the log in-session). This is exactly how the QuakeSpasm
port benches; the session must outlive the app, not the other way round.

**Mistake 2 — KILLing a fullscreen ioquake3 wedges the GPU driver.** The old
"TERM, grace, then KILL backstop" pattern: when TERM didn't finish in the grace
window, the KILL hit a rendering fullscreen app and left it stuck in
**uninterruptible driver exit** (ps state `E`, un-killable), holding the GL
context and hanging the whole WindowServer — the desktop froze, Force-Quit
wouldn't open, only a reboot cleared it. `wait $PID` on such a process hangs
forever too. **Fix:** never signal a rendering fullscreen engine. Make it
**quit itself**: `+set nextdemo quit` — when the timedemo finishes,
`CL_DemoCompleted` runs the `nextdemo` cvar, so the engine executes `quit` and
exits the NORMAL way (SDL restores the display, pid removed). TERM is only a
last-resort backstop; KILL is never used on a fullscreen app.

**Mistake 3 — a stale PID file hangs the next launch headless.** Any un-clean
exit (SIGKILL/SIGPIPE/wedge) leaves `~/Library/Application Support/Quake3/
ioq3.pid`; the next launch pops a modal "Abnormal Exit — safe video settings?"
dialog (`common.c` via `Sys_WritePIDFile`) that blocks forever with no keyboard
to answer it. **Fix:** `rm -f` the pid file before every headless launch.

**Lesson:** an ssh bench of a fullscreen GL app is three problems at once —
keeping the app's display session alive (foreground/single-session), ending it
without a signal (self-quit), and not stranding state that blocks the next run
(pid file). Solve all three or it wedges a machine nobody is there to reset.

---

## The fleet "reboot recovery" was never actually set up — 2026-07-05

**The smell:** trusted `ssh <host> '~/bin/qsreboot.sh'` because CLAUDE.md and
the scripts said it worked. It returned exit 0 every time — but the machines
never rebooted (the user had to hard-reset them by hand).

**Why it breaks:** the NOPASSWD sudoers entry (`qsreboot-setup.sh`) had never
been installed on any machine, so `qsreboot.sh` tier 1 (`sudo -S /sbin/reboot`)
silently failed and fell through to tier 2 (a Finder AppleEvent restart) — which
**returns success even when it does nothing** on a wedged/headless Finder. A
false "reboot succeeded" is worse than a failure: it hid that recovery was
impossible while I kept wedging machines.

**The fixes:**
- Version-controlled the host tooling in `scripts/host-bin/` + a deploy script
  `scripts/install-host-tools.sh` (it was only ever on the machines, never in
  this repo). Ran `sudo ~/bin/qsreboot-setup.sh` on all four live machines to
  install the NOPASSWD entry; verified by a real reboot of the G3.
- `qsreboot.sh` now prints a `QSREBOOT: tier1/tier2` marker so a tier-2
  false-success is visible, and callers (safebench `reboot_m`) VERIFY the host
  actually drops off the net and returns rather than trusting the exit code.

**Bonus mistake:** my first NOPASSWD "detection" probe ran `sudo /sbin/reboot
--help`. BSD `reboot` ignores unknown flags and **just reboots** — the probe
rebooted the G3. Never run `/sbin/reboot` with any argument to "test" it.

**Lesson:** a recovery path you have never actually fired is not a recovery
path. Verify destructive tooling end-to-end (watch the host cycle), and never
trust an exit code from a fallback that can no-op silently.
