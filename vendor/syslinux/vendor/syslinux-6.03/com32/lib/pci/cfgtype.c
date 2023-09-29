#include "pci/pci.h"
#include <com32.h>
#include <string.h>

enum pci_config_type __pci_cfg_type;

static int type1_ok(void)
{
    uint32_t oldcf8, newcf8;

    /* Test for Configuration Method #1 */

    /* Note: XFree86 writes ~0 and expects to read back 0x80fffffc.  Linux
       does this less severe test; go with Linux. */

    cli();
    outb(1, 0xcfb);		/* For old Intel chipsets */
    oldcf8 = inl(0xcf8);
    outl(0x80000000, 0xcf8);
    newcf8 = inl(0xcf8);
    outl(oldcf8, 0xcf8);
    sti();

    return newcf8 == 0x80000000;
}

static int type2_ok(void)
{
    uint8_t oldcf8, oldcfa;
    uint8_t cf8, cfa;

    /* Test for Configuration Method #2 */

    /* CM#2 is hard to probe for, but let's do our best... */

    cli();
    outb(0, 0xcfb);		/* For old Intel chipsets */
    oldcf8 = inb(0xcf8);
    outb(0, 0xcf8);
    oldcfa = inb(0xcfa);
    outb(0, 0xcfa);

    cf8 = inb(0xcf8);
    cfa = inb(0xcfa);

    outb(oldcf8, 0xcf8);
    outb(oldcfa, 0xcfa);
    sti();

    return cf8 == 0 && cfa == 0;
}

int pci_set_config_type(enum pci_config_type type)
{
    static const com32sys_t ireg = {
	.eax.l = 0xb101,
	.edi.l = 0,
	.eflags.l = EFLAGS_CF,
    };
    com32sys_t oreg;

    if (type == PCI_CFG_AUTO) {
	type = PCI_CFG_NONE;

	/* Try to detect PCI BIOS */
	__intcall(0x1a, &ireg, &oreg);

	if (!(oreg.eflags.l & EFLAGS_CF) &&
	    oreg.eax.b[1] == 0 && oreg.edx.l == 0x20494250) {
	    /* PCI BIOS present.  Use direct access if we know how to do it. */

	    if ((oreg.eax.b[0] & 1) && type1_ok())
		type = PCI_CFG_TYPE1;
	    else if ((oreg.eax.b[0] & 2) && type2_ok())
		type = PCI_CFG_TYPE2;
	    else
		type = PCI_CFG_BIOS;	/* Use BIOS calls as fallback */

	} else if (type1_ok()) {
	    type = PCI_CFG_TYPE1;
	} else if (type2_ok()) {
	    type = PCI_CFG_TYPE2;
	} else {
	    type = PCI_CFG_NONE;	/* Badness... */
	}
    }

    return (__pci_cfg_type = type);
}
