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
 * unbase64.c
 *
 * Convert a string in base64 format to a byte array.
 */

#include <string.h>
#include <base64.h>

static const unsigned char _base64chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

size_t unbase64(unsigned char *buffer, size_t bufsiz, const char *txt)
{
    unsigned int bits = 0;
    int nbits = 0;
    char base64tbl[256];
    int i;
    char v;
    size_t nbytes = 0;

    memset(base64tbl, -1, sizeof base64tbl);

    for (i = 0; _base64chars[i]; i++) {
	base64tbl[_base64chars[i]] = i;
    }

    /* Also support filesystem safe alternate base64 encoding */
    base64tbl['.'] = 62;
    base64tbl['-'] = 62;
    base64tbl['_'] = 63;

    while (*txt) {
	if ((v = base64tbl[(unsigned char)*txt]) >= 0) {
	    bits <<= 6;
	    bits += v;
	    nbits += 6;
	    if (nbits >= 8) {
		if (nbytes < bufsiz)
		    *buffer++ = (bits >> (nbits - 8));
		nbytes++;
		nbits -= 8;
	    }
	}
	txt++;
    }

    return nbytes;
}
