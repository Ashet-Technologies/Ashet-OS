/*
 * Dump memory
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/cpu.h>
#include "sysdump.h"

static char *lowmem;
static size_t lowmem_len;

void *zero_addr;		/* Hack to keep gcc from complaining */

void snapshot_lowmem(void)
{
    extern void _start(void);

    lowmem_len = (size_t)_start;
    lowmem = malloc(lowmem_len);
    if (lowmem) {
	printf("Snapshotting lowmem... ");
	cli();
	memcpy(lowmem, zero_addr, lowmem_len);
	sti();
	printf("ok\n");
    }
}

static void dump_memory_range(struct upload_backend *be, const void *where,
			      const void *addr, size_t len)
{
    char filename[32];

    sprintf(filename, "memory/%08zx", (size_t)addr);
    cpio_writefile(be, filename, where, len);
}

void dump_memory(struct upload_backend *be)
{
    printf("Dumping memory... ");

    cpio_mkdir(be, "memory");

    if (lowmem)
	dump_memory_range(be, lowmem, zero_addr, lowmem_len);

    printf("done.\n");
}
