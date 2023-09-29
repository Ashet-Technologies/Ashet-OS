/*
 * Special handling for the MS-DOS derivative: syslinux_ldlinux
 * is a "far" object...
 */

#define _XOPEN_SOURCE 500	/* Required on glibc 2.x */
#define _BSD_SOURCE
/* glibc 2.20 deprecates _BSD_SOURCE in favour of _DEFAULT_SOURCE */
#define _DEFAULT_SOURCE 1
#include <inttypes.h>
#include <string.h>
#include <stddef.h>
#include <stdlib.h>

#include "syslxint.h"
#include "mystuff.h"

static inline void *set_fs_sl(const void *p)
{
    uint16_t seg;

    seg = ds() + ((size_t) p >> 4);
    set_fs(seg);
    return (void *)((size_t) p & 0xf);
}

#if 0				/* unused */
uint8_t get_8_sl(const uint8_t * p)
{
    uint8_t v;

    p = set_fs_sl(p);
    asm volatile("movb %%fs:%1,%0":"=q" (v):"m"(*p));
    return v;
}
#endif

uint16_t get_16_sl(const uint16_t * p)
{
    uint16_t v;

    p = set_fs_sl(p);
    asm volatile("movw %%fs:%1,%0":"=r" (v):"m"(*p));
    return v;
}

uint32_t get_32_sl(const uint32_t * p)
{
    uint32_t v;

    p = set_fs_sl(p);
    asm volatile("movl %%fs:%1,%0":"=r" (v):"m"(*p));
    return v;
}

#if 0				/* unused */
uint64_t get_64_sl(const uint64_t * p)
{
    uint32_t v0, v1;
    const uint32_t *pp = (const uint32_t *)set_fs_sl(p);

    asm volatile("movl %%fs:%1,%0" : "=r" (v0) : "m" (pp[0]));
    asm volatile("movl %%fs:%1,%0" : "=r" (v1) : "m" (pp[1]));
    return v0 + ((uint64_t)v1 << 32);
}
#endif

#if 0				/* unused */
void set_8_sl(uint8_t * p, uint8_t v)
{
    p = set_fs_sl(p);
    asm volatile("movb %1,%%fs:%0":"=m" (*p):"qi"(v));
}
#endif

void set_16_sl(uint16_t * p, uint16_t v)
{
    p = set_fs_sl(p);
    asm volatile("movw %1,%%fs:%0":"=m" (*p):"ri"(v));
}

void set_32_sl(uint32_t * p, uint32_t v)
{
    p = set_fs_sl(p);
    asm volatile("movl %1,%%fs:%0":"=m" (*p):"ri"(v));
}

void set_64_sl(uint64_t * p, uint64_t v)
{
    uint32_t *pp = (uint32_t *)set_fs_sl(p);
    asm volatile("movl %1,%%fs:%0" : "=m" (pp[0]) : "ri"((uint32_t)v));
    asm volatile("movl %1,%%fs:%0" : "=m" (pp[1]) : "ri"((uint32_t)(v >> 32)));
}

void memcpy_to_sl(void *dst, const void *src, size_t len)
{
    uint16_t seg;
    uint16_t off;

    seg = ds() + ((size_t)dst >> 4);
    off = (size_t)dst & 15;

    asm volatile("pushw %%es ; "
		 "movw %3,%%es ; "
		 "rep ; movsb ; "
		 "popw %%es"
		 : "+D" (off), "+S" (src), "+c" (len)
		 : "r" (seg)
		 : "memory");
}

void memcpy_from_sl(void *dst, const void *src, size_t len)
{
    uint16_t seg;
    uint16_t off;

    seg = ds() + ((size_t)src >> 4);
    off = (size_t)src & 15;

    asm volatile("pushw %%ds ; "
		 "movw %3,%%ds ; "
		 "rep ; movsb ; "
		 "popw %%ds"
		 : "+D" (dst), "+S" (off), "+c" (len)
		 : "r" (seg)
		 : "memory");
}

void memset_sl(void *dst, int c, size_t len)
{
    uint16_t seg;
    uint16_t off;

    seg = ds() + ((size_t)dst >> 4);
    off = (size_t)dst & 15;

    asm volatile("pushw %%es ; "
		 "movw %3,%%es ; "
		 "rep ; stosb ; "
		 "popw %%es"
		 : "+D" (off), "+c" (len)
		 : "a" (c), "r" (seg)
		 : "memory");
}
