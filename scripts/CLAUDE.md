# scripts/ - contracts and gotchas

The full reasoning is in `../docs/adr/`; the hazards are repeated here because
they bite inside these scripts.

## Hard rules

- **rsync target directory is ALWAYS `quake3/`** on whichever build host - never
  `quakespasm/`, `quake2/` or `<host>:~/`. The scripts hardcode the DIRECTORY
  (`PROJ_REMOTE=quake3`); they do not hardcode the HOST.
- **The build host is chosen at runtime.** `build.sh`, `build-fat.sh` and
  `build-gamedylibs.sh` call `pick-build-host.sh --acquire` and release on exit.
  `BUILD_HOST=<alias>` pins one; `--status` shows both. `build-fat.sh` and
  `build-gamedylibs.sh` hold ONE host for their whole run, because the slices
  must be lipo'd together on the same box. `../docs/adr/0004`
- **`build.sh` flocks `build/.build.lock`.** Don't run g3 and g4 by hand in
  parallel: both are `ARCH=ppc`, share the remote tree, and race `.o` files into
  a wrong-subtype binary. Use `build-fat.sh`, which sequences them. The flock is
  per-checkout and cannot see a build another repo started on the same mini -
  that is what the picker's on-host lock is for.
- After a build, sanity-check `file build/ioquake3-g3` -> `ppc750`, `-g4` ->
  `ppc7400`, `-lion` -> `x86_64`. The build's own `lipo` assertion is the real
  guard. `../docs/adr/0003`
- **Never modify** the read-only Q3 install at
  `mini-intel:/Users/mini/Games/ioquake3/`, or the shared `/Developer/SDKs`.

## Machine and process gotchas

- **Make the engine QUIT ITSELF; never KILL a fullscreen app.** `+set nextdemo
  quit`. `killall -KILL` on a rendering fullscreen ioquake3 wedges it in
  uninterruptible GPU-driver exit and hangs the WindowServer until a reboot.
  `killall -TERM` is a backstop only; **never `pkill`** (absent on Tiger and
  Panther). Native resolution only - a mode switch hard-hangs the G5's R300
  driver. `safebench.sh` encodes the whole pattern. `../docs/adr/0009`
- Recover a wedged Mac with `ssh <m> '~/bin/qsreboot.sh'`, but only after the
  one-time NOPASSWD setup (`install-host-tools.sh` then `sudo
  qsreboot-setup.sh`), and confirm it actually cycles.
- **Tiger's `ps` lies**: `comm` is not a valid keyword on 10.4, and `ps ax`
  truncates at 79 columns. Use `killall -0 <name>` or `ps -axc -o pid,ucomm`.
- **Panther `/bin/sleep` is integer-only** - `sleep 0.2` returns instantly. Poll
  loops use `sleep 1`.
- **yosemite rsync needs `--protocol=29`** (Panther ships rsync 2.5.x).
- **`mini-intel` sleeps** - "No route to host" means asleep; wake and retry.
- Any script that direct-execs the engine must call `lsregister-app.sh` on the
  way out. `../docs/adr/0010`

## Bench specifics (Q3 is not Quake)

- Quake III `timedemo` prints `<N> frames <S> seconds <F> fps ...`. Run with
  `+set logfile 2` (line-flushed) and poll `baseq3/qconsole.log` for that line;
  don't rely on Q3 auto-quitting after a demo.
- The `<demo>` argument is a real Q3 demo name (e.g. `four`), not `demo1/2/3`.
  Point-release `.dm_68` demos live in `pak8.pk3`.
- `qconsole.log` lands under `fs_homepath`; `bench.sh` sets `fs_homepath=$PWD`
  so it writes into `~/Desktop/quake3/baseq3/`.
- `benchmarks/results.csv` is **rolling history** - never wipe it mid-round.
  `--reset` is the only wipe and backs up first.
- `bench.sh` validates the resolution argument: `bench.sh <m> four 3` would
  otherwise time a 3x3 render.
