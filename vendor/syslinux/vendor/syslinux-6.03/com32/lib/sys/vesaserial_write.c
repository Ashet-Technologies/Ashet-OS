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
 * vesaserial_write.c
 *
 * Write to both to the VESA console and the serial port
 */

#include <errno.h>
#include <string.h>
#include <com32.h>
#include <minmax.h>
#include <console.h>
#include "file.h"

extern int __vesacon_open(struct file_info *);
extern int __vesacon_close(struct file_info *);
extern ssize_t __vesacon_write(struct file_info *, const void *, size_t);
extern ssize_t __xserial_write(struct file_info *, const void *, size_t);

static ssize_t __vesaserial_write(struct file_info *fp, const void *buf,
				  size_t count)
{
    __vesacon_write(fp, buf, count);
    return __xserial_write(fp, buf, count);
}

const struct output_dev dev_vesaserial_w = {
    .dev_magic = __DEV_MAGIC,
    .flags = __DEV_TTY | __DEV_OUTPUT,
    .fileflags = O_WRONLY | O_CREAT | O_TRUNC | O_APPEND,
    .write = __vesaserial_write,
    .close = __vesacon_close,
    .open = __vesacon_open,
    .fallback = &dev_ansiserial_w,
};
