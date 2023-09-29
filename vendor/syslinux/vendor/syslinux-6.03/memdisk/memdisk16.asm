;; -*- fundamental -*-
;; -----------------------------------------------------------------------
;;
;;   Copyright 1994-2008 H. Peter Anvin - All Rights Reserved
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
;; init16.asm
;;
;; Routine to initialize and to trampoline into 32-bit
;; protected memory.  This code is derived from bcopy32.inc and
;; com32.inc in the main SYSLINUX distribution.
;;

%include '../version.gen'

MY_CS		equ 0x0800		; Segment address to use
CS_BASE		equ (MY_CS << 4)	; Corresponding address

; Low memory bounce buffer
BOUNCE_SEG	equ (MY_CS+0x1000)

%define DO_WBINVD 0

		section .rodata align=16
		section .data   align=16
		section .bss    align=16
		section .stack	align=16 nobits
stack		resb 512
stack_end	equ $

;; -----------------------------------------------------------------------
;;  Kernel image header
;; -----------------------------------------------------------------------

		section .text		; Must be first in image
		bits 16

cmdline		times 497 db 0		; We put the command line here
setup_sects	db 0
root_flags	dw 0
syssize		dw 0
swap_dev	dw 0
ram_size	dw 0
vid_mode	dw 0
root_dev	dw 0
boot_flag	dw 0xAA55

_start:		jmp short start

		db "HdrS"		; Header signature
		dw 0x0203		; Header version number

realmode_swtch	dw 0, 0			; default_switch, SETUPSEG
start_sys_seg	dw 0x1000		; obsolete
version_ptr	dw memdisk_version-0x200	; version string ptr
type_of_loader	db 0			; Filled in by boot loader
loadflags	db 1			; Please load high
setup_move_size	dw 0			; Unused
code32_start	dd 0x100000		; 32-bit start address
ramdisk_image	dd 0			; Loaded ramdisk image address
ramdisk_size	dd 0			; Size of loaded ramdisk
bootsect_kludge	dw 0, 0
heap_end_ptr	dw 0
pad1		dw 0
cmd_line_ptr	dd 0			; Command line
ramdisk_max	dd 0xffffffff		; Highest allowed ramdisk address

;
; These fields aren't real setup fields, they're poked in by the
; 32-bit code.
;
b_esdi		dd 0			; ES:DI for boot sector invocation
b_edx		dd 0			; EDX for boot sector invocation
b_sssp		dd 0			; SS:SP on boot sector invocation
b_csip		dd 0			; CS:IP on boot sector invocation

		section .rodata
memdisk_version:
		db "MEMDISK ", VERSION_STR, " ", DATE, 0

;; -----------------------------------------------------------------------
;;  End kernel image header
;; -----------------------------------------------------------------------

;
; Move ourselves down into memory to reduce the risk of conflicts;
; then canonicalize CS to match the other segments.
;
		section .text
		bits 16
start:
		mov ax,MY_CS
		mov es,ax
		movzx cx,byte [setup_sects]
		inc cx			; Add one for the boot sector
		shl cx,7		; Convert to dwords
		xor si,si
		xor di,di
		mov fs,si		; fs <- 0
		cld
		rep movsd
		mov ds,ax
		mov ss,ax
		mov esp,stack_end
		jmp MY_CS:.next
.next:

;
; Copy the command line, if there is one
;
copy_cmdline:
		xor di,di		; Bottom of our own segment (= "boot sector")
		mov eax,[cmd_line_ptr]
		and eax,eax
		jz .endcmd		; No command line
		mov si,ax
		shr eax,4		; Convert to segment
		and si,0x000F		; Starting offset only
		mov gs,ax
		mov cx,496		; Max number of bytes
.copycmd:
		gs lodsb
		and al,al
		jz .endcmd
		stosb
		loop .copycmd
.endcmd:
		xor al,al
		stosb

;
; Now jump to 32-bit code
;
		sti
		call init32
;
; When init32 returns, we have been set up, the new boot sector loaded,
; and we should go and and run the newly loaded boot sector.
;
; The setup function will have poked values into the setup area.
;
		movzx edi,word [cs:b_esdi]
		mov es,word [cs:b_esdi+2]
		mov edx,[cs:b_edx]

		cli
		xor esi,esi		; No partition table involved
		mov ds,si		; Make all the segments consistent
		mov fs,si
		mov gs,si
		lss sp,[cs:b_sssp]
		movzx esp,sp
		jmp far [cs:b_csip]

;
; We enter protected mode, set up a flat 32-bit environment, run rep movsd
; and then exit.  IMPORTANT: This code assumes cs == MY_CS.
;
; This code is probably excessively anal-retentive in its handling of
; segments, but this stuff is painful enough as it is without having to rely
; on everything happening "as it ought to."
;
DummyTSS	equ  0x580		; Hopefully safe place in low mmoery

		section .data

	; desc base, limit, flags
%macro	desc 3
	dd (%2 & 0xffff) | ((%1 & 0xffff) << 16)
	dd (%1 & 0xff000000) | (%2 & 0xf0000) | ((%3 & 0xf0ff) << 8) | ((%1 & 0x00ff0000) >> 16)
%endmacro

		align 8, db 0
call32_gdt:	dw call32_gdt_size-1	; Null descriptor - contains GDT
.adj1:		dd call32_gdt+CS_BASE	; pointer for LGDT instruction
		dw 0

		; 0008: Dummy TSS to make Intel VT happy
		; Should never be actually accessed...
		desc DummyTSS, 103, 0x8089

		; 0010: Code segment, use16, readable, dpl 0, base CS_BASE, 64K
		desc CS_BASE, 0xffff, 0x009b

		; 0018: Data segment, use16, read/write, dpl 0, base CS_BASE, 64K
		desc CS_BASE, 0xffff, 0x0093

		; 0020: Code segment, use32, read/write, dpl 0, base 0, 4G
		desc 0, 0xfffff, 0xc09b

		; 0028: Data segment, use32, read/write, dpl 0, base 0, 4G
		desc 0, 0xfffff, 0xc093

call32_gdt_size:	equ $-call32_gdt

err_a20:	db 'ERROR: A20 gate not responding!',13,10,0

		section .bss
		alignb 4
Return		resd 1			; Return value
SavedSP		resw 1			; Place to save SP
A20Tries	resb 1

		section .data
		align 4, db 0
Target		dd 0			; Target address
Target_Seg	dw 20h			; Target CS

A20Type		dw 0			; Default = unknown

		section .text
		bits 16
;
; Routines to enable and disable (yuck) A20.  These routines are gathered
; from tips from a couple of sources, including the Linux kernel and
; http://www.x86.org/.  The need for the delay to be as large as given here
; is indicated by Donnie Barnes of RedHat, the problematic system being an
; IBM ThinkPad 760EL.
;
; We typically toggle A20 twice for every 64K transferred.
;
%define	io_delay	call _io_delay
%define IO_DELAY_PORT	80h		; Invalid port (we hope!)
%define disable_wait	32		; How long to wait for a disable

%define A20_DUNNO	0		; A20 type unknown
%define A20_NONE	1		; A20 always on?
%define A20_BIOS	2		; A20 BIOS enable
%define A20_KBC		3		; A20 through KBC
%define A20_FAST	4		; A20 through port 92h

		align 2, db 0
A20List		dw a20_dunno, a20_none, a20_bios, a20_kbc, a20_fast
A20DList	dw a20d_dunno, a20d_none, a20d_bios, a20d_kbc, a20d_fast
a20_adjust_cnt	equ ($-A20List)/2

slow_out:	out dx, al		; Fall through

_io_delay:	out IO_DELAY_PORT,al
		out IO_DELAY_PORT,al
		ret

enable_a20:
		pushad
		mov byte [A20Tries],255 ; Times to try to make this work

try_enable_a20:

;
; Flush the caches
;
%if DO_WBINVD
		call try_wbinvd
%endif

;
; If the A20 type is known, jump straight to type
;
		mov bp,[A20Type]
		add bp,bp			; Convert to word offset
.adj4:		jmp word [bp+A20List]

;
; First, see if we are on a system with no A20 gate
;
a20_dunno:
a20_none:
		mov byte [A20Type], A20_NONE
		call a20_test
		jnz a20_done

;
; Next, try the BIOS (INT 15h AX=2401h)
;
a20_bios:
		mov byte [A20Type], A20_BIOS
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

		mov byte [A20Type], A20_KBC	; Starting KBC command sequence

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
		mov byte [A20Type], A20_FAST	; Haven't used the KBC yet
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

		dec byte [A20Tries]
		jnz try_enable_a20


		; Error message time
		mov si,err_a20
print_err:
		lodsb
		and al,al
		jz die
		mov bx,7
		mov ah,0xe
		int 10h
		jmp print_err


die:
		sti
.hlt:		hlt
		jmp short .hlt

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

; This is the INT 1Fh vector, which is standard PCs is used by the
; BIOS when the screen is in graphics mode.  Even if it is, it points to
; data, not code, so it should be safe enough to fiddle with.
A20Test		equ (1Fh*4)

a20_test:
		push ds
		push es
		push cx
		push eax
		xor ax,ax
		mov ds,ax		; DS == 0
		dec ax
		mov es,ax		; ES == 0FFFFh
		mov cx,32		; Loop count
		mov eax,[A20Test]
		cmp eax,[es:A20Test+10h]
		jne .a20_done
		push eax
.a20_wait:
		inc eax
		mov [A20Test],eax
		io_delay
		cmp eax,[es:A20Test+10h]
		loopz .a20_wait
		pop dword [A20Test]	; Restore original value
.a20_done:
		pop eax
		pop cx
		pop es
		pop ds
		ret

disable_a20:
		pushad
;
; Flush the caches
;
%if DO_WBINVD
		call try_wbinvd
%endif

		mov bp,[A20Type]
		add bp,bp			; Convert to word offset
.adj5:		jmp word [bp+A20DList]

a20d_bios:
		mov ax,2400h
		pushf				; Some BIOSes muck with IF
		int 15h
		popf
		jmp short a20d_snooze

;
; Disable the "fast A20 gate"
;
a20d_fast:
		in al, 092h
		and al,~03h
		out 092h, al
		jmp short a20d_snooze

;
; Disable the keyboard controller A20 gate
;
a20d_kbc:
		call empty_8042_uncond

		mov al,0D1h
		out 064h, al		; Write output port
		call empty_8042_uncond

		mov al,0DDh		; A20 off
		out 060h, al
		call empty_8042_uncond

		mov al,0FFh		; Null command/synchronization
		out 064h, al
		call empty_8042_uncond

		; Wait a bit for it to take effect
a20d_snooze:
		push cx
		mov cx, disable_wait
.delayloop:	call a20_test
		jz .disabled
		loop .delayloop
.disabled:	pop cx
a20d_dunno:
a20d_none:
		popad
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
; Execute a WBINVD instruction if possible on this CPU
;
%if DO_WBINVD
try_wbinvd:
		wbinvd
		ret
%endif

		section .bss
		alignb 4
PMESP		resd 1			; Protected mode %esp

		section .idt nobits align=4096
		alignb 4096
pm_idt		resb 4096		; Protected-mode IDT, followed by interrupt stubs




pm_entry:	equ 0x100000

		section .rodata
		align 2, db 0
call32_rmidt:
		dw 0ffffh		; Limit
		dd 0			; Address

		section .data
		alignb 2
call32_pmidt:
		dw 8*256		; Limit
		dd 0			; Address (entered later)

		section .text
;
; This is the main entrypoint in this function
;
init32:
		mov bx,call32_call_start	; Where to go in PM

;
; Enter protected mode.  BX contains the entry point relative to the
; real-mode CS.
;
call32_enter_pm:
		mov ax,cs
		mov ds,ax
		movzx ebp,ax
		shl ebp,4		; EBP <- CS_BASE
		movzx ebx,bx
		add ebx,ebp		; entry point += CS_BASE
		cli
		mov [SavedSP],sp
		cld
		call enable_a20
		mov byte [call32_gdt+8+5],89h	; Mark TSS unbusy
		o32 lgdt [call32_gdt]	; Set up GDT
		o32 lidt [call32_pmidt]	; Set up IDT
		mov eax,cr0
		or al,1
		mov cr0,eax		; Enter protected mode
		jmp 20h:strict dword .in_pm+CS_BASE
.pm_jmp		equ $-6


		bits 32
.in_pm:
		xor eax,eax		; Available for future use...
		mov fs,eax
		mov gs,eax
		lldt ax

		mov al,28h		; Set up data segments
		mov es,eax
		mov ds,eax
		mov ss,eax

		mov al,08h
		ltr ax

		mov esp,[ebp+PMESP]	; Load protmode %esp if available
		jmp ebx			; Go to where we need to go

;
; This is invoked before first dispatch of the 32-bit code, in 32-bit mode
;
call32_call_start:
		;
		; Set up a temporary stack in the bounce buffer;
		; start32.S will override this to point us to the real
		; high-memory stack.
		;
		mov esp, (BOUNCE_SEG << 4) + 0x10000

		push dword call32_enter_rm.rm_jmp+CS_BASE
		push dword call32_enter_pm.pm_jmp+CS_BASE
		push dword stack_end		; RM size
		push dword call32_gdt+CS_BASE
		push dword call32_handle_interrupt+CS_BASE
		push dword CS_BASE		; Segment base
		push dword (BOUNCE_SEG << 4)	; Bounce buffer address
		push dword call32_syscall+CS_BASE ; Syscall entry point

		call pm_entry-CS_BASE		; Run the program...

		; ... fall through to call32_exit ...

call32_exit:
		mov bx,call32_done	; Return to command loop

call32_enter_rm:
		; Careful here... the PM code may have relocated the
		; entire RM code, so we need to figure out exactly
		; where we are executing from.  If the PM code has
		; relocated us, it *will* have adjusted the GDT to
		; match, though.
		call .here
.here:		pop ebp
		sub ebp,.here
		o32 sidt [ebp+call32_pmidt]
		cli
		cld
		mov [ebp+PMESP],esp	; Save exit %esp
		xor esp,esp		; Make sure the high bits are zero
		jmp 10h:.in_pm16	; Return to 16-bit mode first

		bits 16
.in_pm16:
		mov ax,18h		; Real-mode-like segment
		mov es,ax
		mov ds,ax
		mov ss,ax
		mov fs,ax
		mov gs,ax

		lidt [call32_rmidt]	; Real-mode IDT (rm needs no GDT)
		mov eax,cr0
		and al,~1
		mov cr0,eax
		jmp MY_CS:.in_rm
.rm_jmp		equ $-2

.in_rm:					; Back in real mode
		mov ax,cs
		mov ds,ax
		mov es,ax
		mov fs,ax
		mov gs,ax
		mov ss,ax
		mov sp,[SavedSP]	; Restore stack
		jmp bx			; Go to whereever we need to go...

call32_done:
		call disable_a20
		sti
		ret

;
; 16-bit support code
;
		bits 16

;
; 16-bit interrupt-handling code
;
call32_int_rm:
		pushf				; Flags on stack
		push cs				; Return segment
		push word .cont			; Return address
		push dword edx			; Segment:offset of IVT entry
		retf				; Invoke IVT routine
.cont:		; ... on resume ...
		mov bx,call32_int_resume
		jmp call32_enter_pm		; Go back to PM

;
; 16-bit system call handling code
;
call32_sys_rm:
		pop gs
		pop fs
		pop es
		pop ds
		popad
		popfd
		retf				; Invoke routine
.return:
		pushfd
		pushad
		push ds
		push es
		push fs
		push gs
		mov bx,call32_sys_resume
		jmp call32_enter_pm

;
; 32-bit support code
;
		bits 32

;
; This is invoked on getting an interrupt in protected mode.  At
; this point, we need to context-switch to real mode and invoke
; the interrupt routine.
;
; When this gets invoked, the registers are saved on the stack and
; AL contains the register number.
;
call32_handle_interrupt:
		movzx eax,al
		xor ebx,ebx		; Actually makes the code smaller
		mov edx,[ebx+eax*4]	; Get the segment:offset of the routine
		mov bx,call32_int_rm
		jmp call32_enter_rm	; Go to real mode

call32_int_resume:
		popad
		iret

;
; Syscall invocation.  We manifest a structure on the real-mode stack,
; containing the call32sys_t structure from <call32.h> as well as
; the following entries (from low to high address):
; - Target offset
; - Target segment
; - Return offset
; - Return segment (== real mode cs)
; - Return flags
;
call32_syscall:
		pushfd			; Save IF among other things...
		pushad			; We only need to save some, but...
		cld
		call .here
.here:		pop ebp
		sub ebp,.here

		movzx edi,word [ebp+SavedSP]
		sub edi,54		; Allocate 54 bytes
		mov [ebp+SavedSP],di
		add edi,ebp		; Create linear address

		mov esi,[esp+11*4]	; Source regs
		xor ecx,ecx
		mov cl,11		; 44 bytes to copy
		rep movsd

		movzx eax,byte [esp+10*4] ; Interrupt number
		; ecx == 0 here; adding it to the EA makes the
		; encoding smaller
		mov eax,[ecx+eax*4]	; Get IVT entry
		stosd			; Save in stack frame
		mov ax,call32_sys_rm.return	; Return offset
		stosw				; Save in stack frame
		mov eax,ebp
		shr eax,4			; Return segment
		stosw				; Save in stack frame
		mov eax,[edi-12]	; Return flags
		and eax,0x200cd7	; Mask (potentially) unsafe flags
		mov [edi-12],eax	; Primary flags entry
		stosw			; Return flags

		mov bx,call32_sys_rm
		jmp call32_enter_rm	; Go to real mode

		; On return, the 44-byte return structure is on the
		; real-mode stack.  call32_enter_pm will leave ebp
		; pointing to the real-mode base.
call32_sys_resume:
		movzx esi,word [ebp+SavedSP]
		mov edi,[esp+12*4]	; Dest regs
		add esi,ebp		; Create linear address
		and edi,edi		; NULL pointer?
		jnz .do_copy
.no_copy:	mov edi,esi		; Do a dummy copy-to-self
.do_copy:	xor ecx,ecx
		mov cl,11		; 44 bytes
		rep movsd		; Copy register block

		add word [ebp+SavedSP],44	; Remove from stack

		popad
		popfd
		ret			; Return to 32-bit program
