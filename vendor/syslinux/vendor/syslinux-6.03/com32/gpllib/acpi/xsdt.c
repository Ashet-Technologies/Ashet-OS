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
#include <string.h>
#include <memory.h>
#include <stdlib.h>
#include "acpi/acpi.h"

int parse_xsdt(s_acpi * acpi)
{
    /* Let's seach for XSDT table */
    uint8_t *q;

    /* Let's start for the base address */
    q = acpi->xsdt.address;

    /* If address is null return an error */
    if (q == 0 ) {
	DEBUG_PRINT(("XSDT is null, exiting\n"));
    	return -XSDT_TABLE_FOUND;
    }

    DEBUG_PRINT(("Searching XSDT at %p",q));
    /* Searching for MADT with APIC signature */
    if (memcmp(q, XSDT, sizeof(XSDT) - 1) == 0) {
	s_xsdt *x = &acpi->xsdt;
	x->valid = true;
	get_acpi_description_header(q, &x->header);
	DEBUG_PRINT(("XSDT table found at %p : length=%d\n",x->address,x->header.length));
	DEBUG_PRINT(("Expected Tables = %d\n",(x->header.length-ACPI_HEADER_SIZE)/8));

	/* We now have a set of pointers to some tables */
	uint64_t *p = NULL;
	for (p = ((uint64_t *)(x->address + ACPI_HEADER_SIZE));
	     p < ((uint64_t *)(x->address + x->header.length)); p++) {
	    DEBUG_PRINT((" Looking for HEADER at %p = %x\n",p,*p));

	    /* Let's grab the pointed table header */
	    char address[16] = { 0 };
	    sprintf(address, "%llx", *p);
	    uint64_t *pointed_address = (uint64_t *)strtoul(address, NULL, 16);

	    x->entry[x->entry_count] = pointed_address;
	    if (parse_header(pointed_address, acpi)) {
		x->entry_count++;
	    }
	}
	return XSDT_TABLE_FOUND;
    }
    return -XSDT_TABLE_FOUND;
}
