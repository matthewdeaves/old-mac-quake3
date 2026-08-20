# 3. Every PowerPC slice is re-stamped after link and asserted with lipo

Date: 2026-08-20
Status: accepted

## Context

`-arch ppc7400 -mcpu=7400` is on the command line, so the binary must be stamped
`ppc7400`. It is not.

Two things defeat the stamp:

- **`-faltivec` silently un-stamps the cpusubtype**, and it is mandatory on the
  g4 slice (ADR 0002), so that slice loses its stamp on *every* build.
- Apple's `ld` stamps a generic `ppc` (subtype 0) anyway when the crt and
  `libSDLmain` objects are generic, which the bundled ones are.

A generic `ppc` member is not cosmetic. It matches **every** PowerPC host, so it
shadows the correct slice in the fat binary and a G3 is handed the AltiVec
build - an illegal instruction on a 750. The two PowerPC slices also collide
outright in `lipo` if both are generic.

Upstream's `Makefile` hardcoded `-arch ppc -faltivec -mmacosx-version-min=10.2`
for darwin, which is wrong for this port twice over: `-arch ppc` stamps the
generic subtype, and `-faltivec` emits AltiVec for the G3.

## Decision

**Remove the Makefile's hardcoded ppc flags, re-stamp the Mach-O cpusubtype
post-link, then assert the stamp with `lipo` and fail the build on a mismatch.**

- `scripts/build.sh` supplies arch, AltiVec and version-min per target through
  `CFLAGS` instead (ADR 0002).
- The cpusubtype is the 4-byte big-endian field at offset 8 of a thin Mach-O
  header; only the low byte, at offset 11, is non-zero for these values.
  `ppc750` = 9, `ppc7400` = 10. `x86_64` needs no fixup.
- `build.sh`, `build-gamedylibs.sh` and `build-fat.sh` each re-stamp and then
  verify, and exit non-zero on a mismatch (`build.sh:116-135`).
- **Verify with `lipo`, never `file`.** `file` reports subtype 9 as `ppc_650` on
  a modern host.
- The build scripts also clear prior artifacts, so a failed fetch cannot ship a
  stale binary.

## Alternatives rejected

**Trust the compiler.** The whole point: the stamp is wrong on a slice that
cannot be booted where it is built, and nothing else in the pipeline notices.

**Drop `-faltivec` to keep the stamp.** It is required for AltiVec codegen and
for Apple's context-sensitive `vector` keyword against the 10.3.9 SDK.

**Sanity-check by eye after a build.** Kept as a habit (`file build/ioquake3-g3`
should say `ppc750`, `-g4` `ppc7400`, `-lion` `x86_64`) but it is not the guard;
the assertion in the script is.

## Consequences

**Gained**

- A build that would hand a G3 an AltiVec binary now fails instead of shipping.

**Lost**

- The build depends on a byte-level Mach-O edit, so a future toolchain that
  changes header layout would need the offset revisited.

**Related hazard**

- **Never run g3 and g4 builds in parallel from one shell.** Both are
  `ARCH=ppc`, share the remote tree and race `.o` files into a wrong-subtype
  binary. `build.sh` takes `flock build/.build.lock`; `build-fat.sh` sequences
  the three slices. Serialize by hand if you bypass either.
