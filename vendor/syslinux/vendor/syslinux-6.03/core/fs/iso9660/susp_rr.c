/* Reader for SUSP and Rock Ridge information.

   Copyright (c) 2013 Thomas Schmitt <scdbackup@gmx.net>
   Provided under GNU General Public License version 2 or later.

   Based on:
   SUSP 1.12 (entries CE , PD , SP , ST , ER , ES)
     ftp://ftp.ymi.com/pub/rockridge/susp112.ps
   RRIP 1.12 (entries PX , PN , SL , NM , CL , PL , RE , TF , SF)
     ftp://ftp.ymi.com/pub/rockridge/rrip112.ps
   ECMA-119 aka ISO 9660
     http://www.ecma-international.org/publications/files/ECMA-ST/Ecma-119.pdf

   Shortcommings / Future improvements:
   (XXX): Avoid memcpy() with Continuation Areas wich span over more than one
	  block ? (Will then need memcpy() with entries which are hit by a
	  block boundary.) (Questionable whether the effort is worth it.)
   (XXX): Take into respect ES entries ? (Hardly anybody does this.)

*/

#ifndef Isolinux_rockridge_in_libisofS

/* Mindlessly copied from core/fs/iso9660/iso9660.c */
#include <dprintf.h>
#include <stdio.h>
#include <string.h>
#include <sys/dirent.h>
#include <core.h>
#include <cache.h>
#include <disk.h>
#include <fs.h>
#include <byteswap.h>
#include "iso9660_fs.h"

#else /* ! Isolinux_rockridge_in_libisofS */

/* ====== Test mock-up of definitions which should come from syslinux ====== */

/* With defined Isolinux_rockridge_in_libisofS this source file can be included
   into libisofs/fs_image.c and the outcome of its public functions can be
   compared with the perception of libisofs when loading an ISO image.

   Test results look ok with 50 ISO images when read by xorriso underneath
   valgrind.
*/

typedef uint32_t block_t;

#define dprintf printf

struct device {
    IsoDataSource *src;
};


struct susp_rr_dir_rec_wrap {
    char data[256];
};

struct iso_sb_info {
    struct susp_rr_dir_rec_wrap root;

    int do_rr;       /* 1 = try to process Rock Ridge info , 0 = do not */
    int susp_skip;   /* Skip length from SUSP enntry SP */
};

struct fs_info {
    struct device *fs_dev;
    struct iso_sb_info *fs_info;
};

#define get_cache dummy_get_cache

static char *dummy_get_cache(struct device *fs_dev, block_t lba)
{
    static uint8_t buf[2048];
    int ret;

    ret = fs_dev->src->read_block(fs_dev->src, lba, buf);
    if (ret < 0)
	return NULL;
    return (char *) buf;
}

/* =========================== End of test mock-up ========================= */

#endif /* ! Isolinux_rockridge_for_reaL */


static int susp_rr_is_out_of_mem(void *pt)
{
    if (pt != NULL)
	return 0;
    dprintf("susp_rr.c: Out of memory !\n");

    /* XXX : Should one abort on global level ? */

    return 1;
}


static uint32_t susp_rr_read_lsb32(const void *buf)
{
    return get_le32(buf);
}


/* State of iteration over SUSP entries.

   This would be quite trivial if there was not the possibility of Continuation
   Areas announced by the CE entry. In general they are quite rare, because
   often all Rock Ridge entries fit into the ISO 9660 directory record.
   So it seems unwise to invest much complexity into optimization of
   Continuation Areas.
   (I found 35 CE in a backup of mine which contains 63000 files, 2 CE in
    a Debian netinst ISO, 2 CE in a Fedora live CD.)
*/
struct susp_rr_iter {
    struct fs_info *fs;   /* From where to read Continuation Area data */
    char    *dir_rec;     /* ISO 9660 directory record */
    int     in_ce;        /* 0= still reading dir_rec, 1= reading ce_data */
    char    *ce_data;     /* Loaded Continuation Area data */
    int     ce_allocated; /* 0= do not free ce_data, 1= do free */
    size_t  read_pos;     /* Current read offset in dir_rec or ce_data */
    size_t  read_end;     /* Current first invalid read_pos */

    block_t next_lba;     /* Block number of start of next Continuation Area */
    size_t  next_offset;  /* Byte offset within the next_lba block */
    size_t  next_length;  /* Number of valid bytes in next Cont. Area */
};


static int susp_rr_iter_new(struct susp_rr_iter **iter,
			    struct fs_info *fs, char *dir_rec)
{
    struct iso_sb_info *sbi = fs->fs_info;
    struct susp_rr_iter *o;
    uint8_t len_fi;
    int read_pos, read_end;

    len_fi = ((uint8_t *) dir_rec)[32];
    read_pos = 33 + len_fi + !(len_fi % 2) + sbi->susp_skip;
    read_end = ((uint8_t *) dir_rec)[0];
    if (read_pos + 4 > read_end)
	return 0; /* Not enough System Use data present for SUSP */
    if (dir_rec[read_pos + 3] != 1)
	return 0; /* Not SUSP version 1 */

    o= *iter= malloc(sizeof(struct susp_rr_iter));
    if (susp_rr_is_out_of_mem(o))
	return -1;
    o->fs = fs;
    o->dir_rec= dir_rec;
    o->in_ce= 0;
    o->read_pos = read_pos;
    o->read_end = read_end;
    o->next_lba = 0;
    o->next_offset = o->next_length = 0;
    o->ce_data = NULL;
    o->ce_allocated = 0;
    return 1;
}


static int susp_rr_iter_destroy(struct susp_rr_iter **iter)
{
    struct susp_rr_iter *o;

    o = *iter;
    if (o == NULL)
	return 0;
    if (o->ce_data != NULL && o->ce_allocated)
	free(o->ce_data);
    free(o);
    *iter = NULL;
    return 1;
}


/* Switch to next Continuation Area.
*/
static int susp_rr_switch_to_ca(struct susp_rr_iter *iter)
{
    block_t num_blocks, i;
    const char *data = NULL;

    num_blocks = (iter->next_offset + iter->next_length + 2047) / 2048;

    if (iter->ce_data != NULL && iter->ce_allocated)
	free(iter->ce_data);
    iter->ce_data = NULL;
    iter->ce_allocated = 0;
    if (num_blocks > 1) {
	/* The blocks are expected contiguously. Need to consolidate them. */
	if (num_blocks > 50) {
	    dprintf("susp_rr.c: More than 100 KB claimed by a CE entry.\n");
	    return -1;
	}
	iter->ce_data = malloc(num_blocks * 2048);
	if (susp_rr_is_out_of_mem(iter->ce_data))
	    return -1;
	iter->ce_allocated = 1;
	for (i = 0; i < num_blocks; i++) {
	    data = get_cache(iter->fs->fs_dev, iter->next_lba + i);
	    if (data == NULL) {
		dprintf("susp_rr.c: Failure to read block %lu\n",
			(unsigned long) iter->next_lba + i);
		return -1;
	    }
	    memcpy(iter->ce_data + i * 2048, data, 2048);
	}
    } else {
	/* Avoiding malloc() and memcpy() in the single block case */
	data = get_cache(iter->fs->fs_dev, iter->next_lba);
	if (data == NULL) {
	    dprintf("susp_rr.c: Failure to read block %lu\n",
		    (unsigned long) iter->next_lba);
	    return -1;
	}
	iter->ce_data = (char *) data;
    }

    iter->in_ce = 1;
    iter->read_pos = iter->next_offset;
    iter->read_end = iter->next_offset + iter->next_length;
    iter->next_lba = 0;
    iter->next_offset = iter->next_length = 0;
    return 1;
}


/* Obtain the next SUSP entry.
*/
static int susp_rr_iterate(struct susp_rr_iter *iter, char **pos_pt)
{
    char *entries;
    uint8_t susp_len, *u_entry;
    int ret;

    if (iter->in_ce) {
	entries = iter->ce_data + iter->read_pos;
    } else {
	entries = iter->dir_rec + iter->read_pos;
    }
    if (iter->read_pos + 4 <= iter->read_end)
	if (entries[3] != 1) {
	    /* Not SUSP version 1 */
	    dprintf("susp_rr.c: Chain of SUSP entries broken\n");
	    return -1;
	}
    if (iter->read_pos + 4 > iter->read_end ||
	(entries[0] == 'S' && entries[1] == 'T')) {
	/* This part of the SU area is done */
	if (iter->next_length == 0) {
	    /* No further CE entry was encountered. Iteration ends now. */
	    return 0;
	}
	ret = susp_rr_switch_to_ca(iter);
	if (ret <= 0)
	    return ret;
	entries = iter->ce_data + iter->read_pos;
    }

    if (entries[0] == 'C' && entries[1] == 'E') {
	if (iter->next_length > 0) {
	    dprintf("susp_rr.c: Surplus CE entry detected\n");
	    return -1;
	}
	/* Register address data of next Continuation Area */
	u_entry = (uint8_t *) entries;
	iter->next_lba = susp_rr_read_lsb32(u_entry + 4);
	iter->next_offset = susp_rr_read_lsb32(u_entry + 12);
	iter->next_length = susp_rr_read_lsb32(u_entry + 20);
    }

    *pos_pt = entries;
    susp_len = ((uint8_t *) entries)[2];
    iter->read_pos += susp_len;
    return 1;
}


/* Check for SP entry at position try_skip in the System Use area.
*/
static int susp_rr_check_sp(struct fs_info *fs, char *dir_rec, int try_skip)
{
    struct iso_sb_info *sbi = fs->fs_info;
    int read_pos, read_end, len_fi;
    uint8_t *sua;

    len_fi = ((uint8_t *) dir_rec)[32];
    read_pos = 33 + len_fi + !(len_fi % 2) + try_skip;
    read_end = ((uint8_t *) dir_rec)[0];
    if (read_end - read_pos < 7)
	return 0;
    sua = (uint8_t *) (dir_rec + read_pos);
    if (sua[0] != 'S' || sua[1] != 'P' || sua[2] != 7 || sua[3] != 1 ||
	sua[4] != 0xbe || sua[5] != 0xef)
	return 0;
    dprintf("susp_rr.c: SUSP signature detected\n");
    sbi->susp_skip = ((uint8_t *) dir_rec)[6];
    if (sbi->susp_skip > 0 && sbi->susp_skip != try_skip)
	dprintf("susp_rr.c: Unusual: Non-zero skip length in SP entry\n");
    return 1;
}


/* Public function. See susp_rr.h

   Rock Ridge specific knowledge about NM and SL has been integrated here,
   because this saves one malloc and memcpy for the file name.
*/
int susp_rr_get_entries(struct fs_info *fs, char *dir_rec, char *sig,
			char **data, int *len_data, int flag)
{
    int count = 0, ret = 0, head_skip = 4, nmsp_flags = -1, is_done = 0;
    char *pos_pt, *new_data;
    uint8_t pay_len;
    struct susp_rr_iter *iter = NULL;
    struct iso_sb_info *sbi = fs->fs_info;

    *data = NULL;
    *len_data = 0;

    if (!sbi->do_rr)
	return 0; /* Rock Ridge is not enabled */

    if (flag & 1)
	head_skip = 5;

    ret = susp_rr_iter_new(&iter, fs, dir_rec);
    if (ret <= 0)
	goto ex;
    while (!is_done) {
	ret = susp_rr_iterate(iter, &pos_pt);
	if (ret < 0)
	    goto ex;
	if (ret == 0)
	    break; /* End SUSP iteration */
	if (sig[0] != pos_pt[0] || sig[1] != pos_pt[1])
	    continue; /* Next SUSP iteration */

	pay_len = ((uint8_t *) pos_pt)[2];
	if (pay_len < head_skip) {
	    dprintf("susp_rr.c: Short NM entry encountered.\n");
	    ret = -1;
	    goto ex;
	}
	pay_len -= head_skip;
	if ((flag & 1)) {
	    if (nmsp_flags < 0)
		nmsp_flags = ((uint8_t *) pos_pt)[4];
	    if (!(pos_pt[4] & 1)) /* No CONTINUE bit */
		is_done = 1; /* This is the last iteration cycle */
	}
	count += pay_len;
	if (count > 102400) {
	    dprintf("susp_rr.c: More than 100 KB in '%c%c' entries.\n",
		    sig[0], sig[1]);
	    ret = -1;
	    goto ex;
	}
	new_data = malloc(count + 1);
	if (susp_rr_is_out_of_mem(new_data)) {
	    ret = -1;
	    goto ex;
	}
	if (*data != NULL) {
	    /* This case should be rare. An extra iteration pass to predict
	       the needed data size would hardly pay off.
	    */
	    memcpy(new_data, *data, *len_data);
	    free(*data);
	}
	new_data[count] = 0;
	*data = new_data;
	memcpy(*data + *len_data, pos_pt + head_skip, pay_len);
	*len_data += pay_len;
    }
    if (*data == NULL) {
	ret = 0;
    } else if (flag & 1) {
	ret = 0x100 | nmsp_flags;
    } else {
	ret = 1;
    }
ex:;
    susp_rr_iter_destroy(&iter);
    if (ret <= 0 && *data != NULL) {
	free(*data);
	*data = NULL;
    }
    return ret;
}


/* Public function. See susp_rr.h
*/
int susp_rr_get_nm(struct fs_info *fs, char *dir_rec,
		   char **name, int *len_name)
{
    int ret;

    ret = susp_rr_get_entries(fs, dir_rec, "NM", name, len_name, 1);
    if (ret <= 0)
	return ret;

    /* Interpret flags */
    if (ret & 0x6) {
	if (*name != NULL)
	    free(*name);
	*len_name = 0;
	*name = strdup(ret & 0x2 ? "." : "..");
	if (susp_rr_is_out_of_mem(*name)) {
	    return -1;
	}
	*len_name = strlen(*name);
    }
    if (*len_name >= 256) {
	dprintf("susp_rr.c: Rock Ridge name longer than 255 characters.\n");
	free(*name);
	*name = NULL;
	*len_name = 0;
	return -1;
    }
    return 1;
}


/* Public function. See susp_rr.h
*/
int susp_rr_check_signatures(struct fs_info *fs, int flag)
{
    struct iso_sb_info *sbi = fs->fs_info;
    char *dir_rec;
    char *data = NULL;
    uint8_t *u_data;
    block_t lba;
    int len_data, i, len_er = 0, len_id, ret;
    int rrip_112 = 0;

    sbi->do_rr = 1;      /* provisory for the time of examination */
    sbi->susp_skip = 0;

#ifndef Isolinux_rockridge_in_libisofS
/* (There is a name collision with libisofs BLOCK_SIZE. On the other hand,
    libisofs has hardcoded blocksize 2048.) */

    /* For now this works only with 2 KB blocks */
    if (BLOCK_SIZE(fs) != 2048) {
	dprintf("susp_rr.c: Block size is not 2048. Rock Ridge disabled.\n");
	goto no_susp;
    }

#endif /* Isolinux_rockridge_in_libisofS */

    /* Obtain first dir_rec of root directory */
    lba = susp_rr_read_lsb32(((uint8_t *) &(sbi->root)) + 2);
    dir_rec = (char *) get_cache(fs->fs_dev, lba);
    if (dir_rec == NULL)
	goto no_susp;

    /* First System Use entry must be SP */
    ret = susp_rr_check_sp(fs, dir_rec, 0);
    if (ret == 0) {
	/* SUSP 1.12 prescribes that on CD-ROM XA discs the SP entry is at
	   offset 14 of the System Use area.
	   How to detect a CD-ROM XA disc here ?
	   (libisofs ignores this prescription and lives well with that.
	    /usr/src/linux/fs/isofs/ makes a blind try with 14.)
	*/
	ret = susp_rr_check_sp(fs, dir_rec, 14);
    }
    if (ret <= 0)
	goto no_susp;

    if (!(flag & 1)) {
	ret = 1;
	goto ex;
    }

    /* Look for ER entries */
    ret = susp_rr_get_entries(fs, dir_rec, "ER", &data, &len_data, 0);
    if (ret <= 0 || len_data < 8)
	goto no_rr;
    u_data = (uint8_t *) data;
    for (i = 0; i < len_data; i += len_er) {
	len_id = u_data[0];
	len_er = 4 + len_id + u_data[1] + u_data[2];
	if (i + len_er > len_data) {
	    dprintf("susp_rr.c: Error with field lengths in ER entry\n");
	    goto no_rr;
	}
	if (len_id == 10 && strncmp(data + 4, "RRIP_1991A", len_id) == 0) {
	    dprintf("susp_rr.c: Signature of Rock Ridge 1.10 detected\n");
	    break;
	} else if ((len_id == 10 &&
		   strncmp(data + 4, "IEEE_P1282", len_id) == 0) ||
		  (len_id == 9 &&
		   strncmp(data + 4, "IEEE_1282", len_id) == 0)) {
	    dprintf("susp_rr.c: Signature of Rock Ridge 1.12 detected\n");
	    rrip_112 = 1;
	    break;
	}
    }
    if (i >= len_data)
	goto no_rr;

    sbi->do_rr = 1 + rrip_112;
    ret = 2 + rrip_112;
    goto ex;

no_susp:;
    dprintf("susp_rr.c: No SUSP signature detected\n");
    ret = 0;
    goto ex;

no_rr:;
    dprintf("susp_rr.c: No Rock Ridge signature detected\n");
    ret = 0;

ex:;
    if (ret <= 0)
	sbi->do_rr = 0;
    if (data != NULL)
	free(data);
    return ret;
}
