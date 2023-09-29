/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2006 Erwan Velu - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * -----------------------------------------------------------------------
*/

#include <stdio.h>
#include <string.h>
#include "vpd/vpd.h"

int vpd_checksum(char *buf, int len)
{
    uint8_t sum = 0;
    int a;

    for (a = 0; a < len; a++)
	sum += buf[a];
    return (sum == 0);
}

int vpd_decode(s_vpd * vpd)
{
    uint8_t buf[16];
    char *p, *q;

    /* Cleaning structures */
    memset(&vpd->base_address, 0, sizeof(vpd->base_address));
    memset(&vpd->bios_build_id, 0, sizeof(vpd->bios_build_id));
    memset(&vpd->box_serial_number, 0, sizeof(vpd->box_serial_number));
    memset(&vpd->motherboard_serial_number, 0,
	   sizeof(vpd->motherboard_serial_number));
    memset(&vpd->machine_type_model, 0, sizeof(vpd->machine_type_model));
    memset(&vpd->bios_release_date, 0, sizeof(vpd->bios_release_date));
    memset(&vpd->default_flash_filename, 0,
	   sizeof(vpd->default_flash_filename));
    memset(&vpd->bios_version, 0, sizeof(vpd->bios_version));

    /* Until we found elements in the vpdtable, we consider them as not filled */
    vpd->filled = false;

    p = (char *)0xF0000;	/* The start address to look at the dmi table */
    for (q = p; q < p + 0x10000; q += 4) {
	memcpy(buf, q, 5);
	if (memcmp(buf, "\252\125VPD", 5) == 0) {
	    snprintf(vpd->base_address, sizeof(vpd->base_address), "%p", q);
	    if (q[5] < 0x30)
		return -ENOVPDTABLE;

	    vpd->filled = true;
	    /* XSeries have longer records, exact length seems to vary. */
	    if (!(q[5] >= 0x45 && vpd_checksum(q, q[5]))
		/* Some Netvista seem to work with this. */
		&& !(vpd_checksum(q, 0x30))
		/* The Thinkpad/Thinkcentre checksum does *not* include the first 13 bytes. */
		&& !(vpd_checksum(q + 0x0D, 0x30 - 0x0D))) {
		/* A few systems have a bad checksum (xSeries 325, 330, 335
		   and 345 with early BIOS) but the record is otherwise
		   valid. */
		printf("VPD: Bad checksum!\n");
	    }

	    strlcpy(vpd->bios_build_id, q + 0x0D, 9);
	    strlcpy(vpd->box_serial_number, q + 0x16, 7);
	    strlcpy(vpd->motherboard_serial_number, q + 0x1D, 11);
	    strlcpy(vpd->machine_type_model, q + 0x28, 7);

	    if (q[5] < 0x44)
		return VPD_TABLE_PRESENT;

	    strlcpy(vpd->bios_release_date, q + 0x30, 8);
	    strlcpy(vpd->default_flash_filename, q + 0x38, 12);

	    if (q[5] >= 0x46 && q[0x44] != 0x00) {
		strlcpy(vpd->bios_version, q + 0x44, 255);
	    }

	    return VPD_TABLE_PRESENT;
	}
    }
    return -ENOVPDTABLE;
}
