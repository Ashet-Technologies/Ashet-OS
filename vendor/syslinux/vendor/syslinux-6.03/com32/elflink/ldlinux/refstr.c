/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * refstr.c
 *
 * Simple reference-counted strings
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/module.h>
#include "refstr.h"

/* Allocate space for a refstring of len bytes, plus final null */
/* The final null is inserted in the string; the rest is uninitialized. */
char *refstr_alloc(size_t len)
{
    char *r = malloc(sizeof(unsigned int) + len + 1);
    if (!r)
	return NULL;
    *(unsigned int *)r = 1;
    r += sizeof(unsigned int);
    r[len] = '\0';
    return r;
}

const char *refstrndup(const char *str, size_t len)
{
    char *r;

    if (!str)
	return NULL;

    len = strnlen(str, len);
    r = refstr_alloc(len);
    if (r)
	memcpy(r, str, len);
    return r;
}

const char *refstrdup(const char *str)
{
    char *r;
    size_t len;

    if (!str)
	return NULL;

    len = strlen(str);
    r = refstr_alloc(len);
    if (r)
	memcpy(r, str, len);
    return r;
}

int vrsprintf(const char **bufp, const char *fmt, va_list ap)
{
    va_list ap1;
    int len;
    char *p;

    va_copy(ap1, ap);
    len = vsnprintf(NULL, 0, fmt, ap1);
    va_end(ap1);

    *bufp = p = refstr_alloc(len);
    if (!p)
	return -1;

    return vsnprintf(p, len + 1, fmt, ap);
}

int rsprintf(const char **bufp, const char *fmt, ...)
{
    int rv;
    va_list ap;

    va_start(ap, fmt);
    rv = vrsprintf(bufp, fmt, ap);
    va_end(ap);

    return rv;
}

void refstr_put(const char *r)
{
    unsigned int *ref;

    if (r) {
	ref = (unsigned int *)r - 1;

	if (!--*ref)
	    free(ref);
    }
}
