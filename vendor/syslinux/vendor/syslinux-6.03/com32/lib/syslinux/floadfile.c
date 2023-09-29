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
 * floadfile.c
 *
 * Read the contents of a data file into a malloc'd buffer
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>

#include <syslinux/loadfile.h>

#define INCREMENTAL_CHUNK 1024*1024

int floadfile(FILE * f, void **ptr, size_t * len, const void *prefix,
	      size_t prefix_len)
{
    struct stat st;
    void *data, *dp;
    size_t alen, clen, rlen, xlen;

    clen = alen = 0;
    data = NULL;

    if (fstat(fileno(f), &st))
	goto err;

    if (!S_ISREG(st.st_mode)) {
	/* Not a regular file, we can't assume we know the file size */
	if (prefix_len) {
	    clen = alen = prefix_len;
	    data = malloc(prefix_len);
	    if (!data)
		goto err;

	    memcpy(data, prefix, prefix_len);
	}

	do {
	    alen += INCREMENTAL_CHUNK;
	    dp = realloc(data, alen);
	    if (!dp)
		goto err;
	    data = dp;

	    rlen = fread((char *)data + clen, 1, alen - clen, f);
	    clen += rlen;
	} while (clen == alen);

	*len = clen;
	xlen = (clen + LOADFILE_ZERO_PAD - 1) & ~(LOADFILE_ZERO_PAD - 1);
	dp = realloc(data, xlen);
	if (dp)
	    data = dp;
	*ptr = data;
    } else {
	*len = clen = st.st_size + prefix_len - ftell(f);
	xlen = (clen + LOADFILE_ZERO_PAD - 1) & ~(LOADFILE_ZERO_PAD - 1);

	*ptr = data = malloc(xlen);
	if (!data)
	    return -1;

	memcpy(data, prefix, prefix_len);

	if ((off_t) fread((char *)data + prefix_len, 1, clen - prefix_len, f)
	    != clen - prefix_len)
	    goto err;
    }

    memset((char *)data + clen, 0, xlen - clen);
    return 0;

err:
    if (data)
	free(data);
    return -1;
}
