/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2013 Intel Corporation; author: H. Peter Anvin
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

/*
 * argv.c
 *
 * Parse the MS-DOS command line into argc and argv (argc is return value.)
 * memptr points to available memory.
 */

#include <inttypes.h>
#include <stddef.h>
#include <stdbool.h>
#include "mystuff.h"

#define ALIGN_UP(p,t)       ((t *)(((uintptr_t)(p) + (sizeof(t)-1)) & ~(sizeof(t)-1)))

extern char __heap_start[];
void *__mem_end = &__heap_start;	/* Global variable for use by malloc() */

int __parse_argv(char ***argv)
{
    char *mem = __mem_end;
    const char *str, *p;
    char *q = mem;
    char c, *r;
    char **arg;
    bool wasspace;
    int argc;
    int len;
    size_t offs;
    int nulls;
    uint16_t nstr;

    /* Find and copy argv[0] after the environment block */
    set_fs(_PSP.environment);
    offs = 0;
    nulls = 0;
    do {
	if (get_8_fs(offs++) == '\0')
	    nulls++;
	else
	    nulls = 0;
    } while (nulls < 2);

    nstr = get_16_fs(offs);
    offs += 2;

    /* Copy the null-terminated filename string */
    if (nstr >= 1) {
	while ((c = get_8_fs(offs++)))
	    *q++ = c;
    }
    *q++ = '\0';

    /* Now for the command line tail... */

    len = _PSP.cmdlen;
    str = _PSP.cmdtail;
    argc = 1;
    wasspace = true;

    /* Copy the command tail, turning whitespace runs into nulls */
    for (p = str;; p++) {
	if (!len || *p <= ' ') {
	    if (!wasspace) {
		wasspace = true;
		*q++ = '\0';
	    }
	} else {
	    if (wasspace) {
		argc++;
		wasspace = false;
	    }
	    *q++ = *p;
	}

	/* This test is AFTER we have processed the end byte;
	   we treat it as a whitespace character so it terminates
	   the last argument */
	if (!len--)
	    break;
    }

    /* Now create argv */
    arg = ALIGN_UP(q, char *);
    *argv = arg;
    *arg++ = mem;		/* argv[0] */

    q--;			/* Point q to terminal character */
    for (r = mem; r < q; r++) {
	if (*r == '\0') {
	    *arg++ = r + 1;
	}
    }

    *arg++ = NULL;		/* Null pointer at the end */
    __mem_end = arg;		/* End of memory we used */

    return argc;
}
