/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Erwan Velu - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * ifcpu.c
 *
 */

#include <alloca.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <cpuid.h>
#include <unistd.h>
#include <syslinux/boot.h>
#include <com32.h>
#include <consoles.h>

static inline void error(const char *msg)
{
    fputs(msg, stderr);
}

static void usage(void) 
{
 error("Run one command if system match some CPU features, another if it doesn't. \n"
 "Usage: \n"
 "   label ifcpu \n"
 "       com32 ifcpu.c32 \n"
 "       append <option> <cpu_features> -- boot_entry_1 -- boot_entry_2 \n"
 "   label boot_entry_1 \n"
 "   	  kernel vmlinuz_entry1 \n"
 "	  append ... \n"
 "   label boot_entry_2 \n"
 "       kernel vmlinuz_entry2 \n"
 "       append ... \n"
 "\n"
 "options could be :\n"
 "   debug     : display some debugging messages \n"
 "   dry-run   : just do the detection, don't boot \n"
 "\n"
 "cpu_features could be:\n"
 "   64         : Processor is x86_64 compatible (lm cpu flag)\n"
 "   hvm        : Processor features hardware virtualization (hvm or svm cpu flag)\n"
 "   multicore  : Processor must be multi-core \n"
 "   smp        : System must be multi-processor \n"
 "   pae        : Processor features Physical Address Extension (PAE)\n"
 "   hypervisor : Processor is running under an hypervisor\n"
 "\n"
 "if you want to match many cpu features, just separate them with a single space.\n");
}

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

#define show_bool(mybool) mybool ? "found":"not found"

int main(int argc, char *argv[])
{
    char **args[3];
    int i=0;
    int n=0;
    bool hardware_matches = true;
    bool multicore = false;
    bool dryrun = false;
    bool debug = false;

    s_cpu cpu;
    console_ansi_raw();
    detect_cpu(&cpu);

    /* If no argument got passed, let's show the usage */
    if (argc == 1) {
	    usage();
	    return -1;
    }

    for (i = 1; i < argc; i++) {
	if (!strcmp(argv[i], "--")) {
	    argv[i] = NULL;
	    args[n++] = &argv[i + 1];
	} else if (!strcmp(argv[i], "64")) {
	    if (debug)
		printf(" 64bit      : %s on this system\n",
		       show_bool(cpu.flags.lm));
	    hardware_matches = cpu.flags.lm && hardware_matches;
	} else if (!strcmp(argv[i], "pae")) {
	    if (debug)
		printf(" pae        : %s on this system\n",
		       show_bool(cpu.flags.pae));
	    hardware_matches = cpu.flags.pae && hardware_matches;
	} else if (!strcmp(argv[i], "hvm")) {
	    if (debug)
		printf(" hvm        : %s on this system\n",
		       show_bool((cpu.flags.vmx || cpu.flags.svm)));
	    hardware_matches = (cpu.flags.vmx || cpu.flags.svm)
		&& hardware_matches;
	} else if (!strcmp(argv[i], "multicore")) {
	    if (debug)
		printf(" multicore  : %d cores on this system\n", cpu.num_cores);
	    if (cpu.num_cores > 1)
		multicore = true;
	    hardware_matches = multicore && hardware_matches;
	} else if (!strcmp(argv[i], "smp")) {
	    if (debug)
		printf(" smp        : %s on this system\n", show_bool(cpu.flags.smp));
	    hardware_matches = cpu.flags.smp && hardware_matches;
	} else if (!strcmp(argv[i], "hypervisor")) {
	    if (debug)
		printf(" hypervisor : %s on this system\n", show_bool(cpu.flags.hypervisor));
	    hardware_matches = cpu.flags.hypervisor && hardware_matches;
	} else if (!strcmp(argv[i], "dry-run")) {
	    dryrun = true;
	} else if (!strcmp(argv[i], "debug")) {
	    debug = true;
	}
	if (n >= 2)
	    break;
    }
    while (n < 2) {
	args[n] = args[n - 1];
	n++;
    }
    if (debug) {
	printf("\nBooting labels are : '%s' or '%s'\n", *args[0], *args[1]);
	printf("Hardware requirements%smatch this system, let's booting '%s'\n",
	       hardware_matches ? " " : " doesn't ",
	       hardware_matches ? *args[0] : *args[1]);
	printf("Sleeping 5sec before booting\n");
	if (!dryrun)
	    sleep(5);
    }

    if (!dryrun)
	boot_args(hardware_matches ? args[0] : args[1]);
    else
	printf("Dry-run mode, let's exiting\n");

    return -1;
}
