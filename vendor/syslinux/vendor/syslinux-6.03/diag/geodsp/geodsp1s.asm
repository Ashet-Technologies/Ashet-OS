; -----------------------------------------------------------------------
;
;   Copyright 2010 Gene Cumm
;
;   Portions from diskstart.inc:
;   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
;   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
;   Boston MA 02110-1301, USA; either version 2 of the License, or
;   (at your option) any later version; incorporated herein by reference.
;
; -----------------------------------------------------------------------

;
; geodsp1s.asm
;
; Display geometry translation info for diagnosing misconceptions
; 1 sector variant
;
;	nasm -Ox -f bin -o geodsp.bin -l geodsp.lst geodsp.asm
;
;	nasm -Ox -f elf -o geodsp.o -l geodsp.lst geodsp.asm
;	ld -m elf_i386  -T syslinux.ld -M -o geodsp.elf geodsp.o > geodsp.map
;	objcopy -O binary geodsp.elf geodsp.raw
;
;	# OF=/dev/sdb
;	# dd if=core/geodsp.bin of=$OF
;	# dd skip=1 seek=1 if=../dbg/lba-img/lba-img.bin of=$OF
;	# eject $OF
;	# dd count=$() if=/dev/zero of=$OF
;
;	# OF=geo-2.255.63.i
;	# (dd if=core/geodsp.bin; dd skip=1 if=../dbg/lba-img/lba-img.bin; dd count=$((2*255*63 - 256*63 - 1)) if=/dev/zero )|dd of=$OF
;	# OF=geo-20.16.63.i
;	# (dd if=core/geodsp.bin; dd skip=1 if=../dbg/lba-img/lba-img.bin; dd count=$((40*16*63 - 256*63 - 1)) if=/dev/zero )|dd of=$OF
;

%include "macros.inc"
; %include "layout.inc"

; 		global STACK_LEN, STACK_TOP, STACK_BASE
; STACK_LEN	equ 4096
STACK_TOP	equ 7c00h
; STACK_BASE	equ STACK_TOP - STACK_LEN

StackBuf	equ STACK_TOP-44-92	; Start the stack here (grow down - 4K)
DriveNumber	equ StackBuf-4		; Drive number
m_CHS0		equ 00534843h		;'CHS',0
m_EDD0		equ 00444445h		;'EDD',0
m_EDD_SP	equ 20444445h		;'EDD '
retry_count	equ 16
dbuf		equ 8000h
int13_ret	equ 7e00h



; 		extern	real_mode_seg
; 		section .real_mode	write nobits align=65536
; 		global	core_real_mode
; core_real_mode	resb 65536
; 		extern	xfer_buf_seg
; 		section .xfer_buf	write nobits align=65536
; 		global	core_xfer_buf
; core_xfer_buf	resb 65536

		section .text
		org STACK_TOP


		global _start
bootsec		equ $
_start:
			; In case we want to pull more of the standard diskstart stuff in
; 		jmp short start		; 2 bytes
; 		nop			; 1 byte
start:
		cli
		cld
		xor cx,cx
		mov ss,cx
		mov sp,StackBuf-2	; Just below BSS (-2 for alignment)
		push dx			; Save drive number (in DL)
			; Kill everything else and let the BIOS sort it out later
		mov es,cx
		mov ds,cx
		sti

get_geo:		; DL and ES ready
		mov ah,08h
		mov di,0
		int 13h
write_geo:
		jc .bad_geo
		mov si,s_chs
		call writestr_early
		call write_chs
		call crlf
		jmp short .done
.bad_geo:
.done:

		mov bx,dbuf
get_h1c:		; 0,1,1
		mov cx,0001h
		mov dh,01h
		call getonesec_chs
		call write_chs_lba
get_c1c:		; 1,0,1
		mov cx,0101h
		mov dh,00h
		call getonesec_chs
		call write_chs_lba

;
; Do we have EBIOS (EDD)?
;
edd:
.check:
		mov bx,55AAh
		mov ah,41h		; EDD existence query
		mov dl,[DriveNumber]
		int 13h
		jc .noedd
		cmp bx,0AA55h
		jne .noedd
		test cl,1		; Extended disk access functionality set
		jz .noedd
		;
		; We have EDD support...
		;
		mov bx,dbuf
		xor edx,edx
		mov dword [s_chs],m_EDD_SP
.get_lba63:
		mov eax,63	; Same length as mov al,64; movzx eax,al
		call getonesec_ebios
		jc .bad_edd	;read error
		call write_edd_lba
.get_lba16065:
		mov eax,16065
		call getonesec_ebios
		jc .bad_edd	;read error
		call write_edd_lba
.good_edd:
		mov dword [s_type],m_EDD0
.bad_edd:
.noedd:
.end:

write_final_type:
		mov si,s_typespec
		call writestr_early

		jmp short kaboom

;
; getonesec_ebios:
;
; getonesec implementation for EBIOS (EDD)
;
getonesec_ebios:
		mov cx,retry_count
.retry:
		; Form DAPA on stack
		push edx
		push eax
		push es
		push bx
		push word 1
		push word 16
		mov si,sp
		pushad
                mov ah,42h                      ; Extended Read
		call xint13
		popad
		lea sp,[si+16]			; Remove DAPA
		jc .error
                ret

.error:
		; Some systems seem to get "stuck" in an error state when
		; using EBIOS.  Doesn't happen when using CBIOS, which is
		; good, since some other systems get timeout failures
		; waiting for the floppy disk to spin up.

		pushad				; Try resetting the device
		xor ax,ax
		call xint13
		popad
		loop .retry			; CX-- and jump if not zero

		; Total failure.
		stc
		ret

;
; getonesec_chs:
;
; CX,DH specifies CHS address
;
getonesec_chs:	; We could use an xchg and get a loop
; 		mov cx,retry_count
.retry:
		pushad
		mov ax,0201h		; Read one sector
		call xint13
		popad
		jc .error
		ret

.error:
; 		loop .retry
		; Fall through to disk_error
;
; kaboom: write a message and bail out.
;
		global kaboom
disk_error:
kaboom:
.patch:
		mov si,bailmsg
		call writestr_early
		xor eax,eax
.again:		int 16h			; Wait for keypress
					; NB: replaced by int 18h if
					; chosen at install time..
		int 19h			; And try once more to boot...
.norge:		hlt			; If int 19h returned; this is the end
		jmp short .norge

;
; INT 13h wrapper function
;
xint13:
                mov dl,[DriveNumber]
		int 13h
		mov [int13_ret],ax
		ret

;
;
; writestr_early: write a null-terminated string to the console
;	    This assumes we're on page 0.  This is only used for early
;           messages, so it should be OK.
;
writestr_early:
		pushad
.loop:		lodsb
		and al,al
                jz .return
		call writechr
		jmp short .loop
.return:	popad
		ret

%include "geodsplib.inc"
bailmsg		equ s_end

		; This fails if the boot sector overflowsg
		zb 1BEh-($-$$)

ptable		zb 40h		; Partition table

bootsignature	dw 0xAA55

sector_2:
