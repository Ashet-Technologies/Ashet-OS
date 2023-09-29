/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2013 Intel Corporation; author: Matt Fleming
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <syslinux/debug.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *progname;

static void usage(void)
{
    fprintf(stderr, "Usage: %s [-e|-d] <func1> [<func2>, ...]\n", progname);
}

int main(int argc, char *argv[])
{
    bool enable;
    int i;

    progname = argv[0];

    if (argc < 3) {
	usage();
	return -1;
    }

    if (!strncmp(argv[1], "-e", 2))
	enable = true;
    else if (!strncmp(argv[1], "-d", 2))
	enable = false;
    else {
	usage();
	return -1;
    }

    for (i = 2; i < argc; i++) {
	char *str = argv[i];

	if (syslinux_debug(str, enable) < 0)
	    fprintf(stderr, "Failed to debug symbol \"%s\"\n", str);
    }

    return 0;
}
