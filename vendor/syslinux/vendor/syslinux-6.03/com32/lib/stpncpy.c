/*
 * stpncpy.c
 *
 * stpncpy()
 */

#include <string.h>

char *stpncpy(char *dst, const char *src, size_t n)
{
    char *q = dst;
    const char *p = src;
    char ch;

    while (n--) {
	*q = ch = *p++;
	if (!ch)
	    break;
	q++;
    }

    return q;
}
