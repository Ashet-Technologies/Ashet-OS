/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2005-2008 H. Peter Anvin - All Rights Reserved
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
 * base64.h
 *
 * Simple routines for handing base64 text
 */

#ifndef LIBUTIL_BASE64_H
#define LIBUTIL_BASE64_H

#include <stddef.h>

#define BASE64_PAD	0x10000

/* There is plenty of disagreement w.r.t. the last few characters... */
#define BASE64_MIME	('+' + ('/' << 8))
#define BASE64_SAFE	('-' + ('_' << 8))
#define BASE64_CRYPT	('.' + ('/' << 8))
#define BASE64_URL	('*' + ('-' << 8))	/* Haven't seen myself */
#define BASE64_REGEX	('|' + ('-' << 8))	/* Ditto... */

size_t genbase64(char *output, const void *digest, size_t size, int flags);
size_t unbase64(unsigned char *, size_t, const char *);

#endif
