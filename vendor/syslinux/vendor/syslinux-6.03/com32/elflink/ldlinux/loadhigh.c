/*
 * -----------------------------------------------------------------------
 *
 *   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * loadhigh.c
 *
 * An alternate interface to getfssec.
 *
 * Inputs:	SI  = file handle/cluster pointer
 *		EDI = target address in high memory
 *		EAX = maximum number of bytes to load
 *		DX  = zero-padding mask (e.g. 0003h for pad to dword)
 *		BX  = 16-bit subroutine to call at the top of each loop
 *                    (to print status and check for abort)
 *		EBP = maximum load address
 *
 * Outputs:	SI  = file handle/cluster pointer
 *		EBX = first untouched address (not including padding)
 *		EDI = first untouched address (including padding)
 *		CF  = reached EOF
 *		OF  = ran out of high memory
 */

#include <com32.h>
#include <minmax.h>
#include "core.h"
#include "fs.h"

#define MAX_CHUNK	(1UL << 20) /* 1 MB */

void pm_load_high(com32sys_t *regs)
{
    struct fs_info *fs;
    uint32_t bytes;
    uint32_t zero_mask;
    bool have_more;
    uint32_t bytes_read;
    char *buf, *limit;
    struct file *file;
    uint32_t sector_mask;
    size_t pad;
    uint32_t retflags = 0;

    bytes     = regs->eax.l;
    zero_mask = regs->edx.w[0];
    buf       = (char *)regs->edi.l;
    limit     = (char *)(regs->ebp.l & ~zero_mask);
    file      = handle_to_file(regs->esi.w[0]);
    fs        = file->fs;

    sector_mask = SECTOR_SIZE(fs) - 1;

    while (bytes) {
	uint32_t sectors;
	uint32_t chunk;

	if (buf + SECTOR_SIZE(fs) > limit) {
	    /* Can't fit even one more sector in... */
	    retflags = EFLAGS_OF;
	    break;
	}

	chunk = bytes;

	if (regs->ebx.w[0]) {
	    call16((void (*)(void))(size_t)regs->ebx.w[0], &zero_regs, NULL);
	    chunk = min(chunk, MAX_CHUNK);
	}

	if (chunk > (((char *)limit - buf) & ~sector_mask))
	    chunk = ((char *)limit - buf) & ~sector_mask;

	sectors = (chunk + sector_mask) >> SECTOR_SHIFT(fs);
	bytes_read = fs->fs_ops->getfssec(file, buf, sectors, &have_more);

	if (bytes_read > chunk)
	    bytes_read = chunk;

	buf += bytes_read;
	bytes -= bytes_read;

	if (!have_more) {
	    /*
	     * If we reach EOF, the filesystem driver will have already closed
	     * the underlying file... this really should be cleaner.
	     */
	    _close_file(file);
	    regs->esi.w[0] = 0;
	    retflags = EFLAGS_CF;
	    break;
	}
    }

    pad = (size_t)buf & zero_mask;
    if (pad)
	memset(buf, 0, pad);

    regs->ebx.l = (size_t)buf;
    regs->edi.l = (size_t)buf + pad;
    set_flags(regs, retflags);
}
