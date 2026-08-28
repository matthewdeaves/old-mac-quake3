/* scratch/imac-2019-altivec-fix: GCC14's stddef.h skips its own ptrdiff_t
 * typedef whenever _BSD_PTRDIFF_T_ is already defined (stddef.h:127,
 * `#ifndef _BSD_PTRDIFF_T_`). Panther's usr/include/ppc/ansi.h defines that
 * exact macro itself, as a type-alias trick (`#define _BSD_PTRDIFF_T_
 * __PTRDIFF_TYPE__`), not as an include guard - GCC14 misreads the macro's
 * presence as "someone already typedef'd this". Real, narrow,
 * Panther-SDK-specific header-naming collision (old-mac-build-host,
 * independently confirmed by quakespasm, cross-checked here by reading both
 * headers directly). Tiger/Leopard SDK targets don't hit this.
 *
 * Forced in via -include ahead of any other header, so this typedef always
 * wins the race regardless of what pulls stddef.h in first. docs/adr/0020.
 */
#ifndef IMAC_2019_PTRDIFF_SHIM_H
#define IMAC_2019_PTRDIFF_SHIM_H
typedef __PTRDIFF_TYPE__ ptrdiff_t;
#define _BSD_PTRDIFF_T_
#define _PTRDIFF_T_
#endif
