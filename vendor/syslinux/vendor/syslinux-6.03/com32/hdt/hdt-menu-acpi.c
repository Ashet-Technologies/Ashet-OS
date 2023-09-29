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

void compute_table(struct s_my_menu *menu, void *address, s_acpi_description_header * h) {
    char buffer[SUBMENULEN + 1] = { 0 };
    char statbuffer[STATLEN + 1] = { 0 };

    snprintf(buffer, sizeof buffer, "%-4s v%03x %-6s %-8s %-7s %08x", 
		    h->signature, h->revision, h->oem_id, h->oem_table_id, h->creator_id, h->creator_revision);
    snprintf(statbuffer, sizeof statbuffer, "%-4s v%03x %-6s %-7s 0x%08x %-4s    0x%08x @ 0x%p", 
		    h->signature, h->revision, h->oem_id, h->oem_table_id,
		    h->oem_revision, h->creator_id, h->creator_revision, address);
    add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    menu->items_count++;

}

/* Submenu for the vesa card */
static void compute_acpi_tables(struct s_my_menu *menu,
			      struct s_hardware *hardware)
{
    menu->menu = add_menu(" ACPI Tables ", -1);
    menu->items_count = 0;
    set_menu_pos(SUBMENU_Y, SUBMENU_X);

    char buffer[SUBMENULEN + 1] = { 0 };

    snprintf(buffer, sizeof buffer, "%-4s %-4s %-6s %-8s %-7s %-8s", 
		    "ACPI", "rev", "oem", "table_id", "creator", "creator_rev");
    add_item(buffer, "Description", OPT_INACTIVE, NULL, 0);
    menu->items_count++;

    add_item("", "", OPT_SEP, "", 0);

    if (hardware->acpi.rsdt.valid)
        compute_table(menu,hardware->acpi.rsdt.address,
                       &hardware->acpi.rsdt.header);

    if (hardware->acpi.xsdt.valid)
        compute_table(menu,hardware->acpi.xsdt.address,
                       &hardware->acpi.xsdt.header);

    if (hardware->acpi.fadt.valid)
        compute_table(menu,hardware->acpi.fadt.address, &hardware->acpi.fadt.header);

    if (hardware->acpi.dsdt.valid)
        compute_table(menu,hardware->acpi.dsdt.address, &hardware->acpi.dsdt.header);

    /* SSDT includes many optional tables, let's display them */
    for (int i = 0; i < hardware->acpi.ssdt_count; i++) {
        if ((hardware->acpi.ssdt[i] != NULL) && (hardware->acpi.ssdt[i]->valid))
            compute_table(menu,hardware->acpi.ssdt[i]->address,
                        &hardware->acpi.ssdt[i]->header);
    }

    if (hardware->acpi.sbst.valid)
        compute_table(menu,hardware->acpi.sbst.address, &hardware->acpi.sbst.header);

    if (hardware->acpi.ecdt.valid)
        compute_table(menu,hardware->acpi.ecdt.address, &hardware->acpi.ecdt.header);

    if (hardware->acpi.hpet.valid)
        compute_table(menu,hardware->acpi.hpet.address, &hardware->acpi.hpet.header);

    if (hardware->acpi.tcpa.valid)
        compute_table(menu,hardware->acpi.tcpa.address, &hardware->acpi.tcpa.header);

    if (hardware->acpi.mcfg.valid)
        compute_table(menu,hardware->acpi.mcfg.address, &hardware->acpi.mcfg.header);
    
    if (hardware->acpi.slic.valid)
        compute_table(menu,hardware->acpi.slic.address, &hardware->acpi.slic.header);

    if (hardware->acpi.boot.valid)
        compute_table(menu,hardware->acpi.boot.address, &hardware->acpi.boot.header);

    /* FACS isn't having the same headers, let's use a dedicated rendering */
    if (hardware->acpi.facs.valid) {
	s_facs *fa = &hardware->acpi.facs;
        char buffer[SUBMENULEN + 1] = { 0 };
        char statbuffer[STATLEN + 1] = { 0 };

	snprintf(buffer, sizeof buffer, "%-4s", fa->signature); 
	snprintf(statbuffer, sizeof statbuffer, "%-4s @ 0x%p", fa->signature, fa->address);
	add_item(buffer, statbuffer, OPT_INACTIVE, NULL, 0);
    	menu->items_count++;
    }

    if (hardware->acpi.madt.valid)
        compute_table(menu,hardware->acpi.madt.address, &hardware->acpi.madt.header);

}

/* Main ACPI Menu*/
int compute_ACPI(struct s_hdt_menu *hdt_menu, struct s_hardware *hardware)
{
    compute_acpi_tables(&hdt_menu->acpi_tables_menu, hardware);
    hdt_menu->acpi_menu.menu = add_menu(" ACPI ", -1);
    hdt_menu->acpi_menu.items_count = 0;

    add_item("Tables", "Tables", OPT_SUBMENU, NULL,
	     hdt_menu->acpi_tables_menu.menu);
    hdt_menu->acpi_menu.items_count++;
    printf("MENU: ACPI menu done (%d items)\n",
	   hdt_menu->acpi_menu.items_count);
    return 0;
}
