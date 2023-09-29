; -----------------------------------------------------------------------
;
;   Copyright 2003-2008 H. Peter Anvin - All Rights Reserved
;
;   Permission is hereby granted, free of charge, to any person
;   obtaining a copy of this software and associated documentation
;   files (the "Software"), to deal in the Software without
;   restriction, including without limitation the rights to use,
;   copy, modify, merge, publish, distribute, sublicense, and/or
;   sell copies of the Software, and to permit persons to whom
;   the Software is furnished to do so, subject to the following
;   conditions:
;
;   The above copyright notice and this permission notice shall
;   be included in all copies or substantial portions of the Software.
;
;   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
;   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;   OTHER DEALINGS IN THE SOFTWARE.
;
; -----------------------------------------------------------------------

;
; mbr.asm
;
; Simple Master Boot Record, including support for EBIOS extensions.
;
; The MBR lives in front of the boot sector, and is responsible for
; loading the boot sector of the active partition.  The EBIOS support
; is needed if the active partition starts beyond cylinder 1024.
;
; This MBR determines all geometry info at runtime.  It uses only the
; linear block field in the partition table.  It does, however, pass
; the partition table information unchanged to the target OS.
;
; This MBR should be "8086-clean", i.e. not require a 386.
;

%include "bios.inc"

;
; Note: The MBR is actually loaded at 0:7C00h, but we quickly move it down to
; 0600h.
;
		section .text
		cpu 8086
		org 0600h

_start:		cli
		xor ax,ax
		mov ds,ax
		mov es,ax
		mov ss,ax
		mov sp,7C00h
		sti
		cld
		mov si,sp		; Start address
		mov di,0600h		; Destination address
		mov cx,512/2
		rep movsw

;
; Now, jump to the copy at 0600h so we can load the boot sector at 7C00h.
; Since some BIOSes seem to think 0000:7C00h and 07C0:0000h are the same
; thing, use a far jump to canonicalize the address.  This also makes
; sure that it is a code speculation barrier.
;

		jmp 0:next		; Jump to copy at 0600h

next:
		mov [DriveNo], dl		; Drive number stored in DL
;
; Check for CHS parameters.  This doesn't work on floppy disks,
; but for an MBR we don't care.
;
		mov ah,08h			; Get drive parameters
		int 13h
		and cx,3Fh			; Max sector number
		mov [Sectors],cx
		xor ax,ax
		mov al,dh
		inc ax				; From 0-based to count
		mul cx				; Heads*Sectors
		mov [SecPerCyl],ax
		; Note: we actually don't care about the number of
		; cylinders, since that's the highest-order division

;
; Now look for one (and only one) active partition.
;
		mov si,PartitionTable
		xor ax,ax
		mov cx,4
checkpartloop:
		test byte [si],80h
		jz .notactive
		inc ax
		mov di,si
.notactive:	add si,byte 16
		loop checkpartloop

		cmp ax,byte 1			; Better be only one
		jnz not_one_partition

;
; Now we have the active partition partition information in DS:DI.
; Check to see if we support EBIOS.
;
		mov dl,[DriveNo]
		mov ax,4100h
		mov bx,055AAh
		xor cx,cx
		xor dh,dh
		stc
		int 13h
		jc no_ebios
		cmp bx,0AA55h
		jne no_ebios
		test cl,1			; LBA device access
		jz no_ebios
;
; We have EBIOS.  Load the boot sector using LBA.
;
		push di
		mov si,dapa
		mov bx,[di+8]			; Copy the block address
		mov [si+8],bx
		mov bx,[di+10]
		mov [si+10],bx
		mov dl,[DriveNo]
		mov ah,42h			; Extended Read
		jmp short common_tail
;
; No EBIOS.  Load the boot sector using CHS.
;
no_ebios:
		push di
		mov ax,[di+8]
		mov dx,[di+10]
		div word [SecPerCyl]	; AX = cylinder DX = sec in cyl
		ror ah,1
		ror ah,1
		mov cl,ah
		mov ch,al			; CL = cyl[9:8], CH = cyl[7:0]

		mov ax,dx
		div byte [Sectors]		; AL = head AH = sector
		mov dh,al
		inc ah
		or cl,ah			; CX = cylinder and sector

		mov dl,[DriveNo]
		mov bx,7C00h
		mov ax,0201h			; Read one sector
common_tail:
		int 13h
		jc disk_error
		pop si				; DS:SI -> partition table entry
;
; Verify that we have a boot sector, jump
;
		cmp word [7C00h+510],0AA55h
		jne missing_os
		cli
		jmp 0:7C00h			; Jump to boot sector; far
						; jump is speculation barrier
						; (Probably not neecessary, but
						; there is plenty of space.)

not_one_partition:
		ja too_many_os
missing_os:
		mov si,missing_os_msg
		jmp short die
too_many_os:
disk_error:
		mov si,bad_disk_msg
die:
.msgloop:
		lodsb
		and al,al
		jz .now
		mov ah,0Eh			; TTY output
		mov bh,[BIOS_page]		; Current page
		mov bl,07h
		int 10h
		jmp short .msgloop
.now:
		jmp short .now

		align 4, db 0			; Begin data area

;
; EBIOS disk address packet
;
dapa:
		dw 16				; Packet size
.count:		dw 1				; Block count
.off:		dw 7C00h			; Offset of buffer
.seg:		dw 0				; Segment of buffer
.lba:		dd 0				; LBA (LSW)
		dd 0				; LBA (MSW)

; CHS information
SecPerCyl:	dw 0				; Heads*Sectors
Sectors:	dw 0

; Error messages
missing_os_msg	db 'Missing operating system', 13, 10, 0
bad_disk_msg	db 'Operating system loading error', 13, 10, 0

;
; Maximum MBR size: 446 bytes; end-of-boot-sector signature also needed.
; Note that some operating systems (NT, DR-DOS) put additional stuff at
; the end of the MBR, so shorter is better.  Location 440 is known to
; have a 4-byte attempt-at-unique-ID for some OSes.
;

PartitionTable	equ $$+446			; Start of partition table

;
; BSS data; put at 800h
;
DriveNo		equ 0800h
