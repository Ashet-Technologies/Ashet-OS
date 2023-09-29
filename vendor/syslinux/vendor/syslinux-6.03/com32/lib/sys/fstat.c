/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2005-2008 H. Peter Anvin - All Rights Reserved
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
 * fstat.c
 *
 * Very trivial fstat emulation
 */

#include <sys/stat.h>
#include <errno.h>
#include "file.h"

int fstat(int fd, struct stat *buf)
{
    struct file_info *fp = &__file_info[fd];

    if (fd >= NFILES || !fp->iop) {
	errno = EBADF;
	return -1;
    }

    if (fp->iop->flags & __DEV_FILE) {
	if (fp->i.fd.size == (uint32_t) - 1) {
	    /* File of unknown length, report it as a socket
	       (it probably really is, anyway!) */
	    buf->st_mode = S_IFSOCK | 0444;
	    buf->st_size = 0;
	} else {
	    buf->st_mode = S_IFREG | 0444;
	    buf->st_size = fp->i.fd.size;
	}
    } else {
	buf->st_mode = S_IFCHR | 0666;
	buf->st_size = 0;
    }

    return 0;
}
