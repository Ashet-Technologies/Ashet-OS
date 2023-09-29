/*
 * Copyright (c) 2012-2013 Paulo Alcantara <pcacjr@zytor.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it would be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write the Free Software Foundation,
 * Inc.,  51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include <cache.h>
#include <core.h>
#include <fs.h>

#include "xfs_types.h"
#include "xfs_sb.h"
#include "xfs_ag.h"
#include "misc.h"
#include "xfs.h"
#include "xfs_dinode.h"
#include "xfs_dir2.h"

#include "xfs_readdir.h"

static int fill_dirent(struct fs_info *fs, struct dirent *dirent,
		       uint32_t offset, xfs_ino_t ino, char *name,
		       size_t namelen)
{
    xfs_dinode_t *core;

    xfs_debug("fs %p, dirent %p offset %lu ino %llu name %s namelen %llu", fs,
	      dirent, offset, ino, name, namelen);

    dirent->d_ino = ino;
    dirent->d_off = offset;
    dirent->d_reclen = offsetof(struct dirent, d_name) + namelen + 1;

    core = xfs_dinode_get_core(fs, ino);
    if (!core) {
        xfs_error("Failed to get dinode from disk (ino 0x%llx)", ino);
        return -1;
    }

    if (be16_to_cpu(core->di_mode) & S_IFDIR)
	dirent->d_type = DT_DIR;
    else if (be16_to_cpu(core->di_mode) & S_IFREG)
	dirent->d_type = DT_REG;
    else if (be16_to_cpu(core->di_mode) & S_IFLNK)
        dirent->d_type = DT_LNK;

    memcpy(dirent->d_name, name, namelen);
    dirent->d_name[namelen] = '\0';

    return 0;
}

int xfs_readdir_dir2_local(struct file *file, struct dirent *dirent,
			   xfs_dinode_t *core)
{
    xfs_dir2_sf_t *sf = (xfs_dir2_sf_t *)&core->di_literal_area[0];
    xfs_dir2_sf_entry_t *sf_entry;
    uint8_t count = sf->hdr.i8count ? sf->hdr.i8count : sf->hdr.count;
    uint32_t offset = file->offset;
    uint8_t *start_name;
    uint8_t *end_name;
    xfs_ino_t ino;
    struct fs_info *fs = file->fs;
    int retval = 0;

    xfs_debug("file %p dirent %p core %p", file, dirent, core);
    xfs_debug("count %hhu i8count %hhu", sf->hdr.count, sf->hdr.i8count);

    if (file->offset + 1 > count)
	goto out;

    file->offset++;

    sf_entry = (xfs_dir2_sf_entry_t *)((uint8_t *)&sf->list[0] -
				       (!sf->hdr.i8count ? 4 : 0));

    if (file->offset - 1) {
	offset = file->offset;
	while (--offset) {
	    sf_entry = (xfs_dir2_sf_entry_t *)(
				(uint8_t *)sf_entry +
				offsetof(struct xfs_dir2_sf_entry,
					 name[0]) +
				sf_entry->namelen +
				(sf->hdr.i8count ? 8 : 4));
	}
    }

    start_name = &sf_entry->name[0];
    end_name = start_name + sf_entry->namelen;

    ino = xfs_dir2_sf_get_inumber(sf, (xfs_dir2_inou_t *)(
				      (uint8_t *)sf_entry +
				      offsetof(struct xfs_dir2_sf_entry,
					       name[0]) +
				      sf_entry->namelen));

    retval = fill_dirent(fs, dirent, file->offset, ino, (char *)start_name,
			 end_name - start_name);
    if (retval)
	xfs_error("Failed to fill in dirent structure");

    return retval;

out:
    xfs_dir2_dirblks_flush_cache();

    return -1;
}

int xfs_readdir_dir2_block(struct file *file, struct dirent *dirent,
			   xfs_dinode_t *core)
{
    xfs_bmbt_irec_t r;
    block_t dir_blk;
    struct fs_info *fs = file->fs;
    const uint8_t *dirblk_buf;
    uint8_t *p;
    uint32_t offset;
    xfs_dir2_data_hdr_t *hdr;
    xfs_dir2_block_tail_t *btp;
    xfs_dir2_data_unused_t *dup;
    xfs_dir2_data_entry_t *dep;
    uint8_t *start_name;
    uint8_t *end_name;
    xfs_ino_t ino;
    int retval = 0;

    xfs_debug("file %p dirent %p core %p", file, dirent, core);

    bmbt_irec_get(&r, (xfs_bmbt_rec_t *)&core->di_literal_area[0]);
    dir_blk = fsblock_to_bytes(fs, r.br_startblock) >> BLOCK_SHIFT(fs);

    dirblk_buf = xfs_dir2_dirblks_get_cached(fs, dir_blk, r.br_blockcount);
    hdr = (xfs_dir2_data_hdr_t *)dirblk_buf;
    if (be32_to_cpu(hdr->magic) != XFS_DIR2_BLOCK_MAGIC) {
        xfs_error("Block directory header's magic number does not match!");
        xfs_debug("hdr->magic: 0x%lx", be32_to_cpu(hdr->magic));
	goto out;
    }

    btp = xfs_dir2_block_tail_p(XFS_INFO(fs), hdr);

    if (file->offset + 1 > be32_to_cpu(btp->count))
	goto out;

    file->offset++;

    p = (uint8_t *)(hdr + 1);

    if (file->offset - 1) {
	offset = file->offset;
	while (--offset) {
	    dep = (xfs_dir2_data_entry_t *)p;

	    dup = (xfs_dir2_data_unused_t *)p;
	    if (be16_to_cpu(dup->freetag) == XFS_DIR2_DATA_FREE_TAG) {
		p += be16_to_cpu(dup->length);
		continue;
	    }

	    p += xfs_dir2_data_entsize(dep->namelen);
	}
    }

    dep = (xfs_dir2_data_entry_t *)p;

    start_name = &dep->name[0];
    end_name = start_name + dep->namelen;

    ino = be64_to_cpu(dep->inumber);

    retval = fill_dirent(fs, dirent, file->offset, ino, (char *)start_name,
			 end_name - start_name);
    if (retval)
	xfs_error("Failed to fill in dirent structure");

    return retval;

out:
    xfs_dir2_dirblks_flush_cache();

    return -1;
}

int xfs_readdir_dir2_leaf(struct file *file, struct dirent *dirent,
			  xfs_dinode_t *core)
{
    xfs_bmbt_irec_t irec;
    struct fs_info *fs = file->fs;
    xfs_dir2_leaf_t *leaf;
    block_t leaf_blk, dir_blk;
    xfs_dir2_leaf_entry_t *lep;
    uint32_t db;
    unsigned int offset;
    xfs_dir2_data_entry_t *dep;
    xfs_dir2_data_hdr_t *data_hdr;
    uint8_t *start_name;
    uint8_t *end_name;
    xfs_intino_t ino;
    const uint8_t *buf = NULL;
    int retval = 0;

    xfs_debug("file %p dirent %p core %p", file, dirent, core);

    bmbt_irec_get(&irec, ((xfs_bmbt_rec_t *)&core->di_literal_area[0]) +
					be32_to_cpu(core->di_nextents) - 1);
    leaf_blk = fsblock_to_bytes(fs, irec.br_startblock) >>
					BLOCK_SHIFT(file->fs);

    leaf = (xfs_dir2_leaf_t *)xfs_dir2_dirblks_get_cached(fs, leaf_blk,
							  irec.br_blockcount);
    if (be16_to_cpu(leaf->hdr.info.magic) != XFS_DIR2_LEAF1_MAGIC) {
        xfs_error("Single leaf block header's magic number does not match!");
        goto out;
    }

    if (!leaf->hdr.count)
        goto out;

    if (file->offset + 1 > be16_to_cpu(leaf->hdr.count))
	goto out;

    lep = &leaf->ents[file->offset++];

    /* Skip over stale leaf entries */
    for ( ; be32_to_cpu(lep->address) == XFS_DIR2_NULL_DATAPTR;
	  lep++, file->offset++);

    db = xfs_dir2_dataptr_to_db(fs, be32_to_cpu(lep->address));

    bmbt_irec_get(&irec, (xfs_bmbt_rec_t *)&core->di_literal_area[0] + db);

    dir_blk = fsblock_to_bytes(fs, irec.br_startblock) >> BLOCK_SHIFT(fs);

    buf = xfs_dir2_dirblks_get_cached(fs, dir_blk, irec.br_blockcount);
    data_hdr = (xfs_dir2_data_hdr_t *)buf;
    if (be32_to_cpu(data_hdr->magic) != XFS_DIR2_DATA_MAGIC) {
	xfs_error("Leaf directory's data magic number does not match!");
	goto out;
    }

    offset = xfs_dir2_dataptr_to_off(fs, be32_to_cpu(lep->address));

    dep = (xfs_dir2_data_entry_t *)((uint8_t *)buf + offset);

    start_name = &dep->name[0];
    end_name = start_name + dep->namelen;

    ino = be64_to_cpu(dep->inumber);

    retval = fill_dirent(fs, dirent, file->offset, ino, (char *)start_name,
			 end_name - start_name);
    if (retval)
	xfs_error("Failed to fill in dirent structure");

    return retval;

out:
    xfs_dir2_dirblks_flush_cache();

    return -1;
}

int xfs_readdir_dir2_node(struct file *file, struct dirent *dirent,
			  xfs_dinode_t *core)
{
    struct fs_info *fs = file->fs;
    xfs_bmbt_irec_t irec;
    uint32_t node_off = 0;
    block_t fsblkno;
    xfs_da_intnode_t *node = NULL;
    struct inode *inode = file->inode;
    int error;
    xfs_dir2_data_hdr_t *data_hdr;
    xfs_dir2_leaf_t *leaf;
    xfs_dir2_leaf_entry_t *lep;
    unsigned int offset;
    xfs_dir2_data_entry_t *dep;
    uint8_t *start_name;
    uint8_t *end_name;
    uint32_t db;
    const uint8_t *buf = NULL;
    int retval = 0;

    xfs_debug("file %p dirent %p core %p", file, dirent, core);

    do {
        bmbt_irec_get(&irec, (xfs_bmbt_rec_t *)&core->di_literal_area[0] +
								++node_off);
    } while (irec.br_startoff < xfs_dir2_byte_to_db(fs, XFS_DIR2_LEAF_OFFSET));

    fsblkno = fsblock_to_bytes(fs, irec.br_startblock) >> BLOCK_SHIFT(fs);

    node = (xfs_da_intnode_t *)xfs_dir2_dirblks_get_cached(fs, fsblkno, 1);
    if (be16_to_cpu(node->hdr.info.magic) != XFS_DA_NODE_MAGIC) {
        xfs_error("Node's magic number does not match!");
        goto out;
    }

try_next_btree:
    if (!node->hdr.count ||
	XFS_PVT(inode)->i_btree_offset >= be16_to_cpu(node->hdr.count))
	goto out;

    fsblkno = be32_to_cpu(node->btree[XFS_PVT(inode)->i_btree_offset].before);
    fsblkno = xfs_dir2_get_right_blk(fs, core, fsblkno, &error);
    if (error) {
        xfs_error("Cannot find leaf rec!");
        goto out;
    }

    leaf = (xfs_dir2_leaf_t*)xfs_dir2_dirblks_get_cached(fs, fsblkno, 1);
    if (be16_to_cpu(leaf->hdr.info.magic) != XFS_DIR2_LEAFN_MAGIC) {
        xfs_error("Leaf's magic number does not match!");
        goto out;
    }

    if (!leaf->hdr.count ||
	XFS_PVT(inode)->i_leaf_ent_offset >= be16_to_cpu(leaf->hdr.count)) {
	XFS_PVT(inode)->i_btree_offset++;
	XFS_PVT(inode)->i_leaf_ent_offset = 0;
	goto try_next_btree;
    }

    lep = &leaf->ents[XFS_PVT(inode)->i_leaf_ent_offset];

    /* Skip over stale leaf entries */
    for ( ; XFS_PVT(inode)->i_leaf_ent_offset < be16_to_cpu(leaf->hdr.count) &&
			be32_to_cpu(lep->address) == XFS_DIR2_NULL_DATAPTR;
	  lep++, XFS_PVT(inode)->i_leaf_ent_offset++);

    if (XFS_PVT(inode)->i_leaf_ent_offset == be16_to_cpu(leaf->hdr.count)) {
	XFS_PVT(inode)->i_btree_offset++;
	XFS_PVT(inode)->i_leaf_ent_offset = 0;
	goto try_next_btree;
    } else {
	XFS_PVT(inode)->i_leaf_ent_offset++;
    }

    db = xfs_dir2_dataptr_to_db(fs, be32_to_cpu(lep->address));

    fsblkno = xfs_dir2_get_right_blk(fs, core, db, &error);
    if (error) {
	xfs_error("Cannot find data block!");
	goto out;
    }

    buf = xfs_dir2_dirblks_get_cached(fs, fsblkno, 1);
    data_hdr = (xfs_dir2_data_hdr_t *)buf;
    if (be32_to_cpu(data_hdr->magic) != XFS_DIR2_DATA_MAGIC) {
	xfs_error("Leaf directory's data magic No. does not match!");
	goto out;
    }

    offset = xfs_dir2_dataptr_to_off(fs, be32_to_cpu(lep->address));

    dep = (xfs_dir2_data_entry_t *)((uint8_t *)buf + offset);

    start_name = &dep->name[0];
    end_name = start_name + dep->namelen;

    retval = fill_dirent(fs, dirent, 0, be64_to_cpu(dep->inumber),
			 (char *)start_name, end_name - start_name);
    if (retval)
	xfs_error("Failed to fill in dirent structure");

    return retval;

out:
    xfs_dir2_dirblks_flush_cache();

    XFS_PVT(inode)->i_btree_offset = 0;
    XFS_PVT(inode)->i_leaf_ent_offset = 0;

    return -1;
}
