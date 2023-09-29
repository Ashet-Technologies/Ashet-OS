; -*- fundamental -*- (asm-mode sucks)
; ****************************************************************************
;
;  pxelinux.asm
;
;  A program to boot Linux kernels off a TFTP server using the Intel PXE
;  network booting API.  It is based on the SYSLINUX boot loader for
;  MS-DOS floppies.
;
;   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
;   Copyright 2009 Intel Corporation; author: H. Peter Anvin
;
;  This program is free software; you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;  Boston MA 02111-1307, USA; either version 2 of the License, or
;  (at your option) any later version; incorporated herein by reference.
;
; ****************************************************************************

%define IS_PXELINUX 1
%include "head.inc"
%include "pxe.inc"

; gPXE extensions support
%define GPXE	1

;
; Some semi-configurable constants... change on your own risk.
;
my_id		equ pxelinux_id
NULLFILE	equ 0			; Zero byte == null file name
NULLOFFSET	equ 0			; Position in which to look
REBOOT_TIME	equ 5*60		; If failure, time until full reset
%assign HIGHMEM_SLOP 128*1024		; Avoid this much memory near the top
TFTP_BLOCKSIZE_LG2 equ 9		; log2(bytes/block)
TFTP_BLOCKSIZE	equ (1 << TFTP_BLOCKSIZE_LG2)

SECTOR_SHIFT	equ TFTP_BLOCKSIZE_LG2
SECTOR_SIZE	equ TFTP_BLOCKSIZE

; ---------------------------------------------------------------------------
;   BEGIN CODE
; ---------------------------------------------------------------------------

;
; Memory below this point is reserved for the BIOS and the MBR
;
		section .earlybss
                global trackbuf
trackbufsize	equ 8192
trackbuf	resb trackbufsize	; Track buffer goes here
		; ends at 2800h

		; These fields save information from before the time
		; .bss is zeroed... must be in .earlybss
		global InitStack
InitStack	resd 1

		section .bss16
		alignb FILENAME_MAX
PXEStack	resd 1			; Saved stack during PXE call

		alignb 4
                global DHCPMagic, RebootTime, BIOSName
RebootTime	resd 1			; Reboot timeout, if set by option
LocalBootType	resw 1			; Local boot return code
DHCPMagic	resb 1			; PXELINUX magic flags
BIOSName	resw 1			; Dummy variable - always 0

		section .text16
		global StackBuf
StackBuf	equ STACK_TOP-44	; Base of stack if we use our own
StackHome	equ StackBuf

		; PXE loads the whole file, but assume it can't be more
		; than (384-31)K in size.
MaxLMA		equ 384*1024

;
; Primary entry point.
;
bootsec		equ $
_start:
		jmp 0:_start1		; Canonicalize the address and skip
					; the patch header

;
; Patch area for adding hardwired DHCP options
;
		align 4

hcdhcp_magic	dd 0x2983c8ac		; Magic number
hcdhcp_len	dd 7*4			; Size of this structure
hcdhcp_flags	dd 0			; Reserved for the future
		global bdhcp_len, adhcp_len
		; Parameters to be parsed before the ones from PXE
bdhcp_offset	dd 0			; Offset (entered by patcher)
bdhcp_len	dd 0			; Length (entered by patcher)
		; Parameters to be parsed *after* the ones from PXE
adhcp_offset	dd 0			; Offset (entered by patcher)
adhcp_len	dd 0			; Length (entered by patcher)

_start1:
		pushfd			; Paranoia... in case of return to PXE
		pushad			; ... save as much state as possible
		push ds
		push es
		push fs
		push gs

		cld			; Copy upwards
		xor ax,ax
		mov ds,ax
		mov es,ax

%if 0 ; debugging code only... not intended for production use
		; Clobber the stack segment, to test for specific pathologies
		mov di,STACK_BASE
		mov cx,STACK_LEN >> 1
		mov ax,0xf4f4
		rep stosw

		; Clobber the tail of the 64K segment, too
		extern __bss1_end
		mov di,__bss1_end
		sub cx,di		; CX = 0 previously
		shr cx,1
		rep stosw
%endif

		; That is all pushed onto the PXE stack.  Save the pointer
		; to it and switch to an internal stack.
		mov [InitStack],sp
		mov [InitStack+2],ss

		lss esp,[BaseStack]
		sti			; Stack set up and ready

;
; Initialize screen (if we're using one)
;
%include "init.inc"

;
; Tell the user we got this far
;
		mov si,syslinux_banner
		call writestr_early

		mov si,copyright_str
		call writestr_early

;
; do fs initialize
;
	        mov eax,ROOT_FS_OPS
		xor ebp,ebp
                pm_call pm_fs_init

		section .rodata
		alignz 4
ROOT_FS_OPS:
                extern pxe_fs_ops
		dd pxe_fs_ops
		dd 0


		section .text16
;
; Initialize the idle mechanism
;
		extern reset_idle
		pm_call reset_idle

;
; Now we're all set to start with our *real* business.
;
; In previous versions I avoided using 32-bit registers because of a
; rumour some BIOSes clobbered the upper half of 32-bit registers at
; random.  I figure, though, that if there are any of those still left
; they probably won't be trying to install Linux on them...
;
; The code is still ripe with 16-bitisms, though.  Not worth the hassle
; to take'm out.  In fact, we may want to put them back if we're going
; to boot ELKS at some point.
;

;
; Linux kernel loading code is common.  However, we need to define
; a couple of helper macros...
;

; Unload PXE stack
%define HAVE_UNLOAD_PREP
%macro	UNLOAD_PREP 0
		pm_call unload_pxe
%endmacro

;
; Jump to 32-bit ELF space
;
		pm_call load_env32
		jmp kaboom		; load_env32() shouldn't return. If it does, then kaboom!

print_hello:
enter_command:
auto_boot:
		pm_call hello

;
; Save hardwired DHCP options.  This is done before the C environment
; is initialized, so it has to be done in assembly.
;
%define MAX_DHCP_OPTS	4096
		bits 32

		section .savedata
		global bdhcp_data, adhcp_data
bdhcp_data:	resb MAX_DHCP_OPTS
adhcp_data:	resb MAX_DHCP_OPTS

		section .textnr
pm_save_data:
		mov eax,MAX_DHCP_OPTS
		movzx ecx,word [bdhcp_len]
		cmp ecx,eax
		jna .oksize
		mov ecx,eax
		mov [bdhcp_len],ax
.oksize:
		mov esi,[bdhcp_offset]
		add esi,_start
		mov edi,bdhcp_data
		add ecx,3
		shr ecx,2
		rep movsd

adhcp_copy:
		movzx ecx,word [adhcp_len]
		cmp ecx,eax
		jna .oksize
		mov ecx,eax
		mov [adhcp_len],ax
.oksize:
		mov esi,[adhcp_offset]
		add esi,_start
		mov edi,adhcp_data
		add ecx,3
		shr ecx,2
		rep movsd
		ret

		bits 16

; As core/ui.inc used to be included here in core/pxelinux.asm, and it's no
; longer used, its global variables that were previously used by
; core/pxelinux.asm are now declared here.
		section .bss16
		alignb 4
Kernel_EAX	resd 1
Kernel_SI	resw 1

		section .bss16
		alignb 4
ThisKbdTo	resd 1			; Temporary holder for KbdTimeout
ThisTotalTo	resd 1			; Temporary holder for TotalTimeout
KernelExtPtr	resw 1			; During search, final null pointer
FuncFlag	resb 1			; Escape sequences received from keyboard
KernelType	resb 1			; Kernel type, from vkernel, if known
		global KernelName
KernelName	resb FILENAME_MAX	; Mangled name for kernel

		section .text16
;
; COM32 vestigial data structure
;
%include "com32.inc"

		section .text16
		global local_boot16:function hidden
local_boot16:
		mov [LocalBootType],ax
		lss sp,[InitStack]
		pop gs
		pop fs
		pop es
		pop ds
		popad
		mov ax,[cs:LocalBootType]
		cmp ax,-1			; localboot -1 == INT 18h
		je .int18
		popfd
		retf				; Return to PXE
.int18:
		popfd
		int 18h
		jmp 0F000h:0FFF0h
		hlt

;
; kaboom: write a message and bail out.  Wait for quite a while,
;	  or a user keypress, then do a hard reboot.
;
;         Note: use BIOS_timer here; we may not have jiffies set up.
;
                global kaboom
kaboom:
		RESET_STACK_AND_SEGS AX
.patch:		mov si,bailmsg
		call writestr_early		; Returns with AL = 0
.drain:		call pollchar
		jz .drained
		call getchar
		jmp short .drain
.drained:
		mov edi,[RebootTime]
		mov al,[DHCPMagic]
		and al,09h		; Magic+Timeout
		cmp al,09h
		je .time_set
		mov edi,REBOOT_TIME
.time_set:
		mov cx,18
.wait1:		push cx
		mov ecx,edi
.wait2:		mov dx,[BIOS_timer]
.wait3:		call pollchar
		jnz .keypress
		pm_call __idle
		cmp dx,[BIOS_timer]
		je .wait3
		loop .wait2,ecx
		mov al,'.'
		pm_call pm_writechr
		pop cx
		loop .wait1
.keypress:
		pm_call crlf
		mov word [BIOS_magic],0	; Cold reboot
		jmp 0F000h:0FFF0h	; Reset vector address

;
; pxenv
;
; This is the main PXENV+/!PXE entry point, using the PXENV+
; calling convention.  This is a separate local routine so
; we can hook special things from it if necessary.  In particular,
; some PXE stacks seem to not like being invoked from anything but
; the initial stack, so humour it.
;
; While we're at it, save and restore all registers.
;
                global pxenv
pxenv:
		pushfd
		pushad

		; We may be removing ourselves from memory
		cmp bx,PXENV_RESTART_TFTP
		jz .disable_timer
		cmp bx,PXENV_FILE_EXEC
		jnz .store_stack

.disable_timer:
		call bios_timer_cleanup

.store_stack:
		pushf
		cli
		inc word [cs:PXEStackLock]
		jnz .skip1
		pop bp
		mov [cs:PXEStack],sp
		mov [cs:PXEStack+2],ss
		lss sp,[cs:InitStack]
		push bp
.skip1:
		popf

		; Pre-clear the Status field
		mov word [es:di],cs

		; This works either for the PXENV+ or the !PXE calling
		; convention, as long as we ignore CF (which is redundant
		; with AX anyway.)
		push es
		push di
		push bx
.jump:		call 0:0
		add sp,6
		mov [cs:PXEStatus],ax

		pushf
		cli
		dec word [cs:PXEStackLock]
		jns .skip2
		pop bp
		lss sp,[cs:PXEStack]
		push bp
.skip2:
		popf

		mov bp,sp
		and ax,ax
		setnz [bp+32]			; If AX != 0 set CF on return

		; This clobbers the AX return, but we already saved it into
		; the PXEStatus variable.
		popad

		; If the call failed, it could return.
		cmp bx,PXENV_RESTART_TFTP
		jz .enable_timer
		cmp bx,PXENV_FILE_EXEC
		jnz .pop_flags

.enable_timer:
		call timer_init

.pop_flags:
		popfd				; Restore flags (incl. IF, DF)
		ret

; Must be after function def due to NASM bug
                global PXEEntry
PXEEntry	equ pxenv.jump+1

;
; The PXEStackLock keeps us from switching stacks if we take an interrupt
; (which ends up calling pxenv) while we are already on the PXE stack.
; It will be -1 normally, 0 inside a PXE call, and a positive value
; inside a *nested* PXE call.
;
		section .data16
		alignb 2
PXEStackLock	dw -1

		section .bss16
		alignb 2
PXEStatus	resb 2

		section .text16
;
; Invoke INT 1Ah on the PXE stack.  This is used by the "Plan C" method
; for finding the PXE entry point.
;
                global pxe_int1a
pxe_int1a:
		mov [cs:PXEStack],sp
		mov [cs:PXEStack+2],ss
		lss sp,[cs:InitStack]

		int 1Ah			; May trash registers

		lss sp,[cs:PXEStack]
		ret

;
; Special unload for gPXE: this switches the InitStack from
; gPXE to the ROM PXE stack.
;
%if GPXE
		global gpxe_unload
gpxe_unload:
		mov bx,PXENV_FILE_EXIT_HOOK
		mov di,pxe_file_exit_hook
		call pxenv
		jc .plain

		; Now we actually need to exit back to gPXE, which will
		; give control back to us on the *new* "original stack"...
		pushfd
		push ds
		push es
		mov [PXEStack],sp
		mov [PXEStack+2],ss
		lss sp,[InitStack]
		pop gs
		pop fs
		pop es
		pop ds
		popad
		popfd
		xor ax,ax
		retf
.resume:
		cli

		; gPXE will have a stack frame looking much like our
		; InitStack, except it has a magic cookie at the top,
		; and the segment registers are in reverse order.
		pop eax
		pop ax
		pop bx
		pop cx
		pop dx
		push ax
		push bx
		push cx
		push dx
		mov [cs:InitStack],sp
		mov [cs:InitStack+2],ss
		lss sp,[cs:PXEStack]
		pop es
		pop ds
		popfd

.plain:
		ret

writestr_early:
		pm_call pm_writestr
		ret

pollchar:
		pm_call pm_pollchar
		ret

getchar:
		pm_call pm_getchar
		ret

		section .data16
		alignz 4
pxe_file_exit_hook:
.status:	dw 0
.offset:	dw gpxe_unload.resume
.seg:		dw 0
%endif

		section .text16

; -----------------------------------------------------------------------------
;  PXE modules
; -----------------------------------------------------------------------------

%if IS_LPXELINUX
%include "pxeisr.inc"
%endif

; -----------------------------------------------------------------------------
;  Common modules
; -----------------------------------------------------------------------------

%include "common.inc"		; Universal modules

; -----------------------------------------------------------------------------
;  Begin data section
; -----------------------------------------------------------------------------

		section .data16

		global copyright_str, syslinux_banner
copyright_str   db 'Copyright (C) 1994-'
		asciidec YEAR
		db ' H. Peter Anvin et al', CR, LF, 0
err_bootfailed	db CR, LF, 'Boot failed: press a key to retry, or wait for reset...', CR, LF, 0
bailmsg		equ err_bootfailed
localboot_msg	db 'Booting from local disk...', CR, LF, 0
syslinux_banner	db CR, LF, MY_NAME, ' ', VERSION_STR, ' ', MY_TYPE, ' '
		db DATE_STR, ' ', 0

;
; Misc initialized (data) variables
;
		section .data16
                global KeepPXE
KeepPXE		db 0			; Should PXE be kept around?

		section .bss16
		global OrigFDCTabPtr
OrigFDCTabPtr	resd 1			; Keep bios_cleanup_hardware() honest
