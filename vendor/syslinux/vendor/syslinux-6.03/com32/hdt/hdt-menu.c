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

#include <unistd.h>
#include <memory.h>
#include <syslinux/reboot.h>
#include "hdt-menu.h"

int start_menu_mode(struct s_hardware *hardware, char *version_string)
{
    struct s_hdt_menu hdt_menu;

    memset(&hdt_menu, 0, sizeof(hdt_menu));

    /* Setup the menu system */
    setup_menu(version_string);

    /* Compute all submenus */
    compute_submenus(&hdt_menu, hardware);

    /* Compute the main menu */
    compute_main_menu(&hdt_menu, hardware);

#ifdef WITH_MENU_DISPLAY
    t_menuitem *curr;
    char cmd[160];

    if (!quiet)
	more_printf("Starting Menu (%d menus)\n", hdt_menu.total_menu_count);
    curr = showmenus(hdt_menu.main_menu.menu);
    /* When we exit the menu, do we have something to do? */
    if (curr) {
	/* When want to execute something */
	if (curr->action == OPT_RUN) {
	    /* Tweak, we want to switch to the cli */
	    if (!strncmp
		(curr->data, HDT_SWITCH_TO_CLI, sizeof(HDT_SWITCH_TO_CLI))) {
		return HDT_RETURN_TO_CLI;
	    }
	    /* Tweak, we want to start the dump mode */
	    if (!strncmp
		(curr->data, HDT_DUMP, sizeof(HDT_DUMP))) {
		    dump(hardware);
	        return 0;
	    }
	    if (!strncmp
		(curr->data, HDT_REBOOT, sizeof(HDT_REBOOT))) {
		syslinux_reboot(1);
	    }
	    strcpy(cmd, curr->data);

	    /* Use specific syslinux call if needed */
	    if (issyslinux())
		runsyslinuxcmd(cmd);
	    else
		csprint(cmd, 0x07);
	    return 1;		// Should not happen when run from SYSLINUX
	}
    }
#endif
    return 0;
}

/* In the menu system, what to do on keyboard timeout */
TIMEOUTCODE ontimeout(void)
{
    // beep();
    return CODE_WAIT;
}

/* Keyboard handler for the menu system */
void keys_handler(t_menusystem * ms
		  __attribute__ ((unused)), t_menuitem * mi, int scancode)
{
    int nr, nc;

    /* 0xFFFF is an invalid helpid */
    if (scancode == KEY_F1 && mi->helpid != 0xFFFF) {
	runhelpsystem(mi->helpid);
    }

    /*
     * If user hit TAB, and item is an "executable" item
     * and user has privileges to edit it, edit it in place.
     */
    if ((scancode == KEY_TAB) && (mi->action == OPT_RUN)) {
//(isallowed(username,"editcmd") || isallowed(username,"root"))) {
	if (getscreensize(1, &nr, &nc)) {
	    /* Unknown screen size? */
	    nc = 80;
	    nr = 24;
	}
	/* User typed TAB and has permissions to edit command line */
	gotoxy(EDITPROMPT, 1);
	csprint("Command line:", 0x07);
	editstring(mi->data, ACTIONLEN);
	gotoxy(EDITPROMPT, 1);
	cprint(' ', 0x07, nc - 1);
    }
}

/* Setup the Menu system */
void setup_menu(char *version)
{
    /* Creating the menu */
    init_menusystem(version);
    set_window_size(0, 0, 25, 80);

    /* Do not use inactive attributes - they make little sense for HDT */
    set_normal_attr(-1, -1, 0x17, 0x1F);

    /* Register the menusystem handler */
    // reg_handler(HDLR_SCREEN,&msys_handler);
    reg_handler(HDLR_KEYS, &keys_handler);

    /* Register the ontimeout handler, with a time out of 10 seconds */
    reg_ontimeout(ontimeout, 1000, 0);
}

/* Compute Main' submenus */
void compute_submenus(struct s_hdt_menu *hdt_menu, struct s_hardware *hardware)
{

    /* Compute this menu if a DMI table exists */
    if (hardware->is_dmi_valid) {
	if (hardware->dmi.ipmi.filled == true)
	    compute_ipmi(&hdt_menu->ipmi_menu, &hardware->dmi);
	if (hardware->dmi.base_board.filled == true)
	    compute_motherboard(&(hdt_menu->mobo_menu), &(hardware->dmi));
	if (hardware->dmi.chassis.filled == true)
	    compute_chassis(&(hdt_menu->chassis_menu), &(hardware->dmi));
	if (hardware->dmi.system.filled == true)
	    compute_system(&(hdt_menu->system_menu), &(hardware->dmi));
	compute_memory(hdt_menu, &(hardware->dmi), hardware);
	if (hardware->dmi.bios.filled == true)
	    compute_bios(&(hdt_menu->bios_menu), &(hardware->dmi));
	if (hardware->dmi.battery.filled == true)
	    compute_battery(&(hdt_menu->battery_menu), &(hardware->dmi));
    }

    compute_processor(&(hdt_menu->cpu_menu), hardware);
    compute_vpd(&(hdt_menu->vpd_menu), hardware);
    compute_disks(hdt_menu, hardware);

    compute_PCI(hdt_menu, hardware);
    compute_PXE(&(hdt_menu->pxe_menu), hardware);
    compute_kernel(&(hdt_menu->kernel_menu), hardware);
    
    compute_summarymenu(&(hdt_menu->summary_menu), hardware);
    compute_syslinuxmenu(&(hdt_menu->syslinux_menu), hardware);
    compute_VESA(hdt_menu, hardware);
    compute_ACPI(hdt_menu, hardware);
    compute_aboutmenu(&(hdt_menu->about_menu));
}

void compute_main_menu(struct s_hdt_menu *hdt_menu, struct s_hardware *hardware)
{
    char menu_item[64];
    /* Let's count the number of menus we have */
    hdt_menu->total_menu_count = 0;
    hdt_menu->main_menu.items_count = 0;

    hdt_menu->main_menu.menu = add_menu(" Main Menu ", -1);
    set_item_options(-1, 24);

    snprintf(menu_item, sizeof(menu_item), "PC<I> Devices(%2d)\n",
	     hardware->nb_pci_devices);
    add_item(menu_item, "PCI Devices Menu", OPT_SUBMENU, NULL,
	     hdt_menu->pci_menu.menu);
    hdt_menu->main_menu.items_count++;
    hdt_menu->total_menu_count += hdt_menu->pci_menu.items_count;
    
    if (hdt_menu->disk_menu.items_count > 0) {
	snprintf(menu_item, sizeof(menu_item), "<D>isks      (%2d)\n",
		 hdt_menu->disk_menu.items_count);
	add_item(menu_item, "Disks Menu", OPT_SUBMENU, NULL,
		 hdt_menu->disk_menu.menu);
	hdt_menu->main_menu.items_count++;
	hdt_menu->total_menu_count += hdt_menu->disk_menu.items_count;
    }

    snprintf(menu_item, sizeof(menu_item), "<M>emory\n");
    add_item(menu_item, "Memory Menu", OPT_SUBMENU, NULL,
	     hdt_menu->memory_menu.menu);
    hdt_menu->main_menu.items_count++;
    hdt_menu->total_menu_count += hdt_menu->memory_menu.items_count;

    add_item("<P>rocessor", "Main Processor Menu", OPT_SUBMENU, NULL,
	     hdt_menu->cpu_menu.menu);
    hdt_menu->main_menu.items_count++;

    if (hardware->is_dmi_valid) {
	if (hardware->dmi.base_board.filled == true) {
	    add_item("M<o>therboard", "Motherboard Menu",
		     OPT_SUBMENU, NULL, hdt_menu->mobo_menu.menu);
	    hdt_menu->main_menu.items_count++;
	}

	if (hardware->dmi.bios.filled == true) {
	    add_item("<B>ios", "Bios Menu", OPT_SUBMENU, NULL,
		     hdt_menu->bios_menu.menu);
	    hdt_menu->main_menu.items_count++;
	}

	if (hardware->dmi.chassis.filled == true) {
	    add_item("<C>hassis", "Chassis Menu", OPT_SUBMENU, NULL,
		     hdt_menu->chassis_menu.menu);
	    hdt_menu->main_menu.items_count++;
	}

	if (hardware->dmi.system.filled == true) {
	    add_item("<S>ystem", "System Menu", OPT_SUBMENU, NULL,
		     hdt_menu->system_menu.menu);
	    hdt_menu->main_menu.items_count++;
	}

	if (hardware->dmi.battery.filled == true) {
	    add_item("Ba<t>tery", "Battery Menu", OPT_SUBMENU, NULL,
		     hdt_menu->battery_menu.menu);
	    hdt_menu->main_menu.items_count++;
	}
	if (hardware->dmi.ipmi.filled == true) {
	    add_item("I<P>MI", "IPMI Menu", OPT_SUBMENU, NULL,
		     hdt_menu->ipmi_menu.menu);
	    hdt_menu->main_menu.items_count++;
	}
    }

    if (hardware->is_vpd_valid == true) {
	add_item("<V>PD", "VPD Information Menu", OPT_SUBMENU, NULL,
		 hdt_menu->vpd_menu.menu);
	hdt_menu->main_menu.items_count++;
    }

    if (hardware->is_pxe_valid == true) {
	add_item("P<X>E", "PXE Information Menu", OPT_SUBMENU, NULL,
		 hdt_menu->pxe_menu.menu);
	hdt_menu->main_menu.items_count++;
    }

    if (hardware->is_vesa_valid == true) {
	add_item("<V>ESA", "VESA Information Menu", OPT_SUBMENU, NULL,
		 hdt_menu->vesa_menu.menu);
	hdt_menu->main_menu.items_count++;
    }

    if (hardware->is_acpi_valid == true) {
	add_item("<A>CPI", "ACPI Menu", OPT_SUBMENU, NULL,
		 hdt_menu->acpi_menu.menu);
	hdt_menu->main_menu.items_count++;
    }

    add_item("", "", OPT_SEP, "", 0);
    
    if ((hardware->modules_pcimap_return_code != -ENOMODULESPCIMAP) ||
	(hardware->modules_alias_return_code != -ENOMODULESALIAS)) {
	add_item("<K>ernel Modules", "Kernel Modules Menu", OPT_SUBMENU,
		 NULL, hdt_menu->kernel_menu.menu);
	hdt_menu->main_menu.items_count++;
    }
    
    add_item("S<y>slinux", "Syslinux Information Menu", OPT_SUBMENU, NULL,
	     hdt_menu->syslinux_menu.menu);
    hdt_menu->main_menu.items_count++;
    add_item("S<u>mmary", "Summary Information Menu", OPT_SUBMENU, NULL,
	     hdt_menu->summary_menu.menu);
    hdt_menu->main_menu.items_count++;

    add_item("", "", OPT_SEP, "", 0);

    add_item("S<w>itch to CLI", "Switch to Command Line", OPT_RUN,
	     HDT_SWITCH_TO_CLI, 0);

    if (hardware->is_pxe_valid == true) {
    add_item("<D>ump to tftp", "Dump to tftp", OPT_RUN,
	     HDT_DUMP, 0);
    }

    add_item("<A>bout", "About Menu", OPT_SUBMENU, NULL,
	     hdt_menu->about_menu.menu);
    add_item("<R>eboot", "Reboot", OPT_RUN, HDT_REBOOT, 0);
    add_item("E<x>it", "Exit", OPT_EXITMENU, NULL, 0);
    hdt_menu->main_menu.items_count++;

    hdt_menu->total_menu_count += hdt_menu->main_menu.items_count;
}
