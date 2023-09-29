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

/*
 * file.h
 *
 * Internal implementation of file I/O for COM32
 */

#ifndef _COM32_SYS_FILE_H
#define _COM32_SYS_FILE_H

#include <inttypes.h>
#include <stdlib.h>
#include <sys/types.h>
#include <dev.h>
#include <fcntl.h>
#include <syslinux/pmapi.h>

/* Device structure; contains the relevant operations */

struct file_info;

#define __DEV_MAGIC	0xf4e7
#define __DEV_TTY	0x0001	/* TTY - must be bit 0 */
#define __DEV_FILE	0x0002	/* Ordinary file */
#define __DEV_OUTPUT	0x0004	/* This is an output device */
#define __DEV_INPUT	0	/* Dummy */
#define __DEV_ERROR	0x0008	/* This is the error device */
#define __DEV_NULL	0x0010	/* This is the null device */

struct input_dev {
    uint16_t dev_magic;		/* Magic number */
    uint16_t flags;		/* Flags */
    int fileflags;		/* Permitted file flags */
    ssize_t (*read)(struct file_info *, void *, size_t);
    int (*close)(struct file_info *);
    int (*open)(struct file_info *);
};

struct output_dev {
    uint16_t dev_magic;		/* Magic number */
    uint16_t flags;		/* Flags */
    int fileflags;
    ssize_t (*write)(struct file_info *, const void *, size_t);
    int (*close)(struct file_info *);
    int (*open)(struct file_info *);
    const struct output_dev *fallback;	/* Fallback option for certain consoles */
};

/* File structure */

#define NFILES 128		/* Number of files to support */
#define MAXBLOCK 16384		/* Defined by ABI */

struct file_info {
    const struct input_dev *iop;	/* Input operations */
    const struct output_dev *oop;	/* Output operations */

    /* Output file data */
    struct {
	int rows, cols;		/* Rows and columns */
    } o;

    /* Structure used for input blocking */
    struct {
	struct com32_filedata fd;
	size_t offset;		/* Current file offset */
	size_t nbytes;		/* Number of bytes available in buffer */
	char *datap;		/* Current data pointer */
	void *pvt;		/* Private pointer for driver */
	char buf[MAXBLOCK];
    } i;
};

extern struct file_info __file_info[NFILES];
extern const struct input_dev __file_dev;

/* Line input discipline */
ssize_t __line_input(struct file_info *fp, char *buf, size_t bufsize,
		     ssize_t(*get_char) (struct file_info *, void *, size_t));

#endif /* _COM32_SYS_FILE_H */
