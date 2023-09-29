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

#include <inttypes.h>
#include <colortbl.h>
#include <string.h>
#include "vesa.h"
#include "video.h"
#include "fill.h"

/*
 * Visible cursor information
 */
static uint8_t cursor_pattern[FONT_MAX_HEIGHT];
static struct vesa_char *cursor_pointer = NULL;
static int cursor_x, cursor_y;

static inline void *copy_dword(void *dst, void *src, size_t dword_count)
{
    asm volatile ("rep; movsl":"+D" (dst), "+S"(src), "+c"(dword_count));
    return dst;			/* Updated destination pointer */
}

static inline __attribute__ ((always_inline))
uint8_t alpha_val(uint8_t fg, uint8_t bg, uint8_t alpha)
{
    unsigned int tmp;

    tmp = __vesacon_srgb_to_linear[fg] * alpha;
    tmp += __vesacon_srgb_to_linear[bg] * (255 - alpha);

    return __vesacon_linear_to_srgb[tmp >> 12];
}

static uint32_t alpha_pixel(uint32_t fg, uint32_t bg)
{
    uint8_t alpha = fg >> 24;
    uint8_t fg_r = fg >> 16;
    uint8_t fg_g = fg >> 8;
    uint8_t fg_b = fg;
    uint8_t bg_r = bg >> 16;
    uint8_t bg_g = bg >> 8;
    uint8_t bg_b = bg;

    return
	(alpha_val(fg_r, bg_r, alpha) << 16) |
	(alpha_val(fg_g, bg_g, alpha) << 8) | (alpha_val(fg_b, bg_b, alpha));
}

static void vesacon_update_characters(int row, int col, int nrows, int ncols)
{
    const int height = __vesacon_font_height;
    const int width = FONT_WIDTH;
    uint32_t *bgrowptr, *bgptr, bgval, fgval;
    uint32_t fgcolor = 0, bgcolor = 0, color;
    uint8_t chbits = 0, chxbits = 0, chsbits = 0;
    int i, j, jx, pixrow, pixsrow;
    struct vesa_char *rowptr, *rowsptr, *cptr, *csptr;
    unsigned int bytes_per_pixel = __vesacon_bytes_per_pixel;
    unsigned long pixel_offset;
    uint32_t row_buffer[__vesa_info.mi.h_res], *rowbufptr;
    size_t fbrowptr;
    uint8_t sha;

    pixel_offset = ((row * height + VIDEO_BORDER) * __vesa_info.mi.h_res) +
	(col * width + VIDEO_BORDER);

    bgrowptr = &__vesacon_background[pixel_offset];
    fbrowptr = (row * height + VIDEO_BORDER) * __vesa_info.mi.logical_scan +
	(col * width + VIDEO_BORDER) * bytes_per_pixel;

    /* Note that we keep a 1-character guard area around the real text area... */
    rowptr = &__vesacon_text_display[(row+1)*(__vesacon_text_cols+2)+(col+1)];
    rowsptr = rowptr - ((__vesacon_text_cols+2)+1);
    pixrow = 0;
    pixsrow = height - 1;

    for (i = height * nrows; i >= 0; i--) {
	bgptr = bgrowptr;
	rowbufptr = row_buffer;

	cptr = rowptr;
	csptr = rowsptr;

	chsbits = __vesacon_graphics_font[csptr->ch][pixsrow];
	if (__unlikely(csptr == cursor_pointer))
	    chsbits |= cursor_pattern[pixsrow];
	sha = console_color_table[csptr->attr].shadow;
	chsbits &= (sha & 0x02) ? 0xff : 0x00;
	chsbits ^= (sha & 0x01) ? 0xff : 0x00;
	chsbits <<= (width - 2);
	csptr++;

	/* Draw two pixels beyond the end of the line.  One for the shadow,
	   and one to make sure we have a whole dword of data for the copy
	   operation at the end.  Note that this code depends on the fact that
	   all characters begin on dword boundaries in the frame buffer. */

	for (jx = 1, j = width * ncols + 1; j >= 0; j--) {
	    chbits <<= 1;
	    chsbits <<= 1;
	    chxbits <<= 1;

	    switch (jx) {
	    case 1:
		chbits = __vesacon_graphics_font[cptr->ch][pixrow];
		if (__unlikely(cptr == cursor_pointer))
		    chbits |= cursor_pattern[pixrow];
		sha = console_color_table[cptr->attr].shadow;
		chxbits = chbits;
		chxbits &= (sha & 0x02) ? 0xff : 0x00;
		chxbits ^= (sha & 0x01) ? 0xff : 0x00;
		fgcolor = console_color_table[cptr->attr].argb_fg;
		bgcolor = console_color_table[cptr->attr].argb_bg;
		cptr++;
		jx--;
		break;
	    case 0:
		chsbits = __vesacon_graphics_font[csptr->ch][pixsrow];
		if (__unlikely(csptr == cursor_pointer))
		    chsbits |= cursor_pattern[pixsrow];
		sha = console_color_table[csptr->attr].shadow;
		chsbits &= (sha & 0x02) ? 0xff : 0x00;
		chsbits ^= (sha & 0x01) ? 0xff : 0x00;
		csptr++;
		jx = width - 1;
		break;
	    default:
		jx--;
		break;
	    }

	    /* If this pixel is raised, use the offsetted value */
	    bgval = (chxbits & 0x80)
		? bgptr[__vesa_info.mi.h_res + 1] : *bgptr;
	    bgptr++;

	    /* If this pixel is set, use the fg color, else the bg color */
	    fgval = (chbits & 0x80) ? fgcolor : bgcolor;

	    /* Produce the combined color pixel value */
	    color = alpha_pixel(fgval, bgval);

	    /* Apply the shadow (75% shadow) */
	    if ((chsbits & ~chxbits) & 0x80) {
		color >>= 2;
		color &= 0x3f3f3f;
	    }

	    *rowbufptr++ = color;
	}

	/* Copy to frame buffer */
	__vesacon_copy_to_screen(fbrowptr, row_buffer, rowbufptr - row_buffer);

	bgrowptr += __vesa_info.mi.h_res;
	fbrowptr += __vesa_info.mi.logical_scan;

	if (++pixrow == height) {
	    rowptr += __vesacon_text_cols + 2;
	    pixrow = 0;
	}
	if (++pixsrow == height) {
	    rowsptr += __vesacon_text_cols + 2;
	    pixsrow = 0;
	}
    }
}

/* Bounding box for changed text.  The (x1, y1) coordinates are +1! */
static unsigned int upd_x0 = -1U, upd_x1, upd_y0 = -1U, upd_y1;

/* Update the range already touched by various variables */
void __vesacon_doit(void)
{
    if (upd_x1 > upd_x0 && upd_y1 > upd_y0) {
	vesacon_update_characters(upd_y0, upd_x0, upd_y1 - upd_y0,
				  upd_x1 - upd_x0);
	upd_x0 = upd_y0 = -1U;
	upd_x1 = upd_y1 = 0;
    }
}

/* Mark a range for update; note argument sequence is the same as
   vesacon_update_characters() */
static inline void vesacon_touch(int row, int col, int rows, int cols)
{
    unsigned int y0 = row;
    unsigned int x0 = col;
    unsigned int y1 = y0 + rows;
    unsigned int x1 = x0 + cols;

    if (y0 < upd_y0)
	upd_y0 = y0;
    if (y1 > upd_y1)
	upd_y1 = y1;
    if (x0 < upd_x0)
	upd_x0 = x0;
    if (x1 > upd_x1)
	upd_x1 = x1;
}

/* Erase a region of the screen */
void __vesacon_erase(int x0, int y0, int x1, int y1, attr_t attr)
{
    int y;
    struct vesa_char *ptr = &__vesacon_text_display
	[(y0 + 1) * (__vesacon_text_cols + 2) + (x0 + 1)];
    struct vesa_char fill = {
	.ch = ' ',
	.attr = attr,
    };
    int ncols = x1 - x0 + 1;

    for (y = y0; y <= y1; y++) {
	vesacon_fill(ptr, fill, ncols);
	ptr += __vesacon_text_cols + 2;
    }

    vesacon_touch(y0, x0, y1 - y0 + 1, ncols);
}

/* Scroll the screen up */
void __vesacon_scroll_up(int nrows, attr_t attr)
{
    struct vesa_char *fromptr = &__vesacon_text_display
	[(nrows + 1) * (__vesacon_text_cols + 2)];
    struct vesa_char *toptr = &__vesacon_text_display
	[(__vesacon_text_cols + 2)];
    int dword_count =
	(__vesacon_text_rows - nrows) * (__vesacon_text_cols + 2);
    struct vesa_char fill = {
	.ch = ' ',
	.attr = attr,
    };

    toptr = copy_dword(toptr, fromptr, dword_count);

    dword_count = nrows * (__vesacon_text_cols + 2);

    vesacon_fill(toptr, fill, dword_count);

    vesacon_touch(0, 0, __vesacon_text_rows, __vesacon_text_cols);
}

/* Draw one character text at a specific area of the screen */
void __vesacon_write_char(int x, int y, uint8_t ch, attr_t attr)
{
    struct vesa_char *ptr = &__vesacon_text_display
	[(y + 1) * (__vesacon_text_cols + 2) + (x + 1)];

    ptr->ch = ch;
    ptr->attr = attr;

    vesacon_touch(y, x, 1, 1);
}

void __vesacon_set_cursor(int x, int y, bool visible)
{
    struct vesa_char *ptr = &__vesacon_text_display
	[(y + 1) * (__vesacon_text_cols + 2) + (x + 1)];

    if (cursor_pointer)
	vesacon_touch(cursor_y, cursor_x, 1, 1);

    if (!visible) {
	/* Invisible cursor */
	cursor_pointer = NULL;
    } else {
	cursor_pointer = ptr;
	vesacon_touch(y, x, 1, 1);
    }

    cursor_x = x;
    cursor_y = y;
}

void __vesacon_init_cursor(int font_height)
{
    int r0 = font_height - (font_height < 10 ? 2 : 3);

    if (r0 < 0)
	r0 = 0;

    memset(cursor_pattern, 0, font_height);
    cursor_pattern[r0] = 0xff;
    cursor_pattern[r0 + 1] = 0xff;
}

void __vesacon_redraw_text(void)
{
    vesacon_update_characters(0, 0, __vesacon_text_rows, __vesacon_text_cols);
}
