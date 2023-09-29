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

/*
 * partiter.h
 *
 * Provides disk / partition iteration.
 */

#ifndef COM32_CHAIN_PARTITER_H
#define COM32_CHAIN_PARTITER_H

#include <stdint.h>
#include <syslinux/disk.h>

/* status */

enum {PI_ERRLOAD = -31, PI_INSANE, PI_OK = 0, PI_DONE};

/* flags */

enum {PIF_STEPALL = 1, PIF_PREFMBR = 2, PIF_STRICT = 4, PIF_STRICTER = 8};

struct itertype;
struct part_iter;

struct itertype {
	void (*dtor)(struct part_iter *);
	int  (*next)(struct part_iter *);
};

#define PI_GPTLABSIZE ((int)sizeof(((struct disk_gpt_part_entry *)0)->name))

struct part_iter {
    const struct itertype *type;
    char *data;
    char *record;
    uint64_t abs_lba;
    uint64_t length;
    int index0;	    /* including holes, from -1 (disk, then parts from 0) */
    int index;	    /* excluding holes, from  0 (disk, then parts from 1), -1 means hole, if PIF_STEPALL is set */
    int flags;	    /* flags, see #defines above */
    int status;	    /* current status, see enums above */
    struct disk_info di;
    union {
	struct {
	    uint32_t disk_sig;	  /* 32bit disk signature as stored in MBR */

	    uint32_t bebr_lba;	  /* absolute lba of base extended partition */
	    uint32_t bebr_siz;	  /* size of base extended partition */

	    uint32_t cebr_lba;	  /* absolute lba of curr ext. partition */
	    uint32_t cebr_siz;	  /* size of curr ext. partition */
	    uint32_t nebr_lba;	  /* absolute lba of next ext. partition */
	    uint32_t nebr_siz;	  /* size of next ext. partition */

	    int bebr_index0;	  /* index of (0-3) of base ext. part., -1 if not present in MBR */
	    int logskipcnt;	  /* how many logical holes were skipped */
	} dos;
	struct {
	    struct guid disk_guid;
	    struct guid part_guid;
	    char part_label[PI_GPTLABSIZE/2+1];
	    int pe_count;
	    int pe_size;
	    uint64_t ufirst;
	    uint64_t ulast;
	} gpt;
    };
};

extern const struct itertype * const typedos;
extern const struct itertype * const typegpt;
extern const struct itertype * const typeraw;

struct part_iter *pi_begin(const struct disk_info *, int flags);
void pi_del(struct part_iter **);

/* inline virtuals */
static inline int pi_next(struct part_iter *iter)
{
    return iter->type->next(iter);
}

static inline void pi_dtor(struct part_iter *iter)
{
    iter->type->dtor(iter);
}

#endif

/* vim: set ts=8 sts=4 sw=4 noet: */
