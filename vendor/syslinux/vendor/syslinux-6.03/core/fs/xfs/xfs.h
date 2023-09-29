/*
 * Copyright (c) 2012-2013 Paulo Alcantara <pcacjr@zytor.com>
 *
 * Some parts borrowed from Linux kernel tree (linux/fs/xfs):
 *
 * Copyright (c) 2000-2005 Silicon Graphics, Inc.
 * All Rights Reserved.
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

#ifndef XFS_H_
#define XFS_H_

#include <disk.h>
#include <fs.h>
#include <dprintf.h>

#include "xfs_types.h"
#include "xfs_ag.h"

#define xfs_error(fmt, args...)						\
    ({									\
	printf("%s:%u: xfs - [ERROR] " fmt "\n", __func__, __LINE__, ## args); \
    })

#define xfs_debug(fmt, args...)						\
    ({									\
	dprintf("%s:%u: xfs - [DEBUG] " fmt "\n", __func__, __LINE__,	\
		## args);						\
    })

struct xfs_fs_info;

#define XFS_INFO(fs) ((struct xfs_fs_info *)((fs)->fs_info))
#define XFS_PVT(ino) ((struct xfs_inode *)((ino)->pvt))

#define XFS_INO_MASK(k)                 (uint32_t)((1ULL << (k)) - 1)
#define XFS_INO_OFFSET_BITS(fs)		(fs)->inopb_shift
#define XFS_INO_AGINO_BITS(fs) \
    (XFS_INFO((fs))->inopb_shift + XFS_INFO((fs))->agblk_shift)

#define XFS_INO_TO_AGINO(fs, i) \
    ((xfs_agino_t)(i) & XFS_INO_MASK(XFS_INO_AGINO_BITS(fs)))

#define XFS_INO_TO_AGNO(fs, ino) \
    ((xfs_agnumber_t)((ino) >> (XFS_INFO((fs))->inopb_shift + \
				XFS_INFO((fs))->agblk_shift)))

#define XFS_INO_TO_OFFSET(fs, i) \
	((int)(i) & XFS_INO_MASK(XFS_INO_OFFSET_BITS(fs)))

#define XFS_AGNO_TO_FSB(fs, agno) \
    ((block_t)((agno) << XFS_INFO((fs))->agblocks_shift))

#define XFS_AGI_OFFS(fs, mp) \
    ((xfs_agi_t *)((uint8_t *)(mp) + 2 * SECTOR_SIZE((fs))))

#define XFS_GET_DIR_INO4(di) \
    (((uint32_t)(di).i[0] << 24) | ((di).i[1] << 16) | ((di).i[2] << 8) | \
		((di).i[3]))

#define XFS_DI_HI(di) \
    (((uint32_t)(di).i[1] << 16) | ((di).i[2] << 8) | ((di).i[3]))

#define XFS_DI_LO(di) \
    (((uint32_t)(di).i[4] << 24) | ((di).i[5] << 16) | ((di).i[6] << 8) | \
		((di).i[7]))

#define XFS_GET_DIR_INO8(di) \
    (((xfs_ino_t)XFS_DI_LO(di) & 0xffffffffULL) | \
     ((xfs_ino_t)XFS_DI_HI(di) << 32))

#define XFS_FSB_TO_AGNO(fs, fsbno) \
    ((xfs_agnumber_t)((fsbno) >> XFS_INFO((fs))->agblk_shift))
#define XFS_FSB_TO_AGBNO(fs, fsbno) \
    ((xfs_agblock_t)((fsbno) & (uint32_t)((1ULL << \
					   XFS_INFO((fs))->agblk_shift) - 1)))

#define agblock_to_bytes(fs, x) \
    ((uint64_t)(x) << BLOCK_SHIFT((fs)))
#define agino_to_bytes(fs, x) \
    ((uint64_t)(x) << XFS_INFO((fs))->inode_shift)
#define agnumber_to_bytes(fs, x) \
    agblock_to_bytes(fs, (uint64_t)(x) * XFS_INFO((fs))->agblocks)
#define fsblock_to_bytes(fs,x)				\
    (agnumber_to_bytes(fs, XFS_FSB_TO_AGNO(fs, (x))) +	\
     agblock_to_bytes(fs, XFS_FSB_TO_AGBNO(fs, (x))))
#define ino_to_bytes(fs, x)			   \
    (agnumber_to_bytes(fs, XFS_INO_TO_AGNO(fs, (x))) +	\
     agino_to_bytes(fs, XFS_INO_TO_AGINO(fs, (x))))

/* Superblock's LBA */
#define XFS_SB_DADDR ((xfs_daddr_t)0) /* daddr in filesystem/ag */

/* Magic numbers */
#define	XFS_AGI_MAGIC 		"XAGI"
#define XFS_IBT_MAGIC 		"IABT"
#define XFS_DINODE_MAGIC	"IN"

#define XFS_DIR2_BLOCK_MAGIC    0x58443242U      /* XD2B: single block dirs */
#define XFS_DIR2_DATA_MAGIC     0x58443244U      /* XD2D: multiblock dirs */
#define XFS_DIR2_FREE_MAGIC     0x58443246U      /* XD2F: free index blocks */

#define XFS_DIR2_NULL_DATAPTR   ((uint32_t)0)

/* File types and modes */
#define S_IFMT  	00170000
#define S_IFSOCK 	0140000
#define S_IFLNK 	0120000
#define S_IFREG  	0100000
#define S_IFBLK  	0060000
#define S_IFDIR  	0040000
#define S_IFCHR  	0020000
#define S_IFIFO  	0010000
#define S_ISUID  	0004000
#define S_ISGID  	0002000
#define S_ISVTX  	0001000

#define MAXPATHLEN 1024
/*
 * NOTE: The fields in the superblock are stored in big-endian format on disk.
 */
typedef struct xfs_sb {
    uint32_t	sb_magicnum;	/* magic number == XFS_SB_MAGIC */
    uint32_t	sb_blocksize;	/* logical block size, bytes */
    xfs_drfsbno_t	sb_dblocks;	/* number of data blocks */
    xfs_drfsbno_t	sb_rblocks;	/* number of realtime blocks */
    xfs_drtbno_t	sb_rextents;	/* number of realtime extents */
    uuid_t		sb_uuid;	/* file system unique id */
    xfs_dfsbno_t	sb_logstart;	/* starting block of log if internal */
    xfs_ino_t	sb_rootino;	/* root inode number */
    xfs_ino_t	sb_rbmino;	/* bitmap inode for realtime extents */
    xfs_ino_t	sb_rsumino;	/* summary inode for rt bitmap */
    xfs_agblock_t	sb_rextsize;	/* realtime extent size, blocks */
    xfs_agblock_t	sb_agblocks;	/* size of an allocation group */
    xfs_agnumber_t	sb_agcount;	/* number of allocation groups */
    xfs_extlen_t	sb_rbmblocks;	/* number of rt bitmap blocks */
    xfs_extlen_t	sb_logblocks;	/* number of log blocks */
    uint16_t	sb_versionnum;	/* header version == XFS_SB_VERSION */
    uint16_t	sb_sectsize;	/* volume sector size, bytes */
    uint16_t	sb_inodesize;	/* inode size, bytes */
    uint16_t	sb_inopblock;	/* inodes per block */
    char	sb_fname[12];	/* file system name */
    uint8_t	sb_blocklog;	/* log2 of sb_blocksize */
    uint8_t	sb_sectlog;	/* log2 of sb_sectsize */
    uint8_t	sb_inodelog;	/* log2 of sb_inodesize */
    uint8_t	sb_inopblog;	/* log2 of sb_inopblock */
    uint8_t	sb_agblklog;	/* log2 of sb_agblocks (rounded up) */
    uint8_t	sb_rextslog;	/* log2 of sb_rextents */
    uint8_t	sb_inprogress;	/* mkfs is in progress, don't mount */
    uint8_t	sb_imax_pct;	/* max % of fs for inode space */
					/* statistics */
    /*
     * These fields must remain contiguous.  If you really
     * want to change their layout, make sure you fix the
     * code in xfs_trans_apply_sb_deltas().
     */
    uint64_t	sb_icount;	/* allocated inodes */
    uint64_t	sb_ifree;	/* free inodes */
    uint64_t	sb_fdblocks;	/* free data blocks */
    uint64_t	sb_frextents;	/* free realtime extents */
    /*
     * End contiguous fields.
     */
    xfs_ino_t	sb_uquotino;	/* user quota inode */
    xfs_ino_t	sb_gquotino;	/* group quota inode */
    uint16_t	sb_qflags;	/* quota flags */
    uint8_t	sb_flags;	/* misc. flags */
    uint8_t	sb_shared_vn;	/* shared version number */
    xfs_extlen_t	sb_inoalignmt;	/* inode chunk alignment, fsblocks */
    uint32_t	sb_unit;	/* stripe or raid unit */
    uint32_t	sb_width;	/* stripe or raid width */
    uint8_t	sb_dirblklog;	/* log2 of dir block size (fsbs) */
    uint8_t	sb_logsectlog;	/* log2 of the log sector size */
    uint16_t	sb_logsectsize;	/* sector size for the log, bytes */
    uint32_t	sb_logsunit;	/* stripe unit size for the log */
    uint32_t	sb_features2;	/* additional feature bits */

    /*
     * bad features2 field as a result of failing to pad the sb
     * structure to 64 bits. Some machines will be using this field
     * for features2 bits. Easiest just to mark it bad and not use
     * it for anything else.
     */
    uint32_t	sb_bad_features2;
    uint8_t	pad[304]; /* must be padded to a sector boundary */
} __attribute__((__packed__)) xfs_sb_t;

/* In-memory structure that stores filesystem-specific information.
 * The information stored is basically retrieved from the XFS superblock
 * to be used statically around the driver.
 */
struct xfs_fs_info {
    uint32_t 		blocksize; /* Filesystem block size */
    uint8_t		block_shift; /* Filesystem block size in bits */
    uint32_t		dirblksize;
    uint8_t		dirblklog;
    uint8_t		inopb_shift;
    uint8_t		agblk_shift;
    uint32_t		dirleafblk;

    /* AG number bits (MSB of the inode number) */
    uint8_t		ag_number_ino_shift;

    xfs_ino_t 		rootino; /* Root inode number for the filesystem */
    xfs_agblock_t	agblocks; /* Size of each AG in blocks */
    uint8_t		agblocks_shift; /* agblocks in bits */
    xfs_agnumber_t	agcount; /* Number of AGs in the filesytem */
    uint16_t		inodesize; /* Size of the inode in bytes */
    uint8_t		inode_shift; /* Inode size in bits */
} __attribute__((__packed__));

typedef struct xfs_agi {
	/*
	 * Common allocation group header information
	 */
    uint32_t		agi_magicnum;	/* magic number == XFS_AGI_MAGIC */
    uint32_t		agi_versionnum;	/* header version == XFS_AGI_VERSION */
    uint32_t		agi_seqno;	/* sequence # starting from 0 */
    uint32_t		agi_length;	/* size in blocks of a.g. */
    /*
     * Inode information
     * Inodes are mapped by interpreting the inode number, so no
     * mapping data is needed here.
     */
    uint32_t		agi_count;	/* count of allocated inodes */
    uint32_t		agi_root;	/* root of inode btree */
    uint32_t		agi_level;	/* levels in inode btree */
    uint32_t		agi_freecount;	/* number of free inodes */
    uint32_t		agi_newino;	/* new inode just allocated */
    uint32_t		agi_dirino;	/* last directory inode chunk */
    /*
     * Hash table of inodes which have been unlinked but are
     * still being referenced.
     */
    uint32_t		agi_unlinked[XFS_AGI_UNLINKED_BUCKETS];
} __attribute__((__packed__)) xfs_agi_t;

/*
 * Bmap btree record and extent descriptor.
 *  l0:63 is an extent flag (value 1 indicates non-normal).
 *  l0:9-62 are startoff.
 *  l0:0-8 and l1:21-63 are startblock.
 *  l1:0-20 are blockcount.
 */
typedef struct xfs_bmbt_rec {
    uint64_t l0;
    uint64_t l1;
} __attribute__((__packed__)) xfs_bmbt_rec_t;

typedef xfs_bmbt_rec_t xfs_bmdr_rec_t;

/*
 * Possible extent states.
 */
typedef enum {
    XFS_EXT_NORM,
    XFS_EXT_UNWRITTEN,
    XFS_EXT_DMAPI_OFFLINE,
    XFS_EXT_INVALID,
} xfs_exntst_t;

typedef struct xfs_bmbt_irec
{
    xfs_fileoff_t br_startoff;    /* starting file offset */
    xfs_fsblock_t br_startblock;  /* starting block number */
    xfs_filblks_t br_blockcount;  /* number of blocks */
    xfs_exntst_t  br_state;       /* extent state */
} __attribute__((__packed__)) xfs_bmbt_irec_t;

static inline void bmbt_irec_get(xfs_bmbt_irec_t *dest,
				 const xfs_bmbt_rec_t *src)
{
    uint64_t l0, l1;

    l0 = be64_to_cpu(src->l0);
    l1 = be64_to_cpu(src->l1);

    dest->br_startoff = ((xfs_fileoff_t)l0 & 0x7ffffffffffffe00ULL) >> 9;
    dest->br_startblock = (((xfs_fsblock_t)l0 & 0x00000000000001ffULL) << 43) |
                          (((xfs_fsblock_t)l1) >> 21);
    dest->br_blockcount = (xfs_filblks_t)(l1 & 0x00000000001fffffULL);
    dest->br_state = (l0 & 0x8000000000000000ULL) ?
					XFS_EXT_UNWRITTEN : XFS_EXT_NORM;
}

typedef struct xfs_timestamp {
    int32_t t_sec;
    int32_t t_nsec;
} __attribute__((__packed__)) xfs_timestamp_t;

/*
 * Fork identifiers.
 */
#define XFS_DATA_FORK 0
#define xFS_ATTR_FORK 1

typedef enum xfs_dinode_fmt {
    XFS_DINODE_FMT_DEV,
    XFS_DINODE_FMT_LOCAL,
    XFS_DINODE_FMT_EXTENTS,
    XFS_DINODE_FMT_BTREE,
    XFS_DINODE_FMT_UUID,
} xfs_dinode_fmt_t;

typedef struct xfs_dinode {
    uint16_t		di_magic;	/* inode magic # = XFS_DINODE_MAGIC */
    uint16_t		di_mode;	/* mode and type of file */
    uint8_t		di_version;	/* inode version */
    uint8_t		di_format;	/* format of di_c data */
    uint16_t		di_onlink;	/* old number of links to file */
    uint32_t		di_uid;		/* owner's user id */
    uint32_t		di_gid;		/* owner's group id */
    uint32_t		di_nlink;	/* number of links to file */
    uint16_t		di_projid_lo;	/* lower part of owner's project id */
    uint16_t		di_projid_hi;	/* higher part owner's project id */
    uint8_t		di_pad[6];	/* unused, zeroed space */
    uint16_t		di_flushiter;	/* incremented on flush */
    xfs_timestamp_t	di_atime;	/* time last accessed */
    xfs_timestamp_t	di_mtime;	/* time last modified */
    xfs_timestamp_t	di_ctime;	/* time created/inode modified */
    uint64_t		di_size;	/* number of bytes in file */
    uint64_t		di_nblocks;	/* # of direct & btree blocks used */
    uint32_t		di_extsize;	/* basic/minimum extent size for file */
    uint32_t		di_nextents;	/* number of extents in data fork */
    uint16_t		di_anextents;	/* number of extents in attribute fork*/
    uint8_t		di_forkoff;	/* attr fork offs, <<3 for 64b align */
    int8_t		di_aformat;	/* format of attr fork's data */
    uint32_t		di_dmevmask;	/* DMIG event mask */
    uint16_t		di_dmstate;	/* DMIG state info */
    uint16_t		di_flags;	/* random flags, XFS_DIFLAG_... */
    uint32_t		di_gen;		/* generation number */

    /* di_next_unlinked is the only non-core field in the old dinode */
    uint32_t		di_next_unlinked;/* agi unlinked list ptr */
    uint8_t		di_literal_area[1];
} __attribute__((packed)) xfs_dinode_t;

/*
 * Inode size for given fs.
 */
#define XFS_LITINO(fs) \
        ((int)((XFS_INFO(fs)->inodesize) - sizeof(struct xfs_dinode) - 1))

#define XFS_BROOT_SIZE_ADJ \
        (XFS_BTREE_LBLOCK_LEN - sizeof(xfs_bmdr_block_t))

/*
 * Inode data & attribute fork sizes, per inode.
 */
#define XFS_DFORK_Q(dip)	((dip)->di_forkoff != 0)
#define XFS_DFORK_BOFF(dip)	((int)((dip)->di_forkoff << 3))

#define XFS_DFORK_DSIZE(dip, fs) \
        (XFS_DFORK_Q(dip) ? \
                XFS_DFORK_BOFF(dip) : \
                XFS_LITINO(fs))
#define XFS_DFORK_ASIZE(dip, fs) \
        (XFS_DFORK_Q(dip) ? \
                XFS_LITINO(fs) - XFS_DFORK_BOFF(dip) : \
                0)
#define XFS_DFORK_SIZE(dip, fs, w) \
        ((w) == XFS_DATA_FORK ? \
                XFS_DFORK_DSIZE(dip, fs) : \
                XFS_DFORK_ASIZE(dip, fs))

struct xfs_inode {
    xfs_agblock_t 	i_agblock;
    block_t		i_ino_blk;
    uint64_t		i_block_offset;
    uint64_t		i_offset;
    uint32_t		i_cur_extent;
    uint32_t		i_btree_offset;
    uint16_t		i_leaf_ent_offset;
};

typedef struct { uint8_t i[8]; } __attribute__((__packed__)) xfs_dir2_ino8_t;
typedef struct { uint8_t i[4]; } __attribute__((__packed__)) xfs_dir2_ino4_t;

typedef union {
    xfs_dir2_ino8_t i8;
    xfs_dir2_ino4_t i4;
} __attribute__((__packed__)) xfs_dir2_inou_t;

typedef struct { uint8_t i[2]; } __attribute__((__packed__)) xfs_dir2_sf_off_t;

typedef struct xfs_dir2_sf_hdr {
    uint8_t		count;		/* count of entries */
    uint8_t           	i8count;        /* count of 8-byte inode #s */
    xfs_dir2_inou_t     parent;         /* parent dir inode number */
} __attribute__((__packed__)) xfs_dir2_sf_hdr_t;

typedef struct xfs_dir2_sf_entry {
    uint8_t             namelen;        /* actual name length */
    xfs_dir2_sf_off_t   offset;         /* saved offset */
    uint8_t             name[1];        /* name, variable size */
    xfs_dir2_inou_t	inumber;	/* inode number, var. offset */
} __attribute__((__packed__)) xfs_dir2_sf_entry_t;

typedef struct xfs_dir2_sf {
    xfs_dir2_sf_hdr_t       hdr;            /* shortform header */
    xfs_dir2_sf_entry_t     list[1];        /* shortform entries */
} __attribute__((__packed__)) xfs_dir2_sf_t;

typedef xfs_ino_t	xfs_intino_t;

static inline xfs_intino_t xfs_dir2_sf_get_inumber(xfs_dir2_sf_t *sfp,
						   xfs_dir2_inou_t *from)
{
    return ((sfp)->hdr.i8count == 0 ? \
	    (xfs_intino_t)XFS_GET_DIR_INO4((from)->i4) : \
	    (xfs_intino_t)XFS_GET_DIR_INO8((from)->i8));
}

/*
 * DIR2 Data block structures.
 *
 * A pure data block looks like the following drawing on disk:
 *
 *    +-------------------------------------------------+
 *    | xfs_dir2_data_hdr_t                             |
 *    +-------------------------------------------------+
 *    | xfs_dir2_data_entry_t OR xfs_dir2_data_unused_t |
 *    | xfs_dir2_data_entry_t OR xfs_dir2_data_unused_t |
 *    | xfs_dir2_data_entry_t OR xfs_dir2_data_unused_t |
 *    | ...                                             |
 *    +-------------------------------------------------+
 *    | unused space                                    |
 *    +-------------------------------------------------+
 *
 * As all the entries are variable size structure the accessors below should
 * be used to iterate over them.
 *
 * In addition to the pure data blocks for the data and node formats.
 * most structures are also used for the combined data/freespace "block"
 * format below.
 */
#define XFS_DIR2_DATA_ALIGN_LOG 3
#define XFS_DIR2_DATA_ALIGN     (1 << XFS_DIR2_DATA_ALIGN_LOG)
#define XFS_DIR2_DATA_FREE_TAG  0xffff
#define XFS_DIR2_DATA_FD_COUNT  3

/*
 * Directory address space divided into sections.
 * spaces separated by 32GB.
 */
#define XFS_DIR2_SPACE_SIZE	(1ULL << (32 + XFS_DIR2_DATA_ALIGN_LOG))

typedef struct xfs_dir2_data_free {
    uint16_t offset;
    uint16_t length;
} __attribute__((__packed__)) xfs_dir2_data_free_t;

typedef struct xfs_dir2_data_hdr {
    uint32_t magic;
    xfs_dir2_data_free_t bestfree[XFS_DIR2_DATA_FD_COUNT];
} __attribute__((__packed__)) xfs_dir2_data_hdr_t;

typedef struct xfs_dir2_data_entry {
    uint64_t inumber; /* inode number */
    uint8_t  namelen; /* name length */
    uint8_t  name[];  /* name types, no null */
 /* uint16_t tag; */  /* starting offset of us */
} __attribute__((__packed__)) xfs_dir2_data_entry_t;

typedef struct xfs_dir2_data_unused {
    uint16_t freetag; /* XFS_DIR2_DATA_FREE_TAG */
    uint16_t length;  /* total free length */
                      /* variable offset */
 /* uint16_t tag; */  /* starting offset of us */
} __attribute__((__packed__)) xfs_dir2_data_unused_t;

/**
 * rol32 - rotate a 32-bit value left
 * @word: value to rotate
 * @shift: bits to roll
 */
static inline uint32_t rol32(uint32_t word, signed int shift)
{
    return (word << shift) | (word >> (32 - shift));
}

#define roundup(x, y) (					\
{							\
	const typeof(y) __y = y;			\
	(((x) + (__y - 1)) / __y) * __y;		\
}							\
)

static inline int xfs_dir2_data_entsize(int n)
{
    return (int)roundup(offsetof(struct xfs_dir2_data_entry, name[0]) + n + 
			(unsigned int)sizeof(uint16_t), XFS_DIR2_DATA_ALIGN);
}

static inline uint16_t *
xfs_dir2_data_entry_tag_p(struct xfs_dir2_data_entry *dep)
{
    return (uint16_t *)((char *)dep +
	    xfs_dir2_data_entsize(dep->namelen) - sizeof(uint16_t));
}

static inline uint16_t *
xfs_dir2_data_unused_tag_p(struct xfs_dir2_data_unused *dup)
{
    return (uint16_t *)((char *)dup +
	    be16_to_cpu(dup->length) - sizeof(uint16_t));
}

typedef struct xfs_dir2_block_tail {
    uint32_t 		count;			/* count of leaf entries */
    uint32_t 		stale;			/* count of stale lf entries */
} __attribute__((__packed__)) xfs_dir2_block_tail_t;

static inline struct xfs_dir2_block_tail *
xfs_dir2_block_tail_p(struct xfs_fs_info *fs_info, struct xfs_dir2_data_hdr *hdr)
{
    return ((struct xfs_dir2_block_tail *)
	    ((char *)hdr + fs_info->dirblksize)) - 1;
}

static inline uint32_t
xfs_dir2_db_to_da(struct fs_info *fs, uint32_t db)
{
    return db << XFS_INFO(fs)->dirblklog;
}

static inline int64_t
xfs_dir2_dataptr_to_byte(uint32_t dp)
{
    return (int64_t)dp << XFS_DIR2_DATA_ALIGN_LOG;
}

static inline uint32_t
xfs_dir2_byte_to_db(struct fs_info *fs, int64_t by)
{
    return (uint32_t)
	    (by >> (XFS_INFO(fs)->block_shift + XFS_INFO(fs)->dirblklog));
}

static inline uint32_t
xfs_dir2_dataptr_to_db(struct fs_info *fs, uint32_t dp)
{
    return xfs_dir2_byte_to_db(fs, xfs_dir2_dataptr_to_byte(dp));
}

static inline unsigned int
xfs_dir2_byte_to_off(struct fs_info *fs, int64_t by)
{
    return (unsigned int)(by &
        (( 1 << (XFS_INFO(fs)->block_shift + XFS_INFO(fs)->dirblklog)) - 1));
}

static inline unsigned int
xfs_dir2_dataptr_to_off(struct fs_info *fs, uint32_t dp)
{
    return xfs_dir2_byte_to_off(fs, xfs_dir2_dataptr_to_byte(dp));
}

#define XFS_DIR2_LEAF_SPACE	1
#define XFS_DIR2_LEAF_OFFSET	(XFS_DIR2_LEAF_SPACE * XFS_DIR2_SPACE_SIZE)
#define XFS_DIR2_LEAF_FIRSTDB(fs)	\
	xfs_dir2_byte_to_db(fs, XFS_DIR2_LEAF_OFFSET)

typedef struct xfs_da_blkinfo {
    uint32_t		forw;
    uint32_t 		back;
    uint16_t		magic;
    uint16_t	 	pad;
} __attribute__((__packed__)) xfs_da_blkinfo_t;

typedef struct xfs_dir2_leaf_hdr {
    xfs_da_blkinfo_t	info;
    uint16_t		count;
    uint16_t		stale;
} __attribute__((__packed__)) xfs_dir2_leaf_hdr_t;

typedef struct xfs_dir2_leaf_entry {
    uint32_t		hashval;		/* hash value of name */
    uint32_t		address;		/* address of data entry */
} __attribute__((__packed__)) xfs_dir2_leaf_entry_t;

typedef struct xfs_dir2_leaf {
    xfs_dir2_leaf_hdr_t 	hdr;	/* leaf header */
    xfs_dir2_leaf_entry_t	ents[];	/* entries */
} __attribute__((__packed__)) xfs_dir2_leaf_t;

#define XFS_DA_NODE_MAGIC	0xfebeU	/* magic number: non-leaf blocks */
#define XFS_ATTR_LEAF_MAGIC	0xfbeeU	/* magic number: attribute leaf blks */
#define XFS_DIR2_LEAF1_MAGIC	0xd2f1U /* magic number: v2 dirlf single blks */
#define XFS_DIR2_LEAFN_MAGIC	0xd2ffU	/* magic number: V2 dirlf multi blks */

typedef struct xfs_da_intnode {
    struct xfs_da_node_hdr {	/* constant-structure header block */
	xfs_da_blkinfo_t info;	/* block type, links, etc. */
	uint16_t count;		/* count of active entries */
	uint16_t level;		/* level above leaves (leaf == 0) */
    } hdr;
    struct xfs_da_node_entry {
	uint32_t hashval;	/* hash value for this descendant */
	uint32_t before;	/* Btree block before this key */
    } btree[1];
} __attribute__((__packed__)) xfs_da_intnode_t;

typedef struct xfs_da_node_hdr xfs_da_node_hdr_t;
typedef struct xfs_da_node_entry xfs_da_node_entry_t;

static inline bool xfs_is_valid_magicnum(const xfs_sb_t *sb)
{
    return sb->sb_magicnum == *(uint32_t *)XFS_SB_MAGIC;
}

static inline bool xfs_is_valid_agi(xfs_agi_t *agi)
{
    return agi->agi_magicnum == *(uint32_t *)XFS_AGI_MAGIC;
}

static inline struct inode *xfs_new_inode(struct fs_info *fs)
{
    struct inode *inode;

    inode = alloc_inode(fs, 0, sizeof(struct xfs_inode));
    if (!inode)
	malloc_error("xfs_inode structure");

    return inode;
}

static inline void fill_xfs_inode_pvt(struct fs_info *fs, struct inode *inode,
				      xfs_ino_t ino)
{
    XFS_PVT(inode)->i_agblock =
	agnumber_to_bytes(fs, XFS_INO_TO_AGNO(fs, ino)) >> BLOCK_SHIFT(fs);
    XFS_PVT(inode)->i_ino_blk = ino_to_bytes(fs, ino) >> BLOCK_SHIFT(fs);
    XFS_PVT(inode)->i_block_offset = XFS_INO_TO_OFFSET(XFS_INFO(fs), ino) <<
                                     XFS_INFO(fs)->inode_shift;
}

/*
 * Generic btree header.
 *
 * This is a combination of the actual format used on disk for short and long
 * format btrees. The first three fields are shared by both format, but
 * the pointers are different and should be used with care.
 *
 * To get the size of the actual short or long form headers please use
 * the size macros belows. Never use sizeof(xfs_btree_block);
 */
typedef struct xfs_btree_block {
    uint32_t bb_magic;			/* magic number for block type */
    uint16_t bb_level;			/* 0 is a leaf */
    uint16_t bb_numrecs;		/* current # of data records */
    union {
        struct {
            uint32_t bb_leftsib;
            uint32_t bb_rightsib;
        } s;				/* short form pointers */
        struct {
            uint64_t bb_leftsib;
            uint64_t bb_rightsib;
        } l;				/* long form pointers */
    } bb_u;				/* rest */
} xfs_btree_block_t;

#define XFS_BTREE_SBLOCK_LEN 16 /* size of a short form block */
#define XFS_BTREE_LBLOCK_LEN 24 /* size of a long form block */

/*
 * Bmap root header, on-disk form only.
 */
typedef struct xfs_bmdr_block {
    uint16_t bb_level;		/* 0 is a leaf */
    uint16_t bb_numrecs;	/* current # of data records */
} xfs_bmdr_block_t;

/*
 * Key structure for non-leaf levels of the tree.
 */
typedef struct xfs_bmbt_key {
    uint64_t br_startoff;	/* starting file offset */
} xfs_bmbt_key_t, xfs_bmdr_key_t;

/* btree pointer type */
typedef uint64_t xfs_bmbt_ptr_t, xfs_bmdr_ptr_t;

/*
 * Btree block header size depends on a superblock flag.
 *
 * (not quite yet, but soon)
 */
#define XFS_BMBT_BLOCK_LEN(fs) XFS_BTREE_LBLOCK_LEN

#define XFS_BMBT_REC_ADDR(fs, block, index) \
        ((xfs_bmbt_rec_t *) \
                ((char *)(block) + \
                 XFS_BMBT_BLOCK_LEN(fs) + \
                 ((index) - 1) * sizeof(xfs_bmbt_rec_t)))

#define XFS_BMBT_KEY_ADDR(fs, block, index) \
        ((xfs_bmbt_key_t *) \
                ((char *)(block) + \
                 XFS_BMBT_BLOCK_LEN(fs) + \
                 ((index) - 1) * sizeof(xfs_bmbt_key_t)))

#define XFS_BMBT_PTR_ADDR(fs, block, index, maxrecs) \
        ((xfs_bmbt_ptr_t *) \
                ((char *)(block) + \
                 XFS_BMBT_BLOCK_LEN(fs) + \
                 (maxrecs) * sizeof(xfs_bmbt_key_t) + \
                 ((index) - 1) * sizeof(xfs_bmbt_ptr_t)))

#define XFS_BMDR_REC_ADDR(block, index) \
        ((xfs_bmdr_rec_t *) \
                ((char *)(block) + \
                 sizeof(struct xfs_bmdr_block) + \
                 ((index) - 1) * sizeof(xfs_bmdr_rec_t)))

#define XFS_BMDR_KEY_ADDR(block, index) \
        ((xfs_bmdr_key_t *) \
                ((char *)(block) + \
                 sizeof(struct xfs_bmdr_block) + \
                 ((index) - 1) * sizeof(xfs_bmdr_key_t)))

#define XFS_BMDR_PTR_ADDR(block, index, maxrecs) \
        ((xfs_bmdr_ptr_t *) \
                ((char *)(block) + \
                 sizeof(struct xfs_bmdr_block) + \
                 (maxrecs) * sizeof(xfs_bmdr_key_t) + \
                 ((index) - 1) * sizeof(xfs_bmdr_ptr_t)))

/*
 * Calculate number of records in a bmap btree inode root.
 */
static inline int
xfs_bmdr_maxrecs(int blocklen, int leaf)
{
    blocklen -= sizeof(xfs_bmdr_block_t);

    if (leaf)
        return blocklen / sizeof(xfs_bmdr_rec_t);

    return blocklen / (sizeof(xfs_bmdr_key_t) + sizeof(xfs_bmdr_ptr_t));
}

#endif /* XFS_H_ */
