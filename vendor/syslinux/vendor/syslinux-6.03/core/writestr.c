/*
 * -----------------------------------------------------------------------
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
 *
 *
 * writestr.c
 *
 * Code to write a simple string.
 */
#include <com32.h>
#include <core.h>

/*
 * crlf: Print a newline
 */
void crlf(void)
{
	writechr('\r');
	writechr('\n');
}

/*
 * writestr: write a null-terminated string to the console, saving
 *            registers on entry.
 *
 * Note: writestr_early and writestr are distinct in
 * SYSLINUX and EXTLINUX, but not PXELINUX and ISOLINUX
 */
void writestr(char *str)
{
	while (*str)
		writechr(*str++);
}

void pm_writestr(com32sys_t *regs)
{
	writestr(MK_PTR(regs->ds, regs->esi.w[0]));
}
