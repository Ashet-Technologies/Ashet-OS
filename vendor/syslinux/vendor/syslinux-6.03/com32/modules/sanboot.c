/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * sanboot.c
 *
 * Invoke the gPXE "sanboot" command, if available.
 */

#include <alloca.h>
#include <inttypes.h>
#include <stdio.h>
#include <console.h>
#include <com32.h>
#include <string.h>

#include <sys/gpxe.h>
#include <syslinux/pxe_api.h>

struct segoff16 {
    uint16_t offs, seg;
};

struct s_PXENV_FILE_EXEC {
    uint16_t Status;
    struct segoff16 Command;
};

static void sanboot(const char **args)
{
    char *q;
    struct s_PXENV_FILE_EXEC *fx;

    fx = lmalloc(sizeof *fx);
    if (!fx)
	return;

    q = (char *)(fx + 1);

    fx->Status = 1;
    fx->Command.offs = OFFS(q);
    fx->Command.seg = SEG(q);

    q = stpcpy(q, "sanboot");

    while (*args) {
	*q++ = ' ';
	q = stpcpy(q, *args);
	args++;
    }

    pxe_call(PXENV_FILE_EXEC, fx);

    /* This should not return... */
}

int main(int argc, const char *argv[])
{
    if (argc < 2) {
	printf("Usage: sanboot rootpath\n");
	return 1;
    }

    if (!is_gpxe()) {
	printf("sanboot: gPXE API not detected\n");
	return 1;
    }

    sanboot(argv + 1);

    /* sanboot() should not return... */
    printf("SAN boot failed.\n");
    return 1;
}
