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

void dmi_memory_array_error_handle(uint16_t code, char *array)
{
    if (code == 0xFFFE)
	sprintf(array, "%s", "Not Provided");
    else if (code == 0xFFFF)
	sprintf(array, "%s", "No Error");
    else
	sprintf(array, "0x%04X", code);
}

void dmi_memory_device_width(uint16_t code, char *width)
{
    /*
     * 3.3.18 Memory Device (Type 17)
     * If no memory module is present, width may be 0
     */
    if (code == 0xFFFF || code == 0)
	sprintf(width, "%s", "Unknown");
    else
	sprintf(width, "%u bits", code);
}

void dmi_memory_device_size(uint16_t code, char *size)
{
    if (code == 0)
	sprintf(size, "%s", "Free");
    else if (code == 0xFFFF)
	sprintf(size, "%s", "Unknown");
    else {
	if (code & 0x8000)
	    sprintf(size, "%u kB", code & 0x7FFF);
	else
	    sprintf(size, "%u MB", code);
    }
}

const char *dmi_memory_device_form_factor(uint8_t code)
{
    /* 3.3.18.1 */
    static const char *form_factor[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"SIMM",
	"SIP",
	"Chip",
	"DIP",
	"ZIP",
	"Proprietary Card",
	"DIMM",
	"TSOP",
	"Row Of Chips",
	"RIMM",
	"SODIMM",
	"SRIMM",
	"FB-DIMM"		/* 0x0F */
    };

    if (code >= 0x01 && code <= 0x0F)
	return form_factor[code - 0x01];
    return out_of_spec;
}

void dmi_memory_device_set(uint8_t code, char *set)
{
    if (code == 0)
	sprintf(set, "%s", "None");
    else if (code == 0xFF)
	sprintf(set, "%s", "Unknown");
    else
	sprintf(set, "%u", code);
}

const char *dmi_memory_device_type(uint8_t code)
{
    /* 3.3.18.2 */
    static const char *type[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"DRAM",
	"EDRAM",
	"VRAM",
	"SRAM",
	"RAM",
	"ROM",
	"Flash",
	"EEPROM",
	"FEPROM",
	"EPROM",
	"CDRAM",
	"3DRAM",
	"SDRAM",
	"SGRAM",
	"RDRAM",
	"DDR",
	"DDR2",
	"DDR2 FB-DIMM",		/* 0x14 */
	NULL,
	NULL,
	NULL,
	"DDR3",			/* 0x18 */
	"FBD2"			/* 0x19 */
    };

    if (code >= 0x01 && code <= 0x19)
	return type[code - 0x01];
    return out_of_spec;
}

void dmi_memory_device_type_detail(uint16_t code, char *type_detail, int sizeof_type_detail)
{
    /* 3.3.18.3 */
    static const char *detail[] = {
	"Other",		/* 1 */
	"Unknown",
	"Fast-paged",
	"Static Column",
	"Pseudo-static",
	"RAMBus",
	"Synchronous",
	"CMOS",
	"EDO",
	"Window DRAM",
	"Cache DRAM",
	"Non-Volatile"		/* 12 */
    };

    if ((code & 0x1FFE) == 0)
	sprintf(type_detail, "%s", "None");
    else {
	int i;

	for (i = 1; i <= 12; i++)
	    if (code & (1 << i))
		snprintf(type_detail, sizeof_type_detail, "%s", detail[i - 1]);
    }
}

void dmi_memory_device_speed(uint16_t code, char *speed)
{
    if (code == 0)
	sprintf(speed, "%s", "Unknown");
    else
	sprintf(speed, "%u MHz", code);
}

/*
 * 3.3.7 Memory Module Information (Type 6)
 */

void dmi_memory_module_types(uint16_t code, const char *sep, char *type, int sizeof_type)
{
    /* 3.3.7.1 */
    static const char *types[] = {
	"Other",		/* 0 */
	"Unknown",
	"Standard",
	"FPM",
	"EDO",
	"Parity",
	"ECC",
	"SIMM",
	"DIMM",
	"Burst EDO",
	"SDRAM"			/* 10 */
    };

    if ((code & 0x07FF) == 0)
	sprintf(type, "%s", "None");
    else {
	int i;

	for (i = 0; i <= 10; i++)
	    if (code & (1 << i))
		snprintf(type, sizeof_type, "%s%s%s", type, sep, types[i]);
    }
}

void dmi_memory_module_connections(uint8_t code, char *connection, int sizeof_connection)
{
    if (code == 0xFF)
	sprintf(connection, "%s", "None");
    else {
	if ((code & 0xF0) != 0xF0)
	    sprintf(connection, "%u ", code >> 4);
	if ((code & 0x0F) != 0x0F)
	    snprintf(connection, sizeof_connection, "%s%u", connection, code & 0x0F);
    }
}

void dmi_memory_module_speed(uint8_t code, char *speed)
{
    if (code == 0)
	sprintf(speed, "%s", "Unknown");
    else
	sprintf(speed, "%u ns", code);
}

void dmi_memory_module_size(uint8_t code, char *size, int sizeof_size)
{
    /* 3.3.7.2 */
    switch (code & 0x7F) {
    case 0x7D:
	sprintf(size, "%s", "Not Determinable");
	break;
    case 0x7E:
	sprintf(size, "%s", "Disabled");
	break;
    case 0x7F:
	sprintf(size, "%s", "Not Installed");
	return;
    default:
	sprintf(size, "%u MB", 1 << (code & 0x7F));
    }

    if (code & 0x80)
	snprintf(size, sizeof_size, "%s %s", size, "(Double-bank Connection)");
    else
	snprintf(size, sizeof_size, "%s %s", size, "(Single-bank Connection)");
}

void dmi_memory_module_error(uint8_t code, const char *prefix, char *error)
{
    if (code & (1 << 2))
	sprintf(error, "%s", "See Event Log\n");
    else {
	if ((code & 0x03) == 0)
	    sprintf(error, "%s", "OK\n");
	if (code & (1 << 0))
	    sprintf(error, "%sUncorrectable Errors\n", prefix);
	if (code & (1 << 1))
	    sprintf(error, "%sCorrectable Errors\n", prefix);
    }
}
