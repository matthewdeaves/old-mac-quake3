# Tickets and cross-repo work

Board, labels and claim rules are in the fleet POLICY (retro-agents/POLICY.md); this file only holds what is specific to this repo.
Sections: Claims, Cross-repo issues, Public repo.

## Claims
- Every script that drives a fleet Mac re-execs under `scripts/pick-bench-host.sh --run`, so the host is claimed for the run. Check `scripts/pick-bench-host.sh --status` before assuming a box is idle. `BENCH_NO_LOCK=1` is for debugging the picker only.

## Cross-repo issues
- One board (project 8) covers all repos. File an issue in the owning repo, then `bin/board-add.sh <repo>#<n>`. Labels: `from:infra`, `from:port`, `needs-measurement`, `cross-port`.
- An issue one session raises at another starts in Triage and is not worked until a human or a measurement moves it. File sibling issues for `cross-port` findings rather than assuming a fix transfers.

## Public repo
- This repo and `retro-server-infra` are public. Never copy addresses, key material, tunnel tokens or `.env` content from infra into this repo, in code, docs or a commit message.
