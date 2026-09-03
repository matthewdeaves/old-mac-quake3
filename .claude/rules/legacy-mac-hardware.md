# Legacy Mac Hardware & Environments

## Machines

| Machine | CPU | GPU | macOS | Slice | Role |
|---|---|---|---|---|---|
| yosemite | G3 449 MHz | Rage 128 16 MB | Panther 10.3.9 (also 10.4.11) | ppc750 | bench |
| sawtooth | G4 500 MHz | GeForce2 MX 32 MB | Tiger 10.4.11 | ppc7400 | bench |
| quicksilver | G4 733 MHz | Radeon 9000 Pro 64 MB | Tiger 10.4.11 | ppc7400 | bench, DMG fallback |
| mini-g4 | G4 1.25 GHz | Radeon 9200 32 MB | Tiger 10.4.11 | ppc7400 | bench, DMG host |
| imac-g5 | G5 2.0 GHz | Radeon 9600 128 MB | Leopard 10.5.8 | ppc7400 | bench |
| mini-intel | Core 2 Duo 2.33 GHz | GMA 950 | Lion 10.7.5 | x86_64 | **build**, bench, data source |
| mini-intel2 | Core 2 Duo | - | Lion 10.7.5 | - | **build** |
| imac-2019 | i5-9600K | Radeon Pro 580X 8 GB | Sequoia 15.7 | x86_64 | modern reference |

Build TARGET names (`g3`/`g4`/`lion`) are chip family plus SDK, not machines.
The two Intel minis are interchangeable Macmini2,1 / 10.7.5 boxes. The read-only Q3 install lives at `mini-intel:/Users/mini/Games/ioquake3/`; staged copy is `mini-intel:~/quake3-play/baseq3/` (moved off `~/Desktop/` 2026-09-04, old-mac-quake3#49 — TCC blocks headless reads there; NOT plain `~/quake3`, which is the build-tree rsync target on this same host).

## Hardware that can be wedged or damaged
Read `docs/adr/0009` before benching anything.

- **Never `killall -KILL` a rendering fullscreen engine.** It sticks in uninterruptible GPU-driver exit (`ps` state `E`) and hangs the whole WindowServer until a reboot. Use `+set nextdemo quit` and let it exit itself.
- **Native resolution only.** A non-native fullscreen set is a real mode switch; **the G5's Leopard R300 driver hard-hangs the OS on one**, and the other old GPUs corrupt their display.
- **Never `pkill`** - absent on Tiger and Panther.
- **Never run `/sbin/reboot` with any argument to "test" it.** BSD `reboot` ignores unknown flags and just reboots. A `--help` probe rebooted the G3.
- Reboot recovery (`~/bin/qsreboot.sh`) only works after the one-time NOPASSWD setup, and its Finder fallback returns success without rebooting. Verify the host actually drops off the net and returns.

## Platform Traps
- **Tiger's `ps` lies.** `comm` is not a valid keyword on 10.4 and `ps ax` truncates at 79 columns. Use `killall -0 <name>` or `ps -axc -o pid,ucomm`.
- **Panther's `/bin/sleep` is integer-only**; `sleep 0.2` returns instantly.
- **yosemite rsync needs `--protocol=29`** (Panther ships rsync 2.5.x).
