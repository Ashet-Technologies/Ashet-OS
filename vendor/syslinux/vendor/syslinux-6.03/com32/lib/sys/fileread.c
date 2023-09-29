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
 * read.c
 *
 * Reading from a file
 */

#include <errno.h>
#include <string.h>
#include <com32.h>
#include <pmapi.h>
#include <syslinux/pmapi.h>
#include <minmax.h>
#include "file.h"

int __file_get_block(struct file_info *fp)
{
    ssize_t bytes_read;

    bytes_read = pmapi_read_file(&fp->i.fd.handle, fp->i.buf,
					  MAXBLOCK >> fp->i.fd.blocklg2);
    if (!bytes_read) {
	errno = EIO;
	return -1;
    }
    
    fp->i.nbytes = bytes_read;
    fp->i.datap  = fp->i.buf;
    return 0;
}

ssize_t __file_read(struct file_info * fp, void *buf, size_t count)
{
    char *bufp = buf;
    ssize_t n = 0;
    size_t ncopy;

    while (count) {
	if (fp->i.nbytes == 0) {
	    if (fp->i.offset >= fp->i.fd.size || !fp->i.fd.handle)
		return n;	/* As good as it gets... */

	    if (count > MAXBLOCK) {
		/* Large transfer: copy directly, without buffering */
		ncopy = pmapi_read_file(&fp->i.fd.handle, bufp,
						 count >> fp->i.fd.blocklg2);
		if (!ncopy) {
		    errno = EIO;
		    return n ? n : -1;
		}

		goto got_data;
	    } else {
		if (__file_get_block(fp))
		    return n ? n : -1;
	    }
	}

	ncopy = min(count, fp->i.nbytes);
	memcpy(bufp, fp->i.datap, ncopy);

	fp->i.datap += ncopy;
	fp->i.offset += ncopy;
	fp->i.nbytes -= ncopy;

    got_data:
	n += ncopy;
	bufp += ncopy;
	count -= ncopy;
    }

    return n;
}
