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
#include <sys/gpxe.h>

/* Main Kernel menu */
void compute_PXE(struct s_my_menu *menu, struct s_hardware *hardware)
{
    char buffer[SUBMENULEN + 1];
    char infobar[STATLEN + 1];
    char gpxe[4]={0};

    if (hardware->is_pxe_valid == false)
	return;

    menu->menu = add_menu(" PXE ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    struct s_pxe *p = &hardware->pxe;

    if ((hardware->pci_ids_return_code == -ENOPCIIDS)
	|| (p->pci_device == NULL)) {
	snprintf(buffer, sizeof buffer, "PCI Vendor    : %d", p->vendor_id);
	snprintf(infobar, sizeof infobar, "PCI Vendor    : %d", p->vendor_id);
	add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer, "PCI Product   : %d", p->vendor_id);
	snprintf(infobar, sizeof infobar, "PCI Product   : %d", p->vendor_id);
	add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer, "PCI SubVendor  : %d", p->subvendor_id);
	snprintf(infobar, sizeof infobar, "PCI SubVendor  : %d",
		 p->subvendor_id);
	add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer, "PCI SubProduct : %d",
		 p->subproduct_id);
	snprintf(infobar, sizeof infobar, "PCI SubProduct : %d",
		 p->subproduct_id);
	add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer, "PCI Revision   : %d", p->rev);
	snprintf(infobar, sizeof infobar, "PCI Revision   : %d", p->rev);
	add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer,
		 "PCI Bus Pos.   : %02x:%02x.%02x", p->pci_bus,
		 p->pci_dev, p->pci_func);
	snprintf(infobar, sizeof infobar,
		 "PCI Bus Pos.   : %02x:%02x.%02x", p->pci_bus,
		 p->pci_dev, p->pci_func);
	add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

    } else {

	snprintf(buffer, sizeof buffer, "Manufacturer : %s",
		 p->pci_device->dev_info->vendor_name);
	snprintf(infobar, sizeof infobar, "Manufacturer : %s",
		 p->pci_device->dev_info->vendor_name);
	add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer, "Product      : %s",
		 p->pci_device->dev_info->product_name);
	snprintf(infobar, sizeof infobar, "Product      : %s",
		 p->pci_device->dev_info->product_name);
	add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }

    snprintf(buffer, sizeof buffer, "MAC Address  : %s", p->mac_addr);
    snprintf(infobar, sizeof infobar, "MAC Address  : %s", p->mac_addr);
    add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "IP Address   : %d.%d.%d.%d",
	     p->ip_addr[0], p->ip_addr[1], p->ip_addr[2], p->ip_addr[3]);
    snprintf(infobar, sizeof infobar, "IP Address   : %d.%d.%d.%d",
	     p->ip_addr[0], p->ip_addr[1], p->ip_addr[2], p->ip_addr[3]);
    add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    if (is_gpxe()) snprintf(gpxe,sizeof(gpxe),"%s","Yes");
    else snprintf (gpxe, sizeof(gpxe), "%s", "No");

    snprintf(buffer, sizeof buffer, "gPXE Detected: %s", gpxe);
    snprintf(infobar, sizeof infobar, "gPXE Detected: %s", gpxe);
    add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    printf("MENU: PXE menu done (%d items)\n", menu->items_count);
}
