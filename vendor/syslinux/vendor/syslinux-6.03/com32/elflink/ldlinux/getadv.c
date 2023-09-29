/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
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
 * syslinux/getadv.c
 *
 * Get a data item from the auxilliary data vector.  Returns a pointer
 * and sets *size on success; NULL on failure.
 */

#include <syslinux/adv.h>
#include <klibc/compiler.h>
#include <inttypes.h>

__export const void *syslinux_getadv(int tag, size_t * size)
{
    const uint8_t *p;
    size_t left;

    p = syslinux_adv_ptr();
    left = syslinux_adv_size();

    while (left >= 2) {
	uint8_t ptag = *p++;
	size_t plen = *p++;
	left -= 2;

	if (ptag == ADV_END)
	    return NULL;	/* Not found */

	if (left < plen)
	    return NULL;	/* Item overrun */

	if (ptag == tag) {
	    *size = plen;
	    return p;
	}

	p += plen;
	left -= plen;
    }

    return NULL;
}
