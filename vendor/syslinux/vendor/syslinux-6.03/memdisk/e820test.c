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
 * e820hack.c
 *
 * Test of INT 15:E820 canonicalization/manipulation routine
 */

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include "e820.h"

void *sys_bounce;		/* Dummy */

extern void parse_mem(void);
extern uint32_t dos_mem, low_mem, high_mem;

void __attribute__ ((noreturn)) die(void)
{
    abort();
}

void printranges(void)
{
    int i;

    for (i = 0; i < nranges; i++) {
	printf("%016llx %016llx %d\n",
	       ranges[i].start,
	       ranges[i + 1].start - ranges[i].start, ranges[i].type);
    }
}

int main(void)
{
    uint64_t start, len;
    uint32_t type;
    char line[BUFSIZ], *p;

    e820map_init();
    printranges();

    while (fgets(line, BUFSIZ, stdin)) {
	p = strchr(line, ':');
	p = p ? p + 1 : line;
	if (sscanf(p, " %llx %llx %d", &start, &len, &type) == 3) {
	    putchar('\n');
	    printf("%016llx %016llx %d <-\n", start, len, type);
	    putchar('\n');
	    insertrange(start, len, type);
	    printranges();
	}
    }

    parse_mem();

    putchar('\n');
    printf("DOS  mem = %#10x (%u K)\n", dos_mem, dos_mem >> 10);
    printf("Low  mem = %#10x (%u K)\n", low_mem, low_mem >> 10);
    printf("High mem = %#10x (%u K)\n", high_mem, high_mem >> 10);
    putchar('\n');

    /* Now, steal a chunk (2K) of DOS memory and make sure it registered OK */
    insertrange(dos_mem - 2048, 2048, 2, 1);	/* Type 2 = reserved */

    printranges();
    parse_mem();

    putchar('\n');
    printf("DOS  mem = %#10x (%u K)\n", dos_mem, dos_mem >> 10);
    printf("Low  mem = %#10x (%u K)\n", low_mem, low_mem >> 10);
    printf("High mem = %#10x (%u K)\n", high_mem, high_mem >> 10);
    putchar('\n');

    return 0;
}
