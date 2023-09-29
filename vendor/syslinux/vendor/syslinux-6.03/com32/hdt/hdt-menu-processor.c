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

#include "hdt-menu.h"

static void show_flag(struct s_my_menu *menu, char *buffer, bool flag,
		      char *flag_name, bool flush)
{
    char output_buffer[SUBMENULEN + 1];
    char statbuffer[SUBMENULEN + 1];
    if ((((strlen(buffer) + strlen(flag_name)) > 35) && flag) || flush) {
	snprintf(output_buffer, sizeof output_buffer, "Flags     : %s", buffer);
	snprintf(statbuffer, sizeof statbuffer, "Flags: %s", buffer);
	add_item(output_buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	memset(buffer, 0, sizeof(buffer));
	if (flush)
	    return;
    }
    if (flag)
	strcat(buffer, flag_name);
}

/* Compute Processor menu */
void compute_processor(struct s_my_menu *menu, struct s_hardware *hardware)
{
    char buffer[SUBMENULEN + 1];
    char buffer1[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];

    if (hardware->acpi.madt.processor_local_apic_count > 0) {
	snprintf(buffer, sizeof buffer,
		 " Main Processors (%d logical / %d phys. ) ",
		 hardware->acpi.madt.processor_local_apic_count,
		 hardware->physical_cpu_count);
	menu->menu = add_menu(buffer, -1);
	menu->items_count = 0;
	set_menu_pos(SUBMENU_Y, SUBMENU_X);
    } else {
	menu->menu = add_menu(" Main Processor ", -1);
	menu->items_count = 0;
	set_menu_pos(SUBMENU_Y, SUBMENU_X);
    }

    snprintf(buffer, sizeof buffer, "Vendor    : %s", hardware->cpu.vendor);
    snprintf(statbuffer, sizeof statbuffer, "Vendor: %s", hardware->cpu.vendor);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Model     : %s", hardware->cpu.model);
    snprintf(statbuffer, sizeof statbuffer, "Model: %s", hardware->cpu.model);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "CPU Cores : %d", hardware->cpu.num_cores);
    snprintf(statbuffer, sizeof statbuffer, "Number of CPU cores: %d",
	     hardware->cpu.num_cores);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    if (hardware->dmi.processor.core_enabled != 0) {
        snprintf(buffer, sizeof buffer, "CPU Enable: %d", hardware->dmi.processor.core_enabled);
        snprintf(statbuffer, sizeof statbuffer, "Number of CPU Enabled : %d",
	     hardware->dmi.processor.core_enabled);
        add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
        menu->items_count++;
    }

    if (hardware->dmi.processor.thread_count != 0) {
        snprintf(buffer, sizeof buffer, "CPU Thread: %d", hardware->dmi.processor.thread_count);
        snprintf(statbuffer, sizeof statbuffer, "Number of CPU Threads : %d",
	     hardware->dmi.processor.thread_count);
        add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
        menu->items_count++;
    }

    snprintf(buffer, sizeof buffer, "L1 Cache  : %dK + %dK (I+D)",
	     hardware->cpu.l1_instruction_cache_size,
	     hardware->cpu.l1_data_cache_size);
    snprintf(statbuffer, sizeof statbuffer,
	     "L1 Cache Size: %dK + %dK (Instruction + Data)",
	     hardware->cpu.l1_instruction_cache_size,
	     hardware->cpu.l1_data_cache_size);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "L2 Cache  : %dK",
	     hardware->cpu.l2_cache_size);
    snprintf(statbuffer, sizeof statbuffer, "L2 Cache Size: %dK",
	     hardware->cpu.l2_cache_size);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Family ID : %d", hardware->cpu.family);
    snprintf(statbuffer, sizeof statbuffer, "Family ID: %d",
	     hardware->cpu.family);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Model  ID : %d", hardware->cpu.model_id);
    snprintf(statbuffer, sizeof statbuffer, "Model  ID: %d",
	     hardware->cpu.model_id);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Stepping  : %d", hardware->cpu.stepping);
    snprintf(statbuffer, sizeof statbuffer, "Stepping: %d",
	     hardware->cpu.stepping);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    if (hardware->is_dmi_valid) {
	snprintf(buffer, sizeof buffer, "FSB       : %d",
		 hardware->dmi.processor.external_clock);
	snprintf(statbuffer, sizeof statbuffer,
		 "Front Side Bus (MHz): %d",
		 hardware->dmi.processor.external_clock);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer, "Cur. Speed: %d",
		 hardware->dmi.processor.current_speed);
	snprintf(statbuffer, sizeof statbuffer,
		 "Current Speed (MHz): %d",
		 hardware->dmi.processor.current_speed);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer, "Max Speed : %d",
		 hardware->dmi.processor.max_speed);
	snprintf(statbuffer, sizeof statbuffer, "Max Speed (MHz): %d",
		 hardware->dmi.processor.max_speed);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer, "Upgrade   : %s",
		 hardware->dmi.processor.upgrade);
	snprintf(statbuffer, sizeof statbuffer, "Upgrade: %s",
		 hardware->dmi.processor.upgrade);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;

	snprintf(buffer, sizeof buffer, "Voltage   : %d.%02d",
		 hardware->dmi.processor.voltage_mv / 1000,
		 hardware->dmi.processor.voltage_mv -
		 ((hardware->dmi.processor.voltage_mv / 1000) * 1000));
	snprintf(statbuffer, sizeof statbuffer, "Voltage (V) : %d.%02d",
		 hardware->dmi.processor.voltage_mv / 1000,
		 hardware->dmi.processor.voltage_mv -
		 ((hardware->dmi.processor.voltage_mv / 1000) * 1000));
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
	menu->items_count++;
    }

    if (hardware->cpu.flags.smp) {
	snprintf(buffer, sizeof buffer, "SMP       : Yes");
	snprintf(statbuffer, sizeof statbuffer, "SMP: Yes");
    } else {
	snprintf(buffer, sizeof buffer, "SMP       : No");
	snprintf(statbuffer, sizeof statbuffer, "SMP: No");
    }
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    if (hardware->cpu.flags.lm) {
	snprintf(buffer, sizeof buffer, "x86_64    : Yes");
	snprintf(statbuffer, sizeof statbuffer,
		 "x86_64 compatible processor: Yes");
    } else {
	snprintf(buffer, sizeof buffer, "X86_64    : No");
	snprintf(statbuffer, sizeof statbuffer,
		 "X86_64 compatible processor: No");
    }
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    if ((hardware->cpu.flags.vmx) || (hardware->cpu.flags.svm)) {
	snprintf(buffer, sizeof buffer, "Hw Virt.  : Yes");
	snprintf(statbuffer, sizeof statbuffer,
		 "Hardware Virtualisation Capable: Yes");
    } else {
	snprintf(buffer, sizeof buffer, "Hw Virt.  : No");
	snprintf(statbuffer, sizeof statbuffer,
		 "Hardware Virtualisation Capabable : No");
    }
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    memset(buffer1, 0, sizeof(buffer1));
    show_flag(menu, buffer1, hardware->cpu.flags.fpu, "fpu ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.vme, "vme ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.de, "de ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pse, "pse ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.tsc, "tsc ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.msr, "msr ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pae, "pae ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.mce, "mce ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.cx8, "cx8 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.apic, "apic ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.sep, "sep ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.mtrr, "mtrr ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pge, "pge ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.mca, "mca ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.cmov, "cmov ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pat, "pat ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pse_36, "pse_36 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.psn, "psn ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.clflsh, "clflsh ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.dts, "dts ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.acpi, "acpi ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.mmx, "mmx ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.sse, "sse ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.sse2, "sse2 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.ss, "ss ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.htt, "ht ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.acc, "acc ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.syscall, "syscall ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.mp, "mp ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.nx, "nx ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.mmxext, "mmxext ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.lm, "lm ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.nowext, "3dnowext ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.now, "3dnow! ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.svm, "svm ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.vmx, "vmx ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pbe, "pbe ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.fxsr_opt, "fxsr_opt ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.gbpages, "gbpages ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.rdtscp, "rdtscp ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pni, "pni ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pclmulqd, "pclmulqd ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.dtes64, "dtes64 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.smx, "smx ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.est, "est ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.tm2, "tm2 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.sse3, "sse3 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.fma, "fma ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.cx16, "cx16 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.xtpr, "xtpr ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pdcm, "pdcm ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.dca, "dca ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.xmm4_1, "xmm4_1 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.xmm4_2, "xmm4_2 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.x2apic, "x2apic ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.movbe, "movbe ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.popcnt, "popcnt ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.aes, "aes ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.xsave, "xsave ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.osxsave, "osxsave ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.avx, "avx ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.hypervisor, "hypervisor ",
	      false);
    show_flag(menu, buffer1, hardware->cpu.flags.ace2, "ace2 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.ace2_en, "ace2_en ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.phe, "phe ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.phe_en, "phe_en ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pmm, "pmm ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.pmm_en, "pmm_en ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.extapic, "extapic ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.cr8_legacy, "cr8_legacy ",
	      false);
    show_flag(menu, buffer1, hardware->cpu.flags.abm, "abm ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.sse4a, "sse4a ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.misalignsse, "misalignsse ",
	      false);
    show_flag(menu, buffer1, hardware->cpu.flags.nowprefetch, "3dnowprefetch ",
	      false);
    show_flag(menu, buffer1, hardware->cpu.flags.osvw, "osvw ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.ibs, "ibs ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.sse5, "sse5 ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.skinit, "skinit ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.wdt, "wdt ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.ida, "ida ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.arat, "arat ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.tpr_shadow, "tpr_shadow ",
	      false);
    show_flag(menu, buffer1, hardware->cpu.flags.vnmi, "vnmi ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.flexpriority, "flexpriority ",
	      false);
    show_flag(menu, buffer1, hardware->cpu.flags.ept, "ept ", false);
    show_flag(menu, buffer1, hardware->cpu.flags.vpid, "vpid ", false);

    /* Let's flush the remaining flags */
    show_flag(menu, buffer1, false, "", true);

    printf("MENU: Processor menu done (%d items)\n", menu->items_count);
}
