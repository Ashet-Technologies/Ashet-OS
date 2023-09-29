/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010 Gert Hulselmans - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * ifplop.c
 *
 * This COM32 module detects if the PLoP Boot Manager was used to boot a CDROM
 * drive or USB drive, by checking for the presence of the PLoP INT13h hook.
 *
 * Usage:    ifplop.c32 [<plop_detected>] -- [<plop_not_detected>]
 * Examples: ifplop.c32 menu.c32 another.cfg -- plpbt hiddenusb usb1=2
 *              You need to remove the ".bin" extension of the plpbt.bin file
 *              if you use it this way.
 *           ifplop.c32 plop_detected -- plop_not_detected
 *
 * A possible config file could be:
 *
 * ===========================================================================
 *  DEFAULT plopcheck
 *
 *  # Check for the presence of PLoP (run by default)
 *  #   When PLoP INT13h hook is found, run the first command (plop_detected)
 *  #   When PLoP INT13h hook isn't found, run the second command (plop_not_detected)
 *  LABEL plopcheck
 *      COM32 ifplop.c32
 *      APPEND plop_detected -- plop_not_detected
 *
 *  # When PLoP INT13h hook was found, boot the menu system.
 *  # PLoP can have added USB 2.0 speed, so the entries we want to boot
 *  # will be read from disk much faster (supposing that we have a BIOS
 *  # that only supports USB 1.1 speed, but a mobo with USB 2.0 controllers).
 *  LABEL plop_detected
 *      COM32 menu.c32
 *      APPEND another.cfg
 *
 *  # PLoP INT13h hook wasn't found, so we boot PLoP, so it can add USB 2.0 support
 *  # When using "LINUX plpbt.bin", you don't need to remove the .bin extension.
 *  LABEL plop_not_detected
 *      LINUX plpbt.bin
 *      APPEND hiddenusb usb1=2
 *
 * ===========================================================================
 *
 * Why is/can this module be useful?
 *
 * You may want to boot PLoP by default from Syslinux when you boot from your
 * USB stick/drive:
 *   1. PLoP can upgrade USB 1.1 speed offered by the BIOS to USB 2.0 speed
 *      if you have USB 2.0 controllers on your mobo.
 *   2. Some BIOSes only can access the first 128GiB (137GB) on USB drives, while
 *      internal hard drives don't necessarily suffer from this 128GiB problem.
 *      Using PLoPs USB capabilities, you can access the whole drive.
 *
 * When you select the "USB" entry in PLoP, it will boot your USB stick/drive
 * again and it will boot PLoP again when you have set booting PLoP as DEFAULT
 * boot option in your Syslinux configuration file.
 *
 * By using ifplop.c32 you can specify which action you want to do the second
 * time your USB stick/drive is booted. So you can load another config file or
 * boot a large hard disk image or whatever you want.
 *
 * PLoP Boot Manager website: http://www.plop.at/en/bootmanager.html
 */

#include <com32.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <alloca.h>
#include <console.h>
#include <syslinux/boot.h>

static bool plop_INT13h_check(void)
{
    com32sys_t inregs, outregs;

    /* Prepare the register set */
    memset(&inregs, 0, sizeof inregs);

    /*
     * Check if PLoP already has booted a CDROM or USB drive by checking
     * for the presence of the PLoP INT13h hook.
     *
     * The following assembly code (NASM) can detect the PLoP INT13h hook:
     *
     *   mov eax,'PoLP'  ; Reverse of 'PLoP'
     *   mov ebp,'DKHC'  ; Reverse of 'CHKD'
     *   int 13h
     *   cmp eax,' sey'  ; Reverse of 'yes '
     *   jz plop_INT13h_active
     */

    inregs.eax.l = 0x504c6f50;	/* "PLoP" */
    inregs.ebp.l = 0x43484b44;	/* "CHKD" */

    __intcall(0x13, &inregs, &outregs);

    /* eax will contain "yes " if PLoP INT13h hook is available */
    if (outregs.eax.l == 0x79657320)
	return true;

    return false;
}

/* XXX: this really should be librarized */
static void boot_args(char **args)
{
    int len = 0, a = 0;
    char **pp;
    const char *p;
    char c, *q, *str;

    for (pp = args; *pp; pp++)
	len += strlen(*pp) + 1;

    q = str = alloca(len);
    for (pp = args; *pp; pp++) {
	p = *pp;
	while ((c = *p++))
	    *q++ = c;
	*q++ = ' ';
	a = 1;
    }
    q -= a;
    *q = '\0';

    if (!str[0])
	syslinux_run_default();
    else
	syslinux_run_command(str);
}

int main(int argc, char *argv[])
{
    char **args[2];
    int arg = 0;

    if (argc)
	arg++;
    args[0] = &argv[arg];
    args[1] = NULL;
    while (arg < argc) {
	if (!strcmp(argv[arg], "--")) {
	    argv[arg] = NULL;
	    args[1] = &argv[arg + 1];
	    break;
	}
	arg++;
    }
    if (args[1] != NULL) {
	boot_args(plop_INT13h_check()? args[0] : args[1]);
    } else {
	fprintf(stderr,
		"Usage:   ifplop.c32 [<plop_detected>] -- [<plop_not_detected>]\n"
		"Example: ifplop.c32 menu.c32 another.cfg -- plpbt hiddenusb usb1=2\n");
    }

    return 0;
}
