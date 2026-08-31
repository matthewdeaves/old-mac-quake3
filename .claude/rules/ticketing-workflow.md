# Cross-Repo & Ticketing Workflow

Seven repos are worked on together: the four game ports, the private `retro-server-infra` which runs the servers those ports build, `old-mac-build-host` which owns the shared host pickers and the source-stamp primitive, and `retro-agents` which holds the briefs. A session may be open in each at once. Three rules keep them out of each other's way.

**Hardware is claimed, never assumed free.**
Every script that deploys to, benches on, or otherwise drives a fleet machine re-execs itself under `scripts/pick-bench-host.sh --run`, so the machine is claimed for the run and released however it ends. The lock is a directory on the target, shared with the build lock and visible to every repo, agent and workstation. Check `scripts/pick-bench-host.sh --status` before assuming a box is idle. `BENCH_NO_LOCK=1` exists only for debugging the picker.

**Cross-repo work goes through GitHub, not chat.**
One board covers all seven repos: https://github.com/users/matthewdeaves/projects/8. Columns: `Triage / Measuring / Ready / In progress / Blocked / Review / Done`, with `Source` and `Evidence` fields. **`Review` is where your own work stops.** Move a finished ticket there, not to `Done`.

File cross-repo work as an issue and put it on the board:
```sh
gh issue create -R matthewdeaves/<repo> --project Retro \
  --label from:port,needs-measurement --title "..." --body "..."
```

Labels, the same four in every repo: **`from:infra`** raised by the server side for a port to act on, **`from:port`** raised by a port for another repo, **`needs-measurement`** the claim has no number or hardware repro behind it yet, **`cross-port`** it affects more than one port.

**Anything one session raises at another starts in `Triage` with `needs-measurement`, and is not worked until a human or a measurement moves it.**
An issue written by another agent carries no more evidence than the reasoning that produced it. The same finding really does recur across ports, so `cross-port` is worth using, but file the sibling issues rather than assuming the fix transfers.

**This repo is PUBLIC. `retro-server-infra` is also PUBLIC (confirmed by the user 2026-08-31; it went private 2026-07-28 over an upstream dispute, since resolved).**
It describes the topology, firewall rules and admin surface of a live host. Still never copy addresses, key material, tunnel tokens or `.env` content out of it into this repo, in code, docs or a commit message.
