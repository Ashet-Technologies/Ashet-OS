/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010 Gene Cumm
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * mk-lba-img.c
 *
 * Makes an image that contains the LBA in every *word of every sector
 */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>

#define NUM_SECT (256*63+1)
#define BPS (512)
#define SECT_INT (BPS / sizeof(unsigned int))

typedef unsigned char uint8_t;
typedef unsigned int uint32_t;

const char DEF_FN[] = "-";

int main(int argc, char *argv[])
{
	int i, rv = 0, one = 0;
	unsigned int lba, b[SECT_INT];
	int len;
	FILE *f;
	uint8_t tt = 0;
	const char *fn;

	if (argc >= 2) {
		if (argc >= 3) {
			if (strcasecmp("-1", argv[1]) == 0) {
				fn = argv[2];
				one = 1;
			} else {
				fn = argv[1];
			}
		} else {
			fn = argv[1];
		}
	} else {
		fn = DEF_FN;
	}

	if (!strcmp(fn, "-"))
		f = stdout;
	else
		f = fopen(fn, "w");

	if (!f) {
		fprintf(stderr, "%s: %s: unable to open for writing: %s\n",
			argv[0], fn, strerror(errno));
		return 1;
	}

	lba = 0;
	while ((len = fread(b, 1, BPS, stdin))) {
		if (len < BPS)
			memset((char *)b + len, 0, BPS - len);
		fwrite(b, 1, BPS, f);
		lba++;
	}

	memset(b, 0, sizeof b);

	while (lba < NUM_SECT) {
		if (one) {
			b[0] = lba;
		} else {
			for (i = 0; i < SECT_INT; i++)
				b[i] = lba;
		}
		fwrite(b, 1, BPS, f);
		lba++;
	}

	if (f != stdout)
		fclose(f);

	return rv;
}
