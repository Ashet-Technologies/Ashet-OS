/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
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
 * getkey.h
 *
 * Function to get a key symbol and parse it
 */

#ifndef LIBUTIL_GETKEY_H
#define LIBUTIL_GETKEY_H

#include <stdio.h>
#include <unistd.h>
#include <sys/times.h>

#ifndef CLK_TCK
# define CLK_TCK sysconf(_SC_CLK_TCK)
#endif

#define KEY_NONE	(-1)

#define KEY_CTRL(x)	((x) & 0x001f)
#define KEY_BACKSPACE	0x0008
#define KEY_TAB		0x0009
#define KEY_ENTER	0x000d
#define KEY_ESC		0x001b
#define KEY_DEL		0x007f

#define KEY_F1		0x0100
#define KEY_F2		0x0101
#define KEY_F3		0x0102
#define KEY_F4		0x0103
#define KEY_F5		0x0104
#define KEY_F6		0x0105
#define KEY_F7		0x0106
#define KEY_F8		0x0107
#define KEY_F9		0x0108
#define KEY_F10		0x0109
#define KEY_F11		0x010A
#define KEY_F12		0x010B

#define KEY_UP		0x0120
#define KEY_DOWN	0x0121
#define KEY_LEFT	0x0122
#define KEY_RIGHT	0x0123
#define KEY_PGUP	0x0124
#define KEY_PGDN	0x0125
#define KEY_HOME	0x0126
#define KEY_END		0x0127
#define KEY_INSERT	0x0128
#define KEY_DELETE	0x0129

#define KEY_MAX		0x012a

#define KEY_MAXLEN	8

int get_key(FILE *, clock_t);
int key_name_to_code(const char *);
const char *key_code_to_name(int);
int get_key_decode(char *, int, int *);

#endif /* LIBUTIL_GETKEY_H */
