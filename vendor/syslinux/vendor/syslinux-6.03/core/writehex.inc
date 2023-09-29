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
;; writehex.inc
;;
;; Write hexadecimal numbers to the console
;;

;
; writehex[248]: Write a hex number in (AL, AX, EAX) to the console
;
writehex2:
		pushfd
		pushad
		rol eax,24
		mov cx,2
		jmp short writehex_common
writehex4:
		pushfd
		pushad
		rol eax,16
		mov cx,4
		jmp short writehex_common
writehex8:
		pushfd
		pushad
		mov cx,8
writehex_common:
.loop:		rol eax,4
		push eax
		and al,0Fh
		cmp al,10
		jae .high
.low:		add al,'0'
		jmp short .ischar
.high:		add al,'A'-10
.ischar:	call writechr
		pop eax
		loop .loop
		popad
		popfd
		ret
