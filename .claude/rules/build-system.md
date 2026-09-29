---
paths:
  - "scripts/*.sh"
  - "Makefile"
  - "shared-scripts.pin"
---

# Build and bench entry points

Commands: `docs/BUILD-COMMANDS.md` and `docs/BENCH-COMMANDS.md`.
Slice constraints: `docs/BUILD-FACTS.md`. Script-specific hazards: `docs/SCRIPT-CONTRACTS.md`.

- Never run g3 and g4 builds by hand in parallel (shared remote tree, wrong-subtype binary); use `scripts/build-fat.sh`.
- rsync target is always `oldmac/quake3/src/`; `bench.sh` validates the resolution argument.
