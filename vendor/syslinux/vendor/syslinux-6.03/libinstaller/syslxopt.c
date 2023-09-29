/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010 Intel Corp. - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * syslxopt.c
 *
 * parse cmdline for extlinux and syslinux installer
 *
 */
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <getopt.h>
#include <sysexits.h>
#include "version.h"
#include "syslxcom.h"
#include "syslxfs.h"
#include "syslxopt.h"

/* These are the options we can set their values */
struct sys_options opt = {
    .sectors = 0,
    .heads = 0,
    .raid_mode = 0,
    .stupid_mode = 0,
    .reset_adv = 0,
    .set_once = NULL,
    .update_only = -1,
    .directory = NULL,
    .device = NULL,
    .offset = 0,
    .menu_save = NULL,
    .install_mbr = 0,
    .activate_partition = 0,
    .force = 0,
    .bootsecfile = NULL,
};

const struct option long_options[] = {
    {"force", 0, NULL, 'f'},	/* DOS/Win32/mtools only */
    {"install", 0, NULL, 'i'},
    {"directory", 1, NULL, 'd'},
    {"offset", 1, NULL, 't'},
    {"update", 0, NULL, 'U'},
    {"zipdrive", 0, NULL, 'z'},
    {"sectors", 1, NULL, 'S'},
    {"stupid", 0, NULL, 's'},
    {"heads", 1, NULL, 'H'},
    {"raid-mode", 0, NULL, 'r'},
    {"version", 0, NULL, 'v'},
    {"help", 0, NULL, 'h'},
    {"once", 1, NULL, OPT_ONCE},
    {"clear-once", 0, NULL, 'O'},
    {"reset-adv", 0, NULL, OPT_RESET_ADV},
    {"menu-save", 1, NULL, 'M'},
    {"mbr", 0, NULL, 'm'},	/* DOS/Win32 only */
    {"active", 0, NULL, 'a'},	/* DOS/Win32 only */
    {"device", 1, NULL, OPT_DEVICE},
    {NULL, 0, NULL, 0}
};

const char short_options[] = "t:fid:UuzsS:H:rvho:OM:ma";

void __attribute__ ((noreturn)) usage(int rv, enum syslinux_mode mode)
{
    switch (mode) {
    case MODE_SYSLINUX:
	/* For unmounted fs installation (syslinux) */
	fprintf(stderr,
	    "Usage: %s [options] device\n"
	    "  --offset     -t  Offset of the file system on the device \n"
	    "  --directory  -d  Directory for installation target\n",
	    program);
	break;

    case MODE_EXTLINUX:
	/* Mounted fs installation (extlinux) */
	/* Actually extlinux can also use -d to provide a directory too... */
	fprintf(stderr,
	    "Usage: %s [options] directory\n"
	    "  --device         Force use of a specific block device (experts only)\n",
	    program);
	break;

    case MODE_SYSLINUX_DOSWIN:
	/* For fs installation under Windows (syslinux.exe) */
	fprintf(stderr,
	    "Usage: %s [options] <drive>: [bootsecfile]\n"
	    "  --directory  -d  Directory for installation target\n",
	    program);
	break;
    }

    fprintf(stderr,
	    "  --install    -i  Install over the current bootsector\n"
	    "  --update     -U  Update a previous installation\n"
	    "  --zip        -z  Force zipdrive geometry (-H 64 -S 32)\n"
	    "  --sectors=#  -S  Force the number of sectors per track\n"
	    "  --heads=#    -H  Force number of heads\n"
	    "  --stupid     -s  Slow, safe and stupid mode\n"
	    "  --raid       -r  Fall back to the next device on boot failure\n"
	    "  --once=...   %s  Execute a command once upon boot\n"
	    "  --clear-once -O  Clear the boot-once command\n"
	    "  --reset-adv      Reset auxilliary data\n",
	    mode == MODE_SYSLINUX  ? "  " : "-o");
    /*
     * Have to chop this roughly in half for the DOS installer due
     * to limited output buffer size
     */
    fprintf(stderr,
	    "  --menu-save= -M  Set the label to select as default on the next boot\n");
    if (mode == MODE_SYSLINUX_DOSWIN)
	fprintf(stderr,
		"  --mbr        -m  Install an MBR\n"
		"  --active     -a  Mark partition as active\n");

    if (mode == MODE_SYSLINUX_DOSWIN || mode == MODE_SYSLINUX)
	fprintf(stderr,
		"  --force      -f  Ignore precautions\n");

    exit(rv);
}

void parse_options(int argc, char *argv[], enum syslinux_mode mode)
{
    int o;

    program = argv[0];
    while ((o = getopt_long(argc, argv, short_options,
			    long_options, NULL)) != EOF) {
	switch (o) {
	case 'f':
	    opt.force = 1;
	    break;
	case 'z':
	    opt.heads = 64;
	    opt.sectors = 32;
	    break;
	case 'S':
	    opt.sectors = strtoul(optarg, NULL, 0);
	    if (opt.sectors < 1 || opt.sectors > 63) {
		fprintf(stderr,
			"%s: invalid number of sectors: %u (must be 1-63)\n",
			program, opt.sectors);
		exit(EX_USAGE);
	    }
	    break;
	case 'H':
	    opt.heads = strtoul(optarg, NULL, 0);
	    if (opt.heads < 1 || opt.heads > 256) {
		fprintf(stderr,
			"%s: invalid number of heads: %u (must be 1-256)\n",
			program, opt.heads);
		exit(EX_USAGE);
	    }
	    break;
	case 'r':
	    opt.raid_mode = 1;
	    break;
	case 's':
	    opt.stupid_mode = 1;
	    break;
	case 'i':
	    opt.update_only = 0;
	    break;
	case 'u':
	case 'U':
	    opt.update_only = 1;
	    break;
	case 'h':
	    usage(0, mode);
	    break;
	case 'o':
	    if (mode == MODE_SYSLINUX) {
		fprintf(stderr,	"%s: -o will change meaning in a future version, use -t or --offset\n", program);
		goto opt_offset;
	    }
	    /* else fall through */
	case OPT_ONCE:
	    opt.set_once = optarg;
	    break;
	case 't':
	opt_offset:
	    opt.offset = strtoul(optarg, NULL, 0);
	    break;
	case 'O':
	    opt.set_once = "";
	    break;
	case 'd':
	    opt.directory = optarg;
	    break;
	case OPT_RESET_ADV:
	    opt.reset_adv = 1;
	    break;
	case 'M':
	    opt.menu_save = optarg;
	    break;
	case 'm':
	    opt.install_mbr = 1;
	    break;
	case 'a':
	    opt.activate_partition = 1;
	    break;
	case OPT_DEVICE:
	    if (mode != MODE_EXTLINUX)
		usage(EX_USAGE, mode);
	    opt.device = optarg;
	    break;
	case 'v':
	    fprintf(stderr,
		    "%s " VERSION_STR "  Copyright 1994-" YEAR_STR
		    " H. Peter Anvin et al\n", program);
	    exit(0);
	default:
	    fprintf(stderr, "%s: Unknown option: -%c\n", program, optopt);
	    usage(EX_USAGE, mode);
	}
    }

    switch (mode) {
    case MODE_SYSLINUX:
    case MODE_SYSLINUX_DOSWIN:
	opt.device = argv[optind++];
	break;
    case MODE_EXTLINUX:
	if (!opt.directory)
	    opt.directory = argv[optind++];
	break;
    }

    if (argv[optind] && (mode == MODE_SYSLINUX_DOSWIN))
	/* Allow for the boot-sector argument */
	opt.bootsecfile = argv[optind++];
    if (argv[optind])
	usage(EX_USAGE, mode);	/* Excess arguments */
}

/*
 * Make any user-specified ADV modifications in memory
 */
int modify_adv(void)
{
    int rv = 0;

    if (opt.reset_adv)
	syslinux_reset_adv(syslinux_adv);

    if (opt.set_once) {
	if (syslinux_setadv(ADV_BOOTONCE, strlen(opt.set_once), opt.set_once)) {
	    fprintf(stderr, "%s: not enough space for boot-once command\n",
		    program);
	    rv = -1;
	}
    }
    if (opt.menu_save) {
        if (syslinux_setadv(ADV_MENUSAVE, strlen(opt.menu_save), opt.menu_save)) {
	    fprintf(stderr, "%s: not enough space for menu-save label\n",
		    program);
	    rv = -1;
        }
    }

    return rv;
}
