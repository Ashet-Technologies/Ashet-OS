/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2013 Sebastian Herbszt - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * poweroff.c
 *
 * APM poweroff module
 */

#include <stdio.h>
#include <string.h>
#include <com32.h>

int main(int argc __unused, char *argv[] __unused)
{
	com32sys_t inregs, outregs;

	memset(&inregs, 0, sizeof inregs);

	inregs.eax.l = 0x5300; /* APM Installation Check (00h) */
	inregs.ebx.l = 0; /* APM BIOS (0000h) */
	__intcall(0x15, &inregs, &outregs);

	if (outregs.eflags.l & EFLAGS_CF) {
		printf("APM not present.\n");
		return 1;
	}

	if ((outregs.ebx.l & 0xffff) != 0x504d) { /* signature 'PM' */
		printf("APM not present.\n");
		return 1;
	}

	if ((outregs.eax.l & 0xffff) < 0x101) { /* Need version 1.1+ */
		printf("APM 1.1+ not supported.\n");
		return 1;
	}

	if ((outregs.ecx.l & 0x8) == 0x8) { /* bit 3 APM BIOS Power Management disabled */
		printf("Power management disabled.\n");
		return 1;
	}

	memset(&inregs, 0, sizeof inregs);
	inregs.eax.l = 0x5301; /* APM Real Mode Interface Connect (01h) */
	inregs.ebx.l = 0; /* APM BIOS (0000h) */
	__intcall(0x15, &inregs, &outregs);

	if (outregs.eflags.l & EFLAGS_CF) {
		printf("APM RM interface connect failed.\n");
		return 1;
	}

	memset(&inregs, 0, sizeof inregs);
	inregs.eax.l = 0x530e; /* APM Driver Version (0Eh) */
	inregs.ebx.l = 0; /* APM BIOS (0000h) */
	inregs.ecx.l = 0x101; /* APM Driver version 1.1 */
	__intcall(0x15, &inregs, &outregs);

	if (outregs.eflags.l & EFLAGS_CF) {
		printf("APM 1.1+ not supported.\n");
		return 1;
	}

	if ((outregs.ecx.l & 0xffff) < 0x101) { /* APM Connection version */
		printf("APM 1.1+ not supported.\n");
		return 1;
	}

	memset(&inregs, 0, sizeof inregs);
	inregs.eax.l = 0x5307; /* Set Power State (07h) */
	inregs.ebx.l = 1; /* All devices power managed by the APM BIOS */
	inregs.ecx.l = 3; /* Power state off */
	__intcall(0x15, &inregs, &outregs);

	if (outregs.eflags.l & EFLAGS_CF) {
		printf("Power off failed.\n");
		return 1;
	}

	return 0;
}
