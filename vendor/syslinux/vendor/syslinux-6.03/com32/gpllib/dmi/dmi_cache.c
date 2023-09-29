/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer - All Rights Reserved
 *
 *   Some part borrowed from DMI Decode:
 *
 *   (C) 2000-2002 Alan Cox <alan@redhat.com>
 *   (C) 2002-2007 Jean Delvare <khali@linux-fr.org>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <dmi/dmi.h>
#include <dmi/dmi_cache.h>
#include <stdio.h>

/*
 * 3.3.8 Cache Information (Type 7)
 */

const char *dmi_cache_mode(uint8_t code)
{
    static const char *mode[] = {
	"Write Through",	/* 0x00 */
	"Write Back",
	"Varies With Memory Address",
	"Unknown"		/* 0x03 */
    };

    return mode[code];
}

const char *dmi_cache_location(uint8_t code)
{
    static const char *location[4] = {
	"Internal",		/* 0x00 */
	"External",
	"<OUT OF SPEC",		/* 0x02 */
	"Unknown"		/* 0x03 */
    };

    if (location[code] != NULL)
	return location[code];
    return out_of_spec;
}

uint16_t dmi_cache_size(uint16_t code)
{
    if (code & 0x8000)
	return (code & 0x7FFF) << 6;	/* KB */
    else
	return code;		/* KB */
}

void dmi_cache_types(uint16_t code, const char *sep, char *array)
{
    /* 3.3.8.2 */
    static const char *types[] = {
	"Other",		/* 0 */
	"Unknown",
	"Non-burst",
	"Burst",
	"Pipeline Burst",
	"Synchronous",
	"Asynchronous"		/* 6 */
    };

    if ((code & 0x007F) == 0)
	strcpy(array, "None");
    else {
	int i;

	for (i = 0; i <= 6; i++)
	    if (code & (1 << i))
		sprintf(array, "%s%s", sep, types[i]);
    }
}

const char *dmi_cache_ec_type(uint8_t code)
{
    /* 3.3.8.3 */
    static const char *type[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"None",
	"Parity",
	"Single-bit ECC",
	"Multi-bit ECC"		/* 0x06 */
    };

    if (code >= 0x01 && code <= 0x06)
	return type[code - 0x01];
    return out_of_spec;
}

const char *dmi_cache_type(uint8_t code)
{
    /* 3.3.8.4 */
    static const char *type[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"Instruction",
	"Data",
	"Unified"		/* 0x05 */
    };

    if (code >= 0x01 && code <= 0x05)
	return type[code - 0x01];
    return out_of_spec;
}

const char *dmi_cache_associativity(uint8_t code)
{
    /* 3.3.8.5 */
    static const char *type[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"Direct Mapped",
	"2-way Set-associative",
	"4-way Set-associative",
	"Fully Associative",
	"8-way Set-associative",
	"16-way Set-associative",	/* 0x08 */
	"12-way Set-associative",
	"24-way Set-associative",
	"32-way Set-associative",
	"48-way Set-associative",
	"64-way Set-associative"	/* 0x0D */
    };

    if (code >= 0x01 && code <= 0x0D)
	return type[code - 0x01];
    return out_of_spec;
}
