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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

#include "hdt-cli.h"
#include "hdt-common.h"

static void show_dmi_modules(int argc __unused, char **argv __unused,
			     struct s_hardware *hardware)
{
    char available_dmi_commands[1024];
    reset_more_printf();
    memset(available_dmi_commands, 0, sizeof(available_dmi_commands));

    more_printf("Available DMI modules on your system:\n");
    if (hardware->dmi.base_board.filled == true)
	more_printf("\t%s\n", CLI_DMI_BASE_BOARD);
    if (hardware->dmi.battery.filled == true)
	more_printf("\t%s\n", CLI_DMI_BATTERY);
    if (hardware->dmi.bios.filled == true)
	more_printf("\t%s\n", CLI_DMI_BIOS);
    if (hardware->dmi.chassis.filled == true)
	more_printf("\t%s\n", CLI_DMI_CHASSIS);
    for (int i = 0; i < hardware->dmi.memory_count; i++) {
	if (hardware->dmi.memory[i].filled == true) {
	    more_printf("\tbank <number>\n");
	    break;
	}
    }
    for (int i = 0; i < hardware->dmi.memory_module_count; i++) {
	if (hardware->dmi.memory_module[i].filled == true) {
	    more_printf("\tmodule <number>\n");
	    break;
	}
    }
    if (hardware->dmi.processor.filled == true)
	more_printf("\t%s\n", CLI_DMI_PROCESSOR);
    if (hardware->dmi.system.filled == true)
	more_printf("\t%s\n", CLI_DMI_SYSTEM);
    if (hardware->dmi.ipmi.filled == true)
	more_printf("\t%s\n", CLI_DMI_IPMI);
    if (hardware->dmi.cache_count)
	more_printf("\t%s\n", CLI_DMI_CACHE);
    if (strlen(hardware->dmi.oem_strings))
	more_printf("\t%s\n", CLI_DMI_OEM);
    if (hardware->dmi.hardware_security.filled)
	more_printf("\t%s\n", CLI_DMI_SECURITY);
}

static void show_dmi_base_board(int argc __unused, char **argv __unused,
				struct s_hardware *hardware)
{
    if (hardware->dmi.base_board.filled == false) {
	more_printf("base_board information not found on your system, see "
		    "`show list' to see which module is available.\n");
	return;
    }
    reset_more_printf();
    more_printf("Base board\n");
    more_printf(" Manufacturer : %s\n", hardware->dmi.base_board.manufacturer);
    more_printf(" Product Name : %s\n", hardware->dmi.base_board.product_name);
    more_printf(" Version      : %s\n", hardware->dmi.base_board.version);
    more_printf(" Serial       : %s\n", hardware->dmi.base_board.serial);
    more_printf(" Asset Tag    : %s\n", hardware->dmi.base_board.asset_tag);
    more_printf(" Location     : %s\n", hardware->dmi.base_board.location);
    more_printf(" Type         : %s\n", hardware->dmi.base_board.type);
    for (int i = 0; i < BASE_BOARD_NB_ELEMENTS; i++) {
	if (((bool *) (&hardware->dmi.base_board.features))[i] == true) {
	    more_printf(" %s\n", base_board_features_strings[i]);
	}
    }

    for (unsigned int i = 0;
	 i <
	 sizeof hardware->dmi.base_board.devices_information /
	 sizeof *hardware->dmi.base_board.devices_information; i++) {
	if (strlen(hardware->dmi.base_board.devices_information[i].type)) {
	    more_printf("On Board Device #%u Information\n", i)
		more_printf("  Type        : %s\n",
			    hardware->dmi.base_board.devices_information[i].
			    type);
	    more_printf("  Status      : %s\n",
			hardware->dmi.base_board.devices_information[i].
			status ? "Enabled" : "Disabled");
	    more_printf("  Description : %s\n",
			hardware->dmi.base_board.devices_information[i].
			description);
	}
    }
}

static void show_dmi_system(int argc __unused, char **argv __unused,
			    struct s_hardware *hardware)
{
    if (hardware->dmi.system.filled == false) {
	more_printf("system information not found on your system, see "
		    "`show list' to see which module is available.\n");
	return;
    }
    reset_more_printf();
    more_printf("System\n");
    more_printf(" Manufacturer : %s\n", hardware->dmi.system.manufacturer);
    more_printf(" Product Name : %s\n", hardware->dmi.system.product_name);
    more_printf(" Version      : %s\n", hardware->dmi.system.version);
    more_printf(" Serial       : %s\n", hardware->dmi.system.serial);
    more_printf(" UUID         : %s\n", hardware->dmi.system.uuid);
    more_printf(" Wakeup Type  : %s\n", hardware->dmi.system.wakeup_type);
    more_printf(" SKU Number   : %s\n", hardware->dmi.system.sku_number);
    more_printf(" Family       : %s\n", hardware->dmi.system.family);

    if (strlen(hardware->dmi.system.configuration_options)) {
	more_printf("System Configuration Options\n");
	more_printf("%s\n", hardware->dmi.system.configuration_options);
    }

    if (hardware->dmi.system.system_reset.filled) {
	more_printf("System Reset\n");
	more_printf("  Status               : %s\n",
		    (hardware->dmi.system.system_reset.
		     status ? "Enabled" : "Disabled"));
	more_printf("  Watchdog Timer       : %s\n",
		    (hardware->dmi.system.system_reset.
		     watchdog ? "Present" : "Not Present"));
	if (strlen(hardware->dmi.system.system_reset.boot_option))
	    more_printf("  Boot Option          : %s\n",
			hardware->dmi.system.system_reset.boot_option);
	if (strlen(hardware->dmi.system.system_reset.boot_option_on_limit))
	    more_printf("  Boot Option On Limit : %s\n",
			hardware->dmi.system.system_reset.boot_option_on_limit);
	if (strlen(hardware->dmi.system.system_reset.reset_count))
	    more_printf("  Reset Count          : %s\n",
			hardware->dmi.system.system_reset.reset_count);
	if (strlen(hardware->dmi.system.system_reset.reset_limit))
	    more_printf("  Reset Limit          : %s\n",
			hardware->dmi.system.system_reset.reset_limit);
	if (strlen(hardware->dmi.system.system_reset.timer_interval))
	    more_printf("  Timer Interval       : %s\n",
			hardware->dmi.system.system_reset.timer_interval);
	if (strlen(hardware->dmi.system.system_reset.timeout))
	    more_printf("  Timeout              : %s\n",
			hardware->dmi.system.system_reset.timeout);
    }

    more_printf("System Boot Information\n");
    more_printf(" Status       : %s\n",
		hardware->dmi.system.system_boot_status);
}

static void show_dmi_bios(int argc __unused, char **argv __unused,
			  struct s_hardware *hardware)
{
    if (hardware->dmi.bios.filled == false) {
	more_printf("bios information not found on your system, see "
		    "`show list' to see which module is available.\n");
	return;
    }
    reset_more_printf();
    more_printf("BIOS\n");
    more_printf(" Vendor            : %s\n", hardware->dmi.bios.vendor);
    more_printf(" Version           : %s\n", hardware->dmi.bios.version);
    more_printf(" Release Date      : %s\n", hardware->dmi.bios.release_date);
    more_printf(" Bios Revision     : %s\n", hardware->dmi.bios.bios_revision);
    if (strlen(hardware->dmi.bios.firmware_revision))
	more_printf(" Firmware Revision : %s\n",
		    hardware->dmi.bios.firmware_revision);
    more_printf(" Address           : 0x%04X0\n", hardware->dmi.bios.address);
    more_printf(" Runtime address   : %u %s\n",
		hardware->dmi.bios.runtime_size,
		hardware->dmi.bios.runtime_size_unit);
    more_printf(" Rom size          : %u %s\n", hardware->dmi.bios.rom_size,
		hardware->dmi.bios.rom_size_unit);

    for (int i = 0; i < BIOS_CHAR_NB_ELEMENTS; i++) {
	if (((bool *) (&hardware->dmi.bios.characteristics))[i] == true) {
	    more_printf(" %s\n", bios_charac_strings[i]);
	}
    }
    for (int i = 0; i < BIOS_CHAR_X1_NB_ELEMENTS; i++) {
	if (((bool *) (&hardware->dmi.bios.characteristics_x1))[i] == true) {
	    more_printf(" %s\n", bios_charac_x1_strings[i]);
	}
    }

    for (int i = 0; i < BIOS_CHAR_X2_NB_ELEMENTS; i++) {
	if (((bool *) (&hardware->dmi.bios.characteristics_x2))[i] == true) {
	    more_printf(" %s\n", bios_charac_x2_strings[i]);
	}
    }

}

static void show_dmi_chassis(int argc __unused, char **argv __unused,
			     struct s_hardware *hardware)
{
    if (hardware->dmi.chassis.filled == false) {
	more_printf("chassis information not found on your system, see "
		    "`show list' to see which module is available.\n");
	return;
    }
    reset_more_printf();
    more_printf("Chassis\n");
    more_printf(" Manufacturer       : %s\n",
		hardware->dmi.chassis.manufacturer);
    more_printf(" Type               : %s\n", hardware->dmi.chassis.type);
    more_printf(" Lock               : %s\n", hardware->dmi.chassis.lock);
    more_printf(" Version            : %s\n", hardware->dmi.chassis.version);
    more_printf(" Serial             : %s\n", hardware->dmi.chassis.serial);
    more_printf(" Asset Tag          : %s\n",
		del_multi_spaces(hardware->dmi.chassis.asset_tag));
    more_printf(" Boot up state      : %s\n",
		hardware->dmi.chassis.boot_up_state);
    more_printf(" Power supply state : %s\n",
		hardware->dmi.chassis.power_supply_state);
    more_printf(" Thermal state      : %s\n",
		hardware->dmi.chassis.thermal_state);
    more_printf(" Security Status    : %s\n",
		hardware->dmi.chassis.security_status);
    more_printf(" OEM Information    : %s\n",
		hardware->dmi.chassis.oem_information);
    more_printf(" Height             : %u\n", hardware->dmi.chassis.height);
    more_printf(" NB Power Cords     : %u\n",
		hardware->dmi.chassis.nb_power_cords);
}

static void show_dmi_ipmi(int argc __unused, char **argv __unused,
			  struct s_hardware *hardware)
{
    if (hardware->dmi.ipmi.filled == false) {
	more_printf("IPMI module not available\n");
	return;
    }
    reset_more_printf();
    more_printf("IPMI\n");
    more_printf(" Interface Type     : %s\n",
		hardware->dmi.ipmi.interface_type);
    more_printf(" Specification Ver. : %u.%u\n",
		hardware->dmi.ipmi.major_specification_version,
		hardware->dmi.ipmi.minor_specification_version);
    more_printf(" I2C Slave Address  : 0x%02x\n",
		hardware->dmi.ipmi.I2C_slave_address);
    more_printf(" Nv Storage Address : %u\n", hardware->dmi.ipmi.nv_address);
    uint32_t high = hardware->dmi.ipmi.base_address >> 32;
    uint32_t low = hardware->dmi.ipmi.base_address & 0xFFFF;
    more_printf(" Base Address       : %08X%08X\n", high, (low & ~1));
    more_printf(" IRQ                : %d\n", hardware->dmi.ipmi.irq);
}

static void show_dmi_battery(int argc __unused, char **argv __unused,
			     struct s_hardware *hardware)
{
    if (hardware->dmi.battery.filled == false) {
	more_printf("battery information not found on your system, see "
		    "`show list' to see which module is available.\n");
	return;
    }
    reset_more_printf();
    more_printf("Battery \n");
    more_printf(" Vendor             : %s\n",
		hardware->dmi.battery.manufacturer);
    more_printf(" Manufacture Date   : %s\n",
		hardware->dmi.battery.manufacture_date);
    more_printf(" Serial             : %s\n", hardware->dmi.battery.serial);
    more_printf(" Name               : %s\n", hardware->dmi.battery.name);
    more_printf(" Chemistry          : %s\n", hardware->dmi.battery.chemistry);
    more_printf(" Design Capacity    : %s\n",
		hardware->dmi.battery.design_capacity);
    more_printf(" Design Voltage     : %s\n",
		hardware->dmi.battery.design_voltage);
    more_printf(" SBDS               : %s\n", hardware->dmi.battery.sbds);
    more_printf(" SBDS Manuf. Date   : %s\n",
		hardware->dmi.battery.sbds_manufacture_date);
    more_printf(" SBDS Chemistry     : %s\n",
		hardware->dmi.battery.sbds_chemistry);
    more_printf(" Maximum Error      : %s\n",
		hardware->dmi.battery.maximum_error);
    more_printf(" OEM Info           : %s\n", hardware->dmi.battery.oem_info);
}

static void show_dmi_cpu(int argc __unused, char **argv __unused,
			 struct s_hardware *hardware)
{
    if (hardware->dmi.processor.filled == false) {
	more_printf("processor information not found on your system, see "
		    "`show list' to see which module is available.\n");
	return;
    }
    reset_more_printf();
    more_printf("CPU\n");
    more_printf(" Socket Designation : %s\n",
		hardware->dmi.processor.socket_designation);
    more_printf(" Type               : %s\n", hardware->dmi.processor.type);
    more_printf(" Family             : %s\n", hardware->dmi.processor.family);
    more_printf(" Manufacturer       : %s\n",
		hardware->dmi.processor.manufacturer);
    more_printf(" Version            : %s\n", hardware->dmi.processor.version);
    more_printf(" External Clock     : %u\n",
		hardware->dmi.processor.external_clock);
    more_printf(" Max Speed          : %u\n",
		hardware->dmi.processor.max_speed);
    more_printf(" Current Speed      : %u\n",
		hardware->dmi.processor.current_speed);
    more_printf(" Cpu Type           : %u\n",
		hardware->dmi.processor.signature.type);
    more_printf(" Cpu Family         : %u\n",
		hardware->dmi.processor.signature.family);
    more_printf(" Cpu Model          : %u\n",
		hardware->dmi.processor.signature.model);
    more_printf(" Cpu Stepping       : %u\n",
		hardware->dmi.processor.signature.stepping);
    more_printf(" Cpu Minor Stepping : %u\n",
		hardware->dmi.processor.signature.minor_stepping);
    more_printf("Voltage             : %d.%02d\n",
                hardware->dmi.processor.voltage_mv / 1000,
                hardware->dmi.processor.voltage_mv -
                ((hardware->dmi.processor.voltage_mv / 1000) * 1000));
    more_printf(" Status             : %s\n", hardware->dmi.processor.status);
    more_printf(" Upgrade            : %s\n", hardware->dmi.processor.upgrade);
    more_printf(" Cache L1 Handle    : %s\n", hardware->dmi.processor.cache1);
    more_printf(" Cache L2 Handle    : %s\n", hardware->dmi.processor.cache2);
    more_printf(" Cache L3 Handle    : %s\n", hardware->dmi.processor.cache3);
    more_printf(" Serial             : %s\n", hardware->dmi.processor.serial);
    more_printf(" Part Number        : %s\n",
		hardware->dmi.processor.part_number);
    if (hardware->dmi.processor.core_count != 0)
        more_printf(" Cores Count        : %d\n", hardware->dmi.processor.core_count);
    if (hardware->dmi.processor.core_enabled != 0)
        more_printf(" Cores Enabled      : %d\n", hardware->dmi.processor.core_enabled);
    if (hardware->dmi.processor.thread_count != 0)
        more_printf(" Threads Count      : %d\n", hardware->dmi.processor.thread_count);

    more_printf(" ID                 : %s\n", hardware->dmi.processor.id);
    for (int i = 0; i < PROCESSOR_FLAGS_ELEMENTS; i++) {
	if (((bool *) (&hardware->dmi.processor.cpu_flags))[i] == true) {
	    more_printf(" %s\n", cpu_flags_strings[i]);
	}
    }
}

void show_dmi_memory_bank(int argc, char **argv, struct s_hardware *hardware)
{
    int bank = -1;

    /* Sanitize arguments */
    if (argc > 0)
	bank = strtol(argv[0], (char **)NULL, 10);

    if (errno == ERANGE || bank < 0) {
	more_printf("This bank number is incorrect\n");
	return;
    }

    if ((bank >= hardware->dmi.memory_count) || (bank < 0)) {
	more_printf("Bank %d number doesn't exist\n", bank);
	return;
    }
    if (hardware->dmi.memory[bank].filled == false) {
	more_printf("Bank %d doesn't contain any information\n", bank);
	return;
    }

    reset_more_printf();
    more_printf("Memory Bank %d\n", bank);
    more_printf(" Form Factor  : %s\n", hardware->dmi.memory[bank].form_factor);
    more_printf(" Type         : %s\n", hardware->dmi.memory[bank].type);
    more_printf(" Type Detail  : %s\n", hardware->dmi.memory[bank].type_detail);
    more_printf(" Speed        : %s\n", hardware->dmi.memory[bank].speed);
    more_printf(" Size         : %s\n", hardware->dmi.memory[bank].size);
    more_printf(" Device Set   : %s\n", hardware->dmi.memory[bank].device_set);
    more_printf(" Device Loc.  : %s\n",
		hardware->dmi.memory[bank].device_locator);
    more_printf(" Bank Locator : %s\n",
		hardware->dmi.memory[bank].bank_locator);
    more_printf(" Total Width  : %s\n", hardware->dmi.memory[bank].total_width);
    more_printf(" Data Width   : %s\n", hardware->dmi.memory[bank].data_width);
    more_printf(" Error        : %s\n", hardware->dmi.memory[bank].error);
    more_printf(" Vendor       : %s\n",
		hardware->dmi.memory[bank].manufacturer);
    more_printf(" Serial       : %s\n", hardware->dmi.memory[bank].serial);
    more_printf(" Asset Tag    : %s\n", hardware->dmi.memory[bank].asset_tag);
    more_printf(" Part Number  : %s\n", hardware->dmi.memory[bank].part_number);
}

static void show_dmi_cache(int argc, char **argv, struct s_hardware *hardware)
{
    if (!hardware->dmi.cache_count) {
	more_printf("cache information not found on your system, see "
		    "`show list' to see which module is available.\n");
	return;
    }

    int cache = strtol(argv[0], NULL, 10);

    if (argc != 1 || cache > hardware->dmi.cache_count) {
	more_printf("show cache [0-%d]\n", hardware->dmi.cache_count - 1);
	return;
    }

    reset_more_printf();

    more_printf("Cache Information #%d\n", cache);
    more_printf("  Socket Designation    : %s\n",
		hardware->dmi.cache[cache].socket_designation);
    more_printf("  Configuration         : %s\n",
		hardware->dmi.cache[cache].configuration);
    more_printf("  Operational Mode      : %s\n",
		hardware->dmi.cache[cache].mode);
    more_printf("  Location              : %s\n",
		hardware->dmi.cache[cache].location);
    more_printf("  Installed Size        : %u KB",
		hardware->dmi.cache[cache].installed_size);
    more_printf("\n");
    more_printf("  Maximum Size          : %u KB",
		hardware->dmi.cache[cache].max_size);
    more_printf("\n");
    more_printf("  Supported SRAM Types  : %s",
		hardware->dmi.cache[cache].supported_sram_types);
    more_printf("\n");
    more_printf("  Installed SRAM Type   : %s",
		hardware->dmi.cache[cache].installed_sram_types);
    more_printf("\n");
    more_printf("  Speed                 : %u ns",
		hardware->dmi.cache[cache].speed);
    more_printf("\n");
    more_printf("  Error Correction Type : %s\n",
		hardware->dmi.cache[cache].error_correction_type);
    more_printf("  System Type           : %s\n",
		hardware->dmi.cache[cache].system_type);
    more_printf("  Associativity         : %s\n",
		hardware->dmi.cache[cache].associativity);
}

void show_dmi_memory_module(int argc, char **argv, struct s_hardware *hardware)
{
    int module = -1;

    /* Sanitize arguments */
    if (argc > 0)
	module = strtol(argv[0], (char **)NULL, 10);

    if (errno == ERANGE || module < 0) {
	more_printf("This module number is incorrect\n");
	return;
    }

    if ((module >= hardware->dmi.memory_module_count) || (module < 0)) {
	more_printf("Module number %d doesn't exist\n", module);
	return;
    }

    if (hardware->dmi.memory_module[module].filled == false) {
	more_printf("Module %d doesn't contain any information\n", module);
	return;
    }

    reset_more_printf();
    more_printf("Memory Module %d\n", module);
    more_printf(" Socket Designation : %s\n",
		hardware->dmi.memory_module[module].socket_designation);
    more_printf(" Bank Connections   : %s\n",
		hardware->dmi.memory_module[module].bank_connections);
    more_printf(" Current Speed      : %s\n",
		hardware->dmi.memory_module[module].speed);
    more_printf(" Type               : %s\n",
		hardware->dmi.memory_module[module].type);
    more_printf(" Installed Size     : %s\n",
		hardware->dmi.memory_module[module].installed_size);
    more_printf(" Enabled Size       : %s\n",
		hardware->dmi.memory_module[module].enabled_size);
    more_printf(" Error Status       : %s\n",
		hardware->dmi.memory_module[module].error_status);
}

void main_show_dmi(int argc __unused, char **argv __unused,
		   struct s_hardware *hardware)
{

    if (hardware->is_dmi_valid == false) {
	more_printf("No valid DMI table found, exiting.\n");
	return;
    }
    reset_more_printf();
    more_printf("DMI Table version %u.%u found\n",
		hardware->dmi.dmitable.major_version,
		hardware->dmi.dmitable.minor_version);

    show_dmi_modules(0, NULL, hardware);
}

void show_dmi_memory_modules(int argc __unused, char **argv __unused,
			     struct s_hardware *hardware)
{
    /* Do we have so display unpopulated banks ? */
    int show_free_banks = 1;

    more_printf("Memory Size   : %lu MB (%lu KB)\n",
		(hardware->detected_memory_size + (1 << 9)) >> 10,
		hardware->detected_memory_size);

    if ((hardware->dmi.memory_count <= 0)
	&& (hardware->dmi.memory_module_count <= 0)) {
	more_printf("No memory bank found\n");
	return;
    }

    /* Sanitize arguments */
    if (argc > 0) {
	/* When we display a summary, there is no need to show the unpopulated banks
	 * The first argv is set to define this behavior
	 */
	show_free_banks = strtol(argv[0], NULL, 10);
	if (errno == ERANGE || show_free_banks < 0 || show_free_banks > 1)
	    goto usage;
    }

    reset_more_printf();
    /* If type 17 is available */
    if (hardware->dmi.memory_count > 0) {
	char bank_number[255];
	more_printf("Memory Banks\n");
	for (int i = 0; i < hardware->dmi.memory_count; i++) {
	    if (hardware->dmi.memory[i].filled == true) {
		memset(bank_number, 0, sizeof(bank_number));
		snprintf(bank_number, sizeof(bank_number), "%d ", i);
		if (show_free_banks == false) {
		    if (strncmp(hardware->dmi.memory[i].size, "Free", 4))
			more_printf(" bank %02d      : %s %s@%s\n",
				    i, hardware->dmi.memory[i].size,
				    hardware->dmi.memory[i].type,
				    hardware->dmi.memory[i].speed);
		} else {
		    more_printf(" bank %02d      : %s %s@%s\n", i,
				hardware->dmi.memory[i].size,
				hardware->dmi.memory[i].type,
				hardware->dmi.memory[i].speed);
		}
	    }
	}
    } else if (hardware->dmi.memory_module_count > 0) {
	/* Let's use type 6 as a fallback of type 17 */
	more_printf("Memory Modules\n");
	for (int i = 0; i < hardware->dmi.memory_module_count; i++) {
	    if (hardware->dmi.memory_module[i].filled == true) {
		more_printf(" module %02d    : %s %s@%s\n", i,
			    hardware->dmi.memory_module[i].enabled_size,
			    hardware->dmi.memory_module[i].type,
			    hardware->dmi.memory_module[i].speed);
	    }
	}
    }

    return;
    //printf("Type 'show bank<bank_number>' for more details.\n");

usage:
    more_printf("show memory <clear screen? <show free banks?>>\n");
    return;
}

void show_dmi_oem_strings(int argc __unused, char **argv __unused,
			  struct s_hardware *hardware)
{
    reset_more_printf();

    if (strlen(hardware->dmi.oem_strings))
	more_printf("OEM Strings\n%s", hardware->dmi.oem_strings);
}

void show_dmi_hardware_security(int argc __unused, char **argv __unused,
				struct s_hardware *hardware)
{
    reset_more_printf();

    if (!hardware->dmi.hardware_security.filled)
	return;

    more_printf("Hardware Security\n");
    more_printf("  Power-On Password Status      : %s\n",
		hardware->dmi.hardware_security.power_on_passwd_status);
    more_printf("  Keyboard Password Status      : %s\n",
		hardware->dmi.hardware_security.keyboard_passwd_status);
    more_printf("  Administrator Password Status : %s\n",
		hardware->dmi.hardware_security.administrator_passwd_status);
    more_printf("  Front Panel Reset Status      : %s\n",
		hardware->dmi.hardware_security.front_panel_reset_status);
}

struct cli_callback_descr list_dmi_show_modules[] = {
    {
     .name = CLI_DMI_BASE_BOARD,
     .exec = show_dmi_base_board,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_BIOS,
     .exec = show_dmi_bios,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_BATTERY,
     .exec = show_dmi_battery,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_CHASSIS,
     .exec = show_dmi_chassis,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_MEMORY,
     .exec = show_dmi_memory_modules,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_MEMORY_BANK,
     .exec = show_dmi_memory_bank,
     .nomodule = false,
     },
    {
     .name = "module",
     .exec = show_dmi_memory_module,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_PROCESSOR,
     .exec = show_dmi_cpu,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_SYSTEM,
     .exec = show_dmi_system,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_OEM,
     .exec = show_dmi_oem_strings,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_SECURITY,
     .exec = show_dmi_hardware_security,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_IPMI,
     .exec = show_dmi_ipmi,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_CACHE,
     .exec = show_dmi_cache,
     .nomodule = false,
     },
    {
     .name = CLI_DMI_LIST,
     .exec = show_dmi_modules,
     .nomodule = false,
     },
    {
     .name = NULL,
     .exec = NULL,
     .nomodule = false,
     },
};

struct cli_module_descr dmi_show_modules = {
    .modules = list_dmi_show_modules,
    .default_callback = main_show_dmi,
};

struct cli_mode_descr dmi_mode = {
    .mode = DMI_MODE,
    .name = CLI_DMI,
    .default_modules = NULL,
    .show_modules = &dmi_show_modules,
    .set_modules = NULL,
};
