; -----------------------------------------------------------------------
;
;   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
;   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;   Bostom MA 02111-1307, USA; either version 2 of the License, or
;   (at your option) any later version; incorporated herein by reference.
;
; -----------------------------------------------------------------------

;
; layout.inc
;
; Memory layout of segments
;

		; Default to 16-bit code
		bits 16

; Memory below 0800h is reserved for the BIOS and the MBR.
BSS_START	equ 0800h

; Text starts at the load address of 07C00h.
TEXT_START	equ 7C00h

;
; 16-bit stack layout
;
; PXELINUX: There are apparently some AMI BIOSes in the field which
; put their BEV stack somewhere below 7C00h (and therefore don't
; handle localboot properly), so avoid that immediate memory region.
; The range that is known to be bad is approximately 75E8..7C00; the
; lower bound is tight.
; 
		global STACK_LEN, STACK_TOP, STACK_BASE
STACK_LEN	equ 4096
%if IS_PXELINUX
STACK_TOP	equ 7000h
%else
STACK_TOP	equ 7c00h
%endif
STACK_BASE	equ STACK_TOP - STACK_LEN

; The secondary BSS section, above the text; we really wish we could
; just make it follow .bcopy32 or hang off the end,
; but it doesn't seem to work that way.
LATEBSS_START	equ 0B800h

;
; 32-bit stack layout
;
STACK32_LEN	equ 64*1024

		section	.stack		nobits write align=4096
		resb STACK32_LEN

;
; The various sections and their relationship
;
		; Use .earlybss for things that MUST be in low memory.
		section .earlybss	nobits write
		section .config		write progbits align=4
		section .replacestub	exec write progbits align=16
		section .gentextnr	exec write nobits align=16
		section .stack16	write nobits align=16

		; Use .bss16 for things that doesn't have to be in low memory;
		; .earlybss should be used for things that absolutely have
		; to be below 0x7c00.
		section .bss16		write nobits align=16

%if 0 ; IS_PXELINUX
		; Warning here: RBFG build 22 randomly overwrites
		; memory location [0x5680,0x576c), possibly more.  It
		; seems that it gets confused and screws up the
		; pointer to its own internal packet buffer and starts
		; writing a received ARP packet into low memory.
		section .rbfg		write nobits
RBFG_brainfuck:	resb 2048		; Bigger than an Ethernet packet...
%endif

		section .init		exec write progbits align=1
		section .text16		exec write progbits align=1
		section .textnr		exec nowrite progbits align=1
		section .bcopyxx.text	exec nowrite progbits align=16
		section .bcopyxx.data	noexec write progbits align=16
		section .data16		noexec write progbits align=16

		section .adv		write nobits align=512

		; .uibss contains bss data which is guaranteed to be
		; safe to clobber during the loading of the image.  This
		; is because while loading the primary image we will clobber
		; the spillover from the last fractional sector load.
		section .uibss		write nobits align=16

		section .savedata	write nobits align=16

		; Symbols from linker script
%macro SECINFO 1
		extern __%1_start, __%1_lma, __%1_end
		extern __%1_len, __%1_dwords
%endmacro
		SECINFO bss16
		SECINFO uibss
		SECINFO config
		SECINFO replacestub
		SECINFO bcopyxx

		SECINFO pm_code
		SECINFO high_clear

		SECINFO bss

		extern free_high_memory

		global _start

		section .text16

;
; Segment assignments in the bottom 640K
; Keep the low-memory footprint as small as possible... overrun is a hard
; failure!
;

serial_buf_size	equ 4096		; Should be a power of 2

;
; Transfer buffer segment: guaranteed to be aligned 64K, used for disk I/O
; One symbol for the segment number, one for the absolute address
;
		extern	xfer_buf_seg
		section .xfer_buf	write nobits align=65536
		global	core_xfer_buf:data hidden
core_xfer_buf	resb 65536

;
; Segment for the real mode code (needed as long as we have a in-kernel
; loader and/or COM16 support.
; One symbol for the segment number, one for the absolute address
;
		extern	real_mode_seg
		section .real_mode	write nobits align=65536
		global	core_real_mode:data hidden
core_real_mode	resb 65536
comboot_seg	equ real_mode_seg	; COMBOOT image loading zone

;
; At the very end, the lowmem heap
;
		extern __lowmem_heap
min_lowmem_heap	equ 65536

		section .text16
