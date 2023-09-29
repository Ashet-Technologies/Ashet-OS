/*
 * Copyright (c) 2012 Paulo Alcantara <pcacjr@zytor.com>
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

#ifndef XFS_DIR2_H_
#define XFS_DIR2_H_

#include <core.h>
#include <fs.h>

#include "xfs.h"

const void *xfs_dir2_dirblks_get_cached(struct fs_info *fs, block_t startblock,
					xfs_filblks_t c);
void xfs_dir2_dirblks_flush_cache(void);

uint32_t xfs_dir2_da_hashname(const uint8_t *name, int namelen);

block_t xfs_dir2_get_right_blk(struct fs_info *fs, xfs_dinode_t *core,
			       block_t fsblkno, int *error);

struct inode *xfs_dir2_local_find_entry(const char *dname, struct inode *parent,
					xfs_dinode_t *core);
struct inode *xfs_dir2_block_find_entry(const char *dname, struct inode *parent,
					xfs_dinode_t *core);
struct inode *xfs_dir2_leaf_find_entry(const char *dname, struct inode *parent,
				       xfs_dinode_t *core);
struct inode *xfs_dir2_node_find_entry(const char *dname, struct inode *parent,
				       xfs_dinode_t *core);

static inline bool xfs_dir2_isleaf(struct fs_info *fs, xfs_dinode_t *dip)
{
    uint64_t last = 0;
    xfs_bmbt_irec_t irec;

    bmbt_irec_get(&irec, ((xfs_bmbt_rec_t *)&dip->di_literal_area[0]) +
		         be32_to_cpu(dip->di_nextents) - 1);
    last = irec.br_startoff + irec.br_blockcount;

    return (last == XFS_INFO(fs)->dirleafblk + (1 << XFS_INFO(fs)->dirblklog));
}

static inline int xfs_dir2_entry_name_cmp(uint8_t *start, uint8_t *end,
					  const char *name)
{
    if (!name || (strlen(name) != end - start))
	return -1;

    while (start < end)
	if (*start++ != *name++)
	    return -1;

    return 0;
}

#endif /* XFS_DIR2_H_ */
