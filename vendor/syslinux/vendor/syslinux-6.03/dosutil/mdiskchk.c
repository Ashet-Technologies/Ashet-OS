/* -*- c -*- ------------------------------------------------------------- *
 *
 *   Copyright 2003-2008 H. Peter Anvin - All Rights Reserved
 *   Portions copyright 2010 Shao Miller
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * mdiskchk.c
 *
 * DOS program to check for the existence of a memdisk.
 *
 * This program can be compiled for DOS with the OpenWatcom compiler
 * (http://www.openwatcom.org/):
 *
 * wcl -3 -osx -mt mdiskchk.c
 */

#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <i86.h>		/* For MK_FP() */

typedef unsigned long uint32_t;
typedef unsigned short uint16_t;
typedef unsigned char uint8_t;

/* Pull in MEMDISK common structures */
#include "../memdisk/mstructs.h"

struct memdiskinfo {
    struct mdi mdi;

    /* We add our own fields at the end */
    int cylinders;
    int heads;
    int sectors;
};

struct memdiskinfo *query_memdisk(int drive)
{
    static struct memdiskinfo mm;
    uint32_t _eax, _ebx, _ecx, _edx;
    uint16_t _es, _di;
    unsigned char _dl = drive;
    uint16_t bytes;

    __asm {
	.386;
	mov eax, 454d0800h;
	mov ecx, 444d0000h;
	mov edx, 53490000h;
	mov dl, _dl;
	mov ebx, 3f4b0000h;
	int 13h;
	mov _eax, eax;
	mov _ecx, ecx;
	mov _edx, edx;
	mov _ebx, ebx;
	mov _es, es;
	mov _di, di;
    }

    if (_eax >> 16 != 0x4d21 ||
	_ecx >> 16 != 0x4d45 || _edx >> 16 != 0x4944 || _ebx >> 16 != 0x4b53)
	return NULL;

    memset(&mm, 0, sizeof mm);

    bytes = *(uint16_t far *) MK_FP(_es, _di);

    /* 27 is the most we know how to handle */
    if (bytes > 27)
	bytes = 27;

    _fmemcpy((void far *)&mm, (void far *)MK_FP(_es, _di), bytes);

    mm.cylinders = ((_ecx >> 8) & 0xff) + ((_ecx & 0xc0) << 2) + 1;
    mm.heads = ((_edx >> 8) & 0xff) + 1;
    mm.sectors = (_ecx & 0x3f);

    return &mm;
}

const char *bootloadername(uint8_t id)
{
    static const struct {
	uint8_t id, mask;
	const char *name;
    } *lp, list[] = {
	{0x00, 0xf0, "LILO"}, 
	{0x10, 0xf0, "LOADLIN"},
	{0x31, 0xff, "SYSLINUX"},
	{0x32, 0xff, "PXELINUX"},
	{0x33, 0xff, "ISOLINUX"},
	{0x34, 0xff, "EXTLINUX"},
	{0x30, 0xf0, "SYSLINUX family"},
	{0x40, 0xf0, "Etherboot"},
	{0x50, 0xf0, "ELILO"},
	{0x70, 0xf0, "GrUB"},
	{0x80, 0xf0, "U-Boot"},
	{0xA0, 0xf0, "Gujin"},
	{0xB0, 0xf0, "Qemu"},
	{0x00, 0x00, "unknown"}
    };

    for (lp = list;; lp++) {
	if (((id ^ lp->id) & lp->mask) == 0)
	    return lp->name;
    }
}

/* The function type for an output function */
#define OUTPUT_FUNC_DECL(x) \
void x(const int d, const struct memdiskinfo * const m)
typedef OUTPUT_FUNC_DECL((*output_func));

/* Show MEMDISK information for the passed structure */
static OUTPUT_FUNC_DECL(normal_output)
{
    if (m == NULL)
	return;
    printf("Drive %02X is MEMDISK %u.%02u:\n"
	   "\tAddress = 0x%08lx, len = %lu sectors, chs = %u/%u/%u,\n"
	   "\tloader = 0x%02x (%s),\n"
	   "\tcmdline = %Fs\n",
	   d, m->mdi.version_major, m->mdi.version_minor,
	   m->mdi.diskbuf, m->mdi.disksize, m->cylinders, m->heads, m->sectors,
	   m->mdi.bootloaderid, bootloadername(m->mdi.bootloaderid),
	   MK_FP(m->mdi.cmdline.seg_off.segment,
		 m->mdi.cmdline.seg_off.offset));
}

/* Yield DOS SET command(s) as output for each MEMDISK kernel argument */
static OUTPUT_FUNC_DECL(batch_output)
{
    if (m != NULL) {
	char buf[256], *bc;
	const char far *c =
	    MK_FP(m->mdi.cmdline.seg_off.segment,
		  m->mdi.cmdline.seg_off.offset);
	const char *have_equals, is_set[] = "=1";

	while (*c != '\0') {
	    /* Skip whitespace */
	    while (isspace(*c))
		c++;
	    if (*c == '\0')
		/* Trailing whitespace.  That's enough processing */
		break;
	    /* Walk the kernel arguments while filling the buffer,
	     * looking for space or NUL or checking for a full buffer
	     */
	    bc = buf;
	    have_equals = is_set;
	    while ((*c != '\0') && !isspace(*c) &&
		   (bc < &buf[sizeof(buf) - 1])) {
		/* Check if the param is "x=y" */
		if (*c == '=')
		    /* "=1" not needed */
		    have_equals = &is_set[sizeof(is_set) - 1];
		*bc = *c;
		c++;
		bc++;
	    }
	    /* Found the end of the parameter and optional value sequence */
	    *bc = '\0';
	    printf("set %s%s\n", buf, have_equals);
	}
    }
}

/* We do not output batch file output by default.  We show MEMDISK info */
static output_func show_memdisk = normal_output;

/* A generic function type */
#define MDISKCHK_FUNC_DECL(x) \
void x(void)
typedef MDISKCHK_FUNC_DECL((*mdiskchk_func));

static MDISKCHK_FUNC_DECL(do_nothing)
{
    return;
}

static MDISKCHK_FUNC_DECL(show_usage)
{
    printf("\nUsage: mdiskchk [--safe-hooks] [--mbfts] [--batch-output]\n"
	   "\n"
	   "Action: --safe-hooks . . Will scan INT 13h \"safe hook\" chain\n"
	   "        --mbfts . . . .  Will scan memory for MEMDISK mBFTs\n"
	   "        --batch-output . Will output SET command output based\n"
	   "                         on MEMDISK kernel arguments\n"
	   "        --no-sequential  Suppresses probing all drive numbers\n");
}

/* Search memory for mBFTs and report them via the output method */
static MDISKCHK_FUNC_DECL(show_mbfts)
{
    const uint16_t far * const free_base_mem =
	MK_FP(0x0040, 0x0013);
    int seg;
    uint8_t chksum;
    uint32_t i;
    const struct mBFT far *mbft;
    struct memdiskinfo m;
    struct patch_area far *patch_area;

    for (seg = *free_base_mem / 16; seg < 0x9FFF; seg++) {
	mbft = MK_FP(seg, 0);
	/* Check for signature */
	if (mbft->acpi.signature[0] != 'm' ||
	    mbft->acpi.signature[1] != 'B' ||
	    mbft->acpi.signature[2] != 'F' ||
	    mbft->acpi.signature[3] != 'T')
	    continue;
	if (mbft->acpi.length != sizeof(struct mBFT))
	    continue;
	/* Check sum */
	chksum = 0;
	for (i = 0; i < sizeof(struct mBFT); i++)
	    chksum += ((const uint8_t far *)mbft)[i];
	if (chksum)
	    continue;
	/* Copy the MDI from the mBFT */
	_fmemcpy((void far *)&m, &mbft->mdi, sizeof(struct mdi));
	/* Adjust C/H/S since we actually know
	 * it directly for any MEMDISK with an mBFT
	 */
	patch_area = (struct patch_area far *)&mbft->mdi;
	m.cylinders = patch_area->cylinders;
	m.heads = patch_area->heads;
	m.sectors = patch_area->sectors;
	show_memdisk(patch_area->driveno, &m);
    }
}

/* Walk the "safe hook" chain as far as possible
 * and report MEMDISKs that we find via the output method
 */
static MDISKCHK_FUNC_DECL(show_safe_hooks)
{
    const real_addr_t far * const int13 =
	MK_FP(0x0000, 0x0013 * sizeof(real_addr_t));
    const struct safe_hook far *hook =
	MK_FP(int13->seg_off.segment, int13->seg_off.offset);

    while ((hook->signature[0] == '$') &&
	   (hook->signature[1] == 'I') &&
	   (hook->signature[2] == 'N') &&
	   (hook->signature[3] == 'T') &&
	   (hook->signature[4] == '1') &&
	   (hook->signature[5] == '3') &&
	   (hook->signature[6] == 'S') &&
	   (hook->signature[7] == 'F')) {
	/* Found a valid "safe hook" */
	if ((hook->vendor[0] == 'M') &&
	    (hook->vendor[1] == 'E') &&
	    (hook->vendor[2] == 'M') &&
	    (hook->vendor[3] == 'D') &&
	    (hook->vendor[4] == 'I') &&
	    (hook->vendor[5] == 'S') &&
	    (hook->vendor[6] == 'K')) {
	    /* Found a valid MEMDISK "safe hook".  It will have an mBFT */
	    const struct mBFT far *mbft;
	    struct memdiskinfo m;
	    struct patch_area far *patch_area;

	    /* Copy the MDI from the mBFT.  Offset is a misnomer here */
	    mbft = MK_FP(hook->mbft >> 4, 0);	/* Always aligned */
	    _fmemcpy((void far *)&m, &mbft->mdi, sizeof(struct mdi));
	    /* Adjust C/H/S since we actually know
	     * it directly for any MEMDISK with an mBFT
	     */
	    patch_area = (struct patch_area far *)&mbft->mdi;
	    m.cylinders = patch_area->cylinders;
	    m.heads = patch_area->heads;
	    m.sectors = patch_area->sectors;
	    show_memdisk(patch_area->driveno, &m);
	} /* if */
	/* Step to the next hook in the "safe hook" chain */
	hook = MK_FP(hook->old_hook.seg_off.segment,
		     hook->old_hook.seg_off.offset);
    } /* while */
}

int main(int argc, char *argv[])
{
    int d;
    int found = 0;
    int sequential_scan = 1;	/* Classic behaviour */
    const struct memdiskinfo *m;

    /* Default behaviour */
    mdiskchk_func usage = do_nothing,
	safe_hooks = do_nothing,
	mbfts = do_nothing;

    /* For each argument */
    while (--argc) {
	/* Argument should begin with one of these chars */
	if ((*argv[argc] != '/') && (*argv[argc] != '-')) {
	    /* It doesn't.  Print usage soon */
	    usage = show_usage;
	    break;
	}
	argv[argc]++;

	/* Next char might be '-' as in "--safe-hooks" */
	if (*argv[argc] == '-')
	    argv[argc]++;

	switch (*argv[argc]) {
	    case 'S':
	    case 's':
		safe_hooks = show_safe_hooks;
		break;
	    case 'M':
	    case 'm':
		mbfts = show_mbfts;
		break;
	    case 'B':
	    case 'b':
		show_memdisk = batch_output;
		break;
	    case 'N':
	    case 'n':
		sequential_scan = 0;
		break;
	    default:
		usage = show_usage;
	} /* switch */
   } /* while */

    safe_hooks();
    mbfts();
    if (!sequential_scan)
	goto skip_sequential;
    for (d = 0; d <= 0xff; d++) {
	m = query_memdisk(d);
	if (m != NULL) {
	    found++;
	    show_memdisk(d, m);
	}
    }
skip_sequential:
    usage();

    return found;
}

