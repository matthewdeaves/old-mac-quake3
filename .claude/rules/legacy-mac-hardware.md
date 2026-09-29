---
paths:
  - "scripts/*bench*.sh"
  - "scripts/*smoke*.sh"
  - "scripts/*deploy*.sh"
  - "scripts/*launch*.sh"
  - "scripts/*host*.sh"
---

# Hardware hazards

Read `docs/HARDWARE.md` before a fleet run. Native resolution only; make a fullscreen engine quit itself.
Tiger process detection, Panther rsync and recovery prerequisites are documented there.

- Never `killall -KILL` a rendering fullscreen engine (wedges WindowServer until reboot); use `+set nextdemo quit`. Never `pkill` (absent on Tiger/Panther).
- Never run `/sbin/reboot` with any argument to test it; a `--help` probe rebooted the G3.
- Never modify the read-only Q3 install at `mini-intel:/Users/mini/Games/ioquake3/` or `/Developer/SDKs`.
- A released bench lock is not proof the engine stopped; never background an engine on a fleet machine without waiting for exit (#29).
- Never wipe `benchmarks/results.csv` mid-round.
