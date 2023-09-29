/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2003-2008 H. Peter Anvin - All Rights Reserved
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

#include <errno.h>
#include <com32.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <fs.h>
#include "file.h"

/*
 * open.c
 *
 * Open an ordinary file
 */

extern ssize_t __file_read(struct file_info *, void *, size_t);
extern int __file_close(struct file_info *);

const struct input_dev __file_dev = {
    .dev_magic = __DEV_MAGIC,
    .flags = __DEV_FILE | __DEV_INPUT,
    .fileflags = O_RDONLY,
    .read = __file_read,
    .close = __file_close,
    .open = NULL,
};

int open(const char *pathname, int flags, ...)
{
    int fd, handle;
    struct file_info *fp;

    fd = opendev(&__file_dev, NULL, flags);

    //printf("enter, file = %s, fd = %d\n", pathname, fd);

    if (fd < 0)
	return -1;

    fp = &__file_info[fd];

    handle = open_file(pathname, flags, &fp->i.fd);
    if (handle < 0) {
	close(fd);
	errno = ENOENT;
	return -1;
    }

    fp->i.offset = 0;
    fp->i.nbytes = 0;

    return fd;
}
