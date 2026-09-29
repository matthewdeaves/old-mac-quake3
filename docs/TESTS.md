# Test entry points

## Local checks
Repository and binary-format contracts: `tests/test-repo.sh`, `tests/test-macho-archs.sh`.
Benchmark and renderer regressions: `tests/test-bench-data.py`, `tests/test-ssao-fallback.py`, `tests/test-stream-buffers.py`. Join-log regression: `scripts/test-join-log.sh`.

## Installed artifact
`scripts/release-check.sh` checks the release inputs described in `docs/RELEASE.md`. Use `docs/BUILD-COMMANDS.md` for installed smoke and `docs/BENCH-COMMANDS.md` for safebench.
