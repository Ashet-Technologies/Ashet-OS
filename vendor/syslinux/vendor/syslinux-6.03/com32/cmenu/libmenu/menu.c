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

#include "cmenu.h"
#include "com32io.h"
#include <stdlib.h>
#include <console.h>

// Local Variables
static pt_menusystem ms;    // Pointer to the menusystem
char TITLESTR[] =
    "COMBOOT Menu System for SYSLINUX developed by Murali Krishnan Ganapathy";
char TITLELONG[] = " TITLE too long ";
char ITEMLONG[] = " ITEM too long ";
char ACTIONLONG[] = " ACTION too long ";
char STATUSLONG[] = " STATUS too long ";
char EMPTYSTR[] = "";

/* Forward declarations */
int calc_visible(pt_menu menu, int first);
int next_visible(pt_menu menu, int index);
int prev_visible(pt_menu menu, int index);
int next_visible_sep(pt_menu menu, int index);
int prev_visible_sep(pt_menu menu, int index);
int calc_first_early(pt_menu menu, int curr);
int calc_first_late(pt_menu menu, int curr);
int isvisible(pt_menu menu, int first, int curr);

/* Basic Menu routines */

// This is same as inputc except it honors the ontimeout handler
// and calls it when needed. For the callee, there is no difference
// as this will not return unless a key has been pressed.
static int getch(void)
{
    t_timeout_handler th;
    int key;
    unsigned long i;

    // Wait until keypress if no handler specified
    if ((ms->ontimeout == NULL) && (ms->ontotaltimeout == NULL))
        return get_key(stdin, 0);

    th = ms->ontimeout;
    for (;;) {
        for (i = 0; i < ms->tm_numsteps; i++) {
            key = get_key(stdin, ms->tm_stepsize);
            if (key != KEY_NONE)
                return key;

            if ((ms->tm_total_timeout == 0) || (ms->ontotaltimeout == NULL))
                continue;   // Dont bother with calculations if no handler
            ms->tm_sofar_timeout += ms->tm_stepsize;
            if (ms->tm_sofar_timeout >= ms->tm_total_timeout) {
                th = ms->ontotaltimeout;
                ms->tm_sofar_timeout = 0;
                break;      // Get out of the for loop
            }
        }
        if (!th)
            continue;       // no handler
        key = th();
        switch (key) {
        case CODE_ENTER:    // Pretend user hit enter
            return KEY_ENTER;
        case CODE_ESCAPE:   // Pretend user hit escape
            return KEY_ESC;
        default:
            break;
        }
    }
    return KEY_NONE;
}

int find_shortcut(pt_menu menu, uchar shortcut, int index)
// Find the next index with specified shortcut key
{
    int ans;
    pt_menuitem mi;

    // Garbage in garbage out
    if ((index < 0) || (index >= menu->numitems))
    return index;
    ans = index + 1;
    // Go till end of menu
    while (ans < menu->numitems) {
    mi = menu->items[ans];
    if ((mi->action == OPT_INVISIBLE) || (mi->action == OPT_SEP)
        || (mi->shortcut != shortcut))
        ans++;
    else
        return ans;
    }
    // Start at the beginning and try again
    ans = 0;
    while (ans < index) {
    mi = menu->items[ans];
    if ((mi->action == OPT_INVISIBLE) || (mi->action == OPT_SEP)
        || (mi->shortcut != shortcut))
        ans++;
    else
        return ans;
    }
    return index;       // Sorry not found
}

/* Redraw background and title */
static void reset_ui(void)
{
    uchar tpos;

    cls();
    clearwindow(ms->minrow, ms->mincol, ms->maxrow, ms->maxcol,
                ms->fillchar, ms->fillattr);

    tpos = (ms->numcols - strlen(ms->title) - 1) >> 1;  // center it on line
    gotoxy(ms->minrow, ms->mincol);
    cprint(ms->tfillchar, ms->titleattr, ms->numcols);
    gotoxy(ms->minrow, ms->mincol + tpos);
    csprint(ms->title, ms->titleattr);

    cursoroff();
}

/*
 * Print a menu item
 *
 * attr[0] is non-hilite attr, attr[1] is highlight attr
 */
void printmenuitem(const char *str, uchar * attr)
{
    int hlite = NOHLITE;    // Initially no highlighting

    while (*str) {
        switch (*str) {
            case BELL:      // No Bell Char
                break;
            case ENABLEHLITE:   // Switch on highlighting
                hlite = HLITE;
                break;
            case DISABLEHLITE:  // Turn off highlighting
                hlite = NOHLITE;
                break;
            default:
                putch(*str, attr[hlite]);
        }
        str++;
    }
}


/**
 * print_line - Print a whole line in a menu
 * @menu:   current menu to handle
 * @curr:   index of the current entry highlighted
 * @top:    top coordinate of the @menu
 * @left:   left coordinate of the @menu
 * @x:      index in the menu of curr
 * @row:    row currently displayed
 * @radio:  radio item?
 **/
static void print_line(pt_menu menu, int curr, uchar top, uchar left,
                       int x, int row, bool radio)
{
    pt_menuitem ci;
    char fchar[6], lchar[6];    // The first and last char in for each entry
    const char *str;            // Item string (cf printmenuitem)
    char sep[MENULEN];          // Separator (OPT_SEP)
    uchar *attr;                // Attribute
    int menuwidth = menu->menuwidth + 3;

    if (row >= menu->menuheight)
        return;

    ci = menu->items[x];

    memset(sep, ms->box_horiz, menuwidth);
    sep[menuwidth - 1] = 0;

    // Setup the defaults now
    if (radio) {
        fchar[0] = '\b';
        fchar[1] = SO;
        fchar[2] = (x == curr ? RADIOSEL : RADIOUNSEL);
        fchar[3] = SI;
        fchar[4] = '\0';    // Unselected ( )
        lchar[0] = '\0';    // Nothing special after
        attr = ms->normalattr;  // Always same attribute
    } else {
        lchar[0] = fchar[0] = ' ';
        lchar[1] = fchar[1] = '\0'; // fchar and lchar are just spaces
        attr = (x == curr ? ms->reverseattr : ms->normalattr);  // Normal attributes
    }
    str = ci->item;     // Pointer to item string
    switch (ci->action) // set up attr,str,fchar,lchar for everything
    {
    case OPT_INACTIVE:
        if (radio)
            attr = ms->inactattr;
        else
            attr = (x == curr ? ms->revinactattr : ms->inactattr);
        break;
    case OPT_SUBMENU:
        if (radio)
            break;      // Not supported for radio menu
        lchar[0] = '>';
        lchar[1] = 0;
        break;
    case OPT_RADIOMENU:
        if (radio)
            break;      // Not supported for radio menu
        lchar[0] = RADIOMENUCHAR;
        lchar[1] = 0;
        break;
    case OPT_CHECKBOX:
        if (radio)
            break;      // Not supported for radio menu
        lchar[0] = '\b';
        lchar[1] = SO;
        lchar[2] = (ci->itemdata.checked ? CHECKED : UNCHECKED);
        lchar[3] = SI;
        lchar[4] = 0;
        break;
    case OPT_SEP:
        fchar[0] = '\b';
        fchar[1] = SO;
        fchar[2] = LEFT_MIDDLE_BORDER;
        fchar[3] = MIDDLE_BORDER;
        fchar[4] = MIDDLE_BORDER;
        fchar[5] = 0;
        memset(sep, MIDDLE_BORDER, menuwidth);
        sep[menuwidth - 1] = 0;
        str = sep;
        lchar[0] = MIDDLE_BORDER;
        lchar[1] = RIGHT_MIDDLE_BORDER;
        lchar[2] = SI;
        lchar[3] = 0;
        break;
    case OPT_EXITMENU:
        if (radio)
            break;      // Not supported for radio menu
        fchar[0] = '<';
        fchar[1] = 0;
        break;
    default:        // Just to keep the compiler happy
        break;
    }

    // Wipe area with spaces
    gotoxy(top + row, left - 2);
    cprint(ms->spacechar, attr[NOHLITE], menuwidth + 2);

    // Print first part
    gotoxy(top + row, left - 2);
    csprint(fchar, attr[NOHLITE]);

    // Print main part
    gotoxy(top + row, left);
    printmenuitem(str, attr);

    // Print last part
    gotoxy(top + row, left + menuwidth - 1);
    csprint(lchar, attr[NOHLITE]);
}

// print the menu starting from FIRST
// will print a maximum of menu->menuheight items
static void printmenu(pt_menu menu, int curr, uchar top, uchar left, uchar first, bool radio)
{
    int x, row;         // x = index, row = position from top
    int numitems, menuwidth;
    pt_menuitem ci;

    numitems = calc_visible(menu, first);
    if (numitems > menu->menuheight)
    numitems = menu->menuheight;

    menuwidth = menu->menuwidth + 3;
    clearwindow(top, left - 2, top + numitems + 1, left + menuwidth + 1,
        ms->fillchar, ms->shadowattr);
    drawbox(top - 1, left - 3, top + numitems, left + menuwidth,
        ms->normalattr[NOHLITE]);

    // Menu title
    x = (menuwidth - strlen(menu->title) - 1) >> 1;
    gotoxy(top - 1, left + x);
    printmenuitem(menu->title, ms->normalattr);

    // All lines in the menu
    row = -1;           // 1 less than inital value of x
    for (x = first; x < menu->numitems; x++) {
        ci = menu->items[x];
        if (ci->action == OPT_INVISIBLE)
            continue;
        row++;
        if (row >= numitems)
            break;      // Already have enough number of items
        print_line(menu, curr, top, left, x, row, radio);
    }
    // Check if we need to MOREABOVE and MOREBELOW to be added
    // reuse x
    row = 0;
    x = next_visible_sep(menu, 0);  // First item
    if (!isvisible(menu, first, x)) // There is more above
    {
    row = 1;
    gotoxy(top, left + menuwidth);
    cprint(MOREABOVE, ms->normalattr[NOHLITE], 1);
    }
    x = prev_visible_sep(menu, menu->numitems); // last item
    if (!isvisible(menu, first, x)) // There is more above
    {
    row = 1;
    gotoxy(top + numitems - 1, left + menuwidth);
    cprint(MOREBELOW, ms->normalattr[NOHLITE], 1);
    }
    // Add a scroll box
    x = ((numitems - 1) * curr) / (menu->numitems);
    if ((x > 0) && (row == 1)) {
    gotoxy(top + x, left + menuwidth);
    csprint("\016\141\017", ms->normalattr[NOHLITE]);
    }
    if (ms->handler)
    ms->handler(ms, menu->items[curr]);
}

void cleanupmenu(pt_menu menu, uchar top, uchar left, int numitems)
{
    if (numitems > menu->menuheight)
    numitems = menu->menuheight;
    clearwindow(top, left - 2, top + numitems + 1, left + menu->menuwidth + 4, ms->fillchar, ms->fillattr); // Clear the shadow
    clearwindow(top - 1, left - 3, top + numitems, left + menu->menuwidth + 3, ms->fillchar, ms->fillattr); // main window
}


/* Handle one menu */
static pt_menuitem getmenuoption(pt_menu menu, uchar top, uchar left, uchar startopt, bool radio)
     // Return item chosen or NULL if ESC was hit.
{
    int prev, prev_first, curr, i, first, tmp;
    int asc = 0;
    bool redraw = true; // Need to draw the menu the first time
    uchar numitems;
    pt_menuitem ci;     // Current item
    t_handler_return hr;    // Return value of handler

    numitems = calc_visible(menu, 0);
    // Setup status line
    gotoxy(ms->minrow + ms->statline, ms->mincol);
    cprint(ms->spacechar, ms->statusattr[NOHLITE], ms->numcols);

    // Initialise current menu item
    curr = next_visible(menu, startopt);
    prev = curr;

    gotoxy(ms->minrow + ms->statline, ms->mincol);
    cprint(ms->spacechar, ms->statusattr[NOHLITE], ms->numcols);
    gotoxy(ms->minrow + ms->statline, ms->mincol);
    printmenuitem(menu->items[curr]->status, ms->statusattr);
    first = calc_first_early(menu, curr);
    prev_first = first;
    while (1)           // Forever
    {
    /* Redraw everything if:
     *  + we need to scroll (take care of scroll bars, ...)
     *  + menuoption
     */
    if (prev_first != first || redraw) {
        printmenu(menu, curr, top, left, first, radio);
    } else {
        /* Redraw only the highlighted entry */
        print_line(menu, curr, top, left, prev, prev - first, radio);
        print_line(menu, curr, top, left, curr, curr - first, radio);
    }
    redraw = false;
    prev = curr;
    prev_first = first;
    ci = menu->items[curr];
    asc = getch();
    switch (asc) {
        case KEY_CTRL('L'):
        redraw = true;
        break;
    case KEY_HOME:
        curr = next_visible(menu, 0);
        first = calc_first_early(menu, curr);
        break;
    case KEY_END:
        curr = prev_visible(menu, numitems - 1);
        first = calc_first_late(menu, curr);
        break;
    case KEY_PGDN:
        for (i = 0; i < 5; i++)
        curr = next_visible(menu, curr + 1);
        first = calc_first_late(menu, curr);
        break;
    case KEY_PGUP:
        for (i = 0; i < 5; i++)
        curr = prev_visible(menu, curr - 1);
        first = calc_first_early(menu, curr);
        break;
    case KEY_UP:
        curr = prev_visible(menu, curr - 1);
        if (curr < first)
        first = calc_first_early(menu, curr);
        break;
    case KEY_DOWN:
        curr = next_visible(menu, curr + 1);
        if (!isvisible(menu, first, curr))
        first = calc_first_late(menu, curr);
        break;
    case KEY_LEFT:
    case KEY_ESC:
        return NULL;
        break;
    case KEY_RIGHT:
    case KEY_ENTER:
        if (ci->action == OPT_INACTIVE)
        break;
        if (ci->action == OPT_CHECKBOX)
        break;
        if (ci->action == OPT_SEP)
        break;
        if (ci->action == OPT_EXITMENU)
        return NULL;    // As if we hit Esc
        // If we are going into a radio menu, dont call handler, return ci
        if (ci->action == OPT_RADIOMENU)
        return ci;
        if (ci->handler != NULL)    // Do we have a handler
        {
        hr = ci->handler(ms, ci);
        if (hr.refresh) // Do we need to refresh
        {
            // Cleanup menu using old number of items
            cleanupmenu(menu, top, left, numitems);
            // Recalculate the number of items
            numitems = calc_visible(menu, 0);
            // Reprint the menu
            printmenu(menu, curr, top, left, first, radio);
        }
        if (hr.valid)
            return ci;
        } else
        return ci;
        break;
    case SPACECHAR:
        if (ci->action != OPT_CHECKBOX)
        break;
        ci->itemdata.checked = !ci->itemdata.checked;
        if (ci->handler != NULL)    // Do we have a handler
        {
        hr = ci->handler(ms, ci);
        if (hr.refresh) // Do we need to refresh
        {
            // Cleanup menu using old number of items
            cleanupmenu(menu, top, left, numitems);
            // Recalculate the number of items
            numitems = calc_visible(menu, 0);
            // Reprint the menu
            printmenu(menu, curr, top, left, first, radio);
        }
        }
        break;
    default:
        // Check if this is a shortcut key
        if (((asc >= 'A') && (asc <= 'Z')) ||
        ((asc >= 'a') && (asc <= 'z')) ||
        ((asc >= '0') && (asc <= '9'))) {
        tmp = find_shortcut(menu, asc, curr);
        if ((tmp > curr) && (!isvisible(menu, first, tmp)))
            first = calc_first_late(menu, tmp);
        if (tmp < curr)
            first = calc_first_early(menu, tmp);
        curr = tmp;
        } else {
        if (ms->keys_handler)   // Call extra keys handler
            ms->keys_handler(ms, menu->items[curr], asc);

            /* The handler may have changed the UI, reset it on exit */
            reset_ui();
            // Cleanup menu using old number of items
            cleanupmenu(menu, top, left, numitems);
            // Recalculate the number of items
            numitems = calc_visible(menu, 0);
            // Reprint the menu
            printmenu(menu, curr, top, left, first, radio);
        }
        break;
    }
    // Update status line
    /* Erase the previous status */
    gotoxy(ms->minrow + ms->statline, ms->mincol);
    cprint(ms->spacechar, ms->statusattr[NOHLITE], ms->numcols);
    /* Print the new status */
    gotoxy(ms->minrow + ms->statline, ms->mincol);
    printmenuitem(menu->items[curr]->status, ms->statusattr);
    }
    return NULL;        // Should never come here
}

/* Handle the entire system of menu's. */
pt_menuitem runmenusystem(uchar top, uchar left, pt_menu cmenu, uchar startopt,
              uchar menutype)
     /*
      * cmenu
      *    Which menu should be currently displayed
      * top,left
      *    What is the position of the top,left corner of the menu
      * startopt
      *    which menu item do I start with
      * menutype
      *    NORMALMENU or RADIOMENU
      *
      * Return Value:
      *    Returns a pointer to the final item chosen, or NULL if nothing chosen.
      */
{
    pt_menuitem opt, choice;
    uchar startat, mt;
    uchar row, col;

    if (cmenu == NULL)
    return NULL;

startover:
    // Set the menu height
    cmenu->menuheight = ms->maxrow - top - 3;
    if (cmenu->menuheight > ms->maxmenuheight)
    cmenu->menuheight = ms->maxmenuheight;
    if (menutype == NORMALMENU)
    opt = getmenuoption(cmenu, top, left, startopt, false);
    else            // menutype == RADIOMENU
    opt = getmenuoption(cmenu, top, left, startopt, true);

    if (opt == NULL) {
    // User hit Esc
    cleanupmenu(cmenu, top, left, calc_visible(cmenu, 0));
    return NULL;
    }
    // Are we done with the menu system?
    if ((opt->action != OPT_SUBMENU) && (opt->action != OPT_RADIOMENU)) {
    cleanupmenu(cmenu, top, left, calc_visible(cmenu, 0));
    return opt;     // parent cleanup other menus
    }
    // Either radiomenu or submenu
    // Do we have a valid menu number? The next hack uses the fact that
    // itemdata.submenunum = itemdata.radiomenunum (since enum data type)
    if (opt->itemdata.submenunum >= ms->nummenus)   // This is Bad....
    {
    gotoxy(12, 12); // Middle of screen
    csprint("ERROR: Invalid submenu requested.", 0x07);
    cleanupmenu(cmenu, top, left, calc_visible(cmenu, 0));
    return NULL;        // Pretend user hit esc
    }
    // Call recursively for submenu
    // Position the submenu below the current item,
    // covering half the current window (horizontally)
    row = ms->menus[(unsigned int)opt->itemdata.submenunum]->row;
    col = ms->menus[(unsigned int)opt->itemdata.submenunum]->col;
    if (row == 0xFF)
    row = top + opt->index + 2;
    if (col == 0xFF)
    col = left + 3 + (cmenu->menuwidth >> 1);
    mt = (opt->action == OPT_SUBMENU ? NORMALMENU : RADIOMENU);
    startat = 0;
    if ((opt->action == OPT_RADIOMENU) && (opt->data != NULL))
    startat = ((t_menuitem *) opt->data)->index;

    choice = runmenusystem(row, col,
               ms->menus[(unsigned int)opt->itemdata.submenunum],
               startat, mt);
    if (opt->action == OPT_RADIOMENU) {
    if (choice != NULL)
        opt->data = (void *)choice; // store choice in data field
    if (opt->handler != NULL)
        opt->handler(ms, opt);
    choice = NULL;      // Pretend user hit esc
    }
    if (choice == NULL)     // User hit Esc in submenu
    {
    // Startover
    startopt = opt->index;
    goto startover;
    } else {
    cleanupmenu(cmenu, top, left, calc_visible(cmenu, 0));
    return choice;
    }
}

// Finds the indexof the menu with given name
uchar find_menu_num(const char *name)
{
    int i;
    pt_menu m;

    if (name == NULL)
    return (uchar) (-1);
    for (i = 0; i < ms->nummenus; i++) {
    m = ms->menus[i];
    if ((m->name) && (strcmp(m->name, name) == 0))
        return i;
    }
    return (uchar) (-1);
}

// Run through all items and if they are submenus
// with a non-trivial "action" and trivial submenunum
// replace submenunum with the menu with name "action"
void fix_submenus(void)
{
    int i, j;
    pt_menu m;
    pt_menuitem mi;

    i = 0;
    for (i = 0; i < ms->nummenus; i++) {
    m = ms->menus[i];
    for (j = 0; j < m->numitems; j++) {
        mi = m->items[j];
        // if item is a submenu and has non-empty non-trivial data string
        if (mi->data && strlen(mi->data) > 0 &&
        ((mi->action == OPT_SUBMENU)
         || (mi->action == OPT_RADIOMENU))) {
        mi->itemdata.submenunum = find_menu_num(mi->data);
        }
    }
    }
}

/* User Callable functions */

pt_menuitem showmenus(uchar startmenu)
{
    pt_menuitem rv;

    fix_submenus();     // Fix submenu numbers incase nick names were used

    /* Turn autowrap off, to avoid scrolling the menu */
    printf(CSI "?7l");

    // Setup screen for menusystem
    reset_ui();

    // Go, main menu cannot be a radio menu
    rv = runmenusystem(ms->minrow + MENUROW, ms->mincol + MENUCOL,
               ms->menus[(unsigned int)startmenu], 0, NORMALMENU);

    // Hide the garbage we left on the screen
    cls();
    gotoxy(ms->minrow, ms->mincol);
    cursoron();

    // Return user choice
    return rv;
}

pt_menusystem init_menusystem(const char *title)
{
    int i;

    ms = NULL;
    ms = (pt_menusystem) malloc(sizeof(t_menusystem));
    if (ms == NULL)
    return NULL;
    ms->nummenus = 0;
    // Initialise all menu pointers
    for (i = 0; i < MAXMENUS; i++)
    ms->menus[i] = NULL;

    ms->title = (char *)malloc(TITLELEN + 1);
    if (title == NULL)
    strcpy(ms->title, TITLESTR);    // Copy string
    else
    strcpy(ms->title, title);

    // Timeout settings
    ms->tm_stepsize = TIMEOUTSTEPSIZE;
    ms->tm_numsteps = TIMEOUTNUMSTEPS;

    ms->normalattr[NOHLITE] = NORMALATTR;
    ms->normalattr[HLITE] = NORMALHLITE;

    ms->reverseattr[NOHLITE] = REVERSEATTR;
    ms->reverseattr[HLITE] = REVERSEHLITE;

    ms->inactattr[NOHLITE] = INACTATTR;
    ms->inactattr[HLITE] = INACTHLITE;

    ms->revinactattr[NOHLITE] = REVINACTATTR;
    ms->revinactattr[HLITE] = REVINACTHLITE;

    ms->statusattr[NOHLITE] = STATUSATTR;
    ms->statusattr[HLITE] = STATUSHLITE;

    ms->statline = STATLINE;
    ms->tfillchar = TFILLCHAR;
    ms->titleattr = TITLEATTR;

    ms->fillchar = FILLCHAR;
    ms->fillattr = FILLATTR;
    ms->spacechar = SPACECHAR;
    ms->shadowattr = SHADOWATTR;

    ms->menupage = MENUPAGE;    // Usually no need to change this at all

    // Initialise all handlers
    ms->handler = NULL;
    ms->keys_handler = NULL;
    ms->ontimeout = NULL;   // No timeout handler
    ms->tm_total_timeout = 0;
    ms->tm_sofar_timeout = 0;
    ms->ontotaltimeout = NULL;

    // Setup ACTION_{,IN}VALID
    ACTION_VALID.valid = 1;
    ACTION_VALID.refresh = 0;
    ACTION_INVALID.valid = 0;
    ACTION_INVALID.refresh = 0;

    // Figure out the size of the screen we are in now.
    // By default we use the whole screen for our menu
    if (getscreensize(1, &ms->numrows, &ms->numcols)) {
        /* Unknown screen size? */
        ms->numcols = 80;
        ms->numrows = 24;
    }
    ms->minrow = ms->mincol = 0;
    ms->maxcol = ms->numcols - 1;
    ms->maxrow = ms->numrows - 1;

    // How many entries per menu can we display at a time
    ms->maxmenuheight = ms->maxrow - ms->minrow - 3;
    if (ms->maxmenuheight > MAXMENUHEIGHT)
    ms->maxmenuheight = MAXMENUHEIGHT;

    console_ansi_raw();

    return ms;
}

void set_normal_attr(uchar normal, uchar selected, uchar inactivenormal,
             uchar inactiveselected)
{
    if (normal != 0xFF)
    ms->normalattr[0] = normal;
    if (selected != 0xFF)
    ms->reverseattr[0] = selected;
    if (inactivenormal != 0xFF)
    ms->inactattr[0] = inactivenormal;
    if (inactiveselected != 0xFF)
    ms->revinactattr[0] = inactiveselected;
}

void set_normal_hlite(uchar normal, uchar selected, uchar inactivenormal,
              uchar inactiveselected)
{
    if (normal != 0xFF)
    ms->normalattr[1] = normal;
    if (selected != 0xFF)
    ms->reverseattr[1] = selected;
    if (inactivenormal != 0xFF)
    ms->inactattr[1] = inactivenormal;
    if (inactiveselected != 0xFF)
    ms->revinactattr[1] = inactiveselected;
}

void set_status_info(uchar statusattr, uchar statushlite, uchar statline)
{
    if (statusattr != 0xFF)
    ms->statusattr[NOHLITE] = statusattr;
    if (statushlite != 0xFF)
    ms->statusattr[HLITE] = statushlite;
    // statline is relative to minrow
    if (statline >= ms->numrows)
    statline = ms->numrows - 1;
    ms->statline = statline;    // relative to ms->minrow, 0 based
}

void set_title_info(uchar tfillchar, uchar titleattr)
{
    if (tfillchar != 0xFF)
    ms->tfillchar = tfillchar;
    if (titleattr != 0xFF)
    ms->titleattr = titleattr;
}

void set_misc_info(uchar fillchar, uchar fillattr, uchar spacechar,
           uchar shadowattr)
{
    if (fillchar != 0xFF)
    ms->fillchar = fillchar;
    if (fillattr != 0xFF)
    ms->fillattr = fillattr;
    if (spacechar != 0xFF)
    ms->spacechar = spacechar;
    if (shadowattr != 0xFF)
    ms->shadowattr = shadowattr;
}

void set_menu_options(uchar maxmenuheight)
{
    if (maxmenuheight != 0xFF)
    ms->maxmenuheight = maxmenuheight;
}

// Set the window which menusystem should use
void set_window_size(uchar top, uchar left, uchar bot, uchar right)
{
    int nr, nc;

    if ((top > bot) || (left > right))
    return;         // Sorry no change will happen here

    if (getscreensize(1, &nr, &nc)) {
        /* Unknown screen size? */
        nr = 80;
        nc = 24;
    }
    if (bot >= nr)
    bot = nr - 1;
    if (right >= nc)
    right = nc - 1;
    ms->minrow = top;
    ms->mincol = left;
    ms->maxrow = bot;
    ms->maxcol = right;
    ms->numcols = right - left + 1;
    ms->numrows = bot - top + 1;
    if (ms->statline >= ms->numrows)
    ms->statline = ms->numrows - 1; // Clip statline if need be
}

void reg_handler(t_handler htype, void *handler)
{
    // If bad value set to default screen handler
    switch (htype) {
    case HDLR_KEYS:
    ms->keys_handler = (t_keys_handler) handler;
    break;
    default:
    ms->handler = (t_menusystem_handler) handler;
    break;
    }
}

void unreg_handler(t_handler htype)
{
    switch (htype) {
    case HDLR_KEYS:
    ms->keys_handler = NULL;
    break;
    default:
    ms->handler = NULL;
    break;
    }
}

void reg_ontimeout(t_timeout_handler handler, unsigned int numsteps,
           unsigned int stepsize)
{
    ms->ontimeout = handler;
    if (numsteps != 0)
    ms->tm_numsteps = numsteps;
    if (stepsize != 0)
    ms->tm_stepsize = stepsize;
}

void unreg_ontimeout(void)
{
    ms->ontimeout = NULL;
}

void reg_ontotaltimeout(t_timeout_handler handler,
            unsigned long numcentiseconds)
{
    if (numcentiseconds != 0) {
    ms->ontotaltimeout = handler;
    ms->tm_total_timeout = numcentiseconds * 10;    // to convert to milliseconds
    ms->tm_sofar_timeout = 0;
    }
}

void unreg_ontotaltimeout(void)
{
    ms->ontotaltimeout = NULL;
}

int next_visible(pt_menu menu, int index)
{
    int ans;
    if (index < 0)
    ans = 0;
    else if (index >= menu->numitems)
    ans = menu->numitems - 1;
    else
    ans = index;
    while ((ans < menu->numitems - 1) &&
       ((menu->items[ans]->action == OPT_INVISIBLE) ||
        (menu->items[ans]->action == OPT_SEP)))
    ans++;
    return ans;
}

int prev_visible(pt_menu menu, int index)   // Return index of prev visible
{
    int ans;
    if (index < 0)
    ans = 0;
    else if (index >= menu->numitems)
    ans = menu->numitems - 1;
    else
    ans = index;
    while ((ans > 0) &&
       ((menu->items[ans]->action == OPT_INVISIBLE) ||
        (menu->items[ans]->action == OPT_SEP)))
    ans--;
    return ans;
}

int next_visible_sep(pt_menu menu, int index)
{
    int ans;
    if (index < 0)
    ans = 0;
    else if (index >= menu->numitems)
    ans = menu->numitems - 1;
    else
    ans = index;
    while ((ans < menu->numitems - 1) &&
       (menu->items[ans]->action == OPT_INVISIBLE))
    ans++;
    return ans;
}

int prev_visible_sep(pt_menu menu, int index)   // Return index of prev visible
{
    int ans;
    if (index < 0)
    ans = 0;
    else if (index >= menu->numitems)
    ans = menu->numitems - 1;
    else
    ans = index;
    while ((ans > 0) && (menu->items[ans]->action == OPT_INVISIBLE))
    ans--;
    return ans;
}

int calc_visible(pt_menu menu, int first)
{
    int ans, i;

    if (menu == NULL)
    return 0;
    ans = 0;
    for (i = first; i < menu->numitems; i++)
    if (menu->items[i]->action != OPT_INVISIBLE)
        ans++;
    return ans;
}

// is curr visible if first entry is first?
int isvisible(pt_menu menu, int first, int curr)
{
    if (curr < first)
    return 0;
    return (calc_visible(menu, first) - calc_visible(menu, curr) <
        menu->menuheight);
}

// Calculate the first entry to be displayed
// so that curr is visible and make curr as late as possible
int calc_first_late(pt_menu menu, int curr)
{
    int ans, i, nv;

    nv = calc_visible(menu, 0);
    if (nv <= menu->menuheight)
    return 0;
    // Start with curr and go back menu->menuheight times
    ans = curr + 1;
    for (i = 0; i < menu->menuheight; i++)
    ans = prev_visible_sep(menu, ans - 1);
    return ans;
}

// Calculate the first entry to be displayed
// so that curr is visible and make curr as early as possible
int calc_first_early(pt_menu menu, int curr)
{
    int ans, i, nv;

    nv = calc_visible(menu, 0);
    if (nv <= menu->menuheight)
    return 0;
    // Start with curr and go back till >= menu->menuheight
    // items are visible
    nv = calc_visible(menu, curr);  // Already nv of them are visible
    ans = curr;
    for (i = 0; i < menu->menuheight - nv; i++)
    ans = prev_visible_sep(menu, ans - 1);
    return ans;
}

// Create a new menu and return its position
uchar add_menu(const char *title, int maxmenusize)
{
    int num, i;
    pt_menu m;

    num = ms->nummenus;
    if (num >= MAXMENUS)
    return -1;
    m = NULL;
    m = (pt_menu) malloc(sizeof(t_menu));
    if (m == NULL)
    return -1;
    ms->menus[num] = m;
    m->numitems = 0;
    m->name = NULL;
    m->row = 0xFF;
    m->col = 0xFF;
    if (maxmenusize < 1)
    m->maxmenusize = MAXMENUSIZE;
    else
    m->maxmenusize = maxmenusize;
    m->items = (pt_menuitem *) malloc(sizeof(pt_menuitem) * (m->maxmenusize));
    for (i = 0; i < m->maxmenusize; i++)
    m->items[i] = NULL;

    m->title = (char *)malloc(MENULEN + 1);
    if (title) {
    if (strlen(title) > MENULEN - 2)
        strcpy(m->title, TITLELONG);
    else
        strcpy(m->title, title);
    } else
    strcpy(m->title, EMPTYSTR);
    m->menuwidth = strlen(m->title);
    ms->nummenus++;
    return ms->nummenus - 1;
}

void set_menu_name(const char *name)    // Set the "name" of this menu
{
    pt_menu m;

    m = ms->menus[ms->nummenus - 1];
    if (m->name)        // Free up previous name
    {
    free(m->name);
    m->name = NULL;
    }

    if (name) {
    m->name = (char *)malloc(strlen(name) + 1);
    strcpy(m->name, name);
    }
}

// Create a new named menu and return its position
uchar add_named_menu(const char *name, const char *title, int maxmenusize)
{
    add_menu(title, maxmenusize);
    set_menu_name(name);
    return ms->nummenus - 1;
}

void set_menu_pos(uchar row, uchar col) // Set the position of this menu.
{
    pt_menu m;

    m = ms->menus[ms->nummenus - 1];
    m->row = row;
    m->col = col;
}

pt_menuitem add_sep(void)       // Add a separator to current menu
{
    pt_menuitem mi;
    pt_menu m;

    m = (ms->menus[ms->nummenus - 1]);
    mi = NULL;
    mi = (pt_menuitem) malloc(sizeof(t_menuitem));
    if (mi == NULL)
    return NULL;
    m->items[(unsigned int)m->numitems] = mi;
    mi->handler = NULL;     // No handler
    mi->item = mi->status = mi->data = NULL;
    mi->action = OPT_SEP;
    mi->index = m->numitems++;
    mi->parindex = ms->nummenus - 1;
    mi->shortcut = 0;
    mi->helpid = 0;
    return mi;
}

// Add item to the "current" menu
pt_menuitem add_item(const char *item, const char *status, t_action action,
             const char *data, uchar itemdata)
{
    pt_menuitem mi;
    pt_menu m;
    const char *str;
    uchar inhlite = 0;      // Are we inside hlite area

    m = (ms->menus[ms->nummenus - 1]);
    mi = NULL;
    mi = (pt_menuitem) malloc(sizeof(t_menuitem));
    if (mi == NULL)
    return NULL;
    m->items[(unsigned int)m->numitems] = mi;
    mi->handler = NULL;     // No handler

    // Allocate space to store stuff
    mi->item = (char *)malloc(MENULEN + 1);
    mi->status = (char *)malloc(STATLEN + 1);
    mi->data = (char *)malloc(ACTIONLEN + 1);

    if (item) {
    if (strlen(item) > MENULEN) {
        strcpy(mi->item, ITEMLONG);
    } else {
        strcpy(mi->item, item);
    }
    if (strlen(mi->item) > m->menuwidth)
        m->menuwidth = strlen(mi->item);
    } else
    strcpy(mi->item, EMPTYSTR);

    if (status) {
    if (strlen(status) > STATLEN) {
        strcpy(mi->status, STATUSLONG);
    } else {
        strcpy(mi->status, status);
    }
    } else
    strcpy(mi->status, EMPTYSTR);

    mi->action = action;
    str = mi->item;
    mi->shortcut = 0;
    mi->helpid = 0xFFFF;
    inhlite = 0;        // We have not yet seen an ENABLEHLITE char
    // Find the first char in [A-Za-z0-9] after ENABLEHLITE and not arg to control char
    while (*str) {
    if (*str == ENABLEHLITE) {
        inhlite = 1;
    }
    if (*str == DISABLEHLITE) {
        inhlite = 0;
    }
    if ((inhlite == 1) &&
        (((*str >= 'A') && (*str <= 'Z')) ||
         ((*str >= 'a') && (*str <= 'z')) ||
         ((*str >= '0') && (*str <= '9')))) {
        mi->shortcut = *str;
        break;
    }
    ++str;
    }
    if ((mi->shortcut >= 'A') && (mi->shortcut <= 'Z')) // Make lower case
    mi->shortcut = mi->shortcut - 'A' + 'a';

    if (data) {
    if (strlen(data) > ACTIONLEN) {
        strcpy(mi->data, ACTIONLONG);
    } else {
        strcpy(mi->data, data);
    }
    } else
    strcpy(mi->data, EMPTYSTR);

    switch (action) {
    case OPT_SUBMENU:
    mi->itemdata.submenunum = itemdata;
    break;
    case OPT_CHECKBOX:
    mi->itemdata.checked = itemdata;
    break;
    case OPT_RADIOMENU:
    mi->itemdata.radiomenunum = itemdata;
    if (mi->data)
        free(mi->data);
    mi->data = NULL;    // No selection made
    break;
    default:            // to keep the compiler happy
    break;
    }
    mi->index = m->numitems++;
    mi->parindex = ms->nummenus - 1;
    return mi;
}

// Set the shortcut key for the current item
void set_item_options(uchar shortcut, int helpid)
{
    pt_menuitem mi;
    pt_menu m;

    m = (ms->menus[ms->nummenus - 1]);
    if (m->numitems <= 0)
    return;
    mi = m->items[(unsigned int)m->numitems - 1];

    if (shortcut != 0xFF)
    mi->shortcut = shortcut;
    if (helpid != 0xFFFF)
    mi->helpid = helpid;
}

// Free internal datasutructures
void close_menusystem(void)
{
}

// append_line_helper(pt_menu menu,char *line)
void append_line_helper(int menunum, char *line)
{
    pt_menu menu;
    pt_menuitem mi, ri;
    char *app;
    int ctr;

    menu = ms->menus[menunum];
    for (ctr = 0; ctr < (int)menu->numitems; ctr++) {
    mi = menu->items[ctr];
    app = NULL;     //What to append
    switch (mi->action) {
    case OPT_CHECKBOX:
        if (mi->itemdata.checked)
        app = mi->data;
        break;
    case OPT_RADIOMENU:
        if (mi->data) { // Some selection has been made
        ri = (pt_menuitem) (mi->data);
        app = ri->data;
        }
        break;
    case OPT_SUBMENU:
        append_line_helper(mi->itemdata.submenunum, line);
        break;
    default:
        break;
    }
    if (app) {
        strcat(line, " ");
        strcat(line, app);
    }
    }
}

// Generate string based on state of checkboxes and radioitem in given menu
// Assume line points to large enough buffer
void gen_append_line(const char *menu_name, char *line)
{
    int menunum;

    menunum = find_menu_num(menu_name);
    if (menunum < 0)
    return;         // No such menu
    append_line_helper(menunum, line);
}
