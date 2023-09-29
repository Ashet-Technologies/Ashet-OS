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
;; writedec.inc
;;
;; Write decimal numbers to the console
;;

		section .text16
;
; writedec[bwl]: Write an unsigned decimal number in (AL, AX, EAX)
;                to the console
;
writedecb:
		pushad
		movzx eax,al
		jmp short writedec_common
writedecw:
		pushad
		movzx eax,ax
		jmp short writedec_common
writedecl:
		pushad
writedec_common:
		pushfd
		mov ebx,10		; Conversion base
		xor cx,cx		; Number of digits

.cloop:
		mov edx,0
		div ebx
		inc cx
		push dx
		and eax,eax
		jnz .cloop

.dloop:
		pop ax
		add al,'0'
		call writechr
		loop .dloop

		popfd
		popad
		ret

; writechr:
; 		ret
