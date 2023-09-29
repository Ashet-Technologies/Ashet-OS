/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2011 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <minmax.h>
#include <alloca.h>
#include <inttypes.h>
#include <colortbl.h>
#include <com32.h>
#include <syslinux/adv.h>
#include <syslinux/config.h>

#include "menu.h"

/* Empty refstring */
const char *empty_string;

/* Root menu, starting menu, hidden menu, and list of all menus */
struct menu *root_menu, *start_menu, *hide_menu, *menu_list;

/* These are global parameters regardless of which menu we're displaying */
int shiftkey = 0;		/* Only display menu if shift key pressed */
int hiddenmenu = 0;
int clearmenu = 0;
long long totaltimeout = 0;
const char *hide_key[KEY_MAX];

/* Keep track of global default */
static int has_ui = 0;		/* DEFAULT only counts if UI is found */
static const char *globaldefault = NULL;
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

/* Get a single word into a new refstr; advances the input pointer */
static char *get_word(char *str, char **word)
{
    char *p = str;
    char *q;

    while (*p && !my_isspace(*p))
	p++;

    *word = q = refstr_alloc(p - str);
    memcpy(q, str, p - str);
    /* refstr_alloc() already inserted a terminating NUL */

    return p;
}

static struct menu *new_menu(struct menu *parent,
			     struct menu_entry *parent_entry, const char *label)
{
    struct menu *m = calloc(1, sizeof(struct menu));
    int i;

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
	m->immediate = parent->immediate;

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
    int immediate;
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

    if (ld->label) {
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
	me->immediate = ld->immediate ? (ld->immediate > 0) : m->immediate;

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
	    if (ld->type == KT_KERNEL) {
		rsprintf(&me->cmdline, "%s%s%s%s", ld->kernel, s, a, ipoptions);
	    } else {
		rsprintf(&me->cmdline, ".%s %s%s%s%s",
			 kernel_types[ld->type], ld->kernel, s, a, ipoptions);
	    }
	    break;

	case MA_GOTO_UNRES:
	case MA_EXIT_UNRES:
	    me->cmdline = refstr_get(ld->kernel);
	    break;

	case MA_GOTO:
	case MA_EXIT:
	    me->submenu = ld->submenu;
	    break;

	case MA_HELP:
	    me->cmdline = refstr_get(ld->kernel);
	    me->background = refstr_get(ld->append);
	    break;

	default:
	    break;
	}

	if (ld->menudefault && (me->action == MA_CMD ||
				me->action == MA_GOTO ||
				me->action == MA_GOTO_UNRES))
	    m->defentry = m->nentries - 1;
    }

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

static struct menu_entry *find_label(const char *str)
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

static const char *refdup_word(char **p)
{
    char *sp = *p;
    char *ep = sp;

    while (*ep && !my_isspace(*ep))
	ep++;

    *p = ep;
    return refstrndup(sp, ep - sp);
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
static const char *append = NULL;
static unsigned int ipappend = 0;
static struct labeldata ld;

static int parse_one_config(const char *filename);

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

static void parse_config_file(FILE * f)
{
    char line[MAX_LINE], *p, *ep, ch;
    enum kernel_type type = -1;
    enum message_number msgnr = -1;
    int fkeyno = 0;
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
	    } else if (looking_at(p, "immediate")) {
		if (ld.label)
		    ld.immediate = 1;
		else
		    m->immediate = true;
	    } else if (looking_at(p, "noimmediate")) {
		if (ld.label)
		    ld.immediate = -1;
		else
		    m->immediate = false;
	    } else if (looking_at(p, "onerror")) {
		refstr_put(m->onerror);
		m->onerror = refstrdup(skipspace(p + 7));
	    } else if (looking_at(p, "master")) {
		p = skipspace(p + 6);
		if (looking_at(p, "passwd")) {
		    refstr_put(m->menu_master_passwd);
		    m->menu_master_passwd = refstrdup(skipspace(p + 6));
		}
	    } else if ((ep = looking_at(p, "include"))) {
		goto do_include;
	    } else if ((ep = looking_at(p, "background"))) {
		p = skipspace(ep);
		refstr_put(m->menu_background);
		m->menu_background = refdup_word(&p);
	    } else if ((ep = looking_at(p, "hidden"))) {
		hiddenmenu = 1;
	    } else if (looking_at(p, "hiddenkey")) {
		char *key_name, *k, *ek;
		const char *command;
		int key;
		p = get_word(skipspace(p + 9), &key_name);
		command = refstrdup(skipspace(p));
		k = key_name;
		for (;;) {
		    ek = strchr(k+1, ',');
		    if (ek)
			*ek = '\0';
		    key = key_name_to_code(k);
		    if (key >= 0) {
			refstr_put(hide_key[key]);
			hide_key[key] = refstr_get(command);
		    }
		    if (!ek)
			break;
		    k = ek+1;
		}
		refstr_put(key_name);
		refstr_put(command);
	    } else if ((ep = looking_at(p, "clear"))) {
		clearmenu = 1;
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
	    } else if (looking_at(p, "help")) {
		if (ld.label) {
		    ld.action = MA_HELP;
		    p = skipspace(p + 4);

		    refstr_put(ld.kernel);
		    ld.kernel = refdup_word(&p);

		    if (ld.append) {
			refstr_put(ld.append);
			ld.append = NULL;
		    }

		    if (*p) {
			p = skipspace(p);
			ld.append = refdup_word(&p); /* Background */
		    }
		}
	    } else if ((ep = looking_at(p, "resolution"))) {
		int x, y;
		x = strtoul(ep, &ep, 0);
		y = strtoul(skipspace(ep), NULL, 0);
		set_resolution(x, y);
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
	} else if (looking_at(p, "text")) {
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
do_include:
	    {
		const char *file;
		p = skipspace(ep);
		file = refdup_word(&p);
		p = skipspace(p);
		if (*p) {
		    record(m, &ld, append);
		    m = current_menu = begin_submenu(p);
		    parse_one_config(file);
		    record(m, &ld, append);
		    m = current_menu = end_submenu();
		} else {
		    parse_one_config(file);
		}
		refstr_put(file);
	    }
	} else if (looking_at(p, "append")) {
	    const char *a = refstrdup(skipspace(p + 6));
	    if (ld.label) {
		refstr_put(ld.append);
		ld.append = a;
	    } else {
		refstr_put(append);
		append = a;
	    }
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
	    record(m, &ld, append);
	    ld.label = refstrdup(p);
	    ld.kernel = refstrdup(p);
	    ld.type = KT_KERNEL;
	    ld.passwd = NULL;
	    ld.append = NULL;
	    ld.initrd = NULL;
	    ld.menulabel = NULL;
	    ld.helptext = NULL;
	    ld.ipappend = ipappend;
	    ld.menudefault = ld.menuhide = ld.menuseparator =
		ld.menudisabled = ld.menuindent = 0;
	} else if ((ep = is_kernel_type(p, &type))) {
	    if (ld.label) {
		refstr_put(ld.kernel);
		ld.kernel = refstrdup(skipspace(ep));
		ld.type = type;
	    }
	} else if (looking_at(p, "timeout")) {
	    m->timeout = (atoi(skipspace(p + 7)) * CLK_TCK + 9) / 10;
	} else if (looking_at(p, "totaltimeout")) {
	    totaltimeout = (atoll(skipspace(p + 13)) * CLK_TCK + 9) / 10;
	} else if (looking_at(p, "ontimeout")) {
	    m->ontimeout = refstrdup(skipspace(p + 9));
	} else if (looking_at(p, "allowoptions")) {
	    m->allowedit = !!atoi(skipspace(p + 12));
	} else if ((ep = looking_at(p, "ipappend")) ||
		   (ep = looking_at(p, "sysappend"))) {
	    uint32_t s = strtoul(skipspace(ep), NULL, 0);
	    if (ld.label)
		ld.ipappend = s;
	    else
		ipappend = s;
	} else if (looking_at(p, "default")) {
	    refstr_put(globaldefault);
	    globaldefault = refstrdup(skipspace(p + 7));
	} else if (looking_at(p, "ui")) {
	    has_ui = 1;
	}
    }
}

static int parse_one_config(const char *filename)
{
    FILE *f;

    if (!strcmp(filename, "~"))
	filename = syslinux_config_file();

    dprintf("Opening config file: %s ", filename);

    f = fopen(filename, "r");
    dprintf("%s\n", f ? "ok" : "failed");
    
    if (!f)
	return -1;

    parse_config_file(f);
    fclose(f);

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
    int k;

    empty_string = refstrdup("");

    /* Initialize defaults for the root and hidden menus */
    hide_menu = new_menu(NULL, NULL, refstrdup(".hidden"));
    root_menu = new_menu(NULL, NULL, refstrdup(".top"));
    start_menu = root_menu;

    /* Other initialization */
    memset(&ld, 0, sizeof(struct labeldata));

    /* Actually process the files */
    current_menu = root_menu;
    if (!*argv) {
	parse_one_config("~");
    } else {
	while ((filename = *argv++))
	    parse_one_config(filename);
    }

    /* On final EOF process the last label statement */
    record(current_menu, &ld, append);

    /* Common postprocessing */
    resolve_gotos();

    /* Handle global default */
    if (has_ui && globaldefault) {
	me = find_label(globaldefault);
	if (me && me->menu != hide_menu) {
	    me->menu->defentry = me->entry;
	    start_menu = me->menu;
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

    /* Final global initialization, with all labels known */
    for (k = 0; k < KEY_MAX; k++) {
	if (hide_key[k])
	    hide_key[k] = unlabel(hide_key[k]);
    }
}
