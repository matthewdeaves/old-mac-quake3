---
paths:
  - "scripts/**"
  - "code/**"
  - "Makefile"
  - "shared-scripts.pin"
---

# Build and bench commands

old-mac-build-host owns builds and CI. Scripts drive a claimed Intel mini over ssh; `BUILD_HOST=<alias>` pins one. Facts, slices and traps: `docs/BUILD-FACTS.md`.

## Commands

```sh
scripts/pick-build-host.sh --status      # which Intel mini is free
scripts/build.sh <g3|g4|lion>            # one slice -> build/ioquake3-<t>
scripts/build-fat.sh                     # all three + lipo -> build/ioquake3-fat
scripts/build-gamedylibs.sh              # the 6 native game dylibs
scripts/make-app.sh                      # -> build/ioquake3.app
scripts/make-dmg.sh [version]            # Tiger G4 ONLY, see hard rules
scripts/deploy.sh <machine>              # fat binary + app + cfg -> /Applications/Quake3/
scripts/deploy-dmg.sh <machine> [ver]    # install the DMG as a user would
scripts/smoke-dmg.sh <machine>           # does the installed app actually run
scripts/distribute-data.sh <machine>     # ship baseq3 pk3s from mini-intel
scripts/safebench.sh <machine> <WxH>     # THE safe timedemo. Use this.
scripts/bench.sh <machine> <demo> <WxH> [runs]
scripts/parallel-bench.sh [--quick|--reset|--no-<machine>]
scripts/bench-evidence.sh <machine> <round-label>   # evidence bundle + VALID/INVALID verdict, wraps safebench.sh via scripts/bench-adapter.sh. Needs BENCH_RES=<WxH> (native, never guessed). Synced from old-mac-build-host (build-host#104); bench-adapter.sh is port-owned, never synced.
scripts/shared.sh bench-compare.sh --baseline <bundle...> --candidate <bundle...>   # BETTER/WORSE/NO-DIFFERENCE/INCONCLUSIVE verdict from bench-evidence.sh bundles. Quote this instead of eyeballing numbers. Pinned via shared-scripts.pin (#71), not a local copy.
scripts/build-server-linux.sh [--arch x86_64|aarch64]
scripts/install-host-tools.sh <host>     # one-time reboot-recovery setup
BENCH_LOCK_WAIT=1800 scripts/pick-bench-host.sh --run qemu-tiger3d <label> -- <deploy-dmg.sh|smoke-dmg.sh|screenshot.sh|BENCH_ARTEFACT=<local-copy-of-installed-binary> bench-evidence.sh> ...   # iterate the PPC test loop on the QemuMac G4+Radeon9700 VM; deploy-dmg.sh/screenshot.sh want a bare version (v0.6.21), never a relative dist/ path; BENCH_ARTEFACT must point at a LOCAL file, never fetched live off the host under test
```
