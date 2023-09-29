/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * memdisk.h
 *
 * Miscellaneous header definitions
 */

#ifndef MEMDISK_H
#define MEMDISK_H

#include <stddef.h>

/* We use the com32 interface for calling 16-bit code */
#include <com32.h>

/* define it only for i386 */
#if __SIZEOF_POINTER__ == 4
#define __cdecl __attribute__((cdecl,regparm(0)))
#endif

void __cdecl intcall(uint8_t, com32sys_t *, com32sys_t *);

/* Structure passed in from the real-mode code */
struct real_mode_args {
    uint32_t rm_return;
    uint32_t rm_intcall;
    uint32_t rm_bounce;
    uint32_t rm_base;
    uint32_t rm_handle_interrupt;
    uint32_t rm_gdt;
    uint32_t rm_size;
    uint32_t rm_pmjmp;
    uint32_t rm_rmjmp;
};
extern struct real_mode_args rm_args;
#define sys_bounce ((void *)rm_args.rm_bounce)

/* This is the header in the boot sector/setup area */
struct setup_header {
    char cmdline[0x1f1];
    uint8_t setup_secs;
    uint16_t syssize;
    uint16_t swap_dev;
    uint16_t ram_size;
    uint16_t vid_mode;
    uint16_t root_dev;
    uint16_t boot_flag;
    uint16_t jump;
    char header[4];
    uint16_t version;
    uint32_t realmode_swtch;
    uint32_t start_sys;
    uint8_t type_of_loader;
    uint8_t loadflags;
    uint16_t setup_move_size;
    uint32_t code32_start;
    uint32_t ramdisk_image;
    uint32_t ramdisk_size;
    uint32_t bootsect_kludge;
    uint16_t head_end_ptr;
    uint16_t pad1;
    uint32_t cmd_line_ptr;
    uint32_t initrd_addr_max;
    uint32_t esdi;
    uint32_t edx;
    uint32_t sssp;
    uint32_t csip;
};
#define shdr ((struct setup_header *)rm_args.rm_base)

/* Standard routines */
void *memcpy(void *, const void *, size_t);
void *memset(void *, int, size_t);
void *memmove(void *, const void *, size_t);

#define strcpy(a,b)   __builtin_strcpy(a,b)

static inline size_t strlen(const char *__a)
{
    const char *__D;
    size_t __c;

asm("repne;scasb":"=D"(__D), "=c"(__c)
:	"D"(__a), "c"(-1), "a"(0), "m"(*__a));

    return __D - __a - 1;
}

/* memcpy() but returns a pointer to end of buffer */
static inline void *mempcpy(void *__d, const void *__s, unsigned int __n)
{
    memcpy(__d, __s, __n);
    return (void *)((char *)__d + __n);
}

/* memcmp() */
static inline int memcmp(const void *__a, const void *__b, unsigned int __n)
{
    const unsigned char *__aa = __a;
    const unsigned char *__bb = __b;
    int __d;

    while (__n--) {
	__d = *__bb++ - *__aa++;
	if (__d)
	    return __d;
    }

    return 0;
}

static inline void sti(void)
{
    asm volatile("sti");
}

static inline void cli(void)
{
    asm volatile("cli");
}

/* Decompression */
extern int check_zip(void *indata, uint32_t size, uint32_t * zbytes_p,
		     uint32_t * dbytes_p, uint32_t * orig_crc,
		     uint32_t * offset_p);
extern void *unzip(void *indata, uint32_t zbytes, uint32_t dbytes,
		   uint32_t orig_crc, void *target);

#endif
