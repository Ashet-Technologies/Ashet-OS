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
 * gpxecmd.c
 *
 * Invoke an arbitrary gPXE command, if available.
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

static void gpxecmd(const char **args)
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

    while (*args) {
	q = stpcpy(q, *args);
	*q++ = ' ';
	args++;
    }
    *--q = '\0';

    pxe_call(PXENV_FILE_EXEC, fx);

    /* This should not return... */
}

int main(int argc, const char *argv[])
{
    if (argc < 2) {
	printf("Usage: gpxecmd command...\n");
	return 1;
    }

    if (!is_gpxe()) {
	printf("gpxecmd: gPXE API not detected\n");
	return 1;
    }

    gpxecmd(argv + 1);

    return 0;
}
