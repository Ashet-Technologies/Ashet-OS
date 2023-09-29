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

const char *dmi_chassis_type(uint8_t code)
{
    /* 3.3.4.1 */
    static const char *type[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"Desktop",
	"Low Profile Desktop",
	"Pizza Box",
	"Mini Tower",
	"Tower",
	"Portable",
	"Laptop",
	"Notebook",
	"Hand Held",
	"Docking Station",
	"All In One",
	"Sub Notebook",
	"Space-saving",
	"Lunch Box",
	"Main Server Chassis",	/* master.mif says System */
	"Expansion Chassis",
	"Sub Chassis",
	"Bus Expansion Chassis",
	"Peripheral Chassis",
	"RAID Chassis",
	"Rack Mount Chassis",
	"Sealed-case PC",
	"Multi-system",		/* 0x19 */
	"CompactPCI",
	"AdvancedTCA",
	"Blade",
	"Blade Enclosing" /* 0x1D */
    };

    if (code >= 0x01 && code <= 0x1D)
	return type[code - 0x01];
    return out_of_spec;
}

const char *dmi_chassis_lock(uint8_t code)
{
    static const char *lock[] = {
	"Not Present",		/* 0x00 */
	"Present"		/* 0x01 */
    };

    return lock[code];
}

const char *dmi_chassis_state(uint8_t code)
{
    /* 3.3.4.2 */
    static const char *state[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"Safe",			/* master.mif says OK */
	"Warning",
	"Critical",
	"Non-recoverable"	/* 0x06 */
    };

    if (code >= 0x01 && code <= 0x06)
	return (state[code - 0x01]);
    return out_of_spec;
}

const char *dmi_chassis_security_status(uint8_t code)
{
    /* 3.3.4.3 */
    static const char *status[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"None",
	"External Interface Locked Out",
	"External Interface Enabled"	/* 0x05 */
    };

    if (code >= 0x01 && code <= 0x05)
	return (status[code - 0x01]);
    return out_of_spec;
}
