/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Erwan Velu - All Rights Reserved
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

/*
 * vpdtest.c
 *
 * VPD demo program using libcom32
 */

#include <string.h>
#include <stdio.h>
#include <console.h>
#include "vpd/vpd.h"

int main(void)
{
    s_vpd vpd;

    if (vpd_decode(&vpd) == -ENOVPDTABLE) {
	printf("No VPD Structure found\n");
	return -1;
    } else {
	printf("VPD present at address : 0x%s\n", vpd.base_address);
    }
    if (strlen(vpd.bios_build_id) > 0)
	printf("Bios Build ID                 : %s\n", vpd.bios_build_id);
    if (strlen(vpd.bios_release_date) > 0)
	printf("Bios Release Date             : %s\n", vpd.bios_release_date);
    if (strlen(vpd.bios_version) > 0)
	printf("Bios Version                  : %s\n", vpd.bios_version);
    if (strlen(vpd.default_flash_filename) > 0)
	printf("Default Flash Filename        : %s\n",
	       vpd.default_flash_filename);
    if (strlen(vpd.box_serial_number) > 0)
	printf("Box Serial Number             : %s\n", vpd.box_serial_number);
    if (strlen(vpd.motherboard_serial_number) > 0)
	printf("Motherboard Serial Number     : %s\n",
	       vpd.motherboard_serial_number);
    if (strlen(vpd.machine_type_model) > 0)
	printf("Machine Type/Model            : %s\n", vpd.machine_type_model);

    return 0;
}
