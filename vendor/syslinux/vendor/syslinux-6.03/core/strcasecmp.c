/*
 * strcasecmp.c
 */

#include <string.h>
#include <ctype.h>

int strcasecmp(const char *s1, const char *s2)
{
    return strncasecmp(s1, s2, -1);
}
