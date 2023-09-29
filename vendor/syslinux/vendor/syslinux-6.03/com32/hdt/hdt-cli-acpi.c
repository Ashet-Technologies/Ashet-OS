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

#include "hdt-cli.h"
#include "hdt-common.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <acpi/acpi.h>

/* Print ACPI's table header in a defined formating */
static void show_header(void *address, s_acpi_description_header * h)
{
    more_printf("%-4s v%03x %-6s %-8s 0x%08x %-7s 0x%08x @ 0x%p\n",
		h->signature, h->revision, h->oem_id, h->oem_table_id,
		h->oem_revision, h->creator_id, h->creator_revision, address)
}

/* That's an helper to visualize columns*/
static void show_table_separator(void)
{
    more_printf
	("----|----|------|--------|----------|-------|-----------|--------------------\n");
}

/* Display the main header before displaying the ACPI tables */
static void show_table_name(void)
{
    more_printf
	("ACPI rev  oem    table_id oem_rev    creator creat_rev  @ address \n");
    show_table_separator();
}

/* called by "show acpi" */
void main_show_acpi(int argc __unused, char **argv __unused,
		    struct s_hardware *hardware)
{
    reset_more_printf();

    if (hardware->is_acpi_valid == false) {
	more_printf("No ACPI Tables detected\n");
	return;
    }

    show_table_name();

    /* RSDP tables aren't using the same headers as the other
     * So let's use a dedicated rendering */
    if (hardware->acpi.rsdp.valid) {
	s_rsdp *r = &hardware->acpi.rsdp;
	more_printf
	    ("RSDP v%03x %-6s                                        @ %p\n",
	     r->revision, r->oem_id, r->address);
    }

    if (hardware->acpi.rsdt.valid)
	show_header(hardware->acpi.rsdt.address,
		       &hardware->acpi.rsdt.header);

    if (hardware->acpi.xsdt.valid)
	show_header(hardware->acpi.xsdt.address,
		       &hardware->acpi.xsdt.header);

    if (hardware->acpi.fadt.valid)
	show_header(hardware->acpi.fadt.address, &hardware->acpi.fadt.header);

    if (hardware->acpi.dsdt.valid)
	show_header(hardware->acpi.dsdt.address, &hardware->acpi.dsdt.header);

    /* SSDT includes many optional tables, let's display them */
    for (int i = 0; i < hardware->acpi.ssdt_count; i++) {
	if ((hardware->acpi.ssdt[i] != NULL) && (hardware->acpi.ssdt[i]->valid))
	    show_header(hardware->acpi.ssdt[i]->address,
			&hardware->acpi.ssdt[i]->header);
    }

    if (hardware->acpi.sbst.valid)
	show_header(hardware->acpi.sbst.address, &hardware->acpi.sbst.header);

    if (hardware->acpi.ecdt.valid)
	show_header(hardware->acpi.ecdt.address, &hardware->acpi.ecdt.header);

    if (hardware->acpi.hpet.valid)
	show_header(hardware->acpi.hpet.address, &hardware->acpi.hpet.header);

    if (hardware->acpi.tcpa.valid)
	show_header(hardware->acpi.tcpa.address, &hardware->acpi.tcpa.header);

    if (hardware->acpi.mcfg.valid)
	show_header(hardware->acpi.mcfg.address, &hardware->acpi.mcfg.header);

    if (hardware->acpi.slic.valid)
	show_header(hardware->acpi.slic.address, &hardware->acpi.slic.header);

    if (hardware->acpi.boot.valid)
	show_header(hardware->acpi.boot.address, &hardware->acpi.boot.header);

    /* FACS isn't having the same headers, let's use a dedicated rendering */
    if (hardware->acpi.facs.valid) {
	s_facs *fa = &hardware->acpi.facs;
	more_printf
	    ("FACS                                                    @ 0x%p\n",
	     fa->address);
    }

    if (hardware->acpi.madt.valid)
	show_header(hardware->acpi.madt.address, &hardware->acpi.madt.header);

    more_printf("\nLocal APIC at 0x%08x\n", hardware->acpi.madt.local_apic_address);
}

/* Let's display the Processor Local APIC configuration */
static void show_local_apic(s_madt * madt)
{
    if (madt->processor_local_apic_count == 0) {
	more_printf("No Processor Local APIC found\n");
	return;
    }

    /* For all detected logical CPU */
    for (int i = 0; i < madt->processor_local_apic_count; i++) {
	s_processor_local_apic *sla = &madt->processor_local_apic[i];
	char buffer[8];
	memset(buffer, 0, sizeof(buffer));
	strcpy(buffer, "disable");
	/* Let's check if the flags reports the cpu as enabled */
	if ((sla->flags & PROCESSOR_LOCAL_APIC_ENABLE) ==
	    PROCESSOR_LOCAL_APIC_ENABLE)
	    strcpy(buffer, "enable");
	more_printf("CPU #%u, LAPIC (acpi_id[0x%02x] apic_id[0x%02x]) %s\n",
		    sla->apic_id, sla->acpi_id, sla->apic_id, buffer);
    }
}

/* Display the local apic NMI configuration */
static void show_local_apic_nmi(s_madt * madt)
{
    if (madt->local_apic_nmi_count == 0) {
	more_printf("No Local APIC NMI found\n");
	return;
    }

    for (int i = 0; i < madt->local_apic_nmi_count; i++) {
	s_local_apic_nmi *slan = &madt->local_apic_nmi[i];
	char buffer[20];
	more_printf("LAPIC_NMI (acpi_id[0x%02x] %s lint(0x%02x))\n",
		    slan->acpi_processor_id, flags_to_string(buffer,
							     slan->flags),
		    slan->local_apic_lint);
    }
}

/* Display the IO APIC configuration */
static void show_io_apic(s_madt * madt)
{
    if (madt->io_apic_count == 0) {
	more_printf("No IO APIC found\n");
	return;
    }

    /* For all IO APICS */
    for (int i = 0; i < madt->io_apic_count; i++) {
	s_io_apic *sio = &madt->io_apic[i];
	char buffer[15];
	memset(buffer, 0, sizeof(buffer));
	/* GSI base reports the GSI configuration
	 * Let's interpret it as string */
	switch (sio->global_system_interrupt_base) {
	case 0:
	    strcpy(buffer, "GSI 0-23");
	    break;
	case 24:
	    strcpy(buffer, "GSI 24-39");
	    break;
	case 40:
	    strcpy(buffer, "GSI 40-55");
	    break;
	default:
	    strcpy(buffer, "GSI Unknown");
	    break;
	}

	more_printf("IO_APIC[%d] : apic_id[0x%02x] address[0x%08x] %s\n",
		    i, sio->io_apic_id, sio->io_apic_address, buffer);
    }
}

/* Display the interrupt source override configuration */
static void show_interrupt_source_override(s_madt * madt)
{
    if (madt->interrupt_source_override_count == 0) {
	more_printf("No interrupt source override found\n");
	return;
    }

    /* Let's process each interrupt source override */
    for (int i = 0; i < madt->interrupt_source_override_count; i++) {
	s_interrupt_source_override *siso = &madt->interrupt_source_override[i];
	char buffer[20];
	char bus_type[10];
	memset(bus_type, 0, sizeof(bus_type));
	/* Spec report bus type 0 as ISA */
	if (siso->bus == 0)
	    strcpy(bus_type, "ISA");
	else
	    strcpy(bus_type, "unknown");

	more_printf("INT_SRC_OVR (bus %s (%d) bus_irq %d global_irq %d %s)\n",
		    bus_type, siso->bus, siso->source,
		    siso->global_system_interrupt, flags_to_string(buffer,
								   siso->
								   flags));
    }
}

/* Display the apic configuration
 * This is called by acpi> show apic */
static void show_acpi_apic(int argc __unused, char **argv __unused,
			   struct s_hardware *hardware)
{
    if (hardware->is_acpi_valid == false) {
	more_printf("No ACPI Tables detected\n");
	return;
    }

    s_madt *madt = &hardware->acpi.madt;

    if (madt->valid == false) {
	more_printf("No APIC (MADT) table found\n");
	return;
    }

    more_printf("Local APIC at 0x%08x\n", madt->local_apic_address);
    show_local_apic(madt);
    show_local_apic_nmi(madt);
    show_io_apic(madt);
    show_interrupt_source_override(madt);
}

struct cli_callback_descr list_acpi_show_modules[] = {
    {
     .name = "apic",
     .exec = show_acpi_apic,
     .nomodule = false,
     },
    {
     .name = NULL,
     .exec = NULL,
     .nomodule = false,
     },
};

struct cli_module_descr acpi_show_modules = {
    .modules = list_acpi_show_modules,
    .default_callback = main_show_acpi,
};

struct cli_mode_descr acpi_mode = {
    .mode = ACPI_MODE,
    .name = CLI_ACPI,
    .default_modules = NULL,
    .show_modules = &acpi_show_modules,
    .set_modules = NULL,
};
