; -*- fundamental -*- (asm-mode sucks)
; -----------------------------------------------------------------------
;   
;   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
;   Copyright 2009-2011 Intel Corporation; author: H. Peter Anvin
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
;   Boston MA 02110-1301, USA; either version 2 of the License, or
;   (at your option) any later version; incorporated herein by reference.
;
; -----------------------------------------------------------------------

;
; diskfs.inc
;
; Common code for conventional disk-based filesystems
;

;
; Some semi-configurable constants... change on your own risk.
;
NULLFILE	equ 0			; Null character == empty filename
NULLOFFSET	equ 0			; Position in which to look
retry_count	equ 16			; How patient are we with the disk?
%assign HIGHMEM_SLOP 0			; Avoid this much memory near the top
LDLINUX_MAGIC	equ 0x3eb202fe		; A random number to identify ourselves with

; This indicates the general format of the last few bytes in the boot sector
BS_MAGIC_VER	equ 0x1b << 9

MIN_SECTOR_SHIFT	equ 9
MIN_SECTOR_SIZE		equ (1 << MIN_SECTOR_SHIFT)

; ---------------------------------------------------------------------------
;   BEGIN CODE
; ---------------------------------------------------------------------------

;
; Memory below this point is reserved for the BIOS and the MBR
;
		section .earlybss
		global trackbuf:data hidden
trackbufsize	equ 8192
trackbuf	resb trackbufsize	; Track buffer goes here
		; ends at 2800h

;
; Common bootstrap code for disk-based derivatives
;
%include "diskstart.inc"

;
; Now, everything is "up and running"... patch kaboom for more
; verbosity and using the full screen system
;
		; E9 = JMP NEAR
		mov di,kaboom.patch
		mov al,0e9h
		stosb
		mov ax,kaboom2-2
		sub ax,di
		stosw

;
; If we get to this point ldlinux.c32 failed to run. There's nothing
; left to do but inform that user that something went wrong.
;
enter_command:
auto_boot:
		jmp kaboom

		section .bss16
		alignb 4
ThisKbdTo	resd 1			; Temporary holder for KbdTimeout
ThisTotalTo	resd 1			; Temporary holder for TotalTimeout
KernelExtPtr	resw 1			; During search, final null pointer
FuncFlag	resb 1			; Escape sequences received from keyboard
KernelType	resb 1			; Kernel type, from vkernel, if known
		global KernelName
KernelName	resb FILENAME_MAX	; Mangled name for kernel

		section .text16
;
; COM32 vestigial data structure
;
%include "com32.inc"

;
; Common local boot code
;
%include "localboot.inc"

;
; kaboom2: once everything is loaded, replace the part of kaboom
;	   starting with "kaboom.patch" with this part

kaboom2:
		mov si,err_bootfailed
		pm_call pm_writestr
		cmp byte [kaboom.again+1],18h	; INT 18h version?
		je .int18
		pm_call pm_getchar
		pm_call syslinux_force_text_mode
		int 19h			; And try once more to boot...
.norge:		jmp short .norge	; If int 19h returned; this is the end
.int18:
		pm_call syslinux_force_text_mode
		int 18h
.noreg:		jmp short .noreg	; Nynorsk

; -----------------------------------------------------------------------------
;  Common modules
; -----------------------------------------------------------------------------

%include "common.inc"		; Universal modules

; -----------------------------------------------------------------------------
;  Begin data section
; -----------------------------------------------------------------------------

		section .data16
		global copyright_str
copyright_str   db ' Copyright (C) 1994-'
		asciidec YEAR
		db ' H. Peter Anvin et al', CR, LF, 0
err_bootfailed	db CR, LF, 'Boot failed: please change disks and press '
		db 'a key to continue.', CR, LF, 0

;
; Misc initialized (data) variables
;
%ifdef debug				; This code for debugging only
debug_magic	dw 0D00Dh		; Debug code sentinel
%endif
