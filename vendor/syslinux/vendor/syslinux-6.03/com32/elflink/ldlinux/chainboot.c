/* ----------------------------------------------------------------------- *
 *   
 *   Copyright 2012 Intel Corporation, author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * chainbooting - replace the current bootloader completely.  This
 * is BIOS-specific.
 */

#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <dprintf.h>

#include <com32.h>
#include <sys/exec.h>
#include <sys/io.h>
#include "core.h"
#include "menu.h"
#include "fs.h"
#include "config.h"
#include "localboot.h"
#include "bios.h"

#include <syslinux/boot.h>
#include <syslinux/bootrm.h>
#include <syslinux/movebits.h>
#include <syslinux/config.h>

void chainboot_file(const char *file, uint32_t type)
{
    uint8_t keeppxe = 0;
    const union syslinux_derivative_info *sdi;
    struct syslinux_rm_regs regs;
    struct syslinux_movelist *fraglist = NULL;
    struct syslinux_memmap *mmap = NULL;
    struct com32_filedata fd;
    com32sys_t reg;
    char *stack;
    void *buf;
    int rv, max, size;
    
    max = 0xA0000;		/* Maximum load */
    buf = malloc(max);
    if (!buf)
	goto bail;
    
    rv = open_file(file, O_RDONLY, &fd);
    if (rv == -1)
	goto bail;
    
    reg.eax.l = max;
    reg.ebx.l = 0;
    reg.edx.w[0] = 0;
    reg.edi.l = (uint32_t)buf;
    reg.ebp.l = -1;	/* XXX: limit? */
    reg.esi.w[0] = rv;

    pm_load_high(&reg);

    size = reg.edi.l - (unsigned long)buf;
    if (size > 0xA0000 - 0x7C00) {
	printf("Too large for a boostrap (need LINUX instead of KERNEL?)\n");
	goto bail;
    }

    mmap = syslinux_memory_map();
    if (!mmap)
	goto bail;

    sdi = syslinux_derivative_info();

    memset(&regs, 0, sizeof(regs));
    regs.ip = 0x7c00;

    if (sdi->c.filesystem == SYSLINUX_FS_SYSLINUX ||
	sdi->c.filesystem == SYSLINUX_FS_EXTLINUX) {
	if (syslinux_add_movelist(&fraglist, 0x800 - 18,
				  (addr_t)sdi->r.esbx, 16))
	    goto bail;

	/* DS:SI points to partition info */
	regs.esi.l = 0x800 - 18;
    }

    /*
     * For a BSS boot sector we have to transfer the
     * superblock.
     */
    if (sdi->c.filesystem == SYSLINUX_FS_SYSLINUX &&
	type == IMAGE_TYPE_BSS && this_fs->fs_ops->copy_super(buf))
	goto bail;

    if (sdi->c.filesystem == SYSLINUX_FS_PXELINUX) {
	keeppxe = 0x03;		/* Chainloading + keep PXE */
	stack = (char *)sdi->r.fssi;

	/*
	 * Set up the registers with their initial values
	 */

	regs.eax.l = *(uint32_t *)&stack[36];
	regs.ecx.l = *(uint32_t *)&stack[32];
	regs.edx.l = *(uint32_t *)&stack[28];
	regs.ebx.l = *(uint32_t *)&stack[24];
	regs.esp.l = sdi->rr.r.esi.w[0] + 44;
	regs.ebp.l = *(uint32_t *)&stack[16];
	regs.esi.l = *(uint32_t *)&stack[12];
	regs.edi.l = *(uint32_t *)&stack[8];
	regs.es = *(uint16_t *)&stack[4];
	regs.ss = sdi->rr.r.fs;
	regs.ds = *(uint16_t *)&stack[6];
	regs.fs = *(uint16_t *)&stack[2];
	regs.gs = *(uint16_t *)&stack[0];
    } else {
	const uint16_t *esdi = (const uint16_t *)sdi->disk.esdi_ptr;

	regs.esp.l = (uint16_t)(unsigned long)StackBuf + 44;

	/*
	 * DON'T DO THIS FOR PXELINUX...
	 * For PXE, ES:BX -> PXENV+, and this would
	 * corrupt that use.
	 *
	 * Restore ES:DI -> $PnP (if we were ourselves
	 * called that way...)
	 */
	regs.edi.w[0] = esdi[0]; /* New DI */
	regs.es       = esdi[2]; /* New ES */

	regs.edx.l    = sdi->rr.r.edx.b[0]; /* Drive number -> DL */
    }

    if (syslinux_add_movelist(&fraglist, 0x7c00, (addr_t)buf, size))
	goto bail;

    syslinux_shuffle_boot_rm(fraglist, mmap, keeppxe, &regs);

bail:
    if (fraglist)
	syslinux_free_movelist(fraglist);
    if (mmap)
	syslinux_free_memmap(mmap);
    if (buf)
	free(buf);
    return;
}
