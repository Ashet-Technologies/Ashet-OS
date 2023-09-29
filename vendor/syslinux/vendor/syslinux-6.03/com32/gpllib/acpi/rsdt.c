/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009-2011 Erwan Velu - All Rights Reserved
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
#include <stdlib.h>
#include <string.h>
#include <memory.h>
#include <dprintf.h>
#include "acpi/acpi.h"

int parse_rsdt(s_rsdt *r)
{
    /* Let's seach for RSDT table */
    uint8_t *q;

    /* Let's start for the base address */
    q = r->address;

    DEBUG_PRINT(("Searching for RSDT at %p\n",q));
    /* Searching for MADT with APIC signature */
    if (memcmp(q, RSDT, sizeof(RSDT)-1) == 0) {
//        DEBUG_PRINT(("RSDT : %c %c %c %c\n",q[0], q[1], q[2], q[3]));
	r->valid = true;
	DEBUG_PRINT(("Before \n"));
	get_acpi_description_header(q, &r->header);
	DEBUG_PRINT(("RSDT table at %p found with %d bytes long with %d items\n",r->address, r->header.length,(r->header.length-ACPI_HEADER_SIZE)/4));

	uint32_t *start = (uint32_t *)r->address;
	start += (ACPI_HEADER_SIZE / 4);
	uint32_t *max = (uint32_t *)r->address;
	max += (r->header.length / 4);
	DEBUG_PRINT(("Searching starting at %p till %p\n",start,max));
	uint32_t *p;
	for (p = start ; p < max; p++) {
            /* Let's grab the pointed table header */
            char address[16] = { 0 };
            sprintf(address, "%x", *p);
            uint32_t *pointed_address = (uint32_t *)strtoul(address, NULL, 16);
	    r->entry[r->entry_count] = (uint8_t *)pointed_address;
	    DEBUG_PRINT(("%d : %p\n",r->entry_count, r->entry[r->entry_count]));
	    r->entry_count++;
	}
	return RSDT_TABLE_FOUND;
    }

    return -RSDT_TABLE_FOUND;
}
