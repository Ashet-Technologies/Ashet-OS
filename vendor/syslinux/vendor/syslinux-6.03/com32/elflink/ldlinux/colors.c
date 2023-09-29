/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <colortbl.h>
#include "menu.h"

/*
 * The color/attribute indexes (\1#X, \2#XX, \3#XXX) are as follows
 *
 * 00 - screen		Rest of the screen
 * 01 - border		Border area
 * 02 - title		Title bar
 * 03 - unsel		Unselected menu item
 * 04 - hotkey		Unselected hotkey
 * 05 - sel		Selection bar
 * 06 - hotsel		Selected hotkey
 * 07 - scrollbar	Scroll bar
 * 08 - tabmsg		Press [Tab] message
 * 09 - cmdmark		Command line marker
 * 10 - cmdline		Command line
 * 11 - pwdborder	Password box border
 * 12 - pwdheader	Password box header
 * 13 - pwdentry	Password box contents
 * 14 - timeout_msg	Timeout message
 * 15 - timeout		Timeout counter
 * 16 - help		Current entry help text
 * 17 - disabled        Disabled menu item
 */

static const struct color_table default_colors[] = {
    {"screen", "37;40", 0x80ffffff, 0x00000000, SHADOW_NORMAL},
    {"border", "30;44", 0x40000000, 0x00000000, SHADOW_NORMAL},
    {"title", "1;36;44", 0xc00090f0, 0x00000000, SHADOW_NORMAL},
    {"unsel", "37;44", 0x90ffffff, 0x00000000, SHADOW_NORMAL},
    {"hotkey", "1;37;44", 0xffffffff, 0x00000000, SHADOW_NORMAL},
    {"sel", "7;37;40", 0xe0000000, 0x20ff8000, SHADOW_ALL},
    {"hotsel", "1;7;37;40", 0xe0400000, 0x20ff8000, SHADOW_ALL},
    {"scrollbar", "30;44", 0x40000000, 0x00000000, SHADOW_NORMAL},
    {"tabmsg", "31;40", 0x90ffff00, 0x00000000, SHADOW_NORMAL},
    {"cmdmark", "1;36;40", 0xc000ffff, 0x00000000, SHADOW_NORMAL},
    {"cmdline", "37;40", 0xc0ffffff, 0x00000000, SHADOW_NORMAL},
    {"pwdborder", "30;47", 0x80ffffff, 0x20ffffff, SHADOW_NORMAL},
    {"pwdheader", "31;47", 0x80ff8080, 0x20ffffff, SHADOW_NORMAL},
    {"pwdentry", "30;47", 0x80ffffff, 0x20ffffff, SHADOW_NORMAL},
    {"timeout_msg", "37;40", 0x80ffffff, 0x00000000, SHADOW_NORMAL},
    {"timeout", "1;37;40", 0xc0ffffff, 0x00000000, SHADOW_NORMAL},
    {"help", "37;40", 0xc0ffffff, 0x00000000, SHADOW_NORMAL},
    {"disabled", "1;30;44", 0x60cccccc, 0x00000000, SHADOW_NORMAL},
};

#define NCOLORS (sizeof default_colors/sizeof default_colors[0])
const int message_base_color = NCOLORS;
const int menu_color_table_size = NCOLORS + 256;

/* Algorithmically generate the msgXX colors */
void set_msg_colors_global(struct color_table *tbl,
			   unsigned int fg, unsigned int bg,
			   enum color_table_shadow shadow)
{
    struct color_table *cp = tbl + message_base_color;
    unsigned int i;
    unsigned int fga, bga;
    unsigned int fgh, bgh;
    unsigned int fg_idx, bg_idx;
    unsigned int fg_rgb, bg_rgb;

    static const unsigned int pc2rgb[8] =
	{ 0x000000, 0x0000ff, 0x00ff00, 0x00ffff, 0xff0000, 0xff00ff, 0xffff00,
	0xffffff
    };

    /* Converting PC RGBI to sensible RGBA values is an "interesting"
       proposition.  This algorithm may need plenty of tweaking. */

    fga = fg & 0xff000000;
    fgh = ((fg >> 1) & 0xff000000) | 0x80000000;

    bga = bg & 0xff000000;
    bgh = ((bg >> 1) & 0xff000000) | 0x80000000;

    for (i = 0; i < 256; i++) {
	fg_idx = i & 15;
	bg_idx = i >> 4;

	fg_rgb = pc2rgb[fg_idx & 7] & fg;
	bg_rgb = pc2rgb[bg_idx & 7] & bg;

	if (fg_idx & 8) {
	    /* High intensity foreground */
	    fg_rgb |= fgh;
	} else {
	    fg_rgb |= fga;
	}

	if (bg_idx == 0) {
	    /* Default black background, assume transparent */
	    bg_rgb = 0;
	} else if (bg_idx & 8) {
	    bg_rgb |= bgh;
	} else {
	    bg_rgb |= bga;
	}

	cp->argb_fg = fg_rgb;
	cp->argb_bg = bg_rgb;
	cp->shadow = shadow;
	cp++;
    }
}

struct color_table *default_color_table(void)
{
    unsigned int i;
    const struct color_table *dp;
    struct color_table *cp;
    struct color_table *color_table;
    static const int pc2ansi[8] = { 0, 4, 2, 6, 1, 5, 3, 7 };
    static char msg_names[6 * 256];
    char *mp;

    color_table = calloc(NCOLORS + 256, sizeof(struct color_table));

    dp = default_colors;
    cp = color_table;

    for (i = 0; i < NCOLORS; i++) {
	*cp = *dp;
	cp->ansi = refstrdup(dp->ansi);
	cp++;
	dp++;
    }

    mp = msg_names;
    for (i = 0; i < 256; i++) {
	cp->name = mp;
	mp += sprintf(mp, "msg%02x", i) + 1;

	rsprintf(&cp->ansi, "%s3%d;4%d", (i & 8) ? "1;" : "",
		 pc2ansi[i & 7], pc2ansi[(i >> 4) & 7]);
	cp++;
    }

  /*** XXX: This needs to move to run_menu() ***/
    console_color_table = color_table;
    console_color_table_size = NCOLORS + 256;

    set_msg_colors_global(color_table, MSG_COLORS_DEF_FG,
			  MSG_COLORS_DEF_BG, MSG_COLORS_DEF_SHADOW);

    return color_table;
}

struct color_table *copy_color_table(const struct color_table *master)
{
    const struct color_table *dp;
    struct color_table *color_table, *cp;
    unsigned int i;

    color_table = calloc(NCOLORS + 256, sizeof(struct color_table));

    dp = master;
    cp = color_table;

    for (i = 0; i < NCOLORS + 256; i++) {
	*cp = *dp;
	cp->ansi = refstr_get(dp->ansi);
	cp++;
	dp++;
    }

    return color_table;
}
