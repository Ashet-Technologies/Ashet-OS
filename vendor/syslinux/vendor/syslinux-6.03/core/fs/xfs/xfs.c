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
#include "xfs_types.h"
#include "xfs_sb.h"
#include "xfs_ag.h"
#include "misc.h"
#include "xfs.h"
#include "xfs_dinode.h"
#include "xfs_dir2.h"
#include "xfs_readdir.h"

static inline int xfs_fmt_local_readdir(struct file *file,
					struct dirent *dirent,
					xfs_dinode_t *core)
{
    return xfs_readdir_dir2_local(file, dirent, core);
}

static inline int xfs_fmt_extents_readdir(struct file *file,
					  struct dirent *dirent,
					  xfs_dinode_t *core)
{
    if (be32_to_cpu(core->di_nextents) <= 1) {
	/* Single-block Directories */
	return xfs_readdir_dir2_block(file, dirent, core);
    } else if (xfs_dir2_isleaf(file->fs, core)) {
	/* Leaf Directory */
	return xfs_readdir_dir2_leaf(file, dirent, core);
    } else {
	/* Node Directory */
	return xfs_readdir_dir2_node(file, dirent, core);
    }
}

static int xfs_readdir(struct file *file, struct dirent *dirent)
{
    struct fs_info *fs = file->fs;
    xfs_dinode_t *core;
    struct inode *inode = file->inode;

    xfs_debug("file %p dirent %p");

    core = xfs_dinode_get_core(fs, inode->ino);
    if (!core) {
	xfs_error("Failed to get dinode from disk (ino %llx)", inode->ino);
	return -1;
    }

    if (core->di_format == XFS_DINODE_FMT_LOCAL)
	return xfs_fmt_local_readdir(file, dirent, core);
    else if (core->di_format == XFS_DINODE_FMT_EXTENTS)
	return xfs_fmt_extents_readdir(file, dirent, core);

    return -1;
}

static uint32_t xfs_getfssec(struct file *file, char *buf, int sectors,
			     bool *have_more)
{
    return generic_getfssec(file, buf, sectors, have_more);
}

static int xfs_next_extent(struct inode *inode, uint32_t lstart)
{
    struct fs_info *fs = inode->fs;
    xfs_dinode_t *core = NULL;
    xfs_bmbt_irec_t rec;
    block_t bno;
    xfs_bmdr_block_t *rblock;
    int fsize;
    xfs_bmbt_ptr_t *pp;
    xfs_btree_block_t *blk;
    uint16_t nextents;
    block_t nextbno;
    uint32_t index;

    (void)lstart;

    xfs_debug("inode %p lstart %lu", inode, lstart);

    core = xfs_dinode_get_core(fs, inode->ino);
    if (!core) {
	xfs_error("Failed to get dinode from disk (ino %llx)", inode->ino);
	goto out;
    }

    /* The data fork contains the file's data extents */
    if (XFS_PVT(inode)->i_cur_extent == be32_to_cpu(core->di_nextents))
        goto out;

    if (core->di_format == XFS_DINODE_FMT_EXTENTS) {
	bmbt_irec_get(&rec, (xfs_bmbt_rec_t *)&core->di_literal_area[0] +
						XFS_PVT(inode)->i_cur_extent++);

	bno = fsblock_to_bytes(fs, rec.br_startblock) >> BLOCK_SHIFT(fs);

	XFS_PVT(inode)->i_offset = rec.br_startoff;

	inode->next_extent.pstart = bno << BLOCK_SHIFT(fs) >> SECTOR_SHIFT(fs);
	inode->next_extent.len = ((rec.br_blockcount << BLOCK_SHIFT(fs)) +
				  SECTOR_SIZE(fs) - 1) >> SECTOR_SHIFT(fs);
    } else if (core->di_format == XFS_DINODE_FMT_BTREE) {
        xfs_debug("XFS_DINODE_FMT_BTREE");
        index = XFS_PVT(inode)->i_cur_extent++;
        rblock = (xfs_bmdr_block_t *)&core->di_literal_area[0];
        fsize = XFS_DFORK_SIZE(core, fs, XFS_DATA_FORK);
        pp = XFS_BMDR_PTR_ADDR(rblock, 1, xfs_bmdr_maxrecs(fsize, 0));
        bno = fsblock_to_bytes(fs, be64_to_cpu(pp[0])) >> BLOCK_SHIFT(fs);

        /* Find the leaf */
        for (;;) {
            blk = (xfs_btree_block_t *)get_cache(fs->fs_dev, bno);
            if (be16_to_cpu(blk->bb_level) == 0)
                break;

            pp = XFS_BMBT_PTR_ADDR(fs, blk, 1,
                    xfs_bmdr_maxrecs(XFS_INFO(fs)->blocksize, 0));
            bno = fsblock_to_bytes(fs, be64_to_cpu(pp[0])) >> BLOCK_SHIFT(fs);
        }

        /* Find the right extent among threaded leaves */
        for (;;) {
            nextbno = be64_to_cpu(blk->bb_u.l.bb_rightsib);
            nextents = be16_to_cpu(blk->bb_numrecs);
            if (nextents - index > 0) {
                bmbt_irec_get(&rec, XFS_BMDR_REC_ADDR(blk, index + 1));

                bno = fsblock_to_bytes(fs, rec.br_startblock)
						>> BLOCK_SHIFT(fs);

                XFS_PVT(inode)->i_offset = rec.br_startoff;

                inode->next_extent.pstart = bno << BLOCK_SHIFT(fs)
                                                >> SECTOR_SHIFT(fs);
                inode->next_extent.len = ((rec.br_blockcount
                                            << BLOCK_SHIFT(fs))
                                            + SECTOR_SIZE(fs) - 1)
                                            >> SECTOR_SHIFT(fs);
                break;
            }

            index -= nextents;
            bno = fsblock_to_bytes(fs, nextbno) >> BLOCK_SHIFT(fs);
            blk = (xfs_btree_block_t *)get_cache(fs->fs_dev, bno);
        }
    }

    return 0;

out:
    return -1;
}

static inline struct inode *xfs_fmt_local_find_entry(const char *dname,
						     struct inode *parent,
						     xfs_dinode_t *core)
{
    return xfs_dir2_local_find_entry(dname, parent, core);
}

static inline struct inode *xfs_fmt_extents_find_entry(const char *dname,
						       struct inode *parent,
						       xfs_dinode_t *core)
{
    if (be32_to_cpu(core->di_nextents) <= 1) {
	/* Single-block Directories */
	return xfs_dir2_block_find_entry(dname, parent, core);
    } else if (xfs_dir2_isleaf(parent->fs, core)) {
	/* Leaf Directory */
	return xfs_dir2_leaf_find_entry(dname, parent, core);
    } else {
	/* Node Directory */
	return xfs_dir2_node_find_entry(dname, parent, core);
    }
}

static inline struct inode *xfs_fmt_btree_find_entry(const char *dname,
                                                     struct inode *parent,
                                                     xfs_dinode_t *core)
{
    return xfs_dir2_node_find_entry(dname, parent, core);
}

static struct inode *xfs_iget(const char *dname, struct inode *parent)
{
    struct fs_info *fs = parent->fs;
    xfs_dinode_t *core = NULL;
    struct inode *inode = NULL;

    xfs_debug("dname %s parent %p parent ino %lu", dname, parent, parent->ino);

    core = xfs_dinode_get_core(fs, parent->ino);
    if (!core) {
        xfs_error("Failed to get dinode from disk (ino 0x%llx)", parent->ino);
        goto out;
    }

    if (core->di_format == XFS_DINODE_FMT_LOCAL) {
	inode = xfs_fmt_local_find_entry(dname, parent, core);
    } else if (core->di_format == XFS_DINODE_FMT_EXTENTS) {
        inode = xfs_fmt_extents_find_entry(dname, parent, core);
    } else if (core->di_format == XFS_DINODE_FMT_BTREE) {
        inode = xfs_fmt_btree_find_entry(dname, parent, core);
    }

    if (!inode) {
	xfs_debug("Entry not found!");
	goto out;
    }

    if (inode->mode == DT_REG) {
	XFS_PVT(inode)->i_offset = 0;
	XFS_PVT(inode)->i_cur_extent = 0;
    } else if (inode->mode == DT_DIR) {
	XFS_PVT(inode)->i_btree_offset = 0;
	XFS_PVT(inode)->i_leaf_ent_offset = 0;
    }

    return inode;

out:
    return NULL;
}

static int xfs_readlink(struct inode *inode, char *buf)
{
    struct fs_info *fs = inode->fs;
    xfs_dinode_t *core;
    int pathlen = -1;
    xfs_bmbt_irec_t rec;
    block_t db;
    const char *dir_buf;

    xfs_debug("inode %p buf %p", inode, buf);

    core = xfs_dinode_get_core(fs, inode->ino);
    if (!core) {
	xfs_error("Failed to get dinode from disk (ino 0x%llx)", inode->ino);
	goto out;
    }

    pathlen = be64_to_cpu(core->di_size);
    if (!pathlen)
	goto out;

    if (pathlen < 0 || pathlen > MAXPATHLEN) {
	xfs_error("inode (%llu) bad symlink length (%d)",
		  inode->ino, pathlen);
	goto out;
    }

    if (core->di_format == XFS_DINODE_FMT_LOCAL) {
	memcpy(buf, (char *)&core->di_literal_area[0], pathlen);
    } else if (core->di_format == XFS_DINODE_FMT_EXTENTS) {
	bmbt_irec_get(&rec, (xfs_bmbt_rec_t *)&core->di_literal_area[0]);
	db = fsblock_to_bytes(fs, rec.br_startblock) >> BLOCK_SHIFT(fs);
	dir_buf = xfs_dir2_dirblks_get_cached(fs, db, rec.br_blockcount);

        /*
         * Syslinux only supports filesystem block size larger than or equal to
	 * 4 KiB. Thus, one directory block is far enough to hold the maximum
	 * symbolic link file content, which is only 1024 bytes long.
         */
	memcpy(buf, dir_buf, pathlen);
    }

out:
    return pathlen;
}

static struct inode *xfs_iget_root(struct fs_info *fs)
{
    xfs_dinode_t *core = NULL;
    struct inode *inode = xfs_new_inode(fs);

    xfs_debug("Looking for the root inode...");

    core = xfs_dinode_get_core(fs, XFS_INFO(fs)->rootino);
    if (!core) {
	xfs_error("Inode core's magic number does not match!");
	xfs_debug("magic number 0x%04x", be16_to_cpu(core->di_magic));
	goto out;
    }

    fill_xfs_inode_pvt(fs, inode, XFS_INFO(fs)->rootino);

    xfs_debug("Root inode has been found!");

    if ((be16_to_cpu(core->di_mode) & S_IFMT) != S_IFDIR) {
	xfs_error("root inode is not a directory ?! No makes sense...");
	goto out;
    }

    inode->ino			= XFS_INFO(fs)->rootino;
    inode->mode 		= DT_DIR;
    inode->size 		= be64_to_cpu(core->di_size);

    return inode;

out:
    free(inode);

    return NULL;
}

static inline int xfs_read_superblock(struct fs_info *fs, xfs_sb_t *sb)
{
    struct disk *disk = fs->fs_dev->disk;

    if (!disk->rdwr_sectors(disk, sb, XFS_SB_DADDR, 1, false))
	return -1;

    return 0;
}

static struct xfs_fs_info *xfs_new_sb_info(xfs_sb_t *sb)
{
    struct xfs_fs_info *info;

    info = malloc(sizeof *info);
    if (!info)
	malloc_error("xfs_fs_info structure");

    info->blocksize		= be32_to_cpu(sb->sb_blocksize);
    info->block_shift		= sb->sb_blocklog;
    info->dirblksize		= 1 << (sb->sb_blocklog + sb->sb_dirblklog);
    info->dirblklog		= sb->sb_dirblklog;
    info->inopb_shift 		= sb->sb_inopblog;
    info->agblk_shift 		= sb->sb_agblklog;
    info->rootino 		= be64_to_cpu(sb->sb_rootino);
    info->agblocks 		= be32_to_cpu(sb->sb_agblocks);
    info->agblocks_shift 	= sb->sb_agblklog;
    info->agcount 		= be32_to_cpu(sb->sb_agcount);
    info->inodesize 		= be16_to_cpu(sb->sb_inodesize);
    info->inode_shift 		= sb->sb_inodelog;

    return info;
}

static int xfs_fs_init(struct fs_info *fs)
{
    struct disk *disk = fs->fs_dev->disk;
    xfs_sb_t sb;
    struct xfs_fs_info *info;

    xfs_debug("fs %p", fs);

    SECTOR_SHIFT(fs) = disk->sector_shift;
    SECTOR_SIZE(fs) = 1 << SECTOR_SHIFT(fs);

    if (xfs_read_superblock(fs, &sb)) {
	xfs_error("Superblock read failed");
	goto out;
    }

    if (!xfs_is_valid_magicnum(&sb)) {
	xfs_error("Invalid superblock");
	goto out;
    }

    xfs_debug("magicnum 0x%lX", be32_to_cpu(sb.sb_magicnum));

    info = xfs_new_sb_info(&sb);
    if (!info) {
	xfs_error("Failed to fill in filesystem-specific info structure");
	goto out;
    }

    fs->fs_info = info;

    xfs_debug("block_shift %u blocksize 0x%lX (%lu)", info->block_shift,
	      info->blocksize, info->blocksize);

    xfs_debug("rootino 0x%llX (%llu)", info->rootino, info->rootino);

    BLOCK_SHIFT(fs) = info->block_shift;
    BLOCK_SIZE(fs) = info->blocksize;

    cache_init(fs->fs_dev, BLOCK_SHIFT(fs));

    XFS_INFO(fs)->dirleafblk = xfs_dir2_db_to_da(fs, XFS_DIR2_LEAF_FIRSTDB(fs));

    return BLOCK_SHIFT(fs);

out:
    return -1;
}

const struct fs_ops xfs_fs_ops = {
    .fs_name		= "xfs",
    .fs_flags		= FS_USEMEM | FS_THISIND,
    .fs_init		= xfs_fs_init,
    .iget_root		= xfs_iget_root,
    .searchdir		= NULL,
    .getfssec		= xfs_getfssec,
    .open_config	= generic_open_config,
    .close_file         = generic_close_file,
    .mangle_name	= generic_mangle_name,
    .readdir		= xfs_readdir,
    .iget		= xfs_iget,
    .next_extent	= xfs_next_extent,
    .readlink		= xfs_readlink,
    .fs_uuid            = NULL,
};
