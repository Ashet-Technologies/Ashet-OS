/*
 * -----------------------------------------------------------------------
 *
 *   Copyright 1994-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * -----------------------------------------------------------------------
 *
 * -----------------------------------------------------------------------
 *  VGA splash screen code
 * -----------------------------------------------------------------------
 */

#include <stddef.h>
#include "core.h"
#include <sys/io.h>
#include <hw/vga.h>
#include "fs.h"

#include "bios.h"
#include "graphics.h"
#include <syslinux/video.h>

__export uint8_t UsingVGA = 0;
uint16_t VGAPos;		/* Pointer into VGA memory */
__export uint16_t *VGAFilePtr;	/* Pointer into VGAFileBuf */
__export uint16_t VGAFontSize = 16;	/* Defaults to 16 byte font */

__export char VGAFileBuf[VGA_FILE_BUF_SIZE];	/* Unmangled VGA image name */
__export char VGAFileMBuf[FILENAME_MAX];	/* Mangled VGA image name */

static uint8_t VGARowBuffer[640 + 80];	/* Decompression buffer */
static uint8_t VGAPlaneBuffer[(640/8) * 4]; /* Plane buffers */

extern uint16_t GXPixCols;
extern uint16_t GXPixRows;

/* Maps colors to consecutive DAC registers */
static uint8_t linear_color[] = { 0, 1, 2, 3, 4, 5, 6, 7, 8,
				  9, 10, 11, 12, 13, 14, 15, 0 };

static FILE *fd;

typedef struct {
	uint32_t LSSMagic;	/* Magic number */
	uint16_t GraphXSize;	/* Width of splash screen file */
	uint16_t GraphYSize;	/* Height of splash screen file */
	uint8_t GraphColorMap[3*16];
} lssheader_t;

static lssheader_t LSSHeader;

#define LSSMagic	LSSHeader.LSSMagic
#define GraphXSize	LSSHeader.GraphXSize
#define GraphYSize	LSSHeader.GraphYSize

/*
 * Enable VGA graphics, if possible. Return 0 on success.
 */
static int vgasetmode(void)
{
	com32sys_t ireg, oreg;

	if (UsingVGA)
		return 0;		/* Nothing to do... */

	memset(&ireg, 0, sizeof(ireg));
	memset(&oreg, 0, sizeof(oreg));

	if (UsingVGA & 0x4) {
		/*
		 * We're in VESA mode, which means VGA; use VESA call
		 * to revert the mode, and then call the conventional
		 * mode-setting for good measure...
		 */
		ireg.eax.w[0] = 0x4F02;
		ireg.ebx.w[0] = 0x0012;
		__intcall(0x10, &ireg, &oreg);
	} else {
		/* Get video card and monitor */
		ireg.eax.w[0] = 0x1A00;
		__intcall(0x10, &ireg, &oreg);
		oreg.ebx.b[0] -= 7; /* BL=07h and BL=08h OK */

		if (oreg.ebx.b[0] > 1)
			return -1;
	}

	/*
	 * Set mode.
	 */
	memset(&ireg, 0, sizeof(ireg));
	ireg.eax.w[0] = 0x0012;	/* Set mode = 640x480 VGA 16 colors */
	__intcall(0x10, &ireg, &oreg);

	memset(&ireg, 0, sizeof(ireg));
	ireg.edx.w[0] = (uint32_t)linear_color;
	ireg.eax.w[0] = 0x1002;	/* Write color registers */
	__intcall(0x10, &ireg, &oreg);

	UsingVGA = 1;

	/* Set GXPixCols and GXPixRows */
	GXPixCols = 640;
	GXPixRows = 480;

	use_font();
	ScrollAttribute = 0;

	return 0;
}

static inline char getnybble(void)
{
	char data = getc(fd);

	if (data & 0x10) {
		data &= 0x0F;
		return data;
	}

	data = getc(fd);
	return (data & 0x0F);
}

/*
 * rledecode:
 *	Decode a pixel row in RLE16 format.
 *
 * 'in': input (RLE16 encoded) buffer
 * 'out': output (decoded) buffer
 * 'count': pixel count
 */
static void rledecode(uint8_t *out, size_t count)
{
	uint8_t prev_pixel = 0;
	size_t size = count;
	uint8_t data;
	int i;

again:
	for (i = 0; i < size; i++) {

		data = getnybble();
		if (data == prev_pixel)
			break;

		*out++ = data;
		prev_pixel = data;
	}

	size -= i;
	if (!size)
		return;

	/* Start of run sequence */
	data = getnybble();
	if (data == 0) {
		/* long run */
		uint8_t hi;

		data = getnybble();
		hi = getnybble();
		hi <<= 4;
		data |= hi;
		data += 16;
	}

	/* dorun */
	for (i = 0; i < data; i++)
		*out++ = prev_pixel;

	size -= i;
	if (size)
		goto again;
}

/*
 * packedpixel2vga:
 *	Convert packed-pixel to VGA bitplanes
 *
 * 'in': packed pixel string (640 pixels)
 * 'out': output (four planes @ 640/8 = 80 bytes)
 * 'count': pixel count (multiple of 8)
 */
static void packedpixel2vga(const uint8_t *in, uint8_t *out)
{
	int i, j, k;

	for (i = 0; i < 4; i++) {
		const uint8_t *ip = in;

		for (j = 0; j < 640/8; j++) {
			uint8_t ob = 0;

			for (k = 0; k < 8; k++) {
				uint8_t px = *ip++;
				ob = (ob << 1) | ((px >> i) & 1);
			}

			*out++ = ob;
		}
	}
}

/*
 * outputvga:
 *	Output four subsequent lines of VGA data
 *
 * 'in': four planes @ 640/8=80 bytes
 * 'out': pointer into VGA memory
 */
static void outputvga(const void *in, void *out)
{
	int i;

	/* Select the sequencer mask */
	outb(VGA_SEQ_IX_MAP_MASK, VGA_SEQ_ADDR);

	for (i = 1; i <= 8; i <<= 1) {
		/* Select the bit plane to write */
		outb(i, VGA_SEQ_DATA);
		memcpy(out, in, 640/8);
		in = (const char *)in + 640/8;
	}
}

/*
 * Display a graphical splash screen.
 */
__export void vgadisplayfile(FILE *_fd)
{
	char *p;
	int size;

	fd = _fd;

	/*
	 * This is a cheap and easy way to make sure the screen is
	 * cleared in case we were in graphics mode aready.
	 */
	syslinux_force_text_mode();
	vgasetmode();

	size = 4+2*2+16*3;
	p = (char *)&LSSHeader;

	/* Load the header */
	while (size--)
		*p = getc(fd);

	if (*p != EOF) {
		com32sys_t ireg, oreg;
		uint16_t rows;
		int i;

		/* The header WILL be in the first chunk. */
		if (LSSMagic != 0x1413f33d)
			return;

		memset(&ireg, 0, sizeof(ireg));

		/* Color map offset */
		ireg.edx.w[0] = offsetof(lssheader_t, GraphColorMap);

		ireg.eax.w[0] = 0x1012;	       /* Set RGB registers */
		ireg.ebx.w[0] = 0;	       /* First register number */
		ireg.ecx.w[0] = 16;	       /* 16 registers */
		__intcall(0x10, &ireg, &oreg);

		/* Number of pixel rows */
		rows = (GraphYSize + VGAFontSize) - 1;
		rows = rows / VGAFontSize;
		if (rows >= VidRows)
			rows = VidRows - 1;

		memset(&ireg, 0, sizeof(ireg));

		ireg.edx.b[1] = rows;
		ireg.eax.b[1] = 2;
		ireg.ebx.w[0] = 0;

		/* Set cursor below image */
		__intcall(0x10, &ireg, &oreg);

		rows = GraphYSize; /* Number of graphics rows */
		VGAPos = 0;

		for (i = 0; i < rows; i++) {
			/* Pre-clear the row buffer */
			memset(VGARowBuffer, 0, 640);

			/* Decode one row */
			rledecode(VGARowBuffer, GraphXSize);

			packedpixel2vga(VGARowBuffer, VGAPlaneBuffer);
			outputvga(VGAPlaneBuffer, MK_PTR(0xA000, VGAPos));
			VGAPos += 640/8;
		}
	}
}

/*
 * Disable VGA graphics.
 */
__export void syslinux_force_text_mode(void)
{
	com32sys_t ireg, oreg;

	/* Already in text mode? */
	if (!UsingVGA)
		return;

	if (UsingVGA & 0x4) {
		/* VESA return to normal video mode */
		memset(&ireg, 0, sizeof(ireg));

		ireg.eax.w[0] = 0x4F02; /* Set SuperVGA video mode */
		ireg.ebx.w[0] = 0x0003;
		__intcall(0x10, &ireg, &oreg);
	}

	/* Return to normal video mode */
	memset(&ireg, 0, sizeof(ireg));
	ireg.eax.w[0] = 0x0003;
	__intcall(0x10, &ireg, &oreg);

	UsingVGA = 0;

	ScrollAttribute = 0x7;
	/* Restore text font/data */
	use_font();
}

static void vgacursorcommon(char data)
{
	if (UsingVGA) {
		com32sys_t ireg;
                memset(&ireg, 0, sizeof(ireg));

		ireg.eax.b[0] = data;
		ireg.eax.b[1] = 0x09;
		ireg.ebx.w[0] = 0x0007;
		ireg.ecx.w[0] = 1;
		__intcall(0x10, &ireg, NULL);
	}
}

void vgahidecursor(void)
{
	vgacursorcommon(' ');
}

void vgashowcursor(void)
{
	vgacursorcommon('_');
}

__export void using_vga(uint8_t vga, uint16_t pix_cols, uint16_t pix_rows)
{
    UsingVGA = vga;
    GXPixCols = pix_cols;
    GXPixRows = pix_rows;

    if (!(UsingVGA & 0x08))
        adjust_screen();
}

void pm_using_vga(com32sys_t *regs)
{
    using_vga(regs->eax.b[0], regs->ecx.w[0], regs->edx.w[0]);
}
