/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * vesamenu.c
 *
 * Simple menu system which displays a list and allows the user to select
 * a command line and/or edit it.
 *
 * VESA graphics version.
 */

#include <stdio.h>
#include <console.h>
#include <syslinux/vesacon.h>

#include "menu.h"

int draw_background(const char *what)
{
    if (!what)
	return vesacon_default_background();
    else if (what[0] == '#')
	return vesacon_set_background(parse_argb((char **)&what));
    else
	return vesacon_load_background(what);
}

void set_resolution(int x, int y)
{
    vesacon_set_resolution(x, y);
}

void local_cursor_enable(bool enabled)
{
    vesacon_cursor_enable(enabled);
}

void start_console(void)
{
    openconsole(&dev_rawcon_r, &dev_vesaserial_w);
}
