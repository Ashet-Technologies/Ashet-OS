/*
 * mempcpy.c
 */

#include <string.h>
#include <stdint.h>

/* simply a wrapper around memcpy implementation */

void *mempcpy(void *dst, const void *src, size_t n)
{

	return (char *)memcpy(dst, src, n) + n;
}
