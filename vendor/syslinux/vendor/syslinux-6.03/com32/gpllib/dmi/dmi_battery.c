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
const char *dmi_battery_chemistry(uint8_t code)
{
    /* 3.3.23.1 */
    static const char *chemistry[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"Lead Acid",
	"Nickel Cadmium",
	"Nickel Metal Hydride",
	"Lithium Ion",
	"Zinc Air",
	"Lithium Polymer"	/* 0x08 */
    };

    if (code >= 0x01 && code <= 0x08)
	return chemistry[code - 0x01];
    return out_of_spec;
}

void dmi_battery_capacity(uint16_t code, uint8_t multiplier, char *capacity)
{
    if (code == 0)
	sprintf(capacity, "%s", "Unknown");
    else
	sprintf(capacity, "%u mWh", code * multiplier);
}

void dmi_battery_voltage(uint16_t code, char *voltage)
{
    if (code == 0)
	sprintf(voltage, "%s", "Unknown");
    else
	sprintf(voltage, "%u mV", code);
}

void dmi_battery_maximum_error(uint8_t code, char *error)
{
    if (code == 0xFF)
	sprintf(error, "%s", "Unknown");
    else
	sprintf(error, "%u%%", code);
}
