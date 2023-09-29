/*
 * Taken from Linux kernel tree (linux/fs/xfs)
 *
 * Copyright (c) 2000-2005 Silicon Graphics, Inc.
 * All Rights Reserved.
 *
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
#ifndef XFS_TYPES_H_
#define	XFS_TYPES_H_

#include <stddef.h>

#include <sys/types.h>

typedef enum { B_FALSE,B_TRUE }	boolean_t;
typedef uint32_t		prid_t;		/* project ID */
typedef uint32_t		inst_t;		/* an instruction */

typedef int64_t			xfs_off_t;	/* <file offset> type */
typedef unsigned long long	xfs_ino_t;	/* <inode> type */
typedef int64_t			xfs_daddr_t;	/* <disk address> type */
typedef char *			xfs_caddr_t;	/* <core address> type */
typedef uint32_t			xfs_dev_t;
typedef uint32_t			xfs_nlink_t;

/* __psint_t is the same size as a pointer */
typedef int32_t __psint_t;
typedef uint32_t __psunsigned_t;

typedef uint32_t	xfs_agblock_t;	/* blockno in alloc. group */
typedef	uint32_t	xfs_extlen_t;	/* extent length in blocks */
typedef	uint32_t	xfs_agnumber_t;	/* allocation group number */
typedef int32_t	xfs_extnum_t;	/* # of extents in a file */
typedef int16_t	xfs_aextnum_t;	/* # extents in an attribute fork */
typedef	int64_t	xfs_fsize_t;	/* bytes in a file */
typedef uint64_t	xfs_ufsize_t;	/* unsigned bytes in a file */

typedef	int32_t	xfs_suminfo_t;	/* type of bitmap summary info */
typedef	int32_t	xfs_rtword_t;	/* word type for bitmap manipulations */

typedef	int64_t	xfs_lsn_t;	/* log sequence number */
typedef	int32_t	xfs_tid_t;	/* transaction identifier */

typedef	uint32_t	xfs_dablk_t;	/* dir/attr block number (in file) */
typedef	uint32_t	xfs_dahash_t;	/* dir/attr hash value */

/*
 * These types are 64 bits on disk but are either 32 or 64 bits in memory.
 * Disk based types:
 */
typedef uint64_t	xfs_dfsbno_t;	/* blockno in filesystem (agno|agbno) */
typedef uint64_t	xfs_drfsbno_t;	/* blockno in filesystem (raw) */
typedef	uint64_t	xfs_drtbno_t;	/* extent (block) in realtime area */
typedef	uint64_t	xfs_dfiloff_t;	/* block number in a file */
typedef	uint64_t	xfs_dfilblks_t;	/* number of blocks in a file */

/*
 * Memory based types are conditional.
 */
typedef	uint64_t	xfs_fsblock_t;	/* blockno in filesystem (agno|agbno) */
typedef uint64_t	xfs_rfsblock_t;	/* blockno in filesystem (raw) */
typedef uint64_t	xfs_rtblock_t;	/* extent (block) in realtime area */
typedef	int64_t	xfs_srtblock_t;	/* signed version of xfs_rtblock_t */

typedef uint64_t	xfs_fileoff_t;	/* block number in a file */
typedef int64_t	xfs_sfiloff_t;	/* signed block number in a file */
typedef uint64_t	xfs_filblks_t;	/* number of blocks in a file */

/*
 * Null values for the types.
 */
#define	NULLDFSBNO	((xfs_dfsbno_t)-1)
#define	NULLDRFSBNO	((xfs_drfsbno_t)-1)
#define	NULLDRTBNO	((xfs_drtbno_t)-1)
#define	NULLDFILOFF	((xfs_dfiloff_t)-1)

#define	NULLFSBLOCK	((xfs_fsblock_t)-1)
#define	NULLRFSBLOCK	((xfs_rfsblock_t)-1)
#define	NULLRTBLOCK	((xfs_rtblock_t)-1)
#define	NULLFILEOFF	((xfs_fileoff_t)-1)

#define	NULLAGBLOCK	((xfs_agblock_t)-1)
#define	NULLAGNUMBER	((xfs_agnumber_t)-1)
#define	NULLEXTNUM	((xfs_extnum_t)-1)

#define NULLCOMMITLSN	((xfs_lsn_t)-1)

/*
 * Max values for extlen, extnum, aextnum.
 */
#define	MAXEXTLEN	((xfs_extlen_t)0x001fffff)	/* 21 bits */
#define	MAXEXTNUM	((xfs_extnum_t)0x7fffffff)	/* signed int */
#define	MAXAEXTNUM	((xfs_aextnum_t)0x7fff)		/* signed short */

/*
 * Min numbers of data/attr fork btree root pointers.
 */
#define MINDBTPTRS	3
#define MINABTPTRS	2

/*
 * MAXNAMELEN is the length (including the terminating null) of
 * the longest permissible file (component) name.
 */
#define MAXNAMELEN	256

typedef enum {
	XFS_LOOKUP_EQi, XFS_LOOKUP_LEi, XFS_LOOKUP_GEi
} xfs_lookup_t;

typedef enum {
	XFS_BTNUM_BNOi, XFS_BTNUM_CNTi, XFS_BTNUM_BMAPi, XFS_BTNUM_INOi,
	XFS_BTNUM_MAX
} xfs_btnum_t;

struct xfs_name {
	const unsigned char	*name;
	int			len;
};

#endif	/* XFS_TYPES_H_ */
