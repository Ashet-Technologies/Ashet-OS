; -----------------------------------------------------------------------
;
;   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
;   Copyright 2009-2011 Intel Corporation; author: H. Peter Anvin
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
;   Boston MA 02110-1301, USA; either version 2 of the License, or
;   (at your option) any later version; incorporated herein by reference.
;
; -----------------------------------------------------------------------

;
; diskboot.inc
;
; Common boot sector code for harddisk-based Syslinux derivatives.
;
; Requires macros z[bwd], labels ldlinux_ent, ldlinux_magic, ldlinux_sys
; and constants BS_MAGIC_VER, LDLINUX_MAGIC, retry_count, Sect1Ptr[01]_VAL,
; STACK_TOP
;

		section .init
;
; Some of the things that have to be saved very early are saved
; "close" to the initial stack pointer offset, in order to
; reduce the code size...
;

		global StackBuf, PartInfo, Hidden, OrigESDI, DriveNumber
		global OrigFDCTabPtr
StackBuf	equ STACK_TOP-44-92	; Start the stack here (grow down - 4K)
PartInfo	equ StackBuf
.mbr		equ PartInfo
.gptlen		equ PartInfo+16
.gpt		equ PartInfo+20
FloppyTable	equ PartInfo+76
; Total size of PartInfo + FloppyTable == 76+16 = 92 bytes
Hidden		equ StackBuf-24		; Partition offset (qword)
OrigFDCTabPtr	equ StackBuf-16		; Original FDC table
OrigDSSI	equ StackBuf-12		; DS:SI -> partinfo
OrigESDI	equ StackBuf-8		; ES:DI -> $PnP structure
DriveNumber	equ StackBuf-4		; Drive number
StackHome	equ Hidden		; The start of the canonical stack

;
; Primary entry point.  Tempting as though it may be, we can't put the
; initial "cli" here; the jmp opcode in the first byte is part of the
; "magic number" (using the term very loosely) for the DOS superblock.
;
bootsec		equ $
_start:		jmp short start		; 2 bytes
		nop			; 1 byte
;
; "Superblock" follows -- it's in the boot sector, so it's already
; loaded and ready for us
;
bsOemName	db MY_NAME		; The SYS command sets this, so...
		zb 8-($-bsOemName)

;
; These are the fields we actually care about.  We end up expanding them
; all to dword size early in the code, so generate labels for both
; the expanded and unexpanded versions.
;
%macro		superb 1
bx %+ %1	equ SuperInfo+($-superblock)*8+4
bs %+ %1	equ $
		zb 1
%endmacro
%macro		superw 1
bx %+ %1	equ SuperInfo+($-superblock)*8
bs %+ %1	equ $
		zw 1
%endmacro
%macro		superd 1
bx %+ %1	equ $			; no expansion for dwords
bs %+ %1	equ $
		zd 1
%endmacro
superblock	equ $
		superw BytesPerSec
		superb SecPerClust
		superw ResSectors
		superb FATs
		superw RootDirEnts
		superw Sectors
		superb Media
		superw FATsecs
		superw SecPerTrack
		superw Heads
superinfo_size	equ ($-superblock)-1	; How much to expand
		superd Hidden
		superd HugeSectors
		;
		; This is as far as FAT12/16 and FAT32 are consistent
		;
		; FAT12/16 need 26 more bytes,
		; FAT32 need 54 more bytes
		;
superblock_len_fat16	equ $-superblock+26
superblock_len_fat32	equ $-superblock+54
		zb 54			; Maximum needed size
superblock_max	equ $-superblock

SecPerClust	equ bxSecPerClust

;
; Note we don't check the constraints above now; we did that at install
; time (we hope!)
;
start:
		cli			; No interrupts yet, please
		cld			; Copy upwards
;
; Set up the stack
;
		xor cx,cx
		mov ss,cx
		mov sp,StackBuf-2	; Just below BSS (-2 for alignment)
		push dx			; Save drive number (in DL)
		push es			; Save initial ES:DI -> $PnP pointer
		push di
		push ds			; Save original DS:SI -> partinfo
		push si
		mov es,cx

;
; DS:SI may contain a partition table entry and possibly a GPT entry.
; Preserve it for us.  This saves 56 bytes of the GPT entry, which is
; currently the maximum we care about.  Total is 76 bytes.
;
		mov cl,(16+4+56)/2	; Save partition info
		mov di,PartInfo
		rep movsw		; This puts CX back to zero

		mov ds,cx		; Now we can initialize DS...

;
; Now sautee the BIOS floppy info block to that it will support decent-
; size transfers; the floppy block is 11 bytes and is stored in the
; INT 1Eh vector (brilliant waste of resources, eh?)
;
; Of course, if BIOSes had been properly programmed, we wouldn't have
; had to waste precious space with this code.
;
		mov bx,fdctab
		lfs si,[bx]		; FS:SI -> original fdctab
		push fs			; Save on stack in case we need to bail
		push si

		; Save the old fdctab even if hard disk so the stack layout
		; is the same.  The instructions above do not change the flags
		and dl,dl		; If floppy disk (00-7F), assume no
					; partition table
		js harddisk

floppy:
		xor ax,ax
		mov cl,6		; 12 bytes (CX == 0)
		; es:di -> FloppyTable already
		; This should be safe to do now, interrupts are off...
		mov [bx],di		; FloppyTable
		mov [bx+2],ax		; Segment 0
		fs rep movsw		; Faster to move words
		mov cl,[bsSecPerTrack]  ; Patch the sector count
		mov [di-12+4],cl

		push ax			; Partition offset == 0
		push ax
		push ax
		push ax

		int 13h			; Some BIOSes need this
			; Using xint13 costs +1B
		jmp short not_harddisk
;
; The drive number and possibly partition information was passed to us
; by the BIOS or previous boot loader (MBR).  Current "best practice" is to
; trust that rather than what the superblock contains.
;
; Note: di points to beyond the end of PartInfo
; Note: false negatives might slip through the handover area's sanity checks,
;       if the region is very close (less than a paragraph) to
;       PartInfo ; no false positives are possible though
;
harddisk:
		mov dx,[di-76-10]	; Original DS
		mov si,[di-76-12]	; Original SI
		shr si,4
		add dx,si
		cmp dx,4fh		; DS:SI < 50h:0 (BDA or IVT) ?
		jbe .no_partition
		cmp dx,(PartInfo-75)>>4	; DS:SI in overwritten memory?
		jae .no_partition
		test byte [di-76],7Fh	; Sanity check: "active flag" should
		jnz .no_partition	; be 00 or 80
		cmp [di-76+4],cl	; Sanity check: partition type != 0
		je .no_partition
		cmp eax,'!GPT'		; !GPT signature?
		jne .mbr
		cmp byte [di-76+4],0EDh	; Synthetic GPT partition entry?
		jne .mbr
.gpt:					; GPT-style partition info
		push dword [di-76+20+36]
		push dword [di-76+20+32]
		jmp .gotoffs
.mbr:					; MBR-style partition info
		push cx			; Upper half partition offset == 0
		push cx
		push dword [di-76+8]	; Partition offset (dword)
		jmp .gotoffs
.no_partition:
;
; No partition table given... assume that the Hidden field in the boot sector
; tells the truth (in particular, is zero if this is an unpartitioned disk.)
;
		push cx
		push cx
		push dword [bsHidden]
.gotoffs:
;
; Get disk drive parameters (don't trust the superblock.)  Don't do this for
; floppy drives -- INT 13:08 on floppy drives will (may?) return info about
; what the *drive* supports, not about the *media*.  Fortunately floppy disks
; tend to have a fixed, well-defined geometry which is stored in the superblock.
;
		; DL == drive # still
		mov ah,08h
		call xint13
		jc no_driveparm
		and ah,ah
		jnz no_driveparm
		shr dx,8
		inc dx			; Contains # of heads - 1
		mov [bsHeads],dx
		and cx,3fh
		mov [bsSecPerTrack],cx
no_driveparm:
not_harddisk:
;
; Ready to enable interrupts, captain
;
		sti

;
; Do we have EBIOS (EDD)?
;
eddcheck:
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
		mov byte [getonesec.jmp+1],(getonesec_ebios-(getonesec.jmp+2))
.noedd:

;
; Load the first sector of LDLINUX.SYS; this used to be all proper
; with parsing the superblock and root directory; it doesn't fit
; together with EBIOS support, unfortunately.
;
Sect1Load:
		mov eax,strict dword Sect1Ptr0_VAL	; 0xdeadbeef
Sect1Ptr0	equ $-4
		mov edx,strict dword Sect1Ptr1_VAL	; 0xfeedface
Sect1Ptr1	equ $-4
		mov bx,ldlinux_sys	; Where to load it
		call getonesec

		; Some modicum of integrity checking
		cmp dword [ldlinux_magic+4],LDLINUX_MAGIC^HEXDATE
		jne kaboom

		; Go for it!
		jmp ldlinux_ent

;
; getonesec: load a single disk linear sector EDX:EAX into the buffer
;	     at ES:BX.
;
;            This routine assumes CS == DS == SS, and trashes most registers.
;
; Stylistic note: use "xchg" instead of "mov" when the source is a register
; that is dead from that point; this saves space.  However, please keep
; the order to dst,src to keep things sane.
;
getonesec:
		add eax,[Hidden]		; Add partition offset
		adc edx,[Hidden+4]
		mov cx,retry_count
.jmp:		jmp strict short getonesec_cbios

;
; getonesec_ebios:
;
; getonesec implementation for EBIOS (EDD)
;
getonesec_ebios:
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

		; Total failure.  Try falling back to CBIOS.
		mov byte [getonesec.jmp+1],(getonesec_cbios-(getonesec.jmp+2))

;
; getonesec_cbios:
;
; getlinsec implementation for legacy CBIOS
;
getonesec_cbios:
.retry:
		pushad

		movzx esi,word [bsSecPerTrack]
		movzx edi,word [bsHeads]
		;
		; Dividing by sectors to get (track,sector): we may have
		; up to 2^18 tracks, so we need to use 32-bit arithmetric.
		;
		div esi
		xor cx,cx
		xchg cx,dx		; CX <- sector index (0-based)
					; EDX <- 0
		; eax = track #
		div edi			; Convert track to head/cyl

		cmp eax,1023		; Outside the CHS range?
		ja kaboom

		;
		; Now we have AX = cyl, DX = head, CX = sector (0-based),
		; SI = bsSecPerTrack, ES:BX = data target
		;
		shl ah,6		; Because IBM was STOOPID
					; and thought 8 bits were enough
					; then thought 10 bits were enough...
		inc cx			; Sector numbers are 1-based, sigh
		or cl,ah
		mov ch,al
		mov dh,dl
		mov ax,0201h		; Read one sector
		call xint13
		popad
		jc .error
		ret

.error:
		loop .retry
		; Fall through to disk_error

;
; kaboom: write a message and bail out.
;
%ifdef BINFMT
		global kaboom
%else
		global kaboom:function hidden
%endif
disk_error:
kaboom:
		xor si,si
		mov ss,si
		mov sp,OrigFDCTabPtr	; Reset stack
		mov ds,si		; Reset data segment
		pop dword [fdctab]	; Restore FDC table
.patch:					; When we have full code, intercept here
		mov si,bailmsg
.loop:		lodsb
		and al,al
                jz .done
		mov ah,0Eh		; Write to screen as TTY
		mov bx,0007h		; Attribute
		int 10h
		jmp short .loop

.done:
		xor ax,ax
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
		push es		; ES destroyed by INT 13h AH 08h
		int 13h
		pop es
		ret

;
; Error message on failure
;
bailmsg:	db 'Boot error', 0Dh, 0Ah, 0

		; This fails if the boot sector overflowsg
		zb 1F8h-($-$$)

bs_magic	dd LDLINUX_MAGIC
bs_link		dw (Sect1Load - bootsec) | BS_MAGIC_VER
bootsignature	dw 0xAA55

;
; ===========================================================================
;  End of boot sector
; ===========================================================================
