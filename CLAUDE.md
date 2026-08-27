# ioquake3 old-Mac port (Agent Router)

Quake III Arena on ioquake3 as ONE fat binary across PowerPC and Intel Macs, from a single `ioquake3.app`. 
Sister projects on the same fleet and tooling: **old-mac-quakespasm**, **old-mac-quake2**, **old-mac-halflife**. QuakeSpasm is the mature template.

## Goal in one line
Best-looking ioquake3 that stays playable on each machine class, from one fat binary that auto-tunes per machine. Floors: **G3 >= 20 fps, G4/Lion >= 60 fps**, G5 and modern uncapped. **Above the floor, effects beat fps.**

## Centralized CI
All documentation strictly points to `old-mac-build-host` as the centralized source of truth for builds and CI. 

## Documentation Router

> **CRITICAL**: This file is a lightweight router. Do not bloat it with context. Dive into the specific files below when working on those topics.

* **Build System & Commands:** Read `.claude/rules/build-system.md` for build scripts, compilation facts, slices, deployment commands, and hard rules.
* **Hardware & Traps:** Read `.claude/rules/legacy-mac-hardware.md` for the fleet matrix, old macOS quirks, hardware wedge hazards, and platform traps.
* **Ticketing & Cross-Repo:** Read `.claude/rules/ticketing-workflow.md` before making any GitHub issues, dealing with cross-repo tasks, or using the shared fleet locking mechanism.

## Shared Agent Block
See `SHARED-BLOCK.md` for global agent instructions (if present). Do not attempt to edit `SHARED-BLOCK.md` yourself.

## Architecture Decision Records (ADRs) & History
* **Reasoning and rejected alternatives:** `docs/adr/`
* **Measured numbers:** `docs/PROFILING.md` and `benchmarks/results.csv`
* **Lessons from breakages:** `MISTAKES.md`
* **Tuning Inventory:** `docs/KNOBS.md`
