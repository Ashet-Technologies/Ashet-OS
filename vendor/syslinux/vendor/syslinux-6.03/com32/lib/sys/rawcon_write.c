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
 * rawcon_write.c
 *
 * Raw writing to the console; no \n -> \r\n translation
 */

#include <errno.h>
#include <string.h>
#include <com32.h>
#include <core.h>
#include <minmax.h>
#include "file.h"

static ssize_t __rawcon_write(struct file_info *fp, const void *buf,
			      size_t count)
{
    const char *bufp = buf;
    size_t n = 0;

    (void)fp;

    while (count--) {
	writechr(*bufp++);
	n++;
    }

    return n;
}

const struct output_dev dev_rawcon_w = {
    .dev_magic = __DEV_MAGIC,
    .flags = __DEV_TTY | __DEV_OUTPUT,
    .fileflags = O_WRONLY | O_CREAT | O_TRUNC | O_APPEND,
    .write = __rawcon_write,
    .close = NULL,
};
