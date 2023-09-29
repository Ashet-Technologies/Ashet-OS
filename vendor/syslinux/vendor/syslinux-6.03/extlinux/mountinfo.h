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

#ifndef SYSLINUX_MOUNTINFO_H
#define SYSLINUX_MOUNTINFO_H

#include <sys/types.h>

struct mountinfo {
    struct mountinfo *next;
    struct mountinfo *parent;
    const char *root;
    const char *path;
    const char *fstype;
    const char *devpath;
    const char *mountopt;
    int mountid;
    int parentid;
    int pathlen;
    int hidden;
    dev_t dev;
};

const struct mountinfo *find_mount(const char *path, char **subpath);

#endif /* SYSLINUX_MOUNTINFO_H */
