/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * meminfo.c
 *
 * Dump the memory map of the system
 */
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <console.h>
#include <com32.h>

struct e820_data {
    uint64_t base;
    uint64_t len;
    uint32_t type;
    uint32_t extattr;
} __attribute__ ((packed));

static const char *const e820_types[] = {
    "usable",
    "reserved",
    "ACPI reclaim",
    "ACPI NVS",
    "unusable",
};

static void dump_e820(void)
{
    com32sys_t ireg, oreg;
    struct e820_data ed;
    uint32_t type;
    void *low_ed;

    low_ed = lmalloc(sizeof ed);
    if (!low_ed)
	return;

    memset(&ireg, 0, sizeof ireg);

    ireg.eax.w[0] = 0xe820;
    ireg.edx.l = 0x534d4150;
    ireg.ecx.l = sizeof(struct e820_data);
    ireg.edi.w[0] = OFFS(low_ed);
    ireg.es = SEG(low_ed);

    memset(&ed, 0, sizeof ed);
    ed.extattr = 1;

    do {
	memcpy(low_ed, &ed, sizeof ed);

	__intcall(0x15, &ireg, &oreg);
	if (oreg.eflags.l & EFLAGS_CF ||
	    oreg.eax.l != 0x534d4150 || oreg.ecx.l < 20)
	    break;

	memcpy(&ed, low_ed, sizeof ed);

	if (oreg.ecx.l >= 24) {
	    /* ebx base length end type */
	    printf("%8x %016llx %016llx %016llx %d [%x]",
		   ireg.ebx.l, ed.base, ed.len, ed.base + ed.len, ed.type,
		   ed.extattr);
	} else {
	    /* ebx base length end */
	    printf("%8x %016llx %016llx %016llx %d [-]",
		   ireg.ebx.l, ed.base, ed.len, ed.base + ed.len, ed.type);
	    ed.extattr = 1;
	}

	type = ed.type - 1;
	if (type < sizeof(e820_types) / sizeof(e820_types[0]))
	    printf(" %s", e820_types[type]);

	putchar('\n');

	ireg.ebx.l = oreg.ebx.l;
    } while (ireg.ebx.l);

    lfree(low_ed);
}

static void dump_legacy(void)
{
    com32sys_t ireg, oreg;
    uint16_t dosram = *(uint16_t *) 0x413;
    struct {
	uint16_t offs, seg;
    } *const ivt = (void *)0;

    memset(&ireg, 0, sizeof ireg);

    __intcall(0x12, &ireg, &oreg);

    printf
	("INT 15h = %04x:%04x  DOS RAM: %dK (0x%05x)  INT 12h: %dK (0x%05x)\n",
	 ivt[0x15].seg, ivt[0x15].offs, dosram, dosram << 10, oreg.eax.w[0],
	 oreg.eax.w[0] << 10);

    memset(&ireg, 0, sizeof ireg);
    ireg.eax.b[1] = 0x88;
    __intcall(0x15, &ireg, &oreg);

    printf("INT 15 88: 0x%04x (%uK)  ", oreg.eax.w[0], oreg.eax.w[0]);

    memset(&ireg, 0, sizeof ireg);
    ireg.eax.w[0] = 0xe801;
    __intcall(0x15, &ireg, &oreg);

    printf("INT 15 E801: 0x%04x (%uK) 0x%04x (%uK)\n",
	   oreg.ecx.w[0], oreg.ecx.w[0], oreg.edx.w[0], oreg.edx.w[0] << 6);
}

int main(int argc __unused, char **argv __unused)
{
    dump_legacy();
    dump_e820();
    return 0;
}
