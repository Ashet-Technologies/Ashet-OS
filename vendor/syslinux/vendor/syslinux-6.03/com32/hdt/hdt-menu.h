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

#ifndef DEFINE_HDT_MENU_H
#define DEFINE_HDT_MENU_H
#include <stdio.h>
#include <getkey.h>

#include "menu.h"
#include "help.h"
//#include "cpuid.h"
#include "sys/pci.h"
#include "hdt-common.h"
#include "dmi/dmi.h"
#include "hdt-ata.h"

#define EDITPROMPT 21

#define SUBMENULEN 46

#define SUBMENU_Y 3
#define SUBMENU_X 29

#define MAX_PCI_SUB_MENU 128
#define MAX_MEMORY_SUB_MENU 32
#define MAX_DISK_SUB_MENU 32

struct s_my_menu {
    unsigned char menu;
    int items_count;
};

struct s_hdt_menu {
    struct s_my_menu main_menu;
    struct s_my_menu cpu_menu;
    struct s_my_menu mobo_menu;
    struct s_my_menu chassis_menu;
    struct s_my_menu bios_menu;
    struct s_my_menu ipmi_menu;
    struct s_my_menu system_menu;
    struct s_my_menu pci_menu;
    struct s_my_menu pci_sub_menu[MAX_PCI_SUB_MENU];
    struct s_my_menu kernel_menu;
    struct s_my_menu memory_menu;
    struct s_my_menu memory_sub_menu[MAX_MEMORY_SUB_MENU];
    struct s_my_menu disk_menu;
    struct s_my_menu disk_sub_menu[MAX_DISK_SUB_MENU];
    struct s_my_menu battery_menu;
    struct s_my_menu syslinux_menu;
    struct s_my_menu about_menu;
    struct s_my_menu summary_menu;
    struct s_my_menu pxe_menu;
    struct s_my_menu vesa_menu;
    struct s_my_menu vesa_card_menu;
    struct s_my_menu vesa_modes_menu;
    struct s_my_menu vpd_menu;
    struct s_my_menu acpi_menu;
    struct s_my_menu acpi_apic_menu;
    struct s_my_menu acpi_tables_menu;
    int total_menu_count;	// Sum of all menus we have
};

TIMEOUTCODE ontimeout(void);
void keys_handler(t_menusystem * ms
		  __attribute__ ((unused)), t_menuitem * mi, int scancode);

// PCI Stuff
int compute_PCI(struct s_hdt_menu *hdt_menu, struct s_hardware *hardware);

// KERNEL Stuff
void compute_kernel(struct s_my_menu *menu, struct s_hardware *hardware);

// Disk Stuff
void compute_disks(struct s_hdt_menu *menu, struct s_hardware *hardware);

// DMI Stuff
void compute_motherboard(struct s_my_menu *menu, s_dmi * dmi);
void compute_battery(struct s_my_menu *menu, s_dmi * dmi);
void compute_system(struct s_my_menu *menu, s_dmi * dmi);
void compute_chassis(struct s_my_menu *menu, s_dmi * dmi);
void compute_bios(struct s_my_menu *menu, s_dmi * dmi);
void compute_memory(struct s_hdt_menu *menu, s_dmi * dmi,
		    struct s_hardware *hardware);
void compute_ipmi(struct s_my_menu *menu, s_dmi * dmi);

// VPD Stuff
void compute_vpd(struct s_my_menu *menu, struct s_hardware *hardware);

// Processor Stuff
void compute_processor(struct s_my_menu *menu, struct s_hardware *hardware);

// Syslinux stuff
void compute_syslinuxmenu(struct s_my_menu *menu, struct s_hardware *hardware);

// About menu
void compute_aboutmenu(struct s_my_menu *menu);

// Summary menu
void compute_summarymenu(struct s_my_menu *menu, struct s_hardware *hardware);

// PXE menu
void compute_PXE(struct s_my_menu *menu, struct s_hardware *hardware);

//VESA menu
int compute_VESA(struct s_hdt_menu *hdt_menu, struct s_hardware *hardware);

// ACPI menu
int compute_ACPI(struct s_hdt_menu *hdt_menu, struct s_hardware *hardware);

int start_menu_mode(struct s_hardware *hardware, char *version_string);
void setup_menu(char *version);
void compute_main_menu(struct s_hdt_menu *hdt_menu,
		       struct s_hardware *hardware);
void compute_submenus(struct s_hdt_menu *hdt_menu, struct s_hardware *hardware);
#endif
