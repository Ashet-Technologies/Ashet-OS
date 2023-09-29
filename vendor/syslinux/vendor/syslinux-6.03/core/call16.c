/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * call16.c
 *
 * Simple wrapper to call 16-bit core functions from 32-bit code
 */

#include <stddef.h>
#include <stdio.h>
#include "core.h"

__export const com32sys_t zero_regs;	/* Common all-zero register set */

static inline uint32_t eflags(void)
{
    //uint32_t v;

#if __SIZEOF_POINTER__ == 4
    uint32_t v;
    asm volatile("pushfl ; popl %0" : "=rm" (v));
#elif __SIZEOF_POINTER__ == 8
    uint64_t v;
    asm volatile("pushfq ; pop %0" : "=rm" (v));
#else
#error "Unable to build for to-be-defined architecture type"
#endif
    return v;
}

__export void call16(void (*func)(void), const com32sys_t *ireg,
		     com32sys_t *oreg)
{
    com32sys_t xreg = *ireg;

    /* Enable interrupts if and only if they are enabled in the caller */
    xreg.eflags.l = (xreg.eflags.l & ~EFLAGS_IF) | (eflags() & EFLAGS_IF);

    core_farcall((size_t)func, &xreg, oreg);
}
