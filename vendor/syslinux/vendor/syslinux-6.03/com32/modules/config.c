/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * config.c
 *
 * Loads a new configuration file
 *
 * Usage: config filename
 */

#include <stdio.h>
#include <console.h>
#include <syslinux/boot.h>

int main(int argc, char *argv[])
{
    if (argc < 2 || argc > 3) {
	fprintf(stderr, "Usage: config <filename> [<directory>]\n");
	return 1;
    }

    syslinux_run_kernel_image(argv[1], argv[2] ? argv[2] : "",
			      0, IMAGE_TYPE_CONFIG);

    fprintf(stderr, "config: %s: failed to load (missing file?)\n", argv[1]);
    return 1;
}
