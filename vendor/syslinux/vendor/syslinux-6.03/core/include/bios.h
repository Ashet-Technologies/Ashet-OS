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
 *
 * bios.h
 *
 * Header file for the BIOS data structures etc.
 */

#ifndef _BIOS_H
#define _BIOS_H

#include <sys/io.h>

/*
 * Interrupt vectors
 */
#define BIOS_timer_hook	(4 * 0x1C)
#define fdctab		(4 * 0x1E)
#define fdctab1		fdctab
#define fdctab2		(fdctab + 2)

#define SERIAL_BASE	0x0400	/* Base address for 4 serial ports */
#define BIOS_fbm	0x0413	/* Free Base Memory (kilobytes) */
#define BIOS_page	0x0462	/* Current video page */
#define BIOS_timer	0x046C	/* Timer ticks */
#define BIOS_magic	0x0472	/* BIOS reset magic */
#define BIOS_vidrows	0x0484	/* Number of screen rows */

static inline uint16_t bios_fbm(void)
{
	return *(volatile uint16_t *)BIOS_fbm;
}

static inline void set_bios_fbm(uint16_t mem)
{
	*(volatile uint16_t *)BIOS_fbm = mem;
}

#define serial_buf_size		4096
#define IO_DELAY_PORT		0x80 /* Invalid port (we hope!) */

static inline void io_delay(void)
{
	outb(0x0, IO_DELAY_PORT);
	outb(0x0, IO_DELAY_PORT);
}

/*
 * Sometimes we need to access screen coordinates as separate 8-bit
 * entities and sometimes we need to use them as 16-bit entities. Using
 * this structure allows the compiler to do it for us.
 */
union screen {
	struct {
		uint8_t col;	/* Cursor column for message file */
		uint8_t row;	/* Cursor row for message file */
	} b;
	uint16_t dx;
};
extern union screen _cursor;
extern union screen _screensize;

#define CursorDX	_cursor.dx
#define CursorCol	_cursor.b.col
#define CursorRow	_cursor.b.row

#define ScreenSize	_screensize.dx
#define VidCols		_screensize.b.col
#define VidRows		_screensize.b.row

/* font.c */
extern void use_font(void);
extern void bios_adjust_screen(void);

/* serirq.c */
extern char *SerialHead;
extern char *SerialTail;

extern void bios_init(void);

static inline uint16_t get_serial_port(uint16_t port)
{
    /* Magic array in BIOS memory, contains four entries */
    const uint16_t * const serial_ports = (const uint16_t *)SERIAL_BASE;

    /*
     * If port > 3 then the port is simply the I/O base address
     */
    if (port > 3)
	return port;

    /* Get the I/O port from the BIOS */
    return serial_ports[port];
}

#endif /* _BIOS_H */
