/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
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
 * initramfs_file.c
 *
 * Utility functions to add arbitrary files including cpio header
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <syslinux/linux.h>

#define CPIO_MAGIC "070701"
struct cpio_header {
    char c_magic[6];		/* 070701 */
    char c_ino[8];		/* Inode number */
    char c_mode[8];		/* File mode and permissions */
    char c_uid[8];		/* uid */
    char c_gid[8];		/* gid */
    char c_nlink[8];		/* Number of links */
    char c_mtime[8];		/* Modification time */
    char c_filesize[8];		/* Size of data field */
    char c_maj[8];		/* File device major number */
    char c_min[8];		/* File device minor number */
    char c_rmaj[8];		/* Device node reference major number */
    char c_rmin[8];		/* Device node reference minor number */
    char c_namesize[8];		/* Length of filename including final \0 */
    char c_chksum[8];		/* Checksum if c_magic ends in 2 */
};

static uint32_t next_ino = 1;

/* Create cpio headers for the directory entries leading up to a file.
   Returns the number of bytes; doesn't touch the buffer if too small. */
static size_t initramfs_mkdirs(const char *filename, void *buffer,
			       size_t buflen)
{
    const char *p = filename;
    char *bp = buffer;
    int len;
    size_t bytes = 0, hdr_sz;
    int pad;

    while ((p = strchr(p, '/'))) {
	if (p != filename && p[-1] != '/') {
	    len = p - filename;
	    bytes += ((sizeof(struct cpio_header) + len + 1) + 3) & ~3;
	}
	p++;
    }

    if (buflen >= bytes) {
	p = filename;
	while ((p = strchr(p, '/'))) {
	    if (p != filename && p[-1] != '/') {
		len = p - filename;
		hdr_sz = ((sizeof(struct cpio_header) + len + 1) + 3) & ~3;
		bp += sprintf(bp, "070701%08x%08x%08x%08x%08x%08x%08x%08x%08x"
			      "%08x%08x%08x%08x", next_ino++, S_IFDIR | 0755,
			      0, 0, 1, 0, 0, 0, 1, 0, 1, len + 1, 0);
		memcpy(bp, filename, len);
		bp += len;
		pad = hdr_sz - (sizeof(struct cpio_header) + len);
		memset(bp, 0, pad);
		bp += pad;
	    }
	    p++;
	}
    }

    return bytes;
}

/*
 * Create a file header (with optional parent directory entries)
 * and add it to an initramfs chain
 */
int initramfs_mknod(struct initramfs *ihead, const char *filename,
		    int do_mkdir,
		    uint16_t mode, size_t len, uint32_t major, uint32_t minor)
{
    size_t bytes, hdr_sz;
    int namelen = strlen(filename);
    int pad;
    char *buffer, *bp;

    if (do_mkdir)
	bytes = initramfs_mkdirs(filename, NULL, 0);
    else
	bytes = 0;

    hdr_sz = ((sizeof(struct cpio_header) + namelen + 1) + 3) & ~3;
    bytes += hdr_sz;

    bp = buffer = malloc(bytes);
    if (!buffer)
	return -1;

    if (do_mkdir)
	bp += initramfs_mkdirs(filename, bp, bytes);

    bp += sprintf(bp, "070701%08x%08x%08x%08x%08x%08x%08x%08x%08x"
		  "%08x%08x%08x%08x", next_ino++, mode,
		  0, 0, 1, 0, len, 0, 1, major, minor, namelen + 1, 0);
    memcpy(bp, filename, namelen);
    bp += namelen;
    pad = hdr_sz - (sizeof(struct cpio_header) + namelen);
    memset(bp, 0, pad);

    if (initramfs_add_data(ihead, buffer, bytes, bytes, 4)) {
	free(buffer);
	return -1;
    }

    return 0;
}

/*
 * Add a file given data in memory to an initramfs chain.  This
 * can be used to create nonfiles like symlinks by specifying an
 * appropriate mode.
 */
int initramfs_add_file(struct initramfs *ihead, const void *data,
		       size_t data_len, size_t len,
		       const char *filename, int do_mkdir, uint32_t mode)
{
    if (initramfs_mknod(ihead, filename, do_mkdir,
			(mode & S_IFMT) ? mode : mode | S_IFREG, len, 0, 1))
	return -1;

    return initramfs_add_data(ihead, data, data_len, len, 4);
}

int initramfs_add_trailer(struct initramfs *ihead)
{
    return initramfs_mknod(ihead, "TRAILER!!!", 0, 0, 0, 0, 0);
}
