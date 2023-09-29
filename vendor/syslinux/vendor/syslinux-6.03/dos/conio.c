/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * conio.c
 *
 * Output to the screen
 */

#include <stdarg.h>
#include "mystuff.h"

int putchar(int ch)
{
    if (ch == '\n')
	putchar('\r');
asm("movb $0x02,%%ah ; int $0x21": :"d"(ch));
    return ch;
}

/* Note: doesn't put '\n' like the stdc version does */
int puts(const char *s)
{
    int count = 0;

    while (*s) {
	putchar(*s);
	count++;
	s++;
    }

    return count;
}
