; -*- fundamental -*- (asm-mode sucks)
; ****************************************************************************
;
;  ldlinux.asm
;
;  A program to boot Linux kernels off an MS-DOS formatted floppy disk.	 This
;  functionality is good to have for installation floppies, where it may
;  be hard to find a functional Linux system to run LILO off.
;
;  This program allows manipulation of the disk to take place entirely
;  from MS-LOSS, and can be especially useful in conjunction with the
;  umsdos filesystem.
;
;   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
;   Copyright 2009 Intel Corporation; author: H. Peter Anvin
;
;  This program is free software; you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;  Boston MA 02111-1307, USA; either version 2 of the License, or
;  (at your option) any later version; incorporated herein by reference.
;
; ****************************************************************************

%define IS_SYSLINUX 1
%include "head.inc"

;
; Some semi-configurable constants... change on your own risk.
;
my_id		equ syslinux_id

		section .rodata
		alignz 4
ROOT_FS_OPS:
		extern vfat_fs_ops
		dd vfat_fs_ops
		extern ext2_fs_ops
		dd ext2_fs_ops
		extern ntfs_fs_ops
		dd ntfs_fs_ops
		extern xfs_fs_ops
		dd xfs_fs_ops
		extern btrfs_fs_ops
		dd btrfs_fs_ops
		extern ufs_fs_ops
		dd ufs_fs_ops
		dd 0

%include "diskfs.inc"
