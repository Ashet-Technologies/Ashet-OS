/*
 * cfarcall.c
 */

#include <com32.h>

int __cfarcall(uint16_t cs, uint16_t ip, const void *stack, uint32_t stack_size)
{
    return __com32.cs_cfarcall((cs << 16) + ip, stack, stack_size);
}
