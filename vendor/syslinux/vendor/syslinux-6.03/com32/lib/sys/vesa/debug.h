#ifndef LIB_SYS_VESA_DEBUG_H
#define LIB_SYS_VESA_DEBUG_H

#if 0

#include <stdio.h>
#include <unistd.h>

ssize_t __serial_write(void *fp, const void *buf, size_t count);

static void debug(const char *str, ...)
{
    va_list va;
    char buf[65536];
    size_t len;

    va_start(va, str);
    len = vsnprintf(buf, sizeof buf, str, va);
    va_end(va);

    if (len >= sizeof buf)
	len = sizeof buf - 1;

    __serial_write(NULL, buf, len);
}

#else

static inline void debug(const char *str, ...)
{
    (void)str;
}

#endif

#endif /* LIB_SYS_VESA_DEBUG_H */
