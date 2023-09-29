/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2012 Intel Corporation; author: H. Peter Anvin
 *   Chandramouli Narayanan
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * adv.c
 *
 * Core ADV I/O
 * Code consolidated from libinstaller/adv*.c and core/adv.inc with the
 * addition of EFI support
 *
 * Return 0 on success, -1 on error, and set errno.
 *
 */
#define  _GNU_SOURCE

#include <syslinux/config.h>
#include <string.h>
#include "adv.h"

unsigned char syslinux_adv[2 * ADV_SIZE];

static void cleanup_adv(unsigned char *advbuf)
{
    int i;
    uint32_t csum;

    /* Make sure both copies agree, and update the checksum */
    *(uint32_t *)advbuf =  ADV_MAGIC1;

    csum = ADV_MAGIC2;
    for (i = 8; i < ADV_SIZE - 4; i += 4)
	csum -= *(uint32_t *)(advbuf + i);

    *(uint32_t *)(advbuf + 4) =  csum;
    *(uint32_t *)(advbuf + ADV_SIZE - 4) =  ADV_MAGIC3;

    memcpy(advbuf + ADV_SIZE, advbuf, ADV_SIZE);
}

void syslinux_reset_adv(unsigned char *advbuf)
{
    /* Create an all-zero ADV */
    memset(advbuf + 2 * 4, 0, ADV_LEN);
    cleanup_adv(advbuf);
}

static int adv_consistent(const unsigned char *p)
{
    int i;
    uint32_t csum;

    if (*(uint32_t *)p != ADV_MAGIC1 ||
	*(uint32_t *)(p + ADV_SIZE - 4) != ADV_MAGIC3)
	return 0;

    csum = 0;
    for (i = 4; i < ADV_SIZE - 4; i += 4)
	csum += *(uint32_t *)(p + i);

    return csum == ADV_MAGIC2;
}

/*
 * Verify that an in-memory ADV is consistent, making the copies consistent.
 * If neither copy is OK, return -1 and call syslinux_reset_adv().
 */
int syslinux_validate_adv(unsigned char *advbuf)
{
    if (adv_consistent(advbuf + 0 * ADV_SIZE)) {
	memcpy(advbuf + ADV_SIZE, advbuf, ADV_SIZE);
	return 0;
    } else if (adv_consistent(advbuf + 1 * ADV_SIZE)) {
	memcpy(advbuf, advbuf + ADV_SIZE, ADV_SIZE);
	return 0;
    } else {
	syslinux_reset_adv(advbuf);
	return -1;
    }
}

/*
 * Read the ADV from an existing instance, or initialize if invalid.
 * Returns -1 on fatal errors, 0 if ADV is okay, 1 if the ADV is
 * invalid, and 2 if the file does not exist.
 */

/* make_filespec
 * Take the ASCII pathname and filename and concatenate them
 * into an allocated memory space as unicode file specification string.
 * The path and cfg ASCII strings are assumed to be null-terminated.
 * For EFI, the separation character in the path name is '\'
 * and therefore it is assumed that the file spec uses '\' as separation char
 *
 * The function returns
 * 	 0  if successful and fspec is a valid allocated CHAR16 pointer
 * 	    Caller is responsible to free up the allocated filespec string
 * 	-1  otherwise
 *
 */
static int make_filespec(CHAR16 **fspec, const char *path, const char *cfg)
{
	CHAR16 *p;
	int size, append;

	/* allocate size for a CHAR16 string */
	size = sizeof(CHAR16) * (strlena((CHAR8 *)path)+strlena((CHAR8 *)cfg)+2);	/* including null */
	*fspec = malloc(size);
	if (!*fspec) return -1;

	append = path[strlena((CHAR8 *)path) - 1] != '\\';
	for (p = *fspec; *path; path++, p++)
		*p = (CHAR16)*path;
	/* append the separation character to the path if need be */
	if (append) *p++ = (CHAR16)'\\';
	for (; *cfg; cfg++, p++)
		*p = (CHAR16)*cfg;
	*p = (CHAR16)CHAR_NULL;

	return 0;
}


/* TODO:
 * set_attributes() and clear_attributes() are supported for VFAT only
 */
int read_adv(const char *path, const char *cfg)
{
    CHAR16 *file;
    EFI_FILE_HANDLE fd;
    EFI_FILE_INFO st;
    int err = 0;
    int rv;

    rv = make_filespec(&file, path, cfg);
    if (rv < 0 || !file) {
	efi_perror(L"read_adv");
	return -1;
    }

    /* TBD: Not sure if EFI accepts the attribute read only
     * even if an existing file is opened for read access
     */
    fd = efi_open(file, EFI_FILE_MODE_READ);
    if (!fd) {
	if (efi_errno != EFI_NOT_FOUND) {
	    err = -1;
	} else {
	    syslinux_reset_adv(syslinux_adv);
	    err = 2;		/* Nonexistence is not a fatal error */
	}
    } else if (!efi_fstat(fd, &st)) {
	err = -1;
    } else if (st.FileSize < 2 * ADV_SIZE) {
	/* Too small to be useful */
	syslinux_reset_adv(syslinux_adv);
	err = 0;		/* Nothing to read... */
    } else if (efi_xpread(fd, syslinux_adv, 2 * ADV_SIZE,
		      st.FileSize - 2 * ADV_SIZE) != 2 * ADV_SIZE) {
	err = -1;
    } else {
	/* We got it... maybe? */
	err = syslinux_validate_adv(syslinux_adv) ? 1 : 0;
    }

    if (err < 0)
	efi_perror(file);
    if (fd)
	efi_close(fd);
    free(file);

    return err;
}

/* For EFI platform, initialize ADV by opening ldlinux.sys
 * as configured and return the primary (adv0) and alternate (adv1)
 * data into caller's buffer. File remains open for subsequent
 * operations. This routine is to be called from comboot vector.
 */
void efi_adv_init(void)
{
    union syslinux_derivative_info sdi;

    get_derivative_info(&sdi);

    if (sdi.c.filesystem == SYSLINUX_FS_SYSLINUX)
	read_adv("", SYSLINUX_FILE);
    else {
	__syslinux_adv_ptr = &syslinux_adv[8]; /* skip head, csum */
	__syslinux_adv_size = ADV_LEN;

	syslinux_validate_adv(syslinux_adv);
    }
}

/* For EFI platform, write 2 * ADV_SIZE data to the file opened
 * at ADV initialization. (i.e ldlinux.sys).
 *
 * TODO:
 * 1. Validate assumption: write back to file from __syslinux_adv_ptr
 * 2. What if there errors?
 * 3. Do we need to set the attributes of the sys file?
 *
 */
int efi_adv_write(void)
{
    char *name;
    unsigned char advtmp[2 * ADV_SIZE];
    unsigned char *advbuf = syslinux_adv;
    int rv;
    int err = 0;
    EFI_FILE_HANDLE	fd;	/* handle to ldlinux.sys */
    CHAR16 *file;
    EFI_FILE_INFO st, xst;
    union syslinux_derivative_info sdi;

    get_derivative_info(&sdi);
    if (sdi.c.filesystem != SYSLINUX_FS_SYSLINUX)
	return -1;

    name = SYSLINUX_FILE;
    rv = make_filespec(&file, "", name);
    if (rv < 0 || !file) {
	efi_errno = EFI_OUT_OF_RESOURCES;
	efi_perror(L"efi_adv_write:");
	return -1;
    }

    fd = efi_open(file, EFI_FILE_MODE_READ);
    if (fd == (EFI_FILE_HANDLE)NULL) {
	err = -1;
	efi_printerr(L"efi_adv_write: Unable to open file %s\n", file);
    } else if (efi_fstat(fd, &st)) {
	err = -1;
	efi_printerr(L"efi_adv_write: Unable to get info for file %s\n", file);
    } else if (st.FileSize < 2 * ADV_SIZE) {
	/* Too small to be useful */
	err = -2;
	efi_printerr(L"efi_adv_write: File size too small to be useful for file %s\n", file);
    } else if (efi_xpread(fd, advtmp, 2 * ADV_SIZE,
		      st.FileSize - 2 * ADV_SIZE) != 2 * ADV_SIZE) {
	err = -1;
	efi_printerr(L"efi_adv_write: Error reading ADV data from file %s\n", file);
    } else {
	cleanup_adv(advbuf);
	err = syslinux_validate_adv(advbuf) ? -2 : 0;

	if (!err) {
	    /* Got a good one, write our own ADV here */
	    efi_clear_attributes(fd);

	    /* Need to re-open read-write */
	    efi_close(fd);
		/* There is no SYNC attribute with EFI open */
	    fd = efi_open(file, EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE);
	    if (fd == (EFI_FILE_HANDLE)NULL) {
		err = -1;
	    } else if (efi_fstat(fd, &xst) || xst.FileSize != st.FileSize) {
		efi_perror(L"efi_adv_write: file status error/mismatch");
		err = -2;
	    }
	    /* Write our own version ... */
	    if (efi_xpwrite(fd, advbuf, 2 * ADV_SIZE,
			st.FileSize - 2 * ADV_SIZE) != 2 * ADV_SIZE) {
		err = -1;
		efi_printerr(L"efi_adv_write: Error write ADV data to file %s\n", file);
	    }
	    if (!err) {
		efi_sync(fd);
		efi_set_attributes(fd);
	    }
	}
    }

    if (err == -2)
	efi_printerr(L"%s: cannot write auxilliary data (need --update)?\n",
		file);
    else if (err == -1)
	efi_perror(L"efi_adv_write:");

    if (fd)
	efi_close(fd);
    if (file)
	free(file);

    return err;
}
