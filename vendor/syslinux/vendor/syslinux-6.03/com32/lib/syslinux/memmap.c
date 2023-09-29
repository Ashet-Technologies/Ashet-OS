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
 * memmap.c
 *
 * Create initial memory map for "shuffle and boot" operation
 */

#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <inttypes.h>

#include <syslinux/memscan.h>
#include <syslinux/movebits.h>

static int syslinux_memory_map_callback(void *map, addr_t start, addr_t len,
					enum syslinux_memmap_types type)
{
    struct syslinux_memmap **mmap = map;
    return syslinux_add_memmap(mmap, start, len, type);
}

struct syslinux_memmap *syslinux_memory_map(void)
{
    struct syslinux_memmap *mmap;

    mmap = syslinux_init_memmap();
    if (!mmap)
	return NULL;

    if (syslinux_scan_memory(syslinux_memory_map_callback, &mmap)) {
	syslinux_free_memmap(mmap);
	return NULL;
    }

    return mmap;
}
