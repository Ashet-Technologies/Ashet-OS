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

/*
 * fmtpixel.c
 *
 * Functions to format a single pixel
 */

#include <inttypes.h>
#include "video.h"

/*
 * Format a sequence of pixels.  The first argument is the line buffer;
 * we can use it to write up to 4 bytes past the end of the last pixel.
 * Return the place we should be copying from, this is usually the
 * buffer address, but doesn't *have* to be.
 */

static const void *format_pxf_bgra32(void *ptr, const uint32_t * p, size_t n)
{
    (void)ptr;
    (void)n;
    return p;			/* No conversion needed! */
}

static const void *format_pxf_bgr24(void *ptr, const uint32_t * p, size_t n)
{
    char *q = ptr;

    while (n--) {
	*(uint32_t *) q = *p++;
	q += 3;
    }
    return ptr;
}

static const void *format_pxf_le_rgb16_565(void *ptr, const uint32_t * p,
					   size_t n)
{
    uint32_t bgra;
    uint16_t *q = ptr;

    while (n--) {
	bgra = *p++;
	*q++ =
	    ((bgra >> 3) & 0x1f) +
	    ((bgra >> (2 + 8 - 5)) & (0x3f << 5)) +
	    ((bgra >> (3 + 16 - 11)) & (0x1f << 11));
    }
    return ptr;
}

static const void *format_pxf_le_rgb15_555(void *ptr, const uint32_t * p,
					   size_t n)
{
    uint32_t bgra;
    uint16_t *q = ptr;

    while (n--) {
	bgra = *p++;
	*q++ =
	    ((bgra >> 3) & 0x1f) +
	    ((bgra >> (2 + 8 - 5)) & (0x1f << 5)) +
	    ((bgra >> (3 + 16 - 10)) & (0x1f << 10));
    }
    return ptr;
}

__vesacon_format_pixels_t __vesacon_format_pixels;

const __vesacon_format_pixels_t __vesacon_format_pixels_list[PXF_NONE] = {
    [PXF_BGRA32] = format_pxf_bgra32,
    [PXF_BGR24] = format_pxf_bgr24,
    [PXF_LE_RGB16_565] = format_pxf_le_rgb16_565,
    [PXF_LE_RGB15_555] = format_pxf_le_rgb15_555,
};
