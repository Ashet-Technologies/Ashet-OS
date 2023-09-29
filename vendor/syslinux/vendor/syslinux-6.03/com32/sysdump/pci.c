/*
 * Dump PCI device headers
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/pci.h>
#include "sysdump.h"

static void dump_pci_device(struct upload_backend *be, pciaddr_t a, uint8_t hdrtype)
{
    unsigned int bus  = pci_bus(a);
    unsigned int dev  = pci_dev(a);
    unsigned int func = pci_func(a);
    uint8_t data[256];
    unsigned int i;
    char filename[32];

    hdrtype &= 0x7f;

    printf("Scanning PCI bus... %02x:%02x.%x\r", bus, dev, func);

    /* Assume doing a full device dump is actually safe... */
    for (i = 0; i < sizeof data; i += 4)
	*(uint32_t *)(data+i) = pci_readl(a + i);

    snprintf(filename, sizeof filename, "pci/%02x:%02x.%x",
	     bus, dev, func);
    cpio_writefile(be, filename, data, sizeof data);
}

void dump_pci(struct upload_backend *be)
{
    int cfgtype;
    unsigned int nbus, ndev, nfunc, maxfunc;
    pciaddr_t a;
    uint32_t did;
    uint8_t hdrtype;

    cfgtype = pci_set_config_type(PCI_CFG_AUTO);
    if (cfgtype == PCI_CFG_NONE)
	return;

    cpio_mkdir(be, "pci");

    for (nbus = 0; nbus < MAX_PCI_BUSES; nbus++) {
	for (ndev = 0; ndev < MAX_PCI_DEVICES; ndev++) {
	    maxfunc = 1;	/* Assume a single-function device */

	    for (nfunc = 0; nfunc < maxfunc; nfunc++) {
		a = pci_mkaddr(nbus, ndev, nfunc, 0);
		did = pci_readl(a);

		if (did == 0xffffffff || did == 0xffff0000 ||
		    did == 0x0000ffff || did == 0x00000000)
		    continue;

		hdrtype = pci_readb(a + 0x0e);
		if (hdrtype & 0x80)
		    maxfunc = MAX_PCI_FUNC;	/* Multifunction device */

		dump_pci_device(be, a, hdrtype);
	    }
	}
    }

    printf("Scanning PCI bus... done.  \n");
}
