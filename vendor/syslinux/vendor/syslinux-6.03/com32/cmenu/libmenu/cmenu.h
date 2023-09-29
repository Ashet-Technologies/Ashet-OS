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

/* This program can be compiled for DOS with the OpenWatcom compiler
 * (http://www.openwatcom.org/):
 *
 * wcl -3 -osx -mt <filename>.c
 */

#ifndef __MENU_H__
#define __MENU_H__

#include "com32io.h"
#include "tui.h"
#include "syslnx.h"
#include <string.h>
#include <unistd.h>

// TIMEOUT PARAMETERS
/* If no key is pressed within TIMEOUTNUMSTEPS * TIMEOUTSTEPSIZE milliseconds
   and if a timeout handler is registered, then that will be called.
   The handler should either either take control from there on, or return without
   producing any change in the current video settings.

   For e.g. the handler could
   * Could just quit the menu program
   * beep and return.

   TIMEOUTSTEPSIZE is the interval for which the program sleeps without checking for
   any keystroke. So increasing this will make the response of the system slow.
   Decreasing this will make a lot of interrupt calls using up your CPU. Default
   value of TIMEOUTSTEPSIZE of 0.1 seconds should be right in most cases.

   TIMEOUTNUMSTEPS of 3000 corresponds to a wait time of 300 seconds or 5 minutes
*/

#define TIMEOUTSTEPSIZE 10
#define TIMEOUTNUMSTEPS 30000L

// Attributes
#define NORMALATTR    0x17
#define NORMALHLITE   0x1F	// Normal Highlight attribute
#define REVERSEATTR   0x70
#define REVERSEHLITE  0x78	// Reverse Hightlight attribute
#define INACTATTR     0x18
#define INACTHLITE    0x10	// Inactive Highlight attribute
#define REVINACTATTR  0x78
#define REVINACTHLITE 0x70	// Reverse Inactive Highlight attr

#define STATUSATTR    0x74
#define STATUSHLITE   0x7B	// Status highlight

#define FILLCHAR      ' '
#define FILLATTR      NORMALATTR
#define SHADOWATTR    0x00
#define SPACECHAR     ' '

#define TFILLCHAR     ' '
#define TITLEATTR     0x70

#define ENABLEHLITE   '<'	// Char which turns on highlight
#define DISABLEHLITE  '>'	// Char which turns off highlight
#define NOHLITE       0		// The offset into attrib array for non-hilite
#define HLITE         1		// The offset for Hlite attrib

#define MOREABOVE    '^'		// char to print when more menu items available above
#define MOREBELOW    'v'		// more items available below

// Attributes of the menu system
#define MAXMENUS      250	// Maximum number of menu's allowed
#define MAXMENUSIZE   100	// Default value for max num of entries in each menu
#define MAXMENUHEIGHT 20	// Maximum number of entries displayed
#define MENUBOXTYPE   BOX_SINSIN	// Default box type Look at tui.h for other values

// Upper bounds on lengths
// We copy the given string, so user can reuse the space used to store incoming arguments.
#define MENULEN       78	// Each menu entry is atmost MENULEN chars
#define STATLEN       78	// Maximum length of status string
#define TITLELEN      78	// Maximum length of title string
#define ACTIONLEN     255	// Maximum length of an action string

// Layout of menu
#define MENUROW       3		// Row where menu is displayed (relative to window)
#define MENUCOL       4		// Col where menu is displayed (relative to window)
#define MENUPAGE      1		// show in display page 1
#define STATLINE      24	// Line number where status line starts (relative to window)

// Used for printing debugging messages
#define DEBUGLINE     23	// debugging info goes here

// Other Chars
#define RADIOMENUCHAR '>'	// > symbol for radio menu?
#define CHECKED       '\140'	// Check mark
#define UNCHECKED     '\146'	// Light bullet
#define RADIOSEL      '.'	// Current Radio Selection
#define RADIOUNSEL    ' '	// Radio option not selected

typedef unsigned char uchar;

// Types of menu's
#define NORMALMENU 1
#define RADIOMENU  2

typedef enum { OPT_INACTIVE, OPT_SUBMENU, OPT_RUN, OPT_EXITMENU, OPT_CHECKBOX,
    OPT_RADIOMENU, OPT_SEP, OPT_INVISIBLE,
    OPT_RADIOITEM
} t_action;

typedef union {
    uchar submenunum;		// For submenu's
    uchar checked;		// For check boxes
    uchar radiomenunum;		// Item mapping to a radio menu
} t_itemdata;

struct s_menuitem;
struct s_menu;
struct s_menusystem;

typedef struct {
    unsigned int valid:1;	// Is action valid?
    unsigned int refresh:1;	// Should we recompute menu stuff?
    unsigned int reserved:6;	// For future expansion
} t_handler_return;

t_handler_return ACTION_VALID, ACTION_INVALID;	// Specific values

typedef t_handler_return(*t_item_handler) (struct s_menusystem *,
					   struct s_menuitem *);
typedef void (*t_menusystem_handler) (struct s_menusystem *,
				      struct s_menuitem *);
typedef void (*t_keys_handler) (struct s_menusystem *, struct s_menuitem *,
				unsigned int scancode);
    // Last parameter = HIGH BYTE = scan code , LOW BYTE = ASCII CODE

typedef enum { HDLR_SCREEN, HDLR_KEYS } t_handler;
// Types of handlers for menu system

// TIMEOUT is the list of possible values which can be returned by the handler
// instructing the menusystem what to do. The default is CODE_WAIT
typedef enum { CODE_WAIT, CODE_ENTER, CODE_ESCAPE } TIMEOUTCODE;
typedef TIMEOUTCODE(*t_timeout_handler) (void);

typedef struct s_menuitem {
    char *item;
    char *status;
    char *data;			// string containing kernel to run.. but...
    // for radio menu's this is a pointer to the item selected or NULL (initially)
    // for submenu's this string could be name of menu
    void *extra_data;		// Any other data user can point to
    unsigned int helpid;	// Used for Context sensitive help
    t_item_handler handler;	// Pointer to function of type menufn
    t_action action;
    t_itemdata itemdata;	// Data depends on action value
    uchar shortcut;		// one of [A-Za-z0-9] shortcut for this menu item
    uchar index;		// Index within the menu array
    uchar parindex;		// Index of the menu in which this item appears.

} t_menuitem;

typedef t_menuitem *pt_menuitem;	// Pointer to type menuitem

typedef struct s_menu {
    pt_menuitem *items;		// pointer to array of pointer to menuitems
    char *title;		// Title string for menu
    char *name;			// menu can be referred to by this string
    int maxmenusize;		// the size of array allocated
    uchar numitems;		// how many items do we actually have
    uchar menuwidth;
    uchar row, col;		// Position where this menu should be displayed
    uchar menuheight;		// Maximum number of items to be displayed
} t_menu;

typedef t_menu *pt_menu;	// Pointer to type menu

typedef struct s_menusystem {
    pt_menu menus[MAXMENUS];
    char *title;
    t_menusystem_handler handler;	// Menu system handler
    t_keys_handler keys_handler;	// Handler for unknown keys
    t_timeout_handler ontimeout;	// Timeout handler
    unsigned long tm_numsteps;
    // Time to wait for key press=numsteps * stepsize milliseconds
    unsigned int tm_stepsize;	// Timeout step size (in milliseconds)
    // Total timeout max time spent idle before we call handler
    unsigned long tm_total_timeout;	// (in milli seconds)
    unsigned long tm_sofar_timeout;	// All accumulated timeout
    // total timeout handler
    t_timeout_handler ontotaltimeout;	// Total timeout handler

    int maxmenuheight;
    uchar nummenus;
    uchar normalattr[2];	// [0] is non-hlite attr, [1] is hlite attr
    uchar reverseattr[2];
    uchar inactattr[2];
    uchar revinactattr[2];
    uchar statusattr[2];
    uchar fillchar;
    uchar fillattr;
    uchar spacechar;
    uchar tfillchar;
    uchar titleattr;
    uchar shadowattr;
    uchar statline;
    uchar menupage;
    int maxrow, minrow, numrows;	// Number of rows in the window
    int maxcol, mincol, numcols;	// Number of columns in the window

    // Menu box look
    char box_horiz, box_ltrt, box_rtlt;	// Some chars of the box, for redrawing portions of the box

} t_menusystem;

typedef t_menusystem *pt_menusystem;	// Pointer to type menusystem

pt_menuitem showmenus(uchar startmenu);

pt_menusystem init_menusystem(const char *title);

void close_menusystem(void);	// Deallocate memory used

void set_normal_attr(uchar normal, uchar selected, uchar inactivenormal,
		     uchar inactiveselected);

void set_normal_hlite(uchar normal, uchar selected, uchar inactivenormal,
		      uchar inactiveselected);

void set_status_info(uchar statusattr, uchar statushlite, uchar statline);

void set_title_info(uchar tfillchar, uchar titleattr);

void set_misc_info(uchar fillchar, uchar fillattr, uchar spacechar,
		   uchar shadowattr);

void set_window_size(uchar top, uchar left, uchar bot, uchar right);	// Set the window which menusystem should use

void set_menu_options(uchar maxmenuheight);
// maximum height of a menu

void reg_handler(t_handler htype, void *handler);	// Register handler

void unreg_handler(t_handler htype);

void reg_ontimeout(t_timeout_handler, unsigned int numsteps,
		   unsigned int stepsize);
// Set timeout handler, set 0 for default values.
// So stepsize=0 means numsteps is measured in centiseconds.
void unreg_ontimeout(void);

void reg_ontotaltimeout(t_timeout_handler, unsigned long numcentiseconds);
void unreg_ontotaltimeout(void);

// Find the number of the menu given the name
// Returns -1 if not found
uchar find_menu_num(const char *name);

// Create a new menu and return its position
uchar add_menu(const char *title, int maxmenusize);

// Create a named menu and return its position
uchar add_named_menu(const char *name, const char *title, int maxmenusize);

void set_menu_pos(uchar row, uchar col);	// Set the position of this menu.

// Add item to the "current" menu
pt_menuitem add_item(const char *item, const char *status, t_action action,
		     const char *data, uchar itemdata);

// Set shortcut key and help id
void set_item_options(uchar shortcut, int helpid);

// Set the shortcut key for the current item
static inline void set_shortcut(uchar shortcut)
{
    set_item_options(shortcut, 0xFFFF);
}

// Add a separator to the "current" menu
pt_menuitem add_sep(void);

// Generate string based on state of checkboxes and radioitem in given menu
// and append string to existing contents of "line"
// line must have enough space allocated
void gen_append_line(const char *menu_name, char *line);

#endif
