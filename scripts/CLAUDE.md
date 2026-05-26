# scripts/ — contracts + gotchas (ioquake3 old-Mac)

**v0, unvalidated.** Mirrors the gotchas in `~/quakespasm/scripts/CLAUDE.md`;
they apply identically to this fleet.

## Hard rules

- **rsync target is ALWAYS `mini-intel:quake3/`** — never `quakespasm/`,
  never `quake2/`, never `mini-intel:~/`. `build.sh` hard-codes it.
- **`build.sh` flocks `build/.build.lock`.** Don't run g3 + g4 by hand in
  parallel — both are `ARCH=ppc`, share the remote tree, and race `.o` files
  into a wrong-CPU-subtype binary. Use `build-fat.sh` (sequences them).
- After a build, sanity-check: `file build/ioquake3-g3` → `ppc750`,
  `-g4` → `ppc7400`, `-lion` → `x86_64`.

## Per-machine / process gotchas

- **Panther `/bin/sleep` is integer-only** — `sleep 0.2` returns instantly.
  Poll loops use `sleep 1`.
- **Kill the engine with TERM-grace-then-KILL** (`killall -TERM ioquake3;
  sleep; killall -KILL ioquake3`). TERM lets SDL restore the display (Rage 128
  LUT-corruption risk on hard fullscreen kill). **Never `pkill`** (absent on
  Tiger/Panther). Recover a wedged Mac with `ssh <m> '~/bin/qsreboot.sh'`.
- **yosemite rsync needs `--protocol=29`** (Panther rsync 2.5.x).
- **`mini-intel` sleeps** — "No route to host" = asleep; wake and retry.

## Bench specifics (Q3 ≠ Quake)

- Quake III `timedemo` prints `<N> frames <S> seconds <F> fps …`. We run with
  `+set logfile 2` (line-flushed) and poll `baseq3/qconsole.log` for that line,
  then stop the engine — we don't rely on Q3 auto-quitting after a demo.
- The `<demo>` arg is a **real Q3 demo name** (e.g. `four`), not `demo1/2/3`.
  Enumerate demos from the staged pk3s (point-release `.dm_68` live in pak8).
- `qconsole.log` lands under `fs_homepath`; bench.sh sets `fs_homepath=$PWD`
  so it writes into `~/Desktop/quake3/baseq3/`.
- `benchmarks/results.csv` is **rolling history** — never wipe mid-round.
  `--reset` is the only wipe and backs up first.
