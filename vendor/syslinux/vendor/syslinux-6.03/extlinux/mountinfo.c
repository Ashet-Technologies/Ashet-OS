/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2012 Intel Corporation; All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include "mountinfo.h"

/*
 * Parse /proc/self/mountinfo
 */
static int get_string(FILE *f, char *string_buf, size_t string_len, char *ec)
{
    int ch;
    char *p = string_buf;

    for (;;) {
	if (!string_len)
	    return -2;		/* String too long */

	ch = getc(f);
	if (ch == EOF) {
	    return -1;		/* Got EOF */
	} else if (ch == ' ' || ch == '\t' || ch == '\n') {
	    *ec = ch;
	    *p = '\0';
	    return p - string_buf;
	} else if (ch == '\\') {
	    /* Should always be followed by 3 octal digits in 000..377 */
	    int oc = 0;
	    int i;
	    for (i = 0; i < 3; i++) {
		ch = getc(f);
		if (ch < '0' || ch > '7' || (i == 0 && ch > '3'))
		    return -1;	/* Bad escape sequence */
		oc = (oc << 3) + (ch - '0');
	    }
	    if (!oc)
		return -1;	/* We can't handle \000 */
	    *p++ = oc;
	    string_len--;
	} else {
	    *p++ = ch;
	    string_len--;
	}
    }
}

static void free_mountinfo(struct mountinfo *m)
{
    struct mountinfo *nx;

    while (m) {
	free((char *)m->root);
	free((char *)m->path);
	free((char *)m->fstype);
	free((char *)m->devpath);
	free((char *)m->mountopt);
	nx = m->next;
	free(m);
	m = nx;
    }
}

static struct mountinfo *head = NULL, **tail = &head;

static void parse_mountinfo(void)
{
    FILE *f;
    struct mountinfo *m, *mm;
    char string_buf[PATH_MAX*8];
    int n;
    char ec, *ep;
    unsigned int ma, mi;

    f = fopen("/proc/self/mountinfo", "r");
    if (!f)
	return;

    for (;;) {
	m = malloc(sizeof(struct mountinfo));
	if (!m)
	    break;
	memset(m, 0, sizeof *m);

	n = get_string(f, string_buf, sizeof string_buf, &ec);
	if (n < 0 || ec == '\n')
	    break;

	m->mountid = strtoul(string_buf, &ep, 10);
	if (*ep)
	    break;

	n = get_string(f, string_buf, sizeof string_buf, &ec);
	if (n < 0 || ec == '\n')
	    break;

	m->parentid = strtoul(string_buf, &ep, 10);
	if (*ep)
	    break;

	n = get_string(f, string_buf, sizeof string_buf, &ec);
	if (n < 0 || ec == '\n')
	    break;

	if (sscanf(string_buf, "%u:%u", &ma, &mi) != 2)
	    break;

	m->dev = makedev(ma, mi);

	n = get_string(f, string_buf, sizeof string_buf, &ec);
	if (n < 1 || ec == '\n' || string_buf[0] != '/')
	    break;

	m->root = strdup(string_buf);
	if (!m->root)
	    break;

	n = get_string(f, string_buf, sizeof string_buf, &ec);
	if (n < 1 || ec == '\n' || string_buf[0] != '/')
	    break;

	m->path = strdup(string_buf);
	m->pathlen = (n == 1) ? 0 : n; /* Treat / as empty */

	/* Skip tagged attributes */
	do {
	    n = get_string(f, string_buf, sizeof string_buf, &ec);
	    if (n < 0 || ec == '\n')
		goto quit;
	} while (n != 1 || string_buf[0] != '-');

	n = get_string(f, string_buf, sizeof string_buf, &ec);
	if (n < 0 || ec == '\n')
	    break;

	m->fstype = strdup(string_buf);
	if (!m->fstype)
	    break;

	n = get_string(f, string_buf, sizeof string_buf, &ec);
	if (n < 0 || ec == '\n')
	    break;

	m->devpath = strdup(string_buf);
	if (!m->devpath)
	    break;

	n = get_string(f, string_buf, sizeof string_buf, &ec);
	if (n < 0)
	    break;

	m->mountopt = strdup(string_buf);
	if (!m->mountopt)
	    break;

	/* Skip any previously unknown fields */
	while (ec != '\n' && ec != EOF)
	    ec = getc(f);

	*tail = m;
	tail = &m->next;
    }
quit:
    fclose(f);
    free_mountinfo(m);

    /* Create parent links */
    for (m = head; m; m = m->next) {
	for (mm = head; mm; mm = mm->next) {
	    if (m->parentid == mm->mountid) {
		m->parent = mm;
		if (!strcmp(m->path, mm->path))
		    mm->hidden = 1; /* Hidden under another mount */
		break;
	    }
	}
    }
}

const struct mountinfo *find_mount(const char *path, char **subpath)
{
    static int done_init;
    char *real_path;
    const struct mountinfo *m, *best;
    struct stat st;
    int len, matchlen;

    if (!done_init) {
	parse_mountinfo();
	done_init = 1;
    }

    if (stat(path, &st))
	return NULL;

    real_path = realpath(path, NULL);
    if (!real_path)
	return NULL;

    /*
     * Tricky business: we need the longest matching subpath
     * which isn't a parent of the same subpath.
     */
    len = strlen(real_path);
    matchlen = 0;
    best = NULL;
    for (m = head; m; m = m->next) {
	if (m->hidden)
	    continue;		/* Hidden underneath another mount */

	if (m->pathlen > len)
	    continue;		/* Cannot possibly match */

	if (m->pathlen < matchlen)
	    continue;		/* No point in testing this one */

	if (st.st_dev == m->dev &&
	    !memcmp(m->path, real_path, m->pathlen) &&
	    (real_path[m->pathlen] == '/' || real_path[m->pathlen] == '\0')) {
	    matchlen = m->pathlen;
	    best = m;
	}
    }

    if (best && subpath) {
	if (real_path[best->pathlen] == '\0')
	    *subpath = strdup("/");
	else
	    *subpath = strdup(real_path + best->pathlen);
    }

    return best;
}

#ifdef TEST

int main(int argc, char *argv[])
{
    int i;
    const struct mountinfo *m;
    char *subpath;

    parse_mountinfo();

    for (i = 1; i < argc; i++) {
	m = find_mount(argv[i], &subpath);
	if (!m) {
	    printf("%s: %s\n", argv[i], strerror(errno));
	    continue;
	}

	printf("%s -> %s @ %s(%u,%u):%s %s %s\n",
	       argv[i], subpath, m->devpath, major(m->dev), minor(m->dev),
	       m->root, m->fstype, m->mountopt);
	printf("Usable device: %s\n", find_device(m->dev, m->devpath));
	free(subpath);
    }

    return 0;
}

#endif
