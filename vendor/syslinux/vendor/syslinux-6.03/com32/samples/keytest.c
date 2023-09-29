/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * keytest.c
 *
 * Test the key parsing library
 */

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/times.h>

#include <consoles.h>		/* Provided by libutil */
#include <getkey.h>

static void cooked_keys(void)
{
    int key;

    printf("[cooked]");

    for (;;) {
	key = get_key(stdin, 0);

	if (key == 0x03) {
	    printf("[done]\n");
	    exit(0);
	} else if (key == '!')
	    return;

	if (key >= 0x20 && key < 0x100) {
	    putchar(key);
	} else {
	    printf("[%s,%04x]", key_code_to_name(key), key);
	}
    }
}

static void raw_keys(void)
{
    int key;

    printf("[raw]");

    for (;;) {
	key = getc(stdin);

	if (key == 0x03) {
	    printf("[done]\n");
	    exit(0);
	} else if (key == '!')
	    return;

	if (key != EOF)
	    printf("<%02x>", key);
    }
}

int main(void)
{
    console_ansi_raw();

    printf("CLK_TCK = %d\n", (int)CLK_TCK);
    printf("Press keys, end with Ctrl-C, ! changes from cooked to raw\n");

    for (;;) {
	cooked_keys();
	raw_keys();
    }
}
