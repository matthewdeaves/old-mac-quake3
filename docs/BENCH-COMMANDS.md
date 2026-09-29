# Benchmark commands

Use safebench for native-resolution timedemos.
The adapter is port-owned; shared tools come from the shared-script pin.
VM artifact staging requires a local copy, as shown below.

## Commands

```sh
scripts/safebench.sh <machine> <WxH>     # THE safe timedemo. Use this.
scripts/bench.sh <machine> <demo> <WxH> [runs]
scripts/parallel-bench.sh [--quick|--reset|--no-<machine>]
scripts/bench-evidence.sh <machine> <round-label>   # evidence bundle + VALID/INVALID verdict, wraps safebench.sh via scripts/bench-adapter.sh. Needs BENCH_RES=<WxH> (native, never guessed). Synced from old-mac-build-host (build-host#104); bench-adapter.sh is port-owned, never synced.
scripts/shared.sh bench-compare.sh --baseline <bundle...> --candidate <bundle...>   # BETTER/WORSE/NO-DIFFERENCE/INCONCLUSIVE verdict from bench-evidence.sh bundles. Quote this instead of eyeballing numbers. Pinned via shared-scripts.pin (#71), not a local copy.
BENCH_LOCK_WAIT=1800 scripts/pick-bench-host.sh --run qemu-tiger3d <label> -- <deploy-dmg.sh|smoke-dmg.sh|screenshot.sh|BENCH_ARTEFACT=<local-copy-of-installed-binary> bench-evidence.sh> ...   # iterate the PPC test loop on the QemuMac G4+Radeon9700 VM; deploy-dmg.sh/screenshot.sh want a bare version (v0.6.21), never a relative dist/ path; BENCH_ARTEFACT must point at a LOCAL file, never fetched live off the host under test
```
