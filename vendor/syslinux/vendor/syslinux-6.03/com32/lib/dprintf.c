/*
 * dprintf.c
 */

#include <stdio.h>
#include <stdarg.h>

#ifdef DEBUG_PORT

void vdprintf(const char *, va_list);

void dprintf(const char *format, ...)
{
    va_list ap;

    va_start(ap, format);
    vdprintf(format, ap);
    va_end(ap);
}

#endif /* DEBUG_PORT */
