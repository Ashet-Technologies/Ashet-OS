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
 * initramfs.c
 *
 * Utility functions for initramfs manipulation
 */

#include <stdlib.h>
#include <syslinux/linux.h>

struct initramfs *initramfs_init(void)
{
    struct initramfs *ir;

    ir = calloc(sizeof(*ir), 1);
    if (!ir)
	return NULL;

    ir->prev = ir->next = ir;
    return ir;
}

int initramfs_add_data(struct initramfs *ihead, const void *data,
		       size_t data_len, size_t len, size_t align)
{
    struct initramfs *in;

    if (!len)
	return 0;		/* Nothing to add... */

    /* Alignment must be a power of 2, and <= INITRAMFS_MAX_ALIGN */
    if (!align || (align & (align - 1)) || align > INITRAMFS_MAX_ALIGN)
	return -1;

    in = malloc(sizeof(*in));
    if (!in)
	return -1;

    in->len = len;
    in->data = data;
    in->data_len = data_len;
    in->align = align;

    in->next = ihead;
    in->prev = ihead->prev;
    ihead->prev->next = in;
    ihead->prev = in;

    return 0;
}
