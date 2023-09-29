/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
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
 * suffix_number.c
 *
 * Convert a string of a number with potential SI suffix to int-type
 */

#include <stdlib.h>
#include <suffix_number.h>

/* Get a value with a potential suffix (k/m/g/t/p/e) */
unsigned long long suffix_number(const char *str)
{
    char *ep;
    unsigned long long v;
    int shift;

    v = strtoull(str, &ep, 0);
    switch (*ep | 0x20) {
    case 'k':
	shift = 10;
	break;
    case 'm':
	shift = 20;
	break;
    case 'g':
	shift = 30;
	break;
    case 't':
	shift = 40;
	break;
    case 'p':
	shift = 50;
	break;
    case 'e':
	shift = 60;
	break;
    default:
	shift = 0;
	break;
    }
    v <<= shift;

    return v;
}
