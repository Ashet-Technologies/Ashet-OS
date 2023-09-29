/* ----------------------------------------------------------------------- *
 *
 *   Copyright 1994-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2013 Intel Corporation
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 *
 * font.c
 *
 * VGA font handling code
 *
 */

#include <syslinux/firmware.h>
#include <syslinux/video.h>
#include <sys/io.h>
#include <stdio.h>
#include <fs.h>

#include "bios.h"
#include "graphics.h"
#include "core.h"

__export uint8_t UserFont = 0;		/* Using a user-specified font */

__export __lowmem char fontbuf[8192];

uint16_t GXPixCols = 1;		/* Graphics mode pixel columns */
uint16_t GXPixRows = 1;		/* Graphics mode pixel rows */

/*
 * loadfont:	Load a .psf font file and install it onto the VGA console
 *		(if we're not on a VGA screen then ignore.)
 */
__export void loadfont(const char *filename)
{
	struct psfheader {
		uint16_t magic;
		uint8_t mode;
		uint8_t height;
	} hdr;
	FILE *f;

	f = fopen(filename, "r");
	if (!f)
		return;

	/* Read header */
	if (_fread(&hdr, sizeof hdr, f) != sizeof hdr)
		goto fail;

	/* Magic number */
	if (hdr.magic != 0x0436)
		goto fail;

	/* File mode: font modes 0-5 supported */
	if (hdr.mode > 5)
		goto fail;

	/* VGA minimum/maximum */
	if (hdr.height < 2 || hdr.height > 32)
		goto fail;

	/* Load the actual font into the font buffer. */
	memset(fontbuf, 0, 256*32);
	if (_fread(fontbuf, 256*hdr.height, f) != 256*hdr.height)
	    goto fail;

	/* Loaded OK */
	VGAFontSize = hdr.height;
	UserFont = 1;		/* Set font flag */
	use_font();

fail:
	fclose(f);
}

/*
 * use_font:
 *	This routine activates whatever font happens to be in the
 *	vgafontbuf, and updates the bios_adjust_screen data.
 *      Must be called with CS = DS
 */
void use_font(void)
{
	com32sys_t ireg, oreg;
	uint8_t bytes = VGAFontSize;

	/* Nonstandard mode? */
	if (UsingVGA & ~0x3)
		syslinux_force_text_mode();

	memset(&ireg, 0, sizeof(ireg));

	ireg.es = SEG(fontbuf);
	ireg.ebp.w[0] = OFFS(fontbuf); /* ES:BP -> font */

	/* Are we using a user-specified font? */
	if (UserFont & 0x1) {
		/* Are we in graphics mode? */
		if (UsingVGA & 0x1) {
			uint8_t rows;

			rows = GXPixRows / bytes;
			VidRows = rows - 1;

			/* Set user character table */
			ireg.eax.w[0] = 0x1121;
			ireg.ebx.b[0] = 0;
			ireg.ecx.b[0] = bytes; /* bytes/character */
			ireg.edx.b[0] = rows;

			__intcall(0x10, &ireg, &oreg);

			/* 8 pixels/character */
			VidCols = ((GXPixCols >> 3) - 1);

			/* No need to call bios_adjust_screen */
			return;
		} else {
			ireg.eax.w[0] = 0x1110;	/* Load into VGA RAM */
			ireg.ebx.b[0] = 0;
			ireg.ebx.b[1] = bytes; /* bytes/character */
			ireg.ecx.w[0] = 256;
			ireg.edx.w[0] = 0;

			__intcall(0x10, &ireg, &oreg);

                        memset(&ireg, 0, sizeof(ireg));
			ireg.ebx.b[0] = 0;
			ireg.eax.w[0] = 0x1103; /* Select page 0 */
			__intcall(0x10, &ireg, NULL);
		}

	}

	bios_adjust_screen();
}

/*
 * bios_adjust_screen: Set the internal variables associated with the screen size.
 *		This is a subroutine in case we're loading a custom font.
 */
void bios_adjust_screen(void)
{
	com32sys_t ireg, oreg;
	volatile uint8_t *vidrows = (volatile uint8_t *)BIOS_vidrows;
	uint8_t rows, cols;

	memset(&ireg, 0, sizeof(ireg));

	rows = *vidrows;
	if (!rows) {
		/*
		 * No vidrows in BIOS, assume 25.
		 * (Remember: vidrows == rows-1)
		 */
		rows = 24;
	}

	VidRows = rows;

	ireg.eax.b[1] = 0x0f;	/* Read video state */
	__intcall(0x10, &ireg, &oreg);
	cols = oreg.eax.b[1];

	VidCols = --cols;	/* Store count-1 (same as rows) */
}

void adjust_screen(void)
{
	if (firmware->adjust_screen)
		firmware->adjust_screen();
}

void pm_adjust_screen(com32sys_t *regs __unused)
{
	adjust_screen();
}

void pm_userfont(com32sys_t *regs)
{
	regs->es = SEG(fontbuf);
	regs->ebx.w[0] = OFFS(fontbuf);
}
