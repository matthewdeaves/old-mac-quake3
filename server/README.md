# Quake III Arena dedicated server: Linux

A headless Quake III server built from the same ioquake3 tree as the Mac fat
binary. One ELF binary, no packages to install. Why it is built this way, and
the measured amplification and hardening trade-offs, are in
[`../docs/adr/0012`](../docs/adr/0012-the-linux-dedicated-server-is-one-container-built-elf.md).

## What is in the tarball

```
ioq3ded                      the server
baseq3/server.cfg            configuration, already in the game directory
home/baseq3/                 empty, this is fs_homepath
systemd/ioq3ded.service
BUILD-INFO.txt               what this was built from
```

Both directories are laid out so the tarball works unpacked as it is. `baseq3/`
is where the engine looks for `server.cfg`, and `home/` is `fs_homepath`, which
has to exist before systemd can start the unit at all.

No game data. Quake III's content is id Software's and is not ours to ship. You
supply the pak files from your own copy. There is no separate game library,
unlike Quake II: Quake III's game logic is QVM bytecode inside id's pak files
and bytecode is CPU independent, so the server runs the same `qagame.qvm` the
clients do.

## Requirements

Any Linux with glibc 2.31 or newer, so Ubuntu 20.04 and up, Debian 11 and up.
The only shared libraries loaded are part of glibc.

## Install

```sh
sudo useradd --system --home /opt/quake3-server --shell /usr/sbin/nologin quake3
sudo mkdir -p /opt/quake3-server
sudo tar xzf quake3-server-*-linux-x86_64.tar.gz --strip-components=1 \
     -C /opt/quake3-server

# your own copy of the game: pak0.pk3 through pak8.pk3
sudo cp pak*.pk3 /opt/quake3-server/baseq3/

sudo chown -R quake3:quake3 /opt/quake3-server
sudo cp /opt/quake3-server/systemd/ioq3ded.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ioq3ded
```

Three things bite here:

**All nine paks, not just pak0.** Without `pak1.pk3` through `pak8.pk3` the
server refuses to start with "Point Release files are missing", which reads like
a corrupt install rather than an incomplete one.

**Lower case filenames.** Linux is case sensitive and macOS usually is not, so a
`PAK0.PK3` copied off a Mac is simply not found. Rename them:

```sh
cd /opt/quake3-server/baseq3 && for f in *.PK3; do mv "$f" "${f%.PK3}.pk3"; done
```

**`server.cfg` has to be in `baseq3/`**, not next to `ioq3ded`: `exec` searches
the game directory and says nothing when it finds nothing. The tarball ships it
in the right place, so this only matters if you move it. The symptom of getting
it wrong is one `couldn't exec server.cfg` line in the journal and a server
running on defaults, which otherwise looks completely healthy.

Set `g_password` and `rconPassword` in `server.cfg` before exposing the port.

## Upgrading

Unpacking a newer tarball over an existing install **overwrites
`baseq3/server.cfg`**, because that is where the tarball now carries it. Keep
your own copy first:

```sh
sudo cp /opt/quake3-server/baseq3/server.cfg /opt/quake3-server/server.cfg.mine
```

Your pak files are untouched: the tarball contains no game content.

## Server identity

`sv_hostname`, `g_motd` and `g_password` in `server.cfg`, or live over rcon -
all three take effect immediately, no `map_restart` needed.

**`g_motd`** shows on a connecting player's loading/info screen and as the
scoreboard title (`code/cgame/cg_info.c`, `cg_scoreboard.c`). Blank by
default.

**`g_password`** - a joining player must supply this to connect (checked in
`code/game/g_client.c`). Existing connections are unaffected by a live
change; only new joins are checked. Reserved slots
(`sv_privateClients`/`sv_privatePassword`, above) bypass it.

**`g_needpass`** is NOT something you set - it is a read-only status cvar
(`CVAR_ROM`) the game code derives automatically from whether `g_password` is
currently blank or not (`code/game/g_main.c`), and it is what the server
browser / client connect screen actually reads to show "requires password".
Setting it directly does nothing; set `g_password` instead and this follows.

```
rcon set sv_hostname "New name"
rcon set g_motd "Reset Friday 20:00 UTC"
rcon set g_password "letmein"     # or "" to remove it
```

## Changing the map

**From inside the game**, if `rconPassword` is set. On any client:

```
rconpassword "your-password"
rcon map q3dm17
rcon status
rcon addbot sarge 3
```

Bind it to a key and changing map on a G4 is one keypress:

```
bind F6 "rcon map q3dm17"
```

**The rcon password crosses the network in the clear. Long, random, used
nowhere else.**

**From the server**, through the FIFO the systemd unit sets up:

```sh
echo "map q3dm17" | sudo tee /run/quake3-server/console
echo "status"     | sudo tee /run/quake3-server/console
journalctl -u ioq3ded -f
```

Rotation is handled in `server.cfg` by chaining `vstr` configs, the standard
Quake III idiom because there is no maplist cvar.

## IP bans

Persistent, survive a restart, by IP/CIDR - not tied to a player name or
Quake III account (there is no such thing on a standalone server, see the
warning below). Backed by `sv_banFile` (`code/server/sv_ccmds.c`), default
`serverbans.dat`, written to `baseq3/` next to `server.cfg` - same directory
gotcha as everything else in "Install" above. Every add/remove writes the
file immediately; nothing here needs an explicit save.

```
rcon banaddr 203.0.113.10          # ban one address
rcon banaddr 203.0.113.0/24        # ban a subnet (CIDR)
rcon banaddr 3                     # ban by client slot instead of address -
                                    # resolves to that client's current IP
rcon listbans                      # numbered list: Ban #1, Ban #2, Except #1 ...
rcon bandel 2                      # delete by the number listbans showed you
rcon bandel 203.0.113.10           # or delete by address directly
rcon exceptaddr 203.0.113.10       # allowlist one address - wins over a
                                    # broader ban that would otherwise match
rcon exceptdel 1
rcon flushbans                     # remove every ban AND exception
rcon rehashbans                    # reload from serverbans.dat on disk,
                                    # e.g. after hand-editing the file
```

`listbans`' numbering is per category (bans and exceptions numbered
separately, starting at 1 each) and `bandel`/`exceptdel` expect that same
per-category number - confirmed by reading `SV_DelBanFromList`, this is not
a raw array index. A number past the end of its own category (but within
the combined ban+exception count) is accepted with no error and silently
bans nothing - give it a number `listbans` actually showed you.

**Do not wire `banUser` or `banClient` into anything.** They exist
(`code/server/sv_ccmds.c`) but resolve and contact id Software's original
authorize server (`AUTHORIZE_SERVER_NAME`) to register the ban centrally -
that server has been dead for years, so calling either hangs or fails
outright. The names are easy to reach for by mistake: `kicknum` /
`clientkick` (`code/server/sv_ccmds.c`) are the ordinary ban-free "remove
this slot right now" commands, and `banaddr <clientnum>` (which resolves
their current IP) is the persistent-ban equivalent that actually works
standalone.

## Game types

Set with `g_gametype` in `server.cfg`, or live with `rcon set g_gametype <n>`
followed by `rcon map_restart` - a running match does not pick up a gametype
change until the map (re)loads.

| `g_gametype` | Name | Works on this server |
|---|---|---|
| 0 | Free For All | yes |
| 1 | Tournament | yes |
| 2 | Single Player | not for a dedicated server |
| 3 | Team Deathmatch | yes |
| 4 | Capture the Flag | yes |
| 5 | One Flag CTF | **partially - see below** |
| 6 | Overload | **no - see below** |
| 7 | Harvester | **no - see below** |

Values and names come straight from the engine
(`code/game/bg_public.h`'s `gametype_t` enum, `code/game/g_cmds.c`'s
`gameNames[]`), not guessed.

**5-7 are NOT safe to enable yet, and it is more than a missing-map problem.**
These three gametypes started in Quake III: Team Arena, a separate expansion.
Upstream ioquake3 keeps their actual game logic behind `#ifdef MISSIONPACK` in
`code/game/` - obelisk spawn/health/regen and the whole win condition for
Overload (`code/game/g_team.c`, one guarded block alone runs lines 1201-1492),
`TossClientCubes` for Harvester (`code/game/g_combat.c`), even the
`g_obeliskHealth`/`g_obeliskRegenPeriod`/`g_obeliskRegenAmount`/
`g_obeliskRespawnDelay`/`g_cubeTimeout` cvars themselves - the `vmCvar_t` and
the `cvarTable_t` entry that registers each one are both inside the same
`#ifdef` in `code/game/g_main.c`. This repo's baseq3 game module is built with
`BASEGAME_CFLAGS`, not `MISSIONPACK_CFLAGS` (`Makefile`'s `DO_GAME_CC`), and
ships `BUILD_MISSIONPACK=0` everywhere it sets it
(`scripts/build-gamedylibs.sh`, `scripts/build-gamedylibs-arm64.sh`,
`scripts/build-server-linux.sh`) - so none of that code is in the binary this
repo ships. Confirmed by reading the actual guarded ranges, not assumed from
upstream docs.

What that means running today: the gametype **selects and displays** cleanly
(menus, vote naming, the `CS_FLAGSTATUS` configstring plumbing for 1FCTF's
flag status at `g_team.c` line ~219, which is NOT guarded) but Overload has no
working obelisks at all, Harvester never drops cubes, and 1FCTF is missing at
least its team-item pickup validation (`code/game/bg_misc.c` lines 1128-1144).
Setting any of these on a live server produces a match that looks selectable
but plays broken, not a working mode waiting on the right map.

Making 5-7 real would mean building baseq3's game module with `-DMISSIONPACK`
defined, which is not just an Overload/Harvester switch - the same guard also
covers persistent powerups (Guard/Scout/Doubler/Ammo Regen), kamikaze, and
other Team Arena holdables throughout `g_combat.c`/`g_items.c`/`bg_misc.c`.
Untested here, real engineering work, and a genuine design question (does
turning all of that on for baseq3 have side effects worth living with) -
**not decided in this file.**

## Match flow and moderation

All plain `server.cfg` cvars or live over rcon, all unconditional
(`code/game/g_main.c`/`g_cmds.c`/`g_team.c`/`g_svcmds.c`, `code/server/
sv_ccmds.c` - none behind `#ifdef MISSIONPACK`, checked the same way as
"Game types" above).

**Warmup** - two separate cvars, not one:

```
set g_doWarmup 1    # 0/1, off by default: turns warmup on at all
set g_warmup 20      # seconds, only matters if g_doWarmup is 1
```

The countdown does not start the instant you set these - it starts once
enough players have actually joined (`code/game/g_main.c`), so "I turned it
on and nothing happened" usually means the server is still waiting on
players, not a broken setting.

**Team balance:**

```
set g_teamAutoJoin 0        # 1: auto-assign new players to a team instead
                             # of dropping them in as a spectator
set g_teamForceBalance 0    # 1: caps the team size spread at 2
```

**`forceteam <player> <red|blue|spectator|free>`** - admin override, over
rcon exactly like `addbot` (`code/game/g_svcmds.c`'s `ConsoleCommand`
dispatches both the same way). **Not actually an unconditional override**:
it calls the same `SetTeam()` a player's own team-change goes through
(`code/game/g_cmds.c`), so with `g_teamForceBalance 1` set, `forceteam` can
silently do nothing if the target team is already ahead by more than one
player - confirmed by reading `SetTeam`, there is no admin bypass of that
check. If a webadmin "force team" button needs to always work regardless of
balance, that is not available today without a source change.

```
rcon forceteam Sarge red
```

**Kick (no ban)** - `kicknum <slot>` / `clientkick <slot>` (`clientkick` is
the legacy name for the same command, `code/server/sv_ccmds.c`), immediate,
survives no restart, unrelated to the "IP bans" section above. `rcon status`
shows slot numbers.

```
rcon status
rcon kicknum 3
```

## Vote system

**`g_allowVote`** is real and works as a simple on/off gate:

```
set g_allowVote 0    # 1 (default): players can call votes. 0: they can't.
```

**Everything past that gate is not what it looks like from outside the
game, checked directly against the source rather than assumed:**

**There is no admin veto.** Searched for one - nothing. `g_allowVote` is
only checked when a vote is *called* (`Cmd_CallVote_f`,
`code/game/g_cmds.c`); the resolution logic that counts yes/no and passes
or fails a vote already in progress (`CheckVote`, `code/game/g_main.c`)
never checks it again. Setting `g_allowVote 0` mid-vote stops the *next*
vote from being called; it does not touch the one already running. There
is no other command, cvar, or code path anywhere in `code/game/` or
`code/server/` that cancels an in-progress vote early. The closest real
lever is `rcon map_restart`, which resets the whole match (`level.voteTime`
included) as a side effect - it works, but it is not a veto, it is
restarting the game to get one.

**Live vote state is not visible outside an actual connected game
client.** `CS_VOTE_TIME`/`CS_VOTE_STRING`/`CS_VOTE_YES`/`CS_VOTE_NO`
(`code/game/bg_public.h`) are real configstrings, set by `Cmd_CallVote_f`
and updated by `CheckVote`, but configstrings are part of the client-server
snapshot protocol - something that only exists once you are a connected
player in the match. `rcon status` shows none of it (checked
`SV_Status_f`, `code/server/sv_ccmds.c` - map name and per-client rows
only), and Quake III's out-of-band `getstatus`/`getinfo` server-browser
queries only return `CVAR_SERVERINFO`/`CVAR_SYSTEMINFO`-flagged cvars, not
level-local state like an in-progress vote. A webadmin panel that talks
rcon and OOB status queries (the pattern the rest of this doc uses) has no
way to read "is a vote happening right now, and what is the tally" - doing
that for real means implementing enough of the Q3 client protocol to join
as a spectator and parse configstrings, a materially bigger integration
than anything else in this file.

**What is actually buildable today**: an on/off `g_allowVote` toggle.
Nothing else in this section is - not decided here whether that alone is
worth a webadmin feature on its own.

## Bots

Worth remembering on a server that mostly has two people on it. Quake III ships
bots, they are enabled in `server.cfg`, and you can add them live:

```
rcon addbot sarge 4
rcon addbot xaero 5
```

## The network side

Default port is UDP 27960. The server is not advertised: `dedicated 1` accepts
connections from anywhere but sends no heartbeats, and the five `sv_master`
entries are blanked as well.

```sh
sudo ufw allow from <their.ip.here> to any port 27960 proto udp
sudo ufw allow from <your.ip.here>  to any port 27960 proto udp
```

**The per-source-address rules matter.** This server answers unauthenticated
status queries with up to 32x amplification. ioquake3's built-in rate limit caps
the throughput but does not remove the problem; an allowlist does, because a
spoofed packet claims to come from the victim and gets dropped. Numbers in
`../docs/adr/0012`.

Expect one oddity: **the first connection from an internet address may pause up
to five seconds**, while the engine gives up on id's long-dead authorize server.
It is a pause on first connect, not a failure, it does not repeat, and it cannot
be turned off with official paks. See `../docs/adr/0012`.

## Connecting

From the Mac client, by address or by name:

```
connect quake3.example.com
connect quake3.example.com:27960
connect 203.0.113.10
```

A hostname works everywhere: the engine resolves through `getaddrinfo`, so it
behaves the same on Panther as on macOS 26. Point an A record at the box and
that name is all either of you ever needs to type. Several games can share one
name because they differ by port, and each engine has its own default, so
usually you type no port at all.

```
bind F9 "connect quake3.example.com"
```

If `g_password` is set, `set password "..."` on the client first.

## Building it yourself

```sh
scripts/build-server-linux.sh                 # x86_64
scripts/build-server-linux.sh --arch aarch64  # ARM VPS
```

Needs Docker or Colima and nothing else. The build runs in a Debian 11 container
so the result depends on glibc 2.31 rather than on whatever the build machine
happens to have.
