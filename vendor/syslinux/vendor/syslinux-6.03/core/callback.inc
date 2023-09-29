;; -----------------------------------------------------------------------
;;
;;   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
;;   Copyright 2009 Intel Corporation; author: H. Peter Anvin
;;
;;   This program is free software; you can redistribute it and/or modify
;;   it under the terms of the GNU General Public License as published by
;;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;;   Boston MA 02111-1307, USA; either version 2 of the License, or
;;   (at your option) any later version; incorporated herein by reference.
;;
;; -----------------------------------------------------------------------

;;
;; callback.inc
;;
;; Callbacks from 32-bit mode to 16-bit mode
;;

;
; 16-bit intcall/farcall handling code
;

;
; 32-bit support code
;
		bits 32
		section .text

;
; Intcall/farcall invocation.  We manifest a structure on the real-mode stack,
; containing the com32sys_t structure from <com32.h> as well as
; the following entries (from low to high address):
; - Target offset
; - Target segment
; - Return offset
; - Return segment (== real mode cs == 0)
; - Return flags
;
		global core_farcall:function hidden
core_farcall:
		mov eax,[esp+1*4]		; CS:IP
		jmp core_syscall

		global core_intcall:function hidden
core_intcall:
		movzx eax,byte [esp+1*4]	; INT number
		mov eax,[eax*4]			; Get CS:IP from low memory

core_syscall:
		pushfd				; Save IF among other things...
		inc dword [CallbackCtr]
		push ebx
		push ebp
		push esi
		push edi
		push dword [CallbackSP]

		cld

		movzx edi,word [word RealModeSSSP]
		movzx ebx,word [word RealModeSSSP+2]
		sub edi,54		; Allocate 54 bytes
		mov [word RealModeSSSP],di
		shl ebx,4
		add edi,ebx		; Create linear address

		mov esi,[esp+8*4]	; Source regs
		xor ecx,ecx
		mov cl,11		; 44 bytes to copy
		rep movsd

		; EAX is already set up to be CS:IP
		stosd			; Save in stack frame
		mov eax,.rm_return	; Return seg:offs
		stosd			; Save in stack frame
		mov eax,[edi-12]	; Return flags
		and eax,0x200ed7	; Mask (potentially) unsafe flags
		mov [edi-12],eax	; Primary flags entry
		stosw			; Return flags

		mov bx,.rm
		jmp enter_rm	; Go to real mode

		bits 16
		section .text16
.rm:
		mov ax,sp
		add ax,9*4+4*2
		mov [CallbackSP],ax
		pop gs
		pop fs
		pop es
		pop ds
		popad
		popfd
		retf				; Invoke routine

.rm_return:
		; We clean up SP here because we don't know if the
		; routine returned with RET, RETF or IRET
		mov sp,[cs:CallbackSP]
		pushfd
		pushad
		push ds
		push es
		push fs
		push gs
		mov ebx,.pm_return
		jmp enter_pm

		; On return, the 44-byte return structure is on the
		; real-mode stack, plus the 10 additional bytes used
		; by the target address (see above.)
		bits 32
		section .text
.pm_return:
		movzx esi,word [word RealModeSSSP]
		movzx eax,word [word RealModeSSSP+2]
		mov edi,[esp+9*4]	; Dest regs
		shl eax,4
		add esi,eax		; Create linear address
		and edi,edi		; NULL pointer?
		jnz .do_copy
.no_copy:	mov edi,esi		; Do a dummy copy-to-self
.do_copy:	xor ecx,ecx
		mov cl,11		; 44 bytes
		rep movsd		; Copy register block

		add dword [word RealModeSSSP],54
					; Remove from stack

		pop dword [CallbackSP]
		dec dword [CallbackCtr]
		jnz .skip
		call [core_pm_hook]
.skip:
		pop edi
		pop esi
		pop ebp
		pop ebx
		popfd
		ret			; Return to 32-bit program

;
; Cfarcall invocation.  We copy the stack frame to the real-mode stack,
; followed by the return CS:IP and the CS:IP of the target function.
; The value of IF is copied from the calling routine.
;
		global core_cfarcall:function hidden
core_cfarcall:
		pushfd				; Save IF among other things...
		inc dword [CallbackCtr]
		push ebx
		push ebp
		push esi
		push edi
		push dword [CallbackSP]

		cld
		mov ecx,[esp+9*4]		; Size of stack frame

		movzx edi,word [word RealModeSSSP]
		movzx ebx,word [word RealModeSSSP+2]
		mov [word CallbackSP],di
		sub edi,ecx		; Allocate space for stack frame
		and edi,~3		; Round
		sub edi,4*3		; Return pointer, return value, EFLAGS
		mov [word RealModeSSSP],di
		shl ebx,4
		add edi,ebx		; Create linear address

		mov eax,[esp+5*4]	; EFLAGS from entry
		and eax,0x202		; IF only
		stosd
		mov eax,[esp+7*4]	; CS:IP
		stosd			; Save to stack frame
		mov eax,.rm_return	; Return seg:off
		stosd
		mov esi,[esp+8*4]	; Stack frame
		mov eax,ecx		; Copy the stack frame
		shr ecx,2
		rep movsd
		mov ecx,eax
		and ecx,3
		rep movsb

		mov bx,.rm
		jmp enter_rm

		bits 16
		section .text16
.rm:
		popfd
		retf
.rm_return:
		mov sp,[cs:CallbackSP]
		mov esi,eax
		mov ebx,.pm_return
		jmp enter_pm

		bits 32
		section .text
.pm_return:
		mov eax,esi
		; EDX already set up to be the RM return value
		pop dword [CallbackSP]
		dec dword [CallbackCtr]
		jnz .skip
		call [core_pm_hook]
.skip:
		pop ebx
		pop ebp
		pop esi
		pop edi
		popfd
		ret

		section .bss16
		alignb 4
		global core_pm_hook
CallbackSP	resd 1			; SP saved during callback
CallbackCtr	resd 1

		bits 16
		section .text16
