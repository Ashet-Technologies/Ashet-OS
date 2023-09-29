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
 * xserial_write.c
 *
 * Raw writing to the serial port; \n -> \r\n translation, and
 * convert \1# sequences.
 */

#include <errno.h>
#include <string.h>
#include <com32.h>
#include <core.h>
#include <minmax.h>
#include <colortbl.h>
#include <syslinux/config.h>
#include "file.h"

static void emit(char ch)
{
    write_serial(ch);
}

ssize_t __xserial_write(struct file_info *fp, const void *buf, size_t count)
{
    const char *bufp = buf;
    size_t n = 0;
    static enum { st_init, st_tbl, st_tblc } state = st_init;
    static int ndigits;
    static int ncolor = 0;
    int num;
    const char *p;

    (void)fp;

    if (!syslinux_serial_console_info()->iobase)
	return count;		/* Nothing to do */

    while (count--) {
	unsigned char ch = *bufp++;

	switch (state) {
	case st_init:
	    if (ch >= 1 && ch <= 5) {
		state = st_tbl;
		ndigits = ch;
	    } else if (ch == '\n') {
		emit('\r');
		emit('\n');
	    } else {
		emit(ch);
	    }
	    break;

	case st_tbl:
	    if (ch == '#') {
		state = st_tblc;
		ncolor = 0;
	    } else {
		state = st_init;
	    }
	    break;

	case st_tblc:
	    num = ch - '0';
	    if (num < 10) {
		ncolor = (ncolor * 10) + num;
		if (--ndigits == 0) {
		    if (ncolor < console_color_table_size) {
			emit('\033');
			emit('[');
			emit('0');
			emit(';');
			for (p = console_color_table[ncolor].ansi; *p; p++)
			    emit(*p);
			emit('m');
		    }
		    state = st_init;
		}
	    } else {
		state = st_init;
	    }
	    break;
	}
	n++;
    }

    return n;
}
