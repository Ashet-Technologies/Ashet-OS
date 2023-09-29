/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 H. Peter Anvin - All Rights Reserved
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
 * ----------------------------------------------------------------------- */

/*
 * mem.c
 *
 * Obtain a memory map for a Multiboot OS
 *
 * This differs from the libcom32 memory map functions in that it doesn't
 * attempt to filter out memory regions...
 */

#include "mboot.h"
#include <com32.h>

struct e820_entry {
    uint64_t start;
    uint64_t len;
    uint32_t type;
};

#define RANGE_ALLOC_BLOCK	128

static int mboot_scan_memory(struct AddrRangeDesc **ardp, uint32_t * dosmem)
{
    com32sys_t ireg, oreg;
    struct e820_entry *e820buf;
    struct AddrRangeDesc *ard;
    size_t ard_count, ard_space;
    int rv = 0;

    /* Use INT 12h to get DOS memory */
    __intcall(0x12, &__com32_zero_regs, &oreg);
    *dosmem = oreg.eax.w[0] << 10;
    if (*dosmem < 32 * 1024 || *dosmem > 640 * 1024) {
	/* INT 12h reports nonsense... now what? */
	uint16_t ebda_seg = *(uint16_t *) 0x40e;
	if (ebda_seg >= 0x8000 && ebda_seg < 0xa000)
	    *dosmem = ebda_seg << 4;
	else
	    *dosmem = 640 * 1024;	/* Hope for the best... */
    }

    e820buf = lmalloc(sizeof(*e820buf));
    if (!e820buf)
	return 0;

    /* Allocate initial space */
    *ardp = ard = malloc(RANGE_ALLOC_BLOCK * sizeof *ard);
    if (!ard)
	goto out;

    ard_count = 0;
    ard_space = RANGE_ALLOC_BLOCK;

    /* First try INT 15h AX=E820h */
    memset(&ireg, 0, sizeof ireg);
    ireg.eax.l = 0xe820;
    ireg.edx.l = 0x534d4150;
    /* ireg.ebx.l    = 0; */
    ireg.ecx.l = sizeof(*e820buf);
    ireg.es = SEG(e820buf);
    ireg.edi.w[0] = OFFS(e820buf);
    memset(e820buf, 0, sizeof *e820buf);

    do {
	__intcall(0x15, &ireg, &oreg);

	if ((oreg.eflags.l & EFLAGS_CF) ||
	    (oreg.eax.l != 0x534d4150) || (oreg.ecx.l < 20))
	    break;

	if (ard_count >= ard_space) {
	    ard_space += RANGE_ALLOC_BLOCK;
	    *ardp = ard = realloc(ard, ard_space * sizeof *ard);
	    if (!ard) {
		rv = ard_count;
		goto out;
	    }
	}

	ard[ard_count].size = 20;
	ard[ard_count].BaseAddr = e820buf->start;
	ard[ard_count].Length = e820buf->len;
	ard[ard_count].Type = e820buf->type;
	ard_count++;

	ireg.ebx.l = oreg.ebx.l;
    } while (oreg.ebx.l);

    if (ard_count) {
	rv = ard_count;
	goto out;
    };

    ard[0].size = 20;
    ard[0].BaseAddr = 0;
    ard[0].Length = *dosmem << 10;
    ard[0].Type = 1;

    /* Next try INT 15h AX=E801h */
    memset(&ireg, 0, sizeof ireg);
    ireg.eax.w[0] = 0xe801;
    __intcall(0x15, &ireg, &oreg);

    if (!(oreg.eflags.l & EFLAGS_CF) && oreg.ecx.w[0]) {
	ard[1].size = 20;
	ard[1].BaseAddr = 1 << 20;
	ard[1].Length = oreg.ecx.w[0] << 10;
	ard[1].Type = 1;

	if (oreg.edx.w[0]) {
	    ard[2].size = 20;
	    ard[2].BaseAddr = 16 << 20;
	    ard[2].Length = oreg.edx.w[0] << 16;
	    ard[2].Type = 1;
	    rv = 3;
	} else {
	    rv = 2;
	}

	goto out;
    }

    /* Finally try INT 15h AH=88h */
    memset(&ireg, 0, sizeof ireg);
    ireg.eax.w[0] = 0x8800;
    __intcall(0x15, &ireg, &oreg);
    if (!(oreg.eflags.l & EFLAGS_CF) && oreg.eax.w[0]) {
	ard[1].size = 20;
	ard[1].BaseAddr = 1 << 20;
	ard[1].Length = oreg.ecx.w[0] << 10;
	ard[1].Type = 1;
	rv = 2;
	goto out;
    }

    rv = 1;			/* ... problematic ... */
out:
    lfree(e820buf);
    return rv;
}

void mboot_make_memmap(void)
{
    int i, nmap;
    struct AddrRangeDesc *ard;
    uint32_t lowmem, highmem;
    uint32_t highrsvd;

    /* Always report DOS memory as "lowmem", this may be overly conservative
       (e.g. if we're dropping PXE), but it should be *safe*... */

    nmap = mboot_scan_memory(&ard, &lowmem);

    highmem = 0x100000;
    highrsvd = 0xfff00000;

again:
    for (i = 0; i < nmap; i++) {
	uint64_t start, end;

	start = ard[i].BaseAddr;
	end = start + ard[i].Length;

	if (end < start)
	    end = ~0ULL;

	if (start & 0xffffffff00000000ULL)
	    continue;		/* Not interested in 64-bit memory */

	if (start < highmem)
	    start = highmem;

	if (end <= start)
	    continue;

	if (ard[i].Type == 1 && start == highmem) {
	    highmem = end;
	    goto again;
	} else if (ard[i].Type != 1 && start < highrsvd)
	    highrsvd = start;
    }

    if (highmem > highrsvd)
	highmem = highrsvd;

    mbinfo.mem_lower = lowmem >> 10;
    mbinfo.mem_upper = (highmem - 0x100000) >> 10;
    mbinfo.flags |= MB_INFO_MEMORY;

    /* The spec says this address should be +4, but Grub disagrees */
    mbinfo.mmap_addr = map_data(ard, nmap * sizeof *ard, 4, false);
    if (mbinfo.mmap_addr) {
	mbinfo.mmap_length = nmap * sizeof *ard;
	mbinfo.flags |= MB_INFO_MEM_MAP;
    }
}
