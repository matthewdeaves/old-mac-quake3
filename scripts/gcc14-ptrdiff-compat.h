/* GCC14 cross-compiler + old Darwin SDK header compat shim (#39).
 *
 * Root cause (build-host, independently confirmed by old-mac-quakespasm and
 * this repo): Panther's own ppc/ansi.h defines the guard macro
 * _BSD_PTRDIFF_T_ (one of several names GCC's own stddef.h checks for
 * cross-libc compatibility) without actually emitting a ptrdiff_t typedef in
 * this SDK/toolchain combination. GCC's stddef.h then sees "already
 * provided" and skips its own definition, so ptrdiff_t is never declared -
 * confirmed via -dM -E on both the SDK header and stddef.h. Apple's own
 * gcc-4.0 doesn't hit this; it is specific to GCC14 cross-compiling against
 * this SDK. code/zlib/crc32.c is the file that surfaces it in this repo.
 *
 * Use __PTRDIFF_TYPE__ (the compiler's own builtin notion of the type), not
 * a hardcoded `long` - it's `int` on this 32-bit PowerPC target.
 *
 * Wire in via `-include scripts/gcc14-ptrdiff-compat.h` on any GCC14
 * PowerPC compile; harmless (a no-op via the include guard) on Apple's own
 * gcc-4.0 path, so it's safe even if a shared codepath ever adds it there.
 */
#ifndef __PTRDIFF_T_COMPAT_SHIM
#define __PTRDIFF_T_COMPAT_SHIM
typedef __PTRDIFF_TYPE__ ptrdiff_t;
#endif
