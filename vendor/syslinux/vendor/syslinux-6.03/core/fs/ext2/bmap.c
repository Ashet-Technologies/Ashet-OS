/*
 * The logical block -> physical block routine.
 *
 * Copyright (C) 2009 Liu Aleaxander -- All rights reserved. This file
 * may be redistributed under the terms of the GNU Public License.
 */

#include <stdio.h>
#include <dprintf.h>
#include <fs.h>
#include <disk.h>
#include <cache.h>
#include "ext2_fs.h"

static const struct ext4_extent_header *
ext4_find_leaf(struct fs_info *fs, const struct ext4_extent_header *eh,
	       block_t block)
{
    struct ext4_extent_idx *index;
    block_t blk;
    int i;

    while (1) {
	if (eh->eh_magic != EXT4_EXT_MAGIC)
	    return NULL;
	if (eh->eh_depth == 0)
	    return eh;

	index = EXT4_FIRST_INDEX(eh);
	for (i = 0; i < (int)eh->eh_entries; i++) {
	    if (block < index[i].ei_block)
		break;
	}
	if (--i < 0)
	    return NULL;

	blk = index[i].ei_leaf_hi;
	blk = (blk << 32) + index[i].ei_leaf_lo;
	eh = get_cache(fs->fs_dev, blk);
    }
}

/* handle the ext4 extents to get the phsical block number */
/* XXX: still need to handle sparse files with extents */
static block_t
bmap_extent(struct inode *inode, uint32_t block, size_t *nblocks)
{
    struct fs_info *fs = inode->fs;
    const struct ext4_extent_header *leaf;
    const struct ext4_extent *ext;
    int i;
    block_t start;

    leaf = ext4_find_leaf(fs, &PVT(inode)->i_extent_hdr, block);
    if (!leaf) {
	printf("ERROR, extent leaf not found\n");
	return 0;
    }

    ext = EXT4_FIRST_EXTENT(leaf);
    for (i = 0; i < leaf->eh_entries; i++) {
	if (block < ext[i].ee_block)
	    break;
    }
    if (--i < 0) {
	printf("ERROR, not find the right block\n");
	return 0;
    }

    /* got it */
    block -= ext[i].ee_block;
    if (block >= ext[i].ee_len)
	return 0;
    start = ((block_t)ext[i].ee_start_hi << 32) + ext[i].ee_start_lo;

    if (nblocks)
	*nblocks = ext[i].ee_len - block;

    return start + block;
}

/*
 * Scan forward in a range of blocks to see if they are contiguous,
 * then return the initial value.
 */
static uint32_t
scan_set_nblocks(const uint32_t *map, unsigned int count, size_t *nblocks)
{
    uint32_t blk = *map;

    if (nblocks) {
	uint32_t skip = blk ? 1 : 0;
	uint32_t next = blk + skip;
	size_t   cnt = 1;

	while (--count) {
	    map++;
	    if (*map == next) {
		cnt++;
		next += skip;
	    } else {
		break;
	    }
	}

	*nblocks = cnt;
    }

    return blk;
}

/*
 * The actual indirect block map handling - the block passed in should
 * be relative to the beginning of the particular block hierarchy.
 */
static block_t
bmap_indirect(struct fs_info *fs, uint32_t start, uint32_t block,
	      int levels, size_t *nblocks)
{
    int addr_shift = BLOCK_SHIFT(fs) - 2;
    uint32_t addr_count = 1 << addr_shift;
    const uint32_t *blk = NULL;
    uint32_t index = 0;

    while (levels--) {
	if (!start) {
	    if (nblocks)
		*nblocks = addr_count << (levels * addr_shift);
	    return 0;
	}
	blk = get_cache(fs->fs_dev, start);
	index = (block >> (levels * addr_shift)) & (addr_count - 1);
	start = blk[index];
    }

    return scan_set_nblocks(blk + index, addr_count - index, nblocks);
}

/*
 * Handle the traditional block map, like indirect, double indirect
 * and triple indirect
 */
static block_t
bmap_traditional(struct inode *inode, block_t block, size_t *nblocks)
{
    struct fs_info *fs = inode->fs;
    const uint32_t addr_per_block = BLOCK_SIZE(fs) >> 2;
    const int shft_per_block      = BLOCK_SHIFT(fs) - 2;
    const uint32_t direct_blocks   = EXT2_NDIR_BLOCKS;
    const uint32_t indirect_blocks = addr_per_block;
    const uint32_t double_blocks   = addr_per_block << shft_per_block;
    const uint32_t triple_blocks   = double_blocks  << shft_per_block;

    /* direct blocks */
    if (block < direct_blocks)
	return scan_set_nblocks(&PVT(inode)->i_block[block],
				direct_blocks - block, nblocks);

    /* indirect blocks */
    block -= direct_blocks;
    if (block < indirect_blocks)
	return bmap_indirect(fs, PVT(inode)->i_block[EXT2_IND_BLOCK],
			     block, 1, nblocks);

    /* double indirect blocks */
    block -= indirect_blocks;
    if (block < double_blocks)
	return bmap_indirect(fs, PVT(inode)->i_block[EXT2_DIND_BLOCK],
			     block, 2, nblocks);

    /* triple indirect block */
    block -= double_blocks;
    if (block < triple_blocks)
	return bmap_indirect(fs, PVT(inode)->i_block[EXT2_TIND_BLOCK],
			     block, 3, nblocks);

    /* This can't happen... */
    return 0;
}


/**
 * Map the logical block to physic block where the file data stores.
 * In EXT4, there are two ways to handle the map process, extents and indirect.
 * EXT4 uses a inode flag to mark extent file and indirect block file.
 *
 * @fs:      the fs_info structure.
 * @inode:   the inode structure.
 * @block:   the logical block to be mapped.
 * @nblocks: optional pointer to number of contiguous blocks (low estimate)
 * @retrun:  the physical block number.
 *
 */
block_t ext2_bmap(struct inode *inode, block_t block, size_t *nblocks)
{
    block_t ret;

    if (inode->flags & EXT4_EXTENTS_FLAG)
	ret = bmap_extent(inode, block, nblocks);
    else
	ret = bmap_traditional(inode, block, nblocks);

    return ret;
}


/*
 * Next extent for getfssec
 */
int ext2_next_extent(struct inode *inode, uint32_t lstart)
{
    struct fs_info *fs = inode->fs;
    int blktosec =  BLOCK_SHIFT(fs) - SECTOR_SHIFT(fs);
    int blkmask = (1 << blktosec) - 1;
    block_t block;
    size_t nblocks = 0;

    block = ext2_bmap(inode, lstart >> blktosec, &nblocks);

    if (!block)
	inode->next_extent.pstart = EXTENT_ZERO;
    else
	inode->next_extent.pstart =
	    ((sector_t)block << blktosec) | (lstart & blkmask);

    inode->next_extent.len = (nblocks << blktosec) - (lstart & blkmask);
    return 0;
}
