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

#ifndef __SYSLNX_H__
#define __SYSLNX_H__

#include <com32.h>

//Macros which help user not have to remember the structure of register
// Data structure

#define REG_AH(x) ((x).eax.b[1])
#define REG_AL(x) ((x).eax.b[0])
#define REG_AX(x) ((x).eax.w[0])
#define REG_EAX(x) ((x).eax.l)

#define REG_BH(x) ((x).ebx.b[1])
#define REG_BL(x) ((x).ebx.b[0])
#define REG_BX(x) ((x).ebx.w[0])
#define REG_EBX(x) ((x).ebx.l)

#define REG_CH(x) ((x).ecx.b[1])
#define REG_CL(x) ((x).ecx.b[0])
#define REG_CX(x) ((x).ecx.w[0])
#define REG_ECX(x) ((x).ecx.l)

#define REG_DH(x) ((x).edx.b[1])
#define REG_DL(x) ((x).edx.b[0])
#define REG_DX(x) ((x).edx.w[0])
#define REG_EDX(x) ((x).edx.l)

#define REG_DS(x) ((x).ds)
#define REG_ES(x) ((x).es)
#define REG_FS(x) ((x).fs)
#define REG_GS(x) ((x).gs)

#define REG_SI(x) ((x).esi.w[0])
#define REG_ESI(x) ((x).esi.l)

#define REG_DI(x) ((x).edi.w[0])
#define REG_EDI(x) ((x).edi.l)

char issyslinux(void);		/* Check if syslinux is running */

void runsyslinuxcmd(const char *cmd);	/* Run specified command */

void gototxtmode(void);		/* Change mode to text mode */

void syslinux_idle(void);	/* Call syslinux idle loop */

/* Run command line with ipappend, returns if kernel image not found
   If syslinux version too old, then defaults to runsyslinuxcmd */
void runsyslinuximage(const char *cmd, long ipappend);

#endif
