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
 * stdcon_write.c
 *
 * Writing to the console; \n -> \r\n conversion.
 */

#include <errno.h>
#include <string.h>
#include <com32.h>
#include <core.h>
#include <minmax.h>
#include "file.h"

#define BIOS_ROWS (*(uint8_t *)0x484)	/* Minus one; if zero use 24 (= 25 lines) */
#define BIOS_COLS (*(uint16_t *)0x44A)

static int __stdcon_open(struct file_info *fp)
{
    fp->o.rows = BIOS_ROWS + 1;
    fp->o.cols = BIOS_COLS;

    /* Sanity check */
    if (fp->o.rows < 12)
	fp->o.rows = 24;
    if (fp->o.cols < 40)
	fp->o.cols = 80;

    return 0;
}

static ssize_t __stdcon_write(struct file_info *fp, const void *buf,
			      size_t count)
{
    const char *bufp = buf;
    size_t n = 0;

    (void)fp;

    while (count--) {
	if (*bufp == '\n')
	    writechr('\r');

	writechr(*bufp++);
	n++;
    }

    return n;
}

const struct output_dev dev_stdcon_w = {
    .dev_magic = __DEV_MAGIC,
    .flags = __DEV_TTY | __DEV_OUTPUT,
    .fileflags = O_WRONLY | O_CREAT | O_TRUNC | O_APPEND,
    .write = __stdcon_write,
    .close = NULL,
    .open  = __stdcon_open,
};
