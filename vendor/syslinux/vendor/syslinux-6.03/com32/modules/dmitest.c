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

/*
 * dmitest.c
 *
 * DMI demo program using libcom32
 */

#include <string.h>
#include <stdio.h>
#include <console.h>
#include "dmi/dmi.h"

char display_line;

void display_memory(s_dmi * dmi)
{
    int i;
    for (i = 0; i < dmi->memory_count; i++) {
	moreprintf("Memory Bank %d\n", i);
	moreprintf("\tForm Factor  : %s\n", dmi->memory[i].form_factor);
	moreprintf("\tType         : %s\n", dmi->memory[i].type);
	moreprintf("\tType Detail  : %s\n", dmi->memory[i].type_detail);
	moreprintf("\tSpeed        : %s\n", dmi->memory[i].speed);
	moreprintf("\tSize         : %s\n", dmi->memory[i].size);
	moreprintf("\tDevice Set   : %s\n", dmi->memory[i].device_set);
	moreprintf("\tDevice Loc.  : %s\n", dmi->memory[i].device_locator);
	moreprintf("\tBank Locator : %s\n", dmi->memory[i].bank_locator);
	moreprintf("\tTotal Width  : %s\n", dmi->memory[i].total_width);
	moreprintf("\tData Width   : %s\n", dmi->memory[i].data_width);
	moreprintf("\tError        : %s\n", dmi->memory[i].error);
	moreprintf("\tVendor       : %s\n", dmi->memory[i].manufacturer);
	moreprintf("\tSerial       : %s\n", dmi->memory[i].serial);
	moreprintf("\tAsset Tag    : %s\n", dmi->memory[i].asset_tag);
	moreprintf("\tPart Number  : %s\n", dmi->memory[i].part_number);
    }
}

void display_battery(s_dmi * dmi)
{
    moreprintf("Battery\n");
    moreprintf("\tVendor              : %s\n", dmi->battery.manufacturer);
    moreprintf("\tManufacture Date    : %s\n", dmi->battery.manufacture_date);
    moreprintf("\tSerial              : %s\n", dmi->battery.serial);
    moreprintf("\tName                : %s\n", dmi->battery.name);
    moreprintf("\tChemistry           : %s\n", dmi->battery.chemistry);
    moreprintf("\tDesign Capacity     : %s\n", dmi->battery.design_capacity);
    moreprintf("\tDesign Voltage      : %s\n", dmi->battery.design_voltage);
    moreprintf("\tSBDS                : %s\n", dmi->battery.sbds);
    moreprintf("\tSBDS Manufact. Date : %s\n",
	       dmi->battery.sbds_manufacture_date);
    moreprintf("\tSBDS Chemistry      : %s\n", dmi->battery.sbds_chemistry);
    moreprintf("\tMaximum Error       : %s\n", dmi->battery.maximum_error);
    moreprintf("\tOEM Info            : %s\n", dmi->battery.oem_info);
}

void display_bios(s_dmi * dmi)
{
    moreprintf("BIOS\n");
    moreprintf("\tVendor:   %s\n", dmi->bios.vendor);
    moreprintf("\tVersion:  %s\n", dmi->bios.version);
    moreprintf("\tRelease:  %s\n", dmi->bios.release_date);
    moreprintf("\tBios Revision     %s\n", dmi->bios.bios_revision);
    moreprintf("\tFirmware Revision %s\n", dmi->bios.firmware_revision);
    moreprintf("\tAddress:  0x%04X0\n", dmi->bios.address);
    moreprintf("\tRuntime address: %u %s\n", dmi->bios.runtime_size,
	       dmi->bios.runtime_size_unit);
    moreprintf("\tRom size: %u %s\n", dmi->bios.rom_size,
	       dmi->bios.rom_size_unit);
    display_bios_characteristics(dmi);
}

void display_system(s_dmi * dmi)
{
    moreprintf("\nSystem\n");
    moreprintf("\tManufacturer %s\n", dmi->system.manufacturer);
    moreprintf("\tProduct Name %s\n", dmi->system.product_name);
    moreprintf("\tVersion      %s\n", dmi->system.version);
    moreprintf("\tSerial       %s\n", dmi->system.serial);
    moreprintf("\tUUID         %s\n", dmi->system.uuid);
    moreprintf("\tWakeup Type  %s\n", dmi->system.wakeup_type);
    moreprintf("\tSKU Number   %s\n", dmi->system.sku_number);
    moreprintf("\tFamily       %s\n", dmi->system.family);
}

void display_base_board(s_dmi * dmi)
{
    moreprintf("Base board\n");
    moreprintf("\tManufacturer %s\n", dmi->base_board.manufacturer);
    moreprintf("\tProduct Name %s\n", dmi->base_board.product_name);
    moreprintf("\tVersion      %s\n", dmi->base_board.version);
    moreprintf("\tSerial       %s\n", dmi->base_board.serial);
    moreprintf("\tAsset Tag    %s\n", dmi->base_board.asset_tag);
    moreprintf("\tLocation     %s\n", dmi->base_board.location);
    moreprintf("\tType         %s\n", dmi->base_board.type);
    display_base_board_features(dmi);
}

void display_chassis(s_dmi * dmi)
{
    moreprintf("\nChassis\n");
    moreprintf("\tManufacturer %s\n", dmi->chassis.manufacturer);
    moreprintf("\tType	   %s\n", dmi->chassis.type);
    moreprintf("\tLock	   %s\n", dmi->chassis.lock);
    moreprintf("\tVersion      %s\n", dmi->chassis.version);
    moreprintf("\tSerial       %s\n", dmi->chassis.serial);
    moreprintf("\tAsset Tag    %s\n", dmi->chassis.asset_tag);
    moreprintf("\tBoot up state %s\n", dmi->chassis.boot_up_state);
    moreprintf("\tPower supply state %s\n", dmi->chassis.power_supply_state);
    moreprintf("\tThermal state %s\n", dmi->chassis.thermal_state);
    moreprintf("\tSecurity Status    %s\n", dmi->chassis.security_status);
    moreprintf("\tOEM Information    %s\n", dmi->chassis.oem_information);
    moreprintf("\tHeight       %u\n", dmi->chassis.height);
    moreprintf("\tNB Power Cords     %u\n", dmi->chassis.nb_power_cords);
}

void display_cpu(s_dmi * dmi)
{
    moreprintf("\nCPU\n");
    moreprintf("\tSocket Designation %s\n", dmi->processor.socket_designation);
    moreprintf("\tType         %s\n", dmi->processor.type);
    moreprintf("\tFamily       %s\n", dmi->processor.family);
    moreprintf("\tManufacturer %s\n", dmi->processor.manufacturer);
    moreprintf("\tVersion      %s\n", dmi->processor.version);
    moreprintf("\tExternal Clock    %u\n", dmi->processor.external_clock);
    moreprintf("\tMax Speed         %u\n", dmi->processor.max_speed);
    moreprintf("\tCurrent Speed     %u\n", dmi->processor.current_speed);
    moreprintf("\tCpu Type     %u\n", dmi->processor.signature.type);
    moreprintf("\tCpu Family   %u\n", dmi->processor.signature.family);
    moreprintf("\tCpu Model    %u\n", dmi->processor.signature.model);
    moreprintf("\tCpu Stepping %u\n", dmi->processor.signature.stepping);
    moreprintf("\tCpu Minor Stepping %u\n",
	       dmi->processor.signature.minor_stepping);
    moreprintf("\tVoltage      %d mV\n", dmi->processor.voltage_mv);
    moreprintf("\tStatus       %s\n", dmi->processor.status);
    moreprintf("\tUpgrade      %s\n", dmi->processor.upgrade);
    moreprintf("\tCache L1 Handle %s\n", dmi->processor.cache1);
    moreprintf("\tCache L2 Handle %s\n", dmi->processor.cache2);
    moreprintf("\tCache L3 Handle %s\n", dmi->processor.cache3);
    moreprintf("\tSerial       %s\n", dmi->processor.serial);
    moreprintf("\tPart Number  %s\n", dmi->processor.part_number);
    if (dmi->processor.core_count != 0)
        moreprintf("\tCores Count   %d\n", dmi->processor.core_count);
    if (dmi->processor.core_enabled != 0)
        moreprintf("\tCores Enabled %d\n", dmi->processor.core_enabled);
    if (dmi->processor.thread_count != 0)
        moreprintf("\tThreads Count %d\n", dmi->processor.thread_count);
    moreprintf("\tID           %s\n", dmi->processor.id);
    display_processor_flags(dmi);
}

int main(void)
{
    char buffer[1024];
    s_dmi dmi;

    if (dmi_iterate(&dmi) == -ENODMITABLE) {
	printf("No DMI Structure found\n");
	return -1;
    } else {
	printf("DMI %u.%u present.\n", dmi.dmitable.major_version,
	       dmi.dmitable.minor_version);
	printf("%d structures occupying %d bytes.\n", dmi.dmitable.num,
	       dmi.dmitable.len);
	printf("DMI table at 0x%08X.\n", dmi.dmitable.base);
    }

    parse_dmitable(&dmi);

    for (;;) {
	printf
	    ("Available commands are system, chassis, base_board, cpu, bios, memory, battery, all, exit\n");
	printf("dmi: ");
	fgets(buffer, sizeof buffer, stdin);
	if (!strncmp(buffer, "exit", 4))
	    break;
	if (!strncmp(buffer, "system", 6))
	    display_system(&dmi);
	if (!strncmp(buffer, "chassis", 6))
	    display_chassis(&dmi);
	if (!strncmp(buffer, "base_board", 10))
	    display_base_board(&dmi);
	if (!strncmp(buffer, "cpu", 3))
	    display_cpu(&dmi);
	if (!strncmp(buffer, "bios", 4))
	    display_bios(&dmi);
	if (!strncmp(buffer, "memory", 6))
	    display_memory(&dmi);
	if (!strncmp(buffer, "battery", 7))
	    display_battery(&dmi);
	if (!strncmp(buffer, "all", 3)) {
	    display_bios(&dmi);
	    display_system(&dmi);
	    display_chassis(&dmi);
	    display_base_board(&dmi);
	    display_cpu(&dmi);
	    display_memory(&dmi);
	    display_battery(&dmi);
	}
    }

    return 0;
}
