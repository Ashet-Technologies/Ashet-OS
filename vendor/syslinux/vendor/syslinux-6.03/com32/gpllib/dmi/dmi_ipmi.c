/* ----------------------------------------------------------------------- *
 *
 *   Portions of this file taken from the dmidecode project
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

const char *dmi_ipmi_interface_type(uint8_t code)
{
    /* 3.3.39.1 and IPMI 2.0, appendix C1, table C1-2 */
    static const char *type[] = {
	"Unknown",		/* 0x00 */
	"KCS (Keyboard Control Style)",
	"SMIC (Server Management Interface Chip)",
	"BT (Block Transfer)",
	"SSIF (SMBus System Interface)"	/* 0x04 */
    };

    if (code <= 0x04)
	return type[code];
    return out_of_spec;
}

void dmi_ipmi_base_address(uint8_t type, const uint8_t * p, s_ipmi * ipmi)
{
    if (type == 0x04) {		/* SSIF */
	ipmi->base_address = (*p) >> 1;
    } else {
	ipmi->base_address = QWORD(p);
    }
}
