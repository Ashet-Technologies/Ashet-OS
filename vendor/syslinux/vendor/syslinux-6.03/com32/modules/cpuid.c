/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdio.h>
#include <stdlib.h>
#include <sys/cpu.h>
#include <console.h>
#include <com32.h>

static void dump_reg(const char *name, uint32_t val)
{
    int i;

    printf("%-3s : %10u 0x%08x ", name, val, val);

    for (i = 3; i >= 0; i--) {
	uint8_t c = val >> (i*8);
	putchar((c >= ' ' && c <= '~') ? c : '.');
    }
    putchar('\n');
}

int main(int argc, char *argv[])
{
    uint32_t leaf, counter;
    uint32_t eax, ebx, ecx, edx;

    if (argc < 2 || argc > 4) {
	printf("Usage: %s leaf [counter]\n", argv[0]);
	exit(1);
    }

    leaf = strtoul(argv[1], NULL, 0);
    counter = (argc > 2) ? strtoul(argv[2], NULL, 0) : 0;

    if (!cpu_has_eflag(EFLAGS_ID)) {
	printf("The CPUID instruction is not supported\n");
	exit(1);
    }

    cpuid_count(leaf, counter, &eax, &ebx, &ecx, &edx);

    dump_reg("eax", eax);
    dump_reg("ebx", ebx);
    dump_reg("ecx", ecx);
    dump_reg("edx", edx);

    return 0;
}
