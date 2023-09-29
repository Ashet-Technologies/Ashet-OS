/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * menu.c
 *
 * Simple menu system which displays a list and allows the user to select
 * a command line and/or edit it.
 */

#include <consoles.h>
#include "menu.h"

int draw_background(const char *arg)
{
    /* Nothing to do... */
    (void)arg;
    return 0;
}

void set_resolution(int x, int y)
{
    (void)x;
    (void)y;
}

void local_cursor_enable(bool enabled)
{
    (void)enabled;
}

void start_console(void)
{
    console_ansi_raw();
}
