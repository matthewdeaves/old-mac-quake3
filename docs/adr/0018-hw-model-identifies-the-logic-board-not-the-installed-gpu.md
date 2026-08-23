# 18. `hw.model` identifies the logic board, not the installed GPU

Date: 2026-08-23
Status: accepted (documented limitation, no code change)

## Context

`Com_AutoConfigForMachine()` (`code/qcommon/common.c`, ADR 0007) overlays a
per-machine config picked by `sysctl hw.model`. Every tower model in
`com_machineMap` (`PowerMac1,1` yosemite, `PowerMac3,1` sawtooth,
`PowerMac3,5` quicksilver) has a real AGP graphics slot a user could have
populated differently than our bench unit. Issue #33 asked whether that is a
real risk or a theoretical one.

## What was measured

`PowerMac3,5` is specifically the Quicksilver **2002** revision (867
MHz-1.25 GHz), not the original 2001 Quicksilver. Checked against Apple's own
published configurations for every `PowerMac3,5` speed grade (EveryMac.com
spec pages, cross-checked per model):

| Speed grade | Standard graphics | BTO option |
|---|---|---|
| 800 MHz | ATI Radeon 7500, 32 MB | NVIDIA GeForce4 Ti, 128 MB |
| 933 MHz | NVIDIA GeForce4 MX, 64 MB | NVIDIA GeForce4 Ti, 128 MB |
| 1.0 GHz / 1.25 GHz | (GeForce4 MX or Ti pattern continues) | |

**A Radeon 9000 Pro - what our own `quicksilver` bench unit has, and what
`scripts/bundle/autoexec-quicksilver.cfg` is tuned around - was never a
factory or build-to-order option for `PowerMac3,5` at any speed grade.** Our
bench unit's card is an aftermarket AGP upgrade, not representative of what
a `PowerMac3,5` owner has by default. A real owner with the actual factory
Radeon 7500 (weaker, 32 MB) or GeForce4 Ti (stronger, 128 MB) reports the
identical `hw.model` and gets the identical overlay either way.

Sawtooth (`PowerMac3,1`) looks like the same class of problem: it factory-shipped
with an ATI Rage 128 (Rage 128 Pro after Dec 1999), with GeForce2 MX
available as an alternative in some configurations - less cleanly confirmed
than the Quicksilver case above, not re-verified per speed grade here.

## Decision

**Document the limitation. No code change from this ticket.** The overlay
mechanism has no way to detect the installed GPU: `Com_AutoConfigForMachine()`
runs before renderer/sound init by design (ADR 0007), specifically so its
settings apply to the current launch, and at that point `glConfig.renderer_string`
does not exist yet to key off. The two real fixes both change that design
rather than patch this ticket:

- An IOKit device probe for the installed AGP/PCI card before renderer init.
  Real work, unvalidated against how it behaves across 10.3-10.5, and this
  session cannot bench it without hardware that actually carries a different
  card than our bench units.
- Moving (part of) the overlay to after `GLimp_Init`, keying off
  `glConfig.renderer_string`, and re-applying archive cvars. Changes the
  ADR 0007 ordering guarantee ("settings apply to *this* launch") for
  whatever moves.

Neither is undertaken speculatively. A code change here trades a known-safe
default (the per-arch baseline, tuned to the weakest known GPU in that arch,
ADR 0007) for a guess about hardware nobody on this project has measured.
**Above the floor, effects beat fps - but only when the cost is measured, not
guessed**, and there is no bench unit here to measure against.

## What this does NOT affect

A total `hw.model` miss (a Mac model never added to `com_machineMap`) is
unaffected and already safe: it keeps the per-arch baseline, which
`Com_ExecConfigFromBundle` falls into silently and without crashing (ADR
0007). This ADR is about a narrower case: a MATCHED model whose installed
card differs from the one bench unit that model's overlay was tuned around.

## Consequences

**Gained**: the risk is now measured for one machine (quicksilver, cleanly)
rather than inferred, and it is written down so nobody re-derives it from
scratch or "fixes" it with an unbenched guess.

**Lost**: nothing shipped changes. A `PowerMac3,5` owner with a stock Radeon
7500 or GeForce4 Ti still gets `autoexec-quicksilver.cfg`'s Radeon-9000-Pro
tuning regardless.

**Open**: if a second physical `PowerMac3,5` or `PowerMac3,1` with a
different factory card ever joins the fleet, or a user reports a specific
symptom traceable to this, that is the hardware this needs to actually fix
it - see issue #33.
