/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2010 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * advio.c
 *
 * Linux ADV I/O
 *
 * Return 0 on success, -1 on error, and set errno.
 *
 */
#define  _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include "syslxint.h"
#include "syslxcom.h"

/*
 * Read the ADV from an existing instance, or initialize if invalid.
 * Returns -1 on fatal errors, 0 if ADV is okay, 1 if the ADV is
 * invalid, and 2 if the file does not exist.
 */
int read_adv(const char *path, const char *cfg)
{
    char *file;
    int fd = -1;
    struct stat st;
    int err = 0;
    int rv;

    rv = asprintf(&file, "%s%s%s", path,
		  path[0] && path[strlen(path) - 1] == '/' ? "" : "/", cfg);

    if (rv < 0 || !file) {
	perror(program);
	return -1;
    }

    fd = open(file, O_RDONLY);
    if (fd < 0) {
	if (errno != ENOENT) {
	    err = -1;
	} else {
	    syslinux_reset_adv(syslinux_adv);
	    err = 2;		/* Nonexistence is not a fatal error */
	}
    } else if (fstat(fd, &st)) {
	err = -1;
    } else if (st.st_size < 2 * ADV_SIZE) {
	/* Too small to be useful */
	syslinux_reset_adv(syslinux_adv);
	err = 0;		/* Nothing to read... */
    } else if (xpread(fd, syslinux_adv, 2 * ADV_SIZE,
		      st.st_size - 2 * ADV_SIZE) != 2 * ADV_SIZE) {
	err = -1;
    } else {
	/* We got it... maybe? */
	err = syslinux_validate_adv(syslinux_adv) ? 1 : 0;
    }

    if (err < 0)
	perror(file);

    if (fd >= 0)
	close(fd);

    free(file);

    return err;
}

/*
 * Update the ADV in an existing installation.
 */
int write_adv(const char *path, const char *cfg)
{
    unsigned char advtmp[2 * ADV_SIZE];
    char *file;
    int fd = -1;
    struct stat st, xst;
    int err = 0;
    int rv;

    rv = asprintf(&file, "%s%s%s", path,
		  path[0] && path[strlen(path) - 1] == '/' ? "" : "/", cfg);

    if (rv < 0 || !file) {
	perror(program);
	return -1;
    }

    fd = open(file, O_RDONLY);
    if (fd < 0) {
	err = -1;
    } else if (fstat(fd, &st)) {
	err = -1;
    } else if (st.st_size < 2 * ADV_SIZE) {
	/* Too small to be useful */
	err = -2;
    } else if (xpread(fd, advtmp, 2 * ADV_SIZE,
		      st.st_size - 2 * ADV_SIZE) != 2 * ADV_SIZE) {
	err = -1;
    } else {
	/* We got it... maybe? */
	err = syslinux_validate_adv(advtmp) ? -2 : 0;
	if (!err) {
	    /* Got a good one, write our own ADV here */
	    clear_attributes(fd);

	    /* Need to re-open read-write */
	    close(fd);
	    fd = open(file, O_RDWR | O_SYNC);
	    if (fd < 0) {
		err = -1;
	    } else if (fstat(fd, &xst) || xst.st_ino != st.st_ino ||
		       xst.st_dev != st.st_dev || xst.st_size != st.st_size) {
		fprintf(stderr, "%s: race condition on write\n", file);
		err = -2;
	    }
	    /* Write our own version ... */
	    if (xpwrite(fd, syslinux_adv, 2 * ADV_SIZE,
			st.st_size - 2 * ADV_SIZE) != 2 * ADV_SIZE) {
		err = -1;
	    }

	    sync();
	    set_attributes(fd);
	}
    }

    if (err == -2)
	fprintf(stderr, "%s: cannot write auxilliary data (need --update)?\n",
		file);
    else if (err == -1)
	perror(file);

    if (fd >= 0)
	close(fd);
    if (file)
	free(file);

    return err;
}
