/*
 * linuxioctl.h
 *
 * Wrapper for Linux ioctl definitions, including workarounds
 */

#ifndef LIBINSTALLER_LINUXIOCTL_H
#define LIBINSTALLER_LINUXIOCTL_H

#include <sys/ioctl.h>

#ifdef __linux__

#define statfs _kernel_statfs	/* HACK to deal with broken 2.4 distros */

#include <linux/fd.h>		/* Floppy geometry */
#include <linux/hdreg.h>	/* Hard disk geometry */

#include <linux/fs.h>		/* FIGETBSZ, FIBMAP, FS_IOC_* */

#undef SECTOR_SIZE		/* Defined in msdos_fs.h for no good reason */
#undef SECTOR_BITS

#ifndef FS_IOC_GETFLAGS
/* Old kernel headers, these were once ext2-specific... */
# include <linux/ext2_fs.h>	/* EXT2_IOC_* */

# define FS_IOC_GETFLAGS EXT2_IOC_GETFLAGS
# define FS_IOC_SETFLAGS EXT2_IOC_SETFLAGS

# define FS_IMMUTABLE_FL EXT2_IMMUTABLE_FL

#else

# include <ext2fs/ext2_fs.h>

#endif

#ifndef FAT_IOCTL_GET_ATTRIBUTES
# define FAT_IOCTL_GET_ATTRIBUTES	_IOR('r', 0x10, __u32)
#endif
#ifndef FAT_IOCTL_SET_ATTRIBUTES
# define FAT_IOCTL_SET_ATTRIBUTES	_IOW('r', 0x11, __u32)
#endif

#include <linux/fiemap.h>	/* FIEMAP definitions */

#ifndef FS_IOC_FIEMAP
# define FS_IOC_FIEMAP		_IOWR('f', 11, struct fiemap)
#endif

#undef statfs

#ifndef  BLKGETSIZE64
/* This takes a u64, but the size field says size_t.  Someone screwed big. */
# define BLKGETSIZE64 _IOR(0x12,114,size_t)
#endif

#include <linux/loop.h>

#endif /* __linux__ */

#endif /* LIBINSTALLER_LINUXIOCTL_H */
