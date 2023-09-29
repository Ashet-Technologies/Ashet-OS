;; -----------------------------------------------------------------------
;;
;;   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
;;   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
;;
;;   This program is free software; you can redistribute it and/or modify
;;   it under the terms of the GNU General Public License as published by
;;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;;   Boston MA 02111-1307, USA; either version 2 of the License, or
;;   (at your option) any later version; incorporated herein by reference.
;;
;; -----------------------------------------------------------------------

;;
;; com32.inc
;;
;; Common code for running a COM32 image
;;

		extern pm_api_vector

;
; Load a COM32 image.  A COM32 image is the 32-bit analogue to a DOS
; .com file.  A COM32 image is loaded at address 0x101000, with %esp
; set to the high end of usable memory.
;
; A COM32 image should begin with the magic bytes:
; B8 FF 4C CD 21, which is "mov eax,0x21cd4cff" in 32-bit mode and
; "mov ax,0x4cff; int 0x21" in 16-bit mode.  This will abort the
; program with an error if run in 16-bit mode.
;
		bits 16
		section .data16

		; Ersatz com32 invocation structure, to make libcom32
		; code run the same if linked to the core.  This is in
		; the .data16 segment so HighMemSize can live here.
		;
		; Danger, Will Robinson: it's not clear the use of
		; core_xfer_buf is safe here.
		global __com32:data hidden
		alignz 4
__entry_esp:
		dd 0				; Dummy to avoid _exit issues
__com32:
		dd 9				; Argument count
		dd 0				; No command line
		dd core_intcall			; Intcall entry point
		dd 0				; Bounce buffer address
		dd 0				; 64K bounce buffer
		dd core_farcall			; Farcall entry point
		dd core_cfarcall		; Cfarcall entry point
HighMemSize	dd 0				; End of memory pointer (bytes)
		dd 0				; No module name
		dd pm_api_vector		; Protected mode functions

		section .uibss
Com32Name	resb FILENAME_MAX

		section .bss16
%ifndef HAVE_CURRENTDIRNAME
		global CurrentDirName:data hidden
CurrentDirName	resb FILENAME_MAX
%endif

		section .text16
