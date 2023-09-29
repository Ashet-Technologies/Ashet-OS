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
#include <dprintf.h>
#include <stdlib.h>
#include "acpi/acpi.h"

/* Parse the apic structures */
static uint8_t *add_apic_structure(s_acpi * acpi, uint8_t * q)
{
    uint8_t type = *q;
    q++;
    uint8_t length = *q;
    q++;
    s_processor_local_apic *sla;
    s_io_apic *sio;
    s_interrupt_source_override *siso;
    s_nmi *snmi;
    s_local_apic_nmi *slan;
    s_local_apic_address_override *slaao;
    s_io_sapic *siosapic;
    s_local_sapic *sls;
    s_madt *madt = &acpi->madt;

    switch (type) {
    case PROCESSOR_LOCAL_APIC:
	sla = &madt->processor_local_apic[madt->processor_local_apic_count];
	sla->type = type;
	sla->length = length;
	cp_struct(&sla->acpi_id);
	cp_struct(&sla->apic_id);
	cp_struct(&sla->flags);
	madt->processor_local_apic_count++;
	break;
    case IO_APIC:
	sio = &madt->io_apic[madt->io_apic_count];
	sio->type = type;
	sio->length = length;
	cp_struct(&sio->io_apic_id);
	cp_struct(&sio->reserved);
	cp_struct(&sio->io_apic_address);
	cp_struct(&sio->global_system_interrupt_base);
	madt->io_apic_count++;
	break;
    case INTERRUPT_SOURCE_OVERRIDE:
	siso =
	    &madt->interrupt_source_override[madt->
					     interrupt_source_override_count];
	siso->type = type;
	siso->length = length;
	siso->bus = *q;
	q++;
	siso->source = *q;
	q++;
	cp_struct(&siso->global_system_interrupt);
	cp_struct(&siso->flags);
	madt->interrupt_source_override_count++;
	break;
    case NMI:
	snmi = &madt->nmi[madt->nmi_count];
	snmi->type = type;
	snmi->length = length;
	cp_struct(&snmi->flags);
	cp_struct(&snmi->global_system_interrupt);
	madt->nmi_count++;
	break;
    case LOCAL_APIC_NMI_STRUCTURE:
	slan = &madt->local_apic_nmi[madt->local_apic_nmi_count];
	slan->type = type;
	slan->length = length;
	cp_struct(&slan->acpi_processor_id);
	cp_struct(&slan->flags);
	cp_struct(&slan->local_apic_lint);
	madt->local_apic_nmi_count++;
	break;
    case LOCAL_APIC_ADDRESS_OVERRIDE_STRUCTURE:
	slaao =
	    &madt->local_apic_address_override[madt->
					       local_apic_address_override_count];
	slaao->type = type;
	slaao->length = length;
	cp_struct(&slaao->reserved);
	cp_struct(&slaao->local_apic_address);
	madt->local_apic_address_override_count++;
	break;
    case IO_SAPIC:
	siosapic = &madt->io_sapic[madt->io_sapic_count];
	siosapic->type = type;
	siosapic->length = length;
	cp_struct(&siosapic->io_apic_id);
	cp_struct(&siosapic->reserved);
	cp_struct(&siosapic->global_system_interrupt_base);
	cp_struct(&siosapic->io_sapic_address);
	madt->io_sapic_count++;
	break;
    case LOCAL_SAPIC:
	sls = &madt->local_sapic[madt->local_sapic_count];
	sls->type = type;
	sls->length = length;
	cp_struct(&sls->acpi_processor_id);
	cp_struct(&sls->local_sapic_id);
	cp_struct(&sls->local_sapic_eid);
	cp_struct(sls->reserved);
	cp_struct(&sls->flags);
	cp_struct(&sls->acpi_processor_uid_value);
	if ((sls->acpi_processor_uid_string =
	     malloc(length - ACPI_PROCESSOR_UID_STRING_OFFSET)) != NULL) {
	    memcpy(sls->acpi_processor_uid_string, q,
		   length - ACPI_PROCESSOR_UID_STRING_OFFSET);
	    q += length - ACPI_PROCESSOR_UID_STRING_OFFSET;
	}
	madt->local_sapic_count++;
	break;
    default:
	printf("Unkown APIC structure type %u, size=%u \n", type, length);
	q += length - 2;
	break;
    }
    return q;
}

void parse_madt(s_acpi * acpi)
{
    /* Let's seach for FADT table */
    uint8_t *q, *max_address;
    s_madt *m = &acpi->madt;

    /* Fixing table name */
    memcpy(m->header.signature, APIC, sizeof(APIC));

    /* Copying remaining structs */
    q = (uint8_t *)m->address;
    q += ACPI_HEADER_SIZE;
    
    max_address = (uint8_t *)m->address;
    max_address += m->header.length;

    cp_struct(&m->local_apic_address);
    cp_struct(&m->flags);

    while (q <  max_address) {
	q = add_apic_structure(acpi, q);
    }
}
