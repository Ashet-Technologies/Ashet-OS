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
; diskstart.inc
;
; Common early-bootstrap code for harddisk-based Syslinux derivatives.
;

Sect1Ptr0_VAL	equ 0xdeadbeef
Sect1Ptr1_VAL	equ 0xfeedface

%include "diskboot.inc"

; ===========================================================================
;  Padding after the (minimum) 512-byte boot sector so that the rest of
;  the file has aligned sectors, even if they are larger than 512 bytes.
; ===========================================================================

		section .init
align_pad	zb 512

; ===========================================================================
;  Start of LDLINUX.SYS
; ===========================================================================

LDLINUX_SYS	equ ($-$$)+TEXT_START
ldlinux_sys:

early_banner	db CR, LF, MY_NAME, ' ', VERSION_STR, ' ', 0
		db CR, LF, 1Ah	; EOF if we "type" this in DOS

		alignz 8
ldlinux_magic	dd LDLINUX_MAGIC
		dd LDLINUX_MAGIC^HEXDATE

;
; This area is patched by the installer.  It is found by looking for
; LDLINUX_MAGIC, plus 8 bytes.
;
SUBVOL_MAX	equ 256
CURRENTDIR_MAX	equ FILENAME_MAX

patch_area:
DataSectors	dw 0		; Number of sectors (not including bootsec)
ADVSectors	dw 0		; Additional sectors for ADVs
LDLDwords	dd 0		; Total dwords starting at ldlinux_sys,
CheckSum	dd 0		; Checksum starting at ldlinux_sys
				; value = LDLINUX_MAGIC - [sum of dwords]
MaxTransfer	dw 127		; Max sectors to transfer
EPAPtr		dw EPA - LDLINUX_SYS	; Pointer to the extended patch area

;
; Extended patch area -- this is in .data16 so it doesn't occupy space in
; the first sector.  Use this structure for anything that isn't used by
; the first sector itself.
;
		section .data16
		alignz 2
EPA:
ADVSecPtr	dw ADVSec0 - LDLINUX_SYS
CurrentDirPtr	dw CurrentDirName-LDLINUX_SYS	; Current directory name string
CurrentDirLen	dw CURRENTDIR_MAX
SubvolPtr	dw SubvolName-LDLINUX_SYS
SubvolLen	dw SUBVOL_MAX
SecPtrOffset	dw SectorPtrs-LDLINUX_SYS
SecPtrCnt	dw (SectorPtrsEnd - SectorPtrs)/10

;
; Boot sector patch pointers
;
Sect1Ptr0Ptr	dw Sect1Ptr0 - bootsec		; Pointers to Sector 1 location
Sect1Ptr1Ptr	dw Sect1Ptr1 - bootsec
RAIDPatchPtr	dw kaboom.again - bootsec	; Patch to INT 18h in RAID mode

;
; Pointer to the Syslinux banner
;
BannerPtr	dw syslinux_banner - LDLINUX_SYS

;
; Base directory name and subvolume, if applicable.
;
%define HAVE_CURRENTDIRNAME
		global CurrentDirName:data hidden, SubvolName:data hidden
CurrentDirName	times CURRENTDIR_MAX db 0
SubvolName	times SUBVOL_MAX db 0

		section .init
ldlinux_ent:
;
; Note that some BIOSes are buggy and run the boot sector at 07C0:0000
; instead of 0000:7C00 and the like.  We don't want to add anything
; more to the boot sector, so it is written to not assume a fixed
; value in CS, but we don't want to deal with that anymore from now
; on.
;
		jmp 0:.next	; Normalize CS:IP
.next:		sti		; In case of broken INT 13h BIOSes

;
; Tell the user we got this far
;
		mov si,early_banner
		call writestr_early

;
; Checksum data thus far
;
		mov si,ldlinux_sys
		mov cx,[bsBytesPerSec]
		shr cx,2
		mov edx,-LDLINUX_MAGIC
.checksum:
		lodsd
		add edx,eax
		loop .checksum
		mov [CheckSum],edx		; Save intermediate result
		movzx ebx,si			; Start of the next sector

;
; Tell the user if we're using EBIOS or CBIOS
;
print_bios:
		mov si,cbios_name
		cmp byte [getonesec.jmp+1],(getonesec_ebios-(getonesec.jmp+2))
		jne .cbios
		mov si,ebios_name
		mov byte [getlinsec.jmp+1],(getlinsec_ebios-(getlinsec.jmp+2))
.cbios:
		mov [BIOSName],si
		call writestr_early

		section .earlybss
		global BIOSName
		alignb 2
%define	HAVE_BIOSNAME 1
BIOSName	resw 1

		section .init
;
; Now we read the rest of LDLINUX.SYS.
;
load_rest:
		push bx				; LSW of load address

		lea esi,[SectorPtrs]
		mov cx,[DataSectors]
		dec cx				; Minus this sector

.get_chunk:
		jcxz .done
		mov eax,[si]
		mov edx,[si+4]
		movzx ebp,word [si+8]
		sub cx,bp
		push ebx
		shr ebx,4			; Convert to a segment
		mov es,bx
		xor bx,bx
		call getlinsec
		pop ebx
		imul bp,[bsBytesPerSec]		; Will be < 64K
		add ebx,ebp
		add si,10
		jmp .get_chunk

.done:

;
; All loaded up, verify that we got what we needed.
; Note: the checksum field is embedded in the checksum region, so
; by the time we get to the end it should all cancel out.
;
verify_checksum:
		pop si				; LSW of load address
		movzx eax,word [bsBytesPerSec]
		shr ax,2
		mov ecx,[LDLDwords]		; Total dwords
		sub ecx,eax			; ... minus one sector
		mov eax,[CheckSum]
.checksum:
		add eax,[si]
		add si,4
		jnz .nowrap
		; Handle segment wrap
		mov dx,ds
		add dx,1000h
		mov ds,dx
.nowrap:
		dec ecx
		jnz .checksum

		mov ds,cx

		and eax,eax			; Should be zero
		jz all_read			; We're cool, go for it!

;
; Uh-oh, something went bad...
;
		mov si,checksumerr_msg
		call writestr_early
		jmp kaboom

;
; -----------------------------------------------------------------------------
; Subroutines that have to be in the first sector
; -----------------------------------------------------------------------------



;
; getlinsec: load a sequence of BP floppy sector given by the linear sector
;	     number in EAX into the buffer at ES:BX.  We try to optimize
;	     by loading up to a whole track at a time, but the user
;	     is responsible for not crossing a 64K boundary.
;	     (Yes, BP is weird for a count, but it was available...)
;
;	     On return, BX points to the first byte after the transferred
;	     block.
;
;            This routine assumes CS == DS.
;
		global getlinsec:function hidden
getlinsec:
		pushad
		add eax,[Hidden]		; Add partition offset
		adc edx,[Hidden+4]
.jmp:		jmp strict short getlinsec_cbios

;
; getlinsec_ebios:
;
; getlinsec implementation for EBIOS (EDD)
;
getlinsec_ebios:
.loop:
                push bp                         ; Sectors left
.retry2:
		call maxtrans			; Enforce maximum transfer size
		movzx edi,bp			; Sectors we are about to read
		mov cx,retry_count
.retry:

		; Form DAPA on stack
		push edx
		push eax
		push es
		push bx
		push di
		push word 16
		mov si,sp
		pushad
                mov ah,42h                      ; Extended Read
		push ds
		push ss
		pop ds
		call xint13
		pop ds
		popad
		lea sp,[si+16]			; Remove DAPA
		jc .error
		pop bp
		add eax,edi			; Advance sector pointer
		adc edx,0
		sub bp,di			; Sectors left
		imul di,[bsBytesPerSec]
                add bx,di			; Advance buffer pointer
                and bp,bp
                jnz .loop

		popad
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

		;shr word [MaxTransfer],1	; Reduce the transfer size
		;jnz .retry2

		; Total failure.  Try falling back to CBIOS.
		mov byte [getlinsec.jmp+1],(getlinsec_cbios-(getlinsec.jmp+2))
		;mov byte [MaxTransfer],63	; Max possibe CBIOS transfer

		pop bp
		; ... fall through ...

;
; getlinsec_cbios:
;
; getlinsec implementation for legacy CBIOS
;
getlinsec_cbios:
.loop:
		push edx
		push eax
		push bp
		push bx

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
		; BP = sectors to transfer, SI = bsSecPerTrack,
		; ES:BX = data target
		;

		call maxtrans			; Enforce maximum transfer size

		; Must not cross track boundaries, so BP <= SI-CX
		sub si,cx
		cmp bp,si
		jna .bp_ok
		mov bp,si
.bp_ok:

		shl ah,6		; Because IBM was STOOPID
					; and thought 8 bits were enough
					; then thought 10 bits were enough...
		inc cx			; Sector numbers are 1-based, sigh
		or cl,ah
		mov ch,al
		mov dh,dl
		xchg ax,bp		; Sector to transfer count
		mov ah,02h		; Read sectors
		mov bp,retry_count
.retry:
		pushad
		call xint13
		popad
		jc .error
.resume:
		movzx ecx,al		; ECX <- sectors transferred
		imul ax,[bsBytesPerSec]	; Convert sectors in AL to bytes in AX
		pop bx
		add bx,ax
		pop bp
		pop eax
		pop edx
		add eax,ecx
		sub bp,cx
		jnz .loop
		popad
		ret

.error:
		dec bp
		jnz .retry

		xchg ax,bp		; Sectors transferred <- 0
		shr word [MaxTransfer],1
		jnz .resume
		jmp kaboom

maxtrans:
		cmp bp,[MaxTransfer]
		jna .ok
		mov bp,[MaxTransfer]
.ok:		ret

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

;
; Checksum error message
;
checksumerr_msg	db ' Load error - ', 0	; Boot failed appended

;
; BIOS type string
;
cbios_name	db 'CHS', 0			; CHS/CBIOS
ebios_name	db 'EDD', 0			; EDD/EBIOS

;
; Debug routine
;
%ifdef debug
safedumpregs:
		cmp word [Debug_Magic],0D00Dh
		jnz nc_return
		jmp dumpregs
%endif

rl_checkpt	equ $				; Must be <= 8000h

rl_checkpt_off	equ $-ldlinux_sys
%ifndef DEPEND
 %if rl_checkpt_off > 512-10			; Need minimum one extent
  %assign rl_checkpt_overflow rl_checkpt_off - (512-10)
  %error Sector 1 overflow by rl_checkpt_overflow bytes
 %endif
%endif

;
; Extent pointers... each extent contains an 8-byte LBA and an 2-byte
; sector count.  In most cases, we will only ever need a handful of
; extents, but we have to assume a maximally fragmented system where each
; extent contains only one sector.
;
		alignz 2
MaxInitDataSize	equ 96 << 10
MaxLMA		equ LDLINUX_SYS+MaxInitDataSize
SectorPtrs	zb 10*(MaxInitDataSize >> MIN_SECTOR_SHIFT)
SectorPtrsEnd	equ $

; ----------------------------------------------------------------------------
;  End of code and data that have to be in the first sector
; ----------------------------------------------------------------------------

		section .text16
all_read:
		; We enter here with ES scrambled...
		xor ax,ax
		mov es,ax
;
; Let the user (and programmer!) know we got this far.  This used to be
; in Sector 1, but makes a lot more sense here.
;
		mov si,late_banner
		call writestr_early

		mov si,copyright_str
		call writestr_early


;
; Insane hack to expand the DOS superblock to dwords
;
expand_super:
		xor eax,eax
		mov si,superblock
		mov di,SuperInfo
		mov cx,superinfo_size
.loop:
		lodsw
		dec si
		stosd				; Store expanded word
		xor ah,ah
		stosd				; Store expanded byte
		loop .loop


;
; Common initialization code
;
%include "init.inc"
		
		pushad
		mov eax,ROOT_FS_OPS
		movzx dx,byte [DriveNumber]
		; DH = 0: we are boot from disk not CDROM
		mov ecx,[Hidden]
		mov ebx,[Hidden+4]
		mov si,[bsHeads]
		mov di,[bsSecPerTrack]
		movzx ebp,word [MaxTransfer]
		pm_call pm_fs_init
		pm_call load_env32
		popad

		section .bss16
SuperInfo	resq 16			; The first 16 bytes expanded 8 times

;
; Banner information not needed in sector 1
;
		section .data16
		global syslinux_banner
syslinux_banner	db CR, LF, MY_NAME, ' ', VERSION_STR
late_banner	db ' ', DATE_STR, 0

		section .text16
