/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * msetup.c
 *
 * Initialization code for memory-based disk
 */

#include <stdint.h>
#ifdef TEST
# include <string.h>
# include <stdio.h>
#else
# include "memdisk.h"
# include "conio.h"
#endif
#include "e820.h"

uint32_t dos_mem = 0;		/* 0-1MB */
uint32_t low_mem = 0;		/* 1-16MB */
uint32_t high_mem = 0;		/* 16+ MB */

#ifndef TEST

static inline int get_e820(void)
{
    struct e820_info {
	uint64_t base;
	uint64_t len;
	uint32_t type;
    } *buf = sys_bounce;
    uint32_t copied;
    int range_count = 0;
    com32sys_t regs;

    memset(&regs, 0, sizeof regs);
    memset(buf, 0, sizeof *buf);

    do {
	regs.eax.l = 0x0000e820;
	regs.ecx.l = sizeof(*buf);
	regs.edx.l = 0x534d4150;
	regs.edi.w[0] = OFFS(buf);
	regs.es = SEG(buf);

	intcall(0x15, &regs, &regs);
	copied = (regs.eflags.l & 1) ? 0 : regs.ecx.l;

	if (regs.eax.l != 0x534d4150 || copied < 20)
	    break;

	printf("e820: %08x%08x %08x%08x %d\n",
	       (uint32_t) (buf->base >> 32), (uint32_t) buf->base,
	       (uint32_t) (buf->len >> 32), (uint32_t) buf->len, buf->type);

	insertrange(buf->base, buf->len, buf->type);
	range_count++;

    } while (regs.ebx.l);

    return !range_count;
}

static inline void get_dos_mem(void)
{
    com32sys_t regs;

    memset(&regs, 0, sizeof regs);
    intcall(0x12, &regs, &regs);
    insertrange(0, (uint64_t) ((uint32_t) regs.eax.w[0] << 10), 1);
    printf(" DOS: %d K\n", regs.eax.w[0]);
}

static inline int get_e801(void)
{
    int err;
    com32sys_t regs;

    memset(&regs, 0, sizeof regs);

    regs.eax.w[0] = 0xe801;
    intcall(0x15, &regs, &regs);

    if (!(err = regs.eflags.l & 1)) {
	if (regs.eax.w[0]) {
	    insertrange(0x100000, (uint64_t) ((uint32_t) regs.eax.w[0] << 10),
			1);
	}
	if (regs.ebx.w[0]) {
	    insertrange(0x1000000, (uint64_t) ((uint32_t) regs.ebx.w[0] << 16),
			1);
	}

	printf("e801: %04x %04x\n", regs.eax.w[0], regs.ebx.w[0]);
    }

    return err;
}

static inline int get_88(void)
{
    com32sys_t regs;
    int err;

    memset(&regs, 0, sizeof regs);

    regs.eax.b[1] = 0x88;
    intcall(0x15, &regs, &regs);

    if (!(err = regs.eflags.l & 1)) {
	if (regs.eax.w[0]) {
	    insertrange(0x100000, (uint64_t) ((uint32_t) regs.eax.w[0] << 10),
			1);
	}

	printf("  88: %04x\n", regs.eax.w[0]);
    }

    return err;
}

void get_mem(void)
{
    if (get_e820()) {
	get_dos_mem();
	if (get_e801()) {
	    if (get_88()) {
		die("MEMDISK: Unable to obtain memory map\n");
	    }
	}
    }
}

#endif /* TEST */

#define PW(x) (1ULL << (x))

void parse_mem(void)
{
    struct e820range *ep;

    dos_mem = low_mem = high_mem = 0;

    /* Derive "dos mem", "high mem", and "low mem" from the range array */
    for (ep = ranges; ep->type != -1U; ep++) {
	if (ep->type == 1) {
	    /* Only look at memory ranges */
	    if (ep->start == 0) {
		if (ep[1].start > PW(20))
		    dos_mem = PW(20);
		else
		    dos_mem = ep[1].start;
	    }
	    if (ep->start <= PW(20) && ep[1].start > PW(20)) {
		if (ep[1].start > PW(24))
		    low_mem = PW(24) - PW(20);
		else
		    low_mem = ep[1].start - PW(20);
	    }
	    if (ep->start <= PW(24) && ep[1].start > PW(24)) {
		if (ep[1].start > PW(32))
		    high_mem = PW(32) - PW(24);
		else
		    high_mem = ep[1].start - PW(24);
	    }
	}
    }
}
