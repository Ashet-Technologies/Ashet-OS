
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
 * fancyhello.c
 *
 * Hello, World! using libcom32 and ANSI console; also possible to compile
 * as a Linux application for testing.
 */

#include <string.h>
#include <stdio.h>

#include <consoles.h>		/* Provided by libutil */

int main(void)
{
    char buffer[1024];

    console_ansi_std();

    printf("\033[1;33;44m *** \033[37mHello, World!\033[33m *** \033[0m\n");

    for (;;) {
	printf("\033[1;36m>\033[0m ");
	fgets(buffer, sizeof buffer, stdin);
	if (!strncmp(buffer, "exit", 4))
	    break;
	printf("\033[1m:\033[0m %s", buffer);
    }
    return 0;
}
