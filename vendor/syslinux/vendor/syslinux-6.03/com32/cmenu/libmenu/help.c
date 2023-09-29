/* -*- c -*- ------------------------------------------------------------- *
 *
 *   Copyright 2004-2005 Murali Krishnan Ganapathy - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include "help.h"
#include <stdio.h>
#include "string.h"
#include "com32io.h"
#include <syslinux/loadfile.h>	// to read entire file into memory

int nc, nr; // Number of columns/rows of the screen
char helpbasedir[HELPDIRLEN];	// name of help directory limited to HELPDIRLEN

// Find the occurence of the count'th \n in buffer (or NULL) if not found
static char *findline(char *buffer, int count)
{
    int ctr;
    char *p = buffer - 1;

    if (count < 1)
	return buffer;
    for (ctr = 0; ctr < count; ctr++) {
	p = strchr(p + 1, '\n');
	if (p == NULL)
	    return NULL;
    }
    return p;
}

// return the number of lines in buffer
static int countlines(char *buffer)
{
    int ans;
    const char *p;

    p = buffer - 1;
    ans = 1;
    while (p) {
	p = strchr(p + 1, '\n');
	ans++;
    }
    return ans;
}

// Print numlines of text starting from buf
static void printtext(char *buf, int from)
{
    char *f, *t;
    int nlines, i;

    // clear window to print
    nlines = nr - HELP_BODY_ROW - HELP_BOTTOM_MARGIN - 1;

    f = findline(buf, from);
    if (!f)
	return;			// nothing to print
    if (*f == '\n')
	f++;			// start of from+1st line
    t = f;

    for (i = 0; i < nlines; i++) {
        gotoxy(HELP_BODY_ROW + i, HELP_LEFT_MARGIN);
        clear_end_of_line();
        putchar(SO);
        gotoxy(HELP_BODY_ROW + i, nc - 1);
        putch(LEFT_BORDER, 0x07);
        putchar(SI);

        gotoxy(HELP_BODY_ROW + i, HELP_LEFT_MARGIN);
        while (*t != '\n') {
            if (*t == '\0')
                return;
            putchar(*t);
            t++;
        }
        putchar('\n');
        t++;
    }
}

void showhelp(const char *filename)
{
    char ph;
    char *title, *text;
    union {
	char *buffer;
	void *vbuf;
    } buf;			// This is to avoild type-punning issues

    char line[512];
    size_t size;
    int scan;
    int rv, numlines, curr_line;

    if (getscreensize(1, &nr, &nc)) {
        /* Unknown screen size? */
        nc = 80;
        nr = 24;
    }
    ph = nr - HELP_BODY_ROW;
    cls();

    /* Turn autowrap off, to avoid scrolling the menu */
    printf(CSI "?7l");

    if (filename == NULL) {	// print file contents
        strcpy(line, "Filename not given");
        goto puke;
    }

    rv = loadfile(filename, (void **)&buf.vbuf, &size);	// load entire file into memory
    if (rv < 0) {		// Error reading file or no such file
        sprintf(line, "Error reading file or file not found\n file=%s", filename);
        goto puke;
    }

    title = buf.buffer;
    text = findline(title, 1);	// end of first line
    *text++ = '\0';		// end the title string and increment text

    // Now we have a file just print it.
    numlines = countlines(text);
    curr_line = 0;
    scan = KEY_ESC + 1;		// anything except ESCAPE

    /* top, left, bottom, right, attr */
    drawbox(0, 0, nr - 1, nc - 1, 0x07);
    while (scan != KEY_ESC) {
    /* Title */
    gotoxy(1, (nc - strlen(title)) / 2);
    fputs(title, stdout);
    drawhorizline(2, HELP_LEFT_MARGIN - 1, nc - HELP_RIGHT_MARGIN, 0x07, 0);	// dumb==0
    /* Text */
	printtext(text, curr_line);
    gotoxy(HELP_BODY_ROW - 1, nc - HELP_RIGHT_MARGIN);
	if (curr_line > 0)
	    putchar(HELP_MORE_ABOVE);
	else
	    putchar(' ');
	gotoxy(nr - HELP_BOTTOM_MARGIN - 1, nc - HELP_RIGHT_MARGIN);
	if (curr_line < numlines - ph)
	    putchar(HELP_MORE_BELOW);
	else
	    putchar(' ');

    scan = get_key(stdout, 0); // wait for user keypress

	switch (scan) {
	case KEY_HOME:
	    curr_line = 0;
	    break;
	case KEY_END:
	    curr_line = numlines;
	    break;
	case KEY_UP:
	    curr_line--;
	    break;
	case KEY_DOWN:
	    curr_line++;
	    break;
	case KEY_PGUP:
	    curr_line -= ph;
	    break;
	case KEY_PGDN:
	    curr_line += ph;
	    break;
	default:
	    break;
	}
	if (curr_line > numlines - ph)
	    curr_line = numlines - ph;
	if (curr_line < 0)
	    curr_line = 0;
    }
out:
    cls();
    return;

puke:
    gotoxy(HELP_BODY_ROW, HELP_LEFT_MARGIN);
    fputs(line, stdout);
    while (1) {
        scan = get_key(stdin, 0);
        if (scan == KEY_ESC)
            break;
    }
    goto out;
}

void runhelp(const char *filename)
{
    char fullname[HELPDIRLEN + 16];

	cls();
    cursoroff();
    if (helpbasedir[0] != 0) {
	strcpy(fullname, helpbasedir);
	strcat(fullname, "/");
	strcat(fullname, filename);
	showhelp(fullname);
    } else
	showhelp(filename);	// Assume filename is absolute
}

void runhelpsystem(unsigned int helpid)
{
    char filename[15];

    sprintf(filename, "hlp%05d.txt", helpid);
    runhelp(filename);
}

void init_help(const char *helpdir)
{
    if (helpdir != NULL)
	strcpy(helpbasedir, helpdir);
    else
	helpbasedir[0] = 0;
}

void close_help(void)
{
}
