/*
 * stpcpy.c
 *
 * stpcpy()
 */

#include <string.h>

char *stpcpy(char *dst, const char *src)
{
    char *q = dst;
    const char *p = src;
    char ch;

    for (;;) {
	*q = ch = *p++;
	if (!ch)
	    break;
	q++;
    }

    return q;
}
