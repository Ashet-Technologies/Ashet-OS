/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * resolv.c
 *
 * Resolve an IP address
 */

#include <syslinux/pxe_api.h>
#include <string.h>
#include <stdio.h>
#include <console.h>
#include <stdlib.h>
#include <com32.h>

uint32_t resolv(const char *name)
{
    return dns_resolv(name);
}

int main(int argc, char *argv[])
{
    uint32_t ip;

#if 0
	/* this hangs! */
    openconsole(&dev_null_r, &dev_stdcon_w);
#else
	/* this works */
    openconsole(&dev_rawcon_r, &dev_ansiserial_w);
#endif

    if (argc < 2) {
	fputs("Usage: resolv hostname\n", stderr);
	exit(1);
    }

    ip = resolv(argv[1]);

    if (ip) {
	printf("%s = %u.%u.%u.%u\n", argv[1],
	       (ip & 0xff), (ip >> 8) & 0xff,
	       (ip >> 16) & 0xff, (ip >> 24) & 0xff);
    } else {
	printf("%s not found\n", argv[1]);
    }

    return 0;
}
