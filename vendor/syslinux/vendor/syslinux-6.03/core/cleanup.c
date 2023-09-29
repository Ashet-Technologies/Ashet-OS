/* -----------------------------------------------------------------------
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * -----------------------------------------------------------------------
 */
#include <com32.h>
#include <core.h>
#include <syslinux/memscan.h>
#include <syslinux/firmware.h>

/*
 * cleanup.c
 *
 * Some final tidying before jumping to a kernel or bootsector
 */

/*
 * cleanup_hardware:
 *
 *	Shut down anything transient.
 */

__export void cleanup_hardware(void)
{
	firmware->cleanup();
}
