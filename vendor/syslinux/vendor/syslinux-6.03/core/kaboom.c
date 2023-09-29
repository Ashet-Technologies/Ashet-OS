/*
 * kaboom.c
 */

#include "core.h"

#if defined(CORE_DEBUG) || defined(DEBUG_PORT)

#include <dprintf.h>

__export __noreturn __bad_SEG(const volatile void *p)
{
    dprintf("SEG() passed an invalid pointer: %p\n", p);
    kaboom();
}

#endif

#undef kaboom

__export __noreturn _kaboom(void)
{
    extern void kaboom(void);
    call16(kaboom, &zero_regs, NULL);
    /* Do this if kaboom somehow returns... */
    for (;;)
	asm volatile("hlt");
}
