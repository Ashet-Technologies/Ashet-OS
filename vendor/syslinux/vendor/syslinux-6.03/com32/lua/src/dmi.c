#include <stdlib.h>
#include <string.h>

#define ldmilib_c       /* Define the library */

/* Include the Lua API header files */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "dmi/dmi.h"

static void add_string_item(lua_State *L, const char *item, const char *value_str) {
 lua_pushstring(L,item);
 lua_pushstring(L,value_str);
 lua_settable(L,-3);
}

static void add_int_item(lua_State *L, const char *item, int value_int) {
 lua_pushstring(L,item);
 lua_pushnumber(L,value_int);
 lua_settable(L,-3);
}

typedef int (*table_fn)(lua_State*, s_dmi*);

/* Add a Lua_String entry to the table on stack
   xxx_P is the poiter version (i.e., pBase is a pointer)
   xxx_S is the staic version (i.e., Base is the struct)
*/
#define LUA_ADD_STR_P(pLua_state, pBase, Field) \
  add_string_item(pLua_state, #Field, pBase->Field);
#define LUA_ADD_STR_S(pLua_state, Base, Field) \
  add_string_item(pLua_state, #Field, Base.Field);

/* Add a Lua_Number entry to the table on stack
   xxx_P is the poiter version (i.e., pBase is a pointer)
   xxx_S is the staic version (i.e., Base is the struct)
*/
#define LUA_ADD_NUM_P(pLua_state, pBase, Field) \
  add_int_item(pLua_state, #Field, pBase->Field);
#define LUA_ADD_NUM_S(pLua_state, Base, Field) \
  add_int_item(pLua_state, #Field, Base.Field);

/* Add a sub-DMI table to the table on stack
   All (*table_fn)() have to be named as get_<tabel_name>_table() for this
   macro to work. For example, for the bios subtable, the table_fn is
   get_bios_table() and the subtable name is "bios".
   All (*table_fn)() have to return 1 if a subtable is created on the stack
   or 0 if the subtable is not created (no corresponding dim subtable found).
*/
#define LUA_ADD_TABLE(pLua_state, pDmi, tb_name) \
  add_dmi_sub_table(pLua_state, pDmi, #tb_name, get_ ## tb_name ## _table);


static void add_dmi_sub_table(lua_State *L, s_dmi *dmi_ptr, char *table_name,
                              table_fn get_table_fn)
{
  if (get_table_fn(L, dmi_ptr)) {  /* only adding it when it is there */
    lua_pushstring(L, table_name);
    lua_insert(L, -2);
    lua_settable(L,-3);
  }
}


void get_bool_table(lua_State *L, const char *str_table[], int n_elem,
                           bool *bool_table)
{
  int i;
  for (i = 0; i < n_elem; i++) {
    if (!str_table[i] || !*str_table[i])  /* aviod NULL/empty string */
      continue;

    lua_pushstring(L, str_table[i]);
    lua_pushboolean(L, bool_table[i]);
    lua_settable(L,-3);
  }
}


/*
** {======================================================
** DMI subtables
** =======================================================
*/
static int get_bios_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_bios *bios = &dmi_ptr->bios;

  if (!bios->filled)
    return 0;
  /* bios */
  lua_newtable(L);
  LUA_ADD_STR_P(L, bios, vendor)
  LUA_ADD_STR_P(L, bios, version)
  LUA_ADD_STR_P(L, bios, release_date)
  LUA_ADD_STR_P(L, bios, bios_revision)
  LUA_ADD_STR_P(L, bios, firmware_revision)
  LUA_ADD_NUM_P(L, bios, address)
  LUA_ADD_NUM_P(L, bios, runtime_size)
  LUA_ADD_STR_P(L, bios, runtime_size_unit)
  LUA_ADD_NUM_P(L, bios, rom_size)
  LUA_ADD_STR_P(L, bios, rom_size_unit)

  /* bios characteristics */
  lua_pushstring(L, "chars");
  lua_newtable(L);
  get_bool_table(L, bios_charac_strings,
                 sizeof(s_characteristics)/sizeof(bool),
                 (bool *)(&bios->characteristics));
  get_bool_table(L, bios_charac_x1_strings,
                 sizeof(s_characteristics_x1)/sizeof(bool),
                 (bool *)(&bios->characteristics_x1));
  get_bool_table(L, bios_charac_x2_strings,
                 sizeof(s_characteristics_x2)/sizeof(bool),
                 (bool *)(&bios->characteristics_x2));
  lua_settable(L,-3);

  return 1;
}


static int get_system_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_system *system = &dmi_ptr->system;

  if (!system->filled)
    return 0;
  /* system */
  lua_newtable(L);
  LUA_ADD_STR_P(L, system, manufacturer)
  LUA_ADD_STR_P(L, system, product_name)
  LUA_ADD_STR_P(L, system, version)
  LUA_ADD_STR_P(L, system, serial)
  LUA_ADD_STR_P(L, system, uuid)
  LUA_ADD_STR_P(L, system, wakeup_type)
  LUA_ADD_STR_P(L, system, sku_number)
  LUA_ADD_STR_P(L, system, family)
  LUA_ADD_STR_P(L, system, system_boot_status)
  LUA_ADD_STR_P(L, system, configuration_options)

  /* system reset */
  if (system->system_reset.filled) {
    lua_pushstring(L, "reset");
    lua_newtable(L);
    LUA_ADD_NUM_S(L, system->system_reset, status)
    LUA_ADD_NUM_S(L, system->system_reset, watchdog)
    LUA_ADD_STR_S(L, system->system_reset, boot_option)
    LUA_ADD_STR_S(L, system->system_reset, boot_option_on_limit)
	  LUA_ADD_STR_S(L, system->system_reset, reset_count)
	  LUA_ADD_STR_S(L, system->system_reset, reset_limit)
	  LUA_ADD_STR_S(L, system->system_reset, timer_interval)
	  LUA_ADD_STR_S(L, system->system_reset, timeout)
    lua_settable(L,-3);
  }

  return 1;
}


static int get_base_board_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_base_board *base_board = &dmi_ptr->base_board;
  int n_dev = sizeof(base_board->devices_information) /
              sizeof(base_board->devices_information[0]);
  int i, j, has_dev;

  if (!base_board->filled)
    return 0;
  /* base_board */
  lua_newtable(L);
  LUA_ADD_STR_P(L, base_board, manufacturer)
  LUA_ADD_STR_P(L, base_board, product_name)
  LUA_ADD_STR_P(L, base_board, version)
  LUA_ADD_STR_P(L, base_board, serial)
  LUA_ADD_STR_P(L, base_board, asset_tag)
  LUA_ADD_STR_P(L, base_board, location)
  LUA_ADD_STR_P(L, base_board, type)

  /* base board features */
  lua_pushstring(L, "features");
  lua_newtable(L);
  get_bool_table(L, base_board_features_strings,
                 sizeof(s_base_board_features)/sizeof(bool),
                 (bool *)(&base_board->features));
  lua_settable(L,-3);

  /* on-board devices */
  for (has_dev = 0, i = 0; i < n_dev; i++)
    if (*base_board->devices_information[i].type)
      has_dev++;

  if (has_dev) {
    lua_pushstring(L, "devices");
    lua_newtable(L);
    for (i = 0, j = 1; i < n_dev; i++) {
      if (!*base_board->devices_information[i].type)  /* empty device */
        continue;

      lua_pushinteger(L, j++);
      lua_newtable(L);
      LUA_ADD_STR_S(L, base_board->devices_information[i], type)
      LUA_ADD_STR_S(L, base_board->devices_information[i], description)
      LUA_ADD_NUM_S(L, base_board->devices_information[i], status)
      lua_settable(L,-3);
    }
    lua_settable(L,-3);
  }

  return 1;
}


static int get_chassis_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_chassis *chassis = &dmi_ptr->chassis;

  if (!chassis->filled)
    return 0;
  /* chassis */
  lua_newtable(L);
  LUA_ADD_STR_P(L, chassis, manufacturer)
  LUA_ADD_STR_P(L, chassis, type)
  LUA_ADD_STR_P(L, chassis, lock)
  LUA_ADD_STR_P(L, chassis, version)
  LUA_ADD_STR_P(L, chassis, serial)
  LUA_ADD_STR_P(L, chassis, asset_tag)
  LUA_ADD_STR_P(L, chassis, boot_up_state)
  LUA_ADD_STR_P(L, chassis, power_supply_state)
  LUA_ADD_STR_P(L, chassis, thermal_state)
  LUA_ADD_STR_P(L, chassis, security_status)
  LUA_ADD_STR_P(L, chassis, oem_information)
  LUA_ADD_NUM_P(L, chassis, height)
  LUA_ADD_NUM_P(L, chassis, nb_power_cords)

  return 1;
}


static int get_processor_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_processor *processor = &dmi_ptr->processor;
  s_signature *signature = &processor->signature;

  if (!processor->filled)
    return 0;
  /* processor */
  lua_newtable(L);
  LUA_ADD_STR_P(L, processor, socket_designation)
  LUA_ADD_STR_P(L, processor, type)
  LUA_ADD_STR_P(L, processor, family)
  LUA_ADD_STR_P(L, processor, manufacturer)
  LUA_ADD_STR_P(L, processor, version)
  LUA_ADD_NUM_P(L, processor, external_clock)
  LUA_ADD_NUM_P(L, processor, max_speed)
  LUA_ADD_NUM_P(L, processor, current_speed)
  LUA_ADD_NUM_P(L, processor, voltage_mv)
  LUA_ADD_STR_P(L, processor, status)
  LUA_ADD_STR_P(L, processor, upgrade)
  LUA_ADD_STR_P(L, processor, cache1)
  LUA_ADD_STR_P(L, processor, cache2)
  LUA_ADD_STR_P(L, processor, cache3)
  LUA_ADD_STR_P(L, processor, serial)
  LUA_ADD_STR_P(L, processor, part_number)
  LUA_ADD_STR_P(L, processor, id)
  LUA_ADD_NUM_P(L, processor, core_count)
  LUA_ADD_NUM_P(L, processor, core_enabled)
  LUA_ADD_NUM_P(L, processor, thread_count)

  /* processor signature */
  lua_pushstring(L, "signature");
  lua_newtable(L);
  LUA_ADD_NUM_P(L, signature, type)
  LUA_ADD_NUM_P(L, signature, family)
  LUA_ADD_NUM_P(L, signature, model)
  LUA_ADD_NUM_P(L, signature, stepping)
  LUA_ADD_NUM_P(L, signature, minor_stepping)
  lua_settable(L,-3);

  /* processor flags */
  lua_pushstring(L, "flags");
  lua_newtable(L);
  get_bool_table(L, cpu_flags_strings,
                 sizeof(s_dmi_cpu_flags)/sizeof(bool),
                 (bool *)(&processor->cpu_flags));
  lua_settable(L,-3);

  return 1;
}


static int get_battery_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_battery *battery = &dmi_ptr->battery;

  if (!battery->filled)
    return 0;
  /* battery */
  lua_newtable(L);
  LUA_ADD_STR_P(L, battery, location)
  LUA_ADD_STR_P(L, battery, manufacturer)
  LUA_ADD_STR_P(L, battery, manufacture_date)
  LUA_ADD_STR_P(L, battery, serial)
  LUA_ADD_STR_P(L, battery, name)
  LUA_ADD_STR_P(L, battery, chemistry)
  LUA_ADD_STR_P(L, battery, design_capacity)
  LUA_ADD_STR_P(L, battery, design_voltage)
  LUA_ADD_STR_P(L, battery, sbds)
  LUA_ADD_STR_P(L, battery, sbds_serial)
  LUA_ADD_STR_P(L, battery, maximum_error)
  LUA_ADD_STR_P(L, battery, sbds_manufacture_date)
  LUA_ADD_STR_P(L, battery, sbds_chemistry)
  LUA_ADD_STR_P(L, battery, oem_info)

  return 1;
}


static int get_memory_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_memory *memory = dmi_ptr->memory;
  int i, j, n_mem = dmi_ptr->memory_count;

  if (n_mem <= 0)  /*  no memory info */
    return 0;

  /* memory */
  lua_newtable(L);
  for (j = 1, i = 0; i < n_mem; i++) {
    if (!memory[i].filled)
      continue;

    lua_pushinteger(L, j++);
    lua_newtable(L);
    LUA_ADD_STR_S(L, memory[i], manufacturer)
    LUA_ADD_STR_S(L, memory[i], error)
    LUA_ADD_STR_S(L, memory[i], total_width)
    LUA_ADD_STR_S(L, memory[i], data_width)
    LUA_ADD_STR_S(L, memory[i], size)
    LUA_ADD_STR_S(L, memory[i], form_factor)
    LUA_ADD_STR_S(L, memory[i], device_set)
    LUA_ADD_STR_S(L, memory[i], device_locator)
    LUA_ADD_STR_S(L, memory[i], bank_locator)
    LUA_ADD_STR_S(L, memory[i], type)
    LUA_ADD_STR_S(L, memory[i], type_detail)
    LUA_ADD_STR_S(L, memory[i], speed)
    LUA_ADD_STR_S(L, memory[i], serial)
    LUA_ADD_STR_S(L, memory[i], asset_tag)
    LUA_ADD_STR_S(L, memory[i], part_number)
    lua_settable(L,-3);
  }
  return 1;
}


static int get_memory_module_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_memory_module *memory_module = dmi_ptr->memory_module;
  int i, j, n_mem = dmi_ptr->memory_module_count;

  if (n_mem <= 0)  /*  no memory module info */
    return 0;

  /* memory module */
  lua_newtable(L);
  for (j = 1, i = 0; i < n_mem; i++) {
    if (!memory_module[i].filled)
      continue;

    lua_pushinteger(L, j++);
    lua_newtable(L);
    LUA_ADD_STR_S(L, memory_module[i], socket_designation)
    LUA_ADD_STR_S(L, memory_module[i], bank_connections)
    LUA_ADD_STR_S(L, memory_module[i], speed)
    LUA_ADD_STR_S(L, memory_module[i], type)
    LUA_ADD_STR_S(L, memory_module[i], installed_size)
    LUA_ADD_STR_S(L, memory_module[i], enabled_size)
    LUA_ADD_STR_S(L, memory_module[i], error_status)
    lua_settable(L,-3);
  }
  return 1;
}


static int get_cache_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_cache *cache = dmi_ptr->cache;
  int i, n_cache = dmi_ptr->cache_count;

  if (n_cache <= 0)  /*  no cache info */
    return 0;

  /* memory */
  lua_newtable(L);
  for (i = 0; i < n_cache; i++) {
    lua_pushinteger(L, i + 1);
    lua_newtable(L);
    LUA_ADD_STR_S(L, cache[i], socket_designation)
    LUA_ADD_STR_S(L, cache[i], configuration)
    LUA_ADD_STR_S(L, cache[i], mode)
    LUA_ADD_STR_S(L, cache[i], location)
    LUA_ADD_NUM_S(L, cache[i], installed_size)
    LUA_ADD_NUM_S(L, cache[i], max_size)
    LUA_ADD_STR_S(L, cache[i], supported_sram_types)
    LUA_ADD_STR_S(L, cache[i], installed_sram_types)
    LUA_ADD_NUM_S(L, cache[i], speed)
    LUA_ADD_STR_S(L, cache[i], error_correction_type)
    LUA_ADD_STR_S(L, cache[i], system_type)
    LUA_ADD_STR_S(L, cache[i], associativity)
    lua_settable(L,-3);
  }
  return 1;
}


static int get_hardware_security_table(lua_State *L, s_dmi *dmi_ptr)
{
  if (!dmi_ptr->hardware_security.filled)
    return 0;
  /* hardware_security */
  lua_newtable(L);
  LUA_ADD_STR_S(L, dmi_ptr->hardware_security, power_on_passwd_status)
	LUA_ADD_STR_S(L, dmi_ptr->hardware_security, keyboard_passwd_status)
	LUA_ADD_STR_S(L, dmi_ptr->hardware_security, administrator_passwd_status)
	LUA_ADD_STR_S(L, dmi_ptr->hardware_security, front_panel_reset_status)

  return 1;
}


static int get_dmi_info_table(lua_State *L, s_dmi *dmi_ptr)
{
  dmi_table *dmitable = &dmi_ptr->dmitable;

  /* dmi info */
  lua_newtable(L);
  LUA_ADD_NUM_P(L, dmitable, num)
  LUA_ADD_NUM_P(L, dmitable, len)
  LUA_ADD_NUM_P(L, dmitable, ver)
  LUA_ADD_NUM_P(L, dmitable, base)
  LUA_ADD_NUM_P(L, dmitable, major_version)
  LUA_ADD_NUM_P(L, dmitable, minor_version)

  return 1;
}


static int get_ipmi_table(lua_State *L, s_dmi *dmi_ptr)
{
  s_ipmi *ipmi = &dmi_ptr->ipmi;

  if (!ipmi->filled)
    return 0;
  /* ipmi */
  lua_newtable(L);
  LUA_ADD_STR_P(L, ipmi, interface_type)
  LUA_ADD_NUM_P(L, ipmi, major_specification_version)
  LUA_ADD_NUM_P(L, ipmi, minor_specification_version)
  LUA_ADD_NUM_P(L, ipmi, I2C_slave_address)
  LUA_ADD_NUM_P(L, ipmi, nv_address)
  LUA_ADD_NUM_P(L, ipmi, base_address)
  LUA_ADD_NUM_P(L, ipmi, irq)

  return 1;
}
/*
** {======================================================
** End of DMI subtables
** =======================================================
*/


static int dmi_gettable(lua_State *L)
{
  s_dmi dmi;

  lua_newtable(L);

  if ( ! dmi_iterate(&dmi) ) {
          printf("No DMI Structure found\n");
          return -1;
  }

  parse_dmitable(&dmi);

  LUA_ADD_NUM_S(L, dmi, memory_module_count)
  LUA_ADD_NUM_S(L, dmi, memory_count)
  LUA_ADD_NUM_S(L, dmi, cache_count)
  LUA_ADD_STR_S(L, dmi, oem_strings)

  LUA_ADD_TABLE(L, &dmi, bios)
  LUA_ADD_TABLE(L, &dmi, system)
  LUA_ADD_TABLE(L, &dmi, base_board)
  LUA_ADD_TABLE(L, &dmi, chassis)
  LUA_ADD_TABLE(L, &dmi, processor)
  LUA_ADD_TABLE(L, &dmi, battery)
  LUA_ADD_TABLE(L, &dmi, memory)
  LUA_ADD_TABLE(L, &dmi, memory_module)
  LUA_ADD_TABLE(L, &dmi, cache)
  LUA_ADD_TABLE(L, &dmi, ipmi)
  LUA_ADD_TABLE(L, &dmi, hardware_security)
  LUA_ADD_TABLE(L, &dmi, dmi_info)

  /* set global variable: lua_setglobal(L, "dmitable"); */

  /* return number of return values on stack */
  return 1;
}


static int dmi_supported(lua_State *L)
{
  s_dmi dmi;

  if ( dmi_iterate(&dmi) ) {
    lua_pushboolean(L, 1);
  } else {
    lua_pushboolean(L, 0);
  }
  return 1;
}


static const luaL_Reg dmilib[] = {
  {"gettable", dmi_gettable},
  {"supported", dmi_supported},
  {NULL, NULL}
};


LUALIB_API int luaopen_dmi (lua_State *L) {
  luaL_newlib(L, dmilib);
  return 1;
}

