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

/* Main Kernel menu */
void compute_kernel(struct s_my_menu *menu, struct s_hardware *hardware)
{
    char buffer[SUBMENULEN + 1];
    char infobar[STATLEN + 1];
    char kernel_modules[LINUX_KERNEL_MODULE_SIZE *
			MAX_KERNEL_MODULES_PER_PCI_DEVICE];
    struct pci_device *pci_device;

    menu->menu = add_menu(" Kernel Modules ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    if ((hardware->modules_pcimap_return_code == -ENOMODULESPCIMAP) &&
	(hardware->modules_alias_return_code == -ENOMODULESALIAS)) {
	add_item("The modules.{pcimap|alias} file is missing",
		 "Missing modules.{pcimap|alias} file", OPT_INACTIVE, NULL, 0);
	add_item("Kernel modules can't be computed.",
		 "Missing modules.{pcimap|alias} file", OPT_INACTIVE, NULL, 0);
	add_item("Please put one of them in same dir as hdt",
		 "Missing modules.{pcimap|alias} file", OPT_INACTIVE, NULL, 0);
	add_item("", "", OPT_SEP, "", 0);
    } else {
	/*
	 * For every detected pci device, grab its kernel module to
	 * compute this submenu
	 */
	for_each_pci_func(pci_device, hardware->pci_domain) {
	    memset(kernel_modules, 0, sizeof kernel_modules);
	    for (int i = 0;
		 i < pci_device->dev_info->linux_kernel_module_count; i++) {
		if (i > 0) {
		    strncat(kernel_modules, " | ", 3);
		}
		strncat(kernel_modules,
			pci_device->dev_info->linux_kernel_module[i],
			LINUX_KERNEL_MODULE_SIZE - 1);
	    }
	    /* No need to add unknown kernel modules */
	    if (strlen(kernel_modules) > 0) {
		snprintf(buffer, sizeof buffer, "%s (%s)",
			 kernel_modules, pci_device->dev_info->class_name);
		snprintf(infobar, sizeof infobar,
			 "%04x:%04x %s : %s",
			 pci_device->vendor,
			 pci_device->product,
			 pci_device->dev_info->vendor_name,
			 pci_device->dev_info->product_name);

		add_item(buffer, infobar, OPT_INACTIVE, NULL, 0);
		menu->items_count++;
	    }
	}
    }

    printf("MENU: Kernel menu done (%d items)\n", menu->items_count);
}
