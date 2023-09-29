; -*- fundamental -*- (asm-mode sucks)
; ****************************************************************************
;
;  isolinux.asm
;
;  A program to boot Linux kernels off a CD-ROM using the El Torito
;  boot standard in "no emulation" mode, making the entire filesystem
;  available.  It is based on the SYSLINUX boot loader for MS-DOS
;  floppies.
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

%define IS_ISOLINUX 1
%include "head.inc"

;
; Some semi-configurable constants... change on your own risk.
;
my_id		equ isolinux_id
NULLFILE	equ 0			; Zero byte == null file name
NULLOFFSET	equ 0			; Position in which to look
retry_count	equ 6			; How patient are we with the BIOS?
%assign HIGHMEM_SLOP 128*1024		; Avoid this much memory near the top
SECTOR_SHIFT	equ 11			; 2048 bytes/sector (El Torito requirement)
SECTOR_SIZE	equ (1 << SECTOR_SHIFT)

ROOT_DIR_WORD	equ 0x002F

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
;		ends at 2800h

		; Some of these are touched before the whole image
		; is loaded.  DO NOT move this to .bss16/.uibss.
		section .earlybss
		global BIOSName
		alignb 4
FirstSecSum	resd 1			; Checksum of bytes 64-2048
ImageDwords	resd 1			; isolinux.bin size, dwords
InitStack	resd 1			; Initial stack pointer (SS:SP)
DiskSys		resw 1			; Last INT 13h call
ImageSectors	resw 1			; isolinux.bin size, sectors
; These following two are accessed as a single dword...
GetlinsecPtr	resw 1			; The sector-read pointer
BIOSName	resw 1			; Display string for BIOS type
%define HAVE_BIOSNAME 1
		global BIOSType
BIOSType	resw 1
DiskError	resb 1			; Error code for disk I/O
		global DriveNumber
DriveNumber	resb 1			; CD-ROM BIOS drive number
ISOFlags	resb 1			; Flags for ISO directory search
RetryCount      resb 1			; Used for disk access retries

		alignb 8
		global Hidden
Hidden		resq 1			; Used in hybrid mode
bsSecPerTrack	resw 1			; Used in hybrid mode
bsHeads		resw 1			; Used in hybrid mode


;
; El Torito spec packet
;

		alignb 8
_spec_start	equ $
		global spec_packet
spec_packet:	resb 1				; Size of packet
sp_media:	resb 1				; Media type
sp_drive:	resb 1				; Drive number
sp_controller:	resb 1				; Controller index
sp_lba:		resd 1				; LBA for emulated disk image
sp_devspec:	resw 1				; IDE/SCSI information
sp_buffer:	resw 1				; User-provided buffer
sp_loadseg:	resw 1				; Load segment
sp_sectors:	resw 1				; Sector count
sp_chs:		resb 3				; Simulated CHS geometry
sp_dummy:	resb 1				; Scratch, safe to overwrite

;
; EBIOS drive parameter packet
;
		alignb 8
drive_params:	resw 1				; Buffer size
dp_flags:	resw 1				; Information flags
dp_cyl:		resd 1				; Physical cylinders
dp_head:	resd 1				; Physical heads
dp_sec:		resd 1				; Physical sectors/track
dp_totalsec:	resd 2				; Total sectors
dp_secsize:	resw 1				; Bytes per sector
dp_dpte:	resd 1				; Device Parameter Table
dp_dpi_key:	resw 1				; 0BEDDh if rest valid
dp_dpi_len:	resb 1				; DPI len
		resb 1
		resw 1
dp_bus:		resb 4				; Host bus type
dp_interface:	resb 8				; Interface type
db_i_path:	resd 2				; Interface path
db_d_path:	resd 2				; Device path
		resb 1
db_dpi_csum:	resb 1				; Checksum for DPI info

;
; EBIOS disk address packet
;
		alignb 8
dapa:		resw 1				; Packet size
.count:		resw 1				; Block count
.off:		resw 1				; Offset of buffer
.seg:		resw 1				; Segment of buffer
.lba:		resd 2				; LBA (LSW, MSW)

;
; Spec packet for disk image emulation
;
		alignb 8
dspec_packet:	resb 1				; Size of packet
dsp_media:	resb 1				; Media type
dsp_drive:	resb 1				; Drive number
dsp_controller:	resb 1				; Controller index
dsp_lba:	resd 1				; LBA for emulated disk image
dsp_devspec:	resw 1				; IDE/SCSI information
dsp_buffer:	resw 1				; User-provided buffer
dsp_loadseg:	resw 1				; Load segment
dsp_sectors:	resw 1				; Sector count
dsp_chs:	resb 3				; Simulated CHS geometry
dsp_dummy:	resb 1				; Scratch, safe to overwrite

		alignb 4
_spec_end	equ $
_spec_len	equ _spec_end - _spec_start

		section .init
;;
;; Primary entry point.  Because BIOSes are buggy, we only load the first
;; CD-ROM sector (2K) of the file, so the number one priority is actually
;; loading the rest.
;;
		global StackBuf
StackBuf	equ STACK_TOP-44	; 44 bytes needed for
					; the bootsector chainloading
					; code!
		global OrigESDI
OrigESDI	equ StackBuf-4          ; The high dword on the stack
StackHome	equ OrigESDI

bootsec		equ $

_start:		; Far jump makes sure we canonicalize the address
		cli
		jmp 0:_start1
		times 8-($-$$) nop		; Pad to file offset 8

		; This table hopefully gets filled in by mkisofs using the
		; -boot-info-table option.  If not, the values in this
		; table are default values that we can use to get us what
		; we need, at least under a certain set of assumptions.
		global iso_boot_info
iso_boot_info:
bi_pvd:		dd 16				; LBA of primary volume descriptor
bi_file:	dd 0				; LBA of boot file
bi_length:	dd 0xdeadbeef			; Length of boot file
bi_csum:	dd 0xdeadbeef			; Checksum of boot file
bi_reserved:	times 10 dd 0xdeadbeef		; Reserved
bi_end:

		; Custom entry point for the hybrid-mode disk.
		; The following values will have been pushed onto the
		; entry stack:
		;	- partition offset (qword)
		;	- ES
		;	- DI
		;	- DX (including drive number)
		;	- CBIOS Heads
		;	- CBIOS Sectors
		;	- EBIOS flag
		;       (top of stack)
		;
		; If we had an old isohybrid, the partition offset will
		; be missing; we can check for that with sp >= 0x7c00.
		; Serious hack alert.
%ifndef DEBUG_MESSAGES
_hybrid_signature:
	       dd 0x7078c0fb			; An arbitrary number...

_start_hybrid:
		pop cx				; EBIOS flag
		pop word [cs:bsSecPerTrack]
		pop word [cs:bsHeads]
		pop dx
		pop di
		pop es
		xor eax,eax
		xor ebx,ebx
		cmp sp,7C00h
		jae .nooffset
		pop eax
		pop ebx
.nooffset:
		mov si,bios_cbios
		jcxz _start_common
		mov si,bios_ebios
		jmp _start_common
%endif

_start1:
		mov si,bios_cdrom
		xor eax,eax
		xor ebx,ebx
_start_common:
		mov [cs:InitStack],sp	; Save initial stack pointer
		mov [cs:InitStack+2],ss
		xor cx,cx
		mov ss,cx
		mov sp,StackBuf		; Set up stack
		push es			; Save initial ES:DI -> $PnP pointer
		push di
		mov ds,cx
		mov es,cx
		mov fs,cx
		mov gs,cx
		sti
		cld

		mov [Hidden],eax
		mov [Hidden+4],ebx

		mov [BIOSType],si
		mov eax,[si]
		mov [GetlinsecPtr],eax

		; Show signs of life
		mov si,syslinux_banner
		call writestr_early
%ifdef DEBUG_MESSAGES
		mov si,copyright_str
%else
		mov si,[BIOSName]
%endif
		call writestr_early

		;
		; Before modifying any memory, get the checksum of bytes
		; 64-2048
		;
initial_csum:	xor edi,edi
		mov si,bi_end
		mov cx,(SECTOR_SIZE-64) >> 2
.loop:		lodsd
		add edi,eax
		loop .loop
		mov [FirstSecSum],edi

		mov [DriveNumber],dl
%ifdef DEBUG_MESSAGES
		mov si,startup_msg
		call writemsg
		mov al,dl
		call writehex2
		call crlf_early
%endif
		;
		; Initialize spec packet buffers
		;
		mov di,_spec_start
		mov cx,_spec_len >> 2
		xor eax,eax
		rep stosd

		; Initialize length field of the various packets
		mov byte [spec_packet],13h
		mov byte [drive_params],30
		mov byte [dapa],16
		mov byte [dspec_packet],13h

		; Other nonzero fields
		inc word [dsp_sectors]

		; Are we just pretending to be a CD-ROM?
		cmp word [BIOSType],bios_cdrom
		jne found_drive			; If so, no spec packet...

		; Now figure out what we're actually doing
		; Note: use passed-in DL value rather than 7Fh because
		; at least some BIOSes will get the wrong value otherwise
		mov ax,4B01h			; Get disk emulation status
		mov dl,[DriveNumber]
		mov si,spec_packet
		call int13
		jc award_hack			; changed for BrokenAwardHack
		mov dl,[DriveNumber]
		cmp [sp_drive],dl		; Should contain the drive number
		jne spec_query_failed

%ifdef DEBUG_MESSAGES
		mov si,spec_ok_msg
		call writemsg
		mov al,byte [sp_drive]
		call writehex2
		call crlf_early
%endif

found_drive:
		; Alright, we have found the drive.  Now, try to find the
		; boot file itself.  If we have a boot info table, life is
		; good; if not, we have to make some assumptions, and try
		; to figure things out ourselves.  In particular, the
		; assumptions we have to make are:
		; - single session only
		; - only one boot entry (no menu or other alternatives)

		cmp dword [bi_file],0		; Address of code to load
		jne found_file			; Boot info table present :)

%ifdef DEBUG_MESSAGES
		mov si,noinfotable_msg
		call writemsg
%endif

		; No such luck.  See if the spec packet contained one.
		mov eax,[sp_lba]
		and eax,eax
		jz set_file			; Good enough

%ifdef DEBUG_MESSAGES
		mov si,noinfoinspec_msg
		call writemsg
%endif

		; No such luck.  Get the Boot Record Volume, assuming single
		; session disk, and that we're the first entry in the chain.
		mov eax,17			; Assumed address of BRV
		mov bx,trackbuf
		call getonesec

		mov eax,[trackbuf+47h]		; Get boot catalog address
		mov bx,trackbuf
		call getonesec			; Get boot catalog

		mov eax,[trackbuf+28h]		; First boot entry
		; And hope and pray this is us...

		; Some BIOSes apparently have limitations on the size
		; that may be loaded (despite the El Torito spec being very
		; clear on the fact that it must all be loaded.)  Therefore,
		; we load it ourselves, and *bleep* the BIOS.

set_file:
		mov [bi_file],eax

found_file:
		; Set up boot file sizes
		mov eax,[bi_length]
		sub eax,SECTOR_SIZE-3		; ... minus sector loaded
		shr eax,2			; bytes->dwords
		mov [ImageDwords],eax		; boot file dwords
		add eax,((SECTOR_SIZE-1) >> 2)
		shr eax,SECTOR_SHIFT-2		; dwords->sectors
		mov [ImageSectors],ax		; boot file sectors

		mov eax,[bi_file]		; Address of code to load
		inc eax				; Don't reload bootstrap code
%ifdef DEBUG_MESSAGES
		mov si,offset_msg
		call writemsg
		call writehex8
		call crlf_early
%endif

		; Load the rest of the file.  However, just in case there
		; are still BIOSes with 64K wraparound problems, we have to
		; take some extra precautions.  Since the normal load
		; address (TEXT_START) is *not* 2K-sector-aligned, we round
		; the target address upward to a sector boundary,
		; and then move the entire thing down as a unit.
MaxLMA		equ 384*1024		; Reasonable limit (384K)

		mov bx,((TEXT_START+2*SECTOR_SIZE-1) & ~(SECTOR_SIZE-1)) >> 4
		mov bp,[ImageSectors]
		push bx			; Load segment address

.more:
		push bx			; Segment address
		push bp			; Sector count
		mov es,bx
		mov cx,0xfff
		and bx,cx
		inc cx
		sub cx,bx
		shr cx,SECTOR_SHIFT - 4
		jnz .notaligned
		mov cx,0x10000 >> SECTOR_SHIFT	; Full 64K segment possible
.notaligned:
		cmp bp,cx
		jbe .ok
		mov bp,cx
.ok:
		xor bx,bx
		push bp
		push eax
		call getlinsec
		pop eax
		pop cx
		movzx edx,cx
		pop bp
		pop bx

		shl cx,SECTOR_SHIFT - 4
		add bx,cx
		add eax,edx
		sub bp,dx
		jnz .more

		; Move the image into place, and also verify the
		; checksum
		pop ax				; Load segment address
		mov bx,(TEXT_START + SECTOR_SIZE) >> 4
		mov ecx,[ImageDwords]
		mov edi,[FirstSecSum]		; First sector checksum
		xor si,si

move_verify_image:
.setseg:
		mov ds,ax
		mov es,bx
.loop:
		mov edx,[si]
		add edi,edx
		dec ecx
		mov [es:si],edx
		jz .done
		add si,4
		jnz .loop
		add ax,1000h
		add bx,1000h
		jmp .setseg
.done:
		mov ax,cs
		mov ds,ax
		mov es,ax

		; Verify the checksum on the loaded image.
		cmp [bi_csum],edi
		je integrity_ok

		mov si,checkerr_msg
		call writemsg
		jmp kaboom

integrity_ok:
%ifdef DEBUG_MESSAGES
		mov si,allread_msg
		call writemsg
%endif
		jmp all_read			; Jump to main code

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Start of BrokenAwardHack --- 10-nov-2002           Knut_Petersen@t-online.de
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; There is a problem with certain versions of the AWARD BIOS ...
;; the boot sector will be loaded and executed correctly, but, because the
;; int 13 vector points to the wrong code in the BIOS, every attempt to
;; load the spec packet will fail. We scan for the equivalent of
;;
;;	mov	ax,0201h
;;	mov	bx,7c00h
;;	mov	cx,0006h
;;	mov	dx,0180h
;;	pushf
;;	call	<direct far>
;;
;; and use <direct far> as the new vector for int 13. The code above is
;; used to load the boot code into ram, and there should be no reason
;; for anybody to change it now or in the future. There are no opcodes
;; that use encodings relativ to IP, so scanning is easy. If we find the
;; code above in the BIOS code we can be pretty sure to run on a machine
;; with an broken AWARD BIOS ...
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
									     ;;
%ifdef DEBUG_MESSAGES							     ;;
									     ;;
award_notice	db	"Trying BrokenAwardHack first ...",CR,LF,0	     ;;
award_not_orig	db	"BAH: Original Int 13 vector   : ",0		     ;;
award_not_new	db	"BAH: Int 13 vector changed to : ",0		     ;;
award_not_succ	db	"BAH: SUCCESS",CR,LF,0				     ;;
award_not_fail	db	"BAH: FAILURE"					     ;;
award_not_crlf	db	CR,LF,0						     ;;
									     ;;
%endif									     ;;
									     ;;
award_oldint13	dd	0						     ;;
award_string	db	0b8h,1,2,0bbh,0,7ch,0b9h,6,0,0bah,80h,1,09ch,09ah    ;;
									     ;;
						;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
award_hack:	mov	si,spec_err_msg		; Moved to this place from
		call	writemsg		; spec_query_failed
						;
%ifdef DEBUG_MESSAGES				;
						;
		mov	si,award_notice		; display our plan
		call	writemsg		;
		mov	si,award_not_orig	; display original int 13
		call	writemsg		; vector
%endif						;
		mov	eax,[13h*4]		;
		mov	[award_oldint13],eax	;
						;
%ifdef DEBUG_MESSAGES				;
						;
		call	writehex8		;
		mov	si,award_not_crlf	;
		call	writestr_early		;
%endif						;
		push	es			; save ES
		mov	ax,0f000h		; ES = BIOS Seg
		mov	es,ax			;
		cld				;
		xor	di,di			; start at ES:DI = f000:0
award_loop:	push	di			; save DI
		mov	si,award_string		; scan for award_string
		mov	cx,7			; length of award_string = 7dw
		repz	cmpsw			; compare
		pop	di			; restore DI
		jcxz	award_found		; jmp if found
		inc	di			; not found, inc di
		jno	award_loop		;
						;
award_failed:	pop	es			; No, not this way :-((
award_fail2:					;
						;
%ifdef DEBUG_MESSAGES				;
						;
		mov	si,award_not_fail	; display failure ...
		call	writemsg		;
%endif						;
		mov	eax,[award_oldint13]	; restore the original int
		or	eax,eax			; 13 vector if there is one
		jz	spec_query_failed	; and try other workarounds
		mov	[13h*4],eax		;
		jmp	spec_query_failed	;
						;
award_found:	mov	eax,[es:di+0eh]		; load possible int 13 addr
		pop	es			; restore ES
						;
		cmp	eax,[award_oldint13]	; give up if this is the
		jz	award_failed		; active int 13 vector,
		mov	[13h*4],eax		; otherwise change 0:13h*4
						;
						;
%ifdef DEBUG_MESSAGES				;
						;
		push	eax			; display message and
		mov	si,award_not_new	; new vector address
		call	writemsg		;
		pop	eax			;
		call	writehex8		;
		mov	si,award_not_crlf	;
		call	writestr_early		;
%endif						;
		mov	ax,4B01h		; try to read the spec packet
		mov	dl,[DriveNumber]	; now ... it should not fail
		mov	si,spec_packet		; any longer
		int	13h			;
		jc	award_fail2		;
						;
%ifdef DEBUG_MESSAGES				;
						;
		mov	si,award_not_succ	; display our SUCCESS
		call	writemsg		;
%endif						;
		jmp	found_drive		; and leave error recovery code
						;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; End of BrokenAwardHack ----            10-nov-2002 Knut_Petersen@t-online.de
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


		; INT 13h, AX=4B01h, DL=<passed in value> failed.
		; Try to scan the entire 80h-FFh from the end.

spec_query_failed:

		; some code moved to BrokenAwardHack

		mov dl,0FFh
.test_loop:	pusha
		mov ax,4B01h
		mov si,spec_packet
		mov byte [si],13h		; Size of buffer
		call int13
		popa
		jc .still_broken

		mov si,maybe_msg
		call writemsg
		mov al,dl
		call writehex2
		call crlf_early

		cmp byte [sp_drive],dl
		jne .maybe_broken

		; Okay, good enough...
		mov si,alright_msg
		call writemsg
.found_drive0:	mov [DriveNumber],dl
.found_drive:	jmp found_drive

		; Award BIOS 4.51 apparently passes garbage in sp_drive,
		; but if this was the drive number originally passed in
		; DL then consider it "good enough"
.maybe_broken:
		mov al,[DriveNumber]
		cmp al,dl
		je .found_drive

		; Intel Classic R+ computer with Adaptec 1542CP BIOS 1.02
		; passes garbage in sp_drive, and the drive number originally
		; passed in DL does not have 80h bit set.
		or al,80h
		cmp al,dl
		je .found_drive0

.still_broken:	dec dx
		cmp dl, 80h
		jnb .test_loop

		; No spec packet anywhere.  Some particularly pathetic
		; BIOSes apparently don't even implement function
		; 4B01h, so we can't query a spec packet no matter
		; what.  If we got a drive number in DL, then try to
		; use it, and if it works, then well...
		mov dl,[DriveNumber]
		cmp dl,81h			; Should be 81-FF at least
		jb fatal_error			; If not, it's hopeless

		; Write a warning to indicate we're on *very* thin ice now
		mov si,nospec_msg
		call writemsg
		mov al,dl
		call writehex2
		call crlf_early
		mov si,trysbm_msg
		call writemsg
		jmp .found_drive		; Pray that this works...

fatal_error:
		mov si,nothing_msg
		call writemsg

.norge:		jmp short .norge

		; Information message (DS:SI) output
		; Prefix with "isolinux: "
		;
writemsg:	push ax
		push si
		mov si,isolinux_str
		call writestr_early
		pop si
		call writestr_early
		pop ax
		ret

writestr_early:
		pushfd
		pushad
.top:		lodsb
		and al,al
		jz .end
		call writechr
		jmp short .top
.end:		popad
		popfd
		ret

crlf_early:	push ax
		mov al,CR
		call writechr
		mov al,LF
		call writechr
		pop ax
		ret

;
; Write a character to the screen.  There is a more "sophisticated"
; version of this in the subsequent code, so we patch the pointer
; when appropriate.
;

writechr:
.simple:
		pushfd
		pushad
		mov ah,0Eh
		xor bx,bx
		int 10h
		popad
		popfd
		ret

;
; int13: save all the segment registers and call INT 13h.
;	 Some CD-ROM BIOSes have been found to corrupt segment registers
;	 and/or disable interrupts.
;
int13:
		pushf
		push bp
		push ds
		push es
		push fs
		push gs
		int 13h
		mov bp,sp
		setc [bp+10]		; Propagate CF to the caller
		pop gs
		pop fs
		pop es
		pop ds
		pop bp
		popf
		ret

;
; Get one sector.  Convenience entry point.
;
getonesec:
		mov bp,1
		; Fall through to getlinsec

;
; Get linear sectors - EBIOS LBA addressing, 2048-byte sectors.
;
; Input:
;	EAX	- Linear sector number
;	ES:BX	- Target buffer
;	BP	- Sector count
;
		global getlinsec
getlinsec:	jmp word [cs:GetlinsecPtr]

%ifndef DEBUG_MESSAGES

;
; First, the variants that we use when actually loading off a disk
; (hybrid mode.)  These are adapted versions of the equivalent routines
; in ldlinux.asm.
;

;
; getlinsec_ebios:
;
; getlinsec implementation for floppy/HDD EBIOS (EDD)
;
getlinsec_ebios:
		xor edx,edx
		shld edx,eax,2
		shl eax,2			; Convert to HDD sectors
		add eax,[Hidden]
		adc edx,[Hidden+4]
		shl bp,2

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
                mov dl,[DriveNumber]
		push ds
		push ss
		pop ds				; DS <- SS
		mov ah,42h			; Extended Read
		call int13
		pop ds
		popad
		lea sp,[si+16]			; Remove DAPA
		jc .error
		pop bp
		add eax,edi			; Advance sector pointer
		adc edx,0
		sub bp,di			; Sectors left
                shl di,9			; 512-byte sectors
                add bx,di			; Advance buffer pointer
                and bp,bp
                jnz .loop

                ret

.error:
		; Some systems seem to get "stuck" in an error state when
		; using EBIOS.  Doesn't happen when using CBIOS, which is
		; good, since some other systems get timeout failures
		; waiting for the floppy disk to spin up.

		pushad				; Try resetting the device
		xor ax,ax
		mov dl,[DriveNumber]
		call int13
		popad
		loop .retry			; CX-- and jump if not zero

		;shr word [MaxTransfer],1	; Reduce the transfer size
		;jnz .retry2

		; Total failure.  Try falling back to CBIOS.
		mov word [GetlinsecPtr], getlinsec_cbios
		;mov byte [MaxTransfer],63	; Max possibe CBIOS transfer

		pop bp
		jmp getlinsec_cbios.loop

;
; getlinsec_cbios:
;
; getlinsec implementation for legacy CBIOS
;
getlinsec_cbios:
		xor edx,edx
		shl eax,2			; Convert to HDD sectors
		add eax,[Hidden]
		shl bp,2

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

		; We should test this, but it doesn't fit...
		; cmp eax,1023
		; ja .error

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
		mov dl,[DriveNumber]
		xchg ax,bp		; Sector to transfer count
		mov ah,02h		; Read sectors
		mov bp,retry_count
.retry:
		pushad
		call int13
		popad
		jc .error
.resume:
		movzx ecx,al		; ECX <- sectors transferred
		shl ax,9		; Convert sectors in AL to bytes in AX
		pop bx
		add bx,ax
		pop bp
		pop eax
		pop edx
		add eax,ecx
		sub bp,cx
		jnz .loop
		ret

.error:
		dec bp
		jnz .retry

		xchg ax,bp		; Sectors transferred <- 0
		shr word [MaxTransfer],1
		jnz .resume
		jmp disk_error

;
; Truncate BP to MaxTransfer
;
maxtrans:
		cmp bp,[MaxTransfer]
		jna .ok
		mov bp,[MaxTransfer]
.ok:		ret

%endif

;
; This is the variant we use for real CD-ROMs:
; LBA, 2K sectors, some special error handling.
;
getlinsec_cdrom:
		mov si,dapa			; Load up the DAPA
		mov [si+4],bx
		mov [si+6],es
		mov [si+8],eax
.loop:
		push bp				; Sectors left
		cmp bp,[MaxTransferCD]
		jbe .bp_ok
		mov bp,[MaxTransferCD]
.bp_ok:
		mov [si+2],bp
		push si
		mov dl,[DriveNumber]
		mov ah,42h			; Extended Read
		call xint13
		pop si
		pop bp
		movzx eax,word [si+2]		; Sectors we read
		add [si+8],eax			; Advance sector pointer
		sub bp,ax			; Sectors left
		shl ax,SECTOR_SHIFT-4		; 2048-byte sectors -> segment
		add [si+6],ax			; Advance buffer pointer
		and bp,bp
		jnz .loop
		mov eax,[si+8]			; Next sector
		ret

		; INT 13h with retry
xint13:		mov byte [RetryCount],retry_count
.try:		pushad
		call int13
		jc .error
		add sp,byte 8*4			; Clean up stack
		ret
.error:
		mov [DiskError],ah		; Save error code
		popad
		mov [DiskSys],ax		; Save system call number
		dec byte [RetryCount]
		jz .real_error
		push ax
		mov al,[RetryCount]
		mov ah,[dapa+2]			; Sector transfer count
		cmp al,2			; Only 2 attempts left
		ja .nodanger
		mov ah,1			; Drop transfer size to 1
		jmp short .setsize
.nodanger:
		cmp al,retry_count-2
		ja .again			; First time, just try again
		shr ah,1			; Otherwise, try to reduce
		adc ah,0			; the max transfer size, but not to 0
.setsize:
		mov [MaxTransferCD],ah
		mov [dapa+2],ah
.again:
		pop ax
		jmp .try

.real_error:	mov si,diskerr_msg
		call writemsg
		mov al,[DiskError]
		call writehex2
		mov si,oncall_str
		call writestr_early
		mov ax,[DiskSys]
		call writehex4
		mov si,ondrive_str
		call writestr_early
		mov al,dl
		call writehex2
		call crlf_early
		; Fall through to kaboom

;
; kaboom: write a message and bail out.  Wait for a user keypress,
;	  then do a hard reboot.
;
		global kaboom
disk_error:
kaboom:
		RESET_STACK_AND_SEGS AX
		mov si,bailmsg
		pm_call pm_writestr
		pm_call pm_getchar
		cli
		mov word [BIOS_magic],0	; Cold reboot
		jmp 0F000h:0FFF0h	; Reset vector address

; -----------------------------------------------------------------------------
;  Common modules needed in the first sector
; -----------------------------------------------------------------------------

%include "writehex.inc"		; Hexadecimal output

; -----------------------------------------------------------------------------
; Data that needs to be in the first sector
; -----------------------------------------------------------------------------

		global syslinux_banner, copyright_str
syslinux_banner	db CR, LF, MY_NAME, ' ', VERSION_STR, ' ', DATE_STR, ' ', 0
copyright_str   db ' Copyright (C) 1994-'
		asciidec YEAR
		db ' H. Peter Anvin et al', CR, LF, 0
isolinux_str	db 'isolinux: ', 0
%ifdef DEBUG_MESSAGES
startup_msg:	db 'Starting up, DL = ', 0
spec_ok_msg:	db 'Loaded spec packet OK, drive = ', 0
secsize_msg:	db 'Sector size ', 0
offset_msg:	db 'Main image LBA = ', 0
verify_msg:	db 'Image csum verified.', CR, LF, 0
allread_msg	db 'Image read, jumping to main code...', CR, LF, 0
%endif
noinfotable_msg	db 'No boot info table, assuming single session disk...', CR, LF, 0
noinfoinspec_msg db 'Spec packet missing LBA information, trying to wing it...', CR, LF, 0
spec_err_msg:	db 'Loading spec packet failed, trying to wing it...', CR, LF, 0
maybe_msg:	db 'Found something at drive = ', 0
alright_msg:	db 'Looks reasonable, continuing...', CR, LF, 0
nospec_msg	db 'Extremely broken BIOS detected, last attempt with drive = ', 0
nothing_msg:	db 'Failed to locate CD-ROM device; boot failed.', CR, LF
trysbm_msg	db 'See http://syslinux.zytor.com/sbm for more information.', CR, LF, 0
diskerr_msg:	db 'Disk error ', 0
oncall_str:	db ', AX = ',0
ondrive_str:	db ', drive ', 0
checkerr_msg:	db 'Image checksum error, sorry...', CR, LF, 0

err_bootfailed	db CR, LF, 'Boot failed: press a key to retry...'
bailmsg		equ err_bootfailed
crlf_msg	db CR, LF
null_msg	db 0

bios_cdrom_str	db 'ETCD', 0
%ifndef DEBUG_MESSAGES
bios_cbios_str	db 'CHDD', 0
bios_ebios_str	db 'EHDD' ,0
%endif

		alignz 4
		global bios_cdrom
bios_cdrom:	dw getlinsec_cdrom, bios_cdrom_str
%ifndef DEBUG_MESSAGES
bios_cbios:	dw getlinsec_cbios, bios_cbios_str
bios_ebios:	dw getlinsec_ebios, bios_ebios_str
%endif

; Maximum transfer size
MaxTransfer	dw 127				; Hard disk modes
MaxTransferCD	dw 32				; CD mode

rl_checkpt	equ $				; Must be <= 800h

		; This pads to the end of sector 0 and errors out on
		; overflow.
		times 2048-($-$$) db 0

; ----------------------------------------------------------------------------
;  End of code and data that have to be in the first sector
; ----------------------------------------------------------------------------

		section .text16

all_read:

; Test tracers
		TRACER 'T'
		TRACER '>'

;
; Common initialization code
;
%include "init.inc"

; Tell the user we got this far...
%ifndef DEBUG_MESSAGES			; Gets messy with debugging on
		mov si,copyright_str
		pm_call pm_writestr
%endif

;
; Now we're all set to start with our *real* business.	First load the
; configuration file (if any) and parse it.
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
; Now, we need to sniff out the actual filesystem data structures.
; mkisofs gave us a pointer to the primary volume descriptor
; (which will be at 16 only for a single-session disk!); from the PVD
; we should be able to find the rest of what we need to know.
;
init_fs:
		pushad
	        mov eax,ROOT_FS_OPS
	        mov dl,[DriveNumber]
               	cmp word [BIOSType],bios_cdrom
                sete dh                        ; 1 for cdrom, 0 for hybrid mode
		jne .hybrid
		movzx ebp,word [MaxTransferCD]
		jmp .common
.hybrid:
		movzx ebp,word [MaxTransfer]
.common:
	        mov ecx,[Hidden]
	        mov ebx,[Hidden+4]
                mov si,[bsHeads]
		mov di,[bsSecPerTrack]
		pm_call pm_fs_init
		pm_call load_env32
enter_command:
auto_boot:
		jmp kaboom		; load_env32() should never return. If
		                        ; it does, then kaboom!
		popad

		section .rodata
		alignz 4
ROOT_FS_OPS:
		extern iso_fs_ops
		dd iso_fs_ops
		dd 0

		section .text16

%ifdef DEBUG_TRACERS
;
; debug hack to print a character with minimal code impact
;
debug_tracer:	pushad
		pushfd
		mov bp,sp
		mov bx,[bp+9*4]		; Get return address
		mov al,[cs:bx]		; Get data byte
		inc word [bp+9*4]	; Return to after data byte
		call writechr
		popfd
		popad
		ret
%endif	; DEBUG_TRACERS

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

;
; Common local boot code
;
%include "localboot.inc"

; -----------------------------------------------------------------------------
;  Common modules
; -----------------------------------------------------------------------------

%include "common.inc"		; Universal modules

; -----------------------------------------------------------------------------
;  Begin data section
; -----------------------------------------------------------------------------

		section .data16
err_disk_image	db 'Cannot load disk image (invalid file)?', CR, LF, 0

		section .bss16
		global OrigFDCTabPtr
OrigFDCTabPtr	resd 1			; Keep bios_cleanup_hardware() honest
