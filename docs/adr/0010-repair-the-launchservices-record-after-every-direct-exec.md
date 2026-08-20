# 10. Repair the LaunchServices record after every direct exec of the bundle

Date: 2026-08-20
Status: accepted

## Context

Reported from hardware: double-clicking `ioquake3` on `mini-intel` (Lion 10.7.5)
gave *"damaged or incomplete"*, from the Dock and from the folder. The same
build launched fine on the G3 under Panther.

Nothing was wrong with the build. The deployed fat binary was byte-identical to
`build/ioquake3-fat` (md5 `4e716b6d...`), `lipo` listed all three slices, the
bundle was complete, the Finder bundle bit was set, and there was no quarantine
xattr anywhere. `smoke-dmg.sh mini-intel` passed on the production path: 1260
frames, 40.3 fps at 1920x1080.

**The fault was in Lion's LaunchServices database.** Against a known-good sister
app on the same machine:

```
Desktop/quake/Quakespasm.app   executable: Contents/MacOS/quakespasm
Desktop/quake3/ioquake3.app    executable:                            <- blank
                               exec inode: 1511892                    <- correct
```

LS had the executable's inode but had lost its *path*, so it could not launch
the bundle. `lsregister -f <app>` repopulates it immediately.

**The first fix was in the wrong place, because the first diagnosis was wrong.**
`deploy.sh` rsyncs `Contents/MacOS/ioquake3` in place inside a bundle LS is
already watching, so a half-written record looked like a deploy artefact.
`deploy.sh` was taught to re-register, verified green, and pushed. Then the
actual cause was measured:

```
after deploy.sh (with the fix)   executable: Contents/MacOS/ioquake3
after ONE smoke-dmg.sh run       executable:                          <- blank again
```

**Our own bench tooling breaks it.** `safebench.sh`, `screenshot.sh` and
`smoke-dmg.sh` launch `ioquake3.app/Contents/MacOS/ioquake3` directly over ssh -
they have to, because the bench needs one ssh session that outlives the app
(ADR 0009). Deploy then bench is the normal order, so re-registering only at
deploy time fixed nothing: the very next bench re-broke it.

**The exact trigger, measured 2026-07-27, and narrower than "direct exec".** A
single-variable run settles it:

```
smoke run, native game dylibs (vm_* 0)   reg date CHANGED,   executable: BLANK
smoke run, QVM path           (vm_* 1)   reg date UNCHANGED, executable: intact
```

Same binary, same bundle, same direct-exec launch, same `libSDL-1.2.0.dylib`
loaded out of `Contents/MacOS/`. The only difference is whether the engine
`dlopen`s a game module from **inside** the `.app`
(`Contents/MacOS/baseq3/{cgame,qagame,ui}*.dylib`, via `Sys_LoadLibrary` ->
`dlopen`, `code/sys/sys_loadlib.h:32`).

**So the trigger is `dlopen()` of a file inside the `.app`, in a process
LaunchServices did not launch.** LS registers the bundle off the live process,
and since the launch did not come from LS the record gets an empty `executable:`.

Load-time linkage does **not** do it: `libSDL-1.2.0.dylib` lives in the same
bundle, is resolved by dyld at launch through `@executable_path`, and the QVM run
above loaded it without provoking LS.

That also explains why `bench.sh` is innocent: it runs the loose `./ioquake3`
with no enclosing bundle, *and* passes `com_archAutoexec 0`, so the arch cfg that
sets `vm_* 0` never runs and no bundle module is ever `dlopen`d.

**The sister ports were checked and are safe for three different reasons**
(measured on mini-intel 2026-07-27, both records untouched by a smoke run):
QuakeSpasm ships nine dylibs in its bundle but **load-time links** all of them
and never calls `dlopen`; Quake II **does** call `dlopen`, but its `ref_gl.so`
and `baseq2/game.so` live in the deploy root, **outside** `Quake2.app`. Either
would become exposed by a change that sounds like tidying up - moving the codecs
to runtime loading, or making the `.app` self-contained by pulling the game
modules inside it. That is precisely what this port did (ADR 0008).

## Decision

**`scripts/lsregister-app.sh <machine>` repairs the record, and every script that
direct-execs the engine calls it on its way out.**

- It locates `lsregister` at both paths - it moved into `CoreServices.framework`
  at 10.5; Panther and Tiger keep it under `ApplicationServices.framework` - and
  runs `lsregister -f`.
- It then **asserts** that the `executable:` field came back non-empty rather
  than trusting `lsregister -f`'s exit code.
- It is **non-fatal by contract**: launch polish must never fail a bench. It
  reports OK, BLANK, NOAPP, NOTOOL or unreachable and returns success.
- `bench.sh` calls it too, even though it cannot cause the fault, because one
  ssh is cheap and the call keeps working if either of those two facts changes.
- Panther and Tiger have not been seen doing this, so the PowerPC fleet kept
  working and hid it further.

## Alternatives rejected

**Re-register at deploy time only.** Verified green and still worthless: the next
bench re-breaks it.

**Move the game dylibs outside the bundle**, as Quake II does. It would remove
the fault, at the cost of putting our files in the user's data directory
(ADR 0008, ADR 0011).

**Stop direct-exec'ing the engine.** The bench needs one ssh session that
outlives the app (ADR 0009); going through LaunchServices is what the harness
cannot do.

## Consequences

**Gained**

- The app opens by double-click after any bench round.

**Lessons that generalise**

- **"The binary runs" and "the app opens" are different claims**, and this
  project's entire test suite only ever proved the first. When every automated
  check is green and the user still cannot launch the thing, suspect the layer
  the harness bypasses for convenience - here, launching it the way a human
  does.
- **A fix that makes the symptom go away is not evidence you found the cause.**
  The cheap test that would have caught this immediately, and that was skipped
  in favour of a plausible story about rsync: break it, apply the fix, then run
  the rest of the pipeline and look again.
