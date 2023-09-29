/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2009 H. Peter Anvin - All Rights Reserved
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
 * vesacon_write.c
 *
 * Write to the screen using ANSI control codes (about as capable as
 * DOS' ANSI.SYS.)
 */

#include <errno.h>
#include <string.h>
#include <com32.h>
#include <minmax.h>
#include <colortbl.h>
#include <console.h>
#include <klibc/compiler.h>
#include <syslinux/config.h>
#include "ansi.h"
#include "file.h"
#include "vesa/video.h"

static void vesacon_erase(const struct term_state *, int, int, int, int);
static void vesacon_write_char(int, int, uint8_t, const struct term_state *);
static void vesacon_showcursor(const struct term_state *);
static void vesacon_setcursor(int x, int y, bool visible);
static void vesacon_scroll_up(const struct term_state *);

static struct term_state ts;
static struct ansi_ops op = {
    .erase = vesacon_erase,
    .write_char = vesacon_write_char,
    .showcursor = vesacon_showcursor,
    .set_cursor = vesacon_setcursor,
    .scroll_up = vesacon_scroll_up,
    .beep = __ansicon_beep,
};

static struct term_info ti = {
    .disabled = 0,
    .ts = &ts,
    .op = &op
};

/* Reference counter to the screen, to keep track of if we need
   reinitialization. */
static int vesacon_counter = 0;

static struct {
    int x, y;
} vesacon_resolution = {
    .x = DEFAULT_VESA_X_SIZE,
    .y = DEFAULT_VESA_Y_SIZE,
};

/* Set desired resolution - requires a full close/open cycle */
void vesacon_set_resolution(int x, int y)
{
    vesacon_resolution.x = x;
    vesacon_resolution.y = y;
}

/* Common setup */
int __vesacon_open(struct file_info *fp)
{
    (void)fp;

    if (!vesacon_counter) {
	/* Are we disabled? */
	if (syslinux_serial_console_info()->flowctl & 0x8000) {
	    ti.disabled = 1;
	    ti.rows = 25;
	    ti.cols = 80;
	} else {
	    /* Switch mode */
	    /* Deal with a resolution different from default build */
	    if (__vesacon_init(&vesacon_resolution.x, &vesacon_resolution.y)) {
		vesacon_counter = -1;
		return EAGAIN;
	    }

	    /* Initial state */
	    __ansi_init(&ti);
	    ti.rows = __vesacon_text_rows;
	    ti.cols = __vesacon_text_cols;
	}
    } else if (vesacon_counter == -1) {
	return EAGAIN;
    }

    fp->o.rows = ti.rows;
    fp->o.cols = ti.cols;

    vesacon_counter++;
    return 0;
}

int __vesacon_close(struct file_info *fp)
{
    (void)fp;

    vesacon_counter--;
    return 0;
}

/* Erase a region of the screen */
static void vesacon_erase(const struct term_state *st,
			  int x0, int y0, int x1, int y1)
{
    __vesacon_erase(x0, y0, x1, y1, st->cindex);
}

/* Draw text on the screen */
static void vesacon_write_char(int x, int y, uint8_t ch,
			       const struct term_state *st)
{
    __vesacon_write_char(x, y, ch, st->cindex);
}

/* Show or hide the cursor */
static bool cursor_enabled = true;
void vesacon_cursor_enable(bool enabled)
{
    cursor_enabled = enabled;
}
static void vesacon_showcursor(const struct term_state *st)
{
    vesacon_setcursor(st->xy.x, st->xy.y, st->cursor);
}
static void vesacon_setcursor(int x, int y, bool visible)
{
    __vesacon_set_cursor(x, y, visible && cursor_enabled);
}

static void vesacon_scroll_up(const struct term_state *st)
{
    __vesacon_scroll_up(1, st->cindex);
}

ssize_t __vesacon_write(struct file_info *fp, const void *buf, size_t count)
{
    const unsigned char *bufp = buf;
    size_t n = 0;

    (void)fp;

    if (ti.disabled)
	return count;		/* Nothing to do */

    /* This only updates the shadow text buffer... */
    while (count--) {
	__ansi_putchar(&ti, *bufp++);
	n++;
    }

    /* This actually draws it */
    __vesacon_doit();

    return n;
}

const struct output_dev dev_vesacon_w = {
    .dev_magic = __DEV_MAGIC,
    .flags = __DEV_TTY | __DEV_OUTPUT,
    .fileflags = O_WRONLY | O_CREAT | O_TRUNC | O_APPEND,
    .write = __vesacon_write,
    .close = __vesacon_close,
    .open = __vesacon_open,
    .fallback = &dev_ansicon_w,
};
