/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Erwan Velu - All Rights Reserved
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

#include <stdlib.h>

#include "hdt-menu.h"
#include "hdt-util.h"

static int dn;

static void show_partition_information(struct driveinfo *drive_info,
				       struct part_entry *ptab __unused,
				       int partition_offset __unused,
				       int nb_partitions_seen)
{
    char menu_title[MENULEN + 1];
    char menu_title_ref[MENULEN + 1];

    if (nb_partitions_seen == 1)
	add_sep();

    memset(menu_title, 0, sizeof menu_title);
    memset(menu_title_ref, 0, sizeof menu_title_ref);
    snprintf(menu_title_ref, sizeof menu_title_ref, "disk_%x_part_%d",
	     drive_info[dn].disk, nb_partitions_seen);
    snprintf(menu_title, sizeof menu_title, "Partition %d", nb_partitions_seen);

    add_item(menu_title,
	     "Partition information (start, end, length, type, ...)",
	     OPT_SUBMENU, menu_title_ref, 0);
}

/**
 * compute_partition_information - print information about a partition
 * @ptab:       part_entry describing the partition
 * @i:          Partition number (UI purposes only)
 * @ptab_root:  part_entry describing the root partition (extended only)
 * @drive_info: driveinfo struct describing the drive on which the partition
 *              is
 *
 * Note on offsets (from hpa, see chain.c32):
 *
 *  To make things extra confusing: data partition offsets are relative to where
 *  the data partition record is stored, whereas extended partition offsets
 *  are relative to the beginning of the extended partition all the way back
 *  at the MBR... but still not absolute!
 **/
static void compute_partition_information(struct driveinfo *drive_info,
					  struct part_entry *ptab,
					  int partition_offset,
					  int nb_partitions_seen)
{
    char size[11];
    char bootloader_name[9];
    char *parttype;
    unsigned int start, end;
    char buffer[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];
    char menu_title[MENULEN + 1];
    char menu_title_ref[MENULEN + 1];

    memset(buffer, 0, sizeof buffer);
    memset(statbuffer, 0, sizeof statbuffer);
    memset(menu_title, 0, sizeof menu_title);
    memset(menu_title_ref, 0, sizeof menu_title_ref);
    snprintf(menu_title_ref, sizeof menu_title_ref, "disk_%x_part_%d",
	     drive_info[dn].disk, nb_partitions_seen);
    snprintf(menu_title, sizeof menu_title, "Partition %d", nb_partitions_seen);

    add_named_menu(menu_title_ref, menu_title, -1);
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    start = partition_offset;
    end = start + ptab->length - 1;

    if (ptab->length > 0)
	sectors_to_size(ptab->length, size);
    else
	memset(size, 0, sizeof size);

    get_label(ptab->ostype, &parttype);

    snprintf(buffer, sizeof buffer, "Size        : %s", remove_spaces(size));
    snprintf(statbuffer, sizeof statbuffer, "Size : %s", remove_spaces(size));
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);

    snprintf(buffer, sizeof buffer, "Type        : %s", parttype);
    snprintf(statbuffer, sizeof statbuffer, "Type: %s", parttype);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);

    if (get_bootloader_string(drive_info, ptab, bootloader_name, 9) == 0) {
	snprintf(buffer, sizeof buffer, "Bootloader  : %s", bootloader_name);
	snprintf(statbuffer, sizeof statbuffer, "Bootloader: %s",
		 bootloader_name);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    }

    snprintf(buffer, sizeof buffer, "Boot Flag   : %s",
	     (ptab->active_flag == 0x80) ? "Yes" : "No");
    snprintf(statbuffer, sizeof statbuffer, "Boot Flag: %s",
	     (ptab->active_flag == 0x80) ? "Yes" : "No");
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);

    snprintf(buffer, sizeof buffer, "Start       : %d", start);
    snprintf(statbuffer, sizeof statbuffer, "Start: %d", start);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);

    snprintf(buffer, sizeof buffer, "End         : %d", end);
    snprintf(statbuffer, sizeof statbuffer, "End: %d", end);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);

    snprintf(buffer, sizeof buffer, "Id          : %X", ptab->ostype);
    snprintf(statbuffer, sizeof statbuffer, "Id: %X", ptab->ostype);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);

    free(parttype);

    /* Extra info */
    if (ptab->ostype == 0x82 && swsusp_check(drive_info, ptab) != -1) {
	snprintf(buffer, sizeof buffer, "%s", "Swsusp sig  : detected");
	snprintf(statbuffer, sizeof statbuffer, "%s", "Swsusp sig  : detected");
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    }
}

/* Compute the disk submenu */
static int compute_disk_module(struct s_my_menu *menu, int nb_sub_disk_menu,
			       const struct s_hardware *hardware,
			       int disk_number)
{
    char buffer[MENULEN + 1];
    char statbuffer[STATLEN + 1];
    char mbr_name[50];
    struct driveinfo *d = (struct driveinfo *)hardware->disk_info;

    snprintf(buffer, sizeof buffer, " Disk <0x%X> (EDD %X)",
	     d[disk_number].disk, d[disk_number].edd_version);
    menu[nb_sub_disk_menu].menu = add_menu(buffer, -1);
    menu[nb_sub_disk_menu].items_count = 0;

    int previous_size, size;
    char previous_unit[3], unit[3];	// GB
    char size_iec[11];		// GiB
    char size_dec[11];		// GB
    sectors_to_size_dec(previous_unit, &previous_size, unit, &size,
			d[disk_number].edd_params.sectors);
    sectors_to_size(d[disk_number].edd_params.sectors, size_iec);
    sectors_to_size_dec2(d[disk_number].edd_params.sectors, size_dec);

    snprintf(buffer, sizeof buffer, "Size              : %s/%s (%d %s)",
	     remove_spaces(size_iec), remove_spaces(size_dec), previous_size,
	     previous_unit);
    snprintf(statbuffer, sizeof statbuffer, "Size: %s/%s (%d %s)",
	     remove_spaces(size_iec), remove_spaces(size_dec), previous_size,
	     previous_unit);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu[nb_sub_disk_menu].items_count++;

    /* Do not print Host Bus & Interface if EDD isn't 3.0 or more */
    if (d[disk_number].edd_version >= 0x30) {
	snprintf(buffer, sizeof buffer, "Host Bus/Interface: %s / %s",
		 remove_spaces((char *)d[disk_number].edd_params.host_bus_type),
		 d[disk_number].edd_params.interface_type);
	snprintf(statbuffer, sizeof statbuffer, "Host Bus / Interface: %s / %s",
		 remove_spaces((char *)d[disk_number].edd_params.host_bus_type),
		 d[disk_number].edd_params.interface_type);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu[nb_sub_disk_menu].items_count++;
    }

    snprintf(buffer, sizeof buffer, "C / H / S         : %d / %d / %d",
	     d[disk_number].legacy_max_cylinder + 1,
	     d[disk_number].legacy_max_head + 1,
	     (int)d[disk_number].edd_params.sectors);
    snprintf(statbuffer, sizeof statbuffer,
	     "Cylinders / Heads / Sectors: %d / %d / %d",
	     d[disk_number].legacy_max_cylinder + 1,
	     d[disk_number].legacy_max_head + 1,
	     (int)d[disk_number].edd_params.sectors);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu[nb_sub_disk_menu].items_count++;

    snprintf(buffer, sizeof buffer, "Sectors/Track     : %d",
	     d[disk_number].legacy_sectors_per_track);
    snprintf(statbuffer, sizeof statbuffer, "Sectors per Track: %d",
	     d[disk_number].legacy_sectors_per_track);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu[nb_sub_disk_menu].items_count++;

    get_mbr_string(hardware->mbr_ids[disk_number], &mbr_name, 50);

    snprintf(buffer, sizeof buffer, "MBR               : %s (0x%X)",
	     remove_spaces(mbr_name), hardware->mbr_ids[disk_number]);
    snprintf(statbuffer, sizeof statbuffer, "MBR: %s (id 0x%X)",
	     remove_spaces(mbr_name), hardware->mbr_ids[disk_number]);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu[nb_sub_disk_menu].items_count++;

    dn = disk_number;

    parse_partition_table(&d[disk_number], &show_partition_information);
    if (!parse_partition_table(&d[disk_number], &compute_partition_information)) {
	get_error("parse_partition_table");
	menu[nb_sub_disk_menu].items_count++;
    }

    return 0;
}

/* Compute the Disks menu */
void compute_disks(struct s_hdt_menu *menu, struct s_hardware *hardware)
{
    char buffer[MENULEN + 1];
    int nb_sub_disk_menu = 0;

    /* No need to compute that menu if no disks were detected */
    menu->disk_menu.items_count = 0;
    if (hardware->disks_count == 0)
	return;

    for (int drive = 0x80; drive < 0xff; drive++) {
	if (!hardware->disk_info[drive - 0x80].cbios)
	    continue;		/* Invalid geometry */
	compute_disk_module
	    ((struct s_my_menu *)&(menu->disk_sub_menu), nb_sub_disk_menu,
	     hardware, drive - 0x80);
	nb_sub_disk_menu++;
    }

    menu->disk_menu.menu = add_menu(" Disks ", -1);

    for (int i = 0; i < nb_sub_disk_menu; i++) {
	snprintf(buffer, sizeof buffer, " Disk <%d> ", i + 1);
	add_item(buffer, "Disk", OPT_SUBMENU, NULL,
		 menu->disk_sub_menu[i].menu);
	menu->disk_menu.items_count++;
    }
    printf("MENU: Disks menu done (%d items)\n", menu->disk_menu.items_count);
}
