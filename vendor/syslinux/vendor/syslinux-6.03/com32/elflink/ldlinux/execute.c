/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <dprintf.h>

#include <com32.h>
#include <sys/exec.h>
#include <sys/io.h>
#include <sys/module.h>
#include "core.h"
#include "menu.h"
#include "fs.h"
#include "config.h"
#include "localboot.h"
#include "bios.h"

#include <syslinux/bootrm.h>
#include <syslinux/movebits.h>
#include <syslinux/config.h>
#include <syslinux/boot.h>

const struct image_types image_boot_types[] = {
    { "localboot", IMAGE_TYPE_LOCALBOOT },
    { "kernel", IMAGE_TYPE_KERNEL },
    { "linux", IMAGE_TYPE_LINUX },
    { "boot", IMAGE_TYPE_BOOT },
    { "bss", IMAGE_TYPE_BSS },
    { "pxe", IMAGE_TYPE_PXE },
    { "fdimage", IMAGE_TYPE_FDIMAGE },
    { "com32", IMAGE_TYPE_COM32 },
    { "config", IMAGE_TYPE_CONFIG },
    { NULL, 0 },
};

extern int create_args_and_load(char *);

__export void execute(const char *cmdline, uint32_t type, bool sysappend)
{
	const char *kernel, *args;
	const char *p;
	com32sys_t ireg;
	char *q, ch;

	memset(&ireg, 0, sizeof ireg);

	if (strlen(cmdline) >= MAX_CMDLINE_LEN) {
		printf("cmdline too long\n");
		return;
	}

	q = malloc(MAX_CMDLINE_LEN);
	if (!q) {
		printf("%s(): Fail to malloc a buffer to exec %s\n",
			__func__, cmdline);
		return;
	}

	kernel = q;
	p = cmdline;
	while (*p && !my_isspace(*p))
		*q++ = *p++;
	*q++ = '\0';

	args = q;
	while (*p && my_isspace(*p))
		p++;

	do {
		*q++ = ch = *p++;
	} while (ch);

	if (sysappend) {
		/* If we've seen some args, insert a space */
		if (--q != args)
			*q++ = ' ';

		do_sysappend(q);
	}

	dprintf("kernel is %s, args = %s  type = %d \n", kernel, args, type);

	if (kernel[0] == '.') {
		/* It might be a type specifier */
		const struct image_types *t;
		for (t = image_boot_types; t->name; t++) {
			if (!strcmp(kernel + 1, t->name)) {
				/*
				 * Strip the type specifier, apply the
				 * filename extension if COM32 and
				 * retry.
				 */
				p = args;
				if (t->type == IMAGE_TYPE_COM32) {
					p = apply_extension(p, ".c32");
					if (!p)
						return;
				}

				execute(p, t->type, sysappend);
				return;
			}
		}
	}

	if (type == IMAGE_TYPE_COM32) {
		/*
		 * We may be called with the console in an unknown
		 * state, so initialise it.
		 */
		ldlinux_console_init();

		/* new entry for elf format c32 */
		if (create_args_and_load((char *)cmdline))
			printf("Failed to load COM32 file %s\n", kernel);

		/*
		 * The old COM32 module code would run the module then
		 * drop the user back at the command prompt,
		 * irrespective of how the COM32 module was loaded,
		 * e.g. from vesamenu.c32.
		 */
		unload_modules_since(LDLINUX);

		/* Restore the console */
		ldlinux_console_init();

		ldlinux_enter_command();
	} else if (type == IMAGE_TYPE_CONFIG) {
		char *argv[] = { LDLINUX, NULL, NULL };
		char *config;
		int rv;

		/* kernel contains the config file name */
		config = malloc(FILENAME_MAX);
		if (!config)
			goto out;

		realpath(config, kernel, FILENAME_MAX);

		/* If we got anything on the command line, do a chdir */
		if (*args)
			mangle_name(config_cwd, args);

		argv[1] = config;
		rv = start_ldlinux(2, argv);
		printf("Failed to exec %s: %s\n", LDLINUX, strerror(rv));
	} else if (type == IMAGE_TYPE_LOCALBOOT) {
		local_boot(strtoul(kernel, NULL, 0));
	} else if (type == IMAGE_TYPE_PXE || type == IMAGE_TYPE_BSS ||
		   type == IMAGE_TYPE_BOOT) {
		chainboot_file(kernel, type);
	} else {
		/* Need add one item for kernel load, as we don't use
		* the assembly runkernel.inc any more */
		new_linux_kernel((char *)kernel, (char *)args);
	}

out:
	free((void *)kernel);

	/* If this returns, something went bad; return to menu */
}
