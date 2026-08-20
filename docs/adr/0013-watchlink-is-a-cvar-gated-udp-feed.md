# 13. watchlink is a cvar-gated UDP feed: inert by default

Date: 2026-08-20
Status: accepted

## Context

The QuakeSpasm and Quake II sister ports each carry a `cl_watchlink.c` that
pushes live player state to an external companion - an Apple Watch "tactical
computer" - so a second screen can show health, armour, ammo, weapon, score and
powerups. Quake III should drive the same companion.

Anything added to the client frame loop runs on a 449 MHz G3, and the PowerPC
fleet is big-endian.

## Decision

**`code/client/cl_watchlink.c` emits newline-delimited JSON over UDP, on its own
non-blocking socket, and is completely inert unless the `watch_host` cvar is
set.**

- **Same wire format, same UDP port (27999) and same Bonjour service
  (`_q2watch._udp`) as the Quake 1 and Quake II ports**, so one unchanged
  iPhone / Apple Watch companion drives all three games. The feed tags itself
  `"game":"q3"` so the app can adapt. Like Quake 1, Quake III has no F1 help
  computer or inventory pack, so the companion shows a cut-down HUD: vitals and
  score, no objectives or inventory panels.
- Three message kinds: `{"t":"vitals"}` at `watch_rate` Hz, `{"t":"meta"}` once
  per map load (level name plus weapon table), `{"t":"event","kind":...}` for
  damage and centerprint as they happen.
- **JSON, not a binary struct.** The retro fleet is big-endian, so a hand-rolled
  struct would invite byte-order bugs; JSON via `Com_sprintf` is endianness-proof
  and debuggable with `nc -ul 27999`.
- **Its own socket**, not the engine's net layer, so it never touches connection
  state or the loopback-only single-player socket. Sends are fire-and-forget on a
  non-blocking socket, so an unreachable `watch_host` never stalls the frame.
- **Runtime-gated opt-in, not a load-time change.** With `watch_host` empty: no
  sockets touched, no per-frame work, no packets. The default fleet build behaves
  exactly as before. Enable with `seta watch_host "auto"`, or an `ip` / `ip:port`.
- **Zero-config discovery is macOS only** and compiled out elsewhere: `"auto"`
  browses Bonjour through libSystem/mDNSResponder, present on every OS the fleet
  targets, 10.3 through Lion.

**Three SDK drifts are papered over so one source file compiles for every
slice** (g3 10.3.9, g4, lion):

- `DNSSD_API` and `kDNSServiceInterfaceIndexAny` first appear in the 10.4u SDK;
  the 10.3.9 headers lack both, so a no-op / zero fallback is supplied.
- `DNSServiceGetAddrInfo` (explicit A-record lookup) is 10.5+; on 10.3 and 10.4
  the resolver's `hosttarget` is handed to `getaddrinfo` instead.
- The `DNSServiceResolveReply` `txtRecord` argument is `const char *` through
  10.4u and `const unsigned char *` from 10.5 on; each is matched exactly.

## Alternatives rejected

**A binary struct over UDP.** Byte-order bugs across a big-endian client and a
little-endian phone, for no measurable saving on a feed this small.

**Reuse the engine's net layer.** It would put the feature inside connection
state that must keep working when the companion is absent.

**A separate Quake III wire format.** Three ports would then need three
companions.

## Consequences

**Gained**

- One companion app across three engines, with no cost to a build that never
  sets `watch_host`.

**Lost**

- ~960 lines of client code, plus Bonjour header shims, carried for an optional
  feature.

**Not measured**

- The frame cost when the feed *is* enabled has no bench row here. Treat any
  claim about it as INFERRED until one exists.
