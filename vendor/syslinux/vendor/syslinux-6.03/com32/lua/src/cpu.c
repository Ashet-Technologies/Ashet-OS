#include <stdlib.h>
#include <string.h>

#define llua_cpu       /* Define the library */

/* Include the Lua API header files */
#include"lua.h"
#include"lauxlib.h"
#include"lualib.h"
#include"cpuid.h"

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

static void add_flag(lua_State *L, bool value, const char *value_str) {
 char buffer[32] = { 0 };
 snprintf(buffer,sizeof(buffer), "flags.%s",value_str);
 lua_pushstring(L,buffer);
// printf("%s=%d\n",value_str,value);

 if (value == true) {
  lua_pushstring(L,"yes");
 } else {
  lua_pushstring(L,"no");
 }

 lua_settable(L,-3);
}

static int cpu_getflags(lua_State *L)
{
  s_cpu lua_cpu;
  
  detect_cpu(&lua_cpu);

  lua_newtable(L);

  add_string_item(L, "vendor", lua_cpu.vendor);
  add_string_item(L, "model", lua_cpu.model);
  add_int_item(L, "cores", lua_cpu.num_cores);
  add_int_item(L, "l1_instruction_cache", lua_cpu.l1_instruction_cache_size);
  add_int_item(L, "l1_data_cache", lua_cpu.l1_data_cache_size);
  add_int_item(L, "l2_cache", lua_cpu.l2_cache_size);
  add_int_item(L, "family_id", lua_cpu.family);
  add_int_item(L, "model_id", lua_cpu.model_id);
  add_int_item(L, "stepping", lua_cpu.stepping);

  add_flag(L, lua_cpu.flags.fpu, "fpu");
  add_flag(L, lua_cpu.flags.vme, "vme");
  add_flag(L, lua_cpu.flags.de, "de");
  add_flag(L, lua_cpu.flags.pse, "pse");
  add_flag(L, lua_cpu.flags.tsc, "tsc");
  add_flag(L, lua_cpu.flags.msr, "msr");
  add_flag(L, lua_cpu.flags.pae, "pae");
  add_flag(L, lua_cpu.flags.mce, "mce");
  add_flag(L, lua_cpu.flags.cx8, "cx8");
  add_flag(L, lua_cpu.flags.apic, "apic");
  add_flag(L, lua_cpu.flags.sep, "sep");
  add_flag(L, lua_cpu.flags.mtrr, "mtrr");
  add_flag(L, lua_cpu.flags.pge, "pge");
  add_flag(L, lua_cpu.flags.mca, "mca");
  add_flag(L, lua_cpu.flags.cmov, "cmov");
  add_flag(L, lua_cpu.flags.pat, "pat");
  add_flag(L, lua_cpu.flags.pse_36, "pse_36");
  add_flag(L, lua_cpu.flags.psn, "psn");
  add_flag(L, lua_cpu.flags.clflsh, "clflsh");
  add_flag(L, lua_cpu.flags.dts, "dts");
  add_flag(L, lua_cpu.flags.acpi, "acpi");
  add_flag(L, lua_cpu.flags.mmx, "mmx");
  add_flag(L, lua_cpu.flags.sse, "sse");
  add_flag(L, lua_cpu.flags.sse2, "sse2");
  add_flag(L, lua_cpu.flags.ss, "ss");
  add_flag(L, lua_cpu.flags.htt, "ht");
  add_flag(L, lua_cpu.flags.acc, "acc");
  add_flag(L, lua_cpu.flags.syscall, "syscall");
  add_flag(L, lua_cpu.flags.mp, "mp");
  add_flag(L, lua_cpu.flags.nx, "nx");
  add_flag(L, lua_cpu.flags.mmxext, "mmxext");
  add_flag(L, lua_cpu.flags.lm, "lm");
  add_flag(L, lua_cpu.flags.nowext, "3dnowext");
  add_flag(L, lua_cpu.flags.now, "3dnow!");
  add_flag(L, lua_cpu.flags.svm, "svm");
  add_flag(L, lua_cpu.flags.vmx, "vmx");
  add_flag(L, lua_cpu.flags.pbe, "pbe");
  add_flag(L, lua_cpu.flags.fxsr_opt, "fxsr_opt");
  add_flag(L, lua_cpu.flags.gbpages, "gbpages");
  add_flag(L, lua_cpu.flags.rdtscp, "rdtscp");
  add_flag(L, lua_cpu.flags.pni, "pni");
  add_flag(L, lua_cpu.flags.pclmulqd, "pclmulqd");
  add_flag(L, lua_cpu.flags.dtes64, "dtes64");
  add_flag(L, lua_cpu.flags.smx, "smx");
  add_flag(L, lua_cpu.flags.est, "est");
  add_flag(L, lua_cpu.flags.tm2, "tm2");
  add_flag(L, lua_cpu.flags.sse3, "sse3");
  add_flag(L, lua_cpu.flags.fma, "fma");
  add_flag(L, lua_cpu.flags.cx16, "cx16");
  add_flag(L, lua_cpu.flags.xtpr, "xtpr");
  add_flag(L, lua_cpu.flags.pdcm, "pdcm");
  add_flag(L, lua_cpu.flags.dca, "dca");
  add_flag(L, lua_cpu.flags.xmm4_1, "xmm4_1");
  add_flag(L, lua_cpu.flags.xmm4_2, "xmm4_2");
  add_flag(L, lua_cpu.flags.x2apic, "x2apic");
  add_flag(L, lua_cpu.flags.movbe, "movbe");
  add_flag(L, lua_cpu.flags.popcnt, "popcnt");
  add_flag(L, lua_cpu.flags.aes, "aes");
  add_flag(L, lua_cpu.flags.xsave, "xsave");
  add_flag(L, lua_cpu.flags.osxsave, "osxsave");
  add_flag(L, lua_cpu.flags.avx, "avx");
  add_flag(L, lua_cpu.flags.hypervisor, "hypervisor");
  add_flag(L, lua_cpu.flags.ace2, "ace2");
  add_flag(L, lua_cpu.flags.ace2_en, "ace2_en");
  add_flag(L, lua_cpu.flags.phe, "phe");
  add_flag(L, lua_cpu.flags.phe_en, "phe_en");
  add_flag(L, lua_cpu.flags.pmm, "pmm");
  add_flag(L, lua_cpu.flags.pmm_en, "pmm_en");
  add_flag(L, lua_cpu.flags.extapic, "extapic");
  add_flag(L, lua_cpu.flags.cr8_legacy, "cr8_legacy");
  add_flag(L, lua_cpu.flags.abm, "abm");
  add_flag(L, lua_cpu.flags.sse4a, "sse4a");
  add_flag(L, lua_cpu.flags.misalignsse, "misalignsse");
  add_flag(L, lua_cpu.flags.nowprefetch, "3dnowprefetch");
  add_flag(L, lua_cpu.flags.osvw, "osvw");
  add_flag(L, lua_cpu.flags.ibs, "ibs");
  add_flag(L, lua_cpu.flags.sse5, "sse5");
  add_flag(L, lua_cpu.flags.skinit, "skinit");
  add_flag(L, lua_cpu.flags.wdt, "wdt");
  add_flag(L, lua_cpu.flags.ida, "ida");
  add_flag(L, lua_cpu.flags.arat, "arat");
  add_flag(L, lua_cpu.flags.tpr_shadow, "tpr_shadow");
  add_flag(L, lua_cpu.flags.vnmi, "vnmi");
  add_flag(L, lua_cpu.flags.flexpriority, "flexpriority");
  add_flag(L, lua_cpu.flags.ept, "ept");
  add_flag(L, lua_cpu.flags.vpid, "vpid");

  /* return number of return values on stack */
  return 1;
}

static const luaL_Reg cpulib[] = {
  {"flags", cpu_getflags},
  {NULL, NULL}
};


LUALIB_API int luaopen_cpu(lua_State *L) {
  luaL_newlib(L, cpulib);
  return 1;
}

