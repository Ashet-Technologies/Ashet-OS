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
 * e820func.c
 *
 * E820 range database manager
 */

#include <stdint.h>
#ifdef TEST
#include <string.h>
#else
#include "memdisk.h"		/* For memset() */
#endif
#include "e820.h"

#define MAXRANGES	1024
/* All of memory starts out as one range of "indeterminate" type */
struct e820range ranges[MAXRANGES];
int nranges;

void e820map_init(void)
{
    memset(ranges, 0, sizeof(ranges));
    nranges = 1;
    ranges[1].type = -1U;
}

static void insertrange_at(int where, uint64_t start, uint32_t type)
{
    int i;

    for (i = nranges; i > where; i--)
	ranges[i] = ranges[i - 1];

    ranges[where].start = start;
    ranges[where].type = type;

    nranges++;
    ranges[nranges].start = 0ULL;
    ranges[nranges].type = -1U;
}

void insertrange(uint64_t start, uint64_t len, uint32_t type)
{
    uint64_t last;
    uint32_t oldtype;
    int i, j;

    /* Remove this to make len == 0 mean all of memory */
    if (len == 0)
	return;			/* Nothing to insert */

    last = start + len - 1;	/* May roll over */

    i = 0;
    oldtype = -2U;
    while (start > ranges[i].start && ranges[i].type != -1U) {
	oldtype = ranges[i].type;
	i++;
    }

    /* Consider the replacement policy.  This current one is "overwrite." */

    if (start < ranges[i].start || ranges[i].type == -1U)
	insertrange_at(i++, start, type);

    while (i == 0 || last > ranges[i].start - 1) {
	oldtype = ranges[i].type;
	ranges[i].type = type;
	i++;
    }

    if (last < ranges[i].start - 1)
	insertrange_at(i, last + 1, oldtype);

    /* Now the map is correct, but quite possibly not optimal.  Scan the
       map for ranges which are redundant and remove them. */
    i = j = 1;
    oldtype = ranges[0].type;
    while (i < nranges) {
	if (ranges[i].type == oldtype) {
	    i++;
	} else {
	    oldtype = ranges[i].type;
	    if (i != j)
		ranges[j] = ranges[i];
	    i++;
	    j++;
	}
    }

    if (i != j) {
	ranges[j] = ranges[i];	/* Termination sentinel copy */
	nranges -= (i - j);
    }
}
