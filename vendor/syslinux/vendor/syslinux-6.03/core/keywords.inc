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
;; keywords.inc
;;
;; Common header file for the handling of keyword hash and macros
;;

%ifndef DEPEND		; Generated file
%include "kwdhash.gen"
%endif

%macro keyword 2
	dd hash_%1	; Hash value
	dw 0		; No argument
	dw %2		; Entrypoint
%endmacro

%macro keyword 3
	dd hash_%1	; Hash value
	dw %3		; 16-bit argument
	dw %2		; Entrypoint
%endmacro

%macro keyword 4
	dd hash_%1	; Hash value
	db %3, %4	; 2 8-bit arguments
	dw %2		; Entrypoint
%endmacro

keywd_size	equ 8	; Bytes per keyword

		alignz 4

%define FKeyN(n) (FKeyName+(((n)-1) << FILENAME_MAX_LG2))

keywd_table:
		keyword menu,		pc_comment
		keyword text,		pc_text
		keyword include,	pc_opencmd,	pc_include
		keyword append,		pc_append
		keyword initrd,		pc_filename,	InitRD
		keyword default,	pc_default,	1
		keyword ui,		pc_default,	2
		keyword display,	pc_opencmd,	get_msg_file
		keyword font,		pc_opencmd,	loadfont
		keyword implicit,	pc_setint16,	AllowImplicit
		keyword kbdmap,		pc_opencmd,	loadkeys
		keyword kernel,		pc_kernel,	VK_KERNEL
		keyword linux,		pc_kernel,	VK_LINUX
		keyword boot,		pc_kernel,	VK_BOOT
		keyword bss,		pc_kernel,	VK_BSS
		keyword pxe,		pc_kernel,	VK_PXE
		keyword fdimage,	pc_kernel,	VK_FDIMAGE
		keyword comboot,	pc_kernel,	VK_COMBOOT
		keyword com32,		pc_kernel,	VK_COM32
		keyword config,		pc_kernel,	VK_CONFIG
		keyword label,		pc_label
		keyword prompt,		pc_setint16,	ForcePrompt
		keyword say,		pc_say
		keyword serial,		pc_serial
		keyword console,	pc_setint16,	DisplayCon
		keyword timeout,	pc_timeout,	KbdTimeout
		keyword totaltimeout,	pc_timeout,	TotalTimeout
		keyword ontimeout,	pc_ontimeout
		keyword onerror,	pc_onerror
		keyword allowoptions,	pc_setint16,	AllowOptions
		keyword noescape,	pc_setint16,	NoEscape
		keyword nocomplete,	pc_setint16,	NoComplete
		keyword nohalt,		pc_setint16,	NoHalt
		keyword pxeretry,	pc_setint16,	PXERetry
		keyword f1,		pc_filename,	FKeyN(1)
		keyword f2,		pc_filename,	FKeyN(2)
		keyword f3,		pc_filename,	FKeyN(3)
		keyword f4,		pc_filename,	FKeyN(4)
		keyword f5,		pc_filename,	FKeyN(5)
		keyword f6,		pc_filename,	FKeyN(6)
		keyword f7,		pc_filename,	FKeyN(7)
		keyword f8,		pc_filename,	FKeyN(8)
		keyword f9,		pc_filename,	FKeyN(9)
		keyword f10,		pc_filename,	FKeyN(10)
		keyword f0,		pc_filename,	FKeyN(10)
		keyword f11,		pc_filename,	FKeyN(11)
		keyword f12,		pc_filename,	FKeyN(12)
		keyword ipappend,	pc_sysappend
		keyword sysappend,	pc_sysappend
		keyword localboot,	pc_localboot
%if IS_PXELINUX
		keyword sendcookies,	pc_sendcookies
%endif

keywd_count	equ ($-keywd_table)/keywd_size
