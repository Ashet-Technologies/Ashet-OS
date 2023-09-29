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
#include <dprintf.h>
#include "acpi/acpi.h"

void parse_ecdt(s_ecdt * e)
{
    uint8_t *q;
    q = (uint8_t *)e->address;
    q += ACPI_HEADER_SIZE;

    /* Copying remaining structs */
    cp_struct(&e->ec_control);
    cp_struct(&e->ec_data);
    cp_struct(&e->uid);
    cp_struct(&e->gpe_bit);

    /* Searching ec_id size we must copy */
    uint32_t ec_id_size = e->header.length - EC_ID_OFFSET;
    if ((e->ec_id = malloc(ec_id_size)) != NULL) {
	memcpy(e->ec_id, (uint64_t *) (e->address + EC_ID_OFFSET), ec_id_size);
    }
}
