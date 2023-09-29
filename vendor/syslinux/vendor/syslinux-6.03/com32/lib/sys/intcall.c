/*
 * intcall.c
 */

#include <com32.h>

void __intcall(uint8_t vector, const com32sys_t * ireg, com32sys_t * oreg)
{
    __com32.cs_intcall(vector, ireg, oreg);
}
