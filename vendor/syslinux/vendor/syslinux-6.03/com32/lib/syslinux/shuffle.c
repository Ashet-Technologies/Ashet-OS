/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
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
 * shuffle.c
 *
 * Common code for "shuffle and boot" operation; generates a shuffle list
 * and puts it in the bounce buffer.  Returns the number of shuffle
 * descriptors.
 */

#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <com32.h>
#include <core.h>
#include <minmax.h>
#include <dprintf.h>
#include <syslinux/movebits.h>
#include <klibc/compiler.h>
#include <syslinux/boot.h>

struct shuffle_descriptor {
    uint32_t dst, src, len;
};

/*
 * Allocate descriptor memory in these chunks; if this is large we may
 * waste memory, if it is small we may get slow convergence.
 */
#define DESC_BLOCK_SIZE	256

int syslinux_do_shuffle(struct syslinux_movelist *fraglist,
			struct syslinux_memmap *memmap,
			addr_t entry_point, addr_t entry_type,
			uint16_t bootflags)
{
    int rv = -1;
    struct syslinux_movelist *moves = NULL, *mp;
    struct syslinux_memmap *rxmap = NULL, *ml;
    struct shuffle_descriptor *dp, *dbuf;
    int np;
    int desc_blocks, need_blocks;
    int need_ptrs;
    addr_t desczone, descfree, descaddr;
    int nmoves, nzero;

#ifndef __FIRMWARE_BIOS__
    errno = ENOSYS;
    return -1;			/* Not supported at this time*/
#endif

    descaddr = 0;
    dp = dbuf = NULL;

    /* Count the number of zero operations */
    nzero = 0;
    for (ml = memmap; ml->type != SMT_END; ml = ml->next) {
	if (ml->type == SMT_ZERO)
	    nzero++;
    }

    /* Find the largest contiguous region unused by input *and* output;
       this is where we put the move descriptor list and safe area */

    rxmap = syslinux_dup_memmap(memmap);
    if (!rxmap)
	goto bail;
    /* Avoid using the low 1 MB for the shuffle area -- this avoids
       possible interference with the real mode code or stack */
    if (syslinux_add_memmap(&rxmap, 0, 1024 * 1024, SMT_RESERVED))
	goto bail;
    for (mp = fraglist; mp; mp = mp->next) {
	if (syslinux_add_memmap(&rxmap, mp->src, mp->len, SMT_ALLOC) ||
	    syslinux_add_memmap(&rxmap, mp->dst, mp->len, SMT_ALLOC))
	    goto bail;
    }
    if (syslinux_memmap_largest(rxmap, SMT_FREE, &desczone, &descfree))
	goto bail;

    syslinux_free_memmap(rxmap);

    dprintf("desczone = 0x%08x, descfree = 0x%08x\n", desczone, descfree);

    rxmap = syslinux_dup_memmap(memmap);
    if (!rxmap)
	goto bail;

    desc_blocks = (nzero + DESC_BLOCK_SIZE - 1) / DESC_BLOCK_SIZE;
    for (;;) {
	/* We want (desc_blocks) allocation blocks, plus the terminating
	   descriptor, plus the shuffler safe area. */
	addr_t descmem = desc_blocks *
	    sizeof(struct shuffle_descriptor) * DESC_BLOCK_SIZE
	    + sizeof(struct shuffle_descriptor)
	    + syslinux_shuffler_size();

	descaddr = (desczone + descfree - descmem) & ~3;

	if (descaddr < desczone)
	    goto bail;		/* No memory block large enough */

	/* Mark memory used by shuffle descriptors as reserved */
	if (syslinux_add_memmap(&rxmap, descaddr, descmem, SMT_RESERVED))
	    goto bail;

#if DEBUG > 1
	syslinux_dump_movelist(fraglist);
#endif

	if (syslinux_compute_movelist(&moves, fraglist, rxmap))
	    goto bail;

	nmoves = 0;
	for (mp = moves; mp; mp = mp->next)
	    nmoves++;

	need_blocks = (nmoves + nzero + DESC_BLOCK_SIZE - 1) / DESC_BLOCK_SIZE;

	if (desc_blocks >= need_blocks)
	    break;		/* Sufficient memory, yay */

	desc_blocks = need_blocks;	/* Try again... */
    }

#if DEBUG > 1
    dprintf("Final movelist:\n");
    syslinux_dump_movelist(moves);
#endif

    syslinux_free_memmap(rxmap);
    rxmap = NULL;

    need_ptrs = nmoves + nzero + 1;
    dbuf = malloc(need_ptrs * sizeof(struct shuffle_descriptor));
    if (!dbuf)
	goto bail;

#if DEBUG
    {
	addr_t descoffs = descaddr - (addr_t) dbuf;

	dprintf("nmoves = %d, nzero = %d, dbuf = %p, offs = 0x%08x\n",
		nmoves, nzero, dbuf, descoffs);
    }
#endif

    /* Copy the move sequence into the descriptor buffer */
    np = 0;
    dp = dbuf;
    for (mp = moves; mp; mp = mp->next) {
	dp->dst = mp->dst;
	dp->src = mp->src;
	dp->len = mp->len;
	dprintf2("[ %08x %08x %08x ]\n", dp->dst, dp->src, dp->len);
	dp++;
	np++;
    }

    /* Copy bzero operations into the descriptor buffer */
    for (ml = memmap; ml->type != SMT_END; ml = ml->next) {
	if (ml->type == SMT_ZERO) {
	    dp->dst = ml->start;
	    dp->src = (addr_t) - 1;	/* bzero region */
	    dp->len = ml->next->start - ml->start;
	    dprintf2("[ %08x %08x %08x ]\n", dp->dst, dp->src, dp->len);
	    dp++;
	    np++;
	}
    }

    /* Finally, record the termination entry */
    dp->dst = entry_point;
    dp->src = entry_type;
    dp->len = 0;
    dp++;
    np++;

    if (np != need_ptrs) {
	dprintf("!!! np = %d : nmoves = %d, nzero = %d, desc_blocks = %d\n",
		np, nmoves, nzero, desc_blocks);
    }

    rv = 0;

bail:
    /* This is safe only because free() doesn't use the bounce buffer!!!! */
    if (moves)
	syslinux_free_movelist(moves);
    if (rxmap)
	syslinux_free_memmap(rxmap);

    if (rv)
	return rv;

    /* Actually do it... */
    bios_do_shuffle_and_boot(bootflags, descaddr, dbuf,
			     (size_t)dp - (size_t)dbuf);

    return -1;			/* Shouldn't have returned! */
}

/*
 * Common helper routine: takes a memory map and blots out the
 * zones which are used in the destination of a fraglist
 */
struct syslinux_memmap *syslinux_target_memmap(struct syslinux_movelist
					       *fraglist,
					       struct syslinux_memmap *memmap)
{
    struct syslinux_memmap *tmap;
    struct syslinux_movelist *mp;

    tmap = syslinux_dup_memmap(memmap);
    if (!tmap)
	return NULL;

    for (mp = fraglist; mp; mp = mp->next) {
	if (syslinux_add_memmap(&tmap, mp->dst, mp->len, SMT_ALLOC)) {
	    syslinux_free_memmap(tmap);
	    return NULL;
	}
    }

    return tmap;
}
