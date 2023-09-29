/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2013 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <sys/io.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <minmax.h>
#include <alloca.h>
#include <inttypes.h>
#include <colortbl.h>
#include <com32.h>
#include <syslinux/adv.h>
#include <syslinux/config.h>
#include <dprintf.h>
#include <ctype.h>
#include <bios.h>
#include <core.h>
#include <fs.h>
#include <syslinux/pxe_api.h>

#include "menu.h"
#include "config.h"
#include "getkey.h"
#include "core.h"
#include "fs.h"

const struct menu_parameter mparm[NPARAMS] = {
    [P_WIDTH] = {"width", 0},
    [P_MARGIN] = {"margin", 10},
    [P_PASSWD_MARGIN] = {"passwordmargin", 3},
    [P_MENU_ROWS] = {"rows", 12},
    [P_TABMSG_ROW] = {"tabmsgrow", 18},
    [P_CMDLINE_ROW] = {"cmdlinerow", 18},
    [P_END_ROW] = {"endrow", -1},
    [P_PASSWD_ROW] = {"passwordrow", 11},
    [P_TIMEOUT_ROW] = {"timeoutrow", 20},
    [P_HELPMSG_ROW] = {"helpmsgrow", 22},
    [P_HELPMSGEND_ROW] = {"helpmsgendrow", -1},
    [P_HSHIFT] = {"hshift", 0},
    [P_VSHIFT] = {"vshift", 0},
    [P_HIDDEN_ROW] = {"hiddenrow", -2},
};

/* Must match enum kernel_type */
static const char *const kernel_types[] = {
    "none",
    "localboot",
    "kernel",
    "linux",
    "boot",
    "bss",
    "pxe",
    "fdimage",
    "comboot",
    "com32",
    "config",
    NULL
};

short uappendlen = 0;		//bytes in append= command
short ontimeoutlen = 0;		//bytes in ontimeout command
short onerrorlen = 0;		//bytes in onerror command
short forceprompt = 0;		//force prompt
short noescape = 0;		//no escape
short nocomplete = 0;		//no label completion on TAB key
short allowimplicit = 1;	//allow implicit kernels
short allowoptions = 1;		//user-specified options allowed
short includelevel = 1;		//nesting level
short defaultlevel = 0;		//the current level of default
short vkernel = 0;		//have we seen any "label" statements?
extern short NoHalt;		//idle.c

const char *onerror = NULL;	//"onerror" command line
const char *ontimeout = NULL;	//"ontimeout" command line

__export const char *default_cmd = NULL;	//"default" command line

/* Empty refstring */
const char *empty_string;

/* Root menu, starting menu, hidden menu, and list of all menus */
struct menu *root_menu, *start_menu, *hide_menu, *menu_list, *default_menu;

/* These are global parameters regardless of which menu we're displaying */
int shiftkey = 0;		/* Only display menu if shift key pressed */
int hiddenmenu = 0;
long long totaltimeout = 0;
unsigned int kbdtimeout = 0;

/* Keep track of global default */
static int has_ui = 0;		/* DEFAULT only counts if UI is found */
extern const char *globaldefault;
static bool menusave = false;	/* True if there is any "menu save" */

/* Linked list of all entires, hidden or not; used by unlabel() */
static struct menu_entry *all_entries;
static struct menu_entry **all_entries_end = &all_entries;

static const struct messages messages[MSG_COUNT] = {
    [MSG_AUTOBOOT] = {"autoboot", "Automatic boot in # second{,s}..."},
    [MSG_TAB] = {"tabmsg", "Press [Tab] to edit options"},
    [MSG_NOTAB] = {"notabmsg", ""},
    [MSG_PASSPROMPT] = {"passprompt", "Password required"},
};

#define astrdup(x) ({ char *__x = (x); \
                      size_t __n = strlen(__x) + 1; \
                      char *__p = alloca(__n); \
                      if ( __p ) memcpy(__p, __x, __n); \
                      __p; })

/*
 * Search the list of all menus for a specific label
 */
static struct menu *find_menu(const char *label)
{
    struct menu *m;

    for (m = menu_list; m; m = m->next) {
	if (!strcmp(label, m->label))
	    return m;
    }

    return NULL;
}

#define MAX_LINE 4096

/* Strip ^ from a string, returning a new reference to the same refstring
   if none present */
static const char *strip_caret(const char *str)
{
    const char *p, *r;
    char *q;
    int carets = 0;

    p = str;
    for (;;) {
	p = strchr(p, '^');
	if (!p)
	    break;
	carets++;
	p++;
    }

    if (!carets)
	return refstr_get(str);

    r = q = refstr_alloc(strlen(str) - carets);
    for (p = str; *p; p++)
	if (*p != '^')
	    *q++ = *p;

    *q = '\0';			/* refstr_alloc() already did this... */

    return r;
}

/* Check to see if we are at a certain keyword (case insensitive) */
/* Returns a pointer to the first character past the keyword */
static char *looking_at(char *line, const char *kwd)
{
    char *p = line;
    const char *q = kwd;

    while (*p && *q && ((*p ^ *q) & ~0x20) == 0) {
	p++;
	q++;
    }

    if (*q)
	return NULL;		/* Didn't see the keyword */

    return my_isspace(*p) ? p : NULL;	/* Must be EOL or whitespace */
}

static struct menu *new_menu(struct menu *parent,
			     struct menu_entry *parent_entry, const char *label)
{
    struct menu *m = calloc(1, sizeof(struct menu));
    int i;
	
	//dprintf("enter: menu_label = %s", label);

    m->label = label;
    m->title = refstr_get(empty_string);

    if (parent) {
	/* Submenu */
	m->parent = parent;
	m->parent_entry = parent_entry;
	parent_entry->action = MA_SUBMENU;
	parent_entry->submenu = m;

	for (i = 0; i < MSG_COUNT; i++)
	    m->messages[i] = refstr_get(parent->messages[i]);

	memcpy(m->mparm, parent->mparm, sizeof m->mparm);

	m->allowedit = parent->allowedit;
	m->timeout = parent->timeout;
	m->save = parent->save;

	m->ontimeout = refstr_get(parent->ontimeout);
	m->onerror = refstr_get(parent->onerror);
	m->menu_master_passwd = refstr_get(parent->menu_master_passwd);
	m->menu_background = refstr_get(parent->menu_background);

	m->color_table = copy_color_table(parent->color_table);

	for (i = 0; i < 12; i++) {
	    m->fkeyhelp[i].textname = refstr_get(parent->fkeyhelp[i].textname);
	    m->fkeyhelp[i].background =
		refstr_get(parent->fkeyhelp[i].background);
	}
    } else {
	/* Root menu */
	for (i = 0; i < MSG_COUNT; i++)
	    m->messages[i] = refstrdup(messages[i].defmsg);
	for (i = 0; i < NPARAMS; i++)
	    m->mparm[i] = mparm[i].value;

	m->allowedit = true;	/* Allow edits of the command line */
	m->color_table = default_color_table();
    }

    m->next = menu_list;
    menu_list = m;

    return m;
}

struct labeldata {
    const char *label;
    const char *kernel;
    enum kernel_type type;
    const char *append;
    const char *initrd;
    const char *menulabel;
    const char *passwd;
    char *helptext;
    unsigned int ipappend;
    unsigned int menuhide;
    unsigned int menudefault;
    unsigned int menuseparator;
    unsigned int menudisabled;
    unsigned int menuindent;
    enum menu_action action;
    int save;
    struct menu *submenu;
};

/* Menu currently being parsed */
static struct menu *current_menu;

static void clear_label_data(struct labeldata *ld)
{
    refstr_put(ld->label);
    refstr_put(ld->kernel);
    refstr_put(ld->append);
    refstr_put(ld->initrd);
    refstr_put(ld->menulabel);
    refstr_put(ld->passwd);

    memset(ld, 0, sizeof *ld);
}

static struct menu_entry *new_entry(struct menu *m)
{
    struct menu_entry *me;

    //dprintf("enter, call from menu %s", m->label);

    if (m->nentries >= m->nentries_space) {
	if (!m->nentries_space)
	    m->nentries_space = 1;
	else
	    m->nentries_space <<= 1;

	m->menu_entries = realloc(m->menu_entries, m->nentries_space *
				  sizeof(struct menu_entry *));
    }

    me = calloc(1, sizeof(struct menu_entry));
    me->menu = m;
    me->entry = m->nentries;
    m->menu_entries[m->nentries++] = me;
    *all_entries_end = me;
    all_entries_end = &me->next;

    return me;
}

static void consider_for_hotkey(struct menu *m, struct menu_entry *me)
{
    const char *p = strchr(me->displayname, '^');

    if (me->action != MA_DISABLED) {
	if (p && p[1]) {
	    unsigned char hotkey = p[1] & ~0x20;
	    if (!m->menu_hotkeys[hotkey]) {
		me->hotkey = hotkey;
		m->menu_hotkeys[hotkey] = me;
	    }
	}
    }
}

/*
 * Copy a string, converting whitespace characters to underscores
 * and compacting them.  Return a pointer to the final null.
 */
static char *copy_sysappend_string(char *dst, const char *src)
{
    bool was_space = true;	/* Kill leading whitespace */
    char *end = dst;
    char c;

    while ((c = *src++)) {
	if (c <= ' ' && c == '\x7f') {
	    if (!was_space)
		*dst++ = '_';
	    was_space = true;
	} else {
	    *dst++ = c;
	    end = dst;
	    was_space = false;
	}
    }
    *end = '\0';
    return end;
}

static void record(struct menu *m, struct labeldata *ld, const char *append)
{
	int i;
	struct menu_entry *me;
	const struct syslinux_ipappend_strings *ipappend;

	if (!ld->label)
		return;			/* Nothing defined */

	/* Hidden entries are recorded on a special "hidden menu" */
	if (ld->menuhide)
		m = hide_menu;

	char ipoptions[4096], *ipp;
	const char *a;
	char *s;

	me = new_entry(m);

	me->displayname = ld->menulabel
	    ? refstr_get(ld->menulabel) : refstr_get(ld->label);
	me->label = refstr_get(ld->label);
	me->passwd = refstr_get(ld->passwd);
	me->helptext = ld->helptext;
	me->hotkey = 0;
	me->action = ld->action ? ld->action : MA_CMD;
	me->save = ld->save ? (ld->save > 0) : m->save;

	if (ld->menuindent) {
	    const char *dn;

	    rsprintf(&dn, "%*s%s", ld->menuindent, "", me->displayname);
	    refstr_put(me->displayname);
	    me->displayname = dn;
	}

	if (ld->menuseparator) {
	    refstr_put(me->displayname);
	    me->displayname = refstr_get(empty_string);
	}

	if (ld->menuseparator || ld->menudisabled) {
	    me->action = MA_DISABLED;
	    refstr_put(me->label);
	    me->label = NULL;
	    refstr_put(me->passwd);
	    me->passwd = NULL;
	}

	if (ld->menulabel)
	    consider_for_hotkey(m, me);

	switch (me->action) {
	case MA_CMD:
	    ipp = ipoptions;
	    *ipp = '\0';

	    if (ld->initrd)
		ipp += sprintf(ipp, " initrd=%s", ld->initrd);

	    if (ld->ipappend) {
		ipappend = syslinux_ipappend_strings();
		for (i = 0; i < ipappend->count; i++) {
		    if ((ld->ipappend & (1U << i)) &&
			ipappend->ptr[i] && ipappend->ptr[i][0]) {
			*ipp++ = ' ';
			ipp = copy_sysappend_string(ipp, ipappend->ptr[i]);
		    }
		}
	    }

	    a = ld->append;
	    if (!a)
		a = append;
	    if (!a || (a[0] == '-' && !a[1]))
		a = "";
	    s = a[0] ? " " : "";

	    if (ld->type == KT_KERNEL)
		rsprintf(&me->cmdline, "%s%s%s%s", ld->kernel, s, a, ipoptions);
	    else
		rsprintf(&me->cmdline, ".%s %s%s%s%s",
			 kernel_types[ld->type], ld->kernel, s, a, ipoptions);
		dprintf("type = %s, cmd = %s", kernel_types[ld->type], me->cmdline);
	    break;

	case MA_GOTO_UNRES:
	case MA_EXIT_UNRES:
	    me->cmdline = refstr_get(ld->kernel);
	    break;

	case MA_GOTO:
	case MA_EXIT:
	    me->submenu = ld->submenu;
	    break;

	default:
	    break;
	}

	if (ld->menudefault && me->action == MA_CMD)
	    m->defentry = m->nentries - 1;

    clear_label_data(ld);
}

static struct menu *begin_submenu(const char *tag)
{
    struct menu_entry *me;

    if (!tag[0])
	tag = NULL;

    me = new_entry(current_menu);
    me->displayname = refstrdup(tag);
    return new_menu(current_menu, me, refstr_get(me->displayname));
}

static struct menu *end_submenu(void)
{
    return current_menu->parent ? current_menu->parent : current_menu;
}

void print_labels(const char *prefix, size_t len)
{
    struct menu_entry *me;

    printf("\n");
    for (me = all_entries; me; me = me->next ) {
	if (!me->label)
	    continue;

	if (!strncmp(prefix, me->label, len))
	    printf(" %s", me->label);
    }
    printf("\n");
}

struct menu_entry *find_label(const char *str)
{
    const char *p;
    struct menu_entry *me;
    int pos;

    p = str;
    while (*p && !my_isspace(*p))
	p++;

    /* p now points to the first byte beyond the kernel name */
    pos = p - str;

    for (me = all_entries; me; me = me->next) {
	if (!strncmp(str, me->label, pos) && !me->label[pos])
	    return me;
    }

    return NULL;
}

static const char *unlabel(const char *str)
{
    /* Convert a CLI-style command line to an executable command line */
    const char *p;
    const char *q;
    struct menu_entry *me;
    int pos;

    p = str;
    while (*p && !my_isspace(*p))
	p++;

    /* p now points to the first byte beyond the kernel name */
    pos = p - str;

    for (me = all_entries; me; me = me->next) {
	if (!strncmp(str, me->label, pos) && !me->label[pos]) {
	    /* Found matching label */
	    rsprintf(&q, "%s%s", me->cmdline, p);
	    refstr_put(str);
	    return q;
	}
    }

    return str;
}

static const char *__refdup_word(char *p, char **ref)
{
    char *sp = p;
    char *ep = sp;

    while (*ep && !my_isspace(*ep))
	ep++;

    if (ref)
	*ref = ep;
    return refstrndup(sp, ep - sp);
}

static const char *refdup_word(char **p)
{
    return __refdup_word(*p, p);
}

int my_isxdigit(char c)
{
    unsigned int uc = c;

    return (uc - '0') < 10 || ((uc | 0x20) - 'a') < 6;
}

unsigned int hexval(char c)
{
    unsigned char uc = c | 0x20;
    unsigned int v;

    v = uc - '0';
    if (v < 10)
	return v;

    return uc - 'a' + 10;
}

unsigned int hexval2(const char *p)
{
    return (hexval(p[0]) << 4) + hexval(p[1]);
}

uint32_t parse_argb(char **p)
{
    char *sp = *p;
    char *ep;
    uint32_t argb;
    size_t len, dl;

    if (*sp == '#')
	sp++;

    ep = sp;

    while (my_isxdigit(*ep))
	ep++;

    *p = ep;
    len = ep - sp;

    switch (len) {
    case 3:			/* #rgb */
	argb =
	    0xff000000 +
	    (hexval(sp[0]) * 0x11 << 16) +
	    (hexval(sp[1]) * 0x11 << 8) + (hexval(sp[2]) * 0x11);
	break;
    case 4:			/* #argb */
	argb =
	    (hexval(sp[0]) * 0x11 << 24) +
	    (hexval(sp[1]) * 0x11 << 16) +
	    (hexval(sp[2]) * 0x11 << 8) + (hexval(sp[3]) * 0x11);
	break;
    case 6:			/* #rrggbb */
    case 9:			/* #rrrgggbbb */
    case 12:			/* #rrrrggggbbbb */
	dl = len / 3;
	argb =
	    0xff000000 +
	    (hexval2(sp + 0) << 16) +
	    (hexval2(sp + dl) << 8) + hexval2(sp + dl * 2);
	break;
    case 8:			/* #aarrggbb */
	/* #aaarrrgggbbb is indistinguishable from #rrrrggggbbbb,
	   assume the latter is a more common format */
    case 16:			/* #aaaarrrrggggbbbb */
	dl = len / 4;
	argb =
	    (hexval2(sp + 0) << 24) +
	    (hexval2(sp + dl) << 16) +
	    (hexval2(sp + dl * 2) << 8) + hexval2(sp + dl * 3);
	break;
    default:
	argb = 0xffff0000;	/* Bright red (error indication) */
	break;
    }

    return argb;
}

/*
 * Parser state.  This is global so that including multiple
 * files work as expected, which is that everything works the
 * same way as if the files had been concatenated together.
 */
//static const char *append = NULL;
extern const char *append;
extern uint16_t PXERetry;
static struct labeldata ld;

static int parse_main_config(const char *filename);

static char *is_kernel_type(char *cmdstr, enum kernel_type *type)
{
    const char *const *p;
    char *q;
    enum kernel_type t = KT_NONE;

    for (p = kernel_types; *p; p++, t++) {
	if ((q = looking_at(cmdstr, *p))) {
	    *type = t;
	    return q;
	}
    }

    return NULL;
}

static char *is_message_name(char *cmdstr, enum message_number *msgnr)
{
    char *q;
    enum message_number i;

    for (i = 0; i < MSG_COUNT; i++) {
	if ((q = looking_at(cmdstr, messages[i].name))) {
	    *msgnr = i;
	    return q;
	}
    }

    return NULL;
}

extern void get_msg_file(char *);

void cat_help_file(int key)
{
	struct menu *cm = current_menu;
	int fkey;

	switch (key) {
	case KEY_F1:
		fkey = 0;
		break;
	case KEY_F2:
		fkey = 1;
		break;
	case KEY_F3:
		fkey = 2;
		break;
	case KEY_F4:
		fkey = 3;
		break;
	case KEY_F5:
		fkey = 4;
		break;
	case KEY_F6:
		fkey = 5;
		break;
	case KEY_F7:
		fkey = 6;
		break;
	case KEY_F8:
		fkey = 7;
		break;
	case KEY_F9:
		fkey = 8;
		break;
	case KEY_F10:
		fkey = 9;
		break;
	case KEY_F11:
		fkey = 10;
		break;
	case KEY_F12:
		fkey = 11;
		break;
	default:
		fkey = -1;
		break;
	}

	if (fkey == -1)
		return;

	if (cm->fkeyhelp[fkey].textname) {
		printf("\n");
		get_msg_file((char *)cm->fkeyhelp[fkey].textname);
	}
}

static char *is_fkey(char *cmdstr, int *fkeyno)
{
    char *q;
    int no;

    if ((cmdstr[0] | 0x20) != 'f')
	return NULL;

    no = strtoul(cmdstr + 1, &q, 10);
    if (!my_isspace(*q))
	return NULL;

    if (no < 0 || no > 12)
	return NULL;

    *fkeyno = (no == 0) ? 10 : no - 1;
    return q;
}

extern uint8_t FlowIgnore;
extern uint8_t FlowInput;
extern uint8_t FlowOutput;
extern uint16_t SerialPort;
extern uint16_t BaudDivisor;
static uint8_t SerialNotice = 1;

#define DEFAULT_BAUD	9600
#define BAUD_DIVISOR	115200

extern void sirq_cleanup_nowipe(void);
extern void sirq_install(void);
extern void write_serial_str(char *);

extern void loadfont(const char *);
extern void loadkeys(const char *);

extern char syslinux_banner[];
extern char copyright_str[];

/*
 * PATH-based lookup
 *
 * Each entry in the PATH directive is separated by a colon, e.g.
 *
 *     PATH /bar:/bin/foo:/baz/bar/bin
 */
static int parse_path(char *p)
{
    struct path_entry *entry;
    const char *str;

    while (*p) {
	char *c = p;

	/* Find the next directory */
	while (*c && *c != ':')
	    c++;

	str = refstrndup(p, c - p);
	if (!str)
	    goto bail;

	entry = path_add(str);
	refstr_put(str);

	if (!entry)
	    goto bail;

	if (!*c++)
	    break;
	p = c;
    }

    return 0;

bail:
    return -1;
}

static void parse_config_file(FILE * f);

static void do_include_menu(char *str, struct menu *m)
{
    const char *file;
    char *p;
    FILE *f;
    int fd;

    p = skipspace(str);
    file = refdup_word(&p);
    p = skipspace(p);

    fd = open(file, O_RDONLY);
    if (fd < 0)
	goto put;

    f = fdopen(fd, "r");
    if (!f)
	goto bail;

    if (*p) {
	record(m, &ld, append);
	m = current_menu = begin_submenu(p);
    }

    parse_config_file(f);

    if (*p) {
	record(m, &ld, append);
	m = current_menu = end_submenu();
    }

bail:
    close(fd);
put:
    refstr_put(file);

}

static void do_include(char *str)
{
    const char *file;
    char *p;
    FILE *f;
    int fd;

    p = skipspace(str);
    file = refdup_word(&p);

    fd = open(file, O_RDONLY);
    if (fd < 0)
	goto put;

    f = fdopen(fd, "r");
    if (f)
	parse_config_file(f);

    close(fd);
put:
    refstr_put(file);
}

static void parse_config_file(FILE * f)
{
    char line[MAX_LINE], *p, *ep, ch;
    enum kernel_type type;
    enum message_number msgnr;
    int fkeyno;
    struct menu *m = current_menu;

    while (fgets(line, sizeof line, f)) {
	p = strchr(line, '\r');
	if (p)
	    *p = '\0';
	p = strchr(line, '\n');
	if (p)
	    *p = '\0';

	p = skipspace(line);

	if (looking_at(p, "menu")) {

	    p = skipspace(p + 4);

	    if (looking_at(p, "label")) {
			if (ld.label) {
				refstr_put(ld.menulabel);
				ld.menulabel = refstrdup(skipspace(p + 5));
			} else if (m->parent_entry) {
				refstr_put(m->parent_entry->displayname);
				m->parent_entry->displayname = refstrdup(skipspace(p + 5));
				consider_for_hotkey(m->parent, m->parent_entry);
				if (!m->title[0]) {
				/* MENU LABEL -> MENU TITLE on submenu */
				refstr_put(m->title);
				m->title = strip_caret(m->parent_entry->displayname);
				}
			}
			} else if (looking_at(p, "title")) {
			refstr_put(m->title);
			m->title = refstrdup(skipspace(p + 5));
			if (m->parent_entry) {
				/* MENU TITLE -> MENU LABEL on submenu */
				if (m->parent_entry->displayname == m->label) {
				refstr_put(m->parent_entry->displayname);
				m->parent_entry->displayname = refstr_get(m->title);
				}
			}
	    } else if (looking_at(p, "default")) {
		if (ld.label) {
		    ld.menudefault = 1;
		} else if (m->parent_entry) {
		    m->parent->defentry = m->parent_entry->entry;
		}
	    } else if (looking_at(p, "hide")) {
		ld.menuhide = 1;
	    } else if (looking_at(p, "passwd")) {
		if (ld.label) {
		    refstr_put(ld.passwd);
		    ld.passwd = refstrdup(skipspace(p + 6));
		} else if (m->parent_entry) {
		    refstr_put(m->parent_entry->passwd);
		    m->parent_entry->passwd = refstrdup(skipspace(p + 6));
		}
	    } else if (looking_at(p, "shiftkey")) {
		shiftkey = 1;
	    } else if (looking_at(p, "save")) {
		menusave = true;
		if (ld.label)
		    ld.save = 1;
		else
		    m->save = true;
	    } else if (looking_at(p, "nosave")) {
		if (ld.label)
		    ld.save = -1;
		else
		    m->save = false;
	    } else if (looking_at(p, "onerror")) {
		refstr_put(m->onerror);
		m->onerror = refstrdup(skipspace(p + 7));
		onerrorlen = strlen(m->onerror);
		refstr_put(onerror);
		onerror = refstrdup(m->onerror);
	    } else if (looking_at(p, "master")) {
		p = skipspace(p + 6);
		if (looking_at(p, "passwd")) {
		    refstr_put(m->menu_master_passwd);
		    m->menu_master_passwd = refstrdup(skipspace(p + 6));
		}
	    } else if ((ep = looking_at(p, "include"))) {
		do_include_menu(ep, m);
	    } else if ((ep = looking_at(p, "background"))) {
		p = skipspace(ep);
		refstr_put(m->menu_background);
		m->menu_background = refdup_word(&p);
	    } else if ((ep = looking_at(p, "hidden"))) {
		hiddenmenu = 1;
	    } else if ((ep = is_message_name(p, &msgnr))) {
		refstr_put(m->messages[msgnr]);
		m->messages[msgnr] = refstrdup(skipspace(ep));
	    } else if ((ep = looking_at(p, "color")) ||
		       (ep = looking_at(p, "colour"))) {
		int i;
		struct color_table *cptr;
		p = skipspace(ep);
		cptr = m->color_table;
		for (i = 0; i < menu_color_table_size; i++) {
		    if ((ep = looking_at(p, cptr->name))) {
			p = skipspace(ep);
			if (*p) {
			    if (looking_at(p, "*")) {
				p++;
			    } else {
				refstr_put(cptr->ansi);
				cptr->ansi = refdup_word(&p);
			    }

			    p = skipspace(p);
			    if (*p) {
				if (looking_at(p, "*"))
				    p++;
				else
				    cptr->argb_fg = parse_argb(&p);

				p = skipspace(p);
				if (*p) {
				    if (looking_at(p, "*"))
					p++;
				    else
					cptr->argb_bg = parse_argb(&p);

				    /* Parse a shadow mode */
				    p = skipspace(p);
				    ch = *p | 0x20;
				    if (ch == 'n')	/* none */
					cptr->shadow = SHADOW_NONE;
				    else if (ch == 's')	/* std, standard */
					cptr->shadow = SHADOW_NORMAL;
				    else if (ch == 'a')	/* all */
					cptr->shadow = SHADOW_ALL;
				    else if (ch == 'r')	/* rev, reverse */
					cptr->shadow = SHADOW_REVERSE;
				}
			    }
			}
			break;
		    }
		    cptr++;
		}
	    } else if ((ep = looking_at(p, "msgcolor")) ||
		       (ep = looking_at(p, "msgcolour"))) {
		unsigned int fg_mask = MSG_COLORS_DEF_FG;
		unsigned int bg_mask = MSG_COLORS_DEF_BG;
		enum color_table_shadow shadow = MSG_COLORS_DEF_SHADOW;

		p = skipspace(ep);
		if (*p) {
		    if (!looking_at(p, "*"))
			fg_mask = parse_argb(&p);

		    p = skipspace(p);
		    if (*p) {
			if (!looking_at(p, "*"))
			    bg_mask = parse_argb(&p);

			p = skipspace(p);
			switch (*p | 0x20) {
			case 'n':
			    shadow = SHADOW_NONE;
			    break;
			case 's':
			    shadow = SHADOW_NORMAL;
			    break;
			case 'a':
			    shadow = SHADOW_ALL;
			    break;
			case 'r':
			    shadow = SHADOW_REVERSE;
			    break;
			default:
			    /* go with default */
			    break;
			}
		    }
		}
		set_msg_colors_global(m->color_table, fg_mask, bg_mask, shadow);
	    } else if (looking_at(p, "separator")) {
		record(m, &ld, append);
		ld.label = refstr_get(empty_string);
		ld.menuseparator = 1;
		record(m, &ld, append);
	    } else if (looking_at(p, "disable") || looking_at(p, "disabled")) {
		ld.menudisabled = 1;
	    } else if (looking_at(p, "indent")) {
		ld.menuindent = atoi(skipspace(p + 6));
	    } else if (looking_at(p, "begin")) {
		record(m, &ld, append);
		m = current_menu = begin_submenu(skipspace(p + 5));
	    } else if (looking_at(p, "end")) {
		record(m, &ld, append);
		m = current_menu = end_submenu();
	    } else if (looking_at(p, "quit")) {
		if (ld.label)
		    ld.action = MA_QUIT;
	    } else if (looking_at(p, "goto")) {
		if (ld.label) {
		    ld.action = MA_GOTO_UNRES;
		    refstr_put(ld.kernel);
		    ld.kernel = refstrdup(skipspace(p + 4));
		}
	    } else if (looking_at(p, "exit")) {
		p = skipspace(p + 4);
		if (ld.label && m->parent) {
		    if (*p) {
			/* This is really just a goto, except for the marker */
			ld.action = MA_EXIT_UNRES;
			refstr_put(ld.kernel);
			ld.kernel = refstrdup(p);
		    } else {
			ld.action = MA_EXIT;
			ld.submenu = m->parent;
		    }
		}
	    } else if (looking_at(p, "start")) {
		start_menu = m;
	    } else {
		/* Unknown, check for layout parameters */
		enum parameter_number mp;
		for (mp = 0; mp < NPARAMS; mp++) {
		    if ((ep = looking_at(p, mparm[mp].name))) {
			m->mparm[mp] = atoi(skipspace(ep));
			break;
		    }
		}
	    }
	}
	/* feng: menu handling end */	
	else if (looking_at(p, "text")) {

		/* loop till we fined the "endtext" */
	    enum text_cmd {
		TEXT_UNKNOWN,
		TEXT_HELP
	    } cmd = TEXT_UNKNOWN;
	    int len = ld.helptext ? strlen(ld.helptext) : 0;
	    int xlen;

	    p = skipspace(p + 4);

	    if (looking_at(p, "help"))
		cmd = TEXT_HELP;

	    while (fgets(line, sizeof line, f)) {
		p = skipspace(line);
		if (looking_at(p, "endtext"))
		    break;

		xlen = strlen(line);

		switch (cmd) {
		case TEXT_UNKNOWN:
		    break;
		case TEXT_HELP:
		    ld.helptext = realloc(ld.helptext, len + xlen + 1);
		    memcpy(ld.helptext + len, line, xlen + 1);
		    len += xlen;
		    break;
		}
	    }
	} else if ((ep = is_fkey(p, &fkeyno))) {
	    p = skipspace(ep);
	    if (m->fkeyhelp[fkeyno].textname) {
		refstr_put(m->fkeyhelp[fkeyno].textname);
		m->fkeyhelp[fkeyno].textname = NULL;
	    }
	    if (m->fkeyhelp[fkeyno].background) {
		refstr_put(m->fkeyhelp[fkeyno].background);
		m->fkeyhelp[fkeyno].background = NULL;
	    }

	    refstr_put(m->fkeyhelp[fkeyno].textname);
	    m->fkeyhelp[fkeyno].textname = refdup_word(&p);
	    if (*p) {
		p = skipspace(p);
		m->fkeyhelp[fkeyno].background = refdup_word(&p);
	    }
	} else if ((ep = looking_at(p, "include"))) {
	    do_include(ep);
	} else if (looking_at(p, "append")) {
	    const char *a = refstrdup(skipspace(p + 6));
	    if (ld.label) {
		refstr_put(ld.append);
		ld.append = a;
	    } else {
		refstr_put(append);
		append = a;
	    }
	    //dprintf("we got a append: %s", a);
	} else if (looking_at(p, "initrd")) {
	    const char *a = refstrdup(skipspace(p + 6));
	    if (ld.label) {
		refstr_put(ld.initrd);
		ld.initrd = a;
	    } else {
		/* Ignore */
	    }
	} else if (looking_at(p, "label")) {
	    p = skipspace(p + 5);
	    /* when first time see "label", it will not really record anything */
	    record(m, &ld, append);
	    ld.label = __refdup_word(p, NULL);
	    ld.kernel = __refdup_word(p, NULL);
	    /* feng: this is the default type for all */
	    ld.type = KT_KERNEL;
	    ld.passwd = NULL;
	    ld.append = NULL;
	    ld.initrd = NULL;
	    ld.menulabel = NULL;
	    ld.helptext = NULL;
	    ld.ipappend = SysAppends;
	    ld.menudefault = ld.menuhide = ld.menuseparator =
		ld.menudisabled = ld.menuindent = 0;
	} else if ((ep = is_kernel_type(p, &type))) {
	    if (ld.label) {
		refstr_put(ld.kernel);
		ld.kernel = refstrdup(skipspace(ep));
		ld.type = type;
		//dprintf("got a kernel: %s, type = %d", ld.kernel, ld.type);
	    }
	} else if (looking_at(p, "timeout")) {
	    kbdtimeout = (atoi(skipspace(p + 7)) * CLK_TCK + 9) / 10;
	} else if (looking_at(p, "totaltimeout")) {
	    totaltimeout = (atoll(skipspace(p + 13)) * CLK_TCK + 9) / 10;
	} else if (looking_at(p, "ontimeout")) {
	    ontimeout = refstrdup(skipspace(p + 9));
	    ontimeoutlen = strlen(ontimeout);
	} else if (looking_at(p, "allowoptions")) {
	    allowoptions = !!atoi(skipspace(p + 12));
	} else if ((ep = looking_at(p, "ipappend")) ||
		   (ep = looking_at(p, "sysappend"))) {
	    uint32_t s = strtoul(skipspace(ep), NULL, 0);
	    if (ld.label)
		ld.ipappend = s;
	    else
		SysAppends = s;
	} else if (looking_at(p, "default")) {
	    /* default could be a kernel image or another label */
	    refstr_put(globaldefault);
	    globaldefault = refstrdup(skipspace(p + 7));

	    /*
	     * On the chance that "default" is actually a kernel image
	     * and not a label, store a copy of it, but only if we
	     * haven't seen a "ui" command. "ui" commands take
	     * precendence over "default" commands.
	     */
	    if (defaultlevel < LEVEL_UI) {
		defaultlevel = LEVEL_DEFAULT;
		refstr_put(default_cmd);
		default_cmd = refstrdup(globaldefault);
	    }
	} else if (looking_at(p, "ui")) {
	    has_ui = 1;
	    defaultlevel = LEVEL_UI;
	    refstr_put(default_cmd);
	    default_cmd = refstrdup(skipspace(p + 2));
	}
	
	/*
	 * subset 1:  pc_opencmd 
	 * display/font/kbdmap are rather similar, open a file then do sth
	 */
	else if (looking_at(p, "display")) {
		const char *filename;
		char *dst = KernelName;
		size_t len = FILENAME_MAX - 1;

		filename = refstrdup(skipspace(p + 7));

		while (len-- && not_whitespace(*filename))
			*dst++ = *filename++;
		*dst = '\0';

		get_msg_file(KernelName);
		refstr_put(filename);
	} else if (looking_at(p, "font")) {
		const char *filename;
		char *dst = KernelName;
		size_t len = FILENAME_MAX - 1;

		filename = refstrdup(skipspace(p + 4));

		while (len-- && not_whitespace(*filename))
			*dst++ = *filename++;
		*dst = '\0';

		loadfont(KernelName);
		refstr_put(filename);
	} else if (looking_at(p, "kbdmap")) {
		const char *filename;

		filename = refstrdup(skipspace(p + 6));
		loadkeys(filename);
		refstr_put(filename);
	}
	/*
	 * subset 2:  pc_setint16
	 * set a global flag
	 */
	else if (looking_at(p, "implicit")) {
		allowimplicit = atoi(skipspace(p + 8));
	} else if (looking_at(p, "prompt")) {
		forceprompt = atoi(skipspace(p + 6));
	} else if (looking_at(p, "console")) {
		DisplayCon = atoi(skipspace(p + 7));
	} else if (looking_at(p, "allowoptions")) {
		allowoptions = atoi(skipspace(p + 12));
	} else if (looking_at(p, "noescape")) {
		noescape = atoi(skipspace(p + 8));
	} else if (looking_at(p, "nocomplete")) {
		nocomplete = atoi(skipspace(p + 10));
	} else if (looking_at(p, "nohalt")) {
		NoHalt = atoi(skipspace(p + 8));
	} else if (looking_at(p, "onerror")) {
		refstr_put(m->onerror);
		m->onerror = refstrdup(skipspace(p + 7));
		onerrorlen = strlen(m->onerror);
		refstr_put(onerror);
		onerror = refstrdup(m->onerror);
	}

	else if (looking_at(p, "pxeretry"))
		PXERetry = atoi(skipspace(p + 8));

	/* serial setting, bps, flow control */
	else if (looking_at(p, "serial")) {
		uint16_t port, flow;
		uint32_t baud;

		p = skipspace(p + 6);
		port = atoi(p);

		while (isalnum(*p))
			p++;
		p = skipspace(p);

		/* Default to no flow control */
		FlowOutput = 0;
		FlowInput = 0;

		baud = DEFAULT_BAUD;
		if (isalnum(*p)) {
			uint8_t ignore;

			/* setup baud */
			baud = atoi(p);
			while (isalnum(*p))
				p++;
			p = skipspace(p);

			ignore = 0;
			flow = 0;
			if (isalnum(*p)) {
				/* flow control */
				flow = atoi(p);
				ignore = ((flow & 0x0F00) >> 4);
			}

			FlowIgnore = ignore;
			flow = ((flow & 0xff) << 8) | (flow & 0xff);
			flow &= 0xF00B;
			FlowOutput = (flow & 0xff);
			FlowInput = ((flow & 0xff00) >> 8);
		}

		/*
		 * Parse baud
		 */
		if (baud < 75) {
			/* < 75 baud == bogus */
			SerialPort = 0;
			continue;
		}

		baud = BAUD_DIVISOR / baud;
		baud &= 0xffff;
		BaudDivisor = baud;

		port = get_serial_port(port);
		SerialPort = port;

		/*
		 * Begin code to actually set up the serial port
		 */
		sirq_cleanup_nowipe();

		outb(0x83, port + 3); /* Enable DLAB */
		io_delay();

		outb((baud & 0xff), port); /* write divisor to LS */
		io_delay();

		outb(((baud & 0xff00) >> 8), port + 1); /* write to MS */
		io_delay();

		outb(0x03, port + 3); /* Disable DLAB */
		io_delay();

		/*
		 * Read back LCR (detect missing hw). If nothing here
		 * we'll read 00 or FF.
		 */
		if (inb(port + 3) != 0x03) {
			/* Assume serial port busted */
			SerialPort = 0;
			continue;
		}

		outb(0x01, port + 2); /* Enable FIFOs if present */
		io_delay();

		/* Disable FIFO if unusable */
		if (inb(port + 2) < 0x0C0) {
			outb(0, port + 2);
			io_delay();
		}

		/* Assert bits in MCR */
		outb(FlowOutput, port + 4);
		io_delay();

		/* Enable interrupts if requested */
		if (FlowOutput & 0x8)
			sirq_install();

		/* Show some life */
		if (SerialNotice != 0) {
			SerialNotice = 0;

			write_serial_str(syslinux_banner);
			write_serial_str(copyright_str);
		}

	} else if (looking_at(p, "say")) {
		printf("%s\n", p+4);
	} else if (looking_at(p, "path")) {
		if (parse_path(skipspace(p + 4)))
			printf("Failed to parse PATH\n");
	} else if (looking_at(p, "sendcookies")) {
		const union syslinux_derivative_info *sdi;

		p += strlen("sendcookies");
		sdi = syslinux_derivative_info();

		if (sdi->c.filesystem == SYSLINUX_FS_PXELINUX) {
			SendCookies = strtoul(skipspace(p), NULL, 10);
			http_bake_cookies();
		}
	}
    }
}

static int parse_main_config(const char *filename)
{
	const char *mode = "r";
	FILE *f;
	int fd;

	if (!filename)
		fd = open_config();
	else
		fd = open(filename, O_RDONLY);

	if (fd < 0)
		return fd;

	if (config_cwd[0]) {
		if (chdir(config_cwd) < 0)
			printf("Failed to chdir to %s\n", config_cwd);
		config_cwd[0] = '\0';
	}

	f = fdopen(fd, mode);
	parse_config_file(f);

	/*
	 * Update ConfigName so that syslinux_config_file() returns
	 * the filename we just opened. filesystem-specific
	 * open_config() implementations are expected to update
	 * ConfigName themselves.
	 */
	if (filename)
	    strcpy(ConfigName, filename);

	return 0;
}

static void resolve_gotos(void)
{
    struct menu_entry *me;
    struct menu *m;

    for (me = all_entries; me; me = me->next) {
	if (me->action == MA_GOTO_UNRES || me->action == MA_EXIT_UNRES) {
	    m = find_menu(me->cmdline);
	    refstr_put(me->cmdline);
	    me->cmdline = NULL;
	    if (m) {
		me->submenu = m;
		me->action--;	/* Drop the _UNRES */
	    } else {
		me->action = MA_DISABLED;
	    }
	}
    }
}

void parse_configs(char **argv)
{
    const char *filename;
    struct menu *m;
    struct menu_entry *me;
    dprintf("enter");

    empty_string = refstrdup("");

    /* feng: reset current menu_list and entry list */
    menu_list = NULL;
    all_entries = NULL;

    /* Initialize defaults for the root and hidden menus */
    hide_menu = new_menu(NULL, NULL, refstrdup(".hidden"));
    root_menu = new_menu(NULL, NULL, refstrdup(".top"));
    start_menu = root_menu;

    /* Other initialization */
    memset(&ld, 0, sizeof(struct labeldata));

    /* Actually process the files */
    current_menu = root_menu;

    if (!argv || !*argv) {
	if (parse_main_config(NULL) < 0) {
	    printf("WARNING: No configuration file found\n");
	    return;
	}
    } else {
	while ((filename = *argv++)) {
		dprintf("Parsing config: %s", filename);
	    parse_main_config(filename);
	}
    }

    /* On final EOF process the last label statement */
    record(current_menu, &ld, append);

    /* Common postprocessing */
    resolve_gotos();

    /* Handle global default */
    //if (has_ui && globaldefault) {
    if (globaldefault) {
	dprintf("gloabldefault = %s", globaldefault);
	me = find_label(globaldefault);
	if (me && me->menu != hide_menu) {
	    me->menu->defentry = me->entry;
	    start_menu = me->menu;
	    default_menu = me->menu;
	}
    }

    /* If "menu save" is active, let the ADV override the global default */
    if (menusave) {
	size_t len;
	const char *lbl = syslinux_getadv(ADV_MENUSAVE, &len);
	char *lstr;
	if (lbl && len) {
	    lstr = refstr_alloc(len);
	    memcpy(lstr, lbl, len);	/* refstr_alloc() adds the final null */
	    me = find_label(lstr);
	    if (me && me->menu != hide_menu) {
		me->menu->defentry = me->entry;
		start_menu = me->menu;
	    }
	    refstr_put(lstr);
	}
    }

    /* Final per-menu initialization, with all labels known */
    for (m = menu_list; m; m = m->next) {
	m->curentry = m->defentry;	/* All menus start at their defaults */

	if (m->ontimeout)
	    m->ontimeout = unlabel(m->ontimeout);
	if (m->onerror)
	    m->onerror = unlabel(m->onerror);
    }
}
