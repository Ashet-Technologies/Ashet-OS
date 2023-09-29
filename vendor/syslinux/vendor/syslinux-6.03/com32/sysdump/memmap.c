/*
 * Dump memory map information
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <com32.h>
#include "sysdump.h"

#define E820_CHUNK 128
struct e820_info {
    uint32_t ebx;
    uint32_t len;
    uint8_t  data[24];
};

static void dump_e820(struct upload_backend *be)
{
    com32sys_t ireg, oreg;
    struct e820_info *curr;
    struct e820_info *buf, *p;
    int nentry, nalloc;

    curr = lmalloc(sizeof *curr);

    buf = p = NULL;
    nentry = nalloc = 0;
    memset(&ireg, 0, sizeof ireg);
    memset(&curr, 0, sizeof curr);

    ireg.eax.l = 0xe820;
    ireg.edx.l = 0x534d4150;
    ireg.ecx.l = sizeof curr->data;
    ireg.es = SEG(curr->data);
    ireg.edi.w[0] = OFFS(curr->data);

    do {
	__intcall(0x15, &ireg, &oreg);
	if ((oreg.eflags.l & EFLAGS_CF) ||
	    oreg.eax.l != 0x534d4150)
	    break;

	if (nentry >= nalloc) {
	    nalloc += E820_CHUNK;
	    buf = realloc(buf, nalloc*sizeof *buf);
	    if (!buf)
		return;		/* FAILED */
	}
	memcpy(buf[nentry].data, curr->data, sizeof curr->data);
	buf[nentry].ebx = ireg.ebx.l;
	buf[nentry].len = oreg.ecx.l;
	nentry++;

	ireg.ebx.l = oreg.ebx.l;
    } while (ireg.ebx.l);

    if (nentry)
	cpio_writefile(be, "memmap/15e820", buf, nentry*sizeof *buf);

    free(buf);
    lfree(curr);
}

void dump_memory_map(struct upload_backend *be)
{
    com32sys_t ireg, oreg;

    cpio_mkdir(be, "memmap");

    memset(&ireg, 0, sizeof ireg);
    __intcall(0x12, &ireg, &oreg);
    cpio_writefile(be, "memmap/12", &oreg, sizeof oreg);

    memset(&ireg, 0, sizeof ireg);
    ireg.eax.b[1] = 0x88;
    __intcall(0x15, &ireg, &oreg);
    cpio_writefile(be, "memmap/1588", &oreg, sizeof oreg);

    memset(&ireg, 0, sizeof ireg);
    ireg.eax.w[0] = 0xe801;
    __intcall(0x15, &ireg, &oreg);
    cpio_writefile(be, "memmap/15e801", &oreg, sizeof oreg);

    dump_e820(be);
}
