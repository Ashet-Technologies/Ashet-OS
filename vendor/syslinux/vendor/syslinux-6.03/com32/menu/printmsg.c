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

#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <consoles.h>
#include <getkey.h>
#include <minmax.h>
#include <setjmp.h>
#include <limits.h>
#include <sha1.h>
#include <base64.h>
#include <colortbl.h>
#ifdef __COM32__
#include <com32.h>
#endif

#include "menu.h"

static int draw_message_file(const char *filename)
{
    FILE *f;
    int ch;
    enum msgname_state {
	st_init,		/* Base state */
	st_si_1,		/* <SI> digit 1 */
	st_si_2,		/* <SI> digit 2 */
	st_skipline,		/* Skip until NL */
    } state = st_init;
    int eof = 0;
    int attr = 0;

    f = fopen(filename, "r");
    if (!f)
	return -1;

    /* Clear screen, hide cursor, default attribute */
    printf("\033e\033%%@\033)0\033(B\3#%03d\033[?25l\033[2J\033[H",
	   message_base_color + 0x07);

    while (!eof && (ch = getc(f)) != EOF) {
	switch (state) {
	case st_init:
	    switch (ch) {
	    case '\f':
		fputs("\033[2J\033[H", stdout);
		break;
	    case 15:		/* SI */
		state = st_si_1;
		break;
	    case 24:
		state = st_skipline;
		break;
	    case 26:
		eof = 1;
		break;
	    case '\a':
	    case '\n':
	    case '\r':
		putchar(ch);
		break;
	    default:
		if (ch >= 32)
		    putchar(ch);
		break;
	    }
	    break;

	case st_si_1:
	    attr = hexval(ch) << 4;
	    state = st_si_2;
	    break;

	case st_si_2:
	    attr |= hexval(ch);
	    printf("\3#%03d", attr + message_base_color);
	    state = st_init;
	    break;

	case st_skipline:
	    if (ch == '\n')
		state = st_init;
	    break;
	}
    }

    fclose(f);
    return 0;
}

int show_message_file(const char *filename, const char *background)
{
    int rv = KEY_NONE;
    const char *old_background = NULL;

    if (background) {
	old_background = current_background;
	set_background(background);
    }

    if (!(rv = draw_message_file(filename)))
	rv = mygetkey(0);	/* Wait for keypress */

    if (old_background)
	set_background(old_background);

    return rv;
}
