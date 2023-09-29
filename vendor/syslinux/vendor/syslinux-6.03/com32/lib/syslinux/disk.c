/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2003-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *   Copyright (C) 2010 Shao Miller
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

/**
 * @file disk.c
 *
 * Deal with disks and partitions
 */

#include <core.h>
#include <dprintf.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslinux/disk.h>

/**
 * Call int 13h, but with retry on failure.  Especially floppies need this.
 *
 * @v inreg			CPU register settings upon INT call
 * @v outreg			CPU register settings returned by INT call
 * @ret (int)			0 upon success, -1 upon failure
 */
int disk_int13_retry(const com32sys_t * inreg, com32sys_t * outreg)
{
    int retry = 6;		/* Number of retries */
    com32sys_t tmpregs;

    if (!outreg)
	outreg = &tmpregs;

    while (retry--) {
	__intcall(0x13, inreg, outreg);
	if (!(outreg->eflags.l & EFLAGS_CF))
	    return 0;		/* CF=0, OK */
    }

    return -1;			/* Error */
}

/**
 * Query disk parameters and EBIOS availability for a particular disk.
 *
 * @v disk			The INT 0x13 disk drive number to process
 * @v diskinfo			The structure to save the queried params to
 * @ret (int)			0 upon success, -1 upon failure
 */
int disk_get_params(int disk, struct disk_info *const diskinfo)
{
    static com32sys_t inreg, outreg;
    struct disk_ebios_eparam *eparam;
    int rv = 0;

    memset(diskinfo, 0, sizeof *diskinfo);
    diskinfo->disk = disk;
    diskinfo->bps = SECTOR;

    /* Get EBIOS support */
    memset(&inreg, 0, sizeof inreg);
    inreg.eax.b[1] = 0x41;
    inreg.ebx.w[0] = 0x55aa;
    inreg.edx.b[0] = disk;
    inreg.eflags.b[0] = 0x3;	/* CF set */

    __intcall(0x13, &inreg, &outreg);

    if (!(outreg.eflags.l & EFLAGS_CF) &&
	outreg.ebx.w[0] == 0xaa55 && (outreg.ecx.b[0] & 1)) {
	diskinfo->ebios = 1;
    }

    eparam = lmalloc(sizeof *eparam);
    if (!eparam)
	return -1;

    /* Get extended disk parameters if ebios == 1 */
    if (diskinfo->ebios) {
	memset(&inreg, 0, sizeof inreg);
	inreg.eax.b[1] = 0x48;
	inreg.edx.b[0] = disk;
	inreg.esi.w[0] = OFFS(eparam);
	inreg.ds = SEG(eparam);

	memset(eparam, 0, sizeof *eparam);
	eparam->len = sizeof *eparam;

	__intcall(0x13, &inreg, &outreg);

	if (!(outreg.eflags.l & EFLAGS_CF)) {
	    diskinfo->lbacnt = eparam->lbacnt;
	    if (eparam->bps)
		diskinfo->bps = eparam->bps;
	    /*
	     * don't think about using geometry data returned by
	     * 48h, as it can differ from 08h a lot ...
	     */
	}
    }
    /*
     * Get disk parameters the old way - really only useful for hard
     * disks, but if we have a partitioned floppy it's actually our best
     * chance...
     */
    memset(&inreg, 0, sizeof inreg);
    inreg.eax.b[1] = 0x08;
    inreg.edx.b[0] = disk;

    __intcall(0x13, &inreg, &outreg);

    if (outreg.eflags.l & EFLAGS_CF) {
	rv = diskinfo->ebios ? 0 : -1;
	goto out;
    }

    diskinfo->spt = 0x3f & outreg.ecx.b[0];
    diskinfo->head = 1 + outreg.edx.b[1];
    diskinfo->cyl = 1 + (outreg.ecx.b[1] | ((outreg.ecx.b[0] & 0xc0u) << 2));

    if (diskinfo->spt)
	diskinfo->cbios = 1;	/* Valid geometry */
    else {
	diskinfo->head = 1;
	diskinfo->spt = 1;
	diskinfo->cyl = 1;
    }

    if (!diskinfo->lbacnt)
	diskinfo->lbacnt = diskinfo->cyl * diskinfo->head * diskinfo->spt;

out:
    lfree(eparam);
    return rv;
}

/**
 * Fill inreg based on EBIOS addressing properties.
 *
 * @v diskinfo			The disk drive to read from
 * @v inreg			Register data structure to be filled.
 * @v lba			The logical block address to begin reading at
 * @v count			The number of sectors to read
 * @v op_code			Code to write/read operation
 * @ret 			lmalloc'd buf upon success, NULL upon failure
 */
static void *ebios_setup(const struct disk_info *const diskinfo, com32sys_t *inreg,
			 uint64_t lba, uint8_t count, uint8_t op_code)
{
    static struct disk_ebios_dapa *dapa = NULL;
    void *buf;

    if (!dapa) {
	dapa = lmalloc(sizeof *dapa);
	if (!dapa)
	    return NULL;
    }

    buf = lmalloc(count * diskinfo->bps);
    if (!buf)
	return NULL;

    dapa->len = sizeof(*dapa);
    dapa->count = count;
    dapa->off = OFFS(buf);
    dapa->seg = SEG(buf);
    dapa->lba = lba;

    inreg->eax.b[1] = op_code;
    inreg->esi.w[0] = OFFS(dapa);
    inreg->ds = SEG(dapa);
    inreg->edx.b[0] = diskinfo->disk;

    return buf;
}

/**
 * Fill inreg based on CHS addressing properties.
 *
 * @v diskinfo			The disk drive to read from
 * @v inreg			Register data structure to be filled.
 * @v lba			The logical block address to begin reading at
 * @v count			The number of sectors to read
 * @v op_code			Code to write/read operation
 * @ret 			lmalloc'd buf upon success, NULL upon failure
 */
static void *chs_setup(const struct disk_info *const diskinfo, com32sys_t *inreg,
		       uint64_t lba, uint8_t count, uint8_t op_code)
{
    unsigned int c, h, s, t;
    void *buf;

    buf = lmalloc(count * diskinfo->bps);
    if (!buf)
	return NULL;

    /*
     * if we passed lba + count check and we get here, that means that
     * lbacnt was calculated from chs geometry (or faked from 1/1/1), thus
     * 32bits are perfectly enough and lbacnt corresponds to cylinder
     * boundary
     */
    s = lba % diskinfo->spt;
    t = lba / diskinfo->spt;
    h = t % diskinfo->head;
    c = t / diskinfo->head;

    memset(inreg, 0, sizeof *inreg);
    inreg->eax.b[0] = count;
    inreg->eax.b[1] = op_code;
    inreg->ecx.b[1] = c;
    inreg->ecx.b[0] = ((c & 0x300) >> 2) | (s+1);
    inreg->edx.b[1] = h;
    inreg->edx.b[0] = diskinfo->disk;
    inreg->ebx.w[0] = OFFS(buf);
    inreg->es = SEG(buf);

    return buf;
}

/**
 * Get disk block(s) and return a malloc'd buffer.
 *
 * @v diskinfo			The disk drive to read from
 * @v lba			The logical block address to begin reading at
 * @v count			The number of sectors to read
 * @ret data			An allocated buffer with the read data
 *
 * Uses the disk number and information from diskinfo.  Read count sectors
 * from drive, starting at lba.  Return a new buffer, or NULL upon failure.
 */
void *disk_read_sectors(const struct disk_info *const diskinfo, uint64_t lba,
			uint8_t count)
{
    com32sys_t inreg;
    void *buf;
    void *data = NULL;
    uint32_t maxcnt;
    uint32_t size = 65536;

    maxcnt = (size - diskinfo->bps) / diskinfo->bps;
    if (!count || count > maxcnt || lba + count > diskinfo->lbacnt)
	return NULL;

    memset(&inreg, 0, sizeof inreg);

    if (diskinfo->ebios)
	buf = ebios_setup(diskinfo, &inreg, lba, count, EBIOS_READ_CODE);
    else
	buf = chs_setup(diskinfo, &inreg, lba, count, CHS_READ_CODE);

    if (!buf)
	return NULL;

    if (disk_int13_retry(&inreg, NULL))
	goto out;

    data = malloc(count * diskinfo->bps);
    if (data)
	memcpy(data, buf, count * diskinfo->bps);
out:
    lfree(buf);
    return data;
}

/**
 * Write disk block(s).
 *
 * @v diskinfo			The disk drive to write to
 * @v lba			The logical block address to begin writing at
 * @v data			The data to write
 * @v count			The number of sectors to write
 * @ret (int)			0 upon success, -1 upon failure
 *
 * Uses the disk number and information from diskinfo.
 * Write sector(s) to a disk drive, starting at lba.
 */
int disk_write_sectors(const struct disk_info *const diskinfo, uint64_t lba,
		       const void *data, uint8_t count)
{
    com32sys_t inreg;
    void *buf;
    uint32_t maxcnt;
    uint32_t size = 65536;
    int rv = -1;

    maxcnt = (size - diskinfo->bps) / diskinfo->bps;
    if (!count || count > maxcnt || lba + count > diskinfo->lbacnt)
	return -1;

    memset(&inreg, 0, sizeof inreg);

    if (diskinfo->ebios)
	buf = ebios_setup(diskinfo, &inreg, lba, count, EBIOS_WRITE_CODE);
    else
	buf = chs_setup(diskinfo, &inreg, lba, count, CHS_WRITE_CODE);

    if (!buf)
	return -1;

    memcpy(buf, data, count * diskinfo->bps);

    if (disk_int13_retry(&inreg, NULL))
	goto out;

    rv = 0;			/* ok */
out:
    lfree(buf);
    return rv;
}

/**
 * Write disk blocks and verify they were written.
 *
 * @v diskinfo			The disk drive to write to
 * @v lba			The logical block address to begin writing at
 * @v buf			The data to write
 * @v count			The number of sectors to write
 * @ret rv			0 upon success, -1 upon failure
 *
 * Uses the disk number and information from diskinfo.
 * Writes sectors to a disk drive starting at lba, then reads them back
 * to verify they were written correctly.
 */
int disk_write_verify_sectors(const struct disk_info *const diskinfo,
			      uint64_t lba, const void *buf, uint8_t count)
{
    char *rb;
    int rv;

    rv = disk_write_sectors(diskinfo, lba, buf, count);
    if (rv)
	return rv;		/* Write failure */
    rb = disk_read_sectors(diskinfo, lba, count);
    if (!rb)
	return -1;		/* Readback failure */
    rv = memcmp(buf, rb, count * diskinfo->bps);
    free(rb);
    return rv ? -1 : 0;
}

/**
 * Dump info about a DOS partition entry
 *
 * @v part			The 16-byte partition entry to examine
 */
void disk_dos_part_dump(const struct disk_dos_part_entry *const part)
{
    (void)part;
    dprintf("Partition status _____ : 0x%.2x\n"
	    "Partition CHS start\n"
	    "  Cylinder ___________ : 0x%.4x (%u)\n"
	    "  Head _______________ : 0x%.2x (%u)\n"
	    "  Sector _____________ : 0x%.2x (%u)\n"
	    "Partition type _______ : 0x%.2x\n"
	    "Partition CHS end\n"
	    "  Cylinder ___________ : 0x%.4x (%u)\n"
	    "  Head _______________ : 0x%.2x (%u)\n"
	    "  Sector _____________ : 0x%.2x (%u)\n"
	    "Partition LBA start __ : 0x%.8x (%u)\n"
	    "Partition LBA count __ : 0x%.8x (%u)\n"
	    "-------------------------------\n",
	    part->active_flag,
	    chs_cylinder(part->start),
	    chs_cylinder(part->start),
	    chs_head(part->start),
	    chs_head(part->start),
	    chs_sector(part->start),
	    chs_sector(part->start),
	    part->ostype,
	    chs_cylinder(part->end),
	    chs_cylinder(part->end),
	    chs_head(part->end),
	    chs_head(part->end),
	    chs_sector(part->end),
	    chs_sector(part->end),
	    part->start_lba, part->start_lba, part->length, part->length);
}

/* Trivial error message output */
static inline void error(const char *msg)
{
    fputs(msg, stderr);
}

/**
 * This walk-map effectively reverses the little-endian
 * portions of a GPT disk/partition GUID for a string representation.
 * There might be a better header for this...
 */
static const char guid_le_walk_map[] = {
    3, -1, -1, -1, 0,
    5, -1, 0,
    3, -1, 0,
    2, 1, 0,
    1, 1, 1, 1, 1, 1
};

/**
 * Fill a buffer with a textual GUID representation.
 *
 * @v buf			Points to a minimum array of 37 chars
 * @v id			The GUID to represent as text
 *
 * The buffer must be >= char[37] and will be populated
 * with an ASCII NUL C string terminator.
 * Example: 11111111-2222-3333-4444-444444444444
 * Endian:  LLLLLLLL-LLLL-LLLL-BBBB-BBBBBBBBBBBB
 */
void guid_to_str(char *buf, const struct guid *const id)
{
    unsigned int i = 0;
    const char *walker = (const char *)id;

    while (i < sizeof(guid_le_walk_map)) {
	walker += guid_le_walk_map[i];
	if (!guid_le_walk_map[i])
	    *buf = '-';
	else {
	    *buf = ((*walker & 0xF0) >> 4) + '0';
	    if (*buf > '9')
		*buf += 'A' - '9' - 1;
	    buf++;
	    *buf = (*walker & 0x0F) + '0';
	    if (*buf > '9')
		*buf += 'A' - '9' - 1;
	}
	buf++;
	i++;
    }
    *buf = 0;
}

/**
 * Create a GUID structure from a textual GUID representation.
 *
 * @v buf			Points to a GUID string to parse
 * @v id			Points to a GUID to be populated
 * @ret (int)			Returns 0 upon success, -1 upon failure
 *
 * The input buffer must be >= 32 hexadecimal chars and be
 * terminated with an ASCII NUL.  Returns non-zero on failure.
 * Example: 11111111-2222-3333-4444-444444444444
 * Endian:  LLLLLLLL-LLLL-LLLL-BBBB-BBBBBBBBBBBB
 */
int str_to_guid(const char *buf, struct guid *const id)
{
    char guid_seq[sizeof(struct guid) * 2];
    unsigned int i = 0;
    char *walker = (char *)id;

    while (*buf && i < sizeof(guid_seq)) {
	switch (*buf) {
	    /* Skip these three characters */
	case '{':
	case '}':
	case '-':
	    break;
	default:
	    /* Copy something useful to the temp. sequence */
	    if ((*buf >= '0') && (*buf <= '9'))
		guid_seq[i] = *buf - '0';
	    else if ((*buf >= 'A') && (*buf <= 'F'))
		guid_seq[i] = *buf - 'A' + 10;
	    else if ((*buf >= 'a') && (*buf <= 'f'))
		guid_seq[i] = *buf - 'a' + 10;
	    else {
		/* Or not */
		error("Illegal character in GUID!\n");
		return -1;
	    }
	    i++;
	}
	buf++;
    }
    /* Check for insufficient valid characters */
    if (i < sizeof(guid_seq)) {
	error("Too few GUID characters!\n");
	return -1;
    }
    buf = guid_seq;
    i = 0;
    while (i < sizeof(guid_le_walk_map)) {
	if (!guid_le_walk_map[i])
	    i++;
	walker += guid_le_walk_map[i];
	*walker = *buf << 4;
	buf++;
	*walker |= *buf;
	buf++;
	i++;
    }
    return 0;
}

/**
 * Display GPT partition details.
 *
 * @v gpt_part			The GPT partition entry to display
 */
void disk_gpt_part_dump(const struct disk_gpt_part_entry *const gpt_part)
{
    unsigned int i;
    char guid_text[37];

    dprintf("----------------------------------\n"
	    "GPT part. LBA first __ : 0x%.16llx\n"
	    "GPT part. LBA last ___ : 0x%.16llx\n"
	    "GPT part. attribs ____ : 0x%.16llx\n"
	    "GPT part. name _______ : '",
	    gpt_part->lba_first, gpt_part->lba_last, gpt_part->attribs);
    for (i = 0; i < sizeof(gpt_part->name); i++) {
	if (gpt_part->name[i])
	    dprintf("%c", gpt_part->name[i]);
    }
    dprintf("'");
    guid_to_str(guid_text, &gpt_part->type);
    dprintf("GPT part. type GUID __ : {%s}\n", guid_text);
    guid_to_str(guid_text, &gpt_part->uid);
    dprintf("GPT part. unique ID __ : {%s}\n", guid_text);
}

/**
 * Display GPT header details.
 *
 * @v gpt			The GPT header to display
 */
void disk_gpt_header_dump(const struct disk_gpt_header *const gpt)
{
    char guid_text[37];

    printf("GPT sig ______________ : '%8.8s'\n"
	   "GPT major revision ___ : 0x%.4x\n"
	   "GPT minor revision ___ : 0x%.4x\n"
	   "GPT header size ______ : 0x%.8x\n"
	   "GPT header checksum __ : 0x%.8x\n"
	   "GPT reserved _________ : '%4.4s'\n"
	   "GPT LBA current ______ : 0x%.16llx\n"
	   "GPT LBA alternative __ : 0x%.16llx\n"
	   "GPT LBA first usable _ : 0x%.16llx\n"
	   "GPT LBA last usable __ : 0x%.16llx\n"
	   "GPT LBA part. table __ : 0x%.16llx\n"
	   "GPT partition count __ : 0x%.8x\n"
	   "GPT partition size ___ : 0x%.8x\n"
	   "GPT part. table chksum : 0x%.8x\n",
	   gpt->sig,
	   gpt->rev.fields.major,
	   gpt->rev.fields.minor,
	   gpt->hdr_size,
	   gpt->chksum,
	   gpt->reserved1,
	   gpt->lba_cur,
	   gpt->lba_alt,
	   gpt->lba_first_usable,
	   gpt->lba_last_usable,
	   gpt->lba_table, gpt->part_count, gpt->part_size, gpt->table_chksum);
    guid_to_str(guid_text, &gpt->disk_guid);
    printf("GPT disk GUID ________ : {%s}\n", guid_text);
}
