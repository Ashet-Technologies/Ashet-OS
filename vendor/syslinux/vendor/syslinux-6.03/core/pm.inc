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
;; pm.inc
;;
;; Functions to enter and exit 32-bit protected mode, handle interrupts
;; and cross-mode calls.
;;
;; PM refers to 32-bit flat protected mode; RM to 16-bit real mode.
;;

		bits 16
		section .text16
;
; _pm_call: call PM routine in low memory from RM
;
;	on stack	= PM routine to call (a 32-bit address)
;
;	ECX, ESI, EDI passed to the called function;
;	EAX = EBP in the called function points to the stack frame
;	which includes all registers (which can be changed if desired.)
;
;	All registers and the flags saved/restored
;
;	This routine is invoked by the pm_call macro.
;
_pm_call:
		pushfd
		pushad
		push ds
		push es
		push fs
		push gs
		mov bp,sp
		mov ax,cs
		mov ebx,.pm
		mov ds,ax
		jmp enter_pm

		bits 32
		section .textnr
.pm:
		; EAX points to the top of the RM stack, which is EFLAGS
		test RM_FLAGSH,02h		; RM EFLAGS.IF
		jz .no_sti
		sti
.no_sti:
		call [ebp+4*2+9*4+2]		; Entrypoint on RM stack
		mov bx,.rm
		jmp enter_rm

		bits 16
		section .text16
.rm:
		pop gs
		pop fs
		pop es
		pop ds
		popad
		popfd
		ret 4		; Drop entrypoint

;
; enter_pm: Go to PM with interrupt service configured
;	EBX	  = PM entry point
;	EAX = EBP = on exit, points to the RM stack as a 32-bit value
;	ECX, EDX, ESI, EDI preserved across this routine
;
;	Assumes CS == DS
;
; This routine doesn't enable interrupts, but the target routine
; can enable interrupts by executing STI.
;
		bits 16
		section .text16
enter_pm:
		cli
		xor eax,eax
		mov ds,ax
		mov ax,ss
		mov [RealModeSSSP],sp
		mov [RealModeSSSP+2],ax
		movzx ebp,sp
		shl eax,4
		add ebp,eax		; EBP -> top of real-mode stack
		cld
		call enable_a20

.a20ok:
		mov byte [bcopy_gdt.TSS+5],89h	; Mark TSS unbusy

		lgdt [bcopy_gdt]	; We can use the same GDT just fine
		lidt [PM_IDT_ptr]	; Set up the IDT
		mov eax,cr0
		or al,1
		mov cr0,eax		; Enter protected mode
		jmp PM_CS32:.in_pm

		bits 32
		section .textnr
.in_pm:
		xor eax,eax		; Available for future use...
		mov fs,eax
		mov gs,eax
		lldt ax

		mov al,PM_DS32		; Set up data segments
		mov es,eax
		mov ds,eax
		mov ss,eax

		mov al,PM_TSS		; Be nice to Intel's VT by
		ltr ax			; giving it a valid TR

		mov esp,[PMESP]		; Load protmode %esp
		mov eax,ebp		; EAX -> top of real-mode stack
		jmp ebx			; Go to where we need to go

;
; enter_rm: Return to RM from PM
;
;	BX	= RM entry point (CS = 0)
;	ECX, EDX, ESI, EDI preserved across this routine
;	EAX	clobbered
;	EBP	reserved
;
; This routine doesn't enable interrupts, but the target routine
; can enable interrupts by executing STI.
;
		bits 32
		section .textnr
enter_rm:
		cli
		cld
		mov [PMESP],esp		; Save exit %esp
		jmp PM_CS16:.in_pm16	; Return to 16-bit mode first

		bits 16
		section .text16
.in_pm16:
		mov ax,PM_DS16		; Real-mode-like segment
		mov es,ax
		mov ds,ax
		mov ss,ax
		mov fs,ax
		mov gs,ax

		lidt [RM_IDT_ptr]	; Real-mode IDT (rm needs no GDT)
		xor dx,dx
		mov eax,cr0
		and al,~1
		mov cr0,eax
		jmp 0:.in_rm

.in_rm:					; Back in real mode
		lss sp,[cs:RealModeSSSP]	; Restore stack
		movzx esp,sp		; Make sure the high bits are zero
		mov ds,dx		; Set up sane segments
		mov es,dx
		mov fs,dx
		mov gs,dx
		jmp bx			; Go to whereever we need to go...

		section .data16
		alignz 4

		extern __stack_end
PMESP		dd __stack_end		; Protected-mode ESP

PM_IDT_ptr:	dw 8*256-1		; Length
		dd IDT			; Offset

;
; This is invoked on getting an interrupt in protected mode.  At
; this point, we need to context-switch to real mode and invoke
; the interrupt routine.
;
; When this gets invoked, the registers are saved on the stack and
; AL contains the register number.
;
		bits 32
		section .textnr
pm_irq:
		pushad
		movzx esi,byte [esp+8*4] ; Interrupt number
		inc dword [CallbackCtr]
		mov ebx,.rm
		jmp enter_rm		; Go to real mode

		bits 16
		section .text16
.rm:
		pushf			; Flags on stack
		call far [cs:esi*4]	; Call IVT entry
		mov ebx,.pm
		jmp enter_pm		; Go back to PM

		bits 32
		section .textnr
.pm:
		dec dword [CallbackCtr]
		jnz .skip
		call [core_pm_hook]
.skip:
		popad
		add esp,4		; Drop interrupt number
		iretd

;
; Initially, the core_pm_hook does nothing; it is available for the
; threaded derivatives to run the scheduler, or examine the result from
; interrupt routines.
;
		global core_pm_null_hook
core_pm_null_hook:
		ret

		section .data16
		alignz 4
		global core_pm_hook
core_pm_hook:	dd core_pm_null_hook

		bits 16
		section .text16
;
; Routines to enable and disable (yuck) A20.  These routines are gathered
; from tips from a couple of sources, including the Linux kernel and
; http://www.x86.org/.  The need for the delay to be as large as given here
; is indicated by Donnie Barnes of RedHat, the problematic system being an
; IBM ThinkPad 760EL.
;

		section .data16
		alignz 2
A20Ptr		dw a20_dunno

		section .bss16
		alignb 4
A20Test		resd 1			; Counter for testing A20 status
A20Tries	resb 1			; Times until giving up on A20

		section .text16
enable_a20:
		pushad
		mov byte [cs:A20Tries],255 ; Times to try to make this work

try_enable_a20:

;
; First, see if we are on a system with no A20 gate, or the A20 gate
; is already enabled for us...
;
a20_none:
		call a20_test
		jnz a20_done
		; Otherwise, see if we had something memorized...
		jmp word [cs:A20Ptr]

;
; Next, try the BIOS (INT 15h AX=2401h)
;
a20_dunno:
a20_bios:
		mov word [cs:A20Ptr], a20_bios
		mov ax,2401h
		pushf				; Some BIOSes muck with IF
		int 15h
		popf

		call a20_test
		jnz a20_done

;
; Enable the keyboard controller A20 gate
;
a20_kbc:
		mov dl, 1			; Allow early exit
		call empty_8042
		jnz a20_done			; A20 live, no need to use KBC

		mov word [cs:A20Ptr], a20_kbc	; Starting KBC command sequence

		mov al,0D1h			; Write output port
		out 064h, al
		call empty_8042_uncond

		mov al,0DFh			; A20 on
		out 060h, al
		call empty_8042_uncond

		; Apparently the UHCI spec assumes that A20 toggle
		; ends with a null command (assumed to be for sychronization?)
		; Put it here to see if it helps anything...
		mov al,0FFh			; Null command
		out 064h, al
		call empty_8042_uncond

		; Verify that A20 actually is enabled.  Do that by
		; observing a word in low memory and the same word in
		; the HMA until they are no longer coherent.  Note that
		; we don't do the same check in the disable case, because
		; we don't want to *require* A20 masking (SYSLINUX should
		; work fine without it, if the BIOS does.)
.kbc_wait:	push cx
		xor cx,cx
.kbc_wait_loop:
		call a20_test
		jnz a20_done_pop
		loop .kbc_wait_loop

		pop cx
;
; Running out of options here.  Final attempt: enable the "fast A20 gate"
;
a20_fast:
		mov word [cs:A20Ptr], a20_fast
		in al, 092h
		or al,02h
		and al,~01h			; Don't accidentally reset the machine!
		out 092h, al

.fast_wait:	push cx
		xor cx,cx
.fast_wait_loop:
		call a20_test
		jnz a20_done_pop
		loop .fast_wait_loop

		pop cx

;
; Oh bugger.  A20 is not responding.  Try frobbing it again; eventually give up
; and report failure to the user.
;
		dec byte [cs:A20Tries]
		jnz a20_dunno		; Did we get the wrong type?

		mov si, err_a20
		pm_call pm_writestr
		jmp kaboom

		section .data16
err_a20		db CR, LF, 'A20 gate not responding!', CR, LF, 0
		section .text16

;
; A20 unmasked, proceed...
;
a20_done_pop:	pop cx
a20_done:	popad
		ret

;
; This routine tests if A20 is enabled (ZF = 0).  This routine
; must not destroy any register contents.
;
; The no-write early out avoids the io_delay in the (presumably common)
; case of A20 already enabled (e.g. from a previous call.)
;
a20_test:
		push es
		push cx
		push eax
		mov cx,0FFFFh			; HMA = segment 0FFFFh
		mov es,cx
		mov eax,[cs:A20Test]
		mov cx,32			; Loop count
		jmp .test			; First iteration = early out
.wait:		add eax,0x430aea41		; A large prime number
		mov [cs:A20Test],eax
		io_delay			; Serialize, and fix delay
.test:		cmp eax,[es:A20Test+10h]
		loopz .wait
.done:		pop eax
		pop cx
		pop es
		ret

;
; Routine to empty the 8042 KBC controller.  If dl != 0
; then we will test A20 in the loop and exit if A20 is
; suddenly enabled.
;
empty_8042_uncond:
		xor dl,dl
empty_8042:
		call a20_test
		jz .a20_on
		and dl,dl
		jnz .done
.a20_on:	io_delay
		in al, 064h		; Status port
		test al,1
		jz .no_output
		io_delay
		in al, 060h		; Read input
		jmp short empty_8042
.no_output:
		test al,2
		jnz empty_8042
		io_delay
.done:		ret

;
; This initializes the protected-mode interrupt thunk set
;
		section .text16
pm_init:
		xor edi,edi
		mov bx,IDT
		mov di,IRQStubs

		mov eax,7aeb006ah	; push byte .. jmp short ..

		mov cx,8		; 8 groups of 32 IRQs
.gloop:
		push cx
		mov cx,32		; 32 entries per group
.eloop:
		mov [bx],di		; IDT offset [15:0]
		mov word [bx+2],PM_CS32	; IDT segment
		mov dword [bx+4],08e00h	; IDT offset [31:16], 32-bit interrupt
					; gate, CPL 0 (we don't have a TSS
					; set up...)
		add bx,8

		stosd
		; Increment IRQ, decrement jmp short offset
		add eax,(-4 << 24)+(1 << 8)

		loop .eloop

		; At the end of each group, replace the EBxx with
		; the final E9xxxxxxxx
		add di,3
		mov byte [di-5],0E9h	; JMP NEAR
		mov edx,pm_irq
		sub edx,edi
		mov [di-4],edx

		add eax,(0x80 << 24)	; Proper offset for the next one
		pop cx
		loop .gloop

		ret

		; pm_init is called before bss clearing, so put these
		; in .earlybss!
		section .earlybss
		alignb 8
IDT:		resq 256
		global RealModeSSSP
RealModeSSSP	resd 1			; Real-mode SS:SP

		section .gentextnr	; Autogenerated 32-bit code
IRQStubs:	resb 4*256+3*8

		section .text16

%include "callback.inc"			; Real-mode callbacks
