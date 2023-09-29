/* -----------------------------------------------------------------------
 *
 *   Copyright 1994-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * -----------------------------------------------------------------------
 */
#include <core.h>

/*
 * writehex.c
 *
 * Write hexadecimal numbers to the console
 *
 */

static inline void __writehex(uint32_t h, int digits)
{
	while (digits) {
		uint8_t shift;
		uint8_t al;

		shift = --digits;
		al = ((h & 0x0f << shift) >> shift);
		if (al < 10)
			al += '0';
		else
			al += 'A' - 10;

		writechr(al);
	}
}

/*
 * writehex[248]: Write a hex number in (AL, AX, EAX) to the console
 */
void writehex2(uint32_t h)
{
	__writehex(h, 2);
}

void writehex4(uint8_t h)
{
	__writehex(h, 4);
}

void writehex8(uint8_t h)
{
	__writehex(h, 8);
}

void pm_writehex2(com32sys_t *regs)
{
	writehex2(regs->eax.b[0]);
}

void pm_writehex4(com32sys_t *regs)
{
	writehex4(regs->eax.w[0]);
}

void pm_writehex8(com32sys_t *regs)
{
	writehex8(regs->eax.l);
}
