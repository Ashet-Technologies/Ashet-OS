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
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <syslinux/zio.h>

#include "file.h"
#include "zlib.h"

/*
 * zopen.c
 *
 * Open an ordinary file, possibly compressed; if so, insert
 * an appropriate decompressor.
 */

int __file_get_block(struct file_info *fp);
int __file_close(struct file_info *fp);

static ssize_t gzip_file_read(struct file_info *, void *, size_t);
static int gzip_file_close(struct file_info *);

static const struct input_dev gzip_file_dev = {
    .dev_magic = __DEV_MAGIC,
    .flags = __DEV_FILE | __DEV_INPUT,
    .fileflags = O_RDONLY,
    .read = gzip_file_read,
    .close = gzip_file_close,
    .open = NULL,
};

static int gzip_file_init(struct file_info *fp)
{
    z_streamp zs = calloc(1, sizeof(z_stream));

    if (!zs)
	return -1;

    fp->i.pvt = zs;

    zs->next_in = (void *)fp->i.datap;
    zs->avail_in = fp->i.nbytes;

    if (inflateInit2(zs, 15 + 32) != Z_OK) {
	errno = EIO;
	return -1;
    }

    fp->iop = &gzip_file_dev;
    fp->i.fd.size = -1;		/* Unknown */

    return 0;
}

static ssize_t gzip_file_read(struct file_info *fp, void *ptr, size_t n)
{
    z_streamp zs = fp->i.pvt;
    int rv;
    ssize_t bytes;
    ssize_t nout = 0;
    unsigned char *p = ptr;

    while (n) {
	zs->next_out = p;
	zs->avail_out = n;

	if (!zs->avail_in && fp->i.fd.handle) {
	    if (__file_get_block(fp))
		return nout ? nout : -1;

	    zs->next_in = (void *)fp->i.datap;
	    zs->avail_in = fp->i.nbytes;
	}

	rv = inflate(zs, Z_SYNC_FLUSH);

	bytes = n - zs->avail_out;
	nout += bytes;
	p += bytes;
	n -= bytes;

	switch (rv) {
	case Z_DATA_ERROR:
	case Z_NEED_DICT:
	case Z_BUF_ERROR:
	case Z_STREAM_ERROR:
	default:
	    errno = EIO;
	    return nout ? nout : -1;
	case Z_MEM_ERROR:
	    errno = ENOMEM;
	    return nout ? nout : -1;
	case Z_STREAM_END:
	    return nout;
	case Z_OK:
	    break;
	}
    }

    return nout;
}

static int gzip_file_close(struct file_info *fp)
{
    z_streamp zs = fp->i.pvt;

    inflateEnd(zs);
    free(zs);
    return __file_close(fp);
}

int zopen(const char *pathname, int flags, ...)
{
    int fd, rv;
    struct file_info *fp;

    /* We don't actually give a hoot about the creation bits... */
    fd = open(pathname, flags, 0);

    if (fd < 0)
	return -1;

    fp = &__file_info[fd];

    /* Need to get the first block into the buffer, but not consumed */
    if (__file_get_block(fp))
	goto err;

    if (fp->i.nbytes >= 14 &&
	(uint8_t) fp->i.buf[0] == 037 &&
	(uint8_t) fp->i.buf[1] == 0213 &&	/* gzip */
	fp->i.buf[2] == 8)	/* deflate */
	rv = gzip_file_init(fp);
    else
	rv = 0;			/* Plain file */

    if (!rv)
	return fd;

err:
    close(fd);
    return -1;
}
