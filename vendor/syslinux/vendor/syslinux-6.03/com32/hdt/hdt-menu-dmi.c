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

/* Compute System main menu */
void compute_system(struct s_my_menu *menu, s_dmi * dmi)
{
    char buffer[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];

    menu->menu = add_menu(" System ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    snprintf(buffer, sizeof buffer, "Vendor    : %s", dmi->system.manufacturer);
    snprintf(statbuffer, sizeof statbuffer, "Vendor: %s",
	     dmi->system.manufacturer);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Product   : %s", dmi->system.product_name);
    snprintf(statbuffer, sizeof statbuffer, "Product Name: %s",
	     dmi->system.product_name);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Version   : %s", dmi->system.version);
    snprintf(statbuffer, sizeof statbuffer, "Version: %s", dmi->system.version);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Serial    : %s", dmi->system.serial);
    snprintf(statbuffer, sizeof statbuffer, "Serial Number: %s",
	     dmi->system.serial);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "UUID      : %s", dmi->system.uuid);
    snprintf(statbuffer, sizeof statbuffer, "UUID: %s", dmi->system.uuid);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Wakeup    : %s", dmi->system.wakeup_type);
    snprintf(statbuffer, sizeof statbuffer, "Wakeup Type: %s",
	     dmi->system.wakeup_type);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "SKU Number: %s", dmi->system.sku_number);
    snprintf(statbuffer, sizeof statbuffer, "SKU Number: %s",
	     dmi->system.sku_number);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Family    : %s", dmi->system.family);
    snprintf(statbuffer, sizeof statbuffer, "Family: %s", dmi->system.family);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    printf("MENU: System menu done (%d items)\n", menu->items_count);
}

/* Compute Chassis menu */
void compute_chassis(struct s_my_menu *menu, s_dmi * dmi)
{
    char buffer[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];
    menu->menu = add_menu(" Chassis ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    snprintf(buffer, sizeof buffer, "Vendor    : %s",
	     dmi->chassis.manufacturer);
    snprintf(statbuffer, sizeof statbuffer, "Vendor: %s",
	     dmi->chassis.manufacturer);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Type      : %s", dmi->chassis.type);
    snprintf(statbuffer, sizeof statbuffer, "Type: %s", dmi->chassis.type);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Version   : %s", dmi->chassis.version);
    snprintf(statbuffer, sizeof statbuffer, "Version: %s",
	     dmi->chassis.version);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Serial    : %s", dmi->chassis.serial);
    snprintf(statbuffer, sizeof statbuffer, "Serial Number: %s",
	     dmi->chassis.serial);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Asset Tag : %s",
	     del_multi_spaces(dmi->chassis.asset_tag));
    snprintf(statbuffer, sizeof statbuffer, "Asset Tag: %s",
	     del_multi_spaces(dmi->chassis.asset_tag));
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Lock      : %s", dmi->chassis.lock);
    snprintf(statbuffer, sizeof statbuffer, "Lock: %s", dmi->chassis.lock);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    printf("MENU: Chassis menu done (%d items)\n", menu->items_count);
}

/* Compute BIOS menu */
void compute_bios(struct s_my_menu *menu, s_dmi * dmi)
{
    char buffer[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];

    menu->menu = add_menu(" BIOS ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    snprintf(buffer, sizeof buffer, "Vendor    : %s", dmi->bios.vendor);
    snprintf(statbuffer, sizeof statbuffer, "Vendor: %s", dmi->bios.vendor);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Version   : %s", dmi->bios.version);
    snprintf(statbuffer, sizeof statbuffer, "Version: %s", dmi->bios.version);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Release   : %s", dmi->bios.release_date);
    snprintf(statbuffer, sizeof statbuffer, "Release Date: %s",
	     dmi->bios.release_date);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Bios Rev. : %s", dmi->bios.bios_revision);
    snprintf(statbuffer, sizeof statbuffer, "Bios Revision: %s",
	     dmi->bios.bios_revision);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Fw.  Rev. : %s",
	     dmi->bios.firmware_revision);
    snprintf(statbuffer, sizeof statbuffer, "Firmware Revision : %s",
	     dmi->bios.firmware_revision);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);

    printf("MENU: BIOS menu done (%d items)\n", menu->items_count);
}

/* Compute Motherboard main menu */
void compute_motherboard(struct s_my_menu *menu, s_dmi * dmi)
{
    char buffer[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];

    menu->menu = add_menu(" Motherboard ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    snprintf(buffer, sizeof buffer, "Vendor    : %s",
	     dmi->base_board.manufacturer);
    snprintf(statbuffer, sizeof statbuffer, "Vendor: %s",
	     dmi->base_board.manufacturer);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Product   : %s",
	     dmi->base_board.product_name);
    snprintf(statbuffer, sizeof statbuffer, "Product Name: %s",
	     dmi->base_board.product_name);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Version   : %s", dmi->base_board.version);
    snprintf(statbuffer, sizeof statbuffer, "Version: %s",
	     dmi->base_board.version);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Serial    : %s", dmi->base_board.serial);
    snprintf(statbuffer, sizeof statbuffer, "Serial Number: %s",
	     dmi->base_board.serial);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Asset Tag : %s",
	     dmi->base_board.asset_tag);
    snprintf(statbuffer, sizeof statbuffer, "Asset Tag: %s",
	     dmi->base_board.asset_tag);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Location  : %s", dmi->base_board.location);
    snprintf(statbuffer, sizeof statbuffer, "Location: %s",
	     dmi->base_board.location);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Type      : %s", dmi->base_board.type);
    snprintf(statbuffer, sizeof statbuffer, "Type: %s", dmi->base_board.type);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    printf("MENU: Motherboard menu done (%d items)\n", menu->items_count);
}

/* Compute Main IPMI menu */
void compute_ipmi(struct s_my_menu *menu, s_dmi * dmi)
{
    char buffer[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];
    menu->menu = add_menu(" IPMI ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    snprintf(buffer, sizeof buffer, "Interface Type  : %s",
	     dmi->ipmi.interface_type);
    snprintf(statbuffer, sizeof statbuffer, "Interface Type: %s",
	     dmi->ipmi.interface_type);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Spec. Version   : %u.%u",
	     dmi->ipmi.major_specification_version,
	     dmi->ipmi.minor_specification_version);
    snprintf(statbuffer, sizeof statbuffer, "Specification Version: %u.%u",
	     dmi->ipmi.major_specification_version,
	     dmi->ipmi.minor_specification_version);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "I2C Slave @     : 0x%02x",
	     dmi->ipmi.I2C_slave_address);
    snprintf(statbuffer, sizeof statbuffer, "I2C Slave Address: 0x%02x",
	     dmi->ipmi.I2C_slave_address);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "NV Storage @    : %u",
	     dmi->ipmi.nv_address);
    snprintf(statbuffer, sizeof statbuffer, "NV Storage Address: %u",
	     dmi->ipmi.nv_address);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    uint32_t high = dmi->ipmi.base_address >> 32;
    uint32_t low = dmi->ipmi.base_address & 0xFFFF;

    snprintf(buffer, sizeof buffer, "Base Address    : %08X%08X",
	     high, (low & ~1));
    snprintf(statbuffer, sizeof statbuffer, "Base Address : %08X%08X",
	     high, (low & ~1));
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "IRQ             : %d", dmi->ipmi.irq);
    snprintf(statbuffer, sizeof statbuffer, "IRQ : %d", dmi->ipmi.irq);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    printf("MENU: IPMI menu done (%d items)\n", menu->items_count);
}

/* Compute Main Battery menu */
void compute_battery(struct s_my_menu *menu, s_dmi * dmi)
{
    char buffer[SUBMENULEN + 1];
    char statbuffer[STATLEN + 1];
    menu->menu = add_menu(" Battery ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    snprintf(buffer, sizeof buffer, "Vendor          : %s",
	     dmi->battery.manufacturer);
    snprintf(statbuffer, sizeof statbuffer, "Vendor: %s",
	     dmi->battery.manufacturer);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Manufacture Date: %s",
	     dmi->battery.manufacture_date);
    snprintf(statbuffer, sizeof statbuffer, "Manufacture Date: %s",
	     dmi->battery.manufacture_date);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Serial          : %s",
	     dmi->battery.serial);
    snprintf(statbuffer, sizeof statbuffer, "Serial: %s", dmi->battery.serial);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Name            : %s", dmi->battery.name);
    snprintf(statbuffer, sizeof statbuffer, "Name: %s", dmi->battery.name);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Chemistry       : %s",
	     dmi->battery.chemistry);
    snprintf(statbuffer, sizeof statbuffer, "Chemistry: %s",
	     dmi->battery.chemistry);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Design Capacity : %s",
	     dmi->battery.design_capacity);
    snprintf(statbuffer, sizeof statbuffer, "Design Capacity: %s",
	     dmi->battery.design_capacity);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Design Voltage  : %s",
	     dmi->battery.design_voltage);
    snprintf(statbuffer, sizeof statbuffer, "Design Voltage : %s",
	     dmi->battery.design_voltage);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "SBDS            : %s", dmi->battery.sbds);
    snprintf(statbuffer, sizeof statbuffer, "SBDS: %s", dmi->battery.sbds);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "SBDS Manuf. Date: %s",
	     dmi->battery.sbds_manufacture_date);
    snprintf(statbuffer, sizeof statbuffer, "SBDS Manufacture Date: %s",
	     dmi->battery.sbds_manufacture_date);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "SBDS Chemistry  : %s",
	     dmi->battery.sbds_chemistry);
    snprintf(statbuffer, sizeof statbuffer, "SBDS Chemistry : %s",
	     dmi->battery.sbds_chemistry);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "Maximum Error   : %s",
	     dmi->battery.maximum_error);
    snprintf(statbuffer, sizeof statbuffer, "Maximum Error (percent) : %s",
	     dmi->battery.maximum_error);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    snprintf(buffer, sizeof buffer, "OEM Info        : %s",
	     dmi->battery.oem_info);
    snprintf(statbuffer, sizeof statbuffer, "OEM Info: %s",
	     dmi->battery.oem_info);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    printf("MENU: Battery menu done (%d items)\n", menu->items_count);
}
