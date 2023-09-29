;; -----------------------------------------------------------------------
;;
;;   Copyright 2009 Intel Corporation; author: H. Peter Anvin
;;
;;   This program is free software; you can redistribute it and/or modify
;;   it under the terms of the GNU General Public License as published by
;;   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
;;   Boston MA 02110-1301, USA; either version 2 of the License, or
;;   (at your option) any later version; incorporated herein by reference.
;;
;; -----------------------------------------------------------------------

;;
;; timer.inc
;;
;; Very simple counting timer
;;
;; This lets us have a simple incrementing variable without worrying
;; about the BIOS_timer variable wrapping around at "midnight" and other
;; weird things.
;;
;; This also maintains a timer variable calibrated in milliseconds
;; (wraparound time = 49.7 days!)
;;

		section .text16

timer_init:
		; Hook INT 1Ch
		mov eax,[BIOS_timer_hook]
		mov [BIOS_timer_next],eax
		mov dword [BIOS_timer_hook],timer_irq
		ret

		global bios_timer_cleanup:function hidden
bios_timer_cleanup:
		; Unhook INT 1Ch
		mov eax,[BIOS_timer_next]
		mov [BIOS_timer_hook],eax
		ret

;
; The specified frequency is 14.31818 MHz/12/65536; this turns out
; to be a period of 54.92542 ms, or 0x36.ece8(187c) hexadecimal.
;
		global timer_irq:function hidden
timer_irq:
		inc dword [cs:__jiffies]
		add word  [cs:__ms_timer_adj],0xece8
		adc dword [cs:__ms_timer],0x36
		jmp 0:0
		global BIOS_timer_next:data hidden
BIOS_timer_next	equ $-4

		section .data16
		alignz 4
		global __jiffies:data hidden, __ms_timer
__jiffies	dd 0			; Clock tick timer
__ms_timer	dd 0			; Millisecond timer
__ms_timer_adj	dw 0			; Millisecond timer correction factor
