# docs/ — index

Documentation for the ioquake3 old-Mac port. Sticky facts live in the
repo-root [`CLAUDE.md`](../CLAUDE.md).
[`../KICKOFF_PROMPT.md`](../KICKOFF_PROMPT.md) is the original kickoff plan,
kept for history — it describes a pipeline that has since been built and
validated, so don't read it as current state.

## Live references

- [`CONFIG.md`](CONFIG.md) — how one `.app` self-tunes: the per-arch baseline +
  `hw.model` overlay, and which OS each slice needs.
- [`KNOBS.md`](KNOBS.md) — Quake III cvar / cmdline knob inventory used for
  per-machine tuning.
- [`PROFILING.md`](PROFILING.md) — measured wins and measured negatives from the
  tuning rounds.

## ideas/ — forward-looking design (not built)

(empty for now — e.g. the AI-Director concept from the QuakeSpasm side could
land here if ported.)

## archive/

(empty for now — superseded plans go here.)

## See also

- [`../scripts/README.md`](../scripts/README.md) — toolchain + host matrix.
- `~/quakespasm/` — the mature sibling project this one is modeled on.
