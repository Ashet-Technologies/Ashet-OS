/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2013 Intel Corporation; author: Matt Fleming
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <klibc/compiler.h>
#include <linux/list.h>
#include <fs.h>
#include <string.h>

__export LIST_HEAD(PATH);

__export struct path_entry *path_add(const char *str)
{
    struct path_entry *entry;

    if (!strlen(str))
	return NULL;

    entry = malloc(sizeof(*entry));
    if (!entry)
	return NULL;

    entry->str = strdup(str);
    if (!entry->str)
	goto bail;

    list_add(&entry->list, &PATH);

    return entry;

bail:
    free(entry);
    return NULL;
}
