/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2006 Erwan Velu - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * -----------------------------------------------------------------------
*/

/*
 * cpuidtest.c
 *
 * A CPUID demo program using libcom32
 */

#include <string.h>
#include <stdio.h>
#include <console.h>
#include "cpuid.h"

char display_line;

int main(void)
{
    s_cpu cpu;

    for (;;) {
	detect_cpu(&cpu);
	printf("Vendor      = %s\n", cpu.vendor);
	printf("Model       = %s\n", cpu.model);
	printf("Vendor ID   = %d\n", cpu.vendor_id);
	printf("Family      = %d\n", cpu.family);
	printf("Model ID    = %d\n", cpu.model_id);
	printf("Stepping    = %d\n", cpu.stepping);
	printf("Flags       = ");
	if (cpu.flags.fpu)
	    printf("fpu ");
	if (cpu.flags.vme)
	    printf("vme ");
	if (cpu.flags.de)
	    printf("de ");
	if (cpu.flags.pse)
	    printf("pse ");
	if (cpu.flags.tsc)
	    printf("tsc ");
	if (cpu.flags.msr)
	    printf("msr ");
	if (cpu.flags.pae)
	    printf("pae ");
	if (cpu.flags.mce)
	    printf("mce ");
	if (cpu.flags.cx8)
	    printf("cx8 ");
	if (cpu.flags.apic)
	    printf("apic ");
	if (cpu.flags.sep)
	    printf("sep ");
	if (cpu.flags.mtrr)
	    printf("mtrr ");
	if (cpu.flags.pge)
	    printf("pge ");
	if (cpu.flags.mca)
	    printf("mca ");
	if (cpu.flags.cmov)
	    printf("cmov ");
	if (cpu.flags.pat)
	    printf("pat ");
	if (cpu.flags.pse_36)
	    printf("pse_36 ");
	if (cpu.flags.psn)
	    printf("psn ");
	if (cpu.flags.clflsh)
	    printf("clflsh ");
	if (cpu.flags.dts)
	    printf("dts ");
	if (cpu.flags.acpi)
	    printf("acpi ");
	if (cpu.flags.mmx)
	    printf("mmx ");
	if (cpu.flags.sse)
	    printf("sse ");
	if (cpu.flags.sse2)
	    printf("sse2 ");
	if (cpu.flags.ss)
	    printf("ss ");
	if (cpu.flags.htt)
	    printf("ht ");
	if (cpu.flags.acc)
	    printf("acc ");
	if (cpu.flags.syscall)
	    printf("syscall ");
	if (cpu.flags.mp)
	    printf("mp ");
	if (cpu.flags.nx)
	    printf("nx ");
	if (cpu.flags.mmxext)
	    printf("mmxext ");
	if (cpu.flags.lm)
	    printf("lm ");
	if (cpu.flags.nowext)
	    printf("3dnowext ");
	if (cpu.flags.now)
	    printf("3dnow! ");
	if (cpu.flags.vmx)
	    printf("vmx ");
	if (cpu.flags.svm)
	    printf("svm ");
	printf("\n");
	printf("SMP         = ");
	if (cpu.flags.smp)
	    printf("yes\n");
	else
	    printf("no\n");
	break;
    }

    return 0;
}
