# 14. One legacy-only `.icns`, plus a Finder bundle bit setter we ship ourselves

Date: 2026-08-20
Status: accepted

## Context

One `.app` reaches Panther 10.3.9 through Sequoia (ADR 0002), so one icon file
has to render on all of them, and Finder has to treat the directory as an
application on machines with no developer tools installed.

Two independent old-Mac faults:

- **Panther's Finder bails on modern `.icns` chunks**, even when they appear
  after the legacy ones. So a single file that works on Panther, Tiger, Lion and
  Sequoia has to be legacy-only.
- **Panther and Tiger Finder treat a `.app` directory as a package** -
  single-icon, double-clickable - **only when its HFS+ `kHasBundle` bit is
  set.** Without it, Finder shows a generic folder icon even though `Info.plist`
  and the `.icns` are perfectly valid. Apple's `SetFile -a B` sets it, but
  `SetFile` is part of the Xcode developer tools, which are **not** installed on
  the retro fleet.

## Decision

**`scripts/make-icon.py` emits legacy-only chunks, and `deploy.sh` ships a tiny
universal `set-bundle-bit` binary to set `kHasBundle` on the target.**

- Chunks emitted: `ICN#`, `ics#`, `is32`, `s8mk`, `il32`, `l8mk`, `ih32`,
  `h8mk`, `it32`, `t8mk`. **No `TOC`, no modern PNG chunks** (`ic07`-`ic14`).
- **Trade-off accepted:** Lion and later render Retina by upscaling the 128x128
  `it32` chunk instead of getting native 256-1024 px PNG chunks. Worth it - the
  fleet's three Tigers and one Panther are the targets that historically broke,
  and everything Lion and up has more icon-rendering flexibility.
- The script also does optional background removal (edge flood fill so interior
  pixels matching the background colour are not punched transparent, with a soft
  alpha ramp for antialiasing) and refreshes the README hero thumbnails at
  256x256 and 1024x1024 into `docs/images/`.
- `scripts/bundle/set-bundle-bit.c` is compiled to a universal
  (`ppc750 + ppc7400 + x86_64`) binary on the Lion cross-build host and shipped
  to every PowerPC machine by the deploy pipeline. It exits 0 when the bit is
  set or already set, and prints the actual `OSStatus` on any FSRef or Catalog
  failure.

## Alternatives rejected

**`iconutil`.** It unconditionally emits `TOC` plus modern chunks, and does not
produce the 1-bit `ICN#` / `ics#` chunks Panther needs at all.

**Two icon files, legacy and modern.** One `.app` ships to every machine; there
is nowhere to choose between them.

**Python `ctypes` or Carbon bindings to set the bundle bit.** Panther's Python
2.3 lacks `ctypes` (added in 2.5), and Tiger's Python 2.3 Carbon binding does not
expose `finderInfo` on `FSCatalogInfo`.

**Install developer tools on the fleet.** Multi-gigabyte installs on machines
with 25-year-old disks, to get one 4-byte flag set.

## Consequences

**Gained**

- The icon renders from Panther's Finder to modern macOS from one file, and the
  app shows as an app on every fleet machine.

**Lost**

- No Retina-native icon artwork above 128x128.
- A C source file and a checked-in universal binary in `scripts/bundle/`.
