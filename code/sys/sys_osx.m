/*
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/

#ifndef MACOS_X
#error This file is for Mac OS X only. You probably should not compile it.
#endif

// Please note that this file is just some Mac-specific bits. Most of the
// Mac OS X code is shared with other Unix platforms in sys_unix.c ...

#include "../qcommon/q_shared.h"
#include "../qcommon/qcommon.h"
#include "sys_local.h"

#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#include <dlfcn.h>

/*
==============
Sys_Dialog

Display an OS X dialog box
==============
*/
dialogResult_t Sys_Dialog( dialogType_t type, const char *message, const char *title )
{
	dialogResult_t result = DR_OK;
	NSAlert *alert = [NSAlert new];

	[alert setMessageText: [NSString stringWithUTF8String: title]];
	[alert setInformativeText: [NSString stringWithUTF8String: message]];

	if( type == DT_ERROR )
		[alert setAlertStyle: NSCriticalAlertStyle];
	else
		[alert setAlertStyle: NSWarningAlertStyle];

	switch( type )
	{
		default:
			[alert runModal];
			result = DR_OK;
			break;

		case DT_YES_NO:
			[alert addButtonWithTitle: @"Yes"];
			[alert addButtonWithTitle: @"No"];
			switch( [alert runModal] )
			{
				default:
				case NSAlertFirstButtonReturn: result = DR_YES; break;
				case NSAlertSecondButtonReturn: result = DR_NO; break;
			}
			break;

		case DT_OK_CANCEL:
			[alert addButtonWithTitle: @"OK"];
			[alert addButtonWithTitle: @"Cancel"];

			switch( [alert runModal] )
			{
				default:
				case NSAlertFirstButtonReturn: result = DR_OK; break;
				case NSAlertSecondButtonReturn: result = DR_CANCEL; break;
			}
			break;
	}

	[alert release];

	return result;
}

/*
=================
Sys_StripAppBundle

Discovers if passed dir is suffixed with the directory structure of a Mac OS X
.app bundle. If it is, the .app directory structure is stripped off the end and
the result is returned. If not, dir is returned untouched.
=================
*/
char *Sys_StripAppBundle( char *dir )
{
	static char cwd[MAX_OSPATH];

	Q_strncpyz(cwd, dir, sizeof(cwd));
	if(strcmp(Sys_Basename(cwd), "MacOS"))
		return dir;
	Q_strncpyz(cwd, Sys_Dirname(cwd), sizeof(cwd));
	if(strcmp(Sys_Basename(cwd), "Contents"))
		return dir;
	Q_strncpyz(cwd, Sys_Dirname(cwd), sizeof(cwd));
	if(!strstr(Sys_Basename(cwd), ".app"))
		return dir;
	Q_strncpyz(cwd, Sys_Dirname(cwd), sizeof(cwd));
	return cwd;
}

/*
=================
Sys_ResolveTranslocatedPath

Gatekeeper's App Translocation (10.12 Sierra+) launches a freshly-quarantined
.app that has never been moved by Finder from a randomized, read-only shadow
copy under .../AppTranslocation/<uuid>/d/, and argv[0] then names THAT copy,
not the real install location. Every fresh download hits this: the DMG-drag
install our own README describes is fine (a Finder move clears translocation
for future launches), but double-clicking straight off the mounted image, or
any non-Finder copy (ditto/cp), does not, and Sys_SetBinaryPath(Sys_Dirname
(argv[0])) then derives fs_basepath from the shadow copy, which has no
baseq3/ next to it - the engine reports missing pak files even though the
user's real baseq3/ sits right next to the real .app. MEASURED 2026-08-28 on
imac-2019 (Sequoia): reproduced by ditto-copying a quarantined app and
launching it via `open`; `open` succeeds (no Gatekeeper dialog - this app is
ad-hoc signed, not blocked outright) but argv[0] comes back under
/private/var/.../AppTranslocation/. See issue #37.

SecTranslocateCreateOriginalPathForURL is the private Security-framework call
that reverses this. It does not exist before 10.12, and this binary is one
fat Mach-O spanning 10.3 Panther through modern macOS, so it is resolved with
dlopen/dlsym at runtime rather than linked against directly - on every OS
before Sierra the symbol is simply absent, which is fine because nothing
translocates there in the first place.

Returns path unchanged (never NULL) if not translocated, or the resolution
fails for any reason - falling back to the old (wrong but never worse)
behavior rather than crashing the launch path.
=================
*/
char *Sys_ResolveTranslocatedPath( char *path )
{
	static char resolved[MAX_OSPATH];
	void *sec;
	// CFErrorRef itself (CFError.h) does not exist on the 10.3.9 SDK - it was
	// added in Leopard - and this file builds on every slice from ppc750
	// through arm64 off one shared source tree. The exact pointee type does
	// not matter here: this pointer is only ever written by the dlsym'd
	// function and, if non-NULL, released as an opaque CFTypeRef below, never
	// dereferenced as a CFError. `void *` is ABI-identical to any other object
	// pointer and compiles unchanged on every SDK in the fleet. Broke the
	// ppc750 build (issue #17 cleanup pass caught it): "syntax error before
	// 'CFErrorRef'" from make[2] on the Panther SDK.
	CFURLRef (*createOriginal)( CFURLRef, void ** );
	CFURLRef translocated, original;
	void *err = NULL;

	if( !strstr( path, "/AppTranslocation/" ) )
		return path;

	sec = dlopen( "/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_NOLOAD );
	if( !sec )
		sec = dlopen( "/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY );
	if( !sec )
		return path;

	createOriginal = dlsym( sec, "SecTranslocateCreateOriginalPathForURL" );
	if( !createOriginal )
		return path;

	translocated = CFURLCreateFromFileSystemRepresentation(
		kCFAllocatorDefault, (const UInt8 *)path, strlen( path ), true );
	if( !translocated )
		return path;

	original = createOriginal( translocated, &err );
	CFRelease( translocated );
	if( err )
		CFRelease( err );
	if( !original )
		return path;

	if( !CFURLGetFileSystemRepresentation( original, true, (UInt8 *)resolved, sizeof( resolved ) ) )
	{
		CFRelease( original );
		return path;
	}
	CFRelease( original );

	fprintf( stderr, "App Translocation detected; resolved real bundle path: %s\n", resolved );
	return resolved;
}
