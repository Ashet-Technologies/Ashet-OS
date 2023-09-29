/*
 * printf.c
 */

#include <stdio.h>
#include <stdarg.h>

int printf(const char *format, ...)
{
    va_list ap;
    int rv;

    va_start(ap, format);
    rv = vfprintf(stdout, format, ap);
    va_end(ap);
    return rv;
}
