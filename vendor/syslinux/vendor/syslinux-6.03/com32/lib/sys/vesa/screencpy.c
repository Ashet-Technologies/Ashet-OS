/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 H. Peter Anvin - All Rights Reserved
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

#include <inttypes.h>
#include <minmax.h>
#include <klibc/compiler.h>
#include <string.h>
#include <com32.h>
#include <ilog2.h>
#include "vesa.h"
#include "video.h"


static struct win_info wi;

void __vesacon_init_copy_to_screen(void)
{
    struct vesa_mode_info *const mi = &__vesa_info.mi;
    int winn;

    if (mi->mode_attr & 0x0080) {
	/* Linear frame buffer */

	wi.win_base = (char *)mi->lfb_ptr;
	wi.win_size = 1 << 31;	/* 2 GB, i.e. one huge window */
	wi.win_pos = 0;		/* Already positioned (only one position...) */
	wi.win_num = -1;	/* Not a window */
    } else {
	/* Paged frame buffer */

	/* We have already tested that *one* of these is usable */
	if ((mi->win_attr[0] & 0x05) == 0x05 && mi->win_seg[0])
	    winn = 0;
	else
	    winn = 1;

	wi.win_num = winn;
	wi.win_base = (char *)(mi->win_seg[winn] << 4);
	wi.win_size = mi->win_size << 10;
	wi.win_gshift = ilog2(mi->win_grain) + 10;
	wi.win_pos = -1;	/* Undefined position */
    }
}

void __vesacon_copy_to_screen(size_t dst, const uint32_t * src, size_t npixels)
{
    size_t bytes = npixels * __vesacon_bytes_per_pixel;
    char rowbuf[bytes + 4] __aligned(4);
    const uint32_t *s;

    s = (const uint32_t *)__vesacon_format_pixels(rowbuf, src, npixels);
    firmware->vesa->screencpy(dst, s, bytes, &wi);
}
