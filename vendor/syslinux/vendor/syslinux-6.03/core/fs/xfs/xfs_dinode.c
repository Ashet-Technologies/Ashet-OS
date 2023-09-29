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

xfs_dinode_t *xfs_dinode_get_core(struct fs_info *fs, xfs_ino_t ino)
{
    block_t blk;
    xfs_dinode_t *core;
    uint64_t offset;

    xfs_debug("fs %p ino %lu", fs, ino);

    blk = ino_to_bytes(fs, ino) >> BLOCK_SHIFT(fs);
    offset = XFS_INO_TO_OFFSET(XFS_INFO(fs), ino) << XFS_INFO(fs)->inode_shift;
    if (offset > BLOCK_SIZE(fs)) {
        xfs_error("Invalid inode offset in block!");
        xfs_debug("offset: 0x%llx", offset);
        goto out;
    }

    xfs_debug("blk %llu block offset 0x%llx", blk, blk << BLOCK_SHIFT(fs));
    xfs_debug("inode offset in block (in bytes) is 0x%llx", offset);

    core = (xfs_dinode_t *)((uint8_t *)get_cache(fs->fs_dev, blk) + offset);
    if (be16_to_cpu(core->di_magic) !=
	be16_to_cpu(*(uint16_t *)XFS_DINODE_MAGIC)) {
	xfs_error("Inode core's magic number does not match!");
	xfs_debug("magic number 0x%04x", (be16_to_cpu(core->di_magic)));
	goto out;
    }

    return core;

out:
    return NULL;
}
