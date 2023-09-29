/* -*- c -*- ------------------------------------------------------------- *
 *
 *   Copyright 2004-2005 Murali Krishnan Ganapathy - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <string.h>
#include <com32.h>
#include <core.h>
#include <graphics.h>
#include "syslnx.h"
#include <syslinux/config.h>
#include <syslinux/video.h>

com32sys_t inreg, outreg;	// Global registers for this module

void runsyslinuxcmd(const char *cmd)
{
    char *bounce;

    bounce = lmalloc(strlen(cmd) + 1);
    if (!bounce)
	return;

    strcpy(bounce, cmd);
    load_kernel(bounce);
}

void gototxtmode(void)
{
    syslinux_force_text_mode();
}

void syslinux_idle(void)
{
    __idle();
}

unsigned int getversion(char *deriv, unsigned int *numfun)
{
    if (deriv)
	*deriv = __syslinux_version.filesystem;
    if (numfun)
	*numfun = __syslinux_version.max_api;
    return __syslinux_version.version;
}

char issyslinux(void)
{
    return !!getversion(NULL, NULL);
}

void runsyslinuximage(const char *cmd, long ipappend)
{
    (void)ipappend;		// XXX: Unused?!

    getversion(NULL, NULL);
    runsyslinuxcmd(cmd);
}
