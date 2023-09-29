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
#include "help.h"
#include "passwords.h"
#include "des.h"
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <getkey.h>

/* Global variables */
char infoline[160];
char buffer[80];

// Different network options
static char nonet[] = "<n>etwork [none]";
static char dhcpnet[] = "<n>etwork [dhcp]";
static char statnet[] = "<n>etwork [static]";

static char loginstr[] = "<L>ogin  ";
static char logoutstr[] = "<L>ogout ";

struct {
    unsigned int baseurl:1;	// Do we need to specify by url
    unsigned int mountcd:1;	// Should we mount the cd
    unsigned int winrep:1;	// Want to repair windows?
    unsigned int linrep:1;	// Want to repair linux?
} flags;

// Some menu options
t_menuitem *baseurl, *mountcd, *network, *runprep, *winrep, *linrep;
t_menuitem *stat, *dhcp, *none, *prepopt, *secret;

// all the menus we are going to declare
unsigned char TESTING, RESCUE, MAIN, PREPMENU, NETMENU, LONGMENU, SECRETMENU;

char username[12];		// Name of user currently using the system

/* End globals */

TIMEOUTCODE ontimeout(void)
{
    beep();
    return CODE_WAIT;
}

#define INFLINE 22
#define PWDLINE 3
#define PWDPROMPT 21
#define PWDCOLUMN 60
#define PWDATTR 0x74
#define EDITPROMPT 21

void keys_handler(t_menusystem * ms __attribute__ (( unused )), t_menuitem * mi, int scancode)
{
    int nc, nr;

    if ((scancode) == KEY_F1 && mi->helpid != 0xFFFF) {	// If scancode of F1
	runhelpsystem(mi->helpid);
    }
    // If user hit TAB, and item is an "executable" item
    // and user has privileges to edit it, edit it in place.
    if ((scancode == KEY_TAB) && (mi->action == OPT_RUN) &&
	(isallowed(username, "editcmd") || isallowed(username, "root"))) {
    if (getscreensize(1, &nr, &nc)) {
        /* Unknown screen size? */
        nc = 80;
        nr = 24;
    }
	// User typed TAB and has permissions to edit command line
	gotoxy(EDITPROMPT, 1);
	csprint("Command line:", 0x07);
	editstring(mi->data, ACTIONLEN);
	gotoxy(EDITPROMPT, 1);
    clear_line();
    }
}

t_handler_return login_handler(t_menusystem * ms, t_menuitem * mi)
{
    (void)mi;			// Unused
    char pwd[40];
    char login[40];
    int nc, nr;
    t_handler_return rv;

    (void)ms;

    if (mi->item == loginstr) {	/* User wants to login */
    if (getscreensize(1, &nr, &nc)) {
        /* Unknown screen size? */
        nc = 80;
        nr = 24;
    }
	gotoxy(PWDPROMPT, 1);
	csprint("Enter Username: ", 0x07);
	getstring(login, sizeof username);
	gotoxy(PWDPROMPT, 1);
    clear_line();
	csprint("Enter Password: ", 0x07);
	getpwd(pwd, sizeof pwd);
	gotoxy(PWDPROMPT, 1);
    clear_line();

	if (authenticate_user(login, pwd)) {
	    strcpy(username, login);
	    mi->item = logoutstr;	// Change item to read "Logout"
	} else
	    strcpy(username, GUEST_USER);
    } else			// User needs to logout
    {
	strcpy(username, GUEST_USER);
	mi->item = loginstr;
    }

    if (strcmp(username, GUEST_USER) == 0) {
	prepopt->action = OPT_INACTIVE;
	secret->action = OPT_INVISIBLE;
    } else {
	prepopt->action = OPT_SUBMENU;
	prepopt->itemdata.radiomenunum = PREPMENU;
	secret->action = OPT_SUBMENU;
	secret->itemdata.submenunum = SECRETMENU;
    }
    rv.valid = 0;
    rv.refresh = 1;
    rv.reserved = 0;
    return rv;
}

void msys_handler(t_menusystem * ms, t_menuitem * mi)
{
    int nc, nr;
    void *v;

    if (getscreensize(1, &nr, &nc)) {
        /* Unknown screen size? */
        nc = 80;
        nr = 24;
    }
    gotoxy(PWDLINE, PWDCOLUMN);
    csprint("User: ", PWDATTR);
    cprint(ms->fillchar, ms->fillattr, sizeof username);
    gotoxy(PWDLINE, PWDCOLUMN + 6);
    csprint(username, PWDATTR);

    if (mi->parindex != PREPMENU)	// If we are not in the PREP MENU
    {
	gotoxy(INFLINE, 0);
    reset_colors();
    clear_line();
	gotoxy(INFLINE + 1, 0);
    clear_line();
	return;
    }
    strcpy(infoline, " ");
    if (flags.baseurl)
	strcat(infoline, "baseurl=http://192.168.11.12/gui ");
    if (flags.mountcd)
	strcat(infoline, "mountcd=yes ");
    v = (void *)network->data;
    if (v != NULL)		// Some network option specified
    {
	strcat(infoline, "network=");
	strcat(infoline, (char *)(((t_menuitem *) v)->data));
    }
    if (flags.winrep)
	strcat(infoline, "repair=win ");
    if (flags.linrep)
	strcat(infoline, "repair=lin ");

    gotoxy(INFLINE, 0);
    reset_colors();
    clear_line();
    gotoxy(INFLINE + 1, 0);
    clear_line();
    gotoxy(INFLINE, 0);
    csprint("Kernel Arguments:", 0x07);
    gotoxy(INFLINE, 17);
    csprint(infoline, 0x07);
}

t_handler_return network_handler(t_menusystem * ms, t_menuitem * mi)
{
    // mi=network since this is handler only for that.
    (void)ms;			// Unused

    if (mi->data == (void *)none)
	mi->item = nonet;
    if (mi->data == (void *)stat)
	mi->item = statnet;
    if (mi->data == (void *)dhcp)
	mi->item = dhcpnet;
    return ACTION_INVALID;	// VALID or INVALID does not matter
}

t_handler_return checkbox_handler(t_menusystem * ms, t_menuitem * mi)
{
    (void)ms;			/* Unused */

    t_handler_return rv;

    if (mi->action != OPT_CHECKBOX)
	return ACTION_INVALID;

    if (strcmp(mi->data, "baseurl") == 0)
	flags.baseurl = (mi->itemdata.checked ? 1 : 0);
    if (strcmp(mi->data, "winrepair") == 0) {
	if (mi->itemdata.checked) {
	    flags.winrep = 1;
	    linrep->action = OPT_INACTIVE;
	} else {
	    flags.winrep = 0;
	    linrep->action = OPT_CHECKBOX;
	}
    }
    if (strcmp(mi->data, "linrepair") == 0) {
	if (mi->itemdata.checked) {
	    flags.linrep = 1;
	    winrep->action = OPT_INACTIVE;
	} else {
	    flags.winrep = 0;
	    winrep->action = OPT_CHECKBOX;
	}
    }
    if (strcmp(mi->data, "mountcd") == 0)
	flags.mountcd = (mi->itemdata.checked ? 1 : 0);

    rv.valid = 0;
    rv.refresh = 1;
    rv.reserved = 0;
    return rv;
}

int main(void)
{
    t_menuitem *curr;
    char cmd[160];
    char ip[30];

    // Set default username as guest
    strcpy(username, GUEST_USER);

    // Switch video mode here
    // setvideomode(0x18); // or whatever mode you want

    // Choose the default title and setup default values for all attributes....
    init_passwords("/isolinux/password");
    init_help("/isolinux/help");
    init_menusystem(NULL);
    set_window_size(1, 1, 20, 78);	// Leave some space around

    // Choose the default values for all attributes and char's
    // -1 means choose defaults (Actually the next 4 lines are not needed)
    //set_normal_attr (-1,-1,-1,-1);
    //set_status_info (-1,-1); // Display status on the last line
    //set_title_info  (-1,-1);
    //set_misc_info(-1,-1,-1,-1);

    // Register the menusystem handler
    reg_handler(HDLR_SCREEN, &msys_handler);
    reg_handler(HDLR_KEYS, &keys_handler);
    // Register the ontimeout handler, with a time out of 10 seconds
    reg_ontimeout(ontimeout, 10, 0);

    NETMENU = add_menu(" Init Network ", -1);
    none = add_item("<N>one", "Dont start network", OPT_RADIOITEM, "no ", 0);
    dhcp = add_item("<d>hcp", "Use DHCP", OPT_RADIOITEM, "dhcp ", 0);
    stat =
	add_item("<s>tatic", "Use static IP I will specify later",
		 OPT_RADIOITEM, "static ", 0);

    TESTING = add_menu(" Testing ", -1);
    set_menu_pos(5, 55);
    add_item("<M>emory Test", "Perform extensive memory testing", OPT_RUN,
	     "memtest", 0);
    add_item("<I>nvisible", "You dont see this", OPT_INVISIBLE, "junk", 0);
    add_item("<E>xit this menu", "Go one level up", OPT_EXITMENU, "exit", 0);

    RESCUE = add_menu(" Rescue Options ", -1);
    add_item("<L>inux Rescue", "linresc", OPT_RUN, "linresc", 0);
    add_item("<D>os Rescue", "dosresc", OPT_RUN, "dosresc", 0);
    add_item("<W>indows Rescue", "winresc", OPT_RUN, "winresc", 0);
    add_item("<E>xit this menu", "Go one level up", OPT_EXITMENU, "exit", 0);

    PREPMENU = add_menu(" Prep options ", -1);
    baseurl =
	add_item("<b>aseurl by IP?", "Specify gui baseurl by IP address",
		 OPT_CHECKBOX, "baseurl", 0);
    mountcd =
	add_item("<m>ountcd?", "Mount the cdrom drive?", OPT_CHECKBOX,
		 "mountcd", 0);
    network =
	add_item(dhcpnet, "How to initialise network device?", OPT_RADIOMENU,
		 NULL, NETMENU);
    add_sep();
    winrep =
	add_item("Reinstall <w>indows",
		 "Re-install the windows side of a dual boot setup",
		 OPT_CHECKBOX, "winrepair", 0);
    linrep =
	add_item("Reinstall <l>inux",
		 "Re-install the linux side of a dual boot setup", OPT_CHECKBOX,
		 "linrepair", 0);
    add_sep();
    runprep =
	add_item("<R>un prep now", "Execute prep with the above options",
		 OPT_RUN, "prep", 0);
    add_item("<E>xit this menu", "Go up one level", OPT_EXITMENU, "exitmenu",
	     0);
    baseurl->handler = &checkbox_handler;
    mountcd->handler = &checkbox_handler;
    winrep->handler = &checkbox_handler;
    linrep->handler = &checkbox_handler;
    network->handler = &network_handler;
    flags.baseurl = 0;
    flags.mountcd = 0;
    flags.winrep = 0;
    flags.linrep = 0;

    SECRETMENU = add_menu(" Secret Menu ", -1);
    add_item("secret 1", "Secret", OPT_RUN, "A", 0);
    add_item("secret 2", "Secret", OPT_RUN, "A", 0);

    LONGMENU = add_menu(" Long Menu ", 40);	// Override default here
    add_item("<A>a", "Aa", OPT_RUN, "A", 0);
    add_item("<B>b", "Ab", OPT_RUN, "A", 0);
    add_item("<C>", "A", OPT_RUN, "A", 0);
    add_item("<D>", "A", OPT_RUN, "A", 0);
    add_item("<E>", "A", OPT_RUN, "A", 0);
    add_item("<F>", "A", OPT_RUN, "A", 0);
    add_item("<G>", "A", OPT_RUN, "A", 0);
    add_item("<H>", "A", OPT_RUN, "A", 0);
    add_item("<I>", "A", OPT_RUN, "A", 0);
    add_item("<J>", "A", OPT_RUN, "A", 0);
    add_item("<K>", "A", OPT_RUN, "A", 0);
    add_item("<L>", "A", OPT_RUN, "A", 0);
    add_item("<J>", "A", OPT_RUN, "A", 0);
    add_item("<K>", "A", OPT_RUN, "A", 0);
    add_item("<L>", "A", OPT_RUN, "A", 0);
    add_item("<M>", "A", OPT_RUN, "A", 0);
    add_item("<N>", "A", OPT_RUN, "A", 0);
    add_item("<O>", "A", OPT_RUN, "A", 0);
    add_item("<P>", "A", OPT_RUN, "A", 0);
    add_item("<Q>", "A", OPT_RUN, "A", 0);
    add_item("<R>", "A", OPT_RUN, "A", 0);
    add_item("<S>", "A", OPT_RUN, "A", 0);
    add_item("<T>", "A", OPT_RUN, "A", 0);
    add_item("<U>", "A", OPT_RUN, "A", 0);
    add_item("<V>", "A", OPT_RUN, "A", 0);
    add_item("<W>", "A", OPT_RUN, "A", 0);
    add_item("<X>", "A", OPT_RUN, "A", 0);
    add_item("<Y>", "A", OPT_RUN, "A", 0);
    add_item("<Z>", "A", OPT_RUN, "A", 0);
    add_item("<1>", "A", OPT_RUN, "A", 0);
    add_item("<2>", "A", OPT_RUN, "A", 0);
    add_item("<3>", "A", OPT_RUN, "A", 0);
    add_item("<4>", "A", OPT_RUN, "A", 0);
    add_item("<5>", "A", OPT_RUN, "A", 0);
    add_item("<6>", "A", OPT_RUN, "A", 0);
    add_item("<7>", "A", OPT_RUN, "A", 0);
    add_item("<8>", "A", OPT_RUN, "A", 0);
    add_item("<9>", "A", OPT_RUN, "A", 0);

    MAIN = add_menu(" Main Menu ", 8);
    curr = add_item(loginstr, "Login as a privileged user", OPT_RUN, NULL, 0);
    set_item_options(-1, 23);
    curr->handler = &login_handler;

    add_item("<P>repare", "prep", OPT_RUN, "prep", 0);
    set_item_options(-1, 24);
    prepopt =
	add_item("<P>rep options...",
		 "Options for prep image: Requires authenticated user",
		 OPT_INACTIVE, NULL, PREPMENU);
    set_item_options(-1, 25);

    add_item("<R>escue options...", "Troubleshoot a system", OPT_SUBMENU, NULL,
	     RESCUE);
    set_item_options(-1, 26);
    add_item("<T>esting...", "Options to test hardware", OPT_SUBMENU, NULL,
	     TESTING);
    set_item_options(-1, 27);
    add_item("<L>ong Menu...", "test menu system", OPT_SUBMENU, NULL, LONGMENU);
    set_item_options(-1, 28);
    secret =
	add_item("<S>ecret Menu...", "Secret menu", OPT_INVISIBLE, NULL,
		 SECRETMENU);
    set_item_options(-1, 29);
    add_item("<E>xit to prompt", "Exit the menu system", OPT_EXITMENU, "exit",
	     0);
    set_item_options(-1, 30);
    csprint("Press any key within 5 seconds to show menu...", 0x07);
    if (get_key(stdin, 50) == KEY_NONE)	// Granularity of 100 milliseconds
    {
	csprint("Sorry! Time's up.\r\n", 0x07);
	return 1;
    }
    curr = showmenus(MAIN);
    if (curr) {
	if (curr->action == OPT_RUN) {
	    strcpy(cmd, curr->data);
	    if (curr == runprep) {
		strcat(cmd, infoline);
		if (network->data == (void *)stat)	// We want static
		{
		    csprint("Enter IP address (last two octets only): ", 0x07);
		    strcpy(ip, "Junk");
		    editstring(ip, sizeof ip);
		    strcat(cmd, "ipaddr=192.168.");
		    strcat(cmd, ip);
		}
	    }
	    if (issyslinux())
		runsyslinuxcmd(cmd);
	    else
		csprint(cmd, 0x07);
	    return 1;		// Should not happen when run from SYSLINUX
	}
    }
    // If user quits the menu system, control comes here
    // If you want to execute some specific command uncomment the next two lines

    // if (syslinux) runcommand(YOUR_COMMAND_HERE);
    // else csprint(YOUR_COMMAND_HERE,0x07);

    // Deallocate space used for these data structures
    close_passwords();
    close_help();
    close_menusystem();

    // Return to prompt
    return 0;
}
