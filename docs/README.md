# docs/ - index

Sticky facts live in the repo-root [`CLAUDE.md`](../CLAUDE.md). Decisions and
their evidence live in [`adr/`](adr/).

## Decision records

| ADR | Subject |
|---|---|
| [0001](adr/0001-the-baseline-is-the-last-sdl-1-2-commit.md) | The engine baseline is the last SDL 1.2 commit, and the re-examination of that premise |
| [0002](adr/0002-three-slices-floored-at-the-oldest-os-each-cpu-can-run.md) | Slices in one fat binary, floored at the oldest OS each CPU can run (three at the time; five since arm64 and i386, see 0017) |
| [0003](adr/0003-every-powerpc-slice-is-re-stamped-and-asserted.md) | Every PowerPC slice is re-stamped after link and asserted with `lipo` |
| [0004](adr/0004-cross-compile-on-a-claimed-intel-lion-mini.md) | Cross-compile every slice on a claimed Intel Lion mini |
| [0005](adr/0005-package-the-disk-image-on-a-tiger-g4.md) | Package the disk image on a Tiger G4, and verify its contents end to end |
| [0006](adr/0006-prebuilt-mac-libraries-are-rebuilt-from-source-for-panther.md) | Prebuilt Mac libraries are rebuilt from source for Panther |
| [0007](adr/0007-one-app-self-tunes-per-arch-and-per-machine.md) | One app self-tunes, by architecture then by `hw.model` |
| [0008](adr/0008-game-modules-ship-as-native-dylibs-inside-the-bundle.md) | Game modules ship as native dylibs inside the bundle, with QVM fallback |
| [0009](adr/0009-bench-in-one-ssh-session-at-native-res-and-let-the-engine-quit-itself.md) | Bench in one ssh session, at native resolution, and let the engine quit itself **(hardware hazards)** |
| [0010](adr/0010-repair-the-launchservices-record-after-every-direct-exec.md) | Repair the LaunchServices record after every direct exec of the bundle |
| [0011](adr/0011-we-ship-code-not-content.md) | We ship code, not content |
| [0012](adr/0012-the-linux-dedicated-server-is-one-container-built-elf.md) | The Linux dedicated server is one container-built ELF |
| [0013](adr/0013-watchlink-is-a-cvar-gated-udp-feed.md) | watchlink is a cvar-gated UDP feed, inert by default |
| [0014](adr/0014-one-legacy-only-icns-and-the-finder-bundle-bit.md) | One legacy-only `.icns`, plus a Finder bundle bit setter we ship ourselves |
| [0015](adr/0015-no-arm64-slice-and-adding-one-does-not-require-leaving-sdl-1-2.md) | No arm64 slice, and adding one would not require leaving SDL 1.2 |

## Live references

- [`RELEASE.md`](RELEASE.md) - the pre-tag order and the manual double-click
  gate, which `scripts/release-check.sh` enforces.
- [`WII-PORT-REVIEW.md`](WII-PORT-REVIEW.md) - what the ioQuake3-Wii port had
  that we could use, what was rejected and why, and the two traps it warned about.
- [`PROFILING.md`](PROFILING.md) - the on-hardware profiling method and every
  measured result, wins and negatives, per machine class.
- [`KNOBS.md`](KNOBS.md) - the cvar and cmdline inventory used for tuning.
- [`../MISTAKES.md`](../MISTAKES.md) - what already broke, and the lesson.
- [`../scripts/README.md`](../scripts/README.md) - pipeline and host matrix.
- [`../server/README.md`](../server/README.md) - the Linux dedicated server.

`images/` and `screenshots/` hold the README artwork and the per-machine
in-game captures produced by `scripts/screenshot.sh`.
