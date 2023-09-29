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
#include "acpi/acpi.h"

/* M1PS flags have to be interpreted as strings */
char *flags_to_string(char *buffer, uint16_t flags)
{
    strcpy(buffer, "default");
    if ((flags & POLARITY_ACTIVE_HIGH) == POLARITY_ACTIVE_HIGH)
	strcpy(buffer, "high");
    else if ((flags & POLARITY_ACTIVE_LOW) == POLARITY_ACTIVE_LOW)
	strcpy(buffer, "low");
    if ((flags & TRIGGER_EDGE) == TRIGGER_EDGE)
	strncat(buffer, " edge", 5);
    else if ((flags & TRIGGER_LEVEL) == TRIGGER_LEVEL)
	strncat(buffer, " level", 6);
    else
	strncat(buffer, " default", 8);

    return buffer;
}

void dbg_printf(const char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
}

void init_acpi(s_acpi * acpi)
{
    memset(acpi, 0, sizeof(s_acpi));
}

int parse_acpi(s_acpi * acpi)
{
    int ret_val;
    init_acpi(acpi);

    /* Let's seach for RSDP table */
    if ((ret_val = search_rsdp(acpi)) != RSDP_TABLE_FOUND)
	return ret_val;

    /* Let's seach for RSDT table
     * That's not a big deal not having it, XSDT is far more relevant */
    parse_rsdt(&acpi->rsdt);
    if (parse_xsdt(acpi) != XSDT_TABLE_FOUND) {
	    DEBUG_PRINT(("XSDT Detection failed\n"));
	    for (int table=0; table <acpi->rsdt.entry_count; table++) {
		parse_header((uint64_t *)acpi->rsdt.entry[table],acpi);
	    }
    }
    return ACPI_FOUND;
}

void get_acpi_description_header(uint8_t * q, s_acpi_description_header * adh)
{
    cp_str_struct(adh->signature);
    cp_struct(&adh->length);
    cp_struct(&adh->revision);
    cp_struct(&adh->checksum);
    cp_str_struct(adh->oem_id);
    cp_str_struct(adh->oem_table_id);
    cp_struct(&adh->oem_revision);
    cp_str_struct(adh->creator_id);
    cp_struct(&adh->creator_revision);
    DEBUG_PRINT(("acpi_header at %p = %s | %s | %s\n", q, adh->signature,adh->oem_id, adh->creator_id ));
}

bool parse_header(uint64_t *address, s_acpi *acpi) {
	    s_acpi_description_header adh;
	    memset(&adh, 0, sizeof(adh));

	    get_acpi_description_header((uint8_t *)address, &adh);

	    /* Trying to determine the pointed table */
	    /* Looking for FADT */
	    if (memcmp(adh.signature, FACP, sizeof(FACP) - 1) == 0) {
		DEBUG_PRINT(("FACP table found\n"));
		s_fadt *f = &acpi->fadt;
		s_facs *fa = &acpi->facs;
		s_dsdt *d = &acpi->dsdt;
		/* This structure is valid, let's fill it */
		f->valid = true;
		f->address = address;
		memcpy(&f->header, &adh, sizeof(adh));
		parse_fadt(f);

		/* FACS wasn't already detected
		 * FADT points to it, let's try to detect it */
		if (fa->valid == false) {
		    fa->address = (uint64_t *)f->x_firmware_ctrl;
		    parse_facs(fa);
		    if (fa->valid == false) {
			/* Let's try again */
			fa->address = (uint64_t *)f->firmware_ctrl;
			parse_facs(fa);
		    }
		}

		/* DSDT wasn't already detected
		 * FADT points to it, let's try to detect it */
		if (d->valid == false) {
		    s_acpi_description_header new_adh;
		    get_acpi_description_header((uint8_t *)f->x_dsdt,
						&new_adh);
		    if (memcmp(new_adh.signature, DSDT, sizeof(DSDT) - 1) == 0) {
			DEBUG_PRINT(("DSDT table found via x_dsdt\n"));
			d->valid = true;
			d->address = (uint64_t *)f->x_dsdt;
			memcpy(&d->header, &new_adh, sizeof(new_adh));
			parse_dsdt(d);
		    } else {
			/* Let's try again */
			get_acpi_description_header((uint8_t *)f->dsdt_address,
						    &new_adh);
			if (memcmp(new_adh.signature, DSDT, sizeof(DSDT) - 1) ==
			    0) {
			    DEBUG_PRINT(("DSDT table found via dsdt_address\n"));
			    d->valid = true;
			    d->address = (uint64_t *)f->dsdt_address;
			    memcpy(&d->header, &new_adh, sizeof(new_adh));
			    parse_dsdt(d);
			}
		    }
		}
	    } /* Looking for MADT */
	    else if (memcmp(adh.signature, APIC, sizeof(APIC) - 1) == 0) {
		DEBUG_PRINT(("MADT table found\n"));
		s_madt *m = &acpi->madt;
		/* This structure is valid, let's fill it */
		m->valid = true;
		m->address =address;
		memcpy(&m->header, &adh, sizeof(adh));
		parse_madt(acpi);
	    } else if (memcmp(adh.signature, DSDT, sizeof(DSDT) - 1) == 0) {
		DEBUG_PRINT(("DSDT table found\n"));
		s_dsdt *d = &acpi->dsdt;
		/* This structure is valid, let's fill it */
		d->valid = true;
		d->address = address;
		memcpy(&d->header, &adh, sizeof(adh));
		parse_dsdt(d);
		/* PSDT have to be considered as SSDT. Intel ACPI Spec @ 5.2.11.3 */
	    } else if ((memcmp(adh.signature, SSDT, sizeof(SSDT) - 1) == 0)
		       || (memcmp(adh.signature, PSDT, sizeof(PSDT) - 1) == 0)) {
		
		DEBUG_PRINT(("SSDT table found with %s \n",adh.signature));

		if ((acpi->ssdt_count >= MAX_SSDT - 1))
		    return false;

		/* We can have many SSDT, so let's allocate a new one */
		if ((acpi->ssdt[acpi->ssdt_count] =
		     malloc(sizeof(s_ssdt))) == NULL)
		    return false;
		s_ssdt *s = acpi->ssdt[acpi->ssdt_count];

		/* This structure is valid, let's fill it */
		s->valid = true;
		s->address = address;
		memcpy(&s->header, &adh, sizeof(adh));

		/* Searching how much definition blocks we must copy */
		uint32_t definition_block_size = adh.length - ACPI_HEADER_SIZE;
		if ((s->definition_block =
		     malloc(definition_block_size)) != NULL) {
		    memcpy(s->definition_block,
			   (s->address + ACPI_HEADER_SIZE),
			   definition_block_size);
		}
		/* Increment the number of ssdt we have */
		acpi->ssdt_count++;
	    } else if (memcmp(adh.signature, SBST, sizeof(SBST) - 1) == 0) {
		DEBUG_PRINT(("SBST table found\n"));
		s_sbst *s = &acpi->sbst;
		/* This structure is valid, let's fill it */
		s->valid = true;
		s->address = address;
		memcpy(&s->header, &adh, sizeof(adh));
		parse_sbst(s);
	    } else if (memcmp(adh.signature, ECDT, sizeof(ECDT) - 1) == 0) {
		DEBUG_PRINT(("ECDT table found\n"));
		s_ecdt *e = &acpi->ecdt;
		/* This structure is valid, let's fill it */
		e->valid = true;
		e->address = address;
		memcpy(&e->header, &adh, sizeof(adh));
		parse_ecdt(e);
	    }  else if (memcmp(adh.signature, HPET, sizeof(HPET) - 1) == 0) {
		DEBUG_PRINT(("HPET table found\n"));
		s_hpet *h = &acpi->hpet;
		/* This structure is valid, let's fill it */
		h->valid = true;
		h->address = address;
		memcpy(&h->header, &adh, sizeof(adh));
	    } else if (memcmp(adh.signature, TCPA, sizeof(TCPA) - 1) == 0) {
		DEBUG_PRINT(("TCPA table found\n"));
		s_tcpa *t = &acpi->tcpa;
		/* This structure is valid, let's fill it */
		t->valid = true;
		t->address = address;
		memcpy(&t->header, &adh, sizeof(adh));
	    } else if (memcmp(adh.signature, MCFG, sizeof(MCFG) - 1) == 0) {
		DEBUG_PRINT(("MCFG table found\n"));
		s_mcfg *m = &acpi->mcfg;
		/* This structure is valid, let's fill it */
		m->valid = true;
		m->address = address;
		memcpy(&m->header, &adh, sizeof(adh));
	    } else if (memcmp(adh.signature, SLIC, sizeof(SLIC) - 1) == 0) {
		DEBUG_PRINT(("SLIC table found\n"));
		s_slic *s = &acpi->slic;
		/* This structure is valid, let's fill it */
		s->valid = true;
		s->address = address;
		memcpy(&s->header, &adh, sizeof(adh));
	    } else if (memcmp(adh.signature, BOOT, sizeof(BOOT) - 1) == 0) {
		DEBUG_PRINT(("BOOT table found\n"));
		s_boot *b = &acpi->boot;
		/* This structure is valid, let's fill it */
		b->valid = true;
		b->address = address;
		memcpy(&b->header, &adh, sizeof(adh));
	    }
	    
	    return true;
}
