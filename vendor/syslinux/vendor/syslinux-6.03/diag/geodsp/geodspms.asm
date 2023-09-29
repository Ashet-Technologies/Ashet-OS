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
; geodspms.asm
;
; Display geometry translation info for diagnosing misconceptions
; multi-sector variant
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

; Just to define it to look like SYSLINUX
%define IS_SYSLINUX 1

%include "macros.inc"
; %include "layout.inc"

m_CHS0		equ 00534843h		;'CHS',0
m_EDD0		equ 00444445h		;'EDD',0
m_EDD_SP	equ 20444445h		;'EDD '
retry_count	equ 16
dbuf		equ 8000h
; int13_ret	equ 7e00h
LDLINUX_MAGIC	equ 0x3eb202fe		; A random number to identify ourselves with

Sect1Ptr0_VAL	equ 1
Sect1Ptr1_VAL	equ 0

; 		global STACK_LEN, STACK_TOP, STACK_BASE
; STACK_LEN	equ 4096
STACK_TOP	equ 7c00h
; STACK_BASE	equ STACK_TOP - STACK_LEN
		section .init
		org STACK_TOP
geodsp_start:

%include "diskboot.inc"

HEXDATE		equ 1

		section .init
sector_1:
ldlinux_sys:
		alignz 8
ldlinux_magic	dd LDLINUX_MAGIC
		dd LDLINUX_MAGIC^HEXDATE


ldlinux_ent:

get_geo:		; DL and ES ready
		mov ah,08h
		mov di,0
		call xint13
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



; Do we have EBIOS (EDD)?
;
edd:
.check:
		mov bx,55AAh
		mov ah,41h		; EDD existence query
		call xint13
		jc .noedd
		cmp bx,0AA55h
		jne .noedd
		test cl,1		; Extended disk access functionality set
		jz .noedd
		;
		; We have EDD support...
		;
		mov bx,dbuf	; ES should still be safe.
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
		jmp kaboom

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
		jmp disk_error

%include "geodsplib.inc"

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
		mov ah,0Eh		; Write to screen as TTY
		mov bx,0007h		; Attribute
		int 10h
		jmp short .loop
.return:	popad
		ret

SuperInfo:	zd 32			; The first 16 bytes expanded 8 times

		; This fails if the sector overflowsg
		zb 400h-($-$$)
end:

		absolute 4*1Eh
fdctab		equ $
fdctab1		resw 1
fdctab2		resw 1
