/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2005-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * ethersel.c
 *
 * Search for an Ethernet card with a known PCI signature, and run
 * the corresponding Ethernet module.
 *
 * To use this, set up a syslinux config file like this:
 *
 * PROMPT 0
 * DEFAULT ethersel.c32
 * # DEV [DID xxxx:yyyy[/mask]] [RID zz-zz] [SID uuuu:vvvv[/mask]] commandline
 * # ...
 *
 * DID = PCI device ID
 * RID = Revision ID (range)
 * SID = Subsystem ID
 */

#include <inttypes.h>
#include <stdio.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <console.h>
#include <sys/pci.h>
#include <com32.h>
#include <syslinux/boot.h>
#include <syslinux/config.h>
#include <dprintf.h>

#define MAX_LINE 512

/* Check to see if we are at a certain keyword (case insensitive) */
static int looking_at(const char *line, const char *kwd)
{
    const char *p = line;
    const char *q = kwd;

    while (*p && *q && ((*p ^ *q) & ~0x20) == 0) {
	p++;
	q++;
    }

    if (*q)
	return 0;		/* Didn't see the keyword */

    return *p <= ' ';		/* Must be EOL or whitespace */
}

static char *get_did(char *p, uint32_t * idptr, uint32_t * maskptr)
{
    unsigned long vid, did, m1, m2;

    *idptr = -1;
    *maskptr = 0xffffffff;

    vid = strtoul(p, &p, 16);
    if (*p != ':')
	return p;		/* Bogus ID */
    did = strtoul(p + 1, &p, 16);

    *idptr = (did << 16) + vid;

    if (*p == '/') {
	m1 = strtoul(p + 1, &p, 16);
	if (*p != ':') {
	    *maskptr = (m1 << 16) | 0xffff;
	} else {
	    m2 = strtoul(p + 1, &p, 16);
	    *maskptr = (m1 << 16) | m2;
	}
    }

    return p;
}

static char *get_rid_range(char *p, uint8_t * rid_min, uint8_t * rid_max)
{
    unsigned long r0, r1;

    p = skipspace(p + 3);

    r0 = strtoul(p, &p, 16);
    if (*p == '-') {
	r1 = strtoul(p + 1, &p, 16);
    } else {
	r1 = r0;
    }

    *rid_min = r0;
    *rid_max = r1;

    return p;
}

static struct match *parse_config(const char *filename)
{
    char line[MAX_LINE], *p;
    FILE *f;
    struct match *list = NULL;
    struct match **ep = &list;
    struct match *m;

    if (!filename)
	filename = syslinux_config_file();

    f = fopen(filename, "r");
    if (!f)
	return list;

    while (fgets(line, sizeof line, f)) {
	p = skipspace(line);

	if (!looking_at(p, "#"))
	    continue;
	p = skipspace(p + 1);

	if (!looking_at(p, "dev"))
	    continue;
	p = skipspace(p + 3);

	m = malloc(sizeof(struct match));
	if (!m)
	    continue;

	memset(m, 0, sizeof *m);
	m->rid_max = 0xff;

	for (;;) {
	    p = skipspace(p);

	    if (looking_at(p, "did")) {
		p = get_did(p + 3, &m->did, &m->did_mask);
	    } else if (looking_at(p, "sid")) {
		p = get_did(p + 3, &m->sid, &m->sid_mask);
	    } else if (looking_at(p, "rid")) {
		p = get_rid_range(p + 3, &m->rid_min, &m->rid_max);
	    } else {
		char *e;

		e = strchr(p, '\n');
		if (*e)
		    *e = '\0';
		e = strchr(p, '\r');
		if (*e)
		    *e = '\0';

		m->filename = strdup(p);
		if (!m->filename)
		    m->did = -1;
		break;		/* Done with this line */
	    }
	}

	dprintf("DEV DID %08x/%08x SID %08x/%08x RID %02x-%02x CMD %s\n",
		m->did, m->did_mask, m->sid, m->sid_mask,
		m->rid_min, m->rid_max, m->filename);

	*ep = m;
	ep = &m->next;
    }

    return list;
}

int main(int argc, char *argv[])
{
    struct match *list, *match;
    struct pci_domain *pci_domain;

    pci_domain = pci_scan();

    if (pci_domain) {
	list = parse_config(argc < 2 ? NULL : argv[1]);

	match = find_pci_device(pci_domain, list);

	if (match)
	    syslinux_run_command(match->filename);
    }

    /* On error, return to the command line */
    fputs("Error: no recognized network card found!\n", stderr);
    return 1;
}
