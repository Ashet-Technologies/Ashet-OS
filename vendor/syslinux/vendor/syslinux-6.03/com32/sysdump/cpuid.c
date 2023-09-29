/*
 * Dump CPUID information
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <com32.h>
#include <sys/cpu.h>
#include "sysdump.h"

struct cpuid_data {
    uint32_t eax, ebx, ecx, edx;
};

struct cpuid_info {
    uint32_t eax, ecx;
    struct cpuid_data data;
};

static void get_cpuid(uint32_t eax, uint32_t ecx, struct cpuid_data *data)
{
#if __SIZEOF_POINTER__ == 4
    asm("pushl %%ebx ; cpuid ; movl %%ebx,%1 ; popl %%ebx"
	: "=a" (data->eax), "=r" (data->ebx),
	  "=c" (data->ecx), "=d" (data->edx)
	: "a" (eax), "c" (ecx));
#elif __SIZEOF_POINTER__ == 8
        asm volatile("push %%rbx; cpuid; movl %%ebx, %1; pop %%rbx"
            : "=a" (data->eax),
              "=b" (data->ebx),
              "=c" (data->ecx),
              "=d" (data->edx)
            : "a" (eax), "c" (ecx));
#else
#error "unsupported architecture"
#endif
}

#define CPUID_CHUNK 128

void dump_cpuid(struct upload_backend *be)
{
    struct cpuid_info *buf = NULL;
    int nentry, nalloc;
    uint32_t region;
    struct cpuid_data base_leaf;
    uint32_t base, leaf, count;
    struct cpuid_data invalid_leaf;
    struct cpuid_data data;

    if (!cpu_has_eflag(EFLAGS_ID))
	return;

    printf("Dumping CPUID... ");

    nentry = nalloc = 0;

    /* Find out what the CPU returns for invalid leaves */
    get_cpuid(0, 0, &base_leaf);
    get_cpuid(base_leaf.eax+1, 0, &invalid_leaf);

    for (region = 0 ; region <= 0xffff ; region++) {
	base = region << 16;

	get_cpuid(base, 0, &base_leaf);
	if (region && !memcmp(&base_leaf, &invalid_leaf, sizeof base_leaf))
	    continue;

	if ((base_leaf.eax ^ base) & 0xffff0000)
	    continue;

	for (leaf = base ; leaf <= base_leaf.eax ; leaf++) {
	    get_cpuid(leaf, 0, &data);
	    count = 0;

	    do {
		if (nentry >= nalloc) {
		    nalloc += CPUID_CHUNK;
		    buf = realloc(buf, nalloc*sizeof *buf);
		    if (!buf)
			return;		/* FAILED */
		}
		buf[nentry].eax = leaf;
		buf[nentry].ecx = count;
		buf[nentry].data = data;
		nentry++;
		count++;

		get_cpuid(leaf, count, &data);
	    } while (memcmp(&data, &buf[nentry-1].data, sizeof data) &&
		     (data.eax | data.ebx | data.ecx | data.edx));
	}
    }

    if (nentry)
	cpio_writefile(be, "cpuid", buf, nentry*sizeof *buf);
    free(buf);

    printf("done.\n");
}
