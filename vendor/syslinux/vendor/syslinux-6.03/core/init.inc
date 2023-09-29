; -*- fundamental -*-
; -----------------------------------------------------------------------
;
;   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
;   Copyright 2009 Intel Corporation; author: H. Peter Anvin
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;   Boston MA 02111-1307, USA; either version 2 of the License, or
;   (at your option) any later version; incorporated herein by reference.
;
; -----------------------------------------------------------------------

;
; init.inc
;
; Common initialization code (inline)
;

		section .text16
common_init:
		; Initialize PM invocation framework
		call pm_init

%if IS_PXELINUX
		; Save derivative-specific data
		pm_call pm_save_data
%endif

		; Decompress PM code to its target location
		pm_call pm_decompress
		cmp eax,__pm_code_len
		jne kaboom

		extern syslinux_register_bios, init

		pm_call syslinux_register_bios
		pm_call init

;
; The code to decompress the PM code and initialize other segments.
;
		extern _lzo1x_decompress_asm_fast_safe

		section .textnr
		bits 32
pm_decompress:
		push __pm_code_len + 16		; Space for decompressed size
		push esp			; Pointer to previous word
		push __pm_code_start		; Target address
		push dword [lzo_data_size]	; Compressed size
		push dword __pm_code_lma
		call _lzo1x_decompress_asm_fast_safe
		add esp,16
		pop RM_EAX			; Decompressed size

		; Zero bss sections (but not .earlybss, since it may
		; contain already-live data.)
		xor eax,eax
		mov edi,__bss_start
		mov ecx,__bss_dwords
		rep stosd
		mov edi,__bss16_start
		mov ecx,__bss16_dwords
		rep stosd
		mov edi,__high_clear_start	; .uibss, .lowmem
		mov ecx,__high_clear_dwords
		rep stosd

		ret

		section .data16
lzo_data_size	dd 0				; filled in by compressor

		section .text16
		bits 16
