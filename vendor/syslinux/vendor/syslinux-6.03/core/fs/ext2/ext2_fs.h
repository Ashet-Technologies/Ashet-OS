#ifndef __EXT2_FS_H
#define __EXT2_FS_H

#include <stdint.h>

#define	EXT2_SUPER_MAGIC	0xEF53

#define EXT2_GOOD_OLD_REV       0       // The good old (original) format
#define EXT2_DYNAMIC_REV        1       // V2 format w/ dynamic inode sizes
#define EXT2_GOOD_OLD_INODE_SIZE 128

// Special inode numbers
#define	EXT2_BAD_INO		 1	// Bad blocks inode
#define EXT2_ROOT_INO		 2	// Root inode
#define EXT2_BOOT_LOADER_INO	 5	// Boot loader inode
#define EXT2_UNDEL_DIR_INO	 6	// Undelete directory inode
#define EXT3_RESIZE_INO		 7	// Reserved group descriptors inode
#define EXT3_JOURNAL_INO	 8	// Journal inode

// We're readonly, so we only care about incompat features.
#define EXT2_FEATURE_INCOMPAT_COMPRESSION	0x0001
#define EXT2_FEATURE_INCOMPAT_FILETYPE		0x0002
#define EXT3_FEATURE_INCOMPAT_RECOVER		0x0004
#define EXT3_FEATURE_INCOMPAT_JOURNAL_DEV	0x0008
#define EXT2_FEATURE_INCOMPAT_META_BG		0x0010
#define EXT2_FEATURE_INCOMPAT_ANY		0xffffffff

#define EXT2_NDIR_BLOCKS	12
#define	EXT2_IND_BLOCK		EXT2_NDIR_BLOCKS
#define EXT2_DIND_BLOCK		(EXT2_IND_BLOCK+1)
#define	EXT2_TIND_BLOCK		(EXT2_DIND_BLOCK+1)
#define	EXT2_N_BLOCKS		(EXT2_TIND_BLOCK+1)


/* for EXT4 extent */
#define EXT4_EXT_MAGIC     0xf30a
#define EXT4_EXTENTS_FLAG  0x00080000

/*
 * File types and file modes
 */
#define S_IFDIR		0040000	        // Directory
#define S_IFCHR		0020000	        // Character device
#define S_IFBLK		0060000		// Block device
#define S_IFREG		0100000	        // Regular file
#define S_IFIFO		0010000	        // FIFO
#define S_IFLNK		0120000		// Symbolic link
#define S_IFSOCK	0140000		// Socket

#define S_IFSHIFT	12

#define T_IFDIR		(S_IFDIR >> S_IFSHIFT)
#define T_IFCHR		(S_IFCHR >> S_IFSHIFT)
#define T_IFBLK		(S_IFBLK >> S_IFSHIFT)
#define T_IFREG		(S_IFREG >> S_IFSHIFT)
#define T_IFIFO		(S_IFIFO >> S_IFSHIFT)
#define T_IFLNK		(S_IFLNK >> S_IFSHIFT)
#define T_IFSOCK	(S_IFSOCK >> S_IFSHIFT)


#define ext2_group_desc_lg2size 5



/*
 * super block structure:
 * include/linux/ext2_fs.h
 */
struct ext2_super_block {
    uint32_t s_inodes_count;	        /* Inodes count */
    uint32_t s_blocks_count;	        /* Blocks count */
    uint32_t s_r_blocks_count;	        /* Reserved blocks count */
    uint32_t s_free_blocks_count;	/* Free blocks count */
    uint32_t s_free_inodes_count;	/* Free inodes count */
    uint32_t s_first_data_block;	/* First Data Block */
    uint32_t s_log_block_size;	        /* Block size */
    uint32_t s_log_frag_size;	        /* Fragment size */
    uint32_t s_blocks_per_group;	/* # Blocks per group */
    uint32_t s_frags_per_group;	        /* # Fragments per group */
    uint32_t s_inodes_per_group;	/* # Inodes per group */
    uint32_t s_mtime;		        /* Mount time */
    uint32_t s_wtime;		        /* Write time */
    uint16_t s_mnt_count;		/* Mount count */
    int16_t  s_max_mnt_count;	        /* Maximal mount count */
    uint16_t s_magic;		        /* Magic signature */
    uint16_t s_state;		        /* File system state */
    uint16_t s_errors;		        /* Behaviour when detecting errors */
    uint16_t s_minor_rev_level;
    uint32_t s_lastcheck;		/* time of last check */
    uint32_t s_checkinterval;	        /* max. time between checks */
    uint32_t s_creator_os;		/* OS */
    uint32_t s_rev_level;		/* Revision level */
    uint16_t s_def_resuid;		/* Default uid for reserved blocks */
    uint16_t s_def_resgid;		/* Default gid for reserved blocks */

    uint32_t s_first_ino;		/* First non-reserved inode */
    uint16_t s_inode_size;		/* size of inode structure */
    uint16_t s_block_group_nr;	        /* block group # of this superblock */
    uint32_t s_feature_compat;	        /* compatible feature set */
    uint32_t s_feature_incompat;	/* incompatible feature set */
    uint32_t s_feature_ro_compat;	/* readonly-compatible feature set */
    uint8_t  s_uuid[16];		/* 128-bit uuid for volume */
    char  s_volume_name[16];	        /* volume name */
    char  s_last_mounted[64];	        /* directory where last mounted */
    uint32_t s_algorithm_usage_bitmap;  /* For compression */
    uint8_t  s_prealloc_blocks;	        /* Nr of blocks to try to preallocate*/
    uint8_t  s_prealloc_dir_blocks;
    uint16_t s_reserved_gdt_blocks;	/* Per group desc for online growth */
    /*
     * Journaling support valid if EXT4_FEATURE_COMPAT_HAS_JOURNAL set.
     */
    uint8_t  s_journal_uuid[16];	/* uuid of journal superblock */
    uint32_t s_journal_inum;	/* inode number of journal file */
    uint32_t s_journal_dev;		/* device number of journal file */
    uint32_t s_last_orphan;		/* start of list of inodes to delete */
    uint32_t s_hash_seed[4];	/* HTREE hash seed */
    uint8_t  s_def_hash_version;	/* Default hash version to use */
    uint8_t  s_reserved_char_pad;
    uint16_t s_desc_size;		/* size of group descriptor */
    uint32_t s_default_mount_opts;
    uint32_t s_first_meta_bg;	/* First metablock block group */
    uint32_t s_mkfs_time;		/* When the filesystem was created */
    uint32_t s_jnl_blocks[17];	/* Backup of the journal inode */
    /* 64bit support valid if EXT4_FEATURE_COMPAT_64BIT */
    uint32_t s_blocks_count_hi;	/* Blocks count */
    uint32_t s_r_blocks_count_hi;	/* Reserved blocks count */
    uint32_t s_free_blocks_count_hi;/* Free blocks count */
    uint16_t s_min_extra_isize;	/* All inodes have at least # bytes */
    uint16_t s_want_extra_isize;	/* New inodes should reserve # bytes */
    uint32_t s_flags;		/* Miscellaneous flags */
    uint16_t s_raid_stride;		/* RAID stride */
    uint16_t s_mmp_interval;        /* # seconds to wait in MMP checking */
    uint64_t s_mmp_block;           /* Block for multi-mount protection */
    uint32_t s_raid_stripe_width;   /* blocks on all data disks (N*stride)*/
    uint8_t  s_log_groups_per_flex; /* FLEX_BG group size */
    uint8_t  s_reserved_char_pad2;
    uint16_t s_reserved_pad;
    uint32_t s_reserved[162];        /* Padding to the end of the block */
};

/*******************************************************************************
#ifndef DEPEND
#if ext2_super_block_size != 1024
#error ext2_super_block definition bogus
#endif
#endif
*******************************************************************************/

/*
 *  ext2 group desc structure:
 */
struct ext2_group_desc {
    uint32_t bg_block_bitmap;	/* Blocks bitmap block */
    uint32_t bg_inode_bitmap;	/* Inodes bitmap block */
    uint32_t bg_inode_table;	/* Inodes table block */
    uint16_t bg_free_blocks_count;	/* Free blocks count */
    uint16_t bg_free_inodes_count;	/* Free inodes count */
    uint16_t bg_used_dirs_count;	/* Directories count */
    uint16_t bg_pad;
    uint32_t bg_reserved[3];
};

/*******************************************************************************
#ifndef DEPEND
#if ext2_group_desc_size != 32
#error ext2_group_desc definition bogus
#endif
#endif
*******************************************************************************/


/*
 * ext2 inode structure:
 */
struct ext2_inode {
    uint16_t i_mode;		/* File mode */
    uint16_t i_uid;		/* Owner Uid */
    uint32_t i_size;		/* 4: Size in bytes */
    uint32_t i_atime;		/* Access time */
    uint32_t i_ctime;		/* 12: Creation time */
    uint32_t i_mtime;		/* Modification time */
    uint32_t i_dtime;		/* 20: Deletion Time */
    uint16_t i_gid;		/* Group Id */
    uint16_t i_links_count;	/* 24: Links count */
    uint32_t i_blocks;		/* Blocks count */
    uint32_t i_flags;		/* 32: File flags */
    uint32_t l_i_reserved1;
    uint32_t i_block[EXT2_N_BLOCKS];	/* 40: Pointers to blocks */
    uint32_t i_version;		/* File version (for NFS) */
    uint32_t i_file_acl;	/* File ACL */
    uint32_t i_dir_acl;		/* Directory ACL */
    uint32_t i_faddr;		/* Fragment address */
    uint8_t  l_i_frag;	        /* Fragment number */
    uint8_t  l_i_fsize;	        /* Fragment size */
    uint16_t i_pad1;
    uint32_t l_i_reserved2[2];
};

/*******************************************************************************
#ifndef DEPEND
#if ext2_inode_size != 128
#error ext2_inode definition bogus
#endif
#endif
*******************************************************************************/


#define EXT2_NAME_LEN 255
struct ext2_dir_entry {
    unsigned int	d_inode;		/* Inode number */
    unsigned short	d_rec_len;		/* Directory entry length */
    unsigned char	d_name_len;		/* Name length */
    unsigned char	d_file_type;
    char	d_name[EXT2_NAME_LEN];	        /* File name */
};

/*******************************************************************************
#define EXT2_DIR_PAD	 4
#define EXT2_DIR_ROUND	(EXT2_DIR_PAD - 1)
#define EXT2_DIR_REC_LEN(name_len)	(((name_len) + 8 + EXT2_DIR_ROUND) & \
					 ~EXT2_DIR_ROUND)
*******************************************************************************/






/*
 * This is the extent on-disk structure.
 * It's used at the bottom of the tree.
 */
struct ext4_extent {
    uint32_t ee_block;	        /* first logical block extent covers */
    uint16_t ee_len;	        /* number of blocks covered by extent */
    uint16_t ee_start_hi;	/* high 16 bits of physical block */
    uint32_t ee_start_lo;	/* low 32 bits of physical block */
};

/*
 * This is index on-disk structure.
 * It's used at all the levels except the bottom.
 */
struct ext4_extent_idx {
    uint32_t ei_block;	        /* index covers logical blocks from 'block' */
    uint32_t ei_leaf_lo;	/* pointer to the physical block of the next *
				 * level. leaf or next index could be there */
    uint16_t ei_leaf_hi;	/* high 16 bits of physical block */
    uint16_t ei_unused;
};

/*
 * Each block (leaves and indexes), even inode-stored has header.
 */
struct ext4_extent_header {
    uint16_t eh_magic;	        /* probably will support different formats */
    uint16_t eh_entries;	/* number of valid entries */
    uint16_t eh_max;	        /* capacity of store in entries */
    uint16_t eh_depth;	        /* has tree real underlying blocks? */
    uint32_t eh_generation;	/* generation of the tree */
};



#define EXT4_FIRST_EXTENT(header) ( (struct ext4_extent *)(header + 1) )
#define EXT4_FIRST_INDEX(header)  ( (struct ext4_extent_idx *) (header + 1) )


/*
 * The ext2 super block information in memory
 */
struct ext2_sb_info {
    uint32_t s_inodes_per_block;/* Number of inodes per block */
    uint32_t s_inodes_per_group;/* Number of inodes in a group */
    uint32_t s_blocks_per_group;/* Number of blocks in a group */
    uint32_t s_desc_per_block;  /* Number of group descriptors per block */
    uint32_t s_groups_count;    /* Number of groups in the fs */
    uint32_t s_first_data_block;	/* First Data Block */
    int      s_inode_size;
    uint8_t  s_uuid[16];	/* 128-bit uuid for volume */
};

static inline struct ext2_sb_info *EXT2_SB(struct fs_info *fs)
{
    return fs->fs_info;
}

#define EXT2_BLOCKS_PER_GROUP(fs)      (EXT2_SB(fs)->s_blocks_per_group)
#define EXT2_INODES_PER_GROUP(fs)      (EXT2_SB(fs)->s_inodes_per_group)
#define EXT2_INODES_PER_BLOCK(fs)      (EXT2_SB(fs)->s_inodes_per_block)
#define EXT2_DESC_PER_BLOCK(fs)        (EXT2_SB(fs)->s_desc_per_block)

/*
 * ext2 private inode information
 */
struct ext2_pvt_inode {
    union {
	uint32_t i_block[EXT2_N_BLOCKS];
	struct ext4_extent_header i_extent_hdr;
    };
};

#define PVT(i) ((struct ext2_pvt_inode *)((i)->pvt))

/*
 * functions
 */
block_t ext2_bmap(struct inode *, block_t, size_t *);
int ext2_next_extent(struct inode *, uint32_t);

#endif /* ext2_fs.h */
