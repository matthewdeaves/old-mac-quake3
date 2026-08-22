# ioquake3 old-Mac port

Quake III Arena on ioquake3 as ONE fat binary across PowerPC and Intel Macs,
from a single `ioquake3.app`. Sticky facts only, loaded every session.
Reasoning and rejected alternatives live in `docs/adr/`; measured numbers live
in `docs/PROFILING.md` and `benchmarks/results.csv`; lessons from things that
broke live in `MISTAKES.md`.

Sister projects on the same fleet and the same tooling: **old-mac-quakespasm**
(Quake), **old-mac-quake2** (Quake II), **old-mac-halflife**. QuakeSpasm is the
mature template - when a tooling question is not answered here, look at how it
does it.

## Goal in one line

Best-looking ioquake3 that stays playable on each machine class, from one fat
binary that auto-tunes per machine. Floors: **G3 >= 20 fps, G4/Lion >= 60 fps**,
G5 and modern uncapped. **Above the floor, effects beat fps.**

## Commands

```sh
scripts/pick-build-host.sh --status      # which Intel mini is free
scripts/build.sh <g3|g4|lion>            # one slice -> build/ioquake3-<t>
scripts/build-fat.sh                     # all three + lipo -> build/ioquake3-fat
scripts/build-gamedylibs.sh              # the 6 native game dylibs
scripts/make-app.sh                      # -> build/ioquake3.app
scripts/make-dmg.sh [version]            # Tiger G4 ONLY, see hard rules
scripts/deploy.sh <machine>              # fat binary + app + cfg -> ~/Desktop/quake3/
scripts/deploy-dmg.sh <machine> [ver]    # install the DMG as a user would
scripts/smoke-dmg.sh <machine>           # does the installed app actually run
scripts/distribute-data.sh <machine>     # ship baseq3 pk3s from mini-intel
scripts/safebench.sh <machine> <WxH>     # THE safe timedemo. Use this.
scripts/bench.sh <machine> <demo> <WxH> [runs]
scripts/parallel-bench.sh [--quick|--reset|--no-<machine>]
scripts/build-server-linux.sh [--arch x86_64|aarch64]
scripts/install-host-tools.sh <host>     # one-time reboot-recovery setup
```

The build scripts run locally here and drive a claimed Intel mini over ssh; they
never hardcode which mini. `BUILD_HOST=<alias>` pins one.

## Facts

- **Baseline is the last SDL 1.2 commit, `4432a80a`** (2013-01-17), branch
  `master`, the commit before `f478761e` "Use SDL 2 instead of SDL 1.2".
  Fallback, never needed: `b003422d` (1.36 era). ioquake3 drives its own
  env-var top-level `Makefile`, not QuakeSpasm's `Makefile.darwin`.
  **The premise behind the pin is the one unmeasured claim in this project** -
  read `docs/adr/0001` before quoting it, and before treating a rebase as
  settled either way.
- **`dyld` grades a fat binary by CPU subtype alone**, never the OS, and there
  is no fallback to a lower slice. **Five slices:** `ppc750` (G3), `ppc7400`
  (G4 **and G5**), `x86_64`, `i386`, `arm64`. **No `ppc970`** - the G5 takes the
  `ppc7400` slice. Each is built against the oldest OS its CPU family can run:
  both PowerPC slices at the 10.3.9 SDK / min 10.3, Intel at min 10.6. Lowering
  those floors measured free. Verify with `lipo -archs`, never from this list.
  `docs/adr/0002`, `docs/adr/0017`
- **Never trust the compiler's cpusubtype stamp.** `-faltivec` defeats it and is
  mandatory on the g4 slice, and Apple's ld stamps generic `ppc` (subtype 0),
  which matches *every* PowerPC host and would hand a G3 the AltiVec build.
  Every build re-stamps post-link (ppc750=9, ppc7400=10, the byte at offset 11)
  and **asserts with `lipo`, never `file`** - `file` calls subtype 9 `ppc_650`.
  `docs/adr/0003`
- **The g4 slice needs `-isystem /usr/lib/gcc/powerpc-apple-darwin10/4.0.1/
  include`**: `-faltivec` wants `<altivec.h>`, a *compiler* header `-isysroot`
  hides. The g3 slice gets no AltiVec at all - a 750 has no vector unit.
- **One `.app` self-tunes**: a per-arch baseline cfg picked by compile-time
  macro, then a `hw.model` overlay, both read from the bundle before renderer
  and sound init (`Com_AutoConfigForMachine`, `code/qcommon/common.c`).
  `+set com_archAutoexec 0` turns both off, which is what makes bench rows
  comparable. `docs/adr/0007`
- **Game modules ship as native dylibs inside the bundle** at
  `Contents/MacOS/baseq3/`, with `vm_cgame`/`vm_game`/`vm_ui` `0`. Measured
  **+1.3%** over the QVM. Stock ioquake3 already JIT-compiles the QVM to native
  PowerPC, so this is *not* an interpreter win. `FS_FindVM` falls back to the
  QVM automatically, which is what the **`i386` slice gets: no i386 dylibs are
  built**, so it runs bytecode. `docs/adr/0008`
- **The user's `baseq3` stays outside the bundle.** `Sys_StripAppBundle()` makes
  `fs_basepath` the directory *containing* the `.app`. We ship no game data.
  `docs/adr/0011`
- **SDL 1.2 is bundled inside the `.app`** (`Contents/MacOS/libSDL-1.2.0.dylib`,
  via `@executable_path`) and `libSDLmain` is compiled from source per slice.
  The prebuilt blobs are 10.4+ and SIGSEGV on Panther. `docs/adr/0006`
- **`yosemite` and `yosemite-tiger` are the same G3**, booted from its 10.3.9 or
  its 10.4.11 partition. One IP, one OS at a time.

## Machines

| Machine | CPU | GPU | macOS | Slice | Role |
|---|---|---|---|---|---|
| yosemite | G3 449 MHz | Rage 128 16 MB | Panther 10.3.9 (also 10.4.11) | ppc750 | bench |
| sawtooth | G4 500 MHz | GeForce2 MX 32 MB | Tiger 10.4.11 | ppc7400 | bench |
| quicksilver | G4 733 MHz | Radeon 9000 Pro 64 MB | Tiger 10.4.11 | ppc7400 | bench, DMG fallback |
| mini-g4 | G4 1.25 GHz | Radeon 9200 32 MB | Tiger 10.4.11 | ppc7400 | bench, DMG host |
| imac-g5 | G5 2.0 GHz | Radeon 9600 128 MB | Leopard 10.5.8 | ppc7400 | bench |
| mini-intel | Core 2 Duo 2.33 GHz | GMA 950 | Lion 10.7.5 | x86_64 | **build**, bench, data source |
| mini-intel2 | Core 2 Duo | - | Lion 10.7.5 | - | **build** |
| imac-2019 | i5-9600K | Radeon Pro 580X 8 GB | Sequoia 15.7 | x86_64 | modern reference |

Build TARGET names (`g3`/`g4`/`lion`) are chip family plus SDK, not machines.
The two Intel minis are interchangeable Macmini2,1 / 10.7.5 boxes with the same
toolchain: `mini-intel` is 10.188.1.190, `mini-intel2` is **10.188.1.164**. The
.216 recorded here previously was stale, settled 2026-08-20: only .164 answers,
and it is what `~/.ssh/config` has. **Use the ssh alias, never an IP.** The read-only Q3 install lives at
`mini-intel:/Users/mini/Games/ioquake3/`; the staged copy is
`mini-intel:~/Desktop/quake3/baseq3/`.

## Hardware that can be wedged or damaged

Read `docs/adr/0009` before benching anything. In short:

- **Never `killall -KILL` a rendering fullscreen engine.** It sticks in
  uninterruptible GPU-driver exit (`ps` state `E`) and hangs the whole
  WindowServer until a reboot. Use `+set nextdemo quit` and let it exit itself.
- **Native resolution only.** A non-native fullscreen set is a real mode switch;
  **the G5's Leopard R300 driver hard-hangs the OS on one**, and the other old
  GPUs corrupt their display.
- **Never `pkill`** - absent on Tiger and Panther.
- **Never run `/sbin/reboot` with any argument to "test" it.** BSD `reboot`
  ignores unknown flags and just reboots. A `--help` probe rebooted the G3.
- Reboot recovery (`~/bin/qsreboot.sh`) only works after the one-time NOPASSWD
  setup, and its Finder fallback returns success without rebooting. Verify the
  host actually drops off the net and returns.

## Traps

- **NEVER trust a build's "done".** Every slice's cpusubtype is asserted with
  `lipo` or the build fails; a pipeline returns its LAST command's status, so
  `driver.sh | tail && next.sh` reads `tail`'s.
- **Never build g3 and g4 in parallel from one shell** - both are `ARCH=ppc`,
  share the remote tree, and race `.o` files into a wrong-subtype binary.
- **rsync target is always `<host>:quake3/`** - never `quakespasm/`, `quake2/`
  or `<host>:~/`.
- **Never modify `mini-intel:/Users/mini/Games/ioquake3/`** or the shared
  `/Developer/SDKs` - recovery is multi-hour.
- **Tiger's `ps` lies.** `comm` is not a valid keyword on 10.4 and `ps ax`
  truncates at 79 columns. Use `killall -0 <name>` or `ps -axc -o pid,ucomm`.
- **Panther's `/bin/sleep` is integer-only**; `sleep 0.2` returns instantly.
- **yosemite rsync needs `--protocol=29`** (Panther ships rsync 2.5.x).
- **`mini-intel` sleeps** - "No route to host" means asleep; wake and retry.
- **`benchmarks/results.csv` is rolling history** - never wipe it mid-round.

## Hard rules

- **Build the release DMG only on a Tiger G4**, `-format UDZO`, and md5 every
  binary inside the finished image. `hdiutil verify` is not enough - it has
  already passed a corrupt image in this family. `docs/adr/0005`
- **We ship code, not content.** No id assets, ever. `docs/adr/0011`
- **Measure, don't guess.** A change without a known bottleneck is a guess.
  3 runs, median of 2 and 3; two commits per phase (code, then bench data);
  revert any regression; **record every negative result** in
  `docs/PROFILING.md` so it is never re-chased.
- **No em dashes anywhere**, prose or shipped strings.
- **Never rate or praise work**, ours or upstream's; attribution is a fact.
- No Claude co-author on commits.

## Working alongside the other repos

Seven repos are worked on together: the four game ports, the private
`retro-server-infra` which runs the servers those ports build,
`old-mac-build-host` which owns the shared host pickers and the source-stamp
primitive, and `retro-agents` which holds the briefs. A session may be open in
each at once. Three rules keep them out of each other's way.

**Hardware is claimed, never assumed free.** Every script that deploys to,
benches on, or otherwise drives a fleet machine re-execs itself under
`scripts/pick-bench-host.sh --run`, so the machine is claimed for the run and
released however it ends. The lock is a directory on the target, so it is shared
with the build lock and visible to every repo, agent and workstation. Check
`scripts/pick-bench-host.sh --status` before assuming a box is idle, and never
work around a busy one. `BENCH_NO_LOCK=1` exists only for debugging the picker.

**Cross-repo work goes through GitHub, not chat.** One board covers all seven
repos: <https://github.com/users/matthewdeaves/projects/8>. Columns are
`Triage / Measuring / Ready / In progress / Blocked / Review / Done`, with
`Source` and `Evidence` fields. **`Review` is where your own work stops.** Move
a finished ticket there, not to `Done`; `Done` is the user's. File cross-repo
work as an issue and put it on the board:

```sh
gh issue create -R matthewdeaves/<repo> --project Retro \
  --label from:port,needs-measurement --title "..." --body "..."
```

Labels, the same four in every repo: **`from:infra`** raised by the server side
for a port to act on, **`from:port`** raised by a port for another repo,
**`needs-measurement`** the claim has no number or hardware repro behind it yet,
**`cross-port`** it affects more than one port, so expect sibling issues.

**Anything one session raises at another starts in `Triage` with
`needs-measurement`, and is not worked until a human or a measurement moves it.**
An issue written by another agent carries no more evidence than the reasoning
that produced it, and it arrives looking exactly like one backed by a bench run.
That gate is the whole reason the board has a `Measuring` column. The same
finding really does recur across ports (the PowerPC SDL2 `--disable-joystick`
issue was filed in three repos on the same day), so `cross-port` is worth using,
but file the sibling issues rather than assuming the fix transfers.

**This repo is PUBLIC. `retro-server-infra` is PRIVATE.** It describes the
topology, firewall rules and admin surface of a live host. Never copy addresses,
key material, tunnel tokens or `.env` content out of it into this repo, in code,
docs or a commit message. Referring to a server release tag is fine; describing
where it runs is not.

## Read on demand

- `docs/adr/`: 0001 the SDL 1.2 pin (and its re-examination), 0002 slices and OS
  floors, 0003 cpusubtype stamping, 0004 cross-building on a claimed mini, 0005
  DMG on Tiger, 0006 rebuilding prebuilt libs for Panther, 0007 the self-tuning
  app, 0008 native game dylibs, 0009 safe benching **and the hardware hazards**,
  0010 the LaunchServices repair, 0011 code not content, 0012 the Linux server,
  0013 watchlink, 0014 icons and the bundle bit, 0015 arm64 (superseded by
  0017), 0016 current ioquake3 on PowerPC, 0017 the arm64 slice and its shim
- `MISTAKES.md` - what already broke, and why. Never re-chase a recorded
  negative.
- `docs/PROFILING.md` - the on-hardware profiling method, every measured
  hotspot, and every measured negative, per machine class.
- `docs/KNOBS.md` - the cvar and cmdline inventory used for tuning.
- `README.md` - public overview, fleet matrix, framerates, releases.
- `server/README.md` - installing and running the Linux dedicated server.
- `scripts/README.md`, `scripts/CLAUDE.md` - pipeline contracts and gotchas.
