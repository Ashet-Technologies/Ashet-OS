/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * entry.c
 *
 * Dump the entry point registers
 */

#include <string.h>
#include <stdio.h>
#include <inttypes.h>
#include <console.h>
#include <syslinux/config.h>

struct stack_frame {
    uint16_t gs, fs, es, ds;
    uint32_t edi, esi, ebp, esp;
    uint32_t ebx, edx, ecx, eax;
    uint32_t eflags;
    uint16_t ret_ip, ret_cs;
    uint16_t pxe_ip, pxe_cs;
};

int main(void)
{
    const union syslinux_derivative_info *di;
    const struct stack_frame *sf;

#if 0
	/* this hangs! */
    openconsole(&dev_null_r, &dev_stdcon_w);
#else
	/* this works */
    openconsole(&dev_rawcon_r, &dev_ansiserial_w);
#endif

    di = syslinux_derivative_info();

    if (di->c.filesystem != SYSLINUX_FS_PXELINUX) {
	printf("Not running under PXELINUX (fs = %02x)\n", di->c.filesystem);
	return 1;
    }

    sf = (const struct stack_frame *)di->pxe.stack;

    printf("EAX: %08x  EBX: %08x  ECX: %08x  EDX: %08x\n"
	   "ESP: %08x  EBP: %08x  ESI: %08x  EDI: %08x\n"
	   "SS: %04x   DS: %04x   ES: %04x   FS: %04x   GS:  %04x\n"
	   "EFLAGS: %08x   RET: %04x:%04x   PXE: %04x:%04x\n",
	   sf->eax, sf->ebx, sf->ecx, sf->edx,
	   sf->esp + 4, sf->ebp, sf->esi, sf->edi,
	   di->rr.r.fs, sf->ds, sf->es, sf->fs, sf->gs,
	   sf->eflags, sf->ret_cs, sf->ret_ip, sf->pxe_cs, sf->pxe_ip);

    return 0;
}
