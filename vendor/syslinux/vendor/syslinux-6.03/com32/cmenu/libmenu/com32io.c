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

#include <string.h>
#include <com32.h>
#include "com32io.h"
#include "tui.h"
#include "syslnx.h"

com32sys_t inreg, outreg;	// Global register sets for use

void getpos(char *row, char *col, char page)
{
    memset(&inreg, 0, sizeof inreg);
    REG_AH(inreg) = 0x03;
    REG_BH(inreg) = page;
    __intcall(0x10, &inreg, &outreg);
    *row = REG_DH(outreg);
    *col = REG_DL(outreg);
}

char inputc(char *scancode)
{
    syslinux_idle();		/* So syslinux can perform periodic activity */
    memset(&inreg, 0, sizeof inreg);
    REG_AH(inreg) = 0x10;
    __intcall(0x16, &inreg, &outreg);
    if (scancode)
	*scancode = REG_AH(outreg);
    return REG_AL(outreg);
}

void getcursorshape(char *start, char *end)
{
    char page = 0; // XXX TODO
    memset(&inreg, 0, sizeof inreg);
    REG_AH(inreg) = 0x03;
    REG_BH(inreg) = page;
    __intcall(0x10, &inreg, &outreg);
    *start = REG_CH(outreg);
    *end = REG_CL(outreg);
}

void setcursorshape(char start, char end)
{
    memset(&inreg, 0, sizeof inreg);
    REG_AH(inreg) = 0x01;
    REG_CH(inreg) = start;
    REG_CL(inreg) = end;
    __intcall(0x10, &inreg, &outreg);
}

void setvideomode(char mode)
{
    memset(&inreg, 0, sizeof inreg);
    REG_AH(inreg) = 0x00;
    REG_AL(inreg) = mode;
    __intcall(0x10, &inreg, &outreg);
}

// Get char displayed at current position
unsigned char getcharat(char page)
{
    memset(&inreg, 0, sizeof inreg);
    REG_AH(inreg) = 0x08;
    REG_BH(inreg) = page;
    __intcall(0x16, &inreg, &outreg);
    return REG_AL(outreg);
}
