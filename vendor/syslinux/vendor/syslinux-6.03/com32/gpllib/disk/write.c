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

#include <disk/common.h>
#include <disk/errno_disk.h>
#include <disk/read.h>
#include <disk/util.h>
#include <disk/write.h>

/**
 * write_sectors - write several sectors from disk
 * @drive_info:		driveinfo struct describing the disk
 * @lba:		Position to write
 * @data:		Buffer to write
 * @size:		Size of the buffer (number of sectors)
 *
 * Return the number of sectors write on success or -1 on failure.
 * errno_disk contains the error number.
 **/
int write_sectors(const struct driveinfo *drive_info, const unsigned int lba,
		  const void *data, const int size)
{
    com32sys_t inreg, outreg;
    struct ebios_dapa *dapa;
    void *buf;
    int rv = -1;

    buf = lmalloc(size);
    if (!buf)
	return -1;

    dapa = lmalloc(sizeof(*dapa));
    if (!dapa)
	goto out;

    memcpy(buf, data, size);
    memset(&inreg, 0, sizeof inreg);

    if (drive_info->ebios) {
	dapa->len = sizeof(*dapa);
	dapa->count = size;
	dapa->off = OFFS(buf);
	dapa->seg = SEG(buf);
	dapa->lba = lba;

	inreg.esi.w[0] = OFFS(dapa);
	inreg.ds = SEG(dapa);
	inreg.edx.b[0] = drive_info->disk;
	inreg.eax.w[0] = 0x4300;	/* Extended write */
    } else {
	unsigned int c, h, s;

	if (!drive_info->cbios) {	// XXX errno
	    /* We failed to get the geometry */
	    if (lba)
		goto out;	/* Can only write MBR */

	    s = 1;
	    h = 0;
	    c = 0;
	} else
	    lba_to_chs(drive_info, lba, &s, &h, &c);

	// XXX errno
	if (s > 63 || h > 256 || c > 1023)
	    goto out;

	inreg.eax.w[0] = 0x0301;	/* Write one sector */
	inreg.ecx.b[1] = c & 0xff;
	inreg.ecx.b[0] = s + (c >> 6);
	inreg.edx.b[1] = h;
	inreg.edx.b[0] = drive_info->disk;
	inreg.ebx.w[0] = OFFS(buf);
	inreg.es = SEG(buf);
    }

    /* Perform the write */
    if (int13_retry(&inreg, &outreg)) {
	errno_disk = outreg.eax.b[1];	/* Give up */
    } else
	rv = size;
out:
    lfree(dapa);
    lfree(buf);
    return rv;
}

/**
 * write_verify_sectors - write several sectors from disk
 * @drive_info:		driveinfo struct describing the disk
 * @lba:		Position to write
 * @data:		Buffer to write
 **/
int write_verify_sector(struct driveinfo *drive_info,
			const unsigned int lba, const void *data)
{
    return write_verify_sectors(drive_info, lba, data, SECTOR);
}

/**
 * write_verify_sectors - write several sectors from disk
 * @drive_info:		driveinfo struct describing the disk
 * @lba:		Position to write
 * @data:		Buffer to write
 * @size:		Size of the buffer (number of sectors)
 **/
int write_verify_sectors(struct driveinfo *drive_info,
			 const unsigned int lba,
			 const void *data, const int size)
{
    char *rb = malloc(SECTOR * size * sizeof(char));
    int status;

    if (write_sectors(drive_info, lba, data, size) == -1)
	return -1;		/* Write failure */

    if (read_sectors(drive_info, rb, lba, size) == -1)
	return -1;		/* Readback failure */

    status = memcmp(data, rb, SECTOR * size);
    free(rb);
    return status ? -1 : 0;
}
