# Release process

The gate is `scripts/release-check.sh`. It refuses to pass until a human has
confirmed the one thing that cannot be automated here.

```sh
scripts/release-check.sh v0.6.2 mini-g4 yosemite mini-intel
```

## Why there is a manual step

Nothing in this repo opens the app the way a person does. `bench.sh` runs the
loose Mach-O; `safebench.sh`, `screenshot.sh` and `smoke-dmg.sh` all exec
`ioquake3.app/Contents/MacOS/ioquake3` directly over ssh. They have to: a bench
needs one ssh session that outlives the app, and `open <app>` over ssh loses the
WindowServer session and dies instantly with `CFMessagePortCreateLocal failed`.

So every automated check bypasses LaunchServices, and the pipeline is
structurally blind to "the app will not open". On 2026-07-26 it was worse than
blind: `smoke-dmg.sh` reported PASS at 40.3 fps on a build that could not be
double-clicked at all, because direct-exec benching is itself what corrupts the
LaunchServices record. `scripts/lsregister-app.sh` now repairs and asserts that
record after every direct-exec run, which closes that hole but not the general
one.

## Order

1. **Build.** `scripts/build.sh` per slice on a claimed Lion mini,
   `scripts/build-arm64.sh` on an Apple Silicon box, then `build-fat.sh`.
2. **Deploy and smoke** at least one machine per slice: a G3, a G4 or G5, a
   Lion Intel box. `scripts/deploy-dmg.sh`, `scripts/smoke-dmg.sh`.
3. **Package.** `scripts/make-dmg.sh <version>` on a Tiger G4, never elsewhere.
   ADR 0005.
4. **Gate.** `scripts/release-check.sh <version> <machines...>`, interactively.
5. **Screenshots**, if the renderer changed: `scripts/screenshot.sh`.
6. **Tag and publish.** Only the newest release is kept on GitHub.

## What the gate checks

| # | Check | Automated |
|---|---|---|
| 1 | the disk image exists | yes |
| 2 | every slice present, no generic `ppc` member | yes |
| 3 | no debug readouts left on in any shipped config | yes |
| 4a | each machine has the expected version installed | yes |
| 4b | no loose `ioquake3` beside the bundle | yes |
| 4c | LaunchServices record resolves to an executable | yes |
| 5 | **the app opens by double-click, and a new game starts** | no, you |

Step 5 is a new game, not a demo. A demo does not exercise the local server and
entity spawn path.

`RELEASE_CHECK_ASSUME_CLICKED=1` skips the prompt for a re-run in the same
session after the click test has genuinely been done. It is deliberately ugly to
type. Do not put it in a script: the whole point is that somebody looked.

## Related

- ADR [0005](adr/0005-package-the-disk-image-on-a-tiger-g4.md), packaging
- ADR [0009](adr/0009-bench-in-one-ssh-session-at-native-res-and-let-the-engine-quit-itself.md),
  the hardware hazards a fullscreen bench can cause
- ADR [0010](adr/0010-repair-the-launchservices-record-after-every-direct-exec.md),
  the LaunchServices repair
- [`../MISTAKES.md`](../MISTAKES.md), 2026-07-26
