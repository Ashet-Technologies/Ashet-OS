/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * -----------------------------------------------------------------------
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

#include "hdt-cli.h"
#include "hdt-common.h"
#include "hdt-util.h"

/**
 * show_partition_information - print information about a partition
 * @ptab:	part_entry describing the partition
 * @i:		Partition number (UI purposes only)
 * @ptab_root:	part_entry describing the root partition (extended only)
 * @drive_info:	driveinfo struct describing the drive on which the partition
 *		is
 *
 * Note on offsets (from hpa, see chain.c32):
 *
 *  To make things extra confusing: data partition offsets are relative to where
 *  the data partition record is stored, whereas extended partition offsets
 *  are relative to the beginning of the extended partition all the way back
 *  at the MBR... but still not absolute!
 **/
static void show_partition_information(struct driveinfo *drive_info,
				       struct part_entry *ptab,
				       int partition_offset,
				       int nb_partitions_seen)
{
    char size[11];
    char bootloader_name[9];
    char *parttype;
    unsigned int start, end;

    int i = nb_partitions_seen;

    reset_more_printf();

    start = partition_offset;
    end = start + ptab->length - 1;

    if (ptab->length > 0)
	sectors_to_size(ptab->length, size);
    else
	memset(size, 0, sizeof size);

    if (i == 1)
	more_printf(" #  B       Start         End    Size Id Type\n");

    get_label(ptab->ostype, &parttype);
    more_printf("%2d  %s %11d %11d %s %02X %s",
		i, (ptab->active_flag == 0x80) ? "x" : " ",
		start, end, size, ptab->ostype, parttype);

    /* Extra info */
    if (ptab->ostype == 0x82 && swsusp_check(drive_info, ptab))
	more_printf("%s", " (Swsusp sig. detected)");

    if (get_bootloader_string(drive_info, ptab, bootloader_name, 9) == 0)
	more_printf("%-46s %s %s", " ", "Bootloader:", bootloader_name);

    more_printf("\n");

    free(parttype);
}

void main_show_disk(int argc, char **argv, struct s_hardware *hardware)
{
    if (!argc) {
	more_printf("Which disk?\n");
	return;
    }

    int drive = strtol(argv[0], (char **)NULL, 16);

    if (drive < 0x80 || drive >= 0xff) {
	more_printf("Invalid disk: %d.\n", drive);
	return;
    }

    int i = drive - 0x80;
    struct driveinfo *d = &hardware->disk_info[i];
    char disk_size[11];
    char mbr_name[50];

    reset_more_printf();

    if (!hardware->disk_info[i].cbios) {
	more_printf("No disk found\n");
	return;			/* Invalid geometry */
    }

    get_mbr_string(hardware->mbr_ids[i], &mbr_name, 50);

    if ((int)d->edd_params.sectors > 0)
	sectors_to_size((int)d->edd_params.sectors, disk_size);
    else
	memset(disk_size, 0, sizeof disk_size);

    more_printf("DISK 0x%X:\n"
		"  C/H/S: %d cylinders, %d heads, %d sectors/track\n"
		"    EDD: Version: %X\n"
		"         Size: %s, %d bytes/sector, %d sectors/track\n"
		"         Host bus: %s, Interface type: %s\n"
		"    MBR: %s (id 0x%X)\n\n",
		d->disk,
		d->legacy_max_cylinder + 1, d->legacy_max_head + 1,
		d->legacy_sectors_per_track, d->edd_version, disk_size,
		(int)d->edd_params.bytes_per_sector,
		(int)d->edd_params.sectors_per_track,
		remove_spaces((char *)d->edd_params.host_bus_type),
		remove_spaces((char *)d->edd_params.interface_type), mbr_name,
		hardware->mbr_ids[i]);
    display_line_nb += 6;

    if (parse_partition_table(d, &show_partition_information)) {
	if (errno_disk) {
	    fprintf(stderr, "I/O error parsing disk 0x%X\n", d->disk);
	    get_error("parse_partition_table");
	} else {
	    fprintf(stderr, "Disk 0x%X: unrecognized partition layout\n",
		    d->disk);
	}
	fprintf(stderr, "\n");
    }

    more_printf("\n");
}

void main_show_disks(int argc __unused, char **argv __unused,
		     struct s_hardware *hardware)
{
    bool found = false;
    reset_more_printf();

    int first_one = 0;
    for (int drive = 0x80; drive < 0xff; drive++) {
	if (hardware->disk_info[drive - 0x80].cbios) {
	    found = true;
	    if (!first_one) {
		first_one = 1;
	    } else {
		pause_printf();
	    }
	    char buf[5] = "";
	    sprintf(buf, "0x%x", drive);
	    char *argv[1] = { buf };
	    main_show_disk(1, argv, hardware);
	}
    }

    if (found == false)
	more_printf("No disk found\n");
}

void disks_summary(int argc __unused, char **argv __unused,
		   struct s_hardware *hardware)
{
    int i = -1;
    bool found = false;

    reset_more_printf();

    for (int drive = 0x80; drive < 0xff; drive++) {
	i++;
	if (!hardware->disk_info[i].cbios)
	    continue;		/* Invalid geometry */

	found = true;
	struct driveinfo *d = &hardware->disk_info[i];
	char disk_size[11];

	if ((int)d->edd_params.sectors > 0)
	    sectors_to_size((int)d->edd_params.sectors, disk_size);
	else
	    memset(disk_size, 0, sizeof disk_size);

	more_printf("DISK 0x%X:\n", d->disk);
	more_printf("  C/H/S: %d cylinders, %d heads, %d sectors/track\n",
		    d->legacy_max_cylinder + 1, d->legacy_max_head + 1,
		    d->legacy_sectors_per_track);
	more_printf("  EDD:   Version: %X, size: %s\n", d->edd_version,
		    disk_size);

	/* Do not print Host Bus & Interface if EDD isn't 3.0 or more */
	if (d->edd_version >= 0x30)
	    more_printf("         Host bus: %s, Interface type: %s\n\n",
			remove_spaces((char *)d->edd_params.host_bus_type),
			remove_spaces((char *)d->edd_params.interface_type));
    }

    if (found == false)
	more_printf("No disk found\n");
}

struct cli_callback_descr list_disk_show_modules[] = {
    {
     .name = "disks",
     .exec = main_show_disks,
     .nomodule = false,
     },
    {
     .name = "disk",
     .exec = main_show_disk,
     .nomodule = false,
     },
    {
     .name = NULL,
     .exec = NULL,
     .nomodule = false,
     },
};

struct cli_module_descr disk_show_modules = {
    .modules = list_disk_show_modules,
    .default_callback = disks_summary,
};

struct cli_mode_descr disk_mode = {
    .mode = DISK_MODE,
    .name = CLI_DISK,
    .default_modules = NULL,
    .show_modules = &disk_show_modules,
    .set_modules = NULL,
};
