/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010 Intel Corp. - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * syslxcom.c
 *
 * common functions for extlinux & syslinux installer
 *
 */
#define  _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <getopt.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/mount.h>
#include <sys/vfs.h>

#include "linuxioctl.h"
#include "syslxcom.h"
#include "syslxfs.h"

const char *program;

int fs_type;

#ifdef DEBUG
# define dprintf printf
#else
# define dprintf(...) ((void)0)
#endif

#define SECTOR_SHIFT	9

static void die(const char *msg)
{
    fputs(msg, stderr);
    exit(1);
}

/*
 * read/write wrapper functions
 */
ssize_t xpread(int fd, void *buf, size_t count, off_t offset)
{
    char *bufp = (char *)buf;
    ssize_t rv;
    ssize_t done = 0;

    while (count) {
	rv = pread(fd, bufp, count, offset);
	if (rv == 0) {
	    die("short read");
	} else if (rv == -1) {
	    if (errno == EINTR) {
		continue;
	    } else {
		die(strerror(errno));
	    }
	} else {
	    bufp += rv;
	    offset += rv;
	    done += rv;
	    count -= rv;
	}
    }

    return done;
}

ssize_t xpwrite(int fd, const void *buf, size_t count, off_t offset)
{
    const char *bufp = (const char *)buf;
    ssize_t rv;
    ssize_t done = 0;

    while (count) {
	rv = pwrite(fd, bufp, count, offset);
	if (rv == 0) {
	    die("short write");
	} else if (rv == -1) {
	    if (errno == EINTR) {
		continue;
	    } else {
		die(strerror(errno));
	    }
	} else {
	    bufp += rv;
	    offset += rv;
	    done += rv;
	    count -= rv;
	}
    }

    return done;
}

/*
 * Set and clear file attributes
 */
void clear_attributes(int fd)
{
    struct stat st;

    if (!fstat(fd, &st)) {
	switch (fs_type) {
	case EXT2:
	{
	    int flags;

	    if (!ioctl(fd, FS_IOC_GETFLAGS, &flags)) {
		flags &= ~FS_IMMUTABLE_FL;
		ioctl(fd, FS_IOC_SETFLAGS, &flags);
	    }
	    break;
	}
	case VFAT:
	{
	    uint32_t attr = 0x00; /* Clear all attributes */
	    ioctl(fd, FAT_IOCTL_SET_ATTRIBUTES, &attr);
	    break;
	}
    case NTFS:
        break;
	default:
	    break;
	}
	fchmod(fd, st.st_mode | S_IWUSR);
    }
}

void set_attributes(int fd)
{
    struct stat st;

    if (!fstat(fd, &st)) {
	fchmod(fd, st.st_mode & (S_IRUSR | S_IRGRP | S_IROTH));
	switch (fs_type) {
	case EXT2:
	{
	    int flags;

	    if (st.st_uid == 0 && !ioctl(fd, FS_IOC_GETFLAGS, &flags)) {
		flags |= FS_IMMUTABLE_FL;
		ioctl(fd, FS_IOC_SETFLAGS, &flags);
	    }
	    break;
	}
	case VFAT:
	{
	    uint32_t attr = 0x07; /* Hidden+System+Readonly */
	    ioctl(fd, FAT_IOCTL_SET_ATTRIBUTES, &attr);
	    break;
	}
    case NTFS:
        break;
	default:
	    break;
	}
    }
}

/* New FIEMAP based mapping */
static int sectmap_fie(int fd, sector_t *sectors, int nsectors)
{
    struct fiemap *fm;
    struct fiemap_extent *fe;
    unsigned int i, nsec;
    sector_t sec, *secp, *esec;
    struct stat st;
    uint64_t maplen;

    if (fstat(fd, &st))
	return -1;

    fm = alloca(sizeof(struct fiemap)
		+ nsectors * sizeof(struct fiemap_extent));

    memset(fm, 0, sizeof *fm);

    maplen = (uint64_t)nsectors << SECTOR_SHIFT;
    if (maplen > (uint64_t)st.st_size)
	maplen = st.st_size;

    fm->fm_start        = 0;
    fm->fm_length       = maplen;
    fm->fm_flags        = FIEMAP_FLAG_SYNC;
    fm->fm_extent_count = nsectors;

    if (ioctl(fd, FS_IOC_FIEMAP, fm))
	return -1;

    memset(sectors, 0, nsectors * sizeof *sectors);
    esec = sectors + nsectors;

    fe = fm->fm_extents;

    if (fm->fm_mapped_extents < 1 ||
	!(fe[fm->fm_mapped_extents-1].fe_flags & FIEMAP_EXTENT_LAST))
	return -1;

    for (i = 0; i < fm->fm_mapped_extents; i++) {
	if (fe->fe_flags & FIEMAP_EXTENT_LAST) {
	    /* If this is the *final* extent, pad the length */
	    fe->fe_length = (fe->fe_length + SECTOR_SIZE - 1)
		& ~(SECTOR_SIZE - 1);
	}

	if ((fe->fe_logical | fe->fe_physical| fe->fe_length) &
	    (SECTOR_SIZE - 1))
	    return -1;

	if (fe->fe_flags & (FIEMAP_EXTENT_UNKNOWN|
			    FIEMAP_EXTENT_DELALLOC|
			    FIEMAP_EXTENT_ENCODED|
			    FIEMAP_EXTENT_DATA_ENCRYPTED|
			    FIEMAP_EXTENT_UNWRITTEN))
	    return -1;

	secp = sectors + (fe->fe_logical >> SECTOR_SHIFT);
	sec  = fe->fe_physical >> SECTOR_SHIFT;
	nsec = fe->fe_length >> SECTOR_SHIFT;

	while (nsec--) {
	    if (secp >= esec)
		break;
	    *secp++ = sec++;
	}

	fe++;
    }

    return 0;
}

/* Legacy FIBMAP based mapping */
static int sectmap_fib(int fd, sector_t *sectors, int nsectors)
{
    unsigned int blk, nblk;
    unsigned int i;
    unsigned int blksize;
    sector_t sec;

    /* Get block size */
    if (ioctl(fd, FIGETBSZ, &blksize))
	return -1;

    /* Number of sectors per block */
    blksize >>= SECTOR_SHIFT;

    nblk = 0;
    while (nsectors) {
	blk = nblk++;
	if (ioctl(fd, FIBMAP, &blk))
	    return -1;

	sec = (sector_t)blk * blksize;
	for (i = 0; i < blksize; i++) {
	    *sectors++ = sec++;
	    if (! --nsectors)
		break;
	}
    }

    return 0;
}

/*
 * Produce file map
 */
int sectmap(int fd, sector_t *sectors, int nsectors)
{
    if (!sectmap_fie(fd, sectors, nsectors))
	return 0;

    return sectmap_fib(fd, sectors, nsectors);
}

/*
 * SYSLINUX installs the string 'SYSLINUX' at offset 3 in the boot
 * sector; this is consistent with FAT filesystems.  Earlier versions
 * would install the string "EXTLINUX" instead, handle both.
 */
int syslinux_already_installed(int dev_fd)
{
    char buffer[8];

    xpread(dev_fd, buffer, 8, 3);
    return !memcmp(buffer, "SYSLINUX", 8) || !memcmp(buffer, "EXTLINUX", 8);
}
