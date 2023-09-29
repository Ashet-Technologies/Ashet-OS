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

#ifndef LIB_SYS_VESA_VIDEO_H
#define LIB_SYS_VESA_VIDEO_H

#include <stdbool.h>
#include <colortbl.h>
#include "vesa.h"

#define FONT_MAX_CHARS	256
#define FONT_MAX_HEIGHT	 32
#define FONT_WIDTH	  8

#define DEFAULT_VESA_X_SIZE	640
#define DEFAULT_VESA_Y_SIZE	480

#define VIDEO_BORDER	8
#define TEXT_PIXEL_ROWS (__vesa_info.mi.v_res - 2*VIDEO_BORDER)
#define TEXT_PIXEL_COLS (__vesa_info.mi.h_res - 2*VIDEO_BORDER)

typedef uint16_t attr_t;

struct vesa_char {
    uint8_t ch;			/* Character */
    uint8_t _filler;		/* Currently unused */
    attr_t attr;		/* Color table index */
};

struct win_info {
    char *win_base;
    size_t win_pos;
    size_t win_size;
    int win_gshift;
    int win_num;
};

/* Pixel formats in order of decreasing preference; PXF_NONE should be last */
/* BGR24 is preferred over BGRA32 since the I/O overhead is smaller. */
enum vesa_pixel_format {
    PXF_BGR24,			/* 24-bit BGR */
    PXF_BGRA32,			/* 32-bit BGRA */
    PXF_LE_RGB16_565,		/* 16-bit littleendian 5:6:5 RGB */
    PXF_LE_RGB15_555,		/* 15-bit littleendian 5:5:5 RGB */
    PXF_NONE
};
extern enum vesa_pixel_format __vesacon_pixel_format;
extern unsigned int __vesacon_bytes_per_pixel;
typedef const void *(*__vesacon_format_pixels_t)
    (void *, const uint32_t *, size_t);
extern __vesacon_format_pixels_t __vesacon_format_pixels;
extern const __vesacon_format_pixels_t __vesacon_format_pixels_list[PXF_NONE];

extern struct vesa_char *__vesacon_text_display;

extern int __vesacon_font_height;
extern int __vesacon_text_rows;
extern int __vesacon_text_cols;
extern uint8_t __vesacon_graphics_font[FONT_MAX_CHARS][FONT_MAX_HEIGHT];
extern uint32_t *__vesacon_background;
extern uint32_t *__vesacon_shadowfb;

extern const uint16_t __vesacon_srgb_to_linear[256];
extern const uint8_t __vesacon_linear_to_srgb[4080];

int __vesacon_init_background(void);
int vesacon_load_background(const char *);
int __vesacon_init(int *, int *);
void __vesacon_init_cursor(int);
void __vesacon_erase(int, int, int, int, attr_t);
void __vesacon_scroll_up(int, attr_t);
void __vesacon_write_char(int, int, uint8_t, attr_t);
void __vesacon_redraw_text(void);
void __vesacon_doit(void);
void __vesacon_set_cursor(int, int, bool);
void __vesacon_copy_to_screen(size_t, const uint32_t *, size_t);
void __vesacon_init_copy_to_screen(void);

int __vesacon_i915resolution(int x, int y);

#endif /* LIB_SYS_VESA_VIDEO_H */
