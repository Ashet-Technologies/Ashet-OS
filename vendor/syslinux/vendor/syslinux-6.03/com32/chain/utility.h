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

#ifndef COM32_CHAIN_UTILITY_H
#define COM32_CHAIN_UTILITY_H

#include <stdint.h>
#include <stdio.h>
#include <syslinux/disk.h>
#include <syslinux/movebits.h>

/* most (all ?) bpb "types" known to humankind as of 2012 */
enum {bpbUNK, bpbV20, bpbV30, bpbV32, bpbV34, bpbV40, bpbVNT, bpbV70, bpbEXF};

/* see utility.c for details */
enum {L2C_CNUL, L2C_CADD, L2C_CMAX};

/* first usable and first unusable offsets */
#define dosmin ((addr_t)0x500u)
#define dosmax ((addr_t)(*(uint16_t *) 0x413 << 10))

void wait_key(void);
void lba2chs(disk_chs *dst, const struct disk_info *di, uint64_t lba, int mode);
uint32_t get_file_lba(const char *filename);
int drvoff_detect(int type);
int bpb_detect(const uint8_t *bpb, const char *tag);
int guid_is0(const struct guid *guid);

static inline int warn(const char *x)
{
    return fprintf(stderr, "WARN: %s\n", x);
}

static inline int error(const char *x)
{
    return fprintf(stderr, "ERR: %s\n", x);
}

static inline int crit(const char *x)
{
    return fprintf(stderr, "CRIT: %s @%s:%d\n", x, __FILE__, __LINE__);
}

#define critm()  crit("Malloc failure.")

#endif

/* vim: set ts=8 sts=4 sw=4 noet: */
