/* ----------------------------------------------------------------------- *
 *
 *   Pportions of this file taken from the dmidecode project
 *
 *   Copyright (C) 2000-2002 Alan Cox <alan@redhat.com>
 *   Copyright (C) 2002-2008 Jean Delvare <khali@linux-fr.org>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program; if not, write to the Free Software
 *   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 *
 *   For the avoidance of doubt the "preferred form" of this code is one which
 *   is in an open unpatent encumbered format. Where cryptographic key signing
 *   forms part of the process of creating an executable the information
 *   including keys needed to generate an equivalently functional executable
 *   are deemed to be part of the source code.
*/

#include <dmi/dmi.h>
#include <stdio.h>

const char *bios_charac_strings[] = {
    "BIOS characteristics not supported",	/* 3 */
    "ISA is supported",
    "MCA is supported",
    "EISA is supported",
    "PCI is supported",
    "PC Card (PCMCIA) is supported",
    "PNP is supported",
    "APM is supported",
    "BIOS is upgradeable",
    "BIOS shadowing is allowed",
    "VLB is supported",
    "ESCD support is available",
    "Boot from CD is supported",
    "Selectable boot is supported",
    "BIOS ROM is socketed",
    "Boot from PC Card (PCMCIA) is supported",
    "EDD is supported",
    "Japanese floppy for NEC 9800 1.2 MB is supported (int 13h)",
    "Japanese floppy for Toshiba 1.2 MB is supported (int 13h)",
    "5.25\"/360 KB floppy services are supported (int 13h)",
    "5.25\"/1.2 MB floppy services are supported (int 13h)",
    "3.5\"/720 KB floppy services are supported (int 13h)",
    "3.5\"/2.88 MB floppy services are supported (int 13h)",
    "Print screen service is supported (int 5h)",
    "8042 keyboard services are supported (int 9h)",
    "Serial services are supported (int 14h)",
    "Printer services are supported (int 17h)",
    "CGA/mono video services are supported (int 10h)",
    "NEC PC-98"			/* 31 */
};

const char *bios_charac_x1_strings[] = {
    "ACPI is supported",	/* 0 */
    "USB legacy is supported",
    "AGP is supported",
    "I2O boot is supported",
    "LS-120 boot is supported",
    "ATAPI Zip drive boot is supported",
    "IEEE 1394 boot is supported",
    "Smart battery is supported"	/* 7 */
};

const char *bios_charac_x2_strings[] = {
    "BIOS boot specification is supported",	/* 0 */
    "Function key-initiated network boot is supported",
    "Targeted content distribution is supported"	/* 2 */
};
