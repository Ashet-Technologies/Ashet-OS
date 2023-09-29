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

#ifndef _UFS_H_
#define _UFS_H_

#include <stdint.h>

/* Sector addresses */
#define UFS1_SBLOCK_OFFSET	8192
#define UFS2_SBLOCK_OFFSET	65536
#define UFS2_SBLOCK2_OFFSET	262144

#define UFS1_ADDR_SHIFT 2
#define UFS2_ADDR_SHIFT 3

/* Super magic numbers */
#define UFS1_SUPER_MAGIC	(0x011954)
#define UFS2_SUPER_MAGIC	(0x19540119)

#define UFS_ROOT_INODE 2

#define UFS_DIRECT_BLOCKS 12
#define UFS_INDIRECT_BLOCK 1
#define UFS_DOUBLE_INDIRECT_BLOCK 1
#define UFS_TRIPLE_INDIRECT_BLOCK 1
/* Total number of block addr hold by inodes */
#define UFS_NBLOCKS 15

/* Blocks span 8 fragments */
#define FRAGMENTS_PER_BLK 8

/* UFS types */
typedef enum {
    NONE,
    UFS1,
    UFS2,
    UFS2_PIGGY,
} ufs_t;

/*
 * UFS1/UFS2 SUPERBLOCK structure
 * CG stands for Cylinder Group.
 *
 * Variables prepended with off store offsets relative to
 * base address of a Cylinder Group (CG).
 */
struct ufs_super_block { // supporting either ufs1 or ufs2
    uint8_t  unused[8];
    /* Offset values */
    uint32_t off_backup_sb; // Backup super block
    uint32_t off_group_desc; // Group Descriptor
    uint32_t off_inode_tbl; // Inode table
    uint32_t off_data_block; // First data block
    union {
	struct {  /* Used for UFS1 */
	    uint32_t delta_value; // For calc staggering offset
	    uint32_t cycle_mask; // Mask for staggering offset
	    uint32_t last_written; // Last written time
	    uint32_t nr_frags; // Number of frags in FS
	    uint32_t storable_frags_nr; // Nr of frags that can store data
	} ufs1;
	uint8_t unused1[20];
    };
    uint32_t nr_cyl_groups; // Number of cylinder groups.
    uint32_t block_size; // Block size in bytes.
    uint32_t fragment_size; // Fragment size in bytes.
    uint8_t  unused2[16];
    uint32_t block_addr_mask; // to calculate the address
    uint32_t frag_addr_mask;
    uint32_t block_shift; // to calculate byte address
    uint32_t frag_shift;
    uint32_t nr_contiguous_blk; // max number of continuous blks to alloc
    uint32_t nr_blks_per_cg; // max number of blks per cylinder group
    uint32_t c_blk_frag_shift; // Bits to convert blk and frag address.
    uint32_t c_frag_sect_shift; // Bits to convert frag and sect address.
    uint32_t superblk_size; // Superblock size.
    uint8_t  unused3[76];
    uint32_t inodes_per_cg; // Inodes per cylinder group
    uint32_t frags_per_cg; // Fragments per cylinder group
    union {
	struct { /* Used for UFS2 */
	    uint8_t  unused[888];
	    uint64_t nr_frags; // Number of fragments in FS
	    uint8_t  unused1[232];
	} ufs2;
	uint8_t unused4[1128];
    };
    uint32_t maxlen_isymlink; // Max length of internal symlink
    uint32_t inodes_format; // Format of inodes
    uint8_t  unused5[44];
    uint32_t magic; // Magic value
    uint8_t  pad[160]; // padding up to sector (512 bytes) boundary
} __attribute__((__packed__));

/*
 * Info about UFS1/2 super block.
 */
struct ufs_sb_info {
    uint32_t blocks_per_cg; // Blocks per cylinder group
    uint32_t inodes_per_cg; // Inodes per cylinder group
    uint32_t inode_size;
    uint32_t inodes_per_block; // Inodes per block
    struct { /* UFS1 only! */
	/* Values for calculating staggering offset */
	uint32_t delta_value;
	uint32_t cycle_mask;
    } ufs1;
    uint32_t off_inode_tbl; // Inode table offset.
    uint32_t groups_count; // Number of groups in the fs
    uint32_t addr_shift; // 2 ^ addr_shift = size in bytes of default addr.
    uint32_t c_blk_frag_shift; // Convert blk/frag addr (vice-versa)
    uint32_t maxlen_isymlink; // Max length of internal symlink
    struct inode *(*ufs_iget_by_inr)(struct fs_info *, uint32_t);
    void (*ufs_read_blkaddrs)(struct inode *, char *);
    ufs_t    fs_type; // { UFS1, UFS2, UFS2_PIGGY }
};

/*
 * Get super block info struct
 */
static inline struct ufs_sb_info *UFS_SB(struct fs_info *fs)
{
    return fs->fs_info;
}

/*
 * Convert frag addr to blk addr
 */
static inline block_t frag_to_blk(struct fs_info *fs, uint64_t frag)
{
    return frag >> UFS_SB(fs)->c_blk_frag_shift;
}

/*
 * UFS1 inode structures
 */
struct ufs1_inode {
    uint16_t file_mode;
    uint16_t link_count;
    uint8_t  unused[4];
    uint64_t size;
    uint32_t a_time; // Access time
    uint32_t a_time_nanosec;
    uint32_t m_time; // Modified time
    uint32_t m_time_nanosec;
    uint32_t ch_time; // Change time
    uint32_t ch_time_nanosec;
    uint32_t direct_blk_ptr[12];
    uint32_t indirect_blk_ptr;
    uint32_t double_indirect_blk_ptr;
    uint32_t triple_indirect_blk_ptr;
    uint32_t flags; // Status flags
    uint32_t blocks_held; // Blocks held
    uint32_t generation_nrb; // (NFS)
    uint32_t used_id;
    uint32_t group_id;
    uint8_t  unused1[8];
} __attribute__((__packed__));

/*
 * UFS2 inode structures
 */
struct ufs2_inode {
    uint16_t file_mode;
    uint16_t link_count;
    uint32_t user_id;
    uint32_t group_id;
    uint32_t inode_blocksize;
    uint64_t size;
    uint64_t bytes_held;
    uint64_t a_time; // Access time
    uint64_t m_time; // Modified time
    uint64_t ch_time; // Change time
    uint64_t creat_time; // Creation time
    uint32_t a_time_nanosec;
    uint32_t m_time_nanosec;
    uint32_t ch_time_nanosec;
    uint32_t creat_time_nanosec;
    uint32_t generation_nrb; // (NFS)
    uint32_t kernel_flags;
    uint32_t flags;
    uint32_t ext_attr_size; // Extended attrib size.
    uint64_t ext_direct_blk_ptrs[2]; // Ext. attrib blk pointers.
    uint64_t direct_blk_ptr[12];
    uint64_t indirect_blk_ptr;
    uint64_t double_indirect_blk_ptr;
    uint64_t triple_indirect_blk_ptr;
    uint8_t  unused[24];
} __attribute__((__packed__));

#define PVT(p) ((struct ufs_inode_pvt *) p->pvt)

struct ufs_inode_pvt {
    uint64_t direct_blk_ptr[12];
    uint64_t indirect_blk_ptr;
    uint64_t double_indirect_blk_ptr;
    uint64_t triple_indirect_blk_ptr;
};

struct ufs_dir_entry {
    uint32_t inode_value;
    uint16_t dir_entry_len;
    uint8_t  file_type;
    uint8_t  name_length;
    uint8_t  name[1]; // Dir names are null terminated!!!
} __attribute__((__packed__));

enum inode_type_flags {
    UFS_INO_FIFO	= 0x1000,
    UFS_INO_CHARDEV	= 0x2000,
    UFS_INO_DIRECTORY 	= 0x4000,
    UFS_INO_BLOCKDEV	= 0x6000,
    UFS_INO_RFILE	= 0x8000,
    UFS_INO_SYMLINK	= 0xA000,
    UFS_INO_UNIXSOCKET 	= 0xC000,
};

enum dir_type_flags {
    UFS_DTYPE_UNKNOWN	= 0,
    UFS_DTYPE_FIFO 	= 1,
    UFS_DTYPE_CHARDEV	= 2,
    UFS_DTYPE_DIR 	= 4,
    UFS_DTYPE_BLOCK	= 6,
    UFS_DTYPE_RFILE	= 8,
    UFS_DTYPE_SYMLINK 	= 10,
    UFS_DTYPE_SOCKET	= 12,
    UFS_DTYPE_WHITEOUT 	= 14,
};

/* Functions from bmap.c */
extern uint64_t ufs_bmap (struct inode *, block_t, size_t *);
extern int ufs_next_extent(struct inode *, uint32_t);

#define ufs_debug dprintf
//extern void ufs_checking (struct fs_info *);

#endif /* _UFS_H_ */
