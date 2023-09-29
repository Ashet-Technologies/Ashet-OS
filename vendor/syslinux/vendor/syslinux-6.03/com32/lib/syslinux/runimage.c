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
 * runimage.c
 *
 * Load and run a syslinux image.
 */

#include <stdlib.h>
#include <string.h>
#include <syslinux/boot.h>
#include <syslinux/config.h>
#include <core.h>

void syslinux_run_kernel_image(const char *filename, const char *cmdline,
			       uint32_t ipappend_flags, uint32_t type)
{
    char *bbcmdline  = NULL;
    size_t len;
    int rv;

    /* +2 for NULL and space */
    len = strlen(filename) + strlen(cmdline) + 2;
    bbcmdline = malloc(len);
    if (!bbcmdline)
	return;

    rv = snprintf(bbcmdline, len, "%s %s", filename, cmdline);
    if (rv == -1 || (size_t)rv >= len)
	return;

    SysAppends = ipappend_flags;
    execute(bbcmdline, type, true);
}
