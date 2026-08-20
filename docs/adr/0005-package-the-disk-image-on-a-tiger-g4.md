# 5. Package the disk image on a Tiger G4, and verify its contents end to end

Date: 2026-08-20
Status: accepted

## Context

The release is one `.dmg` that has to mount on every machine the fat binary
serves, from Panther 10.3.9 up. Old tools cannot read new formats and new tools
cannot write old ones.

- Lion's `hdiutil` writes a UDIF container Panther's 2003-vintage
  DiskImageMounter cannot parse, reported on 10.3.9 as "no mountable file
  systems". A **Tiger-built UDZO** image mounts on Panther and on everything
  newer. Old-to-new compatibility holds; new-to-old does not.
- `hdiutil verify` checks the container's internal checksum, not that the stored
  bytes match the source. The Quake II sister port shipped a DMG whose PowerPC
  slice had a byte flipped during the read-zlib-write chain; it passed
  `hdiutil verify` and crashed every G4.

## Decision

**`scripts/make-dmg.sh` runs the `hdiutil` step on a Tiger G4 with
`-format UDZO`, and md5s every shipped binary inside the finished image against
the local source.**

- `DMG_HOST` defaults to the first reachable Tiger box, `mini-g4` then
  `quicksilver`. Both write Panther-mountable images.
- The **binary** is always built on Lion by `build-fat.sh` (ADR 0004);
  `DMG_HOST` only runs the packaging step on the staged tree.
- Verification mounts the finished image, hashes the engine and the six native
  game dylibs inside it, compares against the local source, and detaches.
- `make-app.sh` stamps `CFBundleVersion` from the release label and
  `make-dmg.sh` refuses to build an image whose bundle is not stamped with it,
  so a deployed machine can prove which build it ran.
- `deploy-dmg.sh <machine> [version]` then installs the image the way a human
  does - copy to the Desktop, mount, copy `ioquake3.app` into
  `~/Desktop/quake3/`, unmount - preserving the user's `baseq3/*.pk3`,
  `q3config.cfg` and `autoexec.cfg`. `smoke-dmg.sh <machine>` launches that
  installed copy on its production autoexec with a timedemo appended so it
  auto-exits, proving the world actually rendered.

## Alternatives rejected

**Package on Lion, where the build already is.** It produces an image a G3
cannot mount, and the G3 is the machine class the image most has to reach.

**Package on the Panther G3.** Flakiest hardware in the fleet - non-ECC RAM, a
25-year-old disk. The content verification would catch a byte flip on any host,
but there is no reason to build on the worst hardware when a healthy Tiger box
does the job.

**Trust `hdiutil verify`.** It has already passed a corrupt image in this
family of ports.

## Consequences

**Gained**

- One disk image installs on 10.3.9 through modern macOS.
- A corrupt slice fails the release instead of reaching a bench machine.

**Lost**

- A release needs three machines reachable: an Intel mini, the orchestration
  box, and a Tiger G4.

**Note**

- `smoke-dmg.sh` proves world render at the right resolution but **not** the
  live-server / entity-spawn path. Start a new game by hand after it passes.
