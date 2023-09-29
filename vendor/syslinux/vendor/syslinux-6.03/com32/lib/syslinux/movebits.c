/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
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
 * movebits.c
 *
 * Utility function to take a list of memory areas to shuffle and
 * convert it to a set of shuffle operations.
 *
 * Note: a lot of the functions in this file deal with "parent pointers",
 * which are pointers to a pointer to a list, or part of the list.
 * They can be pointers to a variable holding the list root pointer,
 * or pointers to a next field of a previous entry.
 */

#include <assert.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <inttypes.h>
#include <setjmp.h>
#include <minmax.h>
#include <stdbool.h>

#include <syslinux/movebits.h>
#include <dprintf.h>

static jmp_buf new_movelist_bail;

static struct syslinux_movelist *new_movelist(addr_t dst, addr_t src,
					      addr_t len)
{
    struct syslinux_movelist *ml = malloc(sizeof(struct syslinux_movelist));

    if (!ml)
	longjmp(new_movelist_bail, 1);

    ml->dst = dst;
    ml->src = src;
    ml->len = len;
    ml->next = NULL;

    return ml;
}

static struct syslinux_movelist *dup_movelist(struct syslinux_movelist *src)
{
    struct syslinux_movelist *dst = NULL, **dstp = &dst, *ml;

    while (src) {
	ml = new_movelist(src->dst, src->src, src->len);
	*dstp = ml;
	dstp = &ml->next;
	src = src->next;
    }

    return dst;
}

static void
add_freelist(struct syslinux_memmap **mmap, addr_t start,
	     addr_t len, enum syslinux_memmap_types type)
{
    if (syslinux_add_memmap(mmap, start, len, type))
	longjmp(new_movelist_bail, 1);
}

/*
 * Take a chunk, entirely confined in **parentptr, and split it off so that
 * it has its own structure.
 */
static struct syslinux_movelist **split_movelist(addr_t start, addr_t len,
						 struct syslinux_movelist
						 **parentptr)
{
    struct syslinux_movelist *m, *ml = *parentptr;

    assert(start >= ml->src);
    assert(start < ml->src + ml->len);

    /* Split off the beginning */
    if (start > ml->src) {
	addr_t l = start - ml->src;

	m = new_movelist(ml->dst + l, start, ml->len - l);
	m->next = ml->next;
	ml->len = l;
	ml->next = m;

	parentptr = &ml->next;
	ml = m;			/* Continue processing the new node */
    }

    /* Split off the end */
    if (ml->len > len) {
	addr_t l = ml->len - len;

	m = new_movelist(ml->dst + len, ml->src + len, l);
	m->next = ml->next;
	ml->len = len;
	ml->next = m;
    }

    return parentptr;
}

static void delete_movelist(struct syslinux_movelist **parentptr)
{
    struct syslinux_movelist *o = *parentptr;
    *parentptr = o->next;
    free(o);
}

static void free_movelist(struct syslinux_movelist **parentptr)
{
    while (*parentptr)
	delete_movelist(parentptr);
}

/*
 * Scan the freelist looking for a particular chunk of memory.  Returns
 * the memmap chunk containing to the first byte of the region.
 */
static const struct syslinux_memmap *is_free_zone(const struct syslinux_memmap
						  *list, addr_t start,
						  addr_t len)
{
    addr_t last, llast;

    dprintf("f: 0x%08x bytes at 0x%08x\n", len, start);

    last = start + len - 1;

    while (list->type != SMT_END) {
	if (list->start <= start) {
	    const struct syslinux_memmap *ilist = list;
	    while (valid_terminal_type(list->type)) {
		llast = list->next->start - 1;
		if (llast >= last)
		    return ilist;
		list = list->next;
	    }

	    if (list->start > start)
		return NULL;	/* Invalid type in region */
	}
	list = list->next;
    }

    return NULL;		/* Internal error? */
}

/*
 * Scan the freelist looking for the smallest chunk of memory which
 * can fit X bytes; returns the length of the block on success.
 */
static addr_t free_area(const struct syslinux_memmap *mmap,
			addr_t len, addr_t * start)
{
    const struct syslinux_memmap *best = NULL;
    const struct syslinux_memmap *s;
    addr_t slen, best_len = -1;

    for (s = mmap; s->type != SMT_END; s = s->next) {
	if (s->type != SMT_FREE)
	    continue;
	slen = s->next->start - s->start;
	if (slen >= len) {
	    if (!best || best_len > slen) {
		best = s;
		best_len = slen;
	    }
	}
    }

    if (best) {
	*start = best->start;
	return best_len;
    } else {
	return 0;
    }
}

/*
 * Remove a chunk from the freelist
 */
static void
allocate_from(struct syslinux_memmap **mmap, addr_t start, addr_t len)
{
    syslinux_add_memmap(mmap, start, len, SMT_ALLOC);
}

/*
 * Find chunks of a movelist which are one-to-many (one source, multiple
 * destinations.)  Those chunks can get turned into post-shuffle copies,
 * to avoid confusing the shuffler.
 */
static void shuffle_dealias(struct syslinux_movelist **fraglist,
			    struct syslinux_movelist **postcopy)
{
    struct syslinux_movelist *mp, **mpp, *mx, *np;
    addr_t ps, pe, xs, xe, delta;
    bool advance;

    dprintf("Before alias resolution:\n");
    syslinux_dump_movelist(*fraglist);

    *postcopy = NULL;

    /*
     * Note: as written, this is an O(n^2) algorithm; by producing a list
     * sorted by destination address we could reduce it to O(n log n).
     */
    mpp = fraglist;
    while ((mp = *mpp)) {
	dprintf("mp -> (%#x,%#x,%#x)\n", mp->dst, mp->src, mp->len);
	ps = mp->src;
	pe = mp->src + mp->len - 1;
	for (mx = *fraglist; mx != mp; mx = mx->next) {
	    dprintf("mx -> (%#x,%#x,%#x)\n", mx->dst, mx->src, mx->len);
	    /*
	     * If there is any overlap between mx and mp, mp should be
	     * modified and possibly split.
	     */
	    xs = mx->src;
	    xe = mx->src + mx->len - 1;

	    dprintf("?: %#x..%#x (inside %#x..%#x)\n", ps, pe, xs, xe);

	    if (pe <= xs || ps >= xe)
		continue;	/* No overlap */

	    advance = false;
	    *mpp = mp->next;	/* Remove from list */

	    if (pe > xe) {
		delta = pe - xe;
		np = new_movelist(mp->dst + mp->len - delta,
				  mp->src + mp->len - delta, delta);
		mp->len -= delta;
		pe = xe;
		np->next = *mpp;
		*mpp = np;
		advance = true;
	    }
	    if (ps < xs) {
		delta = xs - ps;
		np = new_movelist(mp->dst, ps, delta);
		mp->src += delta;
		ps = mp->src;
		mp->dst += delta;
		mp->len -= delta;
		np->next = *mpp;
		*mpp = np;
		advance = true;
	    }

	    assert(ps >= xs && pe <= xe);

	    dprintf("Overlap: %#x..%#x (inside %#x..%#x)\n", ps, pe, xs, xe);

	    mp->src = mx->dst + (ps - xs);
	    mp->next = *postcopy;
	    *postcopy = mp;

	    mp = *mpp;

	    if (!advance)
		goto restart;
	}

	mpp = &mp->next;
restart:
	;
    }

    dprintf("After alias resolution:\n");
    syslinux_dump_movelist(*fraglist);
    dprintf("Post-shuffle copies:\n");
    syslinux_dump_movelist(*postcopy);
}

/*
 * The code to actually emit moving of a chunk into its final place.
 */
static void
move_chunk(struct syslinux_movelist ***moves,
	   struct syslinux_memmap **mmap,
	   struct syslinux_movelist **fp, addr_t copylen)
{
    addr_t copydst, copysrc;
    addr_t freebase, freelen;
    addr_t needlen;
    int reverse;
    struct syslinux_movelist *f = *fp, *mv;

    if (f->src < f->dst && (f->dst - f->src) < f->len) {
	/* "Shift up" type overlap */
	needlen = f->dst - f->src;
	reverse = 1;
    } else if (f->src > f->dst && (f->src - f->dst) < f->len) {
	/* "Shift down" type overlap */
	needlen = f->src - f->dst;
	reverse = 0;
    } else {
	needlen = f->len;
	reverse = 0;
    }

    copydst = f->dst;
    copysrc = f->src;

    dprintf("Q: copylen = 0x%08x, needlen = 0x%08x\n", copylen, needlen);

    if (copylen < needlen) {
	if (reverse) {
	    copydst += (f->len - copylen);
	    copysrc += (f->len - copylen);
	}

	dprintf("X: 0x%08x bytes at 0x%08x -> 0x%08x\n",
		copylen, copysrc, copydst);

	/* Didn't get all we wanted, so we have to split the chunk */
	fp = split_movelist(copysrc, copylen, fp);	/* Is this right? */
	f = *fp;
    }

    mv = new_movelist(f->dst, f->src, f->len);
    dprintf("A: 0x%08x bytes at 0x%08x -> 0x%08x\n", mv->len, mv->src, mv->dst);
    **moves = mv;
    *moves = &mv->next;

    /* Figure out what memory we just freed up */
    if (f->dst > f->src) {
	freebase = f->src;
	freelen = min(f->len, f->dst - f->src);
    } else if (f->src >= f->dst + f->len) {
	freebase = f->src;
	freelen = f->len;
    } else {
	freelen = f->src - f->dst;
	freebase = f->dst + f->len;
    }

    dprintf("F: 0x%08x bytes at 0x%08x\n", freelen, freebase);

    add_freelist(mmap, freebase, freelen, SMT_FREE);

    delete_movelist(fp);
}

/*
 * moves is computed from "frags" and "freemem".  "space" lists
 * free memory areas at our disposal, and is (src, cnt) only.
 */
int
syslinux_compute_movelist(struct syslinux_movelist **moves,
			  struct syslinux_movelist *ifrags,
			  struct syslinux_memmap *memmap)
{
    struct syslinux_memmap *mmap = NULL;
    const struct syslinux_memmap *mm, *ep;
    struct syslinux_movelist *frags = NULL;
    struct syslinux_movelist *postcopy = NULL;
    struct syslinux_movelist *mv;
    struct syslinux_movelist *f, **fp;
    struct syslinux_movelist *o, **op;
    addr_t needbase, needlen, copysrc, copydst, copylen;
    addr_t avail;
    addr_t fstart, flen;
    addr_t cbyte;
    addr_t ep_len;
    int rv = -1;
    int reverse;

    dprintf("entering syslinux_compute_movelist()...\n");

    if (setjmp(new_movelist_bail)) {
nomem:
	dprintf("Out of working memory!\n");
	goto bail;
    }

    *moves = NULL;

    /* Create our memory map.  Anything that is SMT_FREE or SMT_ZERO is
       fair game, but mark anything used by source material as SMT_ALLOC. */
    mmap = syslinux_init_memmap();
    if (!mmap)
	goto nomem;

    frags = dup_movelist(ifrags);

    /* Process one-to-many conditions */
    shuffle_dealias(&frags, &postcopy);

    for (mm = memmap; mm->type != SMT_END; mm = mm->next)
	add_freelist(&mmap, mm->start, mm->next->start - mm->start,
		     mm->type == SMT_ZERO ? SMT_FREE : mm->type);

    for (f = frags; f; f = f->next)
	add_freelist(&mmap, f->src, f->len, SMT_ALLOC);

    /* As long as there are unprocessed fragments in the chain... */
    while ((fp = &frags, f = *fp)) {

	dprintf("Current free list:\n");
	syslinux_dump_memmap(mmap);
	dprintf("Current frag list:\n");
	syslinux_dump_movelist(frags);

	/* Scan for fragments which can be discarded without action. */
	if (f->src == f->dst) {
	    delete_movelist(fp);
	    continue;
	}
	op = &f->next;
	while ((o = *op)) {
	    if (o->src == o->dst)
		delete_movelist(op);
	    else
		op = &o->next;
	}

	/* Scan for fragments which can be immediately moved
	   to their final destination, if so handle them now */
	for (op = fp; (o = *op); op = &o->next) {
	    if (o->src < o->dst && (o->dst - o->src) < o->len) {
		/* "Shift up" type overlap */
		needlen = o->dst - o->src;
		needbase = o->dst + (o->len - needlen);
		reverse = 1;
		cbyte = o->dst + o->len - 1;
	    } else if (o->src > o->dst && (o->src - o->dst) < o->len) {
		/* "Shift down" type overlap */
		needlen = o->src - o->dst;
		needbase = o->dst;
		reverse = 0;
		cbyte = o->dst;	/* "Critical byte" */
	    } else {
		needlen = o->len;
		needbase = o->dst;
		reverse = 0;
		cbyte = o->dst;	/* "Critical byte" */
	    }

	    if (is_free_zone(mmap, needbase, needlen)) {
		fp = op, f = o;
		dprintf("!: 0x%08x bytes at 0x%08x -> 0x%08x\n",
			f->len, f->src, f->dst);
		copysrc = f->src;
		copylen = needlen;
		allocate_from(&mmap, needbase, copylen);
		goto move_chunk;
	    }
	}

	/* Ok, bother.  Need to do real work at least with one chunk. */

	dprintf("@: 0x%08x bytes at 0x%08x -> 0x%08x\n",
		f->len, f->src, f->dst);

	/* See if we can move this chunk into place by claiming
	   the destination, or in the case of partial overlap, the
	   missing portion. */

	if (f->src < f->dst && (f->dst - f->src) < f->len) {
	    /* "Shift up" type overlap */
	    needlen = f->dst - f->src;
	    needbase = f->dst + (f->len - needlen);
	    reverse = 1;
	    cbyte = f->dst + f->len - 1;
	} else if (f->src > f->dst && (f->src - f->dst) < f->len) {
	    /* "Shift down" type overlap */
	    needlen = f->src - f->dst;
	    needbase = f->dst;
	    reverse = 0;
	    cbyte = f->dst;	/* "Critical byte" */
	} else {
	    needlen = f->len;
	    needbase = f->dst;
	    reverse = 0;
	    cbyte = f->dst;
	}

	dprintf("need: base = 0x%08x, len = 0x%08x, "
		"reverse = %d, cbyte = 0x%08x\n",
		needbase, needlen, reverse, cbyte);

	ep = is_free_zone(mmap, cbyte, 1);
	if (ep) {
	    ep_len = ep->next->start - ep->start;
	    if (reverse)
		avail = needbase + needlen - ep->start;
	    else
		avail = ep_len - (needbase - ep->start);
	} else {
	    avail = 0;
	}

	if (avail) {
	    /* We can move at least part of this chunk into place without
	       further ado */
	    dprintf("space: start 0x%08x, len 0x%08x, free 0x%08x\n",
		    ep->start, ep_len, avail);
	    copylen = min(needlen, avail);

	    if (reverse)
		allocate_from(&mmap, needbase + needlen - copylen, copylen);
	    else
		allocate_from(&mmap, needbase, copylen);

	    goto move_chunk;
	}

	/* At this point, we need to evict something out of our space.
	   Find the object occupying the critical byte of our target space,
	   and move it out (the whole object if we can, otherwise a subset.)
	   Then move a chunk of ourselves into place. */
	for (op = &f->next, o = *op; o; op = &o->next, o = *op) {

	    dprintf("O: 0x%08x bytes at 0x%08x -> 0x%08x\n",
		    o->len, o->src, o->dst);

	    if (!(o->src <= cbyte && o->src + o->len > cbyte))
		continue;	/* Not what we're looking for... */

	    /* Find somewhere to put it... */

	    if (is_free_zone(mmap, o->dst, o->len)) {
		/* Score!  We can move it into place directly... */
		copydst = o->dst;
		copysrc = o->src;
		copylen = o->len;
	    } else if (free_area(mmap, o->len, &fstart)) {
		/* We can move the whole chunk */
		copydst = fstart;
		copysrc = o->src;
		copylen = o->len;
	    } else {
		/* Well, copy as much as we can... */
		if (syslinux_memmap_largest(mmap, SMT_FREE, &fstart, &flen)) {
		    dprintf("No free memory at all!\n");
		    goto bail;	/* Stuck! */
		}

		/* Make sure we include the critical byte */
		copydst = fstart;
		if (reverse) {
		    copysrc = max(o->src, cbyte + 1 - flen);
		    copylen = cbyte + 1 - copysrc;
		} else {
		    copysrc = cbyte;
		    copylen = min(flen, o->len - (cbyte - o->src));
		}
	    }
	    allocate_from(&mmap, copydst, copylen);

	    if (copylen < o->len) {
		op = split_movelist(copysrc, copylen, op);
		o = *op;
	    }

	    mv = new_movelist(copydst, copysrc, copylen);
	    dprintf("C: 0x%08x bytes at 0x%08x -> 0x%08x\n",
		    mv->len, mv->src, mv->dst);
	    *moves = mv;
	    moves = &mv->next;

	    o->src = copydst;

	    if (copylen > needlen) {
		/* We don't need all the memory we freed up.  Mark it free. */
		if (copysrc < needbase) {
		    add_freelist(&mmap, copysrc, needbase - copysrc, SMT_FREE);
		    copylen -= (needbase - copysrc);
		}
		if (copylen > needlen) {
		    add_freelist(&mmap, copysrc + needlen, copylen - needlen,
				 SMT_FREE);
		    copylen = needlen;
		}
	    }
	    reverse = 0;
	    goto move_chunk;
	}
	dprintf("Cannot find the chunk containing the critical byte\n");
	goto bail;		/* Stuck! */

move_chunk:
	move_chunk(&moves, &mmap, fp, copylen);
    }

    /* Finally, append the postcopy chain to the end of the moves list */
    for (op = moves; (o = *op); op = &o->next) ;	/* Locate the end of the list */
    *op = postcopy;
    postcopy = NULL;

    rv = 0;
bail:
    if (mmap)
	syslinux_free_memmap(mmap);
    if (frags)
	free_movelist(&frags);
    if (postcopy)
	free_movelist(&postcopy);
    return rv;
}

#ifdef TEST

#include <stdio.h>

int main(int argc, char *argv[])
{
    FILE *f;
    unsigned long d, s, l;
    struct syslinux_movelist *frags;
    struct syslinux_movelist **fep = &frags;
    struct syslinux_movelist *mv, *moves;
    struct syslinux_memmap *memmap;
    char line[BUFSIZ];

    (void)argc;

    memmap = syslinux_init_memmap();

    f = fopen(argv[1], "r");
    while (fgets(line, sizeof line, f) != NULL) {
	if (sscanf(line, "%lx %lx %lx", &s, &d, &l) == 3) {
	    if (d) {
		if (s == -1UL) {
		    syslinux_add_memmap(&memmap, d, l, SMT_ZERO);
		} else {
		    mv = new_movelist(d, s, l);
		    *fep = mv;
		    fep = &mv->next;
		}
	    } else {
		syslinux_add_memmap(&memmap, s, l, SMT_FREE);
	    }
	}
    }
    fclose(f);

    *fep = NULL;

    dprintf("Input move list:\n");
    syslinux_dump_movelist(frags);
    dprintf("Input free list:\n");
    syslinux_dump_memmap(memmap);

    if (syslinux_compute_movelist(&moves, frags, memmap)) {
	printf("Failed to compute a move sequence\n");
	return 1;
    } else {
	dprintf("Final move list:\n");
	syslinux_dump_movelist(moves);
	return 0;
    }
}

#endif /* TEST */
