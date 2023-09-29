/*
 * Copyright (C) 2011-2012 Paulo Alcantara <pcacjr@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the
 * Free Software Foundation, Inc.,
 * 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/

/* Note: No support for compressed files */

#include <dprintf.h>
#include <stdio.h>
#include <string.h>
#include <sys/dirent.h>
#include <cache.h>
#include <core.h>
#include <disk.h>
#include <fs.h>
#include <ilog2.h>
#include <klibc/compiler.h>
#include <ctype.h>

#include "codepage.h"
#include "ntfs.h"
#include "runlist.h"

static struct ntfs_readdir_state *readdir_state;

/*** Function declarations */
static f_mft_record_lookup ntfs_mft_record_lookup_3_0;
static f_mft_record_lookup ntfs_mft_record_lookup_3_1;
static inline enum dirent_type get_inode_mode(struct ntfs_mft_record *mrec);
static inline struct ntfs_attr_record * ntfs_attr_lookup(struct fs_info *fs, uint32_t type, struct ntfs_mft_record **mmrec, struct ntfs_mft_record *mrec);
static inline uint8_t *mapping_chunk_init(struct ntfs_attr_record *attr,struct mapping_chunk *chunk,uint32_t *offset);
static int parse_data_run(const void *stream, uint32_t *offset, uint8_t *attr_len, struct mapping_chunk *chunk);

/*** Function definitions */

/* Check if there are specific zero fields in an NTFS boot sector */
static inline int ntfs_check_zero_fields(const struct ntfs_bpb *sb)
{
    return !sb->res_sectors && (!sb->zero_0[0] && !sb->zero_0[1] &&
            !sb->zero_0[2]) && !sb->zero_1 && !sb->zero_2 &&
            !sb->zero_3;
}

static inline int ntfs_check_sb_fields(const struct ntfs_bpb *sb)
{
    return ntfs_check_zero_fields(sb) &&
            (!memcmp(sb->oem_name, "NTFS    ", 8) ||
             !memcmp(sb->oem_name, "MSWIN4.0", 8) ||
             !memcmp(sb->oem_name, "MSWIN4.1", 8));
}

static inline struct inode *new_ntfs_inode(struct fs_info *fs)
{
    struct inode *inode;

    inode = alloc_inode(fs, 0, sizeof(struct ntfs_inode));
    if (!inode)
        malloc_error("inode structure");

    return inode;
}

static void ntfs_fixups_writeback(struct fs_info *fs, struct ntfs_record *nrec)
{
    uint16_t *usa;
    uint16_t usa_no;
    uint16_t usa_count;
    uint16_t *blk;

    dprintf("in %s()\n", __func__);

    if (nrec->magic != NTFS_MAGIC_FILE && nrec->magic != NTFS_MAGIC_INDX)
        return;

    /* get the Update Sequence Array offset */
    usa = (uint16_t *)((uint8_t *)nrec + nrec->usa_ofs);
    /* get the Update Sequence Array Number and skip it */
    usa_no = *usa++;
    /* get the Update Sequene Array count */
    usa_count = nrec->usa_count - 1;    /* exclude the USA number */
    /* make it to point to the last two bytes of the RECORD's first sector */
    blk = (uint16_t *)((uint8_t *)nrec + SECTOR_SIZE(fs) - 2);

    while (usa_count--) {
        if (*blk != usa_no)
            break;

        *blk = *usa++;
        blk = (uint16_t *)((uint8_t *)blk + SECTOR_SIZE(fs));
    }
}

/* read content from cache */
static int ntfs_read(struct fs_info *fs, void *buf, size_t len, uint64_t count,
                    block_t *blk, uint64_t *blk_offset,
                    uint64_t *blk_next_offset, uint64_t *lcn)
{
    uint8_t *data;
    uint64_t offset = *blk_offset;
    const uint32_t clust_byte_shift = NTFS_SB(fs)->clust_byte_shift;
    const uint64_t blk_size = UINT64_C(1) << BLOCK_SHIFT(fs);
    uint64_t bytes;
    uint64_t lbytes;
    uint64_t loffset;
    uint64_t k;

    dprintf("in %s()\n", __func__);

    if (count > len)
        goto out;

    data = (uint8_t *)get_cache(fs->fs_dev, *blk);
    if (!data)
        goto out;

    if (!offset)
        offset = (*lcn << clust_byte_shift) % blk_size;

    dprintf("LCN:            0x%X\n", *lcn);
    dprintf("offset:         0x%X\n", offset);

    bytes = count;              /* bytes to copy */
    lbytes = blk_size - offset; /* bytes left to copy */
    if (lbytes >= bytes) {
        /* so there's room enough, then copy the whole content */
        memcpy(buf, data + offset, bytes);
        loffset = offset;
        offset += count;
    } else {
        dprintf("bytes:             %u\n", bytes);
        dprintf("bytes left:        %u\n", lbytes);
        /* otherwise, let's copy it partially... */
        k = 0;
        while (bytes) {
            memcpy(buf + k, data + offset, lbytes);
            bytes -= lbytes;
            loffset = offset;
            offset += lbytes;
            k += lbytes;
            if (offset >= blk_size) {
                /* then fetch a new FS block */
                data = (uint8_t *)get_cache(fs->fs_dev, ++*blk);
                if (!data)
                    goto out;

                lbytes = bytes;
                loffset = offset;
                offset = 0;
            }
        }
    }

    if (loffset >= blk_size)
        loffset = 0;    /* it must be aligned on a block boundary */

    *blk_offset = loffset;

    if (blk_next_offset)
        *blk_next_offset = offset;

    *lcn += blk_size / count;   /* update LCN */

    return 0;

out:
    return -1;
}

/* AndyAlex: read and validate single MFT record. Keep in mind that MFT itself can be fragmented */
static struct ntfs_mft_record *ntfs_mft_record_lookup_any(struct fs_info *fs,
                                                uint32_t file, block_t *out_blk, bool is_v31)
{
    const uint64_t mft_record_size = NTFS_SB(fs)->mft_record_size;
    uint8_t *buf = NULL;
    const uint32_t mft_record_shift = ilog2(mft_record_size);
    const uint32_t clust_byte_shift = NTFS_SB(fs)->clust_byte_shift;
    uint64_t next_offset = 0;
    uint64_t lcn = 0;
    block_t blk = 0;
    uint64_t offset = 0;

    struct ntfs_mft_record *mrec = NULL, *lmrec = NULL;
    uint64_t start_blk = 0;
    struct ntfs_attr_record *attr = NULL;
    uint8_t *stream = NULL;
    uint32_t attr_offset = 0;
    uint8_t *attr_len = NULL;
    struct mapping_chunk chunk;

    int err = 0;

    /* determine MFT record's LCN */
    uint64_t vcn = (file << mft_record_shift >> clust_byte_shift);
    dprintf("in %s(%s)\n", __func__,(is_v31?"v3.1":"v3.0"));
    if (0==vcn) {
      lcn = NTFS_SB(fs)->mft_lcn;
    } else do {
      dprintf("%s: looking for VCN %u for MFT record %u\n", __func__,(unsigned)vcn,(unsigned)file);
      mrec = NTFS_SB(fs)->mft_record_lookup(fs, 0, &start_blk);
      if (!mrec) {dprintf("%s: read MFT(0) failed\n", __func__); break;}
      lmrec = mrec;
      if (get_inode_mode(mrec) != DT_REG) {dprintf("%s: $MFT is not a file\n", __func__); break;}
      attr = ntfs_attr_lookup(fs, NTFS_AT_DATA, &mrec, lmrec);
      if (!attr) {dprintf("%s: $MFT have no data attr\n", __func__); break;}
      if (!attr->non_resident) {dprintf("%s: $MFT data attr is resident\n", __func__); break;}
      attr_len = (uint8_t *)attr + attr->len;
      stream = mapping_chunk_init(attr, &chunk, &attr_offset);
      while (true) {
        err = parse_data_run(stream, &attr_offset, attr_len, &chunk);
        if (err) {dprintf("%s: $MFT data run parse failed with error %d\n", __func__,err); break;}
        if (chunk.flags & MAP_UNALLOCATED) continue;
        if (chunk.flags & MAP_END) break;
        if (chunk.flags & MAP_ALLOCATED) {
          dprintf("%s: Chunk: VCN=%u, LCN=%u, len=%u\n", __func__,(unsigned)chunk.vcn,(unsigned)chunk.lcn,(unsigned)chunk.len);
          if ((vcn>=chunk.vcn)&&(vcn<chunk.vcn+chunk.len)) {
            lcn=vcn-chunk.vcn+chunk.lcn;
            dprintf("%s: VCN %u for MFT record %u maps to lcn %u\n", __func__,(unsigned)vcn,(unsigned)file,(unsigned)lcn);
            break;
          }
          chunk.vcn += chunk.len;
        }
      }
    } while(false);
    if (mrec!=NULL) free(mrec);
    mrec = NULL;
    if (0==lcn) {
      dprintf("%s: unable to map VCN %u for MFT record %u\n", __func__,(unsigned)vcn,(unsigned)file);
      return NULL;
    }

    /* determine MFT record's block number */
    blk = (lcn << clust_byte_shift >> BLOCK_SHIFT(fs));
    offset = (file << mft_record_shift) % BLOCK_SIZE(fs);

    /* Allocate buffer */
    buf = (uint8_t *)malloc(mft_record_size);
    if (!buf) {malloc_error("uint8_t *");return 0;}

    /* Read block */
    err = ntfs_read(fs, buf, mft_record_size, mft_record_size, &blk,
                    &offset, &next_offset, &lcn);
    if (err) {
      dprintf("%s: error read block %u from cache\n", __func__, blk);
      printf("Error while reading from cache.\n");
      free(buf);
      return NULL;
    }

    /* Process fixups and make structure pointer */
    ntfs_fixups_writeback(fs, (struct ntfs_record *)buf);
    mrec = (struct ntfs_mft_record *)buf;

    /* check if it has a valid magic number and record number */
    if (mrec->magic != NTFS_MAGIC_FILE) mrec = NULL;
    if (mrec && is_v31) if (mrec->mft_record_no != file) mrec = NULL;
    if (mrec!=NULL) {
      if (out_blk) {
        *out_blk = (file << mft_record_shift >> BLOCK_SHIFT(fs));   /* update record starting block */
      }
      return mrec;          /* found MFT record */
    }

    /* Invalid record */
    dprintf("%s: MFT record %u is invalid\n", __func__, (unsigned)file);
    free(buf);
    return NULL;
}

static struct ntfs_mft_record *ntfs_mft_record_lookup_3_0(struct fs_info *fs,
                                                uint32_t file, block_t *blk)
{
    return ntfs_mft_record_lookup_any(fs,file,blk,false);
}

static struct ntfs_mft_record *ntfs_mft_record_lookup_3_1(struct fs_info *fs,
                                                uint32_t file, block_t *blk)
{
    return ntfs_mft_record_lookup_any(fs,file,blk,true);
}

static bool ntfs_filename_cmp(const char *dname, struct ntfs_idx_entry *ie)
{
    const uint16_t *entry_fn;
    uint8_t entry_fn_len;
    unsigned i;

    dprintf("in %s()\n", __func__);

    entry_fn = ie->key.file_name.file_name;
    entry_fn_len = ie->key.file_name.file_name_len;

    if (strlen(dname) != entry_fn_len)
        return false;

    /* Do case-sensitive compares for Posix file names */
    if (ie->key.file_name.file_name_type == FILE_NAME_POSIX) {
        for (i = 0; i < entry_fn_len; i++)
            if (entry_fn[i] != dname[i])
                return false;
    } else {
        for (i = 0; i < entry_fn_len; i++)
            if (tolower(entry_fn[i]) != tolower(dname[i]))
                return false;
    }

    return true;
}

static inline uint8_t *mapping_chunk_init(struct ntfs_attr_record *attr,
                                        struct mapping_chunk *chunk,
                                        uint32_t *offset)
{
    memset(chunk, 0, sizeof *chunk);
    *offset = 0U;

    return (uint8_t *)attr + attr->data.non_resident.mapping_pairs_offset;
}

/* Parse data runs.
 *
 * return 0 on success or -1 on failure.
 */
static int parse_data_run(const void *stream, uint32_t *offset,
                            uint8_t *attr_len, struct mapping_chunk *chunk)
{
    uint8_t *buf;   /* Pointer to the zero-terminated byte stream */
    uint8_t count;  /* The count byte */
    uint8_t v, l;   /* v is the number of changed low-order VCN bytes;
                     * l is the number of changed low-order LCN bytes
                     */
    uint8_t *byte;
    const int byte_shift = 8;
    int mask;
    int64_t res;

    (void)attr_len;

    dprintf("in %s()\n", __func__);

    chunk->flags &= ~MAP_MASK;

    buf = (uint8_t *)stream + *offset;
    if (buf > attr_len || !*buf) {
        chunk->flags |= MAP_END;    /* we're done */
        return 0;
    }

    if (!*offset)
        chunk->flags |= MAP_START;  /* initial chunk */

    count = *buf;
    v = count & 0x0F;
    l = count >> 4;

    if (v > 8 || l > 8) /* more than 8 bytes ? */
        goto out;

    byte = (uint8_t *)buf + v;
    count = v;

    res = 0LL;
    while (count--)
	res = (res << byte_shift) | *byte--;

    chunk->len = res;   /* get length data */

    byte = (uint8_t *)buf + v + l;
    count = l;

    mask = 0xFFFFFFFF;
    res = 0LL;
    if (*byte & 0x80)
        res |= (int64_t)mask;   /* sign-extend it */

    while (count--)
        res = (res << byte_shift) | *byte--;

    chunk->lcn += res;
    /* are VCNS from cur_vcn to next_vcn - 1 unallocated ? */
    if (!chunk->lcn)
        chunk->flags |= MAP_UNALLOCATED;
    else
        chunk->flags |= MAP_ALLOCATED;

    *offset += v + l + 1;

    return 0;

out:
    return -1;
}

static struct ntfs_mft_record *
ntfs_attr_list_lookup(struct fs_info *fs, struct ntfs_attr_record *attr,
                      uint32_t type, struct ntfs_mft_record *mrec)
{
    uint8_t *attr_len;
    struct mapping_chunk chunk;
    uint32_t offset;
    uint8_t *stream;
    int err;
    const uint64_t blk_size = UINT64_C(1) << BLOCK_SHIFT(fs);
    uint8_t buf[blk_size];
    uint64_t blk_offset;
    int64_t vcn;
    int64_t lcn;
    int64_t last_lcn;
    block_t blk;
    struct ntfs_attr_list_entry *attr_entry;
    uint32_t len = 0;
    struct ntfs_mft_record *retval;
    uint64_t start_blk = 0;

    dprintf("in %s()\n", __func__);

    if (attr->non_resident)
        goto handle_non_resident_attr;

    attr_entry = (struct ntfs_attr_list_entry *)
        ((uint8_t *)attr + attr->data.resident.value_offset);
    len = attr->data.resident.value_len;
    for (; (uint8_t *)attr_entry < (uint8_t *)attr + len;
         attr_entry = (struct ntfs_attr_list_entry *)((uint8_t *)attr_entry +
                                                      attr_entry->length)) {
        dprintf("<$ATTRIBUTE_LIST> Attribute type: 0x%X\n",
                attr_entry->type);
        if (attr_entry->type == type)
            goto found; /* We got the attribute! :-) */
    }

    printf("No attribute found.\n");
    goto out;

handle_non_resident_attr:
    attr_len = (uint8_t *)attr + attr->len;
    stream = mapping_chunk_init(attr, &chunk, &offset);
    do {
        err = parse_data_run(stream, &offset, attr_len, &chunk);
        if (err) {
            printf("parse_data_run()\n");
            goto out;
        }

        if (chunk.flags & MAP_UNALLOCATED)
            continue;
        if (chunk.flags & MAP_END)
            break;
        if (chunk.flags & MAP_ALLOCATED) {
            vcn = 0;
            lcn = chunk.lcn;
            while (vcn < chunk.len) {
                blk = (lcn + vcn) << NTFS_SB(fs)->clust_byte_shift >>
                    BLOCK_SHIFT(fs);
                blk_offset = 0;
                last_lcn = lcn;
                lcn += vcn;
                err = ntfs_read(fs, buf, blk_size, blk_size, &blk,
                                &blk_offset, NULL, (uint64_t *)&lcn);
                if (err) {
                    printf("Error while reading from cache.\n");
                    goto out;
                }

                attr_entry = (struct ntfs_attr_list_entry *)&buf;
                len = attr->data.non_resident.data_size;
                for (; (uint8_t *)attr_entry < (uint8_t *)&buf[0] + len;
                     attr_entry = (struct ntfs_attr_list_entry *)
                         ((uint8_t *)attr_entry + attr_entry->length)) {
                    dprintf("<$ATTRIBUTE_LIST> Attribute type: 0x%x\n",
                            attr_entry->type);
                    if (attr_entry->type == type)
                        goto found; /* We got the attribute! :-) */
                }

                lcn = last_lcn; /* restore original LCN */
                /* go to the next VCN */
                vcn += (blk_size / (1 << NTFS_SB(fs)->clust_byte_shift));
            }
        }
    } while (!(chunk.flags & MAP_END));

    printf("No attribute found.\n");

out:
    return NULL;

found:
    /* At this point we have the attribute we were looking for. Now we
     * will look for the MFT record that stores information about this
     * attribute.
     */

    /* Check if the attribute type we're looking for is in the same
     * MFT record. If so, we do not need to look it up again - return it.
     */
    if (mrec->mft_record_no == attr_entry->mft_ref)
        return mrec;

    retval = NTFS_SB(fs)->mft_record_lookup(fs, attr_entry->mft_ref,
                                            &start_blk);
    if (!retval) {
        printf("No MFT record found!\n");
        goto out;
    }

    /* return the found MFT record */
    return retval;
}

static struct ntfs_attr_record *
__ntfs_attr_lookup(struct fs_info *fs, uint32_t type,
                   struct ntfs_mft_record **mrec)
{
    struct ntfs_mft_record *_mrec = *mrec;
    struct ntfs_attr_record *attr;
    struct ntfs_attr_record *attr_list_attr;

    dprintf("in %s()\n", __func__);

    if (!_mrec || type == NTFS_AT_END)
        goto out;

again:
    attr_list_attr = NULL;

    attr = (struct ntfs_attr_record *)((uint8_t *)_mrec + _mrec->attrs_offset);
    /* walk through the file attribute records */
    for (;; attr = (struct ntfs_attr_record *)((uint8_t *)attr + attr->len)) {
        if (attr->type == NTFS_AT_END)
            break;

        if (attr->type == NTFS_AT_ATTR_LIST) {
            dprintf("MFT record #%lu has an $ATTRIBUTE_LIST attribute.\n",
                    _mrec->mft_record_no);
            attr_list_attr = attr;
            continue;
        }

        if (attr->type == type)
            break;
    }

    /* if the record has an $ATTRIBUTE_LIST attribute associated
     * with it, then we need to look for the wanted attribute in
     * it as well.
     */
    if (attr->type == NTFS_AT_END && attr_list_attr) {
        struct ntfs_mft_record *retval;

        retval = ntfs_attr_list_lookup(fs, attr_list_attr, type, _mrec);
        if (!retval)
            goto out;

        _mrec = retval;
        goto again;
    } else if (attr->type == NTFS_AT_END && !attr_list_attr) {
        attr = NULL;
    }

    return attr;

out:
    return NULL;
}

static inline struct ntfs_attr_record *
ntfs_attr_lookup(struct fs_info *fs, uint32_t type,
                 struct ntfs_mft_record **mmrec,
                 struct ntfs_mft_record *mrec)
{
    struct ntfs_mft_record *_mrec = mrec;
    struct ntfs_mft_record *other = *mmrec;
    struct ntfs_attr_record *retval = NULL;

    if (mrec == other)
        return __ntfs_attr_lookup(fs, type, &other);

    retval = __ntfs_attr_lookup(fs, type, &_mrec);
    if (!retval) {
        _mrec = other;
        retval = __ntfs_attr_lookup(fs, type, &other);
        if (!retval)
            other = _mrec;
    } else if (retval && (_mrec != mrec)) {
        other = _mrec;
    }

    return retval;
}

static inline enum dirent_type get_inode_mode(struct ntfs_mft_record *mrec)
{
    return mrec->flags & MFT_RECORD_IS_DIRECTORY ? DT_DIR : DT_REG;
}

static int index_inode_setup(struct fs_info *fs, unsigned long mft_no,
                            struct inode *inode)
{
    uint64_t start_blk = 0;
    struct ntfs_mft_record *mrec, *lmrec;
    struct ntfs_attr_record *attr;
    enum dirent_type d_type;
    uint8_t *attr_len;
    struct mapping_chunk chunk;
    int err;
    uint8_t *stream;
    uint32_t offset;

    dprintf("in %s()\n", __func__);

    mrec = NTFS_SB(fs)->mft_record_lookup(fs, mft_no, &start_blk);
    if (!mrec) {
        printf("No MFT record found.\n");
        goto out;
    }

    lmrec = mrec;

    NTFS_PVT(inode)->mft_no = mft_no;
    NTFS_PVT(inode)->seq_no = mrec->seq_no;

    NTFS_PVT(inode)->start_cluster = start_blk >> NTFS_SB(fs)->clust_shift;
    NTFS_PVT(inode)->here = start_blk;

    d_type = get_inode_mode(mrec);
    if (d_type == DT_DIR) {    /* directory stuff */
        dprintf("Got a directory.\n");
        attr = ntfs_attr_lookup(fs, NTFS_AT_INDEX_ROOT, &mrec, lmrec);
        if (!attr) {
            printf("No attribute found.\n");
            goto out;
        }

        /* check if we have a previous allocated state structure */
        if (readdir_state) {
            free(readdir_state);
            readdir_state = NULL;
        }

        /* allocate our state structure */
        readdir_state = malloc(sizeof *readdir_state);
        if (!readdir_state)
            malloc_error("ntfs_readdir_state structure");

        readdir_state->mft_no = mft_no;
        /* obviously, the ntfs_readdir() caller will start from INDEX root */
        readdir_state->in_idx_root = true;
    } else if (d_type == DT_REG) {        /* file stuff */
        dprintf("Got a file.\n");
        attr = ntfs_attr_lookup(fs, NTFS_AT_DATA, &mrec, lmrec);
        if (!attr) {
            printf("No attribute found.\n");
            goto out;
        }

        NTFS_PVT(inode)->non_resident = attr->non_resident;
        NTFS_PVT(inode)->type = attr->type;

        if (!attr->non_resident) {
            NTFS_PVT(inode)->data.resident.offset =
                (uint32_t)((uint8_t *)attr + attr->data.resident.value_offset);
            inode->size = attr->data.resident.value_len;
        } else {
            attr_len = (uint8_t *)attr + attr->len;

            stream = mapping_chunk_init(attr, &chunk, &offset);
            NTFS_PVT(inode)->data.non_resident.rlist = NULL;
            for (;;) {
                err = parse_data_run(stream, &offset, attr_len, &chunk);
                if (err) {
                    printf("parse_data_run()\n");
                    goto out;
                }

                if (chunk.flags & MAP_UNALLOCATED)
                    continue;
                if (chunk.flags & MAP_END)
                    break;
                if (chunk.flags &  MAP_ALLOCATED) {
                    /* append new run to the runlist */
                    runlist_append(&NTFS_PVT(inode)->data.non_resident.rlist,
                                    (struct runlist_element *)&chunk);
                    /* update for next VCN */
                    chunk.vcn += chunk.len;
                }
            }

            if (runlist_is_empty(NTFS_PVT(inode)->data.non_resident.rlist)) {
                printf("No mapping found\n");
                goto out;
            }

            inode->size = attr->data.non_resident.initialized_size;
        }
    }

    inode->mode = d_type;

    free(mrec);

    return 0;

out:
    free(mrec);

    return -1;
}

static struct inode *ntfs_index_lookup(const char *dname, struct inode *dir)
{
    struct fs_info *fs = dir->fs;
    struct ntfs_mft_record *mrec, *lmrec;
    block_t blk;
    uint64_t blk_offset;
    struct ntfs_attr_record *attr;
    struct ntfs_idx_root *ir;
    struct ntfs_idx_entry *ie;
    const uint64_t blk_size = UINT64_C(1) << BLOCK_SHIFT(fs);
    uint8_t buf[blk_size];
    struct ntfs_idx_allocation *iblk;
    int err;
    uint8_t *stream;
    uint8_t *attr_len;
    struct mapping_chunk chunk;
    uint32_t offset;
    int64_t vcn;
    int64_t lcn;
    int64_t last_lcn;
    struct inode *inode;

    dprintf("in %s()\n", __func__);

    mrec = NTFS_SB(fs)->mft_record_lookup(fs, NTFS_PVT(dir)->mft_no, NULL);
    if (!mrec) {
        printf("No MFT record found.\n");
        goto out;
    }

    lmrec = mrec;
    attr = ntfs_attr_lookup(fs, NTFS_AT_INDEX_ROOT, &mrec, lmrec);
    if (!attr) {
        printf("No attribute found.\n");
        goto out;
    }

    ir = (struct ntfs_idx_root *)((uint8_t *)attr +
                            attr->data.resident.value_offset);
    ie = (struct ntfs_idx_entry *)((uint8_t *)&ir->index +
                                ir->index.entries_offset);
    for (;; ie = (struct ntfs_idx_entry *)((uint8_t *)ie + ie->len)) {
        /* bounds checks */
        if ((uint8_t *)ie < (uint8_t *)mrec ||
            (uint8_t *)ie + sizeof(struct ntfs_idx_entry_header) >
            (uint8_t *)&ir->index + ir->index.index_len ||
            (uint8_t *)ie + ie->len >
            (uint8_t *)&ir->index + ir->index.index_len)
            goto index_err;

        /* last entry cannot contain a key. it can however contain
         * a pointer to a child node in the B+ tree so we just break out
         */
        if (ie->flags & INDEX_ENTRY_END)
            break;

        if (ntfs_filename_cmp(dname, ie))
            goto found;
    }

    /* check for the presence of a child node */
    if (!(ie->flags & INDEX_ENTRY_NODE)) {
        printf("No child node, aborting...\n");
        goto out;
    }

    /* then descend into child node */

    attr = ntfs_attr_lookup(fs, NTFS_AT_INDEX_ALLOCATION, &mrec, lmrec);
    if (!attr) {
        printf("No attribute found.\n");
        goto out;
    }

    if (!attr->non_resident) {
        printf("WTF ?! $INDEX_ALLOCATION isn't really resident.\n");
        goto out;
    }

    attr_len = (uint8_t *)attr + attr->len;
    stream = mapping_chunk_init(attr, &chunk, &offset);
    do {
        err = parse_data_run(stream, &offset, attr_len, &chunk);
        if (err)
            break;

        if (chunk.flags & MAP_UNALLOCATED)
            continue;

        if (chunk.flags & MAP_ALLOCATED) {
            dprintf("%d cluster(s) starting at 0x%08llX\n", chunk.len,
                    chunk.lcn);

            vcn = 0;
            lcn = chunk.lcn;
            while (vcn < chunk.len) {
                blk = (lcn + vcn) << NTFS_SB(fs)->clust_shift <<
                    SECTOR_SHIFT(fs) >> BLOCK_SHIFT(fs);

                blk_offset = 0;
                last_lcn = lcn;
                lcn += vcn;
                err = ntfs_read(fs, &buf, blk_size, blk_size, &blk,
                                &blk_offset, NULL, (uint64_t *)&lcn);
                if (err) {
                    printf("Error while reading from cache.\n");
                    goto not_found;
                }

                ntfs_fixups_writeback(fs, (struct ntfs_record *)&buf);

                iblk = (struct ntfs_idx_allocation *)&buf;
                if (iblk->magic != NTFS_MAGIC_INDX) {
                    printf("Not a valid INDX record.\n");
                    goto not_found;
                }

                ie = (struct ntfs_idx_entry *)((uint8_t *)&iblk->index +
                                            iblk->index.entries_offset);
                for (;; ie = (struct ntfs_idx_entry *)((uint8_t *)ie +
                        ie->len)) {
                    /* bounds checks */
                    if ((uint8_t *)ie < (uint8_t *)iblk || (uint8_t *)ie +
                        sizeof(struct ntfs_idx_entry_header) >
                        (uint8_t *)&iblk->index + iblk->index.index_len ||
                        (uint8_t *)ie + ie->len >
                        (uint8_t *)&iblk->index + iblk->index.index_len)
                        goto index_err;

                    /* last entry cannot contain a key */
                    if (ie->flags & INDEX_ENTRY_END)
                        break;

                    if (ntfs_filename_cmp(dname, ie))
                        goto found;
                }

                lcn = last_lcn; /* restore the original LCN */
                /* go to the next VCN */
                vcn += (blk_size / (1 << NTFS_SB(fs)->clust_byte_shift));
            }
        }
    } while (!(chunk.flags & MAP_END));

not_found:
    dprintf("Index not found\n");

out:
    free(mrec);

    return NULL;

found:
    dprintf("Index found\n");
    inode = new_ntfs_inode(fs);
    err = index_inode_setup(fs, ie->data.dir.indexed_file, inode);
    if (err) {
        printf("Error in index_inode_setup()\n");
        free(inode);
        goto out;
    }

    free(mrec);

    return inode;

index_err:
    printf("Corrupt index. Aborting lookup...\n");
    goto out;
}

/* Convert an UTF-16LE LFN to OEM LFN */
static uint8_t ntfs_cvt_filename(char *filename,
                                const struct ntfs_idx_entry *ie)
{
    const uint16_t *entry_fn;
    uint8_t entry_fn_len;
    unsigned i;

    entry_fn = ie->key.file_name.file_name;
    entry_fn_len = ie->key.file_name.file_name_len;

    for (i = 0; i < entry_fn_len; i++)
        filename[i] = (char)entry_fn[i];

    filename[i] = '\0';

    return entry_fn_len;
}

static int ntfs_next_extent(struct inode *inode, uint32_t lstart)
{
    struct fs_info *fs = inode->fs;
    struct ntfs_sb_info *sbi = NTFS_SB(fs);
    sector_t pstart = 0;
    struct runlist *rlist;
    struct runlist *ret;
    const uint32_t sec_size = SECTOR_SIZE(fs);
    const uint32_t sec_shift = SECTOR_SHIFT(fs);

    dprintf("in %s()\n", __func__);

    if (!NTFS_PVT(inode)->non_resident) {
        pstart = (sbi->mft_blk + NTFS_PVT(inode)->here) << BLOCK_SHIFT(fs) >>
                sec_shift;
        inode->next_extent.len = (inode->size + sec_size - 1) >> sec_shift;
    } else {
        rlist = NTFS_PVT(inode)->data.non_resident.rlist;

        if (!lstart || lstart >= NTFS_PVT(inode)->here) {
            if (runlist_is_empty(rlist))
                goto out;   /* nothing to do ;-) */

            ret = runlist_remove(&rlist);

            NTFS_PVT(inode)->here =
                ((ret->run.len << sbi->clust_byte_shift) >> sec_shift);

            pstart = ret->run.lcn << sbi->clust_shift;
            inode->next_extent.len =
                ((ret->run.len << sbi->clust_byte_shift) + sec_size - 1) >>
                sec_shift;

            NTFS_PVT(inode)->data.non_resident.rlist = rlist;

            free(ret);
            ret = NULL;
        }
    }

    inode->next_extent.pstart = pstart;

    return 0;

out:
    return -1;
}

static uint32_t ntfs_getfssec(struct file *file, char *buf, int sectors,
                                bool *have_more)
{
    uint8_t non_resident;
    uint32_t ret;
    struct fs_info *fs = file->fs;
    struct inode *inode = file->inode;
    struct ntfs_mft_record *mrec, *lmrec;
    struct ntfs_attr_record *attr;
    char *p;

    dprintf("in %s()\n", __func__);

    non_resident = NTFS_PVT(inode)->non_resident;

    ret = generic_getfssec(file, buf, sectors, have_more);
    if (!ret)
        return ret;

    if (!non_resident) {
        mrec = NTFS_SB(fs)->mft_record_lookup(fs, NTFS_PVT(inode)->mft_no,
                                              NULL);
        if (!mrec) {
            printf("No MFT record found.\n");
            goto out;
        }

        lmrec = mrec;
        attr = ntfs_attr_lookup(fs, NTFS_AT_DATA, &mrec, lmrec);
        if (!attr) {
            printf("No attribute found.\n");
            goto out;
        }

        p = (char *)((uint8_t *)attr + attr->data.resident.value_offset);

        /* p now points to the data offset, so let's copy it into buf */
        memcpy(buf, p, inode->size);

        ret = inode->size;

        free(mrec);
    }

    return ret;

out:
    free(mrec);

    return 0;
}

static inline bool is_filename_printable(const char *s)
{
    return s && (*s != '.' && *s != '$');
}

static int ntfs_readdir(struct file *file, struct dirent *dirent)
{
    struct fs_info *fs = file->fs;
    struct inode *inode = file->inode;
    struct ntfs_mft_record *mrec, *lmrec;
    block_t blk;
    uint64_t blk_offset;
    const uint64_t blk_size = UINT64_C(1) << BLOCK_SHIFT(fs);
    struct ntfs_attr_record *attr;
    struct ntfs_idx_root *ir;
    uint32_t count;
    int len;
    struct ntfs_idx_entry *ie = NULL;
    uint8_t buf[BLOCK_SIZE(fs)];
    struct ntfs_idx_allocation *iblk;
    int err;
    uint8_t *stream;
    uint8_t *attr_len;
    struct mapping_chunk chunk;
    uint32_t offset;
    int64_t vcn;
    int64_t lcn;
    char filename[NTFS_MAX_FILE_NAME_LEN + 1];

    dprintf("in %s()\n", __func__);

    mrec = NTFS_SB(fs)->mft_record_lookup(fs, NTFS_PVT(inode)->mft_no, NULL);
    if (!mrec) {
        printf("No MFT record found.\n");
        goto out;
    }

    lmrec = mrec;
    attr = ntfs_attr_lookup(fs, NTFS_AT_INDEX_ROOT, &mrec, lmrec);
    if (!attr) {
        printf("No attribute found.\n");
        goto out;
    }

    ir = (struct ntfs_idx_root *)((uint8_t *)attr +
                            attr->data.resident.value_offset);

    if (!file->offset && readdir_state->in_idx_root)
        file->offset = ir->index.entries_offset;

idx_root_next_entry:
    if (readdir_state->in_idx_root) {
        ie = (struct ntfs_idx_entry *)((uint8_t *)&ir->index + file->offset);
        if (ie->flags & INDEX_ENTRY_END) {
            file->offset = 0;
            readdir_state->in_idx_root = false;
            readdir_state->idx_blks_count = 1;
            readdir_state->entries_count = 0;
            readdir_state->last_vcn = 0;
            goto descend_into_child_node;
        }

        file->offset += ie->len;
        len = ntfs_cvt_filename(filename, ie);
        if (!is_filename_printable(filename))
            goto idx_root_next_entry;

        goto done;
    }

descend_into_child_node:
    if (!(ie->flags & INDEX_ENTRY_NODE))
        goto out;

    attr = ntfs_attr_lookup(fs, NTFS_AT_INDEX_ALLOCATION, &mrec, lmrec);
    if (!attr)
        goto out;

    if (!attr->non_resident) {
        printf("WTF ?! $INDEX_ALLOCATION isn't really resident.\n");
        goto out;
    }

    attr_len = (uint8_t *)attr + attr->len;

next_run:
    stream = mapping_chunk_init(attr, &chunk, &offset);
    count = readdir_state->idx_blks_count;
    while (count--) {
        err = parse_data_run(stream, &offset, attr_len, &chunk);
        if (err) {
            printf("Error while parsing data runs.\n");
            goto out;
        }

        if (chunk.flags & MAP_UNALLOCATED)
            break;
        if (chunk.flags & MAP_END)
            goto out;
    }

    if (chunk.flags & MAP_UNALLOCATED) {
       readdir_state->idx_blks_count++;
       goto next_run;
    }

next_vcn:
    vcn = readdir_state->last_vcn;
    if (vcn >= chunk.len) {
        readdir_state->last_vcn = 0;
        readdir_state->idx_blks_count++;
        goto next_run;
    }

    lcn = chunk.lcn;
    blk = (lcn + vcn) << NTFS_SB(fs)->clust_shift << SECTOR_SHIFT(fs) >>
            BLOCK_SHIFT(fs);

    blk_offset = 0;
    err = ntfs_read(fs, &buf, blk_size, blk_size, &blk, &blk_offset, NULL,
                    (uint64_t *)&lcn);
    if (err) {
        printf("Error while reading from cache.\n");
        goto not_found;
    }

    ntfs_fixups_writeback(fs, (struct ntfs_record *)&buf);

    iblk = (struct ntfs_idx_allocation *)&buf;
    if (iblk->magic != NTFS_MAGIC_INDX) {
        printf("Not a valid INDX record.\n");
        goto not_found;
    }

idx_block_next_entry:
    ie = (struct ntfs_idx_entry *)((uint8_t *)&iblk->index +
                        iblk->index.entries_offset);
    count = readdir_state->entries_count;
    for ( ; count--; ie = (struct ntfs_idx_entry *)((uint8_t *)ie + ie->len)) {
        /* bounds checks */
        if ((uint8_t *)ie < (uint8_t *)iblk || (uint8_t *)ie +
            sizeof(struct ntfs_idx_entry_header) >
            (uint8_t *)&iblk->index + iblk->index.index_len ||
            (uint8_t *)ie + ie->len >
            (uint8_t *)&iblk->index + iblk->index.index_len)
            goto index_err;

        /* last entry cannot contain a key */
        if (ie->flags & INDEX_ENTRY_END) {
            /* go to the next VCN */
            readdir_state->last_vcn += (blk_size / (1 <<
                                NTFS_SB(fs)->clust_byte_shift));
            readdir_state->entries_count = 0;
            goto next_vcn;
        }
    }

    readdir_state->entries_count++;

    /* Need to check if this entry has INDEX_ENTRY_END flag set. If
     * so, then it won't contain a indexed_file file, so continue the
     * lookup on the next VCN/LCN (if any).
     */
    if (ie->flags & INDEX_ENTRY_END)
        goto next_vcn;

    len = ntfs_cvt_filename(filename, ie);
    if (!is_filename_printable(filename))
        goto idx_block_next_entry;

    goto done;

out:
    readdir_state->in_idx_root = true;

    free(mrec);

    return -1;

done:
    dirent->d_ino = ie->data.dir.indexed_file;
    dirent->d_off = file->offset;
    dirent->d_reclen = offsetof(struct dirent, d_name) + len + 1;

    free(mrec);

    mrec = NTFS_SB(fs)->mft_record_lookup(fs, ie->data.dir.indexed_file, NULL);
    if (!mrec) {
        printf("No MFT record found.\n");
        goto out;
    }

    dirent->d_type = get_inode_mode(mrec);
    memcpy(dirent->d_name, filename, len + 1);

    free(mrec);

    return 0;

not_found:
    printf("Index not found\n");
    goto out;

index_err:
    printf("Corrupt index. Aborting lookup...\n");
    goto out;
}

static inline struct inode *ntfs_iget(const char *dname, struct inode *parent)
{
    return ntfs_index_lookup(dname, parent);
}

static struct inode *ntfs_iget_root(struct fs_info *fs)
{
    uint64_t start_blk;
    struct ntfs_mft_record *mrec, *lmrec;
    struct ntfs_attr_record *attr;
    struct ntfs_vol_info *vol_info;
    struct inode *inode;
    int err;

    dprintf("in %s()\n", __func__);

    /* Fetch the $Volume MFT record */
    start_blk = 0;
    mrec = NTFS_SB(fs)->mft_record_lookup(fs, FILE_Volume, &start_blk);
    if (!mrec) {
        printf("Could not fetch $Volume MFT record!\n");
        goto err_mrec;
    }

    lmrec = mrec;

    /* Fetch the volume information attribute */
    attr = ntfs_attr_lookup(fs, NTFS_AT_VOL_INFO, &mrec, lmrec);
    if (!attr) {
        printf("Could not find volume info attribute!\n");
        goto err_attr;
    }

    /* Note NTFS version and choose version-dependent functions */
    vol_info = (void *)((char *)attr + attr->data.resident.value_offset);
    NTFS_SB(fs)->major_ver = vol_info->major_ver;
    NTFS_SB(fs)->minor_ver = vol_info->minor_ver;
    if (vol_info->major_ver == 3 && vol_info->minor_ver == 0)
        NTFS_SB(fs)->mft_record_lookup = ntfs_mft_record_lookup_3_0;
    else if (vol_info->major_ver == 3 && vol_info->minor_ver == 1 &&
            mrec->mft_record_no == FILE_Volume)
        NTFS_SB(fs)->mft_record_lookup = ntfs_mft_record_lookup_3_1;

    /* Free MFT record */
    free(mrec);
    mrec = NULL;

    inode = new_ntfs_inode(fs);
    inode->fs = fs;

    err = index_inode_setup(fs, FILE_root, inode);
    if (err)
        goto err_setup;

    NTFS_PVT(inode)->start = NTFS_PVT(inode)->here;

    return inode;

err_setup:

    free(inode);
err_attr:

    free(mrec);
err_mrec:

    return NULL;
}

/* Initialize the filesystem metadata and return blk size in bits */
static int ntfs_fs_init(struct fs_info *fs)
{
    int read_count;
    struct ntfs_bpb ntfs;
    struct ntfs_sb_info *sbi;
    struct disk *disk = fs->fs_dev->disk;
    uint8_t mft_record_shift;

    dprintf("in %s()\n", __func__);

    read_count = disk->rdwr_sectors(disk, &ntfs, 0, 1, 0);
    if (!read_count)
        return -1;

    if (!ntfs_check_sb_fields(&ntfs))
        return -1;

    SECTOR_SHIFT(fs) = disk->sector_shift;

    /* Note: ntfs.clust_per_mft_record can be a negative number.
     * If negative, it represents a shift count, else it represents
     * a multiplier for the cluster size.
     */
    mft_record_shift = ntfs.clust_per_mft_record < 0 ?
                    -ntfs.clust_per_mft_record :
                    ilog2(ntfs.sec_per_clust) + SECTOR_SHIFT(fs) +
                    ilog2(ntfs.clust_per_mft_record);

    SECTOR_SIZE(fs) = 1 << SECTOR_SHIFT(fs);

    sbi = malloc(sizeof *sbi);
    if (!sbi)
        malloc_error("ntfs_sb_info structure");

    fs->fs_info = sbi;

    sbi->clust_shift            = ilog2(ntfs.sec_per_clust);
    sbi->clust_byte_shift       = sbi->clust_shift + SECTOR_SHIFT(fs);
    sbi->clust_mask             = ntfs.sec_per_clust - 1;
    sbi->clust_size             = ntfs.sec_per_clust << SECTOR_SHIFT(fs);
    sbi->mft_record_size        = 1 << mft_record_shift;
    sbi->clust_per_idx_record   = ntfs.clust_per_idx_record;

    BLOCK_SHIFT(fs) = ilog2(ntfs.clust_per_idx_record) + sbi->clust_byte_shift;
    BLOCK_SIZE(fs) = 1 << BLOCK_SHIFT(fs);

    sbi->mft_lcn = ntfs.mft_lclust;
    sbi->mft_blk = ntfs.mft_lclust << sbi->clust_shift << SECTOR_SHIFT(fs) >>
                BLOCK_SHIFT(fs);
    /* 16 MFT entries reserved for metadata files (approximately 16 KiB) */
    sbi->mft_size = mft_record_shift << sbi->clust_shift << 4;

    sbi->clusters = ntfs.total_sectors << SECTOR_SHIFT(fs) >> sbi->clust_shift;
    if (sbi->clusters > 0xFFFFFFFFFFF4ULL)
        sbi->clusters = 0xFFFFFFFFFFF4ULL;

    /*
     * Assume NTFS version 3.0 to begin with. If we find that the
     * volume is a different version later on, we will adjust at
     * that time.
     */
    sbi->major_ver = 3;
    sbi->minor_ver = 0;
    sbi->mft_record_lookup = ntfs_mft_record_lookup_3_0;

    /* Initialize the cache */
    cache_init(fs->fs_dev, BLOCK_SHIFT(fs));

    return BLOCK_SHIFT(fs);
}

const struct fs_ops ntfs_fs_ops = {
    .fs_name        = "ntfs",
    .fs_flags       = FS_USEMEM | FS_THISIND,
    .fs_init        = ntfs_fs_init,
    .searchdir      = NULL,
    .getfssec       = ntfs_getfssec,
    .close_file     = generic_close_file,
    .mangle_name    = generic_mangle_name,
    .open_config    = generic_open_config,
    .readdir        = ntfs_readdir,
    .iget_root      = ntfs_iget_root,
    .iget           = ntfs_iget,
    .next_extent    = ntfs_next_extent,
    .fs_uuid        = NULL,
};
