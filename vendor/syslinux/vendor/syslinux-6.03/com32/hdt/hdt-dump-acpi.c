/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Erwan Velu - All Rights Reserved
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

#include "hdt-common.h"
#include "hdt-dump.h"

void show_header(char *name, void *address, s_acpi_description_header *h, ZZJSON_CONFIG *config, ZZJSON **item)
{
	char signature[10]={0};
	char revision[10]={0};
	char s_address[16]={0};
	char oem_id[16]={0};
	char oem_table_id[16]={0};
	char oem_revision[16]={0};
	char creator_revision[16]={0};
	char creator_id[16]={0};
	snprintf(signature,sizeof(signature),"%s",h->signature);
	snprintf(revision,sizeof(revision),"0x%03x",h->revision);
	snprintf(oem_id,sizeof(oem_id),"%s",h->oem_id);
	snprintf(oem_table_id,sizeof(oem_table_id),"%s",h->oem_table_id);
	snprintf(creator_id,sizeof(creator_id),"%s",h->creator_id);
	snprintf(oem_revision,sizeof(oem_revision),"0x%08x",h->oem_revision);
	snprintf(creator_revision,sizeof(creator_revision),"0x%08x",h->creator_revision);
	snprintf(s_address,sizeof(s_address),"%p",address);

	char address_name[32]={0};
	char signature_name[32]={0};
	char revision_name[32]={0};
	char oem_id_name[32]={0};
	char oem_table_id_name[32]={0};
	char oem_revision_name[32]={0};
	char creator_revision_name[32]={0};
	char creator_id_name[32]={0};
	snprintf(signature_name,sizeof(signature_name),"acpi.%s.signature",name);
	snprintf(revision_name,sizeof(revision_name),"acpi.%s.revision",name);
	snprintf(address_name,sizeof(address_name),"acpi.%s.address",name);
	snprintf(oem_id_name,sizeof(oem_id_name),"acpi.%s.oem_id",name);
	snprintf(oem_table_id_name,sizeof(oem_table_id_name),"acpi.%s.oem_table_id",name);
	snprintf(oem_revision_name,sizeof(oem_revision_name),"acpi.%s.oem_revision",name);
	snprintf(creator_revision_name,sizeof(creator_revision_name),"acpi.%s.creator_revision",name);
	snprintf(creator_id_name,sizeof(creator_id_name),"acpi.%s.creator_id",name);

	APPEND_ARRAY
		add_as(signature_name,signature)
		add_as(revision_name,revision)
		add_as(oem_id_name,oem_id)
		add_as(oem_table_id_name,oem_table_id)
		add_as(oem_revision_name,oem_revision)
		add_as(creator_id_name,creator_id)
		add_as(creator_revision_name,creator_revision)
		add_as(address_name,s_address)
	END_OF_APPEND;

	FLUSH_OBJECT;

}

void dump_rsdt(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->rsdt.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","rsdt")
		add_as("acpi.rsdt.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->rsdt.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("rsdt",acpi->rsdt.address, &acpi->rsdt.header, config, item);	
}

void dump_xsdt(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->xsdt.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","xsdt")
		add_as("acpi.xsdt.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->xsdt.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("xsdt",acpi->xsdt.address, &acpi->xsdt.header, config, item);	
}

void dump_fadt(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->rsdt.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","fadt")
		add_as("acpi.fadt.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->fadt.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("fadt",acpi->fadt.address, &acpi->fadt.header, config, item);	
}

void dump_dsdt(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->dsdt.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","dsdt")
		add_as("acpi.dsdt.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->dsdt.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("dsdt",acpi->dsdt.address, &acpi->dsdt.header, config, item);	
}

void dump_sbst(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->sbst.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","sbst")
		add_as("acpi.sbst.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->sbst.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("sbst",acpi->sbst.address, &acpi->sbst.header, config, item);	
}

void dump_ecdt(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->ecdt.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","ecdt")
		add_as("acpi.ecdt.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->ecdt.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("ecdt",acpi->ecdt.address, &acpi->ecdt.header, config, item);	
}

void dump_hpet(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->hpet.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","hpet")
		add_as("acpi.hpet.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->hpet.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("hpet",acpi->hpet.address, &acpi->hpet.header, config, item);	
}

void dump_tcpa(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->tcpa.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","tcpa")
		add_as("acpi.tcpa.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->tcpa.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("tcpa",acpi->tcpa.address, &acpi->tcpa.header, config, item);	
}

void dump_mcfg(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->mcfg.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","mcfg")
		add_as("acpi.mcfg.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->mcfg.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("mcfg",acpi->mcfg.address, &acpi->mcfg.header, config, item);	
}

void dump_slic(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->slic.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","slic")
		add_as("acpi.slic.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->slic.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("slic",acpi->slic.address, &acpi->slic.header, config, item);	
}


void dump_boot(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->boot.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","boot")
		add_as("acpi.boot.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->boot.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("boot",acpi->boot.address, &acpi->boot.header, config, item);	
}

void dump_madt(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->madt.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","madt")
		add_as("acpi.madt.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->madt.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("madt",acpi->madt.address, &acpi->madt.header, config, item);	
}

void dump_ssdt(s_ssdt *ssdt, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (ssdt->valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","ssdt")
		add_as("acpi.ssdt.is_valid",valid)
	END_OF_ARRAY;
	
	if (ssdt->valid==false) {
		FLUSH_OBJECT;
		return;
	}

	show_header("ssdt",ssdt->address, &ssdt->header, config, item);	
}

void dump_rsdp(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->rsdp.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","rsdp")
		add_as("acpi.rsdp.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->rsdp.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	s_rsdp *r = &acpi->rsdp;
	char revision[10]={0};
	char address[16]={0};
	char oem_id[16]={0};
	snprintf(revision,sizeof(revision),"0x%03x",r->revision);
	snprintf(address,sizeof(address),"%p",r->address);
	snprintf(oem_id,sizeof(oem_id),"%s",r->oem_id);
	APPEND_ARRAY
		add_as("acpi.rsdp.revision",revision)
		add_as("acpi.rsdp.oem_id",oem_id)
		add_as("acpi.rsdp.address",address)
	END_OF_APPEND;

	FLUSH_OBJECT;

}

void dump_facs(s_acpi * acpi, ZZJSON_CONFIG * config, ZZJSON ** item)
{
	char valid[8]={0};
	snprintf(valid,sizeof(valid),"%s","false");
	if (acpi->facs.valid) {
		snprintf(valid,sizeof(valid),"%s","true");
	}
	CREATE_ARRAY
		add_as("acpi.item","facs")
		add_as("acpi.facs.is_valid",valid)
	END_OF_ARRAY;
	
	if (acpi->facs.valid==false) {
		FLUSH_OBJECT;
		return;
	}

	s_facs *fa = &acpi->facs;
	char address[16]={0};
	snprintf(address,sizeof(address),"%p",fa->address);
	APPEND_ARRAY
		add_as("acpi.facs.address",address)
	END_OF_APPEND;

	FLUSH_OBJECT;

}

void dump_interrupt_source_override(s_madt * madt, ZZJSON_CONFIG * config, ZZJSON ** item)
{
    CREATE_ARRAY
	add_as("acpi.item","interrupt_source_override")
    	add_ai("acpi.interrupt_source_override.count", madt->interrupt_source_override_count)
    END_OF_ARRAY;

    if (madt->interrupt_source_override_count == 0) {
    	    FLUSH_OBJECT;
	    return;
    }

    /* Let's process each interrupt source override */
    for (int i = 0; i < madt->interrupt_source_override_count; i++) {
	s_interrupt_source_override *siso = &madt->interrupt_source_override[i];
	char buffer[20] = {0};
	char bus_type[10]= {0};
	
	/* Spec report bus type 0 as ISA */
	if (siso->bus == 0)
	    strcpy(bus_type, "ISA");
	else
	    strcpy(bus_type, "unknown");

	APPEND_ARRAY
		add_as("acpi.interrupt_source_override.bus_type",bus_type)
		add_ai("acpi.interrupt_source_override.bus",siso->bus)
		add_ai("acpi.interrupt_source_override.bus_irq",siso->source)
		add_ai("acpi.interrupt_source_override.global_irq",siso->global_system_interrupt)
		add_as("acpi.interrupt_source_override.flags",flags_to_string(buffer,siso->flags))
	END_OF_APPEND;
    }
    FLUSH_OBJECT;
}

void dump_io_apic(s_madt * madt, ZZJSON_CONFIG * config, ZZJSON ** item)
{
    CREATE_ARRAY
	add_as("acpi.item","io_apic")
    	add_ai("acpi.io_apic.count", madt->io_apic_count)
    END_OF_ARRAY;

    if (madt->io_apic_count == 0) {
    	    FLUSH_OBJECT;
	    return;
    }

    /* For all IO APICS */
    for (int i = 0; i < madt->io_apic_count; i++) {
	s_io_apic *sio = &madt->io_apic[i];
	char buffer[15]={0};
	memset(buffer, 0, sizeof(buffer));
	/* GSI base reports the GSI configuration
	 * Let's interpret it as string */
	switch (sio->global_system_interrupt_base) {
	case 0:
	    strcpy(buffer, "0-23");
	    break;
	case 24:
	    strcpy(buffer,"24-39");
	    break;
	case 40:
	    strcpy(buffer, "40-55");
	    break;
	default:
	    strcpy(buffer,"Unknown");
	    break;
	}

	char apic_id[16] = { 0 };
	char address[16] = { 0 };
	snprintf(apic_id,sizeof(apic_id),"0x%02x",sio->io_apic_id);
	snprintf(address,sizeof(address),"0x%08x",sio->io_apic_address);
	APPEND_ARRAY
		add_ai("acpi.io_apic.number",i)
		add_as("acpi.io_apic.apic_id",apic_id)
		add_as("acpi.io_apic.adress",address)
		add_as("acpi.io_apic.gsi",buffer)
	END_OF_APPEND;
    }
    FLUSH_OBJECT;
}

void dump_local_apic_nmi(s_madt * madt, ZZJSON_CONFIG * config, ZZJSON ** item)
{
    CREATE_ARRAY
	add_as("acpi.item","local_apic_nmi")
    	add_ai("acpi.local_apic_nmi.count", madt->local_apic_nmi_count)
    END_OF_ARRAY;

    if (madt->local_apic_nmi_count == 0) {
    	    FLUSH_OBJECT;
	    return;
    }

    for (int i = 0; i < madt->local_apic_nmi_count; i++) {
	s_local_apic_nmi *slan = &madt->local_apic_nmi[i];
	char buffer[20]={0};
	char acpi_id[16] = { 0 };
	char local_apic_lint[16] = { 0 };
	snprintf(acpi_id, sizeof(acpi_id), "0x%02x", slan->acpi_processor_id);
	snprintf(local_apic_lint, sizeof(local_apic_lint), "0x%02x", slan->local_apic_lint);
	APPEND_ARRAY
		add_as("acpi.processor_id", acpi_id)
		add_as("acpi.local_apic_nmi.flags", flags_to_string(buffer,slan->flags))
		add_as("acpi.local_apic_nmi.lint",local_apic_lint)
	END_OF_APPEND;
    }

    FLUSH_OBJECT;
}

void dump_local_apic(s_madt * madt, ZZJSON_CONFIG * config, ZZJSON ** item)
{
    char buffer[16] = { 0 };
    snprintf(buffer, sizeof(buffer), "0x%08x", madt->local_apic_address);

    CREATE_ARRAY
	add_as("acpi.item","local_apic")
    	add_as("acpi.local_apic.address", buffer)
    	add_ai("acpi.processor_local_apic.count", madt->processor_local_apic_count)
    END_OF_ARRAY;

    if (madt->processor_local_apic_count ==0) {
        FLUSH_OBJECT;
	return;
    }

    /* For all detected logical CPU */
    for (int i = 0; i < madt->processor_local_apic_count; i++) {
	s_processor_local_apic *sla = &madt->processor_local_apic[i];
	char lapic_status[16] = { 0 };
	char acpi_id[16] = { 0 };
	char apic_id[16] = { 0 };

	snprintf(lapic_status,sizeof(lapic_status),"%s","disabled");
	/* Let's check if the flags reports the cpu as enabled */
	if ((sla->flags & PROCESSOR_LOCAL_APIC_ENABLE) ==
	    PROCESSOR_LOCAL_APIC_ENABLE)
	    snprintf(lapic_status,sizeof(lapic_status),"%s","enabled");
	snprintf(acpi_id, sizeof(acpi_id), "0x%02x", sla->acpi_id);
	snprintf(apic_id, sizeof(apic_id), "0x%02x", sla->apic_id);
	APPEND_ARRAY
		add_ai("acpi.cpu.apic_id", sla->apic_id)
		add_as("acpi.cpu.apic_id (hex)", apic_id)
		add_as("acpi.cpu.acpi_id (hex)", acpi_id)
		add_as("acpi.lapic.enabled", lapic_status)
	END_OF_APPEND;
    }
    FLUSH_OBJECT;
}

void dump_acpi(struct s_hardware *hardware, ZZJSON_CONFIG * config,
	       ZZJSON ** item)
{
    CREATE_NEW_OBJECT;
    add_hb(is_acpi_valid);
    if (hardware->is_acpi_valid == false)
	goto exit;

    s_madt *madt = &hardware->acpi.madt;
    add_b("acpi.apic.detected", madt->valid);
    if (madt->valid == false) {
	goto exit;
    }

    FLUSH_OBJECT;

    dump_local_apic(madt, config, item);
    dump_local_apic_nmi(madt, config, item);
    dump_io_apic(madt, config, item);
    dump_interrupt_source_override(madt, config, item);

    dump_rsdp(&hardware->acpi,config,item);
    dump_rsdt(&hardware->acpi,config,item);
    dump_xsdt(&hardware->acpi,config,item);
    dump_fadt(&hardware->acpi,config,item);
    dump_dsdt(&hardware->acpi,config,item);
    dump_sbst(&hardware->acpi,config,item);
    dump_ecdt(&hardware->acpi,config,item);
    dump_hpet(&hardware->acpi,config,item);
    dump_tcpa(&hardware->acpi,config,item);
    dump_mcfg(&hardware->acpi,config,item);
    dump_slic(&hardware->acpi,config,item);
    dump_boot(&hardware->acpi,config,item);
    dump_madt(&hardware->acpi,config,item);
    for (int i = 0; i < hardware->acpi.ssdt_count; i++) {
            if ((hardware->acpi.ssdt[i] != NULL) && (hardware->acpi.ssdt[i]->valid))
		    dump_ssdt(hardware->acpi.ssdt[i], config, item);
    }
    dump_facs(&hardware->acpi,config,item);

exit:
    to_cpio("acpi");
}
