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
#include <syslinux/pxe.h>
#include <syslinux/config.h>
#include <sys/gpxe.h>

#include "hdt-cli.h"
#include "hdt-common.h"

void main_show_pxe(int argc __unused, char **argv __unused,
		   struct s_hardware *hardware)
{
    char buffer[81];
    memset(buffer, 0, sizeof(81));
    reset_more_printf();
    if (hardware->sv->filesystem != SYSLINUX_FS_PXELINUX) {
	more_printf("You are not currently using PXELINUX\n");
	return;
    }

    more_printf("PXE\n");
    if (hardware->is_pxe_valid == false) {
	more_printf(" No valid PXE ROM found\n");
	return;
    }

    struct s_pxe *p = &hardware->pxe;
    more_printf(" PCI device no: %d \n", p->pci_device_pos);

    if (hardware->pci_ids_return_code == -ENOPCIIDS || (p->pci_device == NULL)) {
	snprintf(buffer, sizeof(buffer),
		 " PCI ID       : %04x:%04x[%04x:%04X] rev(%02x)\n",
		 p->vendor_id, p->product_id, p->subvendor_id,
		 p->subproduct_id, p->rev);
	snprintf(buffer, sizeof(buffer),
		 " PCI Bus pos. : %02x:%02x.%02x\n", p->pci_bus,
		 p->pci_dev, p->pci_func);
	more_printf("%s", buffer);
    } else {
	snprintf(buffer, sizeof(buffer), " Manufacturer : %s \n",
		 p->pci_device->dev_info->vendor_name);
	more_printf("%s", buffer);
	snprintf(buffer, sizeof(buffer), " Product      : %s \n",
		 p->pci_device->dev_info->product_name);
	more_printf("%s", buffer);
    }
    more_printf(" Addresses    : %d.%d.%d.%d @ %s\n", p->ip_addr[0],
		p->ip_addr[1], p->ip_addr[2], p->ip_addr[3], p->mac_addr);

    if (is_gpxe())
	more_printf(" gPXE Detected: Yes\n")
    else
	more_printf(" gPXE Detected: No\n");
}

struct cli_module_descr pxe_show_modules = {
    .modules = NULL,
    .default_callback = main_show_pxe,
};

struct cli_mode_descr pxe_mode = {
    .mode = PXE_MODE,
    .name = CLI_PXE,
    .default_modules = NULL,
    .show_modules = &pxe_show_modules,
    .set_modules = NULL,
};
