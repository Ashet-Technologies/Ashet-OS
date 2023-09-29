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

#ifndef __TUI_H__
#define __TUI_H__

#include <com32.h>
#include <getkey.h>
#include <consoles.h>
#include "syslnx.h"
#include "com32io.h"

#ifndef NULL
#define NULL ((void *)0)
#endif

#define SO '\016'
#define SI '\017'

#define TOP_LEFT_CORNER_BORDER '\154'
#define TOP_BORDER '\161'
#define TOP_RIGHT_CORNER_BORDER '\153'
#define BOTTOM_LEFT_CORNER_BORDER '\155'
#define BOTTOM_BORDER '\161'
#define BOTTOM_RIGHT_CORNER_BORDER '\152'
#define LEFT_BORDER '\170'
#define RIGHT_BORDER '\170'
#define LEFT_MIDDLE_BORDER '\164'
#define MIDDLE_BORDER '\161'
#define RIGHT_MIDDLE_BORDER '\165'

#define BELL 0x07
#define GETSTRATTR 0x07

// Generic user input,
// password = 0 iff chars echoed on screen
// showoldvalue <> 0 iff current displayed for editing
void getuserinput(char *str, unsigned int size,
		  unsigned int password, unsigned int showoldvalue);

static inline void getstring(char *str, unsigned int size)
{
    getuserinput(str, size, 0, 0);
}

static inline void editstring(char *str, unsigned int size)
{
    getuserinput(str, size, 0, 1);
}

static inline void getpwd(char *str, unsigned int size)
{
    getuserinput(str, size, 1, 0);
}

void drawbox(const char, const char, const char, const char,
	     const char);

// Draw a horizontal line
// dumb == 1, means just draw the line
// dumb == 0 means check the first and last positions and depending on what is
//    currently on the screen make it a LTRT and/or RTLT appropriately.
void drawhorizline(const char, const char, const char, const char,
		   const char dumb);

#endif
