/*
 * strnlen()
 */

#include <string.h>

size_t strnlen(const char *s, size_t n)
{
    const char *ss = s;
    while (n-- && *ss)
	ss++;
    return ss - s;
}
