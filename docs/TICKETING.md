# Tickets and cross-repo work

Board, labels and claim rules are in the fleet POLICY (retro-agents/POLICY.md); this file only holds what is specific to this repo.
Sections: Claims, Cross-repo references.

## Claims
- Every script that drives a fleet Mac re-execs under `scripts/pick-bench-host.sh --run`, so the host is claimed for the run. Check `scripts/pick-bench-host.sh --status` before assuming a box is idle. `BENCH_NO_LOCK=1` is for debugging the picker only.

## Cross-repo references
Labels: `from:infra`, `from:port`, `needs-measurement`, `cross-port`. File sibling tickets for cross-port findings; a fix is not evidence for another engine.
Board transitions and the public/private boundary are governed by fleet POLICY.
