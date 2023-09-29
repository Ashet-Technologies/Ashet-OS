; -----------------------------------------------------------------------
;
;   Copyright 2005-2008 H. Peter Anvin - All Rights Reserved
;   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;   Boston MA 02111-1307, USA; either version 2 of the License, or
;   (at your option) any later version; incorporated herein by reference.
;
; -----------------------------------------------------------------------

;
; stack.inc
;
; How to reset the stack pointer
;

%ifndef _STACK_INC
%define _STACK_INC

;
; This macro resets the stack pointer (including SS), and sets
; DS == ES == 0, interrupts on, DF = 0.
;
; It takes a 16-bit register that can be safely clobbered as parameter.
;
%macro RESET_STACK_AND_SEGS 1
		xor %1,%1
		mov ds,%1
		mov es,%1
		lss esp,[BaseStack]
		mov dword [PMESP],__stack_end	; Reset PM stack
		sti
		cld
%endmacro

		section .data16
		alignz 4
		global BaseStack:data hidden
BaseStack	dd StackHome		; ESP of the "home" stack pointer
		dw 0			; SS of the "home" stack pointer

		section .text16

%endif ; _STACK_INC
