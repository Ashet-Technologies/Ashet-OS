/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Shao Miller - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * dskprobe.c
 *
 * Routines for probing BIOS disk drives
 */

/* Change to 1 for debugging */
#define DBG_DSKPROBE 0

#include <stdint.h>
#include "memdisk.h"
#include "bda.h"
#include "conio.h"

/* Function type for printf() */
typedef int (f_printf) (const char *, ...);

/* Dummy printf() that does nothing */
static f_printf no_printf;
static f_printf *dskprobe_printfs[] = { no_printf, printf };

#define dskprobe_printf (dskprobe_printfs[DBG_DSKPROBE])

static void dskprobe_pause(com32sys_t *);

/* Probe routine function type */
typedef int (f_probe) (uint8_t, com32sys_t *);
static f_probe probe_int13h_08h, probe_int13h_15h, probe_int13h_41h;

/* We will probe a BIOS drive number using INT 0x13, AH == func */
static void probe_any(uint8_t func, uint8_t drive, com32sys_t * regs)
{
    regs->eax.b[1] = func;	/* AH == sub-function for probe */
    regs->edx.b[0] = drive;	/* DL == drive number to probe */
    intcall(0x13, regs, regs);
    return;
}

/**
 * Determine if the return from probe_int13h_01h indicates a failure; a
 * return of zero indicates no known failure.
 */
static int probe_int13h_01h_fail(int istatus)
{
    int status = 0;

    if (istatus >= 256)
	status = istatus;
    else
	switch (istatus) {
	case 1: status = istatus;
	}
    return status;
}

/**
 * INT 0x13, AH == 0x01: Get status of last command.
 */
static int probe_int13h_01h(uint8_t drive)
{
    int status;
    com32sys_t regs;

    memset(&regs, 0, sizeof regs);
    probe_any(0x01, drive, &regs);
    status = (regs.eflags.l & 1) * 256 + regs.eax.b[1];
    dskprobe_printf("  AH01: CF%d AH%02x", regs.eflags.l & 1, regs.eax.b[1]);
    return status;
}

/**
 * INT 0x13, AH == 0x08: Get drive parameters.
 */
static int probe_int13h_08h(uint8_t drive, com32sys_t * regs)
{
    int present;
    int status;

    memset(regs, 0, sizeof *regs);
    probe_any(0x08, drive, regs);
    dskprobe_printf("  AH08: CF%d AH%02x AL%02x BL%02x DL%02x    ",
		    regs->eflags.l & 1, regs->eax.b[1], regs->eax.b[0],
		    regs->ebx.b[0], regs->edx.b[0]);
    present = !(regs->eflags.l & 1) && !regs->eax.b[1];
    status = probe_int13h_01h(drive);
    present = present && !(probe_int13h_01h_fail(status));
    dskprobe_printf("  P%d\n",  present);
    return present;
}

/**
 * INT 0x13, AH == 0x15: Get disk type.
 */
static int probe_int13h_15h(uint8_t drive, com32sys_t * regs)
{
    int present;
    int status;

    memset(regs, 0, sizeof *regs);
    probe_any(0x15, drive, regs);
    dskprobe_printf("  AH15: CF%d AH%02x AL%02x CX%04x DX%04x",
		    regs->eflags.l & 1, regs->eax.b[1], regs->eax.b[0],
		    regs->ecx.w[0], regs->edx.w[0]);
    present = !(regs->eflags.l & 1) && regs->eax.b[1];
    status = probe_int13h_01h(drive);
    present = present && !(probe_int13h_01h_fail(status));
    dskprobe_printf("  P%d\n",  present);
    return present;
}

/**
 * INT 0x13, AH == 0x41: INT 0x13 extensions installation check.
 */
static int probe_int13h_41h(uint8_t drive, com32sys_t * regs)
{
    int present;
    int status;

    memset(regs, 0, sizeof *regs);
    regs->ebx.w[0] = 0x55AA;	/* BX == 0x55AA */
    probe_any(0x41, drive, regs);
    dskprobe_printf("  AH41: CF%d AH%02x BX%04x CX%04x DH%02x",
		    regs->eflags.l & 1, regs->eax.b[1], regs->ebx.w[0],
		    regs->ecx.w[0], regs->edx.b[1]);
    present = !(regs->eflags.l & 1) && (regs->ebx.w[0] == 0xAA55);
    status = probe_int13h_01h(drive);
    present = present && !(probe_int13h_01h_fail(status));
    dskprobe_printf("  P%d\n",  present);
    return present;
}

/*
 * We will probe the BIOS Data Area and count the drives found there.
 * This heuristic then assumes that all drives of 'drive's type are
 * found in a contiguous range, and returns 1 if the probed drive
 * is less than or equal to the BDA count.
 * This particular function's code is derived from code in setup.c by
 * H. Peter Anvin.  Please respect that file's copyright for this function
 */
int probe_bda_drive(uint8_t drive)
{
    int bios_drives;
    int err;

    if (drive & 0x80) {
	bios_drives = rdz_8(BIOS_HD_COUNT);	/* HDD count */
    } else {
	uint8_t equip = rdz_8(BIOS_EQUIP);
	if (equip & 1)
	    bios_drives = (equip >> 6) + 1;	/* Floppy count */
	else
	    bios_drives = 0;
    }
    err = (drive - (drive & 0x80)) >= bios_drives ? 0 : 1;
    dskprobe_printf("BDA drive %02x? %d, total count: %d\n", drive, err,
		    bios_drives);
    return err;
}

/*
 * We will probe a drive with a few different methods, returning
 * the count of succesful probes
 */
int multi_probe_drive(uint8_t drive)
{
    int c = 0;
    com32sys_t regs;

    dskprobe_printf("INT 13 DL%02x:\n", drive);
    /* Only probe the BDA for floppies */
    if (drive & 0x80) {

	c += probe_int13h_08h(drive, &regs);
	c += probe_int13h_15h(drive, &regs);
	c += probe_int13h_41h(drive, &regs);
    }
    c += probe_bda_drive(drive);
    dskprobe_pause(&regs);
    return c;
}

/*
 * We will probe a contiguous range of BIOS drive, starting with drive
 * number 'start'.  We probe with a few different methods, and return
 * the first drive which doesn't respond to any of the probes.
 */
uint8_t probe_drive_range(uint8_t start)
{
    uint8_t drive = start;
    while (multi_probe_drive(drive)) {
	drive++;
	/* Check for passing the floppy/HDD boundary */
	if ((drive & 0x7F) == 0)
	    break;
    }
    return drive;
}

/* Dummy printf() that does nothing */
static int no_printf(const char *ignored, ...)
{
    (void)ignored;
    return 0;
}

/* Pause if we are in debug-mode */
static void dskprobe_pause(com32sys_t * regs)
{
    if (!DBG_DSKPROBE)
	return;
    dskprobe_printf("Press a key to continue...\n");
    memset(regs, 0, sizeof *regs);
    regs->eax.w[0] = 0;
    intcall(0x16, regs, NULL);
    return;
}
