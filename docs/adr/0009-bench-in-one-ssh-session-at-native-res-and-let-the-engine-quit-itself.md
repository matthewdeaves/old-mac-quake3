# 9. Bench in one ssh session, at native resolution, and let the engine quit itself

Date: 2026-08-20
Status: accepted

## Context

Benching a fullscreen GL app on 2000-era Mac GPUs over ssh is three problems at
once, and getting any of them wrong wedges a machine nobody is there to reset.
Four Macs have needed power-button resets in this project, and quicksilver,
mini-intel and the G5 have each needed reboots during bench rounds.

**Hardware hazards, all observed:**

1. **A non-native fullscreen set is a real mode switch.** A hard `killall -KILL`
   mid mode-set leaves the Rage 128 / R200 / R300 / GMA display corrupted -
   black screen, manual reset. The GPUs also reject or letterbox non-native
   modes: the game came up **windowed** on the G5 and **pillarboxed** on
   quicksilver. **The G5's Leopard R300 driver hard-hangs the OS on a
   mode switch**, which is why the G5 is captured and benched only at its
   native 1440x900.
2. **`killall -KILL` on a rendering fullscreen ioquake3 wedges the GPU driver.**
   The process is left in uninterruptible driver exit (`ps` state `E`,
   un-killable), holding the GL context and hanging the whole WindowServer - the
   desktop freezes, Force Quit will not open, only a reboot clears it.
   `wait $PID` on such a process hangs forever too.
3. **Repeated ssh-launched fullscreen runs can leave the display grabbed**, so
   the next launch hangs in early init, before `Initializing OpenGL`.
4. **Windowed mode is not a safe fallback over ssh.** An ssh-launched app with
   no foreground Aqua focus fails to create a window and exits early - empty
   log, no fps - so the mode switch cannot be sidestepped by going windowed.
5. **Backgrounding an ssh-launched app kills it.** If the launching ssh session
   returns, the detached process loses its Mach bootstrap / WindowServer session
   and dies with `CFMessagePortCreateLocal failed` before opening the display.
6. **A stale PID file hangs the next launch headless.** Any un-clean exit
   (SIGKILL, SIGPIPE, wedge) leaves `~/Library/Application Support/Quake3/
   ioq3.pid`; the next launch pops a modal "Abnormal Exit - safe video
   settings?" dialog (`common.c`, via `Sys_WritePIDFile`) that blocks forever
   with no keyboard to answer it. SIGTERM and SIGINT *are* handled and do clean
   up; only SIGKILL and SIGPIPE strand the pid.

## Decision

**One ssh session that outlives the app, native resolution only, and the engine
quits itself.** Encoded in `scripts/safebench.sh` and `scripts/bench.sh`.

- **ONE session.** The engine is backgrounded but the *same* session stays alive
  polling the log. Keeping the session open is what lets it render.
- **Native desktop resolution only** - quicksilver and mini-g4 1680x1050,
  imac-g5 1440x900, mini-intel 1920x1080, yosemite 800x600, sawtooth 1024x768.
  At native res the fullscreen set is a *same-mode* set, no mode switch, which
  is the only fullscreen these GPUs survive cleanly, and it fills the panel.
- **`+set nextdemo quit`.** When a timedemo finishes, `CL_DemoCompleted()`
  prints the fps line then runs the `nextdemo` cvar as a command (`cl_main.c`),
  so the engine executes `quit` and exits normally: SDL restores the display,
  the pid file is removed, no signal is ever sent. `killall -TERM` is a
  last-resort backstop only. **`killall -KILL` is never used on a fullscreen
  app, and `wait` is never called on its pid.**
- **`rm -f` the pid file before every headless launch** and after each run.
- **Never `pkill`** - it does not exist on Tiger or Panther.
- **Existence checks use `killall -0 <name>`**, not `ps | grep`. See below.
- Don't remote-bench the fragile fleet in a tight loop. One careful run with a
  health check, and `~/bin/qsreboot.sh` on a hang, is the most to attempt;
  prefer on-site Finder-launch validation. The G3 (CRT, no widescreen modes)
  tolerates benching fine - the wedging is specific to the LCD-panel widescreen
  machines and their drivers.

**Tiger's `ps` cannot be trusted for process detection**, two independent silent
limitations that both produced wrong answers here on the same day:

- **`comm` is not a valid ps keyword on 10.4.** `ps -axo comm` returns
  "keyword not found". `ps -axo comm,pid` is worse than an outright failure: it
  errors on `comm` but still prints the PID column, so a grep over it sees bare
  numbers and can never match a process name. Every guard built on it was dead.
- **`ps ax` truncates each line to 79 columns.** `WindowServer`'s path is 113
  characters, so `ps ax | grep -i windowserver` returns nothing on a perfectly
  healthy machine. This briefly looked like the bench had killed WindowServer;
  it was alive at PID 57 throughout.

Use instead: `killall -0 <name>` (matches on process NAME, immune to both,
verified on Tiger, Leopard and Lion), or `ps -axc -o pid,ucomm` (`ucomm` *is*
valid on Tiger unlike `comm`, and `-c` prints the bare command name so nothing
is truncated; verified on 10.4.11, 10.5.8 and 10.7.5). `ps ax | grep` is
acceptable only when the name appears early in the command line, e.g.
`./ioquake3 +set ...`. `bench.sh` ORs `killall -0` with `ps ax` so a failure of
either still detects a live engine.

**Reboot recovery: verify, never trust.** `ssh <host> '~/bin/qsreboot.sh'`
reboots a wedged Mac, but only after the one-time NOPASSWD setup
(`scripts/install-host-tools.sh <host>`, then `ssh <host> 'sudo
~/bin/qsreboot-setup.sh'`). Without it, tier 1 (`sudo -S /sbin/reboot`) fails
silently and falls through to tier 2, a Finder AppleEvent restart that **returns
success even when it does nothing** on a wedged or headless Finder. `qsreboot.sh`
now prints a `QSREBOOT: tier1/tier2` marker, and callers verify the host
actually drops off the net and returns rather than trusting the exit code. All
six machines had the setup installed on 2026-07-05.

> **Never run `/sbin/reboot` with any argument to "test" it.** BSD `reboot`
> ignores unknown flags and just reboots. A `sudo /sbin/reboot --help` probe
> rebooted the G3.

## Bench discipline

- Q3 uses `timedemo`, not Quake's: `+set timedemo 1 +demo <name>`. `<demo>` is a
  real Q3 demo name such as `four`, not `demo1/2/3`; point-release `.dm_68`
  demos live in `pak8.pk3`.
- `+set logfile 2` gives a line-flushed `qconsole.log`, which is the poll target.
  It lands under `fs_homepath`; `bench.sh` sets `fs_homepath=$PWD`.
- **3 runs, median of 2 and 3.** Append to `benchmarks/results.csv`, which is
  rolling history - **never wipe it mid-round**; `--reset` is the only wipe and
  backs up first. Raw logs in `benchmarks/raw/`. Tag rows
  `(commit, machine, demo, res)`. Two commits per phase: code, then bench data.
- Both config layers are suppressed for a bench: the deployed `autoexec.cfg` is
  moved aside and restored on exit, and the engine runs with
  `+set com_archAutoexec 0` (ADR 0007).
- `bench.sh` validates the resolution argument. `bench.sh <m> four 3`, meaning
  three runs, would otherwise split to W=3 H=3 and time a 3x3 render - the
  Quake II port shipped nine such rows at 1x1.
- `parallel-bench.sh` resolves the commit once and exports it, so side commits
  during a long run cannot drift the row tags; CSV appends are under `PIPE_BUF`
  so concurrent legs are safe.
- **`yosemite` and `yosemite-tiger` are one Mac**, the G3 booted from its 10.3.9
  or its 10.4.11 partition. `parallel-bench.sh` skips `yosemite-tiger` by
  default; opt in explicitly.

## Consequences

**Gained**

- Unattended fleet benching that has stopped wedging machines.

**Lost**

- Every bench is at one resolution per machine, its native one, so
  resolution-scaling studies need on-site work.
- `safebench.sh` still cannot fully de-risk ssh fullscreen; on-site validation
  remains the stronger evidence.

**Operational notes**

- **Panther's `/bin/sleep` is integer-only** - `sleep 0.2` returns instantly.
  Poll loops on yosemite use `sleep 1`.
- **yosemite rsync needs `--protocol=29`** (Panther ships rsync 2.5.x).
- **`mini-intel` sleeps aggressively** - "No route to host" means asleep; wake
  and retry.
- **imac-g5 ssh is flaky under back-to-back benching**, roughly 1 in 3
  ("unreachable", or a launch that writes no fps line). It always recovers on a
  short re-poll; not a wedge, no reboot needed. Run samples one at a time.
- Old-Mac ssh needs legacy crypto; `~/.ssh/config` carries the `+ssh-rsa` and
  pre-2014 KEX entries and `id_rsa_tiger`.
