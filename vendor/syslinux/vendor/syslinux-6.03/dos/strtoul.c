/*
 * strtoul.c
 *
 * strtoul() function
 */

#include <stddef.h>
#include <inttypes.h>

extern uintmax_t strntoumax(const char *nptr, char **endptr, int base, size_t n);

unsigned long strtoul(const char *nptr, char **endptr, int base)
{
    return (unsigned long) strntoumax(nptr, endptr, base, ~(size_t) 0);
}
