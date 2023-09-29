/* -----------------------------------------------------------------------
 *
 *   Copyright 1999-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * -----------------------------------------------------------------------
 */
#include <sys/cpu.h>
#include <sys/io.h>
#include <string.h>
#include <core.h>
#include <fs.h>
#include <bios.h>
#include <syslinux/video.h>

/*
 * localboot.c
 *
 * Boot from a local disk, or invoke INT 18h.
 */

#define LOCALBOOT_MSG	"Booting from local disk..."

#define retry_count	16

extern void local_boot16(void);

/*
 * Boot a specified local disk.  AX specifies the BIOS disk number; or
 * -1 in case we should execute INT 18h ("next device.")
 */
__export void local_boot(int16_t ax)
{
	com32sys_t ireg, oreg;
	int i;

        memset(&ireg, 0, sizeof(ireg));
	syslinux_force_text_mode();

	writestr(LOCALBOOT_MSG);
	crlf();
	cleanup_hardware();

	if (ax == -1) {
		/* Hope this does the right thing */
		__intcall(0x18, &zero_regs, NULL);

		/* If we returned, oh boy... */
		kaboom();
	}

	/*
	 * Load boot sector from the specified BIOS device and jump to
	 * it.
	 */
	memset(&ireg, 0, sizeof ireg);
	ireg.edx.b[0] = ax & 0xff;
	ireg.eax.w[0] = 0;	/* Reset drive */
	__intcall(0x13, &ireg, NULL);

	memset(&ireg, 0, sizeof(ireg));
	ireg.eax.w[0] = 0x0201;	/* Read one sector */
	ireg.ecx.w[0] = 0x0001;	/* C/H/S = 0/0/1 (first sector) */
	ireg.ebx.w[0] = OFFS(trackbuf);
	ireg.es = SEG(trackbuf);

	for (i = 0; i < retry_count; i++) {
		__intcall(0x13, &ireg, &oreg);

		if (!(oreg.eflags.l & EFLAGS_CF))
			break;
	}

	if (i == retry_count)
		kaboom();

	cli();			/* Abandon hope, ye who enter here */
	memcpy((void *)0x07C00, trackbuf, 512);

	ireg.esi.w[0] = OFFS(trackbuf);
	ireg.edi.w[0] = 0x07C00;
	ireg.edx.w[0] = ax;
	call16(local_boot16, &ireg, NULL);
}

void pm_local_boot(com32sys_t *regs)
{
	local_boot(regs->eax.w[0]);
}
