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
 * ansicon_write.c
 *
 * Write to the screen using ANSI control codes (about as capable as
 * DOS' ANSI.SYS.)
 */

#include <errno.h>
#include <string.h>
#include <minmax.h>
#include <colortbl.h>
#include <klibc/compiler.h>
#include <syslinux/config.h>
#include "file.h"
#include "ansi.h"
#include <syslinux/firmware.h>
#include "graphics.h"

static void ansicon_erase(const struct term_state *, int, int, int, int);
static void ansicon_write_char(int, int, uint8_t, const struct term_state *);
static void ansicon_showcursor(const struct term_state *);
static void ansicon_scroll_up(const struct term_state *);
static void ansicon_set_cursor(int, int, bool);

static struct term_state ts;
struct ansi_ops __ansicon_ops = {
    .erase = ansicon_erase,
    .write_char = ansicon_write_char,
    .showcursor = ansicon_showcursor,
    .set_cursor = ansicon_set_cursor,
    .scroll_up = ansicon_scroll_up,
    .beep = __ansicon_beep,
};

static struct term_info ti = {
    .disabled = 0,
    .ts = &ts,
    .op = &__ansicon_ops
};

#define TEXT_MODE 0x0005

/* Reference counter to the screen, to keep track of if we need
   reinitialization. */
static int ansicon_counter = 0;

/* Common setup */
int __ansicon_open(struct file_info *fp)
{
    if (!ansicon_counter) {
	/* Are we disabled? */
	if (syslinux_serial_console_info()->flowctl & 0x8000) {
	    ti.disabled = 1;
	    ti.rows = 25;
	    ti.cols = 80;
	} else {
	    /* Force text mode */
	    firmware->o_ops->text_mode();

	    /* Initial state */
	    firmware->o_ops->get_mode(&ti.cols, &ti.rows);
	    __ansi_init(&ti);

	    /* Get cursor shape and position */
	    firmware->o_ops->get_cursor(&ti.ts->xy.x, &ti.ts->xy.y);
	}
    }

    fp->o.rows = ti.rows;
    fp->o.cols = ti.cols;

    ansicon_counter++;
    return 0;
}

int __ansicon_close(struct file_info *fp)
{
    (void)fp;

    ansicon_counter--;
    return 0;
}

/* Turn ANSI attributes into VGA attributes */
static uint8_t ansicon_attribute(const struct term_state *st)
{
    int bg = st->bg;
    int fg;

    if (st->underline)
	fg = 0x01;
    else if (st->intensity == 0)
	fg = 0x08;
    else
	fg = st->fg;

    if (st->reverse) {
	bg = fg & 0x07;
	fg &= 0x08;
	fg |= st->bg;
    }

    if (st->blink)
	bg ^= 0x08;

    if (st->intensity == 2)
	fg ^= 0x08;

    return (bg << 4) | fg;
}

/* Erase a region of the screen */
static void ansicon_erase(const struct term_state *st,
			  int x0, int y0, int x1, int y1)
{
    uint8_t attribute = ansicon_attribute(st);

    if (firmware->o_ops->erase)
	firmware->o_ops->erase(x0, y0, x1, y1, attribute);
}

/* Show or hide the cursor */
static void ansicon_showcursor(const struct term_state *st)
{
    firmware->o_ops->showcursor(st);
}

static void ansicon_set_cursor(int x, int y, bool visible)
{
    firmware->o_ops->set_cursor(x, y, visible);
}

static void ansicon_write_char(int x, int y, uint8_t ch,
			       const struct term_state *st)
{
    uint8_t attribute = ansicon_attribute(st);
    ansicon_set_cursor(x, y, false);

    firmware->o_ops->write_char(ch, attribute);
}

static void ansicon_scroll_up(const struct term_state *st)
{
    uint8_t rows, cols, attribute;

    cols = ti.cols - 1;
    rows = ti.rows - 1;
    attribute = ansicon_attribute(st);

    firmware->o_ops->scroll_up(cols, rows, attribute);
}

ssize_t __ansicon_write(struct file_info *fp, const void *buf, size_t count)
{
    const unsigned char *bufp = buf;
    size_t n = 0;

    (void)fp;

    if (ti.disabled)
	return count;		/* Nothing to do */

    while (count--) {
	__ansi_putchar(&ti, *bufp++);
	n++;
    }

    return n;
}

void __ansicon_beep(void)
{
    if (firmware->o_ops->beep)
	firmware->o_ops->beep();
}

const struct output_dev dev_ansicon_w = {
    .dev_magic = __DEV_MAGIC,
    .flags = __DEV_TTY | __DEV_OUTPUT,
    .fileflags = O_WRONLY | O_CREAT | O_TRUNC | O_APPEND,
    .write = __ansicon_write,
    .close = __ansicon_close,
    .open = __ansicon_open,
};
