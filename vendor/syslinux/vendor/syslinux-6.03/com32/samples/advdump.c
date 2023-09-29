/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * advdump.c
 *
 * Dump the contents of the syslinux ADV
 */

#include <stdio.h>
#include <console.h>
#include <syslinux/adv.h>
#include <string.h>

int main(void)
{
    uint8_t *p, *ep;
    size_t s = syslinux_adv_size();
    char buf[256];

#if 0
	/* this hangs! */
    openconsole(&dev_stdcon_r, &dev_stdcon_w);
#else
	/* this works */
    openconsole(&dev_rawcon_r, &dev_ansiserial_w);
#endif

    p = syslinux_adv_ptr();

    printf("ADV size: %zd bytes at %p\n", s, p);

    ep = p + s;			/* Need at least opcode+len */
    while (p < ep - 1 && *p) {
	int t = *p++;
	int l = *p++;

	if (p + l > ep)
	    break;

	memcpy(buf, p, l);
	buf[l] = '\0';

	printf("ADV %3d: \"%s\"\n", t, buf);

	p += l;
    }

    return 0;
}
