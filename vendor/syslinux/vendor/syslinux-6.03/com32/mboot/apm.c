/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 *   Based on code from the Linux kernel:
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *
 *   Original APM BIOS checking by Stephen Rothwell, May 1994
 *   (sfr@canb.auug.org.au)
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

/*
 * apm.c
 *
 * APM information for Multiboot
 */

#include "mboot.h"
#include <com32.h>

void mboot_apm(void)
{
    static struct apm_info apm;
    com32sys_t ireg, oreg;

    memset(&ireg, 0, sizeof ireg);

    ireg.eax.w[0] = 0x5300;
    __intcall(0x15, &ireg, &oreg);

    if (oreg.eflags.l & EFLAGS_CF)
	return;			/* No APM BIOS */

    if (oreg.ebx.w[0] != 0x504d)
	return;			/* No "PM" signature */

    if (!(oreg.ecx.w[0] & 0x02))
	return;			/* 32 bits not supported */

    /* Disconnect first, just in case */
    memset(&ireg, 0, sizeof ireg);
    ireg.eax.b[0] = 0x04;
    __intcall(0x15, &ireg, &oreg);

    /* 32-bit connect */
    ireg.eax.b[0] = 0x03;
    __intcall(0x15, &ireg, &oreg);

    apm.cseg = oreg.eax.w[0];
    apm.offset = oreg.ebx.l;
    apm.cseg_16 = oreg.ecx.w[0];
    apm.dseg_16 = oreg.edx.w[0];
    apm.cseg_len = oreg.esi.w[0];
    apm.cseg_16_len = oreg.esi.w[1];
    apm.dseg_16_len = oreg.edi.w[0];

    /* Redo the installation check as the 32-bit connect;
       some BIOSes return different flags this way... */

    memset(&ireg, 0, sizeof ireg);
    ireg.eax.b[0] = 0x00;
    __intcall(0x15, &ireg, &oreg);

    if ((oreg.eflags.l & EFLAGS_CF) || (oreg.ebx.w[0] != 0x504d)) {
	/* Failure with 32-bit connect, try to disconect and ignore */
	ireg.eax.b[0] = 0x04;
	__intcall(0x15, &ireg, NULL);
	return;
    }

    apm.version = oreg.eax.w[0];

    mbinfo.apm_table = map_data(&apm, sizeof apm, 4, false);
    if (mbinfo.apm_table)
	mbinfo.flags |= MB_INFO_APM_TABLE;
}
