/* -*- c -*- ------------------------------------------------------------- *
 *
 *   Copyright 2004-2006 Murali Krishnan Ganapathy - All Rights Reserved
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
#include "help.h"
#include "passwords.h"
#include "com32io.h"
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#define MAX_CMD_LINE_LENGTH 514

typedef struct s_xtra {
  long ipappend; // Stores the ipappend flag to send (useful for PXELINUX only)
  char *argsmenu; // Stores the name of menu which contains options for the given RUN item
  char *perms; // stores the permissions required to activate the item
} t_xtra;

typedef t_xtra *pt_xtra; // Pointer to extra datastructure

// Types of dot commands for which caller takes responsibility of handling
// In some case some commands may not make sense, it is up to the caller
// to handle cases which do not make sense
typedef enum {QUIT_CMD, REPEAT_CMD, ENTER_CMD, ESCAPE_CMD} t_dotcmd;


/*----------------- Global Variables */

// default user
#define GUEST_USER "guest"

// for local commands. return value of execdotcmd
#define QUIT_CMD 0
#define RPT_CMD 1

char username[12]; // Name of user currently using the system

int PWD_ROW; // Line number where user authentication happens
int EDIT_ROW; // row where User Tab

char loginstr[] = "<L>ogin  ";
char logoutstr[30];

int vmode; // The video mode we want to be in
char timeoutcmd[MAX_CMD_LINE_LENGTH]; // Command to execute on timeout
char totaltimeoutcmd[MAX_CMD_LINE_LENGTH]; // Command to execute on totaltimeout

char QUITSTR[] = ".quit"; // same as exit
char IGNORESTR[]=".ignore"; // same as repeat, wait

/*----------------  End globals */

// returns pointer to first non-space char
// and advances end of str by removing trailing spaces
char * strip(char *str)
{
  char *p,*s,*e;
  if (!str) return NULL;
  p = str;
  s = NULL;
  e = NULL;
  while (*p) {
    if (*p != ' ') {
       // mark start of string or record the last visited non-space char
       if (!s) s=p; else e=p;
    }
    p++;
  }
  *(++e)='\0'; // kill string earlier
  return s;
}

// executes a list of % separated commands
// non-dot commands are assumed to be syslinux commands
// All syslinux commands are appended with the contents of kerargs
// If it fails (kernel not found) then the next one is tried in the
// list
// returns QUIT_CMD or RPT_CMD
t_dotcmd execdotcmd(const char *cmd, char *defcmd, const char *kerargs)
{
   char cmdline[MAX_CMD_LINE_LENGTH];
   char dotcmd[MAX_CMD_LINE_LENGTH];
   char *curr,*next,*p,*args;
   char ctr;

   strcpy(dotcmd,cmd);
   next = dotcmd;
   cmdline[0] = '\0';
   while (*next) { // if something to do
      curr = next;
      p = strchr(next,'%');
      if (p) {
         *p--='\0'; next=p+2;
         while (*p == ' ') p--;
         *(++p)='\0'; // remove trailing spaces
      } else {
        if (*defcmd) { // execute defcmd next
            next=defcmd;
            defcmd=NULL; // exec def cmd only once
        } else next=NULL;
      }
      // now we just need to execute the command "curr"
      curr = strip(curr);
      if (curr[0] != '.') { // just run the kernel
         strcpy(cmdline,curr);
         if (kerargs) strcat(cmdline,kerargs);
         runsyslinuximage(cmdline,0); // No IPAppend
      } else { // We have a DOT command
        // split command into command and args (may be empty)
        args = curr;
        while ( (*args != ' ') && (*args != '\0') ) args++;
        if (*args) { // found a space
           *args++ = '\0';
           while (*args == ' ') args++; // skip over spaces
        }
        if ( (strcmp(curr,".exit")==0) ||
             (strcmp(curr,".quit")==0)
           )
           return QUIT_CMD;
        if ( (strcmp(curr,".repeat")==0) ||
             (strcmp(curr,".ignore")==0) ||
             (strcmp(curr,".wait")==0)
           )
           return RPT_CMD;
        if (strcmp(curr,".beep")==0) {
           if ((args) && ('0' <= args[0]) && (args[0] <= '9'))
              ctr = args[0]-'0';
           else ctr=1;
           for (;ctr>0; ctr--) beep();
        }
        if (strcmp(curr,".help")==0) runhelp(args);
      }
   }
   return RPT_CMD; // by default we do not quit
}


TIMEOUTCODE timeout(const char *cmd)
{
  t_dotcmd c;
  c = execdotcmd(cmd,".wait",NULL);
  switch(c) {
    case ENTER_CMD:
         return CODE_ENTER;
    case ESCAPE_CMD:
         return CODE_ESCAPE;
    default:
         return CODE_WAIT;
  }
}

TIMEOUTCODE ontimeout(void)
{
   return timeout(timeoutcmd);
}

TIMEOUTCODE ontotaltimeout(void)
{
   return timeout(totaltimeoutcmd);
}

void keys_handler(t_menusystem * ms __attribute__ (( unused )), t_menuitem * mi, int scancode)
{
   int nc, nr;

   if (getscreensize(1, &nr, &nc)) {
       /* Unknown screen size? */
       nc = 80;
       nr = 24;
   }

   if ( (scancode == KEY_F1) && (mi->helpid != 0xFFFF) ) { // If scancode of F1 and non-trivial helpid
      runhelpsystem(mi->helpid);
   }

   // If user hit TAB, and item is an "executable" item
   // and user has privileges to edit it, edit it in place.
   if ((scancode == KEY_TAB) && (mi->action == OPT_RUN) &&
       (EDIT_ROW < nr) && (EDIT_ROW > 0) &&
       (isallowed(username,"editcmd") || isallowed(username,"root"))) {
     // User typed TAB and has permissions to edit command line
     gotoxy(EDIT_ROW,1);
     csprint("Command line:",0x07);
     editstring(mi->data,ACTIONLEN);
     gotoxy(EDIT_ROW,1);
     cprint(' ',0x07,nc-1);
   }
}

t_handler_return login_handler(t_menusystem *ms, t_menuitem *mi)
{
  (void)mi; // Unused
  char pwd[40];
  char login[40];
  int nc, nr;
  t_handler_return rv;

  (void)ms;

  rv = ACTION_INVALID;
  if (PWD_ROW < 0) return rv; // No need to authenticate

  if (mi->item == loginstr) { /* User wants to login */
    if (getscreensize(1, &nr, &nc)) {
        /* Unknown screen size? */
        nc = 80;
        nr = 24;
    }

    gotoxy(PWD_ROW,1);
    csprint("Enter Username: ",0x07);
    getstring(login, sizeof username);
    gotoxy(PWD_ROW,1);
    cprint(' ',0x07,nc);
    csprint("Enter Password: ",0x07);
    getpwd(pwd, sizeof pwd);
    gotoxy(PWD_ROW,1);
    cprint(' ',0x07,nc);

    if (authenticate_user(login,pwd))
    {
      strcpy(username,login);
      strcpy(logoutstr,"<L>ogout ");
      strcat(logoutstr,username);
      mi->item = logoutstr; // Change item to read "Logout"
      rv.refresh = 1; // refresh the screen (as item contents changed)
    }
    else strcpy(username,GUEST_USER);
  }
  else // User needs to logout
  {
    strcpy(username,GUEST_USER);
    strcpy(logoutstr,"");
    mi->item = loginstr;
  }

  return rv;
}

t_handler_return check_perms(t_menusystem *ms, t_menuitem *mi)
{
   char *perms;
   pt_xtra x;

   (void) ms; // To keep compiler happy

   x = (pt_xtra) mi->extra_data;
   perms = ( x ? x->perms : NULL);
   if (!perms) return ACTION_VALID;

   if (isallowed(username,"root") || isallowed(username,perms)) // If allowed
      return ACTION_VALID;
   else return ACTION_INVALID;
}

// Compute the full command line to add and if non-trivial
// prepend the string prepend to final command line
// Assume cmdline points to buffer long enough to hold answer
void gencommand(pt_menuitem mi, char *cmdline)
{
   pt_xtra x;
   cmdline[0] = '\0';
   strcat(cmdline,mi->data);
   x = (pt_xtra) mi->extra_data;
   if ( (x) && (x->argsmenu)) gen_append_line(x->argsmenu,cmdline);
}


// run the given command together with additional options which may need passing
void runcommand(pt_menuitem mi)
{
   char *line;
   pt_xtra x;
   long ipappend;

   line = (char *)malloc(sizeof(char)*MAX_CMD_LINE_LENGTH);
   gencommand(mi,line);
   x = (pt_xtra) mi->extra_data;
   ipappend = (x ? x->ipappend : 0);

   runsyslinuximage(line,ipappend);
   free(line);
}

// set the extra info for the specified menu item.
void set_xtra(pt_menuitem mi, const char *argsmenu, const char *perms, unsigned int helpid, long ipappend)
{
   pt_xtra xtra;
   int bad_argsmenu, bad_perms, bad_ipappend;

   mi->extra_data = NULL; // initalize
   mi->helpid = helpid; // set help id

   if (mi->action != OPT_RUN) return;

   bad_argsmenu = bad_perms = bad_ipappend = 0;
   if ( (argsmenu==NULL) || (strlen(argsmenu)==0)) bad_argsmenu = 1;
   if ( (perms==NULL) || (strlen(perms)==0)) bad_perms = 1;
   if ( ipappend==0) bad_ipappend = 1;

   if (bad_argsmenu && bad_perms && bad_ipappend) return;

   xtra = (pt_xtra) malloc(sizeof(t_xtra));
   mi->extra_data = (void *) xtra;
   xtra->argsmenu = xtra->perms = NULL;
   xtra->ipappend = ipappend;
   if (!bad_argsmenu) {
      xtra->argsmenu = (char *) malloc(sizeof(char)*(strlen(argsmenu)+1));
      strcpy(xtra->argsmenu,argsmenu);
   }
   if (!bad_perms) {
      xtra->perms = (char *) malloc(sizeof(char)*(strlen(perms)+1));
      strcpy(xtra->perms,perms);
      mi->handler = &check_perms;
   }
}

int main(void)
{
  pt_menuitem curr;
  char quit;
  char exitcmd[MAX_CMD_LINE_LENGTH];
  char exitcmdroot[MAX_CMD_LINE_LENGTH];
  char onerrcmd[MAX_CMD_LINE_LENGTH];
  char startfile[MAX_CMD_LINE_LENGTH];
  char *ecmd; // effective exit command or onerrorcmd
  char skipbits;
  char skipcmd[MAX_CMD_LINE_LENGTH];
  int timeout; // time in multiples of 0.1 seconds
  int totaltimeout; // time in multiples of 0.1 seconds
  t_dotcmd dotrv; // to store the return value of execdotcmd
  int temp;

  strcpy(username,GUEST_USER);
/* ---- Initializing menu system parameters --- */
  vmode = 0xFF;
  skipbits = SHIFT_PRESSED | CAPSLOCK_ON;
  PWD_ROW = 23;
  EDIT_ROW = 23;
  strcpy(onerrcmd,".beep 2 % % .help hlp00025.txt % .exit");
  strcpy(exitcmd,".exit");
  strcpy(exitcmdroot,"");
  // If not specified exitcmdroot = exitcmd
  if (exitcmdroot[0] == '\0') strcpy(exitcmdroot,exitcmd);
  // Timeout stuff
  timeout = 600;
  strcpy(timeoutcmd,".wait");
  totaltimeout = 0;
  strcpy(totaltimeoutcmd,"chain.c32 hd 0");
  strcpy(startfile,"hlp00026.txt");

  init_help("/isolinux/help");
  init_passwords("/isolinux/password");
  init_menusystem(" COMBOOT Menu System ");
  set_window_size(1,1,21,79);

  // Register the ontimeout handler, with a time out of 10 seconds
  reg_ontimeout(ontimeout,timeout*10,0);
  reg_ontotaltimeout(ontotaltimeout,totaltimeout*10);

  // Register menusystem handlers
  reg_handler(HDLR_KEYS,&keys_handler);
/* ---- End of initialization --- */

/* ------- MENU netmenu ----- */
  add_named_menu("netmenu"," Init Network ",-1);

  curr = add_item("<N>one","Dont start network",OPT_RADIOITEM,"network=no",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<d>hcp","Use DHCP",OPT_RADIOITEM,"network=dhcp",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

/* ------- MENU testing ----- */
  add_named_menu("testing"," Testing ",-1);

  curr = add_item("<M>emory Test","Perform extensive memory testing",OPT_RUN,"memtest",0);
  set_xtra(curr,"","",25,3); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<I>nvisible","You dont see this",OPT_INVISIBLE,"",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<E>xit menu","Go one level up",OPT_EXITMENU,"",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

/* ------- MENU rescue ----- */
  add_named_menu("rescue"," Rescue Options ",-1);

  curr = add_item("<L>inux Rescue","Run linresc",OPT_RUN,"linresc",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<D>os Rescue","dosresc",OPT_RUN,"dosresc",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<W>indows Rescue","winresc",OPT_RUN,"winresc",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<E>xit this menu","Go one level up",OPT_EXITMENU,"",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

/* ------- MENU prep ----- */
  add_named_menu("prep"," Prep options ",-1);

  curr = add_item("<b>aseurl by IP?","Specify gui baseurl by IP address",OPT_CHECKBOX,"baseurl=http://192.168.0.1",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<m>ountcd?","Mount the cdrom drive?",OPT_CHECKBOX,"mountcd",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("Network Initialization","How to initialise network device?",OPT_RADIOMENU,"netmenu",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("","",OPT_SEP,"",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("Reinstall <w>indows","Re-install the windows side of a dual boot setup",OPT_CHECKBOX,"repair=win",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("Reinstall <l>inux","Re-install the linux side of a dual boot setup",OPT_CHECKBOX,"repair=lin",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("","",OPT_SEP,"",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<R>un prep now","Execute prep with the above options",OPT_RUN,"prep",0);
  set_xtra(curr,"prep","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<E>xit this menu","Go up one level",OPT_EXITMENU,"",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

/* ------- MENU main ----- */
  add_named_menu("main"," Main Menu ",-1);

  curr = add_item(loginstr,"Login/Logout of authentication system",OPT_RUN,NULL,0);
  curr->helpid = 65535;
  curr->handler = &login_handler;

  curr = add_item("<P>repare","prep",OPT_RUN,"prep",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<P>rep options...","Options for prep",OPT_SUBMENU,"prep",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<R>escue options...","Troubleshoot a system",OPT_SUBMENU,"rescue",0);
  set_xtra(curr,"","",26,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<T>esting...","Options to test hardware",OPT_SUBMENU,"testing",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);

  curr = add_item("<E>xit to prompt","Exit the menu system",OPT_EXITMENU,"",0);
  set_xtra(curr,"","",65535,0); // Set associated extra info
  set_shortcut(-1);
/* ------- END OF MENU declarations ----- */

// Check if we should skip the menu altogether
  quit = 0; // Dont skip the menu
  if (getshiftflags() & skipbits) { // we must skip the menu altogther and execute skipcmd
    dotrv = execdotcmd(skipcmd,".beep%.exit",NULL); // Worst case we beep and exit
    if (dotrv == QUIT_CMD) quit = 1;
  }

// Switch vide mode if required
   if (vmode != 0xFF) setvideomode(vmode);

// Do we have a startfile to display?
   if (startfile[0] != '\0') runhelp(startfile);

// The main loop
  while (quit == 0) { // As long as quit is zero repeat
     curr = showmenus(find_menu_num("main")); // Initial menu is the one called "main"

     if (curr) {
        if (curr->action == OPT_RUN) {
           ecmd = (char *)malloc(sizeof(char)*MAX_CMD_LINE_LENGTH);
           gencommand(curr,ecmd);
           temp = (curr->extra_data ? ((pt_xtra)curr->extra_data)->ipappend : 0);
           runsyslinuximage(ecmd,temp);
           // kernel not found so execute the appropriate dot command
           dotrv = execdotcmd(onerrcmd,".quit",ecmd); // pass bad cmdline as arg
           if (dotrv== QUIT_CMD) quit = 1;
           free(ecmd); ecmd = NULL;
        }
        else csprint("Error in programming!",0x07);
     } else {
        // find effective exit command
        ecmd = ( isallowed(username,"root") ? exitcmdroot : exitcmd);
        dotrv = execdotcmd(ecmd,".repeat",NULL);
        quit = (dotrv == QUIT_CMD ? 1 : 0); // should we exit now
     }
  }

// Deallocate space used and quit
  close_passwords();
  close_help();
  close_menusystem();
  return 0;
}

