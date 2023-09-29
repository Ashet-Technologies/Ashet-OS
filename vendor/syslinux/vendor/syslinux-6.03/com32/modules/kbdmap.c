/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdio.h>
#include <string.h>
#include <console.h>
#include <syslinux/loadfile.h>
#include <syslinux/keyboard.h>

static inline void error(const char *msg)
{
    fputs(msg, stderr);
}

int main(int argc, char *argv[])
{
    const struct syslinux_keyboard_map *const kmap = syslinux_keyboard_map();
    size_t map_size;
    void *kbdmap;

    if (argc != 2) {
	error("Usage: kbdmap mapfile\n");
	return 1;
    }

    if (kmap->version != 1) {
	error("Syslinux core version mismatch\n");
	return 1;
    }

    if (loadfile(argv[1], &kbdmap, &map_size)) {
	error("Keyboard map file load error\n");
	return 1;
    }

    if (map_size != kmap->length) {
	error("Keyboard map file format error\n");
	return 1;
    }

    memcpy(kmap->map, kbdmap, map_size);
    return 0;
}
