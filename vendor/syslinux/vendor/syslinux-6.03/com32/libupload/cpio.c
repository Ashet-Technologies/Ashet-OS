/*
 * cpio.c
 *
 * Write a compressed CPIO file
 */

#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <stdbool.h>
#include <zlib.h>
#include "upload_backend.h"
#include "ctime.h"

int cpio_pad(struct upload_backend *be)
{
    static char pad[4];		/* Up to 4 zero bytes */
    if (be->dbytes & 3)
	return write_data(be, pad, -be->dbytes & 3);
    else
	return 0;
}

int cpio_hdr(struct upload_backend *be, uint32_t mode, size_t datalen,
	     const char *filename)
{
    static uint32_t inode = 2;
    char hdr[6+13*8+1];
    int nlen = strlen(filename)+1;
    int rv = 0;

    cpio_pad(be);

    sprintf(hdr, "%06o%08x%08x%08x%08x%08x%08x%08zx%08x%08x%08x%08x%08x%08x",
	    070701,		/* c_magic */
	    inode++,		/* c_ino */
	    mode,		/* c_mode */
	    0,			/* c_uid */
	    0,			/* c_gid */
	    1,			/* c_nlink */
	    be->now,		/* c_mtime */
	    datalen,		/* c_filesize */
	    0,			/* c_maj */
	    0,			/* c_min */
	    0,			/* c_rmaj */
	    0,			/* c_rmin */
	    nlen,		/* c_namesize */
	    0);			/* c_chksum */
    rv |= write_data(be, hdr, 6+13*8);
    rv |= write_data(be, filename, nlen);
    rv |= cpio_pad(be);
    return rv;
}

int cpio_mkdir(struct upload_backend *be, const char *filename)
{
    return cpio_hdr(be, MODE_DIR, 0, filename);
}

int cpio_writefile(struct upload_backend *be, const char *filename,
		   const void *data, size_t len)
{
    int rv;

    rv = cpio_hdr(be, MODE_FILE, len, filename);
    rv |= write_data(be, data, len);
    rv |= cpio_pad(be);

    return rv;
}

int cpio_close(struct upload_backend *be)
{
    return cpio_hdr(be, 0, 0, "TRAILER!!!");
}
