/*
 * fprintf.c
 */

#include <stdio.h>
#include <stdarg.h>

int fprintf(FILE * file, const char *format, ...)
{
    va_list ap;
    int rv;

    va_start(ap, format);
    rv = vfprintf(file, format, ap);
    va_end(ap);
    return rv;
}
