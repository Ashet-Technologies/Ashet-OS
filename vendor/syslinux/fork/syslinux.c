/* ----------------------------------------------------------------------- *
 *
 *   Copyright 1998-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2010 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * syslinux.c - Linux installer program for SYSLINUX
 *
 * This program does not require mtools. It's more portable if we just
 * use our own AshetOS zig libraries here instead of using mtools which is
 * hard to build on windows.
 */

#define _GNU_SOURCE
#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <mntent.h>
#include <paths.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sysexits.h>
#include <syslog.h>
#include <unistd.h>

#include "libfat.h"
#include "setadv.h"
#include "syslinux.h"
#include "syslxfs.h"
#include "syslxopt.h"

#include "syslinux-mtools.h"

char * program; /* Name of program */
pid_t mypid;

void __attribute__((noreturn)) die(const char * msg)
{
    fprintf(stderr, "%s: %s\n", program, msg);
    exit(1);
}

void __attribute__((noreturn)) die_err(const char * msg)
{
    fprintf(stderr, "%s: %s: %s\n", program, msg, strerror(errno));
    exit(1);
}

/*
 * read/write wrapper functions
 */
ssize_t xpread(int fd, void * buf, size_t count, off_t offset)
{
    char * bufp = (char *)buf;
    ssize_t rv;
    ssize_t done = 0;

    while (count)
    {
        rv = pread(fd, bufp, count, offset);
        if (rv == 0)
        {
            die("short read");
        }
        else if (rv == -1)
        {
            if (errno == EINTR)
            {
                continue;
            }
            else
            {
                die(strerror(errno));
            }
        }
        else
        {
            bufp += rv;
            offset += rv;
            done += rv;
            count -= rv;
        }
    }

    return done;
}

ssize_t xpwrite(int fd, const void * buf, size_t count, off_t offset)
{
    const char * bufp = (const char *)buf;
    ssize_t rv;
    ssize_t done = 0;

    while (count)
    {
        rv = pwrite(fd, bufp, count, offset);
        if (rv == 0)
        {
            die("short write");
        }
        else if (rv == -1)
        {
            if (errno == EINTR)
            {
                continue;
            }
            else
            {
                die(strerror(errno));
            }
        }
        else
        {
            bufp += rv;
            offset += rv;
            done += rv;
            count -= rv;
        }
    }

    return done;
}

/*
 * Version of the read function suitable for libfat
 */
int libfat_xpread(intptr_t pp, void * buf, size_t secsize, libfat_sector_t sector)
{
    off_t offset = (off_t)sector * secsize + opt.offset;
    return xpread(pp, buf, secsize, offset);
}

static bool move_file(char * filename)
{
    char target_file[4096], command[5120];
    char *cp = target_file, *ep = target_file + sizeof target_file - 16;
    const char * sd;
    int slash = 1;
    bool success;

    cp += sprintf(cp, "s:/");
    for (sd = opt.directory; *sd; sd++)
    {
        if (*sd == '/' || *sd == '\\')
        {
            if (slash)
                continue; /* Remove duplicated slashes */
            slash = 1;
        }
        else if (*sd == '\'' || *sd == '!')
        {
            slash = 0;
            if (cp < ep)
                *cp++ = '\'';
            if (cp < ep)
                *cp++ = '\\';
            if (cp < ep)
                *cp++ = *sd;
            if (cp < ep)
                *cp++ = '\'';
            continue;
        }
        else
        {
            slash = 0;
        }

        if (cp < ep)
            *cp++ = *sd;
    }
    if (!slash)
        *cp++ = '/';
    sprintf(cp, "%s", filename);

    /* This command may fail legitimately */
    success = mtools_flags_clear(target_file);
    (void)success; /* Keep _FORTIFY_SOURCE happy */

    sprintf(command, "s:/%s", filename);
    success = mtools_move_file(command, target_file);

    if (!success)
    {
        fprintf(stderr, "%s: warning: unable to move %s\n", program, filename);

        sprintf(command, "s:/%s", filename);
        success = mtools_flags_set(command);
    }
    else
    {
        success = mtools_flags_set(target_file);
    }

    return success;
}

int main(int argc, char * argv[])
{
    static unsigned char sectbuf[SECTOR_SIZE];
    int dev_fd;
    struct stat st;
    int status;
    int mtc_fd;
    FILE *mtc, *mtp;
    struct libfat_filesystem * fs;
    libfat_sector_t s, *secp;
    libfat_sector_t * sectors;
    int32_t ldlinux_cluster;
    int nsectors;
    const char * errmsg;
    int ldlinux_sectors, patch_sectors;
    int i;

    (void)argc; /* Unused */

    mypid = getpid();
    program = argv[0];

    parse_options(argc, argv, MODE_SYSLINUX);

    if (!opt.device)
        usage(EX_USAGE, MODE_SYSLINUX);

    if (opt.sectors || opt.heads || opt.reset_adv || opt.set_once || (opt.update_only > 0) || opt.menu_save)
    {
        fprintf(stderr,
                "At least one specified option not yet implemented"
                " for this installer.\n");
        exit(1);
    }

    /*
     * First make sure we can open the device at all, and that we have
     * read/write permission.
     */
    dev_fd = open(opt.device, O_RDWR);
    if (dev_fd < 0 || fstat(dev_fd, &st) < 0)
    {
        die_err(opt.device);
        exit(1);
    }

    if (!opt.force && !S_ISBLK(st.st_mode) && !S_ISREG(st.st_mode))
    {
        fprintf(stderr, "%s: not a block device or regular file (use -f to override)\n", opt.device);
        exit(1);
    }

    xpread(dev_fd, sectbuf, SECTOR_SIZE, opt.offset);

    /*
     * Check to see that what we got was indeed an MS-DOS boot sector/superblock
     */
    if ((errmsg = syslinux_check_bootsect(sectbuf, NULL)))
    {
        die(errmsg);
    }

    status = mtools_configure(dev_fd, opt.offset);
    if (!status)
        die_err("configuration");

    /*
     * Create a vacuous ADV in memory.  This should be smarter.
     */
    syslinux_reset_adv(syslinux_adv);

    /* This command may fail legitimately */
    status = mtools_flags_clear("s:/ldlinux.sys");
    (void)status; /* Keep _FORTIFY_SOURCE happy */

    status = mtools_create_file(
        "s:/ldlinux.sys",
        syslinux_ldlinux,
        syslinux_ldlinux_len,
        syslinux_adv,
        2 * ADV_SIZE);
    if (!status)
        die("failed to create ldlinux.sys");

    /*
     * Now, use libfat to create a block map
     */
    ldlinux_sectors = (syslinux_ldlinux_len + 2 * ADV_SIZE + SECTOR_SIZE - 1) >> SECTOR_SHIFT;
    sectors = calloc(ldlinux_sectors, sizeof *sectors);
    fs = libfat_open(libfat_xpread, dev_fd);
    ldlinux_cluster = libfat_searchdir(fs, 0, "LDLINUX SYS", NULL);
    secp = sectors;
    nsectors = 0;
    s = libfat_clustertosector(fs, ldlinux_cluster);
    while (s && nsectors < ldlinux_sectors)
    {
        *secp++ = s;
        nsectors++;
        s = libfat_nextsector(fs, s);
    }
    libfat_close(fs);

    /* Patch ldlinux.sys and the boot sector */
    i = syslinux_patch(sectors, nsectors, opt.stupid_mode, opt.raid_mode, opt.directory, NULL);
    patch_sectors = (i + SECTOR_SIZE - 1) >> SECTOR_SHIFT;

    /* Write the now-patched first sectors of ldlinux.sys */
    for (i = 0; i < patch_sectors; i++)
    {
        xpwrite(dev_fd,
                (const char _force *)syslinux_ldlinux + i * SECTOR_SIZE,
                SECTOR_SIZE,
                opt.offset + ((off_t)sectors[i] << SECTOR_SHIFT));
    }

    /* Move ldlinux.sys to the desired location */
    if (opt.directory)
    {
        status = move_file("ldlinux.sys");
    }
    else
    {
        status = mtools_flags_set("s:/ldlinux.sys");
    }

    if (!status)
    {
        fprintf(stderr, "%s: warning: failed to set system bit on ldlinux.sys\n", program);
    }

    /* This command may fail legitimately */
    status = mtools_flags_clear("s:/ldlinux.c32");
    (void)status; /* Keep _FORTIFY_SOURCE happy */

    status = mtools_create_file(
        "s:/ldlinux.c32",
        syslinux_ldlinuxc32,
        syslinux_ldlinuxc32_len,
        NULL,
        0);
    if (!status)
        die("failed to create ldlinux.c32");

    /* Move ldlinux.c32 to the desired location */
    if (opt.directory)
    {
        status = move_file("ldlinux.c32");
    }
    else
    {
        status = mtools_flags_set("s:/ldlinux.c32");
    }

    if (!status)
    {
        fprintf(stderr, "%s: warning: failed to set system bit on ldlinux.c32\n", program);
    }

    /*
     * To finish up, write the boot sector
     */

    /* Read the superblock again since it might have changed while mounted */
    xpread(dev_fd, sectbuf, SECTOR_SIZE, opt.offset);

    /* Copy the syslinux code into the boot sector */
    syslinux_make_bootsect(sectbuf, VFAT);

    /* Write new boot sector */
    xpwrite(dev_fd, sectbuf, SECTOR_SIZE, opt.offset);

    close(dev_fd);
    sync();

    /* Done! */

    return 0;
}
