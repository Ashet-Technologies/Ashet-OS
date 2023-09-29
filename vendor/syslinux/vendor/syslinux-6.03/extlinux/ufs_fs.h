/*
 * Taken from Linux kernel tree (linux/fs/ufs)
 * linux/include/linux/ufs_fs.h
 *
 * Copyright (C) 1996
 * Adrian Rodriguez (adrian@franklins-tower.rutgers.edu)
 * Laboratory for Computer Science Research Computing Facility
 * Rutgers, The State University of New Jersey
 *
 * Copyright (c) 2013 Raphael S. Carvalho <raphael.scarv@gmail.com>
 *
 * Clean swab support by Fare <fare@tunes.org>
 * just hope no one is using NNUUXXI on __?64 structure elements
 * 64-bit clean thanks to Maciej W. Rozycki <macro@ds2.pg.gda.pl>
 *
 * 4.4BSD (FreeBSD) support added on February 1st 1998 by
 * Niels Kristian Bech Jensen <nkbj@image.dk> partially based
 * on code by Martin von Loewis <martin@mira.isdn.cs.tu-berlin.de>.
 *
 * NeXTstep support added on February 5th 1998 by
 * Niels Kristian Bech Jensen <nkbj@image.dk>.
 *
 * Write support by Daniel Pirkl <daniel.pirkl@email.cz>
 *
 * HP/UX hfs filesystem support added by
 * Martin K. Petersen <mkp@mkp.net>, August 1999
 *
 * UFS2 (of FreeBSD 5.x) support added by
 * Niraj Kumar <niraj17@iitbombay.org>  , Jan 2004
 *
 */

#ifndef __LINUX_UFS_FS_H
#define __LINUX_UFS_FS_H

#include <inttypes.h>

typedef uint64_t __fs64;
typedef uint32_t __fs32;
typedef uint16_t __fs16;

#define UFS_BBLOCK 0
#define UFS_BBSIZE 8192
#define UFS_SBLOCK 8192
#define UFS_SBSIZE 8192

#define UFS_SECTOR_SIZE 512
#define UFS_SECTOR_BITS 9
#define UFS_MAGIC  0x00011954
#define UFS_MAGIC_BW 0x0f242697
#define UFS2_MAGIC 0x19540119
#define UFS_CIGAM  0x54190100 /* byteswapped MAGIC */

/* Copied from FreeBSD */
/*
 * Each disk drive contains some number of filesystems.
 * A filesystem consists of a number of cylinder groups.
 * Each cylinder group has inodes and data.
 *
 * A filesystem is described by its super-block, which in turn
 * describes the cylinder groups.  The super-block is critical
 * data and is replicated in each cylinder group to protect against
 * catastrophic loss.  This is done at `newfs' time and the critical
 * super-block data does not change, so the copies need not be
 * referenced further unless disaster strikes.
 *
 * For filesystem fs, the offsets of the various blocks of interest
 * are given in the super block as:
 *      [fs->fs_sblkno]         Super-block
 *      [fs->fs_cblkno]         Cylinder group block
 *      [fs->fs_iblkno]         Inode blocks
 *      [fs->fs_dblkno]         Data blocks
 * The beginning of cylinder group cg in fs, is given by
 * the ``cgbase(fs, cg)'' macro.
 *
 * Depending on the architecture and the media, the superblock may
 * reside in any one of four places. For tiny media where every block
 * counts, it is placed at the very front of the partition. Historically,
 * UFS1 placed it 8K from the front to leave room for the disk label and
 * a small bootstrap. For UFS2 it got moved to 64K from the front to leave
 * room for the disk label and a bigger bootstrap, and for really piggy
 * systems we check at 256K from the front if the first three fail. In
 * all cases the size of the superblock will be SBLOCKSIZE. All values are
 * given in byte-offset form, so they do not imply a sector size. The
 * SBLOCKSEARCH specifies the order in which the locations should be searched.
 */
#define SBLOCK_FLOPPY        0
#define SBLOCK_UFS1       8192
#define SBLOCK_UFS2      65536
#define SBLOCK_PIGGY    262144
#define SBLOCKSIZE        8192
#define SBLOCKSEARCH \
        { SBLOCK_UFS2, SBLOCK_UFS1, SBLOCK_FLOPPY, SBLOCK_PIGGY, -1 }

#define	UFS_MAXNAMLEN 255
#define UFS_MAXMNTLEN 512
#define UFS2_MAXMNTLEN 468
#define UFS2_MAXVOLLEN 32
#define UFS_MAXCSBUFS 31
#define UFS_LINK_MAX 32000
/*
#define	UFS2_NOCSPTRS	((128 / sizeof(void *)) - 4)
*/
#define	UFS2_NOCSPTRS	28

/*
 * UFS_DIR_PAD defines the directory entries boundaries
 * (must be a multiple of 4)
 */
#define UFS_DIR_PAD			4
#define UFS_DIR_ROUND			(UFS_DIR_PAD - 1)
#define UFS_DIR_REC_LEN(name_len)	(((name_len) + 1 + 8 + UFS_DIR_ROUND) & ~UFS_DIR_ROUND)

struct ufs_timeval {
	__fs32	tv_sec;
	__fs32	tv_usec;
};

struct ufs_dir_entry {
	__fs32  d_ino;			/* inode number of this entry */
	__fs16  d_reclen;		/* length of this entry */
	union {
		__fs16	d_namlen;		/* actual length of d_name */
		struct {
			__u8	d_type;		/* file type */
			__u8	d_namlen;	/* length of string in d_name */
		} d_44;
	} d_u;
	__u8	d_name[UFS_MAXNAMLEN + 1];	/* file name */
};

struct ufs_csum {
	__fs32	cs_ndir;	/* number of directories */
	__fs32	cs_nbfree;	/* number of free blocks */
	__fs32	cs_nifree;	/* number of free inodes */
	__fs32	cs_nffree;	/* number of free frags */
};
struct ufs2_csum_total {
	__fs64	cs_ndir;	/* number of directories */
	__fs64	cs_nbfree;	/* number of free blocks */
	__fs64	cs_nifree;	/* number of free inodes */
	__fs64	cs_nffree;	/* number of free frags */
	__fs64   cs_numclusters;	/* number of free clusters */
	__fs64   cs_spare[3];	/* future expansion */
};

struct ufs_csum_core {
	__u64	cs_ndir;	/* number of directories */
	__u64	cs_nbfree;	/* number of free blocks */
	__u64	cs_nifree;	/* number of free inodes */
	__u64	cs_nffree;	/* number of free frags */
	__u64   cs_numclusters;	/* number of free clusters */
};

struct ufs_super_block {
	union {
		struct {
			__fs32	fs_link;	/* UNUSED */
		} fs_42;
		struct {
			__fs32	fs_state;	/* file system state flag */
		} fs_sun;
	} fs_u0;
	__fs32	fs_rlink;	/* UNUSED */
	__fs32	fs_sblkno;	/* addr of super-block in filesys */
	__fs32	fs_cblkno;	/* offset of cyl-block in filesys */
	__fs32	fs_iblkno;	/* offset of inode-blocks in filesys */
	__fs32	fs_dblkno;	/* offset of first data after cg */
	__fs32	fs_cgoffset;	/* cylinder group offset in cylinder */
	__fs32	fs_cgmask;	/* used to calc mod fs_ntrak */
	__fs32	fs_time;	/* last time written -- time_t */
	__fs32	fs_size;	/* number of blocks in fs */
	__fs32	fs_dsize;	/* number of data blocks in fs */
	__fs32	fs_ncg;		/* number of cylinder groups */
	__fs32	fs_bsize;	/* size of basic blocks in fs */
	__fs32	fs_fsize;	/* size of frag blocks in fs */
	__fs32	fs_frag;	/* number of frags in a block in fs */
/* these are configuration parameters */
	__fs32	fs_minfree;	/* minimum percentage of free blocks */
	__fs32	fs_rotdelay;	/* num of ms for optimal next block */
	__fs32	fs_rps;		/* disk revolutions per second */
/* these fields can be computed from the others */
	__fs32	fs_bmask;	/* ``blkoff'' calc of blk offsets */
	__fs32	fs_fmask;	/* ``fragoff'' calc of frag offsets */
	__fs32	fs_bshift;	/* ``lblkno'' calc of logical blkno */
	__fs32	fs_fshift;	/* ``numfrags'' calc number of frags */
/* these are configuration parameters */
	__fs32	fs_maxcontig;	/* max number of contiguous blks */
	__fs32	fs_maxbpg;	/* max number of blks per cyl group */
/* these fields can be computed from the others */
	__fs32	fs_fragshift;	/* block to frag shift */
	__fs32	fs_fsbtodb;	/* fsbtodb and dbtofsb shift constant */
	__fs32	fs_sbsize;	/* actual size of super block */
	__fs32	fs_csmask;	/* csum block offset */
	__fs32	fs_csshift;	/* csum block number */
	__fs32	fs_nindir;	/* value of NINDIR */
	__fs32	fs_inopb;	/* value of INOPB */
	__fs32	fs_nspf;	/* value of NSPF */
/* yet another configuration parameter */
	__fs32	fs_optim;	/* optimization preference, see below */
/* these fields are derived from the hardware */
	union {
		struct {
			__fs32	fs_npsect;	/* # sectors/track including spares */
		} fs_sun;
		struct {
			__fs32	fs_state;	/* file system state time stamp */
		} fs_sunx86;
	} fs_u1;
	__fs32	fs_interleave;	/* hardware sector interleave */
	__fs32	fs_trackskew;	/* sector 0 skew, per track */
/* a unique id for this filesystem (currently unused and unmaintained) */
/* In 4.3 Tahoe this space is used by fs_headswitch and fs_trkseek */
/* Neither of those fields is used in the Tahoe code right now but */
/* there could be problems if they are.                            */
	__fs32	fs_id[2];	/* file system id */
/* sizes determined by number of cylinder groups and their sizes */
	__fs32	fs_csaddr;	/* blk addr of cyl grp summary area */
	__fs32	fs_cssize;	/* size of cyl grp summary area */
	__fs32	fs_cgsize;	/* cylinder group size */
/* these fields are derived from the hardware */
	__fs32	fs_ntrak;	/* tracks per cylinder */
	__fs32	fs_nsect;	/* sectors per track */
	__fs32	fs_spc;		/* sectors per cylinder */
/* this comes from the disk driver partitioning */
	__fs32	fs_ncyl;	/* cylinders in file system */
/* these fields can be computed from the others */
	__fs32	fs_cpg;		/* cylinders per group */
	__fs32	fs_ipg;		/* inodes per cylinder group */
	__fs32	fs_fpg;		/* blocks per group * fs_frag */
/* this data must be re-computed after crashes */
	struct ufs_csum fs_cstotal;	/* cylinder summary information */
/* these fields are cleared at mount time */
	__s8	fs_fmod;	/* super block modified flag */
	__s8	fs_clean;	/* file system is clean flag */
	__s8	fs_ronly;	/* mounted read-only flag */
	__s8	fs_flags;
	union {
		struct {
			__s8	fs_fsmnt[UFS_MAXMNTLEN];/* name mounted on */
			__fs32	fs_cgrotor;	/* last cg searched */
			__fs32	fs_csp[UFS_MAXCSBUFS];/*list of fs_cs info buffers */
			__fs32	fs_maxcluster;
			__fs32	fs_cpc;		/* cyl per cycle in postbl */
			__fs16	fs_opostbl[16][8]; /* old rotation block list head */
		} fs_u1;
		struct {
			__s8  fs_fsmnt[UFS2_MAXMNTLEN];	/* name mounted on */
			__u8   fs_volname[UFS2_MAXVOLLEN]; /* volume name */
			__fs64  fs_swuid;		/* system-wide uid */
			__fs32  fs_pad;	/* due to alignment of fs_swuid */
			__fs32   fs_cgrotor;     /* last cg searched */
			__fs32   fs_ocsp[UFS2_NOCSPTRS]; /*list of fs_cs info buffers */
			__fs32   fs_contigdirs;/*# of contiguously allocated dirs */
			__fs32   fs_csp;	/* cg summary info buffer for fs_cs */
			__fs32   fs_maxcluster;
			__fs32   fs_active;/* used by snapshots to track fs */
			__fs32   fs_old_cpc;	/* cyl per cycle in postbl */
			__fs32   fs_maxbsize;/*maximum blocking factor permitted */
			__fs64   fs_sparecon64[17];/*old rotation block list head */
			__fs64   fs_sblockloc; /* byte offset of standard superblock */
			struct  ufs2_csum_total fs_cstotal;/*cylinder summary information*/
			struct  ufs_timeval    fs_time;		/* last time written */
			__fs64    fs_size;		/* number of blocks in fs */
			__fs64    fs_dsize;	/* number of data blocks in fs */
			__fs64   fs_csaddr;	/* blk addr of cyl grp summary area */
			__fs64    fs_pendingblocks;/* blocks in process of being freed */
			__fs32    fs_pendinginodes;/*inodes in process of being freed */
		} fs_u2;
	}  fs_u11;
	union {
		struct {
			__fs32	fs_sparecon[53];/* reserved for future constants */
			__fs32	fs_reclaim;
			__fs32	fs_sparecon2[1];
			__fs32	fs_state;	/* file system state time stamp */
			__fs32	fs_qbmask[2];	/* ~usb_bmask */
			__fs32	fs_qfmask[2];	/* ~usb_fmask */
		} fs_sun;
		struct {
			__fs32	fs_sparecon[53];/* reserved for future constants */
			__fs32	fs_reclaim;
			__fs32	fs_sparecon2[1];
			__fs32	fs_npsect;	/* # sectors/track including spares */
			__fs32	fs_qbmask[2];	/* ~usb_bmask */
			__fs32	fs_qfmask[2];	/* ~usb_fmask */
		} fs_sunx86;
		struct {
			__fs32	fs_sparecon[50];/* reserved for future constants */
			__fs32	fs_contigsumsize;/* size of cluster summary array */
			__fs32	fs_maxsymlinklen;/* max length of an internal symlink */
			__fs32	fs_inodefmt;	/* format of on-disk inodes */
			__fs32	fs_maxfilesize[2];	/* max representable file size */
			__fs32	fs_qbmask[2];	/* ~usb_bmask */
			__fs32	fs_qfmask[2];	/* ~usb_fmask */
			__fs32	fs_state;	/* file system state time stamp */
		} fs_44;
	} fs_u2;
	__fs32	fs_postblformat;	/* format of positional layout tables */
	__fs32	fs_nrpos;		/* number of rotational positions */
	__fs32	fs_postbloff;		/* (__s16) rotation block list head */
	__fs32	fs_rotbloff;		/* (__u8) blocks for each rotation */
	__fs32	fs_magic;		/* magic number */
	__u8	fs_space[1];		/* list of blocks for each rotation */
}; /*struct ufs_super_block*/

#endif
