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

#include "hdt-menu.h"

/**
 * compute_vpd - generate vpd menu
 **/
void compute_vpd(struct s_my_menu *menu, struct s_hardware *hardware)
{
    char buffer[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];	/* Status bar */

    menu->menu = add_menu(" VPD ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    snprintf(buffer, sizeof buffer, "Address                  : %s",
	     hardware->vpd.base_address);
    snprintf(statbuffer, sizeof statbuffer, "Address: %s",
	     hardware->cpu.vendor);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    if (strlen(hardware->vpd.bios_build_id) > 0) {
	snprintf(buffer, sizeof buffer, "Bios Build ID            : %s",
		 hardware->vpd.bios_build_id);
	snprintf(statbuffer, sizeof statbuffer, "Bios Build ID: %s",
		 hardware->vpd.bios_build_id);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }

    if (strlen(hardware->vpd.bios_release_date) > 0) {
	snprintf(buffer, sizeof buffer, "Bios Release Date        : %s",
		 hardware->vpd.bios_release_date);
	snprintf(statbuffer, sizeof statbuffer, "Bios Release Date: %s",
		 hardware->vpd.bios_release_date);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }

    if (strlen(hardware->vpd.bios_version) > 0) {
	snprintf(buffer, sizeof buffer, "Bios Version             : %s",
		 hardware->vpd.bios_version);
	snprintf(statbuffer, sizeof statbuffer, "Bios Version: %s",
		 hardware->vpd.bios_version);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }

    if (strlen(hardware->vpd.default_flash_filename) > 0) {
	snprintf(buffer, sizeof buffer, "Default Flash Filename   : %s",
		 hardware->vpd.default_flash_filename);
	snprintf(statbuffer, sizeof statbuffer, "Default Flash Filename: %s",
		 hardware->vpd.default_flash_filename);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }

    if (strlen(hardware->vpd.box_serial_number) > 0) {
	snprintf(buffer, sizeof buffer, "Box Serial Number        : %s",
		 hardware->vpd.box_serial_number);
	snprintf(statbuffer, sizeof statbuffer, "Box Serial Number: %s",
		 hardware->vpd.box_serial_number);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }

    if (strlen(hardware->vpd.motherboard_serial_number) > 0) {
	snprintf(buffer, sizeof buffer, "Motherboard Serial Number: %s",
		 hardware->vpd.motherboard_serial_number);
	snprintf(statbuffer, sizeof statbuffer, "Motherboard Serial Number: %s",
		 hardware->vpd.motherboard_serial_number);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }

    if (strlen(hardware->vpd.machine_type_model) > 0) {
	snprintf(buffer, sizeof buffer, "Machine Type/Model       : %s",
		 hardware->vpd.machine_type_model);
	snprintf(statbuffer, sizeof statbuffer, "Machine Type/Model: %s",
		 hardware->vpd.machine_type_model);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }

    printf("MENU: VPD menu done (%d items)\n", menu->items_count);
}
