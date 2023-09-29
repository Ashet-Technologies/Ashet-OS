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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <inttypes.h>
#include <dprintf.h>
#include <console.h>
#include <sys/cpu.h>
#include <version.h>
#include "sysdump.h"

const char program[] = "sysdump";
const char version[] = "SYSDUMP " VERSION_STR " " DATE "\n";

__noreturn die(const char *msg)
{
    printf("%s: %s\n", program, msg);
    exit(1);
}

static void dump_all(struct upload_backend *be, const char *argv[])
{
    cpio_init(be, argv);

    cpio_writefile(be, "sysdump", version, sizeof version-1);

    dump_memory_map(be);
    dump_memory(be);
    dump_dmi(be);
    dump_acpi(be);
    dump_cpuid(be);
    dump_pci(be);
    dump_vesa_tables(be);

    cpio_close(be);
    flush_data(be);
}

static struct upload_backend *upload_backends[] =
{
    &upload_tftp,
    &upload_ymodem,
    &upload_srec,
    NULL
};

__noreturn usage(void)
{
    struct upload_backend **bep, *be;

    printf("Usage:\n");
    for (bep = upload_backends ; (be = *bep) ; bep++)
	printf("    %s %s %s\n", program, be->name, be->helpmsg);

    exit(1);
}

int main(int argc, char *argv[])
{
    struct upload_backend **bep, *be;

    fputs(version, stdout);

    if (argc < 2)
	usage();

    for (bep = upload_backends ; (be = *bep) ; bep++) {
	if (!strcmp(be->name, argv[1]))
	    break;
    }

    if (!be || argc < be->minargs + 2)
	usage();

    /* Do this as early as possible */
    snapshot_lowmem();

    printf("Backend: %s\n", be->name);

    /* Do the actual data dump */
    dump_all(be, (const char **)argv + 2);

    return 0;
}
