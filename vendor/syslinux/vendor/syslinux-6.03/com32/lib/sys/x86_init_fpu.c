/*
 * x86_has_fpu.c
 *
 * Test for an x86 FPU, and do any necessary setup.
 */

#if __SIZEOF_POINTER__ == 4
#include <i386/x86_init_fpu.c>
#elif __SIZEOF_POINTER__ == 8
#include <x86_64/x86_init_fpu.c>
#else
#error "Unable to build for to-be-defined architecture type"
#endif
#if 0
#include <inttypes.h>
#include <sys/fpu.h>

static inline uint64_t get_cr0(void)
{
#if __SIZEOF_POINTER__ == 4
    uint32_t v;
asm("movl %%cr0,%0":"=r"(v));
#elif __SIZEOF_POINTER__ == 8
    uint64_t v;
asm("movq %%cr0,%0":"=r"(v));
#else
#error "Unable to build for to-be-defined architecture type"
#endif
    return v;
}

static inline void set_cr0(uint32_t v)
{
#if __SIZEOF_POINTER__ == 4
    asm volatile ("movl %0,%%cr0"::"r" (v));
#elif __SIZEOF_POINTER__ == 8
    asm volatile ("movq %0,%%cr0"::"r" ((uint64_t)v));
#else
#error "Unable to build for to-be-defined architecture type"
#endif
}

#define CR0_PE	0x00000001
#define CR0_MP  0x00000002
#define CR0_EM  0x00000004
#define CR0_TS  0x00000008
#define CR0_ET  0x00000010
#define CR0_NE  0x00000020
#define CR0_WP  0x00010000
#define CR0_AM  0x00040000
#define CR0_NW  0x20000000
#define CR0_CD  0x40000000
#define CR0_PG  0x80000000

int x86_init_fpu(void)
{
    uint32_t cr0;
    uint16_t fsw = 0xffff;
    uint16_t fcw = 0xffff;

    cr0 = get_cr0();
    cr0 &= ~(CR0_EM | CR0_TS);
    cr0 |= CR0_MP;
    set_cr0(cr0);

    asm volatile ("fninit");
    asm volatile ("fnstsw %0":"+m" (fsw));
    if (fsw != 0)
	return -1;

    asm volatile ("fnstcw %0":"+m" (fcw));
    if ((fcw & 0x103f) != 0x3f)
	return -1;

    /* Techically, this could be a 386 with a 287.  We could add a check
       for that here... */

    return 0;
}
#endif
