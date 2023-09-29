/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Erwan Velu - All Rights Reserved
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

#include "hdt-common.h"
#include "hdt-dump.h"

void dump_kernel(struct s_hardware *hardware, ZZJSON_CONFIG * config,
		 ZZJSON ** item)
{
    struct pci_device *pci_device = NULL;
    CREATE_ARRAY
	    add_as("Linux Kernel modules", "")
    END_OF_ARRAY;

    if (hardware->pci_ids_return_code == -ENOPCIIDS) {
	APPEND_ARRAY 
		add_as("Error", "No pci.ids file")
	END_OF_APPEND FLUSH_OBJECT;
	return;
    }

    if ((hardware->modules_pcimap_return_code == -ENOMODULESPCIMAP)
	&&(hardware->modules_pcimap_return_code == -ENOMODULESALIAS)) {
	APPEND_ARRAY
		add_as("Error", "No modules.pcimap or modules.alias file")
	END_OF_APPEND FLUSH_OBJECT;
	return;

	}

    /* For every detected pci device, compute its submenu */
    for_each_pci_func(pci_device, hardware->pci_domain) {
	if (pci_device == NULL)
	    continue;
	for (int kmod = 0;
	     kmod < pci_device->dev_info->linux_kernel_module_count; kmod++) {
	    APPEND_ARRAY
		    add_as(pci_device->dev_info->category_name, pci_device->dev_info->linux_kernel_module[kmod])
	    END_OF_APPEND;
	}
    }
    FLUSH_OBJECT;
    to_cpio("kernel");
}
