/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <consoles.h>
#include <string.h>
#include "menu.h"

const char *current_background = NULL;

void set_background(const char *new_background)
{
    if (!current_background || !new_background ||
	strcmp(current_background, new_background)) {
	draw_background(new_background);
	current_background = new_background;
    }
}
