# Config model — how one `.app` self-tunes on every machine

`ioquake3.app` ships one fat binary and one set of configs, and works out what
it's running on at startup. Two layers, both read from the bundle's `Resources/`
by `Com_AutoConfigForMachine()` (`code/qcommon/common.c`), before the renderer
and sound init — so the settings apply to *this* launch, not the next one.

## Layer 1 — per-arch baseline

Picked by the slice that `dyld` loaded, using compile-time macros:

| Slice | Macro tested | Baseline |
|---|---|---|
| G4 / G5 | `__VEC__` / `__ALTIVEC__` | `autoexec-ppc7400.cfg` |
| G3 | `__ppc__` (and not AltiVec) | `autoexec-ppc750.cfg` |
| Intel 64-bit | `__x86_64__` | `autoexec-x86_64.cfg` |

Each baseline is tuned for the **weakest** machine that can load that slice, so
an unrecognised Mac still gets something playable rather than something
aspirational. The `ppc7400` baseline is built around sawtooth's GeForce2 MX —
the slowest GPU of any G4 here — and pins 1024×768.

## Layer 2 — per-machine overlay

`sysctl hw.model` is looked up in `com_machineMap` and, on a hit, that machine's
`autoexec-<machine>.cfg` is applied on top. A miss keeps the baseline; nothing
breaks, it's just untuned.

Mapped today: `PowerMac1,1` (yosemite), `PowerMac3,1` (sawtooth), `PowerMac3,5`
(quicksilver), `PowerMac10,1` (mini-g4), `PowerMac8,1` / `8,2` / `12,1`
(iMac G5), `Macmini2,1` (mini-intel), `iMac19,1` (imac-2019).

The bench and screenshot scripts pass `+set com_archAutoexec 0` to switch both
layers off, so their own `+set` overrides own the run outright.

## Deliberate divergence: no iMac G4 / eMac profile

The QuakeSpasm and Quake II ports map `PowerMac4,2` / `PowerMac6,1` /
`PowerMac6,3` to an `imac-g4` profile. **This port deliberately does not**, and
that is a decision rather than a gap (see the comment in `com_machineMap`).

Those ports need the profile because their G4 baselines ask for more than a
sunflower iMac can deliver. This port's `ppc7400` baseline is already the
conservative one: 1024×768, `r_picmip 1`, no anisotropic filtering, tuned around
a GeForce2 MX. Every iMac G4 and eMac is at least as fast as sawtooth — same GPU
class at the low end, faster CPU — so the baseline is already the right answer
for them, and a dedicated cfg would be a byte-for-byte copy.

Pinning 1024×768 rather than the panel's native resolution is also correct here:
the 17"/20" sunflower panels are 1440×900 / 1680×1050, and filling those would
put the machine well under the fps floor. The mode switch that implies is safe —
the fullscreen mode-switch hard-hang is specific to the G5's R300 driver, and no
iMac G4 shipped one.

If an iMac G4 or eMac ever joins the fleet and benches show headroom, add the
profile then, with numbers behind it.

## Which OS each CPU needs

Slice grading is by **CPU subtype alone** — the OS plays no part, and there is no
fallback to a lower slice. So each slice is built against the oldest OS its CPU
family can run, not the OS the machines here happen to run:

| Slice | Built against | Floor |
|---|---|---|
| `ppc750` | 10.3.9 SDK, `-mmacosx-version-min=10.3` | 10.3.9 Panther |
| `ppc7400` | 10.3.9 SDK, `-mmacosx-version-min=10.3` | 10.3.9 Panther |
| `x86_64` | Lion toolchain, `-mmacosx-version-min=10.6` | 10.6 Snow Leopard |

The `ppc7400` slice serves both the G4s and the G5. Building it at 10.4 would
leave a G4 or G5 on Panther unable to launch, with no way for the user to force a
different slice — see the README for what is and isn't verified on hardware.
