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

void dump_pci(struct s_hardware *hardware, ZZJSON_CONFIG * config,
	      ZZJSON ** item)
{
    int i = 1;
    struct pci_device *pci_device=NULL;
    char kernel_modules[LINUX_KERNEL_MODULE_SIZE *
			MAX_KERNEL_MODULES_PER_PCI_DEVICE];
    bool nopciids = false;
    bool nomodulespcimap = false;
    bool nomodulesalias = false;
    bool nomodulesfile = false;
    int bus = 0, slot = 0, func = 0;
    
    if (hardware->pci_ids_return_code == -ENOPCIIDS) {
	nopciids = true;
    }
    if (hardware->modules_pcimap_return_code == -ENOMODULESPCIMAP) {
	nomodulespcimap = true;
    }
    if (hardware->modules_pcimap_return_code == -ENOMODULESALIAS) {
	nomodulesalias = true;
    }

    nomodulesfile = nomodulespcimap && nomodulesalias;

    CREATE_NEW_OBJECT;

    add_i("pci_device.count", hardware->nb_pci_devices);

    FLUSH_OBJECT;
    /* For every detected pci device, compute its submenu */
    for_each_pci_func(pci_device, hardware->pci_domain) {
	if (pci_device == NULL)
	    continue;
	char v[10] = { 0 };
	char sv[10] = { 0 };
	char p[10] = { 0 };
	char sp[10] = { 0 };
	char c[10] = { 0 };
	char r[10] = { 0 };

	CREATE_NEW_OBJECT;
	bus = __pci_bus;
	slot = __pci_slot;
	func = __pci_func;

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
	if (pci_device->dev_info->linux_kernel_module_count == 0)
	    strlcpy(kernel_modules, "unknown", 7);

	add_i("pci_device.number", i);
	if (nopciids == false) {
	    add_s("pci_device.vendor_name", pci_device->dev_info->vendor_name);
	    add_s("pci_device.product_name",
		   pci_device->dev_info->product_name);
	}
	if (nomodulesfile == false) {
	    add_s("pci_device.class_name", pci_device->dev_info->class_name);
	    add_s("pci_device.kernel_module", kernel_modules);
	}

	snprintf(v, sizeof(v), "%04x", pci_device->vendor);
	snprintf(p, sizeof(p), "%04x", pci_device->product);
	snprintf(sv, sizeof(sv), "%04x", pci_device->sub_vendor);
	snprintf(sp, sizeof(sp), "%04x", pci_device->sub_product);
	snprintf(c, sizeof(c), "%02x.%02x.%02x",
		 pci_device->class[2],
		 pci_device->class[1], pci_device->class[0]);
	snprintf(r, sizeof(r), "%02x", pci_device->revision);
	add_s("pci_device.vendor_id", v);
	add_s("pci_device.product_id", p);
	add_s("pci_device.sub_vendor_id", sv);
	add_s("pci_device.sub_product_id", sp);
	add_s("pci_device.class_id", c);
	add_s("pci_device.revision", r);
	if ((pci_device->dev_info->irq > 0)
	    && (pci_device->dev_info->irq < 255))
	    add_i("pci_device.irq", pci_device->dev_info->irq);

	add_i("pci_device.latency", pci_device->dev_info->latency);
	add_i("pci_device.bus", bus);
	add_i("pci_device.slot", slot);
	add_i("pci_device.func", func);

	if (hardware->is_pxe_valid == true) {
	    if ((hardware->pxe.pci_device != NULL)
		&& (hardware->pxe.pci_device == pci_device)) {
		add_hs(pxe.mac_addr);
		add_s("pxe", "Current boot device");
	    }
	}
	i++;
	FLUSH_OBJECT;
    }
    to_cpio("pci");
}
