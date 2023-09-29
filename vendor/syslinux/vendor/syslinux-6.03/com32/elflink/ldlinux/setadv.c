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
 * syslinux/setadv.c
 *
 * (Over)write a data item in the auxilliary data vector.  To
 * delete an item, set its length to zero.
 *
 * Return 0 on success, -1 on error, and set errno.
 *
 * NOTE: Data is not written to disk unless
 * syslinux_adv_write() is called.
 */

#include <syslinux/adv.h>
#include <klibc/compiler.h>
#include <inttypes.h>
#include <string.h>
#include <errno.h>
#include <alloca.h>

__export int syslinux_setadv(int tag, size_t size, const void *data)
{
    uint8_t *p, *advtmp;
    size_t rleft, left;

    if ((unsigned)tag - 1 > 254) {
	errno = EINVAL;
	return -1;		/* Impossible tag value */
    }

    if (size > 255) {
	errno = ENOSPC;		/* Max 255 bytes for a data item */
	return -1;
    }

    rleft = left = syslinux_adv_size();
    p = advtmp = alloca(left);
    memcpy(p, syslinux_adv_ptr(), left);	/* Make working copy */

    while (rleft >= 2) {
	uint8_t ptag = p[0];
	size_t plen = p[1] + 2;

	if (ptag == ADV_END)
	    break;

	if (ptag == tag) {
	    /* Found our tag.  Delete it. */

	    if (plen >= rleft) {
		/* Entire remainder is our tag */
		break;
	    }
	    memmove(p, p + plen, rleft - plen);
	    rleft -= plen;	/* Fewer bytes to read, but not to write */
	} else {
	    /* Not our tag */
	    if (plen > rleft)
		break;		/* Corrupt tag (overrun) - overwrite it */

	    left -= plen;
	    rleft -= plen;
	    p += plen;
	}
    }

    /* Now (p, left) reflects the position to write in and how much space
       we have for our data. */

    if (size) {
	if (left < size + 2) {
	    errno = ENOSPC;	/* Not enough space for data */
	    return -1;
	}

	*p++ = tag;
	*p++ = size;
	memcpy(p, data, size);
	p += size;
	left -= size + 2;
    }

    memset(p, 0, left);

    /* If we got here, everything went OK, commit the write to low memory */
    memcpy(syslinux_adv_ptr(), advtmp, syslinux_adv_size());

    return 0;
}
