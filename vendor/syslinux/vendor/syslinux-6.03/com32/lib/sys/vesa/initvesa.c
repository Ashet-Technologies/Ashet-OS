/* ----------------------------------------------------------------------- *
 *
 *   Copyright 1999-2008 H. Peter Anvin - All Rights Reserved
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
 * initvesa.c
 *
 * Query the VESA BIOS and select a 640x480x32 mode with local mapping
 * support, if one exists.
 */

#include <inttypes.h>
#include <com32.h>
#include <stdlib.h>
#include <string.h>
#include <sys/fpu.h>
#include <syslinux/video.h>
#include "vesa.h"
#include "video.h"
#include "fill.h"
#include "debug.h"

struct vesa_info __vesa_info;

struct vesa_char *__vesacon_text_display;

int __vesacon_font_height;
int __vesacon_text_rows;
int __vesacon_text_cols;
enum vesa_pixel_format __vesacon_pixel_format = PXF_NONE;
unsigned int __vesacon_bytes_per_pixel;
uint8_t __vesacon_graphics_font[FONT_MAX_CHARS][FONT_MAX_HEIGHT];

uint32_t *__vesacon_background, *__vesacon_shadowfb;

static void unpack_font(uint8_t * dst, uint8_t * src, int height)
{
    int i;

    for (i = 0; i < FONT_MAX_CHARS; i++) {
	memcpy(dst, src, height);
	memset(dst + height, 0, FONT_MAX_HEIGHT - height);

	dst += FONT_MAX_HEIGHT;
	src += height;
    }
}

static int vesacon_set_mode(int *x, int *y)
{
    uint8_t *rom_font;
    struct vesa_mode_info *mi;
    enum vesa_pixel_format bestpxf;
    int rv;

    debug("Hello, World!\r\n");

    /* Free any existing data structures */
    if (__vesacon_background) {
	free(__vesacon_background);
	__vesacon_background = NULL;
    }
    if (__vesacon_shadowfb) {
	free(__vesacon_shadowfb);
	__vesacon_shadowfb = NULL;
    }

    rv = firmware->vesa->set_mode(&__vesa_info, x, y, &bestpxf);
    if (rv)
	return rv;

    mi = &__vesa_info.mi;
    __vesacon_bytes_per_pixel = (mi->bpp + 7) >> 3;
    __vesacon_format_pixels = __vesacon_format_pixels_list[bestpxf];

    /* Download the SYSLINUX- or firmware-provided font */
    __vesacon_font_height = syslinux_font_query(&rom_font);
    if (!__vesacon_font_height)
	__vesacon_font_height = firmware->vesa->font_query(&rom_font);

    unpack_font((uint8_t *) __vesacon_graphics_font, rom_font,
		__vesacon_font_height);

    __vesacon_background = calloc(mi->h_res*mi->v_res, 4);
    __vesacon_shadowfb = calloc(mi->h_res*mi->v_res, 4);

    __vesacon_init_copy_to_screen();

    /* Tell syslinux we changed video mode */
    /* In theory this should be:

       flags = (mi->mode_attr & 4) ? 0x0007 : 0x000f;

       However, that would assume all systems that claim to handle text
       output in VESA modes actually do that... */
    syslinux_report_video_mode(0x000f, mi->h_res, mi->v_res);

    __vesacon_pixel_format = bestpxf;

    return 0;
}

/* FIXME:
 * Does init_text_display need an EFI counterpart?
 * e.g. vesa_char may need to setup UNICODE char for EFI
 * and the number of screen chars may need to be sized up
 * accordingly. This may also require turning byte strings
 * into unicode strings in the framebuffer
 * Possibly, revisit vesacon_fill() for EFI.
 */
static int init_text_display(void)
{
    size_t nchars;
    struct vesa_char *ptr;
    struct vesa_char def_char = {
	.ch = ' ',
	.attr = 0,
    };

    if (__vesacon_text_display)
	free(__vesacon_text_display);

    __vesacon_text_cols = TEXT_PIXEL_COLS / FONT_WIDTH;
    __vesacon_text_rows = TEXT_PIXEL_ROWS / __vesacon_font_height;
    nchars = (__vesacon_text_cols+2) * (__vesacon_text_rows+2);

    __vesacon_text_display = ptr = malloc(nchars * sizeof(struct vesa_char));

    if (!ptr)
	return -1;

    vesacon_fill(ptr, def_char, nchars);
    __vesacon_init_cursor(__vesacon_font_height);

    return 0;
}

/*
 * On input, VESA initialization is passed a desirable resolution. On
 * return, either the requested resolution is set or the system
 * supported default resolution is set and returned to the caller.
 */
int __vesacon_init(int *x, int *y)
{
    int rv;

    /* We need the FPU for graphics, at least libpng et al will need it... */
    if (x86_init_fpu())
	return 10;

    rv = vesacon_set_mode(x, y);
    if (rv) {
	/* Try to see if we can just patch the BIOS... */
	if (__vesacon_i915resolution(*x, *y))
	    return rv;
	if (vesacon_set_mode(x, y))
	    return rv;
    }

    init_text_display();

    debug("Mode set, now drawing at %#p\r\n", __vesa_info.mi.lfb_ptr);

    __vesacon_init_background();

    debug("Ready!\r\n");
    return 0;
}
