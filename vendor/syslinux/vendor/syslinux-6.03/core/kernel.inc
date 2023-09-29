;; -----------------------------------------------------------------------
;;
;;   Copyright 1994-2008 H. Peter Anvin - All Rights Reserved
;;
;;   This program is free software; you can redistribute it and/or modify
;;   it under the terms of the GNU General Public License as published by
;;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;;   Boston MA 02111-1307, USA; either version 2 of the License, or
;;   (at your option) any later version; incorporated herein by reference.
;;
;; -----------------------------------------------------------------------

;;
;; kernel.inc
;;
;; Header file for the kernel interface definitions
;;

%ifndef _KERNEL_INC
%define _KERNEL_INC

;;
;; Structure of the real_mode_seg
;;

		struc real_mode_seg_t
		resb 20h-($-$$)		; org 20h
kern_cmd_magic	resw 1			; 0020 Magic # for command line
kern_cmd_offset resw 1			; 0022 Offset for kernel command line
		resb 497-($-$$)		; org 497d
bs_setupsecs	resb 1			; 01F1 Sectors for setup code (0 -> 4)
bs_rootflags	resw 1			; 01F2 Root readonly flag
bs_syssize	resw 1			; 01F4
bs_swapdev	resw 1			; 01F6 Swap device (obsolete)
bs_ramsize	resw 1			; 01F8 Ramdisk flags, formerly ramdisk size
bs_vidmode	resw 1			; 01FA Video mode
bs_rootdev	resw 1			; 01FC Root device
bs_bootsign	resw 1			; 01FE Boot sector signature (0AA55h)
su_jump		resb 1			; 0200 0EBh
su_jump2	resb 1			; 0201 Size of following header
su_header	resd 1			; 0202 New setup code: header
su_version	resw 1			; 0206 See linux/arch/i386/boot/setup.S
su_switch	resw 1			; 0208
su_setupseg	resw 1			; 020A
su_startsys	resw 1			; 020C
su_kver		resw 1			; 020E Kernel version pointer
su_loader	resb 1			; 0210 Loader ID
su_loadflags	resb 1			; 0211 Load high flag
su_movesize	resw 1			; 0212
su_code32start	resd 1			; 0214 Start of code loaded high
su_ramdiskat	resd 1			; 0218 Start of initial ramdisk
su_ramdisklen	resd 1			; 021C Length of initial ramdisk
su_bsklugeoffs	resw 1			; 0220
su_bsklugeseg	resw 1			; 0222
su_heapend	resw 1			; 0224
su_pad1		resw 1			; 0226
su_cmd_line_ptr	resd 1			; 0228
su_ramdisk_max	resd 1			; 022C
		resb (0f800h-12)-($-$$)
linux_stack	equ $			; F7F4
linux_fdctab	resb 12
cmd_line_here	equ $			; F800 Should be out of the way
		endstruc

;
; Old kernel command line signature
;
CMD_MAGIC	equ 0A33Fh		; Command line magic

;
; If we're loading the command line old-style, we need a smaller
; heap.
;
old_cmd_line_here equ 9800h
old_max_cmd_len   equ 2047
old_linux_fdctab  equ old_cmd_line_here-12
old_linux_stack   equ old_linux_fdctab

;
; Magic number of su_header field
;
HEADER_ID       equ 'HdrS'		; HdrS (in littleendian hex)

;
; Flags for the su_loadflags field
;
LOAD_HIGH	equ 01h			; Large kernel, load high
QUIET_FLAG	equ 20h			; Quiet the kernel
KEEP_SEGMENTS	equ 40h			; Don't reload segments
CAN_USE_HEAP    equ 80h                 ; Boot loader reports heap size

;
; ID codes for various modules
;
syslinux_id	equ 031h		; 3 = SYSLINUX family; 1 = SYSLINUX
pxelinux_id	equ 032h		; 3 = SYSLINUX family; 2 = PXELINUX
isolinux_id	equ 033h		; 3 = SYSLINUX family; 3 = ISOLINUX
extlinux_id	equ 034h		; 3 = SYSLINUX family; 4 = EXTLINUX

;
; Types of vkernels
;
VK_LOCALBOOT	equ -1			; localboot (no actual kernel loaded)
VK_KERNEL	equ 0			; Choose by filename
VK_LINUX	equ 1			; Linux kernel image
VK_BOOT		equ 2			; Boot sector
VK_BSS		equ 3			; BSS boot sector
VK_PXE		equ 4			; PXE NBP
VK_FDIMAGE	equ 5			; Floppy disk image
VK_COMBOOT	equ 6			; COMBOOT image
VK_COM32	equ 7			; COM32 image
VK_CONFIG	equ 8			; Configuration file
VK_TYPES	equ 9			; Number of VK types

%endif ; _KERNEL_INC
