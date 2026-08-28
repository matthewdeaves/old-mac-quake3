# Build System & Facts

**Centralized CI & Builds:**
All documentation and processes must strictly point to `old-mac-build-host` as the centralized source of truth for builds and CI. The build scripts run locally and drive a claimed Intel mini over ssh. They never hardcode which mini. `BUILD_HOST=<alias>` pins one. `old-mac-build-host` owns the shared host pickers and the source-stamp primitive.

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

## Facts
- **Baseline is the last SDL 1.2 commit, `4432a80a`** (2013-01-17), branch `master`, the commit before `f478761e` "Use SDL 2 instead of SDL 1.2". Fallback, never needed: `b003422d` (1.36 era). ioquake3 drives its own env-var top-level `Makefile`, not QuakeSpasm's `Makefile.darwin`. Read `docs/adr/0001`.
- **`dyld` grades a fat binary by CPU subtype alone**, never the OS, and there is no fallback to a lower slice. **Five slices:** `ppc750` (G3), `ppc7400` (G4 **and G5**), `x86_64`, `i386`, `arm64`. **No `ppc970`** - the G5 takes the `ppc7400` slice. Verify with `lipo -archs`, never from this list. `docs/adr/0002`, `docs/adr/0017`.
- **Never trust the compiler's cpusubtype stamp.** `-faltivec` defeats it and is mandatory on the g4 slice. Every build re-stamps post-link and **asserts with `lipo`, never `file`**. `docs/adr/0003`.
- **The g4 slice needs `-isystem /usr/lib/gcc/powerpc-apple-darwin10/4.0.1/include`**.
- **One `.app` self-tunes**: `Com_AutoConfigForMachine` (`code/qcommon/common.c`). `+set com_archAutoexec 0` turns both off. `docs/adr/0007`.
- **Game modules ship as native dylibs inside the bundle** at `Contents/MacOS/baseq3/`. Measured **+1.3%** over the QVM. The **`i386` slice has no dylibs built for it**, but ships the x86 JIT, so it runs COMPILED QVM. `docs/adr/0008`, issue #23.
- **The user's `baseq3` stays outside the bundle.** We ship no game data. `docs/adr/0011`.
- **SDL 1.2 is bundled inside the `.app`**. `docs/adr/0006`.
- **`yosemite` and `yosemite-tiger` are the same G3**.

## Hard rules
- **Build the release DMG only on a Tiger G4**, `-format UDZO`, and md5 every binary inside the finished image. `docs/adr/0005`.
- **We ship code, not content.** No id assets, ever. `docs/adr/0011`.
- **Measure, don't guess.** 3 runs, median of 2 and 3; revert any regression; **record every negative result** in `docs/PROFILING.md`.
- **No em dashes anywhere**, prose or shipped strings.
- **Never rate or praise work**, ours or upstream's; attribution is a fact.
- No Claude co-author on commits.

## Build Traps
- **`mini-intel`/`mini-intel2` are the only build hosts, and that's deliberate, not unfinished.** `imac-2019` looks tempting (fastest Intel box in the fleet, and `/Users/mini/gcc14-ppc` really is present there) but a real same-day test - built the `lion` slice there with its own clang, correct subtype and `-mmacosx-version-min=10.6` stamp, then ran it on real Lion 10.7.5 hardware - segfaulted instantly, no output. A correct version-min flag does not mean a modern toolchain's SDK generation produces something that runs on a decade-older dyld. `docs/adr/0020`, `MISTAKES.md`.
- **NEVER trust a build's "done".** A pipeline returns its LAST command's status.
- **Never build g3 and g4 in parallel from one shell** - they race `.o` files.
- **rsync target is always `<host>:quake3/`**.
- **Never modify `mini-intel:/Users/mini/Games/ioquake3/`** or the shared `/Developer/SDKs` - recovery is multi-hour.
- **`mini-intel` sleeps** - "No route to host" means asleep; wake and retry.
- **`benchmarks/results.csv` is rolling history** - never wipe it mid-round.
