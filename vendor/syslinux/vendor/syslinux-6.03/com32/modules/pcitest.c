/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2006 Erwan Velu - All Rights Reserved
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

/*
 * pcitest.c
 *
 */

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <console.h>
#include <com32.h>
#include <sys/pci.h>
#include <stdbool.h>
#include <dprintf.h>

char display_line = 0;
#define moreprintf(...)				\
  do {						\
    display_line++;				\
    if (display_line == 24) {			\
      char tempbuf[10];				\
      display_line=0;				\
      printf("Press Enter to continue\n");	\
      fgets(tempbuf, sizeof tempbuf, stdin);	\
    }						\
    printf ( __VA_ARGS__);			\
  } while (0);

void display_pci_devices(struct pci_domain *pci_domain)
{
    struct pci_device *pci_device;
    char kernel_modules[LINUX_KERNEL_MODULE_SIZE *
			MAX_KERNEL_MODULES_PER_PCI_DEVICE];

    for_each_pci_func(pci_device, pci_domain) {

	memset(kernel_modules, 0, sizeof kernel_modules);

/*	printf("PCI: found %d kernel modules for  %04x:%04x[%04x:%04x]\n",
		  pci_device->dev_info->linux_kernel_module_count,
		  pci_device->vendor, pci_device->product,
		  pci_device->sub_vendor, pci_device->sub_product);
*/
	for (int i = 0; i < pci_device->dev_info->linux_kernel_module_count;
	     i++) {
	    if (i > 0) {
		strncat(kernel_modules, " | ", 3);
	    }
	    strncat(kernel_modules,
		    pci_device->dev_info->linux_kernel_module[i],
		    LINUX_KERNEL_MODULE_SIZE - 1);
	}

	moreprintf("%04x:%04x[%04x:%04x]: %s\n",
		   pci_device->vendor, pci_device->product,
		   pci_device->sub_vendor, pci_device->sub_product,
		   pci_device->dev_info->class_name);

	moreprintf(" Vendor Name      : %s\n",
		   pci_device->dev_info->vendor_name);
	moreprintf(" Product Name     : %s\n",
		   pci_device->dev_info->product_name);
	moreprintf(" PCI bus position : %02x:%02x.%01x\n", __pci_bus,
		   __pci_slot, __pci_func);
	moreprintf(" Kernel modules   : %s\n\n", kernel_modules);
    }
}

int main(int argc, char *argv[])
{
    struct pci_domain *pci_domain;
    int return_code = 0;
    int nb_pci_devices = 0;

    (void)argc;
    (void)argv;

    /* Scanning to detect pci buses and devices */
    printf("PCI: Scanning PCI BUS\n");
    pci_domain = pci_scan();
    if (!pci_domain) {
	printf("PCI: no devices found!\n");
	return 1;
    }

    struct pci_device *pci_device;
    for_each_pci_func(pci_device, pci_domain) {
	nb_pci_devices++;
    }

    printf("PCI: %d PCI devices found\n", nb_pci_devices);

    printf("PCI: Looking for device name\n");
    /* Assigning product & vendor name for each device */
    return_code = get_name_from_pci_ids(pci_domain, "pci.ids");
    if (return_code == -ENOPCIIDS) {
	printf("PCI: ERROR !\n");
	printf("PCI: Unable to open pci.ids file in current directory.\n");
	printf("PCI: PCI Device names can't be computed.\n");
    }

    printf("PCI: Resolving class names\n");
    /* Assigning class name for each device */
    return_code = get_class_name_from_pci_ids(pci_domain, "pci.ids");
    if (return_code == -ENOPCIIDS) {
	printf("PCI: ERROR !\n");
	printf("PCI: Unable to open pci.ids file in current directory.\n");
	printf("PCI: PCI class names can't be computed.\n");
    }

    printf("PCI: Looking for Kernel modules\n");
    /* Detecting which kernel module should match each device */
    return_code = get_module_name_from_pcimap(pci_domain, "modules.pcimap");
    if (return_code == -ENOMODULESPCIMAP) {
	printf("PCI: ERROR !\n");
	printf("PCI: Unable to open modules.pcimap file in current directory.\n");
	printf("PCI: Kernel Module names can't be computed.\n");
    }

    /* display the pci devices we found */
    display_pci_devices(pci_domain);
    return 0;
}
