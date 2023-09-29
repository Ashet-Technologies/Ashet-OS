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
 * pxe_get_cached.c
 *
 * PXE call "get cached info"
 */

#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <com32.h>

#include <syslinux/pxe.h>

/* Returns the status code from PXE (0 on success),
   or -1 on invocation failure */
int pxe_get_cached_info(int level, void **buf, size_t * len)
{
    const int max_dhcp_packet = 2048;
    t_PXENV_GET_CACHED_INFO *gci;
    void *bbuf, *nbuf;
    int err;

    gci = lmalloc(sizeof *gci + max_dhcp_packet);
    if (!gci)
	return -1;

    bbuf = &gci[1];

    gci->Status = PXENV_STATUS_FAILURE;
    gci->PacketType = level;
    gci->BufferSize = gci->BufferLimit = max_dhcp_packet;
    gci->Buffer.seg = SEG(bbuf);
    gci->Buffer.offs = OFFS(bbuf);

    err = pxe_call(PXENV_GET_CACHED_INFO, gci);

    if (err) {
	err = -1;
	goto exit;
    }

    if (gci->Status) {
	err = gci->Status;
	goto exit;
    }

    nbuf = malloc(gci->BufferSize);
    if (!nbuf) {
	err = -1;
	goto exit;
    }

    memcpy(nbuf, bbuf, gci->BufferSize);

    *buf = nbuf;
    *len = gci->BufferSize;
    err = 0;

exit:
    lfree(gci);
    return err;
}
