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
 * This program now requires mtools.  It turned out to be a lot
 * easier to deal with than dealing with needing mount privileges.
 * We need device write permission anyway.
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
#include <string.h>
#include <stdlib.h>
#include <sysexits.h>
#include <syslog.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "syslinux.h"
#include "libfat.h"
#include "setadv.h"
#include "syslxopt.h"
#include "syslxfs.h"

char *program;			/* Name of program */
pid_t mypid;

void __attribute__ ((noreturn)) die(const char *msg)
{
    fprintf(stderr, "%s: %s\n", program, msg);
    exit(1);
}

void __attribute__ ((noreturn)) die_err(const char *msg)
{
    fprintf(stderr, "%s: %s: %s\n", program, msg, strerror(errno));
    exit(1);
}

/*
 * read/write wrapper functions
 */
ssize_t xpread(int fd, void *buf, size_t count, off_t offset)
{
    char *bufp = (char *)buf;
    ssize_t rv;
    ssize_t done = 0;

    while (count) {
	rv = pread(fd, bufp, count, offset);
	if (rv == 0) {
	    die("short read");
	} else if (rv == -1) {
	    if (errno == EINTR) {
		continue;
	    } else {
		die(strerror(errno));
	    }
	} else {
	    bufp += rv;
	    offset += rv;
	    done += rv;
	    count -= rv;
	}
    }

    return done;
}

ssize_t xpwrite(int fd, const void *buf, size_t count, off_t offset)
{
    const char *bufp = (const char *)buf;
    ssize_t rv;
    ssize_t done = 0;

    while (count) {
	rv = pwrite(fd, bufp, count, offset);
	if (rv == 0) {
	    die("short write");
	} else if (rv == -1) {
	    if (errno == EINTR) {
		continue;
	    } else {
		die(strerror(errno));
	    }
	} else {
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
int libfat_xpread(intptr_t pp, void *buf, size_t secsize,
		  libfat_sector_t sector)
{
    off_t offset = (off_t) sector * secsize + opt.offset;
    return xpread(pp, buf, secsize, offset);
}

static int move_file(char *filename)
{
    char target_file[4096], command[5120];
    char *cp = target_file, *ep = target_file + sizeof target_file - 16;
    const char *sd;
    int slash = 1;
    int status;

    cp += sprintf(cp, "'s:/");
    for (sd = opt.directory; *sd; sd++) {
	if (*sd == '/' || *sd == '\\') {
	    if (slash)
		continue;	/* Remove duplicated slashes */
	    slash = 1;
	} else if (*sd == '\'' || *sd == '!') {
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
	} else {
	    slash = 0;
	}

	if (cp < ep)
	    *cp++ = *sd;
    }
    if (!slash)
	*cp++ = '/';
    sprintf(cp, "%s'", filename);

    /* This command may fail legitimately */
    sprintf(command, "mattrib -h -r -s %s 2>/dev/null", target_file);
    status = system(command);
    (void)status;		/* Keep _FORTIFY_SOURCE happy */

    sprintf(command, "mmove -D o -D O s:/%s %s", filename, target_file);
    status = system(command);

    if (!WIFEXITED(status) || WEXITSTATUS(status)) {
	fprintf(stderr,
		"%s: warning: unable to move %s\n", program, filename);

	sprintf(command, "mattrib +r +h +s s:/%s", filename);
	status = system(command);
    } else {
	sprintf(command, "mattrib +r +h +s %s", target_file);
	status = system(command);
    }

    return status;
}

int main(int argc, char *argv[])
{
    static unsigned char sectbuf[SECTOR_SIZE];
    int dev_fd;
    struct stat st;
    int status;
    const char *tmpdir;
    char *mtools_conf;
    int mtc_fd;
    FILE *mtc, *mtp;
    struct libfat_filesystem *fs;
    libfat_sector_t s, *secp;
    libfat_sector_t *sectors;
    int32_t ldlinux_cluster;
    int nsectors;
    const char *errmsg;
    int ldlinux_sectors, patch_sectors;
    int i;

    (void)argc;			/* Unused */

    mypid = getpid();
    program = argv[0];

    parse_options(argc, argv, MODE_SYSLINUX);

    if (!opt.device)
	usage(EX_USAGE, MODE_SYSLINUX);

    if (opt.sectors || opt.heads || opt.reset_adv || opt.set_once
	|| (opt.update_only > 0) || opt.menu_save) {
	fprintf(stderr,
		"At least one specified option not yet implemented"
		" for this installer.\n");
	exit(1);
    }

    /*
     * Temp directory of choice...
     */
    tmpdir = getenv("TMPDIR");
    if (!tmpdir) {
#ifdef P_tmpdir
	tmpdir = P_tmpdir;
#elif defined(_PATH_TMP)
	tmpdir = _PATH_TMP;
#else
	tmpdir = "/tmp";
#endif
    }

    /*
     * First make sure we can open the device at all, and that we have
     * read/write permission.
     */
    dev_fd = open(opt.device, O_RDWR);
    if (dev_fd < 0 || fstat(dev_fd, &st) < 0) {
	die_err(opt.device);
	exit(1);
    }

    if (!opt.force && !S_ISBLK(st.st_mode) && !S_ISREG(st.st_mode)) {
	fprintf(stderr,
		"%s: not a block device or regular file (use -f to override)\n",
		opt.device);
	exit(1);
    }

    xpread(dev_fd, sectbuf, SECTOR_SIZE, opt.offset);

    /*
     * Check to see that what we got was indeed an MS-DOS boot sector/superblock
     */
    if ((errmsg = syslinux_check_bootsect(sectbuf, NULL))) {
	die(errmsg);
    }

    /*
     * Create an mtools configuration file
     */
    if (asprintf(&mtools_conf, "%s//syslinux-mtools-XXXXXX", tmpdir) < 0 ||
	!mtools_conf)
	die_err(tmpdir);

    mtc_fd = mkstemp(mtools_conf);
    if (mtc_fd < 0 || !(mtc = fdopen(mtc_fd, "w")))
	die_err(mtools_conf);

    fprintf(mtc,
	    /* These are needed for some flash memories */
	    "MTOOLS_SKIP_CHECK=1\n"
	    "MTOOLS_FAT_COMPATIBILITY=1\n"
	    "drive s:\n"
	    "  file=\"/proc/%lu/fd/%d\"\n"
	    "  offset=%llu\n",
	    (unsigned long)mypid,
	    dev_fd, (unsigned long long)opt.offset);

    if (ferror(mtc) || fclose(mtc))
	die_err(mtools_conf);

    /*
     * Run mtools to create the LDLINUX.SYS file
     */
    if (setenv("MTOOLSRC", mtools_conf, 1)) {
	perror(program);
	exit(1);
    }

    /*
     * Create a vacuous ADV in memory.  This should be smarter.
     */
    syslinux_reset_adv(syslinux_adv);

    /* This command may fail legitimately */
    status = system("mattrib -h -r -s s:/ldlinux.sys 2>/dev/null");
    (void)status;		/* Keep _FORTIFY_SOURCE happy */

    mtp = popen("mcopy -D o -D O -o - s:/ldlinux.sys", "w");
    if (!mtp ||
	fwrite((const void _force *)syslinux_ldlinux,
	       1, syslinux_ldlinux_len, mtp)
		!= syslinux_ldlinux_len ||
	fwrite((const void _force *)syslinux_adv,
	       1, 2 * ADV_SIZE, mtp)
		!= 2 * ADV_SIZE ||
	(status = pclose(mtp), !WIFEXITED(status) || WEXITSTATUS(status))) {
	die("failed to create ldlinux.sys");
    }

    /*
     * Now, use libfat to create a block map
     */
    ldlinux_sectors = (syslinux_ldlinux_len + 2 * ADV_SIZE
		       + SECTOR_SIZE - 1) >> SECTOR_SHIFT;
    sectors = calloc(ldlinux_sectors, sizeof *sectors);
    fs = libfat_open(libfat_xpread, dev_fd);
    ldlinux_cluster = libfat_searchdir(fs, 0, "LDLINUX SYS", NULL);
    secp = sectors;
    nsectors = 0;
    s = libfat_clustertosector(fs, ldlinux_cluster);
    while (s && nsectors < ldlinux_sectors) {
	*secp++ = s;
	nsectors++;
	s = libfat_nextsector(fs, s);
    }
    libfat_close(fs);

    /* Patch ldlinux.sys and the boot sector */
    i = syslinux_patch(sectors, nsectors, opt.stupid_mode, opt.raid_mode,
		       opt.directory, NULL);
    patch_sectors = (i + SECTOR_SIZE - 1) >> SECTOR_SHIFT;

    /* Write the now-patched first sectors of ldlinux.sys */
    for (i = 0; i < patch_sectors; i++) {
	xpwrite(dev_fd, (const char _force *)syslinux_ldlinux
		+ i * SECTOR_SIZE, SECTOR_SIZE,
		opt.offset + ((off_t) sectors[i] << SECTOR_SHIFT));
    }

    /* Move ldlinux.sys to the desired location */
    if (opt.directory) {
	status = move_file("ldlinux.sys");
    } else {
	status = system("mattrib +r +h +s s:/ldlinux.sys");
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status)) {
	fprintf(stderr,
		"%s: warning: failed to set system bit on ldlinux.sys\n",
		program);
    }

    /* This command may fail legitimately */
    status = system("mattrib -h -r -s s:/ldlinux.c32 2>/dev/null");
    (void)status;		/* Keep _FORTIFY_SOURCE happy */

    mtp = popen("mcopy -D o -D O -o - s:/ldlinux.c32", "w");
    if (!mtp ||	fwrite((const char _force *)syslinux_ldlinuxc32,
		       1, syslinux_ldlinuxc32_len, mtp)
	!= syslinux_ldlinuxc32_len ||
	(status = pclose(mtp), !WIFEXITED(status) || WEXITSTATUS(status))) {
	die("failed to create ldlinux.c32");
    }

    /* Move ldlinux.c32 to the desired location */
    if (opt.directory) {
	status = move_file("ldlinux.c32");
    } else {
	status = system("mattrib +r +h +s s:/ldlinux.c32");
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status)) {
	fprintf(stderr,
		"%s: warning: failed to set system bit on ldlinux.c32\n",
		program);
    }

    /*
     * Cleanup
     */
    unlink(mtools_conf);

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
