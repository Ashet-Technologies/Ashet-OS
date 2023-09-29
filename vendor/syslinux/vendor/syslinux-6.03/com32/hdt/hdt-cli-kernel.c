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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

#include "hdt-cli.h"
#include "hdt-common.h"

void main_show_kernel(int argc __unused, char **argv __unused,
		      struct s_hardware *hardware)
{
    char buffer[1024] = {0};
    struct pci_device *pci_device;
    bool found = false;
    char kernel_modules[LINUX_KERNEL_MODULE_SIZE *
			MAX_KERNEL_MODULES_PER_PCI_DEVICE];

    reset_more_printf();
    more_printf("Kernel modules\n");

// more_printf(" PCI device no: %d \n", p->pci_device_pos);

    if ((hardware->modules_pcimap_return_code == -ENOMODULESPCIMAP)
	&& (hardware->modules_alias_return_code == -ENOMODULESALIAS)) {
	more_printf(" modules.pcimap and modules.alias files are missing\n");
	return;
    }

    /* For every detected pci device, compute its submenu */
    for_each_pci_func(pci_device, hardware->pci_domain) {
	memset(kernel_modules, 0, sizeof kernel_modules);

	for (int kmod = 0;
	     kmod < pci_device->dev_info->linux_kernel_module_count; kmod++) {
	    if (kmod > 0) {
		strncat(kernel_modules, " | ", 3);
	    }
	    strncat(kernel_modules,
		    pci_device->dev_info->linux_kernel_module[kmod],
		    LINUX_KERNEL_MODULE_SIZE - 1);
	}

	if ((pci_device->dev_info->linux_kernel_module_count > 0)
	    && (!strstr(buffer, kernel_modules))) {
	    found = true;
	    if (pci_device->dev_info->linux_kernel_module_count > 1)
		strncat(buffer, "(", 1);
	    strncat(buffer, kernel_modules, sizeof(kernel_modules));
	    if (pci_device->dev_info->linux_kernel_module_count > 1)
		strncat(buffer, ")", 1);
	    strncat(buffer, " # ", 3);
	}

    }
    if (found == true) {
	strncat(buffer, "\n", 1);
	more_printf("%s", buffer);
    }
}

static void show_kernel_modules(int argc __unused, char **argv __unused,
				struct s_hardware *hardware)
{
    struct pci_device *pci_device;
    char kernel_modules[LINUX_KERNEL_MODULE_SIZE *
			MAX_KERNEL_MODULES_PER_PCI_DEVICE];
    char modules[MAX_PCI_CLASSES][256] = {{0}};
    char category_name[MAX_PCI_CLASSES][256] = {{0}};

    if (hardware->pci_ids_return_code == -ENOPCIIDS) {
	more_printf(" Missing pci.ids, we can't compute the list\n");
	return;
    }

    if (hardware->modules_pcimap_return_code == -ENOMODULESPCIMAP) {
	more_printf(" Missing modules.pcimap, we can't compute the list\n");
	return;
    }

    reset_more_printf();
    for_each_pci_func(pci_device, hardware->pci_domain) {
	memset(kernel_modules, 0, sizeof kernel_modules);

	for (int kmod = 0;
	     kmod < pci_device->dev_info->linux_kernel_module_count; kmod++) {
	    strncat(kernel_modules,
		    pci_device->dev_info->linux_kernel_module[kmod],
		    LINUX_KERNEL_MODULE_SIZE - 1);
	    strncat(kernel_modules, " ", 1);
	}

	if ((pci_device->dev_info->linux_kernel_module_count > 0)
	    && (!strstr(modules[pci_device->class[2]], kernel_modules))) {
	    strncat(modules[pci_device->class[2]], kernel_modules,
		    sizeof(kernel_modules));
	    snprintf(category_name[pci_device->class[2]],
		     sizeof(category_name[pci_device->class[2]]),
		     "%s", pci_device->dev_info->category_name);
	}
    }
    /* Print the found items */
    for (int i = 0; i < MAX_PCI_CLASSES; i++) {
	if (strlen(category_name[i]) > 1) {
	    more_printf("%s : %s\n", category_name[i], modules[i]);
	}
    }
}

struct cli_module_descr kernel_show_modules = {
    .modules = NULL,
    .default_callback = show_kernel_modules,
};

struct cli_mode_descr kernel_mode = {
    .mode = KERNEL_MODE,
    .name = CLI_KERNEL,
    .default_modules = NULL,
    .show_modules = &kernel_show_modules,
    .set_modules = NULL,
};
