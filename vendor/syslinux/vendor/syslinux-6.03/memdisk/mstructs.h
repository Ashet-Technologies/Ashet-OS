/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2001-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *   Portions copyright 2009-2010 Shao Miller
 *				  [El Torito code, mBFT, "safe hook"]
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/* These structures are common to MEMDISK and MDISKCHK.COM */

#include <stdint.h>
#include "compiler.h"

struct seg_off {
    uint16_t offset;
    uint16_t segment;
};

typedef union {
    struct seg_off seg_off;
    uint32_t uint32;
} real_addr_t;

/* Forward declaration */
struct mBFT;

MEMDISK_PACKED_PREFIX
struct safe_hook {
    uint8_t jump[3];		/* Max. three bytes for jump */
    uint8_t signature[8];	/* "$INT13SF" */
    uint8_t vendor[8];		/* "MEMDISK " */
    real_addr_t old_hook;	/* SEG:OFF for previous INT 13h hook */
    uint32_t flags;		/* "Safe hook" flags */
    /* The next field is a MEMDISK extension to the "safe hook" structure */
    uint32_t mbft;
} MEMDISK_PACKED_POSTFIX;

struct memdisk_header {
    uint16_t int13_offs;
    uint16_t int15_offs;
    uint16_t patch_offs;
    uint16_t total_size;
    uint16_t iret_offs;
    struct safe_hook safe_hook;
};

MEMDISK_PACKED_PREFIX
/* EDD disk parameter table */
struct edd_dpt {
    uint16_t len;		/* Length of table */
    uint16_t flags;		/* Information flags */
    uint32_t c;			/* Physical cylinders (count!) */
    uint32_t h;			/* Physical heads (count!) */
    uint32_t s;			/* Physical sectors/track (count!) */
    uint64_t sectors;		/* Total sectors */
    uint16_t bytespersec;	/* Bytes/sector */
    real_addr_t dpte;		/* DPTE pointer */
    uint16_t dpikey;		/* Device Path Info magic */
    uint8_t  dpilen;		/* Device Path Info length */
    uint8_t  res1;		/* Reserved */
    uint16_t res2;		/* Reserved */
    uint8_t  bustype[4];	/* Host bus type */
    uint8_t  inttype[8];	/* Interface type */
    uint64_t intpath;		/* Interface path */
    uint64_t devpath[2];	/* Device path (double QuadWord!) */
    uint8_t  res3;		/* Reserved */
    uint8_t  chksum;		/* DPI checksum */
} MEMDISK_PACKED_POSTFIX;

/* Requirement for struct edd4_cd_pkt */
#include "../memdisk/eltorito.h"

/* Official MEMDISK Info structure ("MDI") */
MEMDISK_PACKED_PREFIX
struct mdi {
    const uint16_t bytes;
    const uint8_t version_minor;
    const uint8_t version_major;

    uint32_t diskbuf;
    uint32_t disksize;
    real_addr_t cmdline;

    real_addr_t oldint13;
    real_addr_t oldint15;

    uint16_t olddosmem;
    uint8_t bootloaderid;
    uint8_t sector_shift;

    uint16_t dpt_ptr;
} MEMDISK_PACKED_POSTFIX;

/* Requirement for struct acpi_description_header */
#include "../memdisk/acpi.h"

MEMDISK_PACKED_PREFIX
struct mBFT {
    struct acpi_description_header acpi;
    uint32_t safe_hook;		/* "Safe hook" physical address */
    struct mdi mdi;
} MEMDISK_PACKED_POSTFIX;

/* The Disk Parameter Table may be required */
typedef union {
    struct hd_dpt {
	uint16_t max_cyl;	/* Max cylinder */
	uint8_t max_head;	/* Max head */
	uint8_t junk1[5];	/* Obsolete junk, leave at zero */
	uint8_t ctrl;		/* Control byte */
	uint8_t junk2[7];	/* More obsolete junk */
    } hd;
    struct fd_dpt {
	uint8_t specify1;	/* "First specify byte" */
	uint8_t specify2;	/* "Second specify byte" */
	uint8_t delay;		/* Delay until motor turn off */
	uint8_t bps;		/* Bytes/sector (02h = 512) */

	uint8_t sectors;	/* Sectors/track */
	uint8_t isgap;		/* Length of intersector gap */
	uint8_t dlen;		/* Data length (0FFh) */
	uint8_t fgap;		/* Formatting gap */

	uint8_t ffill;		/* Format fill byte */
	uint8_t settle;		/* Head settle time (ms) */
	uint8_t mstart;		/* Motor start time */
	uint8_t maxtrack;	/* Maximum track number */

	uint8_t rate;		/* Data transfer rate */
	uint8_t cmos;		/* CMOS type */
	uint8_t pad[2];

	uint32_t old_fd_dpt;	/* Extension: pointer to old INT 1Eh */
    } fd;
} dpt_t;

MEMDISK_PACKED_PREFIX
struct patch_area {
    struct mdi mdi;

    uint8_t driveshiftlimit;	/* Do not shift drives above this region */
    uint8_t _pad2;		/* Pad to DWORD */
    uint16_t _pad3;		/* Pad to QWORD */

    uint16_t memint1588;

    uint16_t cylinders;
    uint16_t heads;
    uint32_t sectors;

    uint32_t mem1mb;
    uint32_t mem16mb;

    uint8_t driveno;
    uint8_t drivetype;
    uint8_t drivecnt;
    uint8_t configflags;

#define CONFIG_READONLY	0x01
#define CONFIG_RAW	0x02
#define CONFIG_SAFEINT	0x04
#define CONFIG_BIGRAW	0x08	/* MUST be 8! */
#define CONFIG_MODEMASK	0x0e

    uint16_t mystack;
    uint16_t statusptr;

    dpt_t dpt;
    struct edd_dpt edd_dpt;
    struct edd4_cd_pkt cd_pkt;	/* Only really in a memdisk_iso_* hook */
} MEMDISK_PACKED_POSTFIX;
