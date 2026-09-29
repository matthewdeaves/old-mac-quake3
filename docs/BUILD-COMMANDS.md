# Build and deployment commands

Scripts drive a claimed Intel mini over SSH; `BUILD_HOST=<alias>` pins one.
Slice constraints and build traps: `docs/BUILD-FACTS.md`.
Benchmark commands: `docs/BENCH-COMMANDS.md`.

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
scripts/build-server-linux.sh [--arch x86_64|aarch64]
scripts/install-host-tools.sh <host>     # one-time reboot-recovery setup
```
