/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * ifcpu64.c
 *
 * Run one command if the CPU has 64-bit support, and another if it doesn't.
 * Eventually this and other features should get folded into some kind
 * of scripting engine.
 *
 * Usage:
 *
 *    label boot_kernel
 *        com32 ifcpu64.c32
 *        append boot_kernel_64 [-- boot_kernel_32pae] -- boot_kernel_32
 *    label boot_kernel_32
 *        kernel vmlinuz_32
 *        append ...
 *    label boot_kernel_64
 *        kernel vmlinuz_64
 *        append ...
 */

#include <alloca.h>
#include <stdlib.h>
#include <string.h>
#include <cpuid.h>
#include <syslinux/boot.h>

static bool __constfunc cpu_has_cpuid(void)
{
    return cpu_has_eflag(X86_EFLAGS_ID);
}

static bool __constfunc cpu_has_level(uint32_t level)
{
    uint32_t group;
    uint32_t limit;

    if (!cpu_has_cpuid())
	return false;

    group = level & 0xffff0000;
    limit = cpuid_eax(group);

    if ((limit & 0xffff0000) != group)
	return false;

    if (level > limit)
	return false;

    return true;
}

/* This only supports feature groups 0 and 1, corresponding to the
   Intel and AMD EDX bit vectors.  We can add more later if need be. */
static bool __constfunc cpu_has_feature(int x)
{
    uint32_t level = ((x & 1) << 31) | 1;

    return cpu_has_level(level) && ((cpuid_edx(level) >> (x & 31) & 1));
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

int main(int argc, char *argv[])
{
    char **args[3];
    int i;
    int n;

    args[0] = &argv[1];
    n = 1;
    for (i = 1; i < argc; i++) {
	if (!strcmp(argv[i], "--")) {
	    argv[i] = NULL;
	    args[n++] = &argv[i + 1];
	}
	if (n >= 3)
	    break;
    }
    while (n < 3) {
	args[n] = args[n - 1];
	n++;
    }

    boot_args(cpu_has_feature(X86_FEATURE_LM) ? args[0] :
	      cpu_has_feature(X86_FEATURE_PAE) ? args[1] : args[2]);
    return -1;
}
