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

void dump_hardware_security(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {
	if (!hardware->dmi.hardware_security.filled) {
			CREATE_NEW_OBJECT;
				add_s("dmi.warning","No hardware security structure found");
			FLUSH_OBJECT;
			return;
	}
	
	CREATE_NEW_OBJECT;
		add_s("dmi.item","hardware_security");
		add_hs(dmi.hardware_security.power_on_passwd_status);
		add_hs(dmi.hardware_security.keyboard_passwd_status);
		add_hs(dmi.hardware_security.administrator_passwd_status);
		add_hs(dmi.hardware_security.front_panel_reset_status);
	FLUSH_OBJECT;
}

void dump_oem_strings(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {
	if (strlen(hardware->dmi.oem_strings) == 0) {
			CREATE_NEW_OBJECT;
				add_s("dmi.warning","No OEM structure found");
			FLUSH_OBJECT;
			return;
	}
	CREATE_NEW_OBJECT;
		add_s("dmi.item","OEM");
		add_hs(dmi.oem_strings);
	FLUSH_OBJECT;
}

void dump_memory_size(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {
	CREATE_NEW_OBJECT;
		add_s("dmi.item","memory size");
		add_i("dmi.memory_size (KB)",hardware->detected_memory_size);
		add_i("dmi.memory_size (MB)",(hardware->detected_memory_size + (1 << 9)) >> 10);
	FLUSH_OBJECT;
}

void dump_memory_modules(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {

	if (hardware->dmi.memory_module_count == 0) {
			CREATE_NEW_OBJECT;
				add_s("dmi.warning","No memory module structure found");
			FLUSH_OBJECT;
			return;
	}

	for (int module=0; module<hardware->dmi.memory_module_count;module++) {
		if (hardware->dmi.memory_module[module].filled == false) {
			char msg[64]={0};
			snprintf(msg,sizeof(msg),"Module %d doesn't contain any information", module);

			CREATE_NEW_OBJECT;
				add_s("dmi.warning",msg);
			FLUSH_OBJECT;
			continue;
		}

		CREATE_NEW_OBJECT;
		add_i("Memory module", module);
		add_s("dmi.memory_module.socket_designation", hardware->dmi.memory_module[module].socket_designation);
		add_s("dmi.memory_module.bank_connections", hardware->dmi.memory_module[module].bank_connections);
		add_s("dmi.memory_module.speed", hardware->dmi.memory_module[module].speed);
		add_s("dmi.memory_module.type", hardware->dmi.memory_module[module].type);
		add_s("dmi.memory_module.installed_size", hardware->dmi.memory_module[module].installed_size);
		add_s("dmi.memory_module.enabled_size", hardware->dmi.memory_module[module].enabled_size);
		add_s("dmi.memory_module.error_status", hardware->dmi.memory_module[module].error_status);
		FLUSH_OBJECT;
	}
}
	
void dump_cache(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {

	if (hardware->dmi.cache_count == 0) {
			CREATE_NEW_OBJECT;
				add_s("dmi.warning","No cache structure found");
			FLUSH_OBJECT;
			return;
	}

	for (int cache=0; cache<hardware->dmi.cache_count;cache++) {
		CREATE_NEW_OBJECT;
		add_i("Cache", cache);
		add_s("dmi.cache.socket_designation", hardware->dmi.cache[cache].socket_designation);
		add_s("dmi.cache.configuration", hardware->dmi.cache[cache].configuration);
		add_s("dmi.cache.mode", hardware->dmi.cache[cache].mode);
		add_s("dmi.cache.location", hardware->dmi.cache[cache].location);
		add_i("dmi.cache.installed_size (KB)", hardware->dmi.cache[cache].installed_size);
		add_i("dmi.cache.max_size (KB)", hardware->dmi.cache[cache].max_size);
		add_s("dmi.cache.supported_sram_types", hardware->dmi.cache[cache].supported_sram_types);
		add_s("dmi.cache.installed_sram_types", hardware->dmi.cache[cache].installed_sram_types);
		add_i("dmi.cache.speed (ns)", hardware->dmi.cache[cache].speed);
		add_s("dmi.cache.error_correction_type", hardware->dmi.cache[cache].error_correction_type);
		add_s("dmi.cache.system_type", hardware->dmi.cache[cache].system_type);
		add_s("dmi.cache.associativity", hardware->dmi.cache[cache].associativity);
		FLUSH_OBJECT;
	}
}
void dump_memory_banks(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {

	if (hardware->dmi.memory_count == 0) {
			CREATE_NEW_OBJECT;
				add_s("dmi.warning","No memory bank structure found");
			FLUSH_OBJECT;
			return;
	}

	for (int bank=0; bank<hardware->dmi.memory_count;bank++) {

		if (hardware->dmi.memory[bank].filled == false) {
			char msg[64]={0};
			snprintf(msg,sizeof(msg),"Bank %d doesn't contain any information", bank);

			CREATE_NEW_OBJECT;
				add_s("dmi.warning",msg);
			FLUSH_OBJECT;
			continue;
		}

		CREATE_NEW_OBJECT;
		add_i("Memory Bank", bank);
		add_s("dmi.memory.form_factor", hardware->dmi.memory[bank].form_factor);
		add_s("dmi.memory.type", hardware->dmi.memory[bank].type);
		add_s("dmi.memory.type_detail", hardware->dmi.memory[bank].type_detail);
		add_s("dmi.memory.speed", hardware->dmi.memory[bank].speed);
		add_s("dmi.memory.size", hardware->dmi.memory[bank].size);
		add_s("dmi.memory.device_set", hardware->dmi.memory[bank].device_set);
		add_s("dmi.memory.device_locator", hardware->dmi.memory[bank].device_locator);
		add_s("dmi.memory.bank_locator", hardware->dmi.memory[bank].bank_locator);
		add_s("dmi.memory.total_width", hardware->dmi.memory[bank].total_width);
		add_s("dmi.memory.data_width", hardware->dmi.memory[bank].data_width);
		add_s("dmi.memory.error", hardware->dmi.memory[bank].error);
		add_s("dmi.memory.vendor", hardware->dmi.memory[bank].manufacturer);
		add_s("dmi.memory.serial", hardware->dmi.memory[bank].serial);
		add_s("dmi.memory.asset_tag", hardware->dmi.memory[bank].asset_tag);
		add_s("dmi.memory.part_number", hardware->dmi.memory[bank].part_number);
		FLUSH_OBJECT;
	}
}

void dump_processor(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {
	if (hardware->dmi.processor.filled == false) {
		CREATE_NEW_OBJECT;
			add_s("dmi.warning","no processor structure found");
		FLUSH_OBJECT;
		return;
	}

	char voltage[16]={0};
	snprintf(voltage,sizeof(voltage),"%d.%02d",
		hardware->dmi.processor.voltage_mv / 1000,
		hardware->dmi.processor.voltage_mv - ((hardware->dmi.processor.voltage_mv / 1000) * 1000));

	CREATE_NEW_OBJECT;
	add_s("dmi.item","processor");
	add_hs(dmi.processor.socket_designation);
	add_hs(dmi.processor.type);
	add_hs(dmi.processor.family);
	add_hs(dmi.processor.manufacturer);
	add_hs(dmi.processor.version);
	add_hi(dmi.processor.external_clock);
	add_hi(dmi.processor.max_speed);
	add_hi(dmi.processor.current_speed);
	add_hi(dmi.processor.signature.type);
	add_hi(dmi.processor.signature.family);
	add_hi(dmi.processor.signature.model);
	add_hi(dmi.processor.signature.stepping);
	add_hi(dmi.processor.signature.minor_stepping);
	add_s("dmi.processor.voltage",voltage);
	add_hs(dmi.processor.status);
	add_hs(dmi.processor.upgrade);
	add_hs(dmi.processor.cache1);
	add_hs(dmi.processor.cache2);
	add_hs(dmi.processor.cache3);
	add_hs(dmi.processor.serial);
	add_hs(dmi.processor.part_number);
	add_hi(dmi.processor.core_count);
	add_hi(dmi.processor.core_enabled);
	add_hi(dmi.processor.thread_count);
	add_hs(dmi.processor.id);
	for (int i = 0; i < PROCESSOR_FLAGS_ELEMENTS; i++) {
	        if (((bool *) (&hardware->dmi.processor.cpu_flags))[i] == true) {
	            add_s("dmi.processor.flag",(char *)cpu_flags_strings[i]);
		}
	}
	FLUSH_OBJECT;
}

void dump_battery(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {
	if (hardware->dmi.battery.filled == false) {
		CREATE_NEW_OBJECT;
			add_s("dmi.warning","no battery structure found");
		FLUSH_OBJECT;
		return;
	}

	CREATE_NEW_OBJECT;
	add_s("dmi.item","battery");
	add_hs(dmi.battery.manufacturer);
	add_hs(dmi.battery.manufacture_date);
	add_hs(dmi.battery.serial);
	add_hs(dmi.battery.name);
	add_hs(dmi.battery.chemistry);
	add_hs(dmi.battery.design_capacity);
	add_hs(dmi.battery.design_voltage);
	add_hs(dmi.battery.sbds);
	add_hs(dmi.battery.sbds_manufacture_date);
	add_hs(dmi.battery.sbds_chemistry);
	add_hs(dmi.battery.maximum_error);
	add_hs(dmi.battery.oem_info);
	FLUSH_OBJECT;
}

void dump_ipmi(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {
	if (hardware->dmi.ipmi.filled == false) {
		CREATE_NEW_OBJECT;
			add_s("dmi.warning","no IPMI structure found");
		FLUSH_OBJECT;
		return;
	}

	char spec_ver[16]={0};
	char i2c[16]={0};
	char base[16]={0};
	snprintf(spec_ver,sizeof(spec_ver),"%u.%u",
			hardware->dmi.ipmi.major_specification_version,
			hardware->dmi.ipmi.minor_specification_version);

	snprintf(i2c,sizeof(i2c),"0x%02x", hardware->dmi.ipmi.I2C_slave_address);
	snprintf(base,sizeof(base),"%08X%08X",
			(uint32_t)(hardware->dmi.ipmi.base_address >> 32),
			(uint32_t)((hardware->dmi.ipmi.base_address & 0xFFFF) & ~1));

	CREATE_NEW_OBJECT;
	add_s("dmi.item","ipmi");
	add_hs(dmi.ipmi.interface_type);
	add_s("dmi.ipmi.spec_version",spec_ver);
	add_hi(dmi.ipmi.I2C_slave_address);
	add_hi(dmi.ipmi.nv_address);
	add_s("dmi.ipmi.base_address",base);
	add_hi(dmi.ipmi.irq);
	FLUSH_OBJECT;
}

void dump_chassis(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {
	if (hardware->dmi.chassis.filled == false) {
		CREATE_NEW_OBJECT;
			add_s("dmi.warning","no chassis structure found");
		FLUSH_OBJECT;
		return;
	}

	CREATE_NEW_OBJECT;
	add_s("dmi.item","bios");
	add_hs(dmi.chassis.manufacturer);
	add_hs(dmi.chassis.type);
	add_hs(dmi.chassis.lock);
	add_hs(dmi.chassis.version);
	add_hs(dmi.chassis.serial);
	add_s("dmi.chassis.asset_tag",del_multi_spaces(hardware->dmi.chassis.asset_tag));
	add_hs(dmi.chassis.boot_up_state);
	add_hs(dmi.chassis.power_supply_state);
	add_hs(dmi.chassis.thermal_state);
	add_hs(dmi.chassis.security_status);
	add_hs(dmi.chassis.oem_information);
	add_hi(dmi.chassis.height);
	add_hi(dmi.chassis.nb_power_cords);
	FLUSH_OBJECT;
}

void dump_bios(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {
	if (hardware->dmi.bios.filled == false) {
		CREATE_NEW_OBJECT;
			add_s("dmi.warning","no bios structure found");
		FLUSH_OBJECT;
		return;
	}
	char address[16]={0};
	char runtime[16]={0};
	char rom[16]={0};
	snprintf(address,sizeof(address),"0x%04X0",hardware->dmi.bios.address);
	snprintf(runtime,sizeof(runtime),"%u %s",hardware->dmi.bios.runtime_size, hardware->dmi.bios.runtime_size_unit);
	snprintf(rom,sizeof(rom),"%u %s",hardware->dmi.bios.rom_size, hardware->dmi.bios.rom_size_unit);

	CREATE_NEW_OBJECT;
	add_s("dmi.item","bios");
	add_hs(dmi.bios.vendor);
	add_hs(dmi.bios.version);
	add_hs(dmi.bios.release_date);
	add_hs(dmi.bios.bios_revision);
	add_hs(dmi.bios.firmware_revision);
	add_s("dmi.bios.address",address);
	add_s("dmi.bios.runtime_size",runtime);
	add_s("dmi.bios.rom_size",rom);
	for (int i = 0; i < BIOS_CHAR_NB_ELEMENTS; i++) {
	        if (((bool *) (&hardware->dmi.bios.characteristics))[i] == true) {
			add_s("dmi.bios.characteristics",(char *)bios_charac_strings[i]);
		}
	}
	
	for (int i = 0; i < BIOS_CHAR_X1_NB_ELEMENTS; i++) {
	        if (((bool *) (&hardware->dmi.bios.characteristics_x1))[i] == true) {
			add_s("dmi.bios.characteristics",(char *)bios_charac_x1_strings[i]);
		}
	}

	for (int i = 0; i < BIOS_CHAR_X2_NB_ELEMENTS; i++) {
	        if (((bool *) (&hardware->dmi.bios.characteristics_x2))[i] == true) {
			add_s("dmi.bios.characteristics",(char *)bios_charac_x2_strings[i]);
		}
	}
	FLUSH_OBJECT;
}

void dump_system(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {

	if (hardware->dmi.system.filled == false) {
		CREATE_NEW_OBJECT;
			add_s("dmi.warning","no system structure found");
		FLUSH_OBJECT;
		return;
	}
	char system_reset_status[10]={0};
	char watchdog_timer[15]={0};
	snprintf(system_reset_status,sizeof(system_reset_status),"%s", (hardware->dmi.system.system_reset.status ? "Enabled" :"Disabled"));
	snprintf(watchdog_timer,sizeof(watchdog_timer),"%s", (hardware->dmi.system.system_reset.watchdog ? "Present" :"Not Present"));

	CREATE_NEW_OBJECT;
	add_s("dmi.item","system");
	add_hs(dmi.system.manufacturer);
	add_hs(dmi.system.product_name);
	add_hs(dmi.system.version);
	add_hs(dmi.system.serial);
	add_hs(dmi.system.uuid);
	add_hs(dmi.system.wakeup_type);
	add_hs(dmi.system.sku_number);
	add_hs(dmi.system.family);
	add_hs(dmi.system.configuration_options);
	add_s("dmi.system.system_reset.status",system_reset_status);
	add_s("dmi.system.system_reset.watchdog",watchdog_timer);
	add_hs(dmi.system.system_reset.boot_option);
	add_hs(dmi.system.system_reset.boot_option_on_limit);
	add_hs(dmi.system.system_reset.reset_count);
	add_hs(dmi.system.system_reset.reset_limit);
	add_hs(dmi.system.system_reset.timer_interval);
	add_hs(dmi.system.system_reset.timeout);
	add_hs(dmi.system.system_boot_status);
	FLUSH_OBJECT;
}

void dump_base_board(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {

	if (hardware->dmi.base_board.filled == false) {
		CREATE_NEW_OBJECT;
			add_s("dmi.warning","no base_board structure found");
		FLUSH_OBJECT;
		return;
	}

	CREATE_NEW_OBJECT;
	add_s("dmi.item","base_board");
	add_hs(dmi.base_board.manufacturer);
	add_hs(dmi.base_board.product_name);
	add_hs(dmi.base_board.version);
	add_hs(dmi.base_board.serial);
	add_hs(dmi.base_board.asset_tag);
	add_hs(dmi.base_board.location);
	add_hs(dmi.base_board.type);
	for (int i = 0; i < BASE_BOARD_NB_ELEMENTS; i++) {
		if (((bool *) (&hardware->dmi.base_board.features))[i] == true) {
			add_s("dmi.base_board.features",(char *)base_board_features_strings[i]);
		}
	}

	for (unsigned int i = 0; i < sizeof hardware->dmi.base_board.devices_information /
		         sizeof *hardware->dmi.base_board.devices_information; i++) {
	        if (strlen(hardware->dmi.base_board.devices_information[i].type)) {
			add_s("dmi.base_board.devices_information.type", hardware->dmi.base_board.devices_information[i].type);
			add_i("dmi.base_board.devices_information.status", hardware->dmi.base_board.devices_information[i].status);
			add_s("dmi.base_board.devices_information.description", hardware->dmi.base_board.devices_information[i].description);
		}
	}
	FLUSH_OBJECT;
}

void dump_dmi(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {

	CREATE_NEW_OBJECT;
	add_hb(is_dmi_valid);

	if (hardware->is_dmi_valid == false) {
		FLUSH_OBJECT;
		goto exit;
	} else {
		char buffer[8]={0};
		snprintf(buffer,sizeof(buffer),"%d.%d",hardware->dmi.dmitable.major_version, hardware->dmi.dmitable.minor_version);
		add_s("dmi.version",buffer);
		FLUSH_OBJECT;
	}

	dump_base_board(hardware,config,item);
	dump_system(hardware,config,item);
	dump_bios(hardware,config,item);
	dump_chassis(hardware,config,item);
	dump_ipmi(hardware,config,item);
	dump_battery(hardware,config,item);
	dump_processor(hardware,config,item);
	dump_cache(hardware,config,item);
	dump_memory_banks(hardware,config,item);
	dump_memory_modules(hardware,config,item);
	dump_memory_size(hardware,config,item);
	dump_oem_strings(hardware,config,item);
	dump_hardware_security(hardware,config,item);
exit:
	to_cpio("dmi");
}
