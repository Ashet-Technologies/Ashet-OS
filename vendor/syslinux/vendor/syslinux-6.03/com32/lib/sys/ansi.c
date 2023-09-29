/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

/*
 * ansi.c
 *
 * ANSI character code engine
 */

#include <string.h>
#include <colortbl.h>
#include "ansi.h"

static const struct term_state default_state = {
    .state = st_init,
    .pvt = false,
    .nparms = 0,
    .xy = {0, 0},
    .cindex = 0,		/* First color table entry */
    .vtgraphics = false,
    .intensity = 1,
    .underline = false,
    .blink = false,
    .reverse = false,
    .fg = 7,
    .bg = 0,
    .autocr = true,	  	/* Mimic \n -> \r\n conversion by default */
    .autowrap = true,		/* Wrap lines by default */
    .saved_xy = {0, 0},
    .cursor = true,
};

/* DEC VT graphics to codepage 437 table (characters 0x60-0x7F only) */
static const char decvt_to_cp437[] = {
    0004, 0261, 0007, 0007, 0007, 0007, 0370, 0361,
    0007, 0007, 0331, 0277, 0332, 0300, 0305, 0304,
    0304, 0304, 0137, 0137, 0303, 0264, 0301, 0302,
    0263, 0363, 0362, 0343, 0330, 0234, 0007, 00
};

void __ansi_init(const struct term_info *ti)
{
    memcpy(ti->ts, &default_state, sizeof default_state);
}

void __ansi_putchar(const struct term_info *ti, uint8_t ch)
{
    const struct ansi_ops *op = ti->op;
    struct term_state *st = ti->ts;
    const int rows = ti->rows;
    const int cols = ti->cols;
    struct curxy xy = st->xy;

    switch (st->state) {
    case st_init:
	switch (ch) {
	case 1 ... 5:
	    st->state = st_tbl;
	    st->parms[0] = ch;
	    break;
	case '\a':
	    op->beep();
	    break;
	case '\b':
	    if (xy.x > 0)
		xy.x--;
	    break;
	case '\t':
	    {
		int nsp = 8 - (xy.x & 7);
		while (nsp--)
		    __ansi_putchar(ti, ' ');
	    }
	    return;		/* Cursor already updated */
	case '\n':
	case '\v':
	case '\f':
	    xy.y++;
	    if (st->autocr)
		xy.x = 0;
	    break;
	case '\r':
	    xy.x = 0;
	    break;
	case 127:
	    /* Ignore delete */
	    break;
	case 14:
	    st->vtgraphics = 1;
	    break;
	case 15:
	    st->vtgraphics = 0;
	    break;
	case 27:
	    st->state = st_esc;
	    break;
	default:
	    /* Print character */
	    if (ch >= 32) {
		if (st->vtgraphics && (ch & 0xe0) == 0x60)
		    ch = decvt_to_cp437[ch - 0x60];

		op->write_char(xy.x, xy.y, ch, st);
		xy.x++;
	    }
	    break;
	}
	break;

    case st_esc:
	switch (ch) {
	case '%':
	case '(':
	case ')':
	case '#':
	    /* Ignore this plus the subsequent character, allows
	       compatibility with Linux sequence to set charset */
	    break;
	case '[':
	    st->state = st_csi;
	    st->nparms = 0;
	    st->pvt = false;
	    memset(st->parms, 0, sizeof st->parms);
	    break;
	case 'c':
	    /* Reset terminal */
	    memcpy(&st, &default_state, sizeof st);
	    op->erase(st, 0, 0, cols - 1, rows - 1);
	    xy.x = xy.y = 0;
	    st->state = st_init;
	    break;
	default:
	    /* Ignore sequence */
	    st->state = st_init;
	    break;
	}
	break;

    case st_csi:
	{
	    int p0 = st->parms[0] ? st->parms[0] : 1;

	    if (ch >= '0' && ch <= '9') {
		st->parms[st->nparms] = st->parms[st->nparms] * 10 + (ch - '0');
	    } else if (ch == ';') {
		st->nparms++;
		if (st->nparms >= ANSI_MAX_PARMS)
		    st->nparms = ANSI_MAX_PARMS - 1;
		break;
	    } else if (ch == '?') {
		st->pvt = true;
	    } else {
		switch (ch) {
		case 'A':
		    {
			int y = xy.y - p0;
			xy.y = (y < 0) ? 0 : y;
		    }
		    break;
		case 'B':
		    {
			int y = xy.y + p0;
			xy.y = (y >= rows) ? rows - 1 : y;
		    }
		    break;
		case 'C':
		    {
			int x = xy.x + p0;
			xy.x = (x >= cols) ? cols - 1 : x;
		    }
		    break;
		case 'D':
		    {
			int x = xy.x - p0;
			xy.x = (x < 0) ? 0 : x;
		    }
		    break;
		case 'E':
		    {
			int y = xy.y + p0;
			xy.y = (y >= rows) ? rows - 1 : y;
			xy.x = 0;
		    }
		    break;
		case 'F':
		    {
			int y = xy.y - p0;
			xy.y = (y < 0) ? 0 : y;
			xy.x = 0;
		    }
		    break;
		case 'G':
		case '\'':
		    {
			int x = st->parms[0] - 1;
			xy.x = (x >= cols) ? cols - 1 : (x < 0) ? 0 : x;
		    }
		    break;
		case 'H':
		case 'f':
		    {
			int y = st->parms[0] - 1;
			int x = st->parms[1] - 1;

			xy.x = (x >= cols) ? cols - 1 : (x < 0) ? 0 : x;
			xy.y = (y >= rows) ? rows - 1 : (y < 0) ? 0 : y;
		    }
		    break;
		case 'J':
		    {
			switch (st->parms[0]) {
			case 0:
			    op->erase(st, xy.x, xy.y, cols - 1, xy.y);
			    if (xy.y < rows - 1)
				op->erase(st, 0, xy.y + 1, cols - 1, rows - 1);
			    break;

			case 1:
			    if (xy.y > 0)
				op->erase(st, 0, 0, cols - 1, xy.y - 1);
			    if (xy.y > 0)
				op->erase(st, 0, xy.y, xy.x - 1, xy.y);
			    break;

			case 2:
			    op->erase(st, 0, 0, cols - 1, rows - 1);
			    break;

			default:
			    /* Ignore */
			    break;
			}
		    }
		    break;
		case 'K':
		    {
			switch (st->parms[0]) {
			case 0:
			    op->erase(st, xy.x, xy.y, cols - 1, xy.y);
			    break;

			case 1:
			    if (xy.x > 0)
				op->erase(st, 0, xy.y, xy.x - 1, xy.y);
			    break;

			case 2:
			    op->erase(st, 0, xy.y, cols - 1, xy.y);
			    break;

			default:
			    /* Ignore */
			    break;
			}
		    }
		    break;
		case 'h':
		case 'l':
		{
		    bool set = (ch == 'h');
		    switch (st->parms[0]) {
		    case 7:	/* DECAWM */
			st->autowrap = set;
			break;
		    case 20:	/* LNM */
			st->autocr = set;
			break;
		    case 25:	/* DECTECM */
			st->cursor = set;
			op->showcursor(st);
			break;
		    default:
			/* Ignore */
			break;
		    }
		    break;
		}
		case 'm':
		    {
			static const int ansi2pc[8] =
			    { 0, 4, 2, 6, 1, 5, 3, 7 };

			int i;
			for (i = 0; i <= st->nparms; i++) {
			    int a = st->parms[i];
			    switch (a) {
			    case 0:
				st->fg = 7;
				st->bg = 0;
				st->intensity = 1;
				st->underline = 0;
				st->blink = 0;
				st->reverse = 0;
				break;
			    case 1:
				st->intensity = 2;
				break;
			    case 2:
				st->intensity = 0;
				break;
			    case 4:
				st->underline = 1;
				break;
			    case 5:
				st->blink = 1;
				break;
			    case 7:
				st->reverse = 1;
				break;
			    case 21:
			    case 22:
				st->intensity = 1;
				break;
			    case 24:
				st->underline = 0;
				break;
			    case 25:
				st->blink = 0;
				break;
			    case 27:
				st->reverse = 0;
				break;
			    case 30 ... 37:
				st->fg = ansi2pc[a - 30];
				break;
			    case 38:
				st->fg = 7;
				st->underline = 1;
				break;
			    case 39:
				st->fg = 7;
				st->underline = 0;
				break;
			    case 40 ... 47:
				st->bg = ansi2pc[a - 40];
				break;
			    case 49:
				st->bg = 7;
				break;
			    default:
				/* Do nothing */
				break;
			    }
			}
		    }
		    break;
		case 's':
		    st->saved_xy = xy;
		    break;
		case 'u':
		    xy = st->saved_xy;
		    break;
		default:	/* Includes CAN and SUB */
		    break;	/* Drop unknown sequence */
		}
		st->state = st_init;
	    }
	}
	break;

    case st_tbl:
	st->parms[1] = 0;
	if (ch == '#')
	    st->state = st_tblc;
	else
	    st->state = st_init;
	break;

    case st_tblc:
	{
	    unsigned int n = (unsigned char)ch - '0';
	    const char *p;

	    if (n < 10) {
		st->parms[1] = st->parms[1] * 10 + n;

		if (!--st->parms[0]) {
		    if (st->parms[1] < console_color_table_size) {
			/* Set the color table index */
			st->cindex = st->parms[1];

			/* See if there are any other attributes we care about */
			p = console_color_table[st->parms[1]].ansi;
			if (p) {
			    st->state = st_esc;
			    __ansi_putchar(ti, '[');
			    __ansi_putchar(ti, '0');
			    __ansi_putchar(ti, ';');
			    while (*p)
				__ansi_putchar(ti, *p++);
			    __ansi_putchar(ti, 'm');
			}
		    }
		    st->state = st_init;
		}
	    } else {
		st->state = st_init;
	    }
	}
	break;
    }

    /* If we fell off the end of the screen, adjust */
    if (xy.x >= cols) {
	if (st->autowrap) {
	    xy.x = 0;
	    xy.y++;
	} else {
	    xy.x = cols - 1;
	}
    }
    while (xy.y >= rows) {
	xy.y--;
	op->scroll_up(st);
    }

    /* Update cursor position */
    op->set_cursor(xy.x, xy.y, st->cursor);
    st->xy = xy;
}
