/* -*- c -*- ------------------------------------------------------------- *
 *
 *   Copyright 2004-2005 Murali Krishnan Ganapathy - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#ifndef __COM32IO_H__
#define __COM32IO_H__

#include <com32.h>
#include <stdio.h>
#include <libansi.h>

#ifndef NULL
#define NULL ((void *)0)
#endif

/* Bits representing ShiftFlags, See Int16/Function 2 or Mem[0x417] to get this info */

#define INSERT_ON     (1<<7)
#define CAPSLOCK_ON   (1<<6)
#define NUMLOCK_ON    (1<<5)
#define SCRLLOCK_ON   (1<<4)
#define ALT_PRESSED   (1<<3)
#define CTRL_PRESSED  (1<<2)
// actually 1<<1 is Left Shift, 1<<0 is right shift
#define SHIFT_PRESSED (1<<1 | 1 <<0)

/* BIOS Assisted output routines */

void getpos(char *row, char *col, char page);

char inputc(char *scancode);	// Return ASCII char by val, and scancode by reference

void setcursorshape(char start, char end);	// Set cursor shape
void getcursorshape(char *start, char *end);	// Get shape for current page

// Get char displayed at current position in specified page
unsigned char getcharat(char page);

static inline unsigned char readbiosb(unsigned int ofs)
{
    return *((unsigned char *)MK_PTR(0, ofs));
}

static inline char getshiftflags(void)
{
    return readbiosb(0x417);
}

void scrollupwindow(char top, char left, char bot, char right, char attr, char numlines);	//Scroll up given window

void setvideomode(char mode);	// Set the video mode.

static inline char getvideomode(void)	// Get the current video mode
{
    return readbiosb(0x449);
}

#endif
