# 11. We ship code, not content

Date: 2026-08-20
Status: accepted

## Context

Quake III Arena's assets are id Software's. The engine is GPLv2; the pak files
are not ours to redistribute, on the Mac release or the Linux server release.

The fleet needs the data anyway: nine pk3s, `PAK0.PK3` plus `pak1-8.pk3`, about
482 MB, all stock maps and demos included.

## Decision

**No game data ships, anywhere. The user supplies `baseq3/`.**

- The DMG contains `ioquake3.app` and a user-facing README, nothing else. The
  player drops the app next to their own `baseq3/`.
- On macOS ioquake3 derives `fs_basepath` from `Sys_StripAppBundle()`, i.e. the
  directory *containing* the `.app`. So `~/Desktop/quake3/ioquake3.app` finds
  `~/Desktop/quake3/baseq3` - the user's game data stays **outside** the bundle.
- The only files this port puts inside the bundle's `baseq3` are its own native
  game dylibs (ADR 0008). The user's `baseq3` is never written to.
- `deploy-dmg.sh` preserves `baseq3/*.pk3`, `q3config.cfg` and `autoexec.cfg` on
  reinstall; only `ioquake3.app` is replaced.
- The Linux server tarball ships no data either (ADR 0012).

**Fleet data staging.** The reference copy is the installed ioquake3 1.36 at
`mini-intel:/Users/mini/Games/ioquake3/`. **Never modify that install.** A
read-only copy is staged at `mini-intel:~/Desktop/quake3/baseq3/`, and
`scripts/distribute-data.sh <machine>` relays it to a bench machine's
`~/Desktop/quake3/baseq3/` through a local cache under `build/` - the PowerPC
Macs are not in mini-intel's ssh config, so only the orchestration host can
reach the whole fleet. It is idempotent and ships only pk3s.

**On modern macOS** the release needs Gatekeeper cleared once:
`xattr -dr com.apple.quarantine ioquake3.app`. Not needed on Panther, Tiger or
Lion.

## Alternatives rejected

**Bundle the demo pak.** Still id's content, and the demo pak does not satisfy
the point-release check the full game needs.

**Ship data to the bench machines from the release tooling.** Deployment and
data distribution stay separate: `deploy.sh` warns when a machine has no pk3s
rather than shipping them itself.

## Consequences

**Gained**

- A release that can be published without redistributing anyone else's assets.

**Lost**

- A new bench machine needs a `distribute-data.sh` pass, ~482 MB, before it can
  run anything.
- The first run on a fresh machine is a two-part install for the user.
