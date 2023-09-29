/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010 Gert Hulselmans - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * whichsys.c
 *
 * Detemine which command to execute, based on the Syslinux bootloader variant
 * from which you run it.
 *
 * Usage:    whichsys.c32 [-iso- command] [-pxe- command] [-sys- command]
 * Examples: whichsys.c32 -iso- chain.c32 hd0 -sys- chain.c32 hd1 swap
 *           whichsys.c32 -iso- config iso.cfg -pxe- config pxe.cfg
 *
 */

#include <stdio.h>
#include <alloca.h>
#include <console.h>
#include <string.h>
#include <syslinux/boot.h>
#include "syslinux/config.h"


static struct syslinux_parameter {
    char **arg[1];
    bool option;
} isolinux, pxelinux, syslinux;

/* XXX: this really should be librarized */
static void boot_args(char **args)
{
    int len = 0, a = 0;
    char **pp;
    const char *p;
    char c, *q, *str;

    for (pp = args; *pp; pp++)
	len += strlen(*pp) + 1;

    q = str = alloca(len);
    for (pp = args; *pp; pp++) {
	p = *pp;
	while ((c = *p++))
	    *q++ = c;
	*q++ = ' ';
	a = 1;
    }
    q -= a;
    *q = '\0';

    if (!str[0])
	syslinux_run_default();
    else
	syslinux_run_command(str);
}

static void usage(void)
{
    static const char usage[] = "\
Usage:    whichsys.c32 [-iso- command] [-pxe- command] [-sys- command]\n\
Examples: whichsys.c32 -iso- chain.c32 hd0 -sys- chain.c32 hd1 swap\n\
          whichsys.c32 -iso- config iso.cfg -pxe- config pxe.cfg\n";
    fprintf(stderr, usage);
}

int main(int argc, char *argv[])
{
    const union syslinux_derivative_info *sdi;

    int arg = 0;

    /* If no argument got passed, let's show the usage */
    if (argc == 1) {
	    usage();
	    return 0;
    }

    arg++;

    while (arg < argc) {
	if (!strcmp(argv[arg], "-iso-")) {
	    argv[arg] = NULL;
	    isolinux.arg[0] = &argv[arg + 1];
	    isolinux.option = true;
	}
	if (!strcmp(argv[arg], "-pxe-")) {
	    argv[arg] = NULL;
	    pxelinux.arg[0] = &argv[arg + 1];
	    pxelinux.option = true;
	}
	if (!strcmp(argv[arg], "-sys-")) {
	    argv[arg] = NULL;
	    syslinux.arg[0] = &argv[arg + 1];
	    syslinux.option = true;
	}
	arg++;
    }

    sdi = syslinux_derivative_info();

    switch (sdi->c.filesystem) {
	case SYSLINUX_FS_ISOLINUX:
	    isolinux.option ? boot_args(isolinux.arg[0]) : fprintf(stderr, "No command specified for ISOLINUX.\n\n"); usage();
	    break;
	case SYSLINUX_FS_PXELINUX:
	    pxelinux.option ? boot_args(pxelinux.arg[0]) : fprintf(stderr, "No command specified for PXELINUX.\n\n"); usage();
	    break;
	case SYSLINUX_FS_SYSLINUX:
	    syslinux.option ? boot_args(syslinux.arg[0]) : fprintf(stderr, "No command specified for SYSLINUX.\n\n"); usage();
	    break;
	case SYSLINUX_FS_UNKNOWN:
	default:
	    fprintf(stderr, "Unknown Syslinux filesystem\n\n");
    }

    return -1;
}
