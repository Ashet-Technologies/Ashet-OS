/* -*- c -*- ------------------------------------------------------------- *
 *
 *   Copyright 2004-2005 Murali Krishnan Ganapathy - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#ifndef NULL
#define NULL ((void *) 0)
#endif

#include "cmenu.h"
#include "com32io.h"
#include <string.h>

int main(void)
{
    t_menuitem *curr;

    // Change the video mode here
    // setvideomode(0)

    // Choose the default title and setup default values for all attributes....
    init_menusystem(NULL);
    set_window_size(1, 1, 23, 78);	// Leave one row/col border all around

    // Choose the default values for all attributes and char's
    // -1 means choose defaults (Actually the next 4 lines are not needed)
    //set_normal_attr (-1,-1,-1,-1);
    //set_status_info (-1,-1);
    //set_title_info  (-1,-1);
    //set_misc_info(-1,-1,-1,-1);

    // menuindex = add_named_menu("name"," Menu Title ",-1);
    // add_item("Item string","Status String",TYPE,"any string",NUM)
    //   TYPE = OPT_RUN | OPT_EXITMENU | OPT_SUBMENU | OPT_CHECKBOX | OPT_INACTIVE
    //   "any string" useful for storing kernel names
    //   In case of OPT_SUBMENU, "any string" can be set to "name" of menu to be linked
    //   in which case value NUM is ignored
    //   NUM = index of submenu if OPT_SUBMENU,
    //         0/1 default checked state if OPT_CHECKBOX
    //         unused otherwise.

    add_named_menu("testing", " Testing ", -1);
    add_item("Self Loop", "Go to testing", OPT_SUBMENU, "testing", 0);
    add_item("Memory Test", "Perform extensive memory testing", OPT_RUN,
	     "memtest", 0);
    add_item("Exit this menu", "Go one level up", OPT_EXITMENU, "exit", 0);

    add_named_menu("rescue", " Rescue Options ", -1);
    add_item("Linux Rescue", "linresc", OPT_RUN, "linresc", 0);
    add_item("Dos Rescue", "dosresc", OPT_RUN, "dosresc", 0);
    add_item("Windows Rescue", "winresc", OPT_RUN, "winresc", 0);
    add_item("Exit this menu", "Go one level up", OPT_EXITMENU, "exit", 0);

    add_named_menu("main", " Main Menu ", -1);
    add_item("Prepare", "prep", OPT_RUN, "prep", 0);
    add_item("Rescue options...", "Troubleshoot a system", OPT_SUBMENU,
	     "rescue", 0);
    add_item("Testing...", "Options to test hardware", OPT_SUBMENU, "testing",
	     0);
    add_item("Exit to prompt", "Exit the menu system", OPT_EXITMENU, "exit", 0);

    curr = showmenus(find_menu_num("main"));	// Initial menu is the one called "main"

    if (curr) {
	if (curr->action == OPT_RUN) {
	    if (issyslinux())
		runsyslinuxcmd(curr->data);
	    else
		csprint(curr->data, 0x07);
	    return 1;
	}
	csprint("Error in programming!", 0x07);
    }
    return 0;
}
