#include "pci/pci.h"

void BWL(pci_write)(TYPE v, pciaddr_t a)
{
    for (;;) {
	switch (__pci_cfg_type) {
	case PCI_CFG_AUTO:
	    pci_set_config_type(PCI_CFG_AUTO);
	    break;		/* Try again */

	case PCI_CFG_TYPE1:
	    {
		uint32_t oldcf8;
		cli();
		oldcf8 = inl(0xcf8);
		outl(a, 0xcf8);
		BWL(out) (v, 0xcfc + (a & 3));
		outl(oldcf8, 0xcf8);
		sti();
	    }
	    return;

	case PCI_CFG_TYPE2:
	    {
		uint8_t oldcf8, oldcfa;

		if (a & (0x10 << 11))
		    return;	/* Devices 16-31 not supported */

		cli();
		oldcf8 = inb(0xcf8);
		oldcfa = inb(0xcfa);
		outb(0xf0 + ((a >> (8 - 1)) & 0x0e), 0xcf8);
		outb(a >> 16, 0xcfa);
		BWL(out) (v, 0xc000 + ((a >> (11 - 8)) & 0xf00) + (a & 0xff));
		outb(oldcf8, 0xcf8);
		outb(oldcfa, 0xcfa);
		sti();
	    }
	    return;

	case PCI_CFG_BIOS:
	    __pci_read_write_bios(BIOSCALL, v, a);
	    return;

	default:
	    return;
	}
    }
}
