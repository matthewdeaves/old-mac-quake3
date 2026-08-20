# 7. One app self-tunes: by architecture then by `hw.model`

Date: 2026-08-20
Status: accepted

## Context

One fat binary reaches machines ranging from a 449 MHz G3 with a 16 MB Rage 128
to a 2019 iMac. A single set of cvars cannot serve both, and asking the user to
edit a config on a Panther box is not the deployment model.

## Decision

**`ioquake3.app` ships one binary and one set of configs and works out what it
is running on at startup.** Two layers, both read from the bundle's
`Resources/` by `Com_AutoConfigForMachine()` in `code/qcommon/common.c`, before
the renderer and sound init - so the settings apply to *this* launch, not the
next one.

**Layer 1, per-arch baseline**, picked by the slice `dyld` loaded, using
compile-time macros:

| Slice | Macro tested | Baseline |
|---|---|---|
| G4 / G5 | `__VEC__` / `__ALTIVEC__` | `autoexec-ppc7400.cfg` |
| G3 | `__ppc__` and not AltiVec | `autoexec-ppc750.cfg` |
| Intel 64-bit | `__x86_64__` | `autoexec-x86_64.cfg` |

Each baseline is tuned for the **weakest** machine that can load that slice, so
an unrecognised Mac gets something playable rather than something aspirational.
The `ppc7400` baseline is built around sawtooth's GeForce2 MX, the slowest GPU
of any G4 here, and pins 1024x768.

**Layer 2, per-machine overlay.** `sysctl hw.model` is looked up in
`com_machineMap`; on a hit that machine's `autoexec-<machine>.cfg` is applied on
top. A miss keeps the baseline. Mapped today: `PowerMac1,1` (yosemite),
`PowerMac3,1` (sawtooth), `PowerMac3,5` (quicksilver), `PowerMac10,1` (mini-g4),
`PowerMac8,1` / `8,2` / `12,1` (iMac G5), `Macmini2,1` (mini-intel), `iMac19,1`
(imac-2019). All ten cfgs are bundled into `Resources/` by `make-app.sh`.

**`+set com_archAutoexec 0` switches both layers off.** The bench and screenshot
scripts pass it, so their own `+set` overrides own the run outright - that is
what makes bench rows comparable across commits.

Validated on yosemite: with no `baseq3/autoexec.cfg` present, the `.app`
self-applied its settings purely from `PowerMac1,1`.

## Deliberate divergence, no iMac G4 / eMac profile

The QuakeSpasm and Quake II ports map `PowerMac4,2` / `PowerMac6,1` /
`PowerMac6,3` to an `imac-g4` profile. **This port deliberately does not**, and
that is a decision rather than a gap (recorded in `com_machineMap`).

Those ports need it because their G4 baselines ask for more than a sunflower
iMac can deliver. This port's `ppc7400` baseline is already the conservative
one - 1024x768, `r_picmip 1`, no anisotropic filtering, tuned around a GeForce2
MX - and every iMac G4 and eMac is at least as fast as sawtooth, so a dedicated
cfg would be a byte-for-byte copy.

Pinning 1024x768 rather than the panel's native resolution is also right here:
the 17" and 20" sunflower panels are 1440x900 and 1680x1050, and filling those
would put the machine well under the fps floor. The mode switch that implies is
safe - the fullscreen mode-switch hard-hang is specific to the G5's R300 driver
(ADR 0009), and no iMac G4 shipped one.

If an iMac G4 or eMac ever joins the fleet and benches show headroom, add the
profile then, with numbers behind it.

## Alternatives rejected

**One config for everything.** Either the G3 is unplayable or the G5 is wasted.

**Per-machine builds.** Defeats the one-fat-binary model (ADR 0002) and
multiplies the release surface by the fleet size.

**Writing settings into `q3config.cfg` on first run.** Applies next launch, not
this one, and overwrites what the user changed.

## Consequences

**Gained**

- One artefact self-tunes on every Mac, and an unknown Mac still boots to a
  conservative, playable baseline.

**Lost**

- Every tuning change is a config edit plus a redeploy of the bundle, and the
  mapping only covers machines someone has actually benched.

**Rule that follows**

- Every per-target knob must be flippable at runtime (cvar) or at launch
  (cmdline), never hardcoded, so an A/B needs no rebuild.
