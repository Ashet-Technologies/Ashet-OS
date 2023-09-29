/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 Michael Brown - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * cmd.c
 *
 * Execute arbitrary commands
 */

#include <com32.h>
#include <syslinux/boot.h>

int main(void)
{
    syslinux_run_command(com32_cmdline());
    return -1;
}
