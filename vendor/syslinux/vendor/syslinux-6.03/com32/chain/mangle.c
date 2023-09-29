/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2003-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *   Copyright 2010 Shao Miller
 *   Copyright 2010-2012 Michal Soltys
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

#include <com32.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <dprintf.h>
#include <syslinux/config.h>
#include "chain.h"
#include "options.h"
#include "utility.h"
#include "partiter.h"
#include "mangle.h"

static const char cmldr_signature[8] = "cmdcons";

/* Create boot info table: needed when you want to chainload
 * another version of ISOLINUX (or another bootlaoder that needs
 * the -boot-info-table switch of mkisofs)
 * (will only work when run from ISOLINUX)
 */
int manglef_isolinux(struct data_area *data)
{
    const union syslinux_derivative_info *sdi;
    unsigned char *isolinux_bin;
    uint32_t *checksum, *chkhead, *chktail;
    uint32_t file_lba = 0;

    if (!(opt.file && opt.isolinux))
	return 0;

    sdi = syslinux_derivative_info();

    if (sdi->c.filesystem != SYSLINUX_FS_ISOLINUX) {
	error("The isolinux= option is only valid when run from ISOLINUX.");
	goto bail;
    }

    /* Boot info table info (integers in little endian format)

       Offset Name         Size      Meaning
       8      bi_pvd       4 bytes   LBA of primary volume descriptor
       12     bi_file      4 bytes   LBA of boot file
       16     bi_length    4 bytes   Boot file length in bytes
       20     bi_csum      4 bytes   32-bit checksum
       24     bi_reserved  40 bytes  Reserved

       The 32-bit checksum is the sum of all the 32-bit words in the
       boot file starting at byte offset 64. All linear block
       addresses (LBAs) are given in CD sectors (normally 2048 bytes).

       LBA of primary volume descriptor should already be set to 16.
       */

    isolinux_bin = (unsigned char *)data->data;

    /* Get LBA address of bootfile */
    file_lba = get_file_lba(opt.file);

    if (file_lba == 0) {
	error("Failed to find LBA offset of the boot file.");
	goto bail;
    }
    /* Set it */
    *((uint32_t *) & isolinux_bin[12]) = file_lba;

    /* Set boot file length */
    *((uint32_t *) & isolinux_bin[16]) = data->size;

    /* Calculate checksum */
    checksum = (uint32_t *) & isolinux_bin[20];
    chkhead = (uint32_t *) & isolinux_bin[64];
    chktail = (uint32_t *) & isolinux_bin[data->size & ~3u];
    *checksum = 0;
    while (chkhead < chktail)
	*checksum += *chkhead++;

    /*
     * Deal with possible fractional dword at the end;
     * this *should* never happen...
     */
    if (data->size & 3) {
	uint32_t xword = 0;
	memcpy(&xword, chkhead, data->size & 3);
	*checksum += xword;
    }
    return 0;
bail:
    return -1;
}

/*
 * Legacy grub's stage2 chainloading
 */
int manglef_grub(const struct part_iter *iter, struct data_area *data)
{
    /* Layout of stage2 file (from byte 0x0 to 0x270) */
    struct grub_stage2_patch_area {
	/* 0x0 to 0x205 */
	char unknown[0x206];
	/* 0x206: compatibility version number major */
	uint8_t compat_version_major;
	/* 0x207: compatibility version number minor */
	uint8_t compat_version_minor;

	/* 0x208: install_partition variable */
	struct {
	    /* 0x208: sub-partition in sub-partition part2 */
	    uint8_t part3;
	    /* 0x209: sub-partition in top-level partition */
	    uint8_t part2;
	    /* 0x20a: top-level partiton number */
	    uint8_t part1;
	    /* 0x20b: BIOS drive number (must be 0) */
	    uint8_t drive;
	} __attribute__ ((packed)) install_partition;

	/* 0x20c: deprecated (historical reason only) */
	uint32_t saved_entryno;
	/* 0x210: stage2_ID: will always be STAGE2_ID_STAGE2 = 0 in stage2 */
	uint8_t stage2_id;
	/* 0x211: force LBA */
	uint8_t force_lba;
	/* 0x212: version string (will probably be 0.97) */
	char version_string[5];
	/* 0x217: config filename */
	char config_file[89];
	/* 0x270: start of code (after jump from 0x200) */
	char codestart[1];
    } __attribute__ ((packed)) *stage2;

    if (!(opt.file && opt.grub))
	return 0;

    if (data->size < sizeof *stage2) {
	error("The file specified by grub=<loader> is too small to be stage2 of GRUB Legacy.");
	goto bail;
    }
    stage2 = data->data;

    /*
     * Check the compatibility version number to see if we loaded a real
     * stage2 file or a stage2 file that we support.
     */
    if (stage2->compat_version_major != 3
	    || stage2->compat_version_minor != 2) {
	error("The file specified by grub=<loader> is not a supported stage2 GRUB Legacy binary.");
	goto bail;
    }

    /*
     * GRUB Legacy wants the partition number in the install_partition
     * variable, located at offset 0x208 of stage2.
     * When GRUB Legacy is loaded, it is located at memory address 0x8208.
     *
     * It looks very similar to the "boot information format" of the
     * Multiboot specification:
     *   http://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Boot-information-format
     *
     *   0x208 = part3: sub-partition in sub-partition part2
     *   0x209 = part2: sub-partition in top-level partition
     *   0x20a = part1: top-level partition number
     *   0x20b = drive: BIOS drive number (must be 0)
     *
     * GRUB Legacy doesn't store the BIOS drive number at 0x20b, but at
     * another location.
     *
     * Partition numbers always start from zero.
     * Unused partition bytes must be set to 0xFF.
     *
     * We only care about top-level partition, so we only need to change
     * "part1" to the appropriate value:
     *   -1:   whole drive (default) (-1 = 0xFF)
     *   0-3:  primary partitions
     *   4-*:  logical partitions
     */
    stage2->install_partition.part1 = iter->index - 1;

    /*
     * Grub Legacy reserves 89 bytes (from 0x8217 to 0x826f) for the
     * config filename. The filename passed via grubcfg= will overwrite
     * the default config filename "/boot/grub/menu.lst".
     */
    if (opt.grubcfg) {
	if (strlen(opt.grubcfg) >= sizeof stage2->config_file) {
	    error("The config filename length can't exceed 88 characters.");
	    goto bail;
	}

	strcpy((char *)stage2->config_file, opt.grubcfg);
    }

    return 0;
bail:
    return -1;
}
#if 0
/*
 * Dell's DRMK chainloading.
 */
int manglef_drmk(struct data_area *data)
{
    /*
     * DRMK entry is different than MS-DOS/PC-DOS
     * A new size, aligned to 16 bytes to ease use of ds:[bp+28].
     * We only really need 4 new, usable bytes at the end.
     */

    if (!(opt.file && opt.drmk))
	return 0;

    uint32_t tsize = (data->size + 19) & 0xfffffff0;
    const union syslinux_derivative_info *sdi;
    uint64_t fs_lba;

    sdi = syslinux_derivative_info();
    /* We should lookup the Syslinux partition offset and use it */
    fs_lba = *sdi->disk.partoffset;

    /*
     * fs_lba should be verified against the disk as some DRMK
     * variants will check and fail if it does not match
     */
    dprintf("  fs_lba offset is %d\n", fs_lba);
    /* DRMK only uses a DWORD */
    if (fs_lba > 0xffffffff) {
	error("LBA very large; Only using lower 32 bits; DRMK will probably fail.");
    }
    opt.regs.ss = opt.regs.fs = opt.regs.gs = 0;	/* Used before initialized */
    if (!realloc(data->data, tsize)) {
	error("Failed to realloc for DRMK.");
	goto bail;
    }
    data->size = tsize;
    /* ds:bp is assumed by DRMK to be the boot sector */
    /* offset 28 is the FAT HiddenSectors value */
    opt.regs.ds = (tsize >> 4) + (opt.fseg - 2);
    /* "Patch" into tail of the new space */
    *(uint32_t *)((char*)data->data + tsize - 4) = fs_lba;

    return 0;
bail:
    return -1;
}
#endif
/* Adjust BPB common function */
static int mangle_bpb(const struct part_iter *iter, struct data_area *data, const char *tag)
{
    int type = bpb_detect(data->data, tag);
    int off = drvoff_detect(type);

    /* BPB: hidden sectors 64bit - exFAT only for now */
    if (type == bpbEXF)
	    *(uint64_t *) ((char *)data->data + 0x40) = iter->abs_lba;
    /* BPB: hidden sectors 32bit*/
    else if (bpbV34 <= type && type <= bpbV70) {
	if (iter->abs_lba < ~0u)
	    *(uint32_t *) ((char *)data->data + 0x1c) = iter->abs_lba;
	else
	    /* won't really help much, but ... */
	    *(uint32_t *) ((char *)data->data + 0x1c) = ~0u;
    /* BPB: hidden sectors 16bit*/
    } else if (bpbV30 <= type && type <= bpbV32) {
	if (iter->abs_lba < 0xFFFF)
	    *(uint16_t *) ((char *)data->data + 0x1c) = iter->abs_lba;
	else
	    /* won't really help much, but ... */
	    *(uint16_t *) ((char *)data->data + 0x1c) = (uint16_t)~0u;
    }

    /* BPB: legacy geometry */
    if (bpbV30 <= type && type <= bpbV70) {
	if (iter->di.cbios)
	    *(uint32_t *)((char *)data->data + 0x18) = (iter->di.head << 16) | iter->di.spt;
	else {
	    if (iter->di.disk & 0x80)
		*(uint32_t *)((char *)data->data + 0x18) = 0x00FF003F;
	    else
		*(uint32_t *)((char *)data->data + 0x18) = 0x00020012;
	}
    }
    /* BPB: drive */
    if (off >= 0) {
	*(uint8_t *)((char *)data->data + off) = (opt.swap ? iter->di.disk & 0x80 : iter->di.disk);
    }

    return 0;
}

/*
 * Adjust BPB of a BPB-compatible file
 */
int manglef_bpb(const struct part_iter *iter, struct data_area *data)
{
    if (!(opt.file && opt.filebpb))
	return 0;

    return mangle_bpb(iter, data, "file");
}

/*
 * Adjust BPB of a sector
 */
int mangles_bpb(const struct part_iter *iter, struct data_area *data)
{
    if (!(opt.sect && opt.setbpb))
	return 0;

    return mangle_bpb(iter, data, "sect");
}

/*
 * This function performs full BPB patching, analogously to syslinux's
 * native BSS.
 */
int manglesf_bss(struct data_area *sec, struct data_area *fil)
{
    int type1, type2;
    size_t cnt = 0;

    if (!(opt.sect && opt.file && opt.bss))
	return 0;

    type1 = bpb_detect(fil->data, "bss/file");
    type2 = bpb_detect(sec->data, "bss/sect");

    if (!type1 || !type2) {
	error("Couldn't determine the BPB type for option 'bss'.");
	goto bail;
    }
    if (type1 != type2) {
	error("Option 'bss' can't be used,\n"
		"when a sector and a file have incompatible BPBs.");
	goto bail;
    }

    /* Copy common 2.0 data */
    memcpy((char *)fil->data + 0x0B, (char *)sec->data + 0x0B, 0x0D);

    /* Copy 3.0+ data */
    if (type1 <= bpbV30) {
	cnt = 0x06;
    } else if (type1 <= bpbV32) {
	cnt = 0x08;
    } else if (type1 <= bpbV34) {
	cnt = 0x0C;
    } else if (type1 <= bpbV40) {
	cnt = 0x2E;
    } else if (type1 <= bpbVNT) {
	cnt = 0x3C;
    } else if (type1 <= bpbV70) {
	cnt = 0x42;
    } else if (type1 <= bpbEXF) {
	cnt = 0x60;
    }
    memcpy((char *)fil->data + 0x18, (char *)sec->data + 0x18, cnt);

    return 0;
bail:
    return -1;
}

/*
 * Save sector.
 */
int mangles_save(const struct part_iter *iter, const struct data_area *data, void *org)
{
    if (!(opt.sect && opt.save))
	return 0;

    if (memcmp(org, data->data, data->size)) {
	if (disk_write_sectors(&iter->di, iter->abs_lba, data->data, 1)) {
	    error("Cannot write the updated sector.");
	    goto bail;
	}
	/* function can be called again */
	memcpy(org, data->data, data->size);
    }

    return 0;
bail:
    return -1;
}

/*
 * To boot the Recovery Console of Windows NT/2K/XP we need to write
 * the string "cmdcons\0" to memory location 0000:7C03.
 * Memory location 0000:7C00 contains the bootsector of the partition.
 */
int mangles_cmldr(struct data_area *data)
{
    if (!(opt.sect && opt.cmldr))
	return 0;

    memcpy((char *)data->data + 3, cmldr_signature, sizeof cmldr_signature);
    return 0;
}

/* Set common registers */
int mangler_init(const struct part_iter *iter)
{
    /* Set initial registry values */
    if (opt.file) {
	opt.regs.cs = opt.regs.ds = opt.regs.ss = opt.fseg;
	opt.regs.ip = opt.fip;
    } else {
	opt.regs.cs = opt.regs.ds = opt.regs.ss = opt.sseg;
	opt.regs.ip = opt.sip;
    }

    if (opt.regs.ip == 0x7C00 && !opt.regs.cs)
	opt.regs.esp.l = 0x7C00;

    /* DOS kernels want the drive number in BL instead of DL. Indulge them. */
    opt.regs.ebx.b[0] = opt.regs.edx.b[0] = iter->di.disk;

    return 0;
}

/* ds:si & ds:bp */
int mangler_handover(const struct part_iter *iter, const struct data_area *data)
{
    if (opt.file && opt.maps && !opt.hptr) {
	opt.regs.esi.l = opt.regs.ebp.l = opt.soff;
	opt.regs.ds = opt.sseg;
	opt.regs.eax.l = 0;
    } else if (opt.hand) {
	/* base is really 0x7be */
	opt.regs.esi.l = opt.regs.ebp.l = data->base;
	opt.regs.ds = 0;
	if (iter->index && iter->type == typegpt)   /* must be iterated and GPT */
	    opt.regs.eax.l = 0x54504721;	/* '!GPT' */
	else
	    opt.regs.eax.l = 0;
    }

    return 0;
}

/*
 * GRLDR of GRUB4DOS wants the partition number in DH:
 * -1:   whole drive (default)
 * 0-3:  primary partitions
 * 4-*:  logical partitions
 */
int mangler_grldr(const struct part_iter *iter)
{
    if (opt.grldr)
	opt.regs.edx.b[1] = iter->index - 1;

    return 0;
}

/*
 * try to copy values from temporary iterator, if positions match
 */
static void mbrcpy(struct part_iter *diter, struct part_iter *siter)
{
    if (diter->dos.cebr_lba == siter->dos.cebr_lba &&
	    diter->di.disk == siter->di.disk) {
	memcpy(diter->data, siter->data, sizeof(struct disk_dos_mbr));
    }
}

static int fliphide(struct part_iter *iter, struct part_iter *miter)
{
    struct disk_dos_part_entry *dp;
    static const uint16_t mask =
	(1 << 0x01) | (1 << 0x04) | (1 << 0x06) |
	(1 << 0x07) | (1 << 0x0b) | (1 << 0x0c) | (1 << 0x0e);
    uint8_t t;

    dp = (struct disk_dos_part_entry *)iter->record;
    t = dp->ostype;

    if ((t <= 0x1f) && ((mask >> (t & ~0x10u)) & 1)) {
	/* It's a hideable partition type */
	if (miter->index == iter->index || opt.hide & HIDE_REV)
	    t &= ~0x10u;	/* unhide */
	else
	    t |= 0x10u;	/* hide */
    }
    if (dp->ostype != t) {
	dp->ostype = t;
	return -1;
    }
    return 0;
}

/*
 * miter - iterator we match against
 * hide bits meaning:
 * ..| - enable (1) / disable (0)
 * .|. - all (1) / pri (0)
 * |.. - unhide (1) / hide (0)
 */
int manglepe_hide(struct part_iter *miter)
{
    int wb = 0, werr = 0;
    struct part_iter *iter = NULL;
    int ridx;

    if (!(opt.hide & HIDE_ON))
	return 0;

    if (miter->type != typedos) {
	error("Option '[un]hide[all]' works only for legacy (DOS) partition scheme.");
	return -1;
    }

    if (miter->index > 4 && !(opt.hide & HIDE_EXT))
	warn("Specified partition is logical, so it can't be unhidden without 'unhideall'.");

    if (!(iter = pi_begin(&miter->di, PIF_STEPALL | opt.piflags)))
	return -1;

    while (!pi_next(iter) && !werr) {
	ridx = iter->index0;
	if (!(opt.hide & HIDE_EXT) && ridx > 3)
	    break;  /* skip when we're constrained to pri only */

	if (iter->index != -1)
	    wb |= fliphide(iter, miter);

	/*
	 * we have to update mbr and each extended partition, but only if
	 * changes (wb) were detected and there was no prior write error (werr)
	 */
	if (ridx >= 3 && wb && !werr) {
	    mbrcpy(miter, iter);
	    werr |= disk_write_sectors(&iter->di, iter->dos.cebr_lba, iter->data, 1);
	    wb = 0;
	}
    }

    if (iter->status < 0)
	goto bail;

    /* last update */
    if (wb && !werr) {
	mbrcpy(miter, iter);
	werr |= disk_write_sectors(&iter->di, iter->dos.cebr_lba, iter->data, 1);
    }
    if (werr)
	warn("Failed to write E/MBR during '[un]hide[all]'.");

bail:
    pi_del(&iter);
    return 0;
}

static int updchs(struct part_iter *iter, int ext)
{
    struct disk_dos_part_entry *dp;
    uint32_t ochs1, ochs2, lba;

    dp = (struct disk_dos_part_entry *)iter->record;
    if (!ext) {
	/* primary or logical */
	lba = (uint32_t)iter->abs_lba;
    } else {
	/* extended */
	dp += 1;
	lba = iter->dos.nebr_lba;
    }
    ochs1 = *(uint32_t *)dp->start;
    ochs2 = *(uint32_t *)dp->end;

    /*
     * We have to be a bit more careful here in case of 0 start and/or length;
     * start = 0 would be converted to the beginning of the disk (C/H/S =
     * 0/0/1) or the [B]EBR, length = 0 would actually set the end CHS to be
     * lower than the start CHS.
     *
     * Both are harmless in case of a hole (and in non-hole case will make
     * partiter complain about corrupt layout if PIF_STRICT is set), but it
     * makes everything look silly and not really correct.
     *
     * Thus the approach as seen below.
     */

    if (dp->start_lba || iter->index != -1) {
	lba2chs(&dp->start, &iter->di, lba, L2C_CADD);
    } else {
	memset(&dp->start, 0, sizeof dp->start);
    }

    if ((dp->start_lba || iter->index != -1) && dp->length) {
	lba2chs(&dp->end, &iter->di, lba + dp->length - 1, L2C_CADD);
    } else {
	memset(&dp->end, 0, sizeof dp->end);
    }

    return
	*(uint32_t *)dp->start != ochs1 ||
	*(uint32_t *)dp->end != ochs2;
}

/*
 * miter - iterator we match against
 */
int manglepe_fixchs(struct part_iter *miter)
{
    int wb = 0, werr = 0;
    struct part_iter *iter = NULL;
    int ridx;

    if (!opt.fixchs)
	return 0;

    if (miter->type != typedos) {
	error("Option 'fixchs' works only for legacy (DOS) partition scheme.");
	return -1;
    }

    if (!(iter = pi_begin(&miter->di, PIF_STEPALL | opt.piflags)))
	return -1;

    while (!pi_next(iter) && !werr) {
	ridx = iter->index0;

	wb |= updchs(iter, 0);
	if (ridx > 3)
	    wb |= updchs(iter, 1);

	/*
	 * we have to update mbr and each extended partition, but only if
	 * changes (wb) were detected and there was no prior write error (werr)
	 */
	if (ridx >= 3 && wb && !werr) {
	    mbrcpy(miter, iter);
	    werr |= disk_write_sectors(&iter->di, iter->dos.cebr_lba, iter->data, 1);
	    wb = 0;
	}
    }

    if (iter->status < 0)
	goto bail;

    /* last update */
    if (wb && !werr) {
	mbrcpy(miter, iter);
	werr |= disk_write_sectors(&iter->di, iter->dos.cebr_lba, iter->data, 1);
    }
    if (werr)
	warn("Failed to write E/MBR during 'fixchs'.");

bail:
    pi_del(&iter);
    return 0;
}

/* vim: set ts=8 sts=4 sw=4 noet: */
