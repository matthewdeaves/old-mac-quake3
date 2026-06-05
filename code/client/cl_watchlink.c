/*
 * Copyright (C) 2026 ioquake3 PPC/oldmac port
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * =======================================================================
 *
 * watchlink -- pushes the player's live in-game state out over UDP so an
 * external companion (an Apple Watch "tactical computer", or just `nc -ul`)
 * can render the player's health / armor / ammo / weapon / score / powerups
 * on a second screen.
 *
 * This is the Quake III Arena sibling of cl_watchlink.c in the Quake II and
 * QuakeSpasm (Quake 1) ports: it speaks the SAME newline-delimited JSON wire
 * format on the SAME UDP port (27999) and discovers the SAME Bonjour service
 * ("_q2watch._udp"), so one unchanged iPhone/Apple Watch companion drives all
 * three games. Like Quake 1, Quake III has no F1 help computer / inventory
 * pack, so the companion shows a cut-down HUD (vitals + score, no objectives
 * or inventory panels). The feed tags itself "game":"q3" so the app can adapt.
 *
 * Everything here is gated on the `watch_host` cvar: when it is empty the
 * feature is completely inert -- no sockets touched, no per-frame work, no
 * packets emitted -- so the default fleet build behaves exactly as before.
 * This is a runtime-gated opt-in, NOT a load-time change.
 *
 * Transport is newline-delimited JSON. The retro PPC fleet is big-endian, so
 * a hand-rolled binary struct would invite byte-order bugs; JSON via
 * Com_sprintf is endianness-proof and debuggable with `nc -ul 27999`:
 *
 *   {"t":"vitals", ...}        ~watch_rate Hz, the status bar
 *   {"t":"meta", ...}          once per map load: level name + weapon table
 *   {"t":"event","kind":...}   damage / centerprint, as they happen
 *
 * Sends go out on watchlink's OWN non-blocking UDP socket, fire-and-forget, so
 * an unreachable watch_host never stalls the frame.
 *
 * =======================================================================
 */

#include "client.h"

#include <string.h>
#include <stdlib.h>

/*
 * Portable, non-blocking outbound UDP. POSIX everywhere the fleet runs
 * (macOS PPC, Linux); Winsock for Windows builds. We open our own socket
 * rather than borrowing the engine's net layer so we never touch the engine's
 * connection state or its (in single player, loopback-only) socket.
 */
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET wl_socket_t;
#define WL_INVALID_SOCKET	INVALID_SOCKET
static int		wl_wsa_started;
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
typedef int		wl_socket_t;
#define WL_INVALID_SOCKET	(-1)
#define closesocket		close
#endif

/*
 * Zero-config discovery (macOS only). When watch_host is the literal "auto"
 * we browse Bonjour for the companion's "_q2watch._udp" service instead of
 * resolving a typed IP, so the phone never has to be addressed by hand. This
 * is libSystem/mDNSResponder, present on every Mac the fleet targets (Panther
 * 10.3 .. Leopard 10.5 .. Lion), and is compiled out everywhere else. The
 * service type is shared with the Quake I/II ports on purpose: one companion,
 * three games.
 *
 * The browse/resolve calls ship on all fleet OSes, but the SDK *headers*
 * drifted across versions, so we paper over the gaps to keep ONE source file
 * compiling for every slice (g3 10.3.9, g4 10.4u, lion):
 *   - DNSSD_API and kDNSServiceInterfaceIndexAny first appear in the 10.4u
 *     SDK; the 10.3.9 headers lack both. We supply a no-op / zero fallback.
 *   - DNSServiceGetAddrInfo (explicit A-record lookup) is 10.5+. On 10.3/10.4
 *     we fall back to handing the resolver's hosttarget to getaddrinfo.
 *   - The DNSServiceResolveReply txtRecord arg is `const char *` through 10.4u
 *     and `const unsigned char *` from 10.5 on; we match each exactly.
 */
#ifdef __APPLE__
#include <AvailabilityMacros.h>
#include <dns_sd.h>
#include <sys/select.h>
#define WATCHLINK_BONJOUR 1

#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED < 1040
#ifndef DNSSD_API
#define DNSSD_API
#endif
#define kDNSServiceInterfaceIndexAny 0
#endif

#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
#define WATCHLINK_HAVE_ADDRINFO 1
#define WATCHLINK_TXTREC const unsigned char
#else
#define WATCHLINK_TXTREC const char
#endif
#endif /* __APPLE__ */

static cvar_t	*watch_host;	/* "ip"/"ip:port", "auto", "" => off */
static cvar_t	*watch_port;	/* default port when host omits one */
static cvar_t	*watch_rate;	/* vitals heartbeat, Hz */
static cvar_t	*watch_events;	/* also emit damage/centerprint events */

static wl_socket_t	watch_sock = WL_INVALID_SOCKET;
static struct sockaddr_in watch_sin;	/* resolved companion destination */
static qboolean		watch_sin_valid;
static int		watch_sent_count;	/* packets since last (re)connect */

static double		watch_last_send;	/* seconds of last vitals heartbeat */
static char		watch_last_vitals[1024];/* last vitals payload (change-detect) */
static qboolean		watch_meta_pending;	/* meta queued; send once dest resolves */
static char		watch_lastmap[128];	/* detect map changes to re-arm + send meta */
static char		watch_last_cp[1024];	/* last centerprint forwarded (dedup re-fires) */
static int		watch_dmg_flash;	/* pending damage bits, mirrored into next vitals "flashes" */
static int		watch_prev_hp;		/* previous HP, for blood/armor bit + death edge */
static int		watch_prev_armor;	/* previous armor, for the armor damage bit */
static int		watch_prev_dmgevent;	/* previous ps.damageEvent, the real hit signal */
static int		watch_prev_weapons;	/* previous STAT_WEAPONS, for pickup detection */
static qboolean		watch_pu_active;	/* a powerup was active last heartbeat */
static double		watch_pain_at;		/* seconds of last pain psound (rate-limit) */
static qboolean		watch_have_prev;	/* watch_prev_* primed this map */

#ifdef WATCHLINK_BONJOUR
static DNSServiceRef	watch_browse_ref;
static DNSServiceRef	watch_resolve_ref;
static qboolean		watch_discovering;
static uint16_t		watch_disc_port;	/* service port (network byte order) */
static double		watch_disc_until;	/* seconds deadline to give up a fruitless browse */
#define WATCHLINK_DISCOVERY_SECS 30.0
#ifdef WATCHLINK_HAVE_ADDRINFO
static DNSServiceRef	watch_addr_ref;
#endif
#endif

/* Monotonic seconds, mirroring the Quake 1 port's `realtime`. ioquake3 keeps
   wall time as integer milliseconds in cls.realtime (advances even when the
   sim is paused), which is exactly what we want to throttle the heartbeat. */
static double
WatchLink_Now (void)
{
	return cls.realtime / 1000.0;
}

/* Quake III weapon index (playerState weapon) -> display name. */
static const char *
WatchLink_WeaponName (int w)
{
	switch (w)
	{
	case WP_GAUNTLET:		return "Gauntlet";
	case WP_MACHINEGUN:		return "Machinegun";
	case WP_SHOTGUN:		return "Shotgun";
	case WP_GRENADE_LAUNCHER:	return "Grenade Launcher";
	case WP_ROCKET_LAUNCHER:	return "Rocket Launcher";
	case WP_LIGHTNING:		return "Lightning Gun";
	case WP_RAILGUN:		return "Railgun";
	case WP_PLASMAGUN:		return "Plasma Gun";
	case WP_BFG:			return "BFG10K";
	case WP_GRAPPLING_HOOK:		return "Grappling Hook";
#ifdef MISSIONPACK
	case WP_NAILGUN:		return "Nailgun";
	case WP_PROX_LAUNCHER:		return "Prox Launcher";
	case WP_CHAINGUN:		return "Chaingun";
#endif
	default:			return "";
	}
}

/* Quake III powerups, in display priority. ps.powerups[pw] holds the server
   time (ms) the powerup runs out; the icon tokens match the companion's
   neutral powerup labels (quad/pent/envir/ring) where they line up, and fall
   through to an uppercased token (REGEN/HASTE/FLIGHT) for the rest. */
static const struct { int pw; const char *icon; } watch_powerups[] =
{
	{ PW_QUAD,		"quad"   },	/* QUAD DAMAGE   */
	{ PW_INVULNERABILITY,	"pent"   },	/* INVULNERABLE  */
	{ PW_BATTLESUIT,	"envir"  },	/* BATTLE SUIT   */
	{ PW_REGEN,		"regen"  },	/* REGENERATION  */
	{ PW_HASTE,		"haste"  },	/* HASTE         */
	{ PW_INVIS,		"invis"  },	/* INVISIBILITY  */
	{ PW_FLIGHT,		"flight" }	/* FLIGHT        */
};

/* Weapons the companion may want to list once per map (STAT_WEAPONS bitfield,
   one bit per weapon index). */
static const struct { int wp; const char *name; } watch_arsenal[] =
{
	{ WP_GAUNTLET,		"Gauntlet" },
	{ WP_MACHINEGUN,	"Machinegun" },
	{ WP_SHOTGUN,		"Shotgun" },
	{ WP_GRENADE_LAUNCHER,	"Grenade Launcher" },
	{ WP_ROCKET_LAUNCHER,	"Rocket Launcher" },
	{ WP_LIGHTNING,		"Lightning Gun" },
	{ WP_RAILGUN,		"Railgun" },
	{ WP_PLASMAGUN,		"Plasma Gun" },
	{ WP_BFG,		"BFG10K" }
};

static qboolean WatchLink_IsAuto (void);
static void WatchLink_Sync (void);

/*
 * Fill watch_sin from a host (numeric IPv4 or a name getaddrinfo can resolve)
 * and port. A name is resolved once, synchronously -- fine: it only happens on
 * (re)connect, and .local mDNS names resolve locally.
 */
static void
WatchLink_SetDest (const char *host, int port)
{
	struct addrinfo	hints, *res;

	watch_sin_valid = qfalse;

	if (!host || !host[0] || port <= 0 || port > 65535)
		return;

	memset (&watch_sin, 0, sizeof(watch_sin));
	watch_sin.sin_family = AF_INET;
	watch_sin.sin_port = htons ((unsigned short)port);

	if (inet_pton (AF_INET, host, &watch_sin.sin_addr) == 1)
	{
		watch_sin_valid = qtrue;
		return;
	}

	memset (&hints, 0, sizeof(hints));
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_DGRAM;
	res = NULL;
	if (getaddrinfo (host, NULL, &hints, &res) == 0 && res != NULL)
	{
		watch_sin.sin_addr = ((struct sockaddr_in *)res->ai_addr)->sin_addr;
		watch_sin_valid = qtrue;
	}
	if (res)
		freeaddrinfo (res);
}

/*
 * Resolve the watch_host cvar ("ip" or "ip:port") into watch_sin. When no port
 * is given, watch_port is appended. Called lazily whenever a destination is
 * needed so the user can retarget live from the console.
 */
static void
WatchLink_Resolve (void)
{
	char	buf[128];
	char	*colon;
	int	port;

	watch_sin_valid = qfalse;

	if (!watch_host->string[0])
		return;

	Q_strncpyz (buf, watch_host->string, sizeof(buf));
	colon = strrchr (buf, ':');
	if (colon)
	{
		*colon = '\0';
		port = atoi (colon + 1);
	}
	else
	{
		port = watch_port->integer;
	}

	WatchLink_SetDest (buf, port);
}

static qboolean
WatchLink_IsAuto (void)
{
	return (watch_host->string[0] && !Q_stricmp (watch_host->string, "auto")) ? qtrue : qfalse;
}

#ifdef WATCHLINK_BONJOUR
static void
WatchLink_StopDiscovery (void)
{
#ifdef WATCHLINK_HAVE_ADDRINFO
	if (watch_addr_ref) { DNSServiceRefDeallocate (watch_addr_ref); watch_addr_ref = NULL; }
#endif
	if (watch_resolve_ref) { DNSServiceRefDeallocate (watch_resolve_ref); watch_resolve_ref = NULL; }
	if (watch_browse_ref) { DNSServiceRefDeallocate (watch_browse_ref); watch_browse_ref = NULL; }
	watch_discovering = qfalse;
}

/* Adopt a discovered host:port as the live destination. */
static void
WatchLink_Discovered (const char *host, int port)
{
	qboolean had = watch_sin_valid;

	WatchLink_SetDest (host, port);
	if (watch_sin_valid && !had)
		Com_Printf ("watchlink: discovered companion at %s:%d\n", host, port);
}

#ifdef WATCHLINK_HAVE_ADDRINFO
/* Stage 3 (10.5+): the host's IPv4 address arrived -> build the destination. */
static void DNSSD_API
WatchLink_AddrReply (DNSServiceRef sdRef, DNSServiceFlags flags,
		uint32_t interfaceIndex, DNSServiceErrorType err,
		const char *hostname, const struct sockaddr *address,
		uint32_t ttl, void *context)
{
	const struct sockaddr_in *sin;
	char	ip[64];

	(void)sdRef; (void)flags; (void)interfaceIndex; (void)hostname;
	(void)ttl; (void)context;

	if (err != kDNSServiceErr_NoError || !address ||
			address->sa_family != AF_INET)
		return;

	sin = (const struct sockaddr_in *)address;
	if (!inet_ntop (AF_INET, &sin->sin_addr, ip, sizeof(ip)))
		return;

	WatchLink_Discovered (ip, (int)ntohs (watch_disc_port));
}
#endif /* WATCHLINK_HAVE_ADDRINFO */

/* Stage 2: a service instance resolved to host:port. On 10.5+ resolve its
   IPv4 explicitly; on older SDKs hand the hosttarget to getaddrinfo. */
static void DNSSD_API
WatchLink_ResolveReply (DNSServiceRef sdRef, DNSServiceFlags flags,
		uint32_t interfaceIndex, DNSServiceErrorType err,
		const char *fullname, const char *hosttarget, uint16_t port,
		uint16_t txtLen, WATCHLINK_TXTREC *txtRecord, void *context)
{
	(void)sdRef; (void)flags; (void)fullname;
	(void)txtLen; (void)txtRecord; (void)context;

	if (err != kDNSServiceErr_NoError)
		return;

	watch_disc_port = port; /* network byte order */

#ifdef WATCHLINK_HAVE_ADDRINFO
	if (watch_addr_ref)
	{
		DNSServiceRefDeallocate (watch_addr_ref);
		watch_addr_ref = NULL;
	}
	DNSServiceGetAddrInfo (&watch_addr_ref, 0, interfaceIndex,
			kDNSServiceProtocol_IPv4, hosttarget,
			WatchLink_AddrReply, NULL);
#else
	(void)interfaceIndex;
	WatchLink_Discovered (hosttarget, (int)ntohs (port));
#endif
}

/* Stage 1: a companion appeared on the LAN -> resolve it. */
static void DNSSD_API
WatchLink_BrowseReply (DNSServiceRef sdRef, DNSServiceFlags flags,
		uint32_t interfaceIndex, DNSServiceErrorType err,
		const char *serviceName, const char *regtype,
		const char *replyDomain, void *context)
{
	(void)sdRef; (void)context;

	if (err != kDNSServiceErr_NoError || !(flags & kDNSServiceFlagsAdd))
		return; /* ignore errors and "service went away" notifications */

	if (watch_resolve_ref)
	{
		DNSServiceRefDeallocate (watch_resolve_ref);
		watch_resolve_ref = NULL;
	}
	DNSServiceResolve (&watch_resolve_ref, 0, interfaceIndex,
			serviceName, regtype, replyDomain,
			WatchLink_ResolveReply, NULL);
}

static void
WatchLink_StartDiscovery (void)
{
	DNSServiceErrorType err;

	WatchLink_StopDiscovery ();

	err = DNSServiceBrowse (&watch_browse_ref, 0, kDNSServiceInterfaceIndexAny,
			"_q2watch._udp", NULL, WatchLink_BrowseReply, NULL);

	if (err != kDNSServiceErr_NoError)
	{
		Com_Printf ("watchlink: Bonjour browse failed (err %d); "
				"set watch_host to an IP instead\n", (int)err);
		watch_browse_ref = NULL;
		return;
	}

	watch_discovering = qtrue;
	watch_disc_until = WatchLink_Now () + WATCHLINK_DISCOVERY_SECS;
	Com_Printf ("watchlink: browsing for companion (_q2watch._udp)...\n");
}

/* Service one ready DNS-SD socket, without blocking the frame. */
static void
WatchLink_PumpRef (DNSServiceRef ref)
{
	int		fd;
	fd_set		set;
	struct timeval	tv;

	if (!ref)
		return;

	fd = DNSServiceRefSockFD (ref);
	if (fd < 0)
		return;

	FD_ZERO (&set);
	FD_SET (fd, &set);
	tv.tv_sec = 0;
	tv.tv_usec = 0;

	if (select (fd + 1, &set, NULL, NULL, &tv) > 0 && FD_ISSET (fd, &set))
		DNSServiceProcessResult (ref);
}

static void
WatchLink_PumpDiscovery (void)
{
	WatchLink_PumpRef (watch_browse_ref);
	WatchLink_PumpRef (watch_resolve_ref);
#ifdef WATCHLINK_HAVE_ADDRINFO
	WatchLink_PumpRef (watch_addr_ref);
#endif
}
#endif /* WATCHLINK_BONJOUR */

/*
 * Reconcile internal state with the watch_host cvar and, in "auto" mode, drive
 * Bonjour discovery. Cheap to call every frame; only does real work when the
 * cvar string changed or a discovery socket has data pending.
 */
static char watch_host_seen[128] = "\001"; /* sentinel: forces first reconcile */

static void
WatchLink_Sync (void)
{
	if (strcmp (watch_host->string, watch_host_seen) != 0)
	{
		Q_strncpyz (watch_host_seen, watch_host->string, sizeof(watch_host_seen));
		watch_sin_valid = qfalse;
#ifdef WATCHLINK_BONJOUR
		WatchLink_StopDiscovery ();
#endif
		if (WatchLink_IsAuto ())
		{
#ifdef WATCHLINK_BONJOUR
			WatchLink_StartDiscovery ();
#else
			Com_Printf ("watchlink: \"auto\" needs macOS Bonjour; "
					"set watch_host to an IP instead\n");
#endif
		}
	}

#ifdef WATCHLINK_BONJOUR
	if (watch_discovering)
	{
		WatchLink_PumpDiscovery ();

		/* Stop browsing once we have a destination, or after the window
		   elapses with no companion found -- a phoneless game then pays
		   nothing per frame. Re-armed on the next map load. */
		if (watch_sin_valid)
		{
			WatchLink_StopDiscovery ();
		}
		else if (WatchLink_Now () > watch_disc_until)
		{
			WatchLink_StopDiscovery ();
			Com_Printf ("watchlink: no companion found; idling "
					"(load a map to retry)\n");
		}
	}
#endif
}

/*
 * True when the feature is armed and a destination is known. A typed IP is
 * resolved here lazily; in "auto" mode the address is supplied asynchronously
 * by Bonjour discovery (WatchLink_Sync).
 */
static qboolean
WatchLink_DestReady (void)
{
	if (!watch_host->string[0])
		return qfalse;

	if (!watch_sin_valid && !WatchLink_IsAuto ())
		WatchLink_Resolve ();

	return watch_sin_valid;
}

static void
WatchLink_Send (const char *line)
{
	int	len = (int)strlen (line);

	if (len <= 0 || !watch_sin_valid)
		return;

	if (watch_sock == WL_INVALID_SOCKET)
	{
#ifdef _WIN32
		if (!wl_wsa_started)
		{
			WSADATA wsa;
			if (WSAStartup (MAKEWORD(2,2), &wsa) == 0)
				wl_wsa_started = 1;
		}
#endif
		watch_sock = socket (AF_INET, SOCK_DGRAM, 0);
		if (watch_sock != WL_INVALID_SOCKET)
		{
#ifdef _WIN32
			u_long nb = 1;
			ioctlsocket (watch_sock, FIONBIO, &nb);
#else
			fcntl (watch_sock, F_SETFL, O_NONBLOCK);
#endif
		}
	}

	if (watch_sock == WL_INVALID_SOCKET)
		return;

	sendto (watch_sock, line, len, 0,
			(struct sockaddr *)&watch_sin, sizeof(watch_sin));

	if (watch_sent_count++ == 0)
		Com_Printf ("watchlink: streaming to %s:%u\n",
				inet_ntoa (watch_sin.sin_addr),
				(unsigned)ntohs (watch_sin.sin_port));
}

/*
 * Copy src into dst with the characters JSON forbids bare (", \, control
 * chars, and Quake's high-bit "colored" text) escaped or stripped, so a
 * pickup/centerprint string can never break the line framing.
 */
static void
WatchLink_EscapeJson (char *dst, int dstsize, const char *src)
{
	int	o = 0;

	for (; *src && o < dstsize - 7; src++)
	{
		unsigned char c = (unsigned char)*src;

		c &= 0x7f; /* drop Quake's high-bit colored glyphs */

		if (c == '"' || c == '\\')
		{
			dst[o++] = '\\';
			dst[o++] = c;
		}
		else if (c == '\n')
		{
			dst[o++] = '\\';
			dst[o++] = 'n';
		}
		else if (c >= ' ')
		{
			dst[o++] = c;
		}
		/* other control chars dropped */
	}

	dst[o] = 0;
}

void
CL_WatchLink_Init (void)
{
	watch_host = Cvar_Get ("watch_host", "", CVAR_ARCHIVE);
	watch_port = Cvar_Get ("watch_port", "27999", CVAR_ARCHIVE);
	watch_rate = Cvar_Get ("watch_rate", "10", CVAR_ARCHIVE);
	watch_events = Cvar_Get ("watch_events", "1", CVAR_ARCHIVE);

	watch_sin_valid = qfalse;
	watch_last_send = 0;
	watch_last_vitals[0] = '\0';
	watch_lastmap[0] = '\0';
	watch_last_cp[0] = '\0';
	watch_dmg_flash = 0;
	watch_have_prev = qfalse;
	/* watch_host_seen's "\001" sentinel forces the first WatchLink_Sync to
	   reconcile, so an archived watch_host (incl. "auto") is honoured at
	   launch without needing a console edit. */
}

/*
 * Emit a one-off event line. kind is the event class ("damage", "centerprint",
 * ...); detail is pre-formatted JSON members (already escaped) appended
 * verbatim, e.g. ,"msg":"You fragged Sarge".
 */
static void
WatchLink_Event (const char *kind, const char *detail)
{
	char	line[1280];

	if (clc.demoplaying)
		return;
	if (!watch_host->string[0])
		return;

	WatchLink_Sync ();
	if (!WatchLink_DestReady () || !watch_events->integer)
		return;

	Com_sprintf (line, sizeof(line),
			"{\"t\":\"event\",\"kind\":\"%s\"%s}\n",
			kind, detail ? detail : "");
	WatchLink_Send (line);
}

/*
 * Forward a local-player feedback sound to the companion as a "psound" event,
 * matching the Quake I/II wire shape (the app plays a game-correct clip for the
 * basename). Quake III plays sounds entirely in cgame against the player model
 * set, so rather than trying to intercept the (per-entity, deathmatch-noisy)
 * sound layer we DERIVE the handful that matter from the local player's own
 * state deltas in CL_WatchLink_Frame: pain/death from HP, pickups from the
 * weapon mask, powerup from the powerup timers. That is inherently local-only.
 */
static void
WatchLink_PSound (const char *base)
{
	char	esc[80];
	char	detail[100];

	WatchLink_EscapeJson (esc, sizeof(esc), base);
	Com_sprintf (detail, sizeof(detail), ",\"msg\":\"%s\"", esc);
	WatchLink_Event ("psound", detail);
}

/*
 * Hooked from CL_ParseCommandString: forward the "cp" (centerprint) server
 * command -- frag messages, CTF events, round announcements -- to the
 * companion's comms log. The raw command string looks like:  cp "You fragged
 * Sarge"  -- we pull the quoted payload out by hand (tokenizing here would
 * clobber the engine's command parser mid-message).
 */
void
CL_WatchLink_ServerCommand (const char *s)
{
	const char	*p;
	char		msg[1024];
	char		esc[1024];
	char		detail[1100];
	int		o;

	if (clc.demoplaying || !s || !s[0])
		return;
	if (!watch_host->string[0])
		return;

	/* Only centerprints. Q3's command verb is "cp". */
	if (Q_stricmpn (s, "cp ", 3) != 0)
		return;

	p = s + 3;
	while (*p == ' ')
		p++;
	if (*p == '"')			/* quoted payload: copy until the closing quote */
	{
		p++;
		for (o = 0; *p && *p != '"' && o < (int)sizeof(msg) - 1; p++)
			msg[o++] = *p;
		msg[o] = '\0';
	}
	else
	{
		Q_strncpyz (msg, p, sizeof(msg));
	}

	if (!msg[0])
		return;

	/* Drop consecutive duplicates (re-fired triggers / repeated CTF nags). */
	if (!strcmp (msg, watch_last_cp))
		return;
	Q_strncpyz (watch_last_cp, msg, sizeof(watch_last_cp));

	WatchLink_EscapeJson (esc, sizeof(esc), msg);
	Com_sprintf (detail, sizeof(detail), ",\"msg\":\"%s\"", esc);
	WatchLink_Event ("centerprint", detail);
}

/*
 * Build and send the per-map lookup table the watch shows: level name plus the
 * weapons the player owns right now. Sub-MTU by design.
 */
static void
WatchLink_SendMeta (void)
{
	char		line[1024];
	char		raw[128];
	char		base[128];
	char		name[128];
	char		*skip;
	const int	*st = cl.snap.ps.stats;
	int		i, n, off;

	Q_strncpyz (raw, cl.mapname, sizeof(raw));
	skip = COM_SkipPath (raw);
	COM_StripExtension (skip, base, sizeof(base));
	WatchLink_EscapeJson (name, sizeof(name), base[0] ? base : "Arena");

	Com_sprintf (line, sizeof(line),
			"{\"t\":\"meta\",\"level\":\"%s\",\"items\":[", name);
	off = (int)strlen (line);

	n = 0;
	for (i = 0; i < (int)(sizeof(watch_arsenal) / sizeof(watch_arsenal[0])); i++)
	{
		if (!(st[STAT_WEAPONS] & (1 << watch_arsenal[i].wp)))
			continue;
		if (off + (int)strlen (watch_arsenal[i].name) + 8 >= (int)sizeof(line))
			break;
		Com_sprintf (line + off, sizeof(line) - off,
				n ? ",\"%s\"" : "\"%s\"", watch_arsenal[i].name);
		off += (int)strlen (line + off);
		n++;
	}

	Q_strcat (line, sizeof(line), "]}\n");
	WatchLink_Send (line);
}

/*
 * New map: re-arm discovery so the link freshens for this session WITHOUT
 * dropping the current target, and reset the per-session change-detect state.
 */
static void
WatchLink_Reconnect (void)
{
	watch_last_send = 0;
	watch_last_vitals[0] = '\0';
	watch_last_cp[0] = '\0';
	watch_dmg_flash = 0;
	watch_have_prev = qfalse;
	watch_prev_weapons = 0;
	watch_prev_dmgevent = 0;
	watch_pu_active = qfalse;
	watch_pain_at = 0;
	watch_sent_count = 0;

#ifdef WATCHLINK_BONJOUR
	if (WatchLink_IsAuto ())
	{
		WatchLink_StartDiscovery ();
		return;
	}
#endif
	WatchLink_Resolve ();
}

/*
 * Per-frame heartbeat. Called from the tail of CL_Frame (after CL_SetCGameTime
 * so cl.serverTime is current). Throttled to watch_rate Hz, change-detected
 * with a 1 s keepalive. Picks up cvar edits live.
 */
void
CL_WatchLink_Frame (void)
{
	const playerState_t *ps;
	const int	*st;
	char		line[1024];
	const char	*sel;
	const char	*pu_icon;
	int		pu_sec;
	int		hp, armor, ammo, frags, wp;
	int		i;
	double		now, interval;

	if (!watch_host->string[0])
		return;			/* feature off -- stay fully inert */

	WatchLink_Sync ();

	/* Only meaningful with a live in-game snapshot; never stream menus,
	   demos or the benchmark timedemo. */
	if (clc.state != CA_ACTIVE || clc.demoplaying || !cl.snap.valid)
		return;

	/* New map? re-arm discovery and queue the meta table. Done regardless of
	   whether a destination is known yet (auto mode usually has not resolved
	   at map-load), so the meta still goes out as soon as discovery lands. */
	if (strcmp (cl.mapname, watch_lastmap) != 0)
	{
		Q_strncpyz (watch_lastmap, cl.mapname, sizeof(watch_lastmap));
		WatchLink_Reconnect ();
		watch_meta_pending = qtrue;
	}

	if (!WatchLink_DestReady ())
		return;

	if (watch_meta_pending)
	{
		WatchLink_SendMeta ();
		watch_meta_pending = qfalse;
	}

	now = WatchLink_Now ();

	/* throttle the vitals heartbeat; floor at 1 ms. */
	interval = (watch_rate->value > 0) ? (1.0 / watch_rate->value) : 0.1;
	if (interval < 0.001)
		interval = 0.001;
	if (now - watch_last_send < interval)
		return;

	ps = &cl.snap.ps;
	st = ps->stats;

	hp = st[STAT_HEALTH];
	armor = st[STAT_ARMOR];
	frags = ps->persistant[PERS_SCORE];

	wp = ps->weapon;
	sel = WatchLink_WeaponName (wp);
	ammo = (wp > 0 && wp < MAX_WEAPONS) ? ps->ammo[wp] : 0;
	if (ammo < 0)			/* -1 == infinite (gauntlet); show 0 */
		ammo = 0;

	/* Damage edge detection: a drop in HP or armor since the last heartbeat
	   raises the matching "flashes" bit (1=blood, 2=armor) so the wrist buzzes
	   on the always-delivered vitals context, and fires a discrete instant
	   event too. Primed per map so a spawn/respawn never reads as a hit. */
	if (watch_have_prev)
	{
		int gained;

		/* REAL damage is signalled by ps->damageEvent changing -- the exact
		   signal cgame uses to flash the screen red. We must NOT key off an HP
		   or armor DROP: Quake III decays health/armor above 100 back down to
		   100 at 1/sec (you spawn at 125), which is not a hit and would
		   otherwise buzz the wrist and replay the pain sound every second. */
		if (ps->damageEvent != watch_prev_dmgevent && watch_prev_hp > 0)
		{
			char detail[64];
			int bits = 0;
			if (hp < watch_prev_hp)
				bits |= 1;		/* blood */
			if (armor < watch_prev_armor)
				bits |= 2;		/* armor */
			if (!bits)
				bits |= 1;		/* hit registered but the snapshot delta didn't show it */
			watch_dmg_flash |= bits;
			Com_sprintf (detail, sizeof(detail),
					",\"health\":%d,\"armor\":%d,\"ammo\":0",
					(bits & 1) ? 1 : 0, (bits & 2) ? 1 : 0);
			WatchLink_Event ("damage", detail);

			/* Pain vocal on a real hit you survived; rate-limited so continuous
			   damage (lava, drowning) doesn't machine-gun it. Death is handled
			   separately on the HP->0 edge below. */
			if (hp > 0 && now - watch_pain_at > 0.4)
			{
				WatchLink_PSound ("pain");
				watch_pain_at = now;
			}
		}

		if (hp <= 0 && watch_prev_hp > 0)
			WatchLink_PSound ("death");

		/* A newly-owned weapon -> pickup sound. */
		gained = st[STAT_WEAPONS] & ~watch_prev_weapons;
		if (gained & ~1)	/* ignore bit 0 (WP_NONE) churn */
			WatchLink_PSound ("wpkup");
	}
	watch_prev_hp = hp;
	watch_prev_armor = armor;
	watch_prev_dmgevent = ps->damageEvent;
	watch_prev_weapons = st[STAT_WEAPONS];
	watch_have_prev = qtrue;

	/* Active powerup, in priority order. ps.powerups[pw] holds the server time
	   (ms) the powerup expires; remaining = (expiry - now) / 1000. */
	pu_icon = "";
	pu_sec = 0;
	for (i = 0; i < (int)(sizeof(watch_powerups) / sizeof(watch_powerups[0])); i++)
	{
		int pw = watch_powerups[i].pw;
		int rem;
		if (pw <= 0 || pw >= MAX_POWERUPS)
			continue;
		if (ps->powerups[pw] == 0)
			continue;
		rem = (ps->powerups[pw] - cl.serverTime) / 1000;
		if (rem <= 0)
			continue;
		if (rem > 99)
			rem = 99;
		pu_icon = watch_powerups[i].icon;
		pu_sec = rem;
		break;
	}

	/* A powerup just became active -> powerup pickup sound (edge-triggered). */
	if (pu_sec > 0 && !watch_pu_active)
		WatchLink_PSound ("powerup");
	watch_pu_active = (pu_sec > 0) ? qtrue : qfalse;

	/* Quake III has no F1 objectives computer / inventory pack, so layouts and
	   spec stay 0 -- the wire shape stays identical to the Quake I/II feed.
	   "flashes" carries watch_dmg_flash (cleared once sent). */
	Com_sprintf (line, sizeof(line),
			"{\"t\":\"vitals\",\"game\":\"q3\","
			"\"hp\":%d,\"armor\":%d,\"ammo\":%d,"
			"\"sel\":\"%s\","
			"\"frags\":%d,\"flashes\":%d,\"layouts\":%d,\"spec\":%d,"
			"\"pu\":{\"icon\":\"%s\",\"sec\":%d}}\n",
			hp, armor, ammo,
			sel,
			frags, watch_dmg_flash, 0, 0,
			pu_icon, pu_sec);

	/* Only send when the vitals actually changed, plus a ~1 s keepalive. */
	if (strcmp (line, watch_last_vitals) == 0 &&
			now - watch_last_send < 1.0)
		return;

	watch_last_send = now;
	Q_strncpyz (watch_last_vitals, line, sizeof(watch_last_vitals));
	WatchLink_Send (line);
	watch_dmg_flash = 0;	/* edge delivered; next heartbeat clears it on the wire */
}
