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
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <string.h>
#include <fs.h>
#include <syslinux/disk.h>
#include <syslinux/pmapi.h>
#include "utility.h"

static const char *bpbtypes[] = {
    [0] =  "unknown",
    [1] =  "2.0",
    [2] =  "3.0",
    [3] =  "3.2",
    [4] =  "3.4",
    [5] =  "4.0",
    [6] =  "8.0 (NT+)",
    [7] =  "7.0",
    [8] =  "exFAT",
};

void wait_key(void)
{
    int cnt;
    char junk;

    /* drain */
    do {
	errno = 0;
	cnt = read(0, &junk, 1);
    } while (cnt > 0 || (cnt < 0 && errno == EAGAIN));

    /* wait */
    do {
	errno = 0;
	cnt = read(0, &junk, 1);
    } while (!cnt || (cnt < 0 && errno == EAGAIN));
}

int guid_is0(const struct guid *guid)
{
    return
	!(guid->data1 ||
	  guid->data2 ||
	  guid->data3 ||
	  guid->data4);
}

/*
 * mode explanation:
 *
 * cnul - "strict" mode, never returning higher value than obtained from cbios
 * cadd - if the disk is larger than reported geometry /and/ if the geometry has
 *        less cylinders than 1024 - it means that the total size is somewhere
 *        between cs and cs+1; in this particular case, we bump the cs to be able
 *        to return matching chs triplet
 * cmax - assume we can use any cylinder value
 *
 * by default cadd seems most reasonable, giving consistent results with e.g.
 * sfdisk's behavior
 */
void lba2chs(disk_chs *dst, const struct disk_info *di, uint64_t lba, int mode)
{
    uint32_t c, h, s, t;
    uint32_t cs, hs, ss;

    /*
     * Not much reason here, but if we have no valid CHS geometry, we assume
     * "typical" ones to have something to return.
     */
    if (di->cbios) {
	cs = di->cyl;
	hs = di->head;
	ss = di->spt;
	if (mode == L2C_CADD) {
	    if (cs < 1024 && di->lbacnt > cs*hs*ss)
		cs++;
	} else if (mode == L2C_CMAX)
	    cs = 1024;
    } else {
	if (di->disk & 0x80) {
	    cs = 1024;
	    hs = 255;
	    ss = 63;
	} else {
	    cs = 80;
	    hs = 2;
	    ss = 18;
	}
    }

    if (lba >= cs*hs*ss) {
	s = ss;
	h = hs - 1;
	c = cs - 1;
    } else {
	s = (lba % ss) + 1;
	t = lba / ss;
	h = t % hs;
	c = t / hs;
    }

    (*dst)[0] = h;
    (*dst)[1] = s | ((c & 0x300) >> 2);
    (*dst)[2] = c;
}

uint32_t get_file_lba(const char *filename)
{
    struct com32_filedata fd;
    uint32_t lba = 0;
    int size = 65536;
    char *buf;

    buf = lmalloc(size);
    if (!buf)
	return 0;

    /* Put the filename in the bounce buffer */
    strlcpy(buf, filename, size);

    if (open_file(buf, O_RDONLY, &fd) <= 0) {
	goto fail;		/* Filename not found */
    }

    /* Since the first member is the LBA, we simply cast */
    lba = *((uint32_t *) MK_PTR(0, fd.handle));

    /* Call comapi_close() to free the structure */
    close_file(fd.handle);

fail:
    lfree(buf);
    return lba;
}

/* drive offset detection */
int drvoff_detect(int type)
{
    if (bpbV40 <= type && type <= bpbVNT) {
	return 0x24;
    } else if (type == bpbV70) {
	return 0x40;
    } else if (type == bpbEXF) {
	return 0x6F;
    }

    return -1;
}

/*
 * heuristics could certainly be improved
 */
int bpb_detect(const uint8_t *sec, const char *tag)
{
    int a, b, c, jmp = -1, rev = 0;

    /* exFAT mess first (media descriptor is 0 here) */
    if (!memcmp(sec + 0x03, "EXFAT   ", 8)) {
	rev = bpbEXF;
	goto out;
    }

    /* media descriptor check */
    if ((sec[0x15] & 0xF0) != 0xF0)
	goto out;

    if (sec[0] == 0xEB)	/* jump short */
	jmp = 2 + *(int8_t *)(sec + 1);
    else if (sec[0] == 0xE9) /* jump near */
	jmp = 3 + *(int16_t *)(sec + 1);

    if (jmp < 0)    /* no boot code at all ? */
	goto nocode;

    /* sanity */
    if (jmp < 0x18 || jmp > 0x1F0)
	goto out;

    /* detect by jump */
    if (jmp >= 0x18 && jmp < 0x1E)
	rev = bpbV20;
    else if (jmp >= 0x1E && jmp < 0x20)
	rev = bpbV30;
    else if (jmp >= 0x20 && jmp < 0x24)
	rev = bpbV32;
    else if (jmp >= 0x24 && jmp < 0x46)
	rev = bpbV34;

    /* TODO: some better V2 - V3.4 checks ? */

    if (rev)
	goto out;
    /*
     * BPB info:
     * 2.0 ==       0x0B - 0x17
     * 3.0 == 2.0 + 0x18 - 0x1D
     * 3.2 == 3.0 + 0x1E - 0x1F
     * 3.4 ==!2.0 + 0x18 - 0x23
     * 4.0 == 3.4 + 0x24 - 0x45
     *  NT ==~3.4 + 0x24 - 0x53
     * 7.0 == 3.4 + 0x24 - 0x59
     */

nocode:
    a = memcmp(sec + 0x03, "NTFS", 4);
    b = memcmp(sec + 0x36, "FAT", 3);
    c = memcmp(sec + 0x52, "FAT", 3);	/* ext. DOS 7+ bs */

    if ((sec[0x26] & 0xFE) == 0x28 && !b) {
	rev = bpbV40;
    } else if (sec[0x26] == 0x80 && !a) {
	rev = bpbVNT;
    } else if ((sec[0x42] & 0xFE) == 0x28 && !c) {
	rev = bpbV70;
    }

out:
    printf("BPB detection (%s): %s\n", tag, bpbtypes[rev]);
    return rev;
}

/* vim: set ts=8 sts=4 sw=4 noet: */
