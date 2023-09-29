/*
 * Copyright (C) 2013 Raphael S. Carvalho <raphael.scarv@gmail.com>
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

#include <dprintf.h>
#include <stdio.h>
#include <string.h>
#include <sys/dirent.h>
#include <cache.h>
#include <disk.h>
#include <fs.h>
#include <minmax.h>
#include "core.h"
#include "ufs.h"

/*
 * Read the super block and check magic fields based on
 * passed paramaters.
 */
static bool
do_checksb(struct ufs_super_block *sb, struct disk *disk,
	    const uint32_t sblock_off, const uint32_t ufs_smagic)
{
    uint32_t lba;
    static uint32_t count;

    /* How many sectors are needed to fill sb struct */
    if (!count)
	count = sizeof *sb >> disk->sector_shift;
    /* Get lba address based on sector size of disk */
    lba = sblock_off >> (disk->sector_shift);
    /* Read super block */
    disk->rdwr_sectors(disk, sb, lba, count, 0);

    if (sb->magic == ufs_smagic)
	return true;

    return false;
}

/*
 * Go through all possible ufs superblock offsets.
 * TODO: Add UFS support to removable media (sb offset: 0).
 */
static int
ufs_checksb(struct ufs_super_block *sb, struct disk *disk)
{
    /* Check for UFS1 sb */
    if (do_checksb(sb, disk, UFS1_SBLOCK_OFFSET, UFS1_SUPER_MAGIC))
	return UFS1;
    /* Check for UFS2 sb */
    if (do_checksb(sb, disk, UFS2_SBLOCK_OFFSET, UFS2_SUPER_MAGIC))
	return UFS2;
    /* UFS2 may also exist in 256k-, but this isn't the default */
    if (do_checksb(sb, disk, UFS2_SBLOCK2_OFFSET, UFS2_SUPER_MAGIC))
	return UFS2_PIGGY;

    return NONE;
}

/*
 * lblock stands for linear block address,
 * whereas pblock is the actual blk ptr to get data from.
 *
 * UFS1/2 use frag addrs rather than blk ones, then
 * the offset into the block must be calculated.
 */
static const void *
ufs_get_cache(struct inode *inode, block_t lblock)
{
    const void *data;
    struct fs_info *fs = inode->fs;
    struct ufs_sb_info *sb = UFS_SB(inode->fs);
    uint64_t frag_addr, frag_offset;
    uint32_t frag_shift;
    block_t pblock;

    frag_addr = ufs_bmap(inode, lblock, NULL);
    if (!frag_addr)
	return NULL;

    frag_shift = fs->block_shift - sb->c_blk_frag_shift;
    /* Get fragment byte address */
    frag_offset = frag_addr << frag_shift;
    /* Convert frag addr to blk addr */
    pblock = frag_to_blk(fs, frag_addr);
    /* Read the blk */
    data = get_cache(fs->fs_dev, pblock);

    /* Return offset into block */
    return data + (frag_offset & (fs->block_size - 1));
}

/*
 * Based on fs/ext2/ext2.c
 * find a dir entry, return it if found, or return NULL.
 */
static const struct ufs_dir_entry *
ufs_find_entry(struct fs_info *fs, struct inode *inode, const char *dname)
{
    const struct ufs_dir_entry *dir;
    const char *data;
    int32_t i, offset, maxoffset;
    block_t index = 0;

    ufs_debug("ufs_find_entry: dname: %s ", dname);
    for (i = 0; i < inode->size; i += fs->block_size) {
	data = ufs_get_cache(inode, index++);
	offset = 0;
	maxoffset = min(inode->size-i, fs->block_size);

	/* The smallest possible size is 9 bytes */
	while (offset < maxoffset-8) {
	    dir = (const struct ufs_dir_entry *)(data + offset);
	    if (dir->dir_entry_len > maxoffset - offset)
		break;

	    /*
	     * Name fields are variable-length and null terminated,
	     * then it's possible to use strcmp directly.
	     */
	    if (dir->inode_value && !strcmp(dname, (const char *)dir->name)) {
		ufs_debug("(found)\n");
		return dir;
	    }
	    offset += dir->dir_entry_len;
	}
    }
    ufs_debug("(not found)\n");
    return NULL;
}

/*
 * Get either UFS1/2 inode structures.
 */
static const void *
ufs_get_inode(struct fs_info *fs, int inr)
{
    const char *data;
    uint32_t group, inode_offset, inode_table;
    uint32_t block_num, block_off;

    /* Get cylinder group nr. */
    group = inr / UFS_SB(fs)->inodes_per_cg;
    /*
     * Ensuring group will not exceed the range 0:groups_count-1.
     * By the way, this should *never* happen.
     * Unless the (on-disk) fs structure is corrupted!
     */
    if (group >= UFS_SB(fs)->groups_count) {
	printf("ufs_get_inode: "
		"group(%d) exceeded the avail. range (0:%d)\n",
		group, UFS_SB(fs)->groups_count - 1);
	return NULL;
    }

    /* Offset into inode table of the cylinder group */
    inode_offset = inr % UFS_SB(fs)->inodes_per_cg;
    /* Get inode table blk addr respective to cylinder group */
    inode_table = (group * UFS_SB(fs)->blocks_per_cg) +
	UFS_SB(fs)->off_inode_tbl;
    /* Calculating staggering offset (UFS1 only!) */
    if (UFS_SB(fs)->fs_type == UFS1)
	inode_table += UFS_SB(fs)->ufs1.delta_value *
	    (group & UFS_SB(fs)->ufs1.cycle_mask);

    /* Get blk nr and offset into the blk */
    block_num = inode_table + inode_offset / UFS_SB(fs)->inodes_per_block;
    block_off = inode_offset % UFS_SB(fs)->inodes_per_block;

    /*
     * Read the blk from the blk addr previously computed;
     * Calc the inode struct offset into the read block.
     */
    data = get_cache(fs->fs_dev, block_num);
    return data + block_off * UFS_SB(fs)->inode_size;
}

static struct inode *
ufs1_iget_by_inr(struct fs_info *fs, uint32_t inr)
{
    const struct ufs1_inode *ufs_inode;
    struct inode *inode;
    uint64_t *dest;
    uint32_t *source;
    int i;

    ufs_inode = (struct ufs1_inode *) ufs_get_inode(fs, inr);
    if (!ufs_inode)
	return NULL;

    if (!(inode = alloc_inode(fs, inr, sizeof(struct ufs_inode_pvt))))
	return NULL;

    /* UFS1 doesn't support neither creation nor deletion times */
    inode->refcnt  = ufs_inode->link_count;
    inode->mode    = IFTODT(ufs_inode->file_mode);
    inode->size    = ufs_inode->size;
    inode->atime   = ufs_inode->a_time;
    inode->mtime   = ufs_inode->m_time;
    inode->blocks  = ufs_inode->blocks_held;
    inode->flags   = ufs_inode->flags;

    /*
     * Copy and extend blk pointers to 64 bits, so avoid
     * having two structures for inode private.
     */
    dest = (uint64_t *) inode->pvt;
    source = (uint32_t *) ufs_inode->direct_blk_ptr;
    for (i = 0; i < UFS_NBLOCKS; i++)
	dest[i] = ((uint64_t) source[i]) & 0xFFFFFFFF;

    return inode;
}

static struct inode *
ufs2_iget_by_inr(struct fs_info *fs, uint32_t inr)
{
    const struct ufs2_inode *ufs_inode;
    struct inode *inode;

    ufs_inode = (struct ufs2_inode *) ufs_get_inode(fs, inr);
    if (!ufs_inode)
	return NULL;

    if (!(inode = alloc_inode(fs, inr, sizeof(struct ufs_inode_pvt))))
	return NULL;

    /* UFS2 doesn't support deletion time */
    inode->refcnt  = ufs_inode->link_count;
    inode->mode    = IFTODT(ufs_inode->file_mode);
    inode->size    = ufs_inode->size;
    inode->atime   = ufs_inode->a_time;
    inode->ctime   = ufs_inode->creat_time;
    inode->mtime   = ufs_inode->m_time;
    inode->blocks  = ufs_inode->bytes_held >> fs->block_shift;
    inode->flags   = ufs_inode->flags;
    memcpy(inode->pvt, ufs_inode->direct_blk_ptr,
	   sizeof(uint64_t) * UFS_NBLOCKS);

    return inode;
}

/*
 * Both ufs_iget_root and ufs_iget callback based on ufs type.
 */
static struct inode *
ufs_iget_root(struct fs_info *fs)
{
    return UFS_SB(fs)->ufs_iget_by_inr(fs, UFS_ROOT_INODE);
}

static struct inode *
ufs_iget(const char *dname, struct inode *parent)
{
    const struct ufs_dir_entry *dir;
    struct fs_info *fs = parent->fs;

    dir = ufs_find_entry(fs, parent, dname);
    if (!dir)
	return NULL;

    return UFS_SB(fs)->ufs_iget_by_inr(fs, dir->inode_value);
}

static void ufs1_read_blkaddrs(struct inode *inode, char *buf)
{
    uint32_t dest[UFS_NBLOCKS];
    const uint64_t *source = (uint64_t *) (inode->pvt);
    int i;

    /* Convert ufs_inode_pvt uint64_t fields into uint32_t
     * Upper-half part of ufs1 private blk addrs are always supposed to be
     * zero (it's previosuly extended by us), thus data isn't being lost. */
    for (i = 0; i < UFS_NBLOCKS; i++) {
        if ((source[i] >> 32) != 0) {
            /* This should never happen, but will not prevent anything
             * from working. */
            ufs_debug("ufs1: inode->pvt[%d]: warning!\n", i);
        }

        dest[i] = (uint32_t)(source[i] & 0xFFFFFFFF);
    }
    memcpy(buf, (const char *) dest, inode->size);
}

static void ufs2_read_blkaddrs(struct inode *inode, char *buf)
{
    memcpy(buf, (const char *) (inode->pvt), inode->size);
}

/*
 * Taken from ext2/ext2.c.
 * Read the entire contents of an inode into a memory buffer
 */
static int cache_get_file(struct inode *inode, void *buf, size_t bytes)
{
    struct fs_info *fs = inode->fs;
    size_t block_size = BLOCK_SIZE(fs);
    uint32_t index = 0;         /* Logical block number */
    size_t chunk;
    const char *data;
    char *p = buf;

    if (inode->size > bytes)
        bytes = inode->size;

    while (bytes) {
        chunk = min(bytes, block_size);
        data = ufs_get_cache(inode, index++);
        memcpy(p, data, chunk);

        bytes -= chunk;
        p += chunk;
    }

    return 0;
}

static int ufs_readlink(struct inode *inode, char *buf)
{
    struct fs_info *fs = inode->fs;
    uint32_t i_symlink_limit;

    if (inode->size > BLOCK_SIZE(fs))
        return -1;              /* Error! */

    // TODO: use UFS_SB(fs)->maxlen_isymlink instead.
    i_symlink_limit = ((UFS_SB(fs)->fs_type == UFS1) ?
        sizeof(uint32_t) : sizeof(uint64_t)) * UFS_NBLOCKS;
    ufs_debug("UFS_SB(fs)->maxlen_isymlink=%d", UFS_SB(fs)->maxlen_isymlink);

    if (inode->size <= i_symlink_limit)
        UFS_SB(fs)->ufs_read_blkaddrs(inode, buf);
    else
        cache_get_file(inode, buf, inode->size);

    return inode->size;
}

static inline enum dir_type_flags get_inode_mode(uint8_t type)
{
    switch(type) {
        case UFS_DTYPE_FIFO: return DT_FIFO;
        case UFS_DTYPE_CHARDEV: return DT_CHR;
        case UFS_DTYPE_DIR: return DT_DIR;
        case UFS_DTYPE_BLOCK: return DT_BLK;
        case UFS_DTYPE_RFILE: return DT_REG;
        case UFS_DTYPE_SYMLINK: return DT_LNK;
        case UFS_DTYPE_SOCKET: return DT_SOCK;
        case UFS_DTYPE_WHITEOUT: return DT_WHT;
        default: return DT_UNKNOWN;
    }
}

/*
 * Read one directory entry at a time
 */
static int ufs_readdir(struct file *file, struct dirent *dirent)
{
    struct fs_info *fs = file->fs;
    struct inode *inode = file->inode;
    const struct ufs_dir_entry *dir;
    const char *data;
    block_t index = file->offset >> fs->block_shift;

    if (file->offset >= inode->size)
	return -1;		/* End of file */

    data = ufs_get_cache(inode, index);
    dir = (const struct ufs_dir_entry *)
	(data + (file->offset & (BLOCK_SIZE(fs) - 1)));

    dirent->d_ino = dir->inode_value;
    dirent->d_off = file->offset;
    dirent->d_reclen = offsetof(struct dirent, d_name) + dir->name_length + 1;
    dirent->d_type = get_inode_mode(dir->file_type & 0x0F);
    memcpy(dirent->d_name, dir->name, dir->name_length);
    dirent->d_name[dir->name_length] = '\0';

    file->offset += dir->dir_entry_len;  /* Update for next reading */

    return 0;
}

static inline struct ufs_sb_info *
set_ufs_info(struct ufs_super_block *sb, int ufs_type)
{
    struct ufs_sb_info *sbi;

    sbi = malloc(sizeof *sbi);
    if (!sbi)
	malloc_error("ufs_sb_info structure");

    /* Setting up UFS-dependent info */
    if (ufs_type == UFS1) {
	sbi->inode_size = sizeof (struct ufs1_inode);
	sbi->groups_count = sb->ufs1.nr_frags / sb->frags_per_cg;
	sbi->ufs1.delta_value = sb->ufs1.delta_value;
	sbi->ufs1.cycle_mask = sb->ufs1.cycle_mask;
	sbi->ufs_iget_by_inr = ufs1_iget_by_inr;
        sbi->ufs_read_blkaddrs = ufs1_read_blkaddrs;
	sbi->addr_shift = UFS1_ADDR_SHIFT;
    } else { // UFS2 or UFS2_PIGGY
	sbi->inode_size = sizeof (struct ufs2_inode);
	sbi->groups_count = sb->ufs2.nr_frags / sb->frags_per_cg;
	sbi->ufs_iget_by_inr = ufs2_iget_by_inr;
        sbi->ufs_read_blkaddrs = ufs2_read_blkaddrs;
	sbi->addr_shift = UFS2_ADDR_SHIFT;
    }
    sbi->inodes_per_block = sb->block_size / sbi->inode_size;
    sbi->inodes_per_cg = sb->inodes_per_cg;
    sbi->blocks_per_cg = sb->frags_per_cg >> sb->c_blk_frag_shift;
    sbi->off_inode_tbl = sb->off_inode_tbl >> sb->c_blk_frag_shift;
    sbi->c_blk_frag_shift = sb->c_blk_frag_shift;
    sbi->maxlen_isymlink = sb->maxlen_isymlink;
    sbi->fs_type = ufs_type;

    return sbi;
}

/*
 * Init the fs metadata and return block size
 */
static int ufs_fs_init(struct fs_info *fs)
{
    struct disk *disk = fs->fs_dev->disk;
    struct ufs_super_block sb;
    struct cache *cs;

    int ufs_type = ufs_checksb(&sb, disk);
    if (ufs_type == NONE)
	return -1;

    ufs_debug("%s SB FOUND!\n", ufs_type == UFS1 ? "UFS1" : "UFS2");
    ufs_debug("Block size: %u\n", sb.block_size);

    fs->fs_info = (struct ufs_sb_info *) set_ufs_info(&sb, ufs_type);
    fs->sector_shift = disk->sector_shift;
    fs->sector_size  = disk->sector_size;
    fs->block_shift  = sb.block_shift;
    fs->block_size   = sb.block_size;

    /* Initialize the cache, and force a clean on block zero */
    cache_init(fs->fs_dev, sb.block_shift);
    cs = _get_cache_block(fs->fs_dev, 0);
    memset(cs->data, 0, fs->block_size);
    cache_lock_block(cs);

    /* For debug purposes */
    //ufs_checking(fs);

    //return -1;
    return fs->block_shift;
}

const struct fs_ops ufs_fs_ops = {
    .fs_name        = "ufs",
    .fs_flags       = FS_USEMEM | FS_THISIND,
    .fs_init        = ufs_fs_init,
    .searchdir      = NULL,
    .getfssec       = generic_getfssec,
    .close_file     = generic_close_file,
    .mangle_name    = generic_mangle_name,
    .open_config    = generic_open_config,
    .readlink	    = ufs_readlink,
    .readdir        = ufs_readdir,
    .iget_root      = ufs_iget_root,
    .iget           = ufs_iget,
    .next_extent    = ufs_next_extent,
};
