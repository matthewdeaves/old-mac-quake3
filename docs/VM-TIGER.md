# Tiger QEMU playback and capture

> **Summary.** How to capture and judge frames from the emulated G4 + Radeon 9700 Tiger VM (`qemu-tiger3d`): `scripts/screenshot.sh`, playback pacing, and what a VM run can and cannot prove. Builds and VM tooling belong to `old-mac-build-host` (`docs/qemu-vm.md` there).
> Sections: Capture, Playback pacing, Validation limits.

Builds, deployments and shared VM tooling are owned by `old-mac-build-host`.
The installed game lives in `/Applications/Quake3` in `qemu-tiger3d`.

## Capture

```sh
scripts/screenshot.sh qemu-tiger3d four 8
```

This claims the VM, refuses an overlapping game, plays demo `four` at 1024x768,
and saves QEMU framebuffer PNGs under
`~/oldmac/evidence/quake3/screenshots-<UTC>/` on the workstation. It keeps the
Tiger SSH GUI session connected until the demo requests a normal engine exit.
The run uses an isolated temporary config home and leaves the installed user
config alone. `SCREENSHOT_DIR` overrides the local destination.

Guest screenshot readback is unreliable on the emulated Radeon (qemu#7/#8).
Host framebuffer capture avoids that path. Do not terminate a fullscreen
renderer with TERM/KILL as a routine capture cleanup.

## Playback pacing

The deployment hook identifies the QEMU display in the device tree and writes
a VM-only installed `autoexec-sawtooth-darwin8.cfg` with `com_maxfps 60`.
This avoids rendering unnecessary frames in light scenes while the host also
services emulated audio. Timedemo bypasses the play cap. The hook does not apply
to physical Macs and does not disable graphics effects or texture compression.

## Validation limits

The 2026-09-27 investigation reproduced RGB texture corruption and swapped
colour channels in QEMU's compressed texture path. Fixes are tracked in
matthewdeaves/qemu#12. The later turquoise lighting fault was a depth-clear overrun, fixed by
`bee98d449e`: an earlier draw's 769-row bound was incorrectly reused to clear
a 768-row buffer, overwriting the adjacent lightmap. Repeated compressed
demo launches passed after the fix. Neither a passing FPS run nor one clean
picture establishes that every rendering path is correct. Audio improved in user testing but
occasional glitches remain. Frozen-demo diagnostic runs can display
`Connection Interrupted`; use normal continuous gameplay for playback checks.

Follow-ups: qemu#13 tracks occasional audio glitches; qemu#14 tracks the
brightness difference from native rendering. Three final evidence runs
matched the installed v0.6.20 release binary and requested 1024x768 fullscreen
settings, measuring 84.9, 67.0 and 87.7 fps. A concurrent VM claimant was
discovered afterward, so these are informal measurements, not a controlled
performance comparison. Reacquire exclusive ownership before further benches.
