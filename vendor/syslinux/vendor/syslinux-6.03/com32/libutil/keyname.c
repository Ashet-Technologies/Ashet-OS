/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Intel Corporation; author: H. Peter Anvin
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
 * keyname.c
 *
 * Conversion between strings and get_key() key numbers.
 */

#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>
#include <sys/times.h>
#include <getkey.h>
#include <libutil.h>

struct keyname {
    const char *string;
    int key;
};

static const struct keyname key_names[] = {
    { "Backspace", KEY_BACKSPACE },
    { "Tab", KEY_TAB },
    { "Enter", KEY_ENTER },
    { "Esc", KEY_ESC },
    { "Escape", KEY_ESC },
    { "Space", ' ' },
    { "^?", KEY_DEL },
    { "F1", KEY_F1 },
    { "F2", KEY_F2},
    { "F3", KEY_F3 },
    { "F4", KEY_F4 },
    { "F5", KEY_F5 },
    { "F6", KEY_F6 },
    { "F7", KEY_F7 },
    { "F8", KEY_F8 },
    { "F9", KEY_F9 },
    { "F10", KEY_F10 },
    { "F11", KEY_F11 },
    { "F12", KEY_F12 },
    { "Up", KEY_UP },
    { "Down", KEY_DOWN },
    { "Left", KEY_LEFT },
    { "Right", KEY_RIGHT },
    { "PgUp", KEY_PGUP },
    { "PgDn", KEY_PGDN },
    { "Home", KEY_HOME },
    { "End", KEY_END },
    { "Insert", KEY_INSERT },
    { "Delete", KEY_DELETE },
    { NULL, KEY_NONE }
};

int key_name_to_code(const char *code)
{
    const struct keyname *name;

    if (code[0] && !code[1]) {
	/* Single character */
	return (unsigned char)code[0];
    } else if (code[0] == '^' && code[1] && !code[2]) {
	/* Control character */
	if (code[1] == '?')
	    return 0x7f;
	else
	    return (unsigned char)code[1] & 0x9f;
    }


    for (name = key_names; name->string; name++) {
	if (!strcasecmp(name->string, code))
	    break;
    }
    return name->key;	/* KEY_NONE at end of array */
}

const char *key_code_to_name(int key)
{
    static char buf[4];
    const struct keyname *name;

    if (key < 0)
	return NULL;

    if (key > ' ' && key < 0x100) {
	if (key & 0x60) {
	    buf[0] = key;
	    buf[1] = '\0';
	} else {
	    buf[0] = '^';
	    buf[1] = key | 0x40;
	    buf[2] = '\0';
	}
	return buf;
    }

    for (name = key_names; name->string; name++) {
	if (key == name->key)
	    return name->string;
    }

    if (key < ' ') {
	buf[0] = '^';
	buf[1] = key | 0x40;
	buf[2] = '\0';
	return buf;
    }

    return NULL;
}
