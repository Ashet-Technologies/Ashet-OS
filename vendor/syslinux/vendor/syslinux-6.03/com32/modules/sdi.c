/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * sdi.c
 *
 * Loader for the Microsoft System Deployment Image (SDI) format.
 * Based on a historical patch by Remi Lefevre.
 */

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <minmax.h>
#include <sys/stat.h>
#include <console.h>
#include <dprintf.h>

#include <syslinux/loadfile.h>
#include <syslinux/movebits.h>
#include <syslinux/bootrm.h>

typedef uint8_t guid_t[16];

struct SDIHeader {
    uint32_t Signature;
    char Version[4];
    uint64_t MDBtype;
    uint64_t BootCodeOffset;
    uint64_t BootCodeSize;
    uint64_t VendorID;
    uint64_t DeviceID;
    guid_t DeviceModel;
    uint64_t DeviceRole;
    uint64_t Reserved1;
    guid_t RuntimeGUID;
    uint64_t RuntimeOEMrev;
    uint64_t Reserved2;
    uint64_t PageAlignment;	/* BLOB alignment value in pages */
    uint64_t Reserved3[48];
    uint64_t Checksum;
};

#define SDI_LOAD_ADDR	(16 << 20)	/* 16 MB */
#define SDI_SIGNATURE	('$' + ('S' << 8) + ('D' << 16) + ('I' << 24))

static inline void error(const char *msg)
{
    fputs(msg, stderr);
}

static int boot_sdi(void *ptr, size_t len)
{
    const struct SDIHeader *hdr = ptr;
    struct syslinux_memmap *mmap = NULL, *amap = NULL;
    struct syslinux_rm_regs regs;
    struct syslinux_movelist *ml = NULL;

    /* **** Basic sanity checking **** */
    if (hdr->Signature != SDI_SIGNATURE) {
	fputs("No $SDI signature in file\n", stdout);
	goto bail;
    }
    if (memcmp(hdr->Version, "0001", 4)) {
	int i;
	fputs("Warning: unknown SDI version: ", stdout);
	for (i = 0; i < 4; i++)
	    putchar(hdr->Version[i]);
	putchar('\n');
	/* Then try anyway... */
    }

    /* **** Setup **** */
    mmap = syslinux_memory_map();
    amap = syslinux_dup_memmap(mmap);
    if (!mmap || !amap)
	goto bail;

    /* **** Map the BOOT BLOB to 0x7c00 **** */
    if (!hdr->BootCodeOffset) {
	fputs("No BOOT BLOB in image\n", stdout);
	goto bail;
    }
    if (!hdr->BootCodeSize) {
	fputs("BOOT BLOB is empty\n", stdout);
	goto bail;
    }
    if (len < hdr->BootCodeOffset + hdr->BootCodeSize) {
	fputs("BOOT BLOB extends beyond file\n", stdout);
	goto bail;
    }

    if (syslinux_memmap_type(amap, 0x7c00, hdr->BootCodeSize) != SMT_FREE) {
	fputs("BOOT BLOB too large for memory\n", stdout);
	goto bail;
    }
    if (syslinux_add_memmap(&amap, 0x7c00, hdr->BootCodeSize, SMT_ALLOC))
	goto bail;
    if (syslinux_add_movelist(&ml, 0x7c00, (addr_t) ptr + hdr->BootCodeOffset,
			      hdr->BootCodeSize))
	goto bail;

    /* **** Map the entire image to SDI_LOAD_ADDR **** */
    if (syslinux_memmap_type(amap, SDI_LOAD_ADDR, len) != SMT_FREE) {
	fputs("Image too large for memory\n", stdout);
	goto bail;
    }
    if (syslinux_add_memmap(&amap, SDI_LOAD_ADDR, len, SMT_ALLOC))
	goto bail;
    if (syslinux_add_movelist(&ml, SDI_LOAD_ADDR, (addr_t) ptr, len))
	goto bail;

    /* **** Set up registers **** */
    memset(&regs, 0, sizeof regs);
    regs.ip = 0x7c00;
    regs.esp.l = 0x7c00;
    regs.edx.l = SDI_LOAD_ADDR | 0x41;

    fputs("Booting...\n", stdout);
    syslinux_shuffle_boot_rm(ml, mmap, 0, &regs);

bail:
    syslinux_free_memmap(amap);
    syslinux_free_memmap(mmap);
    syslinux_free_movelist(ml);
    return -1;
}

/*
 * Check that the sum of all bytes from first 512 bytes (SDI header)
 * is 0 modulo 256.
 */
int has_valid_header(unsigned char *header)
{
    unsigned char checksum;
    unsigned int i;

    checksum = 0;
    for (i = 0; i < sizeof(struct SDIHeader); i++)
	checksum += header[i];
    return (!checksum);
}

int main(int argc, char *argv[])
{
    void *data;
    size_t data_len;

    if (argc != 2) {
	error("Usage: sdi.c32 sdi_file\n");
	return 1;
    }

    fputs("Loading ", stdout);
    fputs(argv[1], stdout);
    fputs("... ", stdout);
    if (zloadfile(argv[1], &data, &data_len)) {
	error("failed!\n");
	return 1;
    }
    fputs("ok\n", stdout);

    if (!has_valid_header(data)) {
	error("SDI header is corrupted\n");
	return 1;
    }

    boot_sdi(data, data_len);
    error("Invalid SDI file or insufficient memory\n");
    return 1;
}
