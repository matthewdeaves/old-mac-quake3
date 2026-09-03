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
