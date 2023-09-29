/* -*- c -*- ------------------------------------------------------------- *
 *
 *   Copyright 2004-2006 Murali Krishnan Ganapathy - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#ifndef NULL
#define NULL ((void *) 0)
#endif

#include "help.h"
#include "com32io.h"
#include "cmenu.h"
#include "tui.h"
#include <stdlib.h>
#include <com32.h>
#include <stdio.h>

int main(int argc, char *argv[])
{
    if (argc < 2) {
	csprint("Usage: display.c32 <textfile>\n", 0x07);
	exit(1);
    }

    init_help(NULL);		// No base dir, so all filenames must be absolute
    runhelp(argv[1]);
    close_help();
    return 0;
}
