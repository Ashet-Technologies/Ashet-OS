/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdio.h>
#include <console.h>
#include <stdlib.h>
#include <string.h>
#include <disk/geom.h>
#include <disk/util.h>
#include <disk/errno_disk.h>
#include <disk/error.h>

int main(int argc, char *argv[])
{
	struct driveinfo drive;
	struct driveinfo *d = &drive;

	(void)argc;
	(void)argv;

	for (int disk = 0x80; disk < 0xff; disk++) {
		memset(d, 0, sizeof(struct driveinfo));
		d->disk = disk;
		get_drive_parameters(d);

		/* Do not print output when drive does not exists */
		if (errno_disk == -1 || !d->cbios)
			continue;

		if (errno_disk) {
			get_error("reading disk");
			continue;
		}

		printf("DISK 0x%X:\n", d->disk);
		printf("  C/H/S: %d heads, %d cylinders\n",
			d->legacy_max_head + 1, d->legacy_max_cylinder + 1);
		printf("         %d sectors/track, %d drives\n",
			d->legacy_sectors_per_track, d->legacy_max_drive);
		printf("  EDD:   ebios=%d, EDD version: %X\n",
			d->ebios, d->edd_version);
		printf("         %d heads, %d cylinders\n",
			(int) d->edd_params.heads, (int) d->edd_params.cylinders);
		printf("         %d sectors, %d bytes/sector, %d sectors/track\n",
			(int) d->edd_params.sectors, (int) d->edd_params.bytes_per_sector,
			(int) d->edd_params.sectors_per_track);
		printf("         Host bus: %s, Interface type: %s\n\n",
			d->edd_params.host_bus_type, d->edd_params.interface_type);
	}
	return 0;
}
