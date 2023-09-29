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

#include <stdint.h>
#include <minmax.h>
#include <suffix_number.h>
#include "bda.h"
#include "dskprobe.h"
#include "e820.h"
#include "conio.h"
#include "version.h"
#include "memdisk.h"
#include <version.h>

const char memdisk_version[] = "MEMDISK " VERSION_STR " " DATE;
const char copyright[] =
    "Copyright " FIRSTYEAR "-" YEAR_STR " H. Peter Anvin et al";

extern const char _binary_memdisk_chs_512_bin_start[];
extern const char _binary_memdisk_chs_512_bin_end[];
extern const char _binary_memdisk_chs_512_bin_size[];
extern const char _binary_memdisk_edd_512_bin_start[];
extern const char _binary_memdisk_edd_512_bin_end[];
extern const char _binary_memdisk_edd_512_bin_size[];
extern const char _binary_memdisk_iso_512_bin_start[];
extern const char _binary_memdisk_iso_512_bin_end[];
extern const char _binary_memdisk_iso_512_bin_size[];
extern const char _binary_memdisk_iso_2048_bin_start[];
extern const char _binary_memdisk_iso_2048_bin_end[];
extern const char _binary_memdisk_iso_2048_bin_size[];

/* Pull in structures common to MEMDISK and MDISKCHK.COM */
#include "mstructs.h"

/* An EDD disk packet */
struct edd_dsk_pkt {
    uint8_t size;		/* Packet size        */
    uint8_t res1;		/* Reserved           */
    uint16_t count;		/* Count to transfer  */
    uint32_t buf;		/* Buffer pointer     */
    uint64_t start;		/* LBA to start from  */
    uint64_t buf64;		/* 64-bit buf pointer */
} __attribute__ ((packed));

/* Change to 1 for El Torito debugging */
#define DBG_ELTORITO 0

#if DBG_ELTORITO
extern void eltorito_dump(uint32_t);
#endif

/*
 * Routine to seek for a command-line item and return a pointer
 * to the data portion, if present
 */

/* Magic return values */
#define CMD_NOTFOUND   ((char *)-1)	/* Not found */
#define CMD_BOOL       ((char *)-2)	/* Found boolean option */
#define CMD_HASDATA(X) ((int)(X) >= 0)

static const char *getcmditem(const char *what)
{
    const char *p;
    const char *wp = what;
    int match = 0;

    for (p = shdr->cmdline; *p; p++) {
	switch (match) {
	case 0:		/* Ground state */
	    if (*p == ' ')
		break;

	    wp = what;
	    match = 1;
	    /* Fall through */

	case 1:		/* Matching */
	    if (*wp == '\0') {
		if (*p == '=')
		    return p + 1;
		else if (*p == ' ')
		    return CMD_BOOL;
		else {
		    match = 2;
		    break;
		}
	    }
	    if (*p != *wp++)
		match = 2;
	    break;

	case 2:		/* Mismatch, skip rest of option */
	    if (*p == ' ')
		match = 0;	/* Next option */
	    break;
	}
    }

    /* Check for matching string at end of line */
    if (match == 1 && *wp == '\0')
	return CMD_BOOL;

    return CMD_NOTFOUND;
}

/*
 * Check to see if this is a gzip image
 */
#define UNZIP_ALIGN 512

extern const char _end[];		/* Symbol signalling end of data */

void unzip_if_needed(uint32_t * where_p, uint32_t * size_p)
{
    uint32_t where = *where_p;
    uint32_t size = *size_p;
    uint32_t zbytes;
    uint32_t startrange, endrange;
    uint32_t gzdatasize, gzwhere;
    uint32_t orig_crc, offset;
    uint32_t target = 0;
    int i, okmem;

    /* Is it a gzip image? */
    if (check_zip((void *)where, size, &zbytes, &gzdatasize,
		  &orig_crc, &offset) == 0) {

	if (offset + zbytes > size) {
	    /*
	     * Assertion failure; check_zip is supposed to guarantee this
	     * never happens.
	     */
	    die("internal error: check_zip returned nonsense\n");
	}

	/*
	 * Find a good place to put it: search memory ranges in descending
	 * order until we find one that is legal and fits
	 */
	okmem = 0;
	for (i = nranges - 1; i >= 0; i--) {
	    /*
	     * We can't use > 4G memory (32 bits only.)  Truncate to 2^32-1
	     * so we don't have to deal with funny wraparound issues.
	     */

	    /* Must be memory */
	    if (ranges[i].type != 1)
		continue;

	    /* Range start */
	    if (ranges[i].start >= 0xFFFFFFFF)
		continue;

	    startrange = (uint32_t) ranges[i].start;

	    /* Range end (0 for end means 2^64) */
	    endrange = ((ranges[i + 1].start >= 0xFFFFFFFF ||
			 ranges[i + 1].start == 0)
			? 0xFFFFFFFF : (uint32_t) ranges[i + 1].start);

	    /* Make sure we don't overwrite ourselves */
	    if (startrange < (uint32_t) _end)
		startrange = (uint32_t) _end;

	    /* Allow for alignment */
	    startrange =
		(ranges[i].start + (UNZIP_ALIGN - 1)) & ~(UNZIP_ALIGN - 1);

	    /* In case we just killed the whole range... */
	    if (startrange >= endrange)
		continue;

	    /*
	     * Must be large enough... don't rely on gzwhere for this
	     * (wraparound)
	     */
	    if (endrange - startrange < gzdatasize)
		continue;

	    /*
	     * This is where the gz image would be put if we put it in this
	     * range...
	     */
	    gzwhere = (endrange - gzdatasize) & ~(UNZIP_ALIGN - 1);

	    /* Cast to uint64_t just in case we're flush with the top byte */
	    if ((uint64_t) where + size >= gzwhere && where < endrange) {
		/*
		 * Need to move source data to avoid compressed/uncompressed
		 * overlap
		 */
		uint32_t newwhere;

		if (gzwhere - startrange < size)
		    continue;	/* Can't fit both old and new */

		newwhere = (gzwhere - size) & ~(UNZIP_ALIGN - 1);
		printf("Moving compressed data from 0x%08x to 0x%08x\n",
		       where, newwhere);

		memmove((void *)newwhere, (void *)where, size);
		where = newwhere;
	    }

	    target = gzwhere;
	    okmem = 1;
	    break;
	}

	if (!okmem)
	    die("Not enough memory to decompress image (need 0x%08x bytes)\n",
		gzdatasize);

	printf("gzip image: decompressed addr 0x%08x, len 0x%08x: ",
	       target, gzdatasize);

	*size_p = gzdatasize;
	*where_p = (uint32_t) unzip((void *)(where + offset), zbytes,
				    gzdatasize, orig_crc, (void *)target);
    }
}

/*
 * Figure out the "geometry" of the disk in question
 */
struct geometry {
    uint32_t sectors;		/* Sector count */
    uint32_t c, h, s;		/* C/H/S geometry */
    uint32_t offset;		/* Byte offset for disk */
    uint32_t boot_lba;		/* LBA of bootstrap code */
    uint8_t type;		/* Type byte for INT 13h AH=08h */
    uint8_t driveno;		/* Drive no */
    uint8_t sector_shift;	/* Sector size as a power of 2 */
    const char *hsrc, *ssrc;	/* Origins of H and S geometries */
};

/* Format of a DOS partition table entry */
struct ptab_entry {
    uint8_t active;
    uint8_t start_h, start_s, start_c;
    uint8_t type;
    uint8_t end_h, end_s, end_c;
    uint32_t start;
    uint32_t size;
} __attribute__ ((packed));

/* Format of a FAT filesystem superblock */
struct fat_extra {
    uint8_t bs_drvnum;
    uint8_t bs_resv1;
    uint8_t bs_bootsig;
    uint32_t bs_volid;
    char bs_vollab[11];
    char bs_filsystype[8];
} __attribute__ ((packed));
struct fat_super {
    uint8_t bs_jmpboot[3];
    char bs_oemname[8];
    uint16_t bpb_bytspersec;
    uint8_t bpb_secperclus;
    uint16_t bpb_rsvdseccnt;
    uint8_t bpb_numfats;
    uint16_t bpb_rootentcnt;
    uint16_t bpb_totsec16;
    uint8_t bpb_media;
    uint16_t bpb_fatsz16;
    uint16_t bpb_secpertrk;
    uint16_t bpb_numheads;
    uint32_t bpb_hiddsec;
    uint32_t bpb_totsec32;
    union {
	struct {
	    struct fat_extra extra;
	} fat16;
	struct {
	    uint32_t bpb_fatsz32;
	    uint16_t bpb_extflags;
	    uint16_t bpb_fsver;
	    uint32_t bpb_rootclus;
	    uint16_t bpb_fsinfo;
	    uint16_t bpb_bkbootsec;
	    char bpb_reserved[12];
	    /* Clever, eh?  Same fields, different offset... */
	    struct fat_extra extra;
	} fat32 __attribute__ ((packed));
    } x;
} __attribute__ ((packed));

/* Format of a DOSEMU header */
struct dosemu_header {
    uint8_t magic[7];		/* DOSEMU\0 */
    uint32_t h;
    uint32_t s;
    uint32_t c;
    uint32_t offset;
    uint8_t pad[105];
} __attribute__ ((packed));

#define FOUR(a,b,c,d) (((a) << 24)|((b) << 16)|((c) << 8)|(d))

static const struct geometry *get_disk_image_geometry(uint32_t where,
						      uint32_t size)
{
    static struct geometry hd_geometry;
    struct dosemu_header dosemu;
    unsigned int sectors, xsectors, v;
    unsigned int offset;
    int i;
    const char *p;

    printf("command line: %s\n", shdr->cmdline);

    hd_geometry.sector_shift = 9;	/* Assume floppy/HDD at first */

    offset = 0;
    if (CMD_HASDATA(p = getcmditem("offset")) && (v = atou(p)))
	offset = v;

    sectors = xsectors = (size - offset) >> hd_geometry.sector_shift;

    hd_geometry.hsrc = "guess";
    hd_geometry.ssrc = "guess";
    hd_geometry.sectors = sectors;
    hd_geometry.offset = offset;

    if ((p = getcmditem("iso")) != CMD_NOTFOUND) {
#if DBG_ELTORITO
	eltorito_dump(where);
#endif
	struct edd4_bvd *bvd = (struct edd4_bvd *)(where + 17 * 2048);
	/* Tiny sanity check */
	if ((bvd->boot_rec_ind != 0) || (bvd->ver != 1))
	    printf("El Torito BVD sanity check failed.\n");
	struct edd4_bootcat *boot_cat =
	    (struct edd4_bootcat *)(where + bvd->boot_cat * 2048);
	/* Another tiny sanity check */
	if ((boot_cat->validation_entry.platform_id != 0) ||
	    (boot_cat->validation_entry.key55 != 0x55) ||
	    (boot_cat->validation_entry.keyAA != 0xAA))
	    printf("El Torito boot catalog sanity check failed.\n");
	/* If we have an emulation mode, set the offset to the image */
	if (boot_cat->initial_entry.media_type)
	    hd_geometry.offset += boot_cat->initial_entry.load_block * 2048;
	else
	    /* We're a no-emulation mode, so we will boot to an offset */
	    hd_geometry.boot_lba = boot_cat->initial_entry.load_block * 4;
	if (boot_cat->initial_entry.media_type < 4) {
	    /* We're a floppy emulation mode or our params will be
	     * overwritten by the no emulation mode case
	     */
	    hd_geometry.driveno = 0x00;
	    hd_geometry.c = 80;
	    hd_geometry.h = 2;
	}
	switch (boot_cat->initial_entry.media_type) {
	case 0:		/* No emulation   */
	    hd_geometry.driveno = 0xE0;
	    hd_geometry.type = 10;	/* ATAPI removable media device */
	    hd_geometry.c = 65535;
	    hd_geometry.h = 255;
	    hd_geometry.s = 15;
	    /* 2048-byte sectors, so adjust the size and count */
	    hd_geometry.sector_shift = 11;
	    break;
	case 1:		/* 1.2 MB floppy  */
	    hd_geometry.s = 15;
	    hd_geometry.type = 2;
	    sectors = 2400;
	    break;
	case 2:		/* 1.44 MB floppy */
	    hd_geometry.s = 18;
	    hd_geometry.type = 4;
	    sectors = 2880;
	    break;
	case 3:		/* 2.88 MB floppy */
	    hd_geometry.s = 36;
	    hd_geometry.type = 6;
	    sectors = 5760;
	    break;
	case 4:
	    hd_geometry.driveno = 0x80;
	    hd_geometry.type = 0;
	    break;
	}
	sectors = (size - hd_geometry.offset) >> hd_geometry.sector_shift;

	/* For HDD emulation, we figure out the geometry later. Otherwise: */
	if (hd_geometry.s) {
	    hd_geometry.hsrc = hd_geometry.ssrc = "El Torito";
	}
	hd_geometry.sectors = sectors;
    }

    /* Do we have a DOSEMU header? */
    memcpy(&dosemu, (char *)where + hd_geometry.offset, sizeof dosemu);
    if (!memcmp("DOSEMU", dosemu.magic, 7)) {
	/* Always a hard disk unless overruled by command-line options */
	hd_geometry.driveno = 0x80;
	hd_geometry.type = 0;
	hd_geometry.c = dosemu.c;
	hd_geometry.h = dosemu.h;
	hd_geometry.s = dosemu.s;
	hd_geometry.offset += dosemu.offset;
	sectors = (size - hd_geometry.offset) >> hd_geometry.sector_shift;

	hd_geometry.hsrc = hd_geometry.ssrc = "DOSEMU";
    }

    if (CMD_HASDATA(p = getcmditem("c")) && (v = atou(p)))
	hd_geometry.c = v;
    if (CMD_HASDATA(p = getcmditem("h")) && (v = atou(p))) {
	hd_geometry.h = v;
	hd_geometry.hsrc = "cmd";
    }
    if (CMD_HASDATA(p = getcmditem("s")) && (v = atou(p))) {
	hd_geometry.s = v;
	hd_geometry.ssrc = "cmd";
    }

    if (!hd_geometry.h || !hd_geometry.s) {
	int h, s, max_h, max_s;

	max_h = hd_geometry.h;
	max_s = hd_geometry.s;

	if (!(max_h | max_s)) {
	    /* Look for a FAT superblock and if we find something that looks
	       enough like one, use geometry from that.  This takes care of
	       megafloppy images and unpartitioned hard disks. */
	    const struct fat_extra *extra = NULL;
	    const struct fat_super *fs = (const struct fat_super *)
		((char *)where + hd_geometry.offset);

	    if ((fs->bpb_media == 0xf0 || fs->bpb_media >= 0xf8) &&
		(fs->bs_jmpboot[0] == 0xe9 || fs->bs_jmpboot[0] == 0xeb) &&
		fs->bpb_bytspersec == 512 &&
		fs->bpb_numheads >= 1 && fs->bpb_numheads <= 256 &&
		fs->bpb_secpertrk >= 1 && fs->bpb_secpertrk <= 63) {
		extra =
		    fs->bpb_fatsz16 ? &fs->x.fat16.extra : &fs->x.fat32.extra;
		if (!
		    (extra->bs_bootsig == 0x29 && extra->bs_filsystype[0] == 'F'
		     && extra->bs_filsystype[1] == 'A'
		     && extra->bs_filsystype[2] == 'T'))
		    extra = NULL;
	    }
	    if (extra) {
		hd_geometry.driveno = extra->bs_drvnum & 0x80;
		max_h = fs->bpb_numheads;
		max_s = fs->bpb_secpertrk;
		hd_geometry.hsrc = hd_geometry.ssrc = "FAT";
	    }
	}

	if (!(max_h | max_s)) {
	    /* No FAT filesystem found to steal geometry from... */
	    if ((sectors < 4096 * 2) && (hd_geometry.sector_shift == 9)) {
		int ok = 0;
		unsigned int xsectors = sectors;

		hd_geometry.driveno = 0;	/* Assume floppy */

		while (!ok) {
		    /* Assume it's a floppy drive, guess a geometry */
		    unsigned int type, track;
		    int c, h, s = 0;

		    if (xsectors < 320 * 2) {
			c = 40;
			h = 1;
			type = 1;
		    } else if (xsectors < 640 * 2) {
			c = 40;
			h = 2;
			type = 1;
		    } else if (xsectors < 1200 * 2) {
			c = 80;
			h = 2;
			type = 3;
		    } else if (xsectors < 1440 * 2) {
			c = 80;
			h = 2;
			type = 2;
		    } else if (xsectors < 2880 * 2) {
			c = 80;
			h = 2;
			type = 4;
		    } else {
			c = 80;
			h = 2;
			type = 6;
		    }
		    track = c * h;
		    while (c < 256) {
			s = xsectors / track;
			if (s < 63 && (xsectors % track) == 0) {
			    ok = 1;
			    break;
			}
			c++;
			track += h;
		    }
		    if (ok) {
			max_h = h;
			max_s = s;
			hd_geometry.hsrc = hd_geometry.ssrc = "fd";
		    } else {
			/* No valid floppy geometry, fake it by simulating broken
			   sectors at the end of the image... */
			xsectors++;
		    }

		    hd_geometry.type = type;
		}
	    } else {
		/* Assume it is a hard disk image and scan for a partition table */
		const struct ptab_entry *ptab = (const struct ptab_entry *)
		    ((char *)where + hd_geometry.offset + (512 - 2 - 4 * 16));

		/* Assume hard disk */
		if (!hd_geometry.driveno)
		    hd_geometry.driveno = 0x80;

		if (*(uint16_t *) ((char *)where + hd_geometry.offset + 512 - 2) == 0xaa55) {
		    for (i = 0; i < 4; i++) {
			if (ptab[i].type && !(ptab[i].active & 0x7f)) {
			    s = (ptab[i].start_s & 0x3f);
			    h = ptab[i].start_h + 1;

			    if (max_h < h)
				max_h = h;
			    if (max_s < s)
				max_s = s;

			    s = (ptab[i].end_s & 0x3f);
			    h = ptab[i].end_h + 1;

			    if (max_h < h) {
				max_h = h;
				hd_geometry.hsrc = "MBR";
			    }
			    if (max_s < s) {
				max_s = s;
				hd_geometry.ssrc = "MBR";
			    }
			}
		    }
		}

		hd_geometry.type = 0;
	    }
	}

	if (!max_h)
	    max_h = xsectors > 2097152 ? 255 : 64;
	if (!max_s)
	    max_s = xsectors > 2097152 ? 63 : 32;

	hd_geometry.h    = max_h;
	hd_geometry.s    = max_s;
    }

    if (!hd_geometry.c)
	hd_geometry.c = xsectors / (hd_geometry.h * hd_geometry.s);

    if ((p = getcmditem("floppy")) != CMD_NOTFOUND) {
	hd_geometry.driveno = CMD_HASDATA(p) ? atou(p) & 0x7f : 0;
    } else if ((p = getcmditem("harddisk")) != CMD_NOTFOUND) {
	hd_geometry.driveno = CMD_HASDATA(p) ? atou(p) | 0x80 : 0x80;
    }

    if (hd_geometry.driveno & 0x80) {
	hd_geometry.type = 0;	/* Type = hard disk */
    } else {
	if (hd_geometry.type == 0)
	    hd_geometry.type = 0x10;	/* ATAPI floppy, e.g. LS-120 */
    }

    if ((size - hd_geometry.offset) & 0x1ff) {
	puts("MEMDISK: Image has fractional end sector\n");
    }
    if (sectors % (hd_geometry.h * hd_geometry.s)) {
	puts("MEMDISK: Image seems to have fractional end cylinder\n");
    }
    if ((hd_geometry.c * hd_geometry.h * hd_geometry.s) > sectors) {
	puts("MEMDISK: Image appears to be truncated\n");
    }

    return &hd_geometry;
}

/*
 * Find a $PnP installation check structure; return (ES << 16) + DI value
 */
static uint32_t pnp_install_check(void)
{
    uint32_t *seg;
    unsigned char *p, csum;
    int i, len;

    for (seg = (uint32_t *) 0xf0000; seg < (uint32_t *) 0x100000; seg += 4) {
	if (*seg == ('$' + ('P' << 8) + ('n' << 16) + ('P' << 24))) {
	    p = (unsigned char *)seg;
	    len = p[5];
	    if (len < 0x21)
		continue;
	    csum = 0;
	    for (i = len; i; i--)
		csum += *p++;
	    if (csum != 0)
		continue;

	    return (0xf000 << 16) + (uint16_t) (unsigned long)seg;
	}
    }

    return 0;
}

/*
 * Relocate the real-mode code to a new segment
 */
struct gdt_ptr {
    uint16_t limit;
    uint32_t base;
} __attribute__ ((packed));

static void set_seg_base(uint32_t gdt_base, int seg, uint32_t v)
{
    *(uint16_t *) (gdt_base + seg + 2) = v;
    *(uint8_t *) (gdt_base + seg + 4) = v >> 16;
    *(uint8_t *) (gdt_base + seg + 7) = v >> 24;
}

static void relocate_rm_code(uint32_t newbase)
{
    uint32_t gdt_base;
    uint32_t oldbase = rm_args.rm_base;
    uint32_t delta = newbase - oldbase;

    cli();
    memmove((void *)newbase, (void *)oldbase, rm_args.rm_size);

    rm_args.rm_return += delta;
    rm_args.rm_intcall += delta;
    rm_args.rm_bounce += delta;
    rm_args.rm_base += delta;
    rm_args.rm_gdt += delta;
    rm_args.rm_pmjmp += delta;
    rm_args.rm_rmjmp += delta;

    gdt_base = rm_args.rm_gdt;

    *(uint32_t *) (gdt_base + 2) = gdt_base;	/* GDT self-pointer */

    /* Segments 0x10 and 0x18 are real-mode-based */
    set_seg_base(gdt_base, 0x10, rm_args.rm_base);
    set_seg_base(gdt_base, 0x18, rm_args.rm_base);

#if __SIZEOF_POINTER__ == 4
    asm volatile ("lgdtl %0"::"m" (*(char *)gdt_base));
#elif __SIZEOF_POINTER__ == 8
    asm volatile ("lgdt %0"::"m" (*(char *)gdt_base));
#else
#error "unsupported architecture"
#endif

    *(uint32_t *) rm_args.rm_pmjmp += delta;
    *(uint16_t *) rm_args.rm_rmjmp += delta >> 4;

    rm_args.rm_handle_interrupt += delta;

    sti();
}

static uint8_t checksum_buf(const void *buf, int count)
{
    const uint8_t *p = buf;
    uint8_t c = 0;

    while (count--)
	c += *p++;

    return c;
}

static int stack_needed(void)
{
  const unsigned int min_stack = 128;	/* Minimum stack size */
  const unsigned int def_stack = 512;	/* Default stack size */
  unsigned int v = 0;
  const char *p;

  if (CMD_HASDATA(p = getcmditem("stack")))
    v = atou(p);

  if (!v)
    v = def_stack;

  if (v < min_stack)
    v = min_stack;

  return v;
}

/*
 * Set max memory by reservation
 * Adds reservations to data in INT15h to prevent access to the top of RAM
 * if there's any above the point specified.
 */
void setmaxmem(unsigned long long restop_ull)
{
    uint32_t restop;
    struct e820range *ep;
    const int int15restype = 2;

    /* insertrange() works on uint32_t */
    restop = min(restop_ull, UINT32_MAX);
    /* printf("  setmaxmem  '%08x%08x'  => %08x\n",
	(unsigned int)(restop_ull>>32), (unsigned int)restop_ull, restop); */

    for (ep = ranges; ep->type != -1U; ep++) {
	if (ep->type == 1) {	/* Only if available */
	    if (ep->start >= restop) {
		/* printf("  %08x -> 2\n", ep->start); */
		ep->type = int15restype;
	    } else if (ep[1].start > restop) {
		/* printf("  +%08x =2; cut %08x\n", restop, ep->start); */
		insertrange(restop, (ep[1].start - restop), int15restype);
	    }
	}
    }
    parse_mem();
}

struct real_mode_args rm_args;

/*
 * Actual setup routine
 * Returns the drive number (which is then passed in %dl to the
 * called routine.)
 */
void setup(const struct real_mode_args *rm_args_ptr)
{
    unsigned int bin_size;
    char *memdisk_hook;
    struct memdisk_header *hptr;
    struct patch_area *pptr;
    struct mBFT *mbft;
    uint16_t driverseg;
    uint32_t driverptr, driveraddr;
    uint16_t dosmem_k;
    uint32_t stddosmem;
    const struct geometry *geometry;
    unsigned int total_size;
    unsigned int cmdline_len, stack_len, e820_len;
    const struct edd4_bvd *bvd;
    const struct edd4_bootcat *boot_cat = 0;
    com32sys_t regs;
    uint32_t ramdisk_image, ramdisk_size;
    uint32_t boot_base, rm_base;
    int bios_drives;
    int do_edd = 1;		/* 0 = no, 1 = yes, default is yes */
    int do_eltorito = 0;	/* default is no */
    int no_bpt;			/* No valid BPT presented */
    uint32_t boot_seg = 0;	/* Meaning 0000:7C00 */
    uint32_t boot_len = 512;	/* One sector */
    const char *p;

    /* We need to copy the rm_args into their proper place */
    memcpy(&rm_args, rm_args_ptr, sizeof rm_args);
    sti();			/* ... then interrupts are safe */

    /* Show signs of life */
    printf("%s  %s\n", memdisk_version, copyright);

    if (!shdr->ramdisk_image || !shdr->ramdisk_size)
	die("MEMDISK: No ramdisk image specified!\n");

    ramdisk_image = shdr->ramdisk_image;
    ramdisk_size = shdr->ramdisk_size;

    e820map_init();		/* Initialize memory data structure */
    get_mem();			/* Query BIOS for memory map */
    parse_mem();		/* Parse memory map */

    printf("Ramdisk at 0x%08x, length 0x%08x\n", ramdisk_image, ramdisk_size);

    unzip_if_needed(&ramdisk_image, &ramdisk_size);

    geometry = get_disk_image_geometry(ramdisk_image, ramdisk_size);

    if (getcmditem("edd") != CMD_NOTFOUND ||
	getcmditem("ebios") != CMD_NOTFOUND)
	do_edd = 1;
    else if (getcmditem("noedd") != CMD_NOTFOUND ||
	     getcmditem("noebios") != CMD_NOTFOUND ||
	     getcmditem("cbios") != CMD_NOTFOUND)
	do_edd = 0;
    else
	do_edd = (geometry->driveno & 0x80) ? 1 : 0;

    if (getcmditem("iso") != CMD_NOTFOUND) {
	do_eltorito = 1;
	do_edd = 1;		/* Mandatory */
    }

    /* Choose the appropriate installable memdisk hook */
    if (do_eltorito) {
	if (geometry->sector_shift == 11) {
	    bin_size = (int)&_binary_memdisk_iso_2048_bin_size;
	    memdisk_hook = (char *)&_binary_memdisk_iso_2048_bin_start;
	} else {
	    bin_size = (int)&_binary_memdisk_iso_512_bin_size;
	    memdisk_hook = (char *)&_binary_memdisk_iso_512_bin_start;
	}
    } else {
	if (do_edd) {
	    bin_size = (int)&_binary_memdisk_edd_512_bin_size;
	    memdisk_hook = (char *)&_binary_memdisk_edd_512_bin_start;
	} else {
	    bin_size = (int)&_binary_memdisk_chs_512_bin_size;
	    memdisk_hook = (char *)&_binary_memdisk_chs_512_bin_start;
	}
    }

    /* Reserve the ramdisk memory */
    insertrange(ramdisk_image, ramdisk_size, 2);
    parse_mem();		/* Recompute variables */

    /* Figure out where it needs to go */
    hptr = (struct memdisk_header *)memdisk_hook;
    pptr = (struct patch_area *)(memdisk_hook + hptr->patch_offs);

    dosmem_k = rdz_16(BIOS_BASEMEM);
    pptr->mdi.olddosmem = dosmem_k;
    stddosmem = dosmem_k << 10;
    /* If INT 15 E820 and INT 12 disagree, go with the most conservative */
    if (stddosmem > dos_mem)
	stddosmem = dos_mem;

    pptr->driveno = geometry->driveno;
    pptr->drivetype = geometry->type;
    pptr->cylinders = geometry->c;	/* Possible precision loss */
    pptr->heads = geometry->h;
    pptr->sectors = geometry->s;
    pptr->mdi.disksize = geometry->sectors;
    pptr->mdi.diskbuf = ramdisk_image + geometry->offset;
    pptr->mdi.sector_shift = geometry->sector_shift;
    pptr->statusptr = (geometry->driveno & 0x80) ? 0x474 : 0x441;

    pptr->mdi.bootloaderid = shdr->type_of_loader;

    pptr->configflags = CONFIG_SAFEINT;	/* Default */
    /* Set config flags */
    if (getcmditem("ro") != CMD_NOTFOUND) {
	pptr->configflags |= CONFIG_READONLY;
    }
    if (getcmditem("raw") != CMD_NOTFOUND) {
	pptr->configflags &= ~CONFIG_MODEMASK;
	pptr->configflags |= CONFIG_RAW;
    }
    if (getcmditem("bigraw") != CMD_NOTFOUND) {
	pptr->configflags &= ~CONFIG_MODEMASK;
	pptr->configflags |= CONFIG_BIGRAW | CONFIG_RAW;
    }
    if (getcmditem("int") != CMD_NOTFOUND) {
	pptr->configflags &= ~CONFIG_MODEMASK;
	/* pptr->configflags |= 0; */
    }
    if (getcmditem("safeint") != CMD_NOTFOUND) {
	pptr->configflags &= ~CONFIG_MODEMASK;
	pptr->configflags |= CONFIG_SAFEINT;
    }

    printf("Disk is %s%d, %u%s K, C/H/S = %u/%u/%u (%s/%s), EDD %s, %s\n",
	   (geometry->driveno & 0x80) ? "hd" : "fd",
	   geometry->driveno & 0x7f,
	   geometry->sectors >> 1,
	   (geometry->sectors & 1) ? ".5" : "",
	   geometry->c, geometry->h, geometry->s,
	   geometry->hsrc, geometry->ssrc,
	   do_edd ? "on" : "off",
	   pptr->configflags & CONFIG_READONLY ? "ro" : "rw");

    puts("Using ");
    switch (pptr->configflags & CONFIG_MODEMASK) {
    case 0:
	puts("standard INT 15h");
	break;
    case CONFIG_SAFEINT:
	puts("safe INT 15h");
	break;
    case CONFIG_RAW:
	puts("raw");
	break;
    case CONFIG_RAW | CONFIG_BIGRAW:
	puts("big real mode raw");
	break;
    default:
	printf("unknown %#x", pptr->configflags & CONFIG_MODEMASK);
	break;
    }
    puts(" access to high memory\n");

    /* Set up a drive parameter table */
    if (geometry->driveno & 0x80) {
	/* Hard disk */
	pptr->dpt.hd.max_cyl = geometry->c - 1;
	pptr->dpt.hd.max_head = geometry->h - 1;
	pptr->dpt.hd.ctrl = (geometry->h > 8) ? 0x08 : 0;
    } else {
	/* Floppy - most of these fields are bogus and mimic
	   a 1.44 MB floppy drive */
	pptr->dpt.fd.specify1 = 0xdf;
	pptr->dpt.fd.specify2 = 0x02;
	pptr->dpt.fd.delay = 0x25;
	pptr->dpt.fd.sectors = geometry->s;
	pptr->dpt.fd.bps = 0x02;
	pptr->dpt.fd.isgap = 0x12;
	pptr->dpt.fd.dlen = 0xff;
	pptr->dpt.fd.fgap = 0x6c;
	pptr->dpt.fd.ffill = 0xf6;
	pptr->dpt.fd.settle = 0x0f;
	pptr->dpt.fd.mstart = 0x05;
	pptr->dpt.fd.maxtrack = geometry->c - 1;
	pptr->dpt.fd.cmos = geometry->type > 5 ? 5 : geometry->type;

	pptr->dpt.fd.old_fd_dpt = rdz_32(BIOS_INT1E);
    }

    /* Set up an EDD drive parameter table */
    if (do_edd) {
	pptr->edd_dpt.sectors = geometry->sectors;
	/* The EDD spec has this as <= 15482880  sectors (1024x240x63);
	   this seems to make very little sense.  Try for something saner. */
	if (geometry->c <= 1024 && geometry->h <= 255 && geometry->s <= 63) {
	    pptr->edd_dpt.c = geometry->c;
	    pptr->edd_dpt.h = geometry->h;
	    pptr->edd_dpt.s = geometry->s;
	    /* EDD-4 states that invalid geometry should be returned
	     * for INT 0x13, AH=0x48 "EDD Get Disk Parameters" call on an
	     * El Torito ODD.  Check for 2048-byte sector size
	     */
	    if (geometry->sector_shift != 11)
		pptr->edd_dpt.flags |= 0x0002;	/* Geometry valid */
	}
	if (!(geometry->driveno & 0x80)) {
	    /* Floppy drive.  Mark it as a removable device with
	       media change notification; media is present. */
	    pptr->edd_dpt.flags |= 0x0014;
	}

	pptr->edd_dpt.devpath[0] = pptr->mdi.diskbuf;
	pptr->edd_dpt.chksum = -checksum_buf(&pptr->edd_dpt.dpikey, 73 - 30);
    }

    if (do_eltorito) {
	bvd = (struct edd4_bvd *)(ramdisk_image + 17 * 2048);
	boot_cat =
	    (struct edd4_bootcat *)(ramdisk_image + bvd->boot_cat * 2048);
	pptr->cd_pkt.type = boot_cat->initial_entry.media_type;	/* Cheat */
	pptr->cd_pkt.driveno = geometry->driveno;
	pptr->cd_pkt.start = boot_cat->initial_entry.load_block;
	boot_seg = pptr->cd_pkt.load_seg = boot_cat->initial_entry.load_seg;
	pptr->cd_pkt.sect_count = boot_cat->initial_entry.sect_count;
	boot_len = pptr->cd_pkt.sect_count * 512;
	pptr->cd_pkt.geom1 = (uint8_t)(pptr->cylinders) & 0xFF;
	pptr->cd_pkt.geom2 =
	    (uint8_t)(pptr->sectors) | (uint8_t)((pptr->cylinders >> 2) & 0xC0);
	pptr->cd_pkt.geom3 = (uint8_t)(pptr->heads);
    }

    if ((p = getcmditem("mem")) != CMD_NOTFOUND) {
	setmaxmem(suffix_number(p));
    }

    /* The size is given by hptr->total_size plus the size of the E820
       map -- 12 bytes per range; we may need as many as 2 additional
       ranges (each insertrange() can worst-case turn 1 area into 3)
       plus the terminating range, over what nranges currently show. */
    total_size = hptr->total_size;	/* Actual memdisk code */
    e820_len = (nranges + 3) * sizeof(ranges[0]);
    total_size += e820_len;		/* E820 memory ranges */
    cmdline_len = strlen(shdr->cmdline) + 1;
    total_size += cmdline_len;		/* Command line */
    stack_len = stack_needed();
    total_size += stack_len;		/* Stack */
    printf("Code %u, meminfo %u, cmdline %u, stack %u\n",
	   hptr->total_size, e820_len, cmdline_len, stack_len);
    printf("Total size needed = %u bytes, allocating %uK\n",
	   total_size, (total_size + 0x3ff) >> 10);

    if (total_size > dos_mem)
	die("MEMDISK: Insufficient low memory\n");

    driveraddr = stddosmem - total_size;
    driveraddr &= ~0x3FF;

    printf("Old dos memory at 0x%05x (map says 0x%05x), loading at 0x%05x\n",
	   stddosmem, dos_mem, driveraddr);

    /* Reserve this range of memory */
    wrz_16(BIOS_BASEMEM, driveraddr >> 10);
    insertrange(driveraddr, dos_mem - driveraddr, 2);
    parse_mem();

    pptr->mem1mb = low_mem >> 10;
    pptr->mem16mb = high_mem >> 16;
    if (low_mem == (15 << 20)) {
	/* lowmem maxed out */
	uint32_t int1588mem = (high_mem >> 10) + (low_mem >> 10);
	pptr->memint1588 = (int1588mem > 0xffff) ? 0xffff : int1588mem;
    } else {
	pptr->memint1588 = low_mem >> 10;
    }

    printf("1588: 0x%04x  15E801: 0x%04x 0x%04x\n",
	   pptr->memint1588, pptr->mem1mb, pptr->mem16mb);

    driverseg = driveraddr >> 4;
    driverptr = driverseg << 16;

    /* Anything beyond the end is for the stack */
    pptr->mystack = (uint16_t) (stddosmem - driveraddr);

    pptr->mdi.oldint13.uint32 = rdz_32(BIOS_INT13);
    pptr->mdi.oldint15.uint32 = rdz_32(BIOS_INT15);

    /* Adjust the E820 table: if there are null ranges (type 0)
       at the end, change them to type end of list (-1).
       This is necessary for the driver to be able to report end
       of list correctly. */
    while (nranges && ranges[nranges - 1].type == 0) {
	ranges[--nranges].type = -1;
    }

    if (getcmditem("nopassany") != CMD_NOTFOUND) {
	printf("nopassany specified - we're the only drive of any kind\n");
	bios_drives = 0;
	pptr->drivecnt = 0;
	no_bpt = 1;
	pptr->mdi.oldint13.uint32 = driverptr + hptr->iret_offs;
	wrz_8(BIOS_EQUIP, rdz_8(BIOS_EQUIP) & ~0xc1);
	wrz_8(BIOS_HD_COUNT, 0);
    } else if (getcmditem("nopass") != CMD_NOTFOUND) {
	printf("nopass specified - we're the only drive\n");
	bios_drives = 0;
	pptr->drivecnt = 0;
	no_bpt = 1;
    } else {
	/* Query drive parameters of this type */
	memset(&regs, 0, sizeof regs);
	regs.es = 0;
	regs.eax.b[1] = 0x08;
	regs.edx.b[0] = geometry->driveno & 0x80;
	intcall(0x13, &regs, &regs);

	/* Note: per suggestion from the Interrupt List, consider
	   INT 13 08 to have failed if the sector count in CL is zero. */
	if ((regs.eflags.l & 1) || !(regs.ecx.b[0] & 0x3f)) {
	    printf("INT 13 08: Failure, assuming this is the only drive\n");
	    pptr->drivecnt = 0;
	    no_bpt = 1;
	} else {
	    printf("INT 13 08: Success, count = %u, BPT = %04x:%04x\n",
		   regs.edx.b[0], regs.es, regs.edi.w[0]);
	    pptr->drivecnt = regs.edx.b[0];
	    no_bpt = !(regs.es | regs.edi.w[0]);
	}

	/* Compare what INT 13h returned with the appropriate equipment byte */
	if (geometry->driveno & 0x80) {
	    bios_drives = rdz_8(BIOS_HD_COUNT);
	} else {
	    uint8_t equip = rdz_8(BIOS_EQUIP);

	    if (equip & 1)
		bios_drives = (equip >> 6) + 1;
	    else
		bios_drives = 0;
	}

	if (pptr->drivecnt > bios_drives) {
	    printf("BIOS equipment byte says count = %d, go with that\n",
		   bios_drives);
	    pptr->drivecnt = bios_drives;
	}
    }

    /* Add ourselves to the drive count */
    pptr->drivecnt++;

    /* Discontiguous drive space.  There is no really good solution for this. */
    if (pptr->drivecnt <= (geometry->driveno & 0x7f))
	pptr->drivecnt = (geometry->driveno & 0x7f) + 1;

    /* Probe for contiguous range of BIOS drives starting with driveno */
    pptr->driveshiftlimit = probe_drive_range(geometry->driveno) + 1;
    if ((pptr->driveshiftlimit & 0x80) != (geometry->driveno & 0x80))
	printf("We lost the last drive in our class of drives.\n");
    printf("Drive probing gives drive shift limit: 0x%02x\n",
	pptr->driveshiftlimit);

    /* Pointer to the command line */
    pptr->mdi.cmdline.seg_off.offset = bin_size + (nranges + 1) * sizeof(ranges[0]);
    pptr->mdi.cmdline.seg_off.segment = driverseg;

    /* Copy driver followed by E820 table followed by command line */
    {
	unsigned char *dpp = (unsigned char *)(driverseg << 4);

	/* Adjust these pointers to point to the installed image */
	/* Careful about the order here... the image isn't copied yet! */
	pptr = (struct patch_area *)(dpp + hptr->patch_offs);
	hptr = (struct memdisk_header *)dpp;

	/* Actually copy to low memory */
	dpp = mempcpy(dpp, memdisk_hook, bin_size);
	dpp = mempcpy(dpp, ranges, (nranges + 1) * sizeof(ranges[0]));
	dpp = mempcpy(dpp, shdr->cmdline, cmdline_len);
    }

    /* Note the previous INT 13h hook in the "safe hook" structure */
    hptr->safe_hook.old_hook.uint32 = pptr->mdi.oldint13.uint32;

    /* Re-fill the "safe hook" mBFT field with the physical address */
    mbft = (struct mBFT *)(((const char *)hptr) + hptr->safe_hook.mbft);
    hptr->safe_hook.mbft = (size_t)mbft;

    /* Update various BIOS magic data areas (gotta love this shit) */

    if (geometry->driveno & 0x80) {
	/* Update BIOS hard disk count */
	uint8_t nhd = pptr->drivecnt;

	if (nhd > 128)
	    nhd = 128;

	if (!do_eltorito)
	    wrz_8(BIOS_HD_COUNT, nhd);
    } else {
	/* Update BIOS floppy disk count */
	uint8_t equip = rdz_8(BIOS_EQUIP);
	uint8_t nflop = pptr->drivecnt;

	if (nflop > 4)		/* Limit of equipment byte */
	    nflop = 4;

	equip &= 0x3E;
	if (nflop)
	    equip |= ((nflop - 1) << 6) | 0x01;

	wrz_8(BIOS_EQUIP, equip);

	/* Install DPT pointer if this was the only floppy */
	if (getcmditem("dpt") != CMD_NOTFOUND ||
	    ((nflop == 1 || no_bpt) && getcmditem("nodpt") == CMD_NOTFOUND)) {
	    /* Do install a replacement DPT into INT 1Eh */
	    pptr->mdi.dpt_ptr =
		hptr->patch_offs + offsetof(struct patch_area, dpt);
	}
    }

    /* Complete the mBFT */
    mbft->acpi.signature[0] = 'm';	/* "mBFT" */
    mbft->acpi.signature[1] = 'B';
    mbft->acpi.signature[2] = 'F';
    mbft->acpi.signature[3] = 'T';
    mbft->safe_hook = (size_t)&hptr->safe_hook;
    mbft->acpi.checksum = -checksum_buf(mbft, mbft->acpi.length);

    /* Install the interrupt handlers */
    printf("old: int13 = %08x  int15 = %08x  int1e = %08x\n",
	   rdz_32(BIOS_INT13), rdz_32(BIOS_INT15), rdz_32(BIOS_INT1E));

    wrz_32(BIOS_INT13, driverptr + hptr->int13_offs);
    wrz_32(BIOS_INT15, driverptr + hptr->int15_offs);
    if (pptr->mdi.dpt_ptr)
	wrz_32(BIOS_INT1E, driverptr + pptr->mdi.dpt_ptr);

    printf("new: int13 = %08x  int15 = %08x  int1e = %08x\n",
	   rdz_32(BIOS_INT13), rdz_32(BIOS_INT15), rdz_32(BIOS_INT1E));

    /* Figure out entry point */
    if (!boot_seg) {
	boot_base = 0x7c00;
	shdr->sssp = 0x7c00;
	shdr->csip = 0x7c00;
    } else {
	boot_base = boot_seg << 4;
	shdr->sssp = boot_seg << 16;
	shdr->csip = boot_seg << 16;
    }

    /* Relocate the real-mode code to below the stub */
    rm_base = (driveraddr - rm_args.rm_size) & ~15;
    if (rm_base < boot_base + boot_len)
	die("MEMDISK: bootstrap too large to load\n");

    relocate_rm_code(rm_base);

    /* Reboot into the new "disk" */
    puts("Loading boot sector... ");

    memcpy((void *)boot_base,
	   (char *)pptr->mdi.diskbuf + geometry->boot_lba * 512,
	   boot_len);

    if (getcmditem("pause") != CMD_NOTFOUND) {
	puts("press any key to boot... ");
	memset(&regs, 0, sizeof regs);
	regs.eax.w[0] = 0;
	intcall(0x16, &regs, NULL);
    }

    puts("booting...\n");

    /* On return the assembly code will jump to the boot vector */
    shdr->esdi = pnp_install_check();
    shdr->edx = geometry->driveno;
}

