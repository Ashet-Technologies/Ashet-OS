/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer
 *
 *   Some parts borrowed from chain.c32:
 *
 *   Copyright 2003-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This file is part of Syslinux, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

#include <com32.h>
#include <stdlib.h>
#include <string.h>

#include <disk/errno_disk.h>
#include <disk/geom.h>
#include <disk/read.h>
#include <disk/util.h>
#include <disk/common.h>

/*
 * TODO: implement file descriptors to cache metadata (geometry, ...)
 */

/**
 * read_mbr - return a pointer to a malloced buffer containing the mbr
 * @drive:	Drive number
 * @buf:	Pre-allocated buffer for output
 *
 * Return the number of sectors read on success or -1 on failure.
 * errno_disk contains the error number.
 **/
int read_mbr(int drive, void *buf)
{
    struct driveinfo drive_info;
    drive_info.disk = drive;

    /* MBR: lba = 0, 1 sector */
    return read_sectors(&drive_info, buf, 0, 1);
}

/**
 * dev_read - read from a drive
 * @drive:	Drive number
 * @buf:	Pre-allocated buffer for output
 * @lba:	Position to start reading from
 * @sectors:	Number of sectors to read
 *
 * High-level routine to read from a hard drive.
 * Return the number of sectors read on success or -1 on failure.
 * errno_disk contains the error number.
 **/
int dev_read(int drive, void *buf, unsigned int lba, int sectors)
{
    struct driveinfo drive_info;
    drive_info.disk = drive;

    return read_sectors(&drive_info, buf, lba, sectors);
}

/**
 * read_sectors - read several sectors from disk
 * @drive_info:		driveinfo struct describing the disk
 * @data:		Pre-allocated buffer for output
 * @lba:		Position to read
 * @sectors:		Number of sectors to read
 *
 * Return the number of sectors read on success or -1 on failure.
 * errno_disk contains the error number.
 **/
int read_sectors(struct driveinfo *drive_info, void *data,
		 const unsigned int lba, const int sectors)
{
    com32sys_t inreg, outreg;
    struct ebios_dapa *dapa;
    void *buf;
    char *bufp = data;
    int rv = -1;

    if (get_drive_parameters(drive_info) == -1)
	return -1;

    buf = lmalloc(sectors * SECTOR);
    if (!buf)
	return -1;

    dapa = lmalloc(sizeof(*dapa));
    if (!dapa)
	goto fail;

    memset(&inreg, 0, sizeof inreg);

    if (drive_info->ebios) {
	dapa->len = sizeof(*dapa);
	dapa->count = sectors;
	dapa->off = OFFS(buf);
	dapa->seg = SEG(buf);
	dapa->lba = lba;

	inreg.esi.w[0] = OFFS(dapa);
	inreg.ds = SEG(dapa);
	inreg.edx.b[0] = drive_info->disk;
	inreg.eax.b[1] = 0x42;	/* Extended read */
    } else {
	unsigned int c, h, s;

	if (!drive_info->cbios) {	// XXX errno
	    /* We failed to get the geometry */
	    if (lba)
		goto fail;	/* Can only read MBR */

	    s = 1;
	    h = 0;
	    c = 0;
	} else
	    lba_to_chs(drive_info, lba, &s, &h, &c);

	// XXX errno
	if (s > 63 || h > 256 || c > 1023)
	    goto fail;

	inreg.eax.w[0] = 0x0201;	/* Read one sector */
	inreg.ecx.b[1] = c & 0xff;
	inreg.ecx.b[0] = s + (c >> 6);
	inreg.edx.b[1] = h;
	inreg.edx.b[0] = drive_info->disk;
	inreg.ebx.w[0] = OFFS(buf);
	inreg.es = SEG(buf);
    }

    /* Perform the read */
    if (int13_retry(&inreg, &outreg)) {
	errno_disk = outreg.eax.b[1];
	goto fail;		/* Give up */
    }

    memcpy(bufp, buf, sectors * SECTOR);
    rv = sectors;

fail:
    lfree(dapa);
    lfree(buf);
    return rv;
}
