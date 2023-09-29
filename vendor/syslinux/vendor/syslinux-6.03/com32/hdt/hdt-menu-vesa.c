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

#include "hdt-menu.h"

/* Submenu for the vesa card */
static void compute_vesa_card(struct s_my_menu *menu,
			      struct s_hardware *hardware)
{
    char buffer[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];

    menu->menu = add_menu(" VESA Bios ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    snprintf(buffer, sizeof buffer, "VESA Version: %d.%d",
	     hardware->vesa.major_version, hardware->vesa.minor_version);
    snprintf(statbuffer, sizeof statbuffer, "Version: %d.%d",
	     hardware->vesa.major_version, hardware->vesa.minor_version);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Vendor      : %s", hardware->vesa.vendor);
    snprintf(statbuffer, sizeof statbuffer, "Vendor Name: %s",
	     hardware->vesa.vendor);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Product     : %s", hardware->vesa.product);
    snprintf(statbuffer, sizeof statbuffer, "Product Name: %s",
	     hardware->vesa.product);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Product Rev.: %s",
	     hardware->vesa.product_revision);
    snprintf(statbuffer, sizeof statbuffer, "Produt Revision: %s",
	     hardware->vesa.product_revision);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Software Rev: %d",
	     hardware->vesa.software_rev);
    snprintf(statbuffer, sizeof statbuffer, "Software Revision: %d",
	     hardware->vesa.software_rev);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Memory (KB) : %d",
	     hardware->vesa.total_memory * 64);
    snprintf(statbuffer, sizeof statbuffer, "Memory (KB): %d",
	     hardware->vesa.total_memory * 64);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;
}

/* Submenu for the vesa card */
void compute_vesa_modes(struct s_my_menu *menu, struct s_hardware *hardware)
{
    char buffer[56];
    char statbuffer[STATLEN];

    menu->menu = add_menu(" VESA Modes ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);
    for (int i = 0; i < hardware->vesa.vmi_count; i++) {
	struct vesa_mode_info *mi = &hardware->vesa.vmi[i].mi;
	/* Sometimes, vesa bios reports 0x0 modes
	 * We don't need to display that ones */
	if ((mi->h_res == 0) || (mi->v_res == 0))
	    continue;
	snprintf(buffer, sizeof buffer, "%4u x %4u x %2ubits vga=%3d",
		 mi->h_res, mi->v_res, mi->bpp,
		 hardware->vesa.vmi[i].mode + 0x200);
	snprintf(statbuffer, sizeof statbuffer, "%4ux%4ux%2ubits vga=%3d",
		 mi->h_res, mi->v_res, mi->bpp,
		 hardware->vesa.vmi[i].mode + 0x200);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }
}

/* Main VESA Menu*/
int compute_VESA(struct s_hdt_menu *hdt_menu, struct s_hardware *hardware)
{
    char buffer[15];
    compute_vesa_card(&hdt_menu->vesa_card_menu, hardware);
    compute_vesa_modes(&hdt_menu->vesa_modes_menu, hardware);
    hdt_menu->vesa_menu.menu = add_menu(" VESA ", -1);
    hdt_menu->vesa_menu.items_count = 0;

    add_item("VESA Bios", "VESA Bios", OPT_SUBMENU, NULL,
	     hdt_menu->vesa_card_menu.menu);
    hdt_menu->vesa_menu.items_count++;
    snprintf(buffer, sizeof buffer, "%s (%d)", "Modes",
	     hardware->vesa.vmi_count);
    add_item(buffer, "VESA Modes", OPT_SUBMENU, NULL,
	     hdt_menu->vesa_modes_menu.menu);
    hdt_menu->vesa_menu.items_count++;
    printf("MENU: VESA menu done (%d items)\n",
	   hdt_menu->vesa_menu.items_count);
    return 0;
}
