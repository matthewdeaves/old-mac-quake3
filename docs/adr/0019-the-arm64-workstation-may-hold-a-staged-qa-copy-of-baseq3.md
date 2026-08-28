# 19. The arm64 workstation may hold a staged QA copy of `baseq3`

Date: 2026-08-28
Status: accepted

## Context

ADR 0011 ("we ship code, not content") governs what this project
**distributes**: no id assets in the DMG, the server tarball, or the repo
itself. It says nothing about whether a machine used for QA may hold a local,
never-redistributed staging copy of `baseq3`, the same way every vintage bench
Mac already does via `scripts/distribute-data.sh`.

Issue #38 (`from:infra`, raised by `old-mac-build-host`) reports the user's
2026-08-28 directive: the fleet's arm64 workstation (`Hayleys-MacBook-Air`,
the only Apple Silicon Mac available) is now a full bench-lock host for real
launch QA, claimable via `pick-bench-host.sh --run workstation ...` like any
other fleet machine, local-exec rather than ssh
(`old-mac-build-host` ADR 0004; this repo's `pick-bench-host.sh` note 3). The
user's own words: "all machines need the same game data." Read broadly,
`.claude/rules/build-system.md`'s "No id assets, ever" could be misread as
forbidding this. It does not: that line is about what ships, not about a QA
host holding a local copy the way the whole bench fleet already does.

## Decision

**The arm64 workstation, and `imac-2019`, are QA hosts like any bench Mac and
may hold a staged copy of `baseq3` for launch testing.** This does not amend
ADR 0011's shipping decision; it clarifies that ADR 0011 was never a
restriction on QA hosts in the first place - the vintage fleet has staged
`baseq3` copies on every bench machine since `distribute-data.sh` was written,
and this only extends that same pattern to the two non-vintage QA hosts.

- Source and rules are unchanged: the reference copy is the read-only install
  at `mini-intel:/Users/mini/Games/ioquake3/` (never modified), staged at
  `mini-intel:~/Desktop/quake3/baseq3/`, relayed by `distribute-data.sh`,
  pk3s only.
- `distribute-data.sh` now accepts `workstation` as a target. Every other
  target is ssh+rsync to a remote host; `workstation` is this same machine
  (no sshd, no hostkey - `pick-bench-host.sh`'s `LOCAL_ALIASES`), so it ships
  via a local copy into `$HOME/Desktop/quake3/baseq3` instead. `imac-2019`
  needed no change - it was already a valid remote target.
- No new asset path layout was needed: the workstation and `imac-2019` use the
  identical `~/Desktop/quake3/baseq3` layout every other bench Mac uses.
  Measured by reading `distribute-data.sh` and `pick-bench-host.sh` together;
  the only gap was the missing `workstation` case arm, now added.
- The repo itself still ships no assets, has none checked in, and
  `build/baseq3-cache` (the relay cache) stays gitignored. That constraint is
  untouched.

## Consequences

**Gained**: the workstation and `imac-2019` can be provisioned with QA data
the same way as the rest of the fleet, one `distribute-data.sh workstation`
call, needed for #37's launch QA matrix to cover every machine including the
two non-vintage hosts.

**Lost**: nothing. No shipping surface changed.

**Not done here**: `deploy.sh`, `deploy-dmg.sh` and `smoke-dmg.sh` do not yet
have a local-exec branch for `workstation` the way `distribute-data.sh` now
does and `pick-bench-host.sh` already did - they still assume ssh. Follow-up
if the workstation needs a full deploy-and-smoke pass rather than a manual
launch check; not blocking today's QA, which can build/deploy from an
existing checkout on the workstation directly.
