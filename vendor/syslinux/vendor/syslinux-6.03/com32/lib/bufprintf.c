#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <bufprintf.h>

int vbufprintf(struct print_buf *buf, const char *format, va_list ap)
{
    va_list ap2;
    int rv;

    va_copy(ap2, ap);
    rv = vsnprintf(NULL, 0, format, ap);

    /* >= to make sure we have space for terminating null */
    if (rv + buf->len >= buf->size) {
	size_t newsize = rv + buf->len + BUFPAD;
	char *newbuf;

	newbuf = realloc(buf->buf, newsize);
	if (!newbuf) {
	    rv = -1;
	    goto bail;
	}

	buf->buf = newbuf;
	buf->size = newsize;
    }

    rv = vsnprintf(buf->buf + buf->len, buf->size - buf->len, format, ap2);
    buf->len += rv;
bail:
    va_end(ap2);
    return rv;
}

int bufprintf(struct print_buf *buf, const char *format, ...)
{
    va_list ap;
    int rv;

    va_start(ap, format);
    rv = vbufprintf(buf, format, ap);
    va_end(ap);
    return rv;
}
