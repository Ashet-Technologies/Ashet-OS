/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer
 *
 *   This file is part of Syslinux, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

#include <disk/bootloaders.h>
#include <disk/common.h>
#include <disk/geom.h>
#include <disk/read.h>
#include <stdlib.h>
#include <string.h>

/**
 * get_bootloader_string - return a string describing the boot code in a
 *			   bootsector
 * @d:			driveinfo struct describing the drive
 * @p:	partition to scan (usually the active one)
 * @buffer:		pre-allocated buffer
 * @buffer_size:	@buffer size
 **/
int get_bootloader_string(struct driveinfo *d, const struct part_entry *p,
			  char *buffer, const int buffer_size)
{
    char boot_sector[SECTOR * sizeof(char)];

    if (read_sectors(d, &boot_sector, p->start_lba, 1) == -1)
	return -1;
    else {
	if (!strncmp(boot_sector + 3, "SYSLINUX", 8))
	    strlcpy(buffer, "SYSLINUX", buffer_size - 1);
	else if (!strncmp(boot_sector + 3, "EXTLINUX", 8))
	    strlcpy(buffer, "EXTLINUX", buffer_size - 1);
	else if (!strncmp(boot_sector + 3, "MSWIN4.1", 8))
	    strlcpy(buffer, "MSWIN4.1", buffer_size - 1);
	else
	    return -1;
	/* Add more... */

	buffer[buffer_size - 1] = '\0';
	return 0;
    }
}
