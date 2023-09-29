/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2006-2008 H. Peter Anvin - All Rights Reserved
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

#ifndef LIB_SYS_VESA_FILL_H
#define LIB_SYS_VESA_FILL_H

#include "video.h"

/* Fill a number of characters. */
static inline struct vesa_char *vesacon_fill(struct vesa_char *ptr,
					     struct vesa_char fill,
					     unsigned int count)
{
    switch (sizeof(struct vesa_char)) {
    case 1:
	asm volatile ("rep; stosb":"+D" (ptr), "+c"(count)
		      :"a"(fill)
		      :"memory");
	break;
    case 2:
	asm volatile ("rep; stosw":"+D" (ptr), "+c"(count)
		      :"a"(fill)
		      :"memory");
	break;
    case 4:
	asm volatile ("rep; stosl":"+D" (ptr), "+c"(count)
		      :"a"(fill)
		      :"memory");
	break;
    default:
	while (count--)
	    *ptr++ = fill;
	break;
    }

    return ptr;
}

#endif /* LIB_SYS_VESA_FILL_H */
