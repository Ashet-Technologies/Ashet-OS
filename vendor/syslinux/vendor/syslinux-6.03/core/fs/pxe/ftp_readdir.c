/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * ftp_readdir.c
 */
#include <inttypes.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <dprintf.h>
#include "pxe.h"

static int dirtype(char type)
{
    switch (type) {
    case 'f':
	return DT_FIFO;
    case 'c':
	return DT_CHR;
    case 'd':
	return DT_DIR;
    case 'b':
	return DT_BLK;
    case '-':
    case '0' ... '9':		/* Some DOS FTP stacks */
	return DT_REG;
    case 'l':
	return DT_LNK;
    case 's':
	return DT_SOCK;
    default:
	return DT_UNKNOWN;
    }
}

int ftp_readdir(struct inode *inode, struct dirent *dirent)
{
    char bufs[2][FILENAME_MAX + 1];
    int nbuf = 0;
    char *buf = bufs[nbuf];
    char *p = buf;
    char *name = NULL;
    char type;
    int c;
    int dt;
    bool was_cr = false;
    bool first = true;

    for (;;) {
	type = 0;

	for (;;) {
	    c = pxe_getc(inode);
	    if (c == -1)
		return -1;	/* Nothing else there */

	    if (c == '\r') {
		was_cr = true;
		continue;
	    }
	    if (was_cr) {
		if (c == '\n') {
		    if (!name) {
			*p = '\0';
			name = buf;
		    }
		    break;	/* End of line */
		}
		else if (c == '\0')
		    c = '\r';
	    }
	    was_cr = false;

	    if (c == ' ' || c == '\t') {
		if (!name) {
		    *p = '\0';
		    if (first) {
			if (p == buf) {
			    /* Name started with whitespace - skip line */
			    name = buf;
			} else if ((p = strchr(buf, ';'))) {
			    /* VMS/Multinet format */
			    if (p > buf+4 && !memcmp(p-4, ".DIR", 4)) {
				type = 'd';
				p -= 4;
			    } else {
				type = 'f';
			    }
			    *p = '\0';
			    name = buf;
			} else {
			    type = buf[0];
			}
			first = false;
		    } else {
			/* Not the first word */
			if ((type >= '0' && type <= '9') &&
			    !strcmp(buf, "<DIR>")) {
			    /* Some DOS FTP servers */
			    type = 'd';
			} else if (type == 'l' && !strcmp(buf, "->")) {
			    /* The name was the previous word */
			    name = bufs[nbuf ^ 1];
			}
		    }
		    nbuf ^= 1;
		    p = buf = bufs[nbuf];
		}
	    } else {
		if (!name && p < buf + FILENAME_MAX)
		    *p++ = c;
	    }
	}

	dt = dirtype(type);
	if (dt != DT_UNKNOWN) {
	    size_t len = strlen(name);

	    if (len <= NAME_MAX) {
		dirent->d_type = dt;
		dirent->d_ino = 0;	/* Not applicable */
		dirent->d_off = 0;	/* Not applicable */
		dirent->d_reclen = offsetof(struct dirent, d_name) + len+1;
		memcpy(dirent->d_name, name, len+1);
		return 0;
	    }
	}

	/* Otherwise try the next line... */
    }
}
