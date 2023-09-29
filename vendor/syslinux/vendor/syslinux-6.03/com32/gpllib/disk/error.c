/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer
 *
 *   This file is part of Syslinux, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

#include <stdio.h>
#include <string.h>
#include <disk/errno_disk.h>

/**
 * get_error - decode a disk error status
 * @s:	Preallocated buffer
 *
 * Fill @buffer_ptr with the last errno_disk
 **/
void get_error(const char *s)
{
    fprintf(stderr, "%s: error %d\n", s, errno_disk);
}
