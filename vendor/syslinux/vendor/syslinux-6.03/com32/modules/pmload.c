/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
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
 * ----------------------------------------------------------------------- */

/*
 * pmload.c
 *
 * Load a binary file and run it in protected mode.  We give it
 * an ELF-style invocation record, becase, why not?
 *
 * Usage: pmload.c32 filename address [arguments...]
 */

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <elf.h>
#include <console.h>
#include <dprintf.h>

#include <syslinux/loadfile.h>
#include <syslinux/movebits.h>
#include <syslinux/bootpm.h>

/* If we don't have this much memory for the stack, signal failure */
#define MIN_STACK	512

static inline void error(const char *msg)
{
    fputs(msg, stderr);
}

int boot_raw(void *ptr, size_t len, addr_t where, char **argv)
{
    struct syslinux_movelist *ml = NULL;
    struct syslinux_memmap *mmap = NULL, *amap = NULL;
    struct syslinux_pm_regs regs;
    int argc;
    addr_t argsize;
    char **argp;
    addr_t lstart, llen;
    char *stack_frame = NULL;
    addr_t stack_frame_size;
    addr_t stack_pointer;
    uint32_t *spp;
    char *sfp;
    addr_t sfa;

    memset(&regs, 0, sizeof regs);

    mmap = syslinux_memory_map();
    amap = syslinux_dup_memmap(mmap);
    if (!mmap || !amap)
	goto bail;

    dprintf("Initial memory map:\n");
    syslinux_dump_memmap(mmap);

    dprintf("Segment at 0x%08x len 0x%08x\n", where, len);

    if (syslinux_memmap_type(amap, where, len) != SMT_FREE) {
	printf("Memory segment at 0x%08x (len 0x%08x) is unavailable\n",
	       where, len);
	goto bail;		/* Memory region unavailable */
    }

    /* Mark this region as allocated in the available map */
    if (syslinux_add_memmap(&amap, where, len, SMT_ALLOC))
	goto bail;

    /* Data present region.  Create a move entry for it. */
    if (syslinux_add_movelist(&ml, where, (addr_t) ptr, len))
	goto bail;

    /* Create the invocation record (initial stack frame) */

    argsize = argc = 0;
    for (argp = argv; *argp; argp++) {
	dprintf("argv[%2d] = \"%s\"\n", argc, *argp);
	argc++;
	argsize += strlen(*argp) + 1;
    }

    /* We need the argument strings, argument pointers,
       argc, plus four zero-word terminators. */
    stack_frame_size = argsize + argc * sizeof(char *) + 5 * sizeof(long);
    stack_frame_size = (stack_frame_size + 15) & ~15;
    stack_frame = calloc(stack_frame_size, 1);
    if (!stack_frame)
	goto bail;

    dprintf("Right before syslinux_memmap_largest()...\n");
    syslinux_dump_memmap(amap);

    if (syslinux_memmap_largest(amap, SMT_FREE, &lstart, &llen))
	goto bail;		/* NO free memory?! */

    if (llen < stack_frame_size + MIN_STACK + 16)
	goto bail;		/* Insufficient memory  */

    /* Initial stack pointer address */
    stack_pointer = (lstart + llen - stack_frame_size) & ~15;

    dprintf("Stack frame at 0x%08x len 0x%08x\n",
	    stack_pointer, stack_frame_size);

    /* Create the stack frame.  sfp is the pointer in current memory for
       the next argument string, sfa is the address in its final resting place.
       spp is the pointer into the argument array in current memory. */
    spp = (uint32_t *) stack_frame;
    sfp = stack_frame + argc * sizeof(char *) + 5 * sizeof(long);
    sfa = stack_pointer + argc * sizeof(char *) + 5 * sizeof(long);

    *spp++ = argc;
    for (argp = argv; *argp; argp++) {
	int bytes = strlen(*argp) + 1;	/* Including final null */
	*spp++ = sfa;
	memcpy(sfp, *argp, bytes);
	sfp += bytes;
	sfa += bytes;
    }
    /* Zero fields are aready taken care of by calloc() */

    /* ... and we'll want to move it into the right place... */
#if DEBUG
    if (syslinux_memmap_type(amap, stack_pointer, stack_frame_size)
	!= SMT_FREE) {
	dprintf("Stack frame area not free (how did that happen?)!\n");
	goto bail;		/* Memory region unavailable */
    }
#endif

    if (syslinux_add_memmap(&amap, stack_pointer, stack_frame_size, SMT_ALLOC))
	goto bail;

    if (syslinux_add_movelist(&ml, stack_pointer, (addr_t) stack_frame,
			      stack_frame_size))
	goto bail;

    memset(&regs, 0, sizeof regs);
    regs.eip = where;
    regs.esp = stack_pointer;

    dprintf("Final memory map:\n");
    syslinux_dump_memmap(mmap);

    dprintf("Final available map:\n");
    syslinux_dump_memmap(amap);

    dprintf("Movelist:\n");
    syslinux_dump_movelist(ml);

    /* This should not return... */
    fputs("Booting...\n", stdout);
    syslinux_shuffle_boot_pm(ml, mmap, 0, &regs);

bail:
    if (stack_frame)
	free(stack_frame);
    syslinux_free_memmap(amap);
    syslinux_free_memmap(mmap);
    syslinux_free_movelist(ml);

    return -1;
}

int main(int argc, char *argv[])
{
    void *data;
    size_t data_len;
    addr_t where;

    if (argc < 3) {
	error("Usage: pmload.c32 bin_file address arguments...\n");
	return 1;
    }

    where = strtoul(argv[2], NULL, 0);

    if (loadfile(argv[1], &data, &data_len)) {
	error("Unable to load file\n");
	return 1;
    }

    boot_raw(data, data_len, where, &argv[1]);
    error("Failed to boot, probably insufficient memory\n");
    return 1;
}
