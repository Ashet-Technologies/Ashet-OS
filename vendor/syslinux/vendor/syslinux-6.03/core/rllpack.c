/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * rllpack.inc
 *
 * Very simple RLL compressor/decompressor, used to pack binary structures
 * together.
 *
 * Format of leading byte
 * 1-128	= x verbatim bytes follow
 * 129-223	= (x-126) times subsequent byte
 * 224-255	= (x-224)*256+(next byte) times the following byte
 * 0		= end of data
 *
 * These structures are stored *in reverse order* in high memory.
 * High memory pointers point to one byte beyond the end.
 */

#include <com32.h>
#include <stddef.h>
#include <string.h>

void rllpack(com32sys_t * regs)
{
    uint8_t *i = (uint8_t *) (regs->esi.l);
    uint8_t *o = (uint8_t *) (regs->edi.l);
    size_t cnt = regs->ecx.l;
    size_t run, vrun, tcnt;
    uint8_t *hdr = NULL;
    uint8_t c;

    vrun = (size_t)-1;
    while (cnt) {
	c = *i;

	run = 1;
	tcnt = (cnt > 8191) ? 8191 : cnt;
	while (run < tcnt && i[run] == c)
	    run++;

	if (run < 3) {
	    if (vrun >= 128) {
		hdr = --o;
		vrun = 0;
	    }
	    *--o = c;
	    *hdr = ++vrun;
	    i++;
	    cnt--;
	} else {
	    if (run < 224 - 126) {
		*--o = run + 126;
	    } else {
		o -= 2;
		*(uint16_t *) o = run + (224 << 8);
	    }
	    *--o = c;
	    vrun = (size_t)-1;
	    i += run;
	    cnt -= run;
	}
    }
    *--o = 0;

    regs->esi.l = (size_t)i;
    regs->edi.l = (size_t)o;
}

void rllunpack(com32sys_t * regs)
{
    uint8_t *i = (uint8_t *) regs->esi.l;
    uint8_t *o = (uint8_t *) regs->edi.l;
    uint8_t c;
    size_t n;

    while ((c = *--i)) {
	if (c <= 128) {
	    while (c--)
		*o++ = *--i;
	} else {
	    if (c < 224)
		n = c - 126;
	    else
		n = ((c - 224) << 8) + *--i;
	    c = *--i;
	    while (n--)
		*o++ = c;
	}
    }

    regs->esi.l = (size_t)i;
    regs->ecx.l = (size_t)o - regs->edi.l;
    regs->edi.l = (size_t)o;
}
