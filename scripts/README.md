# scripts/ - the pipeline

Build, deploy, bench and release tooling, adapted from the QuakeSpasm sister
port. Contracts and gotchas are in [`CLAUDE.md`](CLAUDE.md); the decisions
behind them are in [`../docs/adr/`](../docs/adr/).

## Pipeline

```
build.sh <g3|g4|lion>                    # one slice on a claimed Intel mini -> build/ioquake3-<t>
build-fat.sh                             # all three + lipo -> build/ioquake3-fat
build-gamedylibs.sh                      # the 6 native game dylibs -> build/gamedylibs/
make-app.sh                              # -> build/ioquake3.app
make-dmg.sh [version]                    # -> dist/ioquake3-OldMac-<v>.dmg  (Tiger G4 only)
deploy.sh <machine>                      # fat binary + app + cfg -> ~/quake3-play/
deploy-dmg.sh <machine> [version]        # install the DMG the way a user does
smoke-dmg.sh <machine> [demo]            # does the installed app actually run
distribute-data.sh <machine>             # baseq3 pk3s from mini-intel (~482M)
safebench.sh <machine> <WxH> [demo] [+set ...]   # THE safe timedemo
bench.sh <machine> <demo> <WxH> [runs]   # one timedemo -> benchmarks/results.csv
parallel-bench.sh [--quick|--reset|--no-<machine> ...]
bench-and-commit.sh "<phase>" [args...]  # clean-tree bench + commit
screenshot.sh <machine> [demo] [count]   # -> docs/screenshots/
lsregister-app.sh <machine>              # LaunchServices repair, see adr/0010
install-host-tools.sh [host ...]         # one-time reboot-recovery setup
pick-build-host.sh [--status|--acquire L|--release H]
build-server-linux.sh [--arch x86_64|aarch64]   # Linux dedicated server
make-icon.py <source.png>                # -> MacOSX/ioquake3.icns, see adr/0014
```

## Host matrix

| Machine | CPU | GPU | macOS | Slice | Role |
|---|---|---|---|---|---|
| yosemite (also yosemite-tiger) | G3 449 MHz | Rage 128 16 MB | 10.3.9 / 10.4.11 | ppc750 | bench |
| sawtooth | G4 500 MHz | GeForce2 MX 32 MB | Tiger 10.4.11 | ppc7400 | bench |
| quicksilver | G4 733 MHz | Radeon 9000 Pro 64 MB | Tiger 10.4.11 | ppc7400 | bench, DMG fallback |
| mini-g4 | G4 1.25 GHz | Radeon 9200 32 MB | Tiger 10.4.11 | ppc7400 | bench, DMG host |
| imac-g5 | G5 2.0 GHz | Radeon 9600 128 MB | Leopard 10.5.8 | ppc7400 | bench |
| mini-intel | Core 2 Duo 2.33 GHz | GMA 950 | Lion 10.7.5 | x86_64 | build, bench, data source |
| mini-intel2 | Core 2 Duo | - | Lion 10.7.5 | - | build |
| imac-2019 | i5-9600K | Radeon Pro 580X 8 GB | Sequoia 15.7 | x86_64 | modern reference |

`yosemite` and `yosemite-tiger` are one Mac on two partitions, one OS at a time.

## bundle/

`autoexec-<arch|machine>.cfg` - the per-arch baselines and per-machine overlays
bundled into the app's `Resources/` (`../docs/adr/0007`). `Info.plist`, and
`set-bundle-bit` plus its source (`../docs/adr/0014`).

`docker/` holds the Linux server build image; `host-bin/` holds the reboot
recovery scripts installed onto the bench Macs.
