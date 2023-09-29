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
 * serialinfo.c
 *
 * Print serial port info
 */

#include <string.h>
#include <stdio.h>
#include <console.h>
#include <syslinux/config.h>

int main(void)
{
    const struct syslinux_serial_console_info *si;

#if 0
	/* this hangs! */
    openconsole(&dev_null_r, &dev_stdcon_w);
#else
	/* this works */
    openconsole(&dev_rawcon_r, &dev_ansiserial_w);
#endif

    si = syslinux_serial_console_info();

    printf("Serial port base:    %#06x\n", si->iobase);
    printf("Serial port divisor:  %5d", si->divisor);
    if (si->divisor)
	printf(" (%d baud)", 115200 / si->divisor);
    printf("\n" "Flow control bits:    %#05x\n", si->flowctl);

    return 0;
}
