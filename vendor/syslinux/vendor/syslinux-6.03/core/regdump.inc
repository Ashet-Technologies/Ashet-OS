;; -----------------------------------------------------------------------
;;
;;   Copyright 2003-2008 H. Peter Anvin - All Rights Reserved
;;
;;   This program is free software; you can redistribute it and/or modify
;;   it under the terms of the GNU General Public License as published by
;;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;;   Boston MA 02111-1307, USA; either version 2 of the License, or
;;   (at your option) any later version; incorporated herein by reference.
;;
;; -----------------------------------------------------------------------

;;
;; regdump.inc
;;
;; Dump as much as possible of the register state; for debugging
;;

disk_dumpregs:
	mov ah,02h
	call dumpregs
	int 13h
	ret

dumpregs:
	push gs
	push fs
	push es
	push ds
	push ss
	push cs
	pushad
	pushfd

	push cs
	pop ds

	mov bp,sp
	mov di,regnames

	mov cx,9		; 9 32-bit registers
.reg8:
	mov si,[di]
	inc di
	inc di
	call writestr
	mov eax,[bp]
	add bp,4
	call writehex8
	loop .reg8

	mov cx,7		; 6 16-bit registers
.reg4:
	mov si,[di]
	inc di
	inc di
	call writestr
	mov eax,[bp]
	inc bp
	inc bp
	call writehex4
	loop .reg4

	call crlf

	popfd
	popad
	add sp,4		; Skip CS, SS
	pop ds
	pop es
	pop fs
	pop gs
	ret

regnames:
	dw .eflags
	dw .edi
	dw .esi
	dw .ebp
	dw .esp
	dw .ebx
	dw .edx
	dw .ecx
	dw .eax
	dw .cs
	dw .ss
	dw .ds
	dw .es
	dw .fs
	dw .gs
	dw .ip

.eflags	db 'EFL: ', 0
.edi	db 13,10,'EDI: ', 0
.esi	db ' ESI: ', 0
.ebp	db ' EBP: ', 0
.esp	db ' ESP: ', 0
.ebx	db 13,10,'EBX: ', 0
.edx	db ' EDX: ', 0
.ecx	db ' ECX: ', 0
.eax	db ' EAX: ', 0
.cs	db 13,10,'CS: ',0
.ss	db ' SS: ',0
.ds	db ' DS: ',0
.es	db ' ES: ',0
.fs	db ' FS: ',0
.gs	db ' GS: ',0
.ip	db ' IP: ',0
