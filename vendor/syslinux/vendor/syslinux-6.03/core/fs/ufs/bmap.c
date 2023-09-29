/*
 * Copyright (C) 2013 Raphael S. Carvalho <raphael.scarv@gmail.com>
 *
 * Partially taken from fs/ext2/bmap.c
 * This file was modified according UFS1/2 needs.
 *
 * Copyright (C) 2009 Liu Aleaxander -- All rights reserved. This file
 * may be redistributed under the terms of the GNU Public License.
 */

#include <stdio.h>
#include <dprintf.h>
#include <fs.h>
#include <disk.h>
#include <cache.h>
#include "ufs.h"

/*
 * Copy blk address into buffer, this was needed since UFS1/2 addr size
 * in blk maps differs from each other (32/64 bits respectivelly).
 */
static inline uint64_t
get_blkaddr (const uint8_t *blk, uint32_t index, uint32_t shift)
{
    uint64_t addr = 0;

    memcpy((uint8_t *) &addr,
	   (uint8_t *) blk + (index << shift),
	    1 << shift);

    return addr;
}

/*
 * Scan forward in a range of blocks to see if they are contiguous,
 * then return the initial value.
 */
static uint64_t
scan_set_nblocks(const uint8_t *map, uint32_t index, uint32_t addr_shift,
		  unsigned int count, size_t *nblocks)
{
    uint64_t addr;
    uint64_t blk = get_blkaddr(map, index, addr_shift);

    /*
     * Block spans 8 fragments, then address is interleaved by 8.
     * This code works for either 32/64 sized addresses.
     */
    if (nblocks) {
	uint32_t skip = blk ? FRAGMENTS_PER_BLK : 0;
	uint32_t next = blk + skip;
	size_t   cnt = 1;

	/* Get address of starting blk pointer */
	map += (index << addr_shift);

	ufs_debug("[scan] start blk: %u\n", blk);
	ufs_debug("[scan] count (nr of blks): %u\n", count);
	/* Go up to the end of blk map */
	while (--count) {
	    map += 1 << addr_shift;
	    addr = get_blkaddr(map, 0, addr_shift);
#if 0
	    /* Extra debugging info (Too much prints) */
	    ufs_debug("[scan] addr: %u next: %u\n", addr, next);
#endif
	    if (addr == next) {
		cnt++;
		next += skip;
	    } else {
		break;
	    }
	}
	*nblocks = cnt;
	ufs_debug("[scan] nblocks: %u\n", cnt);
	ufs_debug("[scan] end blk: %u\n", next - FRAGMENTS_PER_BLK);
    }

    return blk;
}

/*
 * The actual indirect block map handling - the block passed in should
 * be relative to the beginning of the particular block hierarchy.
 *
 * @shft_per_blk: shift to get nr. of addresses in a block.
 * @mask_per_blk: mask to limit the max nr. of addresses in a block.
 * @addr_count:   nr. of addresses in a block.
 */
static uint64_t
bmap_indirect(struct fs_info *fs, uint64_t start, uint32_t block,
	      int levels, size_t *nblocks)
{
    uint32_t shft_per_blk = fs->block_shift - UFS_SB(fs)->addr_shift;
    uint32_t addr_count = (1 << shft_per_blk);
    uint32_t mask_per_blk = addr_count - 1;
    const uint8_t *blk = NULL;
    uint32_t index = 0;

    while (levels--) {
	if (!start) {
	    if (nblocks)
		*nblocks = addr_count << (levels * shft_per_blk);
	    return 0;
	}

	blk = get_cache(fs->fs_dev, frag_to_blk(fs, start));
	index = (block >> (levels * shft_per_blk)) & mask_per_blk;
	start = get_blkaddr(blk, index, UFS_SB(fs)->addr_shift);
    }

    return scan_set_nblocks(blk, index, UFS_SB(fs)->addr_shift,
			    addr_count - index, nblocks);
}

/*
 * Handle the traditional block map, like indirect, double indirect
 * and triple indirect
 */
uint64_t ufs_bmap (struct inode *inode, block_t block, size_t *nblocks)
{
    uint32_t shft_per_blk, ptrs_per_blk;
    static uint32_t indir_blks, double_blks, triple_blks;
    struct fs_info *fs = inode->fs;

    /* Initialize static values */
    if (!indir_blks) {
	shft_per_blk = fs->block_shift - UFS_SB(fs)->addr_shift;
	ptrs_per_blk = fs->block_size >> UFS_SB(fs)->addr_shift;

	indir_blks = ptrs_per_blk;
	double_blks = ptrs_per_blk << shft_per_blk;
	triple_blks = double_blks << shft_per_blk;
    }

    /*
     * direct blocks
     * (UFS2_ADDR_SHIFT) is also used for UFS1 because its direct ptr array
     * was extended to 64 bits.
     */
    if (block < UFS_DIRECT_BLOCKS)
	return scan_set_nblocks((uint8_t *) PVT(inode)->direct_blk_ptr,
				block, UFS2_ADDR_SHIFT,
				UFS_DIRECT_BLOCKS - block, nblocks);

    /* indirect blocks */
    block -= UFS_DIRECT_BLOCKS;
    if (block < indir_blks)
	return bmap_indirect(fs, PVT(inode)->indirect_blk_ptr,
			     block, 1, nblocks);

    /* double indirect blocks */
    block -= indir_blks;
    if (block < double_blks)
	return bmap_indirect(fs, PVT(inode)->double_indirect_blk_ptr,
			     block, 2, nblocks);

    /* triple indirect blocks */
    block -= double_blks;
    if (block < triple_blks)
	return bmap_indirect(fs, PVT(inode)->triple_indirect_blk_ptr,
			     block, 3, nblocks);

    /* This can't happen... */
    return 0;
}

/*
 * Next extent for getfssec
 * "Remaining sectors" means (lstart & blkmask).
 */
int ufs_next_extent(struct inode *inode, uint32_t lstart)
{
    struct fs_info *fs = inode->fs;
    int blktosec =  BLOCK_SHIFT(fs) - SECTOR_SHIFT(fs);
    int frag_shift = BLOCK_SHIFT(fs) - UFS_SB(fs)->c_blk_frag_shift;
    int blkmask = (1 << blktosec) - 1;
    block_t block;
    size_t nblocks = 0;

    ufs_debug("ufs_next_extent:\n");
    block = ufs_bmap(inode, lstart >> blktosec, &nblocks);
    ufs_debug("blk: %u\n", block);

    if (!block) // Sparse block
	inode->next_extent.pstart = EXTENT_ZERO;
    else
	/*
	 * Convert blk into sect addr and add the remaining
	 * sectors into pstart (sector start address).
	 */
	inode->next_extent.pstart =
	    ((sector_t) (block << (frag_shift - SECTOR_SHIFT(fs)))) |
	    (lstart & blkmask);

    /*
     * Subtract the remaining sectors from len since these sectors
     * were added to pstart (sector start address).
     */
    inode->next_extent.len = (nblocks << blktosec) - (lstart & blkmask);
    return 0;
}