# Quake III Arena dedicated server, Linux

A headless Quake III server built from the same ioquake3 tree as the Mac fat
binary. One ELF binary, no packages to install.

## What is in the tarball

```
ioq3ded                      the server
server.cfg                   configuration, goes in baseq3/
systemd/ioq3ded.service
BUILD-INFO.txt               what this was built from
```

No game data. Quake III's content is id Software's and is not ours to ship.
You supply the pak files from your own copy.

There is no separate game library, unlike Quake II. Quake III's game logic is
QVM bytecode inside id's pak files, and bytecode is CPU independent, so the
server runs the same `qagame.qvm` the clients do.

## Requirements

Any Linux with glibc 2.31 or newer, so Ubuntu 20.04 and up, Debian 11 and up.
The only shared libraries loaded are part of glibc.

## Install

```sh
sudo useradd --system --home /opt/quake3-server --shell /usr/sbin/nologin quake3
sudo mkdir -p /opt/quake3-server/baseq3 /opt/quake3-server/home
sudo tar xzf quake3-server-*-linux-x86_64.tar.gz --strip-components=1 \
     -C /opt/quake3-server
sudo cp /opt/quake3-server/server.cfg /opt/quake3-server/baseq3/server.cfg

# your own copy of the game: pak0.pk3 through pak8.pk3
sudo cp pak*.pk3 /opt/quake3-server/baseq3/

sudo chown -R quake3:quake3 /opt/quake3-server
sudo cp /opt/quake3-server/systemd/ioq3ded.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ioq3ded
```

Two things that bite here:

**All nine paks, not just pak0.** Without `pak1.pk3` through `pak8.pk3` the
server refuses to start with "Point Release files are missing", which reads
like a corrupt install rather than an incomplete one.

**Lower case filenames.** Linux is case sensitive and macOS usually is not, so
a `PAK0.PK3` copied off a Mac is simply not found. Rename them:

```sh
cd /opt/quake3-server/baseq3 && for f in *.PK3; do mv "$f" "${f%.PK3}.pk3"; done
```

`server.cfg` has to be in `baseq3/`, not next to `ioq3ded`, for the same
reason: `exec` searches the game directory and says nothing when it finds
nothing.

Set `g_password` and `rconPassword` in `server.cfg` before exposing the port.

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

The rcon password crosses the network in the clear. Long, random, used nowhere
else.

**From the server**, through the FIFO the systemd unit sets up:

```sh
echo "map q3dm17" | sudo tee /run/quake3-server/console
echo "status"     | sudo tee /run/quake3-server/console
journalctl -u ioq3ded -f
```

Rotation is handled in `server.cfg` by chaining `vstr` configs, which is the
standard Quake III idiom because there is no maplist cvar.

## Bots

Worth remembering on a server that mostly has two people on it. Quake III
ships bots, they are enabled in `server.cfg`, and you can add them live:

```
rcon addbot sarge 4
rcon addbot xaero 5
```

## The network side

Default port is UDP 27960.

```sh
sudo ufw allow from <their.ip.here> to any port 27960 proto udp
sudo ufw allow from <your.ip.here>  to any port 27960 proto udp
```

The server is not advertised. `dedicated 1` in the unit means it accepts
connections from anywhere but sends no heartbeats, so it appears in no public
browser, and the five `sv_master` entries are blanked as well. Setting
`dedicated 2` is what would list it.

One oddity to expect: the first connection from an internet address may pause
up to five seconds. Quake III sends non-LAN clients to id's authorize server
to check their CD key, and that server has been gone for years. The engine
copes on its own, with the upstream comment "we couldn't contact the auth
server, let them in", so the connection completes once the lookup fails or
`AUTHORIZE_TIMEOUT` (5 seconds, `code/server/server.h`) expires. It is a pause
on first connect, not a failure, and it does not repeat.

There is no way to turn it off with official paks. `com_standalone` is
`CVAR_ROM` and the engine sets it from the pak checksums, so passing
`+set com_standalone 1` on the command line does nothing.

## Connecting

From the Mac client, by address or by name:

```
connect quake3.example.com
connect quake3.example.com:27960
connect 203.0.113.10
```

A hostname works everywhere: the engine resolves through `getaddrinfo`, so it
behaves the same on Panther as on macOS 26. Point an A record at the box and
that name is all either of you ever needs to type. If you run more than one
game on the same machine they can all share one name, because they differ by
port, and each engine has its own default so usually you type no port at all.

Worth binding it on the client so nobody has to remember anything:

```
bind F9 "connect quake3.example.com"
```

If `g_password` is set, `set password "..."` on the client first.

## Building it yourself

```sh
scripts/build-server-linux.sh                 # x86_64
scripts/build-server-linux.sh --arch aarch64  # ARM VPS
```

Needs Docker or Colima and nothing else. The build runs in a Debian 11
container so the result depends on glibc 2.31 rather than on whatever the
build machine happens to have.
