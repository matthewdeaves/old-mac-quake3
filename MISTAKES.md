# MISTAKES — ioquake3 old-Mac port

Append-only log of approaches that broke or would have broken. **Read before
lighting up an idea that smells "easy", "modern is better", or "load-time /
zero risk".** Mirrors `~/quakespasm/MISTAKES.md`.

---

## Modern ioquake3 (SDL2 / CMake) cannot run on the PPC fleet — caught at planning

**The smell:** "Just clone ioquake3 HEAD, it's the most maintained — newer is
better." Pinned HEAD (and then the last-Makefile commit) before checking the
runtime envelope.

**Why it breaks:** upstream ioquake3 switched to **CMake + SDL2**, and its PPC
build targets the **10.5 SDK** (`make-macosx.sh`: *"For PPC macs, G4's or
better are required"*). **SDL2 has never supported macOS 10.3 / 10.4.** The
PPC fleet runs Panther 10.3.9 (yosemite) and Tiger 10.4.11 (the G4s) — **none
run 10.5** — so a modern binary won't launch on any PPC bench machine. The G4
machines being on Tiger (not Leopard) means even "G4-only" modern builds are
out; the blocker is the OS/SDL pairing, not just the chip.

**The fix:** baseline pinned to the **last SDL 1.2 commit** `4432a80a`
(2013-01-17), branch `oldmac-base`, right before `f478761e "Use SDL 2 instead
of SDL 1.2"`. SDL 1.2 supports Panther/Tiger and is the same family
QuakeSpasm uses. `main` keeps HEAD for reference only. See `CLAUDE.md`
"THE load-bearing constraint".

**Lesson:** for this fleet, "best port" is decided by the **OS + SDL + GPU**
envelope of the *oldest* target, not by upstream activity. Check what will
actually launch on Panther before picking a baseline.

---

## (Open risk, not yet a mistake) Q3A on the 449 MHz G3 may be below playable

Quake III is much heavier than Quake 1, and yosemite (G3 449 MHz, Rage 128
16 MB) is at the 1999 minimum-spec edge. The ≥ 20 fps G3 floor is
**aspirational** — prove it by bench before committing visual work to that
slice. If it can't clear the floor even at `r_picmip 3` / low detail, gate G3
out (compile-time or per-machine) rather than dragging the matrix down.
