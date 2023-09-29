/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2014 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * menumain.c
 *
 * Simple menu system which displays a list and allows the user to select
 * a command line and/or edit it.
 */

#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <consoles.h>
#include <getkey.h>
#include <minmax.h>
#include <setjmp.h>
#include <limits.h>
#include <com32.h>
#include <core.h>
#include <syslinux/adv.h>
#include <syslinux/boot.h>

#include "menu.h"

/* The symbol "cm" always refers to the current menu across this file... */
static struct menu *cm;

const struct menu_parameter mparm[NPARAMS] = {
    [P_WIDTH] = {"width", 0},
    [P_MARGIN] = {"margin", 10},
    [P_PASSWD_MARGIN] = {"passwordmargin", 3},
    [P_MENU_ROWS] = {"rows", 12},
    [P_TABMSG_ROW] = {"tabmsgrow", 18},
    [P_CMDLINE_ROW] = {"cmdlinerow", 18},
    [P_END_ROW] = {"endrow", -1},
    [P_PASSWD_ROW] = {"passwordrow", 11},
    [P_TIMEOUT_ROW] = {"timeoutrow", 20},
    [P_HELPMSG_ROW] = {"helpmsgrow", 22},
    [P_HELPMSGEND_ROW] = {"helpmsgendrow", -1},
    [P_HSHIFT] = {"hshift", 0},
    [P_VSHIFT] = {"vshift", 0},
    [P_HIDDEN_ROW] = {"hiddenrow", -2},
};

/* These macros assume "cm" is a pointer to the current menu */
#define WIDTH		(cm->mparm[P_WIDTH])
#define MARGIN		(cm->mparm[P_MARGIN])
#define PASSWD_MARGIN	(cm->mparm[P_PASSWD_MARGIN])
#define MENU_ROWS	(cm->mparm[P_MENU_ROWS])
#define TABMSG_ROW	(cm->mparm[P_TABMSG_ROW]+VSHIFT)
#define CMDLINE_ROW	(cm->mparm[P_CMDLINE_ROW]+VSHIFT)
#define END_ROW		(cm->mparm[P_END_ROW])
#define PASSWD_ROW	(cm->mparm[P_PASSWD_ROW]+VSHIFT)
#define TIMEOUT_ROW	(cm->mparm[P_TIMEOUT_ROW]+VSHIFT)
#define HELPMSG_ROW	(cm->mparm[P_HELPMSG_ROW]+VSHIFT)
#define HELPMSGEND_ROW	(cm->mparm[P_HELPMSGEND_ROW])
#define HSHIFT		(cm->mparm[P_HSHIFT])
#define VSHIFT		(cm->mparm[P_VSHIFT])
#define HIDDEN_ROW	(cm->mparm[P_HIDDEN_ROW])

static char *pad_line(const char *text, int align, int width)
{
    static char buffer[MAX_CMDLINE_LEN];
    int n, p;

    if (width >= (int)sizeof buffer)
	return NULL;		/* Can't do it */

    n = strlen(text);
    if (n >= width)
	n = width;

    memset(buffer, ' ', width);
    buffer[width] = 0;
    p = ((width - n) * align) >> 1;
    memcpy(buffer + p, text, n);

    return buffer;
}

/* Display an entry, with possible hotkey highlight.  Assumes
   that the current attribute is the non-hotkey one, and will
   guarantee that as an exit condition as well. */
static void
display_entry(const struct menu_entry *entry, const char *attrib,
	      const char *hotattrib, int width)
{
    const char *p = entry->displayname;
    char marker;

    if (!p)
	p = "";

    switch (entry->action) {
    case MA_SUBMENU:
	marker = '>';
	break;
    case MA_EXIT:
	marker = '<';
	break;
    default:
	marker = 0;
	break;
    }

    if (marker)
	width -= 2;

    while (width) {
	if (*p) {
	    if (*p == '^') {
		p++;
		if (*p && ((unsigned char)*p & ~0x20) == entry->hotkey) {
		    fputs(hotattrib, stdout);
		    putchar(*p++);
		    fputs(attrib, stdout);
		    width--;
		}
	    } else {
		putchar(*p++);
		width--;
	    }
	} else {
	    putchar(' ');
	    width--;
	}
    }

    if (marker) {
	putchar(' ');
	putchar(marker);
    }
}

static void draw_row(int y, int sel, int top, int sbtop, int sbbot)
{
    int i = (y - 4 - VSHIFT) + top;
    int dis = (i < cm->nentries) && is_disabled(cm->menu_entries[i]);

    printf("\033[%d;%dH\1#1\016x\017%s ",
	   y, MARGIN + 1 + HSHIFT,
	   (i == sel) ? "\1#5" : dis ? "\2#17" : "\1#3");

    if (i >= cm->nentries) {
	fputs(pad_line("", 0, WIDTH - 2 * MARGIN - 4), stdout);
    } else {
	display_entry(cm->menu_entries[i],
		      (i == sel) ? "\1#5" : dis ? "\2#17" : "\1#3",
		      (i == sel) ? "\1#6" : dis ? "\2#17" : "\1#4",
		      WIDTH - 2 * MARGIN - 4);
    }

    if (cm->nentries <= MENU_ROWS) {
	printf(" \1#1\016x\017");
    } else if (sbtop > 0) {
	if (y >= sbtop && y <= sbbot)
	    printf(" \1#7\016a\017");
	else
	    printf(" \1#1\016x\017");
    } else {
	putchar(' ');		/* Don't modify the scrollbar */
    }
}

static jmp_buf timeout_jump;

int mygetkey(clock_t timeout)
{
    clock_t t0, t;
    clock_t tto, to;
    int key;

    if (!totaltimeout)
	return get_key(stdin, timeout);

    for (;;) {
	tto = min(totaltimeout, INT_MAX);
	to = timeout ? min(tto, timeout) : tto;

	t0 = times(NULL);
	key = get_key(stdin, to);
	t = times(NULL) - t0;

	if (totaltimeout <= t)
	    longjmp(timeout_jump, 1);

	totaltimeout -= t;

	if (key != KEY_NONE)
	    return key;

	if (timeout) {
	    if (timeout <= t)
		return KEY_NONE;

	    timeout -= t;
	}
    }
}

static int ask_passwd(const char *menu_entry)
{
    char user_passwd[WIDTH], *p;
    int done;
    int key;
    int x;
    int rv;

    printf("\033[%d;%dH\2#11\016l", PASSWD_ROW, PASSWD_MARGIN + 1);
    for (x = 2; x <= WIDTH - 2 * PASSWD_MARGIN - 1; x++)
	putchar('q');

    printf("k\033[%d;%dHx", PASSWD_ROW + 1, PASSWD_MARGIN + 1);
    for (x = 2; x <= WIDTH - 2 * PASSWD_MARGIN - 1; x++)
	putchar(' ');

    printf("x\033[%d;%dHm", PASSWD_ROW + 2, PASSWD_MARGIN + 1);
    for (x = 2; x <= WIDTH - 2 * PASSWD_MARGIN - 1; x++)
	putchar('q');

    printf("j\017\033[%d;%dH\2#12 %s \033[%d;%dH\2#13",
	   PASSWD_ROW, (WIDTH - (strlen(cm->messages[MSG_PASSPROMPT]) + 2)) / 2,
	   cm->messages[MSG_PASSPROMPT], PASSWD_ROW + 1, PASSWD_MARGIN + 3);

    drain_keyboard();

    /* Actually allow user to type a password, then compare to the SHA1 */
    done = 0;
    p = user_passwd;

    while (!done) {
	key = mygetkey(0);

	switch (key) {
	case KEY_ENTER:
	case KEY_CTRL('J'):
	    done = 1;
	    break;

	case KEY_ESC:
	case KEY_CTRL('C'):
	    p = user_passwd;	/* No password entered */
	    done = 1;
	    break;

	case KEY_BACKSPACE:
	case KEY_DEL:
	case KEY_DELETE:
	    if (p > user_passwd) {
		printf("\b \b");
		p--;
	    }
	    break;

	case KEY_CTRL('U'):
	    while (p > user_passwd) {
		printf("\b \b");
		p--;
	    }
	    break;

	default:
	    if (key >= ' ' && key <= 0xFF &&
		(p - user_passwd) < WIDTH - 2 * PASSWD_MARGIN - 5) {
		*p++ = key;
		putchar('*');
	    }
	    break;
	}
    }

    if (p == user_passwd)
	return 0;		/* No password entered */

    *p = '\0';

    rv = (cm->menu_master_passwd &&
	  passwd_compare(cm->menu_master_passwd, user_passwd))
	|| (menu_entry && passwd_compare(menu_entry, user_passwd));

    /* Clean up */
    memset(user_passwd, 0, WIDTH);
    drain_keyboard();

    return rv;
}

static void draw_menu(int sel, int top, int edit_line)
{
    int x, y;
    int sbtop = 0, sbbot = 0;
    const char *tabmsg;
    int tabmsg_len;

    if (cm->nentries > MENU_ROWS) {
	int sblen = max(MENU_ROWS * MENU_ROWS / cm->nentries, 1);
	sbtop = (MENU_ROWS - sblen + 1) * top / (cm->nentries - MENU_ROWS + 1);
	sbbot = sbtop + sblen - 1;
	sbtop += 4;
	sbbot += 4;		/* Starting row of scrollbar */
    }

    printf("\033[%d;%dH\1#1\016l", VSHIFT + 1, HSHIFT + MARGIN + 1);
    for (x = 2 + HSHIFT; x <= (WIDTH - 2 * MARGIN - 1) + HSHIFT; x++)
	putchar('q');

    printf("k\033[%d;%dH\1#1x\017\1#2 %s \1#1\016x",
	   VSHIFT + 2,
	   HSHIFT + MARGIN + 1, pad_line(cm->title, 1, WIDTH - 2 * MARGIN - 4));

    printf("\033[%d;%dH\1#1t", VSHIFT + 3, HSHIFT + MARGIN + 1);
    for (x = 2 + HSHIFT; x <= (WIDTH - 2 * MARGIN - 1) + HSHIFT; x++)
	putchar('q');
    fputs("u\017", stdout);

    for (y = 4 + VSHIFT; y < 4 + VSHIFT + MENU_ROWS; y++)
	draw_row(y, sel, top, sbtop, sbbot);

    printf("\033[%d;%dH\1#1\016m", y, HSHIFT + MARGIN + 1);
    for (x = 2 + HSHIFT; x <= (WIDTH - 2 * MARGIN - 1) + HSHIFT; x++)
	putchar('q');
    fputs("j\017", stdout);

    if (edit_line && cm->allowedit && !cm->menu_master_passwd)
	tabmsg = cm->messages[MSG_TAB];
    else
	tabmsg = cm->messages[MSG_NOTAB];

    tabmsg_len = strlen(tabmsg);

    printf("\1#8\033[%d;%dH%s",
	   TABMSG_ROW, 1 + HSHIFT + ((WIDTH - tabmsg_len) >> 1), tabmsg);
    printf("\1#0\033[%d;1H", END_ROW);
}

static void clear_screen(void)
{
    fputs("\033e\033%@\033)0\033(B\1#0\033[?25l\033[2J", stdout);
}

static void display_help(const char *text)
{
    int row;
    const char *p;

    if (!text) {
	text = "";
	printf("\1#0\033[%d;1H", HELPMSG_ROW);
    } else {
	printf("\2#16\033[%d;1H", HELPMSG_ROW);
    }

    for (p = text, row = HELPMSG_ROW; *p && row <= HELPMSGEND_ROW; p++) {
	switch (*p) {
	case '\r':
	case '\f':
	case '\v':
	case '\033':
	    break;
	case '\n':
	    printf("\033[K\033[%d;1H", ++row);
	    break;
	default:
	    putchar(*p);
	}
    }

    fputs("\033[K", stdout);

    while (row <= HELPMSGEND_ROW) {
	printf("\033[K\033[%d;1H", ++row);
    }
}

static void show_fkey(int key)
{
    int fkey;

    while (1) {
	switch (key) {
	case KEY_F1:
	    fkey = 0;
	    break;
	case KEY_F2:
	    fkey = 1;
	    break;
	case KEY_F3:
	    fkey = 2;
	    break;
	case KEY_F4:
	    fkey = 3;
	    break;
	case KEY_F5:
	    fkey = 4;
	    break;
	case KEY_F6:
	    fkey = 5;
	    break;
	case KEY_F7:
	    fkey = 6;
	    break;
	case KEY_F8:
	    fkey = 7;
	    break;
	case KEY_F9:
	    fkey = 8;
	    break;
	case KEY_F10:
	    fkey = 9;
	    break;
	case KEY_F11:
	    fkey = 10;
	    break;
	case KEY_F12:
	    fkey = 11;
	    break;
	default:
	    fkey = -1;
	    break;
	}

	if (fkey == -1)
	    break;

	if (cm->fkeyhelp[fkey].textname)
	    key = show_message_file(cm->fkeyhelp[fkey].textname,
				    cm->fkeyhelp[fkey].background);
	else
	    break;
    }
}

static const char *edit_cmdline(const char *input, int top)
{
    static char cmdline[MAX_CMDLINE_LEN];
    int key, len, prev_len, cursor;
    int redraw = 1;		/* We enter with the menu already drawn */

    strlcpy(cmdline, input, MAX_CMDLINE_LEN);
    cmdline[MAX_CMDLINE_LEN - 1] = '\0';

    len = cursor = strlen(cmdline);
    prev_len = 0;

    for (;;) {
	if (redraw > 1) {
	    /* Clear and redraw whole screen */
	    /* Enable ASCII on G0 and DEC VT on G1; do it in this order
	       to avoid confusing the Linux console */
	    clear_screen();
	    draw_menu(-1, top, 1);
	    prev_len = 0;
	}

	if (redraw > 0) {
	    /* Redraw the command line */
	    printf("\033[?25l\033[%d;1H\1#9> \2#10%s",
		   CMDLINE_ROW, pad_line(cmdline, 0, max(len, prev_len)));
	    printf("\2#10\033[%d;3H%s\033[?25h",
		   CMDLINE_ROW, pad_line(cmdline, 0, cursor));
	    prev_len = len;
	    redraw = 0;
	}

	key = mygetkey(0);

	switch (key) {
	case KEY_CTRL('L'):
	    redraw = 2;
	    break;

	case KEY_ENTER:
	case KEY_CTRL('J'):
	    return cmdline;

	case KEY_ESC:
	case KEY_CTRL('C'):
	    return NULL;

	case KEY_BACKSPACE:
	case KEY_DEL:
	    if (cursor) {
		memmove(cmdline + cursor - 1, cmdline + cursor,
			len - cursor + 1);
		len--;
		cursor--;
		redraw = 1;
	    }
	    break;

	case KEY_CTRL('D'):
	case KEY_DELETE:
	    if (cursor < len) {
		memmove(cmdline + cursor, cmdline + cursor + 1, len - cursor);
		len--;
		redraw = 1;
	    }
	    break;

	case KEY_CTRL('U'):
	    if (len) {
		len = cursor = 0;
		cmdline[len] = '\0';
		redraw = 1;
	    }
	    break;

	case KEY_CTRL('W'):
	    if (cursor) {
		int prevcursor = cursor;

		while (cursor && my_isspace(cmdline[cursor - 1]))
		    cursor--;

		while (cursor && !my_isspace(cmdline[cursor - 1]))
		    cursor--;

		memmove(cmdline + cursor, cmdline + prevcursor,
			len - prevcursor + 1);
		len -= (prevcursor - cursor);
		redraw = 1;
	    }
	    break;

	case KEY_LEFT:
	case KEY_CTRL('B'):
	    if (cursor) {
		cursor--;
		redraw = 1;
	    }
	    break;

	case KEY_RIGHT:
	case KEY_CTRL('F'):
	    if (cursor < len) {
		putchar(cmdline[cursor++]);
	    }
	    break;

	case KEY_CTRL('K'):
	    if (cursor < len) {
		cmdline[len = cursor] = '\0';
		redraw = 1;
	    }
	    break;

	case KEY_HOME:
	case KEY_CTRL('A'):
	    if (cursor) {
		cursor = 0;
		redraw = 1;
	    }
	    break;

	case KEY_END:
	case KEY_CTRL('E'):
	    if (cursor != len) {
		cursor = len;
		redraw = 1;
	    }
	    break;

	case KEY_F1:
	case KEY_F2:
	case KEY_F3:
	case KEY_F4:
	case KEY_F5:
	case KEY_F6:
	case KEY_F7:
	case KEY_F8:
	case KEY_F9:
	case KEY_F10:
	case KEY_F11:
	case KEY_F12:
	    show_fkey(key);
	    redraw = 1;
	    break;

	default:
	    if (key >= ' ' && key <= 0xFF && len < MAX_CMDLINE_LEN - 1) {
		if (cursor == len) {
		    cmdline[len] = key;
		    cmdline[++len] = '\0';
		    cursor++;
		    putchar(key);
		    prev_len++;
		} else {
		    memmove(cmdline + cursor + 1, cmdline + cursor,
			    len - cursor + 1);
		    cmdline[cursor++] = key;
		    len++;
		    redraw = 1;
		}
	    }
	    break;
	}
    }
}

static void print_timeout_message(int tol, int row, const char *msg)
{
    static int last_msg_len = 0;
    char buf[256];
    int nc = 0, nnc, padc;
    const char *tp = msg;
    char tc;
    char *tq = buf;

    while ((size_t) (tq - buf) < (sizeof buf - 16) && (tc = *tp)) {
	tp++;
	if (tc == '#') {
	    nnc = sprintf(tq, "\2#15%d\2#14", tol);
	    tq += nnc;
	    nc += nnc - 8;	/* 8 formatting characters */
	} else if (tc == '{') {
	    /* Deal with {singular[,dual],plural} constructs */
	    struct {
		const char *s, *e;
	    } tx[3];
	    const char *tpp;
	    int n = 0;

	    memset(tx, 0, sizeof tx);

	    tx[0].s = tp;

	    while (*tp && *tp != '}') {
		if (*tp == ',' && n < 2) {
		    tx[n].e = tp;
		    n++;
		    tx[n].s = tp + 1;
		}
		tp++;
	    }
	    tx[n].e = tp;

	    if (*tp)
		tp++;		/* Skip final bracket */

	    if (!tx[1].s)
		tx[1] = tx[0];
	    if (!tx[2].s)
		tx[2] = tx[1];

	    /* Now [0] is singular, [1] is dual, and [2] is plural,
	       even if the user only specified some of them. */

	    switch (tol) {
	    case 1:
		n = 0;
		break;
	    case 2:
		n = 1;
		break;
	    default:
		n = 2;
		break;
	    }

	    for (tpp = tx[n].s; tpp < tx[n].e; tpp++) {
		if ((size_t) (tq - buf) < (sizeof buf)) {
		    *tq++ = *tpp;
		    nc++;
		}
	    }
	} else {
	    *tq++ = tc;
	    nc++;
	}
    }
    *tq = '\0';

    if (nc >= last_msg_len) {
	padc = 0;
    } else {
	padc = (last_msg_len - nc + 1) >> 1;
    }

    printf("\033[%d;%dH\2#14%*s%s%*s", row,
	   HSHIFT + 1 + ((WIDTH - nc) >> 1) - padc,
	   padc, "", buf, padc, "");

    last_msg_len = nc;
}

/* Set the background screen, etc. */
static void prepare_screen_for_menu(void)
{
    console_color_table = cm->color_table;
    console_color_table_size = menu_color_table_size;
    set_background(cm->menu_background);
}

static const char *do_hidden_menu(void)
{
    int key;
    int timeout_left, this_timeout;

    clear_screen();

    if (!setjmp(timeout_jump)) {
	timeout_left = cm->timeout;

	while (!cm->timeout || timeout_left) {
	    int tol = timeout_left / CLK_TCK;

	    print_timeout_message(tol, HIDDEN_ROW, cm->messages[MSG_AUTOBOOT]);

	    this_timeout = min(timeout_left, CLK_TCK);
	    key = mygetkey(this_timeout);

	    if (key != KEY_NONE) {
		/* Clear the message from the screen */
		print_timeout_message(0, HIDDEN_ROW, "");
		return hide_key[key]; /* NULL if no MENU HIDEKEY in effect */
	    }

	    timeout_left -= this_timeout;
	}
    }

    /* Clear the message from the screen */
    print_timeout_message(0, HIDDEN_ROW, "");

    if (cm->ontimeout)
	return cm->ontimeout;
    else
	return cm->menu_entries[cm->defentry]->cmdline; /* Default entry */
}

static const char *run_menu(void)
{
    int key;
    int done = 0;
    volatile int entry = cm->curentry;
    int prev_entry = -1;
    volatile int top = cm->curtop;
    int prev_top = -1;
    int clear = 1, to_clear;
    const char *cmdline = NULL;
    volatile clock_t key_timeout, timeout_left, this_timeout;
    const struct menu_entry *me;
    bool hotkey = false;

    /* Note: for both key_timeout and timeout == 0 means no limit */
    timeout_left = key_timeout = cm->timeout;

    /* If we're in shiftkey mode, exit immediately unless a shift key
       is pressed */
    if (shiftkey && !shift_is_held()) {
	return cm->menu_entries[cm->defentry]->cmdline;
    } else {
	shiftkey = 0;
    }

    /* Do this before hiddenmenu handling, so we show the background */
    prepare_screen_for_menu();

    /* Handle hiddenmenu */
    if (hiddenmenu) {
	cmdline = do_hidden_menu();
	if (cmdline)
	    return cmdline;

	/* Otherwise display the menu now; the timeout has already been
	   cancelled, since the user pressed a key. */
	hiddenmenu = 0;
	key_timeout = 0;
    }

    /* Handle both local and global timeout */
    if (setjmp(timeout_jump)) {
	entry = cm->defentry;

	if (top < 0 || top < entry - MENU_ROWS + 1)
	    top = max(0, entry - MENU_ROWS + 1);
	else if (top > entry || top > max(0, cm->nentries - MENU_ROWS))
	    top = min(entry, max(0, cm->nentries - MENU_ROWS));

	draw_menu(cm->ontimeout ? -1 : entry, top, 1);
	cmdline =
	    cm->ontimeout ? cm->ontimeout : cm->menu_entries[entry]->cmdline;
	done = 1;
    }

    while (!done) {
	if (entry <= 0) {
	    entry = 0;
	    while (entry < cm->nentries && is_disabled(cm->menu_entries[entry]))
		entry++;
	}
	if (entry >= cm->nentries - 1) {
	    entry = cm->nentries - 1;
	    while (entry > 0 && is_disabled(cm->menu_entries[entry]))
		entry--;
	}

	me = cm->menu_entries[entry];

	if (top < 0 || top < entry - MENU_ROWS + 1)
	    top = max(0, entry - MENU_ROWS + 1);
	else if (top > entry || top > max(0, cm->nentries - MENU_ROWS))
	    top = min(entry, max(0, cm->nentries - MENU_ROWS));

	/* Start with a clear screen */
	if (clear) {
	    /* Clear and redraw whole screen */
	    /* Enable ASCII on G0 and DEC VT on G1; do it in this order
	       to avoid confusing the Linux console */
	    if (clear >= 2)
		prepare_screen_for_menu();
	    clear_screen();
	    clear = 0;
	    prev_entry = prev_top = -1;
	}

	if (top != prev_top) {
	    draw_menu(entry, top, 1);
	    display_help(me->helptext);
	} else if (entry != prev_entry) {
	    draw_row(prev_entry - top + 4 + VSHIFT, entry, top, 0, 0);
	    draw_row(entry - top + 4 + VSHIFT, entry, top, 0, 0);
	    display_help(me->helptext);
	}

	prev_entry = entry;
	prev_top = top;
	cm->curentry = entry;
	cm->curtop = top;

	/* Cursor movement cancels timeout */
	if (entry != cm->defentry)
	    key_timeout = 0;

	if (key_timeout) {
	    int tol = timeout_left / CLK_TCK;
	    print_timeout_message(tol, TIMEOUT_ROW, cm->messages[MSG_AUTOBOOT]);
	    to_clear = 1;
	} else {
	    to_clear = 0;
	}

	if (hotkey && me->immediate) {
	    /* If the hotkey was flagged immediate, simulate pressing ENTER */
	    key = KEY_ENTER;
	} else {
	    this_timeout = min(min(key_timeout, timeout_left),
			       (clock_t) CLK_TCK);
	    key = mygetkey(this_timeout);

	    if (key != KEY_NONE) {
		timeout_left = key_timeout;
		if (to_clear)
		    printf("\033[%d;1H\1#0\033[K", TIMEOUT_ROW);
	    }
	}

	hotkey = false;

	switch (key) {
	case KEY_NONE:		/* Timeout */
	    /* This is somewhat hacky, but this at least lets the user
	       know what's going on, and still deals with "phantom inputs"
	       e.g. on serial ports.

	       Warning: a timeout will boot the default entry without any
	       password! */
	    if (key_timeout) {
		if (timeout_left <= this_timeout)
		    longjmp(timeout_jump, 1);

		timeout_left -= this_timeout;
	    }
	    break;

	case KEY_CTRL('L'):
	    clear = 1;
	    break;

	case KEY_ENTER:
	case KEY_CTRL('J'):
	    key_timeout = 0;	/* Cancels timeout */
	    if (me->passwd) {
		clear = 1;
		done = ask_passwd(me->passwd);
	    } else {
		done = 1;
	    }
	    cmdline = NULL;
	    if (done) {
		switch (me->action) {
		case MA_CMD:
		    cmdline = me->cmdline;
		    break;
		case MA_SUBMENU:
		case MA_GOTO:
		case MA_EXIT:
		    done = 0;
		    clear = 2;
		    cm = me->submenu;
		    entry = cm->curentry;
		    top = cm->curtop;
		    break;
		case MA_QUIT:
		    /* Quit menu system */
		    done = 1;
		    clear = 1;
		    draw_row(entry - top + 4 + VSHIFT, -1, top, 0, 0);
		    break;
		case MA_HELP:
		    key = show_message_file(me->cmdline, me->background);
		    /* If the exit was an F-key, display that help screen */
		    show_fkey(key);
		    done = 0;
		    clear = 1;
		    break;
		default:
		    done = 0;
		    break;
		}
	    }
	    if (done && !me->passwd) {
		/* Only save a new default if we don't have a password... */
		if (me->save && me->label) {
		    syslinux_setadv(ADV_MENUSAVE, strlen(me->label), me->label);
		    syslinux_adv_write();
		}
	    }
	    break;

	case KEY_UP:
	case KEY_CTRL('P'):
	    while (entry > 0) {
		entry--;
		if (entry < top)
		    top -= MENU_ROWS;
		if (!is_disabled(cm->menu_entries[entry]))
		    break;
	    }
	    break;

	case KEY_DOWN:
	case KEY_CTRL('N'):
	    while (entry < cm->nentries - 1) {
		entry++;
		if (entry >= top + MENU_ROWS)
		    top += MENU_ROWS;
		if (!is_disabled(cm->menu_entries[entry]))
		    break;
	    }
	    break;

	case KEY_PGUP:
	case KEY_LEFT:
	case KEY_CTRL('B'):
	case '<':
	    entry -= MENU_ROWS;
	    top -= MENU_ROWS;
	    while (entry > 0 && is_disabled(cm->menu_entries[entry])) {
		entry--;
		if (entry < top)
		    top -= MENU_ROWS;
	    }
	    break;

	case KEY_PGDN:
	case KEY_RIGHT:
	case KEY_CTRL('F'):
	case '>':
	case ' ':
	    entry += MENU_ROWS;
	    top += MENU_ROWS;
	    while (entry < cm->nentries - 1
		   && is_disabled(cm->menu_entries[entry])) {
		entry++;
		if (entry >= top + MENU_ROWS)
		    top += MENU_ROWS;
	    }
	    break;

	case '-':
	    while (entry > 0) {
		entry--;
		top--;
		if (!is_disabled(cm->menu_entries[entry]))
		    break;
	    }
	    break;

	case '+':
	    while (entry < cm->nentries - 1) {
		entry++;
		top++;
		if (!is_disabled(cm->menu_entries[entry]))
		    break;
	    }
	    break;

	case KEY_CTRL('A'):
	case KEY_HOME:
	    top = entry = 0;
	    break;

	case KEY_CTRL('E'):
	case KEY_END:
	    entry = cm->nentries - 1;
	    top = max(0, cm->nentries - MENU_ROWS);
	    break;

	case KEY_F1:
	case KEY_F2:
	case KEY_F3:
	case KEY_F4:
	case KEY_F5:
	case KEY_F6:
	case KEY_F7:
	case KEY_F8:
	case KEY_F9:
	case KEY_F10:
	case KEY_F11:
	case KEY_F12:
	    show_fkey(key);
	    clear = 1;
	    break;

	case KEY_TAB:
	    if (cm->allowedit && me->action == MA_CMD) {
		int ok = 1;

		key_timeout = 0;	/* Cancels timeout */
		draw_row(entry - top + 4 + VSHIFT, -1, top, 0, 0);

		if (cm->menu_master_passwd) {
		    ok = ask_passwd(NULL);
		    clear_screen();
		    draw_menu(-1, top, 0);
		} else {
		    /* Erase [Tab] message and help text */
		    printf("\033[%d;1H\1#0\033[K", TABMSG_ROW);
		    display_help(NULL);
		}

		if (ok) {
		    cmdline = edit_cmdline(me->cmdline, top);
		    done = !!cmdline;
		    clear = 1;	/* In case we hit [Esc] and done is null */
		} else {
		    draw_row(entry - top + 4 + VSHIFT, entry, top, 0, 0);
		}
	    }
	    break;
	case KEY_CTRL('C'):	/* Ctrl-C */
	case KEY_ESC:		/* Esc */
	    if (cm->parent) {
		cm = cm->parent;
		clear = 2;
		entry = cm->curentry;
		top = cm->curtop;
	    } else if (cm->allowedit) {
		done = 1;
		clear = 1;
		key_timeout = 0;

		draw_row(entry - top + 4 + VSHIFT, -1, top, 0, 0);

		if (cm->menu_master_passwd)
		    done = ask_passwd(NULL);
	    }
	    break;
	default:
	    if (key > 0 && key < 0xFF) {
		key &= ~0x20;	/* Upper case */
		if (cm->menu_hotkeys[key]) {
		    key_timeout = 0;
		    entry = cm->menu_hotkeys[key]->entry;
		    /* Should we commit at this point? */
		    hotkey = true;
		}
	    }
	    break;
	}
    }

    printf("\033[?25h");	/* Show cursor */

    /* Return the label name so localboot and ipappend work */
    return cmdline;
}

int main(int argc, char *argv[])
{
    const char *cmdline;
    struct menu *m;
    int rows, cols;
    int i;

    (void)argc;

    parse_configs(argv + 1);

    /*
     * We don't start the console until we have parsed the configuration
     * file, since the configuration file might impact the console
     * configuration, e.g. MENU RESOLUTION.
     */
    start_console();
    if (getscreensize(1, &rows, &cols)) {
	/* Unknown screen size? */
	rows = 24;
	cols = 80;
    }

    /* Some postprocessing for all menus */
    for (m = menu_list; m; m = m->next) {
	if (!m->mparm[P_WIDTH])
	    m->mparm[P_WIDTH] = cols;

	/* If anyone has specified negative parameters, consider them
	   relative to the bottom row of the screen. */
	for (i = 0; i < NPARAMS; i++)
	    if (m->mparm[i] < 0)
		m->mparm[i] = max(m->mparm[i] + rows, 0);
    }

    cm = start_menu;

    if (!cm->nentries) {
	fputs("Initial menu has no LABEL entries!\n", stdout);
	return 1;		/* Error! */
    }

    for (;;) {
	local_cursor_enable(true);
	cmdline = run_menu();

	if (clearmenu)
	    clear_screen();

	local_cursor_enable(false);
	printf("\033[?25h\033[%d;1H\033[0m", END_ROW);

	if (cmdline) {
	    uint32_t type = parse_image_type(cmdline);

	    execute(cmdline, type, false);
	    if (cm->onerror) {
		type = parse_image_type(cm->onerror);
		execute(cm->onerror, type, true);
	    }
	} else {
	    return 0;		/* Exit */
	}
    }
}
